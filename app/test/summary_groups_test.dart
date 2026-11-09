// Summary: what was found is listed section by section, in Review order, each problem once,
// with the section name dropped from its place line under the heading.
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/data/ql.dart';
import 'package:bidbus_field/logic/insp.dart';
import 'package:flutter_test/flutter_test.dart';

import 'payload_test.dart' as pt;

void main() {
  initQl(jsonDecode(File('assets/question-list.json').readAsStringSync()));

  for (final fuel in ['Gas or diesel', 'Electric (EV)']) {
    test('findings by section for $fuel', () {
      final st = pt.run(fuel, fuel == 'Gas or diesel' ? '5UXTY5C00L9B00230' : '7SAYGDEE5NF000422');
      final g = findingsBySec(st), pl = problemsList(st), dl = totals(st)['dlist'] as List;
      // every problem and every damage line shows once, under its own section
      expect(g.fold<int>(0, (n, e) => n + e.$2.length), pl.length);
      expect(g.fold<int>(0, (n, e) => n + e.$3.length), dl.length);
      for (final e in g) {
        expect(e.$2.every((p) => p['sec'] == e.$1), true);
      }
      // in Review order, no section twice, no empty section
      final ks = g.map((e) => e.$1).toList();
      expect(ks, [for (final k in capseq) if (ks.contains(k)) k]);
      expect(g.every((e) => e.$2.isNotEmpty || e.$3.isNotEmpty), true);
      expect(ks.length > 2, true, reason: 'the scripted run finds problems in several sections: $ks');
    });
  }

  test('the place line under a section heading', () {
    expect(whereIn('Exterior', 'Exterior · Hood'), 'Hood');
    expect(whereIn('Interior', 'Interior'), '');
    expect(whereIn('Tires', 'Tires & Wheels'), '');
    expect(whereIn('Tires', 'Left front'), 'Left front');
    expect(whereIn('Paint', 'Paint · Hood, Roof'), 'Hood, Roof');
  });
}
