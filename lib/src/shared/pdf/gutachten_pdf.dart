import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/database/app_database.dart';
import 'document_pdf.dart' show loadLogoForPdf;

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

  /// Anlagen (Dokumente) am Gutachten — bekommen am Ende eigene Seiten.
  final List<AnlagePdfEntry> anlagen;

  /// Optionales zweites Logo (data:- oder asset:-URL aus den
  /// Briefkopf-Einstellungen). Wird ab Seite 2 anstelle des Haupt-Logos
  /// im Header eingeblendet — typisch z. B. das verkleinerte Wort-Logo.
  final String? logoPfad2;

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
    this.anlagen = const [],
    this.logoPfad2,
  });
}

/// Eine Anlage (z. B. Vertrag, Foto-Original, Lichtbilddokumentation) die
/// hinter den Gutachten-Hauptteil gedruckt wird. PDFs werden seitenweise
/// gerastert (siehe [_rasterAnlagePdf]), Bild-Anlagen direkt eingebettet.
/// Eine Anlage darf mehrere Items enthalten (z. B. eine
/// Lichtbilddokumentation aus N Fotos), die der Reihe nach auf eigenen
/// Seiten ausgegeben werden.
class AnlagePdfEntry {
  const AnlagePdfEntry({
    required this.nr,
    required this.titel,
    required this.items,
    this.kategorie,
    this.datum,
  });
  final int nr;
  final String titel;
  final List<AnlageItem> items;
  final String? kategorie;
  final DateTime? datum;
}

