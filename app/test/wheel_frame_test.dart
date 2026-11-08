// Review, Tires & Wheels: a wheel card whose tread depth is not in yet has the red frame of a row still to answer.
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

  testWidgets('wheel cards without a tread depth are framed red', (t) async {
    t.view.physicalSize = const Size(1206, 2622);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final s = newInspection(id: 'w', fuel: 'Gas or diesel', email: 'a@b.co', inspector: 'T', car: {'year': 2020, 'make': 'X', 'model': 'Y', 'trim': 'Z'});
    s['phase'] = 'review';
    s['sp'] = capseq.indexOf('Tires');
    tire(s, 'lf')['tread'] = '7';
    store.ins['w'] = s;
    await t.pumpWidget(const ProviderScope(child: MaterialApp(home: ReviewScreen('w'))));
    await t.pumpAndSettle();
    bool framed(String wheel) {
      final c = t.widget<Container>(find.ancestor(of: find.text(wheel), matching: find.byType(Container)).first);
      final b = (c.foregroundDecoration as BoxDecoration?)?.border as Border?;
      return b?.top.color == const Color(0xFFE1255D);
    }

    expect([for (final w in ['LF', 'LR', 'RR', 'RF']) framed(w)], [false, true, true, true]);
    store.mut('w', (x) => tire(x, 'rr')['tread'] = '5');
    await t.pumpAndSettle();
    expect(framed('RR'), false);
  });
}
