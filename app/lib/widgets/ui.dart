// Shared look from the mockup's final style: white page, thin lines, rows alternating white and #f5f5f5,
// black header with the phase steps, one big bottom button, choice drawers and scroll pickers.
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const bid = Color(0xFF045826), amber = Color(0xFFD97706), amberSoft = Color(0xFFFFF4E0), red = Color(0xFFBE123C), alt = Color(0xFFF5F5F5);
const line = Color(0xFFEBEDEF), muted = Color(0xFF7A8087), modBlue = Color(0xFF2563EB);

ThemeData theme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: bid, primary: bid, surface: Colors.white),
      scaffoldBackgroundColor: Colors.white,
      dividerColor: line,
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
    );

Color levelColor(String lv) => lv.contains('Red') || lv.contains('Ends') || lv.contains('Not listed') ? red : amber;

const phases = ['Photos', 'Damages', 'Review', 'Summary', 'Seller signs'];

class PhaseHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final int phase;
  final VoidCallback? onBack;
  const PhaseHeader(this.title, this.phase, {super.key, this.onBack});
  @override
  Size get preferredSize => const Size.fromHeight(96);
  @override
  Widget build(BuildContext context) => Container(
        color: Colors.black,
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            SizedBox(
              height: 52,
              child: Row(children: [
                IconButton(icon: const Icon(LucideIcons.chevronLeft, color: Colors.white), onPressed: onBack ?? () => Navigator.maybePop(context)),
                Expanded(child: Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
                const SizedBox(width: 48),
              ]),
            ),
            SizedBox(
              height: 40,
              child: Row(children: [
                for (var i = 0; i < phases.length; i++)
                  Expanded(
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(phases[i],
                                  maxLines: 1,
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: i == phase ? Colors.white : i < phase ? const Color(0xFF86EFAC) : const Color(0xFF9CA3AF)))))),
              ]),
            ),
          ]),
        ),
      );
}

class TitleBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget> actions;
  final bool back;
  const TitleBar(this.title, {super.key, this.actions = const [], this.back = true});
  @override
  Size get preferredSize => const Size.fromHeight(52);
  @override
  Widget build(BuildContext context) => AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        centerTitle: true,
        automaticallyImplyLeading: back,
        title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        actions: actions,
      );
}

// rows, values and drawers drawn dark over the camera (the end-of-section questions; the mockup's .cap .ask and .cap ~ .ch-bg)
class DarkRows extends InheritedWidget {
  const DarkRows({super.key, required super.child});
  static bool of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<DarkRows>() != null;
  @override
  bool updateShouldNotify(DarkRows old) => false;
}

const dkCard = Color(0xFF1F2326), dkSub = Color(0x8CFFFFFF), dkBtn = Color(0x1FFFFFFF), dkOk = Color(0xFF4ADE80), dkAmber = Color(0xFFFBBF24), dkRed = Color(0xFFF87171);
Color dk(Color? c) => c == red ? dkRed : c == amber ? dkAmber : c == bid ? dkOk : Colors.white;

// full-width rows, white and light grey in turn, no dividers
class RowList extends StatelessWidget {
  final List<Widget> children;
  const RowList(this.children, {super.key});
  @override
  Widget build(BuildContext context) {
    final d = DarkRows.of(context);
    final col = Column(children: [
      for (var i = 0; i < children.length; i++) ColoredBox(color: d ? (i.isEven ? const Color(0x0FFFFFFF) : const Color(0x1CFFFFFF)) : (i.isEven ? alt : Colors.white), child: children[i]),
    ]);
    return d ? ClipRRect(borderRadius: BorderRadius.circular(12), child: col) : col;
  }
}

