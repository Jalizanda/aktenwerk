import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Gerichts-Eintrag aus der Gerichts-Datenbank.
class Gericht {
  final String typ;
  final String name;
  final String strasse;
  final String plz;
  final String ort;
  final String telefon;

  const Gericht({
    required this.typ,
    required this.name,
    required this.strasse,
    required this.plz,
    required this.ort,
    required this.telefon,
  });

  factory Gericht.fromJson(Map<String, dynamic> j) => Gericht(
        typ: j['typ'] as String? ?? '',
        name: j['name'] as String? ?? '',
        strasse: j['strasse'] as String? ?? '',
        plz: j['plz'] as String? ?? '',
        ort: j['ort'] as String? ?? '',
        telefon: j['telefon'] as String? ?? '',
      );
}

/// Lädt die Gerichts-Datenbank lazy aus dem Asset.
class GerichteRepository {
  GerichteRepository._();
  static final GerichteRepository instance = GerichteRepository._();

  List<Gericht>? _cache;

  Future<List<Gericht>> all() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString('assets/data/gerichte.json');
    final list = jsonDecode(raw) as List<dynamic>;
    _cache = list
        .map((e) => Gericht.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return _cache!;
  }

  /// Einfache Textsuche über Name, Ort, PLZ.
  Future<List<Gericht>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all();
    final items = await all();
    return items
        .where((g) =>
            g.name.toLowerCase().contains(q) ||
            g.ort.toLowerCase().contains(q) ||
            g.plz.contains(q) ||
            g.typ.toLowerCase().contains(q))
        .toList();
  }
}
