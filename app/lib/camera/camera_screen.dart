// One camera pass, landscape (docs/11-camera-flow-1109.md): Exterior, Interior with the OBDII screens, the walk-around, Mechanicals,
// Underbody; guided shots with a Look for list, Damage (amber) and Mod (blue) shutters at any point, questions at a section's end.
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
import '../widgets/questions.dart';
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

// keeps a captured or picked photo: a camera shot at once as it came, so the pass moves on without waiting, then in the
// background turned upright and shrunk in place (saveUpright) with its AI reading queued; a library pick is finished
// before it is shown, since the AI may have to turn it
Future<String> keepPhoto(String id, String from, String key, {bool library = false, J? read}) async {
  final rel = '${store.dirOf(id)}/$key-${DateTime.now().millisecondsSinceEpoch}.jpg', to = store.abs(rel);
  if (library) {
    await File(from).copy(to); // the picker's copy is left where it is
  } else {
    try {
      await File(from).rename(to); // the camera's own file moves in, no copy
    } on FileSystemException catch (_) {
      await File(from).copy(to);
      dropTemp(from);
    }
  }
  if (library) {
    await _settle(id, rel, true, read);
  } else {
    // marked until it is done: if the app is closed before, the next start does it (Store.init, resumeSettles)
    store.mut(id, (st) => m(st, 'settle')[rel] = {'read': ?read});
    settleLater(id, rel, read);
  }
  return rel;
}

// camera shots are finished one at a time, in the order taken (a fast walk never piles up work at once)
Future<void> _later = Future.value();
void settleLater(String id, String rel, J? read) => _later = _later.then((_) => _settle(id, rel, false, read)).catchError((Object e) => debugPrint('settle $rel: $e'));

// the photo kept as it came becomes the upright, shrunk one; a photo deleted or retaken meanwhile is left gone
Future<void> _settle(String id, String rel, bool library, J? read) async {
  try {
    await _settle1(id, rel, library, read);
  } finally {
    store.mut(id, (st) => (st['settle'] as Map?)?.remove(rel));
  }
}

Future<void> _settle1(String id, String rel, bool library, J? read) async {
  final path = store.abs(rel), part = '${Directory.systemTemp.path}/${rel.replaceAll('/', '_')}.part';
  var turn = 0;
  try {
    turn = await saveUpright(path, part);
    File(path).existsSync() ? await File(part).rename(path) : dropTemp(part);
  } catch (e) {
    debugPrint('photo $rel: $e');
    dropTemp(part);
  }
  if (!File(path).existsSync()) return;
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
}

