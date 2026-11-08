// Summary: the four numbers sit on one line whatever the labels do; the last label is Damages; section headings are black.
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/db/db.dart';
import 'package:bidbus_field/logic/insp.dart';
import 'package:bidbus_field/screens/summary.dart';
import 'package:bidbus_field/services/store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'payload_test.dart' as pt;

class _Db extends Db {
  _Db() : super(NativeDatabase.memory());
  @override
  Future<void> put(String id, String json) async {}
}

void main() {
  setUpAll(() {
    initQl(jsonDecode(File('assets/question-list.json').readAsStringSync()));
    store.db = _Db();
    store.docs = Directory.systemTemp.path;
  });

  testWidgets('counts line up; headings are black', (t) async {
    // a narrow phone
    t.view.physicalSize = const Size(1125, 2436);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final s = pt.run('Gas or diesel', '5UXTY5C00L9B00230')
      ..['id'] = 's'
      ..['phase'] = 'final';
    store.ins['s'] = s;
    await t.pumpWidget(const ProviderScope(child: MaterialApp(home: SummaryScreen('s'))));
    await t.pumpAndSettle();
    final tot = totals(s), pl = problemsList(s), dl = tot['dlist'] as List;
    final nums = ['${tot['photos']}/${tot['need']}', '${tot['videos']}/${tot['vneed']}', '${pl.length + dl.length}', '${manual(s).length}'];
    final tops = nums.map((n) => t.getTopLeft(find.descendant(of: find.byType(ListView), matching: find.text(n)).first).dy).toSet();
    Finder body(String x) => find.descendant(of: find.byType(ListView), matching: find.text(x)).first; // not the tab bar's Photos
    expect(find.text('Damage photos'), findsNothing);
    expect(body('Damages'), findsOneWidget); // one word, like Photos, Videos and Problems
    expect(tops.length, 1, reason: 'numbers at different heights: $tops');
    final head = t.widget<Text>(find.text(stTitle(findingsBySec(s).first.$1).toUpperCase()));
    expect(head.style?.color, Colors.black);
  });
}
