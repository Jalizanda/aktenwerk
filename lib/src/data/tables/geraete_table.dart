import 'package:drift/drift.dart';

/// Messgeräte.
class Geraete extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get bezeichnung => text()();
  TextColumn get hersteller => text().nullable()();
  TextColumn get modell => text().nullable()();
  TextColumn get seriennummer => text().nullable()();

  DateTimeColumn get angeschafftAm => dateTime().nullable()();
  DateTimeColumn get kalibriertAm => dateTime().nullable()();
  DateTimeColumn get naechsteKalibrierung => dateTime().nullable()();

  TextColumn get messbereich => text().nullable()();
  TextColumn get genauigkeit => text().nullable()();

  TextColumn get standort => text().nullable()();
  BoolColumn get aktiv => boolean().withDefault(const Constant(true))();

  TextColumn get notiz => text().nullable()();
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