/// Ein einzelnes Item innerhalb einer Anlage — typisch eine PDF-Datei
/// oder ein Foto. Wird einzeln auf eigenen Seiten gerendert.
class AnlageItem {
  const AnlageItem({
    required this.bytes,
    required this.mimeType,
    this.caption,
  });
  final Uint8List bytes;
  final String mimeType;
  final String? caption;
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

Future<Uint8List> buildGutachtenPdf(
  GutachtenPdfData data, {
  /// Wenn `true`, wird das PDF als **PDF/A-3b** ausgegeben (gerichts-
  /// fest archivierbar): XMP-Metadaten mit pdfaid-Konformitätsmarkierung +
  /// sRGB-ICC-Output-Intent. Standard-Variante (false) ist ein normales
  /// PDF 1.7.
  bool pdfA = false,
}) async {
  final dateFmt = DateFormat('dd.MM.yyyy', 'de');

  // Dokumenten-Metadaten (Titel etc.) — bei PDF/A wandern sie zusätzlich
  // in das XMP-RDF, damit Validatoren sie erkennen.
  final aktenzeichen = data.auftrag?.aktenzeichen?.trim() ?? '';
  final titelText = aktenzeichen.isEmpty
      ? 'Gutachten'
      : 'Gutachten $aktenzeichen';
  final autorName = [data.absender?.vorname, data.absender?.nachname]
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .join(' ');
  final beschreibung = data.auftrag?.betreff?.trim();

  final doc = pw.Document(
    title: titelText,
    author: autorName.isEmpty ? null : autorName,
    creator: 'Aktenwerk',
    subject: beschreibung,
    keywords: 'Sachverständigengutachten',
    producer: 'Aktenwerk',
    metadata: pdfA
        ? PdfaRdf(
            title: titelText,
            author: autorName.isEmpty ? null : autorName,
            creator: 'Aktenwerk',
            subject: beschreibung,
            keywords: 'Sachverständigengutachten',
            producer: 'Aktenwerk',
          ).create()
        : null,
  );
  final regular = await PdfGoogleFonts.interRegular();
  final bold = await PdfGoogleFonts.interBold();
  final italic = await PdfGoogleFonts.interMedium();
  final theme = pw.ThemeData.withFont(
    base: regular,
    bold: bold,
    italic: italic,
  );
  // Logo aus Absender-Settings laden (data:-URL oder assets/...).
  final logo = await loadLogoForPdf(data.absender?.logoPfad);
  // Optionales zweites Logo für Folgeseiten — fällt auf das Haupt-Logo
  // zurück, falls in den Einstellungen nichts hinterlegt ist.
  final logo2 = await loadLogoForPdf(data.logoPfad2) ?? logo;

  // Deckblatt
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.fromLTRB(_mm(25), _mm(25), _mm(20), _mm(20)),
      theme: theme,
      build: (ctx) => _deckblatt(data, dateFmt, logo),
    ),
  );

  // Inhaltsverzeichnis auf Seite 2 — listet alle Sektionen, die Inhalt
  // haben (oder die als „abschluss"-Sektion immer mit erscheinen sollen).
  // Leere Punkte werden ausgelassen, weil das Gutachten sie auch im
  // Hauptteil nicht rendert. Innerhalb einer Sektion werden zusätzlich
  // Quill-Headings (H1/H2/H3) als eingerückte Sub-Einträge gelistet.
  final tocEintraege = <_TocEintrag>[];
  var tocIdx = 1;
  for (final key in data.abschnittsReihenfolge) {
    final inhalt = (data.abschnitte[key] ?? '').trim();
    if (key == 's_normenverzeichnis') {
      if (inhalt.isNotEmpty || data.verwendeteNormen.isNotEmpty) {
        tocEintraege.add(_TocEintrag(
            label: data.abschnittsLabels[key] ?? 'Normenverzeichnis',
            nummer: ''));
      }
      continue;
    }
    if (inhalt.isEmpty) continue;
    final label = data.abschnittsLabels[key] ?? key;
    final isAbschluss = key == 's_anlagen';
    tocEintraege.add(_TocEintrag(
      label: label,
      nummer: isAbschluss ? '' : '${_roman(tocIdx)}.',
    ));
    // Headings (H1/H2/H3) aus Quill-Delta scannen und als Sub-Einträge
    // einrücken — H1 → 1 Ebene, H2 → 2 Ebenen, H3 → 3 Ebenen Tiefe.
    for (final h in _extrahiereHeadings(inhalt)) {
      tocEintraege.add(_TocEintrag(
        label: h.text,
        nummer: '',
        einzug: h.level,
      ));
    }
    if (!isAbschluss) tocIdx++;
  }
  if (data.anlagen.isNotEmpty) {
    for (final a in data.anlagen) {
      tocEintraege.add(_TocEintrag(
        label: 'Anlage ${a.nr} — ${a.titel}',
        nummer: '',
      ));
    }
  }
  if (tocEintraege.isNotEmpty) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.fromLTRB(_mm(22), _mm(20), _mm(18), _mm(20)),
        theme: theme,
        build: (ctx) => _inhaltsverzeichnis(tocEintraege),
      ),
    );
  }

  // Abschnitte als MultiPage
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.fromLTRB(_mm(22), _mm(20), _mm(18), _mm(20)),
      theme: theme,
      header: (ctx) => _kopfzeile(data, logo2),
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
          // Sonderfall Normenverzeichnis: bevorzugt der vom Anwender
          // editierte Text. Ist das Feld leer, fallen wir auf die
          // automatisch generierte Normen-Liste der Akte zurück.
          if (key == 's_normenverzeichnis') {
            final hatText = inhalt.isNotEmpty;
            if (!hatText && data.verwendeteNormen.isEmpty) {
              idx++;
              continue;
            }
            final label = data.abschnittsLabels[key] ?? 'Normenverzeichnis';
            widgets.add(pw.Padding(
              padding: pw.EdgeInsets.only(top: _mm(6), bottom: _mm(3)),
              child: pw.Text(
                label,
                style: pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold),
              ),
            ));
            if (hatText) {
              widgets.add(_quillDeltaToRichText(inhalt));
            } else {
              widgets.add(_normenListe(data.verwendeteNormen));
            }
            widgets.add(pw.SizedBox(height: _mm(4)));
            idx++;
            continue;
          }
          if (inhalt.isEmpty && inline.isEmpty) {
            idx++;
            continue;
          }
          final label = data.abschnittsLabels[key] ?? key;
          // Anlagen- und Normenverzeichnis sind „abschluss"-Sektionen ohne
          // römische Nummerierung; alle anderen bekommen die fortlaufende
          // Sektions-Nummer.
          final ueberschrift =
              (key == 's_anlagen' || key == 's_normenverzeichnis')
                  ? label
                  : '${_roman(idx)}. $label';
          widgets.add(pw.Padding(
            padding: pw.EdgeInsets.only(top: _mm(6), bottom: _mm(3)),
            child: pw.Text(
              ueberschrift,
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ));
          if (inhalt.isNotEmpty) {
            // Inline-Foto-Marker `[FOTO:#]` (samt der nachfolgenden
            // „Abb.: …"-Zeile) werden ausgefiltert — die Bilder werden
            // separat über `inlineProAbschnitt` gerendert.
            final cleaned = inhalt
                .replaceAll(
                    RegExp(r'\[FOTO:\d+\]\s*\n?Abb\.:[^\n]*\n?'),
                    '')
                .replaceAll(RegExp(r'\[FOTO:\d+\]\s*\n?'), '')
                .replaceAll(RegExp(r'\n{3,}'), '\n\n')
                .trim();
            if (cleaned.isNotEmpty) {
              widgets.add(_quillDeltaToRichText(cleaned));
            }
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
        widgets.add(pw.SizedBox(height: _mm(14)));
        widgets.add(_unterschriftsBlock(data, dateFmt));
        return widgets;
      },
    ),
  );

  // Helper: legt eine Anlagen-Inhaltsseite an, die in der Standard-
  // Fußzeile auch die Seitenzahl trägt. Die Inhalts-Box steht oben mit
  // wenig Margin, der Footer klebt unten.
  pw.Page anlageSeite(pw.Widget child) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      margin: pw.EdgeInsets.fromLTRB(_mm(15), _mm(15), _mm(15), _mm(15)),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Expanded(child: child),
          _fusszeile(ctx, data.absender),
        ],
      ),
    );
  }

  // Anlagen folgen direkt nach der Unterschrift. Pro Anlage:
  //   1) Deckblatt-Seite „Anlage N — Titel"
  //   2) für jedes Item: Bild-Seite (PDFs werden vorher gerastert).
  // Eine Anlage darf mehrere Items enthalten (z. B. Lichtbilddokumentation
  // mit allen Fotos).
  for (final a in data.anlagen) {
    if (a.items.isEmpty) {
      doc.addPage(_anlageDeckseite(a, dateFmt, theme,
          fusszeile: (ctx) => _fusszeile(ctx, data.absender),
          zusatz: '(Keine Inhalte vorhanden.)'));
      continue;
    }
    doc.addPage(_anlageDeckseite(a, dateFmt, theme,
        fusszeile: (ctx) => _fusszeile(ctx, data.absender)));
    for (final item in a.items) {
      final mime = item.mimeType.toLowerCase();
      final isPdf = mime.contains('pdf');
      if (isPdf) {
        final seitenBilder = await _rasterAnlagePdf(item.bytes);
        if (seitenBilder.isEmpty) {
          doc.addPage(anlageSeite(pw.Center(
            child: pw.Text(
                '(PDF konnte nicht gerastert werden.${item.caption == null ? '' : '\n${item.caption}'})',
                style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                    fontStyle: pw.FontStyle.italic)),
          )));
        } else {
          for (final bild in seitenBilder) {
            doc.addPage(anlageSeite(pw.Center(
              child: pw.Image(bild, fit: pw.BoxFit.contain),
            )));
          }
        }
      } else if (mime.startsWith('image/')) {
        final mem = _safeMemoryImage(item.bytes);
        if (mem == null) {
          doc.addPage(anlageSeite(pw.Center(
            child: pw.Text(
                '(Bild-Format nicht darstellbar.${item.caption == null ? '' : '\n${item.caption}'})',
                style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                    fontStyle: pw.FontStyle.italic)),
          )));
        } else {
          doc.addPage(anlageSeite(pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(
                child:
                    pw.Center(child: pw.Image(mem, fit: pw.BoxFit.contain)),
              ),
              if ((item.caption ?? '').isNotEmpty) ...[
                pw.SizedBox(height: _mm(4)),
                pw.Text(item.caption!,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                        fontStyle: pw.FontStyle.italic)),
              ],
            ],
          )));
        }
      } else {
        // Andere Formate (DOCX, XLSX …) können wir nicht inline rendern.
        doc.addPage(anlageSeite(pw.Center(
          child: pw.Text(
              '(Format $mime — bitte separat ausdrucken oder beilegen.${item.caption == null ? '' : '\n${item.caption}'})',
              style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey700,
                  fontStyle: pw.FontStyle.italic)),
        )));
      }
    }
  }

  if (pdfA) {
    // OutputIntent + sRGB-ICC einbetten — Pflicht für PDF/A-Konformität.
    final iccBytes = await rootBundle.load('assets/pdf/sRGB2014.icc');
    PdfaColorProfile(
      doc.document,
      iccBytes.buffer.asUint8List(),
    );
  }

  return doc.save();
}

