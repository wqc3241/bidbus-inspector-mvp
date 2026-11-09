// Damages: one damage photo per screen, section by section. Place on a picture, then type and severity (size optional, exterior only).
// Places and types come from damage_places in the question list; a labelled photo ticks its check (syncDamages).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../camera/camera_screen.dart';
import '../data/ql.dart';
import '../logic/insp.dart';
import '../data/paint_car_data.dart';
import '../services/store.dart';
import '../widgets/car_map.dart';
import '../widgets/paint_car.dart';
import '../widgets/ui.dart';

J? dmgById(J st, String did) => manual(st).where((d) => d['id'] == did).firstOrNull;

// the place groups of a section: pictures first, then tiles; places the layout does not name go to the last group
const _whereUi = {
  'Exterior': [['', 'car', ['Other lights', 'Wipers', 'Fuel door', 'Other']]],
  'Tires': [['', 'tires', <String>[]]],
  'Paint': [['', 'paint', <String>[]]],
  'Interior': [['Cabin', 'cab', ['Headliner', 'Carpet', 'Sunroof', 'Other']], ['Features', '', ['Screen, audio or cameras', 'Power windows, locks, mirrors or seats', 'Interior lights or defroster', 'Horn', 'Navigation', 'Warning lights', 'Seat belts', 'Airbag covers']]],
  'Mechanicals': [['Engine bay', '', ['Engine bay', 'Fluids', 'Leak', '12 V battery', 'High voltage or front trunk', 'Charge port', 'Other']], ['Underbody', '', underTiles]],
};
const _carPlaces = {'Front bumper', 'Left front fender', 'Hood', 'Right front fender', 'Left front door', 'Roof', 'Right front door', 'Left rear door', 'Right rear door', 'Left quarter panel', 'Trunk or liftgate', 'Right quarter panel', 'Rear bumper', 'Windshield', 'Left front window', 'Left rear window', 'Right front window', 'Right rear window', 'Rear glass', 'Mirror', 'Headlight', 'Tail light'};
const _cabPlaces = {'Steering wheel', 'Dash', 'Front seats', 'Center console', 'Rear seats', 'Door panels', 'Cargo area'};
const _wlbl = {'Screen, audio or cameras': 'Screen & audio', 'Power windows, locks, mirrors or seats': 'Power controls', 'Interior lights or defroster': 'Lights & defrost', 'Airbag covers': 'Airbags', 'High voltage or front trunk': 'High voltage', 'Driveshaft or CV': 'Driveshaft'};
// Lucide has no wiper: the dashboard wiper sign (a windshield and its wiper arm), in the same line style as the icons
const _wiperSvg = '<svg viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M2 20 4.6 6.6Q12 3.4 19.4 6.6L22 20Z"/><path d="M12 20 6.3 9.4"/><circle cx="12" cy="20" r="0.6" fill="#000"/></svg>';
Widget _tileIcon(String p, Color color) => p == 'Wipers'
    ? SvgPicture.string(_wiperSvg, width: 22, height: 22, colorFilter: ColorFilter.mode(color, BlendMode.srcIn))
    : Icon(_wicon[p] ?? LucideIcons.ellipsis, size: 22, color: color);
const _wicon = {
  'Other lights': LucideIcons.lightbulb, 'Fuel door': LucideIcons.fuel, 'Other': LucideIcons.ellipsis, 'Headliner': LucideIcons.panelTop, 'Carpet': LucideIcons.grid3x3, 'Sunroof': LucideIcons.sun,
  'Screen, audio or cameras': LucideIcons.monitor, 'Power windows, locks, mirrors or seats': LucideIcons.power, 'Interior lights or defroster': LucideIcons.lightbulb, 'Horn': LucideIcons.megaphone, 'Navigation': LucideIcons.navigation,
  'Warning lights': LucideIcons.triangleAlert, 'Seat belts': LucideIcons.link, 'Airbag covers': LucideIcons.shield, 'Engine bay': LucideIcons.cog, 'Fluids': LucideIcons.droplets, 'Leak': LucideIcons.droplet, '12 V battery': LucideIcons.batteryFull,
  'High voltage or front trunk': LucideIcons.zap, 'Charge port': LucideIcons.plug, 'Structure': LucideIcons.frame, 'Rust': LucideIcons.biohazard, 'Exhaust': LucideIcons.cloud, 'Suspension': LucideIcons.activity, 'Driveshaft or CV': LucideIcons.cog,
  'Brakes': LucideIcons.disc, 'Battery pack': LucideIcons.batteryCharging,
};