class RowBtn extends StatelessWidget {
  final String label;
  final String? sub;
  final Widget value;
  final Color? subColor;
  final VoidCallback? onTap;
  final bool need; // still to answer: a red frame round the whole row
  const RowBtn(this.label, this.value, {super.key, this.sub, this.subColor, this.onTap, this.need = false});
  @override
  Widget build(BuildContext context) {
    final d = DarkRows.of(context);
    return InkWell(
        onTap: onTap,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: need ? BoxDecoration(border: Border.all(color: const Color(0xFFE1255D), width: 2), borderRadius: BorderRadius.circular(10)) : const BoxDecoration(),
          child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: d ? 42 : 52),
          child: Padding(
            padding: d ? const EdgeInsets.fromLTRB(12, 6, 10, 6) : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: d ? const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white) : const TextStyle(fontSize: 15)),
                if (sub != null && sub!.isNotEmpty)
                  d
                      ? Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: subColor == red ? dkRed : subColor != null ? dkAmber : dkSub))
                      : Text(sub!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: subColor ?? muted)),
              ])),
              value,
              if (onTap != null) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(LucideIcons.chevronRight, size: 16, color: d ? const Color(0x59FFFFFF) : const Color(0xFFB0B5BA))),
            ]),
          ),
          ),
        ),
      );
  }
}

Widget okVal(String t) => _Val(t, 'ok', bid);
Widget needVal([String t = 'Pick']) => _Val(t, 'need', null);
Widget alertVal(Color c, [String t = '']) => _Val(t, 'alert', c);
Widget setVal(String t) => _Val(t, 'set', null);
Widget plainVal(String t) => _Val(t, 'plain', null); // a neutral value: Not done, Not read

// a row's value; over the camera a pill (the mockup's .ask .v): OK and answers green, problems amber or red, Pick blue
class _Val extends StatelessWidget {
  final String t, kind;
  final Color? c;
  const _Val(this.t, this.kind, this.c);
  @override
  Widget build(BuildContext context) {
    if (DarkRows.of(context)) {
      final (bg, fg) = switch (kind) {
        'ok' || 'set' => (const Color(0x3322C55E), dkOk),
        'alert' => c == red ? (const Color(0x33EF4444), dkRed) : (const Color(0x33F59E0B), dkAmber),
        'need' => (dkBtn, const Color(0xFF93C5FD)),
        _ => (dkBtn, Colors.white),
      };
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: t.isEmpty && kind == 'alert' ? Icon(LucideIcons.triangleAlert, size: 13, color: fg) : Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
      );
    }
    return switch (kind) {
      'ok' => Row(mainAxisSize: MainAxisSize.min, children: [const Icon(LucideIcons.check, size: 15, color: bid), const SizedBox(width: 4), Text(t, style: const TextStyle(color: bid, fontWeight: FontWeight.w600))]),
      'need' => Text(t, style: const TextStyle(color: Color(0xFFE1255D), fontWeight: FontWeight.w700)),
      'alert' => Row(mainAxisSize: MainAxisSize.min, children: [Icon(LucideIcons.triangleAlert, size: 15, color: c), if (t.isNotEmpty) ...[const SizedBox(width: 4), Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w600))]]),
      'plain' => Text(t, style: const TextStyle(color: muted, fontWeight: FontWeight.w600)),
      _ => Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
    };
  }
}

class Sub3 extends StatelessWidget {
  final String text;
  final IconData icon;
  const Sub3(this.text, this.icon, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [Icon(icon, size: 14, color: muted), const SizedBox(width: 6), Text(text.toUpperCase(), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .7, color: muted))]),
      );
}

class Section extends StatelessWidget {
  final List<Widget> children;
  final String? title;
  final Widget? trailing;
  const Section({super.key, required this.children, this.title, this.trailing});
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: line))),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [Expanded(child: Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))), ?trailing])),
          ...children,
        ]),
      );
}

class BottomBar extends StatelessWidget {
  final Widget child;
  const BottomBar(this.child, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: line))),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: SafeArea(top: false, child: child),
      );
}

class PBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color color;
  final bool trailingIcon;
  const PBtn(this.label, this.onTap, {super.key, this.icon, this.color = bid, this.trailingIcon = false});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: color, disabledBackgroundColor: const Color(0xFFD5D8DB), disabledForegroundColor: const Color(0xFF5F6368), shape: const StadiumBorder()),
          onPressed: onTap,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null && !trailingIcon) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            if (icon != null && trailingIcon) ...[const SizedBox(width: 6), Icon(icon, size: 18)],
          ]),
        ),
      );
}

