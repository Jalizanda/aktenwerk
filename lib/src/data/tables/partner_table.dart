import 'package:drift/drift.dart';

/// Subunternehmer / Partner (z. B. Statik-SV, Schadstoff-Labor, BlowerDoor).
class Partner extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get firma => text()();
  TextColumn get ansprechpartner => text().nullable()();

  /// Fachgebiet: z. B. "Statik", "Schadstoff", "Thermografie".
  TextColumn get fachgebiet => text().nullable()();

  /// Qualifikationen / Zertifikate (freier Text, mehrzeilig).
  TextColumn get qualifikationen => text().nullable()();

  RealColumn get stundensatz =>
      real().withDefault(const Constant(0))();

  TextColumn get strasse => text().nullable()();
  TextColumn get plz => text().nullable()();
  TextColumn get ort => text().nullable()();
  TextColumn get telefon => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get website => text().nullable()();

  TextColumn get ustId => text().nullable()();
  TextColumn get steuerNr => text().nullable()();

  /// Bankverbindung (für Weiterleitung der Zahlung).
  TextColumn get bankInhaber => text().nullable()();
  TextColumn get bankName => text().nullable()();
  TextColumn get iban => text().nullable()();
  TextColumn get bic => text().nullable()();

  /// Rahmenvertrag als PDF (Firebase Storage).
  TextColumn get rahmenvertragStorageUrl => text().nullable()();
  TextColumn get rahmenvertragDateiname => text().nullable()();
  TextColumn get rahmenvertragMimeType => text().nullable()();
  IntColumn get rahmenvertragGroesse => integer().nullable()();

  BoolColumn get aktiv => boolean().withDefault(const Constant(true))();

  TextColumn get notiz => text().nullable()();
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}
