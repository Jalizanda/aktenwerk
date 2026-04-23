import 'package:drift/drift.dart';

/// Qualifikations-/Zertifikate-Mappe: zentrale Ablage von Diplomen,
/// Zertifikaten, Prüfungsnachweisen (ift, BAFA, BVS etc.) mit
/// Ablaufdatum. Als Anlage an Gutachten anhängbar.
class Qualifikationen extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get titel => text()();
  TextColumn get aussteller => text().nullable()();

  DateTimeColumn get ausgestelltAm => dateTime().nullable()();
  DateTimeColumn get gueltigBis => dateTime().nullable()();

  /// 'diplom', 'zertifikat', 'pruefung', 'sonstiges'.
  TextColumn get typ => text().withDefault(const Constant('zertifikat'))();

  TextColumn get beschreibung => text().nullable()();

  TextColumn get nachweisStorageUrl => text().nullable()();
  TextColumn get nachweisDateiname => text().nullable()();
  TextColumn get nachweisMimeType => text().nullable()();
  IntColumn get nachweisGroesse => integer().nullable()();

  /// Flag: im PDF-Anhang standardmäßig mit anhängen.
  BoolColumn get standardAnhang => boolean().withDefault(const Constant(false))();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
