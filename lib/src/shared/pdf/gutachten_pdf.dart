import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/database/app_database.dart';

/// Eingangsdaten für den Gutachten-PDF-Export.
class GutachtenPdfData {
  final GutachtenData gutachten;
  final AuftraegeData? auftrag;
  final KundenData? kunde;
  final BenutzerData? absender;
  /// Map `abschnittsKey → Text`. Key passt zu [abschnittsReihenfolge]
  /// und zu [abschnittsLabels].
  final Map<String, String> abschnitte;

  /// Reihenfolge der Abschnitts-Keys im PDF.
  final List<String> abschnittsReihenfolge;

  /// Map `abschnittsKey → menschenlesbares Label` für die PDF-Überschriften.
  final Map<String, String> abschnittsLabels;

  /// Sachverständigen-Siegel (PNG/JPG-Bytes) fürs Unterschriftsblock.
  final Uint8List? siegelBytes;
  /// Unterschrifts-Scan.
  final Uint8List? unterschriftBytes;
  /// 'unten_links' | 'unten_rechts' | 'mit_unterschrift'.
  final String siegelPosition;
  final String? bestellBehoerde;
  final String? bestellNr;
  final DateTime? bestellGueltigBis;

  /// Verwendete Normen der Akte — werden am Ende als Quellenliste
  /// ausgegeben.
  final List<NormenData> verwendeteNormen;

  /// Lichtbildanlage: Fotos (Metadaten + bereits heruntergeladene Bytes)
  /// die ans Gutachten gepinnt sind. Jedes Tuple liefert Titel,
  /// Beschreibung, Raum und die Bild-Bytes.
  final List<LichtbildPdfEntry> lichtbilder;

  const GutachtenPdfData({
    required this.gutachten,
    required this.abschnitte,
    required this.abschnittsReihenfolge,
    this.abschnittsLabels = const {},
    this.auftrag,
    this.kunde,
    this.absender,
    this.siegelBytes,
    this.unterschriftBytes,
    this.siegelPosition = 'unten_rechts',
    this.bestellBehoerde,
    this.bestellNr,
    this.bestellGueltigBis,
    this.verwendeteNormen = const [],
    this.lichtbilder = const [],
  });
}

/// Ein Lichtbild als Teil der Gutachten-Anlage.
class LichtbildPdfEntry {
  const LichtbildPdfEntry({
    required this.bytes,
    this.titel,
    this.raum,
    this.beschreibung,
    this.abschnittKey,
  });
  final Uint8List bytes;
  final String? titel;
  final String? raum;
  final String? beschreibung;

  /// Wenn gesetzt, wird das Foto im passenden Gutachten-Abschnitt
  /// direkt hinter dem Text eingefügt statt in der Lichtbildanlage
  /// am Ende.
  final String? abschnittKey;
}