// a photo or a slot as a tile: thumbnail when the file exists
class ShotTile extends StatelessWidget {
  final String label;
  final String? sub, file, badge, corner;
  final IconData icon;
  final bool missing, dark, dashed, damage;
  final VoidCallback? onTap;
  const ShotTile(this.label, {super.key, this.sub, this.file, this.icon = LucideIcons.camera, this.missing = false, this.dark = false, this.dashed = false, this.damage = false, this.badge, this.corner, this.onTap});
  @override
  Widget build(BuildContext context) {
    final f = file != null ? File(file!) : null, has = f != null && f.existsSync();
    final bg = dark ? Colors.black : damage ? const Color(0xFFF3D9DF) : missing ? const Color(0xFFFFF4E0) : const Color(0xFFDCE6E0);
    // every tile the same size: two lines for the name and one for the sub line, used or not, at any text size
    final lh = MediaQuery.textScalerOf(context).scale(11) * 1.3;
    return SizedBox(
      width: 80,
      height: 56 + 3 * lh + 1,
      child: GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Container(
            height: 52,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: dashed ? Colors.white : bg, borderRadius: BorderRadius.circular(8), border: dashed ? Border.all(color: const Color(0xFFCFD3D8), width: 1.5) : null),
            child: Stack(fit: StackFit.expand, children: [
              if (has) Image.file(f, fit: BoxFit.cover, cacheWidth: 200) else Icon(icon, size: 18, color: dark ? Colors.white : damage ? const Color(0xFF9F1239) : bid),
              if (corner != null) Positioned(left: 5, top: 2, child: Text(corner!, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF9F1239)))),
              if (badge != null)
                Positioned(
                    bottom: 4,
                    left: 0,
                    right: 0,
                    child: Center(
                        child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                            child: Text(badge!, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFB45309)))))),
            ]),
          ),
          const SizedBox(height: 4),
          Flexible(child: FitLabel(label, const TextStyle(fontSize: 11, height: 1.3))),
          if (sub != null) Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, height: 1.3, color: muted)),
        ]),
      ),
    );
  }
}

Widget tiles(List<Widget> t) => Padding(padding: const EdgeInsets.only(bottom: 20), child: Wrap(spacing: 8, runSpacing: 10, children: t));

// ---------- choice drawer ----------
class Opt {
  final String value, label;
  final Color? color;
  final String? tag;
  final bool locked;
  const Opt(this.value, {String? label, this.color, this.tag, this.locked = false}) : label = label ?? value;
}

// radio: false for a list of actions (Take photo, Upload), which have no selected state. dark: over the camera, centred
Future<String?> showChoice(BuildContext context, String title, List<Opt> opts, List<String?> sel, {String? sub, Widget? body, List<Widget> actions = const [], bool radio = true, bool dark = false}) => dark
    ? _darkDialog<String>(context, (c) => [
          for (var i = 0; i < opts.length; i++)
            () {
              final o = opts[i], on = sel.contains(o.value);
              return Material(
                color: on ? const Color(0x2EFFFFFF) : i.isEven ? const Color(0x0FFFFFFF) : const Color(0x1CFFFFFF),
                child: InkWell(
                  onTap: o.locked ? null : () => Navigator.pop(c, o.value),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 46),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(children: [
                        if (o.locked) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(LucideIcons.camera, size: 15, color: dkSub)),
                        Expanded(child: Text(o.label, style: TextStyle(fontSize: 14, color: o.locked ? dkSub : Colors.white, fontWeight: on ? FontWeight.w700 : FontWeight.w600))),
                        if (o.tag != null) Padding(padding: const EdgeInsets.only(right: 8), child: Text(o.tag!, style: const TextStyle(fontSize: 12, color: dkRed, fontWeight: FontWeight.w700))),
                        if (radio) Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: on ? dk(o.color) : const Color(0x59FFFFFF), size: 22),
                      ]),
                    ),
                  ),
                ),
              );
            }(),
        ], title, sub)
    : showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * .85),
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  if (sub != null && sub.isNotEmpty) Text(sub, style: const TextStyle(color: muted)),
                ]),
              ),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final o in opts)
                    Container(
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: line))),
                      child: InkWell(
                        onTap: o.locked ? null : () => Navigator.pop(c, o.value),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          child: Row(children: [
                            if (o.locked) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(LucideIcons.camera, size: 15, color: muted)),
                            Expanded(child: Text(o.label, style: TextStyle(fontSize: 15, color: o.locked ? muted : (o.color ?? Colors.black), fontWeight: FontWeight.w500))),
                            if (o.tag != null) Padding(padding: const EdgeInsets.only(right: 8), child: Text(o.tag!, style: TextStyle(fontSize: 12, color: o.color ?? muted, fontWeight: FontWeight.w700))),
                            if (radio) Icon(sel.contains(o.value) ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: sel.contains(o.value) ? bid : const Color(0xFFB0B5BA), size: 22),
                          ]),
                        ),
                      ),
                    ),
                  ?body,
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...actions, TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel'))]),
              ),
            ]),
          ),
        ),
      ),
    );

