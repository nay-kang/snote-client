import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:pinput/pinput.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math';
import 'util.dart';
import 'package:photo_view/photo_view.dart';
import 'package:logger/logger.dart';
import 'service.dart';
import 'package:easy_debounce/easy_debounce.dart';

var logger = Logger();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const SNoteApp());
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    var authProviders = [EmailAuthProvider()];
    var appState = SNoteAppState();
    return StreamBuilder(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authState) {
          if (!authState.hasData) {
            return SignInScreen(
              providers: authProviders,
            );
          }
          return ChangeNotifierProvider(
            create: (context) => appState,
            child: const SNoteMain(),
          );
        });
  }
}

class SNoteApp extends StatelessWidget {
  const SNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: AuthGate(),
    );
  }
}

class SNoteMain extends StatelessWidget {
  const SNoteMain({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = Provider.of<SNoteAppState>(context, listen: false);
    appState.listenForAesKeyRequire(() {
      showModalBottomSheet(
          context: context,
          isDismissible: true,
          enableDrag: true,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (context) {
            return ChangeNotifierProvider<SNoteAppState>.value(
              value: appState,
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.8,
                child: const KeyExchangePop(),
              ),
            );
          });
    });
    appState.listenForAesKeyCodeGenerate(() {
      showModalBottomSheet(
          context: context,
          isDismissible: true,
          enableDrag: true,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (context) {
            return ChangeNotifierProvider<SNoteAppState>.value(
              value: appState,
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.8,
                child: const KeyExchangeCodePop(),
              ),
            );
          });
    });
    appState.checkAesKey();

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
          drawer: Drawer(
              child: ListView(
            children: [
              const DrawerHeader(child: Text('Profile')),
              ListTile(
                title: const Text('devices'),
                onTap: () {
                  Navigator.pop(context);
                  logger.d('devices button tapped');
                },
              ),
              ListTile(
                title: const Text('logout'),
                onTap: () {
                  FirebaseAuth.instance.signOut();
                },
              )
            ],
          )),
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
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            ),
            IconButton(
                onPressed: () {
                  showSearch(context: context, delegate: NoteSearch());
                },
                icon: const Icon(Icons.search))
          ],
        ),
      ),
    );
  }
}

class NoteThumb extends StatelessWidget {
  const NoteThumb({super.key, required this.note});
  final NoteModel note;

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<SNoteAppState>();
    var content = note.content;
    Widget? quillWidgets;
    List<Uint8List> images = [];
    for (var d in content) {
      switch (d['type']) {
        case 'quill':
          var textController = quill.QuillController.basic();
          textController.document = quill.Document.fromJson(d['value']);
          var quillWg = quill.QuillProvider(
            configurations:
                quill.QuillConfigurations(controller: textController),
            child: quill.QuillEditor(
              configurations: const quill.QuillEditorConfigurations(
                scrollable: false,
                autoFocus: false,
                readOnly: true,
                expands: false,
                padding: EdgeInsets.zero,
              ),
              scrollController: ScrollController(),
              focusNode: FocusNode(),
            ),
          );
          quillWidgets = quillWg;
          break;
        case 'image':
          images.add(base64.decode(d['value']));
          break;
        default:
          throw 'Not Support Datatype${d['type']}';
      }
    }

