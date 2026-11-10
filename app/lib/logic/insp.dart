// One inspection's state and its rules, ported one to one from the mockup (reference/mockup-1109/src/template.html).
// The state is a plain JSON map with the mockup's shape, saved whole in drift after every change.
import '../data/ql.dart';

J newInspection({required String id, required J car, required String fuel, required String email, required String inspector}) {
  return {
    'id': id, 'car': car, 'report_email': email, 'inspector': inspector, 'created': DateTime.now().toIso8601String(),
    'status': 'progress', 'phase': 'start', 'fuel': fuel, 'owner': '', 'shots': <String, dynamic>{}, 'src': <String, dynamic>{},
    'probs': <String, dynamic>{}, 'extra': <String, dynamic>{}, 'codes': '', 'vals': <String, dynamic>{}, 'paint': <String, dynamic>{},
    'tires': {for (final w in wheels) w[0]: {'shots': <String, dynamic>{}, 'tread': '', 'probs': <String, dynamic>{}, 'extra': <String, dynamic>{}, 'read': <String, dynamic>{}}},
    'manual': <dynamic>[], 'multi': <String, dynamic>{}, 'skip': <String, dynamic>{}, 'feat': <String, dynamic>{}, 'note': '', 'overall': '',
    'signName': car['owner_name'] ?? '', 'signed': false, 'agree': false, 'sok': <String, dynamic>{}, 'dprev': <dynamic>[],
    'files': <String, dynamic>{}, 'turn': <String, dynamic>{}, 'docs': <String, dynamic>{}, 'start': null, 'end': null, 'cap': null,
    'aiq': <dynamic>[], 'up': null, 'nid': 0, 'ub': true, 'c9': true,
  };
}

// an inspection saved before Underbody had its own section: its shots were the end of Mechanicals
J splitUnderbody(J st) {
  if (st['ub'] == true) return st;
  st['ub'] = true;
  final n = capList0('Mechanicals', st).length;
  for (final e in [...manual(st), ...((m(st, 'multi')['ph_mod_mech'] ?? []) as List).cast<J>()]) {
    if (e['sec'] == 'Mechanicals' && e['at'] is int && (e['at'] as int) >= n) {
      e['sec'] = 'Underbody';
      e['at'] = (e['at'] as int) - n;
    }
  }
  if (m(st, 'sok')['Mechanicals'] == true) m(st, 'sok')['Underbody'] = true;
  return st;
}

// an inspection saved before the 1109 camera pass: its damage and mod photos (and where the camera stopped) point at shots of the
// old pass; each moves to the same shot in the new pass. A mod keeps the Review page it showed on (rs).
J cam1109(J st) {
  if (st['c9'] == true) return st;
  st['c9'] = true;
  // the shot at an old section and index, and where that shot is in the new pass
  (String, String, int)? spot(Object? sec, Object? at) {
    if (sec is! String || at is! int || !camseq0.contains(sec)) return null;
    final old = capList0(sec, st);
    if (at < 0 || at >= old.length) return null;
    final key = slotKey(old[at]);
    for (final k in camseq) {
      final l = capList(k, st);
      for (var j = 0; j < l.length; j++) {
        if (slotKey(l[j]) == key) return (key, k, j);
      }
    }
    return null;
  }

  for (final d in manual(st)) {
    final n = spot(d['sec'], d['at']);
    if (n != null) d..['key'] = n.$1..['sec'] = n.$2..['at'] = n.$3;
  }
  for (final s in const ['ph_mod_ext', 'ph_mod_int', 'ph_mod_mech']) {
    for (final e in ((m(st, 'multi')[s] ?? []) as List).cast<J>()) {
      final n = spot(e['sec'], e['at']);
      if (n == null) continue;
      e['key'] = n.$1;
      // a mod stays in its own list (the camera shows mods from modslot[section]): when its shot moved to a section of another
      // list (cargo, now in the walk-around), it keeps its section and is at no shot of it (tagAt)
      if (modslot[n.$2] != s) continue;
      if (n.$2 != e['sec']) e['rs'] ??= e['sec'];
      e..['sec'] = n.$2..['at'] = n.$3;
    }
  }
  final cap = st['cap'] as J?, c = spot(cap?['k'], cap?['i']), n = c == null ? null : (c.$2, c.$3);
  if (cap != null) {
    if (n != null) {
      cap..['k'] = n.$1..['i'] = n.$2;
    } else if (!camRun.contains(cap['k'])) {
      st['cap'] = null;
    }
  }
  return st;
}

String slotKey(J x) => x['panel'] != null ? 'paint:${x['panel']}' : x['wheel'] != null ? '${x['id']}-${x['wheel']}' : x['id'] as String;

// the shot a damage or mod photo was taken at, as an index of its camera section: found by the shot itself (key) when known, so a
// shot dropping out of the list (a panel not on the car, the engine videos when it will not start) moves no tag; null: at no shot
int? tagAt(J st, J e) {
  final sec = e['sec'], key = e['key'];
  if (sec is! String) return null;
  if (key is String) {
    final j = capList(sec, st).indexWhere((x) => slotKey(x) == key);
    return j < 0 ? null : j;
  }
  return e['at'] is int ? e['at'] as int : null;
}

String fuelOf(J st) => st['fuel'] as String;
J m(J st, String k) => (st[k] ??= <String, dynamic>{}) as J;
List<String> lst(J src, String k, String id) => ((m(src, k)[id] ??= <dynamic>[]) as List).cast<String>();
void setLst(J src, String k, String id, List<String> v) => m(src, k)[id] = v;
J tire(J st, String w) => (st['tires'] as J)[w] as J;
List<J> manual(J st) => (st['manual'] as List).cast<J>();

