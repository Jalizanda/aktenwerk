import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/database/app_database.dart';

/// PDF-Variante für das LV.
enum LvPdfVariante {
  /// Komplettes LV mit Einzelpreis, Gesamtpreis, Summen — als interne
  /// Kostenschätzung oder als Bauherren-Rechnung.
  preisLv,

  /// Blanko-LV ohne Einzel-/Gesamtpreis — geht an Handwerker zur
  /// Angebotsabgabe. Nur Texte und Mengen.
  blankoLv,
}

class LvPdfData {
  final LvKopfData kopf;
  final List<LvPositionenData> positionen;
  final AuftraegeData? auftrag;
  final BenutzerData? absender;
  final KundenData? empfaenger;
  final LvPdfVariante variante;

  const LvPdfData({
    required this.kopf,
    required this.positionen,
    required this.variante,
    this.auftrag,
    this.absender,
    this.empfaenger,
  });
}

Future<Uint8List> buildLvPdf(LvPdfData d) async {
  final variantText = d.variante == LvPdfVariante.blankoLv
      ? 'Leistungsverzeichnis (Ausschreibung)'
      : 'Kostenschätzung / Leistungsverzeichnis';

  final doc = pw.Document(
    title: '$variantText · ${d.kopf.bezeichnung}',
    author: [d.absender?.vorname, d.absender?.nachname]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(' '),
    creator: 'Aktenwerk',
    subject: variantText,
  );
  final regular = await PdfGoogleFonts.interRegular();
  final bold = await PdfGoogleFonts.interBold();
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);

  final dateFmt = DateFormat('dd.MM.yyyy', 'de');
  final money = NumberFormat.currency(
      locale: 'de_DE', symbol: '€', decimalDigits: 2);
  final mengeFmt = NumberFormat.decimalPattern('de_DE');

  final mitPreisen = d.variante == LvPdfVariante.preisLv;

  // Top-Level Positionen + ihre Children rekursiv flach in Druckreihenfolge.
  final flat = _flatPositionen(d.positionen);

  // Mischsummen: pro USt-Satz das Netto sammeln. Bedarfspositionen werden
  // ausgenommen, weil sie nur auf Abruf angeboten werden.
  final nettoProSatz = <double, double>{};
  for (final p in flat) {
    if (!(p.art == 'normal' ||
        p.art == 'eventual' ||
        p.art == 'stundenlohn')) {
      continue;
    }
    final satz = p.ustSatz ?? d.kopf.mwstSatz;
    final n = (p.menge ?? 0) * (p.einzelpreis ?? 0);
    nettoProSatz[satz] = (nettoProSatz[satz] ?? 0) + n;
  }
  final summe =
      nettoProSatz.values.fold<double>(0, (s, v) => s + v);
  final ust = nettoProSatz.entries
      .fold<double>(0, (s, e) => s + e.value * e.key / 100);
  final brutto = summe + ust;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.fromLTRB(_mm(20), _mm(20), _mm(15), _mm(20)),
      theme: theme,
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Seite ${ctx.pageNumber} / ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      ),
      build: (ctx) => [
        // Kopfzeile
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(variantText,
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text(d.kopf.bezeichnung,
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold)),
                if ((d.kopf.untertitel ?? '').isNotEmpty)
                  pw.Text(d.kopf.untertitel!,
                      style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                if (d.absender != null)
                  pw.Text(
                      [d.absender!.vorname, d.absender!.nachname]
                          .whereType<String>()
                          .where((s) => s.trim().isNotEmpty)
                          .join(' '),
                      style: pw.TextStyle(
                          fontSize: 10, fontWeight: pw.FontWeight.bold)),
                if ((d.kopf.nummer ?? '').isNotEmpty)
                  pw.Text('LV-Nr.: ${d.kopf.nummer}',
                      style: const pw.TextStyle(fontSize: 9)),
                pw.Text('Datum: ${dateFmt.format(d.kopf.datum)}',
                    style: const pw.TextStyle(fontSize: 9)),
                if ((d.auftrag?.aktenzeichen ?? '').isNotEmpty)
                  pw.Text('Akte: ${d.auftrag!.aktenzeichen}',
                      style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ],
        ),
        if (d.kopf.indexStichtag != null) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            'Preisstand: ${d.kopf.indexStichtag}'
            '${d.kopf.indexWert == null ? "" : " (Baupreisindex ${d.kopf.indexWert!.toStringAsFixed(1)})"}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
        pw.SizedBox(height: 10),
        pw.Divider(thickness: 0.4, color: PdfColors.grey400),
        pw.SizedBox(height: 6),

        // Tabellen-Header
        _zeile(
          ozCol: pw.Text('OZ',
              style:
                  pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          textCol: pw.Text('Bezeichnung',
              style:
                  pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          mengeCol: pw.Text('Menge Einh.',
              textAlign: pw.TextAlign.right,
              style:
                  pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          epCol: mitPreisen
              ? pw.Text('EP',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold))
              : null,
          gpCol: mitPreisen
              ? pw.Text('GP',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold))
              : null,
        ),
        pw.Divider(thickness: 0.3, color: PdfColors.grey300),

        // Positionen
        for (final p in flat) ..._positionsBlock(p, mengeFmt, money, mitPreisen),

        pw.SizedBox(height: 12),
        pw.Divider(thickness: 0.5, color: PdfColors.grey500),
        if (mitPreisen) ...[
          pw.SizedBox(height: 8),
          _summenBlockMix(nettoProSatz, summe, ust, brutto, money),
        ] else ...[
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Text(
              'Bitte tragen Sie Ihre Einheits- und Gesamtpreise ein. '
              'Bedarfspositionen (BP) bitte separat ausweisen. '
              'Stundenlohnpositionen mit Stundensatz.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
              'Erstellt mit Aktenwerk · Sachverständigenbüro ${[
            d.absender?.vorname,
            d.absender?.nachname
          ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ')}',
              style:
                  const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ],
      ],
    ),
  );
  return doc.save();
}

