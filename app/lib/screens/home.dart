// Inspections on this phone, newest first. With scheduler sign-in (docs/12-scheduler-sync.md) the inspector's booked
// jobs come first (DEV-190 UI 2.2): the next one with Navigate and Call, then each day's list.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/ql.dart';
import '../services/store.dart';
import '../services/team.dart';
import '../widgets/ui.dart';
import 'brief.dart';

String carLine(J st) {
  final c = st['car'] as J, md = '${c['model'] ?? ''}', tr = '${c['trim'] ?? ''}';
  final model = md.isNotEmpty && tr.toLowerCase().startsWith('${md.toLowerCase()} ') ? null : c['model']; // Lexus "LC" + "LC 500h"
  return [c['year'], c['make'], model, c['trim']].where((x) => x != null && '$x'.isNotEmpty).join(' ');
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

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    team.refresh(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(storeProvider), t = ref.watch(teamProvider), list = s.list;
    final body = ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
        if (t.on) ..._today(context, t),
        if (t.on && list.isNotEmpty)
          const Padding(padding: EdgeInsets.fromLTRB(16, 20, 16, 8), child: Text('Inspections', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
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
                  const SizedBox(width: 12),
                  ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150), child: Text(statusText(st), textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: st['status'] == 'sent' ? bid : st['status'] == 'failed' || st['status'] == 'ended' ? red : muted))),
                ]),
              ),
            ),
        ]),
      ]);
    return Scaffold(
      appBar: TitleBar(t.on ? 'Today' : 'Inspections', back: false, actions: [IconButton(icon: const Icon(LucideIcons.settings), onPressed: () => context.push('/settings'))]),
      body: t.on ? RefreshIndicator(onRefresh: () => team.refresh(force: true), child: body) : body,
      bottomNavigationBar: BottomBar(PBtn('New inspection', () => context.push('/new'), icon: LucideIcons.plus)),
    );
  }

  String _status(Team t, J a) {
    final st = t.inspectionFor(a);
    if (a['status'] == 'cancelled') return 'Cancelled';
    if (st?['status'] == 'sent' || a['status'] == 'done') return 'Done';
    return st != null ? 'In progress' : 'Booked';
  }

  List<Widget> _today(BuildContext context, Team t) {
    final appts = t.appts,
        next = appts
            .where(
              (a) =>
                  a['status'] == 'booked' &&
                  a['date'] == t.day &&
                  _status(t, a) != 'Done',
            )
            .firstOrNull;
    final days = <String, List<J>>{};
    for (final a in appts) {
      (days[a['date'] as String] ??= []).add(a);
    }
    return [
      if (t.error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            t.error!,
            style: const TextStyle(color: red, fontWeight: FontWeight.w600),
          ),
        ),
      if (next != null) _NextCard(next),
      if (appts.isEmpty && !t.loading)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No inspections booked', style: TextStyle(color: muted)),
        ),
      for (final e in days.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  apptDay(e.key, t.day),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Builder(
                builder: (_) {
                  final n = e.value.where((a) => a['status'] != 'cancelled').length;
                  return Text(n == 1 ? '1 inspection' : '$n inspections', style: const TextStyle(color: muted));
                },
              ),
            ],
          ),
        ),
        RowList([
          for (final a in e.value)
            InkWell(
              onTap: a['status'] == 'cancelled'
                  ? null
                  : () => context.push('/a/${a['slot_id']}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 74,
                      child: Text(
                        apptTime(a),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            apptCar(a),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              decoration: a['status'] == 'cancelled'
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          Text(
                            apptPlace(a),
                            style: const TextStyle(fontSize: 13, color: muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _status(t, a),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: switch (_status(t, a)) {
                          'Done' => bid,
                          'Cancelled' => red,
                          _ => muted,
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ]),
      ],
    ];
  }
}

class _NextCard extends StatelessWidget {
  final J a;
  const _NextCard(this.a);
  @override
  Widget build(BuildContext context) {
    final v = team.briefFor(a)?['vehicle'] as Map?;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/a/${a['slot_id']}'),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip2('Next · ${apptTime(a)}', color: modBlue),
                  if (v != null)
                    Chip2(
                      'Docs ${v['documents_uploaded']}/${v['documents_required']}',
                      icon: LucideIcons.fileText,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          apptCar(a),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          apptPlace(a),
                          style: const TextStyle(color: muted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(LucideIcons.chevronRight, color: muted),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutBtn(
                      'Navigate',
                      LucideIcons.navigation,
                      () => navigate(a),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutBtn(
                      'Call',
                      LucideIcons.phone,
                      (a['seller_phone'] ?? '') == ''
                          ? null
                          : () => phone(a, 'tel'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
