import 'package:drift/drift.dart';

/// Lieferanten.
class Lieferanten extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get firma => text()();
  TextColumn get ansprechpartner => text().nullable()();

  TextColumn get strasse => text().nullable()();
  TextColumn get plz => text().nullable()();
  TextColumn get ort => text().nullable()();
  TextColumn get land => text().nullable()();

  TextColumn get telefon => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get website => text().nullable()();

  TextColumn get kategorie => text().nullable()();
  TextColumn get kundennummer => text().nullable()();
  TextColumn get ustId => text().nullable()();

  TextColumn get iban => text().nullable()();
  TextColumn get bic => text().nullable()();

  TextColumn get notiz => text().nullable()();
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
