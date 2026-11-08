// One inspection: shows the screen for its phase. Camera closed: sections with counts and a button back into the camera.
// After the signature: Saved on phone -> Uploading -> Report sent.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../camera/camera_screen.dart';
import '../data/ql.dart';
import '../logic/insp.dart';
import '../logic/payload.dart';
import '../services/store.dart';
import '../widgets/ui.dart';
import 'check_id.dart';
import 'damages.dart';
import 'home.dart';
import 'review.dart';
import 'summary.dart';

class InspectionScreen extends ConsumerWidget {
  final String id;
  const InspectionScreen(this.id, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(storeProvider).ins[id];
    if (st == null) return const Scaffold();
    if (['saved', 'uploading', 'building', 'sent', 'failed', 'ended'].contains(st['status'])) return SentScreen(id);
    return switch (st['phase']) {
      'start' => CheckIdScreen(id),
      'label' => DamagesScreen(id),
      'summary' => ReviewScreen(id),
      'final' => SummaryScreen(id),
      'sign' => SignScreen(id),
      _ => ResumeScreen(id),
    };
  }
}

class ResumeScreen extends ConsumerWidget {
  final String id;
  const ResumeScreen(this.id, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(storeProvider).ins[id]!, open = firstOpenSection(st);
    return Scaffold(
      appBar: PhaseHeader(carLine(st), 0, onBack: () => context.go('/')),
      body: ListView(children: [
        RowList([
          for (final k in camseq)
            () {
              final c = capCount(st, k), z = zoneDamages(st, k).length;
              return RowBtn(k, c[0] >= c[1] ? okVal('${c[0]}/${c[1]}') : Text('${c[0]}/${c[1]}', style: const TextStyle(color: amber, fontWeight: FontWeight.w700)),
                  sub: z > 0 ? '$z damage photo${z > 1 ? 's' : ''}' : null, onTap: () => context.push('/i/$id/cam', extra: CamArgs(run: true, k: k)));
            }(),
        ]),
      ]),
      bottomNavigationBar: BottomBar(open != null
          ? PBtn('Open the camera', () => context.push('/i/$id/cam', extra: const CamArgs(run: true)), icon: LucideIcons.camera)
          : PBtn(manual(st).isNotEmpty ? 'Next: Damages' : 'Next: Review', () => store.mut(id, afterCapture), icon: LucideIcons.chevronRight, trailingIcon: true)),
    );
  }
}

class SentScreen extends ConsumerWidget {
  final String id;
  const SentScreen(this.id, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(storeProvider), st = s.ins[id]!, up = (st['up'] as J?) ?? {}, status = st['status'] as String;
    if (status == 'ended') {
      return Scaffold(
        appBar: TitleBar(carLine(st)),
        body: ListView(children: [
          const Section(children: [Row(children: [Icon(LucideIcons.ban, color: red), SizedBox(width: 8), Text('Visit ended', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))])]),
          Section(children: [Text('Ended ${clock((st['end'] as J?)?['at'])}'), Text((st['end'] as J?)?['loc'] ?? '', style: const TextStyle(color: muted))]),
        ]),
      );
    }
    final p = inspectionPayload(st), files = p.files.keys, total = (up['total'] as int?) ?? files.length, done = (up['done'] as int?) ?? 0;
    final photos = files.where((f) => f.endsWith('.jpg') && !f.startsWith('spin-')).length, videos = files.where((f) => !f.endsWith('.jpg') && !f.endsWith('.png')).length;
    final sent = status == 'sent', failed = status == 'failed', uploadsDone = status == 'building' || sent || (total > 0 && done >= total);
    Widget part(IconData ic, String label, double v, String right) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: [
            Row(children: [Icon(ic, size: 18), const SizedBox(width: 8), Expanded(child: Text(label)), Text(right, style: const TextStyle(color: muted))]),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: v, color: bid, backgroundColor: alt, minHeight: 6, borderRadius: BorderRadius.circular(3)),
          ]),
        );
    final answersDone = status != 'saved';
    return Scaffold(
      appBar: TitleBar(sent ? 'Sent' : failed ? 'Report not made' : 'Sending', back: false, actions: [IconButton(icon: const Icon(LucideIcons.x), onPressed: () => context.go('/'))]),
      body: ListView(children: [
        if (sent) ...[
          Section(children: [
            const Icon(LucideIcons.circleCheck, size: 40, color: bid),
            const SizedBox(height: 8),
            Text('Report sent to ${st['report_email']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text('${carLine(st)} · signed by ${st['signName']}', textAlign: TextAlign.center, style: const TextStyle(color: muted)),
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: () => openReport(context, up['seller_url']), icon: const Icon(LucideIcons.fileText, size: 18), label: const Text('Open seller report')),
            OutlinedButton.icon(onPressed: () => openReport(context, up['dealer_url']), icon: const Icon(LucideIcons.fileText, size: 18), label: const Text('Open dealer report')),
            TextButton.icon(
                onPressed: () async {
                  try {
                    await s.resendEmail(id);
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email sent again')));
                  } catch (_) {}
                },
                icon: const Icon(LucideIcons.mail, size: 18),
                label: const Text('Resend email')),
          ]),
        ] else if (failed) ...[
          Section(title: 'The server refused the record', children: [
            for (final e in (up['errors'] as List? ?? [])) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $e', style: const TextStyle(color: red))),
            const SizedBox(height: 8),
            PBtn('Send again', () => s.sendAgain(id), icon: LucideIcons.refreshCw),
          ]),
        ] else
          Section(children: [
            Text(status == 'saved' ? 'Saved on phone' : 'Uploading', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            part(LucideIcons.squareCheck, 'Answers and signature', answersDone ? 1 : 0, answersDone ? 'Sent' : 'Waiting'),
            part(LucideIcons.camera, 'Photos and videos', total == 0 ? 0 : done / total, '$done of ${total == 0 ? files.length : total}'),
            part(LucideIcons.fileText, 'Condition report', status == 'building' ? .5 : 0, status == 'building' ? 'Building' : 'Waiting'),
            const SizedBox(height: 8),
            Text(s.online ? 'Everything is saved on this phone. It carries on by itself.' : 'Waiting for signal. Everything is saved on this phone; the upload starts by itself when there is signal.',
                style: const TextStyle(color: muted, fontSize: 13)),
            Text('$photos photos, $videos videos', style: const TextStyle(color: muted, fontSize: 13)),
            if (uploadsDone) const SizedBox(),
          ]),
        visitCard(st),
      ]),
      bottomNavigationBar: BottomBar(PBtn('Back to inspections', () => context.go('/'), icon: LucideIcons.list)),
    );
  }
}

// a report link: in the browser, else in a browser view inside the app, else a message
Future<void> openReport(BuildContext context, String? url) async {
  final u = Uri.tryParse(url ?? '');
  if (u == null || !u.hasScheme) return;
  for (final mode in [LaunchMode.externalApplication, LaunchMode.inAppBrowserView]) {
    if (await launchUrl(u, mode: mode).catchError((_) => false)) return;
  }
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the report')));
}
