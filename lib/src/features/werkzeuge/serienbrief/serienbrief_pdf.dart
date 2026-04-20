import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../data/database/app_database.dart';
import '../../../features/akten/kunden/kunden_repository.dart';

/// Ein Serienbrief-Eintrag — pro Empfänger.
class SerienEintrag {
  final KundenData kunde;
  final String anrede;
  final String brieftext;
  const SerienEintrag(
      {required this.kunde,
      required this.anrede,
      required this.brieftext});
}

double _mm(double v) => v * 72 / 25.4;

/// Erzeugt ein mehrseitiges PDF — 1 Seite pro Empfänger — aus dem
/// Serienbrief-Entwurf. Wird via Drucker-Dialog ausgegeben und von der
/// Akten-Liste als Anschreiben-Beleg geführt.
Future<Uint8List> buildSerienbriefPdf({
  required List<SerienEintrag> eintraege,
  required BenutzerData? absender,
  required String betreff,
  required String gruss,
  required DateTime datum,
}) async {
  final doc = pw.Document();
  final regular = await PdfGoogleFonts.interRegular();
  final bold = await PdfGoogleFonts.interBold();
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);
  final dateFmt = DateFormat('dd.MM.yyyy', 'de');

  final absName = [
    absender?.titel,
    absender?.vorname,
    absender?.nachname,
  ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
  final absFirma = absender?.firma ?? '';
  final absAnschrift = [
    absender?.strasse,
    '${absender?.plz ?? ''} ${absender?.ort ?? ''}'.trim(),
  ].whereType<String>().where((s) => s.isNotEmpty).toList();

  for (final e in eintraege) {
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.fromLTRB(_mm(25), _mm(25), _mm(20), _mm(20)),
      theme: theme,
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Absender-Kurzzeile
          pw.Text(
            [
              if (absFirma.isNotEmpty) absFirma else absName,
              if (absAnschrift.isNotEmpty) absAnschrift.join(' · '),
            ].where((s) => s.isNotEmpty).join(' · '),
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
          pw.Container(height: 0.5, color: PdfColors.grey500),
          pw.SizedBox(height: _mm(6)),
          // Empfängeradresse
          pw.Text(
            [
              e.kunde.firma,
              if ((e.kunde.firma ?? '').isEmpty) kundeAnzeigename(e.kunde),
            ].whereType<String>().where((s) => s.isNotEmpty).join('\n'),
            style: const pw.TextStyle(fontSize: 10),
          ),
          if ((e.kunde.firma ?? '').isNotEmpty)
            pw.Text(
              'z. Hd. ${[e.kunde.vorname, e.kunde.nachname].whereType<String>().where((s) => s.isNotEmpty).join(' ')}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          pw.Text(e.kunde.strasse ?? '',
              style: const pw.TextStyle(fontSize: 10)),
          pw.Text(
              [e.kunde.plz, e.kunde.ort]
                  .whereType<String>()
                  .where((s) => s.isNotEmpty)
                  .join(' '),
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: _mm(12)),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
                (absender?.ort == null || absender!.ort!.isEmpty
                        ? ''
                        : '${absender.ort!}, ') +
                    dateFmt.format(datum),
                style: const pw.TextStyle(fontSize: 10)),
          ),
          pw.SizedBox(height: _mm(6)),
          pw.Text(betreff,
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: _mm(6)),
          pw.Text(e.anrede,
              style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: _mm(4)),
          pw.Text(e.brieftext,
              style:
                  const pw.TextStyle(fontSize: 11, lineSpacing: 3)),
          pw.SizedBox(height: _mm(10)),
          pw.Text(gruss, style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: _mm(14)),
          pw.Text(absName.isEmpty ? absFirma : absName,
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    ));
  }
  return doc.save();
}
