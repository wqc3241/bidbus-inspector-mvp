// Scheduler sign-in (docs/12-scheduler-sync.md): the Today list keeps a job cancelled since the last look as
// cancelled, today's and tomorrow's briefs and documents are kept on the phone, a car's documents go once its
// report is sent or its job is cancelled or booked again for another car, a token that ran out and could not be
// renewed does not sign out, and a refused sign-in signs out and deletes everything. Talks to a small local server.
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/logic/insp.dart';
import 'package:bidbus_field/logic/payload.dart';
import 'package:bidbus_field/services/store.dart';
import 'package:bidbus_field/services/team.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

final day0 = DateTime.now();
String d(int n) => DateFormat('yyyy-MM-dd').format(DateTime(day0.year, day0.month, day0.day + n));

J appt(String slot, int inDays, {String booked = '2026-11-10T18:00:00+00:00'}) => {
  'key': '$slot@$booked', 'slot_id': slot, 'booked_at': booked, 'date': d(inDays),
  'start_time': '10:00', 'status': 'booked', 'seller_name': 'Ana Ruiz', 'vehicle': '2021 Toyota RAV4', 'vehicle_id': '4417',
};

void main() {
  late HttpServer srv;
  late Directory tmp;
  var list = <J>[];
  var refuse = false, forbid = false, renew = false;
  final hits = <String>[];

  setUpAll(() async {
    initQl(jsonDecode(File('assets/question-list.json').readAsStringSync()));
    tmp = Directory.systemTemp.createTempSync('team');
    srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen((r) async {
      final p = r.uri.path;
      hits.add(p);
      r.response.headers.contentType = ContentType.json;
      if (p == '/api/health') {
        r.response.write(jsonEncode({'ok': true, 'auth': 'team'}));
      } else if (p == '/api/auth/refresh' && refuse) {
        r.response.statusCode = 401; // the sign-in was ended
        r.response.write(jsonEncode({'detail': 'Signed out. Sign in again.'}));
      } else if (p == '/api/auth/refresh' && renew) {
        r.response.write(jsonEncode({'access_token': 'tok', 'refresh_token': 'r2', 'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}));
      } else if (p == '/api/auth/refresh') {
        r.response.statusCode = 503; // the scheduler is not reached
        r.response.write(jsonEncode({'detail': 'Scheduler not reached'}));
      } else if (forbid) {
        r.response.statusCode = 403; // taken off the team list
        r.response.write(jsonEncode({'detail': 'Sign in to the scheduler site once with this email, then try again here.'}));
      } else if (r.headers.value('authorization') != 'Bearer tok' || refuse) {
        r.response.statusCode = 401;
        r.response.write(jsonEncode({'detail': 'Signed out. Sign in again.'}));
      } else if (p == '/api/appointments') {
        r.response.write(jsonEncode({'today': d(0), 'appointments': list}));
      } else if (p.endsWith('/brief')) {
        final slot = p.split('/')[3];
        r.response.write(jsonEncode({'appointment': list.firstWhere((x) => x['slot_id'] == slot), 'bidbus': 'ok',
          'vehicle': {'documents': [{'type': 'registration', 'document_id': list.firstWhere((x) => x['slot_id'] == slot)['doc'] ?? '7'}]}}));
      } else if (p.contains('/documents/')) {
        r.response.headers.contentType = ContentType('image', 'jpeg');
        r.response.add([1, 2, 3]);
      } else {
        r.response.statusCode = 404;
      }
      await r.response.close();
    });
    store.docs = tmp.path;
    store.server = 'http://127.0.0.1:${srv.port}';
    team.on = true;
    team.member = {'id': 'm1', 'name': 'Ana', 'email': 'ana@bidbus.com'};
    team.session = {'access_token': 'tok', 'refresh_token': 'r', 'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600};
    await team.checkServer(); // the server uses scheduler sign-in
    while (team.loading) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  tearDownAll(() => srv.close(force: true));

  File doc(String slot, [String id = '7']) => File(team.docPath(slot, id));

  test('jobs, briefs and documents on the phone; cancelled kept; documents go after the report', () async {
    list = [appt('s1', 0), appt('s2', 1), appt('s3', 5)];
    await team.refresh(force: true);
    expect(team.error, isNull);
    expect(team.appts.map((x) => x['slot_id']), ['s1', 's2', 's3']);
    expect(team.briefs.keys.toSet(), {'s1', 's2'}); // today and tomorrow only
    expect(doc('s1').readAsBytesSync(), [1, 2, 3]);
    expect(doc('s2').existsSync(), true);
    expect(doc('s3').existsSync(), false);
    expect(File('${tmp.path}/team/appointments.json').existsSync(), true);

    // s2 cancelled on the scheduler: still listed, as cancelled; its brief and documents go; s1's are not fetched again
    list = [appt('s1', 0), appt('s3', 5)];
    hits.clear();
    await team.refresh(force: true);
    expect(team.appts.map((x) => '${x['slot_id']} ${x['status']}'), ['s1 booked', 's2 cancelled', 's3 booked']);
    expect(hits.where((h) => h.contains('/documents/')), isEmpty);
    expect(team.briefs.containsKey('s2'), false);
    expect(doc('s2').existsSync(), false);

    // a refresh within 5 minutes is skipped unless pulled
    hits.clear();
    await team.refresh();
    expect(hits, isEmpty);

    // the inspection from s1 is sent: s1's documents are deleted
    final st = newInspection(id: 'i1', fuel: 'Gas', email: 'a@b.co', inspector: 'Ana', car: {'year': 2021, 'make': 'Toyota', 'model': 'RAV4', 'trim': 'XLE'});
    st['appt'] = {'key': list.first['key'], 'slot_id': 's1', 'booked_at': list.first['booked_at'], 'vehicle_id': '4417'};
    st['status'] = 'sent';
    store.ins['i1'] = st;
    expect(team.inspectionFor(list.first), same(st));
    team.reportSent();
    expect(doc('s1').existsSync(), false);
    // the record names the Bidbus vehicle as the listing
    expect(inspectionPayload(st).record['source']['listing_id'], '4417');

    // the hour s1 is booked again for another car: the new seller's documents come, the report sent for the old one does not stop them
    list = [{...appt('s1', 0, booked: '2026-11-11T02:00:00+00:00'), 'doc': '8'}, appt('s3', 5)];
    await team.refresh(force: true);
    expect(team.briefFor(list.first), isNotNull);
    expect(doc('s1', '8').existsSync(), true);
    expect(team.inspectionFor(list.first), isNull);
  });

  test('a token that ran out and could not be renewed does not sign out', () async {
    final s = team.session!;
    team.session = {...s, 'access_token': 'tok-old', 'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60};
    await team.refresh(force: true);
    expect(team.signedIn, true);
    expect(team.error, isNotNull);
    team.session = s;
  });

  test('a token refused before the phone thinks it ends is renewed once and the list loads', () async {
    final s = team.session!;
    team.session = {...s, 'access_token': 'tok-skew'}; // the phone's clock is behind
    renew = true;
    await team.refresh(force: true);
    renew = false;
    expect(team.signedIn, true);
    expect(team.error, isNull);
    expect(team.session!['access_token'], 'tok');
  });

  test('only the signed-in inspector\'s inspections are shown', () {
    expect(team.mine({'member': 'm1'}), true);
    expect(team.mine({'member': 'm2'}), false);
    expect(team.mine({}), true); // started before scheduler sign-in
  });

  test('days are counted by the calendar', () {
    expect(dayGap('2027-03-15', '2027-03-14'), 1); // the day daylight saving starts
    expect(dayGap('2027-03-14', '2027-03-13'), 1);
    expect(dayGap('2026-11-02', '2026-11-01'), 1);
    expect(dayGap(null, '2026-11-01'), null);
  });

  test('a refused sign-in signs out and deletes the jobs and documents', () async {
    refuse = true;
    await team.refresh(force: true);
    expect(team.signedIn, false);
    expect(team.appts, isEmpty);
    expect(Directory('${tmp.path}/team').existsSync(), false);
  });

  test('an inspector taken off the team list is signed out', () async {
    refuse = false;
    forbid = true;
    team.member = {'id': 'm1', 'name': 'Ana', 'email': 'ana@bidbus.com'};
    team.session = {'access_token': 'tok', 'refresh_token': 'r', 'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600};
    await team.refresh(force: true);
    expect(team.signedIn, false);
  });
}
