import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/database/app_database.dart';
import '../../data/database/database_provider.dart';

/// Strukturierte Gültigkeits- und Historien-Informationen einer Norm.
///
/// Da Bausachverständige Bauwerke stets nach den zum Bau- bzw. Abnahmezeitpunkt
/// geltenden „anerkannten Regeln der Technik" beurteilen müssen, bleiben auch
/// zurückgezogene/ersetzte Normen dauerhaft aktiv im Normen-Pool (`aktiv = true`),
/// führen aber ihren exakten Gültigkeitszeitraum (`gueltigVon` – `gueltigBis`)
/// sowie die Nachfolgenorm (`ersetztDurch`).
class NormGueltigkeitInfo {
  const NormGueltigkeitInfo({
    this.gueltigVon,
    this.gueltigBis,
    this.ersetztDurch,
    this.ersetztVorgaenger,
  });

  /// Ausgabedatum / Beginn der Gültigkeit (z. B. `2012-12`).
  final String? gueltigVon;

  /// Ende der Gültigkeit / Rückzugsdatum (z. B. `2020-08`), oder leer/`heute`
  /// bei aktuell gültigen Normen.
  final String? gueltigBis;

  /// Nachfolgenorm inkl. Ausgabedatum (z. B. `DIN 18065 (2020-08)`).
  final String? ersetztDurch;

  /// Vorgängernorm (optional, z. B. `DIN 18065 (2015-03)`).
  final String? ersetztVorgaenger;

  factory NormGueltigkeitInfo.fromNorm(NormenData norm) {
    Map<String, dynamic> map = const {};
    final raw = norm.extras;
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          map = decoded;
        }
      } catch (_) {}
    }
    String? clean(Object? v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    final von = clean(map['gueltigVon']) ?? clean(norm.ausgabe);
    final bis = clean(map['gueltigBis']);
    final ersetzt = clean(map['ersetztDurch']);
    final vorgaenger = clean(map['ersetztVorgaenger']);

    return NormGueltigkeitInfo(
      gueltigVon: von,
      gueltigBis: bis,
      ersetztDurch: ersetzt,
      ersetztVorgaenger: vorgaenger,
    );
  }

  /// Mischt die Gültigkeitsfelder verlustfrei in das bestehende `extras`-JSON
  /// (sodass z. B. `sha256` und `erwarteterDateiname` erhalten bleiben).
  String mergeIntoExtras(String? existingExtras) {
    final map = <String, dynamic>{};
    if (existingExtras != null && existingExtras.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(existingExtras);
        if (decoded is Map<String, dynamic>) {
          map.addAll(decoded);
        }
      } catch (_) {}
    }

    void setOrRemove(String key, String? val) {
      final trimmed = val?.trim();
      if (trimmed == null || trimmed.isEmpty) {
        map.remove(key);
      } else {
        map[key] = trimmed;
      }
    }

    setOrRemove('gueltigVon', gueltigVon);
    setOrRemove('gueltigBis', gueltigBis);
    setOrRemove('ersetztDurch', ersetztDurch);
    setOrRemove('ersetztVorgaenger', ersetztVorgaenger);

    return jsonEncode(map);
  }

  /// Kompakter Gültigkeitszeitraum für Tabellen-Spalte und Badges.
  /// Beispiele:
  /// - `seit 2022-12 (heute)` bei aktuellen Normen
  /// - `2004-10 bis 2020-08` bei ersetzten/historischen Normen
  String zeitraumLabel(String? status) {
    final von = (gueltigVon ?? '').trim();
    final bis = (gueltigBis ?? '').trim();
    final bisClean =
        (bis.toLowerCase() == 'heute' || bis.toLowerCase() == 'aktuell')
            ? ''
            : bis;

    if (status == 'aktuell') {
      if (von.isNotEmpty) return '$von – heute';
      return 'aktuell gültig';
    }
    if (status == 'veraltet') {
      if (von.isNotEmpty && bisClean.isNotEmpty) {
        return '$von – $bisClean';
      }
      if (von.isNotEmpty) return 'ab $von (ersetzt)';
      if (bisClean.isNotEmpty) return 'bis $bisClean';
      return 'historisch / ersetzt';
    }
    if (von.isNotEmpty && bisClean.isNotEmpty) {
      return '$von – $bisClean';
    }
    if (von.isNotEmpty) return 'ab $von';
    return '—';
  }
}

/// Einzel-Ergebnis einer KI-Aktualitätsprüfung für eine Norm.
class NormAktualitaetKiErgebnis {
  const NormAktualitaetKiErgebnis({
    required this.normId,
    required this.status,
    required this.gueltigVon,
    required this.gueltigBis,
    required this.ersetztDurch,
    required this.notiz,
  });

  final int normId;

  /// `'aktuell'` | `'veraltet'` | `'unbekannt'`
  final String status;

  /// Beginn der Gültigkeit (`JJJJ-MM`).
  final String gueltigVon;

  /// Ende der Gültigkeit (`JJJJ-MM` bei historischen Normen, oder `'heute'` bei aktuellen).
  final String gueltigBis;

