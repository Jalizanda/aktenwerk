import 'package:drift/drift.dart';
import 'auftraege_table.dart';

/// Ortstermin-Protokolle: Anwesenheitsliste + Protokolltext für jeden
/// Ortstermin einer Akte. Wird als A4-PDF mit Unterschriftslinien und
/// QR-Code zur digitalen Bestätigung gedruckt.
class Protokolle extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().references(Auftraege, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get datum => dateTime().withDefault(currentDateAndTime)();

  /// Dauer in Minuten (gemessen am Timer oder manuell gesetzt).
  IntColumn get dauerMinuten => integer().withDefault(const Constant(0))();

  /// Ort des Ortstermins (freitext, ergänzt `auftrag.objektOrt`).
  TextColumn get ort => text().nullable()();

  /// Wetter / Bedingungen (optional).
  TextColumn get wetter => text().nullable()();

  /// Teilnehmer als JSON-Array:
  /// `[{name, rolle, firma, email, unterschrift?}]`
  TextColumn get teilnehmerJson => text().nullable()();

  /// Protokolltext als Quill-Delta-JSON (optional Plaintext-Fallback).
  TextColumn get protokollJson => text().nullable()();

  /// Komma-separierte Foto-IDs für diesen Termin.
  TextColumn get fotoIds => text().nullable()();
  /// Komma-separierte Dokument-IDs für diesen Termin.
  TextColumn get dokumentIds => text().nullable()();

  TextColumn get status =>
      text().withDefault(const Constant('entwurf'))(); // entwurf | signiert | versendet

  /// Freitext-Notiz zur späteren Nachbearbeitung.
  TextColumn get notiz => text().nullable()();

  /// Archivierte PDF-Version (Firebase Storage).
  TextColumn get pdfStorageUrl => text().nullable()();
  TextColumn get pdfDateiname => text().nullable()();
  DateTimeColumn get pdfErstelltAm => dateTime().nullable()();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