Future<Uint8List> buildGutachtenPdf(GutachtenPdfData data) async {
  final doc = pw.Document();
  final dateFmt = DateFormat('dd.MM.yyyy', 'de');
  final regular = await PdfGoogleFonts.interRegular();
  final bold = await PdfGoogleFonts.interBold();
  final italic = await PdfGoogleFonts.interMedium();
  final theme = pw.ThemeData.withFont(
    base: regular,
    bold: bold,
    italic: italic,
  );

  // Deckblatt
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.fromLTRB(_mm(25), _mm(25), _mm(20), _mm(20)),
      theme: theme,
      build: (ctx) => _deckblatt(data, dateFmt),
    ),
  );

  // Abschnitte als MultiPage
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.fromLTRB(_mm(22), _mm(20), _mm(18), _mm(20)),
      theme: theme,
      header: (ctx) => _kopfzeile(data),
      footer: (ctx) => _fusszeile(ctx, data.absender),
      build: (ctx) {
        // Fotos nach Abschnitts-Key gruppieren; Fotos ohne Key landen
        // später in der Lichtbildanlage.
        final inlineProAbschnitt = <String, List<LichtbildPdfEntry>>{};
        for (final l in data.lichtbilder) {
          final k = l.abschnittKey;
          if (k == null || k.isEmpty) continue;
          (inlineProAbschnitt[k] ??= []).add(l);
        }
        final widgets = <pw.Widget>[];
        var idx = 1;
        // Globaler Fotozähler — die Nummerierung läuft quer durch Inline-
        // und Anlagen-Fotos, damit Bild-Referenzen eindeutig bleiben.
        var fotoIndex = 1;
        for (final key in data.abschnittsReihenfolge) {
          final inhalt = (data.abschnitte[key] ?? '').trim();
          final inline = inlineProAbschnitt[key] ?? const [];
          if (inhalt.isEmpty && inline.isEmpty) {
            idx++;
            continue;
          }
          final label = data.abschnittsLabels[key] ?? key;
          widgets.add(pw.Padding(
            padding: pw.EdgeInsets.only(top: _mm(6), bottom: _mm(3)),
            child: pw.Text(
              '${_roman(idx)}. $label',
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ));
          if (inhalt.isNotEmpty) {
            widgets.add(_quillDeltaToRichText(inhalt));
          }
          if (inline.isNotEmpty) {
            widgets.add(pw.SizedBox(height: _mm(3)));
            for (final f in inline) {
              widgets.addAll(_lichtbildBlock(f, fotoIndex));
              fotoIndex++;
            }
          }
          widgets.add(pw.SizedBox(height: _mm(4)));
          idx++;
        }
        if (widgets.isEmpty) {
          widgets.add(pw.Text('Keine Inhalte erfasst.',
              style: const pw.TextStyle(fontSize: 11)));
        }
        if (data.verwendeteNormen.isNotEmpty) {
          widgets.add(pw.SizedBox(height: _mm(10)));
          widgets.add(_quellenListe(data.verwendeteNormen));
        }
        widgets.add(pw.SizedBox(height: _mm(14)));
        widgets.add(_unterschriftsBlock(data, dateFmt));
        return widgets;
      },
    ),
  );

  // Lichtbild-Anlage nur mit den Fotos *ohne* Abschnitts-Zuordnung
  // (inline-Fotos stehen bereits in den Abschnitten).
  final anlageFotos = data.lichtbilder
      .where((f) => (f.abschnittKey ?? '').isEmpty)
      .toList();
  if (anlageFotos.isNotEmpty) {
    // Offset für die Nummerierung: alle inline-Fotos vorher zählen.
    final inlineVorher = data.lichtbilder
        .where((f) => (f.abschnittKey ?? '').isNotEmpty)
        .length;
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.fromLTRB(_mm(22), _mm(20), _mm(18), _mm(20)),
        theme: theme,
        header: (ctx) => _kopfzeile(data),
        footer: (ctx) => _fusszeile(ctx, data.absender),
        build: (ctx) =>
            _lichtbildAnlage(anlageFotos, startIndex: inlineVorher + 1),
      ),
    );
  }

  return doc.save();
}

List<pw.Widget> _lichtbildAnlage(
  List<LichtbildPdfEntry> fotos, {
  int startIndex = 1,
}) {
  final widgets = <pw.Widget>[
    pw.Text('Lichtbildanlage',
        style: pw.TextStyle(
            fontSize: 15, fontWeight: pw.FontWeight.bold)),
    pw.Divider(thickness: 0.5),
    pw.SizedBox(height: 4),
  ];
  for (var i = 0; i < fotos.length; i++) {
    widgets.addAll(_lichtbildBlock(fotos[i], startIndex + i));
  }
  return widgets;
}

List<pw.Widget> _lichtbildBlock(LichtbildPdfEntry f, int nr) {
  // Einzeln in pw.Wrap packen, damit Titel + Bild möglichst zusammen
  // auf einer Seite umbrechen.
  return [
    pw.Padding(
      padding: pw.EdgeInsets.only(top: _mm(3), bottom: _mm(1)),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Bild $nr',
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold)),
          if ((f.titel ?? '').isNotEmpty) ...[
            pw.SizedBox(width: 6),
            pw.Expanded(
              child: pw.Text(f.titel!,
                  style: const pw.TextStyle(fontSize: 11)),
            ),
          ],
          if ((f.raum ?? '').isNotEmpty) ...[
            pw.SizedBox(width: 6),
            pw.Text('— ${f.raum!}',
                style: pw.TextStyle(
                    fontSize: 10, color: PdfColors.grey700)),
          ],
        ],
      ),
    ),
    pw.Container(
      alignment: pw.Alignment.center,
      constraints: const pw.BoxConstraints(maxHeight: 340),
      child: pw.Image(
        pw.MemoryImage(f.bytes),
        fit: pw.BoxFit.contain,
      ),
    ),
    if ((f.beschreibung ?? '').isNotEmpty)
      pw.Padding(
        padding: pw.EdgeInsets.only(top: _mm(1)),
        child: pw.Text(f.beschreibung!,
            style: pw.TextStyle(
                fontSize: 10,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey700)),
      ),
    pw.SizedBox(height: _mm(4)),
  ];
}

