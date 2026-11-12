// The camera pass (docs/11-camera-flow-1109.md): Exterior, Interior with the OBDII screens, the walk-around, Mechanicals, Underbody.
// Photos use the whole sensor (4:3, as the iPhone camera) and videos 1080p, made smaller after recording; Interior, the walk-around,
// Mechanicals and Underbody end with their questions (Record damage or Next); a damage photo takes the zone of the shot it was
// taken at and is read against every place of that zone; photos are kept at once as taken, then upright, at most 2560 px.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/camera/camera_screen.dart';
import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/db/db.dart';
import 'package:bidbus_field/logic/insp.dart';
import 'package:bidbus_field/services/media.dart';
import 'package:bidbus_field/services/store.dart';
import 'package:bidbus_field/widgets/ui.dart';
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

  group('the 1109 pass', () {
    List<String> ids(List<J> l) => [for (final x in l) x['panel'] ?? (x['wheel'] != null ? '${x['id']}-${x['wheel']}' : x['id'] as String)];

    test('five sections; OBDII at the end of Interior; one walk round the car', () {
      final s = fresh('n');
      expect(camseq, ['Exterior', 'Interior', 'Tires', 'Mechanicals', 'Underbody']);
      expect([for (final k in camseq) camTitle(k)], ['Exterior', 'Interior', 'Walk-around', 'Mechanicals', 'Underbody']);
      expect(ids(capList('Exterior', s)), ['ph_vin_dash', 'video_360']);
      expect(ids(capList('Interior', s)), ['ph_vin_door', 'ph_int_front', 'ph_int_rear', 'ph_odo', 'video_engine', 'ph_keys', 'ph_int_dash', 'ph_int_screen', 'ph_obd_current', 'ph_obd_past', 'ph_obd_emission', 'ph_obd_other']);
      expect(ids(capList('Tires', s)), [
        'Left front fender', 'tire_photo-lf', 'tread_photo-lf', 'Left front door', 'Left rear door', 'tire_photo-lr', 'tread_photo-lr', 'Left quarter panel', 'Trunk or liftgate', 'ph_int_cargo',
        'Right quarter panel', 'tire_photo-rr', 'tread_photo-rr', 'Right rear door', 'Right front door', 'tire_photo-rf', 'tread_photo-rf', 'Right front fender', 'Hood', 'Roof', 'ph_ext_roof',
      ]);
      expect(ids(capList('Mechanicals', s)), ['ph_engine_bay', 'ph_engine_oil', 'video_exhaust']);
      expect(ids(capList('Mechanicals', fresh('ev', fuel: ev))), ['ph_frunk', 'ph_ev_port']);
      expect(ids(capList('Interior', fresh('ev', fuel: ev))).where((x) => x.startsWith('ph_ev_') || x.startsWith('ph_obd_')), ['ph_ev_alerts', 'ph_ev_battery']);
      // a panel not on the car drops out of the walk; engine sound and exhaust go when the engine will not start
      m(s, 'paint')['Roof'] = <String, dynamic>{'na': true};
      lst(s, 'probs', 'ck_engine').add('Will not start');
      expect(ids(capList('Tires', s)).contains('Roof'), false);
      expect(ids(capList('Interior', s)).contains('video_engine'), false);
      expect(ids(capList('Mechanicals', s)).contains('video_exhaust'), false);
    });

    test('Review keeps its pages: each shot on its home page, with the camera section it is taken in', () {
      final s = fresh('h');
      (String, String) at(String k, String id) => revList(k, s).where((e) => (e.$1['panel'] ?? e.$1['id']) == id).map((e) => (e.$2, ids([e.$1]).single)).single;
      expect(revList('Paint', s).length, 11);
      expect(revList('Paint', s).every((e) => e.$2 == 'Tires'), true);
      expect(at('Interior', 'ph_int_cargo'), ('Tires', 'ph_int_cargo'));
      expect(at('Exterior', 'ph_ext_roof'), ('Tires', 'ph_ext_roof'));
      expect(at('Mechanicals', 'video_engine'), ('Interior', 'video_engine'));
      expect({for (final e in revList('OBDII', s)) e.$2}, {'Interior'});
      expect([for (final e in revList('Tires', s)) ids([e.$1]).single].length, 8);
      expect(ids([for (final e in revList('Exterior', s)) e.$1]), ['ph_vin_dash', 'video_360', 'ph_ext_roof']);
      // every shot of the pass shows on exactly one page
      final all = [for (final k in capseq) ...revList(k, s)], pass = [for (final k in camRun) ...capList(k, s)];
      expect(all.length, pass.length);
    });

    test('a tag stays at its own shot when a shot drops out of the list', () {
      final s = fresh('tg'), l = capList('Interior', s), keys = l.indexWhere((x) => x['id'] == 'ph_keys');
      final d = <String, dynamic>{'id': 'd', 'zone': 'Interior', 'sec': 'Interior', 'at': keys, 'key': 'ph_keys'};
      expect(tagAt(s, d), keys);
      lst(s, 'probs', 'ck_engine').add('Will not start'); // engine sound, before the keys, drops out
      expect(capList('Interior', s)[tagAt(s, d)!]['id'], 'ph_keys');
      expect(tagAt(s, {'sec': 'Interior', 'at': 3}), 3); // saved without its shot: by index, as before
      expect(tagAt(s, {'sec': 'Interior', 'key': 'video_engine'}), isNull);
    });

    test('a damage photo takes the zone of the shot it is taken at', () {
      final s = fresh('z'), w = capList('Tires', s);
      J shot(String k, String id) => capList(k, s).firstWhere((x) => (x['panel'] ?? (x['wheel'] != null ? '${x['id']}-${x['wheel']}' : x['id'])) == id);
      expect(shotZone(shot('Tires', 'Left rear door'), 'Tires'), 'Exterior');
      expect(shotZone(shot('Tires', 'tire_photo-lr'), 'Tires'), 'Tires');
      expect(shotZone(shot('Tires', 'ph_int_cargo'), 'Tires'), 'Interior');
      expect(shotZone(w.last, 'Tires'), 'Exterior'); // the roof photo
      expect(shotZone(shot('Interior', 'ph_obd_past'), 'Interior'), 'OBDII'); // no shutters there
      expect(shotZone(shot('Underbody', 'ph_under_lf'), 'Underbody'), 'Underbody');
      expect(shotZone(shot('Exterior', 'ph_vin_dash'), 'Exterior'), 'Exterior');
    });

    test('the questions at the end of each section', () {
      final s = fresh('q');
      // one line per group: its heading (- for the section's own list), then its rows
      List<String> heads(String k, J st) => [for (final g in askGroups(st, k)) '${g.head ?? '-'}: ${[if (g.feat) 'feat', for (final it in g.checks) it['id'], if (g.tm) 'tm'].join(' ')}'];
      final inter = heads('Interior', s);
      expect(inter.first, startsWith('-: feat ck_'));
      expect(inter.sublist(1), ['OBDII: ck_lights_dash ck_scan', 'Mechanicals: ck_trans']);
      expect(heads('Tires', s), [
        startsWith('Exterior: ck_glass'), 'Mechanicals: ck_brakes', 'Paint: ck_paint', 'Left front: ck_tire ck_wheel', 'Left rear: ck_tire ck_wheel', 'Right rear: ck_tire ck_wheel',
        'Right front: ck_tire ck_wheel', '-: tm',
      ]);
      final mech = heads('Mechanicals', s).single;
      expect(mech, contains('ck_leaks')); // asked after both Mechanicals and Underbody: one answer
      for (final out in askOut) {
        expect(mech.contains(out), false, reason: out);
      }
      expect(heads('Underbody', s), ['-: ck_structure ck_rust', 'Mechanicals: ck_leaks ck_exhaust ck_susp ck_cv']);
      // EV: no transmission, scan, leaks or exhaust; the battery pack check under the car
      final e = fresh('qe', fuel: ev);
      expect(heads('Interior', e).map((g) => g.split(':').first), ['-', 'OBDII']);
      expect(heads('Underbody', e), ['-: ck_structure ck_rust ck_pack', 'Mechanicals: ck_susp ck_cv']);
      expect(askQ.contains('Exterior'), false); // Exterior goes straight on
    });

    test('an inspection saved before 1109: its photos move to the same shots of the new pass, once', () {
      final s = fresh('o')..remove('c9');
      final old = capList0('Exterior', s), door = old.indexWhere((x) => x['panel'] == 'Left rear door');
      manual(s).addAll([
        {'id': 'a', 'zone': 'Exterior', 'sec': 'Exterior', 'at': door, 'f': 'a.jpg'},
        {'id': 'b', 'zone': 'Tires', 'sec': 'Tires', 'at': 2, 'f': 'b.jpg'}, // the left rear whole tire photo then
        {'id': 'c', 'zone': 'Interior', 'sec': 'Interior', 'at': 7, 'f': 'c.jpg'}, // cargo then
        {'id': 'd', 'zone': 'Mechanicals', 'sec': 'Underbody', 'at': 1, 'f': 'd.jpg'},
      ]);
      m(s, 'multi')['ph_mod_ext'] = [
        {'src': 'camera', 'sec': 'Exterior', 'at': door, 'f': 'm.jpg'},
        {'src': 'camera', 'sec': 'Exterior', 'at': 0, 'f': 'v.jpg'}, // at the walk-around video
      ];
      m(s, 'multi')['ph_mod_int'] = [
        {'src': 'camera', 'sec': 'Interior', 'at': 7, 'f': 'i.jpg'},
      ];
      s['cap'] = {'k': 'OBDII', 'i': 1};
      cam1109(s);
      final w = capList('Tires', s);
      (String, String) where(J e) => (e['sec'], ids([capList(e['sec'], s)[e['at']]]).single);
      expect([for (final d in manual(s)) where(d)], [('Tires', 'Left rear door'), ('Tires', 'tire_photo-lr'), ('Tires', 'ph_int_cargo'), ('Underbody', 'ph_under_lr')]);
      final ext = (m(s, 'multi')['ph_mod_ext'] as List).cast<J>();
      expect((where(ext[0]), ext[0]['rs']), (('Tires', 'Left rear door'), 'Exterior')); // still on Review Exterior
      expect((where(ext[1]), ext[1]['rs']), (('Exterior', 'video_360'), null));
      // a mod of another list stays in its section (the camera shows mods from their own section's list), at no shot of it
      final cargo = (m(s, 'multi')['ph_mod_int'] as List).single as J;
      expect((cargo['sec'], cargo['key'], tagAt(s, cargo)), ('Interior', 'ph_int_cargo', null));
      expect(s['cap'], {'k': 'Interior', 'i': 9}); // past codes, at the end of Interior now
      expect(w[manual(s)[0]['at'] as int]['panel'], 'Left rear door');
      // a second load changes nothing; a new inspection is never moved
      cam1109(s);
      expect(where(manual(s)[0]), ('Tires', 'Left rear door'));
      final nw = fresh('nw');
      manual(nw).add({'id': 'x', 'zone': 'Exterior', 'sec': 'Exterior', 'at': 1, 'f': 'x.jpg'});
      cam1109(nw);
      expect(manual(nw).single['at'], 1);
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

  testWidgets('the pass: camera kinds, Look for, the end-of-section questions, damage zones', (t) async {
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

    Finder card() => find.byKey(const ValueKey('ask')); // the end-of-section questions are up
    J? lastDamage(String id) => (store.ins[id]!['aiq'] as List).where((x) => x['kind'] == 'damage').lastOrNull as J?;

    // 1. Exterior done: the camera opens on Interior; photos use the whole sensor; Back to the video slot, the camera opens for 1080p video
    final e = fresh('e');
    m(e, 'shots')['ph_vin_dash'] = true;
    m(e, 'shots')['video_360'] = true;
    store.ins['e'] = e;
    cam.opened.clear();
    await open('e', const CamArgs(run: true));
    expect(cam.opened, [('wide', ResolutionPreset.max, null)]);
    expect(find.text('2/5  Interior · 1 of 12'), findsOneWidget);
    // Look for, top left: information only
    expect(find.text('LOOK FOR'), findsOneWidget);
    expect(find.text('Spot welds'), findsOneWidget);
    // a photo still being taken: the camera stays open until the photo is in
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
    expect(m(store.ins['e']!, 'shots')['ph_vin_door'], true);
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
    // Back from Interior's first shot: the walk-around video at the end of Exterior
    await t.tap(find.byIcon(LucideIcons.chevronLeft));
    await settle();
    expect(find.text('1/5  Exterior · 2 of 2'), findsOneWidget);
    expect(find.text('Move smoothly'), findsOneWidget);
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

    // 2. the walk-around: a damage at a tire is a tire damage, at a paint panel an Exterior one, read against every place of that zone
    final r = fresh('r');
    m(r, 'paint')['Left front fender'] = <String, dynamic>{'shot': true};
    store.ins['r'] = r;
    await open('r', const CamArgs(run: true, k: 'Tires'));
    expect(find.text('3/5  Walk-around · 2 of 21'), findsOneWidget);
    expect(find.text('Curb rash'), findsOneWidget); // the whole tire's Look for
    await t.tap(find.text('Damage'));
    await settle();
    expect(lastDamage('r'), containsPair('section', 'Tires'));
    expect(lastDamage('r')!.containsKey('near'), false);
    expect(lastDamage('r')!.containsKey('hint'), false);
    expect((manual(store.ins['r']!).single['zone'], manual(store.ins['r']!).single['sec']), ('Tires', 'Tires'));
    // Auto and a photo that takes long (the flash fired in the dark): the screen flashes once, at the tap, not again when it is in
    cam.hold = Completer<void>();
    await t.tap(find.byType(AnimatedContainer));
    await t.pump();
    expect(white(), findsOneWidget);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400))); // the photo takes a while
    await t.pump(const Duration(milliseconds: 400)); // the tap flash is over
    expect(white(), findsNothing);
    cam.hold!.complete();
    cam.hold = null;
    await t.pump();
    await t.pump();
    expect(white(), findsNothing);
    await settle();
    // with the flash On the photo comes a moment after the tap: the screen flashes once, when it is in, not before
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
    // on to the left front door: a damage there is Exterior, a mod there shows on Review Exterior
    expect(find.text('3/5  Walk-around · 4 of 21'), findsOneWidget);
    expect(find.text('A-pillar'), findsOneWidget);
    await t.tap(find.text('Damage'));
    await settle();
    expect(lastDamage('r'), containsPair('section', 'Exterior'));
    expect(manual(store.ins['r']!).last['zone'], 'Exterior');
    await t.tap(find.text('Mod'));
    await settle();
    expect(((m(store.ins['r']!, 'multi')['ph_mod_ext'] as List).single as Map)['rs'], 'Exterior');

    // 3. the roof photo ends the walk-around: its questions, the same answers as Review, in a dark drawer; Record damage; Next
    for (final x in capList('Tires', r)) {
      if (x['id'] != 'ph_ext_roof') capMark(r, x, 'camera', 'insp/r/${x['panel'] ?? x['id']}${x['wheel'] ?? ''}.jpg');
    }
    await open('r', const CamArgs(run: true, k: 'Tires'));
    expect(find.text('3/5  Walk-around · 21 of 21'), findsOneWidget);
    await t.tap(find.byType(AnimatedContainer)); // the shutter
    await settle();
    expect(card(), findsOneWidget);
    for (final h in ['EXTERIOR', 'MECHANICALS', 'PAINT', 'LEFT FRONT', 'RIGHT FRONT']) {
      expect(find.text(h), findsOneWidget, reason: h);
    }
    expect(find.text('Brakes'), findsOneWidget);
    expect(find.text('Next: Mechanicals'), findsOneWidget);
    await t.ensureVisible(find.text('All 4 tires match'));
    await settle();
    expect(find.descendant(of: find.ancestor(of: find.text('All 4 tires match'), matching: find.byType(RowBtn)), matching: find.text('Pick')), findsOneWidget);
    await t.tap(find.text('All 4 tires match'));
    await settle();
    expect(find.byType(Dialog), findsOneWidget); // the drawer, centred over the camera
    await t.tap(find.text('Mismatch'));
    await settle();
    expect(m(store.ins['r']!, 'vals')['tires_match'], 'Mismatch');
    expect(m(store.ins['r']!, 'vals')['tm_auto'], 0);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Mismatch'), findsOneWidget); // the card shows the answer
    await t.tap(find.text('Record damage'));
    await settle();
    expect(card(), findsNothing);
    expect(find.text('LOOK FOR'), findsNothing); // only the Damage and Mod shutters
    await t.tap(find.text('Damage'));
    await settle();
    expect(lastDamage('r'), containsPair('section', 'Exterior')); // at the roof photo
    // a mod, its tag picked in the strip, then Next: the pick stays behind with its section
    await t.tap(find.text('Mod'));
    await settle();
    await t.tap(find.descendant(of: find.byType(ListView), matching: find.byIcon(LucideIcons.wrench)).last);
    await settle();
    expect(find.text('Delete'), findsOneWidget);
    await t.tap(find.text('Next'));
    await settle();
    expect(find.textContaining('4/5  Mechanicals'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);

    // 4. Mechanicals ends on a video: its questions (not the ones asked after Interior, the walk-around or Underbody); Record damage
    // turns the camera back to photos and the Damage shutter works
    final k = fresh('k');
    for (final id in ['ph_engine_bay', 'ph_engine_oil']) {
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
    expect(card(), findsOneWidget);
    expect(find.text('Leaks'), findsOneWidget);
    expect(find.text('Transmission and clutch'), findsNothing);
    expect(find.text('Brakes'), findsNothing);
    expect(find.text('Next: Underbody'), findsOneWidget);
    expect(native.last, 'squeeze video_exhaust');
    // the engine will not start, answered on the card: the exhaust video drops out of the list, Record damage still has its shutters
    await t.tap(find.text('Engine'));
    await settle();
    await t.tap(find.text('Will not start'));
    await settle();
    expect(capList('Mechanicals', store.ins['k']!).length, 2);
    await t.tap(find.text('Record damage'));
    await settle();
    expect(cam.opened.last.$2, ResolutionPreset.max);
    await t.tap(find.text('Damage'));
    await settle();
    expect(manual(store.ins['k']!).single['sec'], 'Mechanicals');

    // 5. the OBDII screens end Interior: no Damage and Mod shutters on them; then the Interior questions with OBDII's, Next: Walk-around
    final o = fresh('o');
    final ol = capList('Interior', o);
    for (final x in ol.take(ol.length - 1)) {
      capMark(o, x, 'camera', 'insp/o/${x['id']}.${(x['it'] as J)['kind'] == 'video' ? 'mp4' : 'jpg'}');
    }
    store.ins['o'] = o;
    await open('o', const CamArgs(run: true, k: 'Interior'));
    expect(isMulti(ol.last['id']), true); // other images: as many as needed, then Done
    expect(find.text('ABS faults'), findsOneWidget);
    await t.tap(find.text('Damage'));
    await settle();
    expect(manual(store.ins['o']!), isEmpty);
    await t.tap(find.byType(AnimatedContainer));
    await settle();
    await t.tap(find.text('Done · 1'));
    await settle();
    expect(card(), findsOneWidget);
    expect(find.text('Number of keys'), findsOneWidget);
    expect(find.text('OBDII'), findsOneWidget);
    expect(find.text('Transmission and clutch'), findsOneWidget);
    await t.tap(find.text('Next: Walk-around'));
    await settle();
    expect(card(), findsNothing);
    expect(find.text('3/5  Walk-around · 1 of 21'), findsOneWidget);

    // 6. the camera opened again goes on where it stopped, unless an earlier section still has shots to take
    final g = fresh('g')..['cap'] = {'k': 'Tires', 'i': 4};
    m(g, 'shots')['ph_vin_dash'] = true;
    m(g, 'shots')['video_360'] = true;
    store.ins['g'] = g;
    await open('g', const CamArgs(run: true));
    expect(find.text('2/5  Interior · 1 of 12'), findsOneWidget);
    // the OBDII scanner shots (at the end of Interior) have the title Scanner Result
    final sc = fresh('sc'), at = capList('Interior', sc).indexWhere((x) => x['id'] == 'ph_obd_current');
    sc['cap'] = {'k': 'Interior', 'i': at};
    for (final x in [...capList('Exterior', sc), ...capList('Interior', sc).take(at)]) {
      capMark(sc, x, 'camera', 'insp/sc/${x['id']}.jpg');
    }
    store.ins['sc'] = sc;
    await open('sc', const CamArgs(run: true));
    expect(find.text('2/5  Scanner Result · ${at + 1} of 12'), findsOneWidget);
    expect(find.text('Current codes'), findsOneWidget);
    final g2 = fresh('g2')..['cap'] = {'k': 'Exterior', 'i': 1};
    for (final x in [...capList('Exterior', g2), ...capList('Interior', g2)]) {
      capMark(g2, x, 'camera', 'insp/g2/${x['id']}.jpg');
    }
    store.ins['g2'] = g2;
    await open('g2', const CamArgs(run: true));
    expect(find.text('3/5  Walk-around · 1 of 21'), findsOneWidget);
  });
}
