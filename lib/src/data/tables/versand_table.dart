import 'package:drift/drift.dart';
import 'auftraege_table.dart';

/// Versand-Protokoll (Post, E-Mail, EGVP, Kurier ...).
class Versand extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().nullable().references(Auftraege, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get datum => dateTime().withDefault(currentDateAndTime)();

  TextColumn get art => text().nullable()();
  TextColumn get empfaenger => text().nullable()();
  TextColumn get betreff => text().nullable()();
  TextColumn get inhalt => text().nullable()();
  TextColumn get trackingNr => text().nullable()();

  TextColumn get status => text().withDefault(const Constant('versendet'))();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
