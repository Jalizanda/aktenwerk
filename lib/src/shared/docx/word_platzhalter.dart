// Platzhalter-Werte für Word-Vorlagen (Gutachten-Manager-kompatibel).
//
// Kombiniert die Aktenwerk-Platzhalter ({{…}}, $GerichtsAZ …) mit den
// Platzhalternamen der Gutachten-Manager-Vorlagen ($GutachtenNr,
// $Aktenzeichen, $GutName, $Adresse, $Ad1Name, «Name» …), damit vorhandene
// Word-Vorlagen ohne Anpassung weiterverwendet werden können.

import 'package:intl/intl.dart';

import '../../core/jveg/jveg_tabelle.dart';
import '../../data/database/app_database.dart';
import '../../features/akten/akte/beteiligte_tab.dart';
import '../../features/akten/auftraege/auftrag_gm_extras.dart';
import '../../features/akten/auftraege/zusatzfelder.dart';
import '../../features/akten/gerichtssache/beweisfragen.dart';
import '../../features/akten/gutachten/gutachten_repository.dart';
import '../../features/system/einstellungen/einstellungen_repository.dart';
import 'word_vorlagen_engine.dart';

class WordAktenDaten {
  WordAktenDaten({
    required this.resolver,
    required this.personen,
    required this.empfaenger,
    required this.empfaengerNamen,
    required this.raute,
    required this.werte,
  });

  final WordResolver resolver;
  final List<(String, String)> personen;
  final List<WordResolver> empfaenger;
  final List<String> empfaengerNamen;
  final String? Function(String name) raute;

  /// Alle bekannten Platzhalter (für Hilfe/Kontrolle).
  final Map<String, String> werte;
}

String _fmt(DateTime? d) =>
    d == null ? '' : DateFormat('dd.MM.yyyy', 'de').format(d);
String _euro(double? v) => v == null
    ? ''
    : '${NumberFormat('#,##0.00', 'de_DE').format(v)} €';
String _terminLang(DateTime? d, String uhrzeit) {
  if (d == null) return '';
  final tag = DateFormat('EEEE', 'de').format(d);
  var z = uhrzeit.trim();
  if (z.isEmpty && (d.hour != 0 || d.minute != 0)) {
    z = DateFormat('H:mm', 'de').format(d);
  }
  return '$tag, den ${_fmt(d)}${z.isEmpty ? '' : ' um $z Uhr'}';
}

String _ohneKomma(String s) => s.trim().replaceFirst(RegExp(r',\s*$'), '');

