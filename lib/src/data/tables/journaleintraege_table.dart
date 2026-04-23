import 'package:drift/drift.dart';
import 'auftraege_table.dart';

/// Projekt-Tagebuch je Akte: chronologische Kurzeinträge für Telefonate,
/// Überlegungen, Anfragen, interne Notizen. Klein, schnell, stichpunktartig —
/// kein Dokument, sondern ein reines Ereignis-Log.
class Journaleintraege extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().references(Auftraege, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get zeitpunkt => dateTime().withDefault(currentDateAndTime)();

  /// Freie Kategorie (z.B. "Telefonat", "Mail", "Notiz", "Rückfrage").
  TextColumn get kategorie => text().nullable()();

  /// Gesprächspartner/Kontakt (z.B. Name + Firma).
  TextColumn get kontakt => text().nullable()();

  TextColumn get notiz => text()();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
