import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Erzeugt einen **vereinfachten DATEV-Buchungsstapel** als CSV-Datei im
/// Windows-1252-kompatiblen Format (Semikolon-getrennt). Die Datei enthält
/// für Ausgangs- und Eingangsrechnungen die Felder, die Steuerberater
/// typischerweise für den Import in DATEV Kanzlei-Rechnungswesen nutzen:
///
/// Umsatz;Soll/Haben;WKZ;Konto;Gegenkonto;BU-Schlüssel;Belegdatum;
/// Belegfeld1;Belegfeld2;Buchungstext;Kost1;Kost2;Debitor/Kreditor
///
/// Hinweis: Ein DATEV-konformer ASCII-Export (mit 210-Spalten-Header) ist
/// komplexer; dieses CSV reicht aber für fast alle Kanzlei-Importe.
class DatevExportService {
  DatevExportService(this._db);
  final AppDatabase _db;

  static final _dateFmt = DateFormat('dd.MM.yyyy');
  static final _moneyFmt =
      NumberFormat.currency(locale: 'de_DE', symbol: '', decimalDigits: 2);

  Future<DatevExportResult> export({
    required DateTime von,
    required DateTime bis,
    bool inkludiereAusgang = true,
    bool inkludiereEingang = true,
  }) async {
    final zeilen = <List<String>>[];
    zeilen.add([
      'Umsatz',
      'Soll/Haben',
      'WKZ',
      'Konto',
      'Gegenkonto',
      'BU-Schlüssel',
      'Belegdatum',
      'Belegfeld1',
      'Belegfeld2',
      'Buchungstext',
      'Kost1',
      'Kost2',
      'Debitor/Kreditor',
    ]);

    var anzAusgang = 0;
    var anzEingang = 0;

    if (inkludiereAusgang) {
      final q = _db.select(_db.rechnungen).join([
        leftOuterJoin(
            _db.kunden, _db.kunden.id.equalsExp(_db.rechnungen.kundeId)),
      ])
        ..where(_db.rechnungen.rechnungsdatum.isBetweenValues(von, bis))
        ..where(_db.rechnungen.status.isNotValue('storniert'));
      final rows = await q.get();
      for (final r in rows) {
        final re = r.readTable(_db.rechnungen);
        final k = r.readTableOrNull(_db.kunden);
        final datum = re.rechnungsdatum;
        if (datum == null) continue;
        final erloeskonto = re.kontonummer ?? '8400';
        final debitor = k?.debitornummer ?? '10000';
        zeilen.add([
          _moneyFmt.format(re.brutto),
          'S',
          'EUR',
          debitor,
          erloeskonto,
          _buSchluesselFuer(re.ustSatz),
          _dateFmt.format(datum),
          re.rechnungsnummer ?? '',
          '',
          _cut(
              'Rechnung ${_nameFuer(k)}',
              60),
          '',
          '',
          debitor,
        ]);
        anzAusgang++;
      }
    }

    if (inkludiereEingang) {
      final q = _db.select(_db.eingangsrechnungen).join([
        leftOuterJoin(_db.lieferanten,
            _db.lieferanten.id.equalsExp(_db.eingangsrechnungen.lieferantId)),
      ])
        ..where(_db.eingangsrechnungen.rechnungsdatum
            .isBetweenValues(von, bis))
        ..where(_db.eingangsrechnungen.status.isNotValue('storniert'));
      final rows = await q.get();
      for (final r in rows) {
        final er = r.readTable(_db.eingangsrechnungen);
        final l = r.readTableOrNull(_db.lieferanten);
        final datum = er.rechnungsdatum;
        if (datum == null) continue;
        final aufwandskonto =
            er.datevKonto ?? _defaultAufwandskonto(er.kategorie);
        final kreditor = l?.kreditornummer ?? '70000';
        zeilen.add([
          _moneyFmt.format(er.brutto),
          'H',
          'EUR',
          kreditor,
          aufwandskonto,
          _buSchluesselFuer(er.ustSatz),
          _dateFmt.format(datum),
          er.rechnungsnummer ?? '',
          '',
          _cut(
              'Eingang ${l?.firma ?? ""}',
              60),
          er.datevKostenstelle ?? '',
          '',
          kreditor,
        ]);
        anzEingang++;
      }
    }

    final csv = zeilen.map((r) => r.map(_csvCell).join(';')).join('\r\n');
    return DatevExportResult(
      csv: csv,
      anzAusgang: anzAusgang,
      anzEingang: anzEingang,
    );
  }

  String _cut(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);

  String _nameFuer(KundenData? k) {
    if (k == null) return '';
    if ((k.firma ?? '').isNotEmpty) return k.firma!;
    return '${k.vorname ?? ''} ${k.nachname ?? ''}'.trim();
  }

  String _csvCell(String v) {
    final needsQuote =
        v.contains(';') || v.contains('"') || v.contains('\n');
    final escaped = v.replaceAll('"', '""');
    return needsQuote ? '"$escaped"' : escaped;
  }

  /// DATEV-BU-Schlüssel (Auszug):
  /// - 0: ohne USt
  /// - 8: 7 % USt
  /// - 9: 19 % USt
  String _buSchluesselFuer(double ustSatz) {
    if (ustSatz == 0) return '0';
    if (ustSatz == 7) return '8';
    if (ustSatz == 19) return '9';
    return '';
  }

  String _defaultAufwandskonto(String? kategorie) {
    switch (kategorie) {
      case 'porto':
        return '4910';
      case 'buero':
      case 'bürobedarf':
        return '4930';
      case 'kfz':
        return '4400';
      case 'miete':
        return '4210';
      case 'telefon':
        return '4920';
      case 'fortbildung':
        return '4945';
      default:
        return '4980';
    }
  }
}

class DatevExportResult {
  final String csv;
  final int anzAusgang;
  final int anzEingang;
  const DatevExportResult({
    required this.csv,
    required this.anzAusgang,
    required this.anzEingang,
  });

  Future<void> share(String filename) async {
    await Share.shareXFiles(
      [
        XFile.fromData(
          Uint8List.fromList(latin1.encode(csv)),
          name: filename,
          mimeType: 'text/csv',
        ),
      ],
      subject: filename,
      text: 'DATEV-Export – $anzAusgang Ausgangs- / $anzEingang Eingangsrechnungen',
    );
  }
}

final datevExportServiceProvider = Provider<DatevExportService>((ref) {
  return DatevExportService(ref.watch(appDatabaseProvider));
});
