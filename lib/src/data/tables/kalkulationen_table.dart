import 'package:drift/drift.dart';
import 'auftraege_table.dart';

/// Kalkulation pro Auftrag.
class Kalkulationen extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().nullable().references(Auftraege, #id, onDelete: KeyAction.cascade)();

  TextColumn get titel => text().nullable()();
  DateTimeColumn get datum => dateTime().withDefault(currentDateAndTime)();

  RealColumn get summe => real().withDefault(const Constant(0))();

  /// Positionen als JSON-Array.
  TextColumn get positionenJson => text().nullable()();

  TextColumn get notiz => text().nullable()();
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
