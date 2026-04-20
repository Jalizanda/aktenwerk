import 'package:drift/drift.dart';

/// Auftraggeber / Kunden.
/// Typen: privat, firma, anwalt, gericht, versicherung, behoerde
class Kunden extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get typ => text().withDefault(const Constant('privat'))();

  TextColumn get anrede => text().nullable()();
  TextColumn get titel => text().nullable()();
  TextColumn get vorname => text().nullable()();
  TextColumn get nachname => text().nullable()();
  TextColumn get firma => text().nullable()();

  TextColumn get strasse => text().nullable()();
  TextColumn get plz => text().nullable()();
  TextColumn get ort => text().nullable()();
  TextColumn get land => text().nullable()();

  TextColumn get telefon => text().nullable()();
  TextColumn get mobil => text().nullable()();
  TextColumn get fax => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get website => text().nullable()();

  TextColumn get steuerNr => text().nullable()();
  TextColumn get ustId => text().nullable()();

  /// Aktenzeichen-Präfix (z.B. "12 OH 4/26" bei Gerichten).
  TextColumn get aktenpraefix => text().nullable()();

  /// DATEV-Debitorennummer (SKR03: 10000–69999, SKR04: 10000–69999).
  TextColumn get debitornummer => text().nullable()();

  TextColumn get notiz => text().nullable()();
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}