/// Rastert ein Anlagen-PDF Seite für Seite zu Bildern, damit wir sie ohne
/// Page-Merging in unser Gutachten-PDF einbetten können. Liefert eine
/// leere Liste, wenn die Bytes nicht geladen werden können.
Future<List<pw.MemoryImage>> _rasterAnlagePdf(Uint8List pdfBytes) async {
  final result = <pw.MemoryImage>[];
  try {
    await for (final raster in Printing.raster(pdfBytes, dpi: 144)) {
      final png = await raster.toPng();
      result.add(pw.MemoryImage(png));
    }
  } catch (_) {
    return const [];
  }
  return result;
}

/// Deckblatt-Seite für eine Anlage: nur Nummer, Titel, Datum, Kategorie.
pw.Page _anlageDeckseite(
  AnlagePdfEntry a,
  DateFormat dateFmt,
  pw.ThemeData theme, {
  String? zusatz,
  pw.Widget Function(pw.Context ctx)? fusszeile,
}) {
  return pw.Page(
    pageFormat: PdfPageFormat.a4,
    theme: theme,
    margin: pw.EdgeInsets.fromLTRB(_mm(22), _mm(22), _mm(22), _mm(15)),
    build: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Expanded(
          child: pw.Center(
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('Anlage ${a.nr}',
                    style: pw.TextStyle(
                        fontSize: 32, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 12),
                pw.Text(a.titel,
                    style: const pw.TextStyle(fontSize: 16),
                    textAlign: pw.TextAlign.center),
                pw.SizedBox(height: 24),
                if (a.datum != null)
                  pw.Text(dateFmt.format(a.datum!),
                      style: pw.TextStyle(
                          fontSize: 12, color: PdfColors.grey700)),
                if ((a.kategorie ?? '').isNotEmpty)
                  pw.Text(a.kategorie!,
                      style: pw.TextStyle(
                          fontSize: 12, color: PdfColors.grey700)),
                if (zusatz != null) ...[
                  pw.SizedBox(height: 16),
                  pw.Text(zusatz,
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontStyle: pw.FontStyle.italic,
                          color: PdfColors.grey700)),
                ],
              ],
            ),
          ),
        ),
        if (fusszeile != null) fusszeile(ctx),
      ],
    ),
  );
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
      child: _safeImage(f.bytes) ??
          pw.Text('(Bild nicht darstellbar)',
              style: pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                  fontStyle: pw.FontStyle.italic)),
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

