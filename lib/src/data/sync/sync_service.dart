import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_provider.dart';
import 'firestore_service.dart';

/// Spiegelt Drift-Entitäten in Richtung Firestore.
///
/// Dieser Service ist ein schlichter Push-Sync: bei jedem Start und auf
/// Wunsch per [syncAll] werden alle lokalen Datensätze in die jeweilige
/// Firestore-Collection hochgeladen (merge). Das reicht als erster
/// Schritt für Cloud-Backup. Ein feingranularer Zwei-Wege-Sync mit
/// Conflict-Resolution kann später auf dieser Basis aufgebaut werden.
class SyncService {
  SyncService(this._db, this._fs);
  final AppDatabase _db;
  final FirestoreService _fs;

  /// True, wenn Firebase initialisiert und ein User angemeldet ist.
  bool get enabled => _fs.enabled;

  Future<void> syncAll() async {
    if (!_fs.enabled) return;
    await pushKunden();
    await pushAuftraege();
    await pushRechnungen();
    await pushAngebote();
    await pushEingangsrechnungen();
    await pushLieferanten();
    await pushArtikel();
    await pushStunden();
    await pushAuslagen();
    await pushNormen();
    await pushGeraete();
    await pushTextbausteine();
    await pushFortbildungen();
    await pushGutachten();
    await pushAnschreiben();
    await pushFotos();
    await pushDokumente();
    await pushBenutzer();
    await pushEinstellungen();
  }

  /// Dokumente (PDFs/Word/…) werden nur als Metadaten gespiegelt;
  /// der eigentliche Datei-Inhalt liegt in Firebase Storage (storageUrl).
  Future<void> pushDokumente() async {
    final rows = await _db.select(_db.dokumente).get();
    for (final r in rows) {
      await _fs.upsert('dokumente', r.id.toString(), {
        'auftragId': r.auftragId,
        'titel': r.titel,
        'beschreibung': r.beschreibung,
        'kategorie': r.kategorie,
        'mimeType': r.mimeType,
        'dateigroesse': r.dateigroesse,
        'storageUrl': r.storageUrl,
        'storagePfad': r.storagePfad,
        'datum': r.datum.toIso8601String(),
      });
    }
  }

  /// Fotos werden nur mit Metadaten in Firestore abgelegt — die Bilddaten
  /// selbst liegen in Firebase Storage (storageUrl).
  Future<void> pushFotos() async {
    final rows = await _db.select(_db.fotos).get();
    for (final r in rows) {
      await _fs.upsert('fotos', r.id.toString(), {
        'auftragId': r.auftragId,
        'gutachtenId': r.gutachtenId,
        'titel': r.titel,
        'beschreibung': r.beschreibung,
        'mimeType': r.mimeType,
        'storageUrl': r.storageUrl,
        'storagePfad': r.storagePfad,
        'aufnahmeAm': r.aufnahmeAm?.toIso8601String(),
        'lat': r.lat,
        'lon': r.lon,
        'reihenfolge': r.reihenfolge,
      });
    }
  }

  Future<void> pushKunden() async {
    final rows = await _db.select(_db.kunden).get();
    for (final r in rows) {
      await _fs.upsert('kunden', r.id.toString(), {
        'typ': r.typ,
        'anrede': r.anrede,
        'titel': r.titel,
        'vorname': r.vorname,
        'nachname': r.nachname,
        'firma': r.firma,
        'strasse': r.strasse,
        'plz': r.plz,
        'ort': r.ort,
        'land': r.land,
        'telefon': r.telefon,
        'mobil': r.mobil,
        'fax': r.fax,
        'email': r.email,
        'website': r.website,
        'steuerNr': r.steuerNr,
        'ustId': r.ustId,
        'notiz': r.notiz,
      });
    }
  }

  Future<void> pushAuftraege() async {
    final rows = await _db.select(_db.auftraege).get();
    for (final r in rows) {
      await _fs.upsert('auftraege', r.id.toString(), {
        'aktenzeichen': r.aktenzeichen,
        'art': r.art,
        'status': r.status,
        'kundeId': r.kundeId,
        'bezeichnung': r.bezeichnung,
        'objektStrasse': r.objektStrasse,
        'objektPlz': r.objektPlz,
        'objektOrt': r.objektOrt,
        'objektLat': r.objektLat,
        'objektLon': r.objektLon,
        'gerichtsAktenzeichen': r.gerichtsAktenzeichen,
        'richter': r.richter,
        'eingangAm': r.eingangAm?.toIso8601String(),
        'auftragAm': r.auftragAm?.toIso8601String(),
        'abschlussAm': r.abschlussAm?.toIso8601String(),
        'stundensatz': r.stundensatz,
        'kostenLimit': r.kostenLimit,
        'kostenvorschuss': r.kostenvorschuss,
        'notiz': r.notiz,
      });
    }
  }

