import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../akte/beteiligte_tab.dart';
import '../auftraege/auftrag_gm_extras.dart';
import 'gutachten_repository.dart';

/// Ergebnis der automatischen Verzeichnis-Erzeugung für ein Gutachten.
class GutachtenVerzeichnisseResult {
  const GutachtenVerzeichnisseResult({
    required this.sGrundlageText,
    required this.sAnlagenText,
    required this.anzahlUnterlagen,
    required this.anzahlQuellen,
    required this.anzahlAbkuerzungen,
    required this.anzahlFormelzeichen,
    required this.anzahlAnlagen,
  });

  /// Vollständiger Text für Abschnitt `s_grundlage`
  /// (`1. Akten und Unterlagen`, `2. Gesetze, Regelwerke und Fachquellen`,
  /// `3. Ortstermin`, `4. Abkürzungen und Formelzeichen`).
  final String sGrundlageText;

  /// Vollständiger Text für Abschnitt `s_anlagen` (`Anlagenverzeichnis`).
  final String sAnlagenText;

  final int anzahlUnterlagen;
  final int anzahlQuellen;
  final int anzahlAbkuerzungen;
  final int anzahlFormelzeichen;
  final int anzahlAnlagen;
}

class _QuellenDef {
  const _QuellenDef({
    required this.kuerzel,
    required this.pattern,
    required this.volltext,
  });

  /// Optionales festes Kürzel wie `[Q1]` oder `[N]`; wenn leer, wird fortlaufend
  /// `[Q1]`, `[Q2]` … vergeben.
  final String? kuerzel;
  final RegExp pattern;
  final String volltext;
}

class _AbkDef {
  const _AbkDef({
    required this.kuerzel,
    required this.bedeutung,
    required this.pattern,
  });

  final String kuerzel;
  final String bedeutung;
  final RegExp pattern;
}

class _FormelDef {
  const _FormelDef({
    required this.symbol,
    required this.bedeutung,
    required this.pattern,
  });

  final String symbol;
  final String bedeutung;
  final RegExp pattern;
}

/// Erzeugt automatisch aus den geschriebenen Gutachten-Abschnitten und den
/// verknüpften Akten-Stammdaten:
/// 1. **Unterlagenverzeichnis** (`II.1 Akten und Unterlagen`)
/// 2. **Normen- und Quellenverzeichnis** (`II.2 Gesetze, Regelwerke und Fachquellen`)
/// 3. **Ortstermin-Block** (`II.3 Ortstermin` – behält bestehenden Block oder erzeugt Standard)
/// 4. **Abkürzungs- und Formelverzeichnis** (`II.4 Abkürzungen und Formelzeichen`)
/// 5. **Anlagenverzeichnis** (`s_anlagen`)
class GutachtenVerzeichnisseGenerator {
  GutachtenVerzeichnisseGenerator._();

  static final DateFormat _df = DateFormat('dd.MM.yyyy');

