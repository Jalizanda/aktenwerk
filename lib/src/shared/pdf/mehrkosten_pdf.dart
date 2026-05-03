import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/database/app_database.dart';

/// Eingangsdaten für die Mehrkostenanzeige gem. § 8a Abs. 4 JVEG.
class MehrkostenPdfData {
  final AuftraegeData auftrag;
  final KundenData? gericht;
  final BenutzerData? absender;
  final DateTime datum;
  final double bisherigerKostenrahmen;
  final double neuerKostenrahmen;
  final String? begruendung;
  const MehrkostenPdfData({
    required this.auftrag,
    required this.datum,
    required this.bisherigerKostenrahmen,
    required this.neuerKostenrahmen,
    this.gericht,
    this.absender,
    this.begruendung,
  });
}

Future<Uint8List> buildMehrkostenPdf(MehrkostenPdfData d) async {
  final doc = pw.Document(
    title: 'Mehrkostenanzeige · ${d.auftrag.aktenzeichen ?? ""}',
    author: [d.absender?.vorname, d.absender?.nachname]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(' '),
    creator: 'Aktenwerk',
    subject: 'Mehrkostenanzeige gem. § 8a Abs. 4 JVEG',
  );
  final regular = await PdfGoogleFonts.interRegular();
  final bold = await PdfGoogleFonts.interBold();
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);
  final dateFmt = DateFormat('dd.MM.yyyy', 'de');
  final money = NumberFormat.currency(
      locale: 'de_DE', symbol: '€', decimalDigits: 2);
  final differenz = d.neuerKostenrahmen - d.bisherigerKostenrahmen;

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.fromLTRB(_mm(25), _mm(25), _mm(20), _mm(20)),
      theme: theme,
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (d.absender != null) _absenderBlock(d.absender!),
          pw.SizedBox(height: 12),
          _empfaengerBlock(d),
          pw.SizedBox(height: 30),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '${d.absender?.ort ?? ''}${d.absender?.ort == null ? '' : ', '}${dateFmt.format(d.datum)}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Mehrkostenanzeige gem. § 8a Abs. 4 JVEG',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          _bezugBlock(d, dateFmt),
          pw.SizedBox(height: 16),
          pw.Text('Sehr geehrte Damen und Herren,',
              style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 10),
          pw.Text(
            'in der oben genannten Sache zeige ich gemäß § 8a Abs. 4 JVEG '
            'an, dass die voraussichtlich entstehenden Kosten für die '
            'Erstellung des Sachverständigengutachtens den bisher angesetzten '
            'Kostenrahmen erheblich überschreiten werden. Ich bitte deshalb '
            'um Mitteilung, ob am Auftrag in der bisherigen Form festgehalten '
            'werden soll.',
            style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.5),
          ),
          pw.SizedBox(height: 14),
          _kostenTabelle(
              d.bisherigerKostenrahmen, d.neuerKostenrahmen, differenz, money),
          if ((d.begruendung ?? '').trim().isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Text('Begründung des Mehraufwands:',
                style:
                    pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(d.begruendung!,
                style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.5)),
          ],
          pw.SizedBox(height: 16),
          pw.Text(
            'Bis zur Entscheidung des Gerichts werde ich die Bearbeitung in '
            'dem Umfang einstellen, in dem dadurch eine weitere Kostenmehrung '
            'eintreten würde.',
            style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.5),
          ),
          pw.SizedBox(height: 24),
          pw.Text('Mit freundlichen Grüßen',
              style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 40),
          if (d.absender != null) _signaturBlock(d.absender!),
        ],
      ),
    ),
  );
  return doc.save();
}

pw.Widget _kostenTabelle(double bisher, double neu, double diff, NumberFormat money) {
  return pw.Table(
    border: pw.TableBorder(
      top: const pw.BorderSide(color: PdfColors.grey400, width: 0.5),
      bottom: const pw.BorderSide(color: PdfColors.grey400, width: 0.5),
      horizontalInside:
          const pw.BorderSide(color: PdfColors.grey300, width: 0.3),
    ),
    columnWidths: const {
      0: pw.FlexColumnWidth(7),
      1: pw.FlexColumnWidth(2),
    },
    children: [
      pw.TableRow(children: [
        _zelle('Bisher angesetzter Kostenrahmen'),
        _zelle(money.format(bisher), alignRight: true),
      ]),
      pw.TableRow(children: [
        _zelle('Voraussichtlich erforderlicher Kostenrahmen',
            bold: true),
        _zelle(money.format(neu), bold: true, alignRight: true),
      ]),
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey100),
        children: [
          _zelle('Mehrbedarf', bold: true),
          _zelle(money.format(diff), bold: true, alignRight: true),
        ],
      ),
    ],
  );
}

pw.Widget _zelle(String text,
        {bool bold = false, bool alignRight = false}) =>
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

pw.Widget _empfaengerBlock(MehrkostenPdfData d) {
  final g = d.gericht;
  final lines = <String>[
    if (g?.firma != null && g!.firma!.trim().isNotEmpty) g.firma!,
    if (g?.strasse != null && g!.strasse!.trim().isNotEmpty) g.strasse!,
    [g?.plz, g?.ort]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(' '),
  ].where((s) => s.trim().isNotEmpty).toList();
  if (lines.isEmpty) {
    final ort = d.auftrag.gerichtsort;
    final gericht = d.auftrag.gericht;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if ((gericht ?? '').isNotEmpty)
          pw.Text(gericht!,
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold)),
        if ((ort ?? '').isNotEmpty)
          pw.Text(ort!, style: const pw.TextStyle(fontSize: 11)),
      ],
    );
  }
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < lines.length; i++)
        pw.Text(lines[i],
            style: pw.TextStyle(
                fontSize: 11,
                fontWeight: i == 0
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal)),
    ],
  );
}

pw.Widget _bezugBlock(MehrkostenPdfData d, DateFormat fmt) {
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

Future<void> previewMehrkostenPdf(MehrkostenPdfData data) =>
    Printing.layoutPdf(
      onLayout: (_) => buildMehrkostenPdf(data),
      name:
          'Mehrkostenanzeige_${(data.auftrag.aktenzeichen ?? "").replaceAll(RegExp(r"[^A-Za-z0-9-]"), "_")}.pdf',
    );
