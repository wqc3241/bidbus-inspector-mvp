// Start inspection from a car brief: New inspection comes filled in from the booking and Bidbus (the Bidbus trim is
// series + body style), the inspector is the signed-in member (no name field), and the inspection keeps its appointment.
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/data/vehicles.dart';
import 'package:bidbus_field/db/db.dart';
import 'package:bidbus_field/screens/new_inspection.dart';
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

Future<void> open(WidgetTester t, Map<String, dynamic> prefill) async {
  final r = GoRouter(initialLocation: '/new', routes: [
    GoRoute(path: '/new', builder: (c, s) => NewInspectionScreen(prefill: prefill)),
    GoRoute(path: '/i/:id', builder: (c, s) => Text('started ${s.pathParameters['id']}')),
  ]);
  await t.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: r)));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() {
    initVehicles(jsonDecode(File('assets/vehicles.json').readAsStringSync()));
    store.db = _Db();
    store.docs = Directory.systemTemp.createTempSync('nip').path;
    store.defaultEmail = 'reports@bidbus.com';
    store.online = false; // no VIN decode
    team.on = true;
    team.member = {'id': 'm1', 'name': 'Ana Ruiz', 'email': 'ana@bidbus.com'};
    team.session = {'access_token': 'tok', 'expires_at': 9999999999};
  });

  testWidgets('filled in from the brief; the inspection keeps its appointment', (t) async {
    final a = {'key': 's1@2026-11-10T18:00:00+00:00', 'slot_id': 's1', 'booked_at': '2026-11-10T18:00:00+00:00', 'vehicle_id': '4417'};
    await open(t, {'vin': '2t3p1rfv0mc123456', 'year': 2021, 'make': 'Toyota', 'model': 'RAV4', 'series': 'XLE Premium AWD', 'trim': 'XLE Premium AWD Sport Utility 4D', 'mileage': 41250, 'owner_name': 'Ana Ruiz', 'fuel': 'Gas', 'appt': a});
    expect(find.text('2T3P1RFV0MC123456'), findsOneWidget);
    expect(find.text('XLE Premium'), findsOneWidget); // the longest list trim the Bidbus series starts with
    expect(find.text('Inspector name'), findsNothing);
    await t.tap(find.text('At the car: check ID'));
    await t.pumpAndSettle();
    final st = store.ins.values.single;
    expect(st['appt'], a);
    expect(st['member'], 'm1');
    expect(st['inspector'], 'Ana Ruiz');
    expect((st['car'] as Map)['trim'], 'XLE Premium');
    expect((st['car'] as Map)['mileage'], '41250');
  });

  testWidgets('a Bidbus trim that is only a body style picks no trim', (t) async {
    await open(t, {'year': 2021, 'make': 'Toyota', 'model': 'Camry', 'series': null, 'trim': 'Sedan 4D', 'fuel': 'Gas', 'appt': {'key': 'k3', 'slot_id': 's3'}});
    expect(find.text('SE'), findsNothing);
    expect(find.text('Toyota'), findsOneWidget);
    await open(t, {'year': 2023, 'make': 'Honda', 'model': 'Pilot', 'series': null, 'trim': 'Sport Utility 4D', 'fuel': 'Gas', 'appt': {'key': 'k4', 'slot_id': 's4'}});
    expect(find.text('Sport'), findsNothing);
  });

  testWidgets('a Bidbus series that is a list trim is picked as is', (t) async {
    await open(t, {'year': 2021, 'make': 'BMW', 'model': 'X3', 'series': 'xDrive30i', 'trim': 'xDrive30i Sport Utility 4D', 'fuel': 'Gas', 'appt': {'key': 'k', 'slot_id': 's2'}});
    expect(find.text('xDrive30i'), findsOneWidget);
    expect(find.text('Other'), findsNothing);
  });
}