List<(String, String, List<String>)> whereGroups(String z, String fuel) {
  final have = placesFor(z, fuel).map((q) => q['p'] as String).toList(), used = <String>{};
  final gs = (_whereUi[z] ?? [['', '', <String>[]]]).map((g) {
    final map = g[1] as String;
    if (map == 'car') used.addAll(_carPlaces);
    if (map == 'cab') used.addAll(_cabPlaces);
    if (map == 'paint') used.addAll(have);
    if (map == 'tires') used.addAll(have.where((p) => RegExp(r' (tire|wheel)$').hasMatch(p)));
    final t = (g[2] as List<String>).where(have.contains).toList();
    used.addAll(t);
    return (g[0] == 'Engine bay' && fuel == ev ? 'Frunk' : g[0] as String, map, t);
  }).toList();
  final rest = have.where((p) => !used.contains(p)).toList();
  if (rest.isNotEmpty) gs[gs.length - 1] = (gs.last.$1, gs.last.$2, [...gs.last.$3, ...rest]);
  return gs;
}

int groupOf(List<(String, String, List<String>)> gs, String? p) {
  for (var i = 0; i < gs.length; i++) {
    final g = gs[i];
    if (g.$3.contains(p) || (g.$2 == 'car' && _carPlaces.contains(p)) || (g.$2 == 'cab' && _cabPlaces.contains(p)) || (g.$2 == 'tires' && p != null && RegExp(r' (tire|wheel)$').hasMatch(p))) return i;
  }
  return 0;
}

// one option button in the label drawer: white with a grey line, black when picked
Widget _optBtn(Widget child, bool on, VoidCallback tap) => GestureDetector(
      onTap: tap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: on ? Colors.black : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: on ? Colors.black : const Color(0xFFD4D7DB))),
        child: child,
      ),
    );

// the pills of a car seen from above: left side, middle, right side
Widget _pillBtn(String label, bool on, VoidCallback? tap, {double w = 74}) => GestureDetector(
      onTap: tap,
      child: Container(
        width: w,
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(color: on ? Colors.black : Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? Colors.black : const Color(0xFFD5D8DB))),
        child: FitLabel(label, TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: tap == null ? const Color(0xFFB0B5BA) : on ? Colors.white : Colors.black)),
      ),
    );

final _paintShort = {for (final p in paintPickPanels) p.$1: p.$2};

class WhereView extends StatefulWidget {
  final J d;
  final String fuel;
  final ValueChanged<String> onPick;
  final String? shot; // the shot the damage was taken at
  final String? make; // for the brand mark on the paint diagram
  const WhereView(this.d, this.fuel, this.onPick, {super.key, this.shot, this.make});
  @override
  State<WhereView> createState() => _WhereViewState();
}

