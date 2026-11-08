// The car line on the phone does not repeat a model that the trim already starts with (Lexus "LC" + "LC 500h").
import 'package:bidbus_field/screens/home.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String line(String model, String trim) => carLine({'car': {'year': 2020, 'make': 'Lexus', 'model': model, 'trim': trim}});
  test('car line', () {
    expect(line('LC', 'LC 500h'), '2020 Lexus LC 500h');
    expect(line('RX', 'Base'), '2020 Lexus RX Base');
    expect(line('LC', 'LCX'), '2020 Lexus LC LCX');
  });
}