// text value in a drawer (VIN, mileage, mils, codes)
Future<String?> showTextSheet(BuildContext context, String title, String value, {String? unit, TextInputType kb = TextInputType.text, int? max, bool caps = false, List<Widget> extraActions = const [], bool dark = false}) {
  final c = TextEditingController(text: value);
  if (dark) {
    return _darkDialog<String>(context, (ctx) => [
          TextField(
              controller: c,
              autofocus: true,
              keyboardType: kb,
              maxLength: max,
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white,
              textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
              decoration: InputDecoration(
                  suffixText: unit, counterText: '', filled: true, fillColor: const Color(0x0FFFFFFF),
                  enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0x33FFFFFF)), borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0x80FFFFFF)), borderRadius: BorderRadius.circular(10)))),
        ], title, null, done: (ctx) => Navigator.pop(ctx, c.text.trim()));
  }
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
              controller: c,
              autofocus: true,
              keyboardType: kb,
              maxLength: max,
              textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
              decoration: InputDecoration(suffixText: unit, counterText: '')),
          const SizedBox(height: 12),
          PBtn('Done', () => Navigator.pop(ctx, c.text.trim())),
          ...extraActions,
        ]),
      ),
    ),
  );
}

// the drawer over the camera: a dark card in the middle (landscape), the same answers as the white drawer on Review
Future<T?> _darkDialog<T>(BuildContext context, List<Widget> Function(BuildContext c) rows, String title, String? sub, {void Function(BuildContext c)? done}) => showDialog<T>(
      context: context,
      barrierColor: const Color(0xA6000000),
      builder: (c) => Dialog(
        backgroundColor: dkCard,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 480, maxHeight: MediaQuery.of(c).size.height * .94),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
              if (sub != null && sub.isNotEmpty) Text(sub, style: const TextStyle(color: dkSub)),
              const SizedBox(height: 12),
              Flexible(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: rows(c)))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: darkBtn('Cancel', () => Navigator.pop(c))),
                if (done != null) ...[const SizedBox(width: 10), Expanded(child: darkBtn('Done', () => done(c), bg: bid))],
              ]),
            ]),
          ),
        ),
      ),
    );

Widget darkBtn(String t, VoidCallback on, {Color bg = dkBtn, IconData? icon}) => SizedBox(
      height: 50,
      child: TextButton(
        onPressed: on,
        style: TextButton.styleFrom(backgroundColor: bg, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 6)], Text(t, maxLines: 1, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))])),
      ),
    );

// a paint reading on a slider from 3.0 to 10+ mils, with - and + for 0.1. "10+" is more than 10: it is kept as 10.1,
// or as the meter's own reading when the photo gave one above 10
const milsMin = 3.0, milsTop = 10.1;
String milsText(dynamic v) => (double.tryParse('$v') ?? 0) > 10 ? '10+' : '$v';

