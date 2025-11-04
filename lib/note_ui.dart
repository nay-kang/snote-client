import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:provider/provider.dart';
import 'package:snote/util.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

import 'package:snote/service.dart';

class NoteThumb extends StatefulWidget {
  const NoteThumb({super.key, required this.note});
  final NoteModel note;

  @override
  State<NoteThumb> createState() => _NoteThumbState();
}

class _NoteThumbState extends State<NoteThumb> {
  late String htmlContent;
  late List<Uint8List> images;
  // Add key to force rebuild when content changes
  Key _contentKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    images = [];
    htmlContent = '';
    _initializeContent();
  }

  @override
  void didUpdateWidget(NoteThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.content != widget.note.content) {
      setState(() {
        images = [];
        _contentKey = UniqueKey(); // Force rebuild with new key
        _initializeContent();
      });
    }
  }

  void _initializeContent() {
    for (var d in widget.note.content) {
      switch (d['type']) {
        case 'quill':
          final document = quill.Document.fromJson(d['value']);
          var converter = QuillDeltaToHtmlConverter(
            List.castFrom(document.toDelta().toJson()),
            ConverterOptions.forEmail(),
          );
          htmlContent = converter.convert();
          break;
        case 'image':
          images.add(base64.decode(d['value']));
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<SNoteAppState>();

    // Optimize image thumbnails
    Widget medias = const SizedBox.shrink();
    if (images.isNotEmpty) {
      medias = Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        height: 50,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.grey.withAlpha((0.8 * 255).round()),
                Colors.transparent,
              ],
            ),
          ),
          child: ListView.builder(
            cacheExtent: 50,
            itemCount: images.length,
            scrollDirection: Axis.horizontal,
            itemBuilder: (BuildContext context, int index) {
              return Padding(
                padding: const EdgeInsets.all(2),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 46),
                  child: Image.memory(
                    images[index],
                    cacheHeight: 46,
                    fit: BoxFit.cover,
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return RepaintBoundary(
      // Add key to force repaint when content changes
      key: _contentKey,
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => ChangeNotifierProvider<SNoteAppState>.value(
                    value: appState,
                    child: NoteEditor(note: widget.note),
                  ),
            ),
          );
        },
        child: Card(
          child: Container(
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxHeight: 300),
            child: Stack(
              children: [
                // Use HTML instead of QuillEditor
                SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  key: ValueKey(
                    '${widget.note.id}_${widget.note.content.hashCode}',
                  ),
                  child: ScrollConfiguration(
                    behavior: NoScrollbarScrollBehavior(),
                    child: Html(
                      data: htmlContent,
                      style: {
                        "html": Style(
                          margin: Margins.zero,
                          padding: HtmlPaddings.zero,
                        ),
                        "body": Style(
                          margin: Margins.zero,
                          padding: HtmlPaddings.zero,
                          fontSize: FontSize(14),
                        ),
                        "p": Style(
                          margin: Margins.zero,
                          padding: HtmlPaddings.zero,
                        ),
                      },
                      shrinkWrap: true,
                    ),
                  ),
                ),
                medias,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NoteCards extends StatelessWidget {
  static final ScrollController scrollController = ScrollController();
  final List<NoteModel>? searchResult;
  final NoteListType listType;
  const NoteCards({
    super.key,
    this.searchResult,
    this.listType = NoteListType.normal,
  });

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<SNoteAppState>();
    List<NoteModel> noteList;
    if (searchResult != null) {
      noteList = searchResult!;
    } else if (listType == NoteListType.trash) {
      noteList = appState.trashNotes;
    } else {
      noteList = appState.normalNotes;
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await appState.fetchNotes(refresh: true);
        },
        child: MasonryGridView.builder(
          controller: scrollController,
          itemCount: noteList.length,
          cacheExtent: 500,
          itemBuilder: (context, index) {
            var note = noteList[index];
            return NoteThumb(
              // key: ValueKey(note.id), // add key will cause problem when notethumb reorder
              note: note,
            );
          },
          gridDelegate: const SliverSimpleGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 300,
          ),
        ),
      ),
    );
  }
}

class NoteEditor extends StatefulWidget {
  final NoteModel note;
  const NoteEditor({super.key, required this.note});

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late quill.QuillController textController;
  final List<Uint8List> imageData = [];
  bool _contentChanged = false;
  String updatedAt = '';
  String createdAt = '';

  @override
  void initState() {
    super.initState();
    _initializeContent();
  }

