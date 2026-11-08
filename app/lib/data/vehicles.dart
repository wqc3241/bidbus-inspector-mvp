// Year, make, model and trim lists for New inspection (assets/vehicles.json, from data/vehicles.json):
// each make's models, each model's trims with the first and last model year they were offered.
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'ql.dart';

const other = 'Other';
List<J> vmakes = [];
int vFirst = 2013, vLast = 2027;

Future<void> loadVehicles() async {
  try {
    initVehicles(jsonDecode(await rootBundle.loadString('assets/vehicles.json')));
  } catch (_) {}
}

void initVehicles(J d) {
  vmakes = (d['makes'] as List).cast<J>();
  vFirst = (d['years'] as List)[0];
  vLast = (d['years'] as List)[1];
}

bool _on(J t, int y) => (t['from'] as int) <= y && y <= (t['to'] as int);
List<J> _models(J mk) => (mk['models'] as List).cast<J>();
List<J> _trims(J md) => (md['trims'] as List).cast<J>();
J? _make(String make) => vmakes.where((m) => m['make'] == make).firstOrNull;
J? _model(String make, String model) => _make(make) == null ? null : _models(_make(make)!).where((m) => m['model'] == model).firstOrNull;

List<String> yearsList() => [for (var y = vLast; y >= vFirst; y--) '$y'];
List<String> makesFor(int year) => [for (final mk in vmakes) if (_models(mk).any((md) => _trims(md).any((t) => _on(t, year)))) mk['make'] as String];
List<String> modelsFor(String make, int year) {
  final mk = _make(make);
  return mk == null ? [] : [for (final md in _models(mk)) if (_trims(md).any((t) => _on(t, year))) md['model'] as String];
}

List<String> trimsFor(String make, String model, int year) {
  final md = _model(make, model);
  return md == null ? [] : {for (final t in _trims(md)) if (_on(t, year)) t['trim'] as String}.toList();
}

// a decoded value matches a list entry ignoring case, spaces and punctuation ("3-Series" = "3 Series", "TESLA" = "Tesla")
String _norm(String? s) => (s ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
String? matchOption(List<String> opts, String? v) => _norm(v).isEmpty ? null : opts.where((o) => _norm(o) == _norm(v)).firstOrNull;
