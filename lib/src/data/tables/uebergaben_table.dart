import 'package:drift/drift.dart';
import 'auftraege_table.dart';

/// Aktenübergabe-Protokoll: dokumentiert die Übergabe einer Akte oder
/// eines Gutachten-Teils an einen anderen Sachverständigen/Kollegen.
class Uebergaben extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().references(Auftraege, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get datum => dateTime().withDefault(currentDateAndTime)();

  /// Übergebender Sachverständiger (Name).
  TextColumn get von => text().nullable()();

  /// Übernehmender Sachverständiger (Name).
  TextColumn get an => text().nullable()();

  /// Was wird übergeben (Freitext, z.B. "komplette Akte" / "nur Ortstermin").
  TextColumn get umfang => text().nullable()();

  /// Mitgegebene Unterlagen / Dateien (eine pro Zeile).
  TextColumn get unterlagen => text().nullable()();

  TextColumn get bemerkung => text().nullable()();

  /// Unterschrift-URL oder -Status (z.B. Base64 PNG).
  TextColumn get unterschriftBase64 => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
