// Copies the question list, issue catalog and camera guides from the repo into app/assets.
// Run from app/: dart run tool/sync_assets.dart
import 'dart:io';

void main() {
  final root = Directory('..').absolute;
  final out = Directory('assets/guides')..createSync(recursive: true);
  for (final f in ['question-list.json', 'issue-catalog.json']) {
    File('${root.path}/data/$f').copySync('assets/$f');
  }
  for (final f in Directory('${root.path}/guides/svg').listSync().whereType<File>()) {
    if (f.path.endsWith('.svg')) f.copySync('${out.path}/${f.uri.pathSegments.last}');
  }
  stdout.writeln('assets synced');
}
