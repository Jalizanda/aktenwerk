import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../tables/angebote_table.dart';
import '../tables/anschreiben_table.dart';
import '../tables/artikel_table.dart';
import '../tables/auftraege_geraete_table.dart';
import '../tables/auftraege_table.dart';
import '../tables/auslagen_table.dart';
import '../tables/bank_bewegungen_table.dart';
import '../tables/bauteiloeffnungen_table.dart';
import '../tables/befangenheits_eintraege_table.dart';
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
import '../tables/lv_table.dart';
import '../tables/maengel_table.dart';
import '../tables/messwerte_table.dart';
import '../tables/norm_chats_table.dart';
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
  BankBewegungen,
  BefangenheitsEintraege,
  Messwerte,
  Wertermittlungen,
  Serienbriefe,
  RechercheNotizen,
  NormChats,
  LvKopf,
  LvPositionen,
  LvMengenzeilen,
  LvKatalog,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase._(super.executor);

  // Idempotentes addColumn: ignoriert "duplicate column name"-Fehler, die
  // auftreten wenn ein Backup-Restore die Spalte bereits angelegt hat aber
  // die gespeicherte Schema-Version noch auf einem älteren Stand ist.
  static Future<void> _addCol(
    Migrator m,
    TableInfo<Table, dynamic> table,
    GeneratedColumn<Object> col,
  ) async {
    try {
      await m.addColumn(table, col);
    } catch (e) {
      if (!e.toString().contains('duplicate column name')) rethrow;
    }
  }

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
  int get schemaVersion => 36;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          // Echte Step-by-Step-Migrationen — KEIN Drop-All mehr.
          // Jeder Block fügt nur die Spalten hinzu, die in dieser Version
          // dazukamen. Bestehende Daten bleiben erhalten.

          // v4 → v5: Normen-Aktualitäts-Tracking.
          if (from < 5) {
            await _addCol(m, normen, normen.aktualitaetStatus);
            await _addCol(m, normen, normen.aktualitaetGeprueftAm);
            await _addCol(m, normen, normen.aktualitaetQuelle);
            await _addCol(m, normen, normen.aktualitaetNotiz);
          }

          // v5 → v6: Upload-Felder für Fortbildungen, Geräte, Aufträge.
          if (from < 6) {
            await _addCol(m, 
                fortbildungen, fortbildungen.nachweisStorageUrl);
            await _addCol(m, 
                fortbildungen, fortbildungen.nachweisDateiname);
            await _addCol(m, 
                fortbildungen, fortbildungen.nachweisMimeType);
            await _addCol(m, 
                fortbildungen, fortbildungen.nachweisGroesse);

            await _addCol(m, 
                geraete, geraete.kalibrierscheinStorageUrl);
            await _addCol(m, 
                geraete, geraete.kalibrierscheinDateiname);
            await _addCol(m, 
                geraete, geraete.kalibrierscheinMimeType);
            await _addCol(m, 
                geraete, geraete.kalibrierscheinGroesse);
            await _addCol(m, geraete, geraete.handbuchStorageUrl);
            await _addCol(m, geraete, geraete.handbuchDateiname);
            await _addCol(m, geraete, geraete.handbuchMimeType);
            await _addCol(m, geraete, geraete.handbuchGroesse);
            await _addCol(m, geraete, geraete.fotoStorageUrl);
            await _addCol(m, geraete, geraete.fotoDateiname);

            await _addCol(m, 
                auftraege, auftraege.beweisbeschlussStorageUrl);
            await _addCol(m, 
                auftraege, auftraege.beweisbeschlussDateiname);
            await _addCol(m, 
                auftraege, auftraege.beweisbeschlussMimeType);
            await _addCol(m, 
                auftraege, auftraege.beweisbeschlussGroesse);
            await _addCol(m, 
                auftraege, auftraege.objektFotoStorageUrl);
            await _addCol(m, auftraege, auftraege.objektFotoDateiname);
          }

          // v6 → v7: Benutzer-Rolle + Modul-Berechtigungen.
          if (from < 7) {
            await _addCol(m, benutzer, benutzer.rolle);
            await _addCol(m, benutzer, benutzer.erlaubteModule);
            await _addCol(m, benutzer, benutzer.bearbeitbareModule);
          }

          // v7 → v8: PDF-Archivierung für Rechnungen + Angebote.
          if (from < 8) {
            await _addCol(m, rechnungen, rechnungen.pdfStorageUrl);
            await _addCol(m, rechnungen, rechnungen.pdfDateiname);
            await _addCol(m, rechnungen, rechnungen.pdfGroesse);
            await _addCol(m, rechnungen, rechnungen.pdfErstelltAm);

            await _addCol(m, angebote, angebote.pdfStorageUrl);
            await _addCol(m, angebote, angebote.pdfDateiname);
            await _addCol(m, angebote, angebote.pdfGroesse);
            await _addCol(m, angebote, angebote.pdfErstelltAm);
          }

          // v8 → v9: DATEV-Konten-Katalog + Ausgangs-Konto auf Rechnungen.
          // Eingangsrechnungen nutzen das vorhandene `datevKonto`-Feld.
          if (from < 9) {
            await m.createTable(konten);
            await _addCol(m, rechnungen, rechnungen.kontonummer);
          }

          // v9 → v10: DATEV Debitor-/Kreditor-Nummern.
          if (from < 10) {
            await _addCol(m, kunden, kunden.debitornummer);
            await _addCol(m, lieferanten, lieferanten.kreditornummer);
          }

          // v10 → v11: Angebote an Akte knüpfen.
          if (from < 11) {
            await _addCol(m, angebote, angebote.auftragId);
          }

          // v11 → v12: Ortstermin-Protokolle.
          if (from < 12) {
            await m.createTable(protokolle);
          }

          // v12 → v13: Partner/Subunternehmer.
          if (from < 13) {
            await m.createTable(partner);
            await _addCol(m, stunden, stunden.partnerId);
          }

          // v13 → v14: Original-Foto nach Bemalen behalten.
          if (from < 14) {
            await _addCol(m, fotos, fotos.originalDaten);
            await _addCol(m, fotos, fotos.originalStorageUrl);
            await _addCol(m, fotos, fotos.originalStoragePfad);
          }

          // v14 → v15: Benutzer-Profilbild + persönliche Grußformel.
          if (from < 15) {
            await _addCol(m, benutzer, benutzer.profilBildBase64);
            await _addCol(m, benutzer, benutzer.profilBildMime);
            await _addCol(m, benutzer, benutzer.grussformel);
          }

          // v15 → v16: Endzeit für Termine (Wiedervorlagen).
          if (from < 16) {
            await _addCol(m, wiedervorlagen, wiedervorlagen.endeAm);
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

            await _addCol(m, wiedervorlagen, wiedervorlagen.wiederholung);
            await _addCol(m, wiedervorlagen, wiedervorlagen.triggerTyp);
            await _addCol(m, wiedervorlagen, wiedervorlagen.triggerQuellId);
            await _addCol(m, wiedervorlagen, wiedervorlagen.checklisteJson);
          }

          // v17 → v18: Serienbrief-Historie.
          if (from < 18) {
            await m.createTable(serienbriefe);
          }

          // v18 → v19: Streitparteien (Kläger/Beklagter) an der Akte.
          if (from < 19) {
            await _addCol(m, auftraege, auftraege.klaeger);
            await _addCol(m, auftraege, auftraege.beklagter);
          }

          // v19 → v20: Primäres Gewerk an der Norm (für Gruppierung/Filter).
          if (from < 20) {
            await _addCol(m, normen, normen.gewerk);
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
            await _addCol(m, eingangsrechnungen, eingangsrechnungen.geprueft);
          }

          // v22 → v23: Abschnitts-Zuordnung an Fotos (Inline-Platzierung
          // pro Gutachten-Block).
          if (from < 23) {
            await _addCol(m, fotos, fotos.gutachtenAbschnitt);
          }

          // v23 → v24: HRB + weitere Ansprechpartner für Auftraggeber.
          if (from < 24) {
            await _addCol(m, kunden, kunden.hrb);
            await _addCol(m, kunden, kunden.ansprechpartner);
          }

          // v24 → v25: HRB für den Sachverständigen-Absender selbst.
          if (from < 25) {
            await _addCol(m, benutzer, benutzer.hrb);
          }

          // v25 → v26: Standard-Zahlungsbedingung pro Akte.
          if (from < 26) {
            await _addCol(m, auftraege, auftraege.zahlungsbedingung);
          }

          // v26 → v27: Persistente Chat-Verläufe für den Normen-RAG-Chat.
          if (from < 27) {
            await m.createTable(normChats);
          }

          // v27 → v28: Strukturierte Nachfragen (mehrere Q&A pro Schriftsatz)
          // + Bezug auf das jeweilige Gutachten für die Stellungnahme.
          if (from < 28) {
            await _addCol(m, rueckfragen, rueckfragen.gutachtenBezugDatum);
            await _addCol(m, rueckfragen, rueckfragen.gutachtenBezugNummer);
            await _addCol(m, rueckfragen, rueckfragen.fragenJson);
          }

          // v28 → v29: Versand-Tracking (Anzahl Ausfertigungen + Dokument-
          // referenz), Befangenheits-Erklärung gem. §§ 406/407 ZPO,
          // Mehrkostenanzeige § 8a Abs. 4 JVEG und strukturierte
          // Beweisfragen pro Akte.
          if (from < 29) {
            await _addCol(m, versand, versand.anzahlAusfertigungen);
            await _addCol(m, versand, versand.dokumentId);
            await _addCol(m, versand, versand.bezugBezeichnung);

            await _addCol(m, 
                auftraege, auftraege.befangenheitsGeprueftAm);
            await _addCol(m, 
                auftraege, auftraege.befangenheitsErgebnis);
            await _addCol(m, auftraege, auftraege.befangenheitsNotiz);

            await _addCol(m, auftraege, auftraege.mehrkostenAnzeigeAm);
            await _addCol(m, auftraege, auftraege.mehrkostenBetrag);
            await _addCol(m, 
                auftraege, auftraege.mehrkostenBegruendung);

            await _addCol(m, auftraege, auftraege.beweisfragenJson);
          }

          // v29 → v30: Anschreiben-Belegnummer + Druck-Zeitstempel (zum
          // Einfrieren des Schriftstücks beim "Drucken & in Akte ablegen").
          if (from < 30) {
            await _addCol(m, anschreiben, anschreiben.belegNr);
            await _addCol(m, anschreiben, anschreiben.gedrucktAm);
          }

          // v30 → v31: Leistungsverzeichnis-Modul (LV-Kopf, Positionen,
          // Mengenermittlung, eigener Katalog) — neues Modul neben der
          // alten Kalkulationen-Tabelle.
          if (from < 31) {
            await m.createTable(lvKopf);
            await m.createTable(lvPositionen);
            await m.createTable(lvMengenzeilen);
            await m.createTable(lvKatalog);
          }

          // v31 → v32: Bietergegenüberstellung (basisLvId + bieterName
          // auf lv_kopf) und MwSt. pro Position (ustSatz auf
          // lv_positionen) für gemischte Steuersätze.
          if (from < 32) {
            await _addCol(m, lvKopf, lvKopf.basisLvId);
            await _addCol(m, lvKopf, lvKopf.bieterName);
            await _addCol(m, lvPositionen, lvPositionen.ustSatz);
          }

          // v32 → v33: Bieter-Kontakt (Kunden-Verknüpfung) auf lv_kopf,
          // damit Adresse/Mail des Bieters aus den Kontakten gezogen
          // werden kann.
          if (from < 33) {
            await _addCol(m, lvKopf, lvKopf.bieterKundeId);
          }

          // v33 → v34: Gutachten-Anlagen als referenzierbare Dokumente,
          // die hinten ans PDF angehängt werden.
          if (from < 34) {
            await _addCol(m, gutachten, gutachten.anlagenJson);
          }

          // v34 → v35: Befangenheits-Register mit manuellen Einträgen
          // (zusätzlich zu den automatisch aggregierten aus den Akten).
          if (from < 35) {
            await m.createTable(befangenheitsEintraege);
          }

          // v35 → v36: Banking-Modul — Kontoauszug-Zeilen, die mit
          // Ausgangs-/Eingangsrechnungen verknüpft werden können.
          if (from < 36) {
            await m.createTable(bankBewegungen);
          }
        },
      );
}
