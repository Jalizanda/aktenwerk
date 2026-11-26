# Changelog

Alle signifikanten Änderungen an diesem Projekt ("Aktenwerk") werden in dieser Datei dokumentiert.

Das Format basiert auf [Keep a Changelog](https://keepachangelog.com/de/1.0.0/),
und dieses Projekt hält sich an [Semantic Versioning](https://semver.org/lang/de/).

## [0.22.0] - 2026-11-26
### Hinzugefügt
- **KI-Akten- & Gutachten-Wizard** (`ki_gutachten_wizard_dialog.dart`, `gutachten_wizard_ki_service.dart`): Fotos/Unterlagen hochladen → KI extrahiert Stammdaten, Beteiligte, Normen, Beweisfragen, Foto-Befunde und befüllt alle Gutachten-Abschnitte schrittweise.
- **WYSIWYG-Gutachten-Editor** (`gutachten_wysiwyg_embeds.dart`, `formel_editor_dialog.dart`): Tabellen, Formel-/Nachweisblöcke und Seitenumbrüche visuell in Inline-Feldern und Vollbild-Editor.
- **Automatische Verzeichnisse** (`gutachten_verzeichnisse_generator.dart`): Abkürzungs-, Anlagen-, Formel-, Normen- und Quellenverzeichnis aus dem Datensatz.
- PDF-Layout: optionale seitliche Trennlinie, ein-/doppelseitig mit alternierenden Rändern; temporäre Quellen-Markierung im verlinkten PDF (`web/quelle.html`).
- **Normen-Portal `norm.aktenwerk.app`** (`/norm-portal`): eigenständige Bibliothek mit Suche, eingebettetem KI-Chat über alle Normen (filtert die Tabelle auf zitierte Normen), Mandanten-Auswahl und Sofort-Sync.
- **KI-Aktualitätsprüfung** (`normen_aktualitaet_ki_service.dart`): global oder je Norm; historische Normen bleiben im Pool mit Gültigkeitszeitraum (von – bis) und Nachfolgenorm.
- Normen-Detail: echter KI-Chat und KI-Zusammenfassung über Vertex-AI-RAG mit Quellen-Chips (statt Platzhalter).
- PDF-Massen-Upload: Drag & Drop direkt auf den Dialog.

### Behoben
- Graues ErrorWidget im Inline-Editor (`Spacer` innerhalb `Wrap`).
- Standard-Mandant wird auf neuen Subdomains automatisch gesetzt.
- KI-Aktualitätscheck lief in „Firebase AI Logic genai config not found" – läuft jetzt über `normChatHttp` (Modus `direct_json`).

## [0.21.0] - 2026-10-18
### Behoben
- **JVEG 2025 (KostBRÄG 2025):** Sachgebiete nach Anlage 1 Teil 1 (68 Einträge, `core/jveg/jveg_tabelle.dart`) statt M1–M3 für Bausachverständige; M1–M3 auf 87/98/131 € aktualisiert. Rundung der letzten begonnenen Stunde nach § 8 Abs. 2 S. 2 JVEG auf die Gesamtzeit statt je Tätigkeit. Lichtbilder im JVEG-Rechner nach § 12 korrigiert.
- macOS-Entitlements: `network.client`, `files.user-selected.read-write`, `files.downloads.read-write`.
- ICS-Export: Semikolon korrekt maskiert.

### Hinzugefügt
- Word-Vorlagen-Engine (`shared/docx/`): $-/«»-/PH-/{{…}}-Platzhalter, MERGEFIELD-Normalisierung, «TableStart/TableEnd», #-Absätze, Serienbrief mit Abschnittsseitenzählung, Briefkopf-Übernahme.
- Akte › Mehr: Word-Dokument aus Vorlage, Leistungsnachweis, Kostennachweis, Aktendeckel (PDF), Ortstermin als .ics, Zusatzfelder.
- Positionen-Editor: Zu-/Abschlag in Prozent je USt-Satz.
- Gerichts-Schnellbriefe: Sachstandsmitteilung, Terminabstimmung Ortstermin, Anforderung Urteils-/Vergleichsabschrift; Platzhalter `$Verteiler`, `{{zf.Name}}`.
- Einstellungen: Briefkopf-Upload, Gerichte-Import (CSV/JSON), GutachtenManager-Import (CSV) + `tool/gm_export.sh`.
- HEIC→JPEG-Umwandlung beim Foto-Upload (macOS via `sips`, Web via Browser-Decoder).
- Gerichtsverzeichnis (`assets/data/gerichte.json`) von 158 auf 1.038 Einträge erweitert (DE 879, AT 159) inkl. Fax und Postfach; Abgleich der bisherigen Anschriften mit den GutachtenManager-Stammdaten (`tool/gerichte_zusammenfuehren.py`), LG Berlin I/II nach Teilung 2024. Fax wird bei Gerichtsauswahl im Auftraggeber übernommen.

## [Unreleased] - 2026-10-14
### Hinzugefügt
- feat(v0.20.0): Enterprise-Praxispaket (Versicherung/Schieds/Aktenbaende, Beteiligte-Umladung, Arbeitsblatt-PDF, 1-Klick-JVEG-Liquidation, Express-Fotodoku, Platzhalter-Engine & Gerichts-Schnellbriefe)


## [0.20.0] - 2026-10-14
### Hinzugefügt
- **Akten-Stammdaten & Versicherungsgutachten (`AuftragGmExtras`):** Neuer Auftragstyp *Versicherungsgutachten* mit Schadensnummer, Versicherungsschein-Nr. (Police), Schadenstag, Schadensursache, Versicherungsnehmer und Anspruchsteller. Erweiterte Schiedsgutachten-Felder (*Schiedsvertrag vom*, *Obmann*, *Partei A / Partei B*), *Streitwert*, Ortstermin-Zeitfenster (*Uhrzeit von–bis*), Verlegungshistorie (*Ortstermin alt* & *Verlegungsgrund*) sowie Verwaltung mehrerer **Gerichts-/Beiakten-Bände** (`GerichtsaktenBand`: Band-Nr., Bezeichnung, Blatt von–bis, Eingangs- und Rückgabedatum).
- **Erweiterte Beteiligten-Verwaltung (`beteiligte_tab.dart`):** Anrede, individuelle Briefanrede, Kanzlei-/Schadens-Aktenzeichen (*Ihr Zeichen*), Vertretungsvermerk (*Vertritt*), Versandart (*Brief*, *Einwurf-Einschreiben*, *Einschreiben/Rückschein*, *E-Mail*, *beA / EGVP*) und Lade-Checkbox (`OT`).
- **1-Klick Ortstermin-Einladung (Serienbrief) & Umladung / Terminverlegung:** Erzeugt individuelle DIN-5008-Anschreiben je geladenem Beteiligten inkl. dessen *Ihr Zeichen*, automatischer Aufstellung aller geladenen Personen (*„Zu diesem Termin wurden außerdem geladen: …"*) sowie optionaler Benachrichtigung an Gericht/Auftraggeber.
- **Gutachterarbeitsblatt (`arbeitsblatt_pdf.dart`):** Direkt aus dem Akten-Header druckbares Handblatt für den Ortstermin mit Stammdaten, Witterungs-/Temperaturfeldern, Beteiligten-Anwesenheitstabelle zum Abhaken vor Ort sowie allen Beweisfragen mit linierten Notizkästen und Vor-Ort-Checkliste.
- **Vollautomatische 1-Klick JVEG-Liquidation (`rechnungen_positionen_helpers.dart`):** Kombiniert Zeitaufwand nach Akten-Honorargruppe (`M1`/`M2`/`M3`, § 9 JVEG inkl. Halbstunden-Rundung), Fahrtkosten/Auslagen (§ 5 JVEG), Schreibauslagen nach tatsächlicher Zeichenanzahl des Gutachtens (§ 12 Abs. 1 Nr. 3 JVEG: 0,90 € / 1.000 Zeichen), Kopierpauschalen & Lichtbilder inkl. Mehrfertigungen (`anzahlAusfertigungen`, § 12 Abs. 1 Nr. 2 JVEG: 2,00 € Erstausfertigung / 0,50 € Mehrfertigungen) sowie Vorschuss-Abzugshinweis.
- **Express-Fotodokumentation als PDF-Anlage (`fotodoku_pdf.dart`):** Eigenständiger PDF-Export im Reiter *Fotos* mit wählbarem Raster (**1, 2, 4 oder 6 Fotos pro DIN-A4-Seite**), fortlaufender Nummerierung (`Abb. 1`, `Abb. 2` …), Raum/Bauteil, Aufnahmedatum und optionaler Direkt-Archivierung in den Akten-Dokumenten.
- **Zentrale Platzhalter-Engine (`{{…}}` & `$Variablen`) + 1-Klick Gerichts-Schnellbriefe:** Unterstützung für über 35 Variablen (`$Sache`, `$GerichtsAZ`, `$IhrZeichen`, `$Ortstermin`, `$OrtsterminUhrzeit`, `$OrtsterminAlt`, `$Streitwert`, `$Vorschuss`, `$Kostenlimit`, `$Schadensnummer`, `$VersicherungsscheinNr`, `$Beweisfragen`, `$GeladeneBeteiligte`, `$Aktenbaende` u. v. m.), interaktiver Platzhalter-Picker im Anschreiben-Editor sowie 5 1-Klick-Gerichtsschriftsätze im Reiter *Gerichtssache* (*§ 407a ZPO-Bestätigung*, *Vorschussanforderung*, *Aktenanforderung*, *Fristverlängerung § 411 ZPO*, *Gutachtenversand & Aktenrückgabe*).

## [0.19.0] - 2026-05-30
### Hinzugefügt
- **Verträge:** Neue Schnellanlage-Funktion für Privatgutachten-Verträge inkl. digitaler Signatur auf mobilen Endgeräten.
- **KI-Beweisfragen:** Beweisbeschlüsse können jetzt per KI gescannt werden. Die KI bewertet direkt, ob Fragen rechtlich unzulässig oder verständlich sind und es gibt einen neuen Chat, um Nachfragen ans Gericht vorzubereiten.
- **Ortstermin-Wetter:** Automatische Wetter- und GPS-Notiz beim Klick auf „Hier bin ich".


## [1.1.0] - 2026-05-17
### Hinzugefügt
- **Daten-Import:** Vollständiger Import aus dem Altsystem (IndexedDB-Export-JSON) über den Einstellungsbereich (`BackupSection`).
- **Geocoding & Lastzonen:** Automatische Ermittlung von Koordinaten (Nominatim), Höhen über N.N. (Open-Meteo) sowie Schnee- und Windlastzonen direkt in der Auftrags-Erfassung.
- **OPOS & Mahnwesen:** Serienbrief-Generierung für fällige Rechnungen im Mahnlauf als PDF (`mahnwesen_pdf.dart`).
- **Gerichts-Integration:** Durchsuchbare Datenbank mit 158 Gerichten im Kunden-Dialog zur vereinfachten Anlage von Gerichts-Auftraggebern.
- **Jahresbericht:** PDF-Jahresbericht nach IHK-Vorlage mit Auswertungen über Sachgebiete, Umsatz und Fortbildungsstunden.

## [1.0.0] - 2026-05-16
### Hinzugefügt
- Initiale Portierung der SV-Software (Original-Web-App mit IndexedDB) nach Flutter.
- Architektur mit Riverpod, Drift (SQLite) und GoRouter etabliert.
- Voll funktionsfähige Module für Akten, Angebote, Kalkulation, Werkzeuge, Auswertung und Systemeinstellungen.
