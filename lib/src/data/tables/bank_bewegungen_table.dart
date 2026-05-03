import 'package:drift/drift.dart';

/// Bankbewegungen — Kontoauszug-Zeilen importiert aus Volksbank/Sparkasse
/// CSV oder manuell erfasst. Wird im Banking-Modul mit
/// Ausgangs-/Eingangsrechnungen oder Steuern/Privat verknüpft, damit
/// jede Bewegung einen Beleg hat (oder bewusst kein-beleg-pflichtig
/// markiert wird).
class BankBewegungen extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Konto-Bezeichnung („Volksbank Geschäft", „Sparkasse Privat" …).
  TextColumn get konto => text().withDefault(const Constant(''))();
  /// IBAN des eigenen Kontos (für Multi-Konto-Trennung).
  TextColumn get iban => text().nullable()();

  DateTimeColumn get buchungsdatum => dateTime()();
  DateTimeColumn get valuta => dateTime().nullable()();

  /// Verwendungszweck / Buchungstext (mehrere Zeilen möglich).
  TextColumn get verwendungszweck => text().nullable()();
  /// Empfänger / Auftraggeber (Gegenkonto-Name).
  TextColumn get gegenpartei => text().nullable()();
  TextColumn get gegenpartyIban => text().nullable()();
  TextColumn get gegenpartyBic => text().nullable()();

  /// Vorzeichen-richtiger Betrag in EUR. Plus = Eingang, Minus = Ausgang.
  RealColumn get betrag => real()();
  TextColumn get waehrung => text().withDefault(const Constant('EUR'))();

  /// Status der Beleg-Zuordnung:
  ///   `offen`  — noch nichts zugeordnet
  ///   `zugeordnet` — mit Rechnung/Eingangsrechnung verknüpft
  ///   `privat` — gegen Privat verbucht (kein Beleg)
  ///   `kein_beleg` — bewusst ohne Beleg (Kontoführungsgebühr, Steuern…)
  ///   `ignoriert` — soll nicht in Auswertungen einfließen
  TextColumn get status => text().withDefault(const Constant('offen'))();

  /// Wenn zugeordnet: Verweis auf Ausgangs-Rechnung.
  IntColumn get rechnungId => integer().nullable()();
  /// Wenn zugeordnet: Verweis auf Eingangs-Rechnung.
  IntColumn get eingangsrechnungId => integer().nullable()();

  /// DATEV-Konto, falls als kein-beleg-pflichtig oder Privat verbucht
  /// (z. B. „1880 Privatentnahme", „1900 Kontoführungsgebühren",
  /// „1810 Privateinlage" …).
  TextColumn get datevKonto => text().nullable()();

  /// Freie Notiz / Kommentar.
  TextColumn get notiz => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
