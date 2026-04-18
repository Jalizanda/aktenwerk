import 'package:drift/drift.dart';
import 'auftraege_table.dart';
import 'gutachten_table.dart';

/// Fotos / Lichtbildanlage.
class Fotos extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().nullable().references(Auftraege, #id, onDelete: KeyAction.cascade)();
  IntColumn get gutachtenId =>
      integer().nullable().references(Gutachten, #id, onDelete: KeyAction.setNull)();

  TextColumn get titel => text().nullable()();
  TextColumn get beschreibung => text().nullable()();

  TextColumn get pfad => text().nullable()();
  TextColumn get mimeType => text().nullable()();

  /// Eingebettete Daten (Base64 oder raw) – optional.
  BlobColumn get daten => blob().nullable()();

  DateTimeColumn get aufnahmeAm => dateTime().nullable()();
  RealColumn get lat => real().nullable()();
  RealColumn get lon => real().nullable()();

  IntColumn get reihenfolge => integer().withDefault(const Constant(0))();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
