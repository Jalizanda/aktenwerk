import 'package:drift/drift.dart';
import 'auftraege_table.dart';

/// Gutachten (Rich-Text, 13 Abschnitte nach Zöller).
class Gutachten extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().nullable().references(Auftraege, #id, onDelete: KeyAction.cascade)();

  /// Fortlaufende Gutachten-Nummer (z.B. "G2026-014"). Wird in Kopf/Fuß und
  /// in der Aktenzeichen-Zeile des PDF-Exports geführt.
  TextColumn get nummer => text().nullable()();

  /// Datum der Gutachten-Ausstellung (wird im PDF oben angedruckt).
  DateTimeColumn get datum => dateTime().nullable()();

  TextColumn get titel => text().nullable()();
  TextColumn get bezeichnung => text().nullable()();

  /// Gewählte Vorlage (bauschaden/beweissicherung/maengel/frei) — steuert den
  /// Default-Textbaustein pro Abschnitt beim Anlegen eines neuen Gutachtens.
  TextColumn get vorlage => text().withDefault(const Constant('frei'))();

  TextColumn get status => text().withDefault(const Constant('entwurf'))();

  DateTimeColumn get ortsterminAm => dateTime().nullable()();
  DateTimeColumn get abgabeAm => dateTime().nullable()();

  /// Rich-Text (Quill Delta JSON) pro Abschnitt in einem JSON-Map.
  TextColumn get abschnitteJson => text().nullable()();
  TextColumn get normenJson => text().nullable()();
  TextColumn get geraeteJson => text().nullable()();
  TextColumn get lichtbildanlageJson => text().nullable()();

  /// Anlagen (Dokumente, die ans Ende des PDFs gehängt werden) als JSON:
  /// `[{"nr":1,"dokumentId":42,"titel":"…","datum":"YYYY-MM-DD"}]`.
  /// Im Editor erscheinen sie als Referenz-Marker `[Anlage N — Titel]`,
  /// im Druck folgen sie als angehängte Seiten hinter dem Hauptteil.
  TextColumn get anlagenJson => text().nullable()();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
