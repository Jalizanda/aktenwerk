import 'package:drift/drift.dart';

/// Normen-Katalog (DIN, EN, ISO, VOB ...).
class Normen extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get nummer => text()();
  TextColumn get titel => text().nullable()();
  TextColumn get ausgabe => text().nullable()();
  TextColumn get kategorie => text().nullable()();

  TextColumn get beschreibung => text().nullable()();
  TextColumn get notiz => text().nullable()();

  BoolColumn get aktiv => boolean().withDefault(const Constant(true))();
  BoolColumn get favorit => boolean().withDefault(const Constant(false))();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
