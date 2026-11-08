// New inspection: YMMT, fuel and report email required; a typed VIN is decoded (NHTSA vPIC via the server) to prefill.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../data/ql.dart';
import '../logic/insp.dart';
import '../services/store.dart';
import '../widgets/ui.dart';

class NewInspectionScreen extends StatefulWidget {
  const NewInspectionScreen({super.key});
  @override
  State<NewInspectionScreen> createState() => _NewInspectionScreenState();
}

class _NewInspectionScreenState extends State<NewInspectionScreen> {
  final vin = TextEditingController(), make = TextEditingController(), model = TextEditingController(), trim = TextEditingController();
  final miles = TextEditingController(), owner = TextEditingController(), email = TextEditingController(text: store.defaultEmail);
  int? year;
  String? fuel;
  final years = [for (var y = DateTime.now().year + 1; y >= 1981; y--) y];

  Future<void> _decode(String v) async {
    if (v.length != 17 || !store.online) return;
    try {
      final r = await store.api.vin(v);
      if (!mounted) return;
      setState(() {
        if (years.contains(r['year'])) year = r['year'];
        if ((r['make'] ?? '') != '') make.text = r['make'];
        if ((r['model'] ?? '') != '') model.text = r['model'];
        if ((r['trim'] ?? '') != '') trim.text = r['trim'];
        if (fuels.contains(r['fuel'])) fuel = r['fuel'];
      });
    } catch (_) {}
  }

  bool get ready => year != null && make.text.trim().isNotEmpty && model.text.trim().isNotEmpty && trim.text.trim().isNotEmpty && fuel != null && RegExp(r'^\S+@\S+\.\S+$').hasMatch(email.text.trim());

  void _go() {
    final id = const Uuid().v4();
    store.add(newInspection(
      id: id,
      fuel: fuel!,
      email: email.text.trim(),
      inspector: store.inspector,
      car: {'year': year, 'make': make.text.trim(), 'model': model.text.trim(), 'trim': trim.text.trim(), 'vin': vin.text.trim().toUpperCase(), 'mileage': miles.text.trim(), 'owner_name': owner.text.trim()},
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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const TitleBar('New inspection'),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          _f('VIN (optional)', vin, max: 17, caps: true, on: (v) => _decode(v.trim().toUpperCase())),
          _label('Year'),
          DropdownButtonFormField<int>(initialValue: year, items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))], onChanged: (v) => setState(() => year = v)),
          const SizedBox(height: 16),
          _f('Make', make),
          _f('Model', model),
          _f('Trim', trim),
          _label('Fuel type'),
          DropdownButtonFormField<String>(initialValue: fuel, items: [for (final f in fuels) DropdownMenuItem(value: f, child: Text(f))], onChanged: (v) => setState(() => fuel = v)),
          const SizedBox(height: 16),
          _f('Mileage (optional)', miles, kb: TextInputType.number, max: 7),
          _f('Owner name (optional)', owner),
          _f('Report email', email, kb: TextInputType.emailAddress),
        ]),
        bottomNavigationBar: BottomBar(PBtn('At the car: check ID', ready ? _go : null)),
      );
}
