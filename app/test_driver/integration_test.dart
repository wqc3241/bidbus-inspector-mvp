import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

// saves each screenshot the walk-through takes to $SHOTS_DIR (default build/shots)
Future<void> main() => integrationDriver(onScreenshot: (name, bytes, [args]) async {
      final dir = Platform.environment['SHOTS_DIR'] ?? 'build/shots';
      File('$dir/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      return true;
    });
