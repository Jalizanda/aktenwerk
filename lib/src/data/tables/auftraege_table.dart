import 'package:drift/drift.dart';
import 'kunden_table.dart';

/// Auftrag / Akte.
/// Art: privat | gericht
class Auftraege extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get aktenzeichen => text().nullable()();
  TextColumn get art => text().withDefault(const Constant('privat'))();
  TextColumn get status => text().withDefault(const Constant('offen'))();

  IntColumn get kundeId =>
      integer().nullable().references(Kunden, #id, onDelete: KeyAction.setNull)();

  /// Geschäftszeichen des Auftraggebers (bei Gericht = Gerichts-Az.).
  TextColumn get azExtern => text().nullable()();
  /// Betreff / Beweisthema.
  TextColumn get betreff => text().nullable()();
  TextColumn get bezeichnung => text().nullable()();

  // ---------- Objekt ----------
  TextColumn get objektStrasse => text().nullable()();
  TextColumn get objektPlz => text().nullable()();
  TextColumn get objektOrt => text().nullable()();
  RealColumn get objektLat => real().nullable()();
  RealColumn get objektLon => real().nullable()();
  RealColumn get objektHoehe => real().nullable()();

  /// Objektart (Einfamilienhaus, Doppelhaus, …).
  TextColumn get objektart => text().nullable()();
  TextColumn get baujahr => text().nullable()();

  // ---------- Gutachten-Kategorisierung ----------
  TextColumn get sachgebiet => text().nullable()();
  /// Kategorie: Schadensgutachten / Mängelgutachten / Bewertungsgutachten / …
  TextColumn get kategorie => text().nullable()();
  /// JVEG-Honorargruppe: M1, M2, M3, Sonstige.
  TextColumn get honorargruppe => text().nullable()();

  // ---------- Termine / Fristen ----------
  DateTimeColumn get eingangAm => dateTime().nullable()();
  DateTimeColumn get auftragAm => dateTime().nullable()();
  /// Separat zum Auftragsdatum: nächster Ortstermin.
  DateTimeColumn get ortsterminAm => dateTime().nullable()();
  /// Fertigstellungsfrist.
  DateTimeColumn get fristAm => dateTime().nullable()();
  DateTimeColumn get abschlussAm => dateTime().nullable()();
  RealColumn get aufwandSchaetzung => real().nullable()();

  // ---------- Honorar / Kosten ----------
  RealColumn get stundensatz => real().nullable()();
  RealColumn get kostenLimit => real().nullable()();
  RealColumn get kostenvorschuss => real().nullable()();

  // ---------- Gerichts-spezifisch ----------
  TextColumn get gerichtsAktenzeichen => text().nullable()();
  TextColumn get gericht => text().nullable()();
  TextColumn get gerichtsort => text().nullable()();
  /// Verfahrensart (Zivil, Schieds, selbst. Beweisverfahren …).
  TextColumn get verfahrensart => text().nullable()();
  DateTimeColumn get akteneingangAm => dateTime().nullable()();
  IntColumn get anzahlAusfertigungen => integer().nullable()();
  IntColumn get aktenSeitenVon => integer().nullable()();
  IntColumn get aktenSeitenBis => integer().nullable()();
  DateTimeColumn get beweisbeschluss1 => dateTime().nullable()();
  DateTimeColumn get beweisbeschluss2 => dateTime().nullable()();
  DateTimeColumn get beweisbeschluss3 => dateTime().nullable()();

  // ---------- Richter ----------
  TextColumn get richter => text().nullable()();
  TextColumn get richterAnrede => text().nullable()();
  TextColumn get richterBriefanrede => text().nullable()();

  TextColumn get beteiligteJson => text().nullable()();

  /// Aufgaben-Array: `[{"text":"…","done":false,"doneAt":null}]`.
  TextColumn get aufgabenJson => text().nullable()();

  // ---------- Zonendaten (Schnee/Wind) ----------
  /// Schneelastzone (1 | 1a | 2 | 2a | 3) nach DIN EN 1991-1-3/NA.
  TextColumn get schneelastzone => text().nullable()();
  /// Geografische Schneelast in kN/m² (aus Tabelle oder Erläuterung).
  RealColumn get schneelastKnm2 => real().nullable()();
  /// Windlastzone (1 | 2 | 3 | 4) nach DIN EN 1991-1-4/NA.
  TextColumn get windlastzone => text().nullable()();
  /// Quellvermerk der Zonen-Daten (z.B. "DIN EN 1991 / Verwaltungsgrenzen 2025").
  TextColumn get zonenQuelle => text().nullable()();

  /// Beweisbeschluss als PDF (Firebase Storage).
  TextColumn get beweisbeschlussStorageUrl => text().nullable()();
  TextColumn get beweisbeschlussDateiname => text().nullable()();
  TextColumn get beweisbeschlussMimeType => text().nullable()();
  IntColumn get beweisbeschlussGroesse => integer().nullable()();

  /// Übersichts-/Objekt-Foto.
  TextColumn get objektFotoStorageUrl => text().nullable()();
  TextColumn get objektFotoDateiname => text().nullable()();

  TextColumn get notiz => text().nullable()();
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
