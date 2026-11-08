// Place labels wrap between words only, whatever the text size: a word that does not fit its pill shrinks.
import 'package:bidbus_field/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const style = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600);
  for (final scale in [1.0, 1.4]) {
    testWidgets('one word stays on one line at text scale $scale', (t) async {
      // just wider than the bare word: the page's letter spacing alone would push the last letter down
      final bare = (TextPainter(text: const TextSpan(text: 'Headlight', style: style), textDirection: TextDirection.ltr, textScaler: TextScaler.linear(scale))..layout()).width;
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Material(child: Center(child: SizedBox(width: bare + 1, child: const FitLabel('Headlight', style)))),
        ),
      ));
      final p = t.renderObject<RenderParagraph>(find.text('Headlight'));
      expect(p.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 9)).map((b) => b.top).toSet().length, 1);
    });
  }
}
