import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

/// Gerichts-Eintrag aus der Gerichts-Datenbank.
class Gericht {
  final String typ;
  final String name;
  final String strasse;
  final String plz;
  final String ort;
  final String telefon;
  final String fax;
  final String email;

  /// Ländercode, z. B. `DE` oder `AT`.
  final String land;

  /// Postfach (optional, z. B. „Postfach 10 16 20“).
  final String postfach;

  const Gericht({
    required this.typ,
    required this.name,
    required this.strasse,
    required this.plz,
    required this.ort,
    required this.telefon,
    this.fax = '',
    this.email = '',
    this.land = 'DE',
    this.postfach = '',
  });

  factory Gericht.fromJson(Map<String, dynamic> j) {
    String v(List<String> keys) {
      for (final k in keys) {
        final x = j[k];
        if (x != null && x.toString().trim().isNotEmpty) return x.toString().trim();
      }
      return '';
    }

    final name = v(['name', 'GerichtAnschrift1', 'Name', 'bezeichnung']);
    return Gericht(
      typ: v(['typ', 'Typ']).isNotEmpty ? v(['typ', 'Typ']) : typAusName(name),
      name: name,
      strasse: v(['strasse', 'Strasse', 'Straße']),
      plz: v(['plz', 'Plz', 'PLZ']),
      ort: v(['ort', 'stadt', 'Stadt', 'Ort']),
      telefon: v(['telefon', 'Telefon']),
      fax: v(['fax', 'Fax']),
      email: v(['email', 'Email1', 'EMail', 'E-Mail']),
      land: v(['land', 'Land']).isEmpty ? 'DE' : v(['land', 'Land']).toUpperCase(),
      postfach: v(['postfach', 'Postfach']),
    );
  }

  Map<String, dynamic> toJson() => {
        'typ': typ,
        'name': name,
        'strasse': strasse,
        'plz': plz,
        'ort': ort,
        'telefon': telefon,
        if (fax.isNotEmpty) 'fax': fax,
        if (email.isNotEmpty) 'email': email,
        'land': land,
        if (postfach.isNotEmpty) 'postfach': postfach,
      };

  static String typAusName(String name) {
    const map = {
      'Oberstaatsanwaltschaft': 'OStA',
      'Staatsanwaltschaft': 'StA',
      'Generalprokuratur': 'GP',
      'Arbeits- und Sozialgericht': 'ASG',
      'Amtsgericht': 'AG',
      'Landgericht': 'LG',
      'Oberlandesgericht': 'OLG',
      'Verwaltungsgericht': 'VG',
      'Oberverwaltungsgericht': 'OVG',
      'Sozialgericht': 'SG',
      'Arbeitsgericht': 'ArbG',
      'Finanzgericht': 'FG',
      'Bezirksgericht': 'BG',
      'Landesgericht': 'LG',
      'Handelsgericht': 'HG',
    };
    for (final e in map.entries) {
      if (name.startsWith(e.key)) return e.value;
    }
    return '';
  }
}

/// Lädt die Gerichts-Datenbank (rund 1.040 Gerichte und Staatsanwaltschaften
/// in Deutschland und Österreich) lazy aus dem Asset und ergänzt sie um
/// lokal importierte Gerichte (z. B. aus einem Gutachten-Manager-Export
/// oder einer eigenen CSV-Liste). Importierte Einträge haben Vorrang.
class GerichteRepository {
  GerichteRepository._();
  static final GerichteRepository instance = GerichteRepository._();

  static const _prefsKey = 'aw.gerichte.import';

  List<Gericht>? _cache;

  Future<List<Gericht>> all() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString('assets/data/gerichte.json');
    final basis = (jsonDecode(raw) as List<dynamic>)
        .map((e) => Gericht.fromJson(e as Map<String, dynamic>))
        .toList();
    final importiert = await _ladeImport();
    final schluessel = <String>{};
    final out = <Gericht>[];
    for (final g in [...importiert, ...basis]) {
      final k = '${g.name.toLowerCase()}|${g.plz}';
      if (schluessel.add(k)) out.add(g);
    }
    _cache = List.unmodifiable(out);
    return _cache!;
  }

  Future<List<Gericht>> _ladeImport() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(_prefsKey);
      if (s == null || s.isEmpty) return const [];
      return (jsonDecode(s) as List<dynamic>)
          .map((e) => Gericht.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Anzahl der lokal importierten Gerichte.
  Future<int> importierteAnzahl() async => (await _ladeImport()).length;

  /// Ersetzt die importierte Liste.
  Future<void> importieren(List<Gericht> gerichte) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode(gerichte.map((g) => g.toJson()).toList()));
    _cache = null;
  }

  Future<void> importLoeschen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    _cache = null;
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
            g.typ.toLowerCase().contains(q) ||
            g.land.toLowerCase() == q)
        .toList();
  }
}

/// Liest eine Gerichtsliste aus JSON (Liste von Objekten) oder CSV (mit
/// Kopfzeile; Trennzeichen `,` oder `;`). Erkannte Spalten u. a.:
/// name/GerichtAnschrift1, strasse, plz, ort/stadt, telefon, fax, email, land.
List<Gericht> parseGerichteDatei(String dateiname, Uint8List bytes) {
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1);
  final List<Map<String, dynamic>> zeilen;
  if (dateiname.toLowerCase().endsWith('.json') || text.trimLeft().startsWith('[')) {
    zeilen = (jsonDecode(text) as List<dynamic>).whereType<Map<String, dynamic>>().toList();
  } else {
    final erste = text.split('\n').first;
    final trenner = erste.split(';').length > erste.split(',').length ? ';' : ',';
    final rows = CsvToListConverter(fieldDelimiter: trenner, eol: '\n', shouldParseNumbers: false)
        .convert(text.replaceAll('\r\n', '\n'));
    if (rows.isEmpty) return const [];
    final kopf = rows.first.map((e) => e.toString().trim()).toList();
    zeilen = [
      for (final r in rows.skip(1))
        {for (var i = 0; i < kopf.length && i < r.length; i++) kopf[i]: r[i].toString()},
    ];
  }
  return zeilen
      .map(Gericht.fromJson)
      .where((g) => g.name.isNotEmpty)
      .toList();
}