  /// Bekannte Gesetze, Regelwerke, Zulassungen und Fachquellen im Metallbau/Bauwesen.
  static final List<_QuellenDef> _kBekannteQuellen = [
    _QuellenDef(
      kuerzel: 'Q1',
      pattern: RegExp(r'\bHBO\b|Hessische\s+Bauordnung', caseSensitive: false),
      volltext:
          'Hessische Bauordnung (HBO) vom 28. Mai 2018 (GVBl. S. 198), zuletzt geändert durch Gesetz vom 22. November 2022 (GVBl. S. 571): §§ 3, 16a, 16b, 35, 53.',
    ),
    _QuellenDef(
      kuerzel: 'Q2',
      pattern: RegExp(r'\bASR\s*A\s*2\.1\b|\bArbStättV\b|Arbeitsstättenverordnung', caseSensitive: false),
      volltext:
          'Technische Regeln für Arbeitsstätten ASR A2.1 „Schutz vor Absturz und herabfallenden Gegenständen, Betreten von Gefahrenbereichen", Ausgabe November 2012, zuletzt geändert GMBl 2018 S. 473, i. V. m. § 3a Arbeitsstättenverordnung (ArbStättV).',
    ),
    _QuellenDef(
      kuerzel: 'Q3',
      pattern: RegExp(r'\bH-VV\s*TB\b|\bMVV\s*TB\b|Verwaltungsvorschrift\s+Technische\s+Baubestimmungen', caseSensitive: false),
      volltext:
          'Hessische Verwaltungsvorschrift Technische Baubestimmungen (H-VV TB) auf Grundlage der Muster-Verwaltungsvorschrift Technische Baubestimmungen (MVV TB, Ausgabe 2023/1, DIBt) – Erlass des Hessischen Ministeriums für Wirtschaft, Energie, Verkehr und Wohnen (StAnz. Hessen): lfd. Nr. A 1.2.1 (DIN EN 1990 mit NA), A 1.2.2 (DIN EN 1991-1-1 mit NA), A 1.2.5 (DIN EN 1993-1-1 mit NA, DIN EN 1090-2), A 1.2.7 (DIN EN 1992-4), B 2.2.1.4 (DIN 18065) und A 1.2.8 (DIN 18008 Teile 1, 2 und 4).',
    ),
    _QuellenDef(
      kuerzel: 'Q4',
      pattern: RegExp(r'\bETA[-\s]*07/0211\b|Fischer\s+FBN\s*II', caseSensitive: false),
      volltext:
          'Europäische Technische Bewertung ETA-07/0211 für Fischer Bolzenanker FBN II / FBN II K (Deutsches Institut für Bautechnik – DIBt, Berlin).',
    ),
    _QuellenDef(
      kuerzel: 'Q5',
      pattern: RegExp(r'\bTrespa\b|\bDE\s*3075\b|\bMeteon\b', caseSensitive: false),
      volltext:
          'Trespa International B.V.: Verarbeitungsrichtlinie Trespa Meteon – Balkonbekleidungen, Dokumentcode DE3075, Version 2.0.',
    ),
    _QuellenDef(
      kuerzel: 'Q6',
      pattern: RegExp(r'DIN\s*EN\s*ISO\s*1461\b', caseSensitive: false),
      volltext:
          'DIN EN ISO 1461:2022-12 „Durch Feuerverzinken auf Stahl aufgebrachte Zinküberzüge (Stückverzinken) – Anforderungen und Prüfungen".',
    ),
    _QuellenDef(
      kuerzel: 'Q7',
      pattern: RegExp(r'Geländer-Richtlinie|Metallbauverband\s*NRW|\bBVM\b', caseSensitive: false),
      volltext:
          'Metallbauverband NRW / Bundesverband Metall (BVM): „Geländer-Richtlinie – Planung und Ausführung von Geländern aus Metall", Essen.',
    ),
    _QuellenDef(
      kuerzel: 'Q8',
      pattern: RegExp(r'DIN\s*EN\s*1993-1-1(?:/NA)?\b', caseSensitive: false),
      volltext:
          'DIN EN 1993-1-1:2010-12 mit DIN EN 1993-1-1/NA:2018-12 „Eurocode 3: Bemessung und Konstruktion von Stahlbauten – Teil 1-1: Allgemeine Bemessungsregeln und Regeln für den Hochbau".',
    ),
    _QuellenDef(
      kuerzel: 'Q9',
      pattern: RegExp(r'Fachregelwerk\s+des\s+Metallbauerhandwerks|Konstruktiver\s+Korrosionsschutz\s+im\s+Metallbau', caseSensitive: false),
      volltext:
          'Bundesverband Metall (BVM): Fachregelwerk des Metallbauerhandwerks – Blätter „Geländer und Umwehrungen" sowie „Konstruktiver Korrosionsschutz im Metallbau".',
    ),
    _QuellenDef(
      kuerzel: 'Q10',
      pattern: RegExp(r'DIN\s*18531(?:-5)?\b', caseSensitive: false),
      volltext:
          'DIN 18531-5:2017-07 „Abdichtung von Dächern sowie von Balkonen, Loggien und Laubengängen – Teil 5: Balkone, Loggien und Laubengänge".',
    ),
    _QuellenDef(
      kuerzel: 'Q11',
      pattern: RegExp(r'DIN\s*18008(?:-1|-2|-4)?\b', caseSensitive: false),
      volltext:
          'DIN 18008-1:2020-05 „Glas im Bauwesen – Bemessungs- und Konstruktionsregeln – Teil 1: Begriffe und allgemeine Grundlagen"; DIN 18008-2:2020-05 „Teil 2: Linienförmig gelagerte Verglasungen"; DIN 18008-4:2024-12 „Teil 4: Zusatzanforderungen an absturzsichernde Verglasungen".',
    ),
    _QuellenDef(
      kuerzel: 'Q12',
      pattern: RegExp(r'RAL-Leitfaden|Leitfaden\s+zur\s+Planung\s+und\s+Ausführung\s+der\s+Montage', caseSensitive: false),
      volltext:
          'RAL-Gütegemeinschaft Fenster, Fassaden und Haustüren e. V. / ift Rosenheim: „Leitfaden zur Planung und Ausführung der Montage von Fenstern und Haustüren für Neubau und Renovierung", Ausgabe 2020/2024.',
    ),
    _QuellenDef(
      kuerzel: 'Q13',
      pattern: RegExp(r'DIN\s*18339\b', caseSensitive: false),
      volltext:
          'DIN 18339:2019-09 (VOB/C) „Allgemeine Technische Vertragsbedingungen für Bauleistungen (ATV) – Klempnerarbeiten".',
    ),
    _QuellenDef(
      kuerzel: 'Q14',
      pattern: RegExp(r'\bASR\s*A\s*1\.6\b', caseSensitive: false),
      volltext:
          'Technische Regeln für Arbeitsstätten ASR A1.6 „Fenster, Oberlichter, lichtdurchlässige Wände", Ausgabe Januar 2012, zuletzt geändert GMBl 2022 S. 198.',
    ),
    _QuellenDef(
      kuerzel: 'Q15',
      pattern: RegExp(r'DIN\s*4108(?:-2|-3|-7)?\b', caseSensitive: false),
      volltext:
          'DIN 4108-2:2013-02 „Wärmeschutz und Energie-Einsparung in Gebäuden – Teil 2: Mindestanforderungen an den Wärmeschutz"; DIN 4108-3:2024-03 „Teil 3: Klimabedingter Feuchteschutz"; DIN 4108-7:2011-01 „Teil 7: Luftdichtheit von Gebäuden".',
    ),
    _QuellenDef(
      kuerzel: 'Q16',
      pattern: RegExp(r'Jansen\s*VISS|Schüco\s*Jansen', caseSensitive: false),
      volltext:
          'Jansen AG (Schüco Jansen Steel Systems): Systemdokumentation und Verarbeitungsrichtlinien „Jansen VISS Fassade – Aufsatzkonstruktion auf Stahl und Holz", Oberriet (CH).',
    ),
    _QuellenDef(
      kuerzel: 'Q17',
      pattern: RegExp(r'ETA[-\s]*10/0305|ETA[-\s]*13/0183|\bSFS\s+intec\b|\bMBE\b', caseSensitive: false),
      volltext:
          'SFS intec / MBE: Europäische Technische Bewertung (ETA-10/0305 bzw. ETA-13/0183) für Fassadenbauschrauben aus nichtrostendem Stahl für hinterlüftete Fassadenbekleidungen.',
    ),
    _QuellenDef(
      kuerzel: 'Q18',
      pattern: RegExp(r'\bBKI\b|Baukosteninformationszentrum|Preisumfrage\s+im\s+Metallbauerhandwerk', caseSensitive: false),
      volltext:
          'BKI Baukosteninformationszentrum Deutscher Architektenkammern GmbH: „BKI Baukosten Positionen Neubau / Altbau – Metallbau-, Schlosser-, Verglasungs- und Klempnerarbeiten", Stuttgart, Ausgabe 2025/2026, sowie Bundesverband Metall (BVM): „Preisumfrage im Metallbauerhandwerk – Stundensätze und Verrechnungssätze (Region Rhein-Main / Hessen)", aktuelle Erhebung.',
    ),
    _QuellenDef(
      kuerzel: 'Q19',
      pattern: RegExp(r'DIN\s*EN\s*1991-1-1(?:/NA)?\b', caseSensitive: false),
      volltext:
          'DIN EN 1991-1-1:2010-12 mit DIN EN 1991-1-1/NA:2010-12 „Eurocode 1: Einwirkungen auf Tragwerke – Teil 1-1: Allgemeine Einwirkungen auf Tragwerke – Wichten, Eigengewicht und Nutzlasten im Hochbau": Tab. 6.1 DE (Gebäudekategorien), Abschn. 6.4 und Tab. 6.12 DE (Horizontale Nutzlasten q_k auf Brüstungen und Geländer).',
    ),
    _QuellenDef(
      kuerzel: 'Q20',
      pattern: RegExp(r'DIN\s*18065\b', caseSensitive: false),
      volltext:
          'DIN 18065:2020-08 „Gebäudetreppen – Begriffe, Messregeln, Hauptmaße": Tab. 1 Zeilen 12/13 (Mindesthöhe von Treppen- und Brüstungsgeländern: 90 cm bis 12 m Absturzhöhe, 110 cm ab 12 m Absturzhöhe) sowie Abschn. 6.8.3 (Öffnungen in Umwehrungen).',
    ),
    _QuellenDef(
      kuerzel: 'Q21',
      pattern: RegExp(r'DIN\s*EN\s*10025-2\b|\bS235JR\b', caseSensitive: false),
      volltext:
          'DIN EN 10025-2:2019-10 „Warmgewalzte Erzeugnisse aus Baustählen – Teil 2: Technische Lieferbedingungen für unlegierte Baustähle": Tab. 6 (Streckgrenze f_y = 235 N/mm² für S235JR bei Nenndicken t ≤ 16 mm).',
    ),
    _QuellenDef(
      kuerzel: 'Q22',
      pattern: RegExp(r'DIN\s*EN\s*1990(?:/NA)?\b', caseSensitive: false),
      volltext:
          'DIN EN 1990:2021-10 mit DIN EN 1990/NA:2021-10 „Eurocode: Grundlagen der Tragwerksplanung": Abschn. 6.4.3.2 und Tab. A1.2(B) / NDP zu A1.3.1 (Teilsicherheitsbeiwert γ_Q = 1,50 für veränderliche Einwirkungen im Grenzzustand der Tragfähigkeit STR/GEO).',
    ),
    _QuellenDef(
      kuerzel: 'Q23',
      pattern: RegExp(r'DIN\s*EN\s*1992-4\b', caseSensitive: false),
      volltext:
          'DIN EN 1992-4:2019-04 „Eurocode 2: Bemessung und Konstruktion von Stahlbeton- und Spannbetontragwerken – Teil 4: Bemessung der Verankerung von Befestigungen in Beton": Abschn. 7.2.1.4 (Nachweis gegen Betonausbruch unter Zugbeanspruchung, Ψ-Faktoren für Achs- und Randabstände sowie Bewehrungseinfluss).',
    ),
    _QuellenDef(
      kuerzel: 'Q24',
      pattern: RegExp(r'DIN\s*EN\s*13914-1\b', caseSensitive: false),
      volltext:
          'DIN EN 13914-1:2016-09 „Planung, Zubereitung und Ausführung von Außen- und Innenputzen – Teil 1: Außenputze".',
    ),
    _QuellenDef(
      kuerzel: 'Q25',
      pattern: RegExp(r'DIN\s*EN\s*10219-2\b', caseSensitive: false),
      volltext:
          'DIN EN 10219-2:2019-07 „Kaltgefertigte geschweißte Hohlprofile für den Stahlbau aus unlegierten Baustählen und aus Feinkornbaustählen – Teil 2: Grenzabmaße, Maße und statische Werte": Anhang B, Tab. B.1 und B.2 (Querschnittswerte für Quadrat- und Rechteckhohlprofile).',
    ),
  ];

