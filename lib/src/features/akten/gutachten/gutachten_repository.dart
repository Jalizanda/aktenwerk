import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Strukturelles Kurz-/Langlabel der 13 Zöller-Abschnitte (+ Anlagen) —
/// Reihenfolge 1:1 wie in der Original-SV-Software.
class GutachtenAbschnitt {
  /// Interner Key für die JSON-Map (z. B. `s_auftrag`).
  final String key;

  /// Reihenfolge 1–13 bzw. `-1` für Anlagen.
  final int nummer;

  /// Voll ausgeschriebenes Label.
  final String label;

  /// Sektion: 'basis' | 'sachverhalt' | 'abschluss'.
  final String gruppe;

  /// Anzahl Zeilen im Editor.
  final int rows;

  /// Vorgeschlagener Placeholder im Eingabefeld.
  final String? placeholder;

  /// Kategorie-Key für die Textbaustein-Filterung.
  final String textbausteinKategorie;

  const GutachtenAbschnitt({
    required this.key,
    required this.nummer,
    required this.label,
    required this.gruppe,
    required this.rows,
    this.placeholder,
    required this.textbausteinKategorie,
  });
}

/// Die 13 Zöller-Abschnitte + Anlagenverzeichnis.
const List<GutachtenAbschnitt> gutachtenAbschnitte = [
  GutachtenAbschnitt(
    key: 's_auftrag',
    nummer: 1,
    label: 'Auftrag und Beweisthema',
    gruppe: 'basis',
    rows: 5,
    textbausteinKategorie: 'auftrag',
  ),
  GutachtenAbschnitt(
    key: 's_grundlage',
    nummer: 2,
    label: 'Grundlage des Gutachtens',
    gruppe: 'basis',
    rows: 6,
    textbausteinKategorie: 'grundlage',
    placeholder:
        'Ortsbesichtigung, Urkunden, Tech. Empfehlungen, Literatur …',
  ),
  GutachtenAbschnitt(
    key: 's_situation',
    nummer: 3,
    label: 'Allgemeine Angaben zur Situation',
    gruppe: 'basis',
    rows: 5,
    placeholder:
        'Umgebung, Art des Gebäudes, Stockwerke, Lage, Ausrichtung …',
    textbausteinKategorie: 'situation',
  ),
  GutachtenAbschnitt(
    key: 's_objekt',
    nummer: 4,
    label: 'Objektbeschreibung (Konstruktion)',
    gruppe: 'basis',
    rows: 5,
    textbausteinKategorie: 'objekt',
  ),
  GutachtenAbschnitt(
    key: 's_beteiligte_aussagen',
    nummer: 5,
    label: 'Angaben von Beteiligten (Protokoll vor Ort)',
    gruppe: 'basis',
    rows: 3,
    placeholder:
        'Wer hat was wozu gesagt? (sauber abgegrenzt von eigenen Feststellungen)',
    textbausteinKategorie: 'beteiligte',
  ),
  GutachtenAbschnitt(
    key: 's_feststellungen',
    nummer: 6,
    label: 'Tatsächliche Feststellungen / Befund',
    gruppe: 'sachverhalt',
    rows: 8,
    textbausteinKategorie: 'feststellungen',
  ),
  GutachtenAbschnitt(
    key: 's_bewertung',
    nummer: 7,
    label: 'Sachverständige Würdigung / Bewertung',
    gruppe: 'sachverhalt',
    rows: 8,
    textbausteinKategorie: 'bewertung',
  ),
  GutachtenAbschnitt(
    key: 's_maengel',
    nummer: 8,
    label: 'Mängelliste / Schadenspositionen',
    gruppe: 'sachverhalt',
    rows: 5,
    textbausteinKategorie: 'maengel',
  ),
  GutachtenAbschnitt(
    key: 's_massnahmen',
    nummer: 9,
    label: 'Maßnahmen zur Instandsetzung',
    gruppe: 'sachverhalt',
    rows: 5,
    placeholder:
        'Variantenbildung, Vergleich Aufwand/Nutzen, kein Übermaß …',
    textbausteinKategorie: 'massnahmen',
  ),
  GutachtenAbschnitt(
    key: 's_kosten',
    nummer: 10,
    label: 'Kostenschätzung / Mängelbeseitigung',
    gruppe: 'sachverhalt',
    rows: 5,
    textbausteinKategorie: 'kosten',
  ),
  GutachtenAbschnitt(
    key: 's_verantwortlichkeit',
    nummer: 11,
    label: 'Verantwortlichkeit (übliche Maßstäbe)',
    gruppe: 'sachverhalt',
    rows: 5,
    placeholder:
        'Branchenübliche Selbstverständlichkeiten, keine juristische Würdigung …',
    textbausteinKategorie: 'verantwortlichkeit',
  ),
  GutachtenAbschnitt(
    key: 's_beweisfragen',
    nummer: 12,
    label: 'Beantwortung der Beweisfragen',
    gruppe: 'abschluss',
    rows: 6,
    textbausteinKategorie: 'beweisfragen',
  ),
  GutachtenAbschnitt(
    key: 's_fazit',
    nummer: 13,
    label: 'Zusammenfassung / Fazit',
    gruppe: 'abschluss',
    rows: 5,
    textbausteinKategorie: 'fazit',
  ),
  GutachtenAbschnitt(
    key: 's_anlagen',
    nummer: -1,
    label: 'Anlagenverzeichnis',
    gruppe: 'abschluss',
    rows: 3,
    placeholder:
        'eine Anlage pro Zeile, z. B. „Anlage 1 – Lichtbilddokumentation"',
    textbausteinKategorie: 'anlagen',
  ),
];

