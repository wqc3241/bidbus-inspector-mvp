// Summary (counts, findings, VIN and mileage, overall condition, note) and the seller's disclosure and signature.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:signature/signature.dart';

import '../data/ql.dart';
import '../logic/insp.dart';
import '../services/media.dart';
import '../services/store.dart';
import '../widgets/ui.dart';
import 'home.dart';

Widget chip(bool? ok, String t) => Container(
      margin: const EdgeInsets.only(right: 6, top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: ok == true ? const Color(0xFFDEF0E5) : ok == false ? const Color(0xFFFDE8EE) : alt, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (ok != null) Icon(ok ? LucideIcons.check : LucideIcons.x, size: 12, color: ok ? bid : red),
        if (ok != null) const SizedBox(width: 3),
        Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ok == true ? bid : ok == false ? red : muted)),
      ]),
    );

String clock(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${'${d.minute}'.padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

Widget visitCard(J st) {
  final s = (st['start'] as J?) ?? {}, e = st['end'] as J?;
  final mins = e == null ? null : DateTime.tryParse(e['at'] ?? '')?.difference(DateTime.tryParse(s['at'] ?? '') ?? DateTime.now()).inMinutes;
  return Section(children: [
    Row(children: [
      const Icon(LucideIcons.clock, size: 16, color: muted),
      const SizedBox(width: 8),
      Expanded(child: Text('Started ${clock(s['at'])}${e != null ? ' · finished ${clock(e['at'])}' : ''}${mins != null ? ' · $mins min on site' : ''}')),
    ]),
    const SizedBox(height: 8),
    Row(children: [const Icon(LucideIcons.mapPin, size: 16, color: muted), const SizedBox(width: 8), Expanded(child: Text(s['loc'] ?? 'No location'))]),
  ]);
}

class SummaryScreen extends ConsumerStatefulWidget {
  final String id;
  const SummaryScreen(this.id, {super.key});
  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  late final note = TextEditingController(text: store.ins[widget.id]!['note'] ?? '');

  Future<void> _edit(String k) async {
    final vals = m(store.ins[widget.id]!, 'vals'), vin = k == 'vin';
    final v = await showTextSheet(context, vin ? 'VIN' : 'Mileage', vals[vin ? 'vin_read' : 'odo_read'] ?? '', caps: vin, max: vin ? 17 : 7, unit: vin ? null : 'mi', kb: vin ? TextInputType.text : TextInputType.number);
    if (v == null) return;
    store.mut(widget.id, (s) {
      final x = m(s, 'vals');
      x[vin ? 'vin_read' : 'odo_read'] = vin ? v.toUpperCase() : v.replaceAll(RegExp(r'\D'), '');
      x[vin ? 'vin_man' : 'odo_man'] = true;
      x['idconf'] = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.id, st = ref.watch(storeProvider).ins[id]!, fuel = fuelOf(st), tot = totals(st), pl = problemsList(st), un = sumUnconfirmed(st), vals = m(st, 'vals'), car = st['car'] as J;
    final dl = [for (final d in manual(st)) if (labelled(d, fuel) && dmgOwn(st, d)) dmgLine(d)];
    final vin = (vals['vin_read'] ?? '') as String, mi = (vals['odo_read'] ?? '') as String, why = sumBlock(st), ov = st['overall'] as String? ?? '';
    final typedVin = (car['vin'] ?? '') as String, typedMi = int.tryParse('${car['mileage'] ?? ''}');
    Widget count(String n, String l) => Expanded(child: Column(children: [Text(n, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)), Text(l, style: const TextStyle(color: muted, fontSize: 12.5))]));
    return Scaffold(
      appBar: PhaseHeader('Summary', 3, onBack: () => store.mut(id, (s) {
        s['phase'] = 'summary';
        s['sp'] = capseq.length - 1;
      })),
      body: ListView(children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: line))),
          child: Row(children: [
            count('${tot['photos']}/${tot['need']}', 'Photos'),
            count('${tot['videos']}/${tot['vneed']}', 'Videos'),
            count('${pl.length + dl.length}', 'Problems'),
            count('${manual(st).length}', 'Damage photos'),
          ]),
        ),
        if (un.isNotEmpty)
          Section(title: '${un.length} section${un.length > 1 ? 's' : ''} not reviewed', children: [
            Wrap(spacing: 8, children: [
              for (final k in un)
                OutlinedButton(
                    onPressed: () => store.mut(id, (s) {
                          s['phase'] = 'summary';
                          s['sp'] = capseq.indexOf(k);
                        }),
                    child: Text(stTitle(k))),
            ]),
          ]),
        Section(title: 'What you found', trailing: Text('${pl.length + dl.length}', style: const TextStyle(color: muted)), children: [
          if (pl.isEmpty && dl.isEmpty) const Text('No problems marked.', style: TextStyle(color: muted)),
          Transform.translate(
            offset: Offset.zero,
            child: RowList([
              for (final p in pl)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(p['text']), Text('${p['where']}${p['ph'] == true ? ' · damage photo' : ''}', style: const TextStyle(color: muted, fontSize: 12.5))])),
                    Text(p['level'], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: levelColor(p['level']))),
                  ]),
                ),
              for (final t in dl)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [Expanded(child: Text(t)), const Text('Damage', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: amber))]),
                ),
            ]),
          ),
        ]),
        visitCard(st),
        Section(title: 'VIN and mileage', trailing: vals['idconf'] == true ? okVal('Confirmed') : const Text('Required', style: TextStyle(color: amber, fontWeight: FontWeight.w700)), children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('VIN', style: TextStyle(color: muted, fontSize: 12)), Text(vin.isEmpty ? '–' : vin, style: const TextStyle(fontFamily: 'monospace', fontSize: 17, fontWeight: FontWeight.w700))])),
            IconButton(onPressed: () => _edit('vin'), icon: const Icon(LucideIcons.pen, size: 18)),
          ]),
          Wrap(children: [
            if (vin.isEmpty) chip(false, 'No windshield photo') else ...[
              chip(vals['vin_door'] == null ? null : vals['vin_door'] == vin, 'Door jamb'),
              if (typedVin.isNotEmpty) chip(typedVin == vin, typedVin == vin ? 'Typed VIN' : 'Typed $typedVin'),
              chip(vinCheck(vin), 'Check digit'),
            ],
          ]),
          const Divider(height: 24),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Mileage', style: TextStyle(color: muted, fontSize: 12)), Text(mi.isEmpty ? '–' : '$mi mi', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))])),
            IconButton(onPressed: () => _edit('odo'), icon: const Icon(LucideIcons.pen, size: 18)),
          ]),
          Wrap(children: [if (mi.isEmpty) chip(false, 'No odometer photo') else if (typedMi != null) chip(int.parse(mi) >= typedMi ? null : false, 'Typed $typedMi')]),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: idReady(st) && vals['idconf'] != true ? () => store.mut(id, (s) => m(s, 'vals')['idconf'] = true) : null,
            icon: const Icon(LucideIcons.check, size: 16),
            label: Text(vals['idconf'] == true ? 'VIN and mileage confirmed' : 'Confirm VIN and mileage'),
          ),
        ]),
        Section(children: [
          RowList([
            RowBtn('Overall condition', ov.isEmpty ? needVal() : overallOpts.indexOf(ov) >= 3 ? alertVal(amber, ov) : setVal(ov), onTap: () async {
              final v = await showChoice(context, 'Overall condition', [for (var j = 0; j < overallOpts.length; j++) Opt(overallOpts[j], color: j == 4 ? red : j == 3 ? amber : bid)], [ov]);
              if (v != null) store.mut(id, (s) => s['overall'] = v);
            }),
          ]),
        ]),
        Section(title: "Inspector's note", children: [
          TextField(controller: note, maxLines: 5, onChanged: (v) => store.mut(id, (s) => s['note'] = v), decoration: const InputDecoration(hintText: 'What a dealer should know about this car')),
        ]),
      ]),
      bottomNavigationBar: BottomBar(PBtn(why.isEmpty ? 'Show the seller' : why, why.isEmpty ? () => store.mut(id, (s) => s['phase'] = 'sign') : null, icon: why.isEmpty ? LucideIcons.user : null)),
    );
  }
}

