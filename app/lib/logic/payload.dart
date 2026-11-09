// The record sent after the seller signs: port of the mockup's inspectionPayload(), same shape as samples/inspection-*.json.
import '../data/ql.dart';
import 'insp.dart';

class Payload {
  final J record;
  final Map<String, String> files; // upload name -> local path (relative to the app documents folder)
  Payload(this.record, this.files);
}

int? _int(dynamic v) => v == null || v == '' ? null : int.tryParse('$v');
num? _num(dynamic v) => v == null || v == '' ? null : num.tryParse('$v');

Payload inspectionPayload(J st) {
  final fuel = fuelOf(st), photos = <J>[], files = <String, String>{}, car = st['car'] as J, vals = m(st, 'vals'), fl = m(st, 'files'), turn = m(st, 'turn');
  String src(dynamic v) => v == 'library' ? 'upload' : 'camera';
  String fname(J e) => '${[e['question_id'], e['wheel'], e['panel'], e['n']].where((x) => x != null && x != '').join('-').toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]+'), '-')}.jpg';
  void put(J e, String? local) {
    if (e['skipped'] != true) {
      e['file'] = fname(e);
      e['upright_turn_deg'] = turn[local] ?? 0;
      if (local != null) files[e['file']] = local;
    }
    photos.add(e);
  }

  for (final k in capseq) {
    for (final x in capList(k, st)) {
      final id = x['id'] as String;
      if (id.startsWith('video_')) continue;
      final e = <String, dynamic>{'section': k == 'start' ? 'Start' : id == 'paint' ? 'Paint' : (byId[id]?['section'] ?? k), 'question_id': id};
      if (x['wheel'] != null) e['wheel'] = x['wheel'];
      if (x['panel'] != null) e['panel'] = pn(x['panel']);
      if (isMulti(id)) {
        final a = (m(st, 'multi')[id] ?? []) as List;
        for (var j = 0; j < a.length; j++) {
          put({...e, 'n': j + 1, 'source': src(a[j]['src']), if (a[j]['panel'] != null) 'panel': pn(a[j]['panel'])}, a[j]['f']);
        }
        continue;
      }
      if (!capHas(st, x)) {
        if (m(st, 'skip')[id] == true) put({...e, 'skipped': true}, null);
        continue;
      }
      e['source'] = x['panel'] != null ? src((m(st, 'paint')[x['panel']] as J?)?['src']) : src(m(st, 'src')[id]);
      put(e, fl[x['panel'] != null ? 'paint:${x['panel']}' : x['wheel'] != null ? '$id-${x['wheel']}' : id]);
    }
  }
  const modsec = {'ph_mod_ext': 'Exterior', 'ph_mod_int': 'Interior', 'ph_mod_mech': 'Mechanicals'};
  modsec.forEach((id, sec) {
    final a = (m(st, 'multi')[id] ?? []) as List;
    for (var j = 0; j < a.length; j++) {
      put({'section': sec, 'question_id': id, 'n': j + 1, 'source': src(a[j]['src']), 'modification': true}, a[j]['f']);
    }
  });

  final checks = <J>[];
  for (final it in items) {
    if (it['kind'] != 'check' || !fuelOk(it['cars'], fuel)) continue;
    final ws = it['id'] == 'ck_tire' || it['id'] == 'ck_wheel' ? wheels.map((w) => w[0]) : [''];
    for (final w in ws) {
      final sv = w != '' ? tire(st, w) : st, pr = lst(sv, 'probs', it['id']), ex = lst(sv, 'extra', it['id']), ph = dmgVals(st, it['id'], w == '' ? null : w);
      final e = <String, dynamic>{'id': it['id'], 'result': pr.isNotEmpty ? 'Problem' : it['id'] == 'ck_road' && vals['road_done'] != true ? 'Not done' : 'OK'};
      if (w != '') e['wheel'] = w;
      if (pr.isNotEmpty) e['problems'] = [for (final o in pr) {'option': o, 'level': level(it, o), 'from_damage_photo': ph.contains(o)}];
      if (ex.isNotEmpty) e['where'] = ex;
      if (it['id'] == 'ck_scan' && (st['codes'] ?? '') != '') e['codes'] = st['codes'];
      checks.add(e);
    }
  }

  final damages = <J>[];
  final man = manual(st);
  for (var j = 0; j < man.length; j++) {
    final d = man[j], pl0 = placeOf(d['zone'] ?? 'Exterior', d['panel']), tw = twinOf(pl0, d['type'], fuel), pl = tw ?? pl0;
    final e = <String, dynamic>{
      'n': j + 1, 'section': tw != null ? 'Paint' : dmgSec(d['zone'], d['panel']), 'place': tw != null ? tw['p'] : d['panel'] ?? '', 'type': d['type'] ?? '', 'severity': d['sev'] ?? '',
      'size_in': (d['zone'] ?? 'Exterior') == 'Exterior' ? _num(d['size']) : null, 'source': src(d['src']), 'taken_in': d['sec'] ?? '', 'file': 'damage-${j + 1}.jpg', 'upright_turn_deg': turn[d['f']] ?? 0,
    };
    if (d['f'] != null) files[e['file']] = d['f'];
    if ((d['ex'] ?? '') != '') e['where'] = d['ex'];
    if ((d['ex'] ?? '') == '' && tw == null && needsSide(d) && (d['side'] ?? '') != '') e['where'] = d['side']; // Left or Right: which mirror, headlight or tail light
    if (tw != null) e['where'] = strs(tw['exo'])[0];
    if (pl != null && (d['type'] ?? '') != '') {
      if (isStruct(pl, d['type'])) {
        e['check_id'] = 'ck_structure';
        e['check_option'] = pl['st'];
      } else if (pl['ck'] != null) {
        e['check_id'] = pl['ck'];
        e['check_option'] = d['type'];
      } else if (pl['feat'] != null) {
        e['feature'] = pl['feat'];
        e['feature_answer'] = 'Not working';
      }
    }
    e['ai_first_guess'] = d['aiWas'];
    e['confirmed'] = dmgDone(d, fuel);
    damages.add(e);
  }

  final tires = [
    for (final w in wheels)
      () {
        final t = tire(st, w[0]), r = m(t, 'read');
        return {'wheel': w[0], 'tread_32nds': _int(t['tread']), 'tread_read_from_photo': t['treadAuto'] == true, 'brand': (r['brand'] ?? '') == '' ? null : r['brand'], 'size': (r['size'] ?? '') == '' ? null : r['size'], 'read_from_photo': r['auto'] == true};
      }()
  ];
  final paint = [
    for (final x in paintPanels)
      () {
        final r = (m(st, 'paint')[x[1]] as J?) ?? {};
        return {'panel': pn(x[1]), 'mils': r['na'] == true ? null : _num(r['v']), 'not_on_car': r['na'] == true, 'high': paintHigh(r), 'read_from_photo': r['auto'] == true};
      }()
  ];

  // private documents, the signature and the 360 frames are uploaded too
  for (final d in ['ph_license', 'ph_reg', 'ph_family']) {
    if (fl[d] != null) files['$d.jpg'] = fl[d];
  }
  if (fl['signature'] != null) files['signature.png'] = fl['signature'];
  final videos = <J>[];
  for (final id in ['video_360', 'video_engine', 'video_exhaust']) {
    if (m(st, 'shots')[id] != true || fl[id] == null) continue;
    final local = fl[id] as String, ext = local.contains('.') ? local.substring(local.lastIndexOf('.')).toLowerCase() : '.mp4';
    videos.add({'question_id': id, 'file': '$id$ext', 'max_seconds': vmax[id]});
    files['$id$ext'] = local;
  }
  final spin = (st['spin'] as List?)?.cast<String>() ?? const [];
  for (var i = 0; i < spin.length; i++) {
    files['spin-${'${i + 1}'.padLeft(2, '0')}.jpg'] = spin[i];
  }

  final feat = m(st, 'feat');
  final record = <String, dynamic>{
    'source': {'system': 'bidbus_field', 'listing_id': st['id'], 'inspector': st['inspector'] ?? '', 'started': st['start'], 'ended': st['end']},
    'vehicle': {
      'vin_listing': (car['vin'] ?? '') == '' ? null : car['vin'], 'vin_read': (vals['vin_read'] ?? '') == '' ? null : vals['vin_read'], 'vin_door_jamb_read': vals['vin_scan'] == 1 || vals['vin_scan'] == true,
      'mileage_listing': _int(car['mileage']), 'mileage_read': _int(vals['odo_read']), 'vin_mileage_confirmed': vals['idconf'] == true,
      'keys_count': _int(vals['keys_n']), 'keys_count_read_from_photo': vals['keys_auto'] == 1 || vals['keys_auto'] == true, 'fuel': fuel, 'ev_battery_health_pct': _int(vals['ev_soh']),
    },
    'owner_check': st['owner'],
    'documents': {
      'license': fl['ph_license'] != null ? 'taken on site' : null, 'registration': fl['ph_reg'] != null ? 'taken on site' : null,
      'family_proof': st['owner'] == 'Family, with proof' && fl['ph_family'] != null ? 'taken on site' : null,
    },
    'photos': photos, 'videos': videos, 'spin_frames': m(st, 'shots')['video_360'] == true ? 36 : 0,
    'checks': checks, 'tires': tires, 'tires_match': (vals['tires_match'] ?? '') == '' ? null : vals['tires_match'], 'paint': paint,
    'features': {'sunroof': (feat['sunroof'] ?? '') == '' ? null : feat['sunroof'], 'navigation': (feat['navigation'] ?? '') == '' ? null : feat['navigation']},
    'damages': damages, 'overall_condition': (st['overall'] ?? '') == '' ? null : st['overall'], 'inspector_note': st['note'] ?? '',
    'signature': {'seller_name': st['signName'] ?? '', 'agreed': st['agree'] == true, 'signed': st['signed'] == true}, // when and where: source.ended
  };
  return Payload(record, files);
}
