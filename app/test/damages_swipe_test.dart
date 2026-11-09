// Damages: every photo is a page. A swipe drags the page; a photo picked another way slides in;
// a finger on the page during a slide stops it, and the page where it comes to rest is the photo shown.
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/db/db.dart';
import 'package:bidbus_field/logic/insp.dart';
import 'package:bidbus_field/screens/damages.dart';
import 'package:bidbus_field/services/store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Db extends Db {
  _Db() : super(NativeDatabase.memory());
  @override
  Future<void> put(String id, String json) async {}
}

const id = 'swipe';
J st() => store.ins[id]!;
J dm(String did, String zone) => {'id': did, 'zone': zone, 'panel': '', 'type': '', 'sev': '', 'size': '', 'src': 'camera'};
double page(WidgetTester t) => t.widget<PageView>(find.byType(PageView)).controller!.page!;
int shown(WidgetTester t) => labelOrder(st())[page(t).round()];

// one ProviderScope for the whole file: it disposes the app's store when it goes
Future<void> open(WidgetTester t, int n) async {
  final s = newInspection(id: id, fuel: 'Gas or diesel', email: 'a@b.co', inspector: 'T', car: {'year': 2020, 'make': 'X', 'model': 'Y', 'trim': 'Z'});
  s['phase'] = 'label';
  (s['manual'] as List).addAll([dm('e0', 'Exterior'), dm('e1', 'Exterior'), dm('t2', 'Tires'), dm('i3', 'Interior'), dm('m4', 'Mechanicals')]);
  // every tab before Mechanicals is labelled, so all five pages are open (an unfinished tab shuts the ones after it)
  for (final (i, place, type) in [(0, 'Left front door', 'Overspray or colour mismatch'), (1, 'Left front door', 'Overspray or colour mismatch'), (2, 'Right rear tire', 'Uneven wear'), (3, 'Front seats', 'Seats worn')]) {
    final d = manual(s)[i];
    setLabel(d, 'panel', place, 'Gas or diesel');
    setLabel(d, 'type', type, 'Gas or diesel');
    setLabel(d, 'sev', 'Minor', 'Gas or diesel');
  }
  s['li'] = labelOrder(s).first;
  store.ins[id] = s;
  await t.pumpWidget(ProviderScope(child: MaterialApp(home: DamagesScreen(id, key: ValueKey(n)))));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() {
    initQl(jsonDecode(File('assets/question-list.json').readAsStringSync()));
    store.db = _Db();
    store.docs = Directory.systemTemp.path;
  });

  testWidgets('swipe, slide in, and a finger that stops a slide', (t) async {
    // wide: the labelled photos show long values, and the test font draws every letter a full square
    t.view.physicalSize = const Size(2400, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    // a swipe moves one page and the photo follows
    await open(t, 1);
    expect(t.widget<PageView>(find.byType(PageView)).childrenDelegate.estimatedChildCount, 5);
    await t.fling(find.byType(PageView), const Offset(-300, 0), 1500);
    await t.pumpAndSettle();
    expect(page(t), 1);
    expect(st()['li'], shown(t));

    // a photo picked another way slides there; the pages passed do not change it
    await open(t, 2);
    store.mut(id, (s) => s['li'] = 4);
    final seen = <dynamic>{};
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 16));
      seen.add(st()['li']);
    }
    await t.pumpAndSettle();
    expect(seen, {4});
    expect(page(t), 4);

    // a finger on the page stops a slide, and dragging back is followed
    await open(t, 3);
    store.mut(id, (s) => s['li'] = 4);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 16)); // the slide is under way
    }
    expect(page(t) > .3 && page(t) < 3.7, true, reason: 'not mid slide: ${page(t)}');
    final g = await t.startGesture(t.getCenter(find.byType(PageView)));
    await t.pump(const Duration(milliseconds: 16));
    final held = page(t);
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    expect((page(t) - held).abs() < .01, true, reason: 'the slide goes on under the finger: $held -> ${page(t)}');
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(15, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(page(t) < held, true, reason: 'dragging back did not move the page');
    await g.up();
    await t.pumpAndSettle();
    expect(page(t) <= held.ceilToDouble(), true);
    expect(st()['li'], shown(t));
    expect(t.takeException(), isNull);
  });
}