void dropTemp(String path) {
  try {
    File(path).deleteSync();
  } catch (_) {}
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
  bool opening = false, camVideo = false; // camVideo: the camera is open for video (1080p) rather than photos (full sensor, 4:3)
  bool starting = false; // a recording is being started
  // photo flash: Auto (the camera's own default: it fires when it is dark), On, Off; tap to go round, kept for the whole camera screen
  FlashMode flashMode = FlashMode.auto;
  bool get capturing => busy || starting || stopping || rec || (cc?.value.isRecordingVideo ?? false); // never close the camera under a photo or a video
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
  ScrollPosition? stripPos; // and in which list: the strip is rebuilt when the end-of-section dialog opens or closes

  J get st => store.ins[widget.id]!;
  String get fuel => fuelOf(st);
  bool get dmgMode => widget.args.dmg != null;

  // the photo already taken for what is on screen (a taken shot, a picked tag, the damage being retaken); null: live camera
  String? get shown {
    final s = sel;
    if (s != null) {
      final a = s.$1 == 'd' ? manual(st) : (m(st, 'multi')[modslot[k]] ?? []) as List;
      return s.$2 < a.length ? (a[s.$2] as Map)['f'] : null; // a pick of another section's list is no pick (see capGoNext)
    }
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
  // the Damage and Mod shutters are off on videos and on the OBDII screens (taken in Interior), on in Record damage
  bool get tagShut => !free && i < l.length && (homeOf(l[i], k) == 'OBDII' || (l[i]['it'] as J)['kind'] == 'video');
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
    // the run goes on where it stopped, unless an earlier section still has shots to take (the mockup opens the first open one)
    final fo = firstOpenSection(st);
    if (a.run && a.k == null && fo != null && camseq.contains(k) && camseq.indexOf(fo) < camseq.indexOf(k)) k = fo;
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
      await _open(lens);
    } catch (e) {
      debugPrint('camera: $e');
      if (mounted) setState(() => noCam = true);
    }
  }

  CameraDescription get lens => zoom == .5 && ultra != null ? ultra! : wide!;
  // a video slot on screen: the camera records 1080p; everything else is a photo
  bool get wantVideo => !dmgMode && !free && !ask && sel == null && i < l.length && (l[i]['it'] as J)['kind'] == 'video';

  // photos use the whole sensor, 4:3, as the iPhone camera does, so .5, 1 and 2 frame what they frame there;
  // videos are 1080p at the system's own settings, then made smaller after recording (squeezeVideo)
  Future<void> _open(CameraDescription d) async {
    opening = true;
    try {
      final old = cc;
      cc = null;
      if (mounted) setState(() {});
      await old?.dispose();
      final video = wantVideo;
      final c = CameraController(d, video ? ResolutionPreset.veryHigh : ResolutionPreset.max, enableAudio: true, imageFormatGroup: ImageFormatGroup.jpeg);
      await c.initialize();
      await _lockSide(c);
      minZ = await c.getMinZoomLevel();
      maxZ = await c.getMaxZoomLevel();
      if (zoom == 2) await c.setZoomLevel(2.clamp(minZ, maxZ).toDouble());
      await _applyFlash(c);
      if (!mounted) {
        await c.dispose();
        return;
      }
      camVideo = video;
      setState(() => cc = c);
    } finally {
      opening = false;
    }
  }

  // after a move between a photo and a video slot, open the camera again for the other kind; a shot still being taken
  // finishes first (its end rebuilds the screen, which comes back here)
  void _matchKind() {
    if (cc == null || opening || capturing || noCam || camVideo == wantVideo) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || cc == null || opening || capturing || camVideo == wantVideo) return;
      _open(lens).catchError((_) => mounted ? setState(() => noCam = true) : null);
    });
  }

  // the box around CameraPreview has the same ratio the preview draws itself (landscape when capture is locked landscape),
  // so fitting it in the screen shows the whole frame the photo gets and never stretches the picture
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
    } else if (s == AppLifecycleState.resumed && cc == null && wide != null && !noCam && !opening) {
      _open(lens).catchError((_) => mounted ? setState(() => noCam = true) : null);
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

  // the end of a section: its questions (docs/11), then Record damage or Next; Exterior goes straight on
  void capEnd() {
    if (askQ.contains(k)) {
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
    sel = null; // a picked tag belongs to the section left (the mockup's new S.cap)
    liveFor = null;
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
    sel = null;
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
      if (starting) return; // the recording is still starting: a second tap waits for it
      rec ? await _stopVideo() : await _startVideo();
      return;
    }
    setState(() => busy = true);
    if (!library) _blink();
    try {
      if (!library) await _lockSide();
      final from = library ? (await ImagePicker().pickImage(source: ImageSource.gallery))?.path : (await cc!.takePicture()).path;
      if (from == null) return;
      if (!library) _blink(taken: true);
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
    }
  }

  // the white flash over the screen, once for each shutter press: at the tap (the photo is kept at once), or with the flash On
  // when the photo is in (it comes a moment after the tap, once the flash has fired: the inspector holds still until then)
  void _blink({bool taken = false}) {
    if (taken != (flashMode == FlashMode.always)) return;
    setState(() => flash = true);
    Future.delayed(const Duration(milliseconds: 150), () => mounted ? setState(() => flash = false) : null);
  }

  // from the tap the screen is locked as for a recording (no moving to another slot, no lens switch), so the recording
  // that starts is always the one on screen
  Future<void> _startVideo() async {
    final c = cc!;
    recSlot = l[i];
    setState(() {
      starting = true;
      rec = true;
      recAt = DateTime.now();
    });
    try {
      await _lockSide();
      await c.startVideoRecording();
    } catch (e) {
      debugPrint('video: $e');
      recSlot = null;
      if (mounted) setState(() => rec = false);
      return;
    } finally {
      starting = false;
    }
    // closed, left (the app went inactive) or the camera changed while it started: that recording is stopped and dropped
    if (!mounted || !rec || !identical(cc, c) || recSlot == null) {
      try {
        dropTemp((await c.stopVideoRecording()).path);
      } catch (_) {}
      recSlot = null;
      return;
    }
    final max = vmax[recSlot!['id']] ?? 30;
    recAt = DateTime.now();
    recTimer?.cancel();
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
    id == 'video_360' ? _cutSpin(rel) : squeezeVideo(store.abs(rel));
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
      id == 'video_360' ? _cutSpin(rel) : squeezeVideo(store.abs(rel));
      if (widget.args.single) return await _close();
      again || capRet != null ? capResume() : capAdvance();
      _save();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // the frames are cut from the video as recorded, then the video is made smaller
  void _cutSpin(String rel) {
    final id = widget.id;
    cutSpinFrames(store.abs(rel), store.abs(store.dirOf(id))).then((frames) {
      store.mut(id, (s) {
        if (m(s, 'files')['video_360'] == rel) s['spin'] = frames.map((f) => f.substring(store.docs.length + 1)).toList();
      });
    }).catchError((e) => debugPrint('spin: $e')).whenComplete(() => squeezeVideo(store.abs(rel)));
  }

  // retake a picked damage or mod photo: the tag keeps its place and its label
  Future<void> _retakeSel({bool library = false}) async {
    final s = sel!;
    setState(() => busy = true);
    if (!library) _blink();
    try {
      final from = library ? (await ImagePicker().pickImage(source: ImageSource.gallery))?.path : (await cc!.takePicture()).path;
      if (from == null) return;
      if (!library) _blink(taken: true);
      final rel = await keepPhoto(widget.id, from, s.$1 == 'd' ? 'damage' : 'mod', library: library);
      store.mut(widget.id, (x) {
        final e = (s.$1 == 'd' ? manual(x) : (m(x, 'multi')[modslot[k]] ?? []) as List)[s.$2] as Map;
        dropFile(e['f']);
        e['f'] = rel;
        e['src'] = library ? 'library' : 'camera';
      });
      liveFor = null;
      if (widget.args.single) return await _close();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _tag(String t) async {
    if (busy || (cc == null && !noCam) || i >= l.length || tagShut) return;
    sel = null;
    if (showing && !noCam) return setState(() => liveFor = here); // a taken photo is on screen: show the camera first
    setState(() => busy = true);
    if (!noCam) _blink();
    try {
      final at = i, sec = k, x = l[i], home = shotZone(x, k), from = noCam ? (await ImagePicker().pickImage(source: ImageSource.gallery))?.path : (await cc!.takePicture()).path;
      if (from == null) return;
      if (!noCam) _blink(taken: true);
      if (t == 'dmg') {
        // the zone of the shot it was taken at (a paint panel or the roof Exterior, a tire Tires, cargo Interior); the AI picks the
        // place from every place of that zone. A damage shot under the car is read against the underbody places, so it stays on Underbody
        final zone = dzone[home] ?? 'Exterior';
        final did = 'd${DateTime.now().microsecondsSinceEpoch}';
        final rel = await keepPhoto(widget.id, from, 'damage', read: {'kind': 'damage', 'did': did, 'section': home == 'Underbody' ? home : zone});
        store.mut(widget.id, (s) {
          manual(s).add(<String, dynamic>{'id': did, 'zone': zone, 'sec': sec, 'at': at, 'key': slotKey(x), 'panel': '', 'type': '', 'sev': '', 'size': '', 'src': 'camera', 'f': rel});
          syncDamages(s);
        });
        tag = ('dmg', manual(st).where((d) => d['sec'] == sec).length, at);
      } else {
        final rel = await keepPhoto(widget.id, from, 'mod');
        final slot = modslot[sec]!;
        store.mut(widget.id, (s) {
          final a = (m(s, 'multi')[slot] ??= <dynamic>[]) as List;
          // rs: the Review page it shows on; in the walk-around a mod at a tire is a Tires mod, elsewhere an Exterior one
          a.add({'src': 'camera', 'panel': null, 'sec': sec, 'at': at, 'key': slotKey(x), 'rs': sec == 'Tires' ? (x['wheel'] != null ? 'Tires' : 'Exterior') : sec, 'f': rel});
          m(s, 'shots')[slot] = a.length;
        });
        tag = ('mod', ((m(st, 'multi')[slot] ?? []) as List).where((d) => d['sec'] == sec).length, at);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // damage camera (from Damages or Review): every shot is a damage photo of that zone
  Future<void> _dmgShot({bool library = false}) async {
    if (busy) return;
    setState(() => busy = true);
    final cam = !(library || noCam);
    if (cam) _blink();
    try {
      final from = cam ? (await cc!.takePicture()).path : (await ImagePicker().pickImage(source: ImageSource.gallery))?.path;
      if (from == null) return;
      if (cam) _blink(taken: true);
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
        // typed open: labels add true/false and the AI guess a map (a literal of only strings would be Map<String, String> and throw)
        final d = <String, dynamic>{'id': did, 'zone': dzone[zone] ?? zone, if (zone == 'Underbody') 'tab': zone, 'panel': '', 'type': '', 'sev': '', 'size': '', 'src': library ? 'library' : 'camera', 'f': rel};
        if (hint != null) setLabel(d, 'panel', hint, fuelOf(s));
        manual(s).add(d);
        syncDamages(s);
      });
      if (mounted) Navigator.of(context).pop(did);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _cycleFlash() async {
    setState(() => flashMode = {FlashMode.auto: FlashMode.always, FlashMode.always: FlashMode.off}[flashMode] ?? FlashMode.auto);
    final c = cc;
    if (c != null) await _applyFlash(c);
  }

  Future<void> _applyFlash(CameraController c) async {
    try {
      await c.setFlashMode(flashMode);
    } on CameraException catch (e) {
      debugPrint('flash: $e'); // a lens without a flash
    }
  }

  // the flash chip, beside the zoom chips; hidden on a video slot (the photo flash does not light a video)
  Widget _flashChip() {
    final on = flashMode == FlashMode.always;
    return Semantics(
      label: 'Flash ${{FlashMode.auto: 'auto', FlashMode.always: 'on'}[flashMode] ?? 'off'}',
      button: true,
      child: GestureDetector(
        onTap: cc == null || capturing ? null : _cycleFlash,
        child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(shape: BoxShape.circle, color: on ? Colors.black : Colors.black45),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(flashMode == FlashMode.off ? LucideIcons.zapOff : LucideIcons.zap, size: 18, color: on ? const Color(0xFFFACC15) : Colors.white),
            if (flashMode == FlashMode.auto) const Text('A', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }

  Future<void> _setZoom(double z) async {
    final c = cc;
    if (c == null) return;
    final switchLens = (z == .5) != (zoom == .5) && ultra != null;
    if (switchLens && capturing) return;
    zoom = z;
    if (switchLens) return _open(lens);
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

    // the damage and mod tags of this section, each after the shot it was taken at
    final mods = (m(st, 'multi')[modslot[k]] ?? []) as List;
    final dj = [for (final dm in manual(st)) dm['sec'] == k ? tagAt(st, dm) : null], mj = [for (final e in mods) e['sec'] == k ? tagAt(st, e as J) : null];
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
        if (dj[d] == j) out.add(cell(const Icon(LucideIcons.triangleAlert, color: Colors.white, size: 18), bg: const Color(0xFFC2410C), cur: sel == ('d', d), on: rec ? null : () => setState(() => sel = ('d', d))));
      }
      for (var d = 0; d < mods.length; d++) {
        if (mj[d] == j) out.add(cell(const Icon(LucideIcons.wrench, color: Colors.white, size: 18), bg: modBlue, cur: sel == ('m', d), on: rec ? null : () => setState(() => sel = ('m', d))));
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
    _matchKind();
    return PopScope(
      canPop: !rec,
      onPopInvokedWithResult: (did, _) {
        if (did) _save();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false, // the Engine codes keyboard opens over the camera; nothing here moves for it
        body: Stack(fit: StackFit.expand, children: [
          if (c != null && c.value.isInitialized)
            GestureDetector(
              onScaleStart: (_) => pinch0 = zoom == .5 ? 1 : zoom,
              onScaleUpdate: (d) {
                final z = (pinch0 * d.scale).clamp(minZ, maxZ);
                if (zoom != .5) c.setZoomLevel(z);
              },
              child: FittedBox(fit: BoxFit.contain, child: SizedBox(width: 100 * _previewRatio(c), height: 100, child: CameraPreview(c))),
            ),
          // on black: a photo of another shape (a phone screenshot) does not show the live camera beside it
          if (showing) Positioned.fill(child: ColoredBox(color: Colors.black, child: Image.file(File(store.abs(shown!)), fit: BoxFit.contain, cacheWidth: 1600, gaplessPlayback: true, key: ValueKey(shown)))),
          if (flash) Container(color: Colors.white54),
          SafeArea(child: dmgMode ? _dmgLayout() : _passLayout()),
          if (ask && !dmgMode) _askCard(),
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
            child: Row(children: [_btn(LucideIcons.chevronLeft, () => Navigator.of(context).pop()), const Spacer(), _pill(zoneTitle[zone]!.replaceAll('damages', 'damage')), const Spacer(), SizedBox(width: 46, child: _flashChip())]),
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
        Expanded(child: Center(child: _pill('${run && camseq.contains(k) ? '${camseq.indexOf(k) + 1}/${camseq.length}  ' : ''}${i < n && !free && !ask ? '${shotTitle(list[i], k)} · ${i + 1} of $n' : camTitle(k)}', bg: banner ? bid : Colors.black54))),
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
    final tagOk = !widget.args.single, tagOff = tagShut || busy || (cc == null && !noCam) || rec;
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
              // Look for: a few words top left of a guided shot, information only (hidden in Record damage, under the questions, on a tag)
              if (k != 'start' && !free && !ask && sel == null && lookOf(x) != null) Positioned(left: 8, top: 4, child: IgnorePointer(child: _look(lookOf(x)!))),
              if (k != 'start')
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (!wantVideo) _flashChip(),
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
    ]);
  }

  Widget _look(List<String> l) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        decoration: BoxDecoration(color: const Color(0xB3000000), borderRadius: BorderRadius.circular(14)),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(bottom: 2), child: Text('LOOK FOR', style: TextStyle(color: Color(0xA6FFFFFF), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .66))),
          for (final t in l)
            SizedBox(
              height: 26,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Text(t, softWrap: false, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
        ]),
      );

  // Next at the end of a section: the next camera section, or Damages / Review after the last
  String get nextLabel {
    final nk = nextSection(st, k);
    return nk != null && camseq.contains(nk) ? 'Next: ${camTitle(nk)}' : manual(st).isNotEmpty ? 'Next: Damages' : 'Next: Review';
  }

  // the end-of-section questions over the camera (docs/11): the section's questions from Review, each OK until tapped, required
  // rows Pick until answered; a tap opens the same drawer as Review, drawn dark. Record damage keeps the camera with only the
  // Damage and Mod shutters and Next at the top right; Next goes on to the next section
  Widget _askCard() {
    const icons = {'Interior': LucideIcons.armchair, 'Tires': LucideIcons.car, 'Mechanicals': LucideIcons.wrench, 'Underbody': LucideIcons.layers};
    final cx = context; // the camera's own context: drawers opened from a row stay valid while the card redraws
    return Stack(key: const ValueKey('ask'), children: [
      const ModalBarrier(dismissible: false, color: Color(0xA6000000)),
      SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(color: dkCard, borderRadius: BorderRadius.circular(18)),
            child: DarkRows(
              child: ListenableBuilder(
                listenable: store,
                builder: (c, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Icon(icons[k] ?? LucideIcons.camera, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(camTitle(k), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        for (final g in askGroups(st, k)) ...[
                          if (g.head != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(2, 4, 0, 6),
                              child: Text(g.head!.toUpperCase(), style: const TextStyle(color: dkSub, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .66)),
                            ),
                          RowList([
                            if (g.feat) ...featRows(cx, widget.id, st, dark: true),
                            ...checkRowItems(cx, widget.id, st, g.checks, w: g.w, dark: true, labels: g.w != null ? const {'ck_tire': 'Tire', 'ck_wheel': 'Wheel'} : const {}),
                            if (g.tm) tmRow(cx, widget.id, st, dark: true),
                          ]),
                          const SizedBox(height: 6),
                        ],
                      ]),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                        child: darkBtn('Record damage', () => setState(() {
                              ask = false;
                              free = true;
                              tag = null;
                              // an answer on the card may have shortened the list (Will not start drops the engine videos)
                              if (l.isNotEmpty && i >= l.length) i = l.length - 1;
                            }), icon: LucideIcons.triangleAlert)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: darkBtn(nextLabel, () => setState(() {
                              ask = false;
                              capGoNext();
                            }), bg: bid)),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
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
    final nextLbl = nextLabel;
    return Column(children: [
      top,
      Expanded(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(miss > 0 ? LucideIcons.triangleAlert : LucideIcons.circleCheck, color: miss > 0 ? amber : const Color(0xFF4ADE80), size: 40),
            const SizedBox(height: 8),
            Text(miss > 0 ? '$miss still to take' : 'All $n taken', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            Text('$got of $n done in ${camTitle(k)}', style: const TextStyle(color: Colors.white70)),
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
