import 'package:drift/drift.dart';

/// DATEV-Buchungskonten aus SKR03 oder SKR04.
class Konten extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Kontonummer, z. B. '8400' (Erlöse 19 % USt).
  TextColumn get nummer => text()();

  /// Sprechende Bezeichnung, z. B. 'Erlöse 19 % USt'.
  TextColumn get bezeichnung => text()();

  /// 'SKR03' oder 'SKR04'.
  TextColumn get skr => text().withDefault(const Constant('SKR03'))();

  /// Grobe Kategorie: 'ertrag' | 'aufwand' | 'bestand' | 'umsatzsteuer' |
  /// 'finanz' | 'sonstiges'.
  TextColumn get kategorie =>
      text().withDefault(const Constant('sonstiges'))();

  /// USt-Satz in Prozent (z. B. 19, 7, 0) — für automatische Zuordnung.
  RealColumn get ustSatz => real().nullable()();

  BoolColumn get aktiv => boolean().withDefault(const Constant(true))();

  TextColumn get notiz => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
