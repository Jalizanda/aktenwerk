# Changelog

Alle signifikanten Änderungen an diesem Projekt ("Aktenwerk") werden in dieser Datei dokumentiert.

Das Format basiert auf [Keep a Changelog](https://keepachangelog.com/de/1.0.0/),
und dieses Projekt hält sich an [Semantic Versioning](https://semver.org/lang/de/).

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
