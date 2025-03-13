import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:firebase_core/firebase_core.dart';
import 'package:snote/login_ui.dart';
import 'firebase_options.dart';
import 'package:pinput/pinput.dart';
import 'dart:math';
import 'util.dart';
import 'package:photo_view/photo_view.dart';
import 'service.dart';
import 'package:easy_debounce/easy_debounce.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'auth.dart';

var logger = Slogger();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AuthManager.getInstance(); // Initialize AuthManager
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FlutterError.onError = (errorDetails) {
    showErrorMessage(errorDetails.exceptionAsString());
    FirebaseCrashlytics.instance.recordFlutterError(errorDetails);
  };
  // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
  PlatformDispatcher.instance.onError = (error, stack) {
    showErrorMessage(error.toString());
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  runApp(const SNoteApp());
}

void showErrorMessage(String error) {
  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(error),
      duration: const Duration(milliseconds: 3000),
      margin: const EdgeInsets.fromLTRB(15, 0, 15, 0),
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
      ),
    ),
  );
}

class GlobalLoadingIndicatorWidget {
  static final GlobalLoadingIndicatorWidget _instance =
      GlobalLoadingIndicatorWidget._internal();

  factory GlobalLoadingIndicatorWidget() {
    return _instance;
  }

  GlobalLoadingIndicatorWidget._internal();

  late OverlayEntry _overlayEntry;

  //prevent concurrency show loading
  var counter = 0;

  void show(BuildContext context) {
    counter += 1;
    if (counter > 1) {
      return;
    }
    _overlayEntry = OverlayEntry(
      builder: (context) => const Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(child: LinearProgressIndicator()),
      ),
    );

    Overlay.of(context).insert(_overlayEntry);
  }

  void hide() {
    counter -= 1;
    if (counter > 0) {
      return;
    }

    _overlayEntry.remove();
  }
}

class SNoteApp extends StatelessWidget {
  const SNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: ThemeData(
          useMaterial3: false,
          brightness: Brightness.light,
          fontFamily: 'NotoSansSC'),
      darkTheme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: false,
          fontFamily: 'NotoSansSC'),
      home: Builder(
        builder: (context) => AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  AuthGate({super.key});
  final appState = SNoteAppState();
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
        stream: AuthManager.getInstance().authStateChanges,
        builder: (context, authState) {
          if (authState.hasError) {
            showErrorMessage(authState.error.toString());
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          if (authState.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          final state = authState.data!;
          if (!state.isAuthenticated) {
            return const PasswordLessLogin(); // PasswordLessLogin is now wrapped in root MaterialApp
          }

          appState.onLoadingFuture.future.then((streamController) {
            if (streamController.hasListener) {
              return;
            }
            streamController.stream.listen((event) {
              if (event) {
                GlobalLoadingIndicatorWidget().show(context);
              } else {
                GlobalLoadingIndicatorWidget().hide();
              }
            });
          });
          return ChangeNotifierProvider.value(
            value: appState,
            builder: ((context, child) {
              return const SNoteMain();
            }),
          );
        });
  }
}

class SNoteMain extends StatelessWidget {
  const SNoteMain({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.read<SNoteAppState>();
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

    return ChangeNotifierProvider<SNoteAppState>.value(
      value: appState,
      builder: (context, child) {
        return const SNoteHome();
      },
    );
  }
}

class SNoteHome extends StatelessWidget {
  const SNoteHome({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.read<SNoteAppState>();
    appState.currentScreen = 'SNoteHome';
    return Scaffold(
      body: const NoteCards(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          var note = appState.createNote();
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) =>
                      ChangeNotifierProvider<SNoteAppState>.value(
                        value: appState,
                        child: NoteEditor(note: note),
                      )));
        },
        tooltip: 'Create',
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
      bottomNavigationBar: ChangeNotifierProvider<SNoteAppState>.value(
        value: appState,
        builder: (context, child) {
          return const _BottomAppBar();
        },
      ),
      drawer: const MainDrawer(),
    );
  }
}

class SNoteTrash extends StatelessWidget {
  const SNoteTrash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              child:
                  const Text('Notes in trash will auto delete after 30 days'),
            ),
            const Expanded(
                child: NoteCards(
              listType: ListType.trash,
            )),
          ],
        ),
      ),
      bottomNavigationBar: const _BottomAppBar(),
      drawer: const MainDrawer(),
    );
  }
}

class MainDrawer extends StatelessWidget {
  const MainDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<SNoteAppState>();
    return Drawer(
        child: ListView(
      children: [
        DrawerHeader(child: Text(appState.displayName)),
        ListTile(
          leading: const Icon(Icons.home),
          title: const Text('Home'),
          onTap: () {
            appState.currentScreen = 'SNoteHome';
            Navigator.of(context).pushReplacement(MaterialPageRoute(
                builder: (context) =>
                    ChangeNotifierProvider<SNoteAppState>.value(
                      value: appState,
                      builder: (context, child) => const SNoteHome(),
                    )));
          },
        ),
        ListTile(
          leading: const Icon(Icons.devices),
          title: const Text('devices'),
          onTap: () {
            logger.d('devices button tapped');
            throw Exception();
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete),
          title: const Text('Trash'),
          onTap: () {
            appState.currentScreen = 'SNoteTrash';
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) =>
                    ChangeNotifierProvider<SNoteAppState>.value(
                      value: appState,
                      builder: (context, child) => const SNoteTrash(),
                    )));
          },
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign Out'),
          onTap: () {
            appState.remoteAesKey();
            AuthManager.getInstance().logout();
          },
        )
      ],
    ));
  }
}

class _BottomAppBar extends StatelessWidget {
  const _BottomAppBar();

