import 'package:drift/drift.dart';
import 'auftraege_table.dart';
import 'partner_table.dart';

/// Stunden-Buchungen pro Auftrag.
class Stunden extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().nullable().references(Auftraege, #id, onDelete: KeyAction.cascade)();

  /// Partner/Subunternehmer, der die Leistung erbracht hat. Wenn gesetzt
  /// zählt die Buchung als Fremdleistung (nicht in eigene Stunden-KPIs).
  IntColumn get partnerId =>
      integer().nullable().references(Partner, #id, onDelete: KeyAction.setNull)();

  DateTimeColumn get datum => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get beginn => dateTime().nullable()();
  DateTimeColumn get ende => dateTime().nullable()();

  /// Effektive Dauer in Minuten.
  IntColumn get minuten => integer().withDefault(const Constant(0))();
  RealColumn get satz => real().nullable()();

  TextColumn get taetigkeit => text().nullable()();
  TextColumn get notiz => text().nullable()();

  BoolColumn get abgerechnet =>
      boolean().withDefault(const Constant(false))();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
