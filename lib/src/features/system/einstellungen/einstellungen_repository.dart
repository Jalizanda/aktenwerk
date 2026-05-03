import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../data/sync/firestore_service.dart';

/// Zentrale Schlüssel für typisierte Einstellungen.
/// Andere Module sollten diese Konstanten nutzen statt hard-coded Strings.
class SettingsKeys {
  SettingsKeys._();

  // ---------- Sachverständigen-Stammdaten ----------
  static const firmaName = 'firma.name';
  static const firmaTitel = 'firma.titel';
  static const firmaAnschrift = 'firma.anschrift';
  static const firmaTelefon = 'firma.telefon';
  static const firmaEmail = 'firma.email';
  static const firmaWebsite = 'firma.website';
  static const firmaLogoBase64 = 'firma.logo_base64';
  static const firmaLogoMime = 'firma.logo_mime';
  static const firmaLogo2Base64 = 'firma.logo2_base64';
  static const firmaLogo2Mime = 'firma.logo2_mime';
  static const firmaBestellung1 = 'firma.bestellung1';
  static const firmaBestellung2 = 'firma.bestellung2';

  // ---------- Steuerdaten ----------
  static const steuerUstId = 'steuer.ustid';
  static const steuerNr = 'steuer.nummer';
  static const steuerKleinunternehmer = 'steuer.kleinunternehmer'; // 'ja'|'nein'

  // ---------- Bankverbindung ----------
  static const bankInhaber = 'bank.inhaber';
  static const bankName = 'bank.name';
  static const bankIban = 'bank.iban';
  static const bankBic = 'bank.bic';

  // ---------- Honorar ----------
  static const standardStundensatz = 'standard.stundensatz';
  static const stundensatzJveg = 'standard.stundensatz_jveg';
  static const standardUstSatz = 'standard.ust_satz';
  static const standardZahlungszielTage = 'standard.zahlungsziel_tage';
  // JVEG-Honorargruppen — werden in Stunden, Kostenvorschuss und JVEG-
  // Rechnungen automatisch angewendet, wenn die Akte einer Honorargruppe
  // zugeordnet ist. Defaults entsprechen JVEG 2021.
  static const honorargruppeM1Satz = 'honorar.gruppe_m1';
  static const honorargruppeM2Satz = 'honorar.gruppe_m2';
  static const honorargruppeM3Satz = 'honorar.gruppe_m3';
  static const honorargruppeSonstigesSatz = 'honorar.gruppe_sonstiges';

  // ---------- JVEG-Sätze ----------
  static const jvegKmSatz = 'jveg.km_satz';
  static const jvegSchreibsatz = 'jveg.schreibsatz_1000';
  static const jvegKopieSw = 'jveg.kopie_sw';
  static const jvegKopieFarbe = 'jveg.kopie_farbe';
  static const jvegLichtbildErstes = 'jveg.lichtbild_erstes';
  static const jvegLichtbildWeitere = 'jveg.lichtbild_weitere';

  // ---------- Nummernkreise ----------
  // Pattern: {muster, naechste, reset}
  // Reset: 'jahr' | 'nie'
  static const nummernkreisAktenzeichen = 'nummernkreis.aktenzeichen';
  static const nummernkreisAktenzeichenNaechste =
      'nummernkreis.aktenzeichen.naechste';
  static const nummernkreisAktenzeichenReset =
      'nummernkreis.aktenzeichen.reset';

  static const nummernkreisRechnung = 'nummernkreis.rechnung';
  static const nummernkreisRechnungNaechste =
      'nummernkreis.rechnung.naechste';
  static const nummernkreisRechnungReset = 'nummernkreis.rechnung.reset';

  // Eigener Kreis für Akontoanforderungen — die werden USt-technisch erst
  // mit Zahlung als Anzahlungsrechnung relevant; darum getrennte Nummernfolge.
  static const nummernkreisAkonto = 'nummernkreis.akonto';
  static const nummernkreisAkontoNaechste =
      'nummernkreis.akonto.naechste';
  static const nummernkreisAkontoReset = 'nummernkreis.akonto.reset';

  static const nummernkreisAngebot = 'nummernkreis.angebot';
  static const nummernkreisAngebotNaechste =
      'nummernkreis.angebot.naechste';
  static const nummernkreisAngebotReset = 'nummernkreis.angebot.reset';