  void _initializeContent() {
    if (widget.note.updatedAt != null &&
        widget.note.updatedAt != DateTime.fromMillisecondsSinceEpoch(0)) {
      updatedAt = DateFormat(
        'yyyy-MM-dd HH:mm',
      ).format(widget.note.updatedAt!.toLocal());
      updatedAt = '$updatedAt last update';
    }

    if (widget.note.createdAt != null &&
        widget.note.createdAt != DateTime.fromMillisecondsSinceEpoch(0)) {
      createdAt = DateFormat(
        'yyyy-MM-dd HH:mm',
      ).format(widget.note.createdAt!.toLocal());
      createdAt = '$createdAt create';
    }

    // Initialize text controller
    var quillContent =
        widget.note.content.firstWhere(
          (d) => d['type'] == 'quill',
          orElse: () => {'value': []},
        )['value'];
    textController = quill.QuillController.basic();
    textController.document = quill.Document.fromJson(quillContent);
    textController.moveCursorToEnd();

    // Initialize images
    for (var d in widget.note.content) {
      if (d['type'] == 'image') {
        imageData.add(base64.decode(d['value']));
      }
    }

    // Listen for content changes
    textController.addListener(() {
      _contentChanged = true;
    });
    context.read<SNoteAppState>().currentScreen = 'NoteEditor';
  }

  Future<void> _saveContent() async {
    if (!_contentChanged) return;

    List<Map<String, dynamic>> content = [
      {'type': 'quill', 'value': textController.document.toDelta().toJson()},
      ...imageData.map((img) => {"type": 'image', "value": base64.encode(img)}),
    ];
    final appState = context.read<SNoteAppState>();
    await appState.updateContent(widget.note.id, content);
    appState.currentScreen = 'SNoteHome';
    NoteCards.scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    _contentChanged = false;
  }

  Future<void> _addImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
      compressionQuality: 0,
    );

    if (result?.files.single.bytes != null) {
      final compressed = await compressImage(result!.files.single.bytes!);
      setState(() {
        imageData.add(compressed);
        _contentChanged = true;
      });
    }
  }

  void _deleteImage(Uint8List image) {
    setState(() {
      imageData.remove(image);
      _contentChanged = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 40,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              updatedAt,
              style: TextStyle(
                fontSize: 14, // larger text
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              createdAt,
              style: TextStyle(
                fontSize: 12, // smaller text
                color: Colors.white70,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          iconSize: 20,
          onPressed: () async {
            await _saveContent();
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          PopupMenuButton(
            itemBuilder:
                (context) => [
                  if (widget.note.status == NoteStatus.normal)
                    PopupMenuItem(
                      child: const Text('Delete'),
                      onTap: () async {
                        await context.read<SNoteAppState>().deleteNote(
                          widget.note,
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  if (widget.note.status == NoteStatus.softDelete)
                    PopupMenuItem(
                      child: const Text('Restore'),
                      onTap: () async {
                        await _saveContent();
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: quill.QuillEditor.basic(
              controller: textController,
              config: const quill.QuillEditorConfig(
                padding: EdgeInsets.all(18),
              ),
            ),
          ),
          if (imageData.isNotEmpty)
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: imageData.length,
                itemBuilder:
                    (context, index) => GestureDetector(
                      onTap:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => ImageViewer(
                                    imageData[index],
                                    _deleteImage,
                                  ),
                            ),
                          ),
                      child: Image.memory(imageData[index]),
                    ),
              ),
            ),
          quill.QuillSimpleToolbar(
            controller: textController,
            config: quill.QuillSimpleToolbarConfig(
              customButtons: [
                quill.QuillToolbarCustomButtonOptions(
                  icon: const Icon(Icons.image),
                  tooltip: 'Upload image',
                  onPressed: _addImage,
                ),
              ],
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
              showRedo: true,
              showRightAlignment: false,
              showSearchButton: false,
              showSmallButton: false,
              showStrikeThrough: false,
              showUnderLineButton: false,
              showUndo: true,
              showSubscript: false,
              showSuperscript: false,
              showClipboardCopy: false,
              showClipboardCut: false,
              showClipboardPaste: false,
              showLineHeightButton: false,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
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
      appBar: AppBar(title: const Text('Image')),
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
                  child: const Icon(Icons.remove, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NoScrollbarScrollBehavior extends ScrollBehavior {
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child; // Never build a scrollbar
  }
}
