import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:webcrypto/webcrypto.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:json_rpc_2/json_rpc_2.dart' as jrpc;
import 'package:flutter_quill/flutter_quill.dart' as quill;

var logger = Logger();

class SNoteAppState extends ChangeNotifier {
  List<NoteModel> noteList = [];
  String? token;
  late NoteService noteService;
  User? firebaseUser;
  SNoteAppState() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      firebaseUser = user;
    });
  }

  listenForAesKeyRequire(Function aesKeyRequireCallback) {
    _aesKeyRequireCallback = aesKeyRequireCallback;
  }

  listenForAesKeyCodeGenerate(Function aesKeyCodeCallback) {
    _aesKeyCodeCallback = aesKeyCodeCallback;
  }

  listenForAesKeyExchangeDone(Function callback) {
    _aesKeyExchangeDoneCallback = callback;
  }

  Function? _aesKeyCodeCallback;
  Function? _aesKeyRequireCallback;
  Function? _aesKeyExchangeDoneCallback;

  Map<String, dynamic>? _pubTempKey;
  Map<String, dynamic>? _privateTempKey;
  Uint8List? _tempEncryptKey;
  _aesKeyCodeVerifyCallback(String code, String from) async {
    if (code != this.code) {
      logger.w('code not match');
      return;
    }
    var keyPair = await EcdhPrivateKey.generateKey(EllipticCurve.p256);
    _pubTempKey = await keyPair.publicKey.exportJsonWebKey();
    _privateTempKey = await keyPair.privateKey.exportJsonWebKey();
    var data = {"type": "publicKeyFromA", "key": _pubTempKey};
    noteService.sendToClient(from, json.encode(data));
  }

  _messageFromClient(String from, String message) async {
    // https://getstream.io/blog/end-to-end-encrypted-chat-in-flutter/
    var inData = json.decode(message);
    switch (inData['type']) {
      case 'publicKeyFromA':
        var keyPair = await EcdhPrivateKey.generateKey(EllipticCurve.p256);
        _pubTempKey = await keyPair.publicKey.exportJsonWebKey();
        _privateTempKey = await keyPair.privateKey.exportJsonWebKey();
        var outData = {"type": "publicKeyFromB", "key": _pubTempKey};
        noteService.sendToClient(from, json.encode(outData));
        var publicKey = await EcdhPublicKey.importJsonWebKey(
            inData['key'] as Map<String, dynamic>, EllipticCurve.p256);
        var privateKey = await EcdhPrivateKey.importJsonWebKey(
            _privateTempKey!, EllipticCurve.p256);
        _tempEncryptKey = await privateKey.deriveBits(256, publicKey);
        break;

      case 'publicKeyFromB':
        var publicKey0 = await EcdhPublicKey.importJsonWebKey(
            inData['key'] as Map<String, dynamic>, EllipticCurve.p256);
        var privateKey0 = await EcdhPrivateKey.importJsonWebKey(
            _privateTempKey!, EllipticCurve.p256);
        _tempEncryptKey = await privateKey0.deriveBits(256, publicKey0);

        var tempAesKey = await AesGcmSecretKey.importRawKey(_tempEncryptKey!);

        var ivBytes = Uint8List(16);
        fillRandomBytes(ivBytes);
        var encryptedBytes =
            await tempAesKey.encryptBytes(mainAesKey!, ivBytes);
        var iv = base64.encode(ivBytes);
        var outData = {
          "type": "mainAesKeyFromA",
          "key": iv + base64.encode(encryptedBytes)
        };
        noteService.sendToClient(from, json.encode(outData));
        _aesKeyExchangeDoneCallback!();
        break;

      case 'mainAesKeyFromA':
        var keyStr = inData['key'];
        var iv = keyStr.substring(0, 24);
        var ivBytes = base64.decode(iv);
        var encryptedText = keyStr.substring(24);
        var encryptedMainKey = base64.decode(encryptedText);
        var tempAesKey = await AesGcmSecretKey.importRawKey(_tempEncryptKey!);
        var decryptedBytes =
            await tempAesKey.decryptBytes(encryptedMainKey, ivBytes);
        var aesKeyBase64 = base64.encode(decryptedBytes);
        await seStorage.write(key: 'note_aes_key', value: aesKeyBase64);
        _aesKeyExchangeDoneCallback!();
        break;
      default:
        logger.w("unkown message type from client ${inData['type']}");
    }
  }

  Uint8List? mainAesKey;
  late FlutterSecureStorage seStorage;
  Future<void> checkAesKey() async {
    if (firebaseUser == null) {
      return;
    }
    token = await firebaseUser!.getIdToken();
    if (token == null) {
      return;
    }

    seStorage = const FlutterSecureStorage();

    noteService = NoteService(token!, _aesKeyCodeCallback!,
        _aesKeyCodeVerifyCallback, _messageFromClient);
    var clientId = await seStorage.read(key: 'client_id');
    if (clientId == null) {
      var uuid = const Uuid();
      clientId = uuid.v4().toString();
      await seStorage.write(key: 'client_id', value: clientId);
    }
    var clientCount = await noteService.registClient(clientId);

    var aesKeyBase64 = await seStorage.read(key: 'note_aes_key');
    if (aesKeyBase64 == null && clientCount <= 1) {
      var aesKey = Uint8List(32);
      fillRandomBytes(aesKey);
      aesKeyBase64 = base64.encode(aesKey);
      await seStorage.write(key: 'note_aes_key', value: aesKeyBase64);
    }
    if (aesKeyBase64 == null) {
      _aesKeyRequireCallback!();
    } else {
      mainAesKey = base64.decode(aesKeyBase64);
      noteService.setAesKey(mainAesKey!);
      await noteService.getRpcClient();
      var notes = await noteService.loadNotesHttp();
      noteList.clear();
      noteList.addAll(notes);
      notifyListeners();
    }
  }

  void prepareKeyExchange() {
    noteService.prepareKeyExchange();
  }

  List<dynamic> getById(String id) {
    return noteList.firstWhere((element) => element.id == id).content;
  }

  void updateContent(String id, List<dynamic> content) {
    var note = noteList.firstWhere((element) => element.id == id);
    note.content = content;
    noteService.updateNote(id, content).then((value) {
      noteList.remove(note);
      noteList.insert(0, value);
      notifyListeners();
    });
    notifyListeners();
  }

  NoteModel createNote() {
    var note = NoteModel();
    noteList.insert(0, note);

    return note;
  }

  Future<void> deleteNote(NoteModel note) async {
    await noteService.deleteNote(note.id);
    noteList.remove(note);
    notifyListeners();
  }

  late String code;
  setAesExchangeCode(String code) {
    this.code = code;
  }

  void verifyAesExchangeCode(String code) {
    noteService.verifyAesExchangeCode(code);
  }
}

