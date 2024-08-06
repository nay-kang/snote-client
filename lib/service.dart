import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:snote/util.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:webcrypto/webcrypto.dart';
import 'package:http/http.dart' as http;
import 'package:json_rpc_2/json_rpc_2.dart' as jrpc;
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:libsimple_flutter/libsimple_flutter.dart';
import 'package:archive/archive.dart';

var logger = Slogger();

class SNoteAppState extends ChangeNotifier with WidgetsBindingObserver {
  List<NoteModel> normalNotes = [];
  List<NoteModel> trashNotes = [];
  String displayName = '';
  StreamController<String> tokenStream = StreamController();
  NoteService? noteService;
  Session? userSession;
  Completer<StreamController> onLoadingFuture = Completer();
  SNoteAppState() {
    Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      userSession = event.session;
      if (userSession != null && userSession?.isExpired == false) {
        tokenStream
            .add("${userSession!.accessToken}${userSession!.refreshToken}");
      }
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      fetchNotes();
    }
  }

  @override
  void dispose() {
    super.dispose();
    WidgetsBinding.instance.removeObserver(this);
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
    noteService!.sendToClient(from, json.encode(data));
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
        noteService!.sendToClient(from, json.encode(outData));
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
        noteService!.sendToClient(from, json.encode(outData));
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

  Future<void> _noteUpdatedCallback(String eventAt) async {
    var date = DateTime.parse(eventAt);
    if (normalNotes.isNotEmpty &&
        // if updatedAt is null means this is newly created note
        normalNotes[0].updatedAt != null &&
        normalNotes[0].updatedAt!.compareTo(date) < 0) {
      fetchNotes();
    }
  }

  void remoteAesKey() {
    seStorage.delete(key: 'note_aes_key');
  }

  Uint8List? mainAesKey;
  late FlutterSecureStorage seStorage;
  Future<void> checkAesKey() async {
    if (userSession == null) {
      return;
    }
    displayName = userSession!.user.email!;
    seStorage = const FlutterSecureStorage();

    noteService ??= NoteService(
      tokenStream,
      _aesKeyCodeCallback!,
      _aesKeyCodeVerifyCallback,
      _messageFromClient,
      _noteUpdatedCallback,
    );

    noteService!.onLoadingFuture.future.then((value) {
      if (onLoadingFuture.isCompleted == false) {
        onLoadingFuture.complete(value);
      }
    });
    var clientId = await seStorage.read(key: 'client_id');
    if (clientId == null) {
      var uuid = const Uuid();
      clientId = uuid.v4().toString();
      await seStorage.write(key: 'client_id', value: clientId);
    }
    var clientCountFuture = noteService!.registClient(clientId);

    var aesKeyBase64 = await seStorage.read(key: 'note_aes_key');
    if (aesKeyBase64 == null && await clientCountFuture <= 1) {
      var aesKey = Uint8List(32);
      fillRandomBytes(aesKey);
      aesKeyBase64 = base64.encode(aesKey);
      await seStorage.write(key: 'note_aes_key', value: aesKeyBase64);
    }
    if (aesKeyBase64 == null) {
      _aesKeyRequireCallback!();
    } else {
      mainAesKey = base64.decode(aesKeyBase64);
      noteService!.setAesKey(mainAesKey!);
      noteService!.getRpcClient();
      await fetchNotes();
    }
  }

  Future<void> fetchNotes({bool refresh = false}) async {
    var db = NoteDB();
    if (refresh) {
      await db.clear();
    }

    var localNotes = await db.getList();
    var seperatedNotes = trashNoteSeperate(localNotes);
    normalNotes.clear();
    normalNotes.addAll(seperatedNotes['normalNotes']!);
    trashNotes.clear();
    trashNotes.addAll(seperatedNotes['trashNotes']!);
    // display local notes immediately
    if (refresh == false) {
      notifyListeners();
    }
    var lastTimestamp = await db.getLastUpdatedAt();
    var remoteNotes = await noteService!.loadNotesHttp(lastTimestamp);
    var mergedNotes = updateLocalNotes(localNotes, remoteNotes);
    seperatedNotes = trashNoteSeperate(mergedNotes);
    normalNotes.clear();
    normalNotes.addAll(seperatedNotes['normalNotes']!);
    trashNotes.clear();
    trashNotes.addAll(seperatedNotes['trashNotes']!);
    notifyListeners();
  }

  Map<String, List<NoteModel>> trashNoteSeperate(List<NoteModel> notes) {
    List<NoteModel> nNotes = [];
    List<NoteModel> tNotes = [];
    for (var note in notes) {
      if (note.status == NoteStatus.normal) {
        nNotes.add(note);
      } else {
        tNotes.add(note);
      }
    }
    return {'normalNotes': nNotes, 'trashNotes': tNotes};
  }

  List<NoteModel> updateLocalNotes(
      List<NoteModel> local, List<NoteModel> remote) {
    var db = NoteDB();
    for (var note in remote.reversed) {
      if (note.status == NoteStatus.hardDelete) {
        db.delete(note.id);
      } else {
        db.save(note);
      }
      int index = local.indexWhere((element) => element.id == note.id);
      if (index > -1) {
        local.removeAt(index);
      }
    }
    remote =
        remote.where((note) => note.status != NoteStatus.hardDelete).toList();
    return remote + local;
  }

  void prepareKeyExchange() {
    noteService!.prepareKeyExchange();
  }

  List<dynamic> getById(String id) {
    return normalNotes.firstWhere((element) => element.id == id).content;
  }

  /// updateContent also make note from delete status to normal status
  Future<void> updateContent(String id, List<dynamic> content) async {
    var allNotes = normalNotes + trashNotes;
    var note = allNotes.firstWhere((element) => element.id == id);
    // user only create new content but without type anything.so delete the note
    if (note.empty(newContent: content)) {
      normalNotes.remove(note);
      return;
    }
    // prevent trash content restore by just click back from NoteEdtor
    // I want using native compare but it seems has performance issue too. https://github.com/dart-lang/collection/issues/263
    if (jsonEncode(note.content) == jsonEncode(content) &&
        note.status == NoteStatus.normal) {
      return;
    }
    note.content = content;
    await noteService!.updateNote(id, content);
  }

  NoteModel createNote() {
    var note = NoteModel();
    normalNotes.insert(0, note);

    return note;
  }

  Future<void> deleteNote(NoteModel note) async {
    await noteService!.deleteNote(note.id);
    notifyListeners();
  }

  late String code;
  setAesExchangeCode(String code) {
    this.code = code;
  }

  void verifyAesExchangeCode(String code) {
    noteService!.verifyAesExchangeCode(code);
  }

  Future<List<NoteModel>> searchNotes(String query) async {
    var db = NoteDB();
    List<String> ids = await db.search(query);
    var searchResult = <NoteModel>[];
    searchResult.addAll(normalNotes.where((note) => ids.contains(note.id)));
    return searchResult;
  }
}