pw.Widget _quellenListe(List<NormenData> normen) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('Herangezogene Normen, Richtlinien und Regelwerke',
          style: pw.TextStyle(
              fontSize: 12, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Divider(thickness: 0.5),
      pw.SizedBox(height: 2),
      ...normen.map((n) {
        final zeile = <String>[
          n.nummer,
          if (n.ausgabe != null && n.ausgabe!.isNotEmpty) '(${n.ausgabe})',
          if (n.titel != null && n.titel!.isNotEmpty) '— ${n.titel}',
        ].join(' ');
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.2),
          child: pw.Text(
            '• $zeile',
            style: const pw.TextStyle(fontSize: 10),
          ),
        );
      }),
    ],
  );
}

pw.Widget _unterschriftsBlock(GutachtenPdfData d, DateFormat dateFmt) {
  final abgabe = d.gutachten.abgabeAm;
  final absName = [
    d.absender?.vorname,
    d.absender?.nachname,
  ].whereType<String>().where((s) => s.isNotEmpty).join(' ');

  final sig = d.unterschriftBytes == null
      ? null
      : pw.MemoryImage(d.unterschriftBytes!);
  final siegel =
      d.siegelBytes == null ? null : pw.MemoryImage(d.siegelBytes!);

  final unterschriftsBox = pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        d.auftrag?.objektOrt ??
            (d.absender?.ort ?? ''),
        style: const pw.TextStyle(fontSize: 10),
      ),
      pw.SizedBox(height: 2),
      pw.Text(abgabe == null ? '' : dateFmt.format(abgabe),
          style: const pw.TextStyle(fontSize: 10)),
      pw.SizedBox(height: _mm(14)),
      pw.Container(width: _mm(65), height: 0.8, color: PdfColors.grey500),
      pw.SizedBox(height: 2),
      pw.Text(absName.isEmpty ? '(Sachverständiger)' : absName,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      if ((d.bestellBehoerde ?? '').isNotEmpty)
        pw.Text(d.bestellBehoerde!,
            style: const pw.TextStyle(fontSize: 9)),
      if ((d.bestellNr ?? '').isNotEmpty)
        pw.Text('Bestell-Nr. ${d.bestellNr}',
            style: const pw.TextStyle(fontSize: 9)),
      if (d.bestellGueltigBis != null)
        pw.Text('gültig bis ${dateFmt.format(d.bestellGueltigBis!)}',
            style: const pw.TextStyle(fontSize: 9)),
    ],
  );

  final siegelBox = siegel == null
      ? pw.SizedBox(width: _mm(40), height: _mm(40))
      : pw.Container(
          width: _mm(40),
          height: _mm(40),
          alignment: pw.Alignment.center,
          child: pw.Image(siegel, fit: pw.BoxFit.contain),
        );

  final sigBox = sig == null
      ? pw.SizedBox(width: _mm(55), height: _mm(20))
      : pw.Container(
          width: _mm(55),
          height: _mm(20),
          alignment: pw.Alignment.centerLeft,
          child: pw.Image(sig, fit: pw.BoxFit.contain),
        );

  // Layout: bei 'unten_links' ist Siegel links von Unterschrift; sonst rechts.
  final leftRightReversed = d.siegelPosition == 'unten_links';
  final rowChildren = <pw.Widget>[
    if (d.siegelPosition == 'mit_unterschrift')
      pw.Stack(
        alignment: pw.Alignment.center,
        children: [
          sigBox,
          if (siegel != null)
            pw.Opacity(opacity: 0.65, child: siegelBox),
        ],
      )
    else if (leftRightReversed) ...[
      siegelBox,
      pw.SizedBox(width: _mm(10)),
      unterschriftsBox,
      pw.Spacer(),
      sigBox,
    ] else ...[
      unterschriftsBox,
      pw.Spacer(),
      sigBox,
      pw.SizedBox(width: _mm(10)),
      siegelBox,
    ],
  ];

  if (d.siegelPosition == 'mit_unterschrift') {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        unterschriftsBox,
        pw.Spacer(),
        rowChildren.first,
      ],
    );
  }
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: rowChildren,
  );
}