class HttpClient extends http.BaseClient {
  late final http.Client _inner;
  HttpClient._() {
    _inner = http.Client();
  }

  late final String userAgent;
  static HttpClient? _instance;
  static Future<HttpClient> getInstance() async {
    if (_instance == null) {
      _instance = HttpClient._();
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      var info = await deviceInfo.deviceInfo;
      String os = '', osVersion = '', model = '';
      if (kIsWeb) {
        // do nothng
      } else if (Platform.isAndroid) {
        info = info as AndroidDeviceInfo;
        os = 'Android';
        osVersion = info.version.release;
        model = info.device;
      } else if (Platform.isIOS) {
        info = info as IosDeviceInfo;
        os = 'iOS';
        osVersion = info.systemVersion;
        model = info.utsname.machine;
      }
      var packageInfo = await PackageInfo.fromPlatform();

      _instance!.userAgent =
          "Snote/${packageInfo.version} $os/$osVersion ($model)";
    }

    return _instance!;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!kIsWeb) {
      request.headers['User-Agent'] = userAgent;
    }
    return _inner.send(request);
  }
}

class NoteService {
  AesGcmSecretKey? _encryptor;
  late String token;
  Uint8List? aesKey;
  String? host;
  Function aesKeyCodeCallback;
  Function aesKeyCodeVerifyCallback;
  Function messageFromClient;
  NoteService(this.token, this.aesKeyCodeCallback,
      this.aesKeyCodeVerifyCallback, this.messageFromClient);

  Future<AesGcmSecretKey> getEncryptor() async {
    _encryptor ??= await AesGcmSecretKey.importRawKey(aesKey!);
    return _encryptor!;
  }

  void setAesKey(Uint8List aesKey) {
    this.aesKey = aesKey;
  }

  Future<String> getHost() async {
    if (host == null) {
      var env = const bool.fromEnvironment('dart.vm.product') ? 'prod' : 'dev';
      var configJson = await rootBundle.loadString('assets/config.$env.json');
      var config = jsonDecode(configJson);
      host = config['api_host'];
    }
    return host!;
  }

  Future<NoteModel> updateNote(String id, List<dynamic> content) async {
    String encContentStr = await _encrypt(jsonEncode(content));
    var header = getHeaders();
    var host = await getHost();
    var client = await HttpClient.getInstance();
    var response = await client.put(Uri.parse('$host/api/note/$id'),
        headers: header,
        body: jsonEncode({
          'content': encContentStr,
        }));

    Map<String, dynamic> data = jsonDecode(response.body);
    var decContent = await _decrypt(data['content']);
    var note = NoteModel(
        id: data['id'],
        content: jsonDecode(decContent),
        createdAt: data['created_at'],
        updatedAt: data['updated_at']);
    return note;
  }

