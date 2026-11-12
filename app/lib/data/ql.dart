// Question list (assets/question-list.json) and the lists the app derives from it.
// Ported from the mockup (reference/mockup-1109/src/template.html); never hardcode questions.
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

typedef J = Map<String, dynamic>;

late J ql;
late List<J> items;
late Map<String, J> byId;
late Map<String, List<J>> dplaces;

Future<void> loadQl() async => initQl(jsonDecode(await rootBundle.loadString('assets/question-list.json')));

void initQl(J q) {
  ql = q;
  items = (q['items'] as List).cast<J>();
  byId = {for (final it in items) it['id'] as String: it};
  final secs = (q['damage_places']['sections'] as Map).cast<String, dynamic>();
  dplaces = secs.map((z, l) => MapEntry(z, (l as List).cast<J>().map((x) {
        final ex = x['extra'] as J?;
        final p = <String, dynamic>{
          'p': x['place'], 'ck': x['check'], 'opts': (x['options'] as List).cast<String>(), 'w': x['wheel'], 'feat': x['feature'],
          'exo': ex == null ? null : (ex['options'] as List).cast<String>(), 'exl': ex?['label'] ?? '', 'ex': ex != null,
          'types': x['check'] != null || x['feature'] != null ? null : (x['options'] as List).cast<String>(),
          'st': (x['structure'] as J?)?['option'],
        };
        p['fix'] = p['ex'] == true && (p['exo'] as List).length == 1;
        return p;
      }).toList()));
  // an Exterior body panel also offers that panel's Paint problems (stored as Paint)
  for (final x in dplaces['Exterior'] ?? <J>[]) {
    final tw = placeOf('Paint', x['p'] == 'Hood' ? 'Hood or frunk lid' : x['p']);
    if (tw != null && x['ck'] == null && x['feat'] == null) x['tw'] = tw;
  }
}

List<String> strs(dynamic l) => (l as List? ?? const []).cast<String>();

const fuels = ['Gas or diesel', 'Hybrid', 'Plug-in hybrid', 'Electric (EV)'];
// what New inspection offers: Gas and Diesel are picked apart and both use the 'Gas or diesel' items
const fuelChoices = ['Gas', 'Diesel', 'Hybrid', 'Plug-in hybrid', 'Electric (EV)'];
// local time with its UTC offset (2026-11-07T21:28:12-08:00): the server can place it in time and still show the phone's clock
String nowIso() {
  final n = DateTime.now(), o = n.timeZoneOffset.inMinutes.abs();
  return '${n.toIso8601String().split('.').first}${n.timeZoneOffset.isNegative ? '-' : '+'}${'${o ~/ 60}'.padLeft(2, '0')}:${'${o % 60}'.padLeft(2, '0')}';
}

String fuelGroup(String choice) => choice == 'Gas' || choice == 'Diesel' ? 'Gas or diesel' : choice;
const ev = 'Electric (EV)';

bool fuelOk(String? cars, String fuel) {
  final isEv = fuel == ev, hy = fuel == 'Hybrid' || fuel == 'Plug-in hybrid';
  switch (cars) {
    case 'gas':
      return !isEv;
    case 'ev':
      return isEv;
    case 'hybrid':
      return hy;
    case 'plugin':
      return isEv || fuel == 'Plug-in hybrid';
  }
  return true;
}

const gasOnlyOpts = ['Engine oil low or dark', 'Engine oil very low or dry', 'Milky oil, metal or sludge', 'Oil or metal in the coolant', 'Engine hesitates or misfires', 'Transmission delayed, slips or harsh', 'Check engine', 'Oil, temperature or transmission'];
const featDrop = {'Sunroof not working', 'Navigation not working'};

List<String> optsFor(J it, String fuel) {
  final oc = it['option_cars'] as J?;
  return strs(it['options']).where((o) {
    if (it['id'] == 'ck_features' && featDrop.contains(o)) return false;
    if (oc != null && oc[o] != null) return fuelOk(oc[o], fuel);
    return fuel == ev ? !gasOnlyOpts.contains(o) : !o.startsWith('EV: ');
  }).toList();
}