pw.Widget _normenListe(List<NormenData> normen) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
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
  // Datum oben: Druckdatum (heute), nicht das Abgabe-Datum — der
  // Anwender hat darum gebeten, dass „Ort, den TT.MM.JJJJ" das aktuelle
  // Druckdatum trägt. `abgabeAm` bleibt als Fallback wenn der Datensatz
  // älter ist und kein Datum gesetzt ist.
  final druckdatum = DateTime.now();
  final ort = d.auftrag?.objektOrt ?? (d.absender?.ort ?? '');
  // Vollständiger Name: Vorname Nachname, optional Titel danach.
  final vorname = (d.absender?.vorname ?? '').trim();
  final nachname = (d.absender?.nachname ?? '').trim();
  final titel = (d.absender?.titel ?? '').trim();
  final fullName = [
    if (vorname.isNotEmpty) vorname,
    if (nachname.isNotEmpty) nachname,
    if (titel.isNotEmpty) titel,
  ].join(' ');

  final sig = _safeMemoryImage(d.unterschriftBytes);
  final siegel = _safeMemoryImage(d.siegelBytes);

  final unterschriftsBox = pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      // Zeile 1: „Ort, den TT.MM.JJJJ"
      pw.Text(
        [
          if (ort.isNotEmpty) ort,
          'den ${dateFmt.format(druckdatum)}',
        ].join(', '),
        style: const pw.TextStyle(fontSize: 10),
      ),
      // Platz für die Unterschrift (Bild) — wird im Row daneben gerendert.
      pw.SizedBox(height: _mm(18)),
      // Unterschrift-Linie
      pw.Container(width: _mm(65), height: 0.8, color: PdfColors.grey500),
      pw.SizedBox(height: 2),
      // Vorname + Nachname + Titel als eine Zeile.
      pw.Text(fullName.isEmpty ? '(Sachverständiger)' : fullName,
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

Future<void> previewGutachtenPdf(GutachtenPdfData data, {bool pdfA = false}) =>
    Printing.layoutPdf(
      onLayout: (_) => buildGutachtenPdf(data, pdfA: pdfA),
      name: _gutachtenDateiname(data, pdfA: pdfA),
    );

String _gutachtenDateiname(GutachtenPdfData data, {required bool pdfA}) {
  final az = (data.auftrag?.aktenzeichen ?? '').replaceAll(
      RegExp(r'[\\/:*?"<>|\s]'), '_');
  final suffix = pdfA ? '_PDFA' : '';
  return az.isEmpty
      ? 'Gutachten$suffix.pdf'
      : 'Gutachten_$az$suffix.pdf';
}

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

pw.Widget _deckblatt(
    GutachtenPdfData d, DateFormat dateFmt, pw.ImageProvider? logo) {
  final g = d.gutachten;
  final auftrag = d.auftrag;
  final kunde = d.kunde;
  final absender = d.absender;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      // Briefkopf: Logo links, Absender rechts
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logo != null)
            pw.Container(
              constraints: const pw.BoxConstraints(
                  maxHeight: 60, maxWidth: 200),
              child: pw.Image(logo, fit: pw.BoxFit.contain),
            ),
          pw.Spacer(),
          if (absender != null)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  absender.firma ??
                      [absender.vorname, absender.nachname]
                          .whereType<String>()
                          .join(' '),
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
                if ((absender.bestellungsText ?? '').trim().isNotEmpty)
                  pw.Text(
                    absender.bestellungsText!.split('\n').first,
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey700),
                  ),
                pw.SizedBox(height: 2),
                pw.Text(
                  [
                    absender.strasse,
                    [absender.plz, absender.ort]
                        .whereType<String>()
                        .where((s) => s.isNotEmpty)
                        .join(' '),
                  ].where((s) => (s ?? '').isNotEmpty).join(' · '),
                  style: const pw.TextStyle(fontSize: 9),
                ),
                if ((absender.telefon ?? '').isNotEmpty ||
                    (absender.email ?? '').isNotEmpty)
                  pw.Text(
                    [
                      if ((absender.telefon ?? '').isNotEmpty)
                        'Tel. ${absender.telefon}',
                      if ((absender.email ?? '').isNotEmpty)
                        absender.email,
                    ].whereType<String>().join(' · '),
                    style: const pw.TextStyle(fontSize: 9),
                  ),
              ],
            ),
        ],
      ),
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

