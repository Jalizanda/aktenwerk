import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/database/app_database.dart';
import '../../features/akten/gerichtssache/beweisfragen.dart';

/// Eingangsdaten für den Kostenvorschuss-Antrag.
///
/// Wird üblicherweise an das beauftragende Gericht zurückgesendet, sobald
/// der Sachverständige nach Sichtung der Akte den voraussichtlichen
/// Aufwand grob schätzen kann (Stunden + Auslagen).
class KostenvorschussPdfData {
  final AuftraegeData auftrag;
  final KundenData? gericht;
  final BenutzerData? absender;

  /// Voraussichtliche Stunden (Schätzung).
  final double stunden;

  /// JVEG-Stundensatz (€) — meist 95 oder 130 € (Honorargruppe M2/M3).
  final double stundensatz;

  /// Voraussichtliche Auslagen — können einzeln aufgeschlüsselt werden.
  final List<KostenvorschussPosten> auslagen;

  /// USt-Satz (in %). Bei Sachverständigen typisch 19.
  final double ustSatz;

  /// Datum des Antrags.
  final DateTime datum;

  /// Optionaler Begründungstext, der über der Aufstellung steht.
  final String? begruendung;

  const KostenvorschussPdfData({
    required this.auftrag,
    required this.datum,
    required this.stunden,
    required this.stundensatz,
    required this.auslagen,
    required this.ustSatz,
    this.gericht,
    this.absender,
    this.begruendung,
  });
}

class KostenvorschussPosten {
  final String bezeichnung;
  final double netto;
  const KostenvorschussPosten(this.bezeichnung, this.netto);
}

