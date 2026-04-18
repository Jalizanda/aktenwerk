import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class LastzoneResult {
  final String? schnee;
  final String? wind;
  const LastzoneResult({this.schnee, this.wind});
}

/// Schnee- und Windlastzonen nach DIBt-Verwaltungsgrenzen.
class LastzonenRepository {
  LastzonenRepository._();
  static final LastzonenRepository instance = LastzonenRepository._();

  Map<String, Map<String, String>>? _cache;

  Future<void> _load() async {
    if (_cache != null) return;
    final raw = await rootBundle.loadString('assets/data/lastzonen.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    _cache = {
      'schnee': _toStringMap(j['schnee']),
      'schneeKreis': _toStringMap(j['schneeKreis']),
      'wind': _toStringMap(j['wind']),
      'windKreis': _toStringMap(j['windKreis']),
    };
  }

  Map<String, String> _toStringMap(dynamic v) {
    if (v is! Map) return const {};
    return v.map((k, val) => MapEntry(k as String, val.toString()));
  }

  /// Normalisiert Ortsnamen (entspricht window.normLastKey).
  static String normKey(String? s) {
    if (s == null || s.isEmpty) return '';
    var out = s.trim().toLowerCase();
    out = out
        .replaceAll('ä', 'a')
        .replaceAll('ö', 'o')
        .replaceAll('ü', 'u')
        .replaceAll('ß', 'ss');
    out = out.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    out = out.replaceAll(RegExp(r'\s+'), ' ');
    return out;
  }

  Future<LastzoneResult> find({
    String? ort,
    String? kreis,
    String? ags,
  }) async {
    await _load();
    final c = _cache!;
    final k = normKey(ort);
    final kk = normKey(kreis);

    String? schnee;
    String? wind;
    if (kk.isNotEmpty) {
      schnee = c['schnee']!['${kk}__$k'];
      wind = c['wind']!['${kk}__$k'];
    }
    schnee ??= c['schnee']![k];
    wind ??= c['wind']![k];

    if (schnee == null && kk.isNotEmpty) {
      schnee = c['schneeKreis']!['name__$kk'];
    }
    if (wind == null && kk.isNotEmpty) {
      wind = c['windKreis']!['name__$kk'];
    }
    if (ags != null && ags.isNotEmpty) {
      final digits = ags.replaceAll(RegExp(r'\D'), '');
      final kreis5 = digits.length >= 5 ? digits.substring(0, 5) : digits;
      schnee ??= c['schneeKreis']![kreis5];
      wind ??= c['windKreis']![kreis5];
    }

    return LastzoneResult(schnee: schnee, wind: wind);
  }
}
