import 'package:drift/drift.dart';

/// Benutzer / Sachverständiger.
class Benutzer extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get anrede => text().nullable()();
  TextColumn get titel => text().nullable()();
  TextColumn get vorname => text().nullable()();
  TextColumn get nachname => text().nullable()();
  TextColumn get firma => text().nullable()();

  TextColumn get strasse => text().nullable()();
  TextColumn get plz => text().nullable()();
  TextColumn get ort => text().nullable()();

  TextColumn get telefon => text().nullable()();
  TextColumn get mobil => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get website => text().nullable()();

  TextColumn get steuerNr => text().nullable()();
  TextColumn get ustId => text().nullable()();
  TextColumn get iban => text().nullable()();
  TextColumn get bic => text().nullable()();
  TextColumn get bank => text().nullable()();

  TextColumn get bestellungsText => text().nullable()();
  RealColumn get standardStundensatz => real().nullable()();

  TextColumn get unterschriftPfad => text().nullable()();
  TextColumn get logoPfad => text().nullable()();

  BoolColumn get aktiv => boolean().withDefault(const Constant(true))();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
