// New inspection: year, make, model and trim picked from lists (assets/vehicles.json), each with Other to type;
// fuel and report email required. A typed VIN is decoded (NHTSA vPIC via the server) to prefill.
// A scheduler appointment (car brief, At the car: check ID) starts the inspection without it (atTheCar); it opens filled in
// from the booking and Bidbus only when the year, make, model, trim, fuel or report email is not known.
// With scheduler sign-in the inspector is the signed-in team member.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../data/ql.dart';
import '../data/vehicles.dart';
import '../logic/insp.dart';
import '../services/store.dart';
import '../services/team.dart';
import '../widgets/ui.dart';

// the list trim a Bidbus trim (series + body style, "xDrive30i Sport Utility 4D") or a decoded trim names: the series, the
// whole trim, else the longest list trim the series' first words are ("Limited Hybrid" for "Limited Hybrid AWD").
// Never from the body style alone
String? listTrim(List<String> opts, String? series, String? trim) {
  String w(String? x) => ' ${(x ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim()} ';
  return matchOption(opts, series) ??
      matchOption(opts, trim) ??
      (series == null
          ? null
          : (opts.where((o) => w(o).trim().isNotEmpty && w(series).startsWith(w(o))).toList()
                  ..sort((a, b) => b.length.compareTo(a.length)))
                .firstOrNull);
}

bool emailOk(String e) => RegExp(r'^\S+@\S+\.\S+$').hasMatch(e.trim());

// the car New inspection fills in from a car brief, without the VIN decode: year, make and model matched to the lists (else
// as given), the list trim the Bidbus series or the decoded trim names, else the series or the decoded trim. Null when the
// year, make or model is not known
J? carFromBrief(J p) {
  String s(Object? x) => '${x ?? ''}'.trim();
  final y = int.tryParse(s(p['year']));
  if (y == null || y < 1981 || y > DateTime.now().year + 1 || s(p['make']).isEmpty || s(p['model']).isEmpty) return null;
  final mk = matchOption(makesFor(y), s(p['make'])), md = mk == null ? null : matchOption(modelsFor(mk, y), s(p['model']));
  final make = mk ?? s(p['make']), model = md ?? s(p['model']), opts = md == null ? const <String>[] : trimsFor(make, model, y);
  final own = s(p['bidbus'] == true ? p['series'] : p['trim']);
  final trim = listTrim(opts, p['series'], p['trim']) ?? matchOption(opts, s(p['dtrim'])) ?? (own.isNotEmpty ? own : s(p['dtrim']));
  return {'year': y, 'make': make, 'model': model, 'trim': trim, 'vin': s(p['vin']).toUpperCase(), 'mileage': s(p['mileage']), 'owner_name': s(p['owner_name'])};
}

// saves a new inspection (at Check ID) and gives its id
String createInspection({required J car, required String fuel, required String email, required String inspector, J? appt}) {
  final id = const Uuid().v4();
  final st = newInspection(id: id, fuel: fuelGroup(fuel), email: email, inspector: inspector, car: {...car, 'fuel': fuel});
  if (appt != null) st['appt'] = appt; // the scheduler appointment it was started from
  if (team.on) st['member'] = team.member?['id']; // sent only while this inspector is signed in
  store.add(st);
  return id;
}

// At the car: check ID on a car brief. The inspection starts filled in and Check ID opens; New inspection opens instead when
// the year, make, model, trim, fuel, report email or inspector is not known
void atTheCar(BuildContext context, J p) {
  final appt = (p['appt'] as Map?)?.cast<String, dynamic>(), have = appt == null ? null : team.inspectionFor(appt);
  if (have != null) {
    context.push('/i/${have['id']}'); // already started (a second tap): that one opens
    return;
  }
  final car = carFromBrief(p), fuel = fuelChoices.contains(p['fuel']) ? p['fuel'] as String : null;
  final email = store.defaultEmail.trim().isNotEmpty ? store.defaultEmail.trim() : '${team.member?['email'] ?? ''}'.trim();
  final inspector = (team.on && team.signedIn ? team.name : store.inspector).trim();
  if (car == null || car['trim'] == '' || fuel == null || !emailOk(email) || inspector.isEmpty) {
    context.push('/new', extra: p);
    return;
  }
  final id = createInspection(car: car, fuel: fuel, email: email, inspector: inspector, appt: appt);
  context.push('/i/$id');
}