  static final List<_QuellenDef> _kNormenSammelQuellen = [
    _QuellenDef(
      kuerzel: null,
      pattern: RegExp(r'DIN\s*EN\s*1090-1\b', caseSensitive: false),
      volltext:
          'DIN EN 1090-1:2012-02 „Ausführung von Stahltragwerken und Aluminiumtragwerken – Teil 1: Konformitätsnachweisverfahren für tragende Bauteile"',
    ),
    _QuellenDef(
      kuerzel: null,
      pattern: RegExp(r'DIN\s*EN\s*1090-2\b', caseSensitive: false),
      volltext:
          'DIN EN 1090-2:2018-09 „Teil 2: Technische Regeln für die Ausführung von Stahltragwerken"',
    ),
    _QuellenDef(
      kuerzel: null,
      pattern: RegExp(r'DIN\s*EN\s*ISO\s*9606-1\b', caseSensitive: false),
      volltext:
          'DIN EN ISO 9606-1:2017-12 „Prüfung von Schweißern – Schmelzschweißen – Teil 1: Stähle"',
    ),
    _QuellenDef(
      kuerzel: null,
      pattern: RegExp(r'DIN\s*EN\s*1993-1-4\b', caseSensitive: false),
      volltext:
          'DIN EN 1993-1-4:2015-10 mit NA:2020-11 „Eurocode 3 – Teil 1-4: Ergänzende Regeln zur Anwendung von nichtrostenden Stählen"',
    ),
    _QuellenDef(
      kuerzel: null,
      pattern: RegExp(r'DIN\s*18360\b', caseSensitive: false),
      volltext:
          'DIN 18360:2019-09 (VOB/C) „ATV Metallbauarbeiten"',
    ),
  ];

