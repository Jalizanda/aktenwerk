import 'package:drift/drift.dart';

/// Artikel / Leistungs-Katalog.
class Artikel extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get nummer => text().nullable()();
  TextColumn get bezeichnung => text()();
  TextColumn get beschreibung => text().nullable()();
  TextColumn get kategorie => text().nullable()();

  TextColumn get einheit => text().nullable()();
  RealColumn get einzelpreis => real().withDefault(const Constant(0))();
  RealColumn get ustSatz => real().withDefault(const Constant(19))();

  /// Aufschlag in Prozent (z. B. für Handelskalkulation).
  RealColumn get aufschlag => real().withDefault(const Constant(0))();

  /// Standard-Menge, wenn der Artikel in Rechnungen/Angeboten eingefügt wird.
  RealColumn get standardMenge =>
      real().withDefault(const Constant(1))();

  /// Komma-getrennte Tags für Filter/Suche.
  TextColumn get tags => text().nullable()();

  /// Unter-Leistungen / Kalkulationspositionen als JSON-Array.
  TextColumn get kalkulationJson => text().nullable()();

  BoolColumn get aktiv => boolean().withDefault(const Constant(true))();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