// ---------- items per section ----------
class StepItems {
  final List<J> media, entries, checks;
  StepItems(this.media, this.entries, this.checks);
}

const tireIds = {'tire_photo', 'tread_photo', 'tire_brand', 'tire_size', 'tread', 'ck_tire', 'ck_wheel'};
const featIds = {'sunroof', 'navigation'};

StepItems stepItems(String k, J st) {
  final fuel = fuelOf(st), media = <J>[], entries = <J>[], checks = <J>[];
  for (final id in layout[k] ?? const <String>[]) {
    final it = byId[id];
    if (it != null && fuelOk(it['cars'], fuel)) media.add(it);
  }
  for (final it in items) {
    if (secOf(it) != k || tireIds.contains(it['id']) || featIds.contains(it['id']) || !fuelOk(it['cars'], fuel)) continue;
    if (it['kind'] == 'entry') entries.add(it);
    if (it['kind'] == 'check') checks.add(it);
  }
  return StepItems(media, entries, checks);
}

// the end-of-section questions (docs/11, the mockup's askRows): groups of Review questions, the same answers as on Review.
// head: a group heading (null: the section's own list); w: a wheel's Tire and Wheel; feat: keys, sunroof, navigation; tm: All 4 tires match
typedef AskGroup = ({String? head, List<J> checks, String? w, bool feat, bool tm});
List<AskGroup> askGroups(J st, String k) {
  final fuel = fuelOf(st);
  List<J> its(Iterable<String> ids) => [for (final id in ids) if (byId[id] != null && fuelOk(byId[id]!['cars'], fuel)) byId[id]!];
  AskGroup g(String? head, List<J> checks, {String? w, bool feat = false, bool tm = false}) => (head: head, checks: checks, w: w, feat: feat, tm: tm);
  if (k == 'Tires') {
    return [
      g('Exterior', stepItems('Exterior', st).checks),
      if (its(askMove['Tires']!).isNotEmpty) g('Mechanicals', its(askMove['Tires']!)),
      g('Paint', its(['ck_paint'])),
      for (final w in wheels) g(w[2], its(['ck_tire', 'ck_wheel']), w: w[0]),
      if (byId['tires_match'] != null) g(null, const [], tm: true),
    ];
  }
  final obd = stepItems('OBDII', st).checks, trans = its(['ck_trans']), moved = its(askMove[k] ?? const []);
  return [
    g(null, stepItems(k, st).checks.where((it) => !askOut.contains(it['id'])).toList(), feat: k == 'Interior'),
    if (k == 'Interior' && obd.isNotEmpty) g('OBDII', obd), // the OBDII screens are taken at the end of Interior
    if (k == 'Interior' && trans.isNotEmpty) g('Mechanicals', trans), // asked after the first drive-off checks too
    if (moved.isNotEmpty) g('Mechanicals', moved),
  ];
}

// ---------- camera pass ----------
// a slot of the pass: {id, wheel?, panel?, it}
List<J> capList(String k, J st) {
  if (k == 'start') {
    return [if (st['owner'] == 'Family, with proof') {'id': 'ph_family', 'it': {'id': 'ph_family', 'kind': 'photo', 'label': 'Proof of family relationship'}}];
  }
  if (k == 'Paint') return [];
  final fuel = fuelOf(st), noStart = lst(st, 'probs', 'ck_engine').contains('Will not start');
  J? shot(String id) {
    final it = byId[id];
    // engine sound and exhaust videos are hidden when the engine will not start
    if (it == null || !fuelOk(it['cars'], fuel) || (noStart && (id == 'video_engine' || id == 'video_exhaust'))) return null;
    return {'id': id, 'it': it};
  }

  if (k == 'Tires') {
    // the walk-around: paint panel by panel, each tire (whole tire, tread gauge) as it is reached, cargo at the rear, hood, roof
    return [
      for (final w in walk)
        if (w[0] == 'p')
          ...paintSlots(st).where((x) => x['panel'] == w[1])
        else if (w[0] == 'w')
          for (final p in tireShots) {'id': p, 'wheel': w[1], 'it': {'id': p, 'kind': 'photo', 'label': '${wheelName(w[1])}${p == 'tread_photo' ? ' tire: tread gauge' : ' tire: whole tire photo'}'}}
        else
          ?shot(w[1]),
    ];
  }
  return [for (final id in camLayout[k] ?? const <String>[]) ?shot(id)];
}

// the pass before 1109 (Exterior with the paint panels, Tires & Wheels, Interior, OBDII, Mechanicals, Underbody): only to find where
// photos saved then were taken (cam1109, splitUnderbody)
List<J> capList0(String k, J st) {
  if (k == 'Tires') {
    return [
      for (final w in wheels)
        for (final p in tireShots) {'id': p, 'wheel': w[0], 'it': {'id': p, 'kind': 'photo', 'label': '${w[2]}${p == 'tread_photo' ? ' tire: tread gauge' : ' tire: whole tire photo'}'}}
    ];
  }
  if (k == 'start' || k == 'Paint') return capList(k, st);
  final noStart = lst(st, 'probs', 'ck_engine').contains('Will not start');
  var ml = stepItems(k, st)
      .media
      .where((it) => !(it['id'] as String).startsWith('ph_mod_') && !(noStart && (it['id'] == 'video_engine' || it['id'] == 'video_exhaust')))
      .map((it) => <String, dynamic>{'id': it['id'], 'it': it})
      .toList();
  if (k == 'Exterior') {
    final vi = ml.indexWhere((x) => x['id'] == 'video_360') + 1;
    ml = [...ml.sublist(0, vi), ...paintSlots(st), ...ml.sublist(vi)];
  }
  return ml;
}

