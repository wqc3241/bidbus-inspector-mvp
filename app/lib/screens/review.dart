// Review: one page per section (Start, Exterior, Tires & Wheels, Paint, Interior, OBDII, Mechanicals, Underbody) with Next.
// One row per check, OK by default; a tap opens a drawer with its problems. Ported from the mockup's sumCard / viewSummary.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../camera/camera_screen.dart';
import '../data/ql.dart';
import '../logic/insp.dart';
import '../services/store.dart';
import '../services/media.dart' show cutSpinFrames;
import '../data/paint_car_data.dart';
import '../widgets/paint_car.dart';
import '../widgets/spin_view.dart';
import '../widgets/ui.dart';
import 'check_id.dart';
import 'damages.dart';

// ---------- drawers ----------
Future<void> openCheck(BuildContext context, String id, String ck, String? w) async {
  final st = store.ins[id]!, it = byId[ck]!, t = w != null ? tire(st, w) : null, base = ckBase(it), cs = checkState(st, it, t), fuel = fuelOf(st);
  final dv = dmgVals(st, ck, w), hand = cs.$2.where((p) => !dv.contains(p)).toList();
  final sel = [...dv, if (hand.isNotEmpty) hand.first else if (dv.isEmpty) (ck == 'ck_road' && m(st, 'vals')['road_done'] == true ? 'Done, no problems' : base.first)];
  final opts = [
    for (final o in base) Opt(o, color: bid),
    for (final o in optsFor(it, fuel).where((o) => !base.contains(o))) Opt(o, label: plain(o), color: levelColor(level(it, o)), tag: isRedLevel(level(it, o)) ? level(it, o) : null, locked: dv.contains(o)),
  ];
  final v = await showChoice(context, chipLabel[ck] ?? it['label'], opts, sel, sub: w != null ? wheelName(w) : null);
  if (v == null) return;
  String? step;
  store.mut(id, (s) => step = pickCheck(s, ck, w, v));
  if (!context.mounted) return;
  if (step == 'extra') {
    final ex = extra[ck]!, dx = dmgVals(store.ins[id]!, ck, w, 'x'), src = w != null ? tire(store.ins[id]!, w) : store.ins[id]!;
    final e = await showChoice(context, ex[0] as String, [for (final o in ex[1] as List<String>) Opt(o, locked: dx.contains(o))], lst(src, 'extra', ck), sub: plain(v));
    if (e != null) store.mut(id, (s) => pickExtra(s, ck, w, e));
  } else if (step == 'codes') {
    final c = await showTextSheet(context, 'Engine codes', store.ins[id]!['codes'] ?? '', caps: true);
    if (c != null) store.mut(id, (s) => s['codes'] = c.toUpperCase());
  }
}

Future<void> pickOne(BuildContext context, String id, String title, List<Opt> opts, String? cur, void Function(J st, String v) apply, {String? sub}) async {
  final v = await showChoice(context, title, opts, [cur], sub: sub);
  if (v != null) store.mut(id, (s) => apply(s, v));
}

// ---------- rows ----------
Widget checkRows(BuildContext context, String id, J st, List<J> list, {String? w}) => RowList(checkRowItems(context, id, st, list, w: w));

List<Widget> checkRowItems(BuildContext context, String id, J st, List<J> list, {String? w}) => [
      for (final it in list)
        () {
          final t = w != null ? tire(st, w) : null, cs = checkState(st, it, t), p = cs.$2, ex = lst(t ?? st, 'extra', it['id']);
          Widget val;
          String? sub;
          Color? subC;
          if (p.isNotEmpty) {
            final c = levelColor(worstLevel(it, p));
            val = alertVal(c);
            sub = p.map(plain).join(', ') + (ex.isNotEmpty ? ' · ${ex.join(', ')}' : '') + (it['id'] == 'ck_scan' && (st['codes'] ?? '') != '' ? ' · ${st['codes']}' : '');
            subC = c == red ? red : const Color(0xFF9A4F05);
          } else if (it['id'] == 'ck_road') {
            val = m(st, 'vals')['road_done'] == true ? okVal('Done') : const Text('Not done', style: TextStyle(color: muted, fontWeight: FontWeight.w600));
          } else {
            val = okVal(cs.$1);
          }
          return RowBtn(chipLabel[it['id']] ?? it['label'], val, sub: sub, subColor: subC, onTap: () => openCheck(context, id, it['id'], w));
        }(),
    ];

