// Car-shaped Where pickers from the mockup (carSvg, tireSvg): the Exterior car seen from above and the Tires map.
// Drawn in the mockup's viewBox units and scaled to fit; a part, its tap rect and its name pill all pick the place.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/car_map_data.dart';

const _pick = Color(0xFFF5B301), _ink = Color(0xFF111111), _grey = Color(0xFF9AA2AC);

// the mockup paths use absolute M L H V Q C Z only
Path _svgPath(String d) {
  final t = RegExp(r'[MLHVQCZ]|-?[\d.]+').allMatches(d).map((m) => m[0]!).toList(), p = Path();
  var i = 0, c = 'M';
  double x = 0, y = 0;
  double n() => double.parse(t[i++]);
  while (i < t.length) {
    if (RegExp('[A-Z]').hasMatch(t[i])) c = t[i++];
    switch (c) {
      case 'M':
        p.moveTo(x = n(), y = n());
        c = 'L';
      case 'L':
        p.lineTo(x = n(), y = n());
      case 'H':
        p.lineTo(x = n(), y);
      case 'V':
        p.lineTo(x, y = n());
      case 'Q':
        p.quadraticBezierTo(n(), n(), x = n(), y = n());
      case 'C':
        p.cubicTo(n(), n(), n(), n(), x = n(), y = n());
      case 'Z':
        p.close();
    }
  }
  return p;
}

final _sil = _svgPath(carSil), _paths = <String, Path>{};
// what a part picks: its place, or for a place on both sides (mirror, headlight, tail light) its own side ('Left headlight')
const _sided = {'Mirror', 'Headlight', 'Tail light'};
String _key(CarPart q) => _sided.contains(q.$1) ? q.$2 : q.$1;
Path _path(String d) => _paths.putIfAbsent(d, () => _svgPath(d));
Rect _rect(List<double> r) => Rect.fromLTWH(r[0], r[1], r[2], r[3]);
Paint _line(Color c, double w) => Paint()..style = PaintingStyle.stroke..color = c..strokeWidth = w;

// carDefs + carShape + carTop: shadow, mirrors, seams, the parts clipped to the silhouette, side shade and outline
void _paintCar(Canvas c, Iterable<CarPart> parts, Iterable<CarPart> mirrors, String? sel) {
  c.drawPath(_sil.shift(const Offset(0, 7)), Paint()..color = const Color(0x29111827)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
  for (final q in mirrors) {
    c.drawPath(_path(q.$3), Paint()..color = sel == _key(q) ? _pick : Colors.white);
    c.drawPath(_path(q.$3), _line(_grey, 1.5));
  }
  c.drawPath(_sil, Paint()..color = const Color(0xFFC5CBD3));
  for (final q in parts) {
    final p = _path(q.$3), f = Paint()..color = sel == _key(q) ? _pick : q.$4 == 'rf' ? const Color(0xFFFCFCFD) : Colors.white;
    if (sel != _key(q) && q.$4 == 'gl') f.shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF55616E), Color(0xFF2A323B)]).createShader(p.getBounds());
    c.save();
    c.clipPath(_sil);
    c.drawPath(p, f);
    c.restore();
    if (q.$8 == null) continue;
    final tail = q.$1 == 'Tail light', d = _path(q.$8!);
    if (q.$4 == 'lz') {
      c.drawPath(d, Paint()..color = tail ? const Color(0xFFD63C3C) : const Color(0xFFD5DDE6));
      c.drawPath(d, _line(tail ? const Color(0xFFA32626) : const Color(0xFF7F8995), 1.2));
    } else {
      c.drawPath(d, _line(const Color(0xFFE6E9ED), 1.5));
    }
  }
  const s = Color(0x334B5563), s0 = Color(0x004B5563);
  c.drawPath(_sil, Paint()..shader = const LinearGradient(colors: [s, s0, s0, s], stops: [0, .17, .83, 1]).createShader(_sil.getBounds()));
  c.drawPath(_sil, _line(_grey, 1.5));
}

class _Painter extends CustomPainter {
  final Rect vb;
  final String? sel;
  final Set<String>? have; // null: the Tires map
  const _Painter(this.vb, this.sel, this.have);
  @override
  void paint(Canvas c, Size size) {
    c.translate(-vb.left, -vb.top);
    final h = have;
    if (h != null) {
      _paintCar(c, carParts.where((q) => h.contains(q.$1)), h.contains('Mirror') ? carMirrors : const [], sel);
      return;
    }
    _paintCar(c, carParts, carMirrors, null);
    c.drawPath(Path.combine(PathOperation.union, _sil, carMirrors.fold(Path(), (p, q) => p..addPath(_path(q.$3), Offset.zero))), Paint()..color = const Color(0x9EFFFFFF)); // the veil: a lighter car
    for (final w in carWheels) {
      final o = Offset(w.$3, w.$4), wheel = sel == '${w.$2} wheel';
      c.drawCircle(o, 46, Paint()..color = sel == '${w.$2} tire' ? _pick : const Color(0xFF2F353C));
      c.drawCircle(o, 46, _line(const Color(0xFF1C2127), 1.5));
      c.drawCircle(o, 24, Paint()..color = wheel ? _pick : const Color(0xFFE5E7EB));
      c.drawCircle(o, 24, _line(wheel ? Colors.black : _grey, 2));
      for (var k = 0; k < 5; k++) {
        final a = k * 72 * math.pi / 180;
        c.drawLine(o, o + Offset(19 * math.sin(a), -19 * math.cos(a)), _line(const Color(0xFF6B7280), 2.5)..strokeCap = StrokeCap.round);
      }
    }
  }

