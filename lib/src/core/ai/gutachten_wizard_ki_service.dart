import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/auth_service.dart';
import '../../features/akten/gutachten/gutachten_wysiwyg_embeds.dart';
import '../../features/system/einstellungen/einstellungen_repository.dart';
import 'ki_modelle.dart';
import 'ki_usage_service.dart';

class KiWizardFileInput {
  KiWizardFileInput({
    required this.filename,
    required this.mimeType,
    required this.bytes,
    required this.isPhoto,
    this.kategorie = 'Sonstige Unterlage',
    this.existingId,
  });

  final String filename;
  final String mimeType;
  final Uint8List bytes;
  final bool isPhoto;
  String kategorie;
  final int? existingId;
}

class KiWizardStammdaten {
  KiWizardStammdaten({
    this.art = 'gericht',
    this.betreff = '',
    this.bezeichnung = '',
    this.gerichtsAktenzeichen = '',
    this.gericht = '',
    this.gerichtsort = '',
    this.verfahrensart = 'Selbständiges Beweisverfahren',
    this.richter = '',
    this.klaeger = '',
    this.beklagter = '',
    this.streitwert,
    this.kostenvorschuss,
    this.beweisbeschlussVom = '',
    this.objektStrasse = '',
    this.objektPlz = '',
    this.objektOrt = '',
    this.objektart = '',
    this.baujahr = '',
    this.sachgebiet = '',
    this.kategorie = 'Mängelgutachten',
  });

  String art;
  String betreff;
  String bezeichnung;
  String gerichtsAktenzeichen;
  String gericht;
  String gerichtsort;
  String verfahrensart;
  String richter;
  String klaeger;
  String beklagter;
  double? streitwert;
  double? kostenvorschuss;
  String beweisbeschlussVom;
  String objektStrasse;
  String objektPlz;
  String objektOrt;
  String objektart;
  String baujahr;
  String sachgebiet;
  String kategorie;

  factory KiWizardStammdaten.fromJson(Map<String, dynamic> m) {
    double? parseNum(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      final s = v.toString().replaceAll('.', '').replaceAll(',', '.').trim();
      return double.tryParse(s);
    }

    return KiWizardStammdaten(
      art: (m['art'] ?? 'gericht').toString(),
      betreff: (m['betreff'] ?? '').toString(),
      bezeichnung: (m['bezeichnung'] ?? '').toString(),
      gerichtsAktenzeichen: (m['gerichtsAktenzeichen'] ?? '').toString(),
      gericht: (m['gericht'] ?? '').toString(),
      gerichtsort: (m['gerichtsort'] ?? '').toString(),
      verfahrensart: (m['verfahrensart'] ?? '').toString(),
      richter: (m['richter'] ?? '').toString(),
      klaeger: (m['klaeger'] ?? '').toString(),
      beklagter: (m['beklagter'] ?? '').toString(),
      streitwert: parseNum(m['streitwert']),
      kostenvorschuss: parseNum(m['kostenvorschuss']),
      beweisbeschlussVom: (m['beweisbeschlussVom'] ?? '').toString(),
      objektStrasse: (m['objektStrasse'] ?? '').toString(),
      objektPlz: (m['objektPlz'] ?? '').toString(),
      objektOrt: (m['objektOrt'] ?? '').toString(),
      objektart: (m['objektart'] ?? '').toString(),
      baujahr: (m['baujahr'] ?? '').toString(),
      sachgebiet: (m['sachgebiet'] ?? '').toString(),
      kategorie: (m['kategorie'] ?? 'Mängelgutachten').toString(),
    );
  }
}

class KiWizardBeteiligter {
  KiWizardBeteiligter({
    required this.rolle,
    this.anrede = '',
    required this.name,
    this.strasse = '',
    this.plz = '',
    this.ort = '',
    this.ihrZeichen = '',
    this.vertritt = '',
    this.selected = true,
  });

  String rolle;
  String anrede;
  String name;
  String strasse;
  String plz;
  String ort;
  String ihrZeichen;
  String vertritt;
  bool selected;

