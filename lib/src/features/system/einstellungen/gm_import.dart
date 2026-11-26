// Datenübernahme aus dem Gutachten-Manager (Waning Software).
//
// Der Gutachten-Manager speichert seine Daten in einer Access-Datenbank
// (GutachterDBV80.mdb). Diese wird zuerst als CSV exportiert – je Tabelle
// eine Datei (z. B. mit `tool/gm_export.sh`, benötigt mdbtools). Hier
// werden die CSV-Dateien eingelesen und als Akten, Auftraggeber,
// Beteiligte, Zeiten und Auslagen angelegt. Rechnungen werden nicht
// übernommen (Nummernkreise und Belege bleiben im Altsystem).

import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:drift/drift.dart' show Value;

import '../../../core/jveg/jveg_tabelle.dart';
import '../../../data/database/app_database.dart';
import '../../akten/akte/beteiligte_tab.dart';
import '../../akten/auftraege/auftrag_gm_extras.dart';

class GmImportBericht {
  int akten = 0;
  int uebersprungen = 0;
  int kunden = 0;
  int beteiligte = 0;
  int stunden = 0;
  int auslagen = 0;
  final List<String> hinweise = [];

  @override
  String toString() => [
        '$akten Akten übernommen',
        if (uebersprungen > 0) '$uebersprungen bereits vorhanden (übersprungen)',
        '$kunden Auftraggeber angelegt',
        '$beteiligte Beteiligte',
        '$stunden Zeiteinträge',
        '$auslagen Auslagen',
      ].join(' · ');
}

/// Liest eine GM-CSV-Datei (mdb-export-Format, Kopfzeile, `,`- oder `;`-getrennt).
List<Map<String, String>> _csv(Uint8List bytes) {
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1);
  text = text.replaceAll('\r\n', '\n');
  // mdb-export trennt standardmäßig mit Komma; Excel-Exporte oft mit Semikolon.
  final ersteZeile = text.split('\n').first;
  final trenner =
      ';'.allMatches(ersteZeile).length > ','.allMatches(ersteZeile).length ? ';' : ',';
  final rows = CsvToListConverter(
          eol: '\n', fieldDelimiter: trenner, shouldParseNumbers: false)
      .convert(text);
  if (rows.isEmpty) return const [];
  final kopf = rows.first.map((e) => e.toString().trim()).toList();
  return [
    for (final r in rows.skip(1))
      if (r.isNotEmpty && !(r.length == 1 && r.first.toString().trim().isEmpty))
        {for (var i = 0; i < kopf.length && i < r.length; i++) kopf[i]: r[i].toString().trim()},
  ];
}

DateTime? _datum(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final t = s.trim();
  final iso = DateTime.tryParse(t.replaceFirst(' ', 'T'));
  if (iso != null) return iso.year < 1900 ? null : iso;
  // US-Format aus mdb-export: 06/12/26 09:30:00
  final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})(?:\s+(\d{1,2}):(\d{2}))?').firstMatch(t);
  if (m != null) {
    var y = int.parse(m.group(3)!);
    if (y < 100) y += 2000;
    return DateTime(y, int.parse(m.group(1)!), int.parse(m.group(2)!),
        int.tryParse(m.group(4) ?? '0') ?? 0, int.tryParse(m.group(5) ?? '0') ?? 0);
  }
  final d = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})').firstMatch(t);
  if (d != null) {
    return DateTime(int.parse(d.group(3)!), int.parse(d.group(2)!), int.parse(d.group(1)!));
  }
  return null;
}

double? _zahl(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final t = s.trim();
  return double.tryParse(t.contains(',') ? t.replaceAll('.', '').replaceAll(',', '.') : t);
}

