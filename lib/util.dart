import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'package:logger/logger.dart';

var logger = Logger();
const maxImageSize = 1024 * 1024;
const maxResolution = 1200;

Future<Uint8List> compressImage(Uint8List data) async {
  var compress = false;
  if (data.length > maxImageSize) {
    compress = true;
  }
  var desc = await decodeImageFromList(data);
  if (desc.height > maxResolution || desc.width > maxResolution) {
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
  var ratio = max(desc.height / maxResolution, desc.width / maxResolution);
  var destHeight = desc.height / ratio;
  var destWidth = desc.width / ratio;
  var result = await FlutterImageCompress.compressWithList(data,
      quality: 65, minHeight: destHeight.round(), minWidth: destWidth.round());
  logger.i(
      "image compress source:${desc.width}/${desc.height}:${data.length} dest:${destWidth.round()}/${destHeight.round()}:${result.length}");
  return result;
}