/// ----------- Vorlagen -----------

const gutachtenVorlagen = <String, Map<String, String>>{
  'bauschaden': {
    's_auftrag':
        'Der Auftraggeber {{auftraggeber}} hat den Sachverständigen mit der Begutachtung des oben genannten Schadens beauftragt. Gegenstand des Auftrags ist die Feststellung von Schadensumfang, -ursache sowie eine Schätzung der Kosten zur Schadensbeseitigung am Objekt {{objekt}}.',
    's_objekt':
        'Bei dem zu begutachtenden Objekt handelt es sich um {{objektart}}, Baujahr {{baujahr}}, gelegen {{objekt}}. Die Begehung erfolgte am {{ortstermin}} in Anwesenheit von …',
    's_feststellungen':
        '1. Beim Ortstermin wurden folgende Feststellungen getroffen:\n\na) …\nb) …\nc) …\n\n2. Eine Lichtbilddokumentation ist als Anlage 1 beigefügt.',
    's_bewertung':
        'Die festgestellten Schäden sind nach Auffassung des Unterzeichners auf folgende Ursachen zurückzuführen:\n\n- …\n- …\n\nEine sach- und fachgerechte Ausführung gemäß dem zum Zeitpunkt der Errichtung anerkannten Stand der Technik liegt insoweit nicht vor.',
    's_maengel':
        'Mangel 1: …\nUrsache: …\nBeseitigung: …\n\nMangel 2: …\nUrsache: …\nBeseitigung: …',
    's_kosten':
        'Die voraussichtlichen Kosten zur sach- und fachgerechten Beseitigung der vorgenannten Mängel werden nach Erfahrungswerten und marktüblichen Preisen wie folgt geschätzt (netto):\n\nPos. 1 …………………………… €\nPos. 2 …………………………… €\n_________________________\nGesamt netto:  ………… €\nzzgl. MwSt. 19 %\nGesamt brutto: ………… €',
    's_fazit':
        'Aufgrund der vorgenannten Feststellungen kommt der Unterzeichner zu folgendem Ergebnis: …',
    's_anlagen':
        'Anlage 1 – Lichtbilddokumentation\nAnlage 2 – Lageplan / Grundriss\nAnlage 3 – Korrespondenz',
  },
  'beweissicherung': {
    's_auftrag':
        'Mit Beweisbeschluss des {{gericht}} vom {{beweisbeschluss1}} (Geschäftszeichen: {{azExtern}}) wurde der Unterzeichner mit der Erstellung eines Sachverständigengutachtens beauftragt. Gegenstand der Begutachtung ist {{betreff}}.',
    's_objekt':
        'Das streitgegenständliche Objekt {{objekt}} ist {{objektart}}, Baujahr {{baujahr}}.',
    's_feststellungen':
        'Die Begehung des Objekts erfolgte am {{ortstermin}}. Anwesend waren neben dem Unterzeichner: …\n\nIm Rahmen der Begehung wurden die folgenden Feststellungen getroffen und photographisch dokumentiert (Anlage 1):\n\na) …\nb) …\nc) …',
    's_bewertung':
        'Eine sachverständige Würdigung der Feststellungen führt zu folgender Bewertung:\n\n…',
    's_beweisfragen':
        'Zur Beantwortung der im Beweisbeschluss gestellten Fragen führt der Unterzeichner aus:\n\nFrage 1: …\nAntwort: …\n\nFrage 2: …\nAntwort: …',
    's_kosten':
        'Die Kosten zur sach- und fachgerechten Beseitigung der festgestellten Mängel werden auf netto …………… € geschätzt.',
    's_fazit': 'Zusammenfassend kommt der Unterzeichner zu folgendem Ergebnis: …',
    's_anlagen':
        'Anlage 1 – Lichtbilddokumentation\nAnlage 2 – Auszug aus dem Beweisbeschluss',
  },
  'maengel': {
    's_auftrag':
        'Der Auftraggeber {{auftraggeber}} hat den Sachverständigen mit der Feststellung und Bewertung von Mängeln am Objekt {{objekt}} beauftragt.',
    's_objekt':
        '{{objektart}}, Baujahr {{baujahr}}, gelegen {{objekt}}.',
    's_feststellungen':
        'Im Rahmen des Ortstermins am {{ortstermin}} wurden folgende Mängel festgestellt: …',
    's_bewertung': 'Die festgestellten Mängel stellen … dar.',
    's_maengel': '1. …\n2. …\n3. …',
    's_kosten':
        'Die Kosten der Mängelbeseitigung werden geschätzt auf …………… € netto.',
    's_anlagen': 'Anlage 1 – Lichtbilddokumentation',
  },
};

