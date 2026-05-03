import 'package:drift/drift.dart';
import 'auftraege_table.dart';

/// Leistungsverzeichnis (LV) — Kopfdaten. Ein LV gehört zu einer Akte und
/// dient sowohl als Kostenschätzung im Gutachten (mit Preisen) als auch
/// als Ausschreibungstext für Handwerker (ohne Preise — Blanko-LV).
class LvKopf extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().nullable().references(Auftraege, #id, onDelete: KeyAction.cascade)();

  TextColumn get nummer => text().nullable()();
  TextColumn get bezeichnung => text()();
  TextColumn get untertitel => text().nullable()();

  /// Datum der Erstellung; Stichtag für die Indizierung.
  DateTimeColumn get datum => dateTime().withDefault(currentDateAndTime)();

  /// Status: entwurf | freigegeben | versendet | archiviert.
  TextColumn get status => text().withDefault(const Constant('entwurf'))();

  /// Mehrwertsteuer-Satz für die Brutto-Berechnung.
  RealColumn get mwstSatz => real().withDefault(const Constant(19.0))();

  /// Stichtag des Baupreisindex (für historische LVs zur Hochrechnung).
  /// Format: ISO-Jahr-Quartal "2024-Q3" oder Jahr "2024". `null` = aktuell.
  TextColumn get indexStichtag => text().nullable()();
  /// Index-Wert (Destatis Tabelle 61261-0001) zum Stichtag, falls bekannt.
  RealColumn get indexWert => real().nullable()();

  /// Wenn gesetzt: dieses LV ist eine Bieter-Antwort zum Basis-LV
  /// (Ausschreibung). Erlaubt die Bietergegenüberstellung.
  IntColumn get basisLvId => integer().nullable()();
  /// Bieter-Name (Handwerksbetrieb), falls dies ein Bieter-LV ist.
  TextColumn get bieterName => text().nullable()();
  /// Optional: Verknüpfung zum Kontakt (Kunden-Eintrag) des Bieters,
  /// damit Adresse, Telefon, Mail aus dem Kontakt gezogen werden können.
  IntColumn get bieterKundeId => integer().nullable()();

  TextColumn get notiz => text().nullable()();
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Einzelne Position innerhalb eines LV. Selbst-referenzierend für die
/// Hierarchie (Titel → Hauptposition → Unterposition).
class LvPositionen extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get lvId =>
      integer().references(LvKopf, #id, onDelete: KeyAction.cascade)();
  IntColumn get parentId => integer().nullable()();

  /// Ordnungszahl (z. B. "01.02.0030"). Wird bei Bedarf neu berechnet.
  TextColumn get oz => text().nullable()();
  IntColumn get sortIndex => integer().withDefault(const Constant(0))();

  /// Positions-Art:
  /// - `titel`: Strukturzeile, keine Mengen/Preise
  /// - `normal`: Standard-Position mit Menge × Einzelpreis
  /// - `bedarf`: Bedarfsposition (BP), wird optional ausgeschrieben
  /// - `eventual`: Eventualposition (EP)
  /// - `stundenlohn`: Stundenlohn-Position
  /// - `grundtext`: Beschreibungstext über die ganze Zeile, ohne Preis
  TextColumn get art => text().withDefault(const Constant('normal'))();

  TextColumn get kurztext => text()();
  /// Langtext / detaillierte Leistungsbeschreibung (Quill-Delta JSON oder
  /// Plain-Text — bei Import aus GAEB Plain-Text).
  TextColumn get langtext => text().nullable()();

  TextColumn get einheit => text().nullable()(); // m, m², m³, Stk, h, psch, t, kg
  RealColumn get menge => real().nullable()();
  RealColumn get einzelpreis => real().nullable()();

  /// Optionaler USt-Satz pro Position. Wenn `null`, gilt der MwSt-Satz
  /// vom LV-Kopf. Erlaubt Mischsummen (z. B. 7 % bei künstlerischen
  /// Leistungen, 19 % bei Standard-Bauleistungen).
  RealColumn get ustSatz => real().nullable()();

  /// DIN-276-Kostengruppe (z. B. "330" oder "331").
  TextColumn get din276 => text().nullable()();

  /// Gewerk (Innenputz, Maler, Erdarbeiten ...) — frei vergebbar.
  TextColumn get gewerk => text().nullable()();

  /// GAEB-Roundtrip: UUID aus dem importierten LV, damit ein Re-Export
  /// dieselbe ID behält (für Bieter-Vergleich notwendig).
  TextColumn get gaebUuid => text().nullable()();

  TextColumn get notiz => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Mengenermittlungs-Zeilen pro Position. Erlaubt Formeln wie
/// `3,50 * 2,80` oder Einzel-Aufstellungen mit Bezeichnung.
class LvMengenzeilen extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get positionId =>
      integer().references(LvPositionen, #id, onDelete: KeyAction.cascade)();
  IntColumn get sortIndex => integer().withDefault(const Constant(0))();

  TextColumn get bezeichnung => text().nullable()();
  /// Formel-String, z. B. "3,5*2,8" oder "12+8+5".
  TextColumn get formel => text().nullable()();
  /// Berechnetes Ergebnis (Service-Layer rechnet die Formel aus).
  RealColumn get ergebnis => real().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Eigener Positions-Katalog. Beim Erfassen einer Position im LV kann
/// der SV per Klick „in Katalog übernehmen" — die Position landet hier
/// und ist beim nächsten LV per Picker einfügbar. Wächst organisch mit.
class LvKatalog extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get kurztext => text()();
  TextColumn get langtext => text().nullable()();
  TextColumn get einheit => text().nullable()();
  RealColumn get einzelpreis => real().nullable()();

  TextColumn get din276 => text().nullable()();
  TextColumn get gewerk => text().nullable()();
  TextColumn get tags => text().nullable()();

  /// Quelle: `eigen` (selbst angelegt), `bki` (importiert), `gaeb`,
  /// `seed` (mit Aktenwerk ausgeliefert).
  TextColumn get quelle => text().withDefault(const Constant('eigen'))();

  /// Datum des Preisstandes — für spätere Indizierung mit Destatis-Index.
  DateTimeColumn get preisstand => dateTime().nullable()();

  /// Wie oft wurde diese Katalogposition bereits verwendet (für
  /// „Häufig verwendet"-Sortierung im Picker).
  IntColumn get verwendungsZaehler => integer().withDefault(const Constant(0))();

  TextColumn get notiz => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
