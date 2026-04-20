import 'package:drift/drift.dart';

/// Textbausteine.
class Textbausteine extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get kategorie => text().nullable()();
  TextColumn get sachgebiet => text().nullable()();
  TextColumn get titel => text()();
  TextColumn get tags => text().nullable()();

  /// Plain-Text oder Quill Delta JSON.
  TextColumn get inhalt => text().nullable()();

  IntColumn get reihenfolge => integer().withDefault(const Constant(0))();
  BoolColumn get favorit => boolean().withDefault(const Constant(false))();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