class NewInspectionScreen extends StatefulWidget {
  final J? prefill; // from a car brief: vin, year, make, model, series, trim, mileage, owner_name, fuel, appt
  const NewInspectionScreen({super.key, this.prefill});
  @override
  State<NewInspectionScreen> createState() => _NewInspectionScreenState();
}

class _NewInspectionScreenState extends State<NewInspectionScreen> {
  final vin = TextEditingController(), miles = TextEditingController(), owner = TextEditingController(), email = TextEditingController(text: store.defaultEmail);
  final inspector = TextEditingController(text: team.on && team.signedIn ? team.name : store.inspector);
  // a pick from the list, or Other with the typed value
  final typed = {for (final k in ['year', 'make', 'model', 'trim']) k: TextEditingController()};
  final pick = <String, String?>{'year': null, 'make': null, 'model': null, 'trim': null};
  String? fuel;

  String _val(String k) => pick[k] == other ? typed[k]!.text.trim() : (pick[k] ?? '');
  int? get year {
    final y = int.tryParse(_val('year'));
    return y != null && y >= 1981 && y <= DateTime.now().year + 1 ? y : null;
  }

  List<String> _opts(String k) {
    final y = year, mk = _val('make'), md = _val('model');
    final list = switch (k) {
      'year' => yearsList(),
      'make' => y == null ? <String>[] : makesFor(y),
      'model' => y == null || pick['make'] == other ? <String>[] : modelsFor(mk, y),
      _ => y == null || pick['make'] == other || pick['model'] == other ? <String>[] : trimsFor(mk, md, y),
    };
    return [...list, other];
  }

  // a change resets what depends on it
  void _set(String k, String? v, {String? text}) {
    const order = ['year', 'make', 'model', 'trim'];
    pick[k] = v;
    if (text != null) typed[k]!.text = text;
    for (final d in order.sublist(order.indexOf(k) + 1)) {
      if (pick[d] != null && pick[d] != other && !_opts(d).contains(pick[d])) pick[d] = null;
    }
  }

