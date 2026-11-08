// VIN readings from the photos: the windshield leads, and a reading that passes the check digit wins over one that does not.
import 'package:bidbus_field/services/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const good = '5UXTY5C00L9B00230', bad = '5UXTY5C00L9B00231', wind = {'kind': 'vin'}, door = {'kind': 'vin', 'door': true};
  String? vin(Map<String, dynamic> st) => (st['vals'] as Map)['vin_read'];

  test('a door-jamb VIN that passes replaces a windshield VIN that fails', () {
    final st = <String, dynamic>{'vals': <String, dynamic>{}};
    applyReading(st, wind, {'vin': bad});
    applyReading(st, door, {'vin': good});
    expect(vin(st), good);
  });

  test('a reading that fails never replaces one that passes', () {
    final st = <String, dynamic>{'vals': <String, dynamic>{}};
    applyReading(st, wind, {'vin': good});
    applyReading(st, wind, {'vin': bad});
    applyReading(st, door, {'vin': bad});
    expect(vin(st), good);
  });

  test('the windshield leads when both pass, and a typed VIN is kept', () {
    final st = <String, dynamic>{'vals': <String, dynamic>{}};
    applyReading(st, door, {'vin': good});
    applyReading(st, wind, {'vin': '2T3P1RFVXMW145678'});
    expect(vin(st), '2T3P1RFVXMW145678');
    (st['vals'] as Map)['vin_man'] = true;
    applyReading(st, wind, {'vin': good});
    expect(vin(st), '2T3P1RFVXMW145678');
  });
}