  /// Wörterbuch technischer und juristischer Abkürzungen.
  static final List<_AbkDef> _kAbkuerzungen = [
    _AbkDef(
      kuerzel: 'A2',
      bedeutung: 'Nichtrostender austenitischer Edelstahl (z. B. Werkstoff-Nr. 1.4301)',
      pattern: RegExp(r'\bA2\b'),
    ),
    _AbkDef(
      kuerzel: 'Abs., Abschn.',
      bedeutung: 'Absatz, Abschnitt',
      pattern: RegExp(r'\bAbs\.|\bAbschn\.'),
    ),
    _AbkDef(
      kuerzel: 'ArbStättV',
      bedeutung: 'Arbeitsstättenverordnung',
      pattern: RegExp(r'\bArbStättV\b'),
    ),
    _AbkDef(
      kuerzel: 'ASR',
      bedeutung: 'Technische Regeln für Arbeitsstätten',
      pattern: RegExp(r'\bASR\b'),
    ),
    _AbkDef(
      kuerzel: 'ATV',
      bedeutung: 'Allgemeine Technische Vertragsbedingungen für Bauleistungen (VOB/C)',
      pattern: RegExp(r'\bATV\b'),
    ),
    _AbkDef(
      kuerzel: 'Az.',
      bedeutung: 'Aktenzeichen',
      pattern: RegExp(r'\bAz\.'),
    ),
    _AbkDef(
      kuerzel: 'BKI',
      bedeutung: 'Baukosteninformationszentrum Deutscher Architektenkammern',
      pattern: RegExp(r'\bBKI\b'),
    ),
    _AbkDef(
      kuerzel: 'BVM',
      bedeutung: 'Bundesverband Metall – Vereinigung Deutscher Metallhandwerke',
      pattern: RegExp(r'\bBVM\b'),
    ),
    _AbkDef(
      kuerzel: 'CRC',
      bedeutung: 'Corrosion Resistance Class (Korrosionswiderstandsklasse nach DIN EN 1993-1-4)',
      pattern: RegExp(r'\bCRC\b'),
    ),
    _AbkDef(
      kuerzel: 'DIN',
      bedeutung: 'Deutsches Institut für Normung e. V.',
      pattern: RegExp(r'\bDIN\b'),
    ),
    _AbkDef(
      kuerzel: 'EG',
      bedeutung: 'Erdgeschoss',
      pattern: RegExp(r'\bEG\b'),
    ),
    _AbkDef(
      kuerzel: 'EN',
      bedeutung: 'Europäische Norm',
      pattern: RegExp(r'\bEN\b'),
    ),
    _AbkDef(
      kuerzel: 'EPDM',
      bedeutung: 'Ethylen-Propylen-Dien-Kautschuk (Dichtungsbahn / Dichtprofil)',
      pattern: RegExp(r'\bEPDM\b'),
    ),
    _AbkDef(
      kuerzel: 'ESG',
      bedeutung: 'Einscheiben-Sicherheitsglas',
      pattern: RegExp(r'\bESG\b'),
    ),
    _AbkDef(
      kuerzel: 'ETA',
      bedeutung: 'Europäische Technische Bewertung (European Technical Assessment)',
      pattern: RegExp(r'\bETA\b'),
    ),
    _AbkDef(
      kuerzel: 'EXC',
      bedeutung: 'Execution Class (Ausführungsklasse nach DIN EN 1090-2)',
      pattern: RegExp(r'\bEXC\s*[1-4]?\b'),
    ),
    _AbkDef(
      kuerzel: 'FBN',
      bedeutung: 'Fischer Bolzenanker (Produktbezeichnung)',
      pattern: RegExp(r'\bFBN\b'),
    ),
    _AbkDef(
      kuerzel: 'GMBl, GVBl.',
      bedeutung: 'Gemeinsames Ministerialblatt, Gesetz- und Verordnungsblatt',
      pattern: RegExp(r'\bGMBl\b|\bGVBl\.'),
    ),
    _AbkDef(
      kuerzel: 'HBO',
      bedeutung: 'Hessische Bauordnung',
      pattern: RegExp(r'\bHBO\b'),
    ),
    _AbkDef(
      kuerzel: 'HDG',
      bedeutung: 'Hot-Dip Galvanized (feuerverzinkt)',
      pattern: RegExp(r'\bHDG\b'),
    ),
    _AbkDef(
      kuerzel: 'HPL',
      bedeutung: 'High Pressure Laminate (Hochdruck-Schichtpressstoffplatte)',
      pattern: RegExp(r'\bHPL\b'),
    ),
    _AbkDef(
      kuerzel: 'H-VV TB',
      bedeutung: 'Hessische Verwaltungsvorschrift Technische Baubestimmungen',
      pattern: RegExp(r'\bH-VV\s*TB\b'),
    ),
    _AbkDef(
      kuerzel: 'ISO',
      bedeutung: 'International Organization for Standardization',
      pattern: RegExp(r'\bISO\b'),
    ),
    _AbkDef(
      kuerzel: 'MBE',
      bedeutung: 'Moderne Befestigungselemente GmbH (Fassadenbauschrauben)',
      pattern: RegExp(r'\bMBE\b'),
    ),
    _AbkDef(
      kuerzel: 'MVV TB',
      bedeutung: 'Muster-Verwaltungsvorschrift Technische Baubestimmungen',
      pattern: RegExp(r'\bMVV\s*TB\b'),
    ),
    _AbkDef(
      kuerzel: 'NA',
      bedeutung: 'Nationaler Anhang (zu den Eurocodes)',
      pattern: RegExp(r'/NA\b|\bNA\b'),
    ),
    _AbkDef(
      kuerzel: 'NDP',
      bedeutung: 'Nationally Determined Parameter (national festgelegter Parameter)',
      pattern: RegExp(r'\bNDP\b'),
    ),
    _AbkDef(
      kuerzel: 'OG',
      bedeutung: 'Obergeschoss',
      pattern: RegExp(r'\bOG\b|\b\d+\.\s*OG\b'),
    ),
    _AbkDef(
      kuerzel: 'OH',
      bedeutung: 'Over Head (Überkopfverglasung)',
      pattern: RegExp(r'\bOH\b'),
    ),
    _AbkDef(
      kuerzel: 'OK, UK',
      bedeutung: 'Oberkante, Unterkante',
      pattern: RegExp(r'\bOK\b|\bUK\b'),
    ),
    _AbkDef(
      kuerzel: 'QR, RR',
      bedeutung: 'Quadratrohr, Rechteckrohr (Stahlhohlprofil, Maße in mm)',
      pattern: RegExp(r'\bQR\b|\bRR\b'),
    ),
    _AbkDef(
      kuerzel: 'RA, RAin',
      bedeutung: 'Rechtsanwalt, Rechtsanwältin',
      pattern: RegExp(r'\bRA\b|\bRAin\b'),
    ),
    _AbkDef(
      kuerzel: 'RAL',
      bedeutung: 'RAL Gütegemeinschaft Fenster, Fassaden und Haustüren (Leitfaden zur Montage)',
      pattern: RegExp(r'\bRAL\b'),
    ),
    _AbkDef(
      kuerzel: 'StAnz.',
      bedeutung: 'Staatsanzeiger für das Land Hessen',
      pattern: RegExp(r'\bStAnz\.'),
    ),
    _AbkDef(
      kuerzel: 'SZR',
      bedeutung: 'Scheibenzwischenraum',
      pattern: RegExp(r'\bSZR\b'),
    ),
    _AbkDef(
      kuerzel: 'USt.',
      bedeutung: 'Umsatzsteuer',
      pattern: RegExp(r'\bUSt\.'),
    ),
    _AbkDef(
      kuerzel: 'VOB',
      bedeutung: 'Vergabe- und Vertragsordnung für Bauleistungen',
      pattern: RegExp(r'\bVOB\b'),
    ),
    _AbkDef(
      kuerzel: 'VSG',
      bedeutung: 'Verbund-Sicherheitsglas',
      pattern: RegExp(r'\bVSG\b'),
    ),
    _AbkDef(
      kuerzel: 'WDVS',
      bedeutung: 'Wärmedämm-Verbundsystem',
      pattern: RegExp(r'\bWDVS\b'),
    ),
    _AbkDef(
      kuerzel: 'ZPO',
      bedeutung: 'Zivilprozessordnung',
      pattern: RegExp(r'\bZPO\b'),
    ),
    _AbkDef(
      kuerzel: '[Q…], [A…], [N]',
      bedeutung: 'Verweis auf das Quellen- und Unterlagenverzeichnis in Abschnitt II',
      pattern: RegExp(r'\[Q\d+\]|\[A\d+\]|\[N\]'),
    ),
    _AbkDef(
      kuerzel: '[OT]',
      bedeutung: 'Feststellung aus dem Ortstermin',
      pattern: RegExp(r'\[OT\]'),
    ),
  ];

