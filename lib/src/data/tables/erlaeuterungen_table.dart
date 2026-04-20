import 'package:drift/drift.dart';
import 'auftraege_table.dart';
import 'gutachten_table.dart';

/// Erläuterungstermine (mündliche Erläuterung vor Gericht).
class Erlaeuterungen extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().nullable().references(Auftraege, #id, onDelete: KeyAction.cascade)();
  IntColumn get gutachtenId =>
      integer().nullable().references(Gutachten, #id, onDelete: KeyAction.setNull)();

  DateTimeColumn get terminAm => dateTime().nullable()();
  DateTimeColumn get ladungsdatum => dateTime().nullable()();
  TextColumn get ort => text().nullable()();

  TextColumn get gericht => text().nullable()();
  TextColumn get gerichtsort => text().nullable()();
  TextColumn get saal => text().nullable()();
  TextColumn get richter => text().nullable()();

  /// Status: geplant/geladen/vorbereitet/durchgefuehrt/verguetet/abgesagt.
  TextColumn get status => text().withDefault(const Constant('geplant'))();

  /// Externes Geschäftszeichen des Gerichts + Parteien im Rubrum.
  TextColumn get azExtern => text().nullable()();
  TextColumn get parteien => text().nullable()();

  // ---------- JVEG-Vergütung (§ 8, § 9 JVEG) ----------
  /// Tatsächliche Termindauer in Stunden.
  RealColumn get dauerStunden => real().withDefault(const Constant(0))();
  /// Wartezeit in Stunden (wird wie Termindauer vergütet).
  RealColumn get wartezeitStunden => real().withDefault(const Constant(0))();
  /// Gefahrene Kilometer.
  RealColumn get fahrtKm => real().withDefault(const Constant(0))();
  /// €/km (Standard: 0,42 € JVEG § 5).
  RealColumn get kmSatz => real().withDefault(const Constant(0.42))();
  /// Honorargruppe (M1/M2/M3 oder frei).
  TextColumn get honorargruppe => text().nullable()();
  /// Stundensatz in € (JVEG § 9).
  RealColumn get stundensatz => real().withDefault(const Constant(0))();
  /// Datum der Auszahlung / Festsetzung.
  DateTimeColumn get vergueteAm => dateTime().nullable()();

  TextColumn get vorbereitung => text().nullable()();
  TextColumn get notiz => text().nullable()();
  TextColumn get protokoll => text().nullable()();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
