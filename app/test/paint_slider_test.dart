// Paint reading: a slider from 3.0 to 10+ mils with - and + for 0.1; 10+ is more than 10 (10.1, or the meter's own reading above 10).
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/db/db.dart';
import 'package:bidbus_field/logic/insp.dart';
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

void main() {
  testWidgets('start, steps, the top notch and back', (t) async {
    t.view.physicalSize = const Size(2400, 2622);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    String? got;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(builder: (c) => TextButton(onPressed: () async => got = await showMilsSheet(c, 'Hood', ''), child: const Text('open'))))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('5.0 mils'), findsOneWidget);
    await t.tap(find.byIcon(LucideIcons.plus));
    await t.pumpAndSettle();
    expect(find.text('5.1 mils'), findsOneWidget);
    await t.tap(find.byIcon(LucideIcons.minus));
    await t.tap(find.byIcon(LucideIcons.minus));
    await t.pumpAndSettle();
    expect(find.text('4.9 mils'), findsOneWidget);
    // drag to the right end: 10+, and + is off there
    await t.drag(find.byType(Slider), const Offset(2000, 0));
    await t.pumpAndSettle();
    expect(find.text('10+ mils'), findsOneWidget);
    expect(t.widget<IconButton>(find.ancestor(of: find.byIcon(LucideIcons.plus), matching: find.byType(IconButton))).onPressed, isNull);
    // - from 10+ is 10.0; + from 10.0 is 10+ again
    await t.tap(find.byIcon(LucideIcons.minus));
    await t.pumpAndSettle();
    expect(find.text('10.0 mils'), findsOneWidget);
    await t.tap(find.byIcon(LucideIcons.plus));
    await t.pumpAndSettle();
    expect(find.text('10+ mils'), findsOneWidget);
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(got, '10.1');

    // drag to the left end: 3.0, and - is off there
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.drag(find.byType(Slider), const Offset(-2000, 0));
    await t.pumpAndSettle();
    expect(find.text('3.0 mils'), findsOneWidget);
    expect(t.widget<IconButton>(find.ancestor(of: find.byIcon(LucideIcons.minus), matching: find.byType(IconButton))).onPressed, isNull);
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(got, '3.0');
  });

  testWidgets("a meter reading above 10 shows 10+ and is kept", (t) async {
    t.view.physicalSize = const Size(2400, 2622);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    String? got;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(builder: (c) => TextButton(onPressed: () async => got = await showMilsSheet(c, 'Hood', '12.4'), child: const Text('open'))))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('10+ mils'), findsOneWidget);
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(got, '12.4');
    expect(milsText('12.4'), '10+');
    expect(milsText('10.0'), '10.0');
    expect(milsText('4.8'), '4.8');
  });

  testWidgets('large text on a small phone: the sheet scrolls and every button can be reached', (t) async {
    t.view.physicalSize = const Size(1125, 2001);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    var na = false;
    await t.pumpWidget(MaterialApp(
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2.4)), child: w!),
        home: Scaffold(
            body: Builder(
                builder: (c) => TextButton(
                    onPressed: () => showMilsSheet(c, 'Left front door', '4.8', extraActions: [TextButton(onPressed: () => na = true, child: const Text('Not on this car'))]),
                    child: const Text('open'))))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Not on this car'));
    await t.pumpAndSettle();
    await t.tap(find.text('Not on this car'));
    expect(na, true);
    expect(t.takeException(), isNull);
  });

  // last in the file: its ProviderScope disposes the app's store when the test ends
  testWidgets('Done on a panel not on this car keeps no reading', (t) async {
    t.view.physicalSize = const Size(2400, 2622);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    initQl(jsonDecode(File('assets/question-list.json').readAsStringSync()));
    store.db = _Db();
    store.docs = Directory.systemTemp.path;
    final s = newInspection(id: 'p', fuel: 'Gas or diesel', email: 'a@b.co', inspector: 'T', car: {'year': 2020, 'make': 'X', 'model': 'Y', 'trim': 'Z'})
      ..['phase'] = 'review'
      ..['sp'] = capseq.indexOf('Paint');
    m(s, 'paint')['Roof'] = {'na': true, 'v': ''};
    store.ins['p'] = s;
    await t.pumpWidget(const ProviderScope(child: MaterialApp(home: ReviewScreen('p'))));
    await t.pumpAndSettle();
    await t.tap(find.text('N/A'));
    await t.pumpAndSettle();
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(m(store.ins['p']!, 'paint')['Roof'], {'na': true, 'v': ''});
  });
}
