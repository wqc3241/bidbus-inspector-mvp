// The paint diagram as a car seen from above, front at the top (mockup .lpaint: Damages "Where" for Paint; .pcar: Review paint readings).
// A grid like the mockup's CSS: front bumper, then wheel | left panels | centre | right panels | wheel, then rear bumper.
// Bumpers, glass and wheels are drawing only; each panel is a cell from the caller (PaintPickCell or PaintReadingCell).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/paint_car_data.dart';
import 'ui.dart';

// grid areas: (first row, last row, first column, last column)
const _areas = {
  'fb': (0, 0, 0, 4), 'wlf': (1, 2, 0, 0), 'lff': (1, 2, 1, 1), 'hd': (1, 1, 2, 2), 'ws': (2, 2, 2, 2), 'rff': (1, 2, 3, 3), 'wrf': (1, 2, 4, 4),
  'lfd': (3, 3, 1, 1), 'rf': (3, 4, 2, 2), 'rfd': (3, 3, 3, 3), 'lrd': (4, 4, 1, 1), 'rrd': (4, 4, 3, 3),
  'wlr': (5, 6, 0, 0), 'lq': (5, 6, 1, 1), 'rg': (5, 5, 2, 2), 'rq': (5, 6, 3, 3), 'wrr': (5, 6, 4, 4), 'tr': (6, 6, 2, 2), 'rb': (7, 7, 0, 4),
};
const _pickRows = <double>[32, 46, 14, 46, 46, 14, 46, 22], _readRows = <double>[32, 62, 18, 66, 66, 18, 62, 24];
const _edge = Color(0xFFDFE2E6), _ink = Color(0xFF111111), _grey = Color(0xFF687076);

// CSS shrinks corner radii that do not fit the box; do the same for the bumpers
BorderRadius _fit(Size s, double t, double b) {
  final k = math.min(1.0, math.min(s.height / (t + b), s.width / (2 * math.max(t, b))));
  return BorderRadius.vertical(top: Radius.circular(t * k), bottom: Radius.circular(b * k));
}

Widget _lamp(double deg, bool tail) => Transform.rotate(
    angle: deg * math.pi / 180,
    child: Container(width: 30, height: 9, decoration: BoxDecoration(color: tail ? const Color(0xFFD63C3C) : const Color(0xFFD5DDE6), borderRadius: BorderRadius.circular(4.5), border: Border.all(color: tail ? const Color(0xFFA32626) : const Color(0xFF7F8995), width: 1.5))));

/// [cell] is called once per panel and fills its grid area. Panel names: readings false (Damages) the place names of [paintPickPanels]
/// ('Hood or frunk lid', 'Trunk or liftgate', ...); readings true (Review) the panel names of [paintReadPanels] ('Hood', ...).
/// [make] puts its brand mark on the front bumper (BMW, Tesla, Toyota, Honda); other makes leave the gap.
class PaintCar extends StatelessWidget {
  final Widget Function(String panel) cell;
  final bool readings;
  final String? make;
  const PaintCar({super.key, required this.cell, this.readings = false, this.make});

  @override
  Widget build(BuildContext context) {
    final (side, mid, rows, gap, px, wheel, rTop, rBot) = readings ? (34.0, 1.2, _readRows, 5.0, 8.0, 44.0, 46.0, 28.0) : (30.0, 1.15, _pickRows, 4.0, 4.0, 40.0, 30.0, 20.0);
    const py = 8.0;
    final h = rows.reduce((a, b) => a + b) + gap * 7 + py * 2 + 2;
    final mk = make?.toLowerCase(), logo = makeLogos.entries.where((e) => e.key.toLowerCase() == mk).firstOrNull;
    return LayoutBuilder(builder: (c, b) {
      final w = b.maxWidth.isFinite ? b.maxWidth : 356.0, fr = math.max(0.0, (w - 2 - px * 2 - side * 2 - gap * 4) / (2 + mid)), cols = [side, fr, fr * mid, fr, side];
      double at(List<double> l, int i) => [for (var k = 0; k < i; k++) l[k] + gap].fold(0.0, (a, x) => a + x);
      Rect area(String a) {
        final (r0, r1, c0, c1) = _areas[a]!;
        return Rect.fromLTRB(at(cols, c0), at(rows, r0), at(cols, c1) + cols[c1], at(rows, r1) + rows[r1]);
      }

      Widget put(String a, Widget child, {double mx = 0}) {
        final r = area(a);
        return Positioned(left: r.left + mx, top: r.top, width: math.max(0, r.width - mx * 2), height: r.height, child: child);
      }

      Widget end(String a, bool front) {
        final r = area(a);
        return put(
            a,
            mx: 26,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _edge), borderRadius: front ? _fit(Size(r.width - 52, r.height), 40, 6) : _fit(Size(r.width - 52, r.height), 6, 22)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _lamp(front ? -8 : 6, !front),
                if (front)
                  logo == null
                      ? const SizedBox(width: 36, height: 26)
                      : SvgPicture.string('<svg viewBox="0 0 24 24"><path fill="${logo.value.$1}" d="${logo.value.$2}"/></svg>', width: 36, height: 26, semanticsLabel: logo.key),
                _lamp(front ? 8 : -6, !front),
              ]),
            ));
      }

      final wh = Center(child: Container(width: 13, height: wheel, decoration: BoxDecoration(color: const Color(0xFF2B2F33), borderRadius: BorderRadius.circular(5))));
      return Container(
        width: w,
        height: h,
        padding: EdgeInsets.symmetric(horizontal: px, vertical: py),
        decoration: BoxDecoration(color: const Color(0xFFF1F2F4), border: Border.all(color: const Color(0xFFE3E5E8)), borderRadius: BorderRadius.vertical(top: Radius.circular(rTop), bottom: Radius.circular(rBot))),
        child: Stack(children: [
          for (final a in ['wlf', 'wrf', 'wlr', 'wrr']) put(a, wh),
          end('fb', true),
          put('ws', mx: 4, const CustomPaint(painter: _Glass(true))),
          put('rg', mx: 4, const CustomPaint(painter: _Glass(false))),
          end('rb', false),
          if (readings) for (final p in paintReadPanels) put(p.$2, cell(p.$1)) else for (final p in paintPickPanels) put(p.$3, cell(p.$1)),
        ]),
      );
    });
  }
}

