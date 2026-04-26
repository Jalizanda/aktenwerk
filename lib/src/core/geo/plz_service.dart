import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Postleitzahl-zu-Ort-Auflösung über die freie OpenPLZ-API
/// (https://openplzapi.org). Antworten werden im Speicher gecacht.
class PlzService {
  static final _cache = <String, String?>{};

  /// Ermittelt den Ort zur deutschen PLZ. Gibt `null` zurück, wenn die
  /// PLZ unbekannt ist oder ein Netzwerk-Fehler auftrat.
  ///
  /// Bei mehreren Orten zur selben PLZ (kommt bei Großstadt-Bezirken vor)
  /// wird der Eintrag mit dem kürzesten Namen genommen (typischerweise
  /// die Hauptgemeinde, z. B. „Berlin" statt „Berlin Mitte").
  static Future<String?> ortFromPlz(String plz) async {
    final clean = plz.trim();
    if (clean.length != 5 || int.tryParse(clean) == null) return null;
    if (_cache.containsKey(clean)) return _cache[clean];

    try {
      final res = await http
          .get(
            Uri.parse(
                'https://openplzapi.org/de/Localities?postalCode=$clean'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) {
        _cache[clean] = null;
        return null;
      }
      final list = jsonDecode(res.body);
      if (list is! List || list.isEmpty) {
        _cache[clean] = null;
        return null;
      }
      String? best;
      for (final item in list) {
        if (item is Map && item['name'] is String) {
          final name = (item['name'] as String).trim();
          if (name.isEmpty) continue;
          if (best == null || name.length < best.length) {
            best = name;
          }
        }
      }
      _cache[clean] = best;
      return best;
    } catch (_) {
      _cache[clean] = null;
      return null;
    }
  }
}

final plzServiceProvider = Provider<PlzService>((_) => PlzService());
