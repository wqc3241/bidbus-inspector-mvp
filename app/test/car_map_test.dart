// The car-shaped Where pickers: a part, its tap rect and its name pill pick the place; the pick is highlighted; missing places are not drawn.
import 'package:bidbus_field/data/car_map_data.dart';
import 'package:bidbus_field/widgets/car_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final all = {for (final q in carParts) q.$1, 'Mirror'};

Future<List<String>> pump(WidgetTester t, Widget Function(ValueChanged<String>) map) async {
  final picks = <String>[];
  await t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 380, child: map(picks.add))))));
  return picks;
}

// tap a point given in the drawing's viewBox units
Future<void> tapVb(WidgetTester t, Type map, Offset vbTopLeft, double x, double y) async {
  final box = t.renderObject<RenderBox>(find.descendant(of: find.byType(map), matching: find.byType(CustomPaint)));
  await t.tapAt(box.localToGlobal(Offset(x, y) - vbTopLeft));
}

Color? pillColor(WidgetTester t, Finder text) => (t.widget<DecoratedBox>(find.ancestor(of: text, matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration).color;

void main() {
  const car = Offset(-10, -14), tires = Offset(-34, -14);

  testWidgets('car: parts, tap rects and name pills pick their place', (t) async {
    final picks = await pump(t, (p) => CarTopMap(sel: null, have: all, onPick: p));
    await tapVb(t, CarTopMap, car, 130, 80); // inside the hood, away from its pill
    await t.tap(find.text('Hood'));
    await t.tap(find.text('Front\nfender').first);
    await t.tap(find.text('Front\nfender').last);
    await tapVb(t, CarTopMap, car, 66, 130); // the left front fender tap rect, outside the car outline
    await t.tap(find.text('Mirror').last);
    await tapVb(t, CarTopMap, car, 70, 190); // the left mirror
    await t.tap(find.text('Head\nlight').first);
    await tapVb(t, CarTopMap, car, 180, 270); // roof
    expect(picks, ['Hood', 'Hood', 'Left front fender', 'Right front fender', 'Left front fender', 'Mirror', 'Mirror', 'Headlight', 'Roof']);
  });

  testWidgets('car: seams and the part outside the car outline pick nothing', (t) async {
    final picks = await pump(t, (p) => CarTopMap(sel: null, have: all, onPick: p));
    await tapVb(t, CarTopMap, car, 180, 166.5); // between hood and windshield
    await tapVb(t, CarTopMap, car, 50, 30); // the bumper path, clipped away by the outline
    expect(picks, isEmpty);
  });

  testWidgets('car: the picked place is highlighted and named under the car', (t) async {
    await pump(t, (p) => CarTopMap(sel: 'Hood', have: all, onPick: p));
    expect(find.text('Hood'), findsNWidgets(2)); // the pill and the name under the car
    expect(pillColor(t, find.text('Hood').first), const Color(0xFF111111));
    expect(t.widget<Text>(find.text('Hood').first).style!.color, Colors.white);
    expect(pillColor(t, find.text('Roof')), Colors.white);
    await pump(t, (p) => CarTopMap(sel: 'Left front fender', have: all, onPick: p));
    expect(pillColor(t, find.text('Front\nfender').first), const Color(0xFF111111));
    expect(pillColor(t, find.text('Front\nfender').last), Colors.white);
    expect(find.text('Left front fender'), findsOneWidget);
  });

  testWidgets('car: places not in the list are not drawn or tappable', (t) async {
    final picks = await pump(t, (p) => CarTopMap(sel: null, have: all.difference({'Hood', 'Mirror'}), onPick: p));
    expect(find.text('Hood'), findsNothing);
    expect(find.text('Mirror'), findsNothing);
    await tapVb(t, CarTopMap, car, 130, 80);
    await tapVb(t, CarTopMap, car, 180, 116);
    await tapVb(t, CarTopMap, car, 70, 190);
    expect(picks, isEmpty);
    await t.tap(find.text('Windshield'));
    expect(picks, ['Windshield']);
  });

  testWidgets('tires: wheel circle and Wheel pill pick the wheel, the ring and Tire pill the tire', (t) async {
    final picks = await pump(t, (p) => TireMap(sel: null, onPick: p));
    expect(find.text('Tire'), findsNWidgets(4));
    await tapVb(t, TireMap, tires, 78, 135); // left front wheel centre
    await tapVb(t, TireMap, tires, 78 + 36, 135); // left front ring
    await tapVb(t, TireMap, tires, 282, 372 - 20); // right rear wheel
    await tapVb(t, TireMap, tires, 282, 372 + 40); // right rear ring
    await t.tap(find.text('Tire').at(1)); // left rear
    await t.tap(find.text('Wheel').at(3)); // right front
    await tapVb(t, TireMap, tires, 180, 270); // the car itself
    expect(picks, ['Left front wheel', 'Left front tire', 'Right rear wheel', 'Right rear tire', 'Left rear tire', 'Right front wheel']);
  });

  testWidgets('tires: the picked place is highlighted and named under the car', (t) async {
    await pump(t, (p) => TireMap(sel: 'Right rear tire', onPick: p));
    expect([for (var i = 0; i < 4; i++) pillColor(t, find.text('Tire').at(i))], [Colors.white, Colors.white, const Color(0xFF111111), Colors.white]);
    expect([for (var i = 0; i < 4; i++) pillColor(t, find.text('Wheel').at(i))], everyElement(Colors.white));
    expect(find.text('Right rear tire'), findsOneWidget);
  });
}