  Future<void> pushRechnungen() async {
    final rows = await _db.select(_db.rechnungen).get();
    for (final r in rows) {
      await _fs.upsert('rechnungen', r.id.toString(), {
        'rechnungsnummer': r.rechnungsnummer,
        'auftragId': r.auftragId,
        'kundeId': r.kundeId,
        'rechnungsdatum': r.rechnungsdatum?.toIso8601String(),
        'leistungsdatum': r.leistungsdatum?.toIso8601String(),
        'faelligAm': r.faelligAm?.toIso8601String(),
        'bezahltAm': r.bezahltAm?.toIso8601String(),
        'status': r.status,
        'netto': r.netto,
        'ustSatz': r.ustSatz,
        'ustBetrag': r.ustBetrag,
        'brutto': r.brutto,
        'bezahlt': r.bezahlt,
        'positionenJson': r.positionenJson,
        'kopftext': r.kopftext,
        'fusstext': r.fusstext,
      });
    }
  }

  Future<void> pushAngebote() async {
    final rows = await _db.select(_db.angebote).get();
    for (final r in rows) {
      await _fs.upsert('angebote', r.id.toString(), {
        'angebotsnummer': r.angebotsnummer,
        'kundeId': r.kundeId,
        'betreff': r.betreff,
        'datum': r.datum.toIso8601String(),
        'gueltigBis': r.gueltigBis?.toIso8601String(),
        'status': r.status,
        'netto': r.netto,
        'brutto': r.brutto,
        'positionenJson': r.positionenJson,
      });
    }
  }

  Future<void> pushEingangsrechnungen() async {
    final rows = await _db.select(_db.eingangsrechnungen).get();
    for (final r in rows) {
      await _fs.upsert('eingangsrechnungen', r.id.toString(), {
        'rechnungsnummer': r.rechnungsnummer,
        'auftragId': r.auftragId,
        'rechnungsdatum': r.rechnungsdatum?.toIso8601String(),
        'faelligAm': r.faelligAm?.toIso8601String(),
        'bezahltAm': r.bezahltAm?.toIso8601String(),
        'status': r.status,
        'kategorie': r.kategorie,
        'beschreibung': r.beschreibung,
        'netto': r.netto,
        'ustBetrag': r.ustBetrag,
        'brutto': r.brutto,
      });
    }
  }

  Future<void> pushLieferanten() async {
    final rows = await _db.select(_db.lieferanten).get();
    for (final r in rows) {
      await _fs.upsert('lieferanten', r.id.toString(), {
        'firma': r.firma,
        'ansprechpartner': r.ansprechpartner,
        'strasse': r.strasse,
        'plz': r.plz,
        'ort': r.ort,
        'telefon': r.telefon,
        'email': r.email,
        'kategorie': r.kategorie,
        'iban': r.iban,
        'bic': r.bic,
      });
    }
  }

  Future<void> pushArtikel() async {
    final rows = await _db.select(_db.artikel).get();
    for (final r in rows) {
      await _fs.upsert('artikel', r.id.toString(), {
        'nummer': r.nummer,
        'bezeichnung': r.bezeichnung,
        'beschreibung': r.beschreibung,
        'kategorie': r.kategorie,
        'einheit': r.einheit,
        'einzelpreis': r.einzelpreis,
        'ustSatz': r.ustSatz,
        'aktiv': r.aktiv,
      });
    }
  }

  Future<void> pushStunden() async {
    final rows = await _db.select(_db.stunden).get();
    for (final r in rows) {
      await _fs.upsert('stunden', r.id.toString(), {
        'auftragId': r.auftragId,
        'datum': r.datum.toIso8601String(),
        'minuten': r.minuten,
        'satz': r.satz,
        'taetigkeit': r.taetigkeit,
        'abgerechnet': r.abgerechnet,
      });
    }
  }

  Future<void> pushAuslagen() async {
    final rows = await _db.select(_db.auslagen).get();
    for (final r in rows) {
      await _fs.upsert('auslagen', r.id.toString(), {
        'auftragId': r.auftragId,
        'datum': r.datum.toIso8601String(),
        'kategorie': r.kategorie,
        'beschreibung': r.beschreibung,
        'menge': r.menge,
        'einheit': r.einheit,
        'einzelpreis': r.einzelpreis,
        'summe': r.summe,
        'abgerechnet': r.abgerechnet,
      });
    }
  }

  Future<void> pushNormen() async {
    final rows = await _db.select(_db.normen).get();
    for (final r in rows) {
      await _fs.upsert('normen', r.id.toString(), {
        'nummer': r.nummer,
        'titel': r.titel,
        'ausgabe': r.ausgabe,
        'kategorie': r.kategorie,
        'favorit': r.favorit,
        'aktiv': r.aktiv,
      });
    }
  }

