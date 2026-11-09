// M2 and M6: the app lists the same items per fuel as the mockup (verify/allq-report.json),
// and every damage place and type labels and ticks the right check.
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/logic/insp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  initQl(jsonDecode(File('assets/question-list.json').readAsStringSync()));
  final report = jsonDecode(File('../verify/allq-report.json').readAsStringSync());

  for (final run in report['runs']) {
    final fuel = run['fuel'] as String;
    // the report's plug-in run predates docs/01 2.2 (charging items show for EV and plug-in hybrid): docs win
    bool docOverride(J it) => fuel == 'Plug-in hybrid' && it['cars'] == 'plugin';
    J fresh() => newInspection(id: 't', car: {}, fuel: fuel, email: '', inspector: '')..['owner'] = 'Yes';

    test('items for $fuel match the mockup', () {
      final st = fresh(), itemsOn = (run['items'] as Map).cast<String, dynamic>();
      expect(items.length, itemsOn.length);
      var options = 0, damage = 0;
      for (final it in items) {
        final r = itemsOn[it['id']], where = r['where'] as String;
        if (docOverride(it)) {
          expect(fuelOk(it['cars'], fuel), true);
          continue;
        }
        expect(fuelOk(it['cars'], fuel), r['on'], reason: '${it['id']} on/off for $fuel');
        // the mockup's Mechanicals pass holds the underbody shots; the app gives them their own section after it
        if (where.startsWith('Camera ')) expect([where.substring(7), if (where == 'Camera Mechanicals') 'Underbody'].any((k) => capList(k, st).any((x) => x['id'] == it['id'])), true, reason: '${it['id']} in the camera pass');
      }
      for (final k in capseq.skip(1)) {
        for (final id in ckIdsOf(k, st)) {
          final it = byId[id]!;
          if (docOverride(it)) continue;
          final base = ckBase(it), n = optsFor(it, fuel).where((o) => !base.contains(o)).length;
          options += k == 'Tires' ? n * 4 : n;
        }
      }
      for (final z in dz) {
        for (final pl in placesFor(z, fuel)) {
          if (docOverride(byId[pl['ck']] ?? {})) continue;
          // the report predates the Exterior panels offering their Paint problems (mockup 11-07 06:34): count those apart
          final tw = pl['tw'] as J?, twin = tw == null ? 0 : placeOpts0(tw, fuel).length;
          damage += placeOpts(pl, fuel).length - twin;
        }
      }
      // the report also counts the plug-in-only option "Charging cable or adapters missing" for Hybrid; docs/01 2.2 limits charging items to EV and plug-in hybrid
      if (fuel != 'Plug-in hybrid') expect(options, run['options'] - (fuel == 'Hybrid' ? 1 : 0), reason: 'check options for $fuel');
      if (fuel != 'Plug-in hybrid') expect(damage, run['damage'], reason: 'damage place and type pairs for $fuel');
      expect(capList('Exterior', st).where((x) => x['id'] == 'paint').length, 11);
    });

    test('every damage place and type for $fuel labels and ticks its check', () {
      final st = fresh();
      for (final z in dz) {
        for (final pl in placesFor(z, fuel)) {
          for (final t in placeOpts(pl, fuel)) {
            final d = <String, dynamic>{'zone': z, 'panel': '', 'type': '', 'sev': '', 'size': '', 'src': 'camera'};
            manual(st).add(d);
            final sided = z == 'Exterior' && sidedPlaces.contains(pl['p']);
            setLabel(d, 'panel', pl['p'], fuel);
            setLabel(d, 'type', t, fuel);
            if (pl['ex'] == true && d['ex'] == null) d['ex'] = strs(pl['exo'])[0];
            setLabel(d, 'sev', 'Moderate', fuel);
            final tag = '$z/${pl['p']}/$t';
            if (sided) {
              // a mirror, headlight or tail light is labelled only with its side, picked on the car map as 'Left ...'
              expect(labelled(d, fuel), false, reason: '$tag labelled without a side');
              setLabel(d, 'panel', 'Left ${(pl['p'] as String).toLowerCase()}', fuel);
              expect((d['panel'], d['side'], d['type']), (pl['p'], 'Left', t), reason: '$tag keeps its type with the side');
            }
            syncDamages(st);
            expect(labelled(d, fuel), true, reason: '$tag labelled');
            if (dmgOwn(st, d)) {
              expect((totals(st)['dlist'] as List).any((x) => x.contains(dmgLine(d))), true, reason: '$tag listed');
            } else {
              final der = dmgDerived(st).first;
              if (der['t'] == 'p') expect(problemsList(st).any((x) => (x['text'] as String).contains(plain(der['v']))), true, reason: '$tag ticks ${der['id']}');
              if (der['t'] == 'f') expect(m(st, 'feat')[der['id']], 'Not working', reason: '$tag sets ${der['id']}');
            }
            manual(st).removeLast();
            syncDamages(st);
            expect(dmgDerived(st), isEmpty, reason: '$tag left an answer behind');
            expect(problemsList(st), isEmpty, reason: '$tag left a problem behind');
          }
        }
      }
    });
  }

  test('Gas and Diesel are picked apart and both use the Gas or diesel items', () {
    expect(fuelChoices, ['Gas', 'Diesel', 'Hybrid', 'Plug-in hybrid', 'Electric (EV)']);
    expect([for (final f in fuelChoices) fuelGroup(f)], ['Gas or diesel', 'Gas or diesel', 'Hybrid', 'Plug-in hybrid', 'Electric (EV)']);
    expect(fuelChoices.map(fuelGroup).every(fuels.contains), true);
  });

  test('times are local with their UTC offset', () {
    final t = nowIso(), back = DateTime.parse(t).toLocal(), now = DateTime.now();
    expect(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d$').hasMatch(t), true, reason: t);
    expect(now.difference(back).inSeconds.abs() < 5, true);
    expect(t.substring(11, 16), '${'${now.hour}'.padLeft(2, '0')}:${'${now.minute}'.padLeft(2, '0')}');
  });
}