class _WhereViewState extends State<WhereView> {
  int? tab;
  @override
  Widget build(BuildContext context) {
    final d = widget.d, z = d['zone'] ?? 'Exterior', gs = whereGroups(z, widget.fuel), have = placesFor(z, widget.fuel).map((q) => q['p'] as String).toSet();
    final under = (d['panel'] ?? '') == '' && ((widget.shot ?? '').startsWith('ph_under') || dtab(d) == 'Underbody') ? gs.indexWhere((g) => g.$1 == 'Underbody') : -1;
    final t = (tab ?? (under >= 0 ? under : groupOf(gs, d['panel']))).clamp(0, gs.length - 1), g = gs[t], sel = d['panel'] as String?;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (gs.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SegmentedButton<int>(segments: [for (var j = 0; j < gs.length; j++) ButtonSegment(value: j, label: Text(gs[j].$1))], selected: {t}, showSelectedIcon: false, onSelectionChanged: (v) => setState(() => tab = v.first)),
        ),
      if (g.$2 == 'car') CarTopMap(sel: panelName(d), have: have, onPick: widget.onPick),
      if (g.$2 == 'paint') PaintCar(make: widget.make, cell: (p) => PaintPickCell(_paintShort[p]!, on: sel == p, onTap: have.contains(p) ? () => widget.onPick(p) : null)),
      if (g.$2 == 'tires') TireMap(sel: sel, onPick: widget.onPick),
      if (g.$2 == 'cab')
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF1F3F5), borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [_pillBtn('Steering wheel', sel == 'Steering wheel', () => widget.onPick('Steering wheel'), w: 120), const SizedBox(width: 8), _pillBtn('Dash', sel == 'Dash', () => widget.onPick('Dash'), w: 100)]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _pillBtn('Door panel', sel == 'Door panels', () => widget.onPick('Door panels'), w: 64),
              _pillBtn('Front seat', sel == 'Front seats', () => widget.onPick('Front seats'), w: 70),
              _pillBtn('Console', sel == 'Center console', () => widget.onPick('Center console'), w: 66),
              _pillBtn('Front seat', sel == 'Front seats', () => widget.onPick('Front seats'), w: 70),
              _pillBtn('Door panel', sel == 'Door panels', () => widget.onPick('Door panels'), w: 64),
            ]),
            _pillBtn('Rear seats', sel == 'Rear seats', () => widget.onPick('Rear seats'), w: 200),
            _pillBtn('Cargo area', sel == 'Cargo area', () => widget.onPick('Cargo area'), w: 160),
          ]),
        ),
      // four tiles a row, all the same size whatever the length of their name (the mockup's .wts grid)
      if (g.$3.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: LayoutBuilder(
            builder: (c, b) => Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in g.$3)
                GestureDetector(
                  onTap: () => widget.onPick(p),
                  child: Container(
                    width: (b.maxWidth - 24) / 4,
                    height: 43 + 3 * MediaQuery.textScalerOf(c).scale(11.5) * 1.3, // icon, padding and three lines of name at any text size
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(color: sel == p ? Colors.black : alt, borderRadius: BorderRadius.circular(12)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _tileIcon(p, sel == p ? Colors.white : Colors.black87),
                      const SizedBox(height: 4),
                      Flexible(child: FitLabel(_wlbl[p] ?? p, TextStyle(fontSize: 11.5, height: 1.3, fontWeight: FontWeight.w600, color: sel == p ? Colors.white : Colors.black), lines: 3)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      if (sel != null && sel.isNotEmpty && g.$2 != 'car' && g.$2 != 'tires') Padding(padding: const EdgeInsets.only(top: 8), child: Text(sel, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
    ]);
  }
}

// type, severity and size in a drawer that opens when a place is tapped
Future<void> labelDrawer(BuildContext context, String id, String did) {
  final reasons = ScrollController(); // kept across the drawer's rebuilds, so a pick does not jump the list back to the top
  return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (c) => Consumer(builder: (c, ref, _) {
        final st = ref.watch(storeProvider).ins[id]!, d = dmgById(st, did), fuel = fuelOf(st);
        if (d == null) return const SizedBox();
        final pl = placeOf(d['zone'] ?? 'Exterior', d['panel']);
        if (pl == null) return const SizedBox();
        void set(String f, String v) {
          store.mut(id, (s) {
            setLabel(dmgById(s, did)!, f, v, fuel);
            syncDamages(s);
          });
          if (f == 'sev' && labelled(dmgById(store.ins[id]!, did), fuel)) Navigator.pop(c);
        }

        Widget radio(String f, String o, String label) => InkWell(
              onTap: () => set(f, o),
              child: Container(
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: line))),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
                child: Row(children: [Expanded(child: Text(label, style: const TextStyle(fontSize: 15))), Icon(d[f] == o ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: d[f] == o ? bid : const Color(0xFFB0B5BA))]),
              ),
            );
        Widget sub(String t) => Padding(padding: const EdgeInsets.fromLTRB(0, 14, 0, 6), child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .7, color: muted)));
        // at most half the screen: the place on top, the reasons scroll, severity and Done stay at the bottom
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * .5),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: Text(panelName(d), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              Flexible(
                // the scroll bar stays in view while the reasons are longer than the room: there are more below
                child: Scrollbar(
                  controller: reasons,
                  thumbVisibility: true,
                  child: ListView(controller: reasons, shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                    if (pl['ex'] == true && pl['fix'] != true) ...[sub(pl['exl'] ?? 'Where'), for (final o in strs(pl['exo'])) radio('ex', o, o)],
                    sub('Type'),
                    for (final t in placeOpts(pl, fuel)) radio('type', t, dshort(d['panel'], t)),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              sub('Severity'),
              // severity buttons, and for an exterior damage a Size button that looks the same (the mockup's .lsev / .lsz)
              Row(children: [
                for (final v in dmgSev) ...[
                  if (v != dmgSev.first) const SizedBox(width: 6),
                  Expanded(child: _optBtn(FitLabel(v, TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: d['sev'] == v ? Colors.white : Colors.black), lines: 1), d['sev'] == v, () => set('sev', v))),
                ],
                if ((d['zone'] ?? 'Exterior') == 'Exterior') ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: _optBtn(
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('Size', style: TextStyle(fontSize: 11, color: (d['size'] ?? '') != '' ? Colors.white70 : muted)),
                          FitLabel((d['size'] ?? '') != '' ? '${d['size']} in' : 'Optional', TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: (d['size'] ?? '') != '' ? Colors.white : Colors.black), lines: 1),
                        ]),
                        (d['size'] ?? '') != '', () async {
                      final r = await showPicker(c, 'Size', [List.generate(36, (i) => '${i + 1}')], ['${d['size'] == '' || d['size'] == null ? 2 : d['size']}'], unit: 'in', clear: (d['size'] ?? '') != '');
                      if (r != null) store.mut(id, (s) => dmgById(s, did)!['size'] = r.isEmpty ? '' : r[0]);
                    }),
                  ),
                ],
              ]),
              const SizedBox(height: 16),
              PBtn('Done', labelled(d, fuel)
                  ? () {
                      store.mut(id, (s) => dmgById(s, did)!['ai'] = false);
                      Navigator.pop(c);
                    }
                  : null),
                ]),
              ),
            ]),
          ),
        );
      }),
    ).whenComplete(reasons.dispose);
}