Future<String?> showMilsSheet(BuildContext context, String title, String value, {List<Widget> extraActions = const []}) {
  final was = double.tryParse(value);
  var x = was ?? 5.0;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true, // large text: the sheet grows and scrolls, so every button stays reachable
    backgroundColor: Colors.white,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      void to(double v) => set(() => x = (v * 10).roundToDouble() / 10);
      final over = x > 10, shown = over ? '10+' : x.toStringAsFixed(1);
      Widget step(IconData ic, VoidCallback? tap) => IconButton(
          onPressed: tap, icon: Icon(ic), style: IconButton.styleFrom(fixedSize: const Size(52, 52), side: const BorderSide(color: Color(0xFFD4D7DB)), backgroundColor: Colors.white));
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(children: [
              step(LucideIcons.minus, x > milsMin ? () => to(over ? 10 : x - .1) : null),
              Expanded(child: Text('$shown mils', textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]))),
              step(LucideIcons.plus, over ? null : () => to(x >= 10 ? milsTop : x + .1)),
            ]),
            const SizedBox(height: 16), // room for the value bubble while dragging
            Slider(min: milsMin, max: milsTop, divisions: 71, value: x.clamp(milsMin, milsTop), label: shown, onChanged: to),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('3.0', style: TextStyle(color: muted)), Text('10+', style: TextStyle(color: muted))]),
            ),
            const SizedBox(height: 12),
            PBtn('Done', () => Navigator.pop(ctx, over ? (was != null && was > 10 ? value : milsTop.toStringAsFixed(1)) : x.toStringAsFixed(1))),
            ...extraActions,
          ]),
        ),
      );
    }),
  );
}

// scroll pickers: brand, size, tread, damage size
Future<List<String>?> showPicker(BuildContext context, String title, List<List<String>> cols, List<String> sel, {List<String> seps = const [], String? unit, String? sub, bool clear = false}) {
  final idx = [for (var i = 0; i < cols.length; i++) cols[i].indexOf(sel[i]).clamp(0, cols[i].length - 1)];
  return showModalBottomSheet<List<String>>(
    context: context,
    backgroundColor: Colors.white,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            if (sub != null) Text(sub, style: const TextStyle(color: muted)),
          ]),
        ),
        SizedBox(
          height: 200,
          child: Row(children: [
            for (var i = 0; i < cols.length; i++) ...[
              Expanded(
                  child: CupertinoPicker(
                      itemExtent: 40,
                      scrollController: FixedExtentScrollController(initialItem: idx[i]),
                      onSelectedItemChanged: (v) => idx[i] = v,
                      children: [for (final x in cols[i]) Center(child: Text(x, style: const TextStyle(fontSize: 18)))])),
              if (i < seps.length && seps[i].isNotEmpty) Text(seps[i], style: const TextStyle(fontSize: 18)),
            ],
            if (unit != null) Padding(padding: const EdgeInsets.only(right: 24), child: Text(unit, style: const TextStyle(fontSize: 18))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PBtn('Done', () => Navigator.pop(c, [for (var i = 0; i < cols.length; i++) cols[i][idx[i]]])),
            if (clear) TextButton(onPressed: () => Navigator.pop(c, <String>[]), child: const Text('Clear')),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          ]),
        ),
      ]),
    ),
  );
}

class NoSignal extends StatelessWidget {
  const NoSignal({super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: const Color(0xFF374151),
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: const SafeArea(
            bottom: false,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(LucideIcons.wifiOff, size: 13, color: Colors.white),
              SizedBox(width: 6),
              Text('No signal', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ])),
      );
}

// a centred label that wraps between words only: the font shrinks until its longest word fits the width
class FitLabel extends StatelessWidget {
  final String text;
  final TextStyle style;
  final int lines;
  const FitLabel(this.text, this.style, {super.key, this.lines = 2});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (c, b) {
        final sc = MediaQuery.textScalerOf(c), s = DefaultTextStyle.of(c).style.merge(style);
        var widest = 0.0;
        for (final w in text.split(' ')) {
          final tp = TextPainter(text: TextSpan(text: w, style: s), textDirection: TextDirection.ltr, textScaler: sc)..layout();
          if (tp.width > widest) widest = tp.width;
        }
        final k = b.maxWidth.isFinite && widest > b.maxWidth ? b.maxWidth / widest * .95 : 1.0;
        return Text(text, textAlign: TextAlign.center, maxLines: lines, overflow: TextOverflow.ellipsis, style: s.copyWith(fontSize: s.fontSize! * k, letterSpacing: (s.letterSpacing ?? 0) * k));
      });
}

