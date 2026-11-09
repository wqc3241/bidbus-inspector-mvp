// The camera pass: photos use the whole sensor (4:3, as the iPhone camera) and videos 1080p, made smaller after recording; every section but OBDII
// ends with the damage reminder; a damage shot during the walk is read between the shot before and the shot after;
// photos are kept at once as taken, then upright, at most 2560 px on the long side.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/camera/camera_screen.dart';
import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/db/db.dart';
import 'package:bidbus_field/logic/insp.dart';
import 'package:bidbus_field/services/media.dart';
import 'package:bidbus_field/services/store.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Db extends Db {
  _Db() : super(NativeDatabase.memory());
  @override
  Future<void> put(String id, String json) async {}
}

final _tmp = Directory.systemTemp.createTempSync('cam');

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

J fresh(String id, {String fuel = 'Gas or diesel'}) =>
    newInspection(id: id, fuel: fuel, email: 'a@b.co', inspector: 'T', car: {'year': 2020, 'make': 'X', 'model': 'Y', 'trim': 'Z'})..['phase'] = 'capture';

void main() {
  final cam = _Cam();
  setUpAll(() {
    initQl(jsonDecode(File('assets/question-list.json').readAsStringSync()));
    store.db = _Db();
    store.docs = _tmp.path;
    CameraPlatform.instance = cam;
  });

  group('the places a damage photo is read against', () {
    test('Exterior: the panel before and the panel after, with the parts next to them', () {
      final s = fresh('n');
      final l = capList('Exterior', s), door = l.indexWhere((x) => x['panel'] == 'Left rear door');
      // the left front door reading is taken, the left rear door is next: the damage is on one of these two, or what is next to them
      expect(dmgNear(s, 'Exterior', door), ['Left front door', 'Left front window', 'Mirror', 'Left rear door', 'Left rear window', 'Other']);
      // the first panel after the walk-around video: only its own area
      expect(dmgNear(s, 'Exterior', 1), ['Left front fender', 'Front bumper', 'Headlight', 'Mirror', 'Other lights', 'Other']);
      expect(l[1]['panel'], 'Left front fender');
      // every Exterior place a panel or photo names is a place of the catalog
      final places = placesFor('Exterior', 'Gas or diesel').map((p) => p['p']).toSet();
      for (final v in shotNear.values) {
        expect(places.containsAll(v), true, reason: '$v');
      }
      // the walk covers every Exterior body place
      final seen = {for (var j = 1; j < l.length; j++) ...dmgNear(s, 'Exterior', j)!};
      expect(places.difference(seen), {'Other lights', 'Fuel door', 'Wipers', 'Other'}.difference(seen));
    });

    test('Tires: the wheel before and the wheel after, tire and wheel', () {
      final s = fresh('t');
      expect(dmgNear(s, 'Tires', 0), ['Left front tire', 'Left front wheel']);
      expect(dmgNear(s, 'Tires', 1), ['Left front tire', 'Left front wheel']);
      expect(dmgNear(s, 'Tires', 2), ['Left front tire', 'Left front wheel', 'Left rear tire', 'Left rear wheel']);
      expect(dmgNear(s, 'Tires', 7), ['Right front tire', 'Right front wheel']);
    });

    test('Interior, Mechanicals and Underbody shots are not a walk round the car: any place', () {
      final s = fresh('i');
      for (final k in ['Interior', 'OBDII', 'Mechanicals', 'Underbody']) {
        expect(dmgNear(s, k, 1), isNull, reason: k);
      }
    });
  });

  test('a photo is kept upright, at most 2560 px on the long side, without its metadata', () async {
    final from = '${_tmp.path}/big.jpg', to = '${_tmp.path}/kept.jpg';
    final big = img.Image(width: 4032, height: 3024)..exif.imageIfd.orientation = 6;
    File(from).writeAsBytesSync(img.encodeJpg(big));
    expect(await saveUpright(from, to), 90);
    final kept = img.decodeJpg(File(to).readAsBytesSync())!;
    expect((kept.width, kept.height), (1920, 2560)); // turned upright, then shrunk
    expect(kept.exif.imageIfd.hasOrientation, false);
    // a small photo keeps its size
    File(from).writeAsBytesSync(img.encodeJpg(img.Image(width: 800, height: 600)));
    expect(await saveUpright(from, to), -1); // no orientation: the AI is asked how to turn it
    expect(img.decodeJpg(File(to).readAsBytesSync())!.width, 800);
  });

  test('a shot is kept at once as taken; turned upright, shrunk and read in the background', () async {
    store.ins['kp'] = fresh('kp');
    Future<String> shot(String name) async {
      final f = '${_tmp.path}/$name.jpg';
      File(f).writeAsBytesSync(img.encodeJpg(img.Image(width: 4032, height: 3024)..exif.imageIfd.orientation = 6));
      return f;
    }

    final from = await shot('raw');
    final rel = await keepPhoto('kp', from, 'ph_odo', read: {'kind': 'odometer'});
    // at once: the camera's file has moved in as it is, nothing read yet
    expect(File(from).existsSync(), false);
    expect(img.decodeJpgExif(File(store.abs(rel)).readAsBytesSync())!.imageIfd.orientation, 6);
    expect(store.ins['kp']!['aiq'], isEmpty);
    for (var n = 0; n < 50 && (store.ins['kp']!['aiq'] as List).isEmpty; n++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // then: upright and shrunk in place, its turn kept, its reading queued, nothing left over
    final kept = img.decodeJpg(File(store.abs(rel)).readAsBytesSync())!;
    expect((kept.width, kept.height), (1920, 2560));
    expect(m(store.ins['kp']!, 'turn')[rel], 90);
    expect((store.ins['kp']!['aiq'] as List).single, {'kind': 'odometer', 'f': rel});
    String part(String r) => '${Directory.systemTemp.path}/${r.replaceAll('/', '_')}.part';
    expect(File(part(rel)).existsSync(), false);
    expect(store.ins['kp']!['settle'], isEmpty); // the mark is gone once done
    expect(Directory(store.abs(store.dirOf('kp'))).listSync().where((f) => f.path.endsWith('.part')), isEmpty);

    // deleted (or retaken) before it was done: it stays gone, nothing is read
    final gone = await keepPhoto('kp', await shot('raw2'), 'ph_keys', read: {'kind': 'keys'});
    dropFile(gone);
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(File(store.abs(gone)).existsSync(), false);
    expect(File(part(gone)).existsSync(), false);
    expect((store.ins['kp']!['aiq'] as List).length, 1);

    // the app was closed before a shot was finished: the next start finishes it
    final raw = await shot('raw3'), left = '${store.dirOf('kp')}/ph_vin_dash-1.jpg';
    File(raw).renameSync(store.abs(left));
    store.mut('kp', (st) => m(st, 'settle')[left] = {'read': {'kind': 'vin'}});
    store.settle = settleLater;
    store.resumeSettles();
    for (var n = 0; n < 50 && (store.ins['kp']!['settle'] as Map).isNotEmpty; n++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(img.decodeJpg(File(store.abs(left)).readAsBytesSync())!.width, 1920);
    expect((store.ins['kp']!['aiq'] as List).last, {'kind': 'vin', 'f': left});
  });

  testWidgets('the pass: camera kinds, the end-of-section reminder, damages between shots', (t) async {
    // a real font: the test font draws every letter a full square, too wide for the shutter column
    final fonts = '${Platform.environment['FLUTTER_ROOT'] ?? '/Volumes/Storage/sdk/flutter'}/bin/cache/artifacts/material_fonts';
    await (FontLoader('Roboto')
          ..addFont(Future.value(ByteData.sublistView(File('$fonts/Roboto-Regular.ttf').readAsBytesSync())))
          ..addFont(Future.value(ByteData.sublistView(File('$fonts/Roboto-Bold.ttf').readAsBytesSync()))))
        .load();
    t.view.physicalSize = const Size(2796, 1290); // iPhone Pro Max, landscape
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    // file work (photos saved, videos copied) runs outside the test clock
    Future<void> settle() async {
      for (var n = 0; n < 6; n++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await t.pump(const Duration(milliseconds: 200));
      }
    }

    Future<void> open(String id, CamArgs a) async {
      await t.pumpWidget(MaterialApp(home: CameraScreen(id, key: UniqueKey(), args: a)));
      await settle();
    }

    // native video work: the 360 frames are cut from the video as recorded, then the video is made smaller
    final native = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('bidbus/frames'), (c) async {
      native.add('${c.method} ${((c.arguments as Map)['video'] as String).split('/').last.split('-').first}');
      if (c.method == 'squeeze') expect([(c.arguments as Map)['bitrate'], (c.arguments as Map)['max']], [5000000, 1920]);
      return c.method == 'spin' ? <String>[] : true;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('bidbus/frames'), null));

    Finder white() => find.byWidgetPredicate((w) => w is Container && w.color == Colors.white54); // the shutter flash

    String? dialog() => find.textContaining('before proceeding').evaluate().map((e) => (e.widget as Text).data).firstOrNull;

    // 1. Exterior after the walk-around: photos use the whole sensor; back to the video slot, the camera opens for 1080p video
    final e = fresh('e');
    m(e, 'shots')['video_360'] = true;
    store.ins['e'] = e;
    cam.opened.clear();
    await open('e', const CamArgs(run: true));
    expect(cam.opened, [('wide', ResolutionPreset.max, null)]);
    expect(find.text('1/6  Exterior · 2 of 14'), findsOneWidget);
    // Back to the video slot while a photo is still being taken: the camera stays open until the photo is in
    cam.hold = Completer<void>();
    await t.tap(find.byType(AnimatedContainer));
    await t.pump();
    expect(white(), findsOneWidget); // the screen flashes at the tap, before the photo is in
    await t.tap(find.byIcon(LucideIcons.chevronLeft));
    await settle();
    expect(cam.opened.length, 1);
    expect(cam.disposed, isEmpty);
    cam.hold!.complete();
    cam.hold = null;
    await settle();
    expect((m(store.ins['e']!, 'paint')['Left front fender'] as Map)['shot'], true);
    // the flash: Auto (the camera's default, set on every open), then On, Off, and back to Auto
    expect(find.text('A'), findsOneWidget);
    expect(cam.flash, [(1, FlashMode.auto)]);
    await t.tap(find.byIcon(LucideIcons.zap));
    await settle();
    expect(cam.flash.last, (1, FlashMode.always));
    await t.tap(find.byIcon(LucideIcons.zap));
    await settle();
    expect(cam.flash.last, (1, FlashMode.off));
    await t.tap(find.byIcon(LucideIcons.zapOff));
    await settle();
    expect((cam.flash.last, find.text('A').evaluate().length), ((1, FlashMode.auto), 1));
    await t.tap(find.byIcon(LucideIcons.zap));
    await settle();
    expect(cam.flash.last, (1, FlashMode.always));
    await t.tap(find.byIcon(LucideIcons.chevronLeft));
    await settle();
    expect(cam.opened.last, ('wide', ResolutionPreset.veryHigh, null));
    // a video slot: no flash chip; the camera opened again keeps the flash On for the photos after it
    expect(find.byIcon(LucideIcons.zap), findsNothing);
    expect(cam.flash.last, (2, FlashMode.always));
    // the 0.5 lens keeps the kind
    await t.tap(find.text('.5'));
    await settle();
    expect(cam.opened.last, ('ultra', ResolutionPreset.veryHigh, null));
    // record the walk-around again: frames first, then the smaller file
    await t.tap(find.byType(AnimatedContainer));
    await settle();
    await t.tap(find.byType(AnimatedContainer));
    await settle();
    expect(native, ['spin video_360', 'squeeze video_360']);

    // 2. Tires: a damage after the left front shots, before the left rear tire, is read against both wheels
    final r = fresh('r');
    for (final p in tireShots) {
      m(tire(r, 'lf'), 'shots')[p] = true;
    }
    store.ins['r'] = r;
    await open('r', const CamArgs(run: true, k: 'Tires'));
    expect(find.text('2/6  Tires & Wheels · 3 of 8'), findsOneWidget);
    await t.tap(find.text('Damage'));
    await settle();
    final q = (store.ins['r']!['aiq'] as List).where((x) => x['kind'] == 'damage').single as Map;
    expect(q['near'], ['Left front tire', 'Left front wheel', 'Left rear tire', 'Left rear wheel']);
    expect(q.containsKey('hint'), false);
    expect(manual(store.ins['r']!).single['sec'], 'Tires');
    // Auto and a photo that takes long (the flash fired in the dark): the screen flashes again when it is in
    cam.hold = Completer<void>();
    await t.tap(find.byType(AnimatedContainer));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400))); // the photo takes a while
    await t.pump(const Duration(milliseconds: 400)); // the tap flash is over
    expect(white(), findsNothing);
    cam.hold!.complete();
    cam.hold = null;
    await t.pump();
    await t.pump();
    expect(white(), findsOneWidget);
    await settle();
    // with the flash On the photo comes a moment after the tap: the screen flashes when it is in, not before
    await t.tap(find.byIcon(LucideIcons.zap));
    await settle();
    cam.hold = Completer<void>();
    await t.tap(find.byType(AnimatedContainer));
    await t.pump();
    expect(white(), findsNothing);
    cam.hold!.complete();
    cam.hold = null;
    await t.pump();
    await t.pump();
    expect(white(), findsOneWidget);
    await settle();

    // 3. the last tire shot ends Tires with the reminder; Record damage now: damage photos of any wheel, then Next to Interior
    for (final w in wheels) {
      for (final p in tireShots) {
        m(tire(r, w[0]), 'shots')[p] = !(w[0] == 'rf' && p == 'tread_photo');
      }
    }
    await open('r', const CamArgs(run: true, k: 'Tires'));
    expect(find.text('2/6  Tires & Wheels · 8 of 8'), findsOneWidget);
    await t.tap(find.byType(AnimatedContainer)); // the shutter
    await settle();
    expect(dialog(), 'Please record any tire and wheel damage/modification images before proceeding.');
    await t.tap(find.text('Record damage now'));
    await settle();
    await t.tap(find.text('Damage'));
    await settle();
    final last = (store.ins['r']!['aiq'] as List).where((x) => x['kind'] == 'damage').last as Map;
    expect(last.containsKey('near'), false); // after the walk the damage can be on any wheel
    await t.tap(find.text('Next'));
    await settle();
    expect(find.textContaining('Interior'), findsWidgets);

    // 4. Mechanicals ends on a video: the reminder, then the Damage shutter works and the camera opens for photos again
    final k = fresh('k');
    for (final id in ['ph_engine_bay', 'ph_engine_oil', 'video_engine']) {
      m(k, 'shots')[id] = true;
    }
    store.ins['k'] = k;
    cam.opened.clear();
    await open('k', const CamArgs(run: true, k: 'Mechanicals'));
    expect(capList('Mechanicals', k).last['id'], 'video_exhaust');
    expect(cam.opened.last.$2, ResolutionPreset.veryHigh);
    // while the recording starts the screen is locked as for a recording: no Back, no strip, a second tap waits
    cam.holdStart = Completer<void>();
    await t.tap(find.byType(AnimatedContainer)); // record
    await t.pump();
    expect(find.byIcon(LucideIcons.chevronLeft), findsNothing);
    await t.tap(find.byType(AnimatedContainer), warnIfMissed: false);
    await t.pump();
    cam.holdStart!.complete();
    cam.holdStart = null;
    await settle();
    expect(find.textContaining('● 0:0'), findsOneWidget); // still recording: the second tap did not stop or restart it
    expect(cam.disposed.contains(cam.last), false);
    await t.tap(find.byType(AnimatedContainer)); // stop
    await settle();
    expect(dialog(), 'Please record any mechanical damage/modification images before proceeding.');
    expect(native.last, 'squeeze video_exhaust');
    await t.tap(find.text('Record damage now'));
    await settle();
    expect(cam.opened.last.$2, ResolutionPreset.max);
    await t.tap(find.text('Damage'));
    await settle();
    expect(manual(store.ins['k']!).single['sec'], 'Mechanicals');

    // 5. OBDII has no Damage and Mod shutters, so no reminder: the last shot goes straight on to Mechanicals
    final o = fresh('o');
    final ol = capList('OBDII', o);
    for (final x in ol.take(ol.length - 1)) {
      m(o, 'shots')[x['id']] = true;
    }
    store.ins['o'] = o;
    await open('o', const CamArgs(run: true, k: 'OBDII'));
    expect(isMulti(ol.last['id']), true); // other images: as many as needed, then Done
    await t.tap(find.byType(AnimatedContainer));
    await settle();
    await t.tap(find.text('Done · 1'));
    await settle();
    expect(dialog(), isNull);
    expect(find.textContaining('Mechanicals'), findsWidgets);
  });
}