  /// Wörterbuch mathematischer und statischer Formelzeichen.
  static final List<_FormelDef> _kFormelzeichen = [
    _FormelDef(
      symbol: 'q_k',
      bedeutung: 'Charakteristischer Wert der horizontalen Linienlast (Holmlast) in kN/m',
      pattern: RegExp(r'\bq_k\b|\[\[FORMEL_BLOCK_PFOSTEN\]\]'),
    ),
    _FormelDef(
      symbol: 'γ_Q, γ_M0',
      bedeutung: 'Teilsicherheitsbeiwerte für veränderliche Einwirkungen (1,50) bzw. Material Stahl (1,0)',
      pattern: RegExp(r'γ_Q|γ_M0|\[\[FORMEL_BLOCK_PFOSTEN\]\]'),
    ),
    _FormelDef(
      symbol: 'η',
      bedeutung: 'Ausnutzungsgrad (η ≤ 1,0 bedeutet Nachweis erfüllt)',
      pattern: RegExp(r'\bη\b|\[\[FORMEL_BLOCK_PFOSTEN\]\]'),
    ),
    _FormelDef(
      symbol: 'I',
      bedeutung: 'Flächenträgheitsmoment in cm⁴',
      pattern: RegExp(r'\bI\s*=|\[\[FORMEL_BLOCK_PFOSTEN\]\]'),
    ),
    _FormelDef(
      symbol: 'W_el, W_pl',
      bedeutung: 'Elastisches bzw. plastisches Widerstandsmoment in cm³',
      pattern: RegExp(r'\bW_el\b|\bW_pl\b|\[\[FORMEL_BLOCK_PFOSTEN\]\]'),
    ),
    _FormelDef(
      symbol: 'M_pl,Rd',
      bedeutung: 'Bemessungswert der plastischen Momententragfähigkeit in kNm',
      pattern: RegExp(r'\bM_pl,Rd\b|\[\[FORMEL_BLOCK_PFOSTEN\]\]'),
    ),
    _FormelDef(
      symbol: 'f_y,k',
      bedeutung: 'Charakteristischer Wert der Streckgrenze von Stahl in N/mm²',
      pattern: RegExp(r'\bf_y(?:,k)?\b|\[\[FORMEL_BLOCK_PFOSTEN\]\]'),
    ),
    _FormelDef(
      symbol: 'M_Ed, F_Ed',
      bedeutung: 'Bemessungswert des einwirkenden Biegemoments in kNm bzw. der Kraft in kN',
      pattern: RegExp(r'\bM_Ed\b|\bF_Ed\b|\[\[FORMEL_BLOCK_PFOSTEN\]\]'),
    ),
    _FormelDef(
      symbol: 'h_ef',
      bedeutung: 'Effektive Verankerungstiefe eines Dübels in mm',
      pattern: RegExp(r'\bh_ef\b|\[\[FORMEL_BLOCK_ANKER\]\]'),
    ),
    _FormelDef(
      symbol: 'h_min, s_min, c_min',
      bedeutung: 'Mindestbauteildicke, Mindestachsabstand, Mindestrandabstand in mm',
      pattern: RegExp(r'\bh_min\b|\bs_min\b|\bc_min\b|\[\[FORMEL_BLOCK_ANKER\]\]'),
    ),
    _FormelDef(
      symbol: 's_cr,N, c_cr,N',
      bedeutung: 'Charakteristischer Achs- bzw. Randabstand bei Betonausbruch in mm',
      pattern: RegExp(r'\bs_cr,N\b|\bc_cr,N\b|\[\[FORMEL_BLOCK_ANKER\]\]'),
    ),
    _FormelDef(
      symbol: 'A_c,N, A⁰_c,N',
      bedeutung: 'Vorhandene bzw. ideale Projektionsfläche des Betonausbruchkörpers in mm²',
      pattern: RegExp(r'\bA_c,N\b|A⁰_c,N|\[\[FORMEL_BLOCK_ANKER\]\]'),
    ),
    _FormelDef(
      symbol: 'ψ_s,N',
      bedeutung: 'Faktor zur Berücksichtigung der Störung der Spannungsverteilung im Beton durch freie Ränder',
      pattern: RegExp(r'ψ_s,N|\[\[FORMEL_BLOCK_ANKER\]\]'),
    ),
    _FormelDef(
      symbol: 'ψ_re,N',
      bedeutung: 'Schalenabplatzfaktor zur Berücksichtigung einer dichten Bewehrung',
      pattern: RegExp(r'ψ_re,N|\[\[FORMEL_BLOCK_ANKER\]\]'),
    ),
    _FormelDef(
      symbol: 'U_g',
      bedeutung: 'Wärmedurchgangskoeffizient der Verglasung in W/(m²·K)',
      pattern: RegExp(r'\bU_g\b'),
    ),
    _FormelDef(
      symbol: 'U_w, U_f',
      bedeutung: 'Wärmedurchgangskoeffizient des Fensters bzw. Rahmens in W/(m²·K)',
      pattern: RegExp(r'\bU_w\b|\bU_f\b'),
    ),
    _FormelDef(
      symbol: 'f_Rsi',
      bedeutung: 'Temperaturfaktor an der inneren Bauteiloberfläche (Schimmelpilzkriterium)',
      pattern: RegExp(r'\bf_Rsi\b'),
    ),
  ];

