import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/database/app_database.dart';
import '../../features/akten/gerichtssache/beweisfragen.dart';
import '../../features/akten/nachfragen/nachfragen_repository.dart';

/// Eingangsdaten für die "Ergänzende Stellungnahme zum Gutachten" — Antwort
/// des Sachverständigen auf einen Schriftsatz mit Nachfragen.
class StellungnahmePdfData {
  final AuftraegeData auftrag;
  final KundenData? gericht;
  final BenutzerData? absender;
  final RueckfragenData rueckfrage;
  final List<NachfrageEintrag> fragen;
  final DateTime datum;
  const StellungnahmePdfData({
    required this.auftrag,
    required this.rueckfrage,
    required this.fragen,
    required this.datum,
    this.gericht,
    this.absender,
  });
}

Future<Uint8List> buildStellungnahmePdf(StellungnahmePdfData d) async {
  final doc = pw.Document(
    title:
        'Ergänzende Stellungnahme · ${d.auftrag.aktenzeichen ?? ""}',
    author: [d.absender?.vorname, d.absender?.nachname]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(' '),
    creator: 'Aktenwerk',
    subject: 'Ergänzende gutachterliche Stellungnahme',
  );
  final regular = await PdfGoogleFonts.interRegular();
  final bold = await PdfGoogleFonts.interBold();
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);
  final dateFmt = DateFormat('dd.MM.yyyy', 'de');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.fromLTRB(_mm(25), _mm(25), _mm(20), _mm(20)),
      theme: theme,
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Seite ${ctx.pageNumber} / ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      ),
      build: (ctx) => [
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
          'Ergänzende gutachterliche Stellungnahme',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        _bezugBlock(d, dateFmt),
        pw.SizedBox(height: 16),
        pw.Text(
          (d.rueckfrage.empfaenger ?? '').trim().isNotEmpty
              ? d.rueckfrage.empfaenger!
              : 'Sehr geehrte Damen und Herren,',
          style: const pw.TextStyle(fontSize: 11),
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'zu den im oben genannten Schriftsatz an mich gerichteten Fragen '
          'nehme ich nach erneuter Sichtung der Akte und unter Berücksichtigung '
          'meines bisherigen Gutachtens wie folgt Stellung:',
          style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.5),
        ),
        pw.SizedBox(height: 16),
        ..._beweisfragenBezugsBlock(d.auftrag),
        for (var i = 0; i < d.fragen.length; i++) ..._fragenBlock(d.fragen[i], i),
        pw.SizedBox(height: 16),
        pw.Text(
          'Sollten weitere Erläuterungen erforderlich sein, stehe ich auf '
          'Anforderung gerne zur Verfügung.',
          style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.5),
        ),
        pw.SizedBox(height: 24),
        pw.Text('Mit freundlichen Grüßen',
            style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 40),
        if (d.absender != null) _signaturBlock(d.absender!),
      ],
    ),
  );

  return doc.save();
}

/// Optionaler Bezugs-Block: Beweisfragen aus dem Beweisbeschluss.
/// Hilft Richter und Anwälten, die Stellungnahme den ursprünglichen
/// Beweisfragen zuzuordnen — auch wenn die Nachfragen nur einzelne
/// Aspekte aufgreifen.
List<pw.Widget> _beweisfragenBezugsBlock(AuftraegeData auftrag) {
  final fragen = decodeBeweisfragen(auftrag.beweisfragenJson);
  if (fragen.isEmpty) return const [];
  return [
    pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey50,
        border: pw.Border.all(color: PdfColors.grey300, width: 0.4),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Bezug — Beweisfragen aus dem Beweisbeschluss:',
            style: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800),
          ),
          pw.SizedBox(height: 4),
          for (final f in fragen)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 24,
                    child: pw.Text('${f.nr}.',
                        style: pw.TextStyle(
                            fontSize: 9.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey800)),
                  ),
                  pw.Expanded(
                    child: pw.Text(f.frage,
                        style: const pw.TextStyle(
                            fontSize: 9.5,
                            lineSpacing: 1.3,
                            color: PdfColors.grey800)),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  ];
}

List<pw.Widget> _fragenBlock(NachfrageEintrag e, int idx) {
  final nr = e.nr.trim().isEmpty ? '${idx + 1}' : e.nr.trim();
  return [
    pw.Container(
      margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
      child: pw.Text(
        'Frage $nr',
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.grey800,
        ),
      ),
    ),
    pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Text(
        e.frage.trim().isEmpty ? '(keine Frage angegeben)' : e.frage,
        style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.4),
      ),
    ),
    pw.SizedBox(height: 4),
    pw.Container(
      margin: const pw.EdgeInsets.only(top: 6, bottom: 2),
      child: pw.Text(
        'Stellungnahme',
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    ),
    pw.Text(
      e.antwort.trim().isEmpty ? '(noch zu beantworten)' : e.antwort,
      style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.5),
    ),
    pw.SizedBox(height: 6),
  ];
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

pw.Widget _empfaengerBlock(StellungnahmePdfData d) {
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
        pw.Text(
          lines[i],
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: i == 0 ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
    ],
  );
}

pw.Widget _bezugBlock(StellungnahmePdfData d, DateFormat fmt) {
  final teile = <String>[
    if ((d.auftrag.gerichtsAktenzeichen ?? '').isNotEmpty)
      'Az.: ${d.auftrag.gerichtsAktenzeichen}',
    if ((d.auftrag.aktenzeichen ?? '').isNotEmpty)
      'eigenes Az.: ${d.auftrag.aktenzeichen}',
    if (d.rueckfrage.gutachtenBezugDatum != null)
      'Stellungnahme zu Gutachten vom ${fmt.format(d.rueckfrage.gutachtenBezugDatum!)}',
    if (d.rueckfrage.schriftsatzVom != null)
      'Schriftsatz vom ${fmt.format(d.rueckfrage.schriftsatzVom!)}',
    if ((d.rueckfrage.stellerName ?? '').isNotEmpty)
      'Steller: ${d.rueckfrage.stellerName}',
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

Future<void> previewStellungnahmePdf(StellungnahmePdfData data) =>
    Printing.layoutPdf(
      onLayout: (_) => buildStellungnahmePdf(data),
      name:
          'Stellungnahme_${(data.auftrag.aktenzeichen ?? "").replaceAll(RegExp(r"[^A-Za-z0-9-]"), "_")}.pdf',
    );
