import 'package:drift/drift.dart';
import 'auftraege_table.dart';
import 'geraete_table.dart';

/// Messwert-Logger: speichert einzelne Messpunkte (Temperatur, Feuchte,
/// Schalldruck, BlowerDoor-Leckagerate …) für eine Akte, optional
/// verknüpft mit dem verwendeten Messgerät. Wird für Zeitverlaufsdiagramme
/// und CSV-Export genutzt.
class Messwerte extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().references(Auftraege, #id, onDelete: KeyAction.cascade)();

  IntColumn get geraetId => integer().nullable().references(Geraete, #id)();

  DateTimeColumn get zeitpunkt => dateTime().withDefault(currentDateAndTime)();

  /// Art der Messung (z.B. "Temperatur", "rel. Feuchte", "Schalldruck").
  TextColumn get groesse => text()();

  /// Einheit der Messung (z.B. "°C", "% r.F.", "dB").
  TextColumn get einheit => text().nullable()();

  RealColumn get wert => real()();

  /// Mess-Serie/Kanal (z.B. Raum A / Raum B oder Kanal 1/2), damit
  /// mehrere Reihen parallel geloggt werden können.
  TextColumn get serie => text().nullable()();

  /// Ort innerhalb des Objekts (z.B. "Schlafzimmer OG").
  TextColumn get ort => text().nullable()();

  TextColumn get bemerkung => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