List<J> paintSlots(J st) => [
      for (final x in paintPanels)
        if ((m(st, 'paint')[x[1]] as J?)?['na'] != true) {'id': 'paint', 'panel': x[1], 'it': {'id': 'paint', 'kind': 'photo', 'label': '${x[0]}: ${x[1]}'}}
    ];

bool capHas(J st, J x) {
  if (x['panel'] != null) return (m(st, 'paint')[x['panel']] as J?)?['shot'] == true;
  final v = x['wheel'] != null ? m(tire(st, x['wheel']), 'shots')[x['id']] : m(st, 'shots')[x['id']];
  return v != null && v != false && v != 0;
}

bool capSkipped(J st, J x) => (x['it'] as J)['optional'] == true && m(st, 'skip')[x['id']] == true && !capHas(st, x);
bool capOk(J st, J x) => capHas(st, x) || capSkipped(st, x);
List<int> capCount(J st, String k) {
  final l = capList(k, st);
  return [l.where((x) => capOk(st, x)).length, l.length];
}

int capNext(J st, List<J> l, int from) {
  for (var j = from; j < l.length; j++) {
    if (!capOk(st, l[j])) return j;
  }
  for (var j = 0; j < from && j < l.length; j++) {
    if (!capOk(st, l[j])) return j;
  }
  return l.length;
}

// the camera run: Check ID's family proof, then the five camera sections
const camRun = ['start', ...camseq];
int capLeft(J st) => camRun.fold(0, (n, k) {
      final c = capCount(st, k);
      return n + c[1] - c[0];
    });
String? nextSection(J st, String k) {
  final i = camRun.indexOf(k);
  if (i < 0) return null; // OBDII opened from Review: not a section of the run
  for (var j = i + 1; j < camRun.length; j++) {
    if (capList(camRun[j], st).isNotEmpty) return camRun[j];
  }
  return null;
}

String? prevSection(J st, String k) {
  final i = camRun.indexOf(k);
  for (var j = i - 1; j >= 0; j--) {
    if (camRun[j] != 'start' && capList(camRun[j], st).isNotEmpty) return camRun[j];
  }
  return null;
}

String? firstOpenSection(J st) {
  for (final k in camseq) {
    final l = capList(k, st);
    if (capNext(st, l, 0) < l.length) return k;
  }
  return null;
}

// Review pages keep their own sections: a shot shows on its home page (paint meter photos taken in the walk-around on Paint, the
// OBDII screens taken in Interior on OBDII, ...), in camera order; each entry keeps its camera section and index for a retake
List<(J, String, int)> revList(String k, J st) {
  final out = <(J, String, int)>[];
  for (final ck in camRun) {
    final l = capList(ck, st);
    for (var j = 0; j < l.length; j++) {
      if (homeOf(l[j], ck) == k) out.add((l[j], ck, j));
    }
  }
  return out;
}

List<int> revCount(J st, String k) {
  final l = revList(k, st);
  return [l.where((e) => capOk(st, e.$1)).length, l.length];
}

// a taken shot: file path saved, reading queued by the caller
void capMark(J st, J x, String src, String file) {
  if (x['panel'] != null) {
    final r = (m(st, 'paint')[x['panel']] ??= <String, dynamic>{}) as J;
    r['shot'] = true;
    r['src'] = src;
    m(st, 'files')['paint:${x['panel']}'] = file;
    syncPaint(st);
    return;
  }
  final id = x['id'] as String;
  if (isMulti(id)) {
    final a = (m(st, 'multi')[id] ??= <dynamic>[]) as List;
    a.add({'src': src, 'panel': null, 'f': file});
    m(st, 'shots')[id] = a.length;
    return;
  }
  final w = x['wheel'] as String?;
  (w != null ? m(tire(st, w), 'shots') : m(st, 'shots'))[id] = true;
  if (w == null) m(st, 'src')[id] = src;
  m(st, 'files')[w != null ? '$id-$w' : id] = file;
}

void capUnmark(J st, J x) {
  if (x['panel'] != null) {
    final r = (m(st, 'paint')[x['panel']] ??= <String, dynamic>{}) as J;
    r['shot'] = false;
    r.remove('src');
    if (r['auto'] == true) {
      r['v'] = '';
      r.remove('auto');
    }
    m(st, 'files').remove('paint:${x['panel']}');
    syncPaint(st);
    return;
  }
  final id = x['id'] as String, w = x['wheel'] as String?;
  if (isMulti(id)) {
    final a = (m(st, 'multi')[id] ?? []) as List;
    if (a.isNotEmpty) a.removeLast();
    a.isEmpty ? m(st, 'shots').remove(id) : m(st, 'shots')[id] = a.length;
    return;
  }
  if (id == 'tread_photo' && w != null) {
    final t = tire(st, w);
    if (t['treadAuto'] == true) {
      t['tread'] = '';
      t['treadAuto'] = false;
    }
  }
  (w != null ? m(tire(st, w), 'shots') : m(st, 'shots')).remove(id);
  if (w == null) m(st, 'src').remove(id);
  m(st, 'files').remove(w != null ? '$id-$w' : id);
}

