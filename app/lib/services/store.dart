// App state: every inspection on this phone (saved to drift after each change), settings, network state,
// the AI reading queue and the upload queue. Both queues live inside each inspection's saved state, so they survive restarts.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../data/ql.dart';
import '../db/db.dart';
import '../logic/insp.dart';
import '../logic/payload.dart';
import 'api.dart';
import 'media.dart';
import 'team.dart';

const defaultServer = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://server-production-c5da.up.railway.app');
final storeProvider = ChangeNotifierProvider<Store>((ref) => store);
final store = Store();

class Store extends ChangeNotifier {
  late Db db;
  late String docs; // app documents folder; every saved path is relative to it
  final Map<String, J> ins = {};
  final _secure = const FlutterSecureStorage();
  String server = defaultServer, passcode = '', inspector = '', defaultEmail = '';
  bool online = true;
  bool _aiBusy = false, _upBusy = false;
  Timer? _tick;

  // camera shots keepPhoto finishes in the background (camera_screen.dart settleLater, set in main.dart);
  // one the app was closed in the middle of is finished at the next start
  void Function(String id, String rel, J? read)? settle;
  void resumeSettles() {
    final f = settle;
    if (f == null) return;
    for (final st in ins.values.toList()) {
      for (final e in ((st['settle'] as Map?) ?? const {}).entries.toList()) {
        f(st['id'] as String, e.key as String, ((e.value as Map)['read'] as Map?)?.cast<String, dynamic>());
      }
    }
  }

