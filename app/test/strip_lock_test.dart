// Damages and Review strips: while the current page is unfinished, the tabs after it are shut;
// a shut tab does nothing when tapped, and the Damages pages stop at the last photo of the open tabs.
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/db/db.dart';
import 'package:bidbus_field/logic/insp.dart';
import 'package:bidbus_field/screens/damages.dart';
import 'package:bidbus_field/screens/review.dart';
import 'package:bidbus_field/services/store.dart';
import 'package:bidbus_field/widgets/ui.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class _Db extends Db {
  _Db() : super(NativeDatabase.memory());
  @override
  Future<void> put(String id, String json) async {}
}

J dm(String did, String zone) => {'id': did, 'zone': zone, 'panel': '', 'type': '', 'sev': '', 'size': '', 'src': 'camera'};

void main() {
  setUpAll(() {
    initQl(jsonDecode(File('assets/question-list.json').readAsStringSync()));
    store.db = _Db();
    store.docs = Directory.systemTemp.path;
  });

  test('how far a strip opens', () {
    expect(openTo([true, false, true, false], 0), 1);
    expect(openTo([true, false, true, false], 1), 1);
    // on a later tab while an earlier one is unfinished: nothing after the current tab opens
    expect(openTo([true, false, true, false], 2), 2);
    expect(openTo([true, true, false, false], 0), 2);
    expect(openTo([true, true, true], 0), 2);
  });

  testWidgets('shut tabs do nothing; they open when the page is done', (t) async {
    // wide: the test font draws every letter a full square, so long values need the room
    t.view.physicalSize = const Size(2400, 2622);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    J fresh(String id) => newInspection(id: id, fuel: 'Gas or diesel', email: 'a@b.co', inspector: 'T', car: {'year': 2020, 'make': 'X', 'model': 'Y', 'trim': 'Z'});

    // Review, on Tires & Wheels (no tread depths yet): Paint after it is shut, Start before it is open
    final r = fresh('r')
      ..['phase'] = 'review'
      ..['sp'] = 2;
    store.ins['r'] = r;
    await t.pumpWidget(const ProviderScope(child: MaterialApp(home: ReviewScreen('r', key: ValueKey(1)))));
    await t.pumpAndSettle();
    // the strip builds only the tabs in view: scroll it to the tab (left first, then right), then tap
    Future<void> tab(String name) async {
      final strip = find.descendant(of: find.byType(TabStrip), matching: find.byType(Scrollable));
      for (final dx in [-80.0, 80.0]) {
        if (find.text(name).evaluate().isEmpty) {
          await t.scrollUntilVisible(find.text(name), dx, scrollable: strip, maxScrolls: 20).catchError((_) {});
        }
      }
      await t.ensureVisible(find.text(name));
      await t.pumpAndSettle();
      await t.tap(find.text(name));
      await t.pumpAndSettle();
    }

    await tab('Paint');
    expect(store.ins['r']!['sp'], 2);
    await tab('Start');
    expect(store.ins['r']!['sp'], 0);
    // on Start with the owner question open, Exterior is shut; answered, a page further on is still shut while Exterior is unfinished
    await tab('Exterior');
    expect(store.ins['r']!['sp'], 0);
    store.mut('r', (x) => x['owner'] = 'Yes');
    await t.pumpAndSettle();
    await tab('Tires & Wheels');
    expect(store.ins['r']!['sp'], 0);
    // Start is done now: Exterior opens
    await tab('Exterior');
    expect(store.ins['r']!['sp'], 1);

    // Damages: two Exterior photos to label, so the Tires & Wheels tab is shut and the pages stop at Exterior
    final s = fresh('d')..['phase'] = 'label';
    (s['manual'] as List).addAll([dm('e0', 'Exterior'), dm('e1', 'Exterior'), dm('t2', 'Tires')]);
    s['li'] = 0;
    store.ins['d'] = s;
    await t.pumpWidget(const ProviderScope(child: MaterialApp(home: DamagesScreen('d', key: ValueKey(2)))));
    await t.pumpAndSettle();
    expect(t.widget<PageView>(find.byType(PageView)).childrenDelegate.estimatedChildCount, 2);
    await t.tap(find.text('Tires & Wheels 0/1'));
    await t.pumpAndSettle();
    expect(store.ins['d']!['li'], 0);

    // label both Exterior photos: the next tab opens
    store.mut('d', (x) {
      for (final d in manual(x).take(2)) {
        setLabel(d, 'panel', 'Left front door', fuelOf(x));
        d['type'] = 'Overspray or colour mismatch';
        d['sev'] = 'Minor';
      }
      syncDamages(x);
    });
    await t.pumpAndSettle();
    expect(t.widget<PageView>(find.byType(PageView)).childrenDelegate.estimatedChildCount, 3);
    await t.tap(find.text('Tires & Wheels 0/1'));
    await t.pumpAndSettle();
    expect(store.ins['d']!['li'], 2);

    // deleting a photo stays on its tab
    final x = fresh('x')..['phase'] = 'label';
    (x['manual'] as List).addAll([dm('e0', 'Exterior'), dm('e1', 'Exterior'), dm('t2', 'Tires')]);
    x['li'] = 1;
    store.ins['x'] = x;
    await t.pumpWidget(const ProviderScope(child: MaterialApp(home: DamagesScreen('x', key: ValueKey(3)))));
    await t.pumpAndSettle();
    expect(find.text('Exterior · 2 of 2'), findsOneWidget);
    await t.tap(find.byIcon(LucideIcons.trash2));
    await t.pumpAndSettle();
    expect(manual(store.ins['x']!).map((d) => d['id']), ['e0', 't2']);
    expect(store.ins['x']!['li'], 0);
    expect(find.text('Exterior · 1 of 1'), findsOneWidget);
  });

  test('the next photo to label is on the same tab first, then the first one still to label', () {
    final s = newInspection(id: 'n', fuel: 'Gas or diesel', email: 'a@b.co', inspector: 'T', car: {'year': 2020, 'make': 'X', 'model': 'Y', 'trim': 'Z'});
    (s['manual'] as List).addAll([dm('e0', 'Exterior'), dm('e1', 'Exterior'), dm('t2', 'Tires'), dm('i3', 'Interior')]);
    // from the second Exterior photo, the first one (still to label) comes before the Tires photo
    expect(nextUnlabelled(s, 1), 0);
    // from a done Tires photo, the unfinished Exterior comes before Interior
    final d = manual(s)[2];
    setLabel(d, 'panel', 'Right rear tire', 'Gas or diesel');
    setLabel(d, 'type', 'Uneven wear', 'Gas or diesel');
    setLabel(d, 'sev', 'Minor', 'Gas or diesel');
    expect(nextUnlabelled(s, 2), 0);
  });

}
