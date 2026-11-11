// Scheduler sign-in and the inspector's appointments (docs/12-scheduler-sync.md). On when the server says so
// (GET /api/health auth: team): the inspector signs in with an emailed code, the home screen lists their booked
// jobs, and each job's car brief and seller documents are kept on the phone for use without signal. The documents
// are deleted once that car's report is sent, and everything is deleted on sign-out.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

import '../data/ql.dart';
import 'api.dart';
import 'store.dart';

final teamProvider = ChangeNotifierProvider<Team>((ref) => team);
final team = Team();

// calendar days from one YYYY-MM-DD date to another (counted in UTC, so a daylight saving change does not shift it)
int? dayGap(String? date, String? from) {
  final d = DateTime.tryParse('${date}T00:00:00Z'),
      t = DateTime.tryParse('${from}T00:00:00Z');
  return d == null || t == null ? null : d.difference(t).inDays;
}

class Team extends ChangeNotifier {
  final _secure = const FlutterSecureStorage();
  bool on = false; // the server signs inspectors in with the scheduler
  J? session; // access_token, refresh_token, expires_at (unix seconds)
  J? member; // id, name, email
  String? today; // the scheduler's date for today (Los Angeles)
  List<J> appts = [];
  Map<String, J> briefs = {}; // slot id -> brief
  bool loading = false;
  String? error;
  DateTime? _last;
  Future<String?>? _renewing;
  Timer? _tick;
  bool _again = false; // a pull while the list was loading: loaded once more after it
  bool _known = false; // the server has answered whether it uses scheduler sign-in
  int _epoch = 0; // counts sign-outs: work started before one is dropped

  bool get signedIn => session != null;
  // an inspection this inspector may see, open and upload: started by them, or before scheduler sign-in was used
  bool mine(J st) => !on || st['member'] == null || st['member'] == member?['id'];
  String get name => (member?['name'] as String?)?.trim().isNotEmpty == true
      ? member!['name']
      : (member?['email'] ?? '');
  String get _dir => '${store.docs}/team';

  // today: the scheduler's date, or the phone's when that is later (the app opened without signal on a new day)
  String? get day {
    final l = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return today == null || l.compareTo(today!) > 0 ? l : today;
  }

  Future<void> init() async {
    try {
      on = await _secure.read(key: 'team') == '1';
      final s = await _secure.read(key: 'session'),
          mb = await _secure.read(key: 'member');
      session = s == null ? null : jsonDecode(s) as J;
      member = mb == null ? null : jsonDecode(mb) as J;
    } catch (_) {}
    try {
      final f = File('$_dir/appointments.json');
      if (f.existsSync()) {
        final j = jsonDecode(f.readAsStringSync()) as J;
        today = j['today'];
        appts = (j['appts'] as List).cast<J>();
        briefs = (j['briefs'] as Map).cast<String, J>();
      }
    } catch (_) {}
    unawaited(checkServer());
    // the server is asked every minute which sign-in it uses (the app may start without signal, and the server's
    // setup can change); the list is fetched again every 5 minutes
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => checkServer());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  // whether the server uses scheduler sign-in; asked again whenever the server URL changes
  Future<void> checkServer() async {
    final url = store.server;
    try {
      final r = await Api(url, '').health();
      if (url != store.server) return; // the answer of a server no longer set
      final was = on, first = !_known;
      on = r['auth'] == 'team';
      _known = true;
      try {
        await _secure.write(key: 'team', value: on ? '1' : '0');
      } catch (_) {}
      // the server no longer uses scheduler sign-in: the sign-in and the sellers' data go from the phone
      if (was && !on && signedIn) await signOut();
      if (on != was) notifyListeners();
      if (on) unawaited(refresh(force: first || !was));
    } catch (_) {}
  }

  // a new server URL: nothing is fetched until it has said which sign-in it uses
  Future<void> checked = Future.value();
  Future<void> serverChanged() {
    _known = false;
    return checked = checkServer();
  }

  // ---------- sign-in ----------
  Future<void> sendCode(String email) =>
      Api(store.server, '').sendCode(email.trim());

  Future<void> verify(String email, String code) async {
    final r = await Api(store.server, '').verifyCode(email.trim(), code.trim());
    member = (r['member'] as Map).cast<String, dynamic>();
    await _keep({
      'access_token': r['access_token'],
      'refresh_token': r['refresh_token'],
      'expires_at': r['expires_at'],
    });
    store.kick();
    unawaited(refresh(force: true));
  }