    return GestureDetector(
      child: Card(
        child: Container(
          constraints: const BoxConstraints(maxHeight: 300),
          child: AbsorbPointer(
            absorbing: true,
            child: Stack(
              children: [
                quillWidgets!,
                Container(
                  height: 50,
                  alignment: Alignment.bottomLeft,
                  margin: const EdgeInsets.fromLTRB(0, 50, 0, 0),
                  child: ListView.builder(
                      itemCount: images.length,
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (BuildContext context, int index) {
                        return Image.memory(images[index]);
                      }),
                )
              ],
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
  }
}

class NoteCards extends StatelessWidget {
  final List<NoteModel>? searchResult;
  const NoteCards({super.key, this.searchResult});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<SNoteAppState>();
    List<NoteModel> noteList;
    if (searchResult != null) {
      noteList = searchResult!;
    } else {
      noteList = appState.noteList;
    }
    return RefreshIndicator(
        onRefresh: () async {
          await appState.fetchNotes(refresh: true);
        },
        child: MasonryGridView.builder(
            itemCount: noteList.length,
            gridDelegate: const SliverSimpleGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 300),
            itemBuilder: (context, index) {
              var note = noteList[index];
              return NoteThumb(note: note);
            }));
  }
}

class NoteEditor extends StatelessWidget {
  NoteEditor({super.key, required this.note});
  final NoteModel note;

  Widget generatePopupMenu(
      SNoteAppState state, NoteModel note, BuildContext context) {
    return PopupMenuButton(itemBuilder: (context) {
      return <PopupMenuEntry<dynamic>>[
        PopupMenuItem(
          child: const Text('Delete'),
          onTap: () {
            state.deleteNote(note).then((_) {
              Navigator.pop(context);
            });
          },
        ),
      ];
    });
  }

  final List imageData = [];
  @override
  Widget build(BuildContext context) {
    var appState = Provider.of<SNoteAppState>(context, listen: false);
    var content = note.content;
    var quillContent;
    for (var d in content) {
      switch (d['type']) {
        case 'quill':
          quillContent = d['value'];
          break;
        case 'image':
          imageData.add(base64.decode(d['value']));
          break;
        default:
          throw 'not support type:${d['type']}';
      }
    }
    final textController = quill.QuillController.basic();
    textController.document = quill.Document.fromJson(quillContent);
    textController.moveCursorToEnd();

    Function? addImage;
    var imageBtn = quill.QuillToolbarCustomButtonOptions(
      icon: const Icon(Icons.image),
      tooltip: 'upload image',
      onPressed: () async {
        var result = await FilePicker.platform.pickFiles(
            type: FileType.image, allowMultiple: false, withData: true);
        var imageBytes = result?.files.single.bytes;
        imageBytes = await compressImage(imageBytes!);
        addImage!(imageBytes);
      },
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () {
            List<dynamic> content = [];
            content.add({
              'type': 'quill',
              'value': textController.document.toDelta().toJson()
            });
            for (var img in imageData) {
              content.add({"type": 'image', "value": base64.encode(img)});
            }
            appState.updateContent(note.id, content);
            Navigator.pop(context);
          },
        ),
      ),
      body: Column(children: [
        Expanded(
            child: quill.QuillProvider(
          configurations: quill.QuillConfigurations(controller: textController),
          child: quill.QuillEditor.basic(),
        )),
        SizedBox(
          height: 100,
          child: StatefulBuilder(
            builder: (context, setState) {
              addImage = (Uint8List imageBytes) {
                setState(() {
                  imageData.add(imageBytes);
                });
              };
              void deleteImage(Uint8List imageBytes) {
                setState(() {
                  imageData.remove(imageBytes);
                });
              }

              return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: imageData.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => ImageViewer(
                                    imageData[index], deleteImage)));
                      },
                      child: Image.memory(imageData[index]),
                    );
                  });
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            quill.QuillProvider(
                configurations:
                    quill.QuillConfigurations(controller: textController),
                child: quill.QuillToolbar(
                  configurations: quill.QuillToolbarConfigurations(
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
                    showSubscript: false,
                    showSuperscript: false,
                    customButtons: [imageBtn],
                  ),
                )),
            generatePopupMenu(appState, note, context)
          ],
        ),
      ]),
    );
  }
}

class ImageViewer extends StatelessWidget {
  // The image url
  final Uint8List imageBytes;
  final Function deleteImage;