String level(J it, String o) => ((it['levels'] as J?) ?? {})[o] ?? 'Disclosed';
bool isRedLevel(String l) => l.contains('Red') || l.contains('Ends') || l.contains('Not listed');

// wheels, left front then counter-clockwise
const wheels = [['lf', 'LF', 'Left front'], ['lr', 'LR', 'Left rear'], ['rr', 'RR', 'Right rear'], ['rf', 'RF', 'Right front']];
String wheelName(String? w) => wheels.firstWhere((x) => x[0] == w, orElse: () => ['', '', ''])[2];
List<String> get tireShots => items.where((it) => it['section'] == 'Tires' && it['kind'] == 'photo').map((it) => it['id'] as String).toList();

// paint readings: one per panel, left front counter-clockwise, then hood and roof
const paintPanels = [
  ['Left', 'Left front fender'], ['Left', 'Left front door'], ['Left', 'Left rear door'], ['Left', 'Left quarter panel'], ['Rear', 'Trunk or liftgate'],
  ['Right', 'Right quarter panel'], ['Right', 'Right rear door'], ['Right', 'Right front door'], ['Right', 'Right front fender'], ['Front', 'Hood'], ['Top', 'Roof'],
];
const paintHighMils = 8.0;
const paintOpt = 'Panel repainted (the meter reads high)';
String pn(String p) => p == 'Hood' ? 'Hood or frunk lid' : p;

const extra = {
  'ck_paint': ['Which panel', ['Left front fender', 'Left front door', 'Left rear door', 'Left quarter panel', 'Trunk or liftgate', 'Right quarter panel', 'Right rear door', 'Right front door', 'Right front fender', 'Hood or frunk lid', 'Roof']],
  'ck_leaks': ['Where', ['Engine', 'Transmission', 'Differential or transfer case', 'Steering', 'A/C', 'Cooling', 'Drive unit', 'Under the front covers']],
  'ck_brakes': ['Which wheel', ['Left front', 'Left rear', 'Right rear', 'Right front']],
};

