// Check ID: driver's license and registration photos (private), the owner question; No ends the visit.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../camera/camera_screen.dart';
import '../data/ql.dart';
import '../logic/insp.dart';
import '../services/media.dart' show here;
import '../services/store.dart';
import '../widgets/ui.dart';
import 'home.dart';

// a private document photo from the camera or the library
Future<void> takeDoc(BuildContext context, String id, String doc) async {
  final src = await showChoice(context, short[doc] ?? 'Photo', const [Opt('camera', label: 'Take photo'), Opt('library', label: 'Pick from library')], const [], radio: false);
  if (src == null) return;
  final x = await ImagePicker().pickImage(source: src == 'camera' ? ImageSource.camera : ImageSource.gallery);
  if (x == null) return;
  final rel = await keepPhoto(id, x.path, doc, library: src == 'library');
  store.mut(id, (st) {
    dropFile(m(st, 'files')[doc]);
    m(st, 'files')[doc] = rel;
    m(st, 'src')[doc] = src;
    m(st, 'docs')[doc] = DateTime.now().toIso8601String();
    if (doc == 'ph_family') m(st, 'shots')['ph_family'] = true;
  });
  PaintingBinding.instance.imageCache.clear();
}

String idBlock(J st) {
  final d = m(st, 'docs');
  if (d['ph_license'] == null || d['ph_reg'] == null) return 'Add the license and registration';
  if ((st['owner'] ?? '') == '') return 'Answer the owner question';
  if (st['owner'] == 'No') return 'End the visit';
  if (st['owner'] == 'Family, with proof' && d['ph_family'] == null) return 'Take the proof photo';
  return '';
}

// the end is saved at once; the location is added when GPS answers
Future<void> endVisit(BuildContext context, String id) async {
  final at = nowIso();
  store.mut(id, (st) {
    st['status'] = 'ended';
    st['end'] = {'at': at, 'loc': null};
  });
  here().then((h) => store.mut(id, (st) => st['end'] = {'at': at, 'loc': h['loc']}));
  if (context.mounted) context.go('/');
}

class CheckIdScreen extends ConsumerWidget {
  final String id;
  const CheckIdScreen(this.id, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(storeProvider).ins[id]!, fl = m(st, 'files'), why = idBlock(st), ow = byId['id_owner']!;
    Widget card(String doc, String label) {
      final has = fl[doc] != null;
      return Expanded(
        child: GestureDetector(
          onTap: () => takeDoc(context, id, doc),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
              aspectRatio: 1.58,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: has ? Colors.black : alt, borderRadius: BorderRadius.circular(10), border: Border.all(color: line)),
                child: has
                    ? Image.file(File(store.abs(fl[doc])), fit: BoxFit.cover, key: ValueKey(m(st, 'docs')[doc]))
                    : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(LucideIcons.camera, size: 26, color: bid), SizedBox(height: 4), Text('Take photo', style: TextStyle(fontWeight: FontWeight.w700))]),
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [Icon(has ? LucideIcons.check : LucideIcons.clock, size: 14, color: has ? bid : muted), const SizedBox(width: 4), Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))]),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: TitleBar(carLine(st)),
      body: ListView(children: [
        Section(title: "Seller's documents", children: [
          Row(children: [card('ph_license', "Driver's license"), const SizedBox(width: 12), card('ph_reg', 'Registration card')]),
        ]),
        Section(title: ow['label'], children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final o in strs(ow['options']))
              ChoiceChip(
                label: Text(o),
                selected: st['owner'] == o,
                selectedColor: o == 'No' ? const Color(0xFFFDE8EE) : const Color(0xFFDEF0E5),
                onSelected: (_) => store.mut(id, (s) {
                  s['owner'] = o;
                  if (o != 'Family, with proof') {
                    m(s, 'shots').remove('ph_family');
                    m(s, 'docs').remove('ph_family');
                    m(s, 'files').remove('ph_family');
                  }
                }),
              ),
          ]),
          if (st['owner'] == 'Family, with proof') ...[
            const SizedBox(height: 16),
            Row(children: [card('ph_family', 'Proof of family relationship'), const Spacer()]),
          ],
        ]),
      ]),
      bottomNavigationBar: BottomBar(st['owner'] == 'No'
          ? PBtn('End the visit', () => endVisit(context, id), icon: LucideIcons.ban, color: const Color(0xFFDC2626))
          : PBtn(why.isEmpty ? 'Start inspection' : why, why.isEmpty ? () => _start(context) : null)),
    );
  }

  // the start time is saved at once and the camera opens; the location is added when GPS answers
  void _start(BuildContext context) {
    final at = nowIso();
    store.mut(id, (st) {
      st['start'] = {'at': at, 'loc': null};
      st['phase'] = 'capture';
      st['cap'] = {'k': 'Exterior', 'i': 0};
    });
    here().then((h) => store.mut(id, (st) => st['start'] = {'at': at, 'loc': h['loc']}));
    context.push('/i/$id/cam', extra: const CamArgs(run: true));
  }
}
