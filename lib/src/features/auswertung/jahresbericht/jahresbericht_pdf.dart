import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftraege_repository.dart';
import '../../../features/akten/rechnungen/rechnungen_repository.dart';

class JahresberichtPdfData {
  final int jahr;
  final List<AuftragWithKunde> auftraege;
  final List<RechnungWithKunde> rechnungen;
  final Map<int, double> fortbSummen; // jahr → stunden
  final BenutzerData? absender;
  const JahresberichtPdfData({
    required this.jahr,
    required this.auftraege,
    required this.rechnungen,
    required this.fortbSummen,
    this.absender,
  });
}

Future<Uint8List> buildJahresberichtPdf(JahresberichtPdfData d) async {
  final doc = pw.Document();
  final money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
  final theme = pw.ThemeData.withFont(
    base: await PdfGoogleFonts.interRegular(),
    bold: await PdfGoogleFonts.interBold(),
  );

  final jahrStart = DateTime(d.jahr, 1, 1);
  final jahrEnde = DateTime(d.jahr + 1, 1, 1);

  // --- Aggregate ---
  final auftraegeJahr = d.auftraege.where((a) {
    final cm = a.auftrag.auftragAm ?? a.auftrag.createdAt;
    return !cm.isBefore(jahrStart) && cm.isBefore(jahrEnde);
  }).toList();
  final rechnungenJahr = d.rechnungen.where((r) {
    final dt = r.rechnung.rechnungsdatum;
    return dt != null && !dt.isBefore(jahrStart) && dt.isBefore(jahrEnde);
  }).toList();

  final neueAuftraege = auftraegeJahr.length;
  final gerichtsauftraege =
      auftraegeJahr.where((a) => a.auftrag.art == 'gericht').length;
  final privatauftraege =
      auftraegeJahr.where((a) => a.auftrag.art == 'privat').length;
  final abgeschlossen = auftraegeJahr
      .where((a) =>
          a.auftrag.status == 'abgeschlossen' ||
          a.auftrag.status == 'abgerechnet')
      .length;

  final umsatzNetto = rechnungenJahr.fold<double>(
      0, (s, r) => r.rechnung.status == 'storniert' ? s : s + r.rechnung.netto);
  final umsatzBrutto = rechnungenJahr.fold<double>(
      0, (s, r) => r.rechnung.status == 'storniert' ? s : s + r.rechnung.brutto);
  final bezahlt = rechnungenJahr.fold<double>(
      0, (s, r) => s + r.rechnung.bezahlt);
  final offeneForderungen = rechnungenJahr.fold<double>(0, (s, r) {
    if (r.rechnung.status == 'storniert' || r.rechnung.status == 'bezahlt') {
      return s;
    }
    return s + (r.rechnung.brutto - r.rechnung.bezahlt);
  });

  // Kategorien
  final kategorien = <String, int>{};
  for (final a in auftraegeJahr) {
    final k = a.auftrag.kategorie ?? 'Sonstiges';
    kategorien[k] = (kategorien[k] ?? 0) + 1;
  }

  final fortbStunden = d.fortbSummen[d.jahr] ?? 0;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.fromLTRB(_mm(22), _mm(18), _mm(18), _mm(18)),
      theme: theme,
      header: (ctx) => _kopf(d),
      footer: (ctx) => _fuss(ctx),
      build: (ctx) => [
        pw.SizedBox(height: _mm(8)),
        pw.Text('Jahresbericht ${d.jahr}',
            style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: _mm(2)),
        pw.Text(
            'Zusammenfassung der Sachverständigentätigkeit nach den Anforderungen '
                'der IHK bzw. Bestellungskörperschaft.',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: _mm(8)),
        _kpiRow([
          _Kpi('Neue Aufträge', neueAuftraege.toString()),
          _Kpi('Gerichtsgutachten', gerichtsauftraege.toString()),
          _Kpi('Privatgutachten', privatauftraege.toString()),
          _Kpi('Abgeschlossen', abgeschlossen.toString()),
        ]),
        pw.SizedBox(height: _mm(6)),
        _kpiRow([
          _Kpi('Umsatz netto', money.format(umsatzNetto)),
          _Kpi('Umsatz brutto', money.format(umsatzBrutto)),
          _Kpi('Bezahlt', money.format(bezahlt)),
          _Kpi('Offene Forderungen', money.format(offeneForderungen)),
        ]),
        pw.SizedBox(height: _mm(10)),
        pw.Text('Verteilung nach Kategorie',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: _mm(4)),
        if (kategorien.isEmpty)
          pw.Text('Keine Einträge.', style: const pw.TextStyle(fontSize: 10))
        else
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(5),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(3),
            },
            border: const pw.TableBorder(
              horizontalInside:
                  pw.BorderSide(color: PdfColors.grey300, width: 0.3),
            ),
            children: [
              pw.TableRow(
                decoration:
                    const pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  _th('Kategorie'),
                  _th('Anzahl'),
                  _th('Anteil %'),
                ],
              ),
              for (final e in kategorien.entries)
                pw.TableRow(children: [
                  _td(e.key),
                  _td(e.value.toString(), alignRight: true),
                  _td(
                      '${(e.value / neueAuftraege * 100).toStringAsFixed(0)} %',
                      alignRight: true),
                ]),
            ],
          ),
        pw.SizedBox(height: _mm(10)),
        pw.Text('Fortbildung',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: _mm(2)),
        pw.Text(
          'Erfasste Fortbildungsstunden ${d.jahr}: '
              '${fortbStunden.toStringAsFixed(1)} h von 30 h '
              '(${(fortbStunden / 30 * 100).toStringAsFixed(0)} % des Richtwerts).',
          style: const pw.TextStyle(fontSize: 11),
        ),
        pw.SizedBox(height: _mm(8)),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey50,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Rechtliche Hinweise',
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Text(
                'Dieser Bericht basiert auf den in Aktenwerk erfassten Daten. '
                'Er ersetzt nicht die steuerrechtlichen oder berufsrechtlichen '
                'Nachweise gegenüber Finanzamt, Kammer oder Auftraggeber.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  return doc.save();
}

Future<void> previewJahresberichtPdf(JahresberichtPdfData d) =>
    Printing.layoutPdf(onLayout: (_) => buildJahresberichtPdf(d));

// ---------- Helfer ----------

double _mm(double v) => v * PdfPageFormat.mm;

pw.Widget _kopf(JahresberichtPdfData d) {
  final a = d.absender;
  final line = a == null
      ? 'Aktenwerk'
      : (a.firma ??
          [a.vorname, a.nachname].whereType<String>().join(' '));
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
      ),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(line,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.Text('Jahresbericht ${d.jahr}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      ],
    ),
  );
}

pw.Widget _fuss(pw.Context ctx) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(top: 4),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Text('Seite ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
      ],
    ),
  );
}

class _Kpi {
  final String label;
  final String value;
  const _Kpi(this.label, this.value);
}

pw.Widget _kpiRow(List<_Kpi> kpis) {
  return pw.Row(
    children: [
      for (var i = 0; i < kpis.length; i++) ...[
        if (i > 0) pw.SizedBox(width: 6),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(kpis[i].label.toUpperCase(),
                    style: const pw.TextStyle(
                        fontSize: 8, color: PdfColors.grey600)),
                pw.SizedBox(height: 2),
                pw.Text(kpis[i].value,
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
    ],
  );
}

pw.Widget _th(String t) => pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(t,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
    );

pw.Widget _td(String t, {bool alignRight = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(t,
          textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
          style: const pw.TextStyle(fontSize: 10)),
    );
