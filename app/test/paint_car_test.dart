// The paint diagram (car seen from above): each panel cell is placed once, taps give the panel name, the picked panel is black,
// panels not offered do not react, and the readings cells show the high / missing / not-on-car states.
import 'package:bidbus_field/data/paint_car_data.dart';
import 'package:bidbus_field/widgets/paint_car.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(380, 800);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w))));
}

Color? _fill(WidgetTester t, String text) => (t.widget<Container>(find.ancestor(of: find.text(text), matching: find.byType(Container)).first).decoration as BoxDecoration?)?.color;

void main() {
  testWidgets('Damages picker: tap a panel, the picked one is black, a panel not offered does not react', (t) async {
    final short = {for (final p in paintPickPanels) p.$1: p.$2}, asked = <String>[], have = {...short.keys}..remove('Right rear door');
    String? sel = 'Hood or frunk lid';
    late StateSetter set;
    await _pump(
        t,
        StatefulBuilder(builder: (c, s) {
          set = s;
          return PaintCar(cell: (p) {
            asked.add(p);
            return PaintPickCell(short[p]!, on: sel == p, onTap: have.contains(p) ? () => set(() => sel = p) : null);
          });
        }));
    expect(asked.toSet(), short.keys.toSet());
    expect(asked.length, 11);
    expect(_fill(t, 'Hood'), Colors.black);
    expect(t.widget<Text>(find.text('Hood')).style?.color, Colors.white);
    expect(_fill(t, 'LF fender'), Colors.white);

    await t.tap(find.text('LF fender'));
    await t.pump();
    expect(sel, 'Left front fender');
    expect(_fill(t, 'LF fender'), Colors.black);
    expect(_fill(t, 'Hood'), Colors.white);

    await t.tap(find.text('Trunk'));
    await t.pump();
    expect(sel, 'Trunk or liftgate');

    await t.tap(find.text('RR door'));
    await t.pump();
    expect(sel, 'Trunk or liftgate');
    expect(t.widget<Text>(find.text('RR door')).style?.color, const Color(0xFFB0B5BA));
    expect(find.byType(SvgPicture), findsNothing);
  });

  testWidgets('Review readings: panel names, states, the make logo on the front bumper', (t) async {
    final lbl = {for (final p in paintReadPanels) p.$1: p.$3}, tapped = <String>[];
    String st(String p) => p == 'Hood' ? 'hi' : p == 'Right front fender' ? 'ms' : p == 'Right quarter panel' ? 'na' : '';
    String v(String p) => p == 'Hood' ? '12.0' : p == 'Right front fender' ? '–' : p == 'Right quarter panel' ? 'N/A' : p == 'Left front door' ? '4.5' : '4.8';
    await _pump(t, PaintCar(readings: true, make: 'BMW', cell: (p) => PaintReadingCell(panel: p, value: v(p), label: lbl[p]!, state: st(p), onTap: () => tapped.add(p))));
    expect(find.byType(PaintReadingCell), findsNWidgets(11));
    expect(find.byType(SvgPicture), findsOneWidget);

    await t.tap(find.text('12.0'));
    await t.tap(find.text('4.5'));
    await t.tap(find.text('N/A'));
    expect(tapped, ['Hood', 'Left front door', 'Right quarter panel']);

    expect(_fill(t, '12.0'), const Color(0xFFFDE8EE));
    expect(t.widget<Text>(find.text('12.0')).style?.color, const Color(0xFFBE123C));
    expect(_fill(t, 'N/A'), isNull);
    expect(t.widget<Text>(find.text('–')).style?.color, const Color(0xFF9A4F05));
    expect(_fill(t, '4.5'), Colors.white);
  });

  testWidgets('a make without a logo leaves the gap; the car fits a narrow screen', (t) async {
    await _pump(t, SizedBox(width: 300, child: PaintCar(make: 'Ford', cell: (p) => PaintPickCell(p, on: false))));
    expect(find.byType(SvgPicture), findsNothing);
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byType(PaintCar)), const Size(300, 312));
  });
}