  /// Erzeugt alle Verzeichnisse aus den Abschnitten des Gutachtens und den
  /// Stammdaten der verknüpften Akte.
  static GutachtenVerzeichnisseResult generate({
    required Map<String, String> abschnittePlain,
    required AuftraegeData? auftrag,
    required DateTime? ortsterminAm,
    required List<GutachtenAnlage> anlagen,
    required List<DokumenteData> aktenDokumente,
    required List<NormenData> aktenNormen,
  }) {
    // 1. Volltext aller Fachabschnitte zusammenführen (ohne altes Abkürzungs-/Normenverzeichnis,
    //    damit wir nur tatsächlich im Gutachten verwendete Begriffe aufnehmen;
    //    aus s_grundlage berücksichtigen wir aber den Ortstermin-Teil).
    final bisherigeGrundlage = abschnittePlain['s_grundlage'] ?? '';
    final ortsterminBlock = _extractOrBuildOrtsterminBlock(
      bisherigeGrundlage: bisherigeGrundlage,
      auftrag: auftrag,
      ortsterminAm: ortsterminAm,
    );

    final scanBuffer = StringBuffer();
    for (final entry in abschnittePlain.entries) {
      if (entry.key == 's_grundlage' || entry.key == 's_normenverzeichnis') {
        continue;
      }
      scanBuffer.writeln(entry.value);
    }
    scanBuffer.writeln(ortsterminBlock);
    final scanText = scanBuffer.toString();

    // 2. Unterlagenverzeichnis (II.1 Akten und Unterlagen)
    final dokById = {for (final d in aktenDokumente) d.id: d};
    final unterlagenLines = <String>[];

    // [A1] Gerichtsakte / Auftragsunterlagen
    final extras = AuftragGmExtras.fromExtras(auftrag?.extras);
    final gerichtName = [auftrag?.gericht, auftrag?.gerichtsort]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(' ');
    final gerichtsAz = (auftrag?.gerichtsAktenzeichen ?? '').trim();
    final bbDatum = auftrag?.beweisbeschluss1 != null
        ? _df.format(auftrag!.beweisbeschluss1!)
        : null;
    final aktenbaende = extras.aktenbaende
        .map((b) {
          final blatt = (b.seitenVon != null && b.seitenBis != null)
              ? ' (Bl. ${b.seitenVon}–${b.seitenBis})'
              : '';
          return '${b.bandNr}${blatt.isNotEmpty ? blatt : ""}';
        })
        .where((s) => s.trim().isNotEmpty)
        .join(', ');
    if (gerichtName.isNotEmpty || gerichtsAz.isNotEmpty) {
      final teile = <String>[
        'Gerichtsakte des ${gerichtName.isNotEmpty ? gerichtName : "Gerichts"}',
        if (gerichtsAz.isNotEmpty) 'Az. $gerichtsAz',
        if (aktenbaende.isNotEmpty) '($aktenbaende)',
      ];
      final satz1 = teile.join(', ');
      final satz2 = bbDatum != null
          ? ' einschließlich Beweisbeschluss vom $bbDatum und sämtlicher Schriftsätze.'
          : '.';
      unterlagenLines.add('[A1]\t$satz1$satz2');
    } else if (auftrag != null) {
      unterlagenLines.add(
        '[A1]\tAuftragsunterlagen zur Akte ${auftrag.aktenzeichen}${auftrag.bezeichnung != null ? " (${auftrag.bezeichnung})" : ""}.',
      );
    }

    // [OT] Ortstermin
    final otDate = ortsterminAm ?? auftrag?.ortsterminAm;
    if (otDate != null) {
      unterlagenLines.add(
        '[OT]\tEigene Feststellungen, Aufmaße, Messungen und Fotografien beim Ortstermin am ${_df.format(otDate)} (Anlage 1, Bilder 1 bis 50).',
      );
    } else {
      unterlagenLines.add(
        '[OT]\tEigene Feststellungen, Aufmaße, Messungen und Fotografien beim Ortstermin.',
      );
    }

    // [A2] .. [An] aus den Anlagen (oder Dokumenten der Akte)
    final sortierteAnlagen = [...anlagen]..sort((a, b) => a.nr.compareTo(b.nr));
    var aIndex = 2;
    for (final a in sortierteAnlagen) {
      final dok = dokById[a.dokumentId];
      final titel = a.titel.trim().isNotEmpty
          ? a.titel.trim()
          : (dok?.titel ?? 'Dokument');
      // Lichtbilddokumentation ist bereits in [OT] (Anlage 1) genannt.
      if (titel.toLowerCase().contains('lichtbilddokumentation')) {
        continue;
      }
      final beschr = (dok?.beschreibung ?? '').trim();
      final anlageRef = 'Anlage ${a.nr + 1}';
      if (beschr.isNotEmpty) {
        final hatAnlageRef = beschr.toLowerCase().contains('anlage');
        final suffix = hatAnlageRef ? '' : ' ($anlageRef)';
        final punkt = beschr.endsWith('.') ? '' : '.';
        unterlagenLines.add('[A$aIndex]\t$beschr$suffix$punkt');
      } else {
        unterlagenLines.add('[A$aIndex]\t$titel ($anlageRef).');
      }
      aIndex++;
    }

    // 3. Normen- und Quellenverzeichnis (II.2 Gesetze, Regelwerke und Fachquellen)
    final quellenLines = <String>[];
    final erkannteNormNummern = <String>{};

    for (final q in _kBekannteQuellen) {
      // Prüfen, ob das Kürzel [Qx] oder das Fachmuster im Text vorkommt
      final kuerzelHit = q.kuerzel != null &&
          RegExp('\\[${RegExp.escape(q.kuerzel!)}\\]').hasMatch(scanText);
      final patternHit = q.pattern.hasMatch(scanText);
      if (kuerzelHit || patternHit) {
        final label = q.kuerzel ?? 'Q${quellenLines.length + 1}';
        quellenLines.add('[$label]\t${q.volltext}');
        erkannteNormNummern.add(q.volltext.toLowerCase());
      }
    }

    // Sammelblock [N] für Ausführungsnormen + weitere in der Akte hinterlegte Normen
    final sammelNormen = <String>[];
    for (final nq in _kNormenSammelQuellen) {
      if (nq.pattern.hasMatch(scanText) || scanText.contains('[N]')) {
        sammelNormen.add(nq.volltext);
        erkannteNormNummern.add(nq.volltext.toLowerCase());
      }
    }

    // Zusätzlich in der Akte verknüpfte Normen prüfen, die noch nicht über [Q1..Q25] oder [N] abgedeckt sind
    var dynQ = 26;
    for (final n in aktenNormen) {
      final nrClean = n.nummer.trim();
      if (nrClean.isEmpty) continue;
      final schonAbgedeckt = erkannteNormNummern.any(
        (v) => v.contains(nrClean.toLowerCase()),
      );
      if (schonAbgedeckt) continue;
      if (scanText.toLowerCase().contains(nrClean.toLowerCase())) {
        final ausgabe = (n.ausgabe ?? '').trim();
        final titel = (n.titel ?? '').trim();
        final eintrag = [
          '$nrClean${ausgabe.isNotEmpty ? ":$ausgabe" : ""}',
          if (titel.isNotEmpty) '„$titel"',
        ].join(' ');
        quellenLines.add('[Q$dynQ]\t$eintrag.');
        dynQ++;
      }
    }

    if (sammelNormen.isNotEmpty) {
      quellenLines.add('[N]\t${sammelNormen.join('; ')}.');
    }

    // 4. Abkürzungsverzeichnis & Formelverzeichnis (II.4 Abkürzungen und Formelzeichen)
    final gesamtScanText = '$scanText\n${unterlagenLines.join("\n")}\n${quellenLines.join("\n")}';
    final abkRows = <String>[
      '| Abkürzung | Bedeutung |',
      '|---|---|',
    ];
    var abkCount = 0;
    for (final abk in _kAbkuerzungen) {
      if (abk.pattern.hasMatch(gesamtScanText)) {
        abkRows.add('| ${abk.kuerzel} | ${abk.bedeutung} |');
        abkCount++;
      }
    }

    final formelRows = <String>[
      '| Formelzeichen | Bedeutung |',
      '|---|---|',
    ];
    var formelCount = 0;
    for (final f in _kFormelzeichen) {
      if (f.pattern.hasMatch(gesamtScanText)) {
        formelRows.add('| ${f.symbol} | ${f.bedeutung} |');
        formelCount++;
      }
    }

    // 5. Gesamten Text für s_grundlage zusammensetzen
    final grundlageBuf = StringBuffer();
    grundlageBuf.writeln('1. Akten und Unterlagen');
    for (final line in unterlagenLines) {
      grundlageBuf.writeln(line);
    }
    grundlageBuf.writeln();
    grundlageBuf.writeln('2. Gesetze, Regelwerke und Fachquellen');
    for (final line in quellenLines) {
      grundlageBuf.writeln(line);
    }
    grundlageBuf.writeln(
      'Hinweis zu den Normausgaben: Maßgeblich für die technische Beurteilung der Werkleistung ist der Stand der anerkannten Regeln der Technik zum Zeitpunkt der Abnahme. Im Verzeichnis sind die aktuellen Ausgaben genannt; in den hier beurteilten Punkten (Holmlasten, Mindesthöhen, zulässige Öffnungsmaße, Mindestschichtdicken der Feuerverzinkung, Randabstände von Befestigungen und Fassadenplatten, Absturzsicherung und Montage von Verglasungen) stimmen die Anforderungen mit den zum Ausführungszeitpunkt gültigen Fassungen überein.',
    );
    grundlageBuf.writeln();
    grundlageBuf.writeln(ortsterminBlock.trim());
    grundlageBuf.writeln();
    grundlageBuf.writeln('4. Abkürzungen und Formelzeichen');
    for (final row in abkRows) {
      grundlageBuf.writeln(row);
    }
    if (formelCount > 0) {
      grundlageBuf.writeln();
      for (final row in formelRows) {
        grundlageBuf.writeln(row);
      }
    }

    // 6. Anlagenverzeichnis (s_anlagen) erzeugen
    final anlagenBuf = StringBuffer();
    var anlagenCount = 0;

    // Prüfen, ob Anlage 1 bereits in sortierteAnlagen enthalten ist oder ob Lichtbilddokumentation separat geführt wird
    final hatLichtbildInListe = sortierteAnlagen.any(
      (a) => a.titel.toLowerCase().contains('lichtbilddokumentation'),
    );
    if (!hatLichtbildInListe) {
      final otStr = otDate != null ? ' vom ${_df.format(otDate)}' : '';
      anlagenBuf.writeln(
        '• **Anlage 1:** Lichtbilddokumentation zum Ortstermin$otStr (Bilder 1 bis 50).',
      );
      anlagenCount++;
    }

    for (final a in sortierteAnlagen) {
      final dok = dokById[a.dokumentId];
      final anlageNummer = hatLichtbildInListe ? a.nr : a.nr + 1;
      final beschr = (dok?.beschreibung ?? '').trim();
      final titel = a.titel.trim().isNotEmpty
          ? a.titel.trim()
          : (dok?.titel ?? 'Anlage $anlageNummer');
      final text = beschr.isNotEmpty ? beschr : titel;
      final punkt = text.endsWith('.') ? '' : '.';
      anlagenBuf.writeln('• **Anlage $anlageNummer:** $text$punkt');
      anlagenCount++;
    }

    anlagenBuf.writeln();
    anlagenBuf.write(
      'Die vorstehend aufgeführten Anlagen sind Bestandteil dieses Gutachtens und im Anhang beigefügt.',
    );

    return GutachtenVerzeichnisseResult(
      sGrundlageText: grundlageBuf.toString().trim(),
      sAnlagenText: anlagenBuf.toString().trim(),
      anzahlUnterlagen: unterlagenLines.length,
      anzahlQuellen: quellenLines.length + (sammelNormen.isNotEmpty ? sammelNormen.length - 1 : 0),
      anzahlAbkuerzungen: abkCount,
      anzahlFormelzeichen: formelCount,
      anzahlAnlagen: anlagenCount,
    );
  }

