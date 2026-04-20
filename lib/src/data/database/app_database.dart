import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../tables/angebote_table.dart';
import '../tables/anschreiben_table.dart';
import '../tables/artikel_table.dart';
import '../tables/auftraege_geraete_table.dart';
import '../tables/auftraege_table.dart';
import '../tables/auslagen_table.dart';
import '../tables/benutzer_table.dart';
import '../tables/dokumente_table.dart';
import '../tables/eingangsrechnungen_table.dart';
import '../tables/einstellungen_table.dart';
import '../tables/erlaeuterungen_table.dart';
import '../tables/fortbildungen_table.dart';
import '../tables/fotos_table.dart';
import '../tables/geraete_table.dart';
import '../tables/gutachten_table.dart';
import '../tables/kalkulationen_table.dart';
import '../tables/konten_table.dart';
import '../tables/kunden_table.dart';
import '../tables/lieferanten_table.dart';
import '../tables/normen_table.dart';
import '../tables/partner_table.dart';
import '../tables/protokolle_table.dart';
import '../tables/rechnungen_table.dart';
import '../tables/rueckfragen_table.dart';
import '../tables/stunden_table.dart';
import '../tables/textbausteine_table.dart';
import '../tables/versand_table.dart';
import '../tables/wiedervorlagen_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Kunden,
  Auftraege,
  AuftraegeGeraete,
  Gutachten,
  Rechnungen,
  Stunden,
  Fotos,
  Einstellungen,
  Anschreiben,
  Textbausteine,
  Dokumente,
  Kalkulationen,
  Rueckfragen,
  Auslagen,
  Angebote,
  Wiedervorlagen,
  Versand,
  Fortbildungen,
  Artikel,
  Benutzer,
  Geraete,
  Normen,
  Eingangsrechnungen,
  Lieferanten,
  Erlaeuterungen,
  Konten,
  Protokolle,
  Partner,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? _open());

  static QueryExecutor _open() => driftDatabase(
        name: 'aktenwerk',
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
      );

  @override
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          // Echte Step-by-Step-Migrationen — KEIN Drop-All mehr.
          // Jeder Block fügt nur die Spalten hinzu, die in dieser Version
          // dazukamen. Bestehende Daten bleiben erhalten.

          // v4 → v5: Normen-Aktualitäts-Tracking.
          if (from < 5) {
            await m.addColumn(normen, normen.aktualitaetStatus);
            await m.addColumn(normen, normen.aktualitaetGeprueftAm);
            await m.addColumn(normen, normen.aktualitaetQuelle);
            await m.addColumn(normen, normen.aktualitaetNotiz);
          }

          // v5 → v6: Upload-Felder für Fortbildungen, Geräte, Aufträge.
          if (from < 6) {
            await m.addColumn(
                fortbildungen, fortbildungen.nachweisStorageUrl);
            await m.addColumn(
                fortbildungen, fortbildungen.nachweisDateiname);
            await m.addColumn(
                fortbildungen, fortbildungen.nachweisMimeType);
            await m.addColumn(
                fortbildungen, fortbildungen.nachweisGroesse);

            await m.addColumn(
                geraete, geraete.kalibrierscheinStorageUrl);
            await m.addColumn(
                geraete, geraete.kalibrierscheinDateiname);
            await m.addColumn(
                geraete, geraete.kalibrierscheinMimeType);
            await m.addColumn(
                geraete, geraete.kalibrierscheinGroesse);
            await m.addColumn(geraete, geraete.handbuchStorageUrl);
            await m.addColumn(geraete, geraete.handbuchDateiname);
            await m.addColumn(geraete, geraete.handbuchMimeType);
            await m.addColumn(geraete, geraete.handbuchGroesse);
            await m.addColumn(geraete, geraete.fotoStorageUrl);
            await m.addColumn(geraete, geraete.fotoDateiname);

            await m.addColumn(
                auftraege, auftraege.beweisbeschlussStorageUrl);
            await m.addColumn(
                auftraege, auftraege.beweisbeschlussDateiname);
            await m.addColumn(
                auftraege, auftraege.beweisbeschlussMimeType);
            await m.addColumn(
                auftraege, auftraege.beweisbeschlussGroesse);
            await m.addColumn(
                auftraege, auftraege.objektFotoStorageUrl);
            await m.addColumn(auftraege, auftraege.objektFotoDateiname);
          }

          // v6 → v7: Benutzer-Rolle + Modul-Berechtigungen.
          if (from < 7) {
            await m.addColumn(benutzer, benutzer.rolle);
            await m.addColumn(benutzer, benutzer.erlaubteModule);
            await m.addColumn(benutzer, benutzer.bearbeitbareModule);
          }

          // v7 → v8: PDF-Archivierung für Rechnungen + Angebote.
          if (from < 8) {
            await m.addColumn(rechnungen, rechnungen.pdfStorageUrl);
            await m.addColumn(rechnungen, rechnungen.pdfDateiname);
            await m.addColumn(rechnungen, rechnungen.pdfGroesse);
            await m.addColumn(rechnungen, rechnungen.pdfErstelltAm);

            await m.addColumn(angebote, angebote.pdfStorageUrl);
            await m.addColumn(angebote, angebote.pdfDateiname);
            await m.addColumn(angebote, angebote.pdfGroesse);
            await m.addColumn(angebote, angebote.pdfErstelltAm);
          }

          // v8 → v9: DATEV-Konten-Katalog + Ausgangs-Konto auf Rechnungen.
          // Eingangsrechnungen nutzen das vorhandene `datevKonto`-Feld.
          if (from < 9) {
            await m.createTable(konten);
            await m.addColumn(rechnungen, rechnungen.kontonummer);
          }

          // v9 → v10: DATEV Debitor-/Kreditor-Nummern.
          if (from < 10) {
            await m.addColumn(kunden, kunden.debitornummer);
            await m.addColumn(lieferanten, lieferanten.kreditornummer);
          }

          // v10 → v11: Angebote an Akte knüpfen.
          if (from < 11) {
            await m.addColumn(angebote, angebote.auftragId);
          }

          // v11 → v12: Ortstermin-Protokolle.
          if (from < 12) {
            await m.createTable(protokolle);
          }

          // v12 → v13: Partner/Subunternehmer.
          if (from < 13) {
            await m.createTable(partner);
            await m.addColumn(stunden, stunden.partnerId);
          }

          // v13 → v14: Original-Foto nach Bemalen behalten.
          if (from < 14) {
            await m.addColumn(fotos, fotos.originalDaten);
            await m.addColumn(fotos, fotos.originalStorageUrl);
            await m.addColumn(fotos, fotos.originalStoragePfad);
          }

          // v14 → v15: Benutzer-Profilbild + persönliche Grußformel.
          if (from < 15) {
            await m.addColumn(benutzer, benutzer.profilBildBase64);
            await m.addColumn(benutzer, benutzer.profilBildMime);
            await m.addColumn(benutzer, benutzer.grussformel);
          }

          // v15 → v16: Endzeit für Termine (Wiedervorlagen).
          if (from < 16) {
            await m.addColumn(wiedervorlagen, wiedervorlagen.endeAm);
          }
        },
      );
}
