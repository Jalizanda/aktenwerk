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

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