  factory KiWizardBeteiligter.fromJson(Map<String, dynamic> m) =>
      KiWizardBeteiligter(
        rolle: (m['rolle'] ?? 'Beteiligter').toString(),
        anrede: (m['anrede'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        strasse: (m['strasse'] ?? '').toString(),
        plz: (m['plz'] ?? '').toString(),
        ort: (m['ort'] ?? '').toString(),
        ihrZeichen: (m['ihrZeichen'] ?? '').toString(),
        vertritt: (m['vertritt'] ?? '').toString(),
      );
}

class KiWizardBeweisfrage {
  KiWizardBeweisfrage({
    required this.nr,
    required this.frage,
    this.einschaetzung = '',
  });

  String nr;
  String frage;
  String einschaetzung;

  factory KiWizardBeweisfrage.fromJson(Map<String, dynamic> m) =>
      KiWizardBeweisfrage(
        nr: (m['nr'] ?? '').toString(),
        frage: (m['frage'] ?? '').toString(),
        einschaetzung: (m['einschaetzung'] ?? '').toString(),
      );
}

class KiWizardFotoBefund {
  KiWizardFotoBefund({
    required this.fotoIndex,
    required this.dateiname,
    required this.titel,
    this.raum = '',
    required this.beschreibung,
    this.empfohlenerAbschnitt = '',
  });

  final int fotoIndex;
  final String dateiname;
  String titel;
  String raum;
  String beschreibung;
  String empfohlenerAbschnitt;

  factory KiWizardFotoBefund.fromJson(Map<String, dynamic> m) =>
      KiWizardFotoBefund(
        fotoIndex: (m['fotoIndex'] as num?)?.toInt() ?? 0,
        dateiname: (m['dateiname'] ?? '').toString(),
        titel: (m['titel'] ?? '').toString(),
        raum: (m['raum'] ?? '').toString(),
        beschreibung: (m['beschreibung'] ?? '').toString(),
        empfohlenerAbschnitt: (m['empfohlenerAbschnitt'] ?? '').toString(),
      );
}

class KiWizardNorm {
  KiWizardNorm({
    required this.nummer,
    this.ausgabe = '',
    required this.titel,
    this.kategorie = 'DIN / EN',
    this.selected = true,
  });

  String nummer;
  String ausgabe;
  String titel;
  String kategorie;
  bool selected;

  factory KiWizardNorm.fromJson(Map<String, dynamic> m) => KiWizardNorm(
        nummer: (m['nummer'] ?? '').toString(),
        ausgabe: (m['ausgabe'] ?? '').toString(),
        titel: (m['titel'] ?? '').toString(),
        kategorie: (m['kategorie'] ?? 'DIN / EN').toString(),
      );
}

class KiWizardResult {
  KiWizardResult({
    required this.stammdaten,
    required this.beteiligte,
    required this.beweisfragen,
    required this.fotoBefunde,
    required this.normen,
    required this.abschnitte,
    this.formelBloecke = const [],
  });

  final KiWizardStammdaten stammdaten;
  final List<KiWizardBeteiligter> beteiligte;
  final List<KiWizardBeweisfrage> beweisfragen;
  final List<KiWizardFotoBefund> fotoBefunde;
  final List<KiWizardNorm> normen;
  final Map<String, String> abschnitte;
  final List<AwFormulaData> formelBloecke;
}

Schema _buildWizardSchema() => Schema.object(
      properties: {
        'stammdaten': Schema.object(
          properties: {
            'art': Schema.string(
                description: "'gericht' (Gerichtsgutachten) oder 'privat' (Privatgutachten)"),
            'betreff': Schema.string(
                description: 'Kurzer prägnanter Betreff / Beweisthema der Akte'),
            'bezeichnung': Schema.string(
                description: 'Titel des Gutachtens (z. B. Gutachten über Mängel an Balkongeländer und Fassade)'),
            'gerichtsAktenzeichen': Schema.string(
                description: 'Gerichtliches Aktenzeichen (z. B. 4 O 218/25 oder 12 OH 45/25)'),
            'gericht': Schema.string(
                description: 'Name des Gerichts (z. B. Landgericht Darmstadt)'),
            'gerichtsort': Schema.string(description: 'Ort des Gerichts'),
            'verfahrensart': Schema.string(
                description: 'z. B. Selbständiges Beweisverfahren oder Zivilprozess'),
            'richter': Schema.string(
                description: 'Name des Richters / der Richterin'),
            'klaeger': Schema.string(
                description: 'Name des Klägers / Antragstellers'),
            'beklagter': Schema.string(
                description: 'Name des Beklagten / Antragsgegners'),
            'streitwert': Schema.number(
                description: 'Streitwert in Euro (falls genannt, sonst 0)'),
            'kostenvorschuss': Schema.number(
                description: 'Auslagenvorschuss / Kostenvorschuss in Euro (falls genannt, sonst 0)'),
            'beweisbeschlussVom': Schema.string(
                description: 'Datum des Beweisbeschlusses im Format YYYY-MM-DD (falls bekannt)'),
            'objektStrasse': Schema.string(
                description: 'Straße und Hausnummer des Begutachtungsobjekts'),
            'objektPlz': Schema.string(description: 'PLZ des Objekts'),
            'objektOrt': Schema.string(description: 'Ort des Objekts'),
            'objektart': Schema.string(
                description: 'z. B. Mehrfamilienhaus, Bürogebäude, Einfamilienhaus'),
            'baujahr': Schema.string(description: 'Baujahr oder Ausführungsjahr'),
            'sachgebiet': Schema.string(
                description: 'Technisches Sachgebiet (z. B. Metallbau / Fassadenbau / Hochbau)'),
            'kategorie': Schema.string(
                description: 'z. B. Gerichtsgutachten / Mängelgutachten'),
          },
        ),
        'beteiligte': Schema.array(
          description: 'Alle erkannten Verfahrensbeteiligten (Kläger, Beklagter, Prozessbevollmächtigte / Rechtsanwälte, Streitverkündete)',
          items: Schema.object(
            properties: {
              'rolle': Schema.string(
                  description: 'z. B. Kläger, Beklagter, Prozessbevollmächtigter Kläger, Prozessbevollmächtigter Beklagter'),
              'anrede': Schema.string(description: 'Herr, Frau oder Kanzlei/Firma'),
              'name': Schema.string(description: 'Vollständiger Name oder Kanzleiname'),
              'strasse': Schema.string(description: 'Straße und Hausnummer'),
              'plz': Schema.string(description: 'Postleitzahl'),
              'ort': Schema.string(description: 'Ort'),
              'ihrZeichen': Schema.string(description: 'Aktenzeichen der Kanzlei (falls bekannt)'),
              'vertritt': Schema.string(description: 'Wen vertritt dieser Beteiligte?'),
            },
          ),
        ),
        'beweisfragen': Schema.array(
          description: 'Wortgetreu extrahierte Beweisfragen aus dem Beweisbeschluss oder Gutachtenauftrag',
          items: Schema.object(
            properties: {
              'nr': Schema.string(description: 'Nummer der Frage (z. B. 1., 2.1.1)'),
              'frage': Schema.string(description: 'Wortwörtlicher Text der Beweisfrage'),
              'einschaetzung': Schema.string(
                  description: 'Kurze sachverständige Einschätzung (z. B. Unproblematisch beantwortbar / Hinweis auf Rechtsfrage)'),
            },
          ),
        ),
        'fotoBefunde': Schema.array(
          description: 'Technische Auswertung jedes hochgeladenen Fotos (in der Reihenfolge der übergebenen Fotos 0..N-1)',
          items: Schema.object(
            properties: {
              'fotoIndex': Schema.integer(description: '0-basierter Index des Fotos'),
              'dateiname': Schema.string(description: 'Dateiname des Fotos'),
              'titel': Schema.string(
                  description: 'Prägnanter fachtechnischer Bildtitel (z. B. Befestigung Geländerpfosten auf Balkonplatte)'),
              'raum': Schema.string(
                  description: 'Bauteil oder Ort (z. B. Balkon OG, Pfosten-Riegel-Fassade EG)'),
              'beschreibung': Schema.string(
                  description: 'Sachliche technische Befundbeschreibung dessen, was auf dem Foto erkennbar ist'),
              'empfohlenerAbschnitt': Schema.string(
                  description: "'s_objekt', 's_feststellungen' oder '' (für allgemeine Lichtbildanlage)"),
            },
          ),
        ),
        'normen': Schema.array(
          description: 'Einschlägige DIN-/EN-Normen, Richtlinien und Fachregeln für diesen Fall',
          items: Schema.object(
            properties: {
              'nummer': Schema.string(
                  description: 'Normnummer (z. B. DIN 18065, DIN EN 1991-1-1/NA, DIN EN ISO 1461, DIN 4108-2, RAL-Montageleitfaden)'),
              'ausgabe': Schema.string(description: 'Ausgabedatum falls bekannt (z. B. 2020-08)'),
              'titel': Schema.string(description: 'Titel der Norm oder Richtlinie'),
              'kategorie': Schema.string(description: 'DIN / EN, Richtlinie oder Herstellervorschrift'),
            },
          ),
        ),
        'abschnitte': Schema.object(
          description: 'Vollständig ausformulierte Gutachten-Abschnitte nach Zöller im professionellen Gerichtsgutachten-Stil (inkl. Markdown-Tabellen | ... | für Soll-/Ist-Vergleiche und Kostenschätzung)',
          properties: {
            's_auftrag': Schema.string(
                description: 'I. Auftrag und Beweisfragen (Herleitung des Auftrags, Beweisbeschluss, wortgetreue Gliederung der Beweisfragen)'),
            's_grundlage': Schema.string(
                description: 'II. Grundlagen des Gutachtens (1. Verwendete Arbeits- und Hilfsmittel, 2. Ortsbesichtigung, 3. Hinweise und Vorbehalte)'),
            's_situation': Schema.string(
                description: 'III. Allgemeine Angaben zur Situation und Vorgeschichte'),
            's_objekt': Schema.string(
                description: 'Objekt- und Konstruktionsbeschreibung der untersuchten Bauteile'),
            's_beteiligte_aussagen': Schema.string(
                description: 'Angaben der Beteiligten beim Ortstermin (sauber getrennt von eigenen Feststellungen)'),
            's_feststellungen': Schema.string(
                description: 'IV. Tatsächliche Feststellungen, Befund und technische Bewertung (gegliedert in IV.1, IV.2 ..., mit Markdown-Tabellen | Merkmal | Soll | Ist | Bewertung |)'),
            's_bewertung': Schema.string(
                description: 'Zusammenfassende sachverständige technische Würdigung (Soll-Ist-Abgleich nach den anerkannten Regeln der Technik)'),
            's_maengel': Schema.string(
                description: 'Strukturierte Übersichtstabelle und Auflistung der festgestellten technischen Abweichungen / Mängel'),
            's_massnahmen': Schema.string(
                description: 'Erforderliche Maßnahmen zur Instandsetzung / Sanierungsvarianten (inkl. Variantenvergleich als Markdown-Tabelle)'),
            's_kosten': Schema.string(
                description: 'Kostenschätzung der Mängelbeseitigung mit sauberer Markdown-Tabelle (| Pos. | Leistungsbeschreibung | Menge | Einheit | EP (€) | GP (€) |) sowie Zwischensumme, USt. und Gesamtsumme (brutto)'),
            's_verantwortlichkeit': Schema.string(
                description: 'Technische Zuordnung der Ursachen (Planung, Ausführung, Vorleistung) ohne unzulässige Rechtswürdigung'),
            's_beweisfragen': Schema.string(
                description: 'V. Beantwortung der Beweisfragen (jede Frage einzeln mit Überschrift "Beantwortung der Beweisfrage ..." präzise und vollständig beantwortet)'),
            's_fazit': Schema.string(
                description: 'VI. Zusammenfassung / Fazit und Schlusserklärung (§ 407a ZPO)'),
          },
        ),
        'formelBloecke': Schema.array(
          description:
              'Mathematische, statische oder bauphysikalische Nachweis- und Formelblöcke (werden als visuelle Rechenkarten in den Ziel-Abschnitt eingefügt, z. B. Tragfähigkeitsnachweis, Betonausbruch, U-Wert / f_Rsi-Nachweis, Toleranznachweis)',
          items: Schema.object(
            properties: {
              'abschnittKey': Schema.string(
                  description:
                      "Ziel-Abschnitt, z. B. 's_feststellungen' oder 's_bewertung'"),
              'title': Schema.string(
                  description:
                      'Überschrift des Formelblocks (z. B. Plausibilitätsprüfung Einzelpfosten QR 40×3 mm)'),
              'subtitle': Schema.string(
                  description:
                      'System- und Randbedingungen (z. B. Kragträger h = 950 mm, S235JR, Pfostenabstand e = 1,10 m)'),
              'steps': Schema.array(
                items: Schema.object(
                  properties: {
                    'header': Schema.string(
                        description:
                            'Rechenschritt-Überschrift (z. B. 1. Querschnittswerte oder 2. Schnittgrößen und Auslastung)'),
                    'bullets': Schema.array(
                      items: Schema.object(
                        properties: {
                          'label': Schema.string(
                              description:
                                  'Bezeichnung der Größe (z. B. Flächenträgheitsmoment oder Querschnittsauslastung)'),
                          'expr': Schema.string(
                              description:
                                  'Formel und eingesetzte Zahlenwerte (z. B. I = (40^4 - 34^4) / 12 = 101.972 oder η = M_Ed / M_pl,Rd = 1,57 / 1,44 = 109)'),
                          'unit': Schema.string(
                              description: 'Einheit (z. B. mm^4, kNm, %)'),
                          'badge': Schema.string(
                              description:
                                  'Optionales Prüfergebnis-Badge (z. B. rechnerisch tragfähig oder rechnerische Überlastung)'),
                          'badgeColor': Schema.string(
                              description: "'green', 'red' oder 'amber'"),
                        },
                      ),
                    ),
                  },
                ),
              ),
              'conclusion': Schema.string(
                  description:
                      'Technisches Fazit des Rechennachweises in 1–2 Sätzen'),
            },
          ),
        ),
      },
    );

Future<KiWizardResult> analysiereUnterlagenFuerGutachten({
  required WidgetRef ref,
  required List<KiWizardFileInput> files,
  required String freitextNotizen,
  void Function(String statusText)? onStatus,
}) async {
  onStatus?.call('KI-Modell wird vorbereitet …');
  final repo = ref.read(einstellungenRepositoryProvider);
  final sachgebiet = await repo.getOr(SettingsKeys.svSachgebiet, 'Bauwesen / Metallbau / Fassadenbau');
  final modellId = await getKiModell(repo, KiAufgabe.juristisch);

  final systemPrompt = '''
Du bist ein öffentlich bestellter und vereidigter Sachverständiger (Sachgebiet: "$sachgebiet") und erstellst ein gerichtsfestes Sachverständigengutachten nach dem Goldstandard von Zöller (exakt wie unser Referenz-Mustergutachten).
Analysiere alle hochgeladenen Unterlagen (Beweisbeschluss, Gerichtsakten, Schriftsätze, Pläne, Angebote, Messprotokolle), alle hochgeladenen Fotos sowie die Stichpunkte des Sachverständigen.

Deine Aufgabe:
1. Extrahiere alle Akten- und Verfahrensstammdaten (Gericht, Aktenzeichen, Kläger, Beklagter, Richter, Streitwert, Vorschuss, Objektadresse, Baujahr, Objektart).
2. Extrahiere alle Beteiligten (Kläger, Beklagter, Rechtsanwälte / Prozessbevollmächtigte mit Anschrift und Zeichen).
3. Extrahiere alle Beweisfragen wortwörtlich aus dem Beweisbeschluss / Auftrag.
4. Werte jedes übergebene Foto fachtechnisch aus (prägnanter Fachtitel, Raum/Bauteil, sachliche Befundbeschreibung, empfohlener Abschnitt `s_objekt` oder `s_feststellungen`).
5. Bestimme alle einschlägigen DIN-/EN-Normen, technischen Richtlinien (z. B. HBO, ASR A2.1, H-VV TB, DIN 18065, DIN EN 1991-1-1/NA, DIN EN 1993-1-1, DIN EN ISO 1461, DIN 18008, DIN 4108-2, RAL-Leitfaden) und Herstellervorschriften.
6. Erstelle für technische/statische/bauphysikalische Berechnungen strukturierte Einträge in `formelBloecke` (mit `title`, `subtitle`, `steps` inkl. `label`, `expr`, `unit`, `badge`, `badgeColor` und `conclusion`), damit diese automatisch als visuelle Formel-Karten gerendert werden.
7. Formuliere alle 13 Gutachten-Abschnitte (`abschnitte`) so hochwertig, präzise, sachlich und strukturiert aus, dass daraus direkt ein druckfertiges Gerichtsgutachten auf Referenz-Niveau entsteht:
   - Zitiere Akten- und Dokumentenfundstellen im Text mit `[A1]`, `[A1, S. ...]`, `[A2]`, Feststellungen vom Ortstermin mit `[OT]` und Normen/Fachregeln mit `[Q1]`, `[Q2]` usw. (unsere Verzeichnis-Engine und PDF-Quellenmarkierung verlinken diese automatisch).
   - `s_auftrag` (I. Auftrag und Beweisfragen): Herleitung des Auftrags, Beweisbeschluss und vollständige, wortgetreue Gliederung der Beweisfragen.
   - `s_grundlage` (II. Grundlagen des Gutachtens): Schreibe hier insbesondere den Abschnitt `3. Ortstermin` mit Markdown-Tabelle (`| Datum: | ... |`, `| Ort: | ... |`), Tabelle `Anwesende Personen` (`| Funktion | Name |`), `Feststellungen und Maßnahmen beim Ortstermin` und `Hinweis zu Bauteilöffnungen`. (Die Abschnitte `1. Akten und Unterlagen`, `2. Gesetze, Regelwerke und Fachquellen` sowie `4. Abkürzungen und Formelzeichen` werden automatisch ergänzt.)
   - `s_situation` & `s_objekt` (III. Situation und Objektbeschreibung): `1. Allgemeines zum Objekt` und `2. Beschreibung der untersuchten Bauteile` (`2.1 ...`, `2.2 ...`).
   - `s_feststellungen` (IV. Sachverhalte): Gegliedert in `A. ...`, `B. ...` und nummerierte Unterabschnitte `IV.1 ...`, `IV.2 ...`, jeweils mit `Feststellungen` (inkl. Markdown-Messwerttabellen `| Messstelle | Ist | Soll | Abweichung | Bewertung |`) und `Technische Bewertung` (Soll-Ist-Abgleich nach den a. R. d. T.).
   - `s_massnahmen` & `s_kosten`: Sanierungskonzept mit Markdown-Tabelle `Systematischer Variantenvergleich` (`| Leistungsbereich | Teilsanierung / Reparatur | Komplettaustausch |`) sowie detaillierte Kostenschätzung als Markdown-Tabelle (`| Pos. | Leistungsbeschreibung | Menge | Einheit | EP (€) | GP (€) |`) inkl. Netto-Summe, 19 % USt. und Brutto-Gesamtsumme.
   - `s_beweisfragen` (V. Beantwortung der Beweisfragen): Jede Beweisfrage einzeln mit Überschrift `Beantwortung der Beweisfrage ...`, Wiederholung der Frage und strukturierter `Antwort:`.
   - `s_fazit` (VI. Zusammenfassung / Fazit): Prägnante Zusammenfassung und abschließende `Schlusserklärung (§ 407a ZPO)`.
   - Erfinde keine Fakten, die den Unterlagen widersprechen; wo Maße oder Kosten aus den Angaben abgeleitet oder geschätzt werden, kennzeichne sie sachgerecht als sachverständige Kostenschätzung bzw. Plausibilitätsangabe.
''';

  final model = getVertexGenerativeModel(
    modelId: modellId,
    systemInstruction: Content.system(systemPrompt),
    generationConfig: GenerationConfig(
      temperature: 0.2,
      maxOutputTokens: 16384,
      responseMimeType: 'application/json',
      responseSchema: _buildWizardSchema(),
    ),
  );

  final parts = <Part>[];
  final docFiles = files.where((f) => !f.isPhoto).toList();
  final photoFiles = files.where((f) => f.isPhoto).toList();

  final introBuf = StringBuffer()
    ..writeln('Bitte werte die folgenden Unterlagen, Fotos und Sachverständigen-Notizen vollständig aus und erstelle den kompletten Gutachten-Datensatz.')
    ..writeln('Anzahl Dokumente: ${docFiles.length}')
    ..writeln('Anzahl Fotos: ${photoFiles.length}');

  if (freitextNotizen.trim().isNotEmpty) {
    introBuf
      ..writeln('\n--- STICHPUNKTE / ORTSTERMIN-NOTIZEN DES SACHVERSTÄNDIGEN ---')
      ..writeln(freitextNotizen.trim())
      ..writeln('--- ENDE NOTIZEN ---\n');
  }

  parts.add(TextPart(introBuf.toString()));

  for (var i = 0; i < docFiles.length; i++) {
    final doc = docFiles[i];
    onStatus?.call('Lese Unterlage ${i + 1}/${docFiles.length}: ${doc.filename} …');
    parts.add(TextPart('UNTERLAGE [A${i + 1}] (${doc.kategorie}): Dateiname="${doc.filename}"'));
    // PDFs und Bilder bis 18 MB als InlineDataPart übergeben
    if (doc.bytes.isNotEmpty && doc.bytes.length <= 18 * 1024 * 1024) {
      parts.add(InlineDataPart(doc.mimeType, doc.bytes));
    }
  }

  for (var i = 0; i < photoFiles.length; i++) {
    final photo = photoFiles[i];
    onStatus?.call('Analysiere Foto ${i + 1}/${photoFiles.length}: ${photo.filename} …');
    parts.add(TextPart('FOTO Index=$i (Lichtbild ${i + 1}): Dateiname="${photo.filename}"'));
    if (photo.bytes.isNotEmpty && photo.bytes.length <= 12 * 1024 * 1024) {
      parts.add(InlineDataPart(photo.mimeType, photo.bytes));
    }
  }

  onStatus?.call('KI erstellt strukturierten Akten- & Gutachten-Datensatz …');
  final response = await model.generateContent([Content.multi(parts)]);

  try {
    final logger = ref.read(kiUsageLoggerProvider);
    final email = ref.read(authServiceProvider).currentUser?.email;
    await logger.log(
      aufgabe: KiAufgabe.juristisch,
      modellId: modellId,
      usage: response.usageMetadata,
      userEmail: email,
    );
  } catch (_) {}

  var raw = (response.text ?? '').trim();
  raw = raw
      .replaceAll(RegExp(r'^```json\s*'), '')
      .replaceAll(RegExp(r'\s*```$'), '');
  if (raw.isEmpty) {
    throw Exception('Leere Antwort vom KI-Modell.');
  }

  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw Exception('Ungültiges JSON-Format vom KI-Modell.');
  }

  final stammdaten = KiWizardStammdaten.fromJson(
    (decoded['stammdaten'] as Map?)?.cast<String, dynamic>() ?? const {},
  );

  final beteiligte = ((decoded['beteiligte'] as List?) ?? const [])
      .whereType<Map>()
      .map((m) => KiWizardBeteiligter.fromJson(m.cast<String, dynamic>()))
      .where((b) => b.name.trim().isNotEmpty)
      .toList();

  final beweisfragen = ((decoded['beweisfragen'] as List?) ?? const [])
      .whereType<Map>()
      .map((m) => KiWizardBeweisfrage.fromJson(m.cast<String, dynamic>()))
      .where((q) => q.frage.trim().isNotEmpty)
      .toList();

  final rawFotoBefunde = ((decoded['fotoBefunde'] as List?) ?? const [])
      .whereType<Map>()
      .map((m) => KiWizardFotoBefund.fromJson(m.cast<String, dynamic>()))
      .toList();

  // Sicherstellen, dass jedes hochgeladene Foto einen Eintrag hat
  final fotoBefunde = <KiWizardFotoBefund>[];
  for (var i = 0; i < photoFiles.length; i++) {
    final match = rawFotoBefunde
        .where((f) => f.fotoIndex == i)
        .firstOrNull ??
        (i < rawFotoBefunde.length ? rawFotoBefunde[i] : null);
    fotoBefunde.add(
      KiWizardFotoBefund(
        fotoIndex: i,
        dateiname: photoFiles[i].filename,
        titel: (match != null && match.titel.trim().isNotEmpty)
            ? match.titel.trim()
            : 'Lichtbild ${i + 1}: ${photoFiles[i].filename}',
        raum: match?.raum.trim() ?? '',
        beschreibung: match?.beschreibung.trim() ?? '',
        empfohlenerAbschnitt: match?.empfohlenerAbschnitt.trim() ?? 's_feststellungen',
      ),
    );
  }

  final normen = ((decoded['normen'] as List?) ?? const [])
      .whereType<Map>()
      .map((m) => KiWizardNorm.fromJson(m.cast<String, dynamic>()))
      .where((n) => n.nummer.trim().isNotEmpty)
      .toList();

  final rawAbschnitte =
      (decoded['abschnitte'] as Map?)?.cast<String, dynamic>() ?? const {};
  final abschnitte = <String, String>{};
  for (final entry in rawAbschnitte.entries) {
    final val = (entry.value ?? '').toString().trim();
    if (val.isNotEmpty) {
      abschnitte[entry.key] = val;
    }
  }

  // Formelblöcke parsen und als [[FORMEL_BLOCK_JSON:...]] in den jeweiligen Ziel-Abschnitt einbetten
  final rawFormeln = ((decoded['formelBloecke'] as List?) ?? const [])
      .whereType<Map>();
  final formelBloecke = <AwFormulaData>[];
  for (final m in rawFormeln) {
    final map = m.cast<String, dynamic>();
    final title = (map['title'] ?? '').toString().trim();
    final subtitle = (map['subtitle'] ?? '').toString().trim();
    final fullTitle = [
      if (title.isNotEmpty) title,
      if (subtitle.isNotEmpty) '($subtitle)',
    ].join(' ');
    final rows = <AwFormulaRow>[];
    final steps = (map['steps'] as List?)?.whereType<Map>() ?? const [];
    for (final s in steps) {
      final header = (s['header'] ?? '').toString().trim();
      final bullets = (s['bullets'] as List?)?.whereType<Map>() ?? const [];
      for (final b in bullets) {
        final label = (b['label'] ?? header).toString().trim();
        final expr = (b['expr'] ?? '').toString().trim();
        final unit = (b['unit'] ?? '').toString().trim();
        final badge = (b['badge'] ?? '').toString().trim();
        if (expr.isEmpty) continue;
        final fullExpr = [
          expr,
          if (unit.isNotEmpty && !expr.endsWith(unit)) unit,
          if (badge.isNotEmpty) '($badge)',
        ].join(' ');
        rows.add(AwFormulaRow(label: label, expression: fullExpr));
      }
    }
    final conclusion = (map['conclusion'] ?? '').toString().trim();
    if (conclusion.isNotEmpty) {
      rows.add(AwFormulaRow(label: 'Ergebnis', expression: conclusion));
    }
    if (rows.isEmpty) continue;
    final formula = AwFormulaData(
      title: fullTitle.isNotEmpty ? fullTitle : 'Technischer Rechennachweis',
      rows: rows,
    );
    formelBloecke.add(formula);
    final targetKey =
        (map['abschnittKey'] ?? 's_feststellungen').toString().trim();
    final effectiveKey = targetKey.isNotEmpty ? targetKey : 's_feststellungen';
    final placeholder = formula.toMarkerString();
    final existing = abschnitte[effectiveKey] ?? '';
    if (!existing.contains(placeholder)) {
      abschnitte[effectiveKey] =
          existing.isEmpty ? placeholder : '$existing\n\n$placeholder';
    }
  }

  return KiWizardResult(
    stammdaten: stammdaten,
    beteiligte: beteiligte,
    beweisfragen: beweisfragen,
    fotoBefunde: fotoBefunde,
    normen: normen,
    abschnitte: abschnitte,
    formelBloecke: formelBloecke,
  );
}
