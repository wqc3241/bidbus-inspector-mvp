// Car brief for a scheduler appointment (docs/12-scheduler-sync.md; DEV-190 UI 1.2): the car from Bidbus, the visit,
// the seller's documents, what to check before starting and Carfax, then At the car: check ID with the car filled in.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/ql.dart';
import '../services/store.dart';
import '../services/team.dart';
import '../widgets/ui.dart';
import '../widgets/web_page.dart';
import 'new_inspection.dart' show atTheCar;

// ---------- shared with the home screen ----------
String apptTime(J a) {
  final h = int.tryParse('${a['start_time']}'.split(':').first) ?? 0;
  return '${h % 12 == 0 ? 12 : h % 12}:00 ${h < 12 ? 'AM' : 'PM'}';
}

String apptDay(String? date, String? today) {
  final d = DateTime.tryParse(date ?? '');
  if (d == null) return '';
  final n = dayGap(date, today);
  return n == 0
      ? 'Today'
      : n == 1
      ? 'Tomorrow'
      : DateFormat('EEE, MMM d').format(d);
}

J? briefCar(J a) =>
    ((team.briefFor(a)?['vehicle'] as Map?)?['car'] as Map?)
        ?.cast<String, dynamic>();

String apptCar(J a) {
  final c = briefCar(a);
  if (c == null) return '${a['vehicle'] ?? ''}';
  return [
    c['year'],
    c['make'],
    c['model'],
    c['series'],
  ].where((x) => x != null && '$x'.isNotEmpty).join(' ');
}

String apptPlace(J a) => [
  a['address'],
  a['zip'],
].where((x) => x != null && '$x'.isNotEmpty).join(' · ');

Future<void> navigate(J a) {
  final dest = a['lat'] != null && a['lng'] != null
      ? '${a['lat']},${a['lng']}'
      : apptPlace(a).replaceAll(' · ', ' ');
  final u = Platform.isIOS
      ? Uri.https('maps.apple.com', '/', {'daddr': dest})
      : Uri.https('www.google.com', '/maps/dir/', {
          'api': '1',
          'destination': dest,
        });
  return launchUrl(
    u,
    mode: LaunchMode.externalApplication,
  ).catchError((_) => false);
}

String _digits(String? p) {
  final d = (p ?? '').replaceAll(RegExp(r'[^\d+]'), '');
  return d.length == 10 ? '+1$d' : d;
}

Future<void> phone(J a, String scheme) =>
    launchUrl(Uri(scheme: scheme, path: _digits(a['seller_phone'])))
        .catchError((_) => false);

class OutBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const OutBtn(this.label, this.icon, this.onTap, {super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.black,
        shape: const StadiumBorder(),
        side: const BorderSide(color: line),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
  );
}

class Chip2 extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? color;
  const Chip2(this.text, {super.key, this.icon, this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color == null ? alt : color!.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color ?? Colors.black),
          const SizedBox(width: 5),
        ],
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color ?? Colors.black,
          ),
        ),
      ],
    ),
  );
}

// the car the inspection starts with (At the car: check ID, or New inspection when something is not known): Bidbus, else
// the booking VIN's decode, else the booking's text
J prefill(J a, J? b) {
  final v = (b?['vehicle'] as Map?)?.cast<String, dynamic>(),
      car = ((v?['car'] as Map?) ?? const {}).cast<String, dynamic>(),
      dec = ((b?['decoded'] as Map?) ?? const {}).cast<String, dynamic>();
  final typed = car.isEmpty
      ? RegExp(r'^\s*(\d{4})\s+(\S+)\s+(.+?)\s*$')
            .firstMatch('${a['vehicle'] ?? ''}')
      : null; // "2020 BMW X3" on the booking
  return {
    'vin': car['vin'] ?? a['vin'] ?? '',
    'year': car['year'] ?? dec['year'] ?? typed?.group(1),
    'make': car['make'] ?? dec['make'] ?? typed?.group(2),
    'model': car['model'] ?? dec['model'] ?? typed?.group(3),
    'series': car['series'],
    'trim': car.isEmpty ? dec['trim'] : car['trim'],
    'mileage': car['mileage'] ?? a['mileage'],
    'owner_name': (v?['owner'] as Map?)?['name'] ?? a['seller_name'],
    'fuel': b?['fuel'],
    'bidbus': car.isNotEmpty,
    'appt': {
      'key': a['key'],
      'slot_id': a['slot_id'],
      'booked_at': a['booked_at'],
      'vehicle_id': v != null
          ? '${v['vehicle_id']}'
          : (b?['bidbus'] == 'not_found' ? null : a['vehicle_id']),
    },
  };
}

class BriefScreen extends ConsumerStatefulWidget {
  final String slot;
  const BriefScreen(this.slot, {super.key});
  @override
  ConsumerState<BriefScreen> createState() => _BriefScreenState();
}

