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
  DateTimeColumn get leistungsdatum => dateTime().nullable()();
  DateTimeColumn get eingangAm => dateTime().nullable()();
  DateTimeColumn get faelligAm => dateTime().nullable()();
  DateTimeColumn get bezahltAm => dateTime().nullable()();

  /// Zahlungsziel in Tagen (vom Rechnungsdatum).
  IntColumn get zahlungszielTage => integer().withDefault(const Constant(14))();
  /// Zahlungsweise: `ueberweisung` | `lastschrift` | `kreditkarte` | `paypal`.
  TextColumn get zahlungsweise =>
      text().withDefault(const Constant('ueberweisung'))();

  /// Skonto in Prozent und Skontofrist in Tagen.
  RealColumn get skontoProzent => real().withDefault(const Constant(0))();
  IntColumn get skontoFristTage =>
      integer().withDefault(const Constant(0))();

  TextColumn get status => text().withDefault(const Constant('offen'))();

  TextColumn get kategorie => text().nullable()();
  TextColumn get beschreibung => text().nullable()();

  /// SKR-Konto und Kostenstelle (für DATEV-Export).
  TextColumn get datevKonto => text().nullable()();
  TextColumn get datevKostenstelle => text().nullable()();

  /// Lieferanten-Daten **redundant** abgelegt, damit die Rechnung auch dann
  /// gelesen werden kann, wenn der Lieferant später gelöscht wird.
  TextColumn get lieferantName => text().nullable()();
  TextColumn get lieferantStrasse => text().nullable()();
  TextColumn get lieferantPlz => text().nullable()();
  TextColumn get lieferantOrt => text().nullable()();
  TextColumn get lieferantUstId => text().nullable()();

  RealColumn get netto => real().withDefault(const Constant(0))();
  RealColumn get ustSatz => real().withDefault(const Constant(19))();
  RealColumn get ustBetrag => real().withDefault(const Constant(0))();
  RealColumn get brutto => real().withDefault(const Constant(0))();
  RealColumn get bezahlt => real().withDefault(const Constant(0))();

  /// JSON-Array mit mehreren Belegen: `[{filename, storageUrl, mimeType}]`.
  TextColumn get belegeJson => text().nullable()();
  TextColumn get belegPfad => text().nullable()();
  TextColumn get notiz => text().nullable()();
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
