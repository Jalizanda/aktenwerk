import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../tables/angebote_table.dart';
import '../tables/anschreiben_table.dart';
import '../tables/artikel_table.dart';
import '../tables/auftraege_geraete_table.dart';
import '../tables/auftraege_table.dart';
import '../tables/auslagen_table.dart';
import '../tables/bauteiloeffnungen_table.dart';
import '../tables/benutzer_table.dart';
import '../tables/dokumente_table.dart';
import '../tables/eingangsrechnungen_table.dart';
import '../tables/einstellungen_table.dart';
import '../tables/erlaeuterungen_table.dart';
import '../tables/fortbildungen_table.dart';
import '../tables/fotos_table.dart';
import '../tables/geraete_table.dart';
import '../tables/gutachten_table.dart';
import '../tables/journaleintraege_table.dart';
import '../tables/kalkulationen_table.dart';
import '../tables/konten_table.dart';
import '../tables/kunden_table.dart';
import '../tables/lieferanten_table.dart';
import '../tables/maengel_table.dart';
import '../tables/messwerte_table.dart';
import '../tables/normen_table.dart';
import '../tables/partner_table.dart';
import '../tables/protokolle_table.dart';
import '../tables/qualifikationen_table.dart';
import '../tables/rechnungen_table.dart';
import '../tables/recherche_notizen_table.dart';
import '../tables/rueckfragen_table.dart';
import '../tables/serienbriefe_table.dart';
import '../tables/stunden_table.dart';
import '../tables/textbausteine_table.dart';
import '../tables/uebergaben_table.dart';
import '../tables/versand_table.dart';
import '../tables/wertermittlungen_table.dart';
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
  Journaleintraege,
  Maengel,
  Uebergaben,
  Qualifikationen,
  Bauteiloeffnungen,
  Messwerte,
  Wertermittlungen,
  Serienbriefe,
  RechercheNotizen,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase._(super.executor);

  /// Öffnet eine Datenbank unter dem angegebenen Namen. Jeder Name
  /// entspricht einer eigenen IndexedDB/Datei — so lassen sich
  /// Produktiv- und Demo-Mandant sauber trennen.
  factory AppDatabase.named(String dbName) {
    return AppDatabase._(driftDatabase(
      name: dbName,
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    ));
  }

  /// Legacy-Konstruktor für Tests / Direktaufruf.
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(
          name: 'aktenwerk',
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ));

  @override
  int get schemaVersion => 26;

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

          // v16 → v17: Sachverständigen-Features #12, #13, #14, #15, #16,
          // #17, #18 sowie Erweiterungen der Wiedervorlagen (#11).
          if (from < 17) {
            await m.createTable(journaleintraege);
            await m.createTable(maengel);
            await m.createTable(uebergaben);
            await m.createTable(qualifikationen);
            await m.createTable(bauteiloeffnungen);
            await m.createTable(messwerte);
            await m.createTable(wertermittlungen);

            await m.addColumn(wiedervorlagen, wiedervorlagen.wiederholung);
            await m.addColumn(wiedervorlagen, wiedervorlagen.triggerTyp);
            await m.addColumn(wiedervorlagen, wiedervorlagen.triggerQuellId);
            await m.addColumn(wiedervorlagen, wiedervorlagen.checklisteJson);
          }

          // v17 → v18: Serienbrief-Historie.
          if (from < 18) {
            await m.createTable(serienbriefe);
          }

          // v18 → v19: Streitparteien (Kläger/Beklagter) an der Akte.
          if (from < 19) {
            await m.addColumn(auftraege, auftraege.klaeger);
            await m.addColumn(auftraege, auftraege.beklagter);
          }

          // v19 → v20: Primäres Gewerk an der Norm (für Gruppierung/Filter).
          if (from < 20) {
            await m.addColumn(normen, normen.gewerk);
          }

          // v20 → v21: Recherche-Ablage (Notizen aus Normen-KI-Chat,
          // die beim Gutachten-Schreiben als Baustein eingefügt werden).
          if (from < 21) {
            await m.createTable(rechercheNotizen);
          }

          // v21 → v22: Geprüft-Flag an Eingangsrechnungen. KI-Massen-
          // erfassung legt neue Rechnungen mit geprueft=false an, damit
          // der SV die Werte noch einmal durchgehen kann.
          if (from < 22) {
            await m.addColumn(eingangsrechnungen, eingangsrechnungen.geprueft);
          }

          // v22 → v23: Abschnitts-Zuordnung an Fotos (Inline-Platzierung
          // pro Gutachten-Block).
          if (from < 23) {
            await m.addColumn(fotos, fotos.gutachtenAbschnitt);
          }

          // v23 → v24: HRB + weitere Ansprechpartner für Auftraggeber.
          if (from < 24) {
            await m.addColumn(kunden, kunden.hrb);
            await m.addColumn(kunden, kunden.ansprechpartner);
          }

          // v24 → v25: HRB für den Sachverständigen-Absender selbst.
          if (from < 25) {
            await m.addColumn(benutzer, benutzer.hrb);
          }

          // v25 → v26: Standard-Zahlungsbedingung pro Akte.
          if (from < 26) {
            await m.addColumn(auftraege, auftraege.zahlungsbedingung);
          }
        },
      );
}
