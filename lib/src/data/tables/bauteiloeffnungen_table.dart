import 'package:drift/drift.dart';
import 'auftraege_table.dart';

/// Bauteilöffnungs-Protokoll: dokumentiert jede vorgenommene Öffnung
/// eines Bauteils bei einem Ortstermin (Dachziegel entfernt, Fliese
/// abgenommen, Estrich aufgemeißelt …). Enthält Lage, Methode, anwesende
/// Personen sowie Fotos vor/nach der Öffnung.
class Bauteiloeffnungen extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().references(Auftraege, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get datum => dateTime().withDefault(currentDateAndTime)();

  /// Bauteil/Ort innerhalb des Objekts (z.B. "Nordfassade, 1.OG").
  TextColumn get lage => text().nullable()();

  /// Öffnungsmethode (z.B. "manuell, Brechstange" oder "Bohrung DN 20").
  TextColumn get methode => text().nullable()();

  /// Personen die beim Öffnen anwesend waren (eine pro Zeile).
  TextColumn get anwesend => text().nullable()();

  /// Festgestellter Zustand (z.B. Dämmung feucht, Abdichtung fehlt).
  TextColumn get befund => text().nullable()();

  /// Messwerte zur Öffnung als JSON (Feuchte, Schichtdicke etc.).
  TextColumn get messwerteJson => text().nullable()();

  /// Foto vor der Öffnung.
  TextColumn get fotoVorStorageUrl => text().nullable()();

  /// Foto nach der Öffnung.
  TextColumn get fotoNachStorageUrl => text().nullable()();

  TextColumn get bemerkung => text().nullable()();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
