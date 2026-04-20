import 'package:drift/drift.dart';
import 'auftraege_table.dart';
import 'kunden_table.dart';

/// Anschreiben.
class Anschreiben extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().nullable().references(Auftraege, #id, onDelete: KeyAction.setNull)();
  IntColumn get kundeId =>
      integer().nullable().references(Kunden, #id, onDelete: KeyAction.setNull)();

  TextColumn get betreff => text().nullable()();
  DateTimeColumn get datum => dateTime().withDefault(currentDateAndTime)();

  /// Briefanrede, z. B. "Sehr geehrte Frau Müller,".
  TextColumn get anrede => text().nullable()();
  /// Grußformel, z. B. "Mit freundlichen Grüßen".
  TextColumn get gruss => text().nullable()();
  /// Plain-Text-Brieftext (falls ohne Quill gewünscht).
  TextColumn get briefText => text().nullable()();

  /// Rich-Text (Quill Delta JSON).
  TextColumn get inhaltJson => text().nullable()();

  TextColumn get status => text().withDefault(const Constant('entwurf'))();
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