  const ImageViewer(this.imageBytes, this.deleteImage, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image'),
      ),
      body: Center(
        child: Stack(
          children: [
            // The PhotoView widget that displays the image
            PhotoView(
              imageProvider: MemoryImage(imageBytes),
              // The size of the image widget
              // customSize: Size(300, 300),
            ),
            Positioned(
              bottom: 10,
              left: 10,
              child: GestureDetector(
                onTap: () {
                  deleteImage(imageBytes);
                  Navigator.pop(context);
                },
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.remove,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class KeyExchangePop extends StatelessWidget {
  const KeyExchangePop({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = Provider.of<SNoteAppState>(context);
    appState.prepareKeyExchange();
    appState.listenForAesKeyExchangeDone(() {
      appState.checkAesKey();
      Navigator.pop(context);
    });
    final textController = TextEditingController();
    final defaultPinTheme = PinTheme(
      width: 56,
      height: 56,
      textStyle: GoogleFonts.poppins(
        fontSize: 22,
        color: const Color.fromRGBO(30, 60, 87, 1),
      ),
      decoration: const BoxDecoration(),
    );
    final preFilledWidget = Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 56,
          height: 3,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ],
    );

    return Center(
        child: Column(children: [
      const Text('Enter Code'),
      Pinput(
        length: 4,
        pinAnimationType: PinAnimationType.slide,
        controller: textController,
        defaultPinTheme: defaultPinTheme,
        showCursor: true,
        preFilledWidget: preFilledWidget,
        autofocus: true,
        onCompleted: (value) {
          appState.verifyAesExchangeCode(value);
        },
      ),
      const SizedBox(
        height: 44,
      ),
      const Text('Please open your other client to generate code'),
      ElevatedButton.icon(
          onPressed: () {
            appState.prepareKeyExchange();
          },
          icon: const Icon(Icons.refresh),
          label: const Text('Try Again')),
    ]));
  }
}

class KeyExchangeCodePop extends StatelessWidget {
  const KeyExchangeCodePop({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = Provider.of<SNoteAppState>(context, listen: false);
    appState.listenForAesKeyExchangeDone(() {
      Navigator.pop(context);
    });
    var random = Random();
    var code = String.fromCharCodes(
      List.generate(4, (index) => random.nextInt(10) + 48),
    );
    appState.setAesExchangeCode(code);

    return Center(
        child: Column(children: [
      const Text('Key Exchange Code'),
      const SizedBox(
        height: 30,
      ),
      Text(
        code,
        style: const TextStyle(color: Colors.blue, fontSize: 30),
      ),
      const SizedBox(
        height: 30,
      ),
      const Text(
          'One of your client are requiring the important encryption key\nWhen this code typed means authorize that client to decode your notes')
    ]));
  }
}

class NoteSearch extends SearchDelegate {
  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
          // When pressed here the query will be cleared from the search bar.
        },
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        Navigator.of(context).pop();
      },
    );
  }

  final String debouncerId = 'search-debouncer';
  @override
  Widget buildResults(BuildContext context) {
    var appState = context.watch<SNoteAppState>();
    EasyDebounce.cancel(debouncerId);
    var result = appState.searchNotes(query);
    return showFutureResult(result);
  }

  FutureBuilder showFutureResult(Future<dynamic>? result) {
    return FutureBuilder(
        future: result,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              snapshot.hasData) {
            return NoteCards(searchResult: snapshot.data);
          } else {
            /* 
            I want keep showing previous result while user typing, but at here it will fire every time user typed a single letter
            I know it will not re-render if the app state not changed.but I am not sure if there has other costs.
            so I keep showing blank while user typing.
            */
            return const SizedBox.shrink();
          }
        });
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    var appState = context.watch<SNoteAppState>();
    Completer _completer = Completer();

    EasyDebounce.debounce(debouncerId, const Duration(milliseconds: 500),
        () async {
      if (query.isEmpty) {
        _completer.complete(<NoteModel>[]);
        return;
      }
      var result = await appState.searchNotes(query);
      _completer.complete(result);
      // showResults(context);
    });
    return showFutureResult(_completer.future);
  }
}
