// Walk-through of every screen without the camera (the simulator has none): the camera pass is replaced by a fake that
// saves generated photos the way the camera does. Ends with a real upload to the server and the Sent screen.
// flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart --dart-define=PASSCODE=...
import 'dart:io';

import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/logic/insp.dart';
import 'package:bidbus_field/main.dart';
import 'package:bidbus_field/services/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:signature/signature.dart';

String photo(String id, String name, int shade) {
  final rel = '${store.dirOf(id)}/$name.jpg';
  final im = img.Image(width: 320, height: 180)..clear(img.ColorRgb8(shade % 255, 90, 120));
  File(store.abs(rel)).writeAsBytesSync(img.encodeJpg(im));
  return rel;
}

// the fake camera service: every slot of the pass taken, a damage photo in three sections, a mod photo, and the readings the AI gives
void fakePass(String id) {
  var n = 0;
  store.mut(id, (st) {
    for (final k in camseq) {
      for (final x in capList(k, st)) {
        final it = x['it'] as J;
        if (it['optional'] == true && !isMulti(x['id'])) {
          m(st, 'skip')[x['id']] = true;
          continue;
        }
        capMark(st, x, 'camera', photo(id, 'shot${n++}', n * 9));
      }
    }
    m(st, 'shots')['video_360'] = true;
    st['spin'] = [for (var i = 1; i <= 36; i++) photo(id, 'spin-${'$i'.padLeft(2, '0')}', i * 7)];
    m(st, 'files')['video_360'] = photo(id, 'walk', 1).replaceAll('.jpg', '.mp4');
    for (final v in ['video_engine', 'video_exhaust']) {
      if (m(st, 'shots')[v] == true) {
        m(st, 'files')[v] = photo(id, v, 2).replaceAll('.jpg', '.mp4');
        File(store.abs(m(st, 'files')[v])).writeAsBytesSync(List.filled(2048, 0));
      }
    }
    File(store.abs(m(st, 'files')['video_360'])).writeAsBytesSync(List.filled(2048, 0));
    final vals = m(st, 'vals');
    vals.addAll({'vin_read': '5UXTY5C00L9B00230', 'vin_door': '5UXTY5C00L9B00230', 'vin_scan': 1, 'odo_read': '61325', 'keys_n': '2', 'keys_auto': 1});
    for (final w in wheels) {
      tire(st, w[0])
        ..['tread'] = '7'
        ..['treadAuto'] = true
        ..['read'] = {'brand': 'Michelin', 'size': '245/50R19', 'auto': true};
    }
    for (final p in paintPanels) {
      (m(st, 'paint')[p[1]] as J)
        ..['v'] = p[1] == 'Left rear door' ? '11.8' : '4.6'
        ..['auto'] = true;
    }
    syncPaint(st);
    // an AI guess to confirm, and two photos to label by hand
    manual(st).addAll([
      {'id': 'd1', 'zone': 'Exterior', 'sec': 'Exterior', 'at': 3, 'panel': 'Left front door', 'type': 'Scratch', 'sev': 'Minor', 'size': '', 'src': 'camera', 'f': photo(id, 'damage1', 40), 'ai': true, 'aiWas': {'place': 'Left front door', 'type': 'Scratch', 'severity': 'Minor'}},
      {'id': 'd2', 'zone': 'Exterior', 'sec': 'Exterior', 'at': 12, 'panel': '', 'type': '', 'sev': '', 'size': '', 'src': 'camera', 'f': photo(id, 'damage2', 80)},
      {'id': 'd3', 'zone': 'Tires', 'sec': 'Tires', 'at': 4, 'panel': '', 'type': '', 'sev': '', 'size': '', 'src': 'camera', 'f': photo(id, 'damage3', 120)},
    ]);
    syncDamages(st);
    final mods = (m(st, 'multi')['ph_mod_int'] ??= <dynamic>[]) as List;
    mods.add({'src': 'camera', 'panel': null, 'sec': 'Interior', 'at': 2, 'f': photo(id, 'mod1', 160)});
    m(st, 'shots')['ph_mod_int'] = 1;
  });
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every screen without the camera, then a real upload', (t) async {
    await loadQl();
    await store.init();
    await store.saveSettings(server: defaultServer, passcode: const String.fromEnvironment('PASSCODE'), inspector: 'Tom', email: 'qichaotomwang@gmail.com');
    await t.pumpWidget(const ProviderScope(child: App()));
    await t.pumpAndSettle();
    var shotN = 0;
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      await binding.takeScreenshot('${'${++shotN}'.padLeft(2, '0')}-$name');
    }

    Future<void> tap(Finder f) async {
      await t.ensureVisible(f.first);
      await t.pumpAndSettle();
      await t.tap(f.first);
      await t.pumpAndSettle();
    }

    Future<void> wait(Duration d) async {
      final end = DateTime.now().add(d);
      while (DateTime.now().isBefore(end)) {
        await t.pump(const Duration(milliseconds: 200));
      }
    }

    await shot('home');
    // Settings: health check against the server
    await tap(find.byIcon(LucideIcons.settings));
    await wait(const Duration(seconds: 3));
    await shot('settings');
    expect(find.text('Server: OK'), findsOneWidget);
    Navigator.of(t.element(find.byType(Scaffold).last)).pop();
    await t.pumpAndSettle();
    // New inspection with a VIN: the server decodes it
    await tap(find.text('New inspection'));
    await t.enterText(find.byType(TextField).first, '5UXTY5C00L9B00230');
    await wait(const Duration(seconds: 6));
    await t.pumpAndSettle();
    Future<Finder> field(String label) async {
      await t.scrollUntilVisible(find.text(label), 120, scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      return find.descendant(of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first, matching: find.byType(TextField));
    }

    final trim = await field('Trim');
    if (t.widget<TextField>(trim).controller!.text.isEmpty) await t.enterText(trim, 'xDrive30i');
    await t.enterText(await field('Owner name (optional)'), 'Daniel Kim');
    await t.pumpAndSettle();
    await shot('new-inspection');
    await tap(find.text('At the car: check ID'));
    final id = store.list.first['id'] as String;
    expect(store.ins[id]!['car']['make'], isNotEmpty);
    // Check ID: Start stays off until both documents and the owner answer are in
    expect(find.text('Add the license and registration'), findsOneWidget);
    store.mut(id, (st) {
      for (final d in ['ph_license', 'ph_reg']) {
        m(st, 'files')[d] = photo(id, d, 200);
        m(st, 'docs')[d] = DateTime.now().toIso8601String();
      }
    });
    await t.pumpAndSettle();
    expect(find.text('Answer the owner question'), findsOneWidget);
    await tap(find.text('Yes'));
    await shot('check-id');
    await tap(find.text('Start inspection'));
    await wait(const Duration(seconds: 3)); // the camera screen opens at once (no camera on the simulator)
    await shot('camera-no-device');
    Navigator.of(t.element(find.byType(Scaffold).last)).pop();
    await t.pumpAndSettle();
    await shot('camera-closed');
    fakePass(id);
    await t.pumpAndSettle();
    await tap(find.text('Next: Damages'));
    // Damages: confirm the AI guess, label the other two on the pictures
    await shot('damages-ai-guess');
    await tap(find.text('Confirm'));
    await tap(find.text('Hood'));
    await shot('damages-drawer');
    await tap(find.text('Dent'));
    await tap(find.text('Minor').last); // labelled: Damages moves on to the next photo by itself
    await tap(find.text('Tire'));
    await tap(find.text('Uneven wear'));
    await tap(find.text('Moderate').last);
    await shot('damages-tire');
    await tap(find.text('Next: Review'));
    // Review: answer what has no default, then Next through every page
    for (var page = 0; page < capseq.length; page++) {
      final k = capseq[page];
      if (k == 'Tires') {
        await tap(find.text('All 4 tires match'));
        await tap(find.text('Match'));
      }
      if (k == 'Interior') {
        await tap(find.text('Sunroof'));
        await tap(find.text('Works'));
        await tap(find.text('Navigation'));
        await tap(find.text('No navigation'));
      }
      if (k == 'Exterior') {
        await tap(find.text('Lights'));
        await shot('review-drawer');
        await tap(find.text('OK').last);
        // 360 view: cloudimage-360-view over the frames on the phone
        await tap(find.text('360 view'));
        await wait(const Duration(seconds: 4));
        await shot('review-360');
        Navigator.of(t.element(find.text('360 view').last)).pop();
        await t.pumpAndSettle();
      }
      await shot('review-$k');
      await tap(find.textContaining('Next: '));
    }
    // Summary: confirm VIN and mileage, overall condition, note
    await shot('summary');
    await tap(find.text('Confirm VIN and mileage'));
    await tap(find.text('Overall condition'));
    await tap(find.text('Pretty great'));
    await t.enterText(find.byType(TextField).last, 'Clean car for its age. Left rear door repainted.');
    await t.pumpAndSettle();
    await shot('summary-done');
    await tap(find.text('Show the seller'));
    // Seller signs
    expect(t.widget<FilledButton>(find.ancestor(of: find.text('Sign'), matching: find.byType(FilledButton))).onPressed, isNull);
    await tap(find.text('I have read and agree to this disclosure.'));
    await t.ensureVisible(find.byType(Signature));
    await t.drag(find.byType(Signature), const Offset(160, 30));
    await t.pumpAndSettle();
    await shot('sign');
    await tap(find.text('Sign'));
    // upload: record, then each file, then the report
    for (var i = 0; i < 90 && store.ins[id]!['status'] != 'sent' && store.ins[id]!['status'] != 'failed'; i++) {
      await wait(const Duration(seconds: 2));
      if (i % 10 == 0) store.kick();
    }
    await shot('sent');
    expect(store.ins[id]!['status'], 'sent', reason: '${store.ins[id]!['up']}');
    debugPrint('SELLER ${store.ins[id]!['up']['seller_url']}');
    debugPrint('DEALER ${store.ins[id]!['up']['dealer_url']}');
  });
}