String shotLabel(J x) {
  if (x['panel'] != null) return x['panel'];
  if (x['wheel'] != null) return '${(x['wheel'] as String).toUpperCase()}${x['id'] == 'tread_photo' ? ' tread' : ' tire'}';
  return short[x['id']] ?? (x['it'] as J)['label'];
}

// ---------- paint ----------
bool paintHigh(J? r) => r != null && r['na'] != true && r['v'] != null && r['v'] != '' && (double.tryParse('${r['v']}') ?? 0) >= paintHighMils;
List<String> paintHighs(J st) => [for (final x in paintPanels) if (paintHigh(m(st, 'paint')[x[1]] as J?)) x[1]];
List<String> paintWhere(List<String> highs) => highs.map(pn).where((h) => (extra['ck_paint']![1] as List).contains(h)).toList();

// a high reading ticks Panel repainted with that panel, only when the check is OK or already that problem
// what labelled damage photos set on Paint and panels is kept
void syncPaint(J st) {
  final highs = paintHighs(st), dp = dmgVals(st, 'ck_paint', null), dx = dmgVals(st, 'ck_paint', null, 'x');
  final hand = lst(st, 'probs', 'ck_paint').where((p) => !dp.contains(p)).toList();
  if (highs.isNotEmpty) {
    if (hand.isNotEmpty && hand.first != paintOpt) return;
    setLst(st, 'probs', 'ck_paint', [paintOpt, ...dp.where((p) => p != paintOpt)]);
    setLst(st, 'extra', 'ck_paint', {...dx, ...paintWhere(highs)}.toList());
    st['paintAuto'] = true;
  } else if (st['paintAuto'] == true) {
    if (hand.isNotEmpty && hand.first == paintOpt) setLst(st, 'probs', 'ck_paint', dp);
    setLst(st, 'extra', 'ck_paint', dx);
    st['paintAuto'] = false;
  }
}

// panels with a photo but no reading (and not marked not on this car): the report needs every reading
List<String> paintMissing(J st) => [
      for (final x in paintPanels)
        if ((m(st, 'paint')[x[1]] as J?)?['na'] != true && ((m(st, 'paint')[x[1]] as J?)?['v'] ?? '') == '') x[1]
    ];

// ---------- keys ----------
void keysSync(J st) {
  final kp = lst(st, 'probs', 'ck_keys').where((p) => p != 'Only one key').toList();
  if (m(st, 'vals')['keys_n'] == '1') kp.insert(0, 'Only one key');
  setLst(st, 'probs', 'ck_keys', kp);
}

// ---------- checks ----------
(String, List<String>) checkState(J st, J it, [J? t]) {
  final probs = lst(t ?? st, 'probs', it['id']);
  return (probs.isNotEmpty ? 'Problem' : (it['default'] ?? 'OK'), probs);
}

String worstLevel(J it, List<String> probs) {
  const order = ['Ends the visit', 'Not listed until fixed', 'Red', 'Yellow', 'Disclosed', 'Not checked', 'Normal'];
  var best = 'Normal';
  for (final p in probs) {
    final l = level(it, p);
    if (order.indexOf(l) < order.indexOf(best)) best = l;
  }
  return best;
}

List<String> ckBase(J it) => it['id'] == 'ck_road' ? ['Not done', 'Done, no problems'] : [it['default'] ?? 'OK'];

// picking an option in a check drawer; returns the next drawer step ('extra' or 'codes') or null to close
String? pickCheck(J st, String id, String? w, String v) {
  final it = byId[id]!, t = w != null ? tire(st, w) : null, src = t ?? st, base = ckBase(it), vals = m(st, 'vals');
  String? step;
  if (base.contains(v)) {
    setLst(src, 'probs', id, dmgVals(st, id, w));
    setLst(src, 'extra', id, dmgVals(st, id, w, 'x'));
    if (id == 'ck_road') vals['road_done'] = v == 'Done, no problems';
    if (id == 'ck_scan') st['codes'] = '';
    if (id == 'ck_paint') st['paintAuto'] = false;
  } else {
    final dv = dmgVals(st, id, w), was = lst(src, 'probs', id).where((p) => !dv.contains(p)).firstOrNull;
    var auto = false;
    setLst(src, 'probs', id, [...dv, v]);
    if (id == 'ck_road') vals['road_done'] = true;
    if (was != v) {
      setLst(src, 'extra', id, dmgVals(st, id, w, 'x'));
      if (id == 'ck_paint') st['paintAuto'] = false;
      if (id == 'ck_scan') st['codes'] = '';
    }
    if (id == 'ck_paint' && v == paintOpt) {
      final hs = paintWhere(paintHighs(st));
      if (hs.isNotEmpty) {
        setLst(src, 'extra', 'ck_paint', {...dmgVals(st, 'ck_paint', w, 'x'), ...hs}.toList());
        st['paintAuto'] = true;
        auto = true;
      }
    }
    if (extra[id] != null && !auto) {
      step = 'extra';
    } else if (id == 'ck_scan' && v.contains('type the codes')) {
      step = 'codes';
    }
  }
  if (id == 'ck_keys') {
    final k1 = lst(st, 'probs', 'ck_keys').contains('Only one key');
    if (k1 && vals['keys_n'] != '1') {
      vals['keys_n'] = '1';
      vals['keys_auto'] = 0;
    } else if (!k1 && vals['keys_n'] == '1') {
      vals['keys_n'] = '2';
      vals['keys_auto'] = 0;
    }
  }
  return step;
}

