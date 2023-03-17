import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:uuid/uuid.dart';

void main() {
  runApp(const SNoteApp());
}

class SNoteApp extends StatelessWidget {
  const SNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => SNoteAppState(),
      child: const SNoteMain(),
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
    textController.addListener(
      () {
        appState.updateContent(
            note.id, textController.document.toDelta().toJson());
      },
    );
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
  SNoteAppState() {
    var jsonData = loadNotes();
    jsonData.then((value) {
      List<String> jsonList =
          (jsonDecode(value) as List<dynamic>).cast<String>();
      noteList = jsonList.map((e) => NoteModel.autoId(content: e)).toList();
      notifyListeners();
    });
  }
  Future<String> loadNotes() async {
    return await rootBundle.loadString('assets/fake_notes.json');
  }

  List<NoteModel> noteList = [];

  List<dynamic> getById(String id) {
    return noteList.firstWhere((element) => element.id == id).content;
  }

  void updateContent(String id, List<dynamic> content) {
    noteList.firstWhere((element) => element.id == id).content = content;
    notifyListeners();
  }

  NoteModel createNote() {
    var note = NoteModel.autoId(content: '');
    noteList.insert(0, note);

    return note;
  }
}

class NoteModel {
  late String id;
  late List<dynamic> content;
  static const uuid = Uuid();
  NoteModel.autoId({required String content}) {
    id = uuid.v1();
    this.content = convertContent(content);
  }

  NoteModel({required this.id, required String content}) {
    this.content = convertContent(content);
  }

  List<dynamic> convertContent(String content) {
    var deltaNote = quill.Delta();
    deltaNote.insert('$content\n');
    return deltaNote.toJson();
  }
}
