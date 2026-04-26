import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_provider.dart';

/// Importiert Teilmengen des Demo-Seeds in den aktuellen Mandanten ohne
/// bestehende Daten zu löschen. Wird benutzt, um z. B. nur die 95
/// Demo-Textbausteine oder die 25 Demo-Artikel in einen leeren oder
/// gefüllten Mandanten zu übernehmen. Duplikate werden ausgelassen.
class DemoMergeImporter {
  DemoMergeImporter(this._db);
  final AppDatabase _db;

  Future<Map<String, dynamic>> _loadJson() async {
    final raw = await rootBundle.loadString('assets/data/demo_seed.json');
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> _asList(dynamic v) => v is List
      ? v.whereType<Map<String, dynamic>>().toList()
      : const <Map<String, dynamic>>[];

  /// Importiert Textbausteine. Bereits vorhandene (gleicher Titel
  /// case-insensitive) werden übersprungen. Liefert Anzahl der
  /// hinzugefügten Bausteine.
  Future<MergeResult> importTextbausteine() async {
    final json = await _loadJson();
    final list = _asList(json['textbausteine']);
    final existing = await _db.select(_db.textbausteine).get();
    final knownTitles = existing
        .map((e) => e.titel.trim().toLowerCase())
        .toSet();

    var added = 0;
    var skipped = 0;
    await _db.transaction(() async {
      for (final t in list) {
        final titel = t['titel']?.toString().trim() ?? '';
        if (titel.isEmpty) {
          skipped++;
          continue;
        }
        if (knownTitles.contains(titel.toLowerCase())) {
          skipped++;
          continue;
        }
        await _db.into(_db.textbausteine).insert(
              TextbausteineCompanion.insert(
                titel: titel,
                kategorie: Value(t['kategorie']?.toString() ??
                    t['bereich']?.toString()),
                sachgebiet: Value(t['sachgebiet']?.toString()),
                tags: Value(t['tags']?.toString()),
                inhalt: Value(t['text']?.toString() ??
                    t['inhalt']?.toString()),
                favorit: Value(t['favorit'] == true),
              ),
            );
        added++;
        knownTitles.add(titel.toLowerCase());
      }
    });
    return MergeResult(added: added, skipped: skipped, total: list.length);
  }

  /// Importiert Artikel/Leistungen. Duplikate werden anhand der
  /// Artikel-Nummer (oder, falls leer, der Bezeichnung) erkannt und
  /// übersprungen.
  Future<MergeResult> importArtikel() async {
    final json = await _loadJson();
    final list = _asList(json['artikel']);
    final existing = await _db.select(_db.artikel).get();
    final knownKeys = existing
        .map((a) => (a.nummer?.trim().toLowerCase().isNotEmpty ?? false)
            ? a.nummer!.trim().toLowerCase()
            : a.bezeichnung.trim().toLowerCase())
        .toSet();

    var added = 0;
    var skipped = 0;
    await _db.transaction(() async {
      for (final a in list) {
        final nummer = (a['nr']?.toString() ?? a['nummer']?.toString())?.trim();
        final bez = (a['kurztext']?.toString() ??
                a['bezeichnung']?.toString() ??
                '')
            .trim();
        final key = (nummer != null && nummer.isNotEmpty)
            ? nummer.toLowerCase()
            : bez.toLowerCase();
        if (key.isEmpty) {
          skipped++;
          continue;
        }
        if (knownKeys.contains(key)) {
          skipped++;
          continue;
        }
        await _db.into(_db.artikel).insert(
              ArtikelCompanion.insert(
                nummer: Value(nummer),
                bezeichnung: bez.isNotEmpty ? bez : '(ohne)',
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
              ),
            );
        added++;
        knownKeys.add(key);
      }
    });
    return MergeResult(added: added, skipped: skipped, total: list.length);
  }

  /// Importiert Messgeräte. Duplikate werden anhand der Inventar-Nummer
  /// (oder, falls leer, der Bezeichnung + Seriennummer) erkannt.
  Future<MergeResult> importGeraete() async {
    final json = await _loadJson();
    final list = _asList(json['geraete']);
    final existing = await _db.select(_db.geraete).get();
    String keyOf(String? inv, String bez, String? seriennr) {
      if (inv != null && inv.trim().isNotEmpty) {
        return inv.trim().toLowerCase();
      }
      return '${bez.trim().toLowerCase()}|${(seriennr ?? '').trim().toLowerCase()}';
    }

    final knownKeys = existing
        .map((g) => keyOf(g.inventarNr, g.bezeichnung, g.seriennummer))
        .toSet();

    var added = 0;
    var skipped = 0;
    await _db.transaction(() async {
      for (final g in list) {
        final inv = g['inventarNr']?.toString();
        final bez = g['bezeichnung']?.toString() ?? '';
        final ser = g['seriennummer']?.toString();
        final key = keyOf(inv, bez, ser);
        if (key.isEmpty || key == '|') {
          skipped++;
          continue;
        }
        if (knownKeys.contains(key)) {
          skipped++;
          continue;
        }
        await _db.into(_db.geraete).insert(
              GeraeteCompanion.insert(
                inventarNr: Value(inv),
                bezeichnung: bez.isNotEmpty ? bez : '(ohne)',
                kategorie: Value(g['kategorie']?.toString()),
                hersteller: Value(g['hersteller']?.toString()),
                modell: Value(
                    g['modell']?.toString() ?? g['typ']?.toString()),
                seriennummer: Value(ser),
                angeschafftAm: Value(
                    _parseDate(g['anschaffungsdatum']) ??
                        _parseDate(g['angeschafftAm'])),
                anschaffungspreis: Value(_asDouble(g['preis']) ??
                    _asDouble(g['anschaffungspreis'])),
                status: Value(g['status']?.toString() ?? 'aktiv'),
                eichpflicht:
                    Value(g['eichpflicht']?.toString() ?? 'empfohlen'),
                kalibriertAm: Value(_parseDate(g['eichungLetzte']) ??
                    _parseDate(g['kalibriert']) ??
                    _parseDate(g['kalibriertAm'])),
                naechsteKalibrierung: Value(
                    _parseDate(g['eichungFaellig']) ??
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
              ),
            );
        added++;
        knownKeys.add(key);
      }
    });
    return MergeResult(added: added, skipped: skipped, total: list.length);
  }

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().replaceAll(',', '.');
    return double.tryParse(s);
  }

  String? _asJson(dynamic v) {
    if (v == null) return null;
    return jsonEncode(v);
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }
}

class MergeResult {
  const MergeResult({
    required this.added,
    required this.skipped,
    required this.total,
  });
  final int added;
  final int skipped;
  final int total;
}

final demoMergeImporterProvider = Provider<DemoMergeImporter>((ref) {
  return DemoMergeImporter(ref.watch(appDatabaseProvider));
});