  Future<void> pushGeraete() async {
    final rows = await _db.select(_db.geraete).get();
    for (final r in rows) {
      await _fs.upsert('geraete', r.id.toString(), {
        'bezeichnung': r.bezeichnung,
        'hersteller': r.hersteller,
        'modell': r.modell,
        'seriennummer': r.seriennummer,
        'kalibriertAm': r.kalibriertAm?.toIso8601String(),
        'naechsteKalibrierung':
            r.naechsteKalibrierung?.toIso8601String(),
        'aktiv': r.aktiv,
      });
    }
  }

  Future<void> pushTextbausteine() async {
    final rows = await _db.select(_db.textbausteine).get();
    for (final r in rows) {
      await _fs.upsert('textbausteine', r.id.toString(), {
        'titel': r.titel,
        'kategorie': r.kategorie,
        'inhalt': r.inhalt,
        'favorit': r.favorit,
      });
    }
  }

  Future<void> pushFortbildungen() async {
    final rows = await _db.select(_db.fortbildungen).get();
    for (final r in rows) {
      await _fs.upsert('fortbildungen', r.id.toString(), {
        'titel': r.titel,
        'veranstalter': r.veranstalter,
        'datumVon': r.datumVon?.toIso8601String(),
        'datumBis': r.datumBis?.toIso8601String(),
        'stunden': r.stunden,
        'kosten': r.kosten,
        'thema': r.thema,
      });
    }
  }

  Future<void> pushGutachten() async {
    final rows = await _db.select(_db.gutachten).get();
    for (final r in rows) {
      await _fs.upsert('gutachten', r.id.toString(), {
        'auftragId': r.auftragId,
        'titel': r.titel,
        'status': r.status,
        'ortsterminAm': r.ortsterminAm?.toIso8601String(),
        'abgabeAm': r.abgabeAm?.toIso8601String(),
        'abschnitteJson': r.abschnitteJson,
      });
    }
  }

  Future<void> pushAnschreiben() async {
    final rows = await _db.select(_db.anschreiben).get();
    for (final r in rows) {
      await _fs.upsert('anschreiben', r.id.toString(), {
        'auftragId': r.auftragId,
        'kundeId': r.kundeId,
        'datum': r.datum.toIso8601String(),
        'betreff': r.betreff,
        'inhaltJson': r.inhaltJson,
        'status': r.status,
      });
    }
  }

  Future<void> pushBenutzer() async {
    final rows = await _db.select(_db.benutzer).get();
    for (final r in rows) {
      await _fs.upsert('benutzer', r.id.toString(), {
        'vorname': r.vorname,
        'nachname': r.nachname,
        'firma': r.firma,
        'strasse': r.strasse,
        'plz': r.plz,
        'ort': r.ort,
        'telefon': r.telefon,
        'email': r.email,
        'steuerNr': r.steuerNr,
        'ustId': r.ustId,
        'iban': r.iban,
        'bic': r.bic,
        'standardStundensatz': r.standardStundensatz,
        'aktiv': r.aktiv,
      });
    }
  }

  Future<void> pushEinstellungen() async {
    final rows = await _db.select(_db.einstellungen).get();
    for (final r in rows) {
      await _fs.upsert('einstellungen', r.id.toString(), {
        'key': r.key,
        'wert': r.wert,
      });
    }
  }

  /// Pull: lädt eine Firestore-Sammlung nach und merged in Drift.
  /// Minimaler Stub für Kunden – dient als Blaupause für weitere Entitäten.
  Future<int> pullKunden() async {
    if (!_fs.enabled) return 0;
    final col = _fs.orgCollection('kunden');
    if (col == null) return 0;
    final snap = await col.get();
    var count = 0;
    for (final doc in snap.docs) {
      final d = doc.data();
      final id = int.tryParse(doc.id);
      if (id == null) continue;
      await _db.into(_db.kunden).insertOnConflictUpdate(KundenCompanion.insert(
            id: Value(id),
            typ: Value(d['typ'] as String? ?? 'privat'),
            anrede: Value(d['anrede'] as String?),
            titel: Value(d['titel'] as String?),
            vorname: Value(d['vorname'] as String?),
            nachname: Value(d['nachname'] as String?),
            firma: Value(d['firma'] as String?),
            strasse: Value(d['strasse'] as String?),
            plz: Value(d['plz'] as String?),
            ort: Value(d['ort'] as String?),
            telefon: Value(d['telefon'] as String?),
            email: Value(d['email'] as String?),
            notiz: Value(d['notiz'] as String?),
          ));
      count++;
    }
    return count;
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    ref.watch(appDatabaseProvider),
    ref.watch(firestoreServiceProvider),
  );
});
