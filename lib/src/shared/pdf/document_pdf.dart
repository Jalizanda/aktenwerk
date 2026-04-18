import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/database/app_database.dart';
import '../positionen/position_model.dart';

/// Gemeinsame Struktur für Rechnungs- und Angebots-PDFs.
class PdfDocumentData {
  final String dokumentTyp;
  final String? dokumentNr;
  final DateTime? datum;
  final DateTime? faelligBis;
  final String? betreff;
  final List<Position> positionen;
  final String? kopftext;
  final String? fusstext;
  final BenutzerData? absender;
  final KundenData? empfaenger;

  const PdfDocumentData({
    required this.dokumentTyp,
    this.dokumentNr,
    this.datum,
    this.faelligBis,
    this.betreff,
    this.positionen = const [],
    this.kopftext,
    this.fusstext,
    this.absender,
    this.empfaenger,
  });
}

Future<Uint8List> buildDocumentPdf(PdfDocumentData data) async {
  final doc = pw.Document();
  final dateFmt = DateFormat('dd.MM.yyyy', 'de');
  final money = NumberFormat.currency(locale: 'de', symbol: '€');
  final totals = PositionsTotals.fromList(data.positionen);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(30, 30, 30, 30),
      build: (ctx) => [
        _header(data),
        pw.SizedBox(height: 20),
        if (data.empfaenger != null) _empfaengerBlock(data.empfaenger!),
        pw.SizedBox(height: 24),
        _titelBlock(data, dateFmt),
        pw.SizedBox(height: 14),
        if ((data.kopftext ?? '').isNotEmpty) ...[
          pw.Text(data.kopftext!),
          pw.SizedBox(height: 12),
        ],
        _positionenTabelle(data.positionen, money),
        pw.SizedBox(height: 10),
        _summenBlock(totals, money),
        pw.SizedBox(height: 16),
        if ((data.fusstext ?? '').isNotEmpty)
          pw.Text(data.fusstext!,
              style: const pw.TextStyle(fontSize: 10)),
      ],
      footer: (ctx) => _footer(data.absender),
    ),
  );

  return doc.save();
}

Future<void> previewDocumentPdf(PdfDocumentData data) async {
  await Printing.layoutPdf(onLayout: (_) => buildDocumentPdf(data));
}

pw.Widget _header(PdfDocumentData data) {
  final a = data.absender;
  final firma = a?.firma ?? [a?.vorname, a?.nachname].whereType<String>().join(' ');
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (firma.isNotEmpty)
              pw.Text(firma,
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
            if ((a?.bestellungsText ?? '').isNotEmpty)
              pw.Text(a!.bestellungsText!,
                  style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
      if (a != null)
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            if ((a.strasse ?? '').isNotEmpty) pw.Text(a.strasse!),
            if ([a.plz, a.ort].whereType<String>().isNotEmpty)
              pw.Text([a.plz, a.ort].whereType<String>().join(' ')),
            if ((a.telefon ?? '').isNotEmpty)
              pw.Text('Tel: ${a.telefon}'),
            if ((a.email ?? '').isNotEmpty) pw.Text('E-Mail: ${a.email}'),
          ],
        ),
    ],
  );
}

pw.Widget _empfaengerBlock(KundenData k) {
  final name = [k.vorname, k.nachname].whereType<String>().join(' ').trim();
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      if ((k.firma ?? '').isNotEmpty) pw.Text(k.firma!),
      if (name.isNotEmpty) pw.Text(name),
      if ((k.strasse ?? '').isNotEmpty) pw.Text(k.strasse!),
      if ([k.plz, k.ort].whereType<String>().isNotEmpty)
        pw.Text([k.plz, k.ort].whereType<String>().join(' ')),
    ],
  );
}

pw.Widget _titelBlock(PdfDocumentData d, DateFormat dateFmt) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '${d.dokumentTyp}${d.dokumentNr == null ? '' : ' ${d.dokumentNr}'}',
            style: pw.TextStyle(
                fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          if ((d.betreff ?? '').isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(d.betreff!,
                  style: pw.TextStyle(
                      fontStyle: pw.FontStyle.italic, fontSize: 12)),
            ),
        ],
      ),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          if (d.datum != null)
            pw.Text('Datum: ${dateFmt.format(d.datum!)}'),
          if (d.faelligBis != null)
            pw.Text('Fällig: ${dateFmt.format(d.faelligBis!)}'),
        ],
      ),
    ],
  );
}

pw.Widget _positionenTabelle(
    List<Position> items, NumberFormat money) {
  if (items.isEmpty) {
    return pw.Text('Keine Positionen.',
        style: const pw.TextStyle(fontSize: 10));
  }
  final headers = ['#', 'Bezeichnung', 'Menge', 'Einh.', 'Preis', 'USt %', 'Summe'];
  final rows = <List<String>>[];
  for (var i = 0; i < items.length; i++) {
    final p = items[i];
    rows.add([
      '${i + 1}',
      p.bezeichnung,
      p.menge.toStringAsFixed(2),
      p.einheit,
      money.format(p.einzelpreis),
      p.ustSatz.toStringAsFixed(0),
      money.format(p.nettoBetrag),
    ]);
  }
  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    cellAlignment: pw.Alignment.centerLeft,
    cellAlignments: {
      0: pw.Alignment.centerRight,
      2: pw.Alignment.centerRight,
      4: pw.Alignment.centerRight,
      5: pw.Alignment.centerRight,
      6: pw.Alignment.centerRight,
    },
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
    cellStyle: const pw.TextStyle(fontSize: 10),
    border: pw.TableBorder.symmetric(
      inside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
    ),
    headerDecoration:
        const pw.BoxDecoration(color: PdfColors.grey200),
  );
}

pw.Widget _summenBlock(PositionsTotals t, NumberFormat money) {
  return pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.ConstrainedBox(
      constraints: const pw.BoxConstraints(maxWidth: 250),
      child: pw.Column(
        children: [
          _summenZeile('Netto', money.format(t.netto)),
          _summenZeile('Umsatzsteuer', money.format(t.ust)),
          pw.Divider(),
          _summenZeile('Gesamt', money.format(t.brutto), bold: true),
        ],
      ),
    ),
  );
}

pw.Widget _summenZeile(String label, String value, {bool bold = false}) {
  final style = pw.TextStyle(
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    fontSize: bold ? 12 : 11,
  );
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [pw.Text(label, style: style), pw.Text(value, style: style)],
    ),
  );
}

pw.Widget _footer(BenutzerData? a) {
  if (a == null) return pw.SizedBox.shrink();
  return pw.Container(
    padding: const pw.EdgeInsets.only(top: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
            [a.firma, a.vorname, a.nachname]
                .whereType<String>()
                .where((s) => s.isNotEmpty)
                .join(' '),
            style: const pw.TextStyle(fontSize: 9)),
        pw.Text(
            [a.iban, a.bic].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
            style: const pw.TextStyle(fontSize: 9)),
        pw.Text(a.steuerNr ?? a.ustId ?? '',
            style: const pw.TextStyle(fontSize: 9)),
      ],
    ),
  );
}
