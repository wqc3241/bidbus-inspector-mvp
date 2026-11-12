// Review, OBDII: the scanner photos show under the title Scanner Result (headings are drawn in capitals); an EV's
// service-mode screens keep Photos.
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/db/db.dart';
import 'package:bidbus_field/logic/insp.dart';
import 'package:bidbus_field/screens/review.dart';
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

void main() {
  setUpAll(() {
    initQl(jsonDecode(File('assets/question-list.json').readAsStringSync()));
    store.db = _Db();
    store.docs = Directory.systemTemp.path;
  });

  testWidgets('OBDII: Scanner Result over the scanner photos', (t) async {
    t.view.physicalSize = const Size(2400, 2622);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    J at(String id, String fuel) => newInspection(id: id, fuel: fuel, email: 'a@b.co', inspector: 'T', car: {'year': 2020, 'make': 'X', 'model': 'Y', 'trim': 'Z'})
      ..['phase'] = 'review'
      ..['sp'] = capseq.indexOf('OBDII');
    store.ins['g'] = at('g', 'Gas or diesel');
    await t.pumpWidget(const ProviderScope(child: MaterialApp(home: ReviewScreen('g', key: ValueKey('g')))));
    await t.pumpAndSettle();
    expect(find.text('SCANNER RESULT'), findsOneWidget);
    expect(find.text('Current codes'), findsOneWidget);
    expect(find.text('PHOTOS'), findsNothing);

    store.ins['e'] = at('e', 'Electric (EV)');
    await t.pumpWidget(const ProviderScope(child: MaterialApp(home: ReviewScreen('e', key: ValueKey('e')))));
    await t.pumpAndSettle();
    expect(find.text('SCANNER RESULT'), findsNothing);
    expect(find.text('PHOTOS'), findsOneWidget);
  });
}
