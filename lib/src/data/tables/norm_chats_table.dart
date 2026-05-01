import 'package:drift/drift.dart';

/// Eine gespeicherte Chat-Konversation mit der Normen-KI (RAG).
/// Wird in der Sidebar des Chat-Dialogs gelistet, kann angeklickt,
/// umbenannt oder gelöscht werden.
///
/// Persistierung lokal in Drift — sehr klein (nur Frage/Antwort-Texte
/// + Quellenliste pro Turn als JSON), schnell synchron lesbar.
class NormChats extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Anzeigetitel — beim ersten Speichern automatisch aus der ersten
  /// Nutzer-Frage gebildet (max. 80 Zeichen). Kann später umbenannt werden.
  TextColumn get titel => text()();

  /// Nachrichten-Verlauf als JSON-Array. Jeder Eintrag:
  /// `{ "rolle": "user"|"assistant", "text": "...", "quellen": [...],
  ///    "zeit": "ISO-Datum" }`. `quellen` ist nur bei assistant gefüllt.
  TextColumn get nachrichtenJson => text()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}
