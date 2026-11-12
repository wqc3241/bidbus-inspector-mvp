// Upload after the signature: a signed inspection started from a scheduler appointment is sent to the server
// (record first, then complete); a phone with no passcode or sign-in says it is not sending. Talks to a small local server.
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/db/db.dart';
import 'package:bidbus_field/logic/insp.dart';
import 'package:bidbus_field/screens/inspection.dart';
import 'package:bidbus_field/services/store.dart';
import 'package:bidbus_field/services/team.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'payload_test.dart' as pt;

class _Db extends Db {
  _Db() : super(NativeDatabase.memory());
  @override
  Future<void> put(String id, String json) async {}
}

void main() {
  late HttpServer srv;
  final hits = <String>[];

  setUpAll(() async {
    initQl(jsonDecode(File('assets/question-list.json').readAsStringSync()));
    srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen((r) async {
      hits.add('${r.method} ${r.uri.path}');
      await utf8.decoder.bind(r).join();
      r.response.headers.contentType = ContentType.json;
      if (r.method == 'PUT') {
        r.response.write(jsonEncode({'missing': <String>[]}));
      } else if (r.uri.path.endsWith('/complete')) {
        r.response.write(jsonEncode({'ok': true}));
      } else {
        r.response.write(jsonEncode({'status': 'building'}));
      }
      await r.response.close();
    });
    store.db = _Db();
    store.docs = Directory.systemTemp.createTempSync('up').path;
    store.server = 'http://127.0.0.1:${srv.port}';
    store.online = true;
    team.on = true;
    team.member = {'id': 'm1', 'name': 'Ana', 'email': 'ana@bidbus.com'};
    team.session = {'access_token': 'tok', 'refresh_token': 'r', 'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600};
  });
  tearDownAll(() => srv.close(force: true));

  test('a signed appointment inspection is sent', () async {
    final st = pt.run('Gas or diesel', '5UXTY5C00L9B00230');
    m(st, 'vals')['idconf'] = true;
    st['overall'] = 'Pretty great';
    st['agree'] = true;
    st['signed'] = true;
    st['end'] = {'at': '2026-11-07T13:21:00', 'loc': null};
    m(st, 'files')['signature'] = 'insp/x/signature.png';
    st['member'] = 'm1';
    st['appt'] = <dynamic, dynamic>{'key': 'k1', 'slot_id': 's1', 'booked_at': 'b', 'vehicle_id': '4417'}.cast<String, dynamic>();
    store.add(st);
    store.markSigned(st['id']);
    for (var i = 0; i < 50 && !hits.any((h) => h.endsWith('/complete')); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(hits.where((h) => h.startsWith('PUT')).length, 1, reason: '$hits');
    expect(hits.any((h) => h.endsWith('/complete')), true, reason: '$hits');
  });

  test('no passcode and no sign-in: the Sending screen says nothing is sent', () {
    final was = team.on;
    team.on = false;
    store.passcode = '';
    expect(sendingNote(store), contains('Not sent'));
    store.passcode = 'p';
    expect(sendingNote(store), contains('carries on'));
    team.on = was;
  });
}
