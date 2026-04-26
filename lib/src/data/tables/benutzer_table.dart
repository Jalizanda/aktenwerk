import 'package:drift/drift.dart';

/// Benutzer / Sachverständiger.
class Benutzer extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get anrede => text().nullable()();
  TextColumn get titel => text().nullable()();
  TextColumn get vorname => text().nullable()();
  TextColumn get nachname => text().nullable()();
  TextColumn get firma => text().nullable()();

  TextColumn get strasse => text().nullable()();
  TextColumn get plz => text().nullable()();
  TextColumn get ort => text().nullable()();

  TextColumn get telefon => text().nullable()();
  TextColumn get mobil => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get website => text().nullable()();

  TextColumn get steuerNr => text().nullable()();
  TextColumn get ustId => text().nullable()();
  TextColumn get hrb => text().nullable()();
  TextColumn get iban => text().nullable()();
  TextColumn get bic => text().nullable()();
  TextColumn get bank => text().nullable()();

  TextColumn get bestellungsText => text().nullable()();
  RealColumn get standardStundensatz => real().nullable()();

  TextColumn get unterschriftPfad => text().nullable()();
  TextColumn get logoPfad => text().nullable()();

  /// Profilbild als Base64 (Avatar).
  TextColumn get profilBildBase64 => text().nullable()();
  TextColumn get profilBildMime => text().nullable()();

  /// Persönliche Grußformel (z. B. "Mit freundlichen Grüßen\nDr. …").
  TextColumn get grussformel => text().nullable()();

  BoolColumn get aktiv => boolean().withDefault(const Constant(true))();

  /// Rolle im Mandanten: 'admin' | 'mitarbeiter' | 'readonly'.
  TextColumn get rolle => text().withDefault(const Constant('mitarbeiter'))();

  /// Komma-getrennte Liste erlaubter Module (z.B. "auftraege,rechnungen,...").
  /// `null` = Admin (alle Module). Leer = keine. Vollständige Liste = alle.
  TextColumn get erlaubteModule => text().nullable()();

  /// Bearbeitungsrecht pro Modul (komma-getrennt). Nur diese Module dürfen
  /// editiert werden; in anderen erlaubten Modulen ist nur Read-Only erlaubt.
  TextColumn get bearbeitbareModule => text().nullable()();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