class HttpClient extends http.BaseClient {
  late final http.Client _inner;
  final onLoading = StreamController<bool>();
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
    logger.i('start request ${request.url}');
    onLoading.add(true);

    return _inner.send(request).then((response) async {
      // logger.d('end request ${request.url}');
      onLoading.add(false);
      return response;
    });
  }
}

class NoteService {
  AesGcmSecretKey? _encryptor;
  StreamController<String> tokenStream;
  Uint8List? aesKey;
  String? host;
  Function aesKeyCodeCallback;
  Function aesKeyCodeVerifyCallback;
  Function messageFromClient;
  Function noteUpdatedCallback;
  Completer<StreamController> onLoadingFuture = Completer();
  late Future<HttpClient> clientFuture;
  Completer<bool> tokenFuture = Completer();
  String token = '';
  NoteService(
      this.tokenStream,
      this.aesKeyCodeCallback,
      this.aesKeyCodeVerifyCallback,
      this.messageFromClient,
      this.noteUpdatedCallback) {
    clientFuture = HttpClient.getInstance();
    clientFuture.then((client) {
      onLoadingFuture.complete(client.onLoading);
    });
    tokenStream.stream.listen((event) {
      if (!tokenFuture.isCompleted) {
        tokenFuture.complete(true);
      }
      token = event;
    });
  }

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
    var header = await getHeaders();
    header['Content-Encoding'] = 'gzip';
    var host = await getHost();
    var client = await clientFuture;

