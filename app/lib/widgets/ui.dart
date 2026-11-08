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

// full-width rows, white and light grey in turn, no dividers
class RowList extends StatelessWidget {
  final List<Widget> children;
  const RowList(this.children, {super.key});
  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < children.length; i++) ColoredBox(color: i.isEven ? alt : Colors.white, child: children[i]),
      ]);
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
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: need ? BoxDecoration(border: Border.all(color: const Color(0xFFE1255D), width: 2), borderRadius: BorderRadius.circular(10)) : const BoxDecoration(),
          child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 15)),
                if (sub != null && sub!.isNotEmpty) Text(sub!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: subColor ?? muted)),
              ])),
              value,
              if (onTap != null) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(LucideIcons.chevronRight, size: 16, color: Color(0xFFB0B5BA))),
            ]),
          ),
          ),
        ),
      );
}

Widget okVal(String t) => Row(mainAxisSize: MainAxisSize.min, children: [const Icon(LucideIcons.check, size: 15, color: bid), const SizedBox(width: 4), Text(t, style: const TextStyle(color: bid, fontWeight: FontWeight.w600))]);
Widget needVal([String t = 'Pick']) => Text(t, style: const TextStyle(color: Color(0xFFE1255D), fontWeight: FontWeight.w700));
Widget alertVal(Color c, [String t = '']) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(LucideIcons.triangleAlert, size: 15, color: c), if (t.isNotEmpty) ...[const SizedBox(width: 4), Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w600))]]);
Widget setVal(String t) => Text(t, style: const TextStyle(fontWeight: FontWeight.w600));

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

// radio: false for a list of actions (Take photo, Upload), which have no selected state
Future<String?> showChoice(BuildContext context, String title, List<Opt> opts, List<String?> sel, {String? sub, Widget? body, List<Widget> actions = const [], bool radio = true}) =>
    showModalBottomSheet<String>(
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
Future<String?> showTextSheet(BuildContext context, String title, String value, {String? unit, TextInputType kb = TextInputType.text, int? max, bool caps = false, List<Widget> extraActions = const []}) {
  final c = TextEditingController(text: value);
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

Widget stripTab(String label, bool on, VoidCallback tap, {Color? color, Widget? end}) {
  final t = Material(
    color: on ? line : Colors.transparent,
    child: InkWell(
      onTap: tap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(fontSize: 15, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: color ?? (on ? Colors.black : muted))),
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
