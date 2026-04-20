import 'package:drift/drift.dart';

/// Messgeräte.
class Geraete extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get inventarNr => text().nullable()();
  TextColumn get bezeichnung => text()();
  TextColumn get kategorie => text().nullable()();
  TextColumn get hersteller => text().nullable()();
  TextColumn get modell => text().nullable()();
  TextColumn get seriennummer => text().nullable()();

  DateTimeColumn get angeschafftAm => dateTime().nullable()();
  RealColumn get anschaffungspreis => real().nullable()();

  /// aktiv | reparatur | ausser_betrieb | verkauft
  TextColumn get status => text().withDefault(const Constant('aktiv'))();

  /// Eichpflicht: keine | empfohlen | pflicht
  TextColumn get eichpflicht =>
      text().withDefault(const Constant('empfohlen'))();
  DateTimeColumn get kalibriertAm => dateTime().nullable()();
  DateTimeColumn get naechsteKalibrierung => dateTime().nullable()();

  /// Intervall in Monaten zwischen Kalibrierungen.
  IntColumn get eichungIntervall => integer().nullable()();
  TextColumn get pruefstelle => text().nullable()();
  TextColumn get zertifikatNr => text().nullable()();

  TextColumn get messbereich => text().nullable()();
  TextColumn get genauigkeit => text().nullable()();
  TextColumn get norm => text().nullable()();

  TextColumn get standort => text().nullable()();
  BoolColumn get aktiv => boolean().withDefault(const Constant(true))();

  /// Kalibrierschein-PDF (Firebase Storage).
  TextColumn get kalibrierscheinStorageUrl => text().nullable()();
  TextColumn get kalibrierscheinDateiname => text().nullable()();
  TextColumn get kalibrierscheinMimeType => text().nullable()();
  IntColumn get kalibrierscheinGroesse => integer().nullable()();

  /// Bedienungsanleitung / Handbuch (Firebase Storage).
  TextColumn get handbuchStorageUrl => text().nullable()();
  TextColumn get handbuchDateiname => text().nullable()();
  TextColumn get handbuchMimeType => text().nullable()();
  IntColumn get handbuchGroesse => integer().nullable()();

  /// Geräte-Foto (Produktbild).
  TextColumn get fotoStorageUrl => text().nullable()();
  TextColumn get fotoDateiname => text().nullable()();

  TextColumn get notiz => text().nullable()();
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