void pickExtra(J st, String id, String? w, String v) {
  final src = w != null ? tire(st, w) : st, dx = dmgVals(st, id, w, 'x');
  setLst(src, 'extra', id, [...dx, if (!dx.contains(v)) v]);
  if (id == 'ck_paint') st['paintAuto'] = false;
}

// ---------- damage photos ----------
// m: {id, zone, sec, at, panel, type, sev, size, ex, src, f, ai, aiWas, hint}
bool labelled(J? d, String fuel) {
  if (d == null || (d['panel'] ?? '') == '' || (d['type'] ?? '') == '' || (d['sev'] ?? '') == '') return false;
  final pl = placeOf(d['zone'] ?? 'Exterior', d['panel']);
  return pl != null && placeOpts(pl, fuel).contains(d['type']) && (pl['ex'] != true || (d['ex'] ?? '') != '') && (!needsSide(d) || (d['side'] ?? '') != '');
}

bool dmgDone(J d, String fuel) => labelled(d, fuel) && d['ai'] != true;
// the tab a damage shows on: its zone, but a Mechanicals damage at an underbody place (or taken or added there) is on Underbody
String dtab(J d) {
  final z = d['zone'] ?? 'Exterior';
  if (z != 'Mechanicals') return z;
  if (placeOf(z, d['panel']) != null) return dmgSec(z, d['panel']);
  return d['sec'] == 'Underbody' || d['tab'] == 'Underbody' ? 'Underbody' : 'Mechanicals';
}

List<(J, int)> zoneDamages(J st, String z) => [for (var i = 0; i < manual(st).length; i++) if (dtab(manual(st)[i]) == z) (manual(st)[i], i)];
List<int> labelOrder(J st) => [for (final z in dz) ...zoneDamages(st, z).map((e) => e.$2)];
List<int> unlabelledOrder(J st) => labelOrder(st).where((i) => !dmgDone(manual(st)[i], fuelOf(st))).toList();
// the next photo to label: this tab's first, then the first one still to label (a tab opens only when the ones before it are done)
int nextUnlabelled(J st, int from) {
  final o = labelOrder(st), p = o.indexOf(from), z = from >= 0 && from < manual(st).length ? dtab(manual(st)[from]) : null;
  for (var j = 1; j <= o.length; j++) {
    final i = o[(p + j + o.length) % o.length];
    if (!dmgDone(manual(st)[i], fuelOf(st)) && dtab(manual(st)[i]) == z) return i;
  }
  return unlabelledOrder(st).firstOrNull ?? -1;
}

// how far a strip opens: up to the first unfinished tab, and never short of the current one
int openTo(List<bool> done, int cur) {
  final f = done.indexOf(false);
  return f < 0 ? done.length - 1 : (f > cur ? f : cur);
}

// as the condition report words it: the Which/Where answer, or the side of a sided place, in brackets ("Mirror: Damaged (left), Minor")
String dmgLine(J d) {
  final ex = (d['ex'] ?? '') != '' ? d['ex'] as String : needsSide(d) ? (d['side'] ?? '') as String : '';
  return '${d['panel']}: ${dshort(d['panel'], d['type'])}${ex != '' && ex != d['panel'] ? ' (${ex.toLowerCase()})' : ''}, ${d['sev']}${(d['size'] ?? '') != '' ? ', ${d['size']} in' : ''}';
}

// picking a place: the type must belong to it; a single choice is picked for you
// Exterior places that are on both sides of the car: the damage also keeps which one (side), picked on the car map
const sidedPlaces = {'Mirror', 'Headlight', 'Tail light'};
bool needsSide(J d) => (d['zone'] ?? 'Exterior') == 'Exterior' && sidedPlaces.contains(d['panel']);
// 'Left mirror' -> ('Mirror', 'Left'); any other place name stays as it is, with no side
(String, String?) placeSide(String key) {
  final m = RegExp(r'^(Left|Right) (mirror|headlight|tail light)$').firstMatch(key);
  return m == null ? (key, null) : ('${m[2]![0].toUpperCase()}${m[2]!.substring(1)}', m[1]);
}

// the place as the car map names it: 'Left mirror' for a sided place with its side, else the place
String panelName(J d) => needsSide(d) && (d['side'] ?? '') != '' ? '${d['side']} ${(d['panel'] as String).toLowerCase()}' : (d['panel'] ?? '') as String;

void setLabel(J d, String f, String v, String fuel) {
  d['ai'] = false;
  if (f != 'panel') {
    d[f] = v;
    return;
  }
  // a car-map part on one side ('Left headlight'): the place and that side; another place drops the side
  final ps = placeSide(v);
  if (ps.$2 != null) {
    d['side'] = ps.$2;
  } else if (!(sidedPlaces.contains(ps.$1) && d['panel'] == ps.$1)) {
    d.remove('side');
  }
  v = ps.$1;
  if (RegExp(r'^(Left|Right) (front|rear) wheel$').hasMatch(v)) d['zone'] = 'Tires';
  if (d['panel'] == v) return;
  d['panel'] = v;
  final pl = placeOf(d['zone'] ?? 'Exterior', v), ts = placeOpts(pl, fuel);
  if (!ts.contains(d['type'])) d['type'] = ts.length == 1 ? ts[0] : '';
  if (pl == null || pl['ex'] != true || (d['ex'] != null && !strs(pl['exo']).contains(d['ex']))) d.remove('ex');
  if (pl != null && pl['fix'] == true) d['ex'] = strs(pl['exo'])[0];
}

