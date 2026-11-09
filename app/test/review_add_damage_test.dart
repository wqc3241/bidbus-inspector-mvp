// Review > Damages > Add (Take photo or Upload): the label form opens on the new photo and its place, type and severity can be picked;
// the AI first guess can be written to the new damage too. (A damage made there was a Map<String, String>: every pick threw.)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/camera/camera_screen.dart';
import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/db/db.dart';
import 'package:bidbus_field/logic/insp.dart';
import 'package:bidbus_field/screens/damages.dart';
import 'package:bidbus_field/screens/inspection.dart';
import 'package:bidbus_field/services/store.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

final _tmp = Directory.systemTemp.createTempSync('rad');

class _Pick extends ImagePickerPlatform with MockPlatformInterfaceMixin {
  @override
  Future<XFile?> getImageFromSource({required ImageSource source, ImagePickerOptions options = const ImagePickerOptions()}) async {
    final f = File('${_tmp.path}/picked.jpg')..writeAsBytesSync(img.encodeJpg(img.Image(width: 40, height: 30)));
    return XFile(f.path);
  }
}

class _Db extends Db {
  _Db() : super(NativeDatabase.memory());
  @override
  Future<void> put(String id, String json) async {}
}


// a camera that keeps what each open asked for and hands back real files
class _Cam extends CameraPlatform with MockPlatformInterfaceMixin {
  final opened = <(String, ResolutionPreset?, int?)>[];
  final disposed = <int>[];
  Completer<void>? hold; // a photo still being taken
  Completer<void>? holdStart; // a recording still starting
  final flash = <(int, FlashMode)>[];
  var _id = 0, _n = 0;
  int get last => _id; // the camera open now
  final _never = StreamController<CameraErrorEvent>.broadcast();
  @override
  Future<List<CameraDescription>> availableCameras() async => const [
        CameraDescription(name: 'wide', lensDirection: CameraLensDirection.back, sensorOrientation: 90, lensType: CameraLensType.wide),
        CameraDescription(name: 'ultra', lensDirection: CameraLensDirection.back, sensorOrientation: 90, lensType: CameraLensType.ultraWide),
      ];
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() => const Stream.empty();
  @override
  Future<int> createCameraWithSettings(CameraDescription d, MediaSettings s) async {
    opened.add((d.name, s.resolutionPreset, s.videoBitrate));
    return ++_id;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int id) {
    final four = opened.last.$2 == ResolutionPreset.max;
    return Stream.value(CameraInitializedEvent(id, four ? 4032 : 1920, four ? 3024 : 1080, ExposureMode.auto, true, FocusMode.auto, true));
  }

