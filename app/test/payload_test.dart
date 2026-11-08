// M6: a scripted run gives a record with the shape of samples/inspection-*.json that the CR generator accepts (validation ok);
// damage labels tick the right checks; the Summary gate opens only when everything is in.
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/logic/insp.dart';
import 'package:bidbus_field/logic/payload.dart';
import 'package:flutter_test/flutter_test.dart';

J run(String fuel, String vin) {
  final st = newInspection(id: 'test-${fuel.hashCode}', fuel: fuel, email: 'a@b.co', inspector: 'Tom', car: {'year': 2020, 'make': 'X', 'model': 'Y', 'trim': 'Z', 'vin': vin, 'mileage': '61240', 'owner_name': 'Test Seller'});
  st['owner'] = 'Yes';
  for (final d in ['ph_license', 'ph_reg']) {
    m(st, 'files')[d] = 'insp/x/$d.jpg';
    m(st, 'docs')[d] = 'now';
  }
  st['start'] = {'at': '2026-11-07T13:02:00', 'loc': '37.5841, -122.3661'};
  var n = 0;
  for (final k in camseq) {
    for (final x in capList(k, st)) {
      final it = x['it'] as J;
      if (it['optional'] == true && !isMulti(x['id'])) {
        m(st, 'skip')[x['id']] = true;
        continue;
      }
      capMark(st, x, 'camera', 'insp/x/f${n++}.${it['kind'] == 'video' ? 'mp4' : 'jpg'}');
    }
    // a damage and a mod photo in each section where the shutters work
    if (k != 'OBDII') {
      manual(st).add({'id': 'd$k', 'zone': dzone[k], 'sec': k, 'at': 0, 'panel': '', 'type': '', 'sev': '', 'size': '', 'src': 'camera', 'f': 'insp/x/d$k.jpg'});
      final a = (m(st, 'multi')[modslot[k]!] ??= <dynamic>[]) as List;
      a.add({'src': 'camera', 'panel': null, 'sec': k, 'at': 0, 'f': 'insp/x/m$k.jpg'});
      m(st, 'shots')[modslot[k]!] = a.length;
    }
  }
  st['spin'] = [for (var i = 1; i <= 36; i++) 'insp/x/spin-$i.jpg'];
  // readings from the photos
  final vals = m(st, 'vals');
  vals.addAll({'vin_read': vin, 'vin_door': vin, 'vin_scan': 1, 'odo_read': '61325', 'keys_n': '2', 'keys_auto': 1});
  for (final w in wheels) {
    tire(st, w[0])
      ..['tread'] = '7'
      ..['treadAuto'] = true
      ..['read'] = {'brand': 'Michelin', 'size': '245/50R19', 'auto': true};
  }
  for (final p in paintPanels) {
    (m(st, 'paint')[p[1]] as J)
      ..['v'] = p[1] == 'Left rear door' ? '11.8' : '4.6'
      ..['auto'] = true;
  }
  syncPaint(st);
  // label the damages: an Exterior panel with a paint problem, a tire, an interior place, a mechanical place
  final fuelV = fuel;
  void label(String did, String place, String type, String sev) {
    final d = manual(st).firstWhere((x) => x['id'] == did);
    setLabel(d, 'panel', place, fuelV);
    setLabel(d, 'type', type, fuelV);
    setLabel(d, 'sev', sev, fuelV);
    d['aiWas'] = {'place': place, 'type': 'Scratch', 'severity': sev};
  }

  label('dExterior', 'Left front door', 'Overspray or colour mismatch', 'Minor');
  label('dTires', 'Right rear tire', 'Uneven wear', 'Moderate');
  label('dInterior', 'Front seats', 'Seats worn', 'Minor');
  label('dMechanicals', fuel == ev ? 'Suspension' : 'Exhaust', fuel == ev ? 'Struts or shocks leaking or worn' : 'Aftermarket exhaust', 'Minor');
  syncDamages(st);
  vals['tires_match'] = 'Match';
  m(st, 'feat').addAll({'sunroof': 'Works', 'navigation': 'No navigation'});
  if (fuel == ev) vals['ev_soh'] = '93';
  for (final k in capseq) {
    m(st, 'sok')[k] = true;
  }
  return st;
}

