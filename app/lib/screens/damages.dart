// Damages: one damage photo per screen, section by section. Place on a picture, then type and severity (size optional).
// Places and types come from damage_places in the question list; a labelled photo ticks its check (syncDamages).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../camera/camera_screen.dart';
import '../data/ql.dart';
import '../logic/insp.dart';
import '../services/store.dart';
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
const _wicon = {
  'Other lights': LucideIcons.lightbulb, 'Wipers': LucideIcons.wind, 'Fuel door': LucideIcons.fuel, 'Other': LucideIcons.ellipsis, 'Headliner': LucideIcons.panelTop, 'Carpet': LucideIcons.grid3x3, 'Sunroof': LucideIcons.sun,
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

// the pills of a car seen from above: left side, middle, right side
Widget _pillBtn(String label, bool on, VoidCallback? tap, {double w = 74}) => GestureDetector(
      onTap: tap,
      child: Container(
        width: w,
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(color: on ? Colors.black : Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? Colors.black : const Color(0xFFD5D8DB))),
        child: Text(label, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: tap == null ? const Color(0xFFB0B5BA) : on ? Colors.white : Colors.black)),
      ),
    );

class CarMap extends StatelessWidget {
  final String? sel;
  final Set<String> have;
  final ValueChanged<String> onPick;
  const CarMap(this.sel, this.have, this.onPick, {super.key});
  Widget _p(String place, String label, {double w = 78}) => _pillBtn(label, sel == place, have.contains(place) ? () => onPick(place) : null, w: w);
  Widget _side(String s) => Column(children: [
        _p('Headlight', 'Headlight'), _p('$s front fender', 'Front fender'), _p('Mirror', 'Mirror'), _p('$s front window', 'Front window'), _p('$s front door', 'Front door'),
        _p('$s rear door', 'Rear door'), _p('$s rear window', 'Rear window'), _p('$s quarter panel', 'Quarter'), _p('Tail light', 'Tail light'),
      ]);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF1F3F5), borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _side('Left'),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), border: Border.all(color: const Color(0xFFC5CBD3), width: 2)),
              child: Column(children: [
                _p('Front bumper', 'Front bumper', w: 110), const SizedBox(height: 14), _p('Hood', 'Hood', w: 90), const SizedBox(height: 14), _p('Windshield', 'Windshield', w: 100),
                const SizedBox(height: 18), _p('Roof', 'Roof', w: 80), const SizedBox(height: 18), _p('Rear glass', 'Rear glass', w: 100), const SizedBox(height: 14), _p('Trunk or liftgate', 'Trunk', w: 90),
                const SizedBox(height: 14), _p('Rear bumper', 'Rear bumper', w: 110),
              ]),
            ),
          ),
          _side('Right'),
        ]),
      );
}

// 11 body panels seen from above (Damages Paint, Review Paint)
const paintGrid = [
  ['Left front fender', 'Hood', 'Right front fender'], ['Left front door', 'Roof', 'Right front door'], ['Left rear door', '', 'Right rear door'], ['Left quarter panel', 'Trunk or liftgate', 'Right quarter panel'],
];
const paintShort = {'Left front fender': 'LF fender', 'Hood': 'Hood', 'Hood or frunk lid': 'Hood', 'Right front fender': 'RF fender', 'Left front door': 'LF door', 'Roof': 'Roof', 'Right front door': 'RF door', 'Left rear door': 'LR door', 'Right rear door': 'RR door', 'Left quarter panel': 'L quarter', 'Trunk or liftgate': 'Trunk', 'Right quarter panel': 'R quarter'};

class PanelGrid extends StatelessWidget {
  final Widget Function(String panel) cell;
  const PanelGrid(this.cell, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF1F3F5), borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          const Text('Front', style: TextStyle(fontSize: 11, color: muted)),
          for (final r in paintGrid) Row(children: [for (final p in r) Expanded(child: Padding(padding: const EdgeInsets.all(3), child: p.isEmpty ? const SizedBox() : cell(p)))]),
          const Text('Rear', style: TextStyle(fontSize: 11, color: muted)),
        ]),
      );
}

class WhereView extends StatefulWidget {
  final J d;
  final String fuel;
  final ValueChanged<String> onPick;
  const WhereView(this.d, this.fuel, this.onPick, {super.key});
  @override
  State<WhereView> createState() => _WhereViewState();
}

