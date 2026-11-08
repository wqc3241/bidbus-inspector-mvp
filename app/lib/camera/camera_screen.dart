// One camera pass, landscape: guided shots section by section, Damage (amber) and Mod (blue) shutters at any point.
// The state machine is the mockup's capture handlers (capAdvance, capBack, capResume, capEnd, capGoNext) ported one to one.
import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/ql.dart';
import '../logic/insp.dart';
import '../services/media.dart';
import '../services/store.dart';
import '../widgets/ui.dart';

class CamArgs {
  final bool run, single;
  final String? k, dmg, redo, aw; // dmg: damage camera for that zone; redo: damage id to retake; aw: wheel for a new tire damage
  final int? i;
  final (String, int)? sel; // opens on this damage ('d') or mod ('m') tag
  const CamArgs({this.run = false, this.single = false, this.k, this.i, this.dmg, this.redo, this.aw, this.sel});
}

const readKind = {'ph_odo': 'odometer', 'ph_vin_dash': 'vin', 'ph_vin_door': 'vin', 'tire_photo': 'tire', 'tread_photo': 'tread', 'paint': 'paint_meter', 'ph_ev_battery': 'ev_battery', 'ph_keys': 'keys'};
Set<String>? _guides;
Future<Set<String>> guideNames() async => _guides ??= (await AssetManifest.loadFromAssetBundle(rootBundle)).listAssets().where((a) => a.startsWith('assets/guides/')).toSet();

String? guideFor(J? x, String fuel, Set<String> have) {
  if (x == null) return 'assets/guides/damage.svg';
  final id = x['id'] as String;
  final name = x['panel'] != null ? 'paint-${(x['panel'] as String).toLowerCase().replaceAll(' ', '-')}' : id == 'tire_photo' ? 'tire_photo-${x['wheel']}' : id;
  final evName = 'assets/guides/$name-ev.svg', p = 'assets/guides/$name.svg';
  if (fuel == ev && have.contains(evName)) return evName;
  return have.contains(p) ? p : null;
}

// saves a captured or picked photo upright, then queues its AI reading
Future<String> keepPhoto(String id, String from, String key, {bool library = false, J? read}) async {
  final rel = '${store.dirOf(id)}/$key-${DateTime.now().millisecondsSinceEpoch}.jpg';
  var turn = await saveUpright(from, store.abs(rel));
  if (turn < 0) {
    turn = 0;
    // a library photo with no orientation: the AI says how far to turn it; offline it waits in the queue, ahead of its own reading
    var done = !library;
    if (library && store.online) {
      try {
        final r = await store.api.read('upright', File(store.abs(rel)));
        final t = (r['turn_deg'] as num?)?.toInt() ?? 0;
        if (r['ok'] == true) {
          done = true;
          if (t != 0) await rotateFile(store.abs(rel), t);
          turn = t;
        }
      } catch (_) {}
    }
    if (!done) store.queueRead(id, {'kind': 'upright', 'f': rel});
  }
  store.mut(id, (st) => m(st, 'turn')[rel] = turn);
  if (read != null) store.queueRead(id, {...read, 'f': rel});
  return rel;
}

void dropFile(String? rel) {
  if (rel == null) return;
  try {
    File(store.abs(rel)).deleteSync();
  } catch (_) {}
}

// after the last section: Damages when there are damage photos to label, else Review
void afterCapture(J st) {
  final u = unlabelledOrder(st);
  if (u.isNotEmpty) {
    st['phase'] = 'label';
    st['li'] = u.first;
  } else {
    toReview(st);
  }
}

void toReview(J st) {
  final was = st['phase'] == 'summary';
  st['phase'] = 'summary';
  if (was) return;
  final un = sumUnconfirmed(st);
  st['sp'] = un.isNotEmpty ? capseq.indexOf(un.first) : 0;
}

class CameraScreen extends StatefulWidget {
  final String id;
  final CamArgs args;
  const CameraScreen(this.id, {super.key, this.args = const CamArgs()});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? cc;
  List<CameraDescription> cams = [];
  CameraDescription? wide, ultra;
  double zoom = 1, minZ = 1, maxZ = 1, pinch0 = 1;
  Set<String> guides = {};
  late String k;
  late int i;
  bool free = false, ask = false, rec = false, busy = false, flash = false, banner = false;
  (String, int)? sel; // a picked damage ('d') or mod ('m') tag in the strip
  Object? liveFor; // the taken shot or tag the inspector chose to retake: the camera shows live again
  Map<String, dynamic>? capRet;
  (String, int, int)? tag; // last tag taken: kind, number in section, slot
  String note = '';
  Timer? recTimer;
  DateTime? recAt;
  J? recSlot; // the slot a recording belongs to, whatever the inspector taps meanwhile
  bool stopping = false;
  bool noCam = false; // the camera cannot be opened (broken, in use, iPhone Mirroring): every shot is picked from the library
  DeviceOrientation? side; // the landscape side the pass is locked to
  final stripCtl = ScrollController();
  Object? stripAt; // what the strip last scrolled to
  ScrollPosition? stripPos; // and in which list: the strip is rebuilt when the end-of-Exterior dialog opens or closes

