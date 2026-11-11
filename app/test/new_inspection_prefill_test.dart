// At the car: check ID on a car brief starts the inspection filled in from Bidbus, the VIN decode or the booking and opens
// Check ID, with no New inspection; New inspection opens filled in only when something is not known (the Bidbus trim is
// series + body style), the inspector is the signed-in member (no name field), and the inspection keeps its appointment.
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/data/vehicles.dart';
import 'package:bidbus_field/db/db.dart';
import 'package:bidbus_field/screens/brief.dart' show prefill;
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

  // a car brief's button: the inspection starts (Check ID) or New inspection opens
  Future<void> atCar(WidgetTester t, Map<String, dynamic> p) async {
    final r = GoRouter(initialLocation: '/b', routes: [
      GoRoute(path: '/b', builder: (c, s) => Scaffold(body: TextButton(onPressed: () => atTheCar(c, p), child: const Text('At the car: check ID')))),
      GoRoute(path: '/new', builder: (c, s) => const Text('New inspection')),
      GoRoute(path: '/i/:id', builder: (c, s) => Text('Check ID ${s.pathParameters['id']}')),
    ]);
    await t.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: r)));
    await t.pumpAndSettle();
    await t.tap(find.text('At the car: check ID'));
    await t.pumpAndSettle();
  }

  testWidgets('At the car: check ID starts the inspection filled in, with no New inspection', (t) async {
    final a = {'key': 's9@2026-11-11T18:00:00+00:00', 'slot_id': 's9', 'booked_at': '2026-11-11T18:00:00+00:00', 'vehicle_id': '4417'};
    await atCar(t, {'vin': '2t3p1rfv0mc123456', 'year': 2021, 'make': 'Toyota', 'model': 'RAV4', 'series': 'XLE Premium AWD', 'trim': 'XLE Premium AWD Sport Utility 4D', 'mileage': 41250, 'owner_name': 'Ana Ruiz', 'fuel': 'Gas', 'bidbus': true, 'appt': a});
    final st = store.ins.values.singleWhere((x) => (x['appt'] as Map?)?['key'] == a['key']);
    expect(find.text('Check ID ${st['id']}'), findsOneWidget);
    expect(st['phase'], 'start');
    expect(st['member'], 'm1');
    expect(st['inspector'], 'Ana Ruiz');
    expect(st['report_email'], 'reports@bidbus.com');
    expect(st['fuel'], 'Gas or diesel');
    expect(st['car'], {'year': 2021, 'make': 'Toyota', 'model': 'RAV4', 'trim': 'XLE Premium', 'vin': '2T3P1RFV0MC123456', 'mileage': '41250', 'owner_name': 'Ana Ruiz', 'fuel': 'Gas'});
  });

  testWidgets('no fuel known: New inspection opens filled in', (t) async {
    final n = store.ins.length;
    await atCar(t, {'vin': '2T3P1RFV0MC123456', 'year': 2021, 'make': 'Toyota', 'model': 'RAV4', 'fuel': null, 'bidbus': true, 'appt': {'key': 'k8', 'slot_id': 's8'}});
    expect(find.text('New inspection'), findsOneWidget);
    expect(store.ins.length, n);
  });

  testWidgets('no report email: New inspection opens; the member email is the default', (t) async {
    final p = {'year': 2021, 'make': 'Toyota', 'model': 'RAV4', 'fuel': 'Gas', 'bidbus': true, 'appt': {'key': 'k7', 'slot_id': 's7'}};
    store.defaultEmail = '';
    team.member = {'id': 'm1', 'name': 'Ana Ruiz', 'email': ''};
    await atCar(t, p);
    expect(find.text('New inspection'), findsOneWidget);
    team.member = {'id': 'm1', 'name': 'Ana Ruiz', 'email': 'ana@bidbus.com'};
    await atCar(t, p);
    expect(store.ins.values.singleWhere((x) => (x['appt'] as Map?)?['key'] == 'k7')['report_email'], 'ana@bidbus.com');
    store.defaultEmail = 'reports@bidbus.com';
  });

  test('the car without the form: list names, the list trim, else the series or the decoded trim', () {
    final body = carFromBrief({'year': 2021, 'make': 'Toyota', 'model': 'Camry', 'series': null, 'trim': 'Sedan 4D', 'bidbus': true})!;
    expect(body['trim'], ''); // never a trim from the body style alone
    final ser = carFromBrief({'year': 2021, 'make': 'Rivian', 'model': 'R1S', 'series': 'Adventure', 'trim': 'Adventure Sport Utility 4D', 'bidbus': true})!;
    expect([ser['make'], ser['model'], ser['trim']], ['Rivian', 'R1S', 'Adventure']);
    final dec = carFromBrief({'year': '2021', 'make': 'TOYOTA', 'model': 'RAV4', 'series': null, 'trim': 'XLE', 'bidbus': false})!;
    expect([dec['year'], dec['make'], dec['model'], dec['trim']], [2021, 'Toyota', 'RAV4', 'XLE']);
    expect(carFromBrief({'year': null, 'make': 'Toyota', 'model': 'RAV4'}), isNull);
    expect(carFromBrief({'year': 2021, 'make': 'Toyota', 'model': ''}), isNull);
  });

  test("the brief's car: Bidbus, else the VIN decode, else the booking's text", () {
    final a = {'key': 'k', 'slot_id': 's', 'vehicle': '2003 Honda Accord EX', 'vin': '1HGCM82633A004352', 'mileage': 120000, 'seller_name': 'Bo Li'};
    final dec = prefill(a, {'bidbus': 'not_found', 'vehicle': null, 'fuel': 'Gas', 'decoded': {'year': 2003, 'make': 'HONDA', 'model': 'Accord', 'trim': 'EX-L'}});
    expect([dec['year'], dec['make'], dec['model'], dec['trim'], dec['fuel'], dec['bidbus']], [2003, 'HONDA', 'Accord', 'EX-L', 'Gas', false]);
    final typed = prefill(a, {'bidbus': 'not_found', 'vehicle': null, 'fuel': null, 'decoded': null});
    expect([typed['year'], typed['make'], typed['model'], typed['trim']], ['2003', 'Honda', 'Accord EX', null]);
    final bb = prefill(a, {'bidbus': 'ok', 'vehicle': {'vehicle_id': 9, 'car': {'year': 2003, 'make': 'Honda', 'model': 'Accord', 'series': 'EX', 'trim': 'EX Sedan 4D'}}, 'decoded': {'year': 2003, 'make': 'HONDA', 'model': 'Accord', 'trim': 'EX-L'}});
    expect([bb['make'], bb['series'], bb['trim'], bb['bidbus']], ['Honda', 'EX', 'EX Sedan 4D', true]);
  });
}