// the disclosure the seller agrees to; its version is saved with the signature
const discVersion = '2026-11-07';

class SignScreen extends ConsumerStatefulWidget {
  final String id;
  const SignScreen(this.id, {super.key});
  @override
  ConsumerState<SignScreen> createState() => _SignScreenState();
}

class _SignScreenState extends ConsumerState<SignScreen> {
  final pad = SignatureController(penStrokeWidth: 3, penColor: Colors.black, exportBackgroundColor: Colors.white);
  late final name = TextEditingController(text: store.ins[widget.id]!['signName'] ?? '');
  bool signing = false;
  final endLoc = here(); // asked when the seller gets the phone, so Sign does not wait for GPS

  @override
  void initState() {
    super.initState();
    pad.onDrawEnd = () => setState(() {});
  }

  Future<void> _sign() async {
    setState(() => signing = true);
    final id = widget.id, png = await pad.toPngBytes(), rel = '${store.dirOf(id)}/signature.png';
    if (png == null) return setState(() => signing = false);
    await File(store.abs(rel)).writeAsBytes(png);
    final end = {...await endLoc, 'at': DateTime.now().toIso8601String()};
    store.mut(id, (s) {
      m(s, 'files')['signature'] = rel;
      s['signName'] = name.text.trim();
      s['signed'] = true;
      s['discVer'] = discVersion;
      s['end'] = end;
      s['phase'] = 'sent';
    });
    store.markSigned(id);
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.id, st = ref.watch(storeProvider).ins[id]!, pl = problemsList(st), tot = totals(st), dl = tot['dlist'] as List;
    final can = st['agree'] == true && name.text.trim().isNotEmpty && pad.isNotEmpty && !signing;
    const disc = [
      'This inspection records the condition of the vehicle that our inspector could see and test today, at your location. The vehicle was not lifted or taken apart.',
      'It describes the vehicle at the time of the inspection. It is not a warranty.',
      'Bidbus is not responsible for any problem with the vehicle that appears or develops after this inspection, or that could not be seen or tested during it.',
      'You have told us about every problem with the vehicle that you know of.',
    ];
    return Scaffold(
      appBar: PhaseHeader('Seller signs', 4, onBack: () => store.mut(id, (s) => s['phase'] = 'final')),
      body: ListView(children: [
        Section(title: carLine(st), children: [
          const Text('Inspection findings', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (pl.isEmpty && dl.isEmpty) const Text('Nothing found.', style: TextStyle(color: muted)),
          for (final p in pl)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(LucideIcons.triangleAlert, size: 16, color: muted),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(p['text']), Text(p['where'], style: const TextStyle(color: muted, fontSize: 12.5))])),
                ])),
          for (final d in dl) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [const Icon(LucideIcons.triangleAlert, size: 16, color: muted), const SizedBox(width: 8), Expanded(child: Text(d))])),
          const SizedBox(height: 8),
          Text('${tot['photos'] + tot['extra']} photos and ${tot['videos']} videos taken.', style: const TextStyle(color: muted, fontSize: 13)),
        ]),
        Section(title: 'Disclosure', children: [
          for (final t in disc) Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  '), Expanded(child: Text(t))])),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => store.mut(id, (s) => s['agree'] = s['agree'] != true),
            child: Row(children: [
              Icon(st['agree'] == true ? Icons.check_box : Icons.check_box_outline_blank, color: st['agree'] == true ? bid : muted),
              const SizedBox(width: 8),
              const Expanded(child: Text('I have read and agree to this disclosure.', style: TextStyle(fontWeight: FontWeight.w600))),
            ]),
          ),
        ]),
        Section(children: [
          const Text('Your name', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(controller: name, onChanged: (_) => setState(() {})),
          const SizedBox(height: 16),
          const Text('I have seen the inspection findings for this car.', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            height: 180,
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD5D8DB)), borderRadius: BorderRadius.circular(12)),
            child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Signature(controller: pad, backgroundColor: Colors.white)),
          ),
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => setState(pad.clear), child: const Text('Clear'))),
        ]),
      ]),
      bottomNavigationBar: BottomBar(PBtn('Sign', can ? _sign : null, icon: LucideIcons.pen)),
    );
  }
}