  Future<void> init({Db? database, String? docsDir}) async {
    db = database ?? Db();
    docs = docsDir ?? (await getApplicationDocumentsDirectory()).path;
    for (final r in await db.all()) {
      final st = jsonDecode(r.json) as J, old = st['ub'] != true || st['c9'] != true;
      ins[r.id] = cam1109(splitUnderbody(st));
      if (old) await db.put(r.id, jsonEncode(st)); // saved at once, so it is never moved twice
    }
    final s = await db.settingsMap();
    inspector = s['inspector'] ?? '';
    defaultEmail = s['email'] ?? '';
    try {
      server = await _secure.read(key: 'server') ?? defaultServer;
      // a phone build can carry the passcode (--dart-define=PASSCODE=...); Settings can change it
      passcode = await _secure.read(key: 'passcode') ?? const String.fromEnvironment('PASSCODE');
    } catch (_) {}
    try {
      final c = Connectivity();
      online = !(await c.checkConnectivity()).every((x) => x == ConnectivityResult.none);
      c.onConnectivityChanged.listen((r) {
        online = !r.every((x) => x == ConnectivityResult.none);
        notifyListeners();
        if (online) kick();
      });
    } catch (_) {}
    _tick = Timer.periodic(const Duration(seconds: 20), (_) => kick());
    resumeSettles();
    kick();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  // the app passcode, or the scheduler sign-in when the server uses it (team.dart)
  String get bearer =>
      team.on ? (team.session?['access_token'] as String? ?? '') : passcode;
  bool get canCall => bearer.isNotEmpty;
  Api get api => Api(server, bearer);
  String abs(String rel) => '$docs/$rel';
  String dirOf(String id) {
    final d = Directory('$docs/insp/$id');
    if (!d.existsSync()) d.createSync(recursive: true);
    return 'insp/$id';
  }

  List<J> get list => ins.values.toList()..sort((a, b) => (b['created'] as String).compareTo(a['created'] as String));

  Future<void> saveSettings({required String server, required String passcode, required String inspector, required String email}) async {
    this.server = server.trim();
    this.passcode = passcode.trim();
    this.inspector = inspector.trim();
    defaultEmail = email.trim();
    try {
      await _secure.write(key: 'server', value: this.server);
      await _secure.write(key: 'passcode', value: this.passcode);
    } catch (_) {}
    await db.setSetting('inspector', this.inspector);
    await db.setSetting('email', defaultEmail);
    notifyListeners();
    kick();
    unawaited(team.serverChanged());
  }

  // every change goes through here: applied, saved at once, then the screens redraw
  void mut(String id, void Function(J st) fn) {
    final st = ins[id];
    if (st == null) return;
    fn(st);
    db.put(id, jsonEncode(st));
    notifyListeners();
  }

  void add(J st) {
    ins[st['id']] = st;
    db.put(st['id'], jsonEncode(st));
    notifyListeners();
  }

  void kick() {
    if (!online) return;
    _runAi();
    _runUploads();
  }

  // ---------- AI readings (docs/04-ai-reading.md) ----------
  // queue item: {kind, f, section?, hint?, w?, panel?, did?, vin?} (a damage is read against every place of its section)
  void queueRead(String id, J item) {
    mut(id, (st) => (st['aiq'] as List).add(item));
    kick();
  }

  Future<void> _runAi() async {
    if (_aiBusy || !canCall) return;
    _aiBusy = true;
    try {
      if (team.on) await team.token();
      for (final st in list) {
        final q = (st['aiq'] as List? ?? []);
        // after the signature the record is fixed: readings still queued are dropped
        if (st['status'] != 'progress') {
          if (q.isNotEmpty) mut(st['id'], (s) => (s['aiq'] as List).clear());
          continue;
        }
        while (q.isNotEmpty && online) {
          final item = (q.first as Map).cast<String, dynamic>();
          J res;
          try {
            final f = File(abs(item['f']));
            res = f.existsSync() ? await api.read(item['kind'], f, section: item['section'], fuel: st['fuel'], hint: item['hint']) : {'ok': false};
          } on DioException catch (e) {
            // no answer from the server (no signal, timeout, server down, passcode): keep the reading for the next round
            final code = e.response?.statusCode ?? 0;
            if (e.response == null || code == 401 || code >= 500) break;
            res = {'ok': false};
          } on Exception catch (_) {
            res = {'ok': false};
          }
          if (item['kind'] == 'upright' && res['ok'] == true && (res['turn_deg'] ?? 0) != 0) await rotateFile(abs(item['f']), (res['turn_deg'] as num).toInt());
          mut(st['id'], (s) {
            (s['aiq'] as List).removeAt(0);
            if (res['ok'] == true) applyReading(s, item, res);
          });
        }
      }
    } finally {
      _aiBusy = false;
    }
  }

  // ---------- upload: the record first, then each file, then complete ----------
  // the record is built once at the signature and sent as signed on every round
  void markSigned(String id) {
    mut(id, (st) {
      final p = inspectionPayload(st);
      st['rec'] = p.record;
      st['recFiles'] = p.files;
      st['status'] = 'saved';
      st['up'] = {'state': 'saved', 'done': 0, 'total': 0};
    });
    kick();
  }

  Future<void> _runUploads() async {
    if (_upBusy || !canCall) return;
    _upBusy = true;
    try {
      if (team.on) await team.token();
      for (final st in list.where((s) => ['saved', 'uploading', 'building'].contains(s['status']))) {
        if (!online) break;
        if (team.on && st['member'] != null && st['member'] != team.member?['id']) continue; // another inspector's, signed out
        await _upload(st['id']);
      }
    } finally {
      _upBusy = false;
    }
  }

  Future<void> _upload(String id) async {
    final st = ins[id]!, a = api;
    try {
      if (st['status'] != 'building') {
        final p = st['rec'] != null ? Payload(st['rec'], (st['recFiles'] as Map).cast<String, String>()) : inspectionPayload(st), car = st['car'] as J;
        final appt = st['appt'] as Map?;
        final r = await a.putInspection(id, {
          'report_email': st['report_email'], 'inspector': st['inspector'],
          'car': {'year': car['year'], 'make': car['make'], 'model': car['model'], 'trim': car['trim'], 'owner_name': car['owner_name'], 'fuel': ?car['fuel']}, 'record': p.record,
          if (appt != null) 'appointment': {'slot_id': appt['slot_id'], 'booked_at': appt['booked_at'], 'vehicle_id': appt['vehicle_id']},
        });
        var missing = (r['missing'] as List).cast<String>();
        final extra = p.files.keys.where((n) => n.startsWith('spin-')).where((n) => !(m(st, 'up')['spin'] as List? ?? []).contains(n)).toList();
        final todo = [...missing, ...extra];
        final total = p.files.length;
        mut(id, (s) => s['up'] = {...m(s, 'up'), 'state': 'uploading', 'total': total, 'done': total - todo.length});
        st['status'] = 'uploading';
        // three files at a time: each upload has its own set-up time, so one at a time leaves the line idle between files
        final send = <String>[for (final name in todo) if (p.files[name] != null && File(abs(p.files[name]!)).existsSync()) name];
        Future<void> one(String name) async {
          final local = p.files[name]!;
          // a video not made smaller yet (the app was closed while it was being done): now, before it goes
          if (!name.endsWith('.jpg') && !name.endsWith('.png')) await squeezeVideo(abs(local));
          if (team.on) await team.token(); // a sign-in renewed during a long round
          final slash = local.lastIndexOf('/');
          final task = UploadTask(
            url: '${server.replaceAll(RegExp(r'/+$'), '')}/api/inspections/$id/files/$name', baseDirectory: BaseDirectory.applicationDocuments,
            directory: local.substring(0, slash), filename: local.substring(slash + 1), httpRequestMethod: 'PUT', post: 'binary',
            headers: {'Authorization': 'Bearer $bearer', 'Content-Type': name.endsWith('.png') ? 'image/png' : name.endsWith('.jpg') ? 'image/jpeg' : 'video/mp4'},
            retries: 3,
          );
          final res = await FileDownloader().upload(task);
          if (res.status != TaskStatus.complete) throw Exception('upload $name ${res.status}');
          mut(id, (s) {
            final u = m(s, 'up');
            u['done'] = (u['done'] ?? 0) + 1;
            if (name.startsWith('spin-')) u['spin'] = [...(u['spin'] as List? ?? []), name];
          });
        }

        // a failed file stops the round; the next round sends what the server still misses
        Future<void> lane() async {
          while (send.isNotEmpty) {
            try {
              await one(send.removeAt(0));
            } catch (_) {
              send.clear();
              rethrow;
            }
          }
        }

        await Future.wait([for (var w = 0; w < 3; w++) lane()]);
        final c = await (team.on ? Api(server, await team.token() ?? '') : a).complete(id); // a sign-in renewed during the round
        if ((c.statusCode ?? 0) >= 300) return; // something still missing (409), or refused: the next round tries again
        mut(id, (s) => s['status'] = 'building');
      }
      final s = await a.status(id);
      mut(id, (x) {
        x['up'] = {...m(x, 'up'), 'state': s['status'], 'seller_url': s['seller_url'], 'dealer_url': s['dealer_url'], 'errors': s['validation_errors'], 'sent_at': s['report_sent_at']};
        if (s['status'] == 'sent') x['status'] = 'sent';
        if (s['status'] == 'failed') x['status'] = 'failed';
      });
      if (s['status'] == 'sent' && st['appt'] != null) team.reportSent(); // the seller's documents for this car are deleted
    } catch (e) {
      debugPrint('upload $id: $e');
    }
  }

  Future<void> resendEmail(String id) => api.resend(id);
  // sending again after a validation failure updates the same inspection
  void sendAgain(String id) {
    mut(id, (st) => st['status'] = 'saved');
    kick();
  }
}

// a reading fills its field unless the inspector already changed it; the AI value is kept beside it
void applyReading(J st, J item, J r) {
  final vals = m(st, 'vals');
  switch (item['kind']) {
    case 'odometer':
      if (r['mileage'] != null && vals['odo_man'] != true) {
        vals['odo_read'] = '${r['mileage']}';
        vals['idconf'] = false;
      }
    case 'vin':
      if (r['vin'] == null) break;
      if (item['door'] == true) {
        vals['vin_door'] = r['vin'];
        vals['vin_scan'] = 1;
      }
      // the windshield reading leads; a reading that passes the check digit replaces one that does not, never the other way
      final cur = (vals['vin_read'] ?? '') as String, v = '${r['vin']}', better = vinCheck(v) && !vinCheck(cur);
      if (vals['vin_man'] != true && (cur == '' || better || (item['door'] != true && (vinCheck(v) || !vinCheck(cur))))) {
        vals['vin_read'] = r['vin'];
        vals['idconf'] = false;
      }
    case 'tire':
      final t = m(tire(st, item['w']), 'read');
      if (((t['brand'] ?? '') == '' && (t['size'] ?? '') == '') || t['auto'] == true) {
        t['brand'] = r['brand'] ?? '';
        t['model'] = r['model'] ?? ''; // the tire line on the sidewall: only to tell whether the four tires match
        t['size'] = r['size'] ?? '';
        t['auto'] = true;
      }
      tiresMatchSync(st);
    case 'tread':
      final t = tire(st, item['w']);
      if (r['tread_32nds'] != null && (t['tread'] == '' || t['treadAuto'] == true)) {
        t['tread'] = '${r['tread_32nds']}';
        t['treadAuto'] = true;
      }
    case 'paint_meter':
      final p = (m(st, 'paint')[item['panel']] ??= <String, dynamic>{}) as J;
      if (r['mils'] != null && p['na'] != true && ((p['v'] ?? '') == '' || p['auto'] == true)) {
        p['v'] = (r['mils'] as num).toStringAsFixed(1);
        p['auto'] = true;
        syncPaint(st);
      }
    case 'ev_battery':
      if (r['health_pct'] != null && ((vals['ev_soh'] ?? '') == '' || vals['ev_soh_auto'] == 1)) {
        vals['ev_soh'] = '${r['health_pct']}';
        vals['ev_soh_auto'] = 1;
      }
    case 'keys':
      if (r['keys_count'] != null && (vals['keys_n'] == null || vals['keys_auto'] == 1)) {
        vals['keys_n'] = '${r['keys_count']}';
        vals['keys_auto'] = 1;
        keysSync(st);
      }
    case 'upright':
      if (r['turn_deg'] != null) m(st, 'turn')[item['f']] = r['turn_deg'];
    case 'damage':
      final d = manual(st).where((x) => x['id'] == item['did']).firstOrNull;
      if (d == null) break;
      final fuel = fuelOf(st), pl = placeOf(d['zone'] ?? 'Exterior', r['place']);
      if (r['place'] != null && r['type'] != null && r['severity'] != null) d['aiWas'] = {'place': r['place'], 'type': r['type'], 'severity': r['severity']};
      final hinted = item['hint'] != null && d['panel'] == item['hint'] && d['panel'] == r['place'] && (d['sev'] ?? '') == '';
      if (((d['panel'] ?? '') == '' || hinted) && pl != null) {
        d['panel'] = r['place'];
        final ts = placeOpts(pl, fuel);
        d['type'] = ts.contains(r['type']) ? r['type'] : (ts.length == 1 ? ts[0] : '');
        d['sev'] = dmgSev.contains(r['severity']) ? r['severity'] : '';
        if (pl['ex'] == true) d['ex'] = strs(pl['exo'])[0];
        d['ai'] = true;
        syncDamages(st);
      }
  }
}
