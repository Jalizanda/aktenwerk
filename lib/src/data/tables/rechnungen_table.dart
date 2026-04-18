import 'package:drift/drift.dart';
import 'auftraege_table.dart';
import 'kunden_table.dart';

/// Ausgangsrechnung.
class Rechnungen extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get rechnungsnummer => text().nullable()();

  IntColumn get auftragId =>
      integer().nullable().references(Auftraege, #id, onDelete: KeyAction.setNull)();
  IntColumn get kundeId =>
      integer().nullable().references(Kunden, #id, onDelete: KeyAction.setNull)();

  DateTimeColumn get rechnungsdatum => dateTime().nullable()();
  DateTimeColumn get leistungsdatum => dateTime().nullable()();
  DateTimeColumn get faelligAm => dateTime().nullable()();
  DateTimeColumn get bezahltAm => dateTime().nullable()();

  TextColumn get status => text().withDefault(const Constant('offen'))();

  RealColumn get netto => real().withDefault(const Constant(0))();
  RealColumn get ustSatz => real().withDefault(const Constant(19))();
  RealColumn get ustBetrag => real().withDefault(const Constant(0))();
  RealColumn get brutto => real().withDefault(const Constant(0))();
  RealColumn get bezahlt => real().withDefault(const Constant(0))();

  /// Positionen als JSON-Array (num, bezeichnung, menge, einheit, preis, summe)
  TextColumn get positionenJson => text().nullable()();

  TextColumn get kopftext => text().nullable()();
  TextColumn get fusstext => text().nullable()();
  TextColumn get notiz => text().nullable()();
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
