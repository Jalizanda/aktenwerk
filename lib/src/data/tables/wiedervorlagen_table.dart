import 'package:drift/drift.dart';
import 'auftraege_table.dart';

/// Wiedervorlagen / Aufgaben.
class Wiedervorlagen extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().nullable().references(Auftraege, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get faelligAm => dateTime().withDefault(currentDateAndTime)();
  /// Ende eines Termin-Slots (optional). Wenn gesetzt, wird der Termin
  /// als Zeit-Block "von–bis" dargestellt.
  DateTimeColumn get endeAm => dateTime().nullable()();
  DateTimeColumn get erledigtAm => dateTime().nullable()();

  TextColumn get titel => text()();
  /// Anlass / Grund der Wiedervorlage (kurze Auslöse-Beschreibung).
  TextColumn get anlass => text().nullable()();
  TextColumn get beschreibung => text().nullable()();
  TextColumn get prioritaet => text().withDefault(const Constant('normal'))();
  BoolColumn get erledigt => boolean().withDefault(const Constant(false))();

  TextColumn get extras => text().nullable()();

  /// Wiederholungs-Regel nach iCal-RRULE-Kurzform — z.B.
  /// "FREQ=WEEKLY;INTERVAL=1" oder "FREQ=MONTHLY;BYMONTHDAY=15".
  /// Leer = einmalige Wiedervorlage.
  TextColumn get wiederholung => text().nullable()();

  /// Trigger-Typ, wenn die Wiedervorlage automatisch aus einem anderen
  /// Event entstanden ist — z.B. "rechnung.created+3d" für "3 Tage nach
  /// Rechnungsdatum prüfen".
  TextColumn get triggerTyp => text().nullable()();

  /// ID des auslösenden Datensatzes (z.B. Rechnungs-ID) für die Trigger.
  IntColumn get triggerQuellId => integer().nullable()();

  /// Checklisten-Punkte als JSON-Array `[{text, erledigt}]` — wenn gesetzt,
  /// wird die Wiedervorlage als Checkliste dargestellt.
  TextColumn get checklisteJson => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