/// Bringt die hierarchischen Positionen in lineare Druck-Reihenfolge:
/// Top-Level zuerst, dann jeweils ihre Kinder.
List<LvPositionenData> _flatPositionen(List<LvPositionenData> all) {
  final byParent = <int?, List<LvPositionenData>>{};
  for (final p in all) {
    byParent.putIfAbsent(p.parentId, () => []).add(p);
  }
  for (final list in byParent.values) {
    list.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
  }
  final out = <LvPositionenData>[];
  void addRec(int? parent) {
    final list = byParent[parent] ?? [];
    for (final p in list) {
      out.add(p);
      addRec(p.id);
    }
  }
  addRec(null);
  return out;
}

List<pw.Widget> _positionsBlock(
  LvPositionenData p,
  NumberFormat mengeFmt,
  NumberFormat money,
  bool mitPreisen,
) {
  if (p.art == 'titel') {
    return [
      pw.SizedBox(height: 6),
      pw.Container(
        color: PdfColors.grey200,
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Row(
          children: [
            pw.SizedBox(
              width: 60,
              child: pw.Text(p.oz ?? '',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Expanded(
                child: pw.Text(p.kurztext,
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold))),
          ],
        ),
      ),
      pw.SizedBox(height: 4),
    ];
  }
  if (p.art == 'grundtext') {
    return [
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 60,
              child: pw.Text(p.oz ?? '',
                  style: const pw.TextStyle(fontSize: 8.5)),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(p.kurztext,
                      style: pw.TextStyle(
                          fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                  if ((p.langtext ?? '').isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 2),
                      child: pw.Text(p.langtext!,
                          style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.3)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }
  // Normale, Bedarfs-, Eventual-, Stundenlohn-Positionen
  final menge = p.menge ?? 0;
  final ep = p.einzelpreis ?? 0;
  final gp = menge * ep;
  final isBedarf = p.art == 'bedarf';
  final isStunden = p.art == 'stundenlohn';

  return [
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: _zeile(
        ozCol: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(p.oz ?? '',
                style: const pw.TextStyle(fontSize: 9)),
            if (isBedarf)
              pw.Text('BP',
                  style: pw.TextStyle(
                      fontSize: 7,
                      color: PdfColors.orange700,
                      fontWeight: pw.FontWeight.bold)),
            if (isStunden)
              pw.Text('Std.',
                  style: pw.TextStyle(
                      fontSize: 7,
                      color: PdfColors.blue700,
                      fontWeight: pw.FontWeight.bold)),
          ],
        ),
        textCol: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(p.kurztext,
                style: pw.TextStyle(
                    fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
            if ((p.langtext ?? '').isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 1),
                child: pw.Text(p.langtext!,
                    style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.3)),
              ),
            if ((p.din276 ?? '').isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 1),
                child: pw.Text('DIN 276 KG ${p.din276}',
                    style:
                        pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
              ),
          ],
        ),
        mengeCol: pw.Text(
            '${mengeFmt.format(menge)} ${p.einheit ?? ""}'.trim(),
            textAlign: pw.TextAlign.right,
            style: const pw.TextStyle(fontSize: 9)),
        epCol: mitPreisen
            ? pw.Text(money.format(ep),
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 9))
            : null,
        gpCol: mitPreisen
            ? pw.Text(isBedarf ? '(BP)' : money.format(gp),
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: isBedarf
                        ? pw.FontWeight.normal
                        : pw.FontWeight.bold))
            : null,
      ),
    ),
    pw.Divider(
        thickness: 0.2, color: PdfColors.grey300, height: 0),
  ];
}