/// ----------- Sprach-Check (Zöller-konform) -----------

class SprachRegel {
  final RegExp pattern;
  final String hinweis;
  const SprachRegel(this.pattern, this.hinweis);
}

final List<SprachRegel> sprachRegeln = [
  SprachRegel(
    RegExp(
      r'\b(ordnungsgemäß|fach- und sachgerecht|fachgerecht|sachgerecht|allgemein anerkannte Regeln der Technik)\b',
      caseSensitive: false,
    ),
    'Floskel — bitte konkret beschreiben, welche Regel/welcher Standard verletzt ist.',
  ),
  SprachRegel(
    RegExp(r'\bDIN-gerecht\b', caseSensitive: false),
    '„DIN-gerecht" ist eine Floskel — bitte die konkrete DIN nennen.',
  ),
  SprachRegel(
    RegExp(r'\bIsolierung|isolier(t|en|ung)\b', caseSensitive: false),
    '„Isolierung" ist mehrdeutig — präzise: „Abdichtung" (gegen Wasser), '
        '„Wärmedämmung", „Schalldämmung" oder „elektrische Isolierung".',
  ),
  SprachRegel(
    RegExp(r'\bsanier(en|ung|t)\b', caseSensitive: false),
    '„Sanierung" ist unbestimmt — präziser: „Instandsetzung", '
        '„Modernisierung", „Erneuerung" oder „Wartung".',
  ),
  SprachRegel(
    RegExp(
      r'\b(zunehmende|hinzukommende)\s+Unregelmäßigkeit',
      caseSensitive: false,
    ),
    'Vermeide den Begriff „Unregelmäßigkeit" — siehe Zöller. '
        'Nutze „Mangel" (rechtlich) oder „Fehler" (technisch).',
  ),
  SprachRegel(
    RegExp(
      r'\b(unterzeichnet|der\s+Unterzeichner|Unterfertigte)\b',
      caseSensitive: false,
    ),
    '„Der Unterzeichner" wirkt unpersönlich — laut Zöller besser Ich-Form verwenden.',
  ),
  SprachRegel(
    RegExp(
      r'\bman\s+(stellt|sieht|erkennt|betritt)\b',
      caseSensitive: false,
    ),
    'Vermeide das unpersönliche „man" — passive Form oder Ich-Form ist klarer.',
  ),
  SprachRegel(
    RegExp(
      r'\b(Unparteilichkeit|nach\s+bestem\s+Wissen\s+und\s+Gewissen)\b',
      caseSensitive: false,
    ),
    'Floskel — Unparteilichkeit ist Selbstverständlichkeit; '
        'eine Beteuerung weckt eher Misstrauen.',
  ),
];

class SprachCheckTreffer {
  final String abschnittKey;
  final String abschnittLabel;
  final String fundstelle;
  final String hinweis;
  const SprachCheckTreffer({
    required this.abschnittKey,
    required this.abschnittLabel,
    required this.fundstelle,
    required this.hinweis,
  });
}

