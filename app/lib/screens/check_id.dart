// Check ID: the person against the driver's license and registration the seller uploaded (from the car brief), or a photo
// of a missing one taken here (private); the owner question; No ends the visit.
import 'dart:io';

import 'package:camera/camera.dart' show availableCameras;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../camera/camera_screen.dart';
import '../data/ql.dart';
import '../logic/insp.dart';
import '../services/media.dart' show here;
import '../services/store.dart';
import '../services/team.dart';
import '../widgets/ui.dart';
import 'home.dart';

// a private document photo: license and registration from the camera only; the family proof from the camera or the library.
// A debug build on a device with no camera (the simulator) picks from the library, so the flow can still be tested.
Future<void> takeDoc(BuildContext context, String id, String doc) async {
  var src = doc == 'ph_family' ? await showChoice(context, short[doc] ?? 'Photo', const [Opt('camera', label: 'Take photo'), Opt('library', label: 'Pick from library')], const [], radio: false) : 'camera';
  if (src == null) return;
  if (src == 'camera' && kDebugMode && (await availableCameras()).isEmpty) src = 'library';
  XFile? x;
  try {
    x = await ImagePicker().pickImage(source: src == 'camera' ? ImageSource.camera : ImageSource.gallery);
  } on PlatformException {
    // access turned off: say so, or the card just does nothing
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${src == 'camera' ? 'Camera' : 'Photo'} access is off. Allow it in Settings.')));
    return;
  }
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

// the license and registration the seller uploaded for this inspection's booking (its car brief): the file on the phone,
// '' while it is not saved yet
const sellerDocTypes = {'ph_license': 'driver_license', 'ph_reg': 'registration'};
Map<String, String> sellerDocs(J st) {
  final ap = (st['appt'] as Map?)?.cast<String, dynamic>(), b = ap == null ? null : team.briefFor(ap);
  final docs = (((b?['vehicle'] as Map?)?['documents'] as List?) ?? const []).cast<Map>();
  return {
    for (final e in sellerDocTypes.entries)
      if (docs.where((x) => x['type'] == e.value).firstOrNull case final d?)
        e.key: () {
          final p = team.docPath('${ap!['slot_id']}', '${d['document_id']}');
          return File(p).existsSync() ? p : '';
        }(),
  };
}

String idBlock(J st) {
  final d = m(st, 'docs'), s = sellerDocs(st);
  if (sellerDocTypes.keys.any((k) => d[k] == null && !s.containsKey(k))) return 'Add the license and registration';
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

class CheckIdScreen extends ConsumerStatefulWidget {
  final String id;
  const CheckIdScreen(this.id, {super.key});
  @override
  ConsumerState<CheckIdScreen> createState() => _CheckIdScreenState();
}

class _CheckIdScreenState extends ConsumerState<CheckIdScreen> {
  String get id => widget.id;

  @override
  void initState() {
    super.initState();
    // the seller may have just uploaded: the brief and its documents are fetched again
    final ap = store.ins[id]?['appt'] as Map?;
    if (store.online && team.on && ap?['slot_id'] != null) team.loadBrief('${ap!['slot_id']}');
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(teamProvider);
    final st = ref.watch(storeProvider).ins[id]!, fl = m(st, 'files'), why = idBlock(st), ow = byId['id_owner']!, seller = sellerDocs(st);
    final ap = (st['appt'] as Map?)?.cast<String, dynamic>(), reg = '${(((ap == null ? null : team.briefFor(ap))?['vehicle'] as Map?)?['owner'] as Map?)?['registered'] ?? ''}';
    Widget card(String doc, String label) {
      final has = fl[doc] != null, up = !has && seller.containsKey(doc), upFile = up && seller[doc]!.isNotEmpty;
      return Expanded(
        child: GestureDetector(
          onTap: up ? (upFile ? () => showPhotos(context, [seller[doc]!], label) : null) : () => takeDoc(context, id, doc),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
              aspectRatio: 1.58,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: has || upFile ? Colors.black : alt, borderRadius: BorderRadius.circular(10), border: Border.all(color: line)),
                child: has
                    ? Image.file(File(store.abs(fl[doc])), fit: BoxFit.cover, key: ValueKey(m(st, 'docs')[doc]))
                    : upFile
                    ? Image.file(File(seller[doc]!), fit: BoxFit.cover, cacheWidth: 800, errorBuilder: (c, e, s) => const Center(child: Icon(LucideIcons.fileText, color: muted)))
                    : up
                    ? const Center(child: Icon(LucideIcons.download, color: muted))
                    : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(LucideIcons.camera, size: 26, color: bid), SizedBox(height: 4), Text('Take photo', style: TextStyle(fontWeight: FontWeight.w700))]),
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [Icon(has || up ? LucideIcons.check : LucideIcons.clock, size: 14, color: has || up ? bid : muted), const SizedBox(width: 4), Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))]),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: TitleBar(carLine(st)),
      body: ListView(children: [
        Section(title: "Seller's documents", children: [
          Row(children: [card('ph_license', "Driver's license"), const SizedBox(width: 12), card('ph_reg', 'Registration card')]),
          if (reg.isNotEmpty) ...[const SizedBox(height: 12), Text('Registered owner: $reg', style: const TextStyle(fontSize: 14.5))],
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
          : PBtn(why.isEmpty ? 'Start inspection' : why, why.isEmpty ? () => _start(context, seller) : null)),
    );
  }

  // the start time is saved at once and the camera opens; the location is added when GPS answers. The documents the
  // seller uploaded (and no photo was taken of here) go in the record as seller uploads
  void _start(BuildContext context, Map<String, String> seller) {
    final at = nowIso();
    store.mut(id, (st) {
      st['start'] = {'at': at, 'loc': null};
      st['phase'] = 'capture';
      st['cap'] = {'k': 'Exterior', 'i': 0};
      st['sdocs'] = [for (final k in sellerDocTypes.keys) if (m(st, 'files')[k] == null && seller.containsKey(k)) k];
    });
    here().then((h) => store.mut(id, (st) => st['start'] = {'at': at, 'loc': h['loc']}));
    context.push('/i/$id/cam', extra: const CamArgs(run: true));
  }
}