// each shot's home section: the Review page it shows on (the camera takes some of them in another pass, see camLayout)
const layout = {
  'Exterior': ['video_360', 'ph_ext_roof', 'ph_vin_dash', 'ph_mod_ext'],
  'Interior': ['ph_vin_door', 'ph_odo', 'ph_keys', 'ph_int_dash', 'ph_int_screen', 'ph_int_front', 'ph_int_rear', 'ph_int_cargo', 'ph_mod_int'],
  'OBDII': ['ph_obd_current', 'ph_obd_past', 'ph_obd_emission', 'ph_obd_other', 'ph_ev_alerts', 'ph_ev_battery', 'ph_ev_charging'],
  'Mechanicals': ['ph_engine_bay', 'ph_engine_oil', 'ph_frunk', 'ph_ev_port', 'video_engine', 'video_exhaust', 'ph_mod_mech'],
  'Underbody': ['ph_under_lf', 'ph_under_lm', 'ph_under_lr', 'ph_under_rear', 'ph_under_rr', 'ph_under_rm', 'ph_under_rf', 'ph_under_front', 'ph_under_cats', 'ph_under_pack'],
};
const msec = {'vin_scan': 'Interior', 'ck_ids': 'Interior', 'ck_keys': 'Interior', 'ck_equip': 'Interior', 'ck_account': 'Interior'};
String secOf(J it) => msec[it['id']] ?? it['section'];
// sections of Review (Underbody last, so saved page indexes stay)
const capseq = ['start', 'Exterior', 'Tires', 'Paint', 'Interior', 'OBDII', 'Mechanicals', 'Underbody'];
// the camera pass (docs/11-camera-flow-1109.md): windshield VIN and the 360 video, Interior with the OBDII screens at its end,
// one walk round the car (key 'Tires', shown as Walk-around), Mechanicals, Underbody
const camseq = ['Exterior', 'Interior', 'Tires', 'Mechanicals', 'Underbody'];
const camseq0 = ['Exterior', 'Tires', 'Interior', 'OBDII', 'Mechanicals', 'Underbody']; // the pass before 1109 (saved shot indexes point into it)
const camLayout = {
  'Exterior': ['ph_vin_dash', 'video_360'],
  'Interior': ['ph_vin_door', 'ph_int_front', 'ph_int_rear', 'ph_odo', 'video_engine', 'ph_keys', 'ph_int_dash', 'ph_int_screen', 'ph_obd_current', 'ph_obd_past', 'ph_obd_emission', 'ph_obd_other', 'ph_ev_alerts', 'ph_ev_battery', 'ph_ev_charging'],
  'OBDII': ['ph_obd_current', 'ph_obd_past', 'ph_obd_emission', 'ph_obd_other', 'ph_ev_alerts', 'ph_ev_battery', 'ph_ev_charging'], // opened from Review only
  'Mechanicals': ['ph_engine_bay', 'ph_engine_oil', 'ph_frunk', 'ph_ev_port', 'video_exhaust'],
  'Underbody': ['ph_under_lf', 'ph_under_lm', 'ph_under_lr', 'ph_under_rear', 'ph_under_rr', 'ph_under_rm', 'ph_under_rf', 'ph_under_front', 'ph_under_cats', 'ph_under_pack'],
};
// the walk-around, from the left front counter-clockwise: paint panel (p), tire and tread gauge (w), other shot (i)
const walk = [
  ['p', 'Left front fender'], ['w', 'lf'], ['p', 'Left front door'], ['p', 'Left rear door'], ['w', 'lr'], ['p', 'Left quarter panel'], ['p', 'Trunk or liftgate'], ['i', 'ph_int_cargo'],
  ['p', 'Right quarter panel'], ['w', 'rr'], ['p', 'Right rear door'], ['p', 'Right front door'], ['w', 'rf'], ['p', 'Right front fender'], ['p', 'Hood'], ['p', 'Roof'], ['i', 'ph_ext_roof'],
];
String stTitle(String k) => const {'start': 'Start', 'Tires': 'Tires & Wheels'}[k] ?? k;
String camTitle(String k) => k == 'Tires' ? 'Walk-around' : stTitle(k);
// the camera's title on a shot: Scanner Result on the OBDII scanner shots, else its section
String shotTitle(J? x, String k) => '${x?['id'] ?? ''}'.startsWith('ph_obd_') ? 'Scanner Result' : camTitle(k);
final homeSec = {for (final e in layout.entries) for (final id in e.value) id: e.key};
// the Review page a shot taken in camera section ck shows on; the zone a damage photo taken at it gets (a paint panel is Exterior)
String homeOf(J x, String ck) => x['panel'] != null ? 'Paint' : x['wheel'] != null ? 'Tires' : homeSec[x['id']] ?? ck;
String shotZone(J? x, String ck) {
  final h = x == null ? ck : homeOf(x, ck);
  return h == 'Paint' ? 'Exterior' : h;
}