// what the labelled photos say: a problem on a check (p), its second step (x), or a sunroof/navigation answer (f)
List<J> dmgDerived(J st) {
  final out = <J>[], seen = <String>{}, fuel = fuelOf(st);
  for (final d in manual(st)) {
    for (final e in dmgDerivedOf(d, fuel)) {
      if (seen.add(dkey(e))) out.add(e);
    }
  }
  return out;
}

// what one damage photo answers on the checks: a problem ('p'), its Which/Where ('x'), a feature not working ('f'); nothing for its own damage
List<J> dmgDerivedOf(J d, String fuel) {
  final pl = placeOf(d['zone'] ?? 'Exterior', d['panel']);
  if (pl == null || (d['type'] ?? '') == '' || !placeOpts(pl, fuel).contains(d['type'])) return const [];
  final tw = twinOf(pl, d['type'], fuel);
  if (tw != null) {
    return [
      {'t': 'p', 'id': tw['ck'], 'w': null, 'v': d['type']},
      {'t': 'x', 'id': tw['ck'], 'w': null, 'v': strs(tw['exo'])[0]},
    ];
  }
  if (isStruct(pl, d['type'])) return [{'t': 'p', 'id': 'ck_structure', 'w': null, 'v': pl['st']}];
  if (pl['ck'] != null && !fuelOk(byId[pl['ck']]?['cars'] ?? 'all', fuel)) return const [];
  if (pl['feat'] != null) return [{'t': 'f', 'id': pl['feat'], 'v': 'Not working'}];
  if (pl['ck'] == null) return const [];
  return [
    {'t': 'p', 'id': pl['ck'], 'w': pl['w'], 'v': d['type']},
    if (pl['ex'] == true && (d['ex'] ?? '') != '') {'t': 'x', 'id': pl['ck'], 'w': pl['w'], 'v': d['ex']},
  ];
}

// the damage photos behind a check problem (or a feature not working): the ones whose answer it is
List<String> dmgPhotos(J st, String t, String id, String? w, String v) {
  final fuel = fuelOf(st);
  return [
    for (final d in manual(st))
      if ((d['f'] ?? '') != '' && dmgDerivedOf(d, fuel).any((e) => e['t'] == t && e['id'] == id && (e['w'] ?? '') == (w ?? '') && e['v'] == v)) d['f'] as String,
  ];
}

String dkey(J d) => '${d['t']}|${d['w'] ?? ''}|${d['id']}|${d['v']}';
List<String> dmgVals(J st, String id, String? w, [String t = 'p']) =>
    dmgDerived(st).where((d) => d['t'] == t && d['id'] == id && (d['w'] ?? '') == (w ?? '')).map((d) => d['v'] as String).toList();
List<String> dmgList(J st, J d) => lst(d['w'] != null ? tire(st, d['w']) : st, d['t'] == 'x' ? 'extra' : 'probs', d['id']);

// keeps the checks in step with the photos: adds what a photo says, takes back only what it added itself
void syncDamages(J st) {
  final prev = (st['dprev'] as List? ?? []).cast<J>(), now = dmgDerived(st), nk = {for (final d in now) dkey(d)}, pk = {for (final d in prev) dkey(d): d}, rec = <J>[];
  final feat = m(st, 'feat');
  for (final d in prev) {
    if (nk.contains(dkey(d))) continue;
    if (d['t'] == 'f') {
      if (feat[d['id']] == 'Not working') feat[d['id']] = d['was'] ?? '';
      continue;
    }
    dmgList(st, d).remove(d['v']);
  }
  for (final d in now) {
    final p = pk[dkey(d)];
    if (d['t'] == 'f') {
      if (feat[d['id']] == 'Not working') {
        if (p != null) rec.add(p);
        continue;
      }
      d['was'] = p != null ? p['was'] : (feat[d['id']] ?? '');
      feat[d['id']] = 'Not working';
      rec.add(d);
      continue;
    }
    final a = dmgList(st, d);
    if (a.contains(d['v'])) {
      if (p != null) rec.add(p);
      continue;
    }
    a.add(d['v']);
    rec.add(d);
  }
  st['dprev'] = rec;
}

// true when a labelled damage photo sets no check or feature: it is listed on its own
bool dmgOwn(J st, J d) {
  final fuel = fuelOf(st);
  var pl = placeOf(d['zone'] ?? 'Exterior', d['panel']);
  if (pl == null || (d['type'] ?? '') == '' || !placeOpts(pl, fuel).contains(d['type'])) return true;
  pl = effPlace(pl, d['type'], fuel)!;
  if (isStruct(pl, d['type']) || pl['feat'] != null) return false;
  return pl['ck'] == null || !fuelOk(byId[pl['ck']]?['cars'] ?? 'all', fuel);
}

int dmgOwnProbs(J st, String k, List<String> ids) {
  final fuel = fuelOf(st);
  return zoneDamages(st, k).where((e) {
    var pl = placeOf(e.$1['zone'] ?? 'Exterior', e.$1['panel']);
    if (pl == null || (e.$1['type'] ?? '') == '' || !placeOpts(pl, fuel).contains(e.$1['type'])) return true;
    pl = effPlace(pl, e.$1['type'], fuel)!;
    if (isStruct(pl, e.$1['type'])) return !ids.contains('ck_structure');
    if (pl['ck'] != null && !fuelOk(byId[pl['ck']]?['cars'] ?? 'all', fuel)) return true;
    if (pl['feat'] != null) return k != 'Interior';
    return pl['ck'] == null || !ids.contains(pl['ck']);
  }).length;
}

