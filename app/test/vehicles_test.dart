// New inspection lists (data/vehicles.json): every make, model years 2013-2027, trims per year, decoded values matched.
import 'dart:convert';
import 'dart:io';

import 'package:bidbus_field/data/vehicles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  initVehicles(jsonDecode(File('../data/vehicles.json').readAsStringSync()));

  test('seven makes, model years 2013 to 2027', () {
    expect(yearsList().first, '2027');
    expect(yearsList().last, '2013');
    expect(vmakes.map((m) => m['make']).toSet(), {'Honda', 'Toyota', 'Lexus', 'Tesla', 'VinFast', 'BMW', 'Mercedes-Benz'});
    for (final mk in vmakes) {
      for (final md in mk['models'] as List) {
        expect((md['trims'] as List), isNotEmpty, reason: '${mk['make']} ${md['model']}');
        for (final t in md['trims'] as List) {
          expect(t['from'] <= t['to'] && t['from'] >= 2013 && t['to'] <= 2027, true, reason: '${mk['make']} ${md['model']} ${t['trim']}');
        }
      }
    }
  });

  test('every year lists the makes sold that year, with models and trims', () {
    for (var y = 2013; y <= 2027; y++) {
      for (final mk in makesFor(y)) {
        final models = modelsFor(mk, y);
        expect(models, isNotEmpty, reason: '$mk $y');
        for (final md in models) {
          expect(trimsFor(mk, md, y), isNotEmpty, reason: '$mk $md $y');
        }
      }
    }
    expect(makesFor(2020), containsAll(['Honda', 'Toyota', 'Lexus', 'Tesla', 'BMW', 'Mercedes-Benz']));
  });

  test('common cars are in their years', () {
    expect(modelsFor('Honda', 2017), containsAll(['Accord', 'Civic', 'CR-V']));
    expect(modelsFor('Toyota', 2020), containsAll(['Camry', 'Corolla', 'RAV4']));
    expect(modelsFor('Tesla', 2022), containsAll(['Model 3', 'Model Y']));
    expect(matchOption(modelsFor('BMW', 2020), 'X3'), 'X3');
  });

  test('decoded values match ignoring case, spaces and punctuation', () {
    expect(matchOption(['3 Series', 'X5'], '3-Series'), '3 Series');
    expect(matchOption(['Tesla', 'BMW'], 'TESLA'), 'Tesla');
    expect(matchOption(['Tesla'], ''), isNull);
    expect(matchOption(['Tesla'], 'Rivian'), isNull);
  });
}
