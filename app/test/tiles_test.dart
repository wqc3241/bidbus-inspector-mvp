// Photo tiles are the same size whatever the length of their name and whether they have a sub line.
import 'package:bidbus_field/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 1.4]) {
    testWidgets('photo tiles share one size at text scale $scale', (t) async {
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Material(child: Wrap(children: const [ShotTile('Roof'), ShotTile('Left front fender', sub: 'Dent'), ShotTile('Right quarter panel', damage: true, badge: 'Minor')])),
        ),
      ));
      final sizes = t.widgetList(find.byType(ShotTile)).map((w) => t.getSize(find.byWidget(w))).toSet();
      expect(sizes.length, 1);
      expect(t.takeException(), isNull); // no overflow
      // and no text cut short: every line of every name fits in the tile
      for (final e in find.descendant(of: find.byType(ShotTile), matching: find.byType(RichText)).evaluate()) {
        final r = e.renderObject as RenderParagraph;
        expect(r.getMinIntrinsicHeight(r.size.width) <= r.size.height + .5, true, reason: r.text.toPlainText());
      }
    });
  }

  testWidgets('a row still to answer has a red frame round it; an answered one has none', (t) async {
    await t.pumpWidget(MaterialApp(home: Material(child: Column(children: [RowBtn('Type', needVal(), need: true, onTap: () {}), RowBtn('Severity', setVal('Minor'), onTap: () {})]))));
    BoxBorder? frame(String label) => ((t.widget<DecoratedBox>(find.ancestor(of: find.text(label), matching: find.byType(DecoratedBox)).first).decoration) as BoxDecoration).border;
    expect((frame('Type') as Border).top.color, const Color(0xFFE1255D));
    expect(frame('Severity'), isNull);
  });
}