// Look for: a few words top left of each guided shot, information only (docs/11)
const lookFor = {
  'ph_vin_dash': ['Clear photo', 'Full VIN visible'], 'video_360': ['Move smoothly'], 'ph_vin_door': ['VIN label', 'Jamb repaint', 'Spot welds'],
  'ph_int_front': ['Seats', 'Windows', 'Seat belts', 'Airbag covers'], 'ph_int_rear': ['Seats', 'Windows', 'Odor', 'Flood signs'],
  'ph_odo': ['Warning lights', 'Total miles', 'Dash cracks'], 'video_engine': ['Hard start', 'Knock', 'Rough idle', 'Smoke'], 'ph_keys': ['All keys', 'Key works'],
  'ph_int_dash': ['Dash cracks', 'A/C cold', 'Heat', 'Warning lights'], 'ph_int_screen': ['Screen', 'Audio', 'Cameras', 'Navigation'],
  'ph_obd_current': ['Engine codes'], 'ph_obd_past': ['Cleared codes'], 'ph_obd_emission': ['Not ready'], 'ph_obd_other': ['Airbag faults', 'ABS faults'],
  'Left front fender': ['Repaint', 'Fender bolts', 'Panel gaps', 'Dents'], 'Right front fender': ['Repaint', 'Fender bolts', 'Panel gaps', 'Dents'],
  'Left front door': ['Frame damage', 'Repaint', 'A-pillar', 'Window'], 'Right front door': ['Frame damage', 'Repaint', 'A-pillar', 'Window'],
  'Left rear door': ['Frame damage', 'Repaint', 'B-pillar', 'Window'], 'Right rear door': ['Frame damage', 'Repaint', 'B-pillar', 'Window'],
  'Left quarter panel': ['Repaint', 'Dents', 'Panel gaps', 'Fuel door'], 'Right quarter panel': ['Repaint', 'Dents', 'Panel gaps', 'Fuel door'],
  'Trunk or liftgate': ['Repaint', 'Tail lights', 'Panel gaps', 'Rear window'], 'Hood': ['Repaint', 'Hood bolts', 'Chips'], 'Roof': ['Repaint', 'Dents', 'Hail'],
  'ph_ext_roof': ['Dents', 'Hail', 'Sunroof'], 'tire_photo': ['Sidewall cracks', 'Bulge', 'Curb rash', 'Plug or patch'], 'tread_photo': ['Lowest groove', 'Uneven wear'],
  'ph_int_cargo': ['Trunk floor', 'Rails', 'Water', 'Spare tire'], 'ph_engine_bay': ['Aprons', 'Strut towers', 'Core support', 'Leaks'],
  'ph_engine_oil': ['Sludge', 'Milky oil', 'Oil level'], 'video_exhaust': ['Rev noise', 'Smoke', 'Reverse gear'], 'ph_frunk': ['Coolant', 'Water', 'Damage'],
  'ph_ev_port': ['Scorched pins', 'Latch'], 'ph_under_lf': ['Leaks', 'Rust', 'Frame rails', 'Kinks'], 'ph_under_lr': ['Leaks', 'Rust', 'Frame rails', 'Kinks'], 'ph_under_lm': ['Leaks', 'Rust', 'Frame rails', 'Kinks'], 'ph_under_rm': ['Leaks', 'Rust', 'Frame rails', 'Kinks'],
  'ph_under_rr': ['Leaks', 'Rust', 'Frame rails', 'Kinks'], 'ph_under_rf': ['Leaks', 'Rust', 'Frame rails', 'Kinks'], 'ph_under_rear': ['Rear rails', 'Exhaust', 'Leaks'],
  'ph_under_front': ['Core support', 'Subframe', 'Leaks'], 'ph_under_cats': ['Missing converter', 'Cut pipe'], 'ph_under_pack': ['Scrapes', 'Dents', 'Bolts'],
};
List<String>? lookOf(J? x) => x == null ? null : lookFor[x['panel'] ?? x['id']];

