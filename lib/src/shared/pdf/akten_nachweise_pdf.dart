// Aktendeckel, Leistungsnachweis (Zeitaufstellung) und Kostennachweis
// (Auslagenaufstellung) als PDF – Gegenstücke zu den entsprechenden
// Gutachten-Manager-Vorlagen.

import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/jveg/jveg_tabelle.dart';
import '../../data/database/app_database.dart';
import '../../features/akten/akte/beteiligte_tab.dart';
import '../../features/akten/auftraege/auftrag_gm_extras.dart';
import '../../features/akten/auftraege/zusatzfelder.dart';

double _mm(double v) => v * PdfPageFormat.mm;
final _datum = DateFormat('dd.MM.yyyy', 'de');
final _zeit = DateFormat('HH:mm', 'de');
final _euro = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

String _hm(int min) => '${min ~/ 60}:${(min % 60).toString().padLeft(2, '0')}';

String _kundeName(KundenData? k) {
  if (k == null) return '';
  if ((k.firma ?? '').trim().isNotEmpty) return k.firma!.trim();
  return [k.titel, k.vorname, k.nachname]
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .join(' ');
}

String _objekt(AuftraegeData a) => [
      a.objektStrasse,
      [a.objektPlz, a.objektOrt].whereType<String>().where((s) => s.isNotEmpty).join(' ')
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');

Future<pw.ThemeData> _theme() async => pw.ThemeData.withFont(
      base: await PdfGoogleFonts.interRegular(),
      bold: await PdfGoogleFonts.interBold(),
    );

pw.Widget _kopf(String titel, AuftraegeData a, String? zeile2) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(titel,
                style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900)),
            pw.Text('Akte ${a.aktenzeichen ?? '—'}',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ],
        ),
        if (zeile2 != null && zeile2.isNotEmpty)
          pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(zeile2, style: const pw.TextStyle(fontSize: 9.5))),
        pw.SizedBox(height: 4),
        pw.Divider(height: 1, thickness: 0.8, color: PdfColors.blueGrey700),
        pw.SizedBox(height: 10),
      ],
    );

pw.Widget _fuss(pw.Context ctx, String text) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(text, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        pw.Text('Seite ${ctx.pageNumber} von ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ],
    );

String _sacheZeile(AuftraegeData a) {
  final sache = buildSacheKurzbezeichnung(a);
  final az = (a.gerichtsAktenzeichen ?? '').trim();
  return [
    if (sache.isNotEmpty) 'Sache: $sache',
    if (az.isNotEmpty) 'Gerichts-Az.: $az',
    if ((a.gericht ?? '').trim().isNotEmpty) a.gericht!.trim(),
  ].join(' · ');
}

// ---------------------------------------------------------------------------
// Leistungsnachweis
// ---------------------------------------------------------------------------

Future<Uint8List> buildLeistungsnachweisPdf({
  required AuftraegeData auftrag,
  required List<StundenData> stunden,
  bool nurOffene = false,
}) async {
  final rows = [...stunden.where((s) => !nurOffene || !s.abgerechnet)]
    ..sort((a, b) => a.datum.compareTo(b.datum));
  final gesamt = rows.fold<int>(0, (s, r) => s + r.minuten);
  final gruppen = <String, int>{};
  for (final r in rows) {
    final t = (r.taetigkeit ?? '').trim().isEmpty ? 'Sonstige Tätigkeit' : r.taetigkeit!.trim();
    gruppen[t] = (gruppen[t] ?? 0) + r.minuten;
  }
  final istGericht = auftrag.art == 'gericht';
  final doc = pw.Document(title: 'Leistungsnachweis ${auftrag.aktenzeichen ?? ''}', creator: 'Aktenwerk');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: pw.EdgeInsets.fromLTRB(_mm(18), _mm(15), _mm(16), _mm(15)),
    theme: await _theme(),
    header: (_) => _kopf('Leistungsnachweis (Zeitaufstellung)', auftrag, _sacheZeile(auftrag)),
    footer: (ctx) => _fuss(ctx, 'Leistungsnachweis · Stand ${_datum.format(DateTime.now())}'),
    build: (_) => [
      pw.TableHelper.fromTextArray(
        headers: ['Datum', 'Zeit', 'Tätigkeit', 'Dauer'],
        data: [
          for (final r in rows)
            [
              _datum.format(r.datum),
              (r.beginn != null && r.ende != null)
                  ? '${_zeit.format(r.beginn!)}–${_zeit.format(r.ende!)}'
                  : '',
              [r.taetigkeit, r.notiz].whereType<String>().where((s) => s.trim().isNotEmpty).join(' – '),
              '${_hm(r.minuten)} h',
            ],
        ],
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey50),
        columnWidths: {
          0: const pw.FixedColumnWidth(62),
          1: const pw.FixedColumnWidth(64),
          2: const pw.FlexColumnWidth(),
          3: const pw.FixedColumnWidth(52),
        },
        cellAlignments: {3: pw.Alignment.centerRight},
      ),
      pw.SizedBox(height: 14),
      pw.Text('Zusammenfassung nach Tätigkeit',
          style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.TableHelper.fromTextArray(
        headers: ['Tätigkeit', 'Summe'],
        data: [for (final e in gruppen.entries) [e.key, '${_hm(e.value)} h']],
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey50),
        columnWidths: {0: const pw.FlexColumnWidth(), 1: const pw.FixedColumnWidth(70)},
        cellAlignments: {1: pw.Alignment.centerRight},
      ),
      pw.SizedBox(height: 10),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('Gesamter Zeitaufwand: ${_hm(gesamt)} h',
              style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
          if (istGericht)
            pw.Text(
                'abrechenbar nach § 8 Abs. 2 S. 2 JVEG: '
                '${jvegAbrechenbareStunden(gesamt).toStringAsFixed(1).replaceAll('.', ',')} h',
                style: const pw.TextStyle(fontSize: 9.5)),
        ]),
      ),
    ],
  ));
  return doc.save();
}