// the section strip on Damages and Review: one look; the current tab's whole cell is grey
class TabStrip extends StatelessWidget {
  final List<Widget> tabs;
  const TabStrip(this.tabs, {super.key});
  @override
  Widget build(BuildContext context) => SizedBox(height: 48, child: ListView(scrollDirection: Axis.horizontal, children: tabs));
}

// a tab with no tap is shut: it shows light and does nothing
Widget stripTab(String label, bool on, VoidCallback? tap, {Color? color, Widget? end}) {
  final t = Material(
    color: on ? line : Colors.transparent,
    child: InkWell(
      onTap: tap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(fontSize: 15, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: tap == null && !on ? const Color(0xFFC6CACF) : color ?? (on ? Colors.black : muted))),
          if (end != null) Padding(padding: const EdgeInsets.only(left: 4), child: end),
        ]),
      ),
    ),
  );
  return on ? ShowMe(t) : t;
}

// scrolls its child into view when it first shows: the current tab of a strip
class ShowMe extends StatefulWidget {
  final Widget child;
  const ShowMe(this.child, {super.key});
  @override
  State<ShowMe> createState() => _ShowMeState();
}

class _ShowMeState extends State<ShowMe> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? Scrollable.ensureVisible(context, alignment: .5, duration: const Duration(milliseconds: 250)) : null);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// a small photo in a list row (the first when there are several, with their number); tapping it shows them full screen, to look at only
class PhotoThumb extends StatelessWidget {
  final List<String> paths; // absolute
  final String caption;
  const PhotoThumb(this.paths, this.caption, {super.key});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Photo: $caption',
        child: GestureDetector(
          onTap: () => showPhotos(context, paths, caption),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(fit: StackFit.expand, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(paths.first), fit: BoxFit.cover, cacheWidth: 144, errorBuilder: (c, e, s) => const ColoredBox(color: Color(0xFFE9ECEF))),
              ),
              if (paths.length > 1)
                Positioned(
                  right: 3,
                  bottom: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .7), borderRadius: BorderRadius.circular(8)),
                    child: Text('${paths.length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
            ]),
          ),
        ),
      );
}

// photos full screen on black, to look at only: swipe between them, pinch to zoom, X to close; nothing can be changed here
Future<void> showPhotos(BuildContext context, List<String> paths, String caption) =>
    Navigator.of(context).push(PageRouteBuilder(pageBuilder: (c, a, b) => _PhotoViewer(paths, caption), transitionsBuilder: (c, a, b, child) => FadeTransition(opacity: a, child: child)));

class _PhotoViewer extends StatefulWidget {
  final List<String> paths;
  final String caption;
  const _PhotoViewer(this.paths, this.caption);
  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  int at = 0;
  bool zoomed = false; // a zoomed photo pans with a drag; the next photo comes only once it is back to full size
  late final zoom = [for (final _ in widget.paths) TransformationController()];

  @override
  void dispose() {
    for (final z in zoom) {
      z.dispose();
    }
    super.dispose();
  }

  void _zoomed(int i) {
    final z = zoom[i].value.getMaxScaleOnAxis() > 1.01;
    if (z != zoomed) setState(() => zoomed = z);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          PageView.builder(
            itemCount: widget.paths.length,
            physics: zoomed ? const NeverScrollableScrollPhysics() : null,
            onPageChanged: (i) => setState(() {
              at = i;
              for (final z in zoom) {
                z.value = Matrix4.identity();
              }
              zoomed = false;
            }),
            itemBuilder: (c, i) => InteractiveViewer(
              maxScale: 4,
              transformationController: zoom[i],
              onInteractionUpdate: (_) => _zoomed(i),
              onInteractionEnd: (_) => _zoomed(i),
              child: Center(child: Image.file(File(widget.paths[i]), fit: BoxFit.contain)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
              child: Row(children: [
                Expanded(child: Text(widget.caption, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                if (widget.paths.length > 1) Text('${at + 1} / ${widget.paths.length}', style: const TextStyle(color: Colors.white70)),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(LucideIcons.x, color: Colors.white), tooltip: 'Close'),
              ]),
            ),
          ),
        ]),
      );
}
