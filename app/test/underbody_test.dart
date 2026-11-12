// Underbody is its own section after Mechanicals: its shots, its damage tab, its Review page.
// Underbody damages stay Mechanicals damages (the zone that holds their places); inspections saved before the split are moved over once.
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/logic/insp.dart';
import 'package:flutter_test/flutter_test.dart';

J dm(String zone, {String panel = '', String? sec, int? at, String? tab}) =>
    {'id': 'd', 'zone': zone, 'panel': panel, 'type': '', 'sev': '', 'size': '', 'src': 'camera', 'sec': ?sec, 'at': ?at, 'tab': ?tab};

void main() {
  initQl(jsonDecode(File('assets/question-list.json').readAsStringSync()));
  J fresh() => newInspection(id: 'u', fuel: 'Gas or diesel', email: 'a@b.co', inspector: 'T', car: {'year': 2020, 'make': 'X', 'model': 'Y', 'trim': 'Z'});

  test('names and order', () {
    expect(stTitle('Tires'), 'Tires & Wheels');
    expect(capseq.last, 'Underbody');
    expect(camseq.last, 'Underbody');
    final st = fresh();
    expect(capList('Underbody', st).map((x) => x['id']), ['ph_under_lf', 'ph_under_lm', 'ph_under_lr', 'ph_under_rear', 'ph_under_rr', 'ph_under_rm', 'ph_under_rf', 'ph_under_front', 'ph_under_cats']);
    expect(capList('Mechanicals', st).any((x) => (x['id'] as String).startsWith('ph_under')), false);
    expect(ckIdsOf('Underbody', st), containsAll(['ck_structure', 'ck_rust']));
    expect(ckIdsOf('Mechanicals', st).contains('ck_structure'), false);
  });

  test('the tab of a damage', () {
    expect(dtab(dm('Mechanicals', panel: 'Brakes')), 'Underbody');
    expect(dtab(dm('Mechanicals', panel: 'Leak')), 'Mechanicals');
    expect(dtab(dm('Mechanicals', sec: 'Underbody', at: 2)), 'Underbody');
    expect(dtab(dm('Mechanicals', tab: 'Underbody')), 'Underbody');
    expect(dtab(dm('Mechanicals', sec: 'Mechanicals', at: 0)), 'Mechanicals');
    expect(dtab(dm('Tires')), 'Tires');
    // placing it decides: an engine bay place moves an Underbody damage to Mechanicals
    expect(dtab(dm('Mechanicals', panel: 'Leak', sec: 'Underbody')), 'Mechanicals');
  });

  test('an inspection saved before the split is moved over once', () {
    final st = fresh()..remove('ub');
    final n = capList0('Mechanicals', st).length; // the shot indexes of then: the pass before 1109
    (st['manual'] as List).addAll([dm('Mechanicals', sec: 'Mechanicals', at: n + 2), dm('Mechanicals', sec: 'Mechanicals', at: 0)]);
    m(st, 'multi')['ph_mod_mech'] = [
      {'src': 'camera', 'panel': null, 'sec': 'Mechanicals', 'at': n, 'f': 'x.jpg'}
    ];
    m(st, 'sok')['Mechanicals'] = true;
    splitUnderbody(st);
    expect([manual(st)[0]['sec'], manual(st)[0]['at']], ['Underbody', 2]);
    expect([manual(st)[1]['sec'], manual(st)[1]['at']], ['Mechanicals', 0]);
    expect((m(st, 'multi')['ph_mod_mech'] as List).first['sec'], 'Underbody');
    expect(m(st, 'sok')['Underbody'], true);
    // a second load changes nothing
    splitUnderbody(st);
    expect(manual(st)[0]['at'], 2);
    // a new inspection is never moved
    final nw = fresh();
    (nw['manual'] as List).add(dm('Mechanicals', sec: 'Mechanicals', at: n + 2));
    splitUnderbody(nw);
    expect(manual(nw)[0]['sec'], 'Mechanicals');
  });
}