    var compressBody = GZipEncoder().encode(jsonEncode({
      'content': encContentStr,
    }).codeUnits);
    var response = await client.put(Uri.parse('$host/api/note/$id'),
        headers: header, body: compressBody);
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
    var header = await getHeaders();
    var host = await getHost();
    var client = await clientFuture;
    var _ = await client.delete(
      Uri.parse('$host/api/note/$id'),
      headers: header,
    );
  }

  Future<Map<String, String>> getHeaders() async {
    await tokenFuture.future;
    return {
      HttpHeaders.authorizationHeader: 'Bearer $token',
      'Content-Type': 'application/json; charset=UTF-8',
    };
  }

  Future<int> registClient(clientId) async {
    var host = await getHost();
    var headers = await getHeaders();
    var client = await clientFuture;
    var response = await client.put(
      Uri.parse('$host/api/client/$clientId'),
      headers: headers,
    );
    Map<String, dynamic> data = jsonDecode(response.body);
    return data['client_count'];
  }

  Future<List<NoteModel>> loadNotesHttp([DateTime? updatedAt]) async {
    var header = await getHeaders();
    String params = "?";
    if (updatedAt != null) {
      var dateStr = updatedAt.toUtc().toIso8601String();
      params += "updated_at=[$dateStr:]";
    }
    var host = await getHost();
    var client = await clientFuture;
    var response =
        await client.get(Uri.parse('$host/api/note/$params'), headers: header);
    List data = jsonDecode(response.body);
    var notesFutures = data.map((d) async {
      var n = (d as Map<String, dynamic>);
      var ciphertext = n['content'];
      var plaintext = await _decrypt(ciphertext);
      var note = NoteModel(
          id: n['id'],
          content: jsonDecode(plaintext),
          createdAt: n['created_at'],
          updatedAt: n['updated_at'],
          status: NoteStatus.getByValue(n['status']));
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
      await tokenFuture.future;
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

      rpcClient!.registerMethod('noteUpdated', (jrpc.Parameters params) {
        noteUpdatedCallback(params['eventAt'].asString);
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

enum NoteStatus {
  normal(1),
  softDelete(-1),
  hardDelete(-2);

  const NoteStatus(this.value);
  final num value;

  static NoteStatus getByValue(num i) {
    return NoteStatus.values.firstWhere((x) => x.value == i);
  }
}

class NoteModel {
  late String id;
  late List<dynamic> content;
  DateTime? createdAt;
  DateTime? updatedAt;
  NoteStatus status;

  static const uuid = Uuid();

  bool empty({List<dynamic>? newContent}) {
    var _content = content;
    if (newContent != null) {
      _content = newContent;
    }
    if (_content.length == 1 &&
        _content[0]['value'][0]['insert'].toString().trim().isEmpty) {
      return true;
    }
    return false;
  }

  NoteModel(
      {String? id,
      List<dynamic>? content,
      String? createdAt,
      String? updatedAt,
      this.status = NoteStatus.normal}) {
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
    } else {
      // using updateAt indicate the note is newly created not saving
      this.updatedAt = DateTime.fromMillisecondsSinceEpoch(0);
    }
  }
}

class NoteDB {
  //singleton in dart to prevent multi instance operate on one database
  static final NoteDB _instance = NoteDB._internal();
  NoteDB._internal();
  factory NoteDB() {
    return _instance;
  }
  Sqlite? db;
  Future<Sqlite> getDb() async {
    if (db == null) {
      var plugin = LibsimpleFlutter();
      db = plugin.getSqlite('note.sqlite3');
    }
    await initDb(db!);
    return db!;
  }

  Future<List<NoteModel>> getList() async {
    var _db = await getDb();
    var rows = await _db.query("select * from note order by updated_at desc");
    List<NoteModel> notes = [];
    for (var row in rows) {
      var content = jsonDecode(row['content']);
      var createdAt = DateTime.fromMillisecondsSinceEpoch(row['created_at']);
      var updatedAt = DateTime.fromMillisecondsSinceEpoch(row['updated_at']);
      var note = NoteModel(
          id: row['id'],
          content: content,
          createdAt: createdAt.toString(),
          updatedAt: updatedAt.toString(),
          status: NoteStatus.getByValue(row['status']));
      notes.add(note);
    }
    return notes;
  }

  Future<void> save(NoteModel note) async {
    var _db = await getDb();
    var content = jsonEncode(note.content);
    var searchContent = extractQuillText(note.content);
    var createdAt = note.createdAt?.millisecondsSinceEpoch;
    var updatedAt = note.updatedAt?.millisecondsSinceEpoch;
    var sql =
        "insert or replace into note(id,content,created_at,updated_at,status) values(?,?,?,?,?);";
    await _db
        .exec(sql, [note.id, content, createdAt, updatedAt, note.status.value]);
    sql = " delete from note_search where note_id=? ";
    await _db.exec(sql, [note.id]);
    sql = " insert into note_search values(?,?) ";
    await _db.exec(sql, [note.id, searchContent]);
  }

  Future<void> delete(String noteId) async {
    var _db = await getDb();
    await _db.exec('delete from note where id=?', [noteId]);
    await _db.exec('delete from note_search where note_id=?', [noteId]);
  }

  String extractQuillText(List content) {
    var fullText = '';
    for (var c in content) {
      if (c['type'] != 'quill') {
        continue;
      }
      for (var textList in c['value'] as List) {
        fullText += " ${textList.values.join(' ')}";
      }
    }
    return fullText;
  }

  Future<void> clear() async {
    var _db = await getDb();
    await _db.exec("drop table note");
    await _db.exec("drop table note_search");
    dbInited = false;
  }

  Future<DateTime> getLastUpdatedAt() async {
    var _db = await getDb();
    var rows = await _db
        .query("select updated_at from note order by updated_at desc limit 1");
    if (rows.isNotEmpty) {
      var ts = rows[0]['updated_at'];
      return DateTime.fromMillisecondsSinceEpoch(ts);
    } else {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  Future<List<String>> search(String query) async {
    var _db = await getDb();
    var rows = await _db.query(
        "select note_id from note_search where content match simple_query(?)",
        [query]);
    List<String> ids = [];
    for (var row in rows) {
      ids.add(row['note_id']);
    }
    return ids;
  }

  var dbInited = false;
  initDb(Sqlite _db) async {
    if (dbInited) {
      return;
    }
    await _db.exec('''
    create table if not exists note(
      id text primary key,
      content text,
      created_at int,
      updated_at int,
      status int -- 1 means normal,-1 means in trush,
    )
    ''');
    await _db.exec('''
    create virtual table if not exists note_search using fts5(
      note_id,
      content,
      tokenize='simple'
    )
    ''');
    dbInited = true;
  }
}
