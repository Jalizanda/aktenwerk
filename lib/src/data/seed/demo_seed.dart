import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_provider.dart';
import '../sync/sync_service.dart';

/// Lädt den Demo-Seed aus `assets/data/demo_seed.json` (extrahiert aus der
/// SV-Software mit `tool/extract_demo_seed.js`) und schreibt alle Datensätze
/// in die Drift-DB. Vorher werden alle vorhandenen Daten gelöscht.
class DemoSeeder {
  DemoSeeder(this._db, [this._sync]);
  final AppDatabase _db;
  final SyncService? _sync;

  /// Lädt in die lokale Drift-DB und pusht anschließend alles nach Firestore.
  /// Wenn kein SyncService da ist (nicht eingeloggt), wird nur lokal geladen.
  Future<DemoSeedReport> loadAllAndSync() async {
    final report = await loadAll();
    if (_sync != null && _sync.enabled) {
      await _sync.syncAll();
    }
    return report;
  }

  Future<DemoSeedReport> loadAll() async {
    final raw = await rootBundle.loadString('assets/data/demo_seed.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final report = DemoSeedReport();

    await _db.transaction(() async {
      // Reihenfolge: erst Abhängige löschen, dann FK-Ziele.
      await _wipeAll();

      // Kunden-ID-Mapping (alte idb-id → neue drift-id).
      final kundenMap = await _seedKunden(_asList(json['kunden']), report);
      final auftraegeMap =
          await _seedAuftraege(_asList(json['auftraege']), kundenMap, report);
      await _seedStunden(_asList(json['stunden']), auftraegeMap, report);
      await _seedRechnungen(
          _asList(json['rechnungen']), kundenMap, auftraegeMap, report);
      await _seedGutachten(
          _asList(json['gutachten']), auftraegeMap, report);
      await _seedFotos(_asList(json['fotos']), auftraegeMap, report);
      await _seedAnschreiben(_asList(json['anschreiben']), kundenMap,
          auftraegeMap, report);
      await _seedKalkulationen(
          _asList(json['kalkulationen']), auftraegeMap, report);
      await _seedAuslagen(
          _asList(json['auslagen']), auftraegeMap, report);
      await _seedRueckfragen(
          _asList(json['rueckfragen']), auftraegeMap, report);
      await _seedArtikel(_asList(json['artikel']), report);
      await _seedAngebote(_asList(json['angebote']), kundenMap, report);
      await _seedGeraete(_asList(json['geraete']), report);
      await _seedNormen(_asList(json['normen']), report);
      final lieferantenMap = await _seedLieferanten(
          _asList(json['lieferanten']), report);
      await _seedEingangsrechnungen(
          _asList(json['eingangsrechnungen']),
          auftraegeMap,
          lieferantenMap,
          report);
      await _seedErlaeuterungen(
          _asList(json['erlaeuterungen']), auftraegeMap, report);
      await _seedTextbausteine(_asList(json['textbausteine']), report);
      await _seedDokumente(_asList(json['dokumente']), auftraegeMap, report);
      await _seedWiedervorlagen(
          _asList(json['wiedervorlagen']), auftraegeMap, report);
      await _seedFortbildungen(
          _asList(json['fortbildungen']), report);
      await _seedEinstellungen(_asList(json['einstellungen']), report);
    });
    return report;
  }

  Future<void> _seedWiedervorlagen(
    List<Map<String, dynamic>> list,
    Map<int, int> auftragMap,
    DemoSeedReport r,
  ) async {
    for (final w in list) {
      final fall = _parseDate(w['faelligAm']);
      if (fall == null) continue;
      await _db.into(_db.wiedervorlagen).insert(WiedervorlagenCompanion.insert(
            auftragId: Value(_mapId(w['auftragId'], auftragMap)),
            titel: w['titel']?.toString() ?? 'Wiedervorlage',
            anlass: Value(w['anlass']?.toString()),
            beschreibung: Value(w['beschreibung']?.toString()),
            prioritaet: Value(w['prioritaet']?.toString() ?? 'normal'),
            faelligAm: Value(fall),
            erledigt: Value(w['erledigt'] == true),
            erledigtAm: Value(w['erledigt'] == true
                ? _parseDate(w['erledigtAm']) ?? DateTime.now()
                : null),
          ));
    }
  }

  Future<void> _seedFortbildungen(
    List<Map<String, dynamic>> list,
    DemoSeedReport r,
  ) async {
    for (final f in list) {
      await _db.into(_db.fortbildungen).insert(FortbildungenCompanion.insert(
            titel: f['titel']?.toString() ?? 'Fortbildung',
            veranstalter: Value(f['veranstalter']?.toString()),
            ort: Value(f['ort']?.toString()),
            sachgebiet: Value(f['sachgebiet']?.toString()),
            datumVon: Value(_parseDate(f['datumVon'])),
            datumBis: Value(_parseDate(f['datumBis'])),
            stunden: Value(_asDouble(f['stunden']) ?? 0),
            gebuehr: Value(_asDouble(f['gebuehr']) ?? 0),
            kosten: Value(_asDouble(f['kosten']) ?? 0),
            thema: Value(f['thema']?.toString()),
            notiz: Value(f['notiz']?.toString()),
          ));
    }
  }

  Future<void> _seedDokumente(
    List<Map<String, dynamic>> list,
    Map<int, int> auftragMap,
    DemoSeedReport r,
  ) async {
    for (final d in list) {
      await _db.into(_db.dokumente).insert(DokumenteCompanion.insert(
            auftragId: Value(_mapId(d['auftragId'], auftragMap)),
            titel: Value(d['filename']?.toString() ??
                d['titel']?.toString()),
            beschreibung: Value(d['beschreibung']?.toString()),
            kategorie: Value(d['kategorie']?.toString()),
            mimeType: Value(d['mimetype']?.toString() ??
                d['mimeType']?.toString()),
            dateigroesse: Value((d['filesize'] as num?)?.toInt() ??
                (d['dateigroesse'] as num?)?.toInt()),
            datum: Value(_parseDate(d['datum']) ?? DateTime.now()),
          ));
    }
    r.dokumente = list.length;
  }

  // ---------------------- Löschen ----------------------

  Future<void> _wipeAll() async {
    await _db.delete(_db.anschreiben).go();
    await _db.delete(_db.erlaeuterungen).go();
    await _db.delete(_db.rueckfragen).go();
    await _db.delete(_db.fotos).go();
    await _db.delete(_db.dokumente).go();
    await _db.delete(_db.kalkulationen).go();
    await _db.delete(_db.auslagen).go();
    await _db.delete(_db.stunden).go();
    await _db.delete(_db.rechnungen).go();
    await _db.delete(_db.angebote).go();
    await _db.delete(_db.gutachten).go();
    await _db.delete(_db.eingangsrechnungen).go();
    await _db.delete(_db.auftraege).go();
    await _db.delete(_db.lieferanten).go();
    await _db.delete(_db.kunden).go();
    await _db.delete(_db.artikel).go();
    await _db.delete(_db.geraete).go();
    await _db.delete(_db.normen).go();
    await _db.delete(_db.textbausteine).go();
    await _db.delete(_db.wiedervorlagen).go();
    await _db.delete(_db.fortbildungen).go();
    await _db.delete(_db.versand).go();
    await _db.delete(_db.einstellungen).go();
    await _db.delete(_db.benutzer).go();
  }

  // ---------------------- Einzelne Seeds ----------------------

  Future<Map<int, int>> _seedKunden(
      List<Map<String, dynamic>> list, DemoSeedReport r) async {
    final map = <int, int>{};
    for (final k in list) {
      final id = await _db.into(_db.kunden).insert(KundenCompanion.insert(
            typ: Value(k['typ']?.toString() ?? 'privat'),
            anrede: Value(k['anrede']?.toString()),
            titel: Value(k['titel']?.toString()),
            vorname: Value(k['vorname']?.toString()),
            nachname: Value(k['nachname']?.toString()),
            firma: Value(k['firma']?.toString()),
            strasse: Value(k['strasse']?.toString()),
            plz: Value(k['plz']?.toString()),
            ort: Value(k['ort']?.toString()),
            telefon: Value(k['telefon']?.toString()),
            email: Value(k['email']?.toString()),
            ustId: Value(k['ustid']?.toString()),
            aktenpraefix: Value(k['aktenpraefix']?.toString()),
            notiz: Value(
                k['notizen']?.toString() ?? k['notiz']?.toString()),
          ));
      map[(k['id'] as num).toInt()] = id;
    }
    r.kunden = list.length;
    return map;
  }

  Future<Map<int, int>> _seedAuftraege(
    List<Map<String, dynamic>> list,
    Map<int, int> kundenMap,
    DemoSeedReport r,
  ) async {
    final map = <int, int>{};
    for (final a in list) {
      final id = await _db.into(_db.auftraege).insert(AuftraegeCompanion.insert(
            aktenzeichen: Value(a['aktenzeichen']?.toString()),
            azExtern: Value(a['azExtern']?.toString()),
            art: Value(a['art']?.toString() ?? 'privat'),
            status: Value(_mapAuftragStatus(a['status']?.toString())),
            kundeId: Value(_mapId(a['kundeId'], kundenMap)),
            betreff: Value(a['betreff']?.toString()),
            bezeichnung:
                Value(_pickString(a, ['bezeichnung', 'bez', 'titel'])),
            objektStrasse: Value(a['objektStrasse']?.toString() ??
                a['adresse']?.toString()),
            objektPlz:
                Value(a['objektPlz']?.toString() ?? a['plz']?.toString()),
            objektOrt:
                Value(a['objektOrt']?.toString() ?? a['ort']?.toString()),
            objektart: Value(a['objektart']?.toString()),
            baujahr: Value(a['baujahr']?.toString()),
            sachgebiet: Value(a['sachgebiet']?.toString()),
            kategorie: Value(a['kategorie']?.toString()),
            honorargruppe: Value(a['honorargruppe']?.toString()),
            gericht: Value(a['gericht']?.toString()),
            gerichtsort: Value(a['gerichtsort']?.toString()),
            gerichtsAktenzeichen: Value(a['gerichtsaz']?.toString() ??
                a['gerichtsAktenzeichen']?.toString()),
            verfahrensart: Value(a['verfahrensart']?.toString()),
            anzahlAusfertigungen:
                Value((a['anzahlAusfertigungen'] as num?)?.toInt()),
            aktenSeitenVon: Value((a['aktenSeitenVon'] as num?)?.toInt()),
            aktenSeitenBis: Value((a['aktenSeitenBis'] as num?)?.toInt()),
            beweisbeschluss1: Value(_parseDate(a['beweisbeschluss1'])),
            beweisbeschluss2: Value(_parseDate(a['beweisbeschluss2'])),
            beweisbeschluss3: Value(_parseDate(a['beweisbeschluss3'])),
            akteneingangAm: Value(_parseDate(a['akteneingang'])),
            richter: Value(a['richter']?.toString() ??
                a['richterName']?.toString()),
            richterAnrede: Value(a['richterAnrede']?.toString()),
            richterBriefanrede:
                Value(a['richterBriefanrede']?.toString()),
            eingangAm: Value(_parseDate(a['eingangsdatum']) ??
                _parseDate(a['eingangAm'])),
            auftragAm: Value(_parseDate(a['auftragsdatum']) ??
                _parseDate(a['auftragAm'])),
            ortsterminAm: Value(_parseDate(a['ortstermin']) ??
                _parseDate(a['ortsterminAm'])),
            fristAm: Value(_parseDate(a['frist']) ??
                _parseDate(a['fristAm'])),
            abschlussAm: Value(_parseDate(a['abschlussdatum']) ??
                _parseDate(a['abschlussAm'])),
            stundensatz: Value(_asDouble(a['stundensatz'])),
            kostenLimit: Value(_asDouble(a['kostenlimit'])),
            kostenvorschuss: Value(_asDouble(a['kostenvorschuss'])),
            aufwandSchaetzung: Value(_asDouble(a['aufwandSchaetzung'])),
            beteiligteJson: Value(_asJson(a['beteiligte'])),
            notiz:
                Value(a['notizen']?.toString() ?? a['notiz']?.toString()),
          ));
      map[(a['id'] as num).toInt()] = id;
    }
    r.auftraege = list.length;
    return map;
  }

  Future<void> _seedStunden(
    List<Map<String, dynamic>> list,
    Map<int, int> auftragMap,
    DemoSeedReport r,
  ) async {
    for (final s in list) {
      final dauer = _asDouble(s['dauer']) ?? 0;
      final minuten = (dauer * 60).round();
      await _db.into(_db.stunden).insert(StundenCompanion.insert(
            auftragId: Value(_mapId(s['auftragId'], auftragMap)),
            datum: Value(_parseDate(s['datum']) ?? DateTime.now()),
            minuten: Value(minuten),
            satz: Value(_asDouble(s['stundensatz'])),
            taetigkeit: Value(s['taetigkeit']?.toString()),
            notiz: Value(s['bemerkung']?.toString() ?? s['notiz']?.toString()),
          ));
    }
    r.stunden = list.length;
  }

  Future<void> _seedRechnungen(
    List<Map<String, dynamic>> list,
    Map<int, int> kundenMap,
    Map<int, int> auftragMap,
    DemoSeedReport r,
  ) async {
    for (final re in list) {
      final netto = _asDouble(re['netto']) ?? 0;
      final ust = _asDouble(re['ust']) ?? (netto * 0.19);
      final brutto = _asDouble(re['brutto']) ?? (netto + ust);
      await _db.into(_db.rechnungen).insert(RechnungenCompanion.insert(
            rechnungsnummer: Value(re['nummer']?.toString() ??
                re['rechnungsnummer']?.toString()),
            typ: Value(re['typ']?.toString() ?? 'privat'),
            bezugRechnung: Value(re['bezugRechnung']?.toString()),
            kundeId: Value(_mapId(re['kundeId'], kundenMap)),
            auftragId: Value(_mapId(re['auftragId'], auftragMap)),
            rechnungsdatum: Value(_parseDate(re['datum']) ??
                _parseDate(re['rechnungsdatum'])),
            leistungsdatum: Value(_parseDate(re['leistungsdatum'])),
            leistungszeitraum:
                Value(re['leistungsdatum'] is String &&
                        _parseDate(re['leistungsdatum']) == null
                    ? re['leistungsdatum'] as String
                    : null),
            faelligAm: Value(_parseDate(re['zahlungsziel']) ??
                _parseDate(re['faelligAm'])),
            bezahltAm: Value(_parseDate(re['bezahltAm'])),
            zahlungszielTage: Value(
                (re['zahlungszielTage'] as num?)?.toInt() ?? 14),
            kleinunternehmerHinweis:
                Value(re['kleinunternehmerHinweis'] == true),
            status: Value(_mapRechnungStatus(re)),
            ustSatz: Value(
                _asDouble(re['mwstSatz']) ?? _asDouble(re['ustSatz']) ?? 19),
            netto: Value(netto),
            ustBetrag: Value(ust),
            brutto: Value(brutto),
            bezahlt: Value(_asDouble(re['bezahlt']) ?? 0),
            positionenJson: Value(_asJson(re['positionen'])),
            kopftext: Value(re['kopftext']?.toString()),
            fusstext: Value(re['fusstext']?.toString() ??
                re['schlusstext']?.toString()),
            notiz: Value(re['notiz']?.toString()),
          ));
    }
    r.rechnungen = list.length;
  }

  Future<void> _seedGutachten(
    List<Map<String, dynamic>> list,
    Map<int, int> auftragMap,
    DemoSeedReport r,
  ) async {
    for (final g in list) {
      final abschnitte = g['abschnitte'] is Map
          ? g['abschnitte'] as Map<String, dynamic>
          : <String, dynamic>{};
      await _db.into(_db.gutachten).insert(GutachtenCompanion.insert(
            auftragId: Value(_mapId(g['auftragId'], auftragMap)),
            titel: Value(g['titel']?.toString() ?? g['nummer']?.toString()),
            status: Value(g['status']?.toString() ?? 'entwurf'),
            ortsterminAm: Value(_parseDate(g['ortsterminAm'])),
            abgabeAm: Value(_parseDate(g['abgabeAm'])),
            abschnitteJson: Value(jsonEncode(
                abschnitte.map((k, v) => MapEntry(k, v?.toString() ?? '')))),
          ));
    }
    r.gutachten = list.length;
  }

  Future<void> _seedFotos(
    List<Map<String, dynamic>> list,
    Map<int, int> auftragMap,
    DemoSeedReport r,
  ) async {
    // Demo-Fotos werden **immer lokal** abgelegt — ein Cloud-Upload führt
    // regelmäßig zu CORS-Problemen beim späteren Laden im Browser.
    // Echte Uploads des Users laufen weiter über den Storage-Dienst.
    for (var i = 0; i < list.length; i++) {
      final f = list[i];
      final dataUrl = f['dataUrl']?.toString();
      Uint8List? bytes;
      String? mime;
      if (dataUrl != null && dataUrl.startsWith('data:')) {
        final commaIdx = dataUrl.indexOf(',');
        if (commaIdx > 0) {
          final meta = dataUrl.substring(5, commaIdx);
          mime = meta.split(';').first;
          try {
            bytes = base64Decode(dataUrl.substring(commaIdx + 1));
          } catch (_) {
            bytes = null;
          }
        }
      }

      await _db.into(_db.fotos).insert(FotosCompanion.insert(
            auftragId: Value(_mapId(f['auftragId'], auftragMap)),
            titel: Value(f['raum']?.toString() ?? f['titel']?.toString()),
            beschreibung: Value(f['beschreibung']?.toString()),
            aufnahmeAm: Value(_parseDate(f['aufnahmedatum'])),
            reihenfolge: Value((f['nummer'] as num?)?.toInt() ?? 0),
            mimeType: Value(mime),
            daten: Value(bytes),
            extras: Value(jsonEncode({'dataUrl': dataUrl})),
          ));
    }
    r.fotos = list.length;
    r.fotosCloudUploaded = 0;
  }

  Future<void> _seedAnschreiben(
    List<Map<String, dynamic>> list,
    Map<int, int> kundenMap,
    Map<int, int> auftragMap,
    DemoSeedReport r,
  ) async {
    for (final a in list) {
      final text = a['text']?.toString() ?? a['inhalt']?.toString() ?? '';
      await _db.into(_db.anschreiben).insert(AnschreibenCompanion.insert(
            auftragId: Value(_mapId(a['auftragId'], auftragMap)),
            kundeId: Value(_mapId(a['kundeId'], kundenMap)),
            datum: Value(_parseDate(a['datum']) ?? DateTime.now()),
            betreff: Value(a['betreff']?.toString()),
            anrede: Value(a['anrede']?.toString()),
            gruss: Value(a['gruss']?.toString()),
            briefText: Value(text.isEmpty ? null : text),
            inhaltJson:
                Value(jsonEncode([{'insert': '$text\n'}])),
            status: Value(a['status']?.toString() ?? 'entwurf'),
          ));
    }
    r.anschreiben = list.length;
  }

  Future<void> _seedKalkulationen(
    List<Map<String, dynamic>> list,
    Map<int, int> auftragMap,
    DemoSeedReport r,
  ) async {
    for (final k in list) {
      double summe = 0;
      final positionen = k['positionen'];
      if (positionen is List) {
        for (final p in positionen) {
          final m = (p as Map)['menge'];
          final e = p['einzelpreis'];
          final mn = (m is num) ? m.toDouble() : 0.0;
          final en = (e is num) ? e.toDouble() : 0.0;
          summe += mn * en;
        }
      }
      await _db.into(_db.kalkulationen).insert(KalkulationenCompanion.insert(
            auftragId: Value(_mapId(k['auftragId'], auftragMap)),
            titel: Value(k['titel']?.toString()),
            summe: Value(summe),
            positionenJson: Value(_asJson(k['positionen'])),
          ));
    }
    r.kalkulationen = list.length;
  }

  Future<void> _seedAuslagen(
    List<Map<String, dynamic>> list,
    Map<int, int> auftragMap,
    DemoSeedReport r,
  ) async {
    for (final a in list) {
      final menge = _asDouble(a['menge']) ?? 1;
      final ep = _asDouble(a['einzelpreis']) ?? _asDouble(a['preis']) ?? 0;
      final summe = _asDouble(a['summe']) ?? (menge * ep);
      await _db.into(_db.auslagen).insert(AuslagenCompanion.insert(
            auftragId: Value(_mapId(a['auftragId'], auftragMap)),
            datum: Value(_parseDate(a['datum']) ?? DateTime.now()),
            art: Value(a['art']?.toString()),
            kategorie: Value(a['kategorie']?.toString() ??
                a['art']?.toString()),
            beschreibung: Value(a['beschreibung']?.toString() ??
                a['bezeichnung']?.toString()),
            menge: Value(menge),
            einheit: Value(a['einheit']?.toString()),
            einzelpreis: Value(ep),
            summe: Value(summe),
            notiz: Value(a['bemerkung']?.toString() ??
                a['notiz']?.toString()),
          ));
    }
    r.auslagen = list.length;
  }

  Future<void> _seedRueckfragen(
    List<Map<String, dynamic>> list,
    Map<int, int> auftragMap,
    DemoSeedReport r,
  ) async {
    for (final f in list) {
      await _db.into(_db.rueckfragen).insert(RueckfragenCompanion.insert(
            auftragId: Value(_mapId(f['auftragId'], auftragMap)),
            datum: Value(_parseDate(f['datum']) ?? DateTime.now()),
            empfaenger: Value(f['empfaenger']?.toString()),
            betreff: Value(f['betreff']?.toString()),
            frage: Value(f['frage']?.toString() ?? f['text']?.toString()),
            antwort: Value(f['antwort']?.toString()),
            status: Value(f['status']?.toString() ?? 'offen'),
            erledigtAm: Value(_parseDate(f['erledigtAm'])),
          ));
    }
    r.rueckfragen = list.length;
  }

  Future<void> _seedArtikel(
      List<Map<String, dynamic>> list, DemoSeedReport r) async {
    for (final a in list) {
      await _db.into(_db.artikel).insert(ArtikelCompanion.insert(
            nummer: Value(a['nr']?.toString() ?? a['nummer']?.toString()),
            bezeichnung: a['kurztext']?.toString() ??
                a['bezeichnung']?.toString() ??
                '(ohne)',
            beschreibung: Value(a['langtext']?.toString() ??
                a['beschreibung']?.toString()),
            kategorie: Value(a['kategorie']?.toString() ??
                a['gewerk']?.toString()),
            einheit: Value(a['einheit']?.toString()),
            einzelpreis: Value(_asDouble(a['einzelpreis']) ?? 0),
            aufschlag: Value(_asDouble(a['aufschlag']) ?? 0),
            standardMenge: Value(_asDouble(a['standardMenge']) ?? 1),
            tags: Value(a['tags']?.toString()),
            kalkulationJson: Value(_asJson(a['unterpositionen']) ??
                _asJson(a['kalkulation'])),
            ustSatz: Value(_asDouble(a['ustsatz']) ??
                _asDouble(a['mwstSatz']) ??
                19),
          ));
    }
    r.artikel = list.length;
  }

  Future<void> _seedAngebote(
    List<Map<String, dynamic>> list,
    Map<int, int> kundenMap,
    DemoSeedReport r,
  ) async {
    for (final a in list) {
      final netto = _asDouble(a['netto']) ?? 0;
      final ust = _asDouble(a['ust']) ?? (netto * 0.19);
      final brutto = _asDouble(a['brutto']) ?? (netto + ust);
      await _db.into(_db.angebote).insert(AngeboteCompanion.insert(
            angebotsnummer: Value(a['nummer']?.toString() ??
                a['angebotsnummer']?.toString()),
            kundeId: Value(_mapId(a['kundeId'], kundenMap)),
            betreff: Value(a['betreff']?.toString()),
            anfrage: Value(a['anfrage']?.toString()),
            objektStrasse: Value(a['objektStrasse']?.toString()),
            objektPlz: Value(a['objektPlz']?.toString()),
            objektOrt: Value(a['objektOrt']?.toString()),
            bedingungen: Value(a['bedingungen']?.toString()),
            notiz: Value(a['notiz']?.toString()),
            datum: Value(_parseDate(a['datum']) ?? DateTime.now()),
            gueltigBis: Value(_parseDate(a['gueltigBis'])),
            status: Value(a['status']?.toString() ?? 'entwurf'),
            ustSatz: Value(
                _asDouble(a['mwstSatz']) ?? _asDouble(a['ustSatz']) ?? 19),
            netto: Value(netto),
            ustBetrag: Value(ust),
            brutto: Value(brutto),
            positionenJson: Value(_asJson(a['positionen'])),
          ));
    }
    r.angebote = list.length;
  }

  Future<void> _seedGeraete(
      List<Map<String, dynamic>> list, DemoSeedReport r) async {
    for (final g in list) {
      await _db.into(_db.geraete).insert(GeraeteCompanion.insert(
            inventarNr: Value(g['inventarNr']?.toString()),
            bezeichnung: g['bezeichnung']?.toString() ?? '(ohne)',
            kategorie: Value(g['kategorie']?.toString()),
            hersteller: Value(g['hersteller']?.toString()),
            modell:
                Value(g['modell']?.toString() ?? g['typ']?.toString()),
            seriennummer: Value(g['seriennummer']?.toString()),
            angeschafftAm: Value(_parseDate(g['anschaffungsdatum']) ??
                _parseDate(g['angeschafftAm'])),
            anschaffungspreis: Value(
                _asDouble(g['preis']) ?? _asDouble(g['anschaffungspreis'])),
            status: Value(g['status']?.toString() ?? 'aktiv'),
            eichpflicht:
                Value(g['eichpflicht']?.toString() ?? 'empfohlen'),
            kalibriertAm: Value(_parseDate(g['eichungLetzte']) ??
                _parseDate(g['kalibriert']) ??
                _parseDate(g['kalibriertAm'])),
            naechsteKalibrierung: Value(_parseDate(g['eichungFaellig']) ??
                _parseDate(g['naechsteKalibrierung'])),
            eichungIntervall:
                Value((g['eichungIntervall'] as num?)?.toInt()),
            pruefstelle: Value(g['pruefstelle']?.toString()),
            zertifikatNr: Value(g['zertifikatNr']?.toString()),
            messbereich: Value(g['messbereich']?.toString()),
            genauigkeit: Value(g['genauigkeit']?.toString()),
            norm: Value(g['norm']?.toString()),
            notiz: Value(g['bemerkung']?.toString() ??
                g['notiz']?.toString()),
          ));
    }
    r.geraete = list.length;
  }

  Future<void> _seedNormen(
      List<Map<String, dynamic>> list, DemoSeedReport r) async {
    for (final n in list) {
      await _db.into(_db.normen).insert(NormenCompanion.insert(
            nummer: n['nummer']?.toString() ?? '—',
            titel: Value(n['titel']?.toString()),
            ausgabe: Value(n['ausgabe']?.toString() ??
                n['jahr']?.toString()),
            kategorie: Value(n['kategorie']?.toString() ??
                n['gewerk']?.toString()),
            art: Value(n['art']?.toString()),
            herausgeber: Value(n['herausgeber']?.toString()),
            relevanz: Value(n['relevanz']?.toString()),
            zusammenfassung: Value(n['zusammenfassung']?.toString()),
            zitat: Value(n['zitat']?.toString()),
            beschreibung: Value(n['beschreibung']?.toString() ??
                n['anwendung']?.toString()),
          ));
    }
    r.normen = list.length;
  }

  Future<Map<int, int>> _seedLieferanten(
      List<Map<String, dynamic>> list, DemoSeedReport r) async {
    final map = <int, int>{};
    for (final l in list) {
      final id = await _db.into(_db.lieferanten).insert(LieferantenCompanion.insert(
            firma: l['firma']?.toString() ?? l['lief']?.toString() ?? '(ohne)',
            ansprechpartner: Value(l['ansprechpartner']?.toString()),
            strasse: Value(l['strasse']?.toString()),
            plz: Value(l['plz']?.toString()),
            ort: Value(l['ort']?.toString()),
            telefon: Value(l['telefon']?.toString()),
            email: Value(l['email']?.toString()),
            website: Value(l['website']?.toString()),
            kategorie: Value(l['kategorie']?.toString() ??
                l['kat']?.toString()),
            iban: Value(l['iban']?.toString()),
            bic: Value(l['bic']?.toString()),
            notiz: Value(l['notiz']?.toString()),
          ));
      map[(l['id'] as num).toInt()] = id;
    }
    r.lieferanten = list.length;
    return map;
  }

  Future<void> _seedEingangsrechnungen(
    List<Map<String, dynamic>> list,
    Map<int, int> auftragMap,
    Map<int, int> lieferantenMap,
    DemoSeedReport r,
  ) async {
    for (final e in list) {
      final netto = _asDouble(e['netto']) ?? 0;
      final ustSatz = _asDouble(e['ust']) ?? _asDouble(e['ustsatz']) ?? 19;
      final ustBetrag = _asDouble(e['ustBetrag']) ?? (netto * ustSatz / 100);
      final brutto = _asDouble(e['brutto']) ?? (netto + ustBetrag);
      await _db
          .into(_db.eingangsrechnungen)
          .insert(EingangsrechnungenCompanion.insert(
            rechnungsnummer: Value(e['belegNr']?.toString() ??
                e['rnr']?.toString()),
            auftragId: Value(_mapId(e['auftragId'], auftragMap)),
            lieferantId: Value(_mapId(e['lieferantId'], lieferantenMap)),
            rechnungsdatum: Value(_parseDate(e['rechnungsdatum'])),
            faelligAm: Value(_parseDate(e['zahlungsziel'])),
            bezahltAm: Value(_parseDate(e['bezahltAm'])),
            status: Value(_mapErStatus(e)),
            kategorie: Value(e['kategorie']?.toString() ??
                e['kat']?.toString()),
            beschreibung: Value(e['beschreibung']?.toString() ??
                e['zweck']?.toString()),
            netto: Value(netto),
            ustSatz: Value(ustSatz),
            ustBetrag: Value(ustBetrag),
            brutto: Value(brutto),
            notiz: Value(e['notiz']?.toString()),
          ));
    }
    r.eingangsrechnungen = list.length;
  }

  Future<void> _seedErlaeuterungen(
    List<Map<String, dynamic>> list,
    Map<int, int> auftragMap,
    DemoSeedReport r,
  ) async {
    for (final e in list) {
      await _db.into(_db.erlaeuterungen).insert(ErlaeuterungenCompanion.insert(
            auftragId: Value(_mapId(e['auftragId'], auftragMap)),
            terminAm: Value(_parseDate(e['termin']) ??
                _parseDate(e['terminAm'])),
            ort: Value(e['ort']?.toString()),
            gericht: Value(e['gericht']?.toString()),
            saal: Value(e['saal']?.toString()),
            richter: Value(e['richter']?.toString()),
            status: Value(e['status']?.toString() ?? 'geplant'),
            vorbereitung: Value(e['vorbereitung']?.toString()),
            notiz: Value(e['notiz']?.toString()),
          ));
    }
    r.erlaeuterungen = list.length;
  }

  Future<void> _seedTextbausteine(
      List<Map<String, dynamic>> list, DemoSeedReport r) async {
    for (final t in list) {
      await _db.into(_db.textbausteine).insert(TextbausteineCompanion.insert(
            titel: t['titel']?.toString() ?? '(ohne)',
            kategorie: Value(t['kategorie']?.toString() ??
                t['bereich']?.toString()),
            sachgebiet: Value(t['sachgebiet']?.toString()),
            tags: Value(t['tags']?.toString()),
            inhalt: Value(t['text']?.toString() ??
                t['inhalt']?.toString()),
            favorit: Value(t['favorit'] == true),
          ));
    }
    r.textbausteine = list.length;
  }

  Future<void> _seedEinstellungen(
      List<Map<String, dynamic>> list, DemoSeedReport r) async {
    for (final e in list) {
      final wert = e['wert'];
      await _db.into(_db.einstellungen).insert(EinstellungenCompanion.insert(
            key: e['key']?.toString() ?? 'unknown',
            wert: Value(wert is String ? wert : jsonEncode(wert)),
          ));
    }
    r.einstellungen = list.length;
  }

  // ---------------------- Helpers ----------------------

  List<Map<String, dynamic>> _asList(dynamic v) {
    if (v is List) {
      return v.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  int? _mapId(dynamic raw, Map<int, int> map) {
    if (raw is num) return map[raw.toInt()];
    return null;
  }

  String? _pickString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) {
      final d = double.tryParse(v.replaceAll(',', '.'));
      return d;
    }
    return null;
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    if (s.isEmpty) return null;
    // ISO 8601 (YYYY-MM-DD oder YYYY-MM-DDTHH:mm[:ss])
    return DateTime.tryParse(s);
  }

  String? _asJson(dynamic v) => v == null ? null : jsonEncode(v);

  String _mapAuftragStatus(String? s) {
    return switch (s) {
      'laufend' || 'in_arbeit' => 'in_arbeit',
      'wartet' => 'wartet',
      'abgeschlossen' => 'abgeschlossen',
      'abgerechnet' => 'abgerechnet',
      'storniert' => 'storniert',
      _ => 'offen',
    };
  }

  String _mapRechnungStatus(Map<String, dynamic> re) {
    if (re['bezahltAm'] != null) return 'bezahlt';
    final s = re['bezahlStatus']?.toString() ?? re['status']?.toString();
    return switch (s) {
      'bezahlt' => 'bezahlt',
      'teilbezahlt' => 'teilbezahlt',
      'storniert' => 'storniert',
      'ueberfaellig' || 'faellig' => 'ueberfaellig',
      _ => 'offen',
    };
  }

  String _mapErStatus(Map<String, dynamic> er) {
    final s = er['bezahlStatus']?.toString() ?? er['status']?.toString();
    return switch (s) {
      'bezahlt' => 'bezahlt',
      'teilbezahlt' => 'teilbezahlt',
      'storniert' => 'storniert',
      _ => 'offen',
    };
  }
}

class DemoSeedReport {
  int kunden = 0;
  int auftraege = 0;
  int stunden = 0;
  int rechnungen = 0;
  int gutachten = 0;
  int fotos = 0;
  int fotosCloudUploaded = 0;
  int anschreiben = 0;
  int kalkulationen = 0;
  int auslagen = 0;
  int rueckfragen = 0;
  int artikel = 0;
  int angebote = 0;
  int geraete = 0;
  int normen = 0;
  int lieferanten = 0;
  int eingangsrechnungen = 0;
  int erlaeuterungen = 0;
  int textbausteine = 0;
  int dokumente = 0;
  int einstellungen = 0;