/// Baut alle Platzhalter-Werte für eine Akte.
Future<WordAktenDaten> baueWordAktenDaten({
  required AuftraegeData auftrag,
  KundenData? kunde,
  required EinstellungenRepository settings,
  bool auftraggeberAlsEmpfaenger = false,
}) async {
  final ein = <String, String>{};
  for (final k in [
    SettingsKeys.firmaName, SettingsKeys.firmaTitel, SettingsKeys.firmaAnschrift,
    SettingsKeys.firmaTelefon, SettingsKeys.firmaEmail, SettingsKeys.firmaWebsite,
    SettingsKeys.firmaBestellung1, SettingsKeys.firmaBestellung2, SettingsKeys.svSachgebiet,
    SettingsKeys.bankName, SettingsKeys.bankIban, SettingsKeys.bankBic, SettingsKeys.bankInhaber,
    SettingsKeys.steuerUstId, SettingsKeys.steuerNr,
  ]) {
    ein[k] = (await settings.get(k)) ?? '';
  }

  final basis = buildAktenwerkPlatzhalter(auftrag: auftrag, kunde: kunde);
  final gm = AuftragGmExtras.fromAuftragExtras(auftrag.extras);
  final beteiligte = decodeBeteiligte(auftrag.beteiligteJson)
      .where((b) => b.name.trim().isNotEmpty)
      .toList();
  final fragen = decodeBeweisfragen(auftrag.beweisfragenJson);
  final w = <String, String>{};
  void set(String k, String? v) => w[k.toLowerCase()] = v ?? '';

  // --- Sachverständiger ---
  final anschrift = ein[SettingsKeys.firmaAnschrift]!
      .split(RegExp(r'\n|,'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final gutStrasse = anschrift.isNotEmpty ? anschrift.first : '';
  final gutPlzOrt = anschrift.length > 1 ? anschrift[1] : '';
  final plzM = RegExp(r'^(\d{4,5})\s+(.+)$').firstMatch(gutPlzOrt);
  final gutName = [ein[SettingsKeys.firmaTitel], ein[SettingsKeys.firmaName]]
      .where((s) => (s ?? '').trim().isNotEmpty)
      .join(' ');
  set('GutName', gutName);
  set('GutTitel', ein[SettingsKeys.firmaTitel]);
  set('GutVornameName', ein[SettingsKeys.firmaName]);
  set('GutStrasse', gutStrasse);
  set('GutPlz', plzM?.group(1) ?? '');
  set('GutStadt', plzM?.group(2) ?? gutPlzOrt);
  set('GutPlzStadt', gutPlzOrt);
  set('GutTel', ein[SettingsKeys.firmaTelefon]);
  set('GutFax', '');
  set('GutHandy', '');
  set('GutEMail', ein[SettingsKeys.firmaEmail]);
  set('GutWeb', ein[SettingsKeys.firmaWebsite]);
  set('GutZeile1', ein[SettingsKeys.firmaBestellung1]);
  set('GutZeile2', ein[SettingsKeys.firmaBestellung2]);
  set('GutZeile3', ein[SettingsKeys.svSachgebiet]);
  set('GutAbsenderzeile', [gutName, gutStrasse, gutPlzOrt].where((s) => s.isNotEmpty).join(' | '));
  set('IBAN', ein[SettingsKeys.bankIban]);
  set('BIC', ein[SettingsKeys.bankBic]);
  set('Bank', ein[SettingsKeys.bankName]);
  set('UStId', ein[SettingsKeys.steuerUstId]);
  set('SteuerNr', ein[SettingsKeys.steuerNr]);
  set('GutSteuerNrText', (ein[SettingsKeys.steuerUstId] ?? '').isNotEmpty
      ? 'USt-IdNr. ${ein[SettingsKeys.steuerUstId]}'
      : ((ein[SettingsKeys.steuerNr] ?? '').isNotEmpty ? 'Steuernummer ${ein[SettingsKeys.steuerNr]}' : ''));

  // --- Akte ---
  final heute = DateTime.now();
  final sache = buildSacheKurzbezeichnung(auftrag);
  final gerichtsAz = (auftrag.gerichtsAktenzeichen ?? auftrag.azExtern ?? '').trim();
  final objekt = [auftrag.objektStrasse, [auftrag.objektPlz, auftrag.objektOrt].whereType<String>().where((s) => s.isNotEmpty).join(' ')]
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .join(', ');
  final uhrzeit = gm.ortsterminUhrzeitVon.trim();
  set('Datum', _fmt(heute));
  set('Jahr', '${heute.year}');
  set('GutachtenNr', auftrag.aktenzeichen);
  set('Aktenzeichen', gerichtsAz);
  set('Sache', sache);
  set('PrSache', sache);
  set('PrKundZeich', auftrag.azExtern);
  set('IhrZeichen', auftrag.azExtern);
  set('BesichtObj', objekt);
  set('PrBesichObj', objekt);
  set('GutAuf', _fmt(auftrag.auftragAm));
  set('PrAufVon', _fmt(auftrag.auftragAm));
  set('VSAuftragVom', _fmt(auftrag.auftragAm));
  set('AktEin', _fmt(auftrag.akteneingangAm));
  set('BewBesch', _fmt(auftrag.beweisbeschluss1));
  set('OrtTermDat', _fmt(auftrag.ortsterminAm));
  set('VSOrtsterminDatum', _fmt(auftrag.ortsterminAm));
  set('OrtTermZeit', uhrzeit.isEmpty
      ? (auftrag.ortsterminAm == null || (auftrag.ortsterminAm!.hour == 0 && auftrag.ortsterminAm!.minute == 0)
          ? ''
          : '${DateFormat('H:mm', 'de').format(auftrag.ortsterminAm!)} Uhr')
      : '$uhrzeit Uhr');
  set('Ortstermin', _terminLang(auftrag.ortsterminAm, uhrzeit));
  set('OTUrsprungsTermin', _terminLang(gm.ortsterminAltAm, gm.ortsterminAltUhrzeit));
  set('GrundUmladung', gm.ortsterminVerlegtGrund);
  set('GerLang', auftrag.gericht);
  set('GerKurz', (auftrag.gericht ?? '')
      .replaceFirst(RegExp(r'^Amtsgericht'), 'AG')
      .replaceFirst(RegExp(r'^Landgericht'), 'LG')
      .replaceFirst(RegExp(r'^Oberlandesgericht'), 'OLG'));
  set('GerRichterName', auftrag.richter);
  set('AnredeRichter', auftrag.richterAnrede);
  final briefRichter = (auftrag.richterBriefanrede ?? '').trim().isNotEmpty
      ? auftrag.richterBriefanrede!
      : ((auftrag.richter ?? '').trim().isNotEmpty
          ? '${(auftrag.richterAnrede ?? '').toLowerCase().startsWith('frau') ? 'Sehr geehrte Frau' : 'Sehr geehrter Herr'} ${auftrag.richter!.trim()}'
          : 'Sehr geehrte Damen und Herren');
  set('BriefAnredeRichter', _ohneKomma(briefRichter));
  set('VerfahrensType', auftrag.verfahrensart);
  set('GerAkteSeiten', [auftrag.aktenSeitenVon, auftrag.aktenSeitenBis].whereType<int>().join('–'));
  set('GerAnzAus', auftrag.anzahlAusfertigungen?.toString());
  set('GerKosten', _euro(auftrag.kostenvorschuss));
  set('Vorschuss', _euro(auftrag.kostenvorschuss));
  set('GerFertigstellung', _fmt(auftrag.fristAm));
  set('FertigstellenBis', _fmt(auftrag.fristAm));
  set('VSFertigstellung', _fmt(auftrag.fristAm));
  set('Honorar', _euro(auftrag.stundensatz));
  set('PrGutStKost', _euro(auftrag.stundensatz));
  set('VSGetKostenStunde', _euro(auftrag.stundensatz));
  final sg = jvegSachgebietFuer(auftrag.honorargruppe);
  set('Sachgeb', auftrag.sachgebiet ?? sg?.bezeichnung);
  set('SachgebNr', sg?.nr ?? '');
  set('HonGrupp', auftrag.honorargruppe);
  set('Kategorie', auftrag.kategorie);
  set('Bemerkung', auftrag.notiz);
  set('BemerkungAkte', auftrag.notiz);
  set('BemerkungZurAkte', auftrag.notiz);
  set('VSBemerkung', auftrag.notiz);
  set('GutachtenThema', auftrag.betreff);
  set('ZweckDesGutachtens', auftrag.betreff);
  set('ZweckDesGutachten', auftrag.betreff);
  set('GutFragen', fragen.map((f) => '${f.nr}. ${f.frage}').join('\n'));
  set('VSSchadensNr', gm.schadensnummer);
  set('VSVersicherungsNummer', gm.versicherungsscheinNr);
  set('VSSchadenstag', _fmt(gm.schadenstag));
  set('VSSchadensObjekt', [auftrag.objektart, objekt].whereType<String>().where((s) => s.isNotEmpty).join(', '));
  set('VSAdresseSchadensObjekt', objekt);
  set('VSVersicherungsUmfang', gm.schadensursache);
  set('VSSachbearbeiter', kunde?.ansprechpartner);
  set('OTermin', '');

  // --- Auftraggeber / Hauptadresse ---
  String kundeName(KundenData k) => (k.firma ?? '').trim().isNotEmpty
      ? k.firma!.trim()
      : [k.titel, k.vorname, k.nachname].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
  String block(List<String?> zeilen) =>
      zeilen.whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).join('\n');
  if (kunde != null) {
    final istFirma = (kunde.firma ?? '').trim().isNotEmpty;
    final an = (kunde.anrede ?? '').trim() == 'Herr' ? 'Herrn' : (kunde.anrede ?? '');
    set('Adresse', block([
      istFirma ? kunde.firma : an,
      istFirma ? ((kunde.ansprechpartner ?? '').trim().isNotEmpty ? 'z. Hd. ${kunde.ansprechpartner}' : null)
          : [kunde.titel, kunde.vorname, kunde.nachname].whereType<String>().where((s) => s.isNotEmpty).join(' '),
      kunde.strasse,
      [kunde.plz, kunde.ort].whereType<String>().where((s) => s.isNotEmpty).join(' '),
    ]));
    set('Auftraggeber', kundeName(kunde));
    set('AdrAn', an);
    set('AdrTitel', kunde.titel);
    set('AdrVorname', kunde.vorname);
    set('AdrName', istFirma ? kunde.firma : kunde.nachname);
    set('AdrZusatz', istFirma ? kunde.ansprechpartner : '');
    set('AdrStrasse', kunde.strasse);
    set('AdrPlz', kunde.plz);
    set('AdrStadt', kunde.ort);
    set('AdrTelefon1', kunde.telefon);
    set('AdrTelefon2', kunde.mobil);
    set('AdrFax', kunde.fax);
    set('AdrEMail', kunde.email);
    set('AdrWeb', kunde.website);
    set('AdrHandy', kunde.mobil);
    set('AdrIhrZeichen', auftrag.azExtern);
    set('TelAdresse', kunde.telefon);
    final nn = (kunde.nachname ?? '').trim();
    final anrede = kunde.typ == 'gericht'
        ? briefRichter
        : (!istFirma && nn.isNotEmpty && (kunde.anrede ?? '').startsWith('Herr'))
            ? 'Sehr geehrter Herr ${[kunde.titel, nn].whereType<String>().where((s) => s.isNotEmpty).join(' ')}'
            : (!istFirma && nn.isNotEmpty && (kunde.anrede ?? '').startsWith('Frau'))
                ? 'Sehr geehrte Frau ${[kunde.titel, nn].whereType<String>().where((s) => s.isNotEmpty).join(' ')}'
                : 'Sehr geehrte Damen und Herren';
    set('Anrede', _ohneKomma(anrede));
    set('AdrBriefAnrede', _ohneKomma(anrede));
    if (kunde.typ == 'gericht') {
      set('AdGerAnschrift1', kundeName(kunde));
      set('AdGerStrasse', kunde.strasse);
      set('AdGerPlz', kunde.plz);
      set('AdGerStadt', kunde.ort);
      set('AdGerTelefon', kunde.telefon);
      set('AdGerFax', kunde.fax);
      set('AdGerEMail', kunde.email);
      if ((auftrag.gericht ?? '').trim().isEmpty) set('GerLang', kundeName(kunde));
    }
  }
  w.putIfAbsent('adgeranschrift1', () => auftrag.gericht ?? '');

  // --- Beteiligte ---
  String beteiligterBlock(Beteiligter b) => block([
        b.anrede.trim() == 'Herr' ? 'Herrn' : b.anrede,
        b.name,
        b.strasse,
        [b.plz, b.ort].where((s) => s.trim().isNotEmpty).join(' '),
      ]);
  for (var i = 0; i < beteiligte.length; i++) {
    final b = beteiligte[i];
    final n = i + 1;
    set('Ad${n}Status', b.rolle);
    set('Ad${n}An', b.anrede.trim() == 'Herr' ? 'Herrn' : b.anrede);
    set('Ad${n}Name', b.name);
    set('Ad${n}Vorname', '');
    set('Ad${n}Titel', '');
    set('Ad${n}Zusatz', b.vertritt.trim().isEmpty ? '' : 'für ${b.vertritt.trim()}');
    set('Ad${n}Strasse', b.strasse);
    set('Ad${n}Plz', b.plz);
    set('Ad${n}Stadt', b.ort);
    set('Ad${n}Telefon1', b.telefon);
    set('Ad${n}Telefon', b.telefon);
    set('Ad${n}EMail', b.email);
    set('Ad${n}Email', b.email);
    set('Ad${n}IhrZeichen', b.ihrZeichen);
    set('Adresse$n', beteiligterBlock(b));
  }
  set('Verteiler', beteiligte.map((b) => '${b.rolle}: ${b.name.trim()}').join('\n'));
  set('Rechtsanwaelte', beteiligte
      .where((b) => b.rolle.toLowerCase().contains('anwalt') || b.name.toLowerCase().contains('rechtsanw'))
      .map((b) => b.name.trim())
      .join('\n'));
  final allInfo = beteiligte
      .map((b) => block([
            b.rolle,
            beteiligterBlock(b),
            b.telefon.isNotEmpty ? 'Tel.: ${b.telefon}' : null,
            b.email.isNotEmpty ? 'E-Mail: ${b.email}' : null,
            b.ihrZeichen.isNotEmpty ? 'Zeichen: ${b.ihrZeichen}' : null,
          ]))
      .join('\n\n');
  set('BeteiligtePersonenAllInfo', allInfo);
  set('BeteiligtePersonenAllInfoPIZ', allInfo);

  // Zusatzfelder (überschreiben nichts Bestehendes)
  for (final z in zusatzfelderAus(auftrag.extras)) {
    if (z.platzhalter.isNotEmpty) w.putIfAbsent(z.platzhalter.toLowerCase(), () => z.wert);
  }

  String? resolver(String tok) {
    final direkt = basis[tok];
    if (direkt != null) return direkt;
    String key;
    if (tok.startsWith(r'$')) {
      key = tok.substring(1);
    } else if (tok.startsWith('«')) {
      key = tok.substring(1, tok.length - 1);
    } else if (tok.startsWith('PH')) {
      key = tok.substring(2);
    } else if (tok.startsWith('{{')) {
      final k = tok.substring(2, tok.length - 2);
      key = k.startsWith('zf.') ? k.substring(3) : k;
    } else {
      return null;
    }
    final v = w[key.toLowerCase()];
    if (v != null) return v;
    if (RegExp(r'^ad\d+[a-z0-9]+$', caseSensitive: false).hasMatch(key) ||
        RegExp(r'^adresse\d+$', caseSensitive: false).hasMatch(key)) {
      return '';
    }
    return null;
  }

  // Serienbrief-Empfänger: zum Ortstermin geladene Beteiligte
  final empf = <WordResolver>[];
  final empfNamen = <String>[];
  if (auftraggeberAlsEmpfaenger && kunde != null) {
    final kAdr = (w['adresse'] ?? '').split('\n');
    final map = <String, String>{
      'an': kAdr.isNotEmpty ? kAdr.first : '',
      'name': kAdr.length > 1 ? kAdr[1] : '',
      'zusatz': '',
      'strasse': kunde.strasse ?? '',
      'plz': kunde.plz ?? '',
      'stadt': kunde.ort ?? '',
      'anrede': w['anrede'] ?? 'Sehr geehrte Damen und Herren',
      'fax': kunde.fax ?? '',
      'ihrzeichen': auftrag.azExtern ?? '',
      'autoseriendruckfeld': '',
    };
    empf.add((tok) => tok.startsWith('«') ? map[tok.substring(1, tok.length - 1).toLowerCase()] : null);
    empfNamen.add(kundeName(kunde));
  }
  for (final b in beteiligte.where((b) => b.zumOrtsterminLaden)) {
    final map = <String, String>{
      'an': b.anrede.trim() == 'Herr' ? 'Herrn' : b.anrede,
      'name': b.name,
      'vorname': '',
      'nachname': b.name,
      'zusatz': b.vertritt.trim().isEmpty ? '' : 'für ${b.vertritt.trim()}',
      'strasse': b.strasse,
      'plz': b.plz,
      'stadt': b.ort,
      'anrede': _ohneKomma(b.effectiveBriefanrede),
      'fax': '',
      'ihrzeichen': b.ihrZeichen,
      'email': b.email,
      'rolle': b.rolle,
      'status': b.rolle,
      'autoseriendruckfeld': '',
    };
    empf.add((tok) => tok.startsWith('«') ? map[tok.substring(1, tok.length - 1).toLowerCase()] : null);
    empfNamen.add('${b.rolle}: ${b.name}');
  }

  String? raute(String name) {
    final n = name.toLowerCase();
    if (n == 'fragenohneantworten' || n == 'fragenohneantwort' || n == 'beweisfragen') {
      return fragen.map((f) => '${f.nr}. ${f.frage}').join('\n');
    }
    for (final z in zusatzfelderAus(auftrag.extras)) {
      if (z.platzhalter.toLowerCase() == n) return z.wert;
    }
    return null;
  }

  return WordAktenDaten(
    resolver: resolver,
    personen: [for (final b in beteiligte) (b.rolle, beteiligterBlock(b))],
    empfaenger: empf,
    empfaengerNamen: empfNamen,
    raute: raute,
    werte: {
      for (final e in w.entries) e.key: e.value,
      for (final e in basis.entries) e.key: e.value,
    },
  );
}
