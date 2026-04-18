import 'package:drift/drift.dart';

/// Einstellungen (Key-Value Store).
class Einstellungen extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get key => text().unique()();
  TextColumn get wert => text().nullable()();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
