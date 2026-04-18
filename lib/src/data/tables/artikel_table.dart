import 'package:drift/drift.dart';

/// Artikel / Leistungs-Katalog.
class Artikel extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get nummer => text().nullable()();
  TextColumn get bezeichnung => text()();
  TextColumn get beschreibung => text().nullable()();
  TextColumn get kategorie => text().nullable()();

  TextColumn get einheit => text().nullable()();
  RealColumn get einzelpreis => real().withDefault(const Constant(0))();
  RealColumn get ustSatz => real().withDefault(const Constant(19))();

  BoolColumn get aktiv => boolean().withDefault(const Constant(true))();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