  Future<void> deleteNote(String id) async {
    var header = getHeaders();
    var host = await getHost();
    var client = await HttpClient.getInstance();
    var _ = await client.delete(
      Uri.parse('$host/api/note/$id'),
      headers: header,
    );
  }

  Map<String, String> getHeaders() {
    return {
      HttpHeaders.authorizationHeader: 'Bearer $token',
      'Content-Type': 'application/json; charset=UTF-8',
    };
  }

  Future<int> registClient(clientId) async {
    var host = await getHost();
    var headers = getHeaders();
    var client = await HttpClient.getInstance();
    var response = await client.put(
      Uri.parse('$host/api/client/$clientId'),
      headers: headers,
    );
    Map<String, dynamic> data = jsonDecode(response.body);
    return data['client_count'];
  }

  Future<List<NoteModel>> loadNotesHttp() async {
    var header = {
      HttpHeaders.authorizationHeader: 'Bearer $token',
    };

    var host = await getHost();
    var client = await HttpClient.getInstance();
    var response =
        await client.get(Uri.parse('$host/api/note/'), headers: header);
    List data = jsonDecode(response.body);
    var notesFutures = data.map((d) async {
      var n = (d as Map<String, dynamic>);
      var ciphertext = n['content'];
      var plaintext = await _decrypt(ciphertext);
      var note = NoteModel(
          id: n['id'],
          content: jsonDecode(plaintext),
          createdAt: n['created_at'],
          updatedAt: n['updated_at']);
      return note;
    }).toList();
    var notes = await Future.wait(notesFutures);
    return notes;
  }

  Future<String> _encrypt(String content) async {
    var ivBytes = Uint8List(16);
    fillRandomBytes(ivBytes);
    var encryptor = await getEncryptor();
    var data = utf8.encode(content);
    var encryptedBytes = await encryptor.encryptBytes(data, ivBytes);
    var iv = base64.encode(ivBytes);
    return iv + base64.encode(encryptedBytes);
  }

  Future<String> _decrypt(String content) async {
    var iv = content.substring(0, 24);
    var ivBytes = base64.decode(iv);
    var encryptor = await getEncryptor();
    var encryptedText = content.substring(24);
    var data = base64.decode(encryptedText);
    var decryptedBytes = await encryptor.decryptBytes(data, ivBytes);
    var noteText = utf8.decode(decryptedBytes);
    return noteText;
  }

  jrpc.Peer? rpcClient;
  Future<jrpc.Client> getRpcClient() async {
    if (rpcClient == null) {
      var host = await getHost();
      host = host.replaceAll('http', 'ws');
      var uri = Uri.parse("$host/api/ws/");
      var channel = WebSocketChannel.connect(uri);

      rpcClient = jrpc.Peer(channel.cast<String>());
      rpcClient!.done.then(
        (value) {
          logger.w('websocket closed!');
          rpcClient = null;
          getRpcClient();
        },
      );
      unawaited(rpcClient!.listen());
      var _ = await rpcClient!.sendRequest('auth', {'token': token});

      rpcClient!.registerMethod('aeskeyCodeGenerate', (jrpc.Parameters params) {
        aesKeyCodeCallback();
      });

      rpcClient!.registerMethod('aeskeyCodeVerify', (jrpc.Parameters params) {
        var code = params['code'].asString;
        var fromClient = params['from'].asString;
        aesKeyCodeVerifyCallback(code, fromClient);
      });

      rpcClient!.registerMethod('messageFromClient', (jrpc.Parameters params) {
        messageFromClient(params['from'].asString, params['message'].asString);
      });
    }
    return rpcClient!;
  }

  prepareKeyExchange() async {
    var client = await getRpcClient();
    var _ = await client.sendRequest('prepareKeyExchange');
  }

  verifyAesExchangeCode(String code) async {
    var client = await getRpcClient();
    var _ = await client.sendRequest('verifyAesExchangeCode', {'code': code});
  }

  sendToClient(String to, String message) async {
    var client = await getRpcClient();
    var _ = await client
        .sendRequest('sendToClient', {'to': to, 'message': message});
  }
}

class NoteModel {
  late String id;
  late List<dynamic> content;
  DateTime? createdAt;
  DateTime? updatedAt;

  static const uuid = Uuid();

  NoteModel(
      {String? id,
      List<dynamic>? content,
      String? createdAt,
      String? updatedAt}) {
    id ??= uuid.v4();
    this.id = id;
    if (content == null) {
      var delta = quill.Delta();
      delta.insert('\n');
      content = [
        {'type': 'quill', 'value': delta.toJson()}
      ];
    }
    this.content = content;
    if (createdAt != null) {
      this.createdAt = DateTime.parse(createdAt);
    }
    if (updatedAt != null) {
      this.updatedAt = DateTime.parse(updatedAt);
    }
  }
}