  // a decoded value picks the list entry it matches, else goes in Other
  void _fill(String k, String? v) {
    if (v == null || v.trim().isEmpty) return;
    final m = matchOption(_opts(k).where((o) => o != other).toList(), v);
    m != null ? _set(k, m) : _set(k, other, text: v.trim());
  }

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    if (p == null) return;
    vin.text = '${p['vin'] ?? ''}'.trim().toUpperCase();
    miles.text = p['mileage'] == null ? '' : '${p['mileage']}';
    owner.text = '${p['owner_name'] ?? ''}';
    _fill('year', p['year']?.toString());
    _fill('make', p['make']);
    _fill('model', p['model']);
    _fillTrim(p['series'], p['trim']);
    if (pick['trim'] == null) _fill('trim', p['dtrim']); // the decoded trim, when Bidbus names none
    if (fuelChoices.contains(p['fuel'])) fuel = p['fuel'];
    // the VIN decode fills in what Bidbus did not give, or corrects a car split from the booking's text
    if (vin.text.length == 17 && (p['bidbus'] != true || ['year', 'make', 'model', 'trim'].any((k) => pick[k] == null))) _decode(vin.text);
  }

  // Bidbus trims are series + body style: the list trim it names (listTrim); with no list to pick from, the series under Other
  void _fillTrim(String? series, String? trim) {
    final opts = _opts('trim').where((o) => o != other).toList(), m = listTrim(opts, series, trim);
    if (m != null) {
      _set('trim', m);
    } else if (series != null && (opts.isEmpty || pick['model'] == other)) {
      _fill('trim', series); // no list to pick from: typed under Other
    }
  }

  Future<void> _decode(String v) async {
    if (v.length != 17 || !store.online) return;
    try {
      final r = await store.api.vin(v);
      if (!mounted) return;
      // the booked car's own VIN: a Bidbus car keeps what Bidbus gave, and the fuel stays unless vPIC really knows it
      // (the decode says Gas when it does not know); any other VIN typed here is another car: all of it is filled in
      final booked = widget.prefill != null && v == '${widget.prefill!['vin'] ?? ''}'.trim().toUpperCase(), keep = booked && widget.prefill!['bidbus'] == true;
      setState(() {
        if (!keep || pick['year'] == null) _fill('year', r['year']?.toString());
        if (!keep || pick['make'] == null) _fill('make', r['make']);
        if (!keep || pick['model'] == null) _fill('model', r['model']);
        if (!keep || pick['trim'] == null) _fill('trim', r['trim']);
        if (fuelChoices.contains(r['fuel']) && (!booked || fuel == null && r['fuel'] != 'Gas')) fuel = r['fuel'];
      });
    } catch (_) {}
  }

  bool get ready => inspector.text.trim().isNotEmpty && year != null && _val('make').isNotEmpty && _val('model').isNotEmpty && _val('trim').isNotEmpty && fuel != null && emailOk(email.text);

  void _go() {
    if (store.inspector.isEmpty && !team.on) store.saveSettings(server: store.server, passcode: store.passcode, inspector: inspector.text, email: store.defaultEmail); // next time it is filled in
    final id = createInspection(
      fuel: fuel!,
      email: email.text.trim(),
      inspector: inspector.text.trim(),
      car: {'year': year, 'make': _val('make'), 'model': _val('model'), 'trim': _val('trim'), 'vin': vin.text.trim().toUpperCase(), 'mileage': miles.text.trim(), 'owner_name': owner.text.trim()},
      appt: (widget.prefill?['appt'] as Map?)?.cast<String, dynamic>(),
    );
    context.pushReplacement('/i/$id');
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)));
  Widget _f(String l, TextEditingController c, {TextInputType? kb, int? max, bool caps = false, ValueChanged<String>? on}) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(l),
          TextField(
            controller: c,
            keyboardType: kb,
            maxLength: max,
            autocorrect: false,
            textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.words,
            decoration: const InputDecoration(counterText: ''),
            onChanged: (v) {
              on?.call(v);
              setState(() {});
            },
          ),
        ]),
      );

  Widget _pick(String k, String label) {
    final opts = _opts(k), cur = opts.contains(pick[k]) ? pick[k] : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label(label),
        DropdownButtonFormField<String>(
          key: ValueKey('$k-${opts.length}-$cur'),
          initialValue: cur,
          isExpanded: true,
          items: [for (final o in opts) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _set(k, v)),
        ),
        if (pick[k] == other)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              controller: typed[k],
              keyboardType: k == 'year' ? TextInputType.number : TextInputType.text,
              maxLength: k == 'year' ? 4 : null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(counterText: ''),
              onChanged: (_) => setState(() => _set(k, other)),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const TitleBar('New inspection'),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          _f('VIN (optional)', vin, max: 17, caps: true, on: (v) => _decode(v.trim().toUpperCase())),
          _pick('year', 'Year'),
          _pick('make', 'Make'),
          _pick('model', 'Model'),
          _pick('trim', 'Trim'),
          _label('Fuel type'),
          DropdownButtonFormField<String>(initialValue: fuel, items: [for (final f in fuelChoices) DropdownMenuItem(value: f, child: Text(f))], onChanged: (v) => setState(() => fuel = v)),
          const SizedBox(height: 16),
          _f('Mileage (optional)', miles, kb: TextInputType.number, max: 7),
          _f('Owner name (optional)', owner),
          _f('Report email', email, kb: TextInputType.emailAddress),
          if (!team.on) _f('Inspector name', inspector),
        ]),
        bottomNavigationBar: BottomBar(PBtn('At the car: check ID', ready ? _go : null)),
      );
}