  /// Nachfolgenorm (z. B. `DIN 18065 (2020-08)`), leer falls noch aktuell.
  final String ersetztDurch;

  /// Kurze sachverständige Erläuterung zur Historie / Gültigkeit.
  final String notiz;
}

/// KI-Service zur globalen und einzelnen Überprüfung der Aktualität und des
/// Gültigkeitszeitraums (`von – bis`) von Normen im Katalog.
/// Nutzt das Cloud-Backend (`/api/normChat` → Vertex AI `gemini-2.5-flash`),
/// sodass kein Client-seitiger Firebase-AI-Logic-Config-Fehler auftreten kann.
class NormenAktualitaetKiService {
  NormenAktualitaetKiService(this._ref);
  final Ref _ref;

  static String _endpoint() {
    if (kIsWeb) return '/api/normChat';
    return 'https://europe-west1-aktenwerk-88c35.cloudfunctions.net/normChatHttp';
  }

  /// Prüft einen Batch von Normen (empfohlen: 10–20 Stück pro Aufruf) per Vertex AI
  /// unter Berücksichtigung aller im eigenen Pool vorhandenen Ausgaben.
  Future<List<NormAktualitaetKiErgebnis>> pruefeBatch(
    List<NormenData> batch, {
    required List<NormenData> kompletterPool,
  }) async {
    if (batch.isEmpty) return const [];

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Bitte zuerst anmelden.');
    }
    final idToken = await user.getIdToken();

    // Gruppiere alle vorhandenen Ausgaben im eigenen Pool nach Basis-Normnummer,
    // damit die KI sofort sieht, wenn im eigenen Bestand bereits eine neuere
    // Ausgabe derselben Norm existiert.
    final poolByBaseNum = <String, List<String>>{};
    for (final n in kompletterPool) {
      final base = _baseNormNummer(n.nummer);
      if (base.isEmpty) continue;
      final ausg = (n.ausgabe ?? '').trim();
      poolByBaseNum
          .putIfAbsent(base, () => [])
          .add('${n.nummer}${ausg.isNotEmpty ? " ($ausg)" : ""}');
    }

    final itemsPrompt = StringBuffer();
    for (final n in batch) {
      final base = _baseNormNummer(n.nummer);
      final geschwister = poolByBaseNum[base] ?? const [];
      final info = NormGueltigkeitInfo.fromNorm(n);
      itemsPrompt.writeln(
        '- ID: ${n.id} | Nummer: "${n.nummer}" | Ausgabe: "${n.ausgabe ?? ''}" | '
        'Titel: "${n.titel ?? ''}" | Herausgeber: "${n.herausgeber ?? ''}"'
        '${info.gueltigVon != null ? ' | Bisher gueltigVon: "${info.gueltigVon}"' : ''}'
        '${geschwister.length > 1 ? ' | Weitere Ausgaben im eigenen Pool: ${geschwister.join(", ")}' : ''}',
      );
    }

    const systemPrompt = '''
Du bist ein deutscher Normen-Experte für Bausachverständige (DIN, DIN EN, DIN EN ISO, VDI, VOB, WTA, ift, EAD/ETA, DVS, Flachdachrichtlinie).
Deine Aufgabe ist es, für jede übergebene Norm / Richtlinie mit ihrem jeweiligen Ausgabedatum zu prüfen:
1. Ist diese spezifische Ausgabe (`Ausgabe`) heute noch die **aktuell gültige** Fassung (`status: "aktuell"`) oder wurde sie durch eine neuere Ausgabe bzw. Nachfolgenorm abgelöst/zurückgezogen (`status: "veraltet"`)?
2. **Von wann bis wann war sie aktuell/gültig?**
   - `gueltigVon`: Das Ausgabedatum dieser Fassung im Format `JJJJ-MM` (falls nur das Jahr bekannt ist: `JJJJ-01`).
   - `gueltigBis`:
     - Wenn `status == "aktuell"`: `"heute"`.
     - Wenn `status == "veraltet"`: Das Ausgabedatum der ablösenden Nachfolgenorm bzw. das Rückzugsdatum im Format `JJJJ-MM` (z. B. wenn DIN 18195-4:2000-08 im Juli 2017 durch DIN 18533:2017-07 abgelöst wurde: `gueltigVon: "2000-08"`, `gueltigBis: "2017-07"`, `ersetztDurch: "DIN 18533-1 (2017-07)"`).
3. WICHTIG:
   - Beachte unbedingt das angegebene `Ausgabe`-Datum der jeweiligen Zeile!
   - Wenn unter "Weitere Ausgaben im eigenen Pool" bereits eine jüngere Hauptausgabe derselben Norm existiert (kein bloßer Entwurf `E`), dann ist die ältere Ausgabe `veraltet` und ihr `gueltigBis` ist das Ausgabedatum der nächstjüngeren Ausgabe.
   - Entwürfe (erkennbar an `E DIN...` oder `Entwurf` im Titel), zu denen bereits die endgültige Fassung oder eine neuere Ausgabe erschienen ist, sind ebenfalls `veraltet`.
4. Gib AUSSCHLIESSLICH valides JSON in folgendem Schema zurück:
{
  "ergebnisse": [
    {
      "id": 123,
      "status": "aktuell",
      "gueltigVon": "2022-12",
      "gueltigBis": "heute",
      "ersetztDurch": "",
      "notiz": "Aktuell gültige Ausgabe seit 2022-12 (ersetzt Ausgabe 2009-09)."
    }
  ]
}
''';

