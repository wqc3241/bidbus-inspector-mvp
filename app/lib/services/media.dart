// Photos saved upright, 360 frames cut from the walk-around, GPS.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;

// bakes the EXIF orientation into the pixels; returns the clockwise turn applied (0, 90, 180, 270), or -1 when the file had no orientation
Future<int> saveUpright(String from, String to, {int extraTurn = 0}) => compute(_upright, [from, to, extraTurn]);

int _upright(List<dynamic> a) {
  final bytes = File(a[0] as String).readAsBytesSync();
  var im = img.decodeImage(bytes);
  if (im == null) {
    File(a[1] as String).writeAsBytesSync(bytes);
    return 0;
  }
  final o = im.exif.imageIfd.hasOrientation ? im.exif.imageIfd.orientation ?? 1 : 0;
  final turn = {1: 0, 3: 180, 6: 90, 8: 270}[o] ?? (o == 0 ? -1 : 0);
  im = img.bakeOrientation(im);
  final extra = a[2] as int;
  if (extra != 0) im = img.copyRotate(im, angle: extra);
  im.exif = img.ExifData();
  File(a[1] as String).writeAsBytesSync(img.encodeJpg(im, quality: 88));
  return turn < 0 ? (extra == 0 ? -1 : extra) : (turn + extra) % 360;
}

Future<void> rotateFile(String path, int deg) => compute((List<dynamic> a) {
      final im = img.decodeImage(File(a[0]).readAsBytesSync());
      if (im != null) File(a[0]).writeAsBytesSync(img.encodeJpg(img.copyRotate(im, angle: a[1] as int), quality: 88));
    }, [path, deg]);

// 36 evenly spaced frames, cut natively (iOS AVAssetImageGenerator, Android MediaMetadataRetriever): see AppDelegate.swift and MainActivity.kt
const _frames = MethodChannel('bidbus/frames');
Future<List<String>> cutSpinFrames(String video, String dir) async => ((await _frames.invokeMethod<List>('spin', {'video': video, 'dir': dir})) ?? []).cast<String>();

Future<Map<String, dynamic>> here() async {
  final at = DateTime.now().toIso8601String();
  try {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return {'at': at, 'loc': null};
  } catch (_) {
    return {'at': at, 'loc': null};
  }
  return _here(at).timeout(const Duration(seconds: 12), onTimeout: () => {'at': at, 'loc': null});
}

Future<Map<String, dynamic>> _here(String at) async {
  try {
    final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(timeLimit: Duration(seconds: 10))).catchError((_) async => (await Geolocator.getLastKnownPosition())!);
    return {'at': at, 'loc': '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}'};
  } catch (_) {
    return {'at': at, 'loc': null};
  }
}