// windshield (wide at the top) or rear glass (wide at the bottom): a dark trapezoid with rounded outer corners
class _Glass extends CustomPainter {
  final bool front;
  const _Glass(this.front);
  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s, a = s.width * .14, b = s.width * .86;
    canvas.clipRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)));
    final path = front ? (Path()..addPolygon([Offset.zero, Offset(s.width, 0), Offset(b, s.height), Offset(a, s.height)], true)) : (Path()..addPolygon([Offset(a, 0), Offset(b, 0), Offset(s.width, s.height), Offset(0, s.height)], true));
    canvas.drawPath(path, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF55616E), Color(0xFF2A323B)]).createShader(r));
  }

  @override
  bool shouldRepaint(_Glass o) => o.front != front;
}

/// Damages paint picker cell (mockup .lp): white, black when [on]; grey text and no tap when [onTap] is null.
class PaintPickCell extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback? onTap;
  const PaintPickCell(this.label, {super.key, required this.on, this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: on,
        enabled: onTap != null,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(color: on ? Colors.black : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: on ? Colors.black : const Color(0xFFD4D7DB))),
            child: FitLabel(label, TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.2, color: onTap == null ? const Color(0xFFB0B5BA) : on ? Colors.white : _ink)),
          ),
        ),
      );
}

/// Review paint reading cell (mockup .pcl): big [value] over a small [label]. [state]: '' plain, 'hi' high reading (pink),
/// 'na' not on this car (dashed grey, no fill), 'ms' missing reading (dashed amber). [panel] rounds the Hood and Trunk like the car's ends.
class PaintReadingCell extends StatelessWidget {
  final String panel, value, label, state;
  final VoidCallback? onTap;
  const PaintReadingCell({super.key, required this.panel, required this.value, required this.label, this.state = '', this.onTap});
  @override
  Widget build(BuildContext context) {
    final hi = state == 'hi', na = state == 'na', dashed = na || state == 'ms';
    final br = panel.startsWith('Hood')
        ? const BorderRadius.vertical(top: Radius.circular(22), bottom: Radius.circular(10))
        : panel.startsWith('Trunk')
            ? const BorderRadius.vertical(top: Radius.circular(10), bottom: Radius.circular(18))
            : BorderRadius.circular(10);
    final edge = hi ? const Color(0xFFF19BB2) : na ? const Color(0xFFC4C9CE) : dashed ? const Color(0xFFE0A14A) : _edge;
    final body = Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: na ? null : hi ? const Color(0xFFFDE8EE) : Colors.white, borderRadius: br, border: dashed ? null : Border.all(color: edge)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        FitLabel(value, TextStyle(fontSize: na ? 13 : 17, fontWeight: FontWeight.w700, height: 1.15, color: hi ? red : na ? const Color(0xFF8A9096) : dashed ? const Color(0xFF9A4F05) : _ink, fontFeatures: const [FontFeature.tabularFigures()]), lines: 1),
        const SizedBox(height: 1),
        FitLabel(label, TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, height: 1.2, color: hi ? red : _grey), lines: 1),
      ]),
    );
    return Semantics(button: true, label: '$panel: $value', excludeSemantics: true, child: GestureDetector(onTap: onTap, child: dashed ? CustomPaint(foregroundPainter: _Dash(edge, br), child: body) : body));
  }
}

// 1 px dashed border (no package for it)
class _Dash extends CustomPainter {
  final Color color;
  final BorderRadius br;
  const _Dash(this.color, this.br);
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke;
    for (final m in (Path()..addRRect(br.toRRect(Offset.zero & s).deflate(.5))).computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 5) {
        canvas.drawPath(m.extractPath(d, math.min(d + 3.5, m.length)), p);
      }
    }
  }

  @override
  bool shouldRepaint(_Dash o) => o.color != color || o.br != br;
}
