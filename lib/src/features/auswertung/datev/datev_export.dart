import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Erzeugt einen DATEV-Buchungsstapel-Export als CSV (Format „EXTF",
/// Version 700, Buchungsstapel v13). Der Steuerberater kann das in
/// DATEV Kanzlei-Rechnungswesen oder DATEV Unternehmen Online importieren.
///
/// Der Export enthält:
///   • Ausgangsrechnungen (Rechnungen) — als Erlös-Buchung mit dem auf
///     der Rechnung hinterlegten Erlöskonto (Default: 8400, SKR04)
///   • Eingangsrechnungen — als Aufwand mit hinterlegtem DATEV-Konto
///   • Bankbewegungen mit `kein_beleg` oder `privat` und gesetztem
///     `datevKonto` — als Bankbuchung gegen das angegebene Sachkonto
class DatevExportService {
  DatevExportService(this._db);
  final AppDatabase _db;

  /// Standard-Sachkonten nach SKR04. Wenn der Datensatz nichts
  /// hinterlegt hat, fällt der Export auf diese Defaults zurück —
  /// der Steuerberater kann sie in DATEV nachjustieren.
  static const String _defaultErloesKonto = '8400';
  static const String _defaultAufwandKonto = '4980'; // Sonstiger Aufwand
  static const String _defaultBankKonto = '1200';

  Future<Uint8List> erstelleBuchungsstapel({
    required DateTime vonDatum,
    required DateTime bisDatum,
    required String mandantNr,
    required String beraterNr,
  }) async {
    final puffer = StringBuffer();

    // ----- Header-Zeile (Zeile 1) -----
    final jetzt = DateTime.now();
    final tsImported = DateFormat('yyyyMMddHHmmssSSS').format(jetzt);
    final wjBeginn = DateFormat('yyyyMMdd').format(DateTime(vonDatum.year));
    final dtVon = DateFormat('yyyyMMdd').format(vonDatum);
    final dtBis = DateFormat('yyyyMMdd').format(bisDatum);
    final bezeichnung = 'Aktenwerk_${dtVon}_$dtBis';
    final headerFields = [
      '"EXTF"', // Format-Kennzeichen
      '700', // Versionsnummer
      '21', // Datenkategorie 21 = Buchungsstapel
      '"Buchungsstapel"',
      '13', // Format-Version
      tsImported, // Erzeugt am
      '', // Importiert am
      '"RE"', // Herkunft (RE = aus externer Software)
      '"AKTENWERK"', // Exportiert von
      '"AKTENWERK"', // Importiert von
      '', // Ergebnis (leer)
      beraterNr.isEmpty ? '0' : beraterNr,
      mandantNr.isEmpty ? '0' : mandantNr,
      wjBeginn,
      '4', // Sachkontenlänge (4 = SKR04 Standard)
      dtVon,
      dtBis,
      '"$bezeichnung"',
      '""', // Diktatkürzel
      '1', // Buchungstyp 1 = Finanzbuchführung
      '0', // Rechnungslegungszweck (0 = unspezifisch)
      '0', // Festschreibung (0 = nicht festgeschrieben)
      '"EUR"', // WKZ
    ];
    puffer.writeln(headerFields.join(';'));

    // ----- Spalten-Header (Zeile 2) -----
    const spalten = [
      'Umsatz (ohne Soll/Haben-Kz)',
      'Soll/Haben-Kennzeichen',
      'WKZ Umsatz',
      'Kurs',
      'Basis-Umsatz',
      'WKZ Basis-Umsatz',
      'Konto',
      'Gegenkonto (ohne BU-Schlüssel)',
      'BU-Schlüssel',
      'Belegdatum',
      'Belegfeld 1',
      'Belegfeld 2',
      'Skonto',
      'Buchungstext',
    ];
    puffer.writeln(spalten.map((c) => '"$c"').join(';'));

    // ----- Buchungssätze -----
    // Rechnungen (Ausgangsrechnungen) — Bank/Debitor an Erlös
    final rechnungen = await _db.select(_db.rechnungen).get();
    for (final r in rechnungen) {
      final dat = r.rechnungsdatum;
      if (dat == null) continue;
      if (dat.isBefore(vonDatum) || dat.isAfter(bisDatum)) continue;
      if (r.brutto <= 0) continue;
      final beleg = r.rechnungsnummer ?? 'RE${r.id}';
      final konto = (r.kontonummer ?? _defaultErloesKonto).trim().isEmpty
          ? _defaultErloesKonto
          : r.kontonummer!.trim();
      final text = _kuerze('Rechnung $beleg', 60);
      puffer.writeln(_buchung(
        umsatz: r.brutto,
        sollHaben: 'S',
        konto: _defaultBankKonto,
        gegenkonto: konto,
        belegdatum: dat,
        belegfeld1: beleg,
        text: text,
      ));
    }

    // Eingangsrechnungen — Aufwand an Bank/Kreditor
    final eingang = await _db.select(_db.eingangsrechnungen).get();
    for (final e in eingang) {
      final dat = e.rechnungsdatum;
      if (dat == null) continue;
      if (dat.isBefore(vonDatum) || dat.isAfter(bisDatum)) continue;
      final brutto = e.brutto;
      if (brutto <= 0) continue;
      final beleg = e.rechnungsnummer ?? 'ER${e.id}';
      final konto = (e.datevKonto ?? '').trim().isEmpty
          ? _defaultAufwandKonto
          : e.datevKonto!.trim();
      final text = _kuerze(
          [e.lieferantName, e.beschreibung]
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .join(' · '),
          60);
      puffer.writeln(_buchung(
        umsatz: brutto,
        sollHaben: 'S',
        konto: konto,
        gegenkonto: _defaultBankKonto,
        belegdatum: dat,
        belegfeld1: beleg,
        text: text.isEmpty ? 'Eingangsrechnung $beleg' : text,
      ));
    }

    // Bankbewegungen mit kein_beleg / privat + DATEV-Konto
    final bewegungenAlle = await (_db.select(_db.bankBewegungen)
          ..where((t) => t.status.isIn(['kein_beleg', 'privat'])))
        .get();
    final bewegungen = bewegungenAlle.where((b) =>
        !b.buchungsdatum.isBefore(vonDatum) &&
        !b.buchungsdatum.isAfter(bisDatum));
    for (final b in bewegungen) {
      final konto = (b.datevKonto ?? '').trim();
      if (konto.isEmpty) continue;
      final betragAbs = b.betrag.abs();
      // Ausgang (negativer Betrag) → Sachkonto im Soll, Bank im Haben.
      // Eingang (positiver Betrag) → Bank im Soll, Sachkonto im Haben.
      final sollHaben = b.betrag < 0 ? 'S' : 'H';
      final text = _kuerze(
          [b.gegenpartei, b.verwendungszweck]
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .join(' · '),
          60);
      puffer.writeln(_buchung(
        umsatz: betragAbs,
        sollHaben: sollHaben,
        konto: konto,
        gegenkonto: _defaultBankKonto,
        belegdatum: b.buchungsdatum,
        belegfeld1: 'BANK${b.id}',
        text: text.isEmpty ? 'Bankbuchung' : text,
      ));
    }

    // DATEV erwartet Windows-1252 (ANSI) — wir kodieren die Bytes
    // entsprechend, damit Umlaute beim Import in DATEV korrekt
    // erscheinen. Latin1 deckt die deutschen Zeichen ab; Zeichen
    // außerhalb werden auf '?' fallback'd.
    final inhalt = puffer.toString();
    return Uint8List.fromList(
      latin1.encode(inhalt.replaceAllMapped(
          RegExp(r'[^\x00-\xFF]'), (_) => '?')),
    );
  }

  String _buchung({
    required double umsatz,
    required String sollHaben,
    required String konto,
    required String gegenkonto,
    required DateTime belegdatum,
    required String belegfeld1,
    required String text,
  }) {
    // Umsatz: Komma als Dezimaltrennzeichen, kein Tausenderpunkt.
    final umsatzStr = umsatz.toStringAsFixed(2).replaceAll('.', ',');
    final dat = DateFormat('ddMM').format(belegdatum);
    return [
      umsatzStr,
      sollHaben,
      'EUR',
      '', // Kurs
      '', // Basis-Umsatz
      '', // WKZ Basis-Umsatz
      konto,
      gegenkonto,
      '', // BU-Schlüssel (DATEV mappt USt automatisch via Konto)
      dat,
      '"${_csvEscape(belegfeld1)}"',
      '',
      '',
      '"${_csvEscape(text)}"',
    ].join(';');
  }

  String _csvEscape(String s) => s.replaceAll('"', '""');

  String _kuerze(String s, int max) {
    if (s.length <= max) return s;
    return s.substring(0, max);
  }

  /// Belegjournal als ZIP — enthält:
  ///   • beleg-uebersicht.csv (Liste aller Belege mit Beleg-Nr, Datum,
  ///     Betrag, Konto, Dateiname)
  ///   • PDFs aller Ausgangsrechnungen (sofern als PDF archiviert)
  ///   • PDFs aller Eingangsrechnungen (sofern Datei vorhanden)
  ///   • alle Akten-Dokumente, die im Zeitraum erstellt wurden
  Future<Uint8List> erstelleBelegjournalZip({
    required DateTime vonDatum,
    required DateTime bisDatum,
  }) async {
    final archive = Archive();
    final csv = StringBuffer();
    csv.writeln(
        'Typ;Beleg-Nr;Datum;Betrag;Konto;Gegenpartei/Kunde;Dateiname');

    // Ausgangsrechnungen (PDF aus DB-Spalte oder Storage-URL).
    final rechnungen = await _db.select(_db.rechnungen).get();
    for (final r in rechnungen) {
      final dat = r.rechnungsdatum;
      if (dat == null) continue;
      if (dat.isBefore(vonDatum) || dat.isAfter(bisDatum)) continue;
      final beleg = r.rechnungsnummer ?? 'RE${r.id}';
      final dateiname = 'Rechnungen/${_dateiname(beleg)}.pdf';
      final bytes = await _ladePdfBytes(r.pdfStorageUrl);
      if (bytes != null) {
        archive.addFile(ArchiveFile(dateiname, bytes.length, bytes));
      }
      csv.writeln([
        'Ausgangsrechnung',
        beleg,
        DateFormat('dd.MM.yyyy').format(dat),
        r.brutto.toStringAsFixed(2).replaceAll('.', ','),
        r.kontonummer ?? '',
        '',
        bytes != null ? dateiname : '(kein PDF)',
      ].join(';'));
    }

    // Eingangsrechnungen — falls als PDF gespeichert.
    final eingang = await _db.select(_db.eingangsrechnungen).get();
    for (final e in eingang) {
      final dat = e.rechnungsdatum;
      if (dat == null) continue;
      if (dat.isBefore(vonDatum) || dat.isAfter(bisDatum)) continue;
      final beleg = e.rechnungsnummer ?? 'ER${e.id}';
      final dateiname = 'Eingangsrechnungen/${_dateiname(beleg)}.pdf';
      final bytes = await _ladePdfBytes(e.belegPfad);
      if (bytes != null) {
        archive.addFile(ArchiveFile(dateiname, bytes.length, bytes));
      }
      csv.writeln([
        'Eingangsrechnung',
        beleg,
        DateFormat('dd.MM.yyyy').format(dat),
        e.brutto.toStringAsFixed(2).replaceAll('.', ','),
        e.datevKonto ?? '',
        e.lieferantName ?? '',
        bytes != null ? dateiname : '(kein PDF)',
      ].join(';'));
    }

    // Dokumente der Akten im Zeitraum (alle PDFs/Bilder).
    final dokumenteAlle = await _db.select(_db.dokumente).get();
    final dokumente = dokumenteAlle.where((d) =>
        !d.datum.isBefore(vonDatum) && !d.datum.isAfter(bisDatum));
    for (final d in dokumente) {
      final titel = d.titel ?? 'Dokument_${d.id}';
      final ext = (d.mimeType ?? '').contains('pdf') ? 'pdf' : 'bin';
      final dateiname = 'Akten-Dokumente/${_dateiname(titel)}.$ext';
      final bytes = d.daten ?? await _ladePdfBytes(d.storageUrl);
      if (bytes == null || bytes.isEmpty) continue;
      archive.addFile(ArchiveFile(dateiname, bytes.length, bytes));
      csv.writeln([
        'Dokument',
        '',
        DateFormat('dd.MM.yyyy').format(d.datum),
        '',
        '',
        d.kategorie ?? '',
        dateiname,
      ].join(';'));
    }

    // Übersichts-CSV ans Archiv hängen.
    final csvBytes = utf8.encode('﻿${csv.toString()}'); // mit BOM für Excel
    archive.addFile(
        ArchiveFile('beleg-uebersicht.csv', csvBytes.length, csvBytes));

    final zipped = ZipEncoder().encode(archive);
    return Uint8List.fromList(zipped);
  }

  Future<Uint8List?> _ladePdfBytes(String? storageUrl) async {
    if (storageUrl == null || storageUrl.isEmpty) return null;
    try {
      final resp = await http.get(Uri.parse(storageUrl));
      if (resp.statusCode != 200) return null;
      return resp.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  String _dateiname(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
}

final datevExportServiceProvider = Provider<DatevExportService>((ref) {
  return DatevExportService(ref.watch(appDatabaseProvider));
});
