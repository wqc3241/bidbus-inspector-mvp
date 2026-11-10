// The Review questions as rows with their answer drawers: checks (OK by default, a tap opens OK and its problems), number of keys,
// sunroof and navigation, All 4 tires match. Review shows them on its pages; the camera asks some of them at the end of a section
// (docs/11), drawn dark (dark: true, inside DarkRows). One answer either way.
import 'package:flutter/material.dart';

import '../data/ql.dart';
import '../logic/insp.dart';
import '../services/store.dart';
import 'ui.dart';

// ---------- drawers ----------
Future<void> openCheck(BuildContext context, String id, String ck, String? w, {bool dark = false}) async {
  final st = store.ins[id]!, it = byId[ck]!, t = w != null ? tire(st, w) : null, base = ckBase(it), cs = checkState(st, it, t), fuel = fuelOf(st);
  final dv = dmgVals(st, ck, w), hand = cs.$2.where((p) => !dv.contains(p)).toList();
  final sel = [...dv, if (hand.isNotEmpty) hand.first else if (dv.isEmpty) (ck == 'ck_road' && m(st, 'vals')['road_done'] == true ? 'Done, no problems' : base.first)];
  final opts = [
    for (final o in base) Opt(o, color: bid),
    for (final o in optsFor(it, fuel).where((o) => !base.contains(o))) Opt(o, label: plain(o), color: levelColor(level(it, o)), tag: isRedLevel(level(it, o)) ? level(it, o) : null, locked: dv.contains(o)),
  ];
  final v = await showChoice(context, chipLabel[ck] ?? it['label'], opts, sel, sub: w != null ? wheelName(w) : null, dark: dark);
  if (v == null) return;
  String? step;
  store.mut(id, (s) => step = pickCheck(s, ck, w, v));
  if (!context.mounted) return;
  if (step == 'extra') {
    final ex = extra[ck]!, dx = dmgVals(store.ins[id]!, ck, w, 'x'), src = w != null ? tire(store.ins[id]!, w) : store.ins[id]!;
    final e = await showChoice(context, ex[0] as String, [for (final o in ex[1] as List<String>) Opt(o, locked: dx.contains(o))], lst(src, 'extra', ck), sub: plain(v), dark: dark);
    if (e != null) store.mut(id, (s) => pickExtra(s, ck, w, e));
  } else if (step == 'codes') {
    final c = await showTextSheet(context, 'Engine codes', store.ins[id]!['codes'] ?? '', caps: true, dark: dark);
    if (c != null) store.mut(id, (s) => s['codes'] = c.toUpperCase());
  }
}

Future<void> pickOne(BuildContext context, String id, String title, List<Opt> opts, String? cur, void Function(J st, String v) apply, {String? sub, bool dark = false}) async {
  final v = await showChoice(context, title, opts, [cur], sub: sub, dark: dark);
  if (v != null) store.mut(id, (s) => apply(s, v));
}

// ---------- rows ----------
Widget checkRows(BuildContext context, String id, J st, List<J> list, {String? w, bool dark = false}) => RowList(checkRowItems(context, id, st, list, w: w, dark: dark));

// labels: shorter names for some checks (the end-of-section card's Tire and Wheel under each wheel)
List<Widget> checkRowItems(BuildContext context, String id, J st, List<J> list, {String? w, bool dark = false, Map<String, String> labels = const {}}) => [
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
            val = m(st, 'vals')['road_done'] == true ? okVal('Done') : plainVal('Not done');
          } else {
            val = okVal(cs.$1);
          }
          return RowBtn(labels[it['id']] ?? chipLabel[it['id']] ?? it['label'], val, sub: sub, subColor: subC, onTap: () => openCheck(context, id, it['id'], w, dark: dark));
        }(),
    ];

// Interior: number of keys (read from the keys photo until the inspector picks), then sunroof and navigation; all required
List<Widget> featRows(BuildContext context, String id, J st, {bool dark = false}) {
  final vals = m(st, 'vals'), feat = m(st, 'feat'), kn = vals['keys_n'] as String?;
  return [
    RowBtn('Number of keys', kn == null ? needVal() : kn == '2' ? setVal(kn) : alertVal(kn == '0' ? red : amber, kn), need: kn == null,
        sub: kn != null && vals['keys_auto'] == 1 ? 'Read from photo' : null,
        onTap: () => pickOne(context, id, 'Number of keys', [Opt('0', color: red), Opt('1', color: amber), Opt('2', label: '2 or more', color: bid)], kn, (s, v) {
              m(s, 'vals')['keys_n'] = v;
              m(s, 'vals')['keys_auto'] = 0;
              keysSync(s);
            }, dark: dark)),
    for (final q in featq)
      () {
        final v = feat[q[0]] as String?, locked = dmgVals(st, q[0], null, 'f').isNotEmpty;
        return RowBtn(q[1], (v ?? '') == '' ? needVal() : v == 'Not working' ? alertVal(amber, v!) : setVal(v!), need: (v ?? '') == '',
            onTap: () => pickOne(context, id, q[1], [for (final o in q[2] as List<String>) Opt(o, color: o == 'Not working' ? amber : bid, locked: locked && o != 'Not working')], v, (s, x) => m(s, 'feat')[q[0]] = x, dark: dark));
      }(),
  ];
}

// All 4 tires match: required; answered by the AI from the four whole-tire photos (Read from photo) until the inspector picks
Widget tmRow(BuildContext context, String id, J st, {bool dark = false}) {
  final vals = m(st, 'vals'), tm = vals['tires_match'] as String?;
  return RowBtn('All 4 tires match', (tm ?? '') == '' ? needVal() : tm == 'Mismatch' ? alertVal(amber, tm!) : setVal(tm!), need: (tm ?? '') == '',
      sub: (tm ?? '') != '' && vals['tm_auto'] == 1 ? 'Read from photo' : null,
      onTap: () => pickOne(context, id, 'All 4 tires match', [for (final o in strs(byId['tires_match']!['options'])) Opt(o, color: o == 'Mismatch' ? amber : bid)], tm, (s, v) {
            m(s, 'vals')['tires_match'] = v;
            m(s, 'vals')['tm_auto'] = 0;
          }, dark: dark));
}