// ---------------------------------------------------------------------------
// Kostennachweis
// ---------------------------------------------------------------------------

Future<Uint8List> buildKostennachweisPdf({
  required AuftraegeData auftrag,
  required List<AuslagenData> auslagen,
  bool nurOffene = false,
}) async {
  final rows = [...auslagen.where((a) => !nurOffene || !a.abgerechnet)]
    ..sort((a, b) => a.datum.compareTo(b.datum));
  double betrag(AuslagenData a) => a.summe != 0 ? a.summe : a.menge * a.einzelpreis;
  final gesamt = rows.fold<double>(0, (s, r) => s + betrag(r));
  final doc = pw.Document(title: 'Kostennachweis ${auftrag.aktenzeichen ?? ''}', creator: 'Aktenwerk');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: pw.EdgeInsets.fromLTRB(_mm(18), _mm(15), _mm(16), _mm(15)),
    theme: await _theme(),
    header: (_) => _kopf('Kostennachweis (Auslagen)', auftrag, _sacheZeile(auftrag)),
    footer: (ctx) => _fuss(ctx, 'Kostennachweis · Stand ${_datum.format(DateTime.now())}'),
    build: (_) => [
      pw.TableHelper.fromTextArray(
        headers: ['Pos.', 'Datum', 'Auslage', 'Menge', 'Einzelpreis', 'Betrag'],
        data: [
          for (var i = 0; i < rows.length; i++)
            [
              '${i + 1}',
              _datum.format(rows[i].datum),
              [rows[i].art, rows[i].beschreibung]
                  .whereType<String>()
                  .where((s) => s.trim().isNotEmpty)
                  .join(' – '),
              '${NumberFormat('#,##0.##', 'de_DE').format(rows[i].menge)} ${rows[i].einheit ?? ''}'.trim(),
              _euro.format(rows[i].einzelpreis),
              _euro.format(betrag(rows[i])),
            ],
        ],
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey50),
        columnWidths: {
          0: const pw.FixedColumnWidth(28),
          1: const pw.FixedColumnWidth(60),
          2: const pw.FlexColumnWidth(),
          3: const pw.FixedColumnWidth(62),
          4: const pw.FixedColumnWidth(66),
          5: const pw.FixedColumnWidth(70),
        },
        cellAlignments: {3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight, 5: pw.Alignment.centerRight},
      ),
      pw.SizedBox(height: 10),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Auslagen gesamt (netto): ${_euro.format(gesamt)}',
            style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
      ),
    ],
  ));
  return doc.save();
}

// ---------------------------------------------------------------------------
// Aktendeckel
// ---------------------------------------------------------------------------