  /// Extrahiert einen bereits geschriebenen Abschnitt `3. Ortstermin` aus `s_grundlage`
  /// oder erzeugt einen strukturierten Ortstermin-Block aus den Akten-Stammdaten.
  static String _extractOrBuildOrtsterminBlock({
    required String bisherigeGrundlage,
    required AuftraegeData? auftrag,
    required DateTime? ortsterminAm,
  }) {
    final startMatch =
        RegExp(r'^3\.\s+Ortstermin\b', multiLine: true).firstMatch(bisherigeGrundlage);
    if (startMatch != null) {
      final afterStart = bisherigeGrundlage.substring(startMatch.start);
      final endMatch = RegExp(
        r'^4\.\s+Abkürzungen\b',
        multiLine: true,
      ).firstMatch(afterStart);
      if (endMatch != null) {
        return afterStart.substring(0, endMatch.start).trim();
      }
      return afterStart.trim();
    }

    // Fallback: Standard-Ortstermin-Block aus Akten-Stammdaten aufbauen
    final otDate = ortsterminAm ?? auftrag?.ortsterminAm;
    final otStr = otDate != null ? _df.format(otDate) : '—';
    final objektAdresse = [
      auftrag?.objektStrasse,
      [auftrag?.objektPlz, auftrag?.objektOrt]
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .join(' '),
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');

    final buf = StringBuffer();
    buf.writeln('3. Ortstermin');
    buf.writeln('| Datum: | $otStr |');
    buf.writeln('|---|---|');
    if (objektAdresse.isNotEmpty) {
      buf.writeln('| Ort: | Streitobjekt $objektAdresse |');
    }

    if (auftrag != null) {
      final beteiligte = decodeBeteiligte(auftrag.beteiligteJson);
      if (beteiligte.isNotEmpty) {
        buf.writeln();
        buf.writeln('Anwesende Personen');
        buf.writeln('| Funktion | Name |');
        buf.writeln('|---|---|');
        for (final b in beteiligte) {
          if (b.name.trim().isEmpty) continue;
          buf.writeln('| ${b.rolle.isEmpty ? "Beteiligte/r" : b.rolle} | ${b.name} |');
        }
      }
    }
    return buf.toString().trim();
  }
}