// the photo, the place picture and the label rows of one damage photo
class DamageEditor extends ConsumerWidget {
  final String id, did;
  final Widget? nav;
  final String? title;
  final VoidCallback? onLabelled; // Damages moves on once place, type and severity are picked
  const DamageEditor(this.id, this.did, {super.key, this.nav, this.title, this.onLabelled});

  void _drawer(BuildContext context) => labelDrawer(context, id, did).then((_) {
        final s = store.ins[id], d = s == null ? null : dmgById(s, did);
        if (onLabelled != null && d != null && dmgDone(d, fuelOf(s!))) onLabelled!();
      });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(storeProvider).ins[id]!, d = dmgById(st, did), fuel = fuelOf(st);
    if (d == null) return const SizedBox();
    final pl = placeOf(d['zone'] ?? 'Exterior', d['panel']);
    final f = d['f'] != null ? File(store.abs(d['f'])) : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 200,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: const Color(0xFFF3D9DF), borderRadius: BorderRadius.circular(16)),
        child: Stack(fit: StackFit.expand, children: [
          if (f != null && f.existsSync()) Image.file(f, fit: BoxFit.cover, key: ValueKey(d['f'])) else const Icon(LucideIcons.camera, size: 30, color: Color(0xFF9F1239)),
          Positioned(
              left: 10,
              top: 10,
              child: Row(children: [
                if (title != null) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), child: Text(title!, style: const TextStyle(fontWeight: FontWeight.w700))),
                if (d['ai'] == true && labelled(d, fuel))
                  Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(color: const Color(0xFF7C3AED), borderRadius: BorderRadius.circular(10)),
                      child: const Row(children: [Icon(LucideIcons.sparkles, size: 13, color: Colors.white), SizedBox(width: 4), Text('AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))])),
              ])),
          Positioned(
            right: 10,
            top: 10,
            child: Row(children: [
              _sq(LucideIcons.camera, () => context.push('/i/$id/cam', extra: CamArgs(dmg: dtab(d), redo: did))),
              const SizedBox(width: 8),
              _sq(LucideIcons.trash2, () {
                final file = d['f'] as String?;
                store.mut(id, (s) {
                  final z = dtab(dmgById(s, did)!);
                  manual(s).removeWhere((x) => x['id'] == did);
                  syncDamages(s);
                  // stay on this tab: a photo still to label there, else its first; with none left, the first photo still to label
                  final same = zoneDamages(s, z), todo = same.where((e) => !dmgDone(e.$1, fuelOf(s)));
                  s['li'] = (todo.firstOrNull ?? same.firstOrNull)?.$2 ?? unlabelledOrder(s).firstOrNull ?? 0;
                });
                dropFile(file);
              }, color: red),
            ]),
          ),
          ?nav,
        ]),
      ),
      const SizedBox(height: 20),
      const Sub3('Where', LucideIcons.mapPin),
      WhereView(d, fuel, make: (st['car'] as J?)?['make'], shot: d['sec'] is String && d['at'] is int ? (capList(d['sec'], st).elementAtOrNull(d['at']) ?? {})['id'] : null, (p) {
        store.mut(id, (s) {
          setLabel(dmgById(s, did)!, 'panel', p, fuel);
          syncDamages(s);
        });
        final now = dmgById(store.ins[id]!, did)!; // p may be a side's name ('Left mirror'): the damage holds the place
        if (placeOf(now['zone'] ?? 'Exterior', now['panel']) != null) _drawer(context);
      }),
      if (pl != null) ...[
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: RowList([
            if (pl['ex'] == true && pl['fix'] != true) RowBtn(pl['exl'] ?? 'Where', (d['ex'] ?? '') != '' ? setVal(d['ex']) : needVal(), need: (d['ex'] ?? '') == '', onTap: () => _drawer(context)),
            RowBtn('Type', (d['type'] ?? '') != '' ? setVal(dshort(d['panel'], d['type'])) : needVal(), need: (d['type'] ?? '') == '', onTap: () => _drawer(context)),
            RowBtn('Severity', (d['sev'] ?? '') != '' ? setVal('${d['sev']}${(d['size'] ?? '') != '' && (d['zone'] ?? 'Exterior') == 'Exterior' ? ' · ${d['size']} in' : ''}') : needVal(), need: (d['sev'] ?? '') == '', onTap: () => _drawer(context)),
          ]),
        ),
      ],
    ]);
  }

  Widget _sq(IconData ic, VoidCallback on, {Color color = Colors.black}) => GestureDetector(
        onTap: on,
        child: Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Icon(ic, size: 20, color: color)),
      );
}

