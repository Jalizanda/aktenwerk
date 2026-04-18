import 'package:drift/drift.dart';
import 'auftraege_table.dart';

/// Gutachten (Rich-Text, 13 Abschnitte nach Zöller).
class Gutachten extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().nullable().references(Auftraege, #id, onDelete: KeyAction.cascade)();

  TextColumn get titel => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('entwurf'))();

  DateTimeColumn get ortsterminAm => dateTime().nullable()();
  DateTimeColumn get abgabeAm => dateTime().nullable()();

  /// Rich-Text (Quill Delta JSON) pro Abschnitt in einem JSON-Map.
  TextColumn get abschnitteJson => text().nullable()();
  TextColumn get normenJson => text().nullable()();
  TextColumn get geraeteJson => text().nullable()();
  TextColumn get lichtbildanlageJson => text().nullable()();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
