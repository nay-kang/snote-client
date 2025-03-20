import 'dart:convert';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:math';
import 'package:logger/logger.dart';

class Slogger extends Logger {
  @override
  void log(Level level, message,
      {DateTime? time, Object? error, StackTrace? stackTrace}) {
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.log("$time:$level:$message");
    }
    super.log(level, message, time: time, error: error, stackTrace: stackTrace);
  }
}

var logger = Slogger();
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

class Config {
  Config._internal();
  static final Config instance = Config._internal();

  String? _host;
  bool _hostBenchmarkRun = false;

  Future<String> get host async {
    if (_host != null) return _host!;
    var config = await getConfig();
    var hosts = config['api_hosts'];
    // the first host is the default host,ensure can be used
    if (_hostBenchmarkRun) {
      return hosts[0];
    }
    _hostBenchmarkRun = true;
    var hostFuture = findFastestHost(hosts);
    hostFuture.then((host) {
      _host = host;
    });
    return hosts[0];
  }

  Map<String, dynamic>? _config;
  Future<Map<String, dynamic>> getConfig() async {
    if (_config != null) {
      return _config!;
    }

    var env = kReleaseMode ? 'prod' : 'dev';
    var configJson = await rootBundle.loadString('assets/config.$env.json');
    _config = jsonDecode(configJson) as Map<String, dynamic>;
    _config?['api_hosts'] = (_config?['api_hosts'] as List<dynamic>)
        .map((e) => e.toString())
        .toList();
    return _config!;
  }

  Future<String> findFastestHost(List<String> hosts) {
    var completer = Completer<String>();
    var failedHosts = 0;

    for (var host in hosts) {
      (() async {
        final start = DateTime.now();
        try {
          final response = await http
              .get(Uri.parse('$host/api/hello/'))
              .timeout(const Duration(seconds: 2));
          if (response.statusCode == 200 && !completer.isCompleted) {
            final latency = DateTime.now().difference(start).inMilliseconds;
            debugPrint('Host $host responded in ${latency}ms');
            completer.complete(host);
          }
        } catch (_) {
          failedHosts++;
          // If all hosts failed, complete with first host
          if (failedHosts == hosts.length && !completer.isCompleted) {
            debugPrint(
                'All hosts failed, falling back to first host: ${hosts[0]}');
            completer.complete(hosts[0]);
          }
        }
      })();
    }
    return completer.future;
  }
}
