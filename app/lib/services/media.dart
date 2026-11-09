// Photos saved upright, 360 frames cut from the walk-around, GPS.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;

import '../data/ql.dart' show nowIso;

// photos are kept at most this many pixels on the long side, as JPEG of this quality: sharp on the reports, a fraction of the original's size
const photoMax = 2560, photoQuality = 82;
const _photo = MethodChannel('bidbus/photo');

// bakes the EXIF orientation into the pixels, shrinks to photoMax and drops the metadata; returns the clockwise turn applied (0, 90, 180, 270),
// or -1 when the file had no orientation. On iOS the system image tools do it in a fraction of the time (AppDelegate.swift)
Future<int> saveUpright(String from, String to, {int extraTurn = 0}) async {
  if (extraTurn == 0 && Platform.isIOS) {
    try {
      final t = await _photo.invokeMethod<int>('upright', {'from': from, 'to': to, 'max': photoMax, 'q': photoQuality / 100});
      if (t != null) return t;
    } on PlatformException catch (e) {
      debugPrint('photo: $e');
    } on MissingPluginException catch (_) {}
  }
  return compute(_upright, [from, to, extraTurn]);
}

int _upright(List<dynamic> a) {
  final bytes = File(a[0] as String).readAsBytesSync();
  var im = img.decodeImage(bytes);
  if (im == null) {
    File(a[1] as String).writeAsBytesSync(bytes);
    return 0;
  }
  // the JPEG decoder already turns the pixels upright and drops the orientation, so it is read from the file's own EXIF
  final ex = img.decodeJpgExif(bytes), o = ex != null && ex.imageIfd.hasOrientation ? ex.imageIfd.orientation ?? 1 : 0;
  final turn = {1: 0, 3: 180, 6: 90, 8: 270}[o] ?? (o == 0 ? -1 : 0);
  im = img.bakeOrientation(im);
  final extra = a[2] as int;
  if (extra != 0) im = img.copyRotate(im, angle: extra);
  if (im.width > photoMax || im.height > photoMax) {
    im = im.width >= im.height ? img.copyResize(im, width: photoMax, interpolation: img.Interpolation.average) : img.copyResize(im, height: photoMax, interpolation: img.Interpolation.average);
  }
  im.exif = img.ExifData();
  File(a[1] as String).writeAsBytesSync(img.encodeJpg(im, quality: photoQuality));
  return turn < 0 ? (extra == 0 ? -1 : extra) : (turn + extra) % 360;
}

Future<void> rotateFile(String path, int deg) => compute((List<dynamic> a) {
      final im = img.decodeImage(File(a[0]).readAsBytesSync());
      if (im != null) File(a[0]).writeAsBytesSync(img.encodeJpg(img.copyRotate(im, angle: a[1] as int), quality: photoQuality));
    }, [path, deg]);

// 36 evenly spaced frames, cut natively (iOS AVAssetImageGenerator, Android MediaMetadataRetriever): see AppDelegate.swift and MainActivity.kt
const _frames = MethodChannel('bidbus/frames');
Future<List<String>> cutSpinFrames(String video, String dir) async => ((await _frames.invokeMethod<List>('spin', {'video': video, 'dir': dir})) ?? []).cast<String>();

// videos upload at 5 Mbit/s, H.264, 1080p at most. The camera records at the system's own settings, so the 360 frames are cut sharp;
// then the file is re-encoded in place (iOS: squeezeVideo in AppDelegate.swift; elsewhere it stays as recorded).
// Once per file at a time; a file already at that rate is left alone, so asking again (before the upload) costs nothing
const videoBitrate = 5000000, videoMax = 1920;
final _squeezing = <String, Future<void>>{};
Future<void> squeezeVideo(String path) => _squeezing[path] ??= () async {
      try {
        await _frames.invokeMethod<bool>('squeeze', {'video': path, 'bitrate': videoBitrate, 'max': videoMax});
      } on PlatformException catch (e) {
        debugPrint('squeeze: $e');
      } on MissingPluginException catch (_) {
      } finally {
        _squeezing.remove(path);
      }
    }();

Future<Map<String, dynamic>> here() async {
  final at = nowIso();
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
