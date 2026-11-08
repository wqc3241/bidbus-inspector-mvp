// drift (SQLite): one row per inspection holding its whole state as JSON (answers, photos, damages, tires, paint,
// features, signature, times, GPS, phase, AI queue and upload progress), and a settings table.
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'db.g.dart';

class Inspections extends Table {
  TextColumn get id => text()();
  TextColumn get json => text()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Inspections, Settings])
class Db extends _$Db {
  Db([QueryExecutor? e]) : super(e ?? driftDatabase(name: 'bidbus_field'));
  @override
  int get schemaVersion => 1;

  Future<List<Inspection>> all() => select(inspections).get();
  Future<void> put(String id, String json) => into(inspections).insertOnConflictUpdate(InspectionsCompanion.insert(id: id, json: json, updatedAt: DateTime.now()));
  Future<Map<String, String>> settingsMap() async => {for (final r in await select(settings).get()) r.key: r.value};
  Future<void> setSetting(String k, String v) => into(settings).insertOnConflictUpdate(SettingsCompanion.insert(key: k, value: v));
}