class DamagesScreen extends ConsumerStatefulWidget {
  final String id;
  const DamagesScreen(this.id, {super.key});
  @override
  ConsumerState<DamagesScreen> createState() => _DamagesScreenState();
}

class _DamagesScreenState extends ConsumerState<DamagesScreen> {
  PageController? pc;
  bool sliding = false; // moving to a photo picked another way (a tab, the arrows, the next one after labelling)
  bool dragging = false; // the inspector's finger is on the page: it wins over any slide

  void _go(int i) => store.mut(widget.id, (s) => s['li'] = i);

  // every photo is one page: a swipe drags the whole page; a photo picked another way slides in
  void _follow(int pos) {
    final c = pc;
    if (c == null || !c.hasClients || sliding || dragging || (c.page ?? pos).round() == pos) return;
    sliding = true;
    c.animateToPage(pos, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic).whenComplete(() {
      sliding = false;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    pc?.dispose();
    super.dispose();
  }
  void _next(J st) {
    final nx = nextUnlabelled(st, st['li'] ?? 0);
    if (nx >= 0) _go(nx);
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(storeProvider).ins[widget.id]!, fuel = fuelOf(st), o = labelOrder(st);
    if (o.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => store.mut(widget.id, toReview));
      return const Scaffold();
    }
    var li = st['li'] as int? ?? o.first;
    if (!o.contains(li)) li = unlabelledOrder(st).firstOrNull ?? o.first;
    final d = manual(st)[li], z = dtab(d), pos = o.indexOf(li);
    final left = unlabelledOrder(st).length, ok = dmgDone(d, fuel), guess = labelled(d, fuel) && d['ai'] == true;
    // while this tab has photos to label the tabs after it are shut, and the pages stop at its last photo
    final zs = [for (final zz in dz) if (zoneDamages(st, zz).isNotEmpty) zz];
    final open = openTo([for (final zz in zs) zoneDamages(st, zz).every((e) => dmgDone(e.$1, fuel))], zs.indexOf(z));
    final count = [for (var k = 0; k <= open; k++) zoneDamages(st, zs[k]).length].fold(0, (a, b) => a + b);
    pc ??= PageController(initialPage: pos);
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow(pos));
    Widget arrow(IconData ic, int? to) => to == null
        ? const SizedBox()
        : GestureDetector(onTap: () => _go(to), child: Container(width: 44, height: 44, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: Icon(ic, size: 20)));
    return Scaffold(
      appBar: PhaseHeader('Damages', 1, onBack: () => store.mut(widget.id, (s) => s['phase'] = 'capture')),
      body: Column(children: [
        TabStrip([
          for (var k = 0; k < zs.length; k++)
            () {
              final zz = zs[k], l = zoneDamages(st, zz), done = l.where((e) => dmgDone(e.$1, fuel)).length;
              return stripTab('${stTitle(zz)} $done/${l.length}', zz == z, k <= open ? () => _go(l.first.$2) : null, color: done == l.length ? bid : null);
            }(),
        ]),
        const Divider(height: 1),
        Expanded(
          // a finger on the page stops a slide; where the page comes to rest is the photo shown
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.depth != 0) return false; // the page's own vertical list
              if (n is ScrollStartNotification && n.dragDetails != null) dragging = true;
              if (n is ScrollEndNotification && dragging) {
                dragging = sliding = false;
                final oo = labelOrder(store.ins[widget.id]!), p = pc!.page?.round();
                if (p != null && p < oo.length) _go(oo[p]);
              }
              return false;
            },
            child: PageView.builder(
            controller: pc,
            itemCount: count,
            onPageChanged: (p) {
              final oo = labelOrder(store.ins[widget.id]!);
              if ((!sliding || dragging) && p < oo.length) _go(oo[p]);
            },
            itemBuilder: (c, p) {
              final dd = manual(st)[o[p]], zz = dtab(dd), zzl = zoneDamages(st, zz), nn = zzl.indexWhere((e) => e.$2 == o[p]) + 1;
              return ListView(key: ValueKey(dd['id']), padding: const EdgeInsets.all(16), children: [
                DamageEditor(widget.id, dd['id'], title: '${stTitle(zz)} · $nn of ${zzl.length}', onLabelled: () => _next(store.ins[widget.id]!), nav: Positioned(right: 10, top: 78, child: Column(children: [arrow(LucideIcons.chevronRight, p < count - 1 ? o[p + 1] : null)])), key: ValueKey(dd['id'])),
                if (p > 0) Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _go(o[p - 1]), icon: const Icon(LucideIcons.chevronLeft, size: 16), label: const Text('Previous photo'))),
              ]);
            },
          ),
          ),
        ),
      ]),
      bottomNavigationBar: BottomBar(guess
          ? PBtn('Confirm', () {
              store.mut(widget.id, (s) => manual(s)[li]['ai'] = false);
              _next(store.ins[widget.id]!);
            }, icon: LucideIcons.check)
          : left > 0
              ? PBtn(ok ? 'Next photo' : '$left to label', ok ? () => _next(st) : null, icon: ok ? LucideIcons.chevronRight : null, trailingIcon: true)
              : PBtn('Next: Review', () => store.mut(widget.id, toReview), icon: LucideIcons.chevronRight, trailingIcon: true)),
    );
  }
}