// ---------- Review and Summary gates ----------
List<J> featMissingList(J st) => featq.where((q) => (m(st, 'feat')[q[0]] ?? '') == '').map((q) => {'id': q[0]}).toList();
int featMissing(J st) => featMissingList(st).length;
int keysMissing(J st) => m(st, 'vals')['keys_n'] == null ? 1 : 0;
int tmMissing(J st) => byId['tires_match'] != null && (m(st, 'vals')['tires_match'] ?? '') == '' ? 1 : 0;

// All 4 tires match, answered by the AI once the four whole-tire photos are read (docs/11): the same brand and the same model on all
// four is Match, a different brand or model Mismatch; size does not count. Left for the inspector while a brand, or a model of four
// tires of one brand, cannot be read. Never over the inspector's own pick (tm_auto 0); a later reading updates the AI's answer.
String _tw(Object? v) => '${v ?? ''}'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''); // case, spaces and dashes do not count
void tiresMatchSync(J st) {
  final vals = m(st, 'vals');
  if (byId['tires_match'] == null || ((vals['tires_match'] ?? '') != '' && vals['tm_auto'] != 1)) return;
  final rd = [for (final w in wheels) m(tire(st, w[0]), 'read')];
  if (rd.any((r) => _tw(r['brand']) == '')) return;
  final String v;
  if (rd.any((r) => _tw(r['brand']) != _tw(rd[0]['brand']))) {
    v = 'Mismatch';
  } else if (rd.any((r) => _tw(r['model']) == '')) {
    return;
  } else {
    v = rd.every((r) => _tw(r['model']) == _tw(rd[0]['model'])) ? 'Match' : 'Mismatch';
  }
  vals['tires_match'] = v;
  vals['tm_auto'] = 1;
}
bool idReady(J st) => vinCheck((m(st, 'vals')['vin_read'] ?? '') as String) && (m(st, 'vals')['odo_read'] ?? '') != ''; // the CR refuses a VIN that fails the check digit

class SecInfo {
  final int miss, unl, fqm, probs;
  final List<String> tdm;
  SecInfo(this.miss, this.unl, this.fqm, this.probs, this.tdm);
}

List<String> ckIdsOf(String k, J st) => k == 'Tires' ? ['ck_tire', 'ck_wheel'] : k == 'Paint' ? ['ck_paint'] : k == 'start' ? [] : stepItems(k, st).checks.map((it) => it['id'] as String).toList();

SecInfo secInfo(J st, String k) {
  final cc = revCount(st, k), miss = cc[1] - cc[0], fuel = fuelOf(st);
  var probs = 0;
  if (k == 'Tires') {
    for (final w in wheels) {
      probs += lst(tire(st, w[0]), 'probs', 'ck_tire').length + lst(tire(st, w[0]), 'probs', 'ck_wheel').length;
    }
    if (m(st, 'vals')['tires_match'] == 'Mismatch') probs++;
  } else if (k == 'Paint') {
    probs += lst(st, 'probs', 'ck_paint').length;
  } else if (k != 'start') {
    if (k == 'Interior') probs += featq.where((q) => m(st, 'feat')[q[0]] == 'Not working').length;
    for (final it in stepItems(k, st).checks) {
      probs += lst(st, 'probs', it['id']).length;
    }
  }
  final isZone = zoneTitle.containsKey(k);
  // Mechanicals and Underbody count a damage once: on the page with its check, or as its own problem
  if (isZone) probs += dmgOwnProbs(st, k, k == 'Mechanicals' || k == 'Underbody' ? [...ckIdsOf('Mechanicals', st), ...ckIdsOf('Underbody', st)] : ckIdsOf(k, st));
  final unl = isZone ? zoneDamages(st, k).where((e) => !dmgDone(e.$1, fuel)).length : 0;
  final tdm = k == 'Tires' ? [for (final w in wheels) if (tire(st, w[0])['tread'] == '') w[1]] : <String>[];
  final fqm = k == 'Interior' ? keysMissing(st) + featMissing(st) : k == 'Tires' ? tmMissing(st) + tdm.length : 0;
  return SecInfo(miss, unl, fqm, probs, tdm);
}

String pageBlock(J st, String k) {
  if (k == 'start') {
    if ((st['owner'] ?? '') == '') return 'Answer the owner question';
    if (st['owner'] == 'No') return 'End the visit';
  }
  final f = secInfo(st, k);
  if (f.miss > 0) return '${f.miss} left to take';
  if (f.unl > 0) return 'Label ${f.unl} damage photo${f.unl > 1 ? 's' : ''}';
  if (f.tdm.isNotEmpty) return 'Pick the tread depth: ${f.tdm.join(', ')}';
  if (f.fqm > 0) return k == 'Tires' ? 'Answer: do the 4 tires match?' : keysMissing(st) > 0 ? 'Pick the number of keys' : 'Answer sunroof and navigation';
  if (k == 'Paint' && paintMissing(st).isNotEmpty) return 'Add the paint reading: ${paintMissing(st).join(', ')}';
  return '';
}

List<String> sumUnconfirmed(J st) => capseq.where((k) => m(st, 'sok')[k] != true).toList();

