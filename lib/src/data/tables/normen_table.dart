import 'package:drift/drift.dart';
import 'auftraege_table.dart';

/// Normen-Katalog (DIN, EN, ISO, VOB ...).
///
/// Wird zweifach genutzt: (1) zentrale Bibliothek (auftragId = null) —
/// wiederverwendbarer Normen-Pool, (2) Akten-Normen (auftragId != null) —
/// Auszug für ein konkretes Gutachten.
class Normen extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Wenn gesetzt → Akten-spezifische Norm, sonst Teil des Bibliotheks-Katalogs.
  IntColumn get auftragId =>
      integer().nullable().references(Auftraege, #id, onDelete: KeyAction.cascade)();

  TextColumn get nummer => text()();
  TextColumn get titel => text().nullable()();
  TextColumn get ausgabe => text().nullable()();
  TextColumn get kategorie => text().nullable()();

  /// Art: DIN-Norm / DIN EN / WTA-Merkblatt / VOB / …
  TextColumn get art => text().nullable()();
  TextColumn get herausgeber => text().nullable()();

  /// Relevanz: gutachten / referenz / beweis
  TextColumn get relevanz => text().nullable()();
  TextColumn get zusammenfassung => text().nullable()();
  TextColumn get zitat => text().nullable()();

  TextColumn get beschreibung => text().nullable()();
  TextColumn get notiz => text().nullable()();

  /// Primäres Gewerk zur Gruppierung / Filterung — z. B.
  /// „Fenster/Türen", „Schallschutz/Akustik", „Brandschutz", „Abdichtung".
  TextColumn get gewerk => text().nullable()();

  /// Optional: eingebundenes PDF (Volltext, Merkblatt, Zitat).
  TextColumn get pdfPfad => text().nullable()();
  TextColumn get pdfStorageUrl => text().nullable()();
  TextColumn get pdfMimeType => text().nullable()();
  IntColumn get pdfGroesse => integer().nullable()();
  TextColumn get pdfDateiname => text().nullable()();

  BoolColumn get aktiv => boolean().withDefault(const Constant(true))();
  BoolColumn get favorit => boolean().withDefault(const Constant(false))();

  /// Aktualitäts-Status: 'aktuell' | 'veraltet' | 'unbekannt' | null.
  TextColumn get aktualitaetStatus => text().nullable()();
  DateTimeColumn get aktualitaetGeprueftAm => dateTime().nullable()();
  /// URL zur Quelle (z. B. DIN-Katalog / Beuth-Eintrag).
  TextColumn get aktualitaetQuelle => text().nullable()();
  TextColumn get aktualitaetNotiz => text().nullable()();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
