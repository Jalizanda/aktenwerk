import 'package:drift/drift.dart';
import 'auftraege_table.dart';

/// Dokumente (beliebige Dateien pro Auftrag).
class Dokumente extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().nullable().references(Auftraege, #id, onDelete: KeyAction.cascade)();

  TextColumn get titel => text().nullable()();
  TextColumn get beschreibung => text().nullable()();
  TextColumn get kategorie => text().nullable()();

  TextColumn get pfad => text().nullable()();
  TextColumn get mimeType => text().nullable()();
  IntColumn get dateigroesse => integer().nullable()();

  /// Firebase-Storage-Pfad relativ zum Org-Ordner (organizations/{orgId}/pfad).
  TextColumn get storagePfad => text().nullable()();
  /// Öffentliche Download-URL aus Firebase Storage.
  TextColumn get storageUrl => text().nullable()();

  BlobColumn get daten => blob().nullable()();

  DateTimeColumn get datum => dateTime().withDefault(currentDateAndTime)();
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
