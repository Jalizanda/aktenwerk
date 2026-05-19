import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../data/database/app_database.dart';
import '../../../features/akten/rechnungen/rechnungen_repository.dart';
import '../../../features/system/einstellungen/absender_service.dart';


class MahnlaufData {
  final List<RechnungWithKunde> ueberfaellig;
  final BenutzerData? absender;
  final String siegelBase64;

  const MahnlaufData({
    required this.ueberfaellig,
    required this.absender,
    this.siegelBase64 = '',
  });
}

Future<Uint8List> buildMahnlaufPdf(MahnlaufData d) async {
  final doc = pw.Document();
  final money = NumberFormat.currency(
    locale: 'de_DE',
    symbol: '€',
    decimalDigits: 2,
  );
  final df = DateFormat('dd.MM.yyyy', 'de');

  final theme = pw.ThemeData.withFont(
    base: await PdfGoogleFonts.interRegular(),
    bold: await PdfGoogleFonts.interBold(),
  );

  for (final r in d.ueberfaellig) {
    final kunde = r.kunde;
    final rDat = r.rechnung.rechnungsdatum;
    final fDat = r.rechnung.faelligAm;
    final alter = fDat == null ? 0 : DateTime.now().difference(fDat).inDays;

    final stufe = _mahnstufe(alter);
    final isErinnerung = stufe == 1;

    final titel = isErinnerung ? 'Zahlungserinnerung' : '$stufe. Mahnung';
    final offen = r.rechnung.brutto - r.rechnung.bezahlt;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.fromLTRB(
          25 * PdfPageFormat.mm,
          45 * PdfPageFormat.mm,
          20 * PdfPageFormat.mm,
          20 * PdfPageFormat.mm,
        ),
        theme: theme,
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Anschrift
              if (kunde != null)
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (kunde.firma != null && kunde.firma!.isNotEmpty)
                      pw.Text(kunde.firma!),
                    if (kunde.nachname != null && kunde.nachname!.isNotEmpty)
                      pw.Text(
                        [
                          kunde.vorname,
                          kunde.nachname,
                        ].where((e) => e != null && e.isNotEmpty).join(' '),
                      ),
                    if (kunde.strasse != null && kunde.strasse!.isNotEmpty)
                      pw.Text(kunde.strasse!),
                    if (kunde.plz != null && kunde.ort != null)
                      pw.Text('${kunde.plz} ${kunde.ort}'),
                  ],
                ),
              pw.SizedBox(height: 30 * PdfPageFormat.mm),
              // Datum
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(df.format(DateTime.now())),
              ),
              pw.SizedBox(height: 10 * PdfPageFormat.mm),
              // Betreff
              pw.Text(
                '$titel zur Rechnung ${r.rechnung.rechnungsnummer}',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5 * PdfPageFormat.mm),
              pw.Text(
                r.auftrag?.aktenzeichen != null
                    ? 'Akte: ${r.auftrag!.aktenzeichen}'
                    : '',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 15 * PdfPageFormat.mm),
              // Text
              pw.Text('Sehr geehrte Damen und Herren,'),
              pw.SizedBox(height: 5 * PdfPageFormat.mm),
              if (isErinnerung)
                pw.Text(
                  'sicher ist es Ihnen im Alltagsgeschäft entgangen: Unsere Rechnung vom ${rDat != null ? df.format(rDat) : '?'} ist seit dem ${fDat != null ? df.format(fDat) : '?'} zur Zahlung fällig.',
                )
              else
                pw.Text(
                  'auf unsere Zahlungserinnerung konnten wir leider keinen Zahlungseingang feststellen. Bitte begleichen Sie den ausstehenden Betrag.',
                ),
              pw.SizedBox(height: 10 * PdfPageFormat.mm),
              pw.Text(
                'Offener Rechnungsbetrag: ${money.format(offen)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 10 * PdfPageFormat.mm),
              pw.Text(
                'Wir bitten Sie, den Betrag bis zum ${df.format(DateTime.now().add(const Duration(days: 7)))} auf unser Konto zu überweisen.',
              ),
              pw.SizedBox(height: 15 * PdfPageFormat.mm),
              pw.Text('Mit freundlichen Grüßen'),
              pw.SizedBox(height: 5 * PdfPageFormat.mm),
              pw.Text(
                d.absender?.firma ??
                    [
                      d.absender?.vorname,
                      d.absender?.nachname,
                    ].whereType<String>().join(' '),
              ),
            ],
          );
        },
      ),
    );
  }

  if (d.ueberfaellig.isEmpty) {
    doc.addPage(
      pw.Page(
        build: (ctx) =>
            pw.Center(child: pw.Text('Keine überfälligen Rechnungen')),
      ),
    );
  }

  return doc.save();
}

Future<void> previewMahnlaufPdf(MahnlaufData d) =>
    Printing.layoutPdf(onLayout: (_) => buildMahnlaufPdf(d));

int _mahnstufe(int alter) {
  if (alter > 35) return 3;
  if (alter > 14) return 2;
  if (alter > 0) return 1;
  return 0;
}
