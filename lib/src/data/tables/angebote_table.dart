import 'package:drift/drift.dart';
import 'auftraege_table.dart';
import 'kunden_table.dart';

/// Angebote.
class Angebote extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get angebotsnummer => text().nullable()();

  IntColumn get kundeId =>
      integer().nullable().references(Kunden, #id, onDelete: KeyAction.setNull)();

  /// Verknüpfung zur Akte. Wenn das Angebot ohne Akte angelegt wird, wird
  /// beim Speichern automatisch eine neue Akte mit AW-Nummer erzeugt.
  IntColumn get auftragId => integer()
      .nullable()
      .references(Auftraege, #id, onDelete: KeyAction.setNull)();

  TextColumn get betreff => text().nullable()();
  DateTimeColumn get datum => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get gueltigBis => dateTime().nullable()();

  /// Anfragenbeschreibung / Sachverhalt vom Kunden.
  TextColumn get anfrage => text().nullable()();

  /// Objekt-Adresse (bei Angeboten ohne verknüpften Auftrag nützlich).
  TextColumn get objektStrasse => text().nullable()();
  TextColumn get objektPlz => text().nullable()();
  TextColumn get objektOrt => text().nullable()();

  /// Hinweise / AGB / Bedingungen (separat vom Fußtext).
  TextColumn get bedingungen => text().nullable()();

  TextColumn get status => text().withDefault(const Constant('entwurf'))();

  RealColumn get netto => real().withDefault(const Constant(0))();
  RealColumn get ustSatz => real().withDefault(const Constant(19))();
  RealColumn get ustBetrag => real().withDefault(const Constant(0))();
  RealColumn get brutto => real().withDefault(const Constant(0))();

  /// Positionen als JSON-Array.
  TextColumn get positionenJson => text().nullable()();

  TextColumn get kopftext => text().nullable()();
  TextColumn get fusstext => text().nullable()();
  TextColumn get notiz => text().nullable()();

  /// Archivierte PDF-Version (Firebase Storage).
  TextColumn get pdfStorageUrl => text().nullable()();
  TextColumn get pdfDateiname => text().nullable()();
  IntColumn get pdfGroesse => integer().nullable()();
  DateTimeColumn get pdfErstelltAm => dateTime().nullable()();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
