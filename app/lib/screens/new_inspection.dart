// New inspection: year, make, model and trim picked from lists (assets/vehicles.json), each with Other to type;
// fuel and report email required. A typed VIN is decoded (NHTSA vPIC via the server) to prefill.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../data/ql.dart';
import '../data/vehicles.dart';
import '../logic/insp.dart';
import '../services/store.dart';
import '../widgets/ui.dart';

class NewInspectionScreen extends StatefulWidget {
  const NewInspectionScreen({super.key});
  @override
  State<NewInspectionScreen> createState() => _NewInspectionScreenState();
}

class _NewInspectionScreenState extends State<NewInspectionScreen> {
  final vin = TextEditingController(), miles = TextEditingController(), owner = TextEditingController(), email = TextEditingController(text: store.defaultEmail);
  final inspector = TextEditingController(text: store.inspector);
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

  Future<void> _decode(String v) async {
    if (v.length != 17 || !store.online) return;
    try {
      final r = await store.api.vin(v);
      if (!mounted) return;
      setState(() {
        _fill('year', r['year']?.toString());
        _fill('make', r['make']);
        _fill('model', r['model']);
        _fill('trim', r['trim']);
        if (fuelChoices.contains(r['fuel'])) fuel = r['fuel'];
      });
    } catch (_) {}
  }

  bool get ready => inspector.text.trim().isNotEmpty && year != null && _val('make').isNotEmpty && _val('model').isNotEmpty && _val('trim').isNotEmpty && fuel != null && RegExp(r'^\S+@\S+\.\S+$').hasMatch(email.text.trim());

  void _go() {
    final id = const Uuid().v4();
    if (store.inspector.isEmpty) store.saveSettings(server: store.server, passcode: store.passcode, inspector: inspector.text, email: store.defaultEmail); // next time it is filled in
    store.add(newInspection(
      id: id,
      fuel: fuelGroup(fuel!),
      email: email.text.trim(),
      inspector: inspector.text.trim(),
      car: {'year': year, 'make': _val('make'), 'model': _val('model'), 'trim': _val('trim'), 'vin': vin.text.trim().toUpperCase(), 'mileage': miles.text.trim(), 'owner_name': owner.text.trim(), 'fuel': fuel},
    ));
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
          _f('Inspector name', inspector),
        ]),
        bottomNavigationBar: BottomBar(PBtn('At the car: check ID', ready ? _go : null)),
      );
}
