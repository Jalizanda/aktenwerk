import 'package:drift/drift.dart';

/// Lieferanten.
class Lieferanten extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get firma => text()();
  TextColumn get ansprechpartner => text().nullable()();

  TextColumn get strasse => text().nullable()();
  TextColumn get plz => text().nullable()();
  TextColumn get ort => text().nullable()();
  TextColumn get land => text().nullable()();

  TextColumn get telefon => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get website => text().nullable()();

  TextColumn get kategorie => text().nullable()();
  TextColumn get kundennummer => text().nullable()();

  /// DATEV-Kreditorennummer (SKR03/SKR04: 70000–99999).
  TextColumn get kreditornummer => text().nullable()();

  TextColumn get ustId => text().nullable()();
  TextColumn get steuerNr => text().nullable()();

  /// Standard-Zahlungsziel in Tagen (bei neuer Eingangsrechnung vorbefüllt).
  IntColumn get zahlungszielTage =>
      integer().withDefault(const Constant(14))();
  /// Zahlungsweise: `ueberweisung` | `lastschrift` | `kreditkarte` | `paypal`.
  TextColumn get zahlungsweise =>
      text().withDefault(const Constant('ueberweisung'))();

  TextColumn get bank => text().nullable()();
  TextColumn get kontoinhaber => text().nullable()();
  TextColumn get iban => text().nullable()();
  TextColumn get bic => text().nullable()();

  /// SEPA-Mandat (bei Lastschrift).
  TextColumn get glaeubigerId => text().nullable()();
  TextColumn get mandatRef => text().nullable()();

  TextColumn get notiz => text().nullable()();
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
