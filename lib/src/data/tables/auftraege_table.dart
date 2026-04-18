import 'package:drift/drift.dart';
import 'kunden_table.dart';

/// Auftrag / Akte.
/// Art: privat | gericht
class Auftraege extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get aktenzeichen => text().nullable()();
  TextColumn get art => text().withDefault(const Constant('privat'))();
  TextColumn get status => text().withDefault(const Constant('offen'))();

  IntColumn get kundeId =>
      integer().nullable().references(Kunden, #id, onDelete: KeyAction.setNull)();

  TextColumn get bezeichnung => text().nullable()();

  TextColumn get objektStrasse => text().nullable()();
  TextColumn get objektPlz => text().nullable()();
  TextColumn get objektOrt => text().nullable()();
  RealColumn get objektLat => real().nullable()();
  RealColumn get objektLon => real().nullable()();
  RealColumn get objektHoehe => real().nullable()();

  TextColumn get gerichtsAktenzeichen => text().nullable()();
  TextColumn get richter => text().nullable()();
  DateTimeColumn get eingangAm => dateTime().nullable()();
  DateTimeColumn get auftragAm => dateTime().nullable()();
  DateTimeColumn get abschlussAm => dateTime().nullable()();

  RealColumn get stundensatz => real().nullable()();
  RealColumn get kostenLimit => real().nullable()();
  RealColumn get kostenvorschuss => real().nullable()();

  TextColumn get beteiligteJson => text().nullable()();
  TextColumn get notiz => text().nullable()();
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
