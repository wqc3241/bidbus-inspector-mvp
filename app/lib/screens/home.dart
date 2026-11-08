// Inspections on this phone, newest first.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/ql.dart';
import '../services/store.dart';
import '../widgets/ui.dart';

String carLine(J st) {
  final c = st['car'] as J;
  return [c['year'], c['make'], c['model'], c['trim']].where((x) => x != null && '$x'.isNotEmpty).join(' ');
}

String statusText(J st) {
  final up = (st['up'] as J?) ?? {};
  return switch (st['status']) {
    'saved' => 'Saved on phone',
    'uploading' || 'building' => 'Uploading${(up['total'] ?? 0) > 0 ? ' (${up['done']} of ${up['total']})' : ''}',
    'sent' => 'Report sent',
    'ended' => 'Visit ended',
    'failed' => (up['errors'] as List? ?? []).isEmpty ? 'Report not made' : '${(up['errors'] as List).first}${(up['errors'] as List).length > 1 ? ' (+${(up['errors'] as List).length - 1} more)' : ''}',
    _ => 'In progress',
  };
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(storeProvider), list = s.list;
    return Scaffold(
      appBar: TitleBar('Inspections', back: false, actions: [IconButton(icon: const Icon(LucideIcons.settings), onPressed: () => context.push('/settings'))]),
      body: ListView(children: [
        RowList([
          for (final st in list)
            InkWell(
              onTap: () => context.push('/i/${st['id']}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(carLine(st), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      if (((st['car'] as J)['vin'] ?? '') != '') Text((st['car'] as J)['vin'], style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: Color(0xFF595959))),
                    ]),
                  ),
                  Flexible(child: Text(statusText(st), textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: st['status'] == 'sent' ? bid : st['status'] == 'failed' || st['status'] == 'ended' ? red : muted))),
                ]),
              ),
            ),
        ]),
      ]),
      bottomNavigationBar: BottomBar(PBtn('New inspection', () => context.push('/new'), icon: LucideIcons.plus)),
    );
  }
}