Future<Uint8List> buildAktendeckelPdf({
  required AuftraegeData auftrag,
  KundenData? auftraggeber,
}) async {
  final a = auftrag;
  final gm = AuftragGmExtras.fromAuftragExtras(a.extras);
  final beteiligte = decodeBeteiligte(a.beteiligteJson).where((b) => b.name.trim().isNotEmpty).toList();
  final zusatz = zusatzfelderAus(a.extras);
  String d(DateTime? x) => x == null ? '—' : _datum.format(x);

  pw.Widget kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 120, child: pw.Text(k, style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700))),
          pw.Expanded(child: pw.Text(v.isEmpty ? '—' : v, style: const pw.TextStyle(fontSize: 10))),
        ]),
      );
  pw.Widget block(String titel, List<pw.Widget> kinder) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.blueGrey300, width: 0.6)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(titel, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
          pw.SizedBox(height: 4),
          ...kinder,
        ]),
      );

  final doc = pw.Document(title: 'Aktendeckel ${a.aktenzeichen ?? ''}', creator: 'Aktenwerk');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: pw.EdgeInsets.fromLTRB(_mm(18), _mm(16), _mm(16), _mm(15)),
    theme: await _theme(),
    footer: (ctx) => _fuss(ctx, 'Aktendeckel · Stand ${_datum.format(DateTime.now())}'),
    build: (_) => [
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.blueGrey900, width: 2)),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(a.aktenzeichen ?? '—', style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(buildSacheKurzbezeichnung(a), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              if ((a.betreff ?? '').trim().isNotEmpty)
                pw.Text(a.betreff!, style: const pw.TextStyle(fontSize: 10.5)),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text((a.art).toUpperCase(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey700)),
            if ((a.gerichtsAktenzeichen ?? '').isNotEmpty)
              pw.Text('Az. ${a.gerichtsAktenzeichen}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            if (gm.schadensnummer.isNotEmpty)
              pw.Text('Schaden-Nr. ${gm.schadensnummer}', style: const pw.TextStyle(fontSize: 10.5)),
          ]),
        ]),
      ),
      pw.SizedBox(height: 12),
      block('Auftrag', [
        kv('Auftraggeber', _kundeName(auftraggeber)),
        if ((a.gericht ?? '').isNotEmpty) kv('Gericht', [a.gericht, a.gerichtsort].whereType<String>().where((s) => s.isNotEmpty).join(', ')),
        if ((a.richter ?? '').isNotEmpty) kv('Richter/in', a.richter!),
        if ((a.verfahrensart ?? '').isNotEmpty) kv('Verfahren', a.verfahrensart!),
        kv('Objekt', _objekt(a)),
        kv('Sachgebiet / Satz', [
          jvegCodeLabel(a.honorargruppe),
          if (a.stundensatz != null) '${_euro.format(a.stundensatz)}/h',
        ].where((s) => s.isNotEmpty).join(' · ')),
        if (a.kostenvorschuss != null) kv('Kostenvorschuss', _euro.format(a.kostenvorschuss)),
        if (a.kostenLimit != null) kv('Kostenlimit', _euro.format(a.kostenLimit)),
      ]),
      block('Termine und Fristen', [
        kv('Auftrag erteilt', d(a.auftragAm)),
        kv('Akteneingang', d(a.akteneingangAm)),
        kv('Beweisbeschluss', [a.beweisbeschluss1, a.beweisbeschluss2, a.beweisbeschluss3].whereType<DateTime>().map(_datum.format).join(', ')),
        kv('Ortstermin', a.ortsterminAm == null ? '—' : '${d(a.ortsterminAm)} ${gm.ortsterminUhrzeitVon}'.trim()),
        kv('Frist Gutachten', d(a.fristAm)),
        kv('Abgeschlossen', d(a.abschlussAm)),
      ]),
      if (beteiligte.isNotEmpty)
        block('Beteiligte', [
          pw.TableHelper.fromTextArray(
            headers: ['Rolle', 'Name / Anschrift', 'Kontakt', 'Zeichen'],
            data: [
              for (final b in beteiligte)
                [
                  b.rolle + (b.vertritt.trim().isNotEmpty ? '\n(für ${b.vertritt.trim()})' : ''),
                  [b.name, b.anschrift].where((s) => s.trim().isNotEmpty).join('\n'),
                  [b.telefon, b.email].where((s) => s.trim().isNotEmpty).join('\n'),
                  b.ihrZeichen,
                ],
            ],
            headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey50),
            columnWidths: {
              0: const pw.FixedColumnWidth(90),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(1.4),
              3: const pw.FixedColumnWidth(70),
            },
          ),
        ]),
      if (gm.aktenbaende.isNotEmpty)
        block('Gerichtsakten-Bände', [
          for (final b in gm.aktenbaende)
            kv('Band ${b.bandNr}', '${b.bezeichnung}'
                '${b.seitenVon != null || b.seitenBis != null ? ' (Bl. ${b.seitenVon ?? 1}–${b.seitenBis ?? '?'})' : ''}'
                '${b.eingangAm != null ? ' · Eingang ${_datum.format(b.eingangAm!)}' : ''}'
                '${b.rueckgabeAm != null ? ' · zurück ${_datum.format(b.rueckgabeAm!)}' : ''}'),
        ]),
      if (zusatz.isNotEmpty)
        block('Zusatzfelder', [for (final z in zusatz) kv(z.name, z.wert)]),
      if ((a.notiz ?? '').trim().isNotEmpty)
        block('Bemerkung', [pw.Text(a.notiz!.trim(), style: const pw.TextStyle(fontSize: 9.5))]),
    ],
  ));
  return doc.save();
}