String? _leer(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

/// Führt den Import aus. [dateien]: Dateiname → Inhalt (CSV je GM-Tabelle).
Future<GmImportBericht> gmImportAusfuehren(
    AppDatabase db, Map<String, Uint8List> dateien) async {
  final bericht = GmImportBericht();
  List<Map<String, String>> tabelle(String name) {
    for (final e in dateien.entries) {
      final n = e.key.split('/').last.toLowerCase();
      if (n == '${name.toLowerCase()}.csv') return _csv(e.value);
    }
    return const [];
  }

  final akten = tabelle('GmDbAktenDaten');
  if (akten.isEmpty) {
    bericht.hinweise.add('GmDbAktenDaten.csv fehlt oder ist leer – ohne diese Tabelle '
        'kann nichts übernommen werden.');
    return bericht;
  }
  Map<String, Map<String, String>> nachId(String t) =>
      {for (final r in tabelle(t)) (r['GutachtenID'] ?? ''): r};
  final gericht = nachId('GmDbAktenDatenGericht');
  final privat = nachId('GmDbAktenDatenPrivat');
  final vers = nachId('GmDbAktenDatenVersicherung');
  final adressen = <String, List<Map<String, String>>>{};
  for (final r in tabelle('GmDbGutachtenAdressen')) {
    adressen.putIfAbsent(r['GutachtenID'] ?? '', () => []).add(r);
  }
  final zeiten = <String, List<Map<String, String>>>{};
  for (final r in tabelle('GmDbZeitenAppointments')) {
    zeiten.putIfAbsent(r['GutachtenID'] ?? '', () => []).add(r);
  }
  final auslagen = <String, List<Map<String, String>>>{};
  for (final r in tabelle('GmDbAuslagen')) {
    auslagen.putIfAbsent(r['GutachtenID'] ?? '', () => []).add(r);
  }

  final vorhanden = (await db.select(db.auftraege).get())
      .map((a) => (a.aktenzeichen ?? '').trim())
      .toSet();
  final kundenCache = <String, int>{};

  Future<int> kundeAnlegen({
    required String typ,
    String? firma,
    String? anrede,
    String? titel,
    String? vorname,
    String? nachname,
    String? strasse,
    String? plz,
    String? ort,
    String? telefon,
    String? fax,
    String? email,
  }) async {
    final key = '$typ|${firma ?? ''}|${nachname ?? ''}|${plz ?? ''}'.toLowerCase();
    if (kundenCache.containsKey(key)) return kundenCache[key]!;
    final id = await db.into(db.kunden).insert(KundenCompanion.insert(
          typ: Value(typ),
          firma: Value(_leer(firma)),
          anrede: Value(_leer(anrede)),
          titel: Value(_leer(titel)),
          vorname: Value(_leer(vorname)),
          nachname: Value(_leer(nachname)),
          strasse: Value(_leer(strasse)),
          plz: Value(_leer(plz)),
          ort: Value(_leer(ort)),
          telefon: Value(_leer(telefon)),
          fax: Value(_leer(fax)),
          email: Value(_leer(email)),
          notiz: const Value('Übernommen aus Gutachten-Manager'),
        ));
    kundenCache[key] = id;
    bericht.kunden++;
    return id;
  }

  for (final a in akten) {
    final gid = a['GutachtenID'] ?? '';
    if (gid.isEmpty) continue;
    final az = gid;
    if (vorhanden.contains(az)) {
      bericht.uebersprungen++;
      continue;
    }
    final typNr = int.tryParse(a['GutachtenTyp'] ?? '') ?? 2;
    final art = switch (typNr) { 1 => 'gericht', 3 => 'versicherung', _ => 'privat' };
    final g = gericht[gid];
    final p = privat[gid];
    final v = vers[gid];
    final adr = adressen[gid] ?? const [];

    // Auftraggeber
    int? kundeId;
    if (art == 'gericht' && g != null && (g['GerichtAnschrift1'] ?? '').isNotEmpty) {
      kundeId = await kundeAnlegen(
        typ: 'gericht',
        firma: g['GerichtAnschrift1'],
        strasse: g['GerichtStrasse'],
        plz: null,
        ort: g['GerichtOrt'],
        email: g['EMail1'],
      );
    } else {
      final ag = adr.firstWhere((x) => x['IstDieRechnungsAdresse'] == '1',
          orElse: () => adr.isNotEmpty ? adr.first : const {});
      if (ag.isNotEmpty) {
        final istFirma = (ag['Vorname'] ?? '').isEmpty && (ag['An'] ?? '').toLowerCase().contains('firma');
        kundeId = await kundeAnlegen(
          typ: art == 'versicherung' ? 'versicherung' : (istFirma ? 'firma' : 'privat'),
          firma: istFirma ? ag['Name'] : null,
          anrede: istFirma ? null : ag['An'],
          titel: ag['Titel'],
          vorname: istFirma ? null : ag['Vorname'],
          nachname: istFirma ? null : ag['Name'],
          strasse: ag['Strasse'],
          plz: ag['Plz'],
          ort: ag['Stadt'],
          telefon: ag['Telefon1'],
          fax: ag['Fax'],
          email: ag['EMail'],
        );
      }
    }

    // Beteiligte
    final beteiligte = <Beteiligter>[
      for (final x in adr)
        Beteiligter(
          rolle: (x['Status'] ?? '').isEmpty ? 'Beteiligter' : x['Status']!,
          anrede: x['An'] ?? '',
          name: [x['Titel'], x['Vorname'], x['Name']]
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .join(' '),
          briefanrede: x['Anrede'] ?? '',
          ihrZeichen: x['IhrZeichen'] ?? '',
          strasse: x['Strasse'] ?? '',
          plz: x['Plz'] ?? '',
          ort: x['Stadt'] ?? '',
          telefon: x['Telefon1'] ?? '',
          email: x['EMail'] ?? '',
          zumOrtsterminLaden: (x['OrtsterminEinladungErstellen'] ?? '1') != '0',
        ),
    ];
    bericht.beteiligte += beteiligte.length;

    // Versicherungs-Extras
    String? extras;
    if (v != null) {
      extras = AuftragGmExtras(
        schadensnummer: v['SchadensNr'] ?? '',
        versicherungsscheinNr: v['VersicherungsNummer'] ?? '',
        schadenstag: _datum(v['Schadenstag']),
        schadensursache: v['VersicherungsUmfang'] ?? v['VSUmfang'] ?? '',
      ).mergeIntoExtras(null);
    }
    final sgNr = (g?['SachgebietsNr'] ?? '').trim();
    final hg = sgNr.isNotEmpty && jvegSachgebietFuer(sgNr) != null ? 'SG $sgNr' : null;
    final abgeschlossen = (a['abgeschlossen'] ?? '').toLowerCase();

    final auftragId = await db.into(db.auftraege).insert(AuftraegeCompanion.insert(
          aktenzeichen: Value(az),
          art: Value(art),
          status: Value(abgeschlossen == 'true' || abgeschlossen == '1' || abgeschlossen == 'ja'
              ? 'abgeschlossen'
              : 'offen'),
          kundeId: Value(kundeId),
          azExtern: Value(_leer(p?['Kundenzeichen']) ?? _leer(a['Aktenzeichen'])),
          betreff: Value(_leer(a['Sache']) ?? _leer(p?['GutachtenThema'])),
          bezeichnung: Value(_leer(a['Ordnerbezeichnung'])),
          objektStrasse: Value(_leer(a['Besichtigungsobjekt']) ?? _leer(v?['AdresseSchadensObjekt'])),
          kategorie: Value(_leer(a['Kategorie'])),
          sachgebiet: Value(_leer(g?['Sachgebiet'])),
          honorargruppe: Value(hg),
          auftragAm: Value(_datum(g?['Gutachterauftrag']) ?? _datum(p?['GutachterAuftragDatum']) ?? _datum(v?['AuftragVom']) ?? _datum(a['Datum'])),
          ortsterminAm: Value(_datum(a['NaechsterOrtstermin'])),
          fristAm: Value(_datum(a['Fertigstellung'])),
          stundensatz: Value(_zahl(g?['HonorarKosten']) ?? _zahl(p?['Stundensatz']) ?? _zahl(v?['KostenStunde']) ?? _zahl(a['SV_Stundensatz'])),
          kostenvorschuss: Value(_zahl(p?['ZuZahlenderVorschuss']) ?? _zahl(g?['KostenVorschussBeantragenEuro'])),
          gerichtsAktenzeichen: Value(_leer(g?['GerichtAktenzeichen']) ?? (art == 'gericht' ? _leer(a['Aktenzeichen']) : null)),
          gericht: Value(_leer(g?['GerichtAnschrift1'])),
          gerichtsort: Value(_leer(g?['GerichtOrt'])),
          verfahrensart: Value(_leer(g?['VerfahrensTyp'])),
          akteneingangAm: Value(_datum(g?['Akteneingang'])),
          beweisbeschluss1: Value(_datum(g?['Beweisbeschluss'])),
          richter: Value(_leer(g?['NameRichter'])),
          richterAnrede: Value(_leer(g?['AnredeRichter'])),
          richterBriefanrede: Value(_leer(g?['BriefAnredeRichter'])),
          beteiligteJson: Value(beteiligte.isEmpty ? null : encodeBeteiligte(beteiligte)),
          notiz: Value([
            _leer(a['BemerkungAkte']),
            _leer(p?['ZweckDesGutachtens']) == null ? null : 'Zweck: ${p!['ZweckDesGutachtens']}',
            'Übernommen aus Gutachten-Manager (GutachtenID $gid)',
          ].whereType<String>().join('\n')),
          extras: Value(extras),
        ));
    bericht.akten++;

    for (final z in zeiten[gid] ?? const <Map<String, String>>[]) {
      final von = _datum(z['Von']);
      final bis = _datum(z['Bis']);
      var minuten = ((_zahl(z['TotalStunden']) ?? 0) * 60).round();
      if (minuten == 0 && von != null && bis != null) minuten = bis.difference(von).inMinutes;
      if (minuten <= 0) continue;
      await db.into(db.stunden).insert(StundenCompanion.insert(
            auftragId: Value(auftragId),
            datum: Value(_datum(z['Datum']) ?? von ?? DateTime.now()),
            beginn: Value(von),
            ende: Value(bis),
            minuten: Value(minuten),
            satz: Value(_zahl(z['Stundensatz'])),
            taetigkeit: Value(_leer(z['Taetigkeit']) ?? _leer(z['Subject'])),
            notiz: Value(_leer(z['Kommentar'])),
            abgerechnet: Value((z['RechnungsNummer'] ?? '').isNotEmpty),
          ));
      bericht.stunden++;
    }
    for (final x in auslagen[gid] ?? const <Map<String, String>>[]) {
      final menge = _zahl(x['Menge']) ?? 1;
      final preis = _zahl(x['PreisME']) ?? 0;
      await db.into(db.auslagen).insert(AuslagenCompanion.insert(
            auftragId: Value(auftragId),
            datum: Value(_datum(x['Datum']) ?? DateTime.now()),
            art: Value(_leer(x['Kurzbezeichnung'])),
            beschreibung: Value(_leer(x['RechnungsText'])),
            menge: Value(menge),
            einheit: Value(_leer(x['MengenEinheit'])),
            einzelpreis: Value(preis),
            summe: Value(_zahl(x['Kosten']) ?? menge * preis),
            abgerechnet: Value(x['Abgerechnet'] == '1' || (x['RechnungsNr'] ?? '').isNotEmpty),
          ));
      bericht.auslagen++;
    }
  }
  if (bericht.akten == 0 && bericht.uebersprungen == 0) {
    bericht.hinweise.add('Die Tabelle GmDbAktenDaten enthielt keine Akten.');
  }
  return bericht;
}
