import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:uuid/uuid.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:http/http.dart' as http;
import 'package:webcrypto/webcrypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

Future<void> main() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const SNoteApp());
}

class SNoteApp extends StatelessWidget {
  const SNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    var authProviders = [EmailAuthProvider()];
    var appState = SNoteAppState();

    return MaterialApp(
      initialRoute:
          FirebaseAuth.instance.currentUser == null ? '/sign-in' : '/index',
      routes: {
        '/sign-in': (context) {
          return SignInScreen(
            providers: authProviders,
            actions: [
              AuthStateChangeAction<SignedIn>((context, state) {
                Navigator.pushReplacementNamed(context, '/index');
              })
            ],
          );
        },
        '/index': (context) {
          return ChangeNotifierProvider(
            create: (context) => appState,
            child: const SNoteMain(),
          );
        }
      },
    );
  }
}

class SNoteMain extends StatelessWidget {
  const SNoteMain({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = Provider.of<SNoteAppState>(context, listen: false);

    return MaterialApp(
      theme: ThemeData(
          useMaterial3: false,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.white)),
      home: Builder(
        builder: (context) => Scaffold(
          body: const NoteCards(),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              var note = appState.createNote();
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => NoteEditor(note: note)));
            },
            tooltip: 'Create',
            child: const Icon(Icons.add),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
          bottomNavigationBar: const _BottomAppBar(),
        ),
      ),
    );
  }
}

class _BottomAppBar extends StatelessWidget {
  const _BottomAppBar();

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      color: Theme.of(context).colorScheme.background,
      child: IconTheme(
        data: IconThemeData(
            color: Theme.of(context).colorScheme.onPrimaryContainer),
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: 'Open navigation menu',
              icon: const Icon(Icons.menu),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class NoteCards extends StatelessWidget {
  const NoteCards({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<SNoteAppState>();
    var noteList = appState.noteList;
    return MasonryGridView.builder(
        itemCount: noteList.length,
        gridDelegate: const SliverSimpleGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 300),
        itemBuilder: (context, index) {
          var note = noteList[index];
          var content = note.content;
          final textController = quill.QuillController.basic();
          textController.document = quill.Document.fromJson(content);
          return GestureDetector(
            child: Card(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 300),
                child: AbsorbPointer(
                  absorbing: true,
                  child: quill.QuillEditor(
                    controller: textController,
                    scrollController: ScrollController(),
                    scrollable: false,
                    focusNode: FocusNode(),
                    autoFocus: false,
                    readOnly: true,
                    expands: false,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            onTap: () => {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                          ChangeNotifierProvider<SNoteAppState>.value(
                            value: appState,
                            child: NoteEditor(note: note),
                          )))
            },
          );
        });
  }
}

class NoteEditor extends StatelessWidget {
  const NoteEditor({super.key, required this.note});
  final NoteModel note;
  @override
  Widget build(BuildContext context) {
    var appState = Provider.of<SNoteAppState>(context, listen: false);
    var content = note.content;
    final textController = quill.QuillController.basic();
    textController.document = quill.Document.fromJson(content);
    // textController.addListener(
    //   () {
    //     appState.updateContent(
    //         note.id, textController.document.toDelta().toJson());
    //   },
    // );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () {
            appState.updateContent(
                note.id, textController.document.toDelta().toJson());
            Navigator.pop(context);
          },
        ),
      ),
      body: Column(children: [
        Expanded(
            child: quill.QuillEditor.basic(
                controller: textController, readOnly: false)),
        quill.QuillToolbar.basic(
          controller: textController,
          showAlignmentButtons: false,
          showBackgroundColorButton: false,
          showBoldButton: false,
          showCenterAlignment: false,
          showClearFormat: false,
          showCodeBlock: false,
          showColorButton: false,
          showDirection: false,
          showDividers: false,
          showFontFamily: false,
          showFontSize: false,
          showHeaderStyle: false,
          showIndent: false,
          showInlineCode: false,
          showItalicButton: false,
          showJustifyAlignment: false,
          showLeftAlignment: false,
          showLink: false,
          showListBullets: true,
          showListCheck: true,
          showListNumbers: false,
          showQuote: false,
          showRedo: false,
          showRightAlignment: false,
          showSearchButton: false,
          showSmallButton: false,
          showStrikeThrough: false,
          showUnderLineButton: false,
          showUndo: false,
        ),
      ]),
    );
  }
}

class SNoteAppState extends ChangeNotifier {
  List<NoteModel> noteList = [];
  String? token;
  late NoteService noteService;

  SNoteAppState() {
    FirebaseAuth.instance.authStateChanges().listen(
      (User? user) {
        () async {
          if (user == null) {
            return;
          }
          token = await user.getIdToken();
          if (token == null) {
            return;
          }
          //TODO need a solution to generate a aes key for new user
          var seStorage = const FlutterSecureStorage();
          var aesKeyBase64 = await seStorage.read(key: 'note_aes_key');
          if (aesKeyBase64 == null) {
            var aesKey = Uint8List(32);
            fillRandomBytes(aesKey);
            aesKeyBase64 = base64.encode(aesKey);
            await seStorage.write(key: 'note_aes_key', value: aesKeyBase64);
          }
          var aesKey = base64.decode(aesKeyBase64);
          noteService = NoteService(token!, aesKey);
          var notes = await noteService.loadNotesHttp();
          noteList.addAll(notes);
          notifyListeners();
        }();
      },
    );
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
}

class NoteService {
  AesGcmSecretKey? _encryptor;
  late String token;
  late Uint8List aesKey;
  String? host;
  NoteService(this.token, this.aesKey);

  Future<AesGcmSecretKey> getEncryptor() async {
    _encryptor ??= await AesGcmSecretKey.importRawKey(aesKey);
    return _encryptor!;
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
    var header = {
      HttpHeaders.authorizationHeader: 'Bearer $token',
      'Content-Type': 'application/json; charset=UTF-8',
    };
    var host = await getHost();
    var response = await http.put(Uri.parse('$host/note/$id'),
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

  Future<List<NoteModel>> loadNotesHttp() async {
    var header = {
      HttpHeaders.authorizationHeader: 'Bearer $token',
    };
    var host = await getHost();
    var response = await http.get(Uri.parse('$host/note/'), headers: header);
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
    var data = Uint8List.fromList(content.codeUnits);
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
    var noteText = String.fromCharCodes(decryptedBytes);
    return noteText;
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
      content = delta.toJson();
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
