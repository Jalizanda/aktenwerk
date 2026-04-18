import 'package:drift/drift.dart';

/// Fortbildungen / Nachweise.
class Fortbildungen extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get titel => text()();
  TextColumn get veranstalter => text().nullable()();
  TextColumn get ort => text().nullable()();

  DateTimeColumn get datumVon => dateTime().nullable()();
  DateTimeColumn get datumBis => dateTime().nullable()();
  RealColumn get stunden => real().withDefault(const Constant(0))();
  RealColumn get kosten => real().withDefault(const Constant(0))();

  TextColumn get thema => text().nullable()();
  TextColumn get nachweisPfad => text().nullable()();

  TextColumn get notiz => text().nullable()();
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
