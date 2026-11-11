// Check ID with a scheduler appointment: the license and registration the seller uploaded (car brief) need no photo; the
// inspector checks the person against them and they go in the record as seller uploads; one missing or not yet on the
// phone is photographed here.
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/db/db.dart';
import 'package:bidbus_field/logic/insp.dart';
import 'package:bidbus_field/logic/payload.dart';
import 'package:bidbus_field/screens/check_id.dart';
import 'package:bidbus_field/services/store.dart';
import 'package:bidbus_field/services/team.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Db extends Db {
  _Db() : super(NativeDatabase.memory());
  @override
  Future<void> put(String id, String json) async {}
}

void main() {
  setUpAll(() {
    initQl(jsonDecode(File('assets/question-list.json').readAsStringSync()));
    store.db = _Db();
    store.docs = Directory.systemTemp.createTempSync('idc').path;
    store.online = false;
    team.on = true;
    team.member = {'id': 'm1', 'name': 'Ana', 'email': 'ana@bidbus.com'};
  });

  testWidgets("the seller's uploads: no photos, checked against them, recorded as seller uploads", (t) async {
    J brief(List<J> docs) => {'appointment': {'key': 'k1', 'slot_id': 's1'}, 'vehicle': {'documents': docs, 'owner': {'registered': 'Ana Ruiz'}}};
    team.briefs['s1'] = brief([{'type': 'registration', 'document_id': 'd2'}]);
    File(team.docPath('s1', 'd2'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    store.ins['c'] = newInspection(id: 'c', fuel: 'Gas or diesel', email: 'a@b.co', inspector: 'T', car: {'year': 2020, 'make': 'X', 'model': 'Y', 'trim': 'Z'})
      ..['appt'] = {'key': 'k1', 'slot_id': 's1'};
    final r = GoRouter(initialLocation: '/c', routes: [
      GoRoute(path: '/c', builder: (c, s) => const CheckIdScreen('c')),
      GoRoute(path: '/i/:id/cam', builder: (c, s) => const Text('camera')),
    ]);
    await t.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: r)));
    await t.pumpAndSettle();
    expect(find.text('Take photo'), findsOneWidget); // the license is not uploaded: photographed here
    expect(find.text('Registered owner: Ana Ruiz'), findsOneWidget);
    expect(find.text('Add the license and registration'), findsOneWidget);

    // the seller uploads the license too: while its file is not on the phone it still has Take photo
    team.briefs['s1'] = brief([{'type': 'driver_license', 'document_id': 'd1'}, {'type': 'registration', 'document_id': 'd2'}]);
    store.mut('c', (s) {});
    await t.pumpAndSettle();
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Add the license and registration'), findsOneWidget);
    expect(idBlock(store.ins['c']!), 'Add the license and registration');

    // saved on the phone: no photo
    File(team.docPath('s1', 'd1')).writeAsBytesSync([1, 2, 3]);
    store.mut('c', (s) {});
    await t.pumpAndSettle();
    expect(find.text('Take photo'), findsNothing);
    expect(find.text('Answer the owner question'), findsOneWidget);
    await t.tap(find.text('Yes'));
    await t.pumpAndSettle();
    await t.tap(find.text('Start inspection'));
    await t.pumpAndSettle();
    expect(find.text('camera'), findsOneWidget);

    final st = store.ins['c']!;
    expect(st['sdocs'], ['ph_license', 'ph_reg']);
    final p = inspectionPayload(st);
    expect(p.record['documents'], {'license': 'seller upload', 'registration': 'seller upload', 'family_proof': null});
    expect(p.files.keys.where((f) => f.startsWith('ph_')), isEmpty); // nothing private to upload: Bidbus has them
  });

  test('an inspection with no appointment still needs both photos', () {
    final st = newInspection(id: 'n', fuel: 'Gas or diesel', email: 'a@b.co', inspector: 'T', car: {'year': 2020, 'make': 'X', 'model': 'Y', 'trim': 'Z'});
    expect(sellerDocs(st), isEmpty);
    expect(idBlock(st), 'Add the license and registration');
    m(st, 'docs')['ph_license'] = 'x';
    m(st, 'docs')['ph_reg'] = 'x';
    expect(idBlock(st), 'Answer the owner question');
  });
}