class _BriefScreenState extends ConsumerState<BriefScreen> {
  @override
  void initState() {
    super.initState();
    if (store.online) team.loadBrief(widget.slot);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(teamProvider);
    ref.watch(storeProvider);
    // the booking on the list now (a cancelled one shows as it was, with no brief), and its brief (not one kept for
    // an earlier booking of the same hour)
    final listed = t.appts.where((x) => x['slot_id'] == widget.slot);
    final cur =
        listed.where((x) => x['status'] != 'cancelled').firstOrNull ??
        listed.firstOrNull;
    final b = cur == null
        ? t.briefs[widget.slot]
        : cur['status'] == 'cancelled'
        ? null
        : t.briefFor(cur);
    final a = (cur ?? b?['appointment'] as Map?)?.cast<String, dynamic>();
    if (a == null) {
      return const Scaffold(
        appBar: TitleBar('Car brief'),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final v = (b?['vehicle'] as Map?)?.cast<String, dynamic>(),
        car = ((v?['car'] as Map?) ?? const {}).cast<String, dynamic>();
    final insp = t.inspectionFor(a), miles = car['mileage'] ?? a['mileage'];
    final vin = '${car['vin'] ?? a['vin'] ?? ''}',
        cf = (v?['carfax'] as Map?)?.cast<String, dynamic>();
    final checks = ((v?['checks'] as List?) ?? const []).cast<Map>(),
        photos = ((v?['photos'] as List?) ?? const []).cast<Map>();
    return Scaffold(
      appBar: const TitleBar('Car brief'),
      body: RefreshIndicator(
        onRefresh: () => team.loadBrief(widget.slot),
        child: ListView(
          children: [
            Section(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: v?['photo_url'] != null
                        ? Image.network(
                            v!['photo_url'],
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => const _NoPhoto(),
                          )
                        : const _NoPhoto(),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  car.isEmpty
                      ? '${a['vehicle'] ?? ''}'
                      : [
                          car['year'],
                          car['make'],
                          car['model'],
                          car['trim'],
                        ].where((x) => x != null).join(' '),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (vin.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        vin,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                          color: Color(0xFF595959),
                        ),
                      ),
                      if (b?['vin_differs'] == true) ...[
                        const SizedBox(width: 8),
                        const Chip2('VIN differs', color: amber),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (miles != null)
                      Chip2(
                        '${NumberFormat.decimalPattern().format(miles)} mi',
                        icon: LucideIcons.gauge,
                      ),
                    if ((car['zip'] ?? a['zip']) != null)
                      Chip2(
                        '${car['zip'] ?? a['zip']}',
                        icon: LucideIcons.mapPin,
                      ),
                    if (b?['fuel'] != null)
                      Chip2('${b!['fuel']}', icon: LucideIcons.fuel),
                  ],
                ),
              ],
            ),
            Section(
              title: '${apptDay(a['date'], t.day)} · ${apptTime(a)}',
              children: [
                if ((a['seller_name'] ?? '') != '')
                  Text(
                    '${a['seller_name']}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(apptPlace(a), style: const TextStyle(color: muted)),
                if ((a['notes'] ?? '') != '')
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('${a['notes']}'),
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
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutBtn(
                        'Text',
                        LucideIcons.messageSquare,
                        (a['seller_phone'] ?? '') == ''
                            ? null
                            : () => phone(a, 'sms'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (v != null) _Docs(widget.slot, v),
            if (checks.isNotEmpty)
              Section(
                title: 'Check before you start',
                children: [
                  for (final c in checks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Icon(
                              LucideIcons.triangleAlert,
                              size: 16,
                              color: c['level'] == 'red' ? red : amber,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${c['text']}',
                              style: const TextStyle(fontSize: 14.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            if (cf != null) _Carfax(cf),
            if (photos.isNotEmpty)
              Section(
                title: "Seller's photos",
                children: [
                  SizedBox(
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: photos.length,
                      separatorBuilder: (c, i) => const SizedBox(width: 8),
                      itemBuilder: (c, i) => GestureDetector(
                        onTap: () => _showNetwork(context, photos, i),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            children: [
                              Image.network(
                                '${photos[i]['url']}',
                                width: 112,
                                height: 84,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => const SizedBox(
                                  width: 112,
                                  height: 84,
                                  child: ColoredBox(color: alt),
                                ),
                              ),
                              if (photos[i]['damage'] == true)
                                const Positioned(
                                  right: 4,
                                  top: 4,
                                  child: Icon(
                                    LucideIcons.circleAlert,
                                    size: 18,
                                    color: amber,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      bottomNavigationBar: BottomBar(
        insp != null
            ? PBtn(
                'Open inspection',
                () => context.push('/i/${insp['id']}'),
                icon: LucideIcons.clipboardCheck,
              )
            : PBtn(
                'At the car: check ID',
                a['status'] == 'booked'
                    ? () => atTheCar(context, prefill(a, b))
                    : null,
                icon: LucideIcons.idCard,
              ),
      ),
    );
  }
}

class _NoPhoto extends StatelessWidget {
  const _NoPhoto();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: alt,
    child: Center(child: Icon(LucideIcons.carFront, size: 56, color: muted)),
  );
}

class _Docs extends StatelessWidget {
  final String slot;
  final J v;
  const _Docs(this.slot, this.v);
  @override
  Widget build(BuildContext context) {
    final docs = ((v['documents'] as List?) ?? const []).cast<Map>();
    Widget tile(String type, String label) {
      final d = docs.where((x) => x['type'] == type).firstOrNull;
      final path = d == null ? null : team.docPath(slot, '${d['document_id']}');
      final have = path != null && File(path).existsSync();
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: !have ? null : () => showPhotos(context, [path], label),
              child: Container(
                height: 110,
                decoration: BoxDecoration(
                  color: alt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: line),
                ),
                clipBehavior: Clip.antiAlias,
                child: have
                    ? Image.file(
                        File(path),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        cacheWidth: 600,
                        errorBuilder: (c, e, s) => const Center(
                          child: Icon(LucideIcons.fileText, color: muted),
                        ),
                      )
                    : Center(
                        child: Icon(
                          d == null ? LucideIcons.clock : LucideIcons.download,
                          color: muted,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  d == null ? LucideIcons.clock : LucideIcons.check,
                  size: 15,
                  color: d == null ? amber : bid,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (d == null)
              const Text(
                'Not uploaded',
                style: TextStyle(color: amber, fontSize: 13),
              ),
          ],
        ),
      );
    }

    return Section(
      title: "Seller's documents",
      trailing: Text(
        '${v['documents_uploaded']} of ${v['documents_required']} uploaded',
        style: const TextStyle(color: muted),
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tile('driver_license', "Driver's license"),
            const SizedBox(width: 10),
            tile('registration', 'Registration'),
          ],
        ),
        if (((v['owner'] as Map?)?['registered'] ?? '') != '') ...[
          const SizedBox(height: 12),
          Text(
            'Registered owner: ${(v['owner'] as Map)['registered']}',
            style: const TextStyle(fontSize: 14.5),
          ),
        ],
      ],
    );
  }
}

class _Carfax extends StatelessWidget {
  final J cf;
  const _Carfax(this.cf);
  @override
  Widget build(BuildContext context) {
    Widget flag(
      bool? bad, {
      String no = 'No',
      String yes = 'Yes',
      Color color = red,
    }) => bad == true ? alertVal(color, yes) : plainVal(no);
    final acc = (cf['accident_detail'] as List?)?.cast<String>() ?? const [];
    return Section(
      title: 'Carfax',
      children: [
        RowList([
          if (cf['report_url'] != null)
            RowBtn(
              'Carfax report',
              const SizedBox(),
              lead: SvgPicture.asset('assets/carfax.svg', height: 26),
              onTap: () => openWebPage(context, 'Carfax', cf['report_url']),
            ),
          if (cf['owners'] != null)
            RowBtn('Owners', plainVal('${cf['owners']}')),
          RowBtn(
            'Accident or damage',
            flag(
              cf['accident'] == true,
              yes: acc.isEmpty ? 'Yes' : acc.join(', '),
              color: amber,
            ),
          ),
          RowBtn(
            'Title',
            cf['clean_title'] == false
                ? alertVal(red, 'Not clean')
                : plainVal(cf['clean_title'] == true ? 'Clean' : '-'),
          ),
          RowBtn('Frame damage', flag(cf['frame_damage'] == true)),
          RowBtn('Total loss', flag(cf['total_loss'] == true)),
          RowBtn('Airbag deployed', flag(cf['airbag'] == true, color: amber)),
          RowBtn('Odometer rollback', flag(cf['odometer_rollback'] == true)),
          if (cf['last_odometer'] != null)
            RowBtn('Last odometer', plainVal('${cf['last_odometer']}')),
          if (cf['service_records'] != null)
            RowBtn('Service records', plainVal('${cf['service_records']}')),
          RowBtn('Open recall', flag(cf['open_recall'] == true, color: amber)),
        ]),
      ],
    );
  }
}

Future<void> _showNetwork(BuildContext context, List<Map> photos, int at) =>
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (c) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: PageView(
            controller: PageController(initialPage: at),
            children: [
              for (final p in photos)
                Column(
                  children: [
                    Expanded(
                      child: InteractiveViewer(
                        child: Center(
                          child: Image.network(
                            '${p['url']}',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '${p['label'] ?? ''}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