Future<void> previewGutachtenPdf(GutachtenPdfData data) =>
    Printing.layoutPdf(onLayout: (_) => buildGutachtenPdf(data));

// ---------------- Helfer ----------------

double _mm(double v) => v * PdfPageFormat.mm;

String _roman(int n) {
  const roman = [
    [1000, 'M'], [900, 'CM'], [500, 'D'], [400, 'CD'],
    [100, 'C'], [90, 'XC'], [50, 'L'], [40, 'XL'],
    [10, 'X'], [9, 'IX'], [5, 'V'], [4, 'IV'], [1, 'I'],
  ];
  final sb = StringBuffer();
  var v = n;
  for (final r in roman) {
    while (v >= (r[0] as int)) {
      sb.write(r[1] as String);
      v -= r[0] as int;
    }
  }
  return sb.toString();
}

pw.Widget _deckblatt(GutachtenPdfData d, DateFormat dateFmt) {
  final g = d.gutachten;
  final auftrag = d.auftrag;
  final kunde = d.kunde;
  final absender = d.absender;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      if (absender != null) ...[
        pw.Text(
          absender.firma ??
              [absender.vorname, absender.nachname]
                  .whereType<String>()
                  .join(' '),
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          [
            absender.strasse,
            [absender.plz, absender.ort]
                .whereType<String>()
                .where((s) => s.isNotEmpty)
                .join(' '),
          ].where((s) => (s ?? '').isNotEmpty).join(' · '),
          style: const pw.TextStyle(fontSize: 10),
        ),
      ],
      pw.Spacer(),
      pw.Center(
        child: pw.Column(
          children: [
            pw.Text('GUTACHTEN',
                style: pw.TextStyle(
                    fontSize: 36, fontWeight: pw.FontWeight.bold)),
            if ((g.nummer ?? '').isNotEmpty) ...[
              pw.SizedBox(height: _mm(4)),
              pw.Text(g.nummer!,
                  style: const pw.TextStyle(fontSize: 14)),
            ],
            pw.SizedBox(height: _mm(14)),
            if ((g.titel ?? '').isNotEmpty)
              pw.Text(g.titel!,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
            if ((g.bezeichnung ?? '').isNotEmpty) ...[
              pw.SizedBox(height: _mm(4)),
              pw.Text(g.bezeichnung!,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 13)),
            ],
          ],
        ),
      ),
      pw.Spacer(),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (auftrag != null) ...[
              _row('Aktenzeichen', auftrag.aktenzeichen ?? '—'),
              if ((auftrag.gerichtsAktenzeichen ?? '').isNotEmpty)
                _row('Az. Gericht', auftrag.gerichtsAktenzeichen!),
            ],
            if (kunde != null)
              _row(
                'Auftraggeber',
                [
                  kunde.firma,
                  [kunde.vorname, kunde.nachname]
                      .whereType<String>()
                      .where((s) => s.isNotEmpty)
                      .join(' ')
                ].where((s) => (s ?? '').isNotEmpty).join(' · '),
              ),
            if (auftrag != null &&
                ((auftrag.objektStrasse ?? '').isNotEmpty))
              _row('Objekt',
                  '${auftrag.objektStrasse}, ${auftrag.objektPlz ?? ''} ${auftrag.objektOrt ?? ''}'
                      .trim()),
            if (g.ortsterminAm != null)
              _row('Ortstermin', dateFmt.format(g.ortsterminAm!)),
            if (g.datum != null)
              _row('Gutachten vom', dateFmt.format(g.datum!)),
            if (g.abgabeAm != null)
              _row('Abgabe', dateFmt.format(g.abgabeAm!)),
            _row('Status', g.status),
          ],
        ),
      ),
      pw.SizedBox(height: _mm(10)),
      pw.Text('Aktenwerk · Sachverständigen-Suite',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
    ],
  );
}