String sumBlock(J st) {
  final fuel = fuelOf(st), left = capLeft(st), unl = manual(st).where((d) => !dmgDone(d, fuel)).length;
  if ((st['owner'] ?? '') == '' || st['owner'] == 'No') return 'Answer the owner question in Start';
  if (left > 0) return '$left left to take';
  if (unl > 0) return 'Label $unl damage photo${unl > 1 ? 's' : ''}';
  if (wheels.any((x) => tire(st, x[0])['tread'] == '')) return 'Pick the tread depth for every tire';
  if (tmMissing(st) > 0) return 'Answer: do the 4 tires match?';
  if (keysMissing(st) > 0) return 'Pick the number of keys';
  if (featMissing(st) > 0) return 'Answer sunroof and navigation';
  if (paintMissing(st).isNotEmpty) return 'Add the paint reading: ${paintMissing(st).join(', ')}';
  final unc = sumUnconfirmed(st);
  if (unc.isNotEmpty) return 'Review ${unc.length} more section${unc.length > 1 ? 's' : ''}';
  final vin = (m(st, 'vals')['vin_read'] ?? '') as String;
  if (vin.length == 17 && !vinCheck(vin)) return RegExp(r'^[A-HJ-NPR-Z0-9]{17}$').hasMatch(vin) ? 'Fix the VIN: the check digit is wrong' : 'Fix the VIN: no I, O, Q or spaces';
  if (!idReady(st) || m(st, 'vals')['idconf'] != true) return 'Confirm the VIN and mileage';
  if ((st['overall'] ?? '') == '') return 'Pick the overall condition';
  return '';
}

// every problem with its level, for the Summary and the seller
List<J> problemsList(J st) {
  final out = <J>[];
  for (final k in capseq.sublist(1)) {
    if (k == 'Tires') {
      for (final w in wheels) {
        for (final id in ['ck_tire', 'ck_wheel']) {
          for (final p in lst(tire(st, w[0]), 'probs', id)) {
            out.add({'sec': k, 'text': '${id == 'ck_tire' ? 'Tire: ' : 'Wheel: '}$p', 'where': w[2], 'level': level(byId[id]!, p), 'ph': dmgVals(st, id, w[0]).contains(p), 'photos': dmgPhotos(st, 'p', id, w[0], p)});
          }
        }
      }
      if (m(st, 'vals')['tires_match'] == 'Mismatch') out.add({'sec': k, 'text': 'Tires do not match (brand or model)', 'where': stTitle('Tires'), 'level': level(byId['tires_match']!, 'Mismatch')});
      continue;
    }
    if (k == 'Paint') {
      for (final p in lst(st, 'probs', 'ck_paint')) {
        final ex = lst(st, 'extra', 'ck_paint').join(', ');
        out.add({'sec': k, 'text': '${byId['ck_paint']!['label']}: ${plain(p)}', 'where': 'Paint${ex.isNotEmpty ? ' · $ex' : ''}', 'level': level(byId['ck_paint']!, p), 'ph': dmgVals(st, 'ck_paint', null).contains(p), 'photos': dmgPhotos(st, 'p', 'ck_paint', null, p)});
      }
      continue;
    }
    if (k == 'Interior') {
      for (final q in featq) {
        if (m(st, 'feat')[q[0]] == 'Not working') out.add({'sec': k, 'text': '${q[1]}: Not working', 'where': k, 'level': level(byId[q[0]] ?? {}, 'Not working'), 'photos': dmgPhotos(st, 'f', q[0], null, 'Not working')});
      }
    }
    for (final it in stepItems(k, st).checks) {
      for (final p in lst(st, 'probs', it['id'])) {
        final ex = lst(st, 'extra', it['id']).join(', ');
        out.add({'sec': k, 'text': '${it['label']}: ${plain(p)}', 'where': '$k${ex.isNotEmpty ? ' · $ex' : ''}', 'level': level(it, p), 'ph': dmgVals(st, it['id'], null).contains(p), 'photos': dmgPhotos(st, 'p', it['id'], null, p)});
      }
    }
  }
  return out;
}

// what was found, section by section in Review order: its problems, then its damage photos that answer no check (each line is dmgLine)
List<(String, List<J>, List<J>)> findingsBySec(J st) {
  final pl = problemsList(st), fuel = fuelOf(st);
  return [
    for (final k in capseq.sublist(1))
      (k, pl.where((p) => p['sec'] == k).toList(), [for (final d in manual(st)) if (dtab(d) == k && labelled(d, fuel) && dmgOwn(st, d)) d]),
  ].where((g) => g.$2.isNotEmpty || g.$3.isNotEmpty).toList();
}

// a problem's place under its section heading: the section name in front is dropped ("Exterior · Hood" -> "Hood")
String whereIn(String k, String w) {
  for (final p in [stTitle(k), k]) {
    if (w == p) return '';
    if (w.startsWith('$p · ')) return w.substring(p.length + 3);
  }
  return w;
}

// counts for the Summary
J totals(J st) {
  var photos = 0, need = 0, videos = 0, vneed = 0, extra = 0;
  for (final k in camseq) {
    for (final x in capList(k, st)) {
      final opt = (x['it'] as J)['optional'] == true, has = capHas(st, x);
      if (opt && !has) continue;
      if ((x['it'] as J)['kind'] == 'video') {
        vneed++;
        if (has) videos++;
      } else {
        need++;
        if (has) photos++;
        if (has && isMulti(x['id'])) extra += ((m(st, 'multi')[x['id']] ?? []) as List).length - 1;
      }
    }
  }
  for (final a in m(st, 'multi').entries) {
    if ((a.key).startsWith('ph_mod_')) extra += (a.value as List).length;
  }
  extra += manual(st).length;
  final dl = [for (final d in manual(st)) if (labelled(d, fuelOf(st)) && dmgOwn(st, d)) dmgLine(d)];
  return {'photos': photos, 'need': need, 'extra': extra, 'videos': videos, 'vneed': vneed, 'dlist': dl};
}