List<SprachCheckTreffer> runSprachCheck(Map<String, String> abschnitte) {
  final ergebnisse = <SprachCheckTreffer>[];
  for (final a in gutachtenAbschnitte) {
    final text = abschnitte[a.key] ?? '';
    if (text.trim().isEmpty) continue;
    for (final regel in sprachRegeln) {
      for (final match in regel.pattern.allMatches(text)) {
        ergebnisse.add(SprachCheckTreffer(
          abschnittKey: a.key,
          abschnittLabel: a.label,
          fundstelle: match.group(0) ?? '',
          hinweis: regel.hinweis,
        ));
      }
    }
  }
  return ergebnisse;
}

/// ----------- Platzhalter-Ersetzung -----------

String applyVorlagenPlatzhalter(
  String text, {
  AuftraegeData? auftrag,
  KundenData? kunde,
}) {
  String kundeName() {
    if (kunde == null) return '';
    if ((kunde.firma ?? '').isNotEmpty) return kunde.firma!;
    return [kunde.vorname, kunde.nachname]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' ');
  }

  String objekt() {
    if (auftrag == null) return '';
    return [auftrag.objektStrasse, auftrag.objektPlz, auftrag.objektOrt]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(', ');
  }

  String bb1() {
    final d = auftrag?.beweisbeschluss1;
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  String ortstermin() {
    final d = auftrag?.ortsterminAm;
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  final map = <String, String>{
    '{{auftraggeber}}': kundeName(),
    '{{objekt}}': objekt(),
    '{{objektart}}': auftrag?.objektart ?? '',
    '{{baujahr}}': auftrag?.baujahr ?? '',
    '{{ortstermin}}': ortstermin(),
    '{{betreff}}': auftrag?.betreff ?? '',
    '{{aktenzeichen}}': auftrag?.aktenzeichen ?? '',
    '{{azExtern}}': auftrag?.azExtern ?? '',
    '{{gericht}}': auftrag?.gericht ?? '',
    '{{beweisbeschluss1}}': bb1(),
  };
  var out = text;
  map.forEach((k, v) {
    out = out.replaceAll(k, v);
  });
  return out;
}

/// ----------- Persistence-Helpers -----------

/// Key-Liste als flaches Array für Legacy-Kompat.
List<String> get gutachtenAbschnittsKeys =>
    gutachtenAbschnitte.map((a) => a.key).toList();

class GutachtenWithAuftrag {
  final GutachtenData gutachten;
  final AuftraegeData? auftrag;
  const GutachtenWithAuftrag(this.gutachten, this.auftrag);
}

class GutachtenRepository {
  GutachtenRepository(this._db);
  final AppDatabase _db;

  Stream<List<GutachtenWithAuftrag>> watchAll({String query = ''}) {
    final q = _db.select(_db.gutachten).join([
      leftOuterJoin(_db.auftraege,
          _db.auftraege.id.equalsExp(_db.gutachten.auftragId)),
    ]);
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where(_db.gutachten.nummer.lower().like(like) |
          _db.gutachten.bezeichnung.lower().like(like) |
          _db.gutachten.titel.lower().like(like) |
          _db.auftraege.aktenzeichen.lower().like(like));
    }
    q.orderBy([
      OrderingTerm(
          expression: _db.gutachten.updatedAt, mode: OrderingMode.desc),
    ]);
    return q.watch().map((rows) => rows
        .map((r) => GutachtenWithAuftrag(
              r.readTable(_db.gutachten),
              r.readTableOrNull(_db.auftraege),
            ))
        .toList());
  }

  Future<int> upsert(GutachtenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.gutachten)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.gutachten).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.gutachten)..where((t) => t.id.equals(id))).go();
}

Map<String, String> abschnitteFromJson(String? json) {
  if (json == null || json.trim().isEmpty) return {};
  try {
    final parsed = jsonDecode(json);
    if (parsed is Map) {
      return parsed.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    }
  } catch (_) {}
  return {};
}

String abschnitteToJson(Map<String, String> map) => jsonEncode(map);

final gutachtenRepositoryProvider = Provider<GutachtenRepository>((ref) {
  return GutachtenRepository(ref.watch(appDatabaseProvider));
});

final gutachtenQueryProvider = StateProvider<String>((ref) => '');

final gutachtenListProvider =
    StreamProvider<List<GutachtenWithAuftrag>>((ref) {
  return ref
      .watch(gutachtenRepositoryProvider)
      .watchAll(query: ref.watch(gutachtenQueryProvider));
});
