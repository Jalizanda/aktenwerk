import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/database/app_database.dart';
import '../../features/akten/akte/beteiligte_tab.dart';

/// Eingangsdaten für die eigenständige Express-Fotodokumentation (Anlage).
class FotodokumentationPdfData {
  final AuftraegeData auftrag;
  final List<Foto> fotos;
  /// Layout: 1, 2, 4 oder 6 Bilder pro A4-Seite.
  final int bilderProSeite;
  final String anlagenTitel;
  final BenutzerData? absender;

  const FotodokumentationPdfData({
    required this.auftrag,
    required this.fotos,
    this.bilderProSeite = 2,
    this.anlagenTitel = 'Anlage — Fotodokumentation / Lichtbildanlage',
    this.absender,
  });
}

Future<Uint8List> buildFotodokumentationPdf(
    FotodokumentationPdfData d) async {
  final a = d.auftrag;
  final dateFmt = DateFormat('dd.MM.yyyy', 'de');
  final dateTimeFmt = DateFormat('dd.MM.yyyy HH:mm', 'de');
  final sache = buildSacheKurzbezeichnung(a);

  final doc = pw.Document(
    title: 'Fotodokumentation · ${a.aktenzeichen ?? ""}',
    creator: 'Aktenwerk',
    subject: d.anlagenTitel,
  );

  final regular = await PdfGoogleFonts.interRegular();
  final bold = await PdfGoogleFonts.interBold();
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);

  final validFotos =
      d.fotos.where((f) => f.daten != null && f.daten!.isNotEmpty).toList();

  final proSeite = switch (d.bilderProSeite) {
    1 => 1,
    2 => 2,
    4 => 4,
    6 => 6,
    _ => 2,
  };

  // Chunk fotos into pages of size `proSeite`.
  final chunks = <List<({int nr, Foto foto})>>[];
  for (var i = 0; i < validFotos.length; i += proSeite) {
    final slice = <({int nr, Foto foto})>[];
    for (var j = i; j < i + proSeite && j < validFotos.length; j++) {
      slice.add((nr: j + 1, foto: validFotos[j]));
    }
    chunks.add(slice);
  }
  if (chunks.isEmpty) {
    chunks.add(const []);
  }

  for (var pageIdx = 0; pageIdx < chunks.length; pageIdx++) {
    final pageFotos = chunks[pageIdx];
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.fromLTRB(_mm(16), _mm(15), _mm(16), _mm(15)),
        theme: theme,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Kopfzeile
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      d.anlagenTitel,
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blueGrey900,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      [
                        if (sache.isNotEmpty) 'Sache: $sache',
                        if ((a.objektStrasse ?? '').isNotEmpty ||
                            (a.objektOrt ?? '').isNotEmpty)
                          'Objekt: ${[a.objektStrasse, a.objektOrt].whereType<String>().where((s) => s.isNotEmpty).join(", ")}',
                      ].join(' · '),
                      style: const pw.TextStyle(
                          fontSize: 8.5, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Az.: ${a.aktenzeichen ?? "—"}',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if ((a.gerichtsAktenzeichen ?? '').trim().isNotEmpty)
                      pw.Text(
                        'Gerichts-AZ: ${a.gerichtsAktenzeichen}',
                        style: const pw.TextStyle(
                            fontSize: 8.5, color: PdfColors.grey700),
                      ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Divider(height: 1, thickness: 0.7, color: PdfColors.blueGrey700),
            pw.SizedBox(height: 8),

            // Hauptbereich mit Bildern im gewählten Raster
            pw.Expanded(
              child: pageFotos.isEmpty
                  ? pw.Center(
                      child: pw.Text('Keine Fotos mit Bilddaten vorhanden.'),
                    )
                  : _buildPageGrid(
                      pageFotos,
                      proSeite: proSeite,
                      dateTimeFmt: dateTimeFmt,
                    ),
            ),

            pw.SizedBox(height: 6),
            pw.Divider(height: 1, thickness: 0.4, color: PdfColors.grey400),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Fotodokumentation (${validFotos.length} Aufnahmen) · Stand ${dateFmt.format(DateTime.now())}',
                  style:
                      const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
                pw.Text(
                  'Seite ${pageIdx + 1} von ${chunks.length}',
                  style:
                      const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  return doc.save();
}

pw.Widget _buildPageGrid(
  List<({int nr, Foto foto})> items, {
  required int proSeite,
  required DateFormat dateTimeFmt,
}) {
  if (proSeite == 1) {
    final item = items.first;
    return _buildFotoCard(
      item.nr,
      item.foto,
      imageHeight: _mm(175),
      dateTimeFmt: dateTimeFmt,
      compact: false,
    );
  }
  if (proSeite == 2) {
    return pw.Column(
      children: [
        pw.Expanded(
          child: _buildFotoCard(
            items[0].nr,
            items[0].foto,
            imageHeight: _mm(90),
            dateTimeFmt: dateTimeFmt,
            compact: false,
          ),
        ),
        pw.SizedBox(height: _mm(6)),
        pw.Expanded(
          child: items.length > 1
              ? _buildFotoCard(
                  items[1].nr,
                  items[1].foto,
                  imageHeight: _mm(90),
                  dateTimeFmt: dateTimeFmt,
                  compact: false,
                )
              : pw.SizedBox(),
        ),
      ],
    );
  }

  // 4 oder 6 Bilder pro Seite -> 2 Spalten x (2 bzw. 3 Zeilen)
  final rowsCount = proSeite == 4 ? 2 : 3;
  final imgHeight = proSeite == 4 ? _mm(76) : _mm(50);

  return pw.Column(
    children: [
      for (var r = 0; r < rowsCount; r++) ...[
        if (r > 0) pw.SizedBox(height: _mm(4)),
        pw.Expanded(
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Expanded(
                child: (r * 2 < items.length)
                    ? _buildFotoCard(
                        items[r * 2].nr,
                        items[r * 2].foto,
                        imageHeight: imgHeight,
                        dateTimeFmt: dateTimeFmt,
                        compact: true,
                      )
                    : pw.SizedBox(),
              ),
              pw.SizedBox(width: _mm(4)),
              pw.Expanded(
                child: (r * 2 + 1 < items.length)
                    ? _buildFotoCard(
                        items[r * 2 + 1].nr,
                        items[r * 2 + 1].foto,
                        imageHeight: imgHeight,
                        dateTimeFmt: dateTimeFmt,
                        compact: true,
                      )
                    : pw.SizedBox(),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}

pw.Widget _buildFotoCard(
  int nr,
  Foto f, {
  required double imageHeight,
  required DateFormat dateTimeFmt,
  required bool compact,
}) {
  pw.Widget imgWidget;
  try {
    imgWidget = pw.Image(
      pw.MemoryImage(f.daten!),
      fit: pw.BoxFit.contain,
    );
  } catch (_) {
    imgWidget = pw.Center(
      child: pw.Text(
        'Bilddaten nicht darstellbar',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    );
  }

  final titel = (f.titel ?? '').trim();
  final raum = (f.raum ?? '').trim();
  final beschr = (f.beschreibung ?? '').trim();
  final aufnahme =
      f.aufnahmeAm != null ? dateTimeFmt.format(f.aufnahmeAm!) : '';

  return pw.Container(
    padding: pw.EdgeInsets.all(compact ? 5 : 8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          height: imageHeight,
          color: PdfColors.grey100,
          alignment: pw.Alignment.center,
          child: imgWidget,
        ),
        pw.SizedBox(height: compact ? 4 : 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                [
                  'Abb. $nr',
                  if (titel.isNotEmpty) titel,
                  if (raum.isNotEmpty) '($raum)',
                ].join(' · '),
                style: pw.TextStyle(
                  fontSize: compact ? 8.5 : 9.5,
                  fontWeight: pw.FontWeight.bold,
                ),
                maxLines: 1,
              ),
            ),
            if (aufnahme.isNotEmpty)
              pw.Text(
                aufnahme,
                style: pw.TextStyle(
                  fontSize: compact ? 7.5 : 8,
                  color: PdfColors.grey700,
                ),
              ),
          ],
        ),
        if (beschr.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            beschr,
            style: pw.TextStyle(
              fontSize: compact ? 8 : 9,
              color: PdfColors.grey800,
            ),
            maxLines: compact ? 2 : 4,
          ),
        ],
      ],
    ),
  );
}

double _mm(double v) => v * PdfPageFormat.mm;

Future<void> previewFotodokumentationPdf(FotodokumentationPdfData data) =>
    Printing.layoutPdf(
      onLayout: (_) => buildFotodokumentationPdf(data),
      name:
          'Fotodokumentation_${(data.auftrag.aktenzeichen ?? "Akte").replaceAll(RegExp(r"[^A-Za-z0-9-]"), "_")}.pdf',
    );