// end-of-section questions (docs/11): which camera sections ask, Mechanicals checks asked after another section instead
const askQ = {'Interior', 'Tires', 'Mechanicals', 'Underbody'};
const askMove = {'Tires': ['ck_brakes'], 'Underbody': ['ck_leaks', 'ck_exhaust', 'ck_susp', 'ck_cv']};
const askOut = {'ck_trans', 'ck_brakes', 'ck_exhaust', 'ck_susp', 'ck_cv'}; // not on the Mechanicals card (Leaks stays: asked twice, one answer)
const vmax = {'video_360': 60, 'video_engine': 30, 'video_exhaust': 30};
const short = {
  'video_360': 'Walk-around', 'video_engine': 'Engine sound', 'video_exhaust': 'Exhaust', 'ph_under_front': 'Underbody, front', 'ph_under_rear': 'Underbody, rear', 'ph_under_cats': 'Catalytic converters',
  'ph_int_dash': 'Dash', 'ph_int_screen': 'Infotainment', 'ph_int_front': 'Front seats', 'ph_int_rear': 'Rear seats', 'ph_int_cargo': 'Cargo, floor up', 'ph_engine_bay': 'Engine bay', 'ph_engine_oil': 'Engine oil, dipstick',
  'ph_frunk': 'Frunk and coolant', 'ph_ev_port': 'Charge port', 'ph_ev_battery': 'Battery health', 'ph_ev_charging': 'Charging rate', 'ph_ev_alerts': 'Service alerts', 'ph_vin_door': 'Door-jamb VIN', 'ph_vin_dash': 'Windshield VIN',
  'ph_odo': 'Odometer, car on', 'ph_keys': 'All keys', 'ph_license': "Driver's license", 'ph_reg': 'Registration card', 'ph_family': 'Family proof', 'ph_ext_roof': 'Roof', 'ph_under_lf': 'Underbody, left front', 'ph_under_lr': 'Underbody, left rear', 'ph_under_lm': 'Underbody, left middle', 'ph_under_rm': 'Underbody, right middle',
  'ph_under_rr': 'Underbody, right rear', 'ph_under_rf': 'Underbody, right front', 'ph_under_pack': 'Battery pack', 'ph_obd_current': 'Current codes', 'ph_obd_past': 'Past codes', 'ph_obd_emission': 'Emission codes', 'ph_obd_other': 'Other images',
  'ph_mod_ext': 'Modification', 'ph_mod_int': 'Modification', 'ph_mod_mech': 'Modification',
};
bool isMulti(String id) => byId[id]?['multi'] == true;
bool isLib(String id) => id == 'paint' || byId[id]?['upload'] == true;
const multiHint = {'ph_ev_battery': 'One photo per battery screen', 'ph_ev_charging': 'One photo per charging screen', 'ph_ev_alerts': 'One photo per alert screen'};

// damage and mod shutters
// Underbody damages are Mechanicals damages (the zone that holds their places) shown on their own tab
const dz = ['Exterior', 'Tires', 'Paint', 'Interior', 'Mechanicals', 'Underbody'];
const dzone = {'Exterior': 'Exterior', 'Tires': 'Tires', 'Interior': 'Interior', 'OBDII': 'Interior', 'Mechanicals': 'Mechanicals', 'Underbody': 'Mechanicals'};
const modslot = {'Exterior': 'ph_mod_ext', 'Paint': 'ph_mod_ext', 'Tires': 'ph_mod_ext', 'Interior': 'ph_mod_int', 'OBDII': 'ph_mod_int', 'Mechanicals': 'ph_mod_mech', 'Underbody': 'ph_mod_mech'};
const zoneTitle = {'Exterior': 'Exterior damages', 'Tires': 'Tire and wheel damages', 'Paint': 'Paint damages', 'Interior': 'Interior damages', 'Mechanicals': 'Mechanical damages', 'Underbody': 'Underbody damages'};
List<String> get dmgSev => strs(ql['damage_places']['severity']);
const structT = 'Structure';
const underTiles = ['Structure', 'Rust', 'Exhaust', 'Suspension', 'Driveshaft or CV', 'Brakes', 'Battery pack'];

J? placeOf(String z, String? p) {
  for (final x in dplaces[z] ?? <J>[]) {
    if (x['p'] == p) return x;
  }
  return null;
}

List<String> placeOpts0(J pl, String fuel) {
  if (pl['feat'] != null) return strs(pl['opts']);
  if (pl['ck'] == null) return strs(pl['types']);
  final it = byId[pl['ck']];
  if (it == null) return [];
  final o = strs(pl['opts']);
  return optsFor(it, fuel).where(o.contains).toList();
}

List<String> placeOpts(J? pl, String fuel) {
  if (pl == null) return [];
  var o = placeOpts0(pl, fuel);
  if (pl['st'] != null && !o.contains(structT)) o = [...o, structT];
  final tw = pl['tw'] as J?;
  return tw != null ? [...o, ...placeOpts0(tw, fuel).where((t) => !o.contains(t))] : o;
}

