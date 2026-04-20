import 'package:drift/drift.dart';

/// Fortbildungen / Nachweise.
class Fortbildungen extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get titel => text()();
  TextColumn get veranstalter => text().nullable()();
  TextColumn get ort => text().nullable()();
  TextColumn get sachgebiet => text().nullable()();

  DateTimeColumn get datumVon => dateTime().nullable()();
  DateTimeColumn get datumBis => dateTime().nullable()();
  /// Stunden (Unterrichtseinheiten à 45 Min.).
  RealColumn get stunden => real().withDefault(const Constant(0))();
  /// Alias-Feld für das Original (die App schreibt Gebühr, liest Kosten).
  RealColumn get gebuehr => real().withDefault(const Constant(0))();
  RealColumn get kosten => real().withDefault(const Constant(0))();

  TextColumn get thema => text().nullable()();
  TextColumn get nachweisPfad => text().nullable()();

  /// Hochgeladene Teilnahmebescheinigung (Firebase Storage).
  TextColumn get nachweisStorageUrl => text().nullable()();
  TextColumn get nachweisDateiname => text().nullable()();
  TextColumn get nachweisMimeType => text().nullable()();
  IntColumn get nachweisGroesse => integer().nullable()();

  TextColumn get notiz => text().nullable()();
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
