import 'package:drift/drift.dart';

/// Manuell gepflegte Einträge für das Befangenheits-Register.
/// Die automatischen Einträge (aus Auftraggeber- und Akten-Daten) sind
/// nicht hier gespeichert; sie werden zur Anzeige direkt aus den
/// jeweiligen Quellen aggregiert.
class BefangenheitsEintraege extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get rolle => text().withDefault(const Constant('Sonstiger'))();
  TextColumn get name => text()();
  TextColumn get firma => text().nullable()();
  TextColumn get anschrift => text().nullable()();
  TextColumn get plz => text().nullable()();
  TextColumn get ort => text().nullable()();
  TextColumn get telefon => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get aktenzeichen => text().nullable()();
  TextColumn get gericht => text().nullable()();
  TextColumn get notiz => text().nullable()();
  DateTimeColumn get datum => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
