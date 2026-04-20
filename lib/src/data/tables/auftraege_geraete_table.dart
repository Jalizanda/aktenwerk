import 'package:drift/drift.dart';
import 'auftraege_table.dart';
import 'geraete_table.dart';

/// Junction-Tabelle: Welche Messgeräte wurden bei welchem Auftrag eingesetzt?
/// Pro Zuordnung kann zusätzlich das Einsatzdatum erfasst werden.
@DataClassName('AuftragGeraet')
class AuftraegeGeraete extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get auftragId =>
      integer().references(Auftraege, #id, onDelete: KeyAction.cascade)();
  IntColumn get geraetId =>
      integer().references(Geraete, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get eingesetztAm => dateTime().nullable()();
  TextColumn get notiz => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