pw.Widget _kopfzeile(GutachtenPdfData d, pw.ImageProvider? logo) {
  final az = d.auftrag?.aktenzeichen ?? '';
  final nr = d.gutachten.nummer ?? '';
  final line = [nr, az].where((s) => s.isNotEmpty).join(' · ');
  // Wenn weder Logo noch Beleginfos vorhanden, Header weglassen.
  if (line.isEmpty && logo == null) return pw.SizedBox.shrink();
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
      ),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logo != null)
          pw.Container(
            constraints:
                const pw.BoxConstraints(maxHeight: 30, maxWidth: 120),
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          )
        else
          pw.SizedBox(),
        pw.Text(line,
            style: const pw.TextStyle(
                fontSize: 9, color: PdfColors.grey700)),
      ],
    ),
  );
}

pw.Widget _fusszeile(pw.Context ctx, BenutzerData? absender) {
  // Erweiterte Fußzeile mit Briefkopf-Daten: Name/Firma · Anschrift ·
  // Telefon/Mail · Bank — wie bei Anschreiben/Rechnung. Gibt dem
  // Gutachten den geschäftsbrief-üblichen Anstrich.
  final name = absender?.firma ??
      [absender?.vorname, absender?.nachname]
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .join(' ');
  final anschrift = [
    absender?.strasse,
    [absender?.plz, absender?.ort]
        .whereType<String>()
        .where((s) => (s).trim().isNotEmpty)
        .join(' '),
  ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · ');
  final kontakt = [
    if ((absender?.telefon ?? '').isNotEmpty)
      'Tel. ${absender!.telefon}',
    if ((absender?.email ?? '').isNotEmpty) absender!.email,
    if ((absender?.website ?? '').isNotEmpty) absender!.website,
  ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · ');
  final bank = [
    if ((absender?.bank ?? '').isNotEmpty) absender!.bank,
    if ((absender?.iban ?? '').isNotEmpty) 'IBAN ${absender!.iban}',
    if ((absender?.bic ?? '').isNotEmpty) 'BIC ${absender!.bic}',
  ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · ');
  final ust = [
    if ((absender?.ustId ?? '').isNotEmpty) 'USt-IdNr. ${absender!.ustId}',
    if ((absender?.steuerNr ?? '').isNotEmpty)
      'St-Nr. ${absender!.steuerNr}',
  ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · ');

  return pw.Container(
    padding: const pw.EdgeInsets.only(top: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
      ),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (name.isNotEmpty || anschrift.isNotEmpty || kontakt.isNotEmpty)
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (name.isNotEmpty)
                      pw.Text(name,
                          style: pw.TextStyle(
                              fontSize: 8.5,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey700)),
                    if (anschrift.isNotEmpty)
                      pw.Text(anschrift,
                          style: const pw.TextStyle(
                              fontSize: 8.5,
                              color: PdfColors.grey700)),
                    if (kontakt.isNotEmpty)
                      pw.Text(kontakt,
                          style: const pw.TextStyle(
                              fontSize: 8.5,
                              color: PdfColors.grey700)),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (bank.isNotEmpty)
                    pw.Text(bank,
                        style: const pw.TextStyle(
                            fontSize: 8.5, color: PdfColors.grey700)),
                  if (ust.isNotEmpty)
                    pw.Text(ust,
                        style: const pw.TextStyle(
                            fontSize: 8.5, color: PdfColors.grey700)),
                  pw.Text(
                    'Seite ${ctx.pageNumber} / ${ctx.pagesCount}',
                    style: const pw.TextStyle(
                        fontSize: 8.5, color: PdfColors.grey700),
                  ),
                ],
              ),
            ],
          )
        else
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text(
                'Seite ${ctx.pageNumber} / ${ctx.pagesCount}',
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey600),
              ),
            ],
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
      // Blocksatz für Fließtext, links für Headings — gibt dem
      // Gutachten den professionellen Sachverständigen-Look. Wird über
      // Block-Attribute überschrieben, wenn der Anwender im Editor
      // bewusst Links/Mitte/Rechts wählt.
      textAlign: header != null
          ? pw.TextAlign.left
          : (() {
              final align = blockAttrs?['align'];
              if (align == 'center') return pw.TextAlign.center;
              if (align == 'right') return pw.TextAlign.right;
              return pw.TextAlign.justify;
            })(),
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
    // Quill-BlockEmbeds: {insert: {image: 'data:image/...;base64,...'}}
    if (insert is Map) {
      // Vorhandenen Absatz schließen, damit das Bild auf eigener Zeile
      // beginnt.
      if (currentSpans.isNotEmpty) flushParagraph();
      final imageDataUrl = insert['image'];
      if (imageDataUrl is String) {
        final img = _safeImage(_decodeDataUrl(imageDataUrl));
        if (img != null) {
          paragraphs.add(pw.Container(
            alignment: pw.Alignment.center,
            constraints: const pw.BoxConstraints(maxHeight: 360),
            margin: pw.EdgeInsets.symmetric(vertical: _mm(2)),
            child: img,
          ));
        }
      }
      continue;
    }
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