Future<Uint8List> buildKostenvorschussPdf(KostenvorschussPdfData d) async {
  final doc = pw.Document(
    title: 'Antrag auf Kostenvorschuss · ${d.auftrag.aktenzeichen ?? ""}',
    author: [d.absender?.vorname, d.absender?.nachname]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(' '),
    creator: 'Aktenwerk',
    subject: 'Kostenvorschussantrag gem. § 17 JVEG',
  );
  final regular = await PdfGoogleFonts.interRegular();
  final bold = await PdfGoogleFonts.interBold();
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);

  final dateFmt = DateFormat('dd.MM.yyyy', 'de');
  final money = NumberFormat.currency(
      locale: 'de_DE', symbol: '€', decimalDigits: 2);

  final stundenNetto = d.stunden * d.stundensatz;
  final auslagenNetto = d.auslagen.fold<double>(0, (s, p) => s + p.netto);
  final summeNetto = stundenNetto + auslagenNetto;
  final ust = summeNetto * d.ustSatz / 100;
  final brutto = summeNetto + ust;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.fromLTRB(_mm(25), _mm(25), _mm(20), _mm(20)),
      theme: theme,
      footer: (ctx) => ctx.pagesCount > 1
          ? pw.Container(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Seite ${ctx.pageNumber} / ${ctx.pagesCount}',
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey600),
              ),
            )
          : pw.SizedBox(),
      build: (ctx) => [
          // Absender (klein, rechts oben)
          if (d.absender != null) _absenderBlock(d.absender!),
          pw.SizedBox(height: 12),
          // Empfänger
          _empfaengerBlock(d),
          pw.SizedBox(height: 30),
          // Datum + Ort
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '${d.absender?.ort ?? ''}${d.absender?.ort == null ? '' : ', '}${dateFmt.format(d.datum)}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
          pw.SizedBox(height: 20),
          // Betreff
          pw.Text(
            'Antrag auf Auslagen-/Kostenvorschuss gem. § 17 JVEG',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          _bezugBlock(d, dateFmt),
          pw.SizedBox(height: 16),
          // Anrede
          pw.Text(
            d.gericht?.typ == 'gericht'
                ? 'Sehr geehrte Damen und Herren,'
                : 'Sehr geehrte Damen und Herren,',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 10),
          // Begründung
          pw.Text(
            d.begruendung ??
                'für die Erstellung des Gutachtens in oben genannter Sache erlaube ich '
                    'mir, gemäß § 17 JVEG einen Auslagen- und Kostenvorschuss zu '
                    'beantragen. Die nachstehende Aufstellung beruht auf einer ersten '
                    'Sichtung der Akte und stellt eine Schätzung des voraussichtlichen '
                    'Aufwands dar.',
            style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.5),
          ),
          pw.SizedBox(height: 12),
          ..._beweisfragenBezugsBlock(d.auftrag),
          pw.SizedBox(height: 4),
          // Aufstellung
          pw.Text('Voraussichtlicher Aufwand:',
              style:
                  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          _aufstellung(d, money),
          pw.SizedBox(height: 14),
          // Summen
          _summenBlock(stundenNetto, auslagenNetto, summeNetto, ust, brutto,
              d.ustSatz, money),
          pw.SizedBox(height: 20),
          // Bankverbindung-Hinweis
          if (d.absender != null && (d.absender!.iban ?? '').isNotEmpty)
            _bankBlock(d.absender!),
          pw.SizedBox(height: 20),
          pw.Text(
            'Ich bitte um Anweisung des Vorschusses auf das oben genannte Konto. '
            'Die endgültige Abrechnung nach JVEG erfolgt nach Erstellung des '
            'Gutachtens unter Verrechnung des hier beantragten Vorschusses.',
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

List<pw.Widget> _beweisfragenBezugsBlock(AuftraegeData auftrag) {
  final fragen = decodeBeweisfragen(auftrag.beweisfragenJson);
  if (fragen.isEmpty) return const [];
  return [
    pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
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
            'Beweisfragen lt. Beweisbeschluss:',
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

pw.Widget _empfaengerBlock(KostenvorschussPdfData d) {
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

pw.Widget _bezugBlock(KostenvorschussPdfData d, DateFormat fmt) {
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

pw.Widget _aufstellung(KostenvorschussPdfData d, NumberFormat money) {
  final stundenBetrag = d.stunden * d.stundensatz;
  final stundenLabel =
      '${d.stunden.toStringAsFixed(1).replaceAll('.', ',')} h × ${money.format(d.stundensatz)} (Honorargruppe ${d.auftrag.honorargruppe ?? '—'})';
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
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey100),
        children: [
          _zelle('Position', bold: true),
          _zelle('Netto €', bold: true, alignRight: true),
        ],
      ),
      pw.TableRow(children: [
        _zelle('Sachverständigen-Honorar — $stundenLabel'),
        _zelle(money.format(stundenBetrag), alignRight: true),
      ]),
      for (final p in d.auslagen)
        pw.TableRow(children: [
          _zelle(p.bezeichnung),
          _zelle(money.format(p.netto), alignRight: true),
        ]),
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

pw.Widget _summenBlock(
    double stundenNetto,
    double auslagenNetto,
    double summeNetto,
    double ust,
    double brutto,
    double ustSatz,
    NumberFormat money) {
  pw.Widget zeile(String l, String w, {bool bold = false, double size = 10}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          children: [
            pw.Expanded(
                child: pw.Text(l,
                    style: pw.TextStyle(
                        fontSize: size,
                        fontWeight:
                            bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
            pw.Text(w,
                style: pw.TextStyle(
                    fontSize: size,
                    fontWeight:
                        bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        ),
      );
  return pw.Container(
    width: 320,
    alignment: pw.Alignment.centerRight,
    margin: const pw.EdgeInsets.only(left: 200),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        zeile('Honorar (netto)', money.format(stundenNetto)),
        zeile('Auslagen (netto)', money.format(auslagenNetto)),
        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
        zeile('Summe netto', money.format(summeNetto)),
        zeile('zzgl. ${ustSatz.toStringAsFixed(0)} % USt.',
            money.format(ust)),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 6),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6),
            child: zeile('Beantragter Vorschuss (brutto)',
                money.format(brutto),
                bold: true, size: 12),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _bankBlock(BenutzerData a) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
      borderRadius: pw.BorderRadius.circular(3),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Bankverbindung',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        // Kontoinhaber = Vorname Nachname (Aktenwerk speichert keinen
        // separaten Kontoinhaber pro Benutzer).
        if ([a.vorname, a.nachname]
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .isNotEmpty)
          pw.Text(
              'Kontoinhaber: ${[a.vorname, a.nachname].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ')}',
              style: const pw.TextStyle(fontSize: 9)),
        if ((a.bank ?? '').isNotEmpty)
          pw.Text('Bank: ${a.bank}',
              style: const pw.TextStyle(fontSize: 9)),
        if ((a.iban ?? '').isNotEmpty)
          pw.Text('IBAN: ${a.iban}',
              style: const pw.TextStyle(fontSize: 9)),
        if ((a.bic ?? '').isNotEmpty)
          pw.Text('BIC: ${a.bic}',
              style: const pw.TextStyle(fontSize: 9)),
      ],
    ),
  );
}

pw.Widget _signaturBlock(BenutzerData a) {
  final name = [a.vorname, a.nachname]
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .join(' ');
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(
          width: 200, height: 0.5, color: PdfColors.grey400),
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

Future<void> previewKostenvorschussPdf(KostenvorschussPdfData data) =>
    Printing.layoutPdf(
      onLayout: (_) => buildKostenvorschussPdf(data),
      name:
          'Kostenvorschuss_${(data.auftrag.aktenzeichen ?? "").replaceAll(RegExp(r"[^A-Za-z0-9-]"), "_")}.pdf',
    );