void main() {
  initQl(jsonDecode(File('assets/question-list.json').readAsStringSync()));
  final dir = Directory.systemTemp.createTempSync('payload');

  for (final c in [('Gas or diesel', '5UXTY5C00L9B00230', 'bmw-x3'), ('Electric (EV)', '7SAYGDEE5NF000422', 'tesla-model-y')]) {
    test('scripted ${c.$1} run: record shape and CR validation ok', () {
      final st = run(c.$1, c.$2);
      expect(sumBlock(st), 'Confirm the VIN and mileage');
      m(st, 'vals')['idconf'] = true;
      expect(sumBlock(st), 'Pick the overall condition');
      st['overall'] = 'Pretty great';
      expect(sumBlock(st), ''); // the note is optional (question list S3)
      st['note'] = 'Clean car.';
      st['agree'] = true;
      st['signed'] = true;
      st['end'] = {'at': '2026-11-07T13:21:00', 'loc': '37.5841, -122.3661'};
      m(st, 'files')['signature'] = 'insp/x/signature.png';

      final p = inspectionPayload(st), r = p.record;
      final sample = jsonDecode(File('../samples/inspection-${c.$3}.json').readAsStringSync()) as J;
      expect(r.keys.toSet(), sample.keys.toSet());
      for (final part in ['source', 'vehicle', 'documents', 'features', 'signature']) {
        expect((r[part] as J).keys.toSet(), (sample[part] as J).keys.toSet(), reason: part);
      }
      // skipped is in the data contract (docs/03) though neither sample skips a shot
      Set<String> keysOf(String part) => {for (final e in sample[part] as List) ...(e as J).keys, if (part == 'photos') 'skipped'};
      for (final part in ['photos', 'checks', 'tires', 'paint', 'damages', 'videos']) {
        for (final e in r[part] as List) {
          expect(keysOf(part).containsAll((e as J).keys), true, reason: '$part ${e.keys.toSet().difference(keysOf(part))}');
        }
      }
      // checks ticked by the damage labels
      final checks = {for (final e in r['checks'] as List) '${e['id']}${e['wheel'] ?? ''}': e};
      expect(checks['ck_paint']['problems'].map((x) => x['option']), containsAll(['Panel repainted (the meter reads high)', 'Overspray or colour mismatch']));
      expect(checks['ck_tirerr']['problems'][0]['from_damage_photo'], true);
      expect(checks['ck_seats']['problems'][0]['option'], 'Seats worn');
      expect((r['damages'] as List).first['section'], 'Paint');
      // every file named in the record has a local file to upload; 36 spin frames, documents and the signature too
      for (final e in [...r['photos'] as List, ...r['damages'] as List, ...r['videos'] as List]) {
        if (e['file'] != null) expect(p.files.containsKey(e['file']), true, reason: e['file']);
      }
      expect(p.files.keys.where((f) => f.startsWith('spin-')).length, 36);
      expect(p.files.keys, containsAll(['ph_license.jpg', 'ph_reg.jpg', 'signature.png']));

      final f = File('${dir.path}/rec-${c.$3}.json')..writeAsStringSync(jsonEncode(r));
      final out = Process.runSync('python3', ['-I', '../tools/cr_from_inspection.py', f.path, '${dir.path}/cr-${c.$3}.json']);
      expect(out.stdout.toString(), contains('validation ok'), reason: '${out.stdout}${out.stderr}');
    });
  }

  test('relabelling or removing a damage photo takes its answer back', () {
    final st = run('Gas or diesel', '5UXTY5C00L9B00230'), fuel = fuelOf(st);
    final d = manual(st).firstWhere((x) => x['id'] == 'dTires');
    expect(lst(tire(st, 'rr'), 'probs', 'ck_tire'), ['Uneven wear']);
    setLabel(d, 'panel', 'Left front wheel', fuel);
    setLabel(d, 'type', 'Curb rash', fuel);
    syncDamages(st);
    expect(lst(tire(st, 'rr'), 'probs', 'ck_tire'), isEmpty);
    expect(lst(tire(st, 'lf'), 'probs', 'ck_wheel'), ['Curb rash']);
    manual(st).remove(d);
    syncDamages(st);
    expect(lst(tire(st, 'lf'), 'probs', 'ck_wheel'), isEmpty);
  });

  test('a high paint reading ticks Panel repainted with that panel; one key ticks Only one key', () {
    final st = run('Gas or diesel', '5UXTY5C00L9B00230');
    expect(lst(st, 'extra', 'ck_paint'), contains('Left rear door'));
    m(st, 'vals')['keys_n'] = '1';
    keysSync(st);
    expect(lst(st, 'probs', 'ck_keys'), ['Only one key']);
    pickCheck(st, 'ck_keys', null, 'Two or more work');
    expect(m(st, 'vals')['keys_n'], '2');
  });

  test('Show the seller stays off until every section is reviewed', () {
    final st = run('Gas or diesel', '5UXTY5C00L9B00230');
    m(st, 'sok').remove('Paint');
    expect(sumBlock(st), 'Review 1 more section');
    m(st, 'sok')['Paint'] = true;
    manual(st).first['ai'] = true;
    expect(sumBlock(st), 'Label 1 damage photo');
  });

  test('a VIN that fails the check digit cannot be confirmed or signed', () {
    final st = run('Gas or diesel', '5UXTY5C00L9B00231'), v = m(st, 'vals');
    expect(idReady(st), false);
    v['idconf'] = true; // confirmed before this rule
    expect(sumBlock(st), 'Fix the VIN: the check digit is wrong');
    v['vin_read'] = '5UXTY5C00L9B00230';
    v['idconf'] = false;
    expect(idReady(st), true);
    expect(sumBlock(st), 'Confirm the VIN and mileage');
    v['idconf'] = true;
    expect(sumBlock(st), 'Pick the overall condition'); // past the VIN
  });

  test('only an exterior damage sends its size', () {
    final st = run('Gas or diesel', '5UXTY5C00L9B00230');
    for (final d in manual(st)) {
      d['size'] = '3';
    }
    final sent = {for (final d in inspectionPayload(st).record['damages'] as List) d['taken_in']: d['size_in']};
    expect(sent['Exterior'], 3);
    expect(sent.entries.where((e) => e.key != 'Exterior').every((e) => e.value == null), true, reason: '$sent');
  });
}