class _WhereViewState extends State<WhereView> {
  int? tab;
  @override
  Widget build(BuildContext context) {
    final d = widget.d, z = d['zone'] ?? 'Exterior', gs = whereGroups(z, widget.fuel), have = placesFor(z, widget.fuel).map((q) => q['p'] as String).toSet();
    final t = (tab ?? groupOf(gs, d['panel'])).clamp(0, gs.length - 1), g = gs[t], sel = d['panel'] as String?;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (gs.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SegmentedButton<int>(segments: [for (var j = 0; j < gs.length; j++) ButtonSegment(value: j, label: Text(gs[j].$1))], selected: {t}, showSelectedIcon: false, onSelectionChanged: (v) => setState(() => tab = v.first)),
        ),
      if (g.$2 == 'car') CarMap(sel, have, widget.onPick),
      if (g.$2 == 'paint') PanelGrid((p) => _pillBtn(paintShort[p]!, sel == pn(p), have.contains(pn(p)) ? () => widget.onPick(pn(p)) : null)),
      if (g.$2 == 'tires')
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF1F3F5), borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            for (final r in [['lf', 'rf'], ['lr', 'rr']])
              Row(children: [
                for (final w in r)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(children: [
                        Text(wheelName(w), style: const TextStyle(fontWeight: FontWeight.w700)),
                        for (final part in ['tire', 'wheel']) _pillBtn(part == 'tire' ? 'Tire' : 'Wheel', sel == '${wheelName(w)} $part', () => widget.onPick('${wheelName(w)} $part'), w: 110),
                      ]),
                    ),
                  ),
              ]),
          ]),
        ),
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
      if (g.$3.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in g.$3)
              GestureDetector(
                onTap: () => widget.onPick(p),
                child: Container(
                  width: 84,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  decoration: BoxDecoration(color: sel == p ? Colors.black : alt, borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    Icon(_wicon[p] ?? LucideIcons.ellipsis, size: 22, color: sel == p ? Colors.white : Colors.black87),
                    const SizedBox(height: 4),
                    Text(_wlbl[p] ?? p, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: sel == p ? Colors.white : Colors.black)),
                  ]),
                ),
              ),
          ]),
        ),
      if (sel != null && sel.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(sel, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
    ]);
  }
}

// type, severity and size in a drawer that opens when a place is tapped
Future<void> labelDrawer(BuildContext context, String id, String did) => showModalBottomSheet(
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
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * .85),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
              Text(d['panel'], style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              if (pl['ex'] == true && pl['fix'] != true) ...[sub(pl['exl'] ?? 'Where'), for (final o in strs(pl['exo'])) radio('ex', o, o)],
              sub('Type'),
              for (final t in placeOpts(pl, fuel)) radio('type', t, dshort(d['panel'], t)),
              sub('Severity'),
              Row(children: [
                for (final v in dmgSev) ...[
                  Expanded(child: _pillBtn(v, d['sev'] == v, () => set('sev', v))),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final r = await showPicker(c, 'Size', [List.generate(36, (i) => '${i + 1}')], ['${d['size'] == '' || d['size'] == null ? 2 : d['size']}'], unit: 'in', clear: (d['size'] ?? '') != '');
                      if (r != null) store.mut(id, (s) => dmgById(s, did)!['size'] = r.isEmpty ? '' : r[0]);
                    },
                    child: Column(children: [const Text('Size', style: TextStyle(fontSize: 11, color: muted)), Text((d['size'] ?? '') != '' ? '${d['size']} in' : 'Optional', style: const TextStyle(fontWeight: FontWeight.w700))]),
                  ),
                ),
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
        );
      }),
    );