pw.Widget _row(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 100,
          child: pw.Text(label,
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey700)),
        ),
        pw.Expanded(
          child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
        ),
      ],
    ),
  );
}

pw.Widget _kopfzeile(GutachtenPdfData d) {
  final az = d.auftrag?.aktenzeichen ?? '';
  final nr = d.gutachten.nummer ?? '';
  final line = [nr, az].where((s) => s.isNotEmpty).join(' · ');
  if (line.isEmpty) return pw.SizedBox.shrink();
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
      ),
    ),
    child: pw.Text(line,
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
  );
}

pw.Widget _fusszeile(pw.Context ctx, BenutzerData? absender) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(top: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
      ),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          absender?.firma ??
              [absender?.vorname, absender?.nachname]
                  .whereType<String>()
                  .join(' '),
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
        pw.Text(
          'Seite ${ctx.pageNumber} / ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      ],
    ),
  );
}

/// Einfacher Quill-Delta → PDF-Text-Renderer. Unterstützt **bold**, *italic*,
/// Header 1–3 und einfache Aufzählungs-/Nummernlisten.
pw.Widget _quillDeltaToRichText(String json) {
  List ops;
  try {
    final parsed = jsonDecode(json);
    if (parsed is List) {
      ops = parsed;
    } else if (parsed is Map && parsed['ops'] is List) {
      ops = parsed['ops'] as List;
    } else {
      // Fallback: treat as plain text.
      return pw.Text(json, style: const pw.TextStyle(fontSize: 11));
    }
  } catch (_) {
    return pw.Text(json, style: const pw.TextStyle(fontSize: 11));
  }

  final paragraphs = <pw.Widget>[];
  final currentSpans = <pw.InlineSpan>[];
  Map<String, dynamic>? blockAttrs;

  void flushParagraph() {
    if (currentSpans.isEmpty) {
      paragraphs.add(pw.SizedBox(height: _mm(2)));
      return;
    }
    final header = blockAttrs?['header'];
    final isBullet = blockAttrs?['list'] == 'bullet';
    final isOrdered = blockAttrs?['list'] == 'ordered';
    final style = header == 1
        ? pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)
        : header == 2
            ? pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)
            : header == 3
                ? pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)
                : const pw.TextStyle(fontSize: 11);
    final rich = pw.RichText(
      text: pw.TextSpan(
        children: currentSpans.toList(),
        style: style,
      ),
    );
    if (isBullet) {
      paragraphs.add(pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Padding(
            padding: pw.EdgeInsets.only(right: _mm(2), top: 2),
            child: pw.Text('•',
                style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Expanded(child: rich),
        ],
      ));
    } else if (isOrdered) {
      paragraphs.add(pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Padding(
            padding: pw.EdgeInsets.only(right: _mm(2), top: 2),
            child: pw.Text('·',
                style: const pw.TextStyle(fontSize: 11)),
          ),
          pw.Expanded(child: rich),
        ],
      ));
    } else {
      paragraphs.add(rich);
    }
    paragraphs.add(pw.SizedBox(height: _mm(2)));
    currentSpans.clear();
    blockAttrs = null;
  }

  for (final op in ops) {
    if (op is! Map) continue;
    final insert = op['insert'];
    if (insert is! String) continue;
    final attrs = op['attributes'] as Map<String, dynamic>?;

    final parts = insert.split('\n');
    for (var i = 0; i < parts.length; i++) {
      final text = parts[i];
      if (text.isNotEmpty) {
        currentSpans.add(
          pw.TextSpan(
            text: text,
            style: pw.TextStyle(
              fontWeight: attrs?['bold'] == true
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
              fontStyle: attrs?['italic'] == true
                  ? pw.FontStyle.italic
                  : pw.FontStyle.normal,
              decoration: attrs?['underline'] == true
                  ? pw.TextDecoration.underline
                  : null,
            ),
          ),
        );
      }
      if (i < parts.length - 1) {
        // Der Newline gilt als Block-Ende. Block-Attribute stehen am Ende.
        if (attrs != null && attrs.keys.any((k) =>
            k == 'header' || k == 'list' || k == 'blockquote')) {
          blockAttrs = attrs;
        }
        flushParagraph();
      }
    }
  }
  // Letzten offenen Absatz flushen.
  if (currentSpans.isNotEmpty) flushParagraph();

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: paragraphs,
  );
}
