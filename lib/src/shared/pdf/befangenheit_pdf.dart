import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/database/app_database.dart';

/// Eingangsdaten für die "Erklärung zur Unbefangenheit gem. §§ 406 / 407 ZPO".
class BefangenheitPdfData {
  final AuftraegeData auftrag;
  final KundenData? gericht;
  final BenutzerData? absender;
  final DateTime datum;
  final String ergebnis; // 'unbefangen' | 'befangen'
  final String? notiz;
  const BefangenheitPdfData({
    required this.auftrag,
    required this.datum,
    required this.ergebnis,
    this.gericht,
    this.absender,
    this.notiz,
  });
}

Future<Uint8List> buildBefangenheitPdf(BefangenheitPdfData d) async {
  final doc = pw.Document(
    title:
        'Befangenheitserklärung · ${d.auftrag.aktenzeichen ?? ""}',
    author: [d.absender?.vorname, d.absender?.nachname]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(' '),
    creator: 'Aktenwerk',
    subject: 'Erklärung zur Unbefangenheit gem. §§ 406 / 407 ZPO',
  );
  final regular = await PdfGoogleFonts.interRegular();
  final bold = await PdfGoogleFonts.interBold();
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);
  final dateFmt = DateFormat('dd.MM.yyyy', 'de');
  final unbefangen = d.ergebnis != 'befangen';

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
            unbefangen
                ? 'Erklärung zur Unbefangenheit gem. §§ 406, 407 ZPO'
                : 'Anzeige der Befangenheit gem. §§ 406, 407 ZPO',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          _bezugBlock(d, dateFmt),
          pw.SizedBox(height: 16),
          pw.Text('Sehr geehrte Damen und Herren,',
              style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 10),
          pw.Text(
            unbefangen
                ? 'in der oben genannten Sache erkläre ich, dass mir keine '
                    'Tatsachen bekannt sind, die geeignet sind, Misstrauen '
                    'gegen meine Unparteilichkeit zu begründen. Insbesondere '
                    'bestehen zu keiner der Parteien — auch nicht zu deren '
                    'Bevollmächtigten oder zu anderen Beteiligten — '
                    'persönliche, geschäftliche oder verwandtschaftliche '
                    'Beziehungen, die eine Befangenheit i. S. d. § 406 ZPO '
                    'begründen könnten.'
                : 'in der oben genannten Sache zeige ich Umstände an, die '
                    'geeignet sein können, Misstrauen gegen meine '
                    'Unparteilichkeit zu begründen. Ich bitte um Entscheidung, '
                    'ob mir der Auftrag dennoch übertragen werden kann.',
            style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.5),
          ),
          if ((d.notiz ?? '').trim().isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Text('Erläuterung:',
                style:
                    pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(d.notiz!,
                style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.5)),
          ],
          pw.SizedBox(height: 16),
          pw.Text(
            unbefangen
                ? 'Ich nehme den Auftrag zur Erstellung des angeforderten '
                    'Sachverständigengutachtens an.'
                : 'Eine endgültige Annahme des Auftrags erfolgt vorbehaltlich '
                    'der Entscheidung des Gerichts.',
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

pw.Widget _empfaengerBlock(BefangenheitPdfData d) {
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

pw.Widget _bezugBlock(BefangenheitPdfData d, DateFormat fmt) {
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

Future<void> previewBefangenheitPdf(BefangenheitPdfData data) =>
    Printing.layoutPdf(
      onLayout: (_) => buildBefangenheitPdf(data),
      name:
          'Befangenheit_${(data.auftrag.aktenzeichen ?? "").replaceAll(RegExp(r"[^A-Za-z0-9-]"), "_")}.pdf',
    );