class _TocEintrag {
  const _TocEintrag(
      {required this.label, required this.nummer, this.einzug = 0});
  final String label;
  final String nummer;
  /// 0 = Sektions-Hauptzeile; >0 = Sub-Heading (H1=1 / H2=2 / H3=3),
  /// wird im Inhaltsverzeichnis entsprechend eingerückt.
  final int einzug;
}

class _Heading {
  const _Heading({required this.text, required this.level});
  final String text;
  final int level;
}

/// Sucht in einem Sektionstext (Plain-Text oder Quill-Delta-JSON) alle
/// Headings (H1/H2/H3) und liefert sie in Reihenfolge des Auftretens.
List<_Heading> _extrahiereHeadings(String inhalt) {
  final out = <_Heading>[];
  final t = inhalt.trim();
  if (t.isEmpty) return out;
  if (!(t.startsWith('[') || t.startsWith('{'))) return out;
  dynamic decoded;
  try {
    decoded = jsonDecode(t);
  } catch (_) {
    return out;
  }
  if (decoded is! List) return out;
  // Quill-Delta-Heuristik: ein Heading wird als Plain-Text-Run mit
  // attributes:{header:N} markiert, wobei der Header beim Newline
  // angewandt wird. Wir sammeln Text-Buffer pro Block und committen
  // ihn beim Newline mit Header-Attribut.
  final buffer = StringBuffer();
  for (final op in decoded) {
    if (op is! Map) continue;
    final insert = op['insert'];
    final attrs = op['attributes'];
    if (insert is String) {
      final parts = insert.split('\n');
      for (var i = 0; i < parts.length; i++) {
        buffer.write(parts[i]);
        if (i < parts.length - 1) {
          // Newline → Block-Ende. Wenn das Op ein Header-Attribut trägt,
          // ist der gesammelte Text die Heading-Zeile.
          if (attrs is Map) {
            final h = attrs['header'];
            if (h is num) {
              final lvl = h.toInt().clamp(1, 3);
              final text = buffer.toString().trim();
              if (text.isNotEmpty) {
                out.add(_Heading(text: text, level: lvl));
              }
            }
          }
          buffer.clear();
        }
      }
    } else {
      // Embed (Bild) — Block-Ende ohne Heading.
      buffer.clear();
    }
  }
  return out;
}

