// Copies the question list, issue catalog, vehicle list and camera guides from the repo into app/assets.
// Run from app/: dart run tool/sync_assets.dart
// The guides colour their parts with a <style> block (green = the part to shoot); flutter_svg ignores CSS,
// so the rules are written onto each element as attributes here. The source SVGs stay as they are.
import 'dart:io';

void main() {
  final root = Directory('..').absolute;
  final out = Directory('assets/guides')..createSync(recursive: true);
  for (final f in ['question-list.json', 'issue-catalog.json', 'vehicles.json']) {
    final src = File('${root.path}/data/$f');
    if (src.existsSync()) src.copySync('assets/$f');
  }
  for (final f in Directory('${root.path}/guides/svg').listSync().whereType<File>()) {
    if (f.path.endsWith('.svg')) File('${out.path}/${f.uri.pathSegments.last}').writeAsStringSync(inlineCss(f.readAsStringSync()));
  }
  stdout.writeln('assets synced');
}

// the guides' one stylesheet: .pl{stroke-width:1.6;opacity:.5} .hl{stroke:#4ade80;fill:#22c55e33} .hl.ln{fill:none}
// .hlc{stroke:#4ade80;fill:#22c55e} .mt rect:first-child{fill:#0b0d0f} .mini{stroke-width:7} .mini .pl{stroke-width:5}
String inlineCss(String svg) {
  svg = svg.replaceAll(RegExp(r'<metadata>.*?</metadata>', dotAll: true), '').replaceAll(RegExp(r'<style>.*?</style>', dotAll: true), '');
  final out = StringBuffer(), open = <(Set<String>, List<bool>)>[]; // classes of each open element, and whether it has had a child
  var last = 0;
  for (final t in RegExp(r'<(/?)([a-zA-Z]+)([^>]*?)(/?)>').allMatches(svg)) {
    out.write(svg.substring(last, t.start));
    last = t.end;
    if (t[1] == '/') {
      if (open.isNotEmpty) open.removeLast();
      out.write(t[0]);
      continue;
    }
    final tag = t[2]!, selfClose = t[4] == '/';
    var attrs = t[3]!;
    final cls = (RegExp(r'class="([^"]*)"').firstMatch(attrs)?[1] ?? '').split(' ').where((c) => c.isNotEmpty).toSet();
    final parent = open.isEmpty ? null : open.last, first = parent != null && !parent.$2[0];
    if (parent != null) parent.$2[0] = true;
    final inMini = open.any((o) => o.$1.contains('mini'));
    final set = <String, String?>{};
    if (cls.contains('mini')) set['stroke-width'] = '7';
    if (cls.contains('pl')) set.addAll({'stroke-width': inMini ? '5' : '1.6', 'opacity': '0.5'});
    if (cls.contains('hl')) set.addAll(cls.contains('ln') ? {'stroke': '#4ade80', 'fill': 'none', 'fill-opacity': null} : {'stroke': '#4ade80', 'fill': '#22c55e', 'fill-opacity': '0.2'});
    if (cls.contains('hlc')) set.addAll({'stroke': '#4ade80', 'fill': '#22c55e'});
    if (tag == 'rect' && first && parent.$1.contains('mt')) set['fill'] = '#0b0d0f';
    set.forEach((k, v) {
      attrs = attrs.replaceAll(RegExp('\\s$k="[^"]*"'), '');
      if (v != null) attrs += ' $k="$v"';
    });
    out.write('<$tag$attrs${selfClose ? '/' : ''}>');
    if (!selfClose) open.add((cls, [false]));
  }
  out.write(svg.substring(last));
  return out.toString();
}