  @override
  bool shouldRepaint(_Painter o) => o.sel != sel || !setEquals(o.have, have);
}

// the .cmap box: the drawing (max 340 wide) with its name pills, the picked place under it
Widget _frame(Rect vb, _Painter painter, List<(String, String, Rect, List<String>)> pills, double fs, String? Function(Offset) hit, ValueChanged<String> onPick, String caption) => Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      decoration: BoxDecoration(color: const Color(0xFFF1F2F4), border: Border.all(color: const Color(0xFFE3E5E8)), borderRadius: BorderRadius.circular(20)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: AspectRatio(
            aspectRatio: vb.width / vb.height,
            child: FittedBox(
              child: SizedBox.fromSize(
                size: vb.size,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    final p = hit(d.localPosition + vb.topLeft);
                    if (p != null) onPick(p);
                  },
                  child: Stack(clipBehavior: Clip.none, children: [
                    CustomPaint(size: vb.size, painter: painter),
                    for (final (place, label, r, lines) in pills)
                      Positioned.fromRect(
                        rect: r.shift(-vb.topLeft),
                        child: Semantics(
                          button: true,
                          selected: painter.sel == place,
                          label: label,
                          excludeSemantics: true,
                          onTap: () => onPick(place),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: painter.sel == place ? _ink : Colors.white,
                                border: Border.all(color: painter.sel == place ? _ink : const Color(0xFFD9DDE3), strokeAlign: BorderSide.strokeAlignCenter),
                                borderRadius: BorderRadius.circular(math.min(12, r.height / 2))),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: Center(
                                  child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(lines.join('\n'),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(fontSize: fs, fontWeight: FontWeight.w700, height: 15 / fs, leadingDistribution: TextLeadingDistribution.even, color: painter.sel == place ? Colors.white : _ink)))),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        ConstrainedBox(constraints: const BoxConstraints(minHeight: 20), child: Text(caption, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink))),
      ]),
    );

/// Exterior Where picker: the car from above, front at the top. Only places in [have] are drawn and tappable. [sel] and the picked
/// value are a place, or for a mirror, headlight or tail light its side's name ('Left mirror'), so only that one is picked.
class CarTopMap extends StatelessWidget {
  final String? sel;
  final Set<String> have;
  final ValueChanged<String> onPick;
  const CarTopMap({super.key, required this.sel, required this.have, required this.onPick});
  static const _vb = Rect.fromLTWH(-10, -14, 380, 488);
  static final places = {for (final q in carParts) q.$1, 'Mirror'};

  bool _on(CarPart q, Offset o, bool clip) => _rect(q.$6).contains(o) || (q.$5 != null && _rect(q.$5!).contains(o)) || (_path(q.$3).contains(o) && (!clip || _sil.contains(o)));
  String? _hit(Offset o) {
    final part = carParts.reversed.where((q) => have.contains(q.$1) && _on(q, o, true)).firstOrNull;
    if (part != null || _sil.contains(o)) return part == null ? null : _key(part); // the seams between parts pick nothing
    final m = have.contains('Mirror') ? carMirrors.where((q) => _on(q, o, false)).firstOrNull : null;
    return m == null ? null : _key(m);
  }

  @override
  Widget build(BuildContext context) => _frame(
        _vb,
        _Painter(_vb, sel, have),
        [for (final q in [if (have.contains('Mirror')) ...carMirrors, ...carParts.where((q) => have.contains(q.$1))]) (_key(q), q.$2, _rect(q.$6), q.$7)],
        13,
        _hit,
        onPick,
        // the picked part's name under the car (a sided place picked without its side shows nothing: pick a side)
        sel != null && (have.contains(sel) && !_sided.contains(sel) || [...carMirrors, ...carParts].any((q) => _key(q) == sel && have.contains(q.$1))) ? sel! : '',
      );
}

/// Tires Where picker: the same car, lighter, with the four wheels; places 'Left front tire', 'Left front wheel', ... for each wheel.
class TireMap extends StatelessWidget {
  final String? sel;
  final ValueChanged<String> onPick;
  const TireMap({super.key, required this.sel, required this.onPick});
  static const _vb = Rect.fromLTWH(-34, -14, 428, 488);
  static final places = {for (final w in carWheels) ...['${w.$2} tire', '${w.$2} wheel']};

  // the Tire pill sits above the wheel centre, the Wheel pill below it, outside the car
  static Rect _pill(double x, double y, bool tire) => Rect.fromLTWH(x > 180 ? 340 : -30, y + (tire ? -26 : 26) - 14, 50, 28);
  static String? _hit(Offset o) {
    for (final w in carWheels) {
      final d = (o - Offset(w.$3, w.$4)).distance;
      if (d <= 25 || _pill(w.$3, w.$4, false).contains(o)) return '${w.$2} wheel';
      if (d <= 46.75 || _pill(w.$3, w.$4, true).contains(o)) return '${w.$2} tire';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => _frame(
        _vb,
        _Painter(_vb, sel, null),
        [for (final w in carWheels) ...[('${w.$2} tire', '${w.$2} tire', _pill(w.$3, w.$4, true), ['Tire']), ('${w.$2} wheel', '${w.$2} wheel', _pill(w.$3, w.$4, false), ['Wheel'])]],
        14,
        _hit,
        onPick,
        places.contains(sel) ? sel! : '',
      );
}