    final userPrompt =
        'Prüfe folgende ${batch.length} Normen auf Aktualität, Gültigkeitszeitraum (gueltigVon – gueltigBis) und Nachfolgenorm und antworte als JSON mit dem Schlüssel "ergebnisse":\n\n'
        '$itemsPrompt';

    final response = await http
        .post(
          Uri.parse(_endpoint()),
          headers: {
            'Content-Type': 'application/json',
            if (idToken != null) 'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({
            'mode': 'direct_json',
            'system': systemPrompt,
            'prompt': userPrompt,
          }),
        )
        .timeout(const Duration(seconds: 90));

    if (response.statusCode != 200) {
      throw Exception(
        'KI-Server-Antwort (${response.statusCode}): ${response.body}',
      );
    }

    final outer = jsonDecode(response.body);
    final rawText = (outer is Map ? outer['antwort']?.toString() ?? '' : '')
        .trim()
        .replaceAll(RegExp(r'^```json\s*|\s*```$'), '')
        .trim();
    if (rawText.isEmpty) return const [];

    final decoded = jsonDecode(rawText);
    final list = decoded is Map
        ? decoded['ergebnisse']
        : (decoded is List ? decoded : null);
    if (list is! List) return const [];

    final results = <NormAktualitaetKiErgebnis>[];
    for (final item in list) {
      if (item is! Map) continue;
      final idRaw = item['id'];
      final id = idRaw is int
          ? idRaw
          : (idRaw is num ? idRaw.toInt() : int.tryParse(idRaw?.toString() ?? ''));
      if (id == null) continue;
      final status = (item['status']?.toString() ?? 'unbekannt').trim();
      final von = (item['gueltigVon']?.toString() ?? '').trim();
      final bis = (item['gueltigBis']?.toString() ?? '').trim();
      final ersetzt = (item['ersetztDurch']?.toString() ?? '').trim();
      final notiz = (item['notiz']?.toString() ?? '').trim();

      results.add(
        NormAktualitaetKiErgebnis(
          normId: id,
          status: ['aktuell', 'veraltet', 'unbekannt'].contains(status)
              ? status
              : 'unbekannt',
          gueltigVon: von,
          gueltigBis: bis,
          ersetztDurch: ersetzt,
          notiz: notiz,
        ),
      );
    }
    return results;
  }

  /// Speichert die KI-Prüfergebnisse direkt in der Datenbank.
  /// Alle Normen (auch `veraltet`) bleiben aktiv im Pool (`aktiv` wird NICHT auf false gesetzt!).
  Future<void> speichereErgebnisse(
    List<NormAktualitaetKiErgebnis> ergebnisse,
    Map<int, NormenData> normById,
  ) async {
    final db = _ref.read(appDatabaseProvider);
    final now = DateTime.now();

    for (final r in ergebnisse) {
      final existing = normById[r.normId];
      if (existing == null) continue;

      final currentInfo = NormGueltigkeitInfo.fromNorm(existing);
      final updatedInfo = NormGueltigkeitInfo(
        gueltigVon: r.gueltigVon.isNotEmpty
            ? r.gueltigVon
            : (currentInfo.gueltigVon ?? existing.ausgabe),
        gueltigBis: r.status == 'aktuell'
            ? 'heute'
            : (r.gueltigBis.isNotEmpty ? r.gueltigBis : currentInfo.gueltigBis),
        ersetztDurch: r.status == 'aktuell'
            ? null
            : (r.ersetztDurch.isNotEmpty
                ? r.ersetztDurch
                : currentInfo.ersetztDurch),
        ersetztVorgaenger: currentInfo.ersetztVorgaenger,
      );

      final mergedExtras = updatedInfo.mergeIntoExtras(existing.extras);

      await (db.update(db.normen)..where((t) => t.id.equals(r.normId))).write(
        NormenCompanion(
          aktualitaetStatus: Value(r.status),
          aktualitaetGeprueftAm: Value(now),
          aktualitaetNotiz:
              r.notiz.isNotEmpty ? Value(r.notiz) : Value(existing.aktualitaetNotiz),
          extras: Value(mergedExtras),
          // Wichtig: Auch historische Normen bleiben aktiv im Pool!
          aktiv: const Value(true),
          updatedAt: Value(now),
        ),
      );
    }
  }

  static String _baseNormNummer(String raw) {
    return raw
        .toUpperCase()
        .replaceFirst(RegExp(r'^E\s+'), '')
        .replaceAll(RegExp(r'\s*\(\d{4}.*$'), '')
        .replaceAll(RegExp(r':\d{4}.*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

final normenAktualitaetKiServiceProvider =
    Provider<NormenAktualitaetKiService>((ref) {
  return NormenAktualitaetKiService(ref);
});