class ReviewScreen extends ConsumerWidget {
  final String id;
  const ReviewScreen(this.id, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(storeProvider).ins[id]!, fuel = fuelOf(st), i = ((st['sp'] ?? 0) as int).clamp(0, capseq.length - 1), k = capseq[i];
    final f = secInfo(st, k), bl = pageBlock(st, k), nx = i + 1 < capseq.length ? stTitle(capseq[i + 1]) : 'Summary', sok = m(st, 'sok');
    final ul = zoneTitle.containsKey(k) && f.miss == 0 ? zoneDamages(st, k).where((e) => !dmgDone(e.$1, fuel)).toList() : <(J, int)>[];
    return Scaffold(
      appBar: PhaseHeader('Review', 2, onBack: () => store.mut(id, (s) {
        if (i > 0) {
          s['sp'] = i - 1;
        } else if (manual(s).isNotEmpty) {
          s['phase'] = 'label';
          s['li'] = labelOrder(s).first;
        } else {
          s['phase'] = 'capture';
        }
      })),
      body: Column(children: [
        TabStrip([
          // while this page is unfinished the pages after it are shut
          for (var j = 0, open = openTo([for (final kk in capseq) pageBlock(st, kk).isEmpty], i); j < capseq.length; j++)
            () {
              final kk = capseq[j], fi = secInfo(st, kk), b = pageBlock(st, kk), done = sok[kk] == true;
              return stripTab(stTitle(kk), j == i, j <= open ? () => store.mut(id, (s) => s['sp'] = j) : null,
                  end: !done ? null : b.isNotEmpty ? const CircleAvatar(radius: 3, backgroundColor: amber) : fi.probs > 0 ? Text('${fi.probs}', style: const TextStyle(color: red, fontWeight: FontWeight.w700)) : null);
            }(),
        ]),
        const Divider(height: 1),
        // each page opens at its top
        Expanded(child: ListView(key: ValueKey(k), padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [_card(context, st, k, f)])),
      ]),
      bottomNavigationBar: BottomBar(ul.isNotEmpty
          ? PBtn('Label ${ul.length > 1 ? '${ul.length} damage photos' : 'the damage photo'}', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DamageFormPage(id, ul.first.$1['id']))), icon: LucideIcons.pen)
          : PBtn(bl.isNotEmpty ? bl : '${f.probs > 0 ? '${f.probs} problem${f.probs > 1 ? 's' : ''}' : 'No problems'} · Next: $nx', bl.isNotEmpty
              ? null
              : () => store.mut(id, (s) {
                    m(s, 'sok')[k] = true;
                    i >= capseq.length - 1 ? s['phase'] = 'final' : s['sp'] = i + 1;
                  }), icon: bl.isEmpty ? LucideIcons.chevronRight : null, trailingIcon: true)),
    );
  }

  Widget _card(BuildContext context, J st, String k, SecInfo f) {
    final tag = f.miss > 0
        ? Text('${f.miss} to take', style: const TextStyle(color: amber, fontWeight: FontWeight.w700))
        : f.unl > 0
            ? Text('${f.unl} to label', style: const TextStyle(color: amber, fontWeight: FontWeight.w700))
            : f.fqm > 0
                ? Text('${f.fqm} to answer', style: const TextStyle(color: amber, fontWeight: FontWeight.w700))
                : f.probs > 0
                    ? Text('${f.probs} problem${f.probs > 1 ? 's' : ''}', style: const TextStyle(color: red, fontWeight: FontWeight.w700, fontSize: 15))
                    : okVal('OK');
    final head = Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Expanded(child: Text(stTitle(k), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700))),
        tag,
        if (f.miss > 0) TextButton.icon(onPressed: () => _takeMissing(context, st, k), icon: const Icon(LucideIcons.camera, size: 14), label: const Text('Take')),
      ]),
    );
    final body = switch (k) {
      'start' => _start(context, st),
      'Tires' => _tires(context, st),
      'Paint' => _paint(context, st),
      _ => _generic(context, st, k),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [head, ...body]);
  }

  void _takeMissing(BuildContext context, J st, String k) {
    final ck = k == 'Paint' ? 'Exterior' : k, l = capList(ck, st);
    final rl = revList(k, st), first = rl.where((e) => !capOk(st, e.$1)).firstOrNull;
    context.push('/i/$id/cam', extra: CamArgs(k: ck, i: first?.$3 ?? capNext(st, l, 0)));
  }

  // photos of the page; a tap retakes that shot in the camera
  Widget _shots(BuildContext context, J st, String k, {String? w}) {
    final rl = revList(k, st).where((e) => w == null || e.$1['wheel'] == w).toList(), fl = m(st, 'files');
    if (rl.isEmpty) return const SizedBox();
    final t = <Widget>[];
    for (final e in rl) {
      final x = e.$1, id = x['id'] as String, has = capHas(st, x), sk = capSkipped(st, x);
      void retake() => context.push('/i/${this.id}/cam', extra: CamArgs(k: e.$2, i: e.$3, single: true));
      if (isMulti(id)) {
        final a = (m(st, 'multi')[id] ?? []) as List;
        if (a.isEmpty) t.add(ShotTile(shotLabel(x), icon: sk ? LucideIcons.minus : LucideIcons.plus, missing: !sk, onTap: retake));
        for (var q = 0; q < a.length; q++) {
          t.add(ShotTile('${shotLabel(x)}${a.length > 1 ? ' ${q + 1}' : ''}', file: store.abs(a[q]['f']), onTap: retake));
        }
        continue;
      }
      final key = x['panel'] != null ? 'paint:${x['panel']}' : x['wheel'] != null ? '$id-${x['wheel']}' : id;
      final vid = (x['it'] as J)['kind'] == 'video';
      t.add(ShotTile(shotLabel(x), file: has && !vid ? store.abs(fl[key]) : null, icon: vid ? LucideIcons.video : has ? LucideIcons.camera : sk ? LucideIcons.minus : LucideIcons.plus, missing: !has && !sk, onTap: retake));
      if (id == 'video_360' && has) t.add(ShotTile('360 view', icon: LucideIcons.rotateCw, dark: true, onTap: () => showSpin(context, st)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Sub3('Photos', LucideIcons.camera), tiles(t)]);
  }

  Widget _damages(BuildContext context, J st, String z, {String? w}) {
    final fuel = fuelOf(st), list = zoneDamages(st, z).where((e) => w == null || (e.$1['panel'] ?? '') == '' || (e.$1['panel'] as String).startsWith('${wheelName(w)} ')).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Sub3('Damages', LucideIcons.triangleAlert),
      tiles([
        for (var j = 0; j < list.length; j++)
          () {
            final d = list[j].$1, lb = labelled(d, fuel);
            return ShotTile(lb ? d['panel'] : 'Not labelled',
                sub: lb ? dshort(d['panel'], d['type']) : null,
                file: d['f'] != null ? store.abs(d['f']) : null,
                damage: true,
                corner: '${j + 1}',
                badge: lb ? d['sev'] : null,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DamageFormPage(id, d['id']))));
          }(),
        ShotTile('Add', icon: LucideIcons.plus, dashed: true, onTap: () => addDamage(context, id, z, wheel: w)),
      ]),
    ]);
  }

  // a mod tile opens the camera on that photo: it shows there, to delete or retake
  Widget _mods(BuildContext context, J st, String k) {
    final all = (m(st, 'multi')[modslot[k]] ?? []) as List, at = [for (var q = 0; q < all.length; q++) if (all[q]['sec'] == k) q];
    if (at.isEmpty) return const SizedBox();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Sub3('Mods', LucideIcons.wrench),
      tiles([
        for (var n = 0; n < at.length; n++)
          ShotTile('Mod ${n + 1}',
              file: all[at[n]]['f'] != null ? store.abs(all[at[n]]['f']) : null,
              icon: LucideIcons.wrench,
              onTap: () => context.push('/i/$id/cam', extra: CamArgs(k: k, i: all[at[n]]['at'] as int?, single: true, sel: ('m', at[n])))),
      ]),
    ]);
  }

  List<Widget> _start(BuildContext context, J st) {
    final fl = m(st, 'files'), ow = byId['id_owner']!;
    return [
      const Sub3('Documents', LucideIcons.idCard),
      tiles([
        for (final d in ['ph_license', 'ph_reg', if (st['owner'] == 'Family, with proof') 'ph_family'])
          ShotTile(short[d]!, file: fl[d] != null ? store.abs(fl[d]) : null, missing: fl[d] == null, icon: fl[d] != null ? LucideIcons.camera : LucideIcons.plus, onTap: () => takeDoc(context, id, d)),
      ]),
      RowList([
        RowBtn(ow['label'], (st['owner'] ?? '') == '' ? needVal() : st['owner'] == 'No' ? alertVal(red, 'No') : okVal(st['owner']), need: (st['owner'] ?? '') == '',
            onTap: () => pickOne(context, id, ow['label'], [for (final o in strs(ow['options'])) Opt(o, color: o == 'No' ? red : bid)], st['owner'], (s, v) {
                  s['owner'] = v;
                  if (v != 'Family, with proof') m(s, 'shots').remove('ph_family');
                })),
      ]),
      if (st['owner'] == 'No') ...[const SizedBox(height: 16), PBtn('End the visit', () => endVisit(context, id), icon: LucideIcons.ban, color: const Color(0xFFDC2626))],
    ];
  }

  List<Widget> _generic(BuildContext context, J st, String k) {
    final si = stepItems(k, st), vals = m(st, 'vals'), feat = m(st, 'feat');
    final rows = <Widget>[];
    if (k == 'Interior') {
      final kn = vals['keys_n'] as String?;
      rows.add(RowBtn('Number of keys', kn == null ? needVal() : kn == '2' ? setVal(kn) : alertVal(kn == '0' ? red : amber, kn), need: kn == null,
          sub: kn != null && vals['keys_auto'] == 1 ? 'Read from photo' : null,
          onTap: () => pickOne(context, id, 'Number of keys', [Opt('0', color: red), Opt('1', color: amber), Opt('2', label: '2 or more', color: bid)], kn, (s, v) {
                m(s, 'vals')['keys_n'] = v;
                m(s, 'vals')['keys_auto'] = 0;
                keysSync(s);
              })));
      for (final q in featq) {
        final v = feat[q[0]] as String?, locked = dmgVals(st, q[0], null, 'f').isNotEmpty;
        rows.add(RowBtn(q[1], (v ?? '') == '' ? needVal() : v == 'Not working' ? alertVal(amber, v!) : setVal(v!), need: (v ?? '') == '',
            onTap: () => pickOne(context, id, q[1], [for (final o in q[2] as List<String>) Opt(o, color: o == 'Not working' ? amber : bid, locked: locked && o != 'Not working')], v, (s, x) => m(s, 'feat')[q[0]] = x)));
      }
    }
    final entries = <Widget>[];
    for (final e in si.entries) {
      if (e['id'] == 'vin_scan') {
        entries.add(RowBtn('VIN, read from the door-jamb photo', vals['vin_door'] != null ? setVal(vals['vin_door']) : const Text('Not read', style: TextStyle(color: muted))));
      } else if (e['id'] == 'ev_soh') {
        entries.add(RowBtn(e['label'], (vals['ev_soh'] ?? '') != '' ? setVal('${vals['ev_soh']}%') : const Text('–'), sub: vals['ev_soh_auto'] == 1 && (vals['ev_soh'] ?? '') != '' ? 'Read from photo' : null, onTap: () async {
          final v = await showTextSheet(context, 'Battery health', vals['ev_soh'] ?? '', unit: '%', kb: TextInputType.number, max: 3);
          if (v != null) {
            store.mut(id, (s) {
              final n = int.tryParse(v);
              m(s, 'vals')['ev_soh'] = n != null && n >= 1 && n <= 100 ? '$n' : '';
              m(s, 'vals')['ev_soh_auto'] = 0;
            });
          }
        }));
      }
    }
    return [
      _shots(context, st, k),
      if (zoneTitle.containsKey(k)) _damages(context, st, k),
      _mods(context, st, k),
      if (entries.isNotEmpty) ...[RowList(entries), const SizedBox(height: 16)],
      RowList([...rows, ...checkRowItems(context, id, st, si.checks)]),
    ];
  }

  List<Widget> _tires(BuildContext context, J st) {
    final w = st['wheel'] as String? ?? 'lf', t = tire(st, w), r = m(t, 'read'), vals = m(st, 'vals');
    Future<void> pick(String f) async {
      if (f == 'brand') {
        final v = await showPicker(context, 'Brand', [tireBrands], [(r['brand'] ?? '') == '' ? 'Michelin' : r['brand']], sub: '${wheelName(w)} · optional', clear: (r['brand'] ?? '') != '');
        if (v != null) store.mut(id, (s) => m(tire(s, w), 'read')..['brand'] = v.isEmpty ? '' : v[0]..['auto'] = false);
      } else if (f == 'size') {
        final p = (byId['tire_size']!['picker']['parts'] as List).map((x) => strs(x['options'])).toList();
        final mm = RegExp(r'^(\d+)/(\d+)(R\d+)$').firstMatch(r['size'] ?? '');
        final v = await showPicker(context, 'Size', p, mm != null ? [mm[1]!, mm[2]!, mm[3]!] : ['225', '55', 'R17'], seps: ['/', ''], sub: '${wheelName(w)} · optional', clear: (r['size'] ?? '') != '');
        if (v != null) store.mut(id, (s) => m(tire(s, w), 'read')..['size'] = v.isEmpty ? '' : '${v[0]}/${v[1]}${v[2]}'..['auto'] = false);
      } else {
        final v = await showPicker(context, 'Tread depth, lowest groove', [List.generate(14, (i) => '${i + 1}')], [t['tread'] == '' ? '6' : t['tread']], unit: '/32', sub: wheelName(w));
        if (v != null && v.isNotEmpty) {
          store.mut(id, (s) => tire(s, w)
            ..['tread'] = v[0]
            ..['treadAuto'] = false);
        }
      }
    }

    final tm = vals['tires_match'] as String?;
    return [
      Row(children: [
        for (final x in wheels)
          Expanded(
            child: GestureDetector(
              onTap: () => store.mut(id, (s) => s['wheel'] = x[0]),
              child: Container(
                margin: const EdgeInsets.all(3),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: x[0] == w ? Colors.black : alt, borderRadius: BorderRadius.circular(12)),
                // a wheel whose tread depth is not in yet gets the red frame of a row still to answer
                foregroundDecoration: tire(st, x[0])['tread'] == '' ? BoxDecoration(border: Border.all(color: const Color(0xFFE1255D), width: 2), borderRadius: BorderRadius.circular(12)) : null,
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (lst(tire(st, x[0]), 'probs', 'ck_tire').length + lst(tire(st, x[0]), 'probs', 'ck_wheel').length > 0) const Icon(LucideIcons.triangleAlert, size: 13, color: amber),
                    Text(x[1], style: TextStyle(fontWeight: FontWeight.w700, color: x[0] == w ? Colors.white : Colors.black)),
                  ]),
                  Text(tire(st, x[0])['tread'] != '' ? '${tire(st, x[0])['tread']}/32' : '–', style: TextStyle(fontSize: 12, color: x[0] == w ? Colors.white70 : muted)),
                ]),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 12),
      _shots(context, st, 'Tires', w: w),
      _damages(context, st, 'Tires', w: w),
      _mods(context, st, 'Tires'),
      RowList([
        RowBtn('Brand', (r['brand'] ?? '') != '' ? setVal(r['brand']) : const Text('Optional', style: TextStyle(color: muted)), sub: r['auto'] == true && (r['brand'] ?? '') != '' ? 'Read from photo' : null, onTap: () => pick('brand')),
        RowBtn('Size', (r['size'] ?? '') != '' ? setVal((r['size'] as String).replaceFirst('R', ' R')) : const Text('Optional', style: TextStyle(color: muted)), onTap: () => pick('size')),
        RowBtn('Tread depth', t['tread'] != '' ? setVal('${t['tread']}/32') : needVal(), need: t['tread'] == '', sub: t['treadAuto'] == true ? 'Read from photo' : null, onTap: () => pick('tread')),
        ...checkRowItems(context, id, st, [byId['ck_tire']!, byId['ck_wheel']!], w: w),
      ]),
      const SizedBox(height: 16),
      RowList([
        RowBtn('All 4 tires match', (tm ?? '') == '' ? needVal() : tm == 'Mismatch' ? alertVal(amber, tm!) : setVal(tm!), need: (tm ?? '') == '',
            onTap: () => pickOne(context, id, 'All 4 tires match', [for (final o in strs(byId['tires_match']!['options'])) Opt(o, color: o == 'Mismatch' ? amber : bid)], tm, (s, v) => m(s, 'vals')['tires_match'] = v)),
      ]),
    ];
  }

  List<Widget> _paint(BuildContext context, J st) {
    Future<void> edit(String panel) async {
      final r = (m(st, 'paint')[panel] as J?) ?? {};
      final v = await showMilsSheet(context, panel, r['na'] == true ? '' : '${r['v'] ?? ''}', extraActions: [
        TextButton(
            onPressed: () {
              store.mut(id, (s) {
                final p = (m(s, 'paint')[panel] ??= <String, dynamic>{}) as J;
                p['na'] = p['na'] != true;
                if (p['na'] == true) {
                  p['shot'] = false;
                  p['v'] = '';
                }
                syncPaint(s);
              });
              Navigator.pop(context);
            },
            child: Text(r['na'] == true ? 'On this car' : 'Not on this car')),
      ]);
      if (v == null || r['na'] == true) return; // a panel not on this car keeps no reading: "On this car" first
      store.mut(id, (s) {
        final p = (m(s, 'paint')[panel] ??= <String, dynamic>{}) as J;
        final n = double.tryParse(v);
        p['v'] = n == null || n < 0 || n > 99.9 ? '' : n.toStringAsFixed(1);
        p['auto'] = false;
        syncPaint(s);
      });
    }

    return [
      // the mockup's paint diagram: the car from above, one reading per panel
      PaintCar(
          readings: true,
          make: (st['car'] as J?)?['make'],
          cell: (panel) {
            final r = (m(st, 'paint')[panel] as J?) ?? {}, has = (r['v'] ?? '') != '';
            return PaintReadingCell(
                panel: panel,
                value: r['na'] == true ? 'N/A' : has ? milsText(r['v']) : '–',
                label: paintReadPanels.firstWhere((x) => x.$1 == panel).$3,
                state: r['na'] == true ? 'na' : paintHigh(r) ? 'hi' : !has ? 'ms' : '',
                onTap: () => edit(panel));
          }),
      const SizedBox(height: 20),
      _shots(context, st, 'Paint'),
      _damages(context, st, 'Paint'),
      checkRows(context, id, st, [byId['ck_paint']!]),
    ];
  }
}

// 360 view: Scaleflex cloudimage-360-view over the 36 frames saved on the phone (lib/widgets/spin_view.dart).
// If the frames were never cut (the app was closed while cutting), they are cut again here from the walk-around.
Future<void> showSpin(BuildContext context, J st) async {
  final id = st['id'] as String;
  var frames = ((st['spin'] as List?) ?? []).cast<String>();
  final video = m(st, 'files')['video_360'] as String?;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('360 view', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Consumer(builder: (c, ref, _) {
            final f = ((ref.watch(storeProvider).ins[id]?['spin'] as List?) ?? []).cast<String>();
            return f.length == 36 ? SpinView([for (final x in f) store.abs(x)]) : const Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator());
          }),
        ]),
      ),
    ),
  );
  if (frames.length != 36 && video != null && File(store.abs(video)).existsSync()) {
    frames = (await cutSpinFrames(store.abs(video), store.abs(store.dirOf(id)))).map((f) => f.substring(store.docs.length + 1)).toList();
    store.mut(id, (s) {
      if (m(s, 'files')['video_360'] == video) s['spin'] = frames;
    });
  }
}
