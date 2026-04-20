import 'package:drift/drift.dart';
import 'auftraege_table.dart';
import 'kunden_table.dart';

/// Ausgangsrechnung.
class Rechnungen extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get rechnungsnummer => text().nullable()();

  /// Rechnungstyp: privat | jveg | gutschrift | korrektur
  TextColumn get typ => text().withDefault(const Constant('privat'))();

  IntColumn get auftragId =>
      integer().nullable().references(Auftraege, #id, onDelete: KeyAction.setNull)();
  IntColumn get kundeId =>
      integer().nullable().references(Kunden, #id, onDelete: KeyAction.setNull)();

  /// Bezug zur Originalrechnung (bei Gutschrift/Korrektur).
  TextColumn get bezugRechnung => text().nullable()();

  DateTimeColumn get rechnungsdatum => dateTime().nullable()();
  DateTimeColumn get leistungsdatum => dateTime().nullable()();
  /// Leistungsdatum als Freitext (z. B. "10.–20.03.2026").
  TextColumn get leistungszeitraum => text().nullable()();
  DateTimeColumn get faelligAm => dateTime().nullable()();
  DateTimeColumn get bezahltAm => dateTime().nullable()();
  IntColumn get zahlungszielTage =>
      integer().withDefault(const Constant(14))();

  TextColumn get status => text().withDefault(const Constant('offen'))();
  BoolColumn get kleinunternehmerHinweis =>
      boolean().withDefault(const Constant(false))();

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

  /// Archivierte PDF-Version (Firebase Storage).
  TextColumn get pdfStorageUrl => text().nullable()();
  TextColumn get pdfDateiname => text().nullable()();
  IntColumn get pdfGroesse => integer().nullable()();
  DateTimeColumn get pdfErstelltAm => dateTime().nullable()();

  /// DATEV-Erlöskonto (Kontonummer, z. B. '8400'). Bei neuen Rechnungen
  /// automatisch anhand des USt-Satzes vorbelegt.
  TextColumn get kontonummer => text().nullable()();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