List<J> placesFor(String z, String fuel) => (dplaces[z] ?? <J>[]).where((pl) {
      if (pl['ck'] == null) return true;
      final it = byId[pl['ck']];
      return it != null && fuelOk(it['cars'], fuel) && placeOpts(pl, fuel).isNotEmpty;
    }).toList();

bool isStruct(J? pl, String? t) => pl != null && pl['st'] != null && t == structT;
J? twinOf(J? pl, String? t, String fuel) {
  final tw = pl?['tw'] as J?;
  return tw != null && t != null && t.isNotEmpty && placeOpts0(tw, fuel).contains(t) ? tw : null;
}

J? effPlace(J? pl, String? t, String fuel) => twinOf(pl, t, fuel) ?? pl;
bool underPlace(String? p) => underTiles.contains(p);
String dmgSec(String? z, String? p) => (z ?? 'Exterior') == 'Mechanicals' && underPlace(p) ? 'Underbody' : (z ?? 'Exterior');

// the problem without the place in front: Windshield + "Windshield crack" -> "Crack"
String dshort(String? place, String? type) {
  final t = type ?? '', p = (place ?? '').toLowerCase(), parts = p.split(' ');
  for (final c in [p, parts.last, parts.first]) {
    if (c.length > 2 && t.toLowerCase().startsWith('$c ')) {
      final r = t.substring(c.length + 1);
      if (!RegExp(r'^(or|and)\b').hasMatch(r)) return r[0].toUpperCase() + r.substring(1);
    }
  }
  return t;
}

String plain(String t) => t.replaceAll(RegExp(r'\s*\(type[^)]*\)'), '');

// sunroof and navigation, required on Review Interior
List<List<dynamic>> get featq => [
      ['sunroof', 'Sunroof', ['Works', 'Not working', 'No sunroof']],
      ['navigation', 'Navigation', ['Works', 'Not working', 'No navigation']],
    ].map((x) {
      final it = byId[x[0]];
      return [x[0], it?['label'] ?? x[1], it?['options'] != null ? strs(it!['options']) : x[2]];
    }).toList();
List<String> get overallOpts => strs(byId['overall_condition']?['options'] ?? ['Like new', 'Pretty great', 'Just okay', 'Kind of rough', 'Major issues']);

const chipLabel = {'ck_road': 'Road test (if needed)', 'ck_srs': 'Seat belts, airbags', 'ck_hv': 'High voltage, frunk'};

const tireBrands = ['Achilles', 'Atturo', 'BFGoodrich', 'Bridgestone', 'Continental', 'Cooper', 'Delinte', 'Dick Cepek', 'Dunlop', 'Falken', 'Federal', 'Firestone', 'Fuzion', 'General', 'Goodride', 'Goodyear', 'GT Radial', 'Hankook', 'Hercules', 'Ironman', 'Kelly', 'Kenda', 'Kumho', 'Laufenn', 'Lexani', 'Lionhart', 'Mastercraft', 'Maxxis', 'Michelin', 'Mickey Thompson', 'Milestar', 'Nankang', 'Nexen', 'Nitto', 'Nokian', 'Pirelli', 'Primewell', 'Sailun', 'Sumitomo', 'Toyo', 'Uniroyal', 'Vredestein', 'Westlake', 'Yokohama', 'Other'];

bool vinCheck(String v) {
  if (!RegExp(r'^[A-HJ-NPR-Z0-9]{17}$').hasMatch(v)) return false;
  const t = {'A': 1, 'B': 2, 'C': 3, 'D': 4, 'E': 5, 'F': 6, 'G': 7, 'H': 8, 'J': 1, 'K': 2, 'L': 3, 'M': 4, 'N': 5, 'P': 7, 'R': 9, 'S': 2, 'T': 3, 'U': 4, 'V': 5, 'W': 6, 'X': 7, 'Y': 8, 'Z': 9};
  const w = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2];
  var n = 0;
  for (var i = 0; i < 17; i++) {
    n += (int.tryParse(v[i]) ?? t[v[i]]!) * w[i];
  }
  return v[8] == (n % 11 == 10 ? 'X' : '${n % 11}');
}
