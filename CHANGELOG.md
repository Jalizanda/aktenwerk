# Changelog

Alle signifikanten Änderungen an diesem Projekt ("Aktenwerk") werden in dieser Datei dokumentiert.

Das Format basiert auf [Keep a Changelog](https://keepachangelog.com/de/1.0.0/),
und dieses Projekt hält sich an [Semantic Versioning](https://semver.org/lang/de/).

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