  static const nummernkreisAuftragsbestaetigung =
      'nummernkreis.auftragsbestaetigung';
  static const nummernkreisAuftragsbestaetigungNaechste =
      'nummernkreis.auftragsbestaetigung.naechste';
  static const nummernkreisAuftragsbestaetigungReset =
      'nummernkreis.auftragsbestaetigung.reset';

  static const nummernkreisGutachten = 'nummernkreis.gutachten';
  static const nummernkreisGutachtenNaechste =
      'nummernkreis.gutachten.naechste';
  static const nummernkreisGutachtenReset = 'nummernkreis.gutachten.reset';

  static const nummernkreisFortbildung = 'nummernkreis.fortbildung';
  static const nummernkreisFortbildungNaechste =
      'nummernkreis.fortbildung.naechste';
  static const nummernkreisFortbildungReset =
      'nummernkreis.fortbildung.reset';

  // Interne Belegnummer für Anschreiben/Dokumente (D{YYYY}-{NNNN}).
  static const nummernkreisDokument = 'nummernkreis.dokument';
  static const nummernkreisDokumentNaechste =
      'nummernkreis.dokument.naechste';
  static const nummernkreisDokumentReset = 'nummernkreis.dokument.reset';

  // ---------- Texte / Fußzeilen ----------
  static const rechnungFusstext = 'rechnung.fusstext';
  static const rechnungSchlusstext = 'rechnung.schlusstext';
  static const angebotFusstext = 'angebot.fusstext';

  // ---------- DATEV / Buchhaltung ----------
  static const datevKontenrahmen =
      'datev.kontenrahmen'; // 'SKR03' | 'SKR04'

  /// Leitweg-ID für XRechnung/ZUGFeRD bei Behörden-Rechnungen.
  static const leitwegId = 'erechnung.leitweg_id';

  // ---------- Sachverständigen-Siegel ----------
  static const siegelBase64 = 'siegel.base64';
  static const siegelMime = 'siegel.mime';
  /// 'unten_links' | 'unten_rechts' | 'mit_unterschrift'
  static const siegelPosition = 'siegel.position';
  static const siegelBestellBehoerde = 'siegel.bestell_behoerde';
  static const siegelBestellNr = 'siegel.bestell_nr';
  static const siegelGueltigBis = 'siegel.gueltig_bis'; // ISO-Datum
  static const unterschriftBase64 = 'unterschrift.base64';
  static const unterschriftMime = 'unterschrift.mime';

  /// Interner Kostensatz pro Stunde (für Deckungsbeitrag).
  static const internerKostensatz = 'kalkulation.interner_kostensatz';

  // ---------- Tätigkeitsbericht IHK/HWK ----------
  static const taetigkeitBerichtEmpfaenger =
      'taetigkeit.empfaenger'; // Kammer
  static const taetigkeitBerichtVorwort = 'taetigkeit.vorwort';
  static const taetigkeitBerichtEidesstatt =
      'taetigkeit.eidesstattliche_erklaerung';

  // ---------- UI ----------
  static const theme = 'ui.theme'; // 'system' | 'light' | 'dark'

  // ---------- KI-Modell-Zuordnung pro Feature ----------
  /// Werte: 'gemini-2.5-flash' | 'gemini-2.5-flash-lite' | 'gemini-2.5-pro'
  static const kiModellKorrektur = 'ki.modell.korrektur';
  static const kiModellUmformulieren = 'ki.modell.umformulieren';
  static const kiModellJuristisch = 'ki.modell.juristisch';
  static const kiModellKuerzen = 'ki.modell.kuerzen';
  static const kiModellErweitern = 'ki.modell.erweitern';
  static const kiModellNormenChat = 'ki.modell.normen_chat';
  static const kiModellAudioTranskript = 'ki.modell.audio_transkript';
  static const kiModellBelegErfassung = 'ki.modell.beleg_erfassung';

  // Gutachten-Editor Standard-Schriftart und -größe (siehe
  // EinstellungenScreen → Briefkopf/Layout). Dropdown-Wert (z. B.
  // 'Arial', 'Times New Roman', 'Standard') und PT-Wert ('10','11','12').
  static const gutachtenFontFamily = 'gutachten.font_family';
  static const gutachtenFontSize = 'gutachten.font_size';
}

class EinstellungenRepository {
  EinstellungenRepository(this._db, [this._fs]);
  final AppDatabase _db;
  final FirestoreService? _fs;

