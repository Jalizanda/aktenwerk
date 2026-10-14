import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../data/database/app_database.dart';
import '../../../shared/pdf/document_pdf.dart';

class VertragPdfData {
  final KundenData kunde;
  final BenutzerData absender;
  final String aktenzeichen;
  final String gegenstand;
  final double stundensatz;
  final double vorschuss;
  final bool dsgvoAkzeptiert;
  final bool widerrufsverzicht;
  final Uint8List unterschriftKunde;
  final Uint8List unterschriftSv;

  const VertragPdfData({
    required this.kunde,
    required this.absender,
    required this.aktenzeichen,
    required this.gegenstand,
    required this.stundensatz,
    required this.vorschuss,
    required this.dsgvoAkzeptiert,
    required this.widerrufsverzicht,
    required this.unterschriftKunde,
    required this.unterschriftSv,
  });
}

Future<Uint8List> buildPrivatgutachtenVertragPdf(VertragPdfData data) async {
  final doc = pw.Document();
  final dateFmt = DateFormat('dd.MM.yyyy', 'de');
  final moneyFmt = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
  final datumHeute = dateFmt.format(DateTime.now());

  final logo = await loadLogoForPdf(data.absender.logoPfad);
  final theme = pw.ThemeData.withFont(
    base: await PdfGoogleFonts.interRegular(),
    bold: await PdfGoogleFonts.interBold(),
    italic: await PdfGoogleFonts.interMedium(),
  );

  // Mapped data for the header/footer from existing structure
  final mappedData = PdfDocumentData(
    dokumentTyp: 'Vertrag über Privatgutachten',
    aktenzeichen: data.aktenzeichen,
    datum: DateTime.now(),
    absender: data.absender,
    empfaenger: data.kunde,
  );

  final clientSigImage = pw.MemoryImage(data.unterschriftKunde);
  final svSigImage = pw.MemoryImage(data.unterschriftSv);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(51.02, 28.34, 25.51, 14.17), // ~ 18mm, 10mm, 9mm, 5mm
      theme: theme,
      // Unfortunately _pageHeader is private in document_pdf.dart, so we'll construct a simple header
      header: (ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 20),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Vertrag: ${data.aktenzeichen}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            if (logo != null)
              pw.SizedBox(
                width: 100,
                child: pw.Image(logo, fit: pw.BoxFit.contain),
              ),
          ],
        ),
      ),
      build: (ctx) => [
        pw.Text('Vertrag über die Erstattung eines Privatgutachtens', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 16),

        _buildSectionTitle('1. Vertragsparteien'),
        pw.Text('Zwischen dem Sachverständigen:', style: const pw.TextStyle(fontSize: 10)),
        pw.Text('${data.absender.vorname ?? ''} ${data.absender.nachname ?? ''}\n${data.absender.strasse ?? ''}, ${data.absender.plz ?? ''} ${data.absender.ort ?? ''}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Text('und dem Auftraggeber:', style: const pw.TextStyle(fontSize: 10)),
        pw.Text('${data.kunde.vorname ?? ''} ${data.kunde.nachname ?? ''}\n${data.kunde.strasse ?? ''}, ${data.kunde.plz ?? ''} ${data.kunde.ort ?? ''}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 16),

        _buildSectionTitle('2. Vertragsgegenstand'),
        pw.Text('Der Sachverständige soll zu folgenden Fragen gutachterlich Stellung nehmen:', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 4),
        pw.Text(data.gegenstand, style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 16),

        _buildSectionTitle('3. Vergütung'),
        pw.Text('Als Vergütung für die Sachverständigen-Leistung wird ein Stundensatz von ${moneyFmt.format(data.stundensatz)}/Std. zzgl. gesetzlicher MwSt. berechnet.', style: const pw.TextStyle(fontSize: 11)),
        if (data.vorschuss > 0) ...[
          pw.SizedBox(height: 4),
          pw.Text('Hierauf wird ein Vorschuss in Höhe von ${moneyFmt.format(data.vorschuss)} (brutto) geleistet. Die Tätigkeit wird erst nach Eingang des Vorschusses aufgenommen.', style: const pw.TextStyle(fontSize: 11)),
        ],
        pw.SizedBox(height: 16),

        _buildSectionTitle('4. Erklärungen & Rechtliches'),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 10, height: 10,
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
              child: data.dsgvoAkzeptiert ? pw.Center(child: pw.Text('x', style: const pw.TextStyle(fontSize: 8))) : null,
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(child: pw.Text('Der Auftraggeber bestätigt den Erhalt der Informationspflichten gemäß Art. 13 DSGVO.', style: const pw.TextStyle(fontSize: 10))),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 10, height: 10,
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
              child: data.widerrufsverzicht ? pw.Center(child: pw.Text('x', style: const pw.TextStyle(fontSize: 8))) : null,
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(child: pw.Text('Zustimmung zum vorzeitigen Tätigkeitsbeginn: Der Auftraggeber verlangt ausdrücklich, dass der Sachverständige vor Ablauf der Widerrufsfrist mit der Leistungserbringung beginnt. Ihm ist bekannt, dass er bei vollständiger Vertragserfüllung durch den Sachverständigen sein Widerrufsrecht verliert.', style: const pw.TextStyle(fontSize: 10))),
          ],
        ),
        pw.SizedBox(height: 32),

        _buildSectionTitle('5. Unterschriften'),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Datum: $datumHeute'),
                  pw.SizedBox(height: 40),
                  pw.Image(clientSigImage, height: 50),
                  pw.Container(height: 1, color: PdfColors.black),
                  pw.Text('Unterschrift Auftraggeber', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),
            pw.SizedBox(width: 40),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Datum: $datumHeute'),
                  pw.SizedBox(height: 40),
                  pw.Image(svSigImage, height: 50),
                  pw.Container(height: 1, color: PdfColors.black),
                  pw.Text('Unterschrift Sachverständiger', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _buildSectionTitle(String title) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Text(
      title,
      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
    ),
  );
}
