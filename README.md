# Aktenwerk

Bausachverständigen-Verwaltung – Flutter-Portierung der SV-Software.
Akten, Gutachten, Rechnungen, Angebote, Kalkulation, Auswertung.

## Status: alle Module voll funktional

Die Portierung der Original-Web-App (~12.663 Zeilen HTML/JS mit IndexedDB) nach
Flutter/Dart ist abgeschlossen. `flutter analyze` meldet keine Issues,
`flutter build web` läuft sauber durch.

## Funktionsumfang

### Akten
- **Auftraggeber** (Kunden) — Typen Privat/Firma/Anwalt/Gericht/Versicherung/Behörde, Suche, Filter, Typ-Badges
- **Aufträge** — mit Art (privat/gericht), Status, Objekt-Adresse, Stundensatz, Kostenlimit, Nummernkreis
- **Gutachten** — Rich-Text-Editor (flutter_quill), 13 Abschnitte nach Zöller, Vollbild-Editor
- **Erläuterungstermine** — Datum, Gericht, Saal, Richter, Vorbereitung, Protokoll
- **Rechnungen** — Positions-Tabelle, USt-Berechnung, Status, PDF-Export (`pdf`/`printing`)
- **Eingangsrechnungen** — Belege, Kategorien, Netto/USt/Brutto, Fälligkeit
- **Lieferanten** — Stammdaten, Bankverbindung, Kategorien

### Angebote & Anschreiben
- **Angebote** — Positions-Tabelle, Gültigkeit, PDF-Export
- **Anschreiben** — Rich-Text, Empfänger + Auftragsbezug, Vollbild-Editor

### Kalkulation
- **Artikel / Leistungen** — Katalog mit USt-Satz, Einheit, Preis
- **Stunden** — Live-Timer mit Auftragsauswahl, Übersicht nach abgerechnet/offen
- **Auslagen** — Positionen pro Auftrag mit Menge/Einheit
- **Kalkulation** — Ist/Soll pro Auftrag, Kostenlimit-Warnung

### Werkzeuge
- **Messgeräte** — Kalibrier-Warnung bei überfälligen Geräten
- **Normen** — Katalog mit Favoriten-Flag
- **Textbausteine** — Kategorisiert, Favoriten, Listenansicht
- **Fotos** — Multi-Upload (`file_picker`), Gitteransicht, BLOB-Speicherung
- **Termine** — Erläuterungstermine + Wiedervorlagen zusammengeführt, gruppiert nach Tag
- **Wiedervorlagen** — Scope-Filter (Heute/Woche/Überfällig/Offen/Erledigt), Priorität, Auftragsbezug
- **JVEG-Rechner** — Honorarstufen M1–M12, Fahrt, Wartezeit, Kopien, Live-Summen
- **Ortstermin-Modus** — Fokus-Oberfläche: Fotos, Timer, Schnell-Notizen → Auftrag

### Auswertung
- **OPOS / Mahnwesen** — Offene Posten, Alter, automatische Mahnstufen (14/30/60 Tage)
- **Steuer & Statistik** — USt-Voranmeldung, EÜR, Monats-Balkendiagramm (`fl_chart`)
- **Jahresbericht** — Anzahl Gutachten nach Art, Umsatz, Fortbildungsstunden
- **Fortbildungen** — Nachweise mit Stunden + Kosten, Jahres-Summen-Chips

### System
- **Einstellungen** — Nummernkreise (mit Platzhaltern YYYY/MM/####), Standard-Stundensatz, USt, Theme (live umschaltbar), Fußtexte
- **Benutzer** — Sachverständigen-Profil für Briefkopf, Bank, Steuer-Nr. / USt-ID

## Technik

- **Flutter 3.11** · **Material 3** · Cross-Platform (Web/Desktop/Mobile)
- **Drift (SQLite)** für Persistenz, 24 Tabellen
- **Riverpod** für State Management
- **GoRouter** mit persistenter Sidebar (ShellRoute)
- **flutter_quill 11** für Rich-Text (Gutachten + Anschreiben)
- **pdf + printing** für Rechnungs-/Angebots-PDFs
- **fl_chart** für Auswertungs-Diagramme
- **file_picker** für Foto-Upload
- Deutsche Lokalisierung, DIN-Formatierung (Datum, Währung)
- 158 Gerichte als JSON-Asset aus dem Original portiert
- Lastzonen-Datenbank (Schnee/Wind, ~6400 Einträge) als JSON-Asset + Dart-Lookup

## Start

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d chrome      # Web
flutter run -d macos       # Desktop (braucht CocoaPods)
flutter run -d <device>    # Mobile
```

Nach Änderungen an `lib/src/data/tables/*_table.dart` muss der Code-Generator
neu laufen:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Architektur-Muster je Modul

Jedes Modul folgt dem gleichen Dreiklang:

1. **Repository** (`*_repository.dart`) — Drift-Queries, Riverpod-Provider, Filter-State
2. **Form-Dialog** oder **Vollbild-Editor** — CRUD-Oberfläche
3. **Screen** — Liste mit `DataTable`, Toolbar, Empty-State

Geteilte Bausteine liegen in `lib/src/shared/`:
- `widgets/form_widgets.dart` — Row2/Row3, LabeledField, StandardFormDialog
- `widgets/module_scaffold.dart` — ModuleHeader, DataTableCard
- `widgets/date_field.dart` — Datumsfeld mit DE-Format
- `positionen/` — Positions-Editor + Summen-Logik (Rechnung/Angebot)
- `richtext/quill_editor.dart` — flutter_quill-Wrapper
- `pdf/document_pdf.dart` — PDF-Generator für Rechnungen/Angebote

## Referenz-Projekt

Das Original bleibt unter `/Users/ahoepken/Documents/CoWork/SV-Software/` zur
Funktions-Referenz. Bei fachlichen Fragen oder Abweichungen zum Original kann
dort nachgesehen werden.

## Offene Punkte (nach Bedarf)

- Daten-Import aus dem Original (IndexedDB-Export → Drift-Insert)
- Geocoding-Anbindung (Nominatim + Open-Meteo) in der Auftrags-Erfassung
- Lastzonen-Lookup automatisch bei Adress-Eingabe auslösen
- Mahnungen als PDF-Serienbrief (Grundlage OPOS steht)
- Jahresbericht-PDF nach IHK-Vorlage
- Gerichts-Datenbank-Integration im Kunden-Dialog (Typ „Gericht")