  Future<String?> get(String key) async {
    final row = await (_db.select(_db.einstellungen)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.wert;
  }

  Future<String> getOr(String key, String fallback) async =>
      (await get(key)) ?? fallback;

  Future<double?> getDouble(String key) async {
    final v = await get(key);
    if (v == null) return null;
    return double.tryParse(v.replaceAll(',', '.'));
  }

  /// Werte > ~900 KB werden nicht zu Firestore gepusht (Firestore hat 1 MB
  /// pro Document und die Mandant-Logos liegen als Base64 vor).
  static const int _firestoreMaxValueBytes = 900 * 1024;
  static const Duration _firestoreTimeout = Duration(seconds: 6);

  Future<void> set(String key, String? value) async {
    final now = DateTime.now();
    if (value == null || value.isEmpty) {
      await (_db.delete(_db.einstellungen)
            ..where((t) => t.key.equals(key)))
          .go();
      // Cloud-Löschung darf die lokale Persistenz nicht blockieren.
      unawaited(_fs
          ?.delete('einstellungen', _fsDocId(key))
          .timeout(_firestoreTimeout)
          .catchError((_) {}));
      return;
    }
    // WICHTIG: insertOnConflictUpdate löst Konflikte über den Primary Key
    // (id) auf — die UNIQUE-Constraint liegt aber auf `key`, was beim
    // Wiederspeichern in einen "UNIQUE constraint failed: einstellungen.key"
    // läuft. Daher manueller Upsert anhand des Keys.
    final existing = await (_db.select(_db.einstellungen)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    if (existing != null) {
      await (_db.update(_db.einstellungen)
            ..where((t) => t.id.equals(existing.id)))
          .write(EinstellungenCompanion(
            wert: Value(value),
            updatedAt: Value(now),
          ));
    } else {
      await _db.into(_db.einstellungen).insert(
            EinstellungenCompanion.insert(
              key: key,
              wert: Value(value),
              updatedAt: Value(now),
            ),
          );
    }
    if (value.length > _firestoreMaxValueBytes) {
      // z. B. Firma-Logo-Base64 ist zu groß für Firestore — nur lokal.
      return;
    }
    // Cloud-Push laufen lassen, aber nicht blockieren und nach Timeout
    // aufgeben — lokal ist die Wahrheit.
    unawaited(_fs
        ?.upsert('einstellungen', _fsDocId(key), {
          'key': key,
          'wert': value,
        })
        .timeout(_firestoreTimeout)
        .catchError((_) {}));
  }

  /// Pullt alle Einstellungen aus Firestore und überschreibt lokale Werte.
  /// Wird bei Mandanten-Wechsel automatisch ausgeführt.
  Future<int> pullFromFirestore() async {
    final fs = _fs;
    if (fs == null || !fs.enabled) return 0;
    final col = fs.orgCollection('einstellungen');
    if (col == null) return 0;
    final snap = await col.get();
    var count = 0;
    for (final doc in snap.docs) {
      final d = doc.data();
      final key = d['key']?.toString();
      final wert = d['wert']?.toString();
      if (key == null || key.isEmpty) continue;
      // Upsert per Key (siehe Hinweis in `set` — UNIQUE-Constraint liegt
      // auf `key`, nicht auf `id`).
      final existing = await (_db.select(_db.einstellungen)
            ..where((t) => t.key.equals(key)))
          .getSingleOrNull();
      if (existing != null) {
        await (_db.update(_db.einstellungen)
              ..where((t) => t.id.equals(existing.id)))
            .write(EinstellungenCompanion(
              wert: Value(wert),
              updatedAt: Value(DateTime.now()),
            ));
      } else {
        await _db.into(_db.einstellungen).insert(
              EinstellungenCompanion.insert(
                key: key,
                wert: Value(wert),
                updatedAt: Value(DateTime.now()),
              ),
            );
      }
      count++;
    }
    return count;
  }

  /// Dokument-ID für Firestore: wir verwenden den Key direkt (replaced für
  /// unerlaubte Zeichen). So ist pro Org jeder Key genau einmal vorhanden —
  /// saubere Upserts ohne ID-Mapping.
  String _fsDocId(String key) => key.replaceAll(RegExp(r'[/.#\$\[\]]'), '_');

  Stream<Map<String, String>> watchAll() {
    return _db.select(_db.einstellungen).watch().map((rows) => {
          for (final r in rows) r.key: r.wert ?? '',
        });
  }
}

final einstellungenRepositoryProvider =
    Provider<EinstellungenRepository>((ref) {
  return EinstellungenRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(firestoreServiceProvider),
  );
});

final einstellungenProvider = StreamProvider<Map<String, String>>((ref) {
  return ref.watch(einstellungenRepositoryProvider).watchAll();
});
