import 'package:drift/drift.dart';

/// Historie aller versendeten Serienbriefe. Pro Serienbrief-Batch ein
/// Eintrag mit Betreff, Brieftext, Anrede, Grußformel, Versandart und
/// der Liste aller Empfänger-IDs (als JSON). Dient als Quelle, um einen
/// Serienbrief später wieder aufzugreifen und zu kopieren.
class Serienbriefe extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Versand-/Erstellungsdatum.
  DateTimeColumn get datum => dateTime().withDefault(currentDateAndTime)();

  TextColumn get betreff => text().nullable()();
  TextColumn get anrede => text().nullable()();
  TextColumn get gruss => text().nullable()();

  /// Rich-Text-Delta-JSON des Brieftexts.
  TextColumn get inhaltJson => text().nullable()();

  /// 'brief' oder 'mail'.
  TextColumn get versandart => text().withDefault(const Constant('brief'))();

  /// Kundennummern als JSON-Array, damit später „nochmal an dieselben
  /// Empfänger senden" möglich ist.
  TextColumn get empfaengerIdsJson => text().nullable()();

  /// Gesamtanzahl Empfänger bei Versand.
  IntColumn get anzahl => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
