import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/database/app_database.dart';

/// Eingangsdaten für das Gutachtentagebuch (Stundenübersicht).
class TagebuchPdfData {
  final AuftraegeData auftrag;
  final BenutzerData? absender;
  final List<StundenData> stunden;

  const TagebuchPdfData({
    required this.auftrag,
    required this.stunden,
    this.absender,
  });
}

Future<Uint8List> buildTagebuchPdf(TagebuchPdfData d) async {
  final doc = pw.Document(
    title: 'Gutachtentagebuch · ${d.auftrag.aktenzeichen ?? ""}',
    author: [d.absender?.vorname, d.absender?.nachname]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(' '),
    creator: 'Aktenwerk',
    subject: 'Gutachtentagebuch',
  );
  final regular = await PdfGoogleFonts.interRegular();
  final bold = await PdfGoogleFonts.interBold();
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);
  final dateFmt = DateFormat('dd.MM.yyyy', 'de');
  final timeFmt = DateFormat('HH:mm', 'de');

  int totalMinutes = 0;
  for (final s in d.stunden) {
    totalMinutes += s.minuten;
  }
  
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  final totalTime = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} h';

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.fromLTRB(_mm(25), _mm(25), _mm(20), _mm(20)),
      theme: theme,
      build: (ctx) => [
        if (d.absender != null) _absenderBlock(d.absender!),
        pw.SizedBox(height: 12),
        pw.Text(
          'Gutachtentagebuch',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        _bezugBlock(d, dateFmt),
        pw.SizedBox(height: 20),
        
        _stundenTabelle(d.stunden, dateFmt, timeFmt),
        
        pw.SizedBox(height: 12),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Gesamtdauer: $totalTime',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
        ),
        
        pw.SizedBox(height: 40),
        if (d.absender != null) _signaturBlock(d.absender!),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _stundenTabelle(List<StundenData> stunden, DateFormat dateFmt, DateFormat timeFmt) {
  return pw.Table(
    border: pw.TableBorder(
      top: const pw.BorderSide(color: PdfColors.grey400, width: 0.5),
      bottom: const pw.BorderSide(color: PdfColors.grey400, width: 0.5),
      horizontalInside: const pw.BorderSide(color: PdfColors.grey300, width: 0.3),
    ),
    columnWidths: const {
      0: pw.FlexColumnWidth(2),
      1: pw.FlexColumnWidth(4),
      2: pw.FlexColumnWidth(2),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey100),
        children: [
          _zelle('Datum', bold: true),
          _zelle('Tätigkeit', bold: true),
          _zelle('Dauer', bold: true, alignRight: true),
        ],
      ),
      for (final s in stunden)
        pw.TableRow(children: [
          _zelle(dateFmt.format(s.datum)),
          _zelle(s.taetigkeit ?? ''),
          _zelle('${(s.minuten ~/ 60).toString().padLeft(2, '0')}:${(s.minuten % 60).toString().padLeft(2, '0')} h', alignRight: true),
        ]),
    ],
  );
}

pw.Widget _zelle(String text, {bool bold = false, bool alignRight = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );

pw.Widget _absenderBlock(BenutzerData a) {
  final name = [a.vorname, a.nachname]
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .join(' ');
  final lines = <String>[
    if (name.isNotEmpty) name,
    if ((a.titel ?? '').trim().isNotEmpty) a.titel!.trim(),
    if ((a.bestellungsText ?? '').trim().isNotEmpty)
      ...a.bestellungsText!.split('\n').where((s) => s.trim().isNotEmpty),
  ];
  return pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        for (final l in lines)
          pw.Text(l, style: const pw.TextStyle(fontSize: 9)),
      ],
    ),
  );
}

pw.Widget _bezugBlock(TagebuchPdfData d, DateFormat fmt) {
  final teile = <String>[
    if ((d.auftrag.gerichtsAktenzeichen ?? '').isNotEmpty)
      'Az.: ${d.auftrag.gerichtsAktenzeichen}',
    if ((d.auftrag.aktenzeichen ?? '').isNotEmpty)
      'eigenes Az.: ${d.auftrag.aktenzeichen}',
    if (d.auftrag.beweisbeschluss1 != null)
      'Beweisbeschluss vom ${fmt.format(d.auftrag.beweisbeschluss1!)}',
  ];
  if (teile.isEmpty) return pw.SizedBox();
  return pw.Text(teile.join(' · '),
      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700));
}

pw.Widget _signaturBlock(BenutzerData a) {
  final name = [a.vorname, a.nachname]
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .join(' ');
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(width: 200, height: 0.5, color: PdfColors.grey400),
      pw.SizedBox(height: 3),
      if (name.isNotEmpty)
        pw.Text(name,
            style: pw.TextStyle(
                fontSize: 10, fontWeight: pw.FontWeight.bold)),
      if ((a.titel ?? '').trim().isNotEmpty)
        pw.Text(a.titel!,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
    ],
  );
}

double _mm(double v) => v * PdfPageFormat.mm;

Future<void> previewTagebuchPdf(TagebuchPdfData data) =>
    Printing.layoutPdf(
      onLayout: (_) => buildTagebuchPdf(data),
      name:
          'Gutachtentagebuch_${(data.auftrag.aktenzeichen ?? "").replaceAll(RegExp(r"[^A-Za-z0-9-]"), "_")}.pdf',
    );
