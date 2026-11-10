// All 4 tires match, read by the AI (docs/11): once the four whole-tire photos are read, the same brand and model on all four is
// Match, a different brand or model Mismatch (size does not count); the row says Read from photo; the inspector's pick wins.
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/logic/insp.dart';
import 'package:bidbus_field/logic/payload.dart';
import 'package:bidbus_field/services/store.dart';
import 'package:bidbus_field/widgets/questions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

J fresh() => newInspection(id: 'tm', fuel: 'Gas or diesel', email: 'a@b.co', inspector: 'T', car: {'year': 2020, 'make': 'X', 'model': 'Y', 'trim': 'Z'});

// the four whole-tire readings, as the server returns them
void read(J st, List<(String?, String?)> tires, {String size = '245/50R19'}) {
  for (var j = 0; j < tires.length; j++) {
    applyReading(st, {'kind': 'tire', 'w': wheels[j][0]}, {'ok': true, 'brand': tires[j].$1, 'model': tires[j].$2, 'size': j == 3 ? '255/45R19' : size});
  }
}

void main() {
  setUpAll(() => initQl(jsonDecode(File('assets/question-list.json').readAsStringSync())));
  String? tm(J st) => m(st, 'vals')['tires_match'];

  test('the same brand and model on all four: Match, read from photo; size does not count', () {
    final st = fresh();
    read(st, [('Michelin', 'Pilot Sport 4S'), ('Michelin', 'Pilot Sport 4S'), ('Michelin', 'Pilot Sport 4S')]);
    expect(tm(st), isNull); // three read: nothing yet
    read(st, [('Michelin', 'Pilot Sport 4S'), ('Michelin', 'Pilot Sport 4S'), ('Michelin', 'Pilot Sport 4S'), ('Michelin', 'pilot sport 4s')]);
    expect((tm(st), m(st, 'vals')['tm_auto']), ('Match', 1)); // the size of the fourth differs; the model's case does not count
    expect(inspectionPayload(st).record['tires_match_read_from_photo'], true);
    expect(m(tire(st, 'lf'), 'read')['model'], 'Pilot Sport 4S');
  });

  test('a different model or brand: Mismatch; an unreadable model of one brand: left to the inspector', () {
    final a = fresh();
    read(a, [('Michelin', 'Pilot Sport 4S'), ('Michelin', 'Pilot Sport 4S'), ('Michelin', 'Primacy 4'), ('Michelin', 'Pilot Sport 4S')]);
    expect(tm(a), 'Mismatch');
    final b = fresh();
    read(b, [('Michelin', null), ('Goodyear', null), ('Michelin', null), ('Michelin', null)]);
    expect(tm(b), 'Mismatch');
    final c = fresh();
    read(c, [('Michelin', 'Pilot Sport 4S'), ('Michelin', null), ('Michelin', 'Pilot Sport 4S'), ('Michelin', 'Pilot Sport 4S')]);
    expect(tm(c), isNull);
    final d = fresh();
    read(d, [('Michelin', 'Pilot Sport 4S'), (null, null), ('Michelin', 'Pilot Sport 4S'), ('Michelin', 'Pilot Sport 4S')]);
    expect(tm(d), isNull);
    expect(inspectionPayload(d).record['tires_match_read_from_photo'], false);
  });

  test("a retaken tire updates the AI's answer; the inspector's pick is never changed", () {
    final st = fresh();
    read(st, [for (var j = 0; j < 4; j++) ('Michelin', 'Pilot Sport 4S')]);
    expect(tm(st), 'Match');
    applyReading(st, {'kind': 'tire', 'w': 'rf'}, {'ok': true, 'brand': 'Michelin', 'model': 'Primacy 4', 'size': null});
    expect(tm(st), 'Mismatch');
    m(st, 'vals')
      ..['tires_match'] = 'Match'
      ..['tm_auto'] = 0; // picked on Review or on the walk-around's questions
    read(st, [for (var j = 0; j < 4; j++) ('Goodyear', 'Eagle F1')]);
    expect((tm(st), m(st, 'vals')['tm_auto']), ('Match', 0));
    expect(inspectionPayload(st).record['tires_match_read_from_photo'], false);
  });

  testWidgets('the row: Read from photo while the answer is the AI\'s', (t) async {
    final st = fresh();
    store.ins['tm'] = st;
    read(st, [for (var j = 0; j < 4; j++) ('Michelin', 'Pilot Sport 4S')]);
    await t.pumpWidget(MaterialApp(home: Material(child: Builder(builder: (c) => tmRow(c, 'tm', st)))));
    expect(find.text('Match'), findsOneWidget);
    expect(find.text('Read from photo'), findsOneWidget);
    m(st, 'vals')['tm_auto'] = 0;
    await t.pumpWidget(MaterialApp(home: Material(child: Builder(builder: (c) => tmRow(c, 'tm', st)))));
    expect(find.text('Read from photo'), findsNothing);
  });

  test('the record sends each shot once, in camera order (the OBDII screens are taken in Interior)', () {
    final st = fresh();
    var n = 0;
    for (final k in camRun) {
      for (final x in capList(k, st)) {
        capMark(st, x, 'camera', 'insp/tm/f${n++}.${(x['it'] as J)['kind'] == 'video' ? 'mp4' : 'jpg'}');
      }
    }
    final photos = (inspectionPayload(st).record['photos'] as List).cast<J>();
    final keys = [for (final p in photos) '${p['question_id']} ${p['wheel'] ?? ''} ${p['panel'] ?? ''} ${p['n'] ?? ''}'];
    expect(keys.toSet().length, keys.length);
    expect(photos.where((p) => p['section'] == 'OBDII').length, capList('OBDII', st).length);
    expect(photos.where((p) => p['section'] == 'Paint').length, 11);
  });
}
