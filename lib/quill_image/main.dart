import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file/memory.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:universal_html/html.dart' as html;
import 'responsive_widget.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import 'fake_ui.dart' if (dart.library.html) 'real_ui.dart' as ui_instance;

class PlatformViewRegistryFix {
  void registerViewFactory(dynamic x, dynamic y) {
    if (kIsWeb) {
      ui_instance.PlatformViewRegistry.registerViewFactory(
        x,
        y,
      );
    }
  }
}

class UniversalUI {
  PlatformViewRegistryFix platformViewRegistry = PlatformViewRegistryFix();
}

var ui = UniversalUI();

class ImageEmbedBuilderWeb extends quill.EmbedBuilder {
  @override
  String get key => quill.BlockEmbed.imageType;

  @override
  Widget build(
    BuildContext context,
    quill.QuillController controller,
    quill.Embed node,
    bool readOnly,
    bool inline,
    TextStyle textStyle,
  ) {
    final imageUrl = node.value.data;
    if (isImageBase64(imageUrl)) {
      // TODO: handle imageUrl of base64
      return const SizedBox();
    }
    final size = MediaQuery.of(context).size;
    ui.platformViewRegistry.registerViewFactory(imageUrl, (viewId) {
      return html.ImageElement()
        ..src = imageUrl
        ..style.height = 'auto'
        ..style.width = 'auto';
    });
    return Padding(
      padding: EdgeInsets.only(
        right: ResponsiveWidget.isMediumScreen(context)
            ? size.width * 0.5
            : (ResponsiveWidget.isLargeScreen(context))
                ? size.width * 0.75
                : size.width * 0.2,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.45,
        child: HtmlElementView(
          viewType: imageUrl,
        ),
      ),
    );
  }
}

const MAX_IMG_SIZE = 1024 * 1024;
const MAX_RESOLUTION = 1200;
Future<Uint8List> compressImage(File file) async {
  var data = await file.readAsBytes();
  var compress = false;
  if (data.length > MAX_IMG_SIZE) {
    compress = true;
  }
  var desc = await decodeImageFromList(data);
  print("${desc.height} ${desc.width} ${data.length}");
  if (desc.height > MAX_RESOLUTION || desc.width > MAX_RESOLUTION) {
    compress = true;
  }
  if (compress == false) {
    return data;
  }
  var totalPixels = desc.height * desc.width;
  // this formula was derived by one of my hard to compress picture.
  // I compress that image with different resolution and mark the size, then write this data sheet to libre sheet
  // using libre sheet trend line export this formula
  var idealSize = -0.000000007313998571 * (totalPixels ^ 2) +
      0.248113856 * totalPixels -
      293.792;
  if (data.length > idealSize) {
    compress = true;
  }
  var ratio = max(desc.height / MAX_RESOLUTION, desc.width / MAX_RESOLUTION);
  var destHeight = desc.height / ratio;
  var destWidth = desc.width / ratio;
  var result = await FlutterImageCompress.compressWithList(data,
      quality: 60, minHeight: destHeight.round(), minWidth: destWidth.round());
  print(
      "image compress source:${desc.width}/${desc.height}:${data.length} dest:${destWidth.round()}/${destHeight.round()}:${result.length}");
  return result;
}

Future<String> onImagePickCallback(File file) async {
  var imageBytes = await compressImage(file);
  // var imageBytes = await file.readAsBytes();
  var base64image = base64.encode(imageBytes);
  return "data:image/webp;base64,$base64image";
  // final appDocDir = await getApplicationDocumentsDirectory();
  // final copiedFile =
  //     await file.copy('${appDocDir.path}/${p.basename(file.path)}');
  // return copiedFile.path.toString();
}

Future<String?> webImagePickImpl(
    OnImagePickCallback onImagePickCallback) async {
  final result = await FilePicker.platform.pickFiles();
  if (result == null) {
    return null;
  }
  var webFile = result.files.first;

  // final fileName = webFile.name;
  // var blob = html.Blob(webFile.bytes as List);
  // // var url = html.Url.createObjectUrlFromStream(webFile.readStream);
  // var url = html.Url.createObjectUrlFromBlob(blob);
  // var file = File(url);
  // // final file = File(fileName);
  // return onImagePickCallback(file);
  var mfs = MemoryFileSystem();

  File file = mfs.file('temp.jpg');
  file.writeAsBytes(webFile.bytes!.toList());
  return onImagePickCallback(file);
}

// var customImageStyles = quill.DefaultStyles(
//   embedBuilder:(context,node){
//     if (node.value is quill.Embeddable) {
//       final embed = node.value as quill.Embeddable;
//       switch (embed.type) {
//         case 'image':
//           // Returning an Image widget with a fixed width of 300 pixels
//           return Image.network (embed.data, width: 300);
//         // Other cases omitted for brevity
//       }
//     }
//   }
// );
