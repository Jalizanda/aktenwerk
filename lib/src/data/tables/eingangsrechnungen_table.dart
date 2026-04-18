import 'package:drift/drift.dart';
import 'auftraege_table.dart';

/// Eingangsrechnungen.
class Eingangsrechnungen extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get rechnungsnummer => text().nullable()();

  IntColumn get lieferantId => integer().nullable()();
  IntColumn get auftragId =>
      integer().nullable().references(Auftraege, #id, onDelete: KeyAction.setNull)();

  DateTimeColumn get rechnungsdatum => dateTime().nullable()();
  DateTimeColumn get eingangAm => dateTime().nullable()();
  DateTimeColumn get faelligAm => dateTime().nullable()();
  DateTimeColumn get bezahltAm => dateTime().nullable()();

  TextColumn get status => text().withDefault(const Constant('offen'))();

  TextColumn get kategorie => text().nullable()();
  TextColumn get beschreibung => text().nullable()();

  RealColumn get netto => real().withDefault(const Constant(0))();
  RealColumn get ustSatz => real().withDefault(const Constant(19))();
  RealColumn get ustBetrag => real().withDefault(const Constant(0))();
  RealColumn get brutto => real().withDefault(const Constant(0))();
  RealColumn get bezahlt => real().withDefault(const Constant(0))();

  TextColumn get belegPfad => text().nullable()();
  TextColumn get notiz => text().nullable()();
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
