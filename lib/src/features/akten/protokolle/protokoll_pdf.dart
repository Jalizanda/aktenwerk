import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../data/database/app_database.dart';
import '../../../shared/richtext/quill_editor.dart';
import 'protokolle_tab.dart';

double _mm(double v) => v * 72 / 25.4;

/// Generiert das A4-Protokoll mit Anwesenheitsliste und Unterschriftenlinien.
Future<Uint8List> buildProtokollPdf(
    ProtokolleData p, AuftraegeData a, List<Teilnehmer> teilnehmer) async {
  final doc = pw.Document();
  final regular = await PdfGoogleFonts.interRegular();
  final bold = await PdfGoogleFonts.interBold();
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);
  final dateFmt = DateFormat('dd.MM.yyyy', 'de');
  final timeFmt = DateFormat('HH:mm', 'de');
  final protokollText = plainTextFromDeltaJson(p.protokollJson);

  // QR-Code-Payload — eindeutige ID für digitale Bestätigung.
  final qrPayload = jsonEncode({
    'typ': 'aktenwerk.ortstermin',
    'protokollId': p.id,
    'auftragId': a.id,
    'az': a.aktenzeichen,
    'datum': p.datum.toIso8601String(),
  });

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: pw.EdgeInsets.fromLTRB(_mm(22), _mm(20), _mm(18), _mm(20)),
    theme: theme,
    header: (ctx) => pw.Padding(
      padding: pw.EdgeInsets.only(bottom: _mm(8)),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Protokoll Ortstermin',
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Akte ${a.aktenzeichen ?? ""}'
                  '${(a.betreff ?? "").isNotEmpty ? " · ${a.betreff}" : ""}',
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: qrPayload,
            width: _mm(22),
            height: _mm(22),
          ),
        ],
      ),
    ),
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Seite ${ctx.pageNumber} / ${ctx.pagesCount}',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
    ),
    build: (ctx) => [
      // Stammdaten-Block
      pw.Container(
        decoration: pw.BoxDecoration(
          color: PdfColors.grey200,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        padding: pw.EdgeInsets.symmetric(horizontal: _mm(6), vertical: _mm(4)),
        child: pw.Row(
          children: [
            _kv('Datum', dateFmt.format(p.datum)),
            _kv('Beginn', timeFmt.format(p.datum)),
            _kv('Dauer', '${p.dauerMinuten} min'),
            _kv('Ort', p.ort ?? a.objektOrt ?? '—'),
            if ((p.wetter ?? '').isNotEmpty) _kv('Wetter', p.wetter!),
          ],
        ),
      ),
      pw.SizedBox(height: _mm(6)),
      pw.Text('Teilnehmer',
          style: pw.TextStyle(
              fontSize: 13, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: _mm(2)),
      _teilnehmerTabelle(teilnehmer),
      pw.SizedBox(height: _mm(8)),
      if (protokollText.trim().isNotEmpty) ...[
        pw.Text('Protokoll',
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: _mm(2)),
        pw.Text(protokollText, style: const pw.TextStyle(fontSize: 11, lineSpacing: 3)),
        pw.SizedBox(height: _mm(8)),
      ],
      pw.Text('Unterschriften',
          style: pw.TextStyle(
              fontSize: 13, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: _mm(4)),
      _unterschriften(teilnehmer),
    ],
  ));

  return doc.save();
}

Future<void> previewProtokollPdf(
    ProtokolleData p, AuftraegeData a, List<Teilnehmer> teilnehmer) async {
  await Printing.layoutPdf(
    onLayout: (_) => buildProtokollPdf(p, a, teilnehmer),
    name: 'Protokoll_${a.aktenzeichen ?? a.id}_${p.id}.pdf',
  );
}

pw.Widget _kv(String k, String v) => pw.Padding(
      padding: pw.EdgeInsets.only(right: _mm(8)),
      child: pw.RichText(
        text: pw.TextSpan(children: [
          pw.TextSpan(
              text: '$k: ',
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey700)),
          pw.TextSpan(
              text: v,
              style: const pw.TextStyle(fontSize: 10)),
        ]),
      ),
    );

pw.Widget _teilnehmerTabelle(List<Teilnehmer> tl) {
  if (tl.isEmpty) {
    return pw.Text('Keine Teilnehmer erfasst.',
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600));
  }
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
    columnWidths: const {
      0: pw.FlexColumnWidth(3),
      1: pw.FlexColumnWidth(2),
      2: pw.FlexColumnWidth(2),
      3: pw.FlexColumnWidth(3),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: ['Name', 'Rolle', 'Firma', 'E-Mail'].map((s) =>
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(s,
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
            )).toList(),
      ),
      for (final t in tl)
        pw.TableRow(children: [
          pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(t.name.isEmpty ? '—' : t.name,
                  style: const pw.TextStyle(fontSize: 10))),
          pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(t.rolle,
                  style: const pw.TextStyle(fontSize: 10))),
          pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(t.firma,
                  style: const pw.TextStyle(fontSize: 10))),
          pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(t.email,
                  style: const pw.TextStyle(fontSize: 10))),
        ]),
    ],
  );
}

pw.Widget _unterschriften(List<Teilnehmer> tl) {
  if (tl.isEmpty) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 3; i++) _sigLine(name: ''),
      ],
    );
  }
  return pw.Wrap(
    spacing: _mm(14),
    runSpacing: _mm(10),
    children: [
      for (final t in tl)
        pw.Container(
          width: _mm(85),
          child: _sigLine(
              name: t.name.isEmpty
                  ? (t.rolle.isEmpty ? '—' : t.rolle)
                  : t.name),
        ),
    ],
  );
}

pw.Widget _sigLine({required String name}) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: _mm(14)),
        pw.Container(
          height: 0.8,
          color: PdfColors.grey600,
        ),
        pw.SizedBox(height: 2),
        pw.Text(name.isEmpty ? '(Unterschrift)' : name,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      ],
    );
