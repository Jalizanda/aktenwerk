import 'package:drift/drift.dart';
import 'auftraege_table.dart';

/// Verkehrswert-Ermittlung nach ImmoWertV (Sachwert- + Vergleichswert-
/// Verfahren). Liefert Sachwert, Vergleichswert und Marktwert. Kann als
/// Berechnungs-Anlage ins Gutachten eingefügt werden.
class Wertermittlungen extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().references(Auftraege, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get stichtag => dateTime().withDefault(currentDateAndTime)();

  // --- Grundstück ---
  RealColumn get bodenrichtwert => real().nullable()();
  RealColumn get grundstueckFlaeche => real().nullable()();

  // --- Sachwertverfahren ---
  /// Bruttogrundfläche in m².
  RealColumn get bgf => real().nullable()();
  /// Normalherstellungskosten (€/m² BGF) inkl. Baunebenkosten.
  RealColumn get nhk => real().nullable()();
  /// Alterswertminderung (0..1).
  RealColumn get altersminderungFaktor => real().nullable()();
  /// Marktanpassung (0..n, z.B. 0.9 für -10%).
  RealColumn get marktanpassungFaktor => real().nullable()();

  // --- Vergleichswertverfahren ---
  RealColumn get vergleichswert => real().nullable()();

  // --- Ergebnisse ---
  RealColumn get sachwert => real().nullable()();
  RealColumn get marktwert => real().nullable()();

  TextColumn get berechnungJson => text().nullable()();
  TextColumn get bemerkung => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