// the photo, the place picture and the label rows of one damage photo
class DamageEditor extends ConsumerWidget {
  final String id, did;
  final Widget? nav;
  final String? title;
  const DamageEditor(this.id, this.did, {super.key, this.nav, this.title});
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
              _sq(LucideIcons.camera, () => context.push('/i/$id/cam', extra: CamArgs(dmg: d['zone'] ?? 'Exterior', redo: did))),
              const SizedBox(width: 8),
              _sq(LucideIcons.trash2, () {
                final file = d['f'] as String?;
                store.mut(id, (s) {
                  manual(s).removeWhere((x) => x['id'] == did);
                  syncDamages(s);
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
      WhereView(d, fuel, (p) {
        store.mut(id, (s) {
          setLabel(dmgById(s, did)!, 'panel', p, fuel);
          syncDamages(s);
        });
        if (placeOf(dmgById(store.ins[id]!, did)!['zone'] ?? 'Exterior', p) != null) labelDrawer(context, id, did);
      }),
      if (pl != null) ...[
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: RowList([
            if (pl['ex'] == true && pl['fix'] != true) RowBtn(pl['exl'] ?? 'Where', (d['ex'] ?? '') != '' ? setVal(d['ex']) : needVal(), onTap: () => labelDrawer(context, id, did)),
            RowBtn('Type', (d['type'] ?? '') != '' ? setVal(dshort(d['panel'], d['type'])) : needVal(), onTap: () => labelDrawer(context, id, did)),
            RowBtn('Severity', (d['sev'] ?? '') != '' ? setVal('${d['sev']}${(d['size'] ?? '') != '' ? ' · ${d['size']} in' : ''}') : needVal(), onTap: () => labelDrawer(context, id, did)),
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
  void _go(int i) => store.mut(widget.id, (s) => s['li'] = i);
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
    final d = manual(st)[li], z = d['zone'] ?? 'Exterior', zl = zoneDamages(st, z), n = zl.indexWhere((e) => e.$2 == li) + 1, pos = o.indexOf(li);
    final left = unlabelledOrder(st).length, ok = dmgDone(d, fuel), guess = labelled(d, fuel) && d['ai'] == true;
    Widget arrow(IconData ic, int? to) => to == null
        ? const SizedBox()
        : GestureDetector(onTap: () => _go(to), child: Container(width: 44, height: 44, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: Icon(ic, size: 20)));
    return Scaffold(
      appBar: PhaseHeader('Damages', 1, onBack: () => store.mut(widget.id, (s) => s['phase'] = 'capture')),
      body: Column(children: [
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
            for (final zz in dz)
              if (zoneDamages(st, zz).isNotEmpty)
                () {
                  final l = zoneDamages(st, zz), done = l.where((e) => dmgDone(e.$1, fuel)).length, on = zz == z;
                  return TextButton.icon(
                    onPressed: () => _go(l.first.$2),
                    icon: done == l.length ? const Icon(LucideIcons.check, size: 14) : const SizedBox(),
                    label: Text('$zz $done/${l.length}', style: TextStyle(fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: done == l.length ? bid : Colors.black, decoration: on ? TextDecoration.underline : null)),
                  );
                }(),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: GestureDetector(
            onHorizontalDragEnd: (e) {
              final v = e.primaryVelocity ?? 0;
              if (v < -200 && pos < o.length - 1) _go(o[pos + 1]);
              if (v > 200 && pos > 0) _go(o[pos - 1]);
            },
            child: ListView(padding: const EdgeInsets.all(16), children: [
              DamageEditor(widget.id, d['id'], title: '$z · $n of ${zl.length}', nav: Positioned(right: 10, top: 78, child: Column(children: [arrow(LucideIcons.chevronRight, pos < o.length - 1 ? o[pos + 1] : null)])), key: ValueKey(d['id'])),
              if (pos > 0) Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _go(o[pos - 1]), icon: const Icon(LucideIcons.chevronLeft, size: 16), label: const Text('Previous photo'))),
            ]),
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
      appBar: TitleBar(zoneTitle[d['zone'] ?? 'Exterior']!.replaceAll('damages', 'damage')),
      body: ListView(padding: const EdgeInsets.all(16), children: [DamageEditor(id, did)]),
      bottomNavigationBar: BottomBar(Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: ok ? () => addDamage(context, id, d['zone'] ?? 'Exterior', replace: true) : null, icon: const Icon(LucideIcons.plus, size: 16), label: const Text('Add another'))),
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
  final src = await showChoice(context, 'Add a damage', const [Opt('camera', label: 'Take photo'), Opt('library', label: 'Upload')], const []);
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
      final d = {'id': newId, 'zone': zone, 'panel': '', 'type': '', 'sev': '', 'size': '', 'src': 'library', 'f': rel};
      if (hint != null) setLabel(d, 'panel', hint, fuelOf(s));
      manual(s).add(d);
      syncDamages(s);
    });
  }
  if (did == null || !context.mounted) return;
  final page = MaterialPageRoute(builder: (_) => DamageFormPage(id, did!));
  replace ? Navigator.of(context).pushReplacement(page) : Navigator.of(context).push(page);
}