pw.Widget _zeile({
  required pw.Widget ozCol,
  required pw.Widget textCol,
  required pw.Widget mengeCol,
  pw.Widget? epCol,
  pw.Widget? gpCol,
}) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(width: 60, child: ozCol),
      pw.Expanded(flex: 6, child: textCol),
      // Menge + Einheit in einer Spalte (z. B. „18 m³") mit
      // genau einem Leerzeichen.
      pw.SizedBox(width: 95, child: mengeCol),
      if (epCol != null) pw.SizedBox(width: 60, child: epCol),
      if (gpCol != null) pw.SizedBox(width: 70, child: gpCol),
    ],
  );
}

/// Summenblock mit Mischsummen pro USt-Satz. Wenn nur ein einziger
/// Satz auftritt, wird er kompakt dargestellt.
pw.Widget _summenBlockMix(
  Map<double, double> nettoProSatz,
  double summe,
  double ust,
  double brutto,
  NumberFormat money,
) {
  pw.Widget zeile(String l, String w, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [
          pw.Expanded(
              child: pw.Text(l,
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                      fontSize: bold ? 11 : 10,
                      fontWeight:
                          bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
          pw.SizedBox(width: 24),
          pw.SizedBox(
              width: 100,
              child: pw.Text(w,
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                      fontSize: bold ? 11 : 10,
                      fontWeight: bold
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal))),
        ]),
      );

  final entries = nettoProSatz.entries.toList()
    ..sort((a, b) => b.key.compareTo(a.key));
  return pw.Container(
    margin: const pw.EdgeInsets.only(left: 200),
    child: pw.Column(children: [
      if (entries.length > 1) ...[
        for (final e in entries)
          zeile(
              'Netto bei ${e.key.toStringAsFixed(0)} % USt.',
              money.format(e.value)),
        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
      ],
      zeile('Summe netto', money.format(summe)),
      for (final e in entries)
        zeile(
            'USt. ${e.key.toStringAsFixed(0)} % auf ${money.format(e.value)}',
            money.format(e.value * e.key / 100)),
      if (entries.length > 1) zeile('USt. gesamt', money.format(ust)),
      pw.Container(
        decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(3)),
        child: zeile('Gesamtbetrag (brutto)', money.format(brutto), bold: true),
      ),
    ]),
  );
}

pw.Widget _summenBlock(
    double netto, double ust, double brutto, double ustSatz, NumberFormat money) {
  pw.Widget zeile(String l, String w, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          children: [
            pw.Expanded(
                child: pw.Text(l,
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                        fontSize: bold ? 11 : 10,
                        fontWeight:
                            bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
            pw.SizedBox(width: 24),
            pw.SizedBox(
              width: 100,
              child: pw.Text(w,
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                      fontSize: bold ? 11 : 10,
                      fontWeight:
                          bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            ),
          ],
        ),
      );
  return pw.Container(
    margin: const pw.EdgeInsets.only(left: 200),
    child: pw.Column(children: [
      zeile('Summe netto', money.format(netto)),
      zeile('zzgl. ${ustSatz.toStringAsFixed(0)} % USt.', money.format(ust)),
      pw.Container(
        decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(3)),
        child: zeile('Gesamtbetrag (brutto)', money.format(brutto), bold: true),
      ),
    ]),
  );
}

double _mm(double v) => v * PdfPageFormat.mm;

Future<void> previewLvPdf(LvPdfData d) => Printing.layoutPdf(
      onLayout: (_) => buildLvPdf(d),
      name:
          '${d.variante == LvPdfVariante.blankoLv ? "Ausschreibung" : "Kostenschaetzung"}_${(d.auftrag?.aktenzeichen ?? d.kopf.bezeichnung).replaceAll(RegExp(r"[^A-Za-z0-9-]"), "_")}.pdf',
    );
