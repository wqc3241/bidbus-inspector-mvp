// Summary, What you found: a finding with a photo shows it small (a damage its own photo; a check problem the damage photos behind it,
// with their number); tapping it shows the photos full screen to look at only, and closing goes back.
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/db/db.dart';
import 'package:bidbus_field/logic/insp.dart';
import 'package:bidbus_field/screens/summary.dart';
import 'package:bidbus_field/services/store.dart';
import 'package:bidbus_field/widgets/ui.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lucide_icons_flutter/lucide_icons.dart';

class _Db extends Db {
  _Db() : super(NativeDatabase.memory());
  @override
  Future<void> put(String id, String json) async {}
}

final _tmp = Directory.systemTemp.createTempSync('sum');

J withDamages() {
  final s = newInspection(id: 'p', fuel: 'Gas or diesel', email: 'a@b.co', inspector: 'T', car: {'year': 2020, 'make': 'X', 'model': 'Y', 'trim': 'Z'})
    ..['phase'] = 'final';
  var n = 0;
  J dmg(String panel, String type, String sev) {
    final f = 'p-${n++}.jpg';
    File('${_tmp.path}/$f').writeAsBytesSync(img.encodeJpg(img.Image(width: 40, height: 30)));
    final d = <String, dynamic>{'id': 'd$n', 'zone': 'Exterior', 'panel': '', 'type': '', 'sev': '', 'size': '', 'src': 'camera', 'f': f};
    setLabel(d, 'panel', panel, 'Gas or diesel');
    setLabel(d, 'type', type, 'Gas or diesel');
    setLabel(d, 'sev', sev, 'Gas or diesel');
    return d;
  }

  manual(s).addAll([dmg('Left front door', 'Dent', 'Minor'), dmg('Right front wheel', 'Curb rash', 'Minor'), dmg('Right front wheel', 'Curb rash', 'Moderate')]);
  syncDamages(s);
  return s;
}

void main() {
  setUpAll(() {
    initQl(jsonDecode(File('assets/question-list.json').readAsStringSync()));
    store.db = _Db();
    store.docs = _tmp.path;
  });

  test('a check problem knows the damage photos behind it', () {
    final s = withDamages();
    final wheel = problemsList(s).singleWhere((p) => p['text'] == 'Wheel: Curb rash');
    expect(wheel['photos'], ['p-1.jpg', 'p-2.jpg']);
    expect(dmgPhotos(s, 'p', 'ck_wheel', 'rf', 'Curb rash'), ['p-1.jpg', 'p-2.jpg']);
    expect(dmgPhotos(s, 'p', 'ck_wheel', 'lf', 'Curb rash'), isEmpty); // another wheel
    // the door dent answers no check: it is its own finding, with its own photo
    final ext = findingsBySec(s).singleWhere((g) => g.$1 == 'Exterior');
    expect(ext.$3.single['f'], 'p-0.jpg');
    expect(dmgLine(ext.$3.single), startsWith('Left front door: Dent, Minor'));
  });

  testWidgets('photos small in the list, large to look at only', (t) async {
    t.view.physicalSize = const Size(1290, 2796);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    store.ins['p'] = withDamages();
    await t.pumpWidget(const ProviderScope(child: MaterialApp(home: SummaryScreen('p'))));
    await t.pumpAndSettle();
    final thumbs = find.byType(PhotoThumb);
    expect(thumbs, findsNWidgets(2));
    final byCaption = {for (final e in thumbs.evaluate()) (e.widget as PhotoThumb).caption: (e.widget as PhotoThumb).paths.map((p) => p.split('/').last).toList()};
    expect(byCaption['Wheel: Curb rash'], ['p-1.jpg', 'p-2.jpg']);
    expect(byCaption.keys.where((c) => c.startsWith('Left front door: Dent')).length, 1);
    final wheel = find.byWidgetPredicate((w) => w is PhotoThumb && w.caption == 'Wheel: Curb rash');
    expect(find.descendant(of: wheel, matching: find.text('2')), findsOneWidget); // two photos behind the wheel problem
    final before = store.ins['p'].toString();

    // tap: full screen, the finding as caption, swipe to the second; no way to change anything there
    await t.ensureVisible(wheel);
    await t.tap(wheel);
    await t.pumpAndSettle();
    expect(find.text('Wheel: Curb rash'), findsWidgets);
    expect(find.text('1 / 2'), findsOneWidget);
    for (final ic in [LucideIcons.pen, LucideIcons.trash2, LucideIcons.camera, LucideIcons.rotateCcw]) {
      expect(find.descendant(of: find.byType(PageView), matching: find.byIcon(ic)), findsNothing);
    }
    // zoomed in, a sideways drag looks across the photo, it does not turn to the next one
    final mid = t.getCenter(find.byType(PageView));
    final a = await t.startGesture(mid - const Offset(40, 0), pointer: 7), b = await t.startGesture(mid + const Offset(40, 0), pointer: 8);
    for (var k = 1; k <= 10; k++) {
      await a.moveTo(mid - Offset(40.0 + 12 * k, 0));
      await b.moveTo(mid + Offset(40.0 + 12 * k, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await t.pumpAndSettle();
    final iv = t.widget<InteractiveViewer>(find.byType(InteractiveViewer).first).transformationController!;
    expect(iv.value.getMaxScaleOnAxis(), greaterThan(1.5));
    final x0 = iv.value.getTranslation().x;
    await t.drag(find.byType(PageView), const Offset(-250, 0));
    await t.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(iv.value.getTranslation().x, lessThan(x0 - 50)); // panned
    // back to full size (double pinch in): swiping turns the photos again
    iv.value = Matrix4.identity();
    final a2 = await t.startGesture(mid - const Offset(90, 0), pointer: 9), b2 = await t.startGesture(mid + const Offset(90, 0), pointer: 10);
    await a2.moveTo(mid - const Offset(89, 0));
    await b2.moveTo(mid + const Offset(89, 0));
    await a2.up();
    await b2.up();
    await t.pumpAndSettle();
    await t.fling(find.byType(PageView), const Offset(-400, 0), 1500);
    await t.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    expect(find.byType(PageView), findsNothing);
    expect(find.byType(PhotoThumb), findsNWidgets(2));
    expect(store.ins['p'].toString(), before); // looking changed nothing
  });
}
