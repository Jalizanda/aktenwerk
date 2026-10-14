import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/database/app_database.dart';
import '../../features/akten/akte/beteiligte_tab.dart';
import '../../features/akten/auftraege/auftrag_gm_extras.dart';
import '../../features/akten/gerichtssache/beweisfragen.dart';

/// Eingangsdaten für das „Gutachterarbeitsblatt (Handblatt für den Ortstermin)".
class GutachtenArbeitsblattPdfData {
  final AuftraegeData auftrag;
  final KundenData? auftraggeber;
  final BenutzerData? absender;

  const GutachtenArbeitsblattPdfData({
    required this.auftrag,
    this.auftraggeber,
    this.absender,
  });
}

Future<Uint8List> buildGutachtenArbeitsblattPdf(
    GutachtenArbeitsblattPdfData d) async {
  final a = d.auftrag;
  final gm = AuftragGmExtras.fromAuftragExtras(a.extras);
  final beteiligte = decodeBeteiligte(a.beteiligteJson);
  final fragen = decodeBeweisfragen(a.beweisfragenJson);
  final dateFmt = DateFormat('dd.MM.yyyy', 'de');

  final doc = pw.Document(
    title: 'Gutachterarbeitsblatt · ${a.aktenzeichen ?? ""}',
    creator: 'Aktenwerk',
    subject: 'Handblatt für den Ortstermin',
  );

  final regular = await PdfGoogleFonts.interRegular();
  final bold = await PdfGoogleFonts.interBold();
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);

  final uhrzeitStr = [
    if (gm.ortsterminUhrzeitVon.trim().isNotEmpty)
      gm.ortsterminUhrzeitVon.trim(),
    if (gm.ortsterminUhrzeitBis.trim().isNotEmpty)
      'bis ca. ${gm.ortsterminUhrzeitBis.trim()} Uhr'
    else if (gm.ortsterminUhrzeitVon.trim().isNotEmpty)
      'Uhr',
  ].join(' ');

  final terminStr = a.ortsterminAm == null
      ? '____.____.20____'
      : '${dateFmt.format(a.ortsterminAm!)}${uhrzeitStr.isNotEmpty ? " ($uhrzeitStr)" : ""}';

  final objektAnschrift = [
    a.objektStrasse,
    '${a.objektPlz ?? ''} ${a.objektOrt ?? ''}'.trim(),
  ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');

  final agName = d.auftraggeber == null
      ? ''
      : ((d.auftraggeber!.firma ?? '').trim().isNotEmpty
          ? d.auftraggeber!.firma!.trim()
          : [d.auftraggeber!.vorname, d.auftraggeber!.nachname]
              .whereType<String>()
              .where((s) => s.trim().isNotEmpty)
              .join(' '));

  final sache = buildSacheKurzbezeichnung(a);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.fromLTRB(_mm(16), _mm(15), _mm(16), _mm(15)),
      theme: theme,
      header: (ctx) => pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'GUTACHTER-ARBEITSBLATT · ORTSTERMIN',
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blueGrey900,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Sache: ${sache.isEmpty ? (a.betreff ?? "—") : sache}',
                    style: const pw.TextStyle(fontSize: 9.5),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Akte: ${a.aktenzeichen ?? "—"}',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if ((a.gerichtsAktenzeichen ?? '').trim().isNotEmpty)
                    pw.Text(
                      'Gerichts-AZ: ${a.gerichtsAktenzeichen}',
                      style: const pw.TextStyle(fontSize: 9),
                    )
                  else if (gm.schadensnummer.trim().isNotEmpty)
                    pw.Text(
                      'Schaden-Nr.: ${gm.schadensnummer}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Divider(height: 1, thickness: 0.8, color: PdfColors.blueGrey700),
          pw.SizedBox(height: 8),
        ],
      ),
      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Gutachterarbeitsblatt · Akte ${a.aktenzeichen ?? ""} · Stand ${dateFmt.format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
          pw.Text(
            'Seite ${ctx.pageNumber} von ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
      build: (ctx) => [
        // 1. Ortstermin- & Klimakopf
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.blueGrey50,
            border: pw.Border.all(color: PdfColors.blueGrey200, width: 0.6),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: _kv('Ortstermin am', terminStr, boldValue: true),
                  ),
                  pw.Expanded(
                    flex: 4,
                    child: _kv(
                      'Objekt / Treffpunkt',
                      objektAnschrift.isEmpty ? '—' : objektAnschrift,
                      boldValue: true,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      'Witterung: _____________________',
                      style: const pw.TextStyle(fontSize: 8.5),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      'Außentemp./r.F.: _____ °C / _____ %',
                      style: const pw.TextStyle(fontSize: 8.5),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      'Innentemp./r.F.: _____ °C / _____ %',
                      style: const pw.TextStyle(fontSize: 8.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 8),

        // 2. Stammdaten-Übersicht (2 Spalten)
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _kv('Auftraggeber', agName.isEmpty ? (a.gericht ?? '—') : agName),
                    if ((a.gericht ?? '').isNotEmpty)
                      _kv('Gericht / Ort', [a.gericht, a.gerichtsort].whereType<String>().where((s) => s.isNotEmpty).join(' · ')),
                    if ((a.richter ?? '').isNotEmpty)
                      _kv('Richter:in', a.richter!),
                    if ((a.klaeger ?? '').isNotEmpty || (a.beklagter ?? '').isNotEmpty)
                      _kv('Parteien', '${a.klaeger ?? "—"} ./. ${a.beklagter ?? "—"}'),
                    if (gm.schadensnummer.isNotEmpty)
                      _kv('Schaden-Nr. / Police', '${gm.schadensnummer} / ${gm.versicherungsscheinNr.isEmpty ? "—" : gm.versicherungsscheinNr}'),
                    if (gm.schadenstag != null)
                      _kv('Schadenstag / Ursache', '${dateFmt.format(gm.schadenstag!)} · ${gm.schadensursache.isEmpty ? "—" : gm.schadensursache}'),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _kv('Objektart / Baujahr', '${a.objektart ?? "—"} · Bj. ${a.baujahr ?? "—"}'),
                    if ((a.schneelastzone ?? '').isNotEmpty || (a.windlastzone ?? '').isNotEmpty)
                      _kv('Schnee- / Windzone', 'SLZ ${a.schneelastzone ?? "—"} (${a.schneelastKnm2 ?? "—"} kN/m²) · WLZ ${a.windlastzone ?? "—"}'),
                    _kv(
                      'Vorschuss / Limit',
                      'Vorschuss: ${a.kostenvorschuss != null ? "${a.kostenvorschuss!.toStringAsFixed(0)} €" : "—"} · Limit: ${a.kostenLimit != null ? "${a.kostenLimit!.toStringAsFixed(0)} €" : "—"}',
                    ),
                    if (gm.streitwert != null)
                      _kv('Streitwert', '${gm.streitwert!.toStringAsFixed(2)} €'),
                    if (a.fristAm != null)
                      _kv('Gutachten-Frist', dateFmt.format(a.fristAm!)),
                    if (gm.aktenbaende.isNotEmpty)
                      _kv(
                        'Gerichtsakten',
                        gm.aktenbaende
                            .map((b) => 'Bd. ${b.bandNr} (Bl. ${b.seitenVon ?? 1}-${b.seitenBis ?? "?"})')
                            .join(', '),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),

        // 3. Beteiligten- & Anwesenheitstabelle
        pw.Text(
          '1. Beteiligte & Anwesenheitsliste vor Ort',
          style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        _buildBeteiligteTable(beteiligte),
        pw.SizedBox(height: 12),

        // 4. Beweisfragen & Befund-Notizfelder
        pw.Text(
          fragen.isEmpty
              ? '2. Feststellungen / Befund / Beweisthema vor Ort'
              : '2. Beweisfragen & handschriftliche Befundnotizen (${fragen.length})',
          style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        if (fragen.isEmpty) ...[
          if ((a.notiz ?? '').trim().isNotEmpty) ...[
            pw.Text(
              'Auftragsnotiz: ${a.notiz!.trim()}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 4),
          ],
          _notizBox(lines: 10, label: 'Feststellungen / Schäden / Ursache / Messwerte:'),
        ] else
          for (final f in fragen) ...[
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 8),
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Beweisfrage ${f.nr}: ${f.frage}',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  for (var l = 0; l < 4; l++)
                    pw.Container(
                      height: 16,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                            color: PdfColors.grey300,
                            width: 0.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],

        pw.SizedBox(height: 6),

        // 5. Messwerte / Skizze / Kurz-Checkliste
        pw.Text(
          '3. Messwerte, Bauteilöffnungen & Checkliste vor Abfahrt',
          style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        _notizBox(
          lines: 5,
          label: 'Messwerte (Feuchte / Temperatur / Maße) & vorgefundene Unterlagen:',
        ),
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _checkItem('Übersichtsfotos Außen'),
              _checkItem('Detailfotos m. Maßstab'),
              _checkItem('Alle Beweisfragen geprüft'),
              _checkItem('Parteiaussagen notiert'),
              _checkItem('Weiterer Termin nötig?'),
            ],
          ),
        ),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _kv(String label, String value, {bool boldValue = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2.5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 85,
          child: pw.Text(
            '$label:',
            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight:
                  boldValue ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _buildBeteiligteTable(List<Beteiligter> liste) {
  final headerStyle = pw.TextStyle(
    fontSize: 8,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.blueGrey900,
  );
  const cellStyle = pw.TextStyle(fontSize: 8);

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
    columnWidths: const {
      0: pw.FixedColumnWidth(26),
      1: pw.FixedColumnWidth(82),
      2: pw.FlexColumnWidth(2.4),
      3: pw.FixedColumnWidth(72),
      4: pw.FixedColumnWidth(82),
      5: pw.FlexColumnWidth(1.6),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.blueGrey50),
        children: [
          _cell(pw.Text('Anw.', style: headerStyle)),
          _cell(pw.Text('Rolle / Partei', style: headerStyle)),
          _cell(pw.Text('Name / Kanzlei & Anschrift', style: headerStyle)),
          _cell(pw.Text('Ihr Zeichen', style: headerStyle)),
          _cell(pw.Text('Telefon / Mobil', style: headerStyle)),
          _cell(pw.Text('Bemerkung / anwesend', style: headerStyle)),
        ],
      ),
      for (final b in liste)
        pw.TableRow(
          children: [
            _cell(
              pw.Center(
                child: pw.Container(
                  width: 9,
                  height: 9,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 0.7),
                  ),
                ),
              ),
            ),
            _cell(
              pw.Text(
                '${b.rolle}${b.vertritt.trim().isNotEmpty ? "\n(${b.vertritt.trim()})" : ""}',
                style: cellStyle,
              ),
            ),
            _cell(
              pw.Text(
                '${b.name}${b.anschrift.isNotEmpty ? "\n${b.anschrift}" : ""}',
                style: cellStyle,
              ),
            ),
            _cell(pw.Text(b.ihrZeichen, style: cellStyle)),
            _cell(pw.Text(b.telefon, style: cellStyle)),
            _cell(pw.SizedBox(height: 16)),
          ],
        ),
      // 2 Leerzeilen für spontan anwesende Personen vor Ort
      for (var i = 0; i < 2; i++)
        pw.TableRow(
          children: [
            _cell(
              pw.Center(
                child: pw.Container(
                  width: 9,
                  height: 9,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 0.7),
                  ),
                ),
              ),
            ),
            _cell(pw.SizedBox(height: 16)),
            _cell(pw.SizedBox(height: 16)),
            _cell(pw.SizedBox(height: 16)),
            _cell(pw.SizedBox(height: 16)),
            _cell(pw.SizedBox(height: 16)),
          ],
        ),
    ],
  );
}

pw.Widget _cell(pw.Widget child) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
      child: child,
    );

pw.Widget _notizBox({required int lines, required String label}) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(6),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey700,
          ),
        ),
        pw.SizedBox(height: 2),
        for (var i = 0; i < lines; i++)
          pw.Container(
            height: 16,
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
              ),
            ),
          ),
      ],
    ),
  );
}

pw.Widget _checkItem(String label) {
  return pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Container(
        width: 8,
        height: 8,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 0.7),
        ),
      ),
      pw.SizedBox(width: 4),
      pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
    ],
  );
}

double _mm(double v) => v * PdfPageFormat.mm;

Future<void> previewGutachtenArbeitsblattPdf(
        GutachtenArbeitsblattPdfData data) =>
    Printing.layoutPdf(
      onLayout: (_) => buildGutachtenArbeitsblattPdf(data),
      name:
          'Arbeitsblatt_${(data.auftrag.aktenzeichen ?? "Akte").replaceAll(RegExp(r"[^A-Za-z0-9-]"), "_")}.pdf',
    );
