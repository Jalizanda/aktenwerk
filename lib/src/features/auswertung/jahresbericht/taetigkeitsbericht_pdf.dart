import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../data/database/app_database.dart';

double _mm(double v) => v * 72 / 25.4;

/// Eingangsdaten für den Tätigkeitsbericht.
class TaetigkeitsberichtData {
  final int jahr;
  final BenutzerData? absender;
  final List<AuftraegeData> auftraege;
  final List<KundenData> kunden;
  final List<RechnungenData> rechnungen;
  final List<FortbildungenData> fortbildungen;
  final Uint8List? siegelBytes;
  final String? bestellBehoerde;
  final String? bestellNr;
  final DateTime? bestellGueltigBis;

  /// Editierbare Vorlagetexte aus den Einstellungen.
  final String empfaenger;
  final String vorwort;
  final String eidesstattlich;

  const TaetigkeitsberichtData({
    required this.jahr,
    required this.auftraege,
    required this.kunden,
    required this.rechnungen,
    required this.fortbildungen,
    this.absender,
    this.siegelBytes,
    this.bestellBehoerde,
    this.bestellNr,
    this.bestellGueltigBis,
    this.empfaenger = '',
    this.vorwort = '',
    this.eidesstattlich = '',
  });
}

Future<Uint8List> buildTaetigkeitsberichtPdf(
    TaetigkeitsberichtData d) async {
  final doc = pw.Document();
  final dateFmt = DateFormat('dd.MM.yyyy', 'de');
  final money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
  final regular = await PdfGoogleFonts.interRegular();
  final bold = await PdfGoogleFonts.interBold();
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);
  final absName = [
    d.absender?.titel,
    d.absender?.vorname,
    d.absender?.nachname,
  ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
  final absAnschrift = [
    d.absender?.firma,
    d.absender?.strasse,
    '${d.absender?.plz ?? ''} ${d.absender?.ort ?? ''}',
  ].whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  final kundeById = {for (final k in d.kunden) k.id: k};

  // ---------- Deckblatt ----------
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: pw.EdgeInsets.fromLTRB(_mm(22), _mm(30), _mm(18), _mm(25)),
    theme: theme,
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (d.siegelBytes != null)
          pw.Align(
            alignment: pw.Alignment.topRight,
            child: pw.Container(
              width: _mm(38),
              height: _mm(38),
              child: pw.Image(pw.MemoryImage(d.siegelBytes!),
                  fit: pw.BoxFit.contain),
            ),
          ),
        pw.SizedBox(height: _mm(10)),
        pw.Text('Tätigkeitsbericht',
            style: pw.TextStyle(
                fontSize: 28, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('für das Kalenderjahr ${d.jahr}',
            style: const pw.TextStyle(fontSize: 18)),
        pw.SizedBox(height: _mm(18)),
        pw.Text(absName.isEmpty ? '(Sachverständiger)' : absName,
            style: pw.TextStyle(
                fontSize: 14, fontWeight: pw.FontWeight.bold)),
        for (final l in absAnschrift)
          pw.Text(l, style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: _mm(12)),
        if ((d.bestellBehoerde ?? '').isNotEmpty)
          pw.Text('Öffentlich bestellt und vereidigt durch '
              '${d.bestellBehoerde}',
              style: const pw.TextStyle(fontSize: 11)),
        if ((d.bestellNr ?? '').isNotEmpty)
          pw.Text('Bestellnummer: ${d.bestellNr}',
              style: const pw.TextStyle(fontSize: 11)),
        if (d.bestellGueltigBis != null)
          pw.Text(
              'Bestellung gültig bis: ${dateFmt.format(d.bestellGueltigBis!)}',
              style: const pw.TextStyle(fontSize: 11)),
        pw.Spacer(),
        if ((d.empfaenger).trim().isNotEmpty) ...[
          pw.Text('Einzureichen bei:',
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(d.empfaenger, style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: _mm(10)),
        ],
        pw.Text('Erstellt am ${dateFmt.format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      ],
    ),
  ));

  // ---------- Statistik ----------
  final byArt = <String, int>{};
  final bySachgebiet = <String, int>{};
  var aufAbgeschlossen = 0;
  var aufLaufend = 0;
  for (final a in d.auftraege) {
    byArt.update(a.art, (v) => v + 1, ifAbsent: () => 1);
    final sg = (a.sachgebiet ?? 'ohne').toLowerCase();
    bySachgebiet.update(sg, (v) => v + 1, ifAbsent: () => 1);
    if (a.status == 'abgeschlossen' || a.status == 'abgerechnet') {
      aufAbgeschlossen++;
    } else if (a.status != 'storniert') {
      aufLaufend++;
    }
  }
  final umsatzGesamt = d.rechnungen
      .where((r) => r.status != 'storniert')
      .fold<double>(0, (s, r) => s + r.netto);

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: pw.EdgeInsets.fromLTRB(_mm(22), _mm(20), _mm(18), _mm(20)),
    theme: theme,
    header: (ctx) => pw.Padding(
      padding: pw.EdgeInsets.only(bottom: _mm(6)),
      child: pw.Text('Tätigkeitsbericht ${d.jahr}',
          style: pw.TextStyle(
              fontSize: 11, color: PdfColors.grey700)),
    ),
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Seite ${ctx.pageNumber} / ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
    ),
    build: (ctx) => [
      if (d.vorwort.trim().isNotEmpty) ...[
        pw.Text('Vorwort',
            style: pw.TextStyle(
                fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(d.vorwort,
            style: const pw.TextStyle(fontSize: 11, lineSpacing: 3)),
        pw.SizedBox(height: _mm(8)),
      ],
      pw.Text('Statistik ${d.jahr}',
          style: pw.TextStyle(
              fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      _stat('Aufträge gesamt', '${d.auftraege.length}'),
      _stat('    davon abgeschlossen / abgerechnet', '$aufAbgeschlossen'),
      _stat('    davon laufend / offen', '$aufLaufend'),
      _stat('Rechnungen (ohne Stornos)', '${d.rechnungen.where((r) => r.status != "storniert").length}'),
      _stat('Umsatz netto', money.format(umsatzGesamt)),
      pw.SizedBox(height: _mm(4)),
      pw.Text('Verteilung nach Auftragsart',
          style: pw.TextStyle(
              fontSize: 12, fontWeight: pw.FontWeight.bold)),
      for (final e in byArt.entries)
        _stat('  ${e.key}', '${e.value}'),
      pw.SizedBox(height: _mm(3)),
      pw.Text('Verteilung nach Sachgebiet',
          style: pw.TextStyle(
              fontSize: 12, fontWeight: pw.FontWeight.bold)),
      for (final e in bySachgebiet.entries)
        _stat('  ${e.key}', '${e.value}'),
      pw.SizedBox(height: _mm(8)),

      pw.Text('Fortbildungen ${d.jahr}',
          style: pw.TextStyle(
              fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      if (d.fortbildungen.isEmpty)
        pw.Text('Keine Fortbildungen dokumentiert.',
            style: const pw.TextStyle(fontSize: 10))
      else
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          headerDecoration:
              const pw.BoxDecoration(color: PdfColors.grey200),
          headerStyle: pw.TextStyle(
              fontSize: 10, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 10),
          headers: const ['Datum', 'Titel', 'Veranstalter', 'UE (h)'],
          data: [
            for (final f in d.fortbildungen)
              [
                f.datumVon == null ? '' : dateFmt.format(f.datumVon!),
                f.titel,
                f.veranstalter ?? '',
                f.stunden.toStringAsFixed(1),
              ],
          ],
        ),
      pw.SizedBox(height: 4),
      pw.Text(
          'Summe Unterrichtseinheiten: '
          '${d.fortbildungen.fold<double>(0, (s, f) => s + f.stunden).toStringAsFixed(1)}\u00a0h',
          style: pw.TextStyle(
              fontSize: 10, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: _mm(8)),

      pw.Text('Auftragsliste ${d.jahr} (anonymisiert)',
          style: pw.TextStyle(
              fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.TableHelper.fromTextArray(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        headerStyle: pw.TextStyle(
            fontSize: 9.5, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 9.5),
        columnWidths: const {
          0: pw.FlexColumnWidth(2),
          1: pw.FlexColumnWidth(2),
          2: pw.FlexColumnWidth(3),
          3: pw.FlexColumnWidth(2),
          4: pw.FlexColumnWidth(2),
        },
        headers: const [
          'Az.',
          'Datum',
          'Sachgebiet',
          'Art',
          'Auftraggeber-Typ',
        ],
        data: [
          for (final a in d.auftraege)
            [
              a.aktenzeichen ?? '',
              a.eingangAm == null ? '' : dateFmt.format(a.eingangAm!),
              a.sachgebiet ?? '',
              a.art,
              kundeById[a.kundeId ?? -1]?.typ ?? '—',
            ],
        ],
      ),
      pw.SizedBox(height: _mm(12)),

      pw.Text('Eidesstattliche Erklärung',
          style: pw.TextStyle(
              fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Text(
          d.eidesstattlich.trim().isNotEmpty
              ? d.eidesstattlich
              : 'Ich versichere, dass die vorstehenden Angaben vollständig '
                  'und wahrheitsgemäß sind. Die im Berichtsjahr durchgeführten '
                  'Gutachten wurden unparteiisch, weisungsfrei und nach '
                  'bestem Wissen und Gewissen erstellt.',
          style: const pw.TextStyle(fontSize: 11, lineSpacing: 3)),
      pw.SizedBox(height: _mm(16)),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                    [d.absender?.ort, dateFmt.format(DateTime.now())]
                        .whereType<String>()
                        .where((s) => s.isNotEmpty)
                        .join(', '),
                    style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: _mm(12)),
                pw.Container(
                    width: _mm(70),
                    height: 0.8,
                    color: PdfColors.grey500),
                pw.SizedBox(height: 2),
                pw.Text(absName.isEmpty ? '(Sachverständiger)' : absName,
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          if (d.siegelBytes != null)
            pw.Container(
              width: _mm(35),
              height: _mm(35),
              child: pw.Image(pw.MemoryImage(d.siegelBytes!),
                  fit: pw.BoxFit.contain),
            ),
        ],
      ),
    ],
  ));

  return doc.save();
}

pw.Widget _stat(String label, String value) => pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          ),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );

Future<void> previewTaetigkeitsbericht(TaetigkeitsberichtData d) async {
  await Printing.layoutPdf(
    onLayout: (_) => buildTaetigkeitsberichtPdf(d),
    name: 'Taetigkeitsbericht_${d.jahr}.pdf',
  );
}

/// Decodiert einen Base64-Siegel-Wert aus den Einstellungen.
Uint8List? decodeSiegelBase64(String? b64) {
  if (b64 == null || b64.isEmpty) return null;
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}