// relabel, retake or remove one damage photo from Review
class DamageFormPage extends ConsumerWidget {
  final String id, did;
  const DamageFormPage(this.id, this.did, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(storeProvider).ins[id]!, d = dmgById(st, did);
    if (d == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.maybePop(context));
      return const Scaffold();
    }
    final ok = labelled(d, fuelOf(st));
    return Scaffold(
      appBar: TitleBar(zoneTitle[dtab(d)]!.replaceAll('damages', 'damage')),
      body: ListView(padding: const EdgeInsets.all(16), children: [DamageEditor(id, did)]),
      bottomNavigationBar: BottomBar(Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: ok ? () => addDamage(context, id, dtab(d), replace: true) : null, icon: const Icon(LucideIcons.plus, size: 16), label: const Text('Add another'))),
        const SizedBox(width: 12),
        Expanded(
            child: PBtn('Done', ok
                ? () {
                    store.mut(id, (s) => dmgById(s, did)!['ai'] = false);
                    Navigator.pop(context);
                  }
                : null)),
      ])),
    );
  }
}

// Add a damage: a photo from the camera or the library, then the label form
Future<void> addDamage(BuildContext context, String id, String zone, {String? wheel, bool replace = false}) async {
  final src = await showChoice(context, 'Add a damage', const [Opt('camera', label: 'Take photo'), Opt('library', label: 'Upload')], const [], radio: false);
  if (src == null || !context.mounted) return;
  String? did;
  if (src == 'camera') {
    did = await context.push<String>('/i/$id/cam', extra: CamArgs(dmg: zone, aw: wheel));
  } else {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null) return;
    did = 'd${DateTime.now().microsecondsSinceEpoch}';
    final hint = wheel != null ? '${wheelName(wheel)} tire' : null;
    final rel = await keepPhoto(id, x.path, 'damage', library: true, read: {'kind': 'damage', 'did': did, 'section': zone, 'hint': ?hint});
    final newId = did;
    store.mut(id, (s) {
      // typed open: labels add true/false and the AI guess a map (a literal of only strings would be Map<String, String> and throw)
      final d = <String, dynamic>{'id': newId, 'zone': dzone[zone] ?? zone, if (zone == 'Underbody') 'tab': zone, 'panel': '', 'type': '', 'sev': '', 'size': '', 'src': 'library', 'f': rel};
      if (hint != null) setLabel(d, 'panel', hint, fuelOf(s));
      manual(s).add(d);
      syncDamages(s);
    });
  }
  if (did == null || !context.mounted) return;
  final page = MaterialPageRoute(builder: (_) => DamageFormPage(id, did!));
  replace ? Navigator.of(context).pushReplacement(page) : Navigator.of(context).push(page);
}
