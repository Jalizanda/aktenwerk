import 'package:drift/drift.dart';
import 'auftraege_table.dart';

/// Auslagen pro Auftrag.
class Auslagen extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().nullable().references(Auftraege, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get datum => dateTime().withDefault(currentDateAndTime)();

  /// Art der Auslage: fahrt | schreibauslagen | kopie_sw | kopie_farbe |
  /// lichtbilder | porto | fremdleistung | sonstiges
  TextColumn get art => text().nullable()();
  TextColumn get kategorie => text().nullable()();
  TextColumn get beschreibung => text().nullable()();

  RealColumn get menge => real().withDefault(const Constant(1))();
  TextColumn get einheit => text().nullable()();
  RealColumn get einzelpreis => real().withDefault(const Constant(0))();
  RealColumn get summe => real().withDefault(const Constant(0))();

  BoolColumn get abgerechnet =>
      boolean().withDefault(const Constant(false))();

  TextColumn get belegPfad => text().nullable()();
  TextColumn get notiz => text().nullable()();
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
