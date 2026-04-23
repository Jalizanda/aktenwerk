import 'package:drift/drift.dart';
import 'auftraege_table.dart';

/// Recherche-Zwischenablage: Notizen aus dem Normen-KI-Chat, Messungen
/// o. Ä., die der SV sich für ein konkretes Gutachten merken möchte.
/// Wird beim Schreiben des Gutachtens pro Abschnitt als Baustein
/// eingefügt — ähnlich wie Textbausteine, aber akten-spezifisch und
/// einmalig.
class RechercheNotizen extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Zuordnung zur Akte. `null` = allgemeine Ablage, sichtbar in jedem
  /// Gutachten-Editor als globale Notiz.
  IntColumn get auftragId => integer()
      .nullable()
      .references(Auftraege, #id, onDelete: KeyAction.cascade)();

  /// Kurzer Titel zum Wiederfinden (meist auto-generiert aus der ersten
  /// Satz der Frage).
  TextColumn get titel => text()();

  /// Der eigentliche Notiz-Inhalt. Plaintext, wird beim Einfügen als
  /// Absatz ans gewählte Abschnitts-Feld angehängt.
  TextColumn get inhalt => text()();

  /// Herkunft der Notiz — z. B. 'Normen-Chat', 'Manuell',
  /// 'Ortstermin'. Wird in der Liste als kleines Badge angezeigt.
  TextColumn get quelle => text().nullable()();

  /// Referenzierte Norm-IDs als JSON-Array (z. B. `[12, 47]`) — dient
  /// der Quellenangabe im Gutachten.
  TextColumn get referenzNormenJson => text().nullable()();

  /// Markiert, wenn die Notiz bereits in ein Gutachten eingefügt wurde.
  /// Dient nur als Status-Indikator (Filterung, Aufräumen).
  BoolColumn get verwendet =>
      boolean().withDefault(const Constant(false))();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}
