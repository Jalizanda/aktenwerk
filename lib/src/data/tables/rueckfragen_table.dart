import 'package:drift/drift.dart';
import 'auftraege_table.dart';

/// Rückfragen an Gericht / Anwalt / Beteiligte.
class Rueckfragen extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().nullable().references(Auftraege, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get datum => dateTime().withDefault(currentDateAndTime)();
  TextColumn get empfaenger => text().nullable()();
  TextColumn get betreff => text().nullable()();
  TextColumn get frage => text().nullable()();
  TextColumn get antwort => text().nullable()();

  TextColumn get status => text().withDefault(const Constant('offen'))();
  DateTimeColumn get erledigtAm => dateTime().nullable()();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
