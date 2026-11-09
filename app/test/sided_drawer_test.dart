// A mirror, headlight or tail light is on one side: the car map picks and shows only that side, the damage keeps it (side) and the
// record says it (where: Left or Right). The reason drawer takes at most half the screen; its reasons scroll, severity stays in view.
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/db/db.dart';
import 'package:bidbus_field/logic/insp.dart';
import 'package:bidbus_field/logic/payload.dart';
import 'package:bidbus_field/screens/damages.dart';
import 'package:bidbus_field/services/store.dart';
import 'package:bidbus_field/widgets/car_map.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Db extends Db {
  _Db() : super(NativeDatabase.memory());
  @override
  Future<void> put(String id, String json) async {}
}

const fuel = 'Gas or diesel';
J fresh() => newInspection(id: 'p', fuel: fuel, email: 'a@b.co', inspector: 'T', car: {'year': 2020, 'make': 'X', 'model': 'Y', 'trim': 'Z'});
J dmg() => <String, dynamic>{'id': 'd1', 'zone': 'Exterior', 'panel': '', 'type': '', 'sev': '', 'size': '', 'src': 'camera', 'f': 'x.jpg'};

void main() {
  setUpAll(() {
    initQl(jsonDecode(File('assets/question-list.json').readAsStringSync()));
    store.db = _Db();
    store.docs = Directory.systemTemp.path;
  });

  test('the side of a mirror, headlight or tail light', () {
    expect(placeSide('Left mirror'), ('Mirror', 'Left'));
    expect(placeSide('Right tail light'), ('Tail light', 'Right'));
    expect(placeSide('Left front door'), ('Left front door', null)); // a place of its own, not a side
    final d = dmg();
    setLabel(d, 'panel', 'Right headlight', fuel);
    setLabel(d, 'type', 'Headlight not working', fuel);
    setLabel(d, 'sev', 'Minor', fuel);
    expect((d['panel'], d['side'], panelName(d)), ('Headlight', 'Right', 'Right headlight'));
    expect(labelled(d, fuel), true);
    expect(dmgLine(d), 'Headlight: Not working (right), Minor');
    // the other side: same place, the type stays
    setLabel(d, 'panel', 'Left headlight', fuel);
    expect((d['side'], d['type']), ('Left', 'Headlight not working'));
    // the AI's guess or a pick with no side: not labelled until a side is picked
    final g = dmg()
      ..['panel'] = 'Mirror'
      ..['type'] = 'Mirror damaged'
      ..['sev'] = 'Minor';
    expect(labelled(g, fuel), false);
    // another place drops the side
    setLabel(d, 'panel', 'Hood', fuel);
    expect(d.containsKey('side'), false);
    expect(panelName(d), 'Hood');
  });

  test('the record says the side as where', () {
    final s = fresh();
    final d = dmg();
    setLabel(d, 'panel', 'Left tail light', fuel);
    setLabel(d, 'type', 'Tail light cracked or water inside', fuel);
    setLabel(d, 'sev', 'Moderate', fuel);
    final door = dmg()..['id'] = 'd2';
    setLabel(door, 'panel', 'Left front door', fuel);
    setLabel(door, 'type', 'Dent', fuel);
    setLabel(door, 'sev', 'Minor', fuel);
    manual(s).addAll([d, door]);
    syncDamages(s);
    final rec = inspectionPayload(s).record, ds = rec['damages'] as List;
    expect((ds[0]['place'], ds[0]['where']), ('Tail light', 'Left'));
    expect((ds[1] as Map).containsKey('where'), false); // a door needs no side
  });

  testWidgets('the car map picks and shows one side', (t) async {
    t.view.physicalSize = const Size(1290, 2796);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final have = placesFor('Exterior', fuel).map((p) => p['p'] as String).toSet();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: CarTopMap(sel: 'Left mirror', have: have, onPick: (_) {}))));
    final pills = find.text('Mirror').evaluate().map((e) => (e.widget as Text).style!.color).toList();
    expect(pills, [Colors.white, const Color(0xFF111111)]); // the left pill is picked (white on black), the right one is not
    expect(find.text('Left mirror'), findsOneWidget); // the caption under the car
    await t.pumpWidget(MaterialApp(home: Scaffold(body: CarTopMap(sel: 'Mirror', have: have, onPick: (_) {}))));
    expect(find.text('Mirror').evaluate().map((e) => (e.widget as Text).style!.color).toSet(), {const Color(0xFF111111)}); // no side: neither
    expect(find.text('Mirror'), findsNWidgets(2)); // the two pills, no caption
    // a tile under the car (not drawn on it) still names itself under the car
    await t.pumpWidget(MaterialApp(home: Scaffold(body: CarTopMap(sel: 'Wipers', have: have, onPick: (_) {}))));
    expect(find.text('Wipers'), findsOneWidget);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: CarTopMap(sel: 'Hood', have: have, onPick: (_) {}))));
    expect(find.text('Hood'), findsNWidgets(2)); // its pill and the caption
  });

  // last in the file: its ProviderScope disposes the app's store when the test ends
  testWidgets('the reason drawer is at most half the screen; reasons scroll, severity stays', (t) async {
    t.view.physicalSize = const Size(1179, 2001); // a short phone
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final s = fresh(), d = dmg();
    setLabel(d, 'panel', 'Left front door', fuel);
    manual(s).add(d);
    store.ins['p'] = s;
    await t.pumpWidget(ProviderScope(
        child: MaterialApp(home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => labelDrawer(c, 'p', 'd1'), child: const Text('open')))))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    final sheet = t.getRect(find.byType(BottomSheet)), screen = t.view.physicalSize.height / 3;
    expect(sheet.height, lessThanOrEqualTo(screen / 2 + 1));
    // severity and Done are in view without scrolling
    for (final v in dmgSev) {
      expect(t.getRect(find.text(v)).bottom, lessThanOrEqualTo(screen));
    }
    expect(t.getRect(find.text('Done')).bottom, lessThanOrEqualTo(screen));
    // the reasons scroll: the last one comes into view, the place name stays on top
    final types = placeOpts(placeOf('Exterior', 'Left front door'), fuel);
    expect(types.length, greaterThan(6));
    final list = find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable));
    final last = find.text(dshort('Left front door', types.last));
    await t.scrollUntilVisible(last, 80, scrollable: list);
    await t.ensureVisible(last);
    await t.pumpAndSettle();
    expect(t.getRect(last).bottom, lessThan(t.getRect(find.text('SEVERITY')).top)); // in the list, above the fixed severity
    await t.tap(last);
    await t.pumpAndSettle();
    expect(store.ins['p']!['manual'][0]['type'], types.last);
    expect(find.text('Left front door'), findsWidgets);
    await t.tap(find.text('Minor'));
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing); // labelled: the drawer closes
  });
}