pw.Widget _inhaltsverzeichnis(List<_TocEintrag> eintraege) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('Inhaltsverzeichnis',
          style: pw.TextStyle(
              fontSize: 18, fontWeight: pw.FontWeight.normal)),
      pw.Divider(thickness: 0.6),
      pw.SizedBox(height: _mm(4)),
      for (final e in eintraege)
        pw.Padding(
          padding: pw.EdgeInsets.fromLTRB(
              _mm(e.einzug * 6.0), _mm(0.8), 0, _mm(0.8)),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (e.nummer.isNotEmpty)
                pw.SizedBox(
                  width: _mm(14),
                  child: pw.Text(e.nummer,
                      style: const pw.TextStyle(fontSize: 11)),
                )
              else
                pw.SizedBox(width: e.einzug > 0 ? _mm(8) : _mm(14)),
              pw.Expanded(
                child: pw.Text(
                  e.label,
                  style: pw.TextStyle(
                    fontSize: e.einzug == 0 ? 11 : 10,
                    fontWeight: pw.FontWeight.normal,
                    color: e.einzug > 0 ? PdfColors.grey800 : null,
                  ),
                ),
              ),
              // Punkte-Leader bis zur (rechtsbündigen) Seitenzahl-Spalte.
              pw.Container(
                width: _mm(40),
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  // Platzhalter — exakte Seitenzahlen erfordern einen
                  // 2-Pass-Build und sind eine größere Erweiterung.
                  '…',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey500),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Extrahiert die Bytes aus einer `data:image/<mime>;base64,<payload>`-URL.
/// Liefert `null`, wenn der String kein gültiger Data-URL ist.
Uint8List? _decodeDataUrl(String dataUrl) {
  if (!dataUrl.startsWith('data:')) return null;
  final comma = dataUrl.indexOf(',');
  if (comma < 0) return null;
  try {
    return base64Decode(dataUrl.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

/// Erzeugt ein [pw.MemoryImage] nur dann, wenn die Bytes als von der
/// pdf-Bibliothek unterstütztes Format (PNG/JPEG/GIF) erkennbar sind.
/// Andernfalls `null`, damit ein einzelnes kaputtes Bild nicht den
/// kompletten PDF-Build mit „Unable to guess the image type" abreißt.
pw.MemoryImage? _safeMemoryImage(Uint8List? bytes) {
  if (bytes == null || bytes.length < 4) return null;
  final b = bytes;
  // PNG: 89 50 4E 47
  final isPng = b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
  // JPEG: FF D8 FF
  final isJpg = b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
  // GIF: 47 49 46 38
  final isGif = b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38;
  if (!(isPng || isJpg || isGif)) return null;
  try {
    return pw.MemoryImage(b);
  } catch (_) {
    return null;
  }
}

pw.Widget? _safeImage(Uint8List? bytes,
    {pw.BoxFit fit = pw.BoxFit.contain}) {
  final mem = _safeMemoryImage(bytes);
  if (mem == null) return null;
  return pw.Image(mem, fit: fit);
}
