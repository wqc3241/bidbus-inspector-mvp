// 360 view on Review Exterior: the 36 frames cut on the phone, shown in Scaleflex cloudimage-360-view
// (assets/ci360, v4.9.5, MIT). Bundled and loaded from the phone, so it works offline. Drag to turn; the frame number shows.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'ui.dart';

const _sides = ['Left front corner', 'Left side', 'Left rear corner', 'Rear', 'Right rear corner', 'Right side', 'Right front corner', 'Front'];

class SpinView extends StatefulWidget {
  final List<String> frames; // absolute paths, spin-01.jpg to spin-36.jpg in one folder
  const SpinView(this.frames, {super.key});
  @override
  State<SpinView> createState() => _SpinViewState();
}

class _SpinViewState extends State<SpinView> {
  final c = WebViewController();
  int f = 0;

  @override
  void initState() {
    super.initState();
    c
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel('Frame', onMessageReceived: (m) => setState(() => f = int.tryParse(m.message) ?? f));
    final p = c.platform;
    if (p is AndroidWebViewController) p.setAllowFileAccess(true);
    _load();
  }

  Future<void> _load() async {
    final dir = File(widget.frames.first).parent.path, names = widget.frames.map((x) => x.split('/').last).toList();
    File('$dir/ci360.min.js').writeAsStringSync(await rootBundle.loadString('assets/ci360/js-cloudimage-360-view.min.js'));
    final html = File('$dir/spin.html')
      ..writeAsStringSync('''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<style>html,body{margin:0;background:#fff}#v{width:100%}</style></head><body><div id="v"></div>
<script>/* the frames are files on the phone: a CORS image load from a file page fails, so plain loads */
Object.defineProperty(HTMLImageElement.prototype, 'crossOrigin', {set: function () {}, get: function () { return null; }});</script>
<script src="ci360.min.js"></script>
<script>CI360.init(document.getElementById('v'), {imageListX: ${names.map((n) => '"$n"').toList()}, amountX: ${names.length}, aspectRatio: '16/9',
  hints: false, initialIconShown: false, zoomControls: false, fullscreen: false, lazyload: false,
  onSpin: function (e) { Frame.postMessage(String(e.activeImageX)); }});</script></body></html>''');
    await c.loadFile(html.path);
  }

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        AspectRatio(aspectRatio: 16 / 9, child: ClipRRect(borderRadius: BorderRadius.circular(12), child: WebViewWidget(controller: c, gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())}))),
        const SizedBox(height: 8),
        Text('Frame ${f + 1} of ${widget.frames.length} · ${_sides[(f / 4.5).round() % 8]}', style: const TextStyle(color: muted)),
      ]);
}
