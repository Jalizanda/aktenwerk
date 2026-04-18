import 'package:drift/drift.dart';
import 'auftraege_table.dart';
import 'gutachten_table.dart';

/// Erläuterungstermine (mündliche Erläuterung vor Gericht).
class Erlaeuterungen extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().nullable().references(Auftraege, #id, onDelete: KeyAction.cascade)();
  IntColumn get gutachtenId =>
      integer().nullable().references(Gutachten, #id, onDelete: KeyAction.setNull)();

  DateTimeColumn get terminAm => dateTime().nullable()();
  TextColumn get ort => text().nullable()();

  TextColumn get gericht => text().nullable()();
  TextColumn get saal => text().nullable()();
  TextColumn get richter => text().nullable()();

  TextColumn get status => text().withDefault(const Constant('geplant'))();
  TextColumn get vorbereitung => text().nullable()();
  TextColumn get notiz => text().nullable()();
  TextColumn get protokoll => text().nullable()();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