  J get st => store.ins[widget.id]!;
  String get fuel => fuelOf(st);
  bool get dmgMode => widget.args.dmg != null;

  // the photo already taken for what is on screen (a taken shot, a picked tag, the damage being retaken); null: live camera
  String? get shown {
    final s = sel;
    if (s != null) return ((s.$1 == 'd' ? manual(st) : (m(st, 'multi')[modslot[k]] ?? []) as List)[s.$2] as Map)['f'];
    if (dmgMode) {
      final d = manual(st).where((d) => d['id'] == widget.args.redo).firstOrNull;
      return d == null ? null : d['f'];
    }
    if (i >= l.length || free || ask) return null;
    final x = l[i], id = x['id'] as String;
    if ((x['it'] as J)['kind'] == 'video' || !capHas(st, x)) return null;
    if (isMulti(id)) {
      final a = (m(st, 'multi')[id] ?? []) as List;
      return widget.args.single && a.isNotEmpty ? a.last['f'] : null;
    }
    return m(st, 'files')[x['panel'] != null ? 'paint:${x['panel']}' : x['wheel'] != null ? '$id-${x['wheel']}' : id];
  }

  Object get here => (k, i, sel);
  bool get showing => shown != null && liveFor != here;
  List<J> get l => capList(k, st);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final a = widget.args, saved = st['cap'] as J?;
    sel = a.sel;
    k = a.dmg ?? a.k ?? saved?['k'] ?? firstOpenSection(st) ?? 'Exterior';
    final lst = capList(k, st);
    i = a.i ?? capNext(st, lst, 0);
    if (a.run && i >= lst.length && !a.single) {
      final f = firstOpenSection(st);
      if (f != null) {
        k = f;
        i = capNext(st, capList(f, st), 0);
      }
    }
    guideNames().then((g) => setState(() => guides = g));
    _init();
  }

  Future<void> _init() async {
    try {
      cams = await availableCameras();
      final back = cams.where((c) => c.lensDirection == CameraLensDirection.back).toList();
      wide = back.where((c) => c.lensType != CameraLensType.ultraWide && c.lensType != CameraLensType.telephoto).firstOrNull ?? back.firstOrNull;
      ultra = back.where((c) => c.lensType == CameraLensType.ultraWide).firstOrNull;
      await _open(zoom == .5 && ultra != null ? ultra! : wide!);
    } catch (e) {
      debugPrint('camera: $e');
      if (mounted) setState(() => noCam = true);
    }
  }

  Future<void> _open(CameraDescription d) async {
    final old = cc;
    cc = null;
    if (mounted) setState(() {});
    await old?.dispose();
    final c = CameraController(d, ResolutionPreset.veryHigh, enableAudio: true, imageFormatGroup: ImageFormatGroup.jpeg);
    await c.initialize();
    await _lockSide(c);
    minZ = await c.getMinZoomLevel();
    maxZ = await c.getMaxZoomLevel();
    if (zoom == 2) await c.setZoomLevel(2.clamp(minZ, maxZ).toDouble());
    if (!mounted) return c.dispose();
    setState(() => cc = c);
  }

  // the box around CameraPreview has the same ratio the preview draws itself (landscape when capture is locked landscape),
  // so cover-filling the screen crops a little and never stretches the picture
  double _previewRatio(CameraController c) {
    final o = c.value.lockedCaptureOrientation ?? c.value.deviceOrientation;
    final land = o == DeviceOrientation.landscapeLeft || o == DeviceOrientation.landscapeRight;
    return land ? c.value.aspectRatio : 1 / c.value.aspectRatio;
  }

  // lock the capture orientation to the current landscape side (landscape left when the phone is upright or flat)
  Future<void> _lockSide([CameraController? cam]) async {
    final c = cam ?? cc;
    if (c == null) return;
    final o = c.value.deviceOrientation;
    final want = o == DeviceOrientation.landscapeLeft || o == DeviceOrientation.landscapeRight ? o : side ?? DeviceOrientation.landscapeLeft;
    if (want == side && cam == null) return;
    side = want;
    await c.lockCaptureOrientation(want);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final c = cc;
    if (s == AppLifecycleState.inactive && c != null) {
      if (rec) _stopVideo();
      cc = null;
      c.dispose();
    } else if (s == AppLifecycleState.resumed && cc == null && wide != null && !noCam) {
      _open(zoom == .5 && ultra != null ? ultra! : wide!).catchError((_) => mounted ? setState(() => noCam = true) : null);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    recTimer?.cancel();
    stripCtl.dispose();
    cc?.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _save() => store.mut(widget.id, (s) => s['cap'] = {'k': k, 'i': i});
  Future<void> _close() async {
    if (rec) await _stopVideo();
    _save();
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  // ---------- the mockup's pass logic ----------
  void capAdvance() {
    i = capNext(st, l, i + 1);
    rec = false;
    banner = false;
    if (widget.args.run && i >= l.length) capEnd();
  }

  void capEnd() {
    if (k == 'Exterior') {
      i = l.length - 1;
      ask = true;
      free = false;
      return;
    }
    capGoNext();
  }

  void capGoNext() {
    final nk = nextSection(st, k);
    capRet = null;
    if (nk == null) {
      store.mut(widget.id, afterCapture);
      Navigator.of(context).pop();
      return;
    }
    k = nk;
    i = capNext(st, l, 0);
    banner = true;
    tag = null;
    _save();
  }

  void capResume() {
    final r = capRet;
    capRet = null;
    note = '';
    rec = false;
    if (r != null && r['free'] == true) {
      tag = null;
      k = r['k'];
      i = r['i'];
      free = true;
      return;
    }
    if (r != null && !(r['k'] == k && (r['i'] as int) <= i)) {
      tag = null;
      k = r['k'];
      i = (r['i'] as int).clamp(0, l.length);
      return;
    }
    i = (i + 1).clamp(0, l.length);
    if (widget.args.run && i >= l.length) capEnd();
  }

  bool get canBack => !widget.args.single && (i > 0 || (widget.args.run && prevSection(st, k) != null && camseq.contains(prevSection(st, k))));
  void capBack() {
    capRet ??= {'k': k, 'i': i};
    if (i > 0) {
      i = i.clamp(0, l.length) - 1;
    } else {
      final pk = prevSection(st, k);
      if (pk == null || !camseq.contains(pk)) return;
      k = pk;
      i = l.length - 1;
      tag = null;
    }
    rec = false;
    note = '';
    banner = false;
  }

  // ---------- capture ----------
  Future<void> _shutter({bool library = false}) async {
    if (busy || (cc == null && !library && !noCam) || i >= l.length) return;
    library = library || noCam;
    if (showing && !library) return setState(() => liveFor = here);
    if (sel != null) return _retakeSel(library: library);
    final x = l[i], it = x['it'] as J;
    if (it['kind'] == 'video' && library) return _pickVideo();
    if (it['kind'] == 'video' && !library) {
      rec ? await _stopVideo() : await _startVideo();
      return;
    }
    setState(() => busy = true);
    try {
      if (!library) await _lockSide();
      final from = library ? (await ImagePicker().pickImage(source: ImageSource.gallery))?.path : (await cc!.takePicture()).path;
      if (from == null) return;
      tag = null;
      final mstay = isMulti(x['id']) && !widget.args.single, again = !mstay && capHas(st, x), id = x['id'] as String;
      final key = x['panel'] != null ? 'paint-${x['panel']}'.replaceAll(' ', '_') : x['wheel'] != null ? '$id-${x['wheel']}' : id;
      final kind = readKind[id];
      final rel = await keepPhoto(widget.id, from, key, library: library, read: kind == null ? null : {'kind': kind, 'w': x['wheel'], 'panel': x['panel'], 'door': id == 'ph_vin_door'});
      store.mut(widget.id, (s) {
        final fl = m(s, 'files');
        if (again && !isMulti(id)) dropFile(fl[x['panel'] != null ? 'paint:${x['panel']}' : x['wheel'] != null ? '$id-${x['wheel']}' : id]);
        if (again && isMulti(id)) {
          final a = (m(s, 'multi')[id] ?? []) as List;
          if (a.isNotEmpty) dropFile((a.removeLast() as Map)['f']);
        }
        capMark(s, x, library ? 'library' : 'camera', rel);
      });
      liveFor = null;
      flash = !library;
      note = '';
      if (widget.args.single) return await _close();
      if (again) {
        capResume();
        note = 'Retaken: ${shotLabel(x)}';
      } else if (!mstay) {
        capRet != null ? capResume() : capAdvance();
      }
      _save();
    } catch (e) {
      debugPrint('shot: $e');
    } finally {
      if (mounted) setState(() => busy = false);
      Future.delayed(const Duration(milliseconds: 180), () => mounted ? setState(() => flash = false) : null);
    }
  }

  Future<void> _startVideo() async {
    await _lockSide();
    await cc!.startVideoRecording();
    recSlot = l[i];
    final max = vmax[recSlot!['id']] ?? 30;
    setState(() {
      rec = true;
      recAt = DateTime.now();
    });
    recTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted) return;
      if (DateTime.now().difference(recAt!).inSeconds >= max) _stopVideo();
      setState(() {});
    });
  }

  Future<void> _stopVideo() async {
    recTimer?.cancel();
    if (stopping) return;
    if (cc == null || !cc!.value.isRecordingVideo || recSlot == null) return setState(() => rec = false);
    stopping = true;
    final x = recSlot!, id = x['id'] as String;
    final XFile f;
    try {
      f = await cc!.stopVideoRecording();
    } finally {
      stopping = false;
    }
    final ext = f.path.contains('.') ? f.path.substring(f.path.lastIndexOf('.')) : '.mp4';
    final rel = '${store.dirOf(widget.id)}/$id-${DateTime.now().millisecondsSinceEpoch}$ext';
    await File(f.path).copy(store.abs(rel));
    final again = capHas(st, x);
    store.mut(widget.id, (s) {
      if (again) dropFile(m(s, 'files')[id]);
      capMark(s, x, 'camera', rel);
      if (id == 'video_360') s['spin'] = null;
    });
    if (id == 'video_360') _cutSpin(rel);
    recSlot = null;
    setState(() => rec = false);
    if (widget.args.single) return _close();
    if (again) {
      capResume();
    } else {
      capRet != null ? capResume() : capAdvance();
    }
    _save();
    setState(() {});
  }

  Future<void> _pickVideo() async {
    final x = l[i], id = x['id'] as String, f = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (f == null) return;
    setState(() => busy = true);
    try {
      final ext = f.path.contains('.') ? f.path.substring(f.path.lastIndexOf('.')).toLowerCase() : '.mp4';
      final rel = '${store.dirOf(widget.id)}/$id-${DateTime.now().millisecondsSinceEpoch}$ext';
      await File(f.path).copy(store.abs(rel));
      final again = capHas(st, x);
      store.mut(widget.id, (s) {
        if (again) dropFile(m(s, 'files')[id]);
        capMark(s, x, 'library', rel);
        if (id == 'video_360') s['spin'] = null;
      });
      if (id == 'video_360') _cutSpin(rel);
      if (widget.args.single) return await _close();
      again || capRet != null ? capResume() : capAdvance();
      _save();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _cutSpin(String rel) {
    final id = widget.id;
    cutSpinFrames(store.abs(rel), store.abs(store.dirOf(id))).then((frames) {
      store.mut(id, (s) {
        if (m(s, 'files')['video_360'] == rel) s['spin'] = frames.map((f) => f.substring(store.docs.length + 1)).toList();
      });
    }).catchError((e) => debugPrint('spin: $e'));
  }

  // retake a picked damage or mod photo: the tag keeps its place and its label
  Future<void> _retakeSel({bool library = false}) async {
    final s = sel!;
    setState(() => busy = true);
    try {
      final from = library ? (await ImagePicker().pickImage(source: ImageSource.gallery))?.path : (await cc!.takePicture()).path;
      if (from == null) return;
      final rel = await keepPhoto(widget.id, from, s.$1 == 'd' ? 'damage' : 'mod', library: library);
      store.mut(widget.id, (x) {
        final e = (s.$1 == 'd' ? manual(x) : (m(x, 'multi')[modslot[k]] ?? []) as List)[s.$2] as Map;
        dropFile(e['f']);
        e['f'] = rel;
        e['src'] = library ? 'library' : 'camera';
      });
      flash = !library;
      liveFor = null;
      if (widget.args.single) return await _close();
    } finally {
      if (mounted) setState(() => busy = false);
      Future.delayed(const Duration(milliseconds: 180), () => mounted ? setState(() => flash = false) : null);
    }
  }

  Future<void> _tag(String t) async {
    if (busy || (cc == null && !noCam) || i >= l.length || k == 'OBDII' || (l[i]['it'] as J)['kind'] == 'video') return;
    sel = null;
    if (showing && !noCam) return setState(() => liveFor = here); // a taken photo is on screen: show the camera first
    setState(() => busy = true);
    try {
      final at = i, sec = k, from = noCam ? (await ImagePicker().pickImage(source: ImageSource.gallery))?.path : (await cc!.takePicture()).path;
      if (from == null) return;
      if (t == 'dmg') {
        final zone = dzone[sec] ?? 'Exterior', hint = dmgHint(st, sec, at);
        final did = 'd${DateTime.now().microsecondsSinceEpoch}';
        final rel = await keepPhoto(widget.id, from, 'damage', read: {'kind': 'damage', 'did': did, 'section': zone, 'hint': ?hint});
        store.mut(widget.id, (s) {
          manual(s).add({'id': did, 'zone': zone, 'sec': sec, 'at': at, 'panel': '', 'type': '', 'sev': '', 'size': '', 'src': 'camera', 'f': rel});
          syncDamages(s);
        });
        tag = ('dmg', manual(st).where((d) => d['sec'] == sec).length, at);
      } else {
        final rel = await keepPhoto(widget.id, from, 'mod');
        final slot = modslot[sec]!;
        store.mut(widget.id, (s) {
          final a = (m(s, 'multi')[slot] ??= <dynamic>[]) as List;
          a.add({'src': 'camera', 'panel': null, 'sec': sec, 'at': at, 'f': rel});
          m(s, 'shots')[slot] = a.length;
        });
        tag = ('mod', ((m(st, 'multi')[slot] ?? []) as List).where((d) => d['sec'] == sec).length, at);
      }
      flash = true;
    } finally {
      if (mounted) setState(() => busy = false);
      Future.delayed(const Duration(milliseconds: 180), () => mounted ? setState(() => flash = false) : null);
    }
  }

  // damage camera (from Damages or Review): every shot is a damage photo of that zone
  Future<void> _dmgShot({bool library = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final from = library || noCam ? (await ImagePicker().pickImage(source: ImageSource.gallery))?.path : (await cc!.takePicture()).path;
      if (from == null) return;
      final zone = widget.args.dmg!, redo = widget.args.redo;
      if (redo != null) {
        final rel = await keepPhoto(widget.id, from, 'damage', library: library);
        store.mut(widget.id, (s) {
          final d = manual(s).firstWhere((x) => x['id'] == redo);
          dropFile(d['f']);
          d['f'] = rel;
          d['src'] = library ? 'library' : 'camera';
        });
        if (mounted) Navigator.of(context).pop(redo);
        return;
      }
      final did = 'd${DateTime.now().microsecondsSinceEpoch}', aw = widget.args.aw;
      final hint = aw != null ? '${wheelName(aw)} tire' : null;
      final rel = await keepPhoto(widget.id, from, 'damage', library: library, read: {'kind': 'damage', 'did': did, 'section': zone, 'hint': ?hint});
      store.mut(widget.id, (s) {
        final d = {'id': did, 'zone': zone, 'panel': '', 'type': '', 'sev': '', 'size': '', 'src': library ? 'library' : 'camera', 'f': rel};
        if (hint != null) setLabel(d, 'panel', hint, fuelOf(s));
        manual(s).add(d);
        syncDamages(s);
      });
      if (mounted) Navigator.of(context).pop(did);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _setZoom(double z) async {
    final c = cc;
    if (c == null) return;
    final switchLens = (z == .5) != (zoom == .5) && ultra != null;
    if (switchLens && rec) return;
    zoom = z;
    if (switchLens) return _open(z == .5 ? ultra! : wide!);
    await c.setZoomLevel((z == .5 ? 1.0 : z).clamp(minZ, maxZ));
    setState(() {});
  }

  // ---------- UI ----------
  Widget _btn(IconData ic, VoidCallback? on, {String? label, Color bg = const Color(0x99000000)}) => GestureDetector(
        onTap: on,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: label == null ? 9 : 14, vertical: 9),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(ic, color: Colors.white, size: 22), if (label != null) ...[const SizedBox(width: 6), Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))]]),
        ),
      );

  Widget _round(Color c, IconData ic, String label, VoidCallback? on) => Opacity(
        opacity: on == null ? .35 : 1,
        child: GestureDetector(
          onTap: on,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c, width: 3), color: Colors.black38), child: Icon(ic, color: c, size: 24)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  Widget _shutterBtn(bool video, VoidCallback? on, {bool again = false}) => GestureDetector(
        onTap: on,
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: again ? const Color(0xFF4ADE80) : Colors.white, width: 4)),
          padding: const EdgeInsets.all(5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(color: video ? const Color(0xFFDC2626) : Colors.white, borderRadius: BorderRadius.circular(video && rec ? 8 : 40)),
            margin: EdgeInsets.all(video && rec ? 14 : 0),
            child: again ? const Icon(LucideIcons.rotateCcw, color: Colors.black, size: 26) : null,
          ),
        ),
      );

  Widget _pill(String t, {Color bg = Colors.black87, IconData? ic, double size = 18}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (ic != null) ...[Icon(ic, color: Colors.white, size: size - 2), const SizedBox(width: 6)],
          Flexible(child: Text(t, textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: size, fontWeight: FontWeight.w700))),
        ]),
      );

  Widget _strip() {
    final list = l, out = <Widget>[], next = capNext(st, list, 0);
    int? at;
    Widget cell(Widget child, {Color? bg, bool cur = false, VoidCallback? on}) {
      if (cur) at = out.length;
      return GestureDetector(
          onTap: on,
          child: Container(
            width: 46,
            height: 46,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: bg ?? Colors.white10, borderRadius: BorderRadius.circular(8), border: cur ? Border.all(color: Colors.white, width: 2) : null),
            child: Center(child: child),
          ),
        );
    }

    for (var j = 0; j < list.length; j++) {
      final x = list[j], has = capHas(st, x), sk = capSkipped(st, x), mn = isMulti(x['id']) ? ((m(st, 'multi')[x['id']] ?? []) as List).length : 0;
      if (mn > 0) {
        for (var q = 0; q < mn; q++) {
          out.add(cell(const Icon(LucideIcons.check, color: Colors.white, size: 18), bg: bid, on: rec ? null : () => _jump(j)));
        }
        if (j == i && !widget.args.single) out.add(cell(const Icon(LucideIcons.plus, color: Colors.white54, size: 18), cur: true));
      } else {
        out.add(cell(
          has ? const Icon(LucideIcons.check, color: Colors.white, size: 18) : sk ? const Text('–', style: TextStyle(color: Colors.white)) : Text('${j + 1}', style: const TextStyle(color: Colors.white54)),
          bg: has ? bid : null,
          cur: j == i && sel == null && !free && !ask,
          on: !rec && (has || sk || j == next || j == i) ? () => _jump(j) : null,
        ));
      }
      for (var d = 0; d < manual(st).length; d++) {
        final dm = manual(st)[d];
        if (dm['sec'] == k && dm['at'] == j) out.add(cell(const Icon(LucideIcons.triangleAlert, color: Colors.white, size: 18), bg: const Color(0xFFC2410C), cur: sel == ('d', d), on: rec ? null : () => setState(() => sel = ('d', d))));
      }
      final mods = (m(st, 'multi')[modslot[k]] ?? []) as List;
      for (var d = 0; d < mods.length; d++) {
        if (mods[d]['sec'] == k && mods[d]['at'] == j) out.add(cell(const Icon(LucideIcons.wrench, color: Colors.white, size: 18), bg: modBlue, cur: sel == ('m', d), on: rec ? null : () => setState(() => sel = ('m', d))));
      }
    }
    // the strip follows the current cell, or its end in free mode (the mockup's capScroll)
    final want = (free || ask ? null : at, out.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !stripCtl.hasClients) return;
      final p = stripCtl.position, a = want.$1;
      if (want == stripAt && identical(p, stripPos)) return;
      stripAt = want;
      stripPos = p;
      stripCtl.animateTo((a == null ? p.maxScrollExtent : a * 52 - p.viewportDimension / 2 + 23).clamp(0, p.maxScrollExtent), duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
    return SizedBox(height: 52, child: ListView(controller: stripCtl, scrollDirection: Axis.horizontal, children: out));
  }

  void _jump(int j) => setState(() {
        sel = null;
        if (j < l.length && !capOk(st, l[j]) && j != capNext(st, l, 0)) return;
        if (free && j < l.length) {
          capRet = {'k': k, 'i': i, 'free': true};
          free = false;
        } else if (j < l.length && capOk(st, l[j])) {
          if (capRet == null && j != i) capRet = {'k': k, 'i': i};
        } else {
          capRet = null;
        }
        tag = null;
        i = j;
        rec = false;
        note = '';
      });

  void _deleteSel() {
    final s = sel;
    if (s == null) return;
    store.mut(widget.id, (x) {
      if (s.$1 == 'd') {
        dropFile(manual(x)[s.$2]['f']);
        manual(x).removeAt(s.$2);
        syncDamages(x);
      } else {
        final slot = modslot[k]!, a = (m(x, 'multi')[slot] ?? []) as List;
        dropFile(a[s.$2]['f']);
        a.removeAt(s.$2);
        a.isEmpty ? m(x, 'shots').remove(slot) : m(x, 'shots')[slot] = a.length;
      }
    });
    setState(() => sel = null);
    if (widget.args.single) _close();
  }

  @override
  Widget build(BuildContext context) {
    final c = cc;
    return PopScope(
      canPop: !rec,
      onPopInvokedWithResult: (did, _) {
        if (did) _save();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          if (c != null && c.value.isInitialized)
            GestureDetector(
              onScaleStart: (_) => pinch0 = zoom == .5 ? 1 : zoom,
              onScaleUpdate: (d) {
                final z = (pinch0 * d.scale).clamp(minZ, maxZ);
                if (zoom != .5) c.setZoomLevel(z);
              },
              child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: 100 * _previewRatio(c), height: 100, child: CameraPreview(c))),
            ),
          if (showing) Positioned.fill(child: Image.file(File(store.abs(shown!)), fit: BoxFit.cover, cacheWidth: 1600, gaplessPlayback: true, key: ValueKey(shown))),
          if (flash) Container(color: Colors.white54),
          SafeArea(child: dmgMode ? _dmgLayout() : _passLayout()),
        ]),
      ),
    );
  }

  Widget _dmgLayout() {
    final zone = widget.args.dmg!;
    return Row(children: [
      Expanded(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [_btn(LucideIcons.chevronLeft, () => Navigator.of(context).pop()), const Spacer(), _pill(zoneTitle[zone]!.replaceAll('damages', 'damage')), const Spacer(), const SizedBox(width: 40)]),
          ),
          Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [if (!showing) SvgPicture.asset('assets/guides/damage.svg', height: MediaQuery.of(context).size.height * .45), const SizedBox(height: 8), _pill(showing ? 'Tap the green shutter to retake it' : 'One damage per photo', size: 13)]))),
        ]),
      ),
      SizedBox(
        width: 110,
        child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _btn(LucideIcons.upload, busy ? null : () => _dmgShot(library: true), label: 'Upload'),
          _shutterBtn(false, busy || (cc == null && !noCam) ? null : () => showing && !noCam ? setState(() => liveFor = here) : _dmgShot(), again: showing),
          const SizedBox(height: 56),
        ]),
      ),
    ]);
  }

  Widget _passLayout() {
    final list = l, n = list.length, run = widget.args.run;
    final top = Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(children: [
        if (rec) const SizedBox(width: 40) else if (canBack && !free && !ask) _btn(LucideIcons.chevronLeft, () => setState(capBack)) else if (free) _btn(LucideIcons.chevronLeft, () => setState(() => free = false)) else const SizedBox(width: 40),
        const SizedBox(width: 8),
        Expanded(child: Center(child: _pill('${run ? '${camseq.indexOf(k) + 1}/${camseq.length}  ' : ''}${stTitle(k)}${i < n && !free && !ask ? ' · ${i + 1} of $n' : ''}', bg: banner ? bid : Colors.black54))),
        const SizedBox(width: 8),
        if (free) ...[
          _btn(LucideIcons.chevronRight, () => setState(() {
                free = false;
                capGoNext();
              }), label: 'Next', bg: bid),
          const SizedBox(width: 8)
        ],
        _btn(LucideIcons.x, _close),
      ]),
    );
    if (i >= n) return _doneLayout(top, n);
    final x = list[i], it = x['it'] as J, id = x['id'] as String, vid = it['kind'] == 'video', multiStay = isMulti(id) && !widget.args.single;
    final arr = isMulti(id) ? ((m(st, 'multi')[id] ?? []) as List) : const [];
    final rv = !multiStay && capHas(st, x);
    var lbl = x['panel'] ?? (x['wheel'] == null ? (short[id] ?? it['label']) : it['label']);
    if (multiStay) lbl = '$lbl · photo ${arr.length + 1}';
    var hint = x['panel'] != null
        ? '${(it['label'] as String).split(':')[0]} · meter on the panel, reading in view'
        : vid
            ? (id == 'video_360' ? 'Start at the left front corner, walk down the left side and all the way round, engine off' : 'Up to ${vmax[id]} seconds')
            : '';
    if (hint.isEmpty && id == 'ph_engine_oil') hint = 'No dipstick? Take the oil level screen.';
    if (hint.isEmpty && id == 'ph_ext_roof') hint = 'Hold the phone up high, the whole roof in view.';
    if (it['optional'] == true && !rv) hint = 'Optional. ${hint.isEmpty ? 'Skip it if you cannot get to it.' : hint}';
    if (rv) hint = vid ? 'Taken. Record again to replace it.' : showing ? 'Taken. Tap the green shutter to retake it.' : 'Take the new photo.';
    if (multiStay) hint = '${multiHint[id] ?? 'One photo each'}. ${arr.isNotEmpty ? '${arr.length} taken. Take another, or tap Done.' : 'Take as many as you need, then tap Done.'}';
    final selLbl = sel == null ? null : sel!.$1 == 'd' ? 'Damage' : 'Mod';
    final tagOk = !widget.args.single, tagOff = k == 'OBDII' || vid || busy || (cc == null && !noCam) || rec;
    final recS = recAt == null ? 0 : DateTime.now().difference(recAt!).inSeconds;
    final g = guideFor(x, fuel, guides);
    final scale = zoom == .5 ? .6 : zoom == 2 ? 1.35 : 1.0;
    return Row(children: [
      Expanded(
        child: Column(children: [
          top,
          Expanded(
            child: Stack(children: [
              // scaled down to fit above the strip; in free mode only the last tag shows
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (c, b) => Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: b.maxWidth,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (tag != null && tag!.$3 == i && sel == null) _pill('${tag!.$1 == 'dmg' ? 'Damage' : 'Mod'} ${tag!.$2}', bg: tag!.$1 == 'dmg' ? const Color(0xFFC2410C) : modBlue, ic: tag!.$1 == 'dmg' ? LucideIcons.triangleAlert : LucideIcons.wrench, size: 16),
                    if ((!free && !ask) || sel != null) ...[
                    if (rec) _pill('● ${recS ~/ 60}:${'${recS % 60}'.padLeft(2, '0')}', bg: const Color(0xFFDC2626), size: 15),
                    if (g != null && selLbl == null && !showing) Transform.scale(scale: scale, child: SvgPicture.asset(g, height: MediaQuery.of(context).size.height * .45)),
                    const SizedBox(height: 6),
                    _pill(selLbl ?? lbl, size: 15),
                    if (selLbl != null || note.isNotEmpty || hint.isNotEmpty)
                      Container(margin: const EdgeInsets.only(top: 6), padding: showing ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4) : null, decoration: showing ? BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)) : null, child: Text(selLbl != null ? (showing ? 'Delete it, or tap the green shutter to retake it.' : 'Take the new photo.') : note.isNotEmpty ? note : hint, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12, shadows: [Shadow(blurRadius: 6)]))),
                    if (selLbl == null) ...[
                      if (x['panel'] != null && !rv)
                        TextButton(onPressed: () => setState(_notOnCar), child: _pill('Not on this car', bg: Colors.white24, size: 13))
                      else if (multiStay && arr.isNotEmpty)
                        TextButton(onPressed: () => setState(_undoMulti), child: _pill('Remove photo ${arr.length}', bg: Colors.white24, ic: LucideIcons.trash2, size: 13))
                      else if (it['optional'] == true && !rv && !rec)
                        TextButton(onPressed: () => setState(_skip), child: _pill('Skip, optional', bg: Colors.white24, size: 13)),
                    ],
                    ],
                  ]),
                      ),
                    ),
                  ),
                ),
              ),
              if (k != 'start')
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final z in [if (ultra != null) .5, 1.0, 2.0])
                        GestureDetector(
                          onTap: () => _setZoom(z),
                          child: Container(
                            width: 40,
                            height: 40,
                            margin: const EdgeInsets.all(3),
                            decoration: BoxDecoration(shape: BoxShape.circle, color: z == zoom ? Colors.black : Colors.black45),
                            child: Center(child: Text(z == .5 ? '.5' : '${z.toInt()}${z == zoom ? '×' : ''}', style: TextStyle(color: z == zoom ? const Color(0xFFFACC15) : Colors.white, fontWeight: FontWeight.w700))),
                          ),
                        ),
                    ]),
                  ),
                ),
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 6), child: _strip()),
        ]),
      ),
      SizedBox(
        width: 120,
        child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          if (isLib(id) && !free && !ask) _btn(LucideIcons.upload, busy ? null : () => _shutter(library: true), label: 'Upload') else const SizedBox(height: 40),
          if (tagOk) _round(const Color(0xFFF59E0B), LucideIcons.triangleAlert, 'Damage', tagOff ? null : () => _tag('dmg')),
          if ((!free && !ask) || sel != null) _shutterBtn(vid && sel == null, busy || (cc == null && !noCam) ? null : () => _shutter(), again: showing),
          if (tagOk) _round(const Color(0xFF60A5FA), LucideIcons.wrench, 'Mod', tagOff ? null : () => _tag('mod')),
          if (sel != null)
            _btn(LucideIcons.trash2, _deleteSel, label: 'Delete', bg: red)
          else if (multiStay && arr.isNotEmpty && !free && !ask)
            _btn(LucideIcons.check, () => setState(() => capRet != null ? capResume() : capAdvance()), label: 'Done · ${arr.length}', bg: bid)
          else if (rv && !rec && !free && !ask)
            _btn(LucideIcons.trash2, () => setState(() => store.mut(widget.id, (s) => capUnmark(s, x))), label: 'Delete', bg: red)
          else
            const SizedBox(height: 40),
        ]),
      ),
    ]).withAsk(ask, context, () => setState(() {
          ask = false;
          capGoNext();
        }), () => setState(() {
          ask = false;
          free = true;
          tag = null;
        }));
  }

  void _notOnCar() {
    final x = l[i];
    store.mut(widget.id, (s) {
      final r = (m(s, 'paint')[x['panel']] ??= <String, dynamic>{}) as J;
      r['na'] = true;
      r['shot'] = false;
      r['v'] = '';
      syncPaint(s);
    });
    i = capNext(st, l, i.clamp(0, l.length - 1));
    if (widget.args.run && i >= l.length) capEnd();
  }

  void _skip() {
    store.mut(widget.id, (s) => m(s, 'skip')[l[i]['id']] = true);
    capRet != null ? capResume() : capAdvance();
  }

  void _undoMulti() {
    final id = l[i]['id'] as String;
    store.mut(widget.id, (s) {
      final a = (m(s, 'multi')[id] ?? []) as List;
      if (a.isNotEmpty) dropFile((a.removeLast() as Map)['f']);
      a.isEmpty ? m(s, 'shots').remove(id) : m(s, 'shots')[id] = a.length;
    });
  }

  Widget _doneLayout(Widget top, int n) {
    final list = l, got = list.where((x) => capOk(st, x)).length, miss = n - got, run = widget.args.run;
    final nk = nextSection(st, k), nextLbl = nk != null && camseq.contains(nk) ? 'Next: ${stTitle(nk)}' : manual(st).isNotEmpty ? 'Next: Damages' : 'Next: Review';
    return Column(children: [
      top,
      Expanded(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(miss > 0 ? LucideIcons.triangleAlert : LucideIcons.circleCheck, color: miss > 0 ? amber : const Color(0xFF4ADE80), size: 40),
            const SizedBox(height: 8),
            Text(miss > 0 ? '$miss still to take' : 'All $n taken', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            Text('$got of $n done in ${stTitle(k)}', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 8, children: [
              if (miss > 0) _btn(LucideIcons.camera, () => _jump(capNext(st, list, 0)), label: 'Take the rest'),
              run ? _btn(LucideIcons.chevronRight, () => setState(capGoNext), label: nextLbl, bg: bid) : _btn(LucideIcons.check, _close, label: 'Done', bg: bid),
            ]),
          ]),
        ),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(8, 0, 128, 6), child: _strip()),
    ]);
  }
}

extension on Widget {
  // the end-of-Exterior dialog over the camera
  Widget withAsk(bool ask, BuildContext context, VoidCallback done, VoidCallback record) => !ask
      ? this
      : Stack(children: [
          this,
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  width: 480,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Please record any exterior damage/modification images before proceeding.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: OutlinedButton(onPressed: done, child: const FittedBox(fit: BoxFit.scaleDown, child: Text("I'm done", maxLines: 1)))),
                      const SizedBox(width: 12),
                      Expanded(child: FilledButton(onPressed: record, child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Record damage now', maxLines: 1)))),
                    ]),
                  ]),
                ),
              ),
            ),
          ),
        ]);
}