  Future<void> _keep(J? s) async {
    session = s;
    try {
      if (s == null) {
        await _secure.delete(key: 'session');
        await _secure.delete(key: 'member');
      } else {
        await _secure.write(key: 'session', value: jsonEncode(s));
        await _secure.write(key: 'member', value: jsonEncode(member));
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> signOut() async {
    _epoch++;
    member = null;
    appts = [];
    briefs = {};
    today = null;
    _last = null;
    _rm(_dir);
    await _keep(null);
  }

  // the access token, renewed when it ends within 10 minutes (an upload round can be long) or when [now];
  // null when signed out
  Future<String?> token({bool now = false}) {
    final s = session;
    if (s == null) return Future.value(null);
    final left =
        ((s['expires_at'] as num?) ?? 0) -
        DateTime.now().millisecondsSinceEpoch / 1000;
    if (!now && left > 600) return Future.value(s['access_token'] as String);
    return _renewing ??= _renew(s).whenComplete(() => _renewing = null);
  }

  Future<String?> _renew(J s) async {
    final e = _epoch;
    try {
      final r = await Api(store.server, '').refresh(s['refresh_token']);
      if (e != _epoch) return null;
      await _keep({
        'access_token': r['access_token'],
        'refresh_token': r['refresh_token'],
        'expires_at': r['expires_at'],
      });
      return r['access_token'];
    } on DioException catch (x) {
      if (e != _epoch) return null;
      // the sign-in was ended (signed out elsewhere, or taken off the team list)
      if (x.response?.statusCode == 401) {
        await signOut();
        return null;
      }
      return s['access_token']; // server not reached: renewed on the next call
    }
  }

  Future<Api> api() async => Api(store.server, await token() ?? '');

  // ---------- appointments ----------
  // on open, on pull, and every 5 minutes while the app is open
  Future<void> refresh({bool force = false}) async {
    if (!on || !_known || !signedIn || !store.online) return;
    if (loading) {
      _again |= force;
      return;
    }
    if (!force &&
        _last != null &&
        DateTime.now().difference(_last!) < const Duration(minutes: 5)) {
      return;
    }
    final e = _epoch;
    loading = true;
    notifyListeners();
    var renewed = false; // a new token was refused too
    try {
      final tok = await token();
      var a = Api(store.server, tok ?? '');
      J r;
      try {
        r = await a.appointments();
      } on DioException catch (x) {
        // refused: the phone's clock may be off, so the token is renewed once and the call tried again
        if (x.response?.statusCode != 401 || e != _epoch) rethrow;
        final t = await token(now: true);
        if (e != _epoch || t == null) return;
        if (t == tok) rethrow; // not renewed (server not reached): tried again on the next refresh
        renewed = true;
        a = Api(store.server, t);
        r = await a.appointments();
      }
      if (e != _epoch) return;
      final now = (r['appointments'] as List).cast<J>(),
          keys = {for (final x in now) x['key']};
      today = r['today'];
      // a job cancelled since the last look stays on the list, as cancelled, until its day is over
      final gone = [
        for (final x in appts)
          if (!keys.contains(x['key']) &&
              x['status'] != 'done' &&
              '${x['date']}'.compareTo(today ?? '') >= 0)
            {...x, 'status': 'cancelled'},
      ];
      appts = [...now, ...gone]
        ..sort(
          (x, y) => '${x['date']} ${x['start_time']}'.compareTo(
            '${y['date']} ${y['start_time']}',
          ),
        );
      error = null;
      _last = DateTime.now();
      _save();
      // today's and tomorrow's car briefs and documents, for the drive and the visit
      for (final x in now.where((x) => x['status'] == 'booked' && _soon(x))) {
        if (e != _epoch) return;
        await loadBrief(x['slot_id'], a: a);
      }
      if (e == _epoch) _tidy();
    } on DioException catch (x) {
      if (e != _epoch) return;
      error = apiError(x);
      // a refused sign-in (a token just renewed and still refused), or an inspector taken off the team list
      final code = x.response?.statusCode;
      if (code == 403 || code == 401 && renewed) await signOut();
    } catch (x) {
      if (e == _epoch) error = apiError(x);
    } finally {
      loading = false;
      notifyListeners();
      if (_again) {
        _again = false;
        unawaited(refresh(force: true));
      }
    }
  }

  bool _soon(J x) {
    final n = dayGap(x['date'], day);
    return n != null && n <= 1;
  }

  // the brief of this booking (one kept for an earlier booking of the same hour does not count)
  J? briefFor(J a) {
    final b = briefs[a['slot_id']];
    return b != null && (b['appointment'] as Map?)?['key'] == a['key']
        ? b
        : null;
  }

  Future<void> loadBrief(String slot, {Api? a}) async {
    final e = _epoch, inRefresh = a != null;
    try {
      a ??= await api();
      final b = await a.brief(slot), old = briefs[slot];
      if (e != _epoch) return;
      final same =
          old != null &&
          (old['appointment'] as Map?)?['key'] ==
              (b['appointment'] as Map?)?['key'];
      // Bidbus not reached: keep the car from the last look at the same booking
      if (b['bidbus'] == 'error' && same && old['vehicle'] != null) {
        b['vehicle'] = old['vehicle'];
        b['fuel'] = old['fuel'];
        b['vin_differs'] = old['vin_differs'];
      }
      // vPIC not reached: keep the decode from the last look at the same booking and VIN
      if (b['decoded'] == null && same && old['decoded'] != null && (old['appointment'] as Map?)?['vin'] == (b['appointment'] as Map?)?['vin']) {
        b['decoded'] = old['decoded'];
        b['fuel'] ??= old['fuel'];
      }
      // the hour was booked again for another car: the last seller's documents go
      if (!same) _rm('$_dir/docs/$slot');
      briefs[slot] = b;
      _save();
      notifyListeners();
      // the list has an older booking of this hour: the list is fetched again (when not being fetched now)
      final listed = appts
          .where((x) => x['slot_id'] == slot && x['status'] != 'cancelled')
          .firstOrNull;
      if (!inRefresh &&
          listed != null &&
          listed['key'] != (b['appointment'] as Map?)?['key']) {
        unawaited(refresh(force: true));
      }
      await _docs(slot, a, e);
    } catch (x) {
      debugPrint('brief $slot: $x');
    }
  }

  // the seller's documents, saved on the phone (the server sends each one as a photo)
  String docPath(String slot, String doc) => '$_dir/docs/$slot/$doc';
  Future<void> _docs(String slot, Api a, int e) async {
    final b = briefs[slot];
    for (final d
        in (((b?['vehicle'] as Map?)?['documents'] as List?) ?? const [])
            .cast<Map>()) {
      final f = File(docPath(slot, '${d['document_id']}'));
      if (f.existsSync() || _sent(b)) continue;
      try {
        final bytes = await a.document(slot, '${d['document_id']}');
        if (e != _epoch || briefs[slot] != b || _sent(b)) return;
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(bytes);
        notifyListeners();
      } catch (x) {
        debugPrint('document ${d['document_id']}: $x');
      }
    }
  }

  // the inspection on this phone started from this appointment (the same booking)
  J? inspectionFor(J appt) => store.ins.values
      .where((st) => (st['appt'] as Map?)?['key'] == appt['key'] && mine(st))
      .firstOrNull;
  bool _sent(J? brief) {
    final k = (brief?['appointment'] as Map?)?['key'];
    return k != null &&
        store.ins.values.any(
          (st) => (st['appt'] as Map?)?['key'] == k && st['status'] == 'sent',
        );
  }

  // briefs and documents are kept only for jobs still booked for this inspector, for the same booking;
  // documents go once the car's report is sent
  void _tidy() {
    final keys = {
      for (final x in appts)
        if (x['status'] != 'cancelled') x['slot_id']: x['key'],
    };
    briefs.removeWhere(
      (k, b) =>
          keys[k] == null || (b['appointment'] as Map?)?['key'] != keys[k],
    );
    _save();
    try {
      final d = Directory('$_dir/docs');
      if (!d.existsSync()) return;
      for (final x in d.listSync().whereType<Directory>()) {
        final slot = x.path.split('/').last;
        if (briefs[slot] == null || _sent(briefs[slot])) {
          x.deleteSync(recursive: true);
        }
      }
    } catch (_) {}
  }

  void reportSent() => _tidy();

  void _rm(String path) {
    try {
      final d = Directory(path);
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {}
  }

  void _save() {
    try {
      final f = File('$_dir/appointments.json');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(
        jsonEncode({'today': today, 'appts': appts, 'briefs': briefs}),
      );
    } catch (_) {}
  }
}