  @override
  Widget build(BuildContext context) {
    var appState = context.read<SNoteAppState>();
    return BottomAppBar(
      color: Theme.of(context).colorScheme.surface,
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
                  showSearch(context: context, delegate: NoteSearch(appState));
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
          textController.readOnly = true;
          var quillWg = quill.QuillEditor.basic(
            controller: textController,
            configurations: const quill.QuillEditorConfigurations(
              scrollable: true,
              autoFocus: false,
              // readOnly: true,
              expands: false,
              padding: EdgeInsets.zero,
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
    Widget medias = const SizedBox(
      height: 0,
      width: 0,
    );
    if (images.isNotEmpty) {
      medias = Container(
        height: 50,
        alignment: Alignment.bottomLeft,
        margin: const EdgeInsets.fromLTRB(0, 50, 0, 0),
        child: ListView.builder(
            itemCount: images.length,
            scrollDirection: Axis.horizontal,
            itemBuilder: (BuildContext context, int index) {
              return Image.memory(images[index]);
            }),
      );
    }
    return GestureDetector(
      child: Card(
        child: Container(
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(maxHeight: 300),
          child: AbsorbPointer(
            absorbing: true,
            child: Stack(
              children: [quillWidgets!, medias],
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

enum ListType { normal, trash }

class NoteCards extends StatelessWidget {
  final List<NoteModel>? searchResult;
  final ListType listType;
  const NoteCards(
      {super.key, this.searchResult, this.listType = ListType.normal});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<SNoteAppState>();
    List<NoteModel> noteList;
    if (searchResult != null) {
      noteList = searchResult!;
    } else if (listType == ListType.trash) {
      noteList = appState.trashNotes;
    } else {
      noteList = appState.normalNotes;
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
      var delBtn = PopupMenuItem(
        child: const Text('Delete'),
        onTap: () {
          state.deleteNote(note).then((_) {
            Navigator.pop(context);
          });
        },
      );
      var restoreBtn = PopupMenuItem(
        child: const Text('Restore'),
        onTap: () {
          state.updateContent(note.id, note.content).then((_) {
            Navigator.pop(context);
          });
        },
      );
      List<PopupMenuEntry<dynamic>> btns = [];
      if (note.status == NoteStatus.normal) {
        btns.addAll([delBtn]);
      } else if (note.status == NoteStatus.softDelete) {
        btns.addAll([restoreBtn]);
      }
      return btns;
    });
  }

  final List imageData = [];
  @override
  Widget build(BuildContext context) {
    var appState = context.read<SNoteAppState>();
    appState.currentScreen = 'NoteEditor';
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
        toolbarHeight: 40,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_rounded,
          ),
          alignment: Alignment.centerLeft,
          iconSize: 20,
          onPressed: () {
            List<dynamic> content = [];
            content.add({
              'type': 'quill',
              'value': textController.document.toDelta().toJson()
            });
            for (var img in imageData) {
              content.add({"type": 'image', "value": base64.encode(img)});
            }
            appState.updateContent(note.id, content).then((_) {
              appState.currentScreen = 'SNoteHome';
              Navigator.pop(context);
            });
          },
        ),
      ),
      body: Column(children: [
        Expanded(
            child: Container(
                margin: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                child: quill.QuillEditor.basic(
                  controller: textController,
                ))),
        //using statefulbuilder to keep text unchanged while update image change
        StatefulBuilder(
          builder: ((context, setState) {
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

            return SizedBox(
                height: imageData.isEmpty ? 0 : 100,
                child: ListView.builder(
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
                    }));
          }),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            quill.QuillToolbar.simple(
                controller: textController,
                configurations: quill.QuillSimpleToolbarConfigurations(
                    customButtons: [imageBtn],
                    showListBullets: true,
                    showListCheck: true,
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
                    showClipboardCopy: false,
                    showClipboardCut: false,
                    showClipboardPaste: false,
                    showLineHeightButton: false)),
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
    const borderColor = Colors.white;

    const defaultPinTheme = PinTheme(
      width: 56,
      height: 56,
      textStyle: TextStyle(fontSize: 22, color: Colors.white),
      decoration: BoxDecoration(),
    );
    final cursor = Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 56,
          height: 3,
          decoration: BoxDecoration(
            color: borderColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ],
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
        cursor: cursor,
        showCursor: true,
        preFilledWidget: preFilledWidget,
        autofocus: true,
        onCompleted: (value) {
          appState.verifyAesExchangeCode(value);
        },
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(0, 10, 0, 10),
        child: Text('Please open your other client to generate code'),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
        child: ElevatedButton.icon(
            onPressed: () {
              appState.prepareKeyExchange();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again')),
      ),
    ]));
  }
}

class KeyExchangeCodePop extends StatelessWidget {
  const KeyExchangeCodePop({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.read<SNoteAppState>();
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
  // the showSearch using navigator push inside,which will create new context,so I had to pass appstate by param
  SNoteAppState appState;
  NoteSearch(this.appState);
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
            return ChangeNotifierProvider<SNoteAppState>.value(
                value: appState, child: NoteCards(searchResult: snapshot.data));
            // below method will cause SnoteAppState dispose, I don't know why
            // return ChangeNotifierProvider(create: (context) => appState,
            //   builder: (context, child) =>
            //       NoteCards(searchResult: snapshot.data),
            // );
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
    Completer completer = Completer();

    EasyDebounce.debounce(debouncerId, const Duration(milliseconds: 500),
        () async {
      if (query.isEmpty) {
        completer.complete(<NoteModel>[]);
        return;
      }
      var result = await appState.searchNotes(query);
      completer.complete(result);
      // showResults(context);
    });
    return showFutureResult(completer.future);
  }
}