  @override
  Stream<CameraErrorEvent> onCameraError(int id) => _never.stream;
  @override
  Future<void> initializeCamera(int id, {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {}
  @override
  Future<void> lockCaptureOrientation(int id, DeviceOrientation o) async {}
  @override
  Future<double> getMinZoomLevel(int id) async => 1;
  @override
  Future<double> getMaxZoomLevel(int id) async => 10;
  @override
  Future<void> setZoomLevel(int id, double z) async {}
  @override
  Future<void> setFlashMode(int id, FlashMode mode) async => flash.add((id, mode));
  @override
  Widget buildPreview(int id) => const ColoredBox(color: Colors.grey);
  @override
  Future<void> dispose(int id) async => disposed.add(id);
  @override
  Future<XFile> takePicture(int id) async {
    await hold?.future;
    final f = File('${_tmp.path}/shot-${_n++}.jpg')..writeAsBytesSync(img.encodeJpg(img.Image(width: 40, height: 30)));
    return XFile(f.path);
  }

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions o) async => holdStart?.future;
  @override
  Future<XFile> stopVideoRecording(int id) async {
    final f = File('${_tmp.path}/clip-${_n++}.mp4')..writeAsBytesSync([0, 0, 0, 24]);
    return XFile(f.path);
  }
}


void main() {
  testWidgets('Review: Add, then label the new damage photo', (t) async {
    final fonts = '${Platform.environment['FLUTTER_ROOT'] ?? '/Volumes/Storage/sdk/flutter'}/bin/cache/artifacts/material_fonts';
    await (FontLoader('Roboto')
          ..addFont(Future.value(ByteData.sublistView(File('$fonts/Roboto-Regular.ttf').readAsBytesSync())))
          ..addFont(Future.value(ByteData.sublistView(File('$fonts/Roboto-Bold.ttf').readAsBytesSync()))))
        .load();
    t.view.physicalSize = const Size(1290, 2796);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    initQl(jsonDecode(File('assets/question-list.json').readAsStringSync()));
    store.db = _Db();
    store.docs = _tmp.path;
    CameraPlatform.instance = _Cam();
    ImagePickerPlatform.instance = _Pick();
    final s = newInspection(id: 'r', fuel: 'Gas or diesel', email: 'a@b.co', inspector: 'T', car: {'year': 2020, 'make': 'X', 'model': 'Y', 'trim': 'Z'})
      ..['phase'] = 'summary'
      ..['sp'] = capseq.indexOf('Exterior');
    store.ins['r'] = s;
    Future<void> settle() async {
      for (var n = 0; n < 8; n++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await t.pump(const Duration(milliseconds: 250));
      }
    }

    final router = GoRouter(initialLocation: '/i/r', routes: [
      GoRoute(path: '/i/:id', builder: (c, st) => InspectionScreen(st.pathParameters['id']!)),
      GoRoute(path: '/i/:id/cam', builder: (c, st) => CameraScreen(st.pathParameters['id']!, args: st.extra as CamArgs? ?? const CamArgs())),
    ]);
    await t.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await settle();
    final fuel = fuelOf(s), type = placeOpts(placeOf('Exterior', 'Hood'), fuel).first;
    Future<J> addAndLabel(String how) async {
      final add = find.text('Add');
      await t.scrollUntilVisible(add.last, 300, scrollable: find.byType(Scrollable).first);
      await t.tap(add.last);
      await settle();
      await t.tap(find.text(how));
      await settle();
      if (how == 'Take photo') {
        await t.tap(find.byType(AnimatedContainer).last); // the damage camera's shutter
        await settle();
      }
      // the label form on the new photo: Where, then the type and severity sheet
      expect(find.text('WHERE'), findsOneWidget);
      final did = manual(store.ins['r']!).last['id'] as String;
      await t.tap(find.text('Hood').first);
      await settle();
      expect(find.text('TYPE'), findsOneWidget);
      await t.tap(find.text(dshort('Hood', type)).last);
      await settle();
      await t.tap(find.text(dmgSev.first).last);
      await settle();
      await t.tap(find.text('Done'));
      await settle();
      return dmgById(store.ins['r']!, did)!;
    }

    for (final how in ['Take photo', 'Upload']) {
      final d = await addAndLabel(how);
      expect([d['panel'], d['type'], d['sev'], d['src']], ['Hood', type, dmgSev.first, how == 'Upload' ? 'library' : 'camera'], reason: how);
      expect(find.text('WHERE'), findsNothing, reason: '$how: back on Review');
    }

    // the AI first guess lands on a damage just made by the damage camera
    store.mut('r', (x) => manual(x).add(<String, dynamic>{...manual(x).first as Map, 'id': 'dai', 'panel': '', 'type': '', 'sev': ''}));
    final made = Map.of(manual(store.ins['r']!).first as Map).map((k, v) => MapEntry(k as String, v is String ? v : '$v')).cast<String, String>();
    expect(() => applyReading(<String, dynamic>{...store.ins['r']!, 'manual': [made..['id'] = 'dai2'..['panel'] = '']}, {'kind': 'damage', 'did': 'dai2'}, {'place': 'Hood', 'type': type, 'severity': dmgSev.first}),
        throwsA(isA<TypeError>()), reason: 'a Map<String, String> damage (the old literal) cannot take the guess');
    store.mut('r', (x) => applyReading(x, {'kind': 'damage', 'did': 'dai'}, {'place': 'Hood', 'type': type, 'severity': dmgSev.first}));
    expect(dmgById(store.ins['r']!, 'dai')!['ai'], true);
  });
}
