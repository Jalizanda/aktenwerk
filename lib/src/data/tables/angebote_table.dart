import 'package:drift/drift.dart';
import 'kunden_table.dart';

/// Angebote.
class Angebote extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get angebotsnummer => text().nullable()();

  IntColumn get kundeId =>
      integer().nullable().references(Kunden, #id, onDelete: KeyAction.setNull)();

  TextColumn get betreff => text().nullable()();
  DateTimeColumn get datum => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get gueltigBis => dateTime().nullable()();

  TextColumn get status => text().withDefault(const Constant('entwurf'))();

  RealColumn get netto => real().withDefault(const Constant(0))();
  RealColumn get ustSatz => real().withDefault(const Constant(19))();
  RealColumn get ustBetrag => real().withDefault(const Constant(0))();
  RealColumn get brutto => real().withDefault(const Constant(0))();

  /// Positionen als JSON-Array.
  TextColumn get positionenJson => text().nullable()();

  TextColumn get kopftext => text().nullable()();
  TextColumn get fusstext => text().nullable()();
  TextColumn get notiz => text().nullable()();
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
