import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';

import '../../../data/database/app_database.dart';

/// CSV-Header und -Reihenfolge für LV-Positionen.
const _spaltenLv = [
  'OZ',
  'Art',
  'Kurztext',
  'Langtext',
  'Einheit',
  'Menge',
  'Einzelpreis',
  'Gesamtpreis',
  'DIN276',
  'Gewerk',
];

/// Erzeugt eine CSV-Datei (UTF-8 mit BOM, Semikolon-getrennt — Excel-DE).
/// Die Mengenpositionen bekommen Komma als Dezimaltrenner.
Uint8List buildLvCsv(List<LvPositionenData> positionen) {
  final rows = <List<dynamic>>[_spaltenLv];
  for (final p in positionen) {
    final menge = p.menge ?? 0;
    final ep = p.einzelpreis ?? 0;
    final gp = menge * ep;
    rows.add([
      p.oz ?? '',
      p.art,
      p.kurztext,
      p.langtext ?? '',
      p.einheit ?? '',
      _fmt(menge),
      _fmt(ep),
      _fmt(gp),
      p.din276 ?? '',
      p.gewerk ?? '',
    ]);
  }
  final csv = const ListToCsvConverter(
    fieldDelimiter: ';',
    eol: '\r\n',
  ).convert(rows);
  // BOM für Excel-DE-Erkennung
  final bytes = utf8.encode('﻿$csv');
  return Uint8List.fromList(bytes);
}

String _fmt(double v) =>
    v == 0 ? '0,00' : v.toStringAsFixed(2).replaceAll('.', ',');

/// Eine CSV-Zeile, geparst, in vereinheitlichter Form.
class CsvImportZeile {
  final String? oz;
  final String? art;
  final String kurztext;
  final String? langtext;
  final String? einheit;
  final double? menge;
  final double? einzelpreis;
  final String? din276;
  final String? gewerk;

  const CsvImportZeile({
    required this.kurztext,
    this.oz,
    this.art,
    this.langtext,
    this.einheit,
    this.menge,
    this.einzelpreis,
    this.din276,
    this.gewerk,
  });
}

/// Parst eine CSV-Datei (auto-Erkennung Trenner ; oder ,). Erwartet eine
/// Header-Zeile mit den im _spaltenLv definierten Spalten — fehlende
/// Spalten werden ignoriert, zusätzliche ignoriert.
List<CsvImportZeile> parseLvCsv(Uint8List bytes) {
  var text = utf8.decode(bytes, allowMalformed: true);
  // Eventuelles BOM entfernen.
  if (text.startsWith('﻿')) text = text.substring(1);

  // Trenner detektieren: Häufigster ; oder , in der ersten Zeile.
  final firstLine = text.split('\n').first;
  final delim = firstLine.split(';').length > firstLine.split(',').length
      ? ';'
      : ',';
  final rows = const CsvToListConverter(
    eol: '\n',
    shouldParseNumbers: false,
  ).convert(text, fieldDelimiter: delim);
  if (rows.isEmpty) return [];

  // Header-Mapping (case-insensitive)
  final header = rows.first
      .map((c) => c.toString().trim().toLowerCase())
      .toList();
  int idx(List<String> alts) {
    for (final a in alts) {
      final i = header.indexOf(a.toLowerCase());
      if (i >= 0) return i;
    }
    return -1;
  }

  final iOz = idx(['oz', 'ordnungszahl', 'pos', 'pos.']);
  final iArt = idx(['art', 'positionsart', 'typ']);
  final iKurz = idx(['kurztext', 'bezeichnung', 'titel']);
  final iLang = idx(['langtext', 'beschreibung']);
  final iEinheit = idx(['einheit', 'einh', 'me', 'me.']);
  final iMenge = idx(['menge', 'qty']);
  final iEp = idx(['einzelpreis', 'ep', 'preis']);
  final iDin = idx(['din276', 'din 276', 'kg', 'kostengruppe']);
  final iGewerk = idx(['gewerk']);

  final out = <CsvImportZeile>[];
  for (var r = 1; r < rows.length; r++) {
    final row = rows[r];
    String? cell(int i) {
      if (i < 0 || i >= row.length) return null;
      final v = row[i].toString().trim();
      return v.isEmpty ? null : v;
    }

    final kurztext = cell(iKurz);
    if (kurztext == null) continue;
    out.add(CsvImportZeile(
      oz: cell(iOz),
      art: _normArt(cell(iArt)),
      kurztext: kurztext,
      langtext: cell(iLang),
      einheit: cell(iEinheit),
      menge: _parseDouble(cell(iMenge)),
      einzelpreis: _parseDouble(cell(iEp)),
      din276: cell(iDin),
      gewerk: cell(iGewerk),
    ));
  }
  return out;
}

String? _normArt(String? raw) {
  if (raw == null) return null;
  final l = raw.toLowerCase();
  if (l.contains('titel')) return 'titel';
  if (l.contains('bedarf') || l.contains('bp')) return 'bedarf';
  if (l.contains('event') || l.contains('alt')) return 'eventual';
  if (l.contains('stund')) return 'stundenlohn';
  if (l.contains('grund') || l.contains('vorbem')) return 'grundtext';
  return 'normal';
}

double? _parseDouble(String? s) {
  if (s == null) return null;
  return double.tryParse(s.replaceAll(',', '.').trim());
}