  int get total =>
      kunden +
      auftraege +
      stunden +
      rechnungen +
      gutachten +
      fotos +
      anschreiben +
      kalkulationen +
      auslagen +
      rueckfragen +
      artikel +
      angebote +
      geraete +
      normen +
      lieferanten +
      eingangsrechnungen +
      erlaeuterungen +
      textbausteine +
      dokumente +
      einstellungen;

  @override
  String toString() => 'Demo-Seed: $total Datensätze\n'
      '  Kunden: $kunden, Aufträge: $auftraege, Stunden: $stunden, '
      'Rechnungen: $rechnungen, Gutachten: $gutachten, Fotos: $fotos,\n'
      '  Anschreiben: $anschreiben, Kalkulationen: $kalkulationen, '
      'Auslagen: $auslagen, Rückfragen: $rueckfragen,\n'
      '  Artikel: $artikel, Angebote: $angebote, Geräte: $geraete, '
      'Normen: $normen, Lieferanten: $lieferanten,\n'
      '  Eingangsrechnungen: $eingangsrechnungen, '
      'Erläuterungstermine: $erlaeuterungen,\n'
      '  Dokumente: $dokumente, Textbausteine: $textbausteine, '
      'Einstellungen: $einstellungen';
}

final demoSeederProvider = Provider<DemoSeeder>((ref) {
  return DemoSeeder(
    ref.watch(appDatabaseProvider),
    ref.watch(syncServiceProvider),
  );
});
