import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/database/app_database.dart';
import '../positionen/position_model.dart';

/// Gemeinsame Struktur für Rechnungs-/Angebots-/AB-PDFs.
/// Das Layout orientiert sich 1:1 an den Originalen aus der SV-Software
/// (Absender-Mini-Zeile, Empfänger links, Metadaten rechts, Positionen mit
/// Langtext, Summen-Block rechtsbündig, optional SEPA-QR am Fuß).
class PdfDocumentData {
  final String dokumentTyp;
  final String? dokumentNr;
  final DateTime? datum;
  final DateTime? faelligBis;
  final String? betreff;

  /// Eindeutige Auftragsnummer (Aktenzeichen). Wird auf Folgeseiten oben
  /// links zusammen mit Dokumenttyp und Belegnummer angedruckt.
  final String? aktenzeichen;

  /// Anfrage-/Sachverhalts-Text (für Angebot/AB oben unter dem Titel).
  final String? sachverhalt;

  /// Objekt-Adresse (optionaler separater Block im Angebot).
  final String? objektAdresse;

  final List<Position> positionen;

  /// Vorgeschaltete Einleitung zwischen Titel und Sachverhalt
  /// (überschreibt den automatischen Default-Text).
  final String? kopftext;

  /// Schlusstext / AGB / Zahlungshinweis.
  final String? fusstext;

  final BenutzerData? absender;
  final KundenData? empfaenger;

  /// Wenn > 0 und [mitSepaQr] true, wird ein SEPA-QR am Fuß eingebettet.
  final double? brutto;
  final bool mitSepaQr;

  /// Label-Text in der Metadaten-Tabelle oben rechts für die Nummer.
  /// Default passt zum `dokumentTyp` (Angebots-Nr., Rechnungs-Nr., AB-Nr.).
  final String? nummerLabel;

  /// Gericht, gerichtliches Aktenzeichen und Streitparteien der Akte —
  /// werden als eigener „In Sachen"-Block zwischen Titel und Sachverhalt
  /// ausgewiesen, sofern mindestens ein Feld gesetzt ist.
  final String? gericht;
  final String? gerichtsAktenzeichen;
  final String? klaeger;
  final String? beklagter;

  /// Skonto-Prozent, falls gewünscht — erzeugt eine Skonto-Box vor dem
  /// SEPA-QR-Block.
  final double? skontoProzent;

  /// Skonto-Frist in Tagen (gerechnet ab [datum]).
  final int? skontoTage;

  /// Barzahlung — erzeugt eine Quittungs-Zeile „in bar erhalten am ___"
  /// mit Unterschriftsfeld.
  final bool barzahlung;

  const PdfDocumentData({
    required this.dokumentTyp,
    this.dokumentNr,
    this.datum,
    this.faelligBis,
    this.betreff,
    this.aktenzeichen,
    this.sachverhalt,
    this.objektAdresse,
    this.positionen = const [],
    this.kopftext,
    this.fusstext,
    this.absender,
    this.empfaenger,
    this.brutto,
    this.mitSepaQr = false,
    this.nummerLabel,
    this.skontoProzent,
    this.skontoTage,
    this.barzahlung = false,
    this.gericht,
    this.gerichtsAktenzeichen,
    this.klaeger,
    this.beklagter,
  });
}

Future<Uint8List> buildDocumentPdf(PdfDocumentData data) async {
  final doc = pw.Document();
  final dateFmt = DateFormat('d.M.yyyy', 'de');
  final druckDatum = DateFormat('dd.MM.yyyy').format(DateTime.now());
  final money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
  final totals = PositionsTotals.fromList(data.positionen);
  final logo = await _loadLogo(data.absender?.logoPfad);
  // QR-Code immer zeigen bei Rechnungen (inkl. Korrektur), sobald Brutto > 0
  // und IBAN vorhanden.
  final istRechnung = data.dokumentTyp.startsWith('Rechnung') ||
      data.dokumentTyp == 'Rechnungskorrektur';
  final zeigeQr = data.mitSepaQr || istRechnung;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      // Margins: oben 10mm (Logo ragt aus dem Header), rechts/links 18mm.
      // Unten 0mm → die Fußzeile sitzt direkt am Papierende (1 cm tiefer
      // als vorher, wie von Anwendern gewünscht).
      margin:
          pw.EdgeInsets.fromLTRB(_mm(18), _mm(10), _mm(18), 0),
      theme: pw.ThemeData.withFont(
        base: await PdfGoogleFonts.interRegular(),
        bold: await PdfGoogleFonts.interBold(),
        italic: await PdfGoogleFonts.interMedium(),
      ),
      // Header rendert auf JEDER Seite: Logo oben rechts + Folgeseiten-Info
      // oben links (Auftragsnummer · Dokumenttyp · Belegnr + Druckdatum).
      header: (ctx) => _pageHeader(data, logo, ctx, druckDatum),
      // Footer rendert auf JEDER Seite mit dünnem Strich darüber.
      footer: (ctx) => _footer(data.absender),
      build: (ctx) => [
        // Kein zusätzlicher Spacer nötig — der Header ist jetzt 44mm
        // hoch (Logo 20mm tiefer), und das Adressfeld soll unmittelbar
        // unter dem Logo ins DIN-Sichtfenster rücken.
        pw.SizedBox(height: _mm(2)),
        // Erste-Seite-Block: Empfänger mit Absender-Mini (Sichtfenster-Höhe)
        // + Metadaten rechts. Nur auf Seite 1.
        _ersteSeiteKopf(data, dateFmt),
        pw.SizedBox(height: _mm(8)),
        pw.Text(
          data.dokumentTyp,
          style:
              pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: _mm(6)),
        _introText(data),
        pw.SizedBox(height: _mm(6)),
        _positionenTabelle(data.positionen, money),
        pw.SizedBox(height: _mm(4)),
        _summenBlock(totals, money, data.dokumentTyp),
        if ((data.fusstext ?? '').isNotEmpty) ...[
          pw.SizedBox(height: _mm(6)),
          pw.Text(data.fusstext!,
              style: const pw.TextStyle(fontSize: 10)),
        ],
        if (data.skontoProzent != null && data.skontoTage != null)
          _skontoBlock(data, money, dateFmt),
        if (data.barzahlung) _barQuittungBlock(data, money),
        if (zeigeQr) _sepaQrBlock(data, money),
      ],
    ),
  );

  return doc.save();
}

Future<void> previewDocumentPdf(PdfDocumentData data) async {
  await Printing.layoutPdf(onLayout: (_) => buildDocumentPdf(data));
}

/// Baut EIN gebündeltes PDF aus mehreren [PdfDocumentData]. Jeder Beleg
/// bekommt seine eigenen Seiten (MultiPage), alle zusammen in einem PDF.
/// Wird für den Monats-Sammelausdruck im Steuer-Modul genutzt.
Future<Uint8List> buildMergedDocumentsPdf(
    List<PdfDocumentData> alle) async {
  final doc = pw.Document();
  final dateFmt = DateFormat('d.M.yyyy', 'de');
  final druckDatum = DateFormat('dd.MM.yyyy').format(DateTime.now());
  final money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
  final theme = pw.ThemeData.withFont(
    base: await PdfGoogleFonts.interRegular(),
    bold: await PdfGoogleFonts.interBold(),
    italic: await PdfGoogleFonts.interMedium(),
  );
  for (final data in alle) {
    final totals = PositionsTotals.fromList(data.positionen);
    final logo = await _loadLogo(data.absender?.logoPfad);
    final istRechnung = data.dokumentTyp.startsWith('Rechnung') ||
        data.dokumentTyp == 'Rechnungskorrektur';
    final zeigeQr = data.mitSepaQr || istRechnung;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        // Fußzeile 1 cm tiefer als früher — Bottom-Margin auf 0.
        margin: pw.EdgeInsets.fromLTRB(
            _mm(18), _mm(10), _mm(18), 0),
        theme: theme,
        header: (ctx) => _pageHeader(data, logo, ctx, druckDatum),
        footer: (ctx) => _footer(data.absender),
        build: (ctx) => [
          pw.SizedBox(height: _mm(20)),
          _ersteSeiteKopf(data, dateFmt),
          pw.SizedBox(height: _mm(8)),
          pw.Text(
            data.dokumentTyp,
            style: pw.TextStyle(
                fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: _mm(6)),
          _introText(data),
          pw.SizedBox(height: _mm(6)),
          _positionenTabelle(data.positionen, money),
          pw.SizedBox(height: _mm(4)),
          _summenBlock(totals, money, data.dokumentTyp),
          if ((data.fusstext ?? '').isNotEmpty) ...[
            pw.SizedBox(height: _mm(6)),
            pw.Text(data.fusstext!,
                style: const pw.TextStyle(fontSize: 10)),
          ],
          if (data.skontoProzent != null && data.skontoTage != null)
            _skontoBlock(data, money, dateFmt),
          if (data.barzahlung) _barQuittungBlock(data, money),
          if (zeigeQr) _sepaQrBlock(data, money),
        ],
      ),
    );
  }
  return doc.save();
}

double _mm(double mm) => mm * PdfPageFormat.mm;

Future<pw.ImageProvider?> _loadLogo(String? pfad) async {
  if (pfad == null || pfad.trim().isEmpty) return null;
  try {
    Uint8List? bytes;
    String? mime;
    if (pfad.startsWith('data:')) {
      // data:image/<mime>;base64,<payload>
      final comma = pfad.indexOf(',');
      if (comma < 0) return null;
      final header = pfad.substring(0, comma);
      mime = RegExp(r'data:([^;]+)').firstMatch(header)?.group(1);
      bytes = base64Decode(pfad.substring(comma + 1));
    } else if (pfad.startsWith('assets/')) {
      final b = await rootBundle.load(pfad);
      bytes = b.buffer.asUint8List();
      if (pfad.endsWith('.svg')) mime = 'image/svg+xml';
    } else {
      // Lokale Datei-Pfade ignorieren wir — für Web nicht erreichbar.
      return null;
    }

    // SVG rastern — das pdf-Paket kann SVG nicht direkt als MemoryImage
    // darstellen. Ohne diesen Schritt erscheint kein Logo.
    final isSvg =
        mime == 'image/svg+xml' || _looksLikeSvg(bytes);
    if (isSvg) {
      final png = await _rasterSvgToPng(bytes);
      if (png == null) return null;
      bytes = png;
    }
    return pw.MemoryImage(bytes);
  } catch (_) {
    return null;
  }
}

bool _looksLikeSvg(Uint8List bytes) {
  if (bytes.length < 5) return false;
  final head = String.fromCharCodes(
      bytes.take(200).where((b) => b > 0 && b < 128));
  return head.contains('<svg') || head.trimLeft().startsWith('<?xml');
}

/// Rastert SVG-Bytes in ein PNG — damit das pdf-Paket sie als
/// [MemoryImage] rendern kann.
Future<Uint8List?> _rasterSvgToPng(Uint8List svgBytes,
    {int width = 800, int height = 300}) async {
  try {
    final info = await vg.loadPicture(SvgBytesLoader(svgBytes), null);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // transparenter Hintergrund, sonst wird das Logo mit weißem Rand
    // gerendert, was im Briefkopf störend ist.
    final size = info.size;
    final scaleX = width / (size.width == 0 ? 1 : size.width);
    final scaleY = height / (size.height == 0 ? 1 : size.height);
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final offX = (width - size.width * scale) / 2;
    final offY = (height - size.height * scale) / 2;
    canvas.translate(offX, offY);
    canvas.scale(scale);
    canvas.drawPicture(info.picture);
    info.picture.dispose();
    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final byteData =
        await img.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    img.dispose();
    return byteData?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// Seiten-Header, wird auf JEDER Seite gerendert.
///
/// Layout:
/// - Logo oben rechts (falls hinterlegt)
/// - Ab Seite 2: oben links ein Info-Block mit Auftragsnummer, Dokumenttyp,
///   Belegnummer + Druckdatum
pw.Widget _pageHeader(PdfDocumentData d, pw.ImageProvider? logo,
    pw.Context ctx, String druckDatum) {
  final isFirst = ctx.pageNumber == 1;
  return pw.Container(
    // Höhe inkl. 20 mm Logo-Top-Offset — sonst wird der Inhalt unter
    // dem Header verschoben.
    height: _mm(44),
    margin: pw.EdgeInsets.only(bottom: _mm(4)),
    child: pw.Stack(
      children: [
        if (!isFirst)
          pw.Positioned(
            left: 0,
            top: 0,
            child: _folgeseiteInfo(d, druckDatum),
          ),
        if (logo != null)
          pw.Positioned(
            // Logo 1 cm nach rechts (in die Seiten-Margin), 2 cm tiefer.
            right: -_mm(10),
            top: _mm(20),
            child: pw.ConstrainedBox(
              constraints:
                  pw.BoxConstraints(maxWidth: _mm(55), maxHeight: _mm(24)),
              child: pw.Image(logo, fit: pw.BoxFit.contain),
            ),
          ),
      ],
    ),
  );
}

/// Info-Block für Folgeseiten (ab Seite 2).
///
/// Layout:
///   Auftragsnummer: 2026-001
///   Dokumententyp: Rechnung
///   Belegnummer: R-2026-014    Datum: 19.04.2026
pw.Widget _folgeseiteInfo(PdfDocumentData d, String druckDatum) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      if ((d.aktenzeichen ?? '').isNotEmpty)
        _infoLine('Auftragsnummer', d.aktenzeichen!),
      _infoLine('Dokumententyp', d.dokumentTyp),
      pw.Row(
        children: [
          if ((d.dokumentNr ?? '').isNotEmpty) ...[
            _infoLine('Belegnummer', d.dokumentNr!),
            pw.SizedBox(width: _mm(6)),
          ],
          _infoLine('Datum', druckDatum),
        ],
      ),
    ],
  );
}

pw.Widget _infoLine(String label, String value) {
  return pw.RichText(
    text: pw.TextSpan(
      children: [
        pw.TextSpan(
          text: '$label: ',
          style: pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
              fontWeight: pw.FontWeight.bold),
        ),
        pw.TextSpan(
          text: value,
          style: pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey900,
              fontWeight: pw.FontWeight.normal),
        ),
      ],
    ),
  );
}

/// Erste-Seite-Kopfblock: Empfänger mit Absender-Mini +
/// Metadaten-Tabelle rechts. Nur auf Seite 1.
///
/// Durch den 40mm-Spacer vor diesem Block liegt der Adressblock bei
/// ~74mm vom Seitenoberrand — tief genug, dass er auch bei leicht
/// abweichenden Sichtfenstern sicher passt.
pw.Widget _ersteSeiteKopf(PdfDocumentData d, DateFormat dateFmt) {
  return pw.Container(
    height: _mm(55),
    child: pw.Stack(
      children: [
        pw.Positioned(
          left: 0,
          top: 0,
          child: pw.SizedBox(
            width: _mm(85),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _absenderMini(d.absender),
                pw.SizedBox(height: _mm(1)),
                if (d.empfaenger != null) _empfaengerBlock(d.empfaenger!),
              ],
            ),
          ),
        ),
        // Metadaten rechts — unterhalb des (jetzt 2cm tiefer sitzenden)
        // Logos, auf gleicher Höhe wie das Adressfeld.
        pw.Positioned(
          right: 0,
          top: 0,
          child: pw.SizedBox(
            width: _mm(75),
            child: _metaTabelle(d, dateFmt),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _absenderMini(BenutzerData? a) {
  if (a == null) return pw.SizedBox.shrink();
  final name = a.firma?.trim().isNotEmpty == true
      ? a.firma!.trim()
      : [a.vorname, a.nachname]
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .join(' ');
  final adresse = [
    a.strasse,
    [a.plz, a.ort].whereType<String>().where((s) => s.isNotEmpty).join(' '),
  ].where((s) => (s ?? '').trim().isNotEmpty).join(', ');
  final line = [name, adresse].where((s) => s.isNotEmpty).join(' · ');
  if (line.isEmpty) return pw.SizedBox.shrink();
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 2),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfColors.grey500, width: 0.3),
      ),
    ),
    child: pw.Text(line,
        style:
            const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
  );
}

pw.Widget _empfaengerBlock(KundenData k) {
  final name = [k.vorname, k.nachname]
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .join(' ')
      .trim();
  String anrede;
  if ((k.anrede ?? '').isNotEmpty && name.isNotEmpty) {
    anrede = '${k.anrede} $name';
  } else {
    anrede = name;
  }
  final ort =
      [k.plz, k.ort].whereType<String>().where((s) => s.isNotEmpty).join(' ');
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      if ((k.firma ?? '').trim().isNotEmpty)
        pw.Text(k.firma!, style: const pw.TextStyle(fontSize: 11)),
      if (anrede.isNotEmpty)
        pw.Text(anrede, style: const pw.TextStyle(fontSize: 11)),
      if ((k.strasse ?? '').trim().isNotEmpty)
        pw.Text(k.strasse!, style: const pw.TextStyle(fontSize: 11)),
      if (ort.isNotEmpty)
        pw.Text(ort, style: const pw.TextStyle(fontSize: 11)),
    ],
  );
}

pw.Widget _metaTabelle(PdfDocumentData d, DateFormat dateFmt) {
  final rows = <List<String>>[];
  final nummerLabel = d.nummerLabel ??
      switch (d.dokumentTyp) {
        'Angebot' => 'Angebots-Nr.',
        'Auftragsbestätigung' => 'AB-Nr.',
        'Gutschrift' => 'Gutschrift-Nr.',
        'Rechnungskorrektur' => 'Korrektur-Nr.',
        'Rechnung gemäß JVEG' || 'Rechnung' => 'Rechnungs-Nr.',
        _ => 'Nr.',
      };
  if ((d.dokumentNr ?? '').isNotEmpty) rows.add([nummerLabel, d.dokumentNr!]);
  if (d.datum != null) rows.add(['Datum', dateFmt.format(d.datum!)]);
  if (d.faelligBis != null) {
    final label = d.dokumentTyp.contains('Angebot') ||
            d.dokumentTyp.contains('Auftragsbestätigung')
        ? 'Gültig bis'
        : 'Fällig am';
    rows.add([label, dateFmt.format(d.faelligBis!)]);
  }
  if ((d.aktenzeichen ?? '').isNotEmpty) {
    rows.add(['Akte', d.aktenzeichen!]);
  }
  return pw.Column(
    children: [
      for (final r in rows)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(r[0],
                    style: const pw.TextStyle(fontSize: 10)),
              ),
              pw.Text(r[1],
                  style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: r[0].contains('Nr.')
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal)),
            ],
          ),
        ),
    ],
  );
}

bool _hatGerichtInfo(PdfDocumentData d) {
  return (d.gericht ?? '').trim().isNotEmpty ||
      (d.gerichtsAktenzeichen ?? '').trim().isNotEmpty ||
      (d.klaeger ?? '').trim().isNotEmpty ||
      (d.beklagter ?? '').trim().isNotEmpty;
}

/// Gerichts-Block: „In Sachen Kläger ./. Beklagter / AZ: … / Gericht: …"
pw.Widget _gerichtsblock(PdfDocumentData d) {
  final zeilen = <pw.TextSpan>[];
  final kl = (d.klaeger ?? '').trim();
  final be = (d.beklagter ?? '').trim();
  if (kl.isNotEmpty || be.isNotEmpty) {
    zeilen.add(pw.TextSpan(
      text: 'In Sachen: ',
      style: pw.TextStyle(
          fontSize: 11, fontWeight: pw.FontWeight.bold),
    ));
    zeilen.add(pw.TextSpan(
      text:
          '${kl.isEmpty ? '—' : kl} ./. ${be.isEmpty ? '—' : be}\n',
      style: const pw.TextStyle(fontSize: 11),
    ));
  }
  final g = (d.gericht ?? '').trim();
  final az = (d.gerichtsAktenzeichen ?? '').trim();
  if (g.isNotEmpty || az.isNotEmpty) {
    zeilen.add(pw.TextSpan(
      text: 'Gericht: ',
      style: pw.TextStyle(
          fontSize: 11, fontWeight: pw.FontWeight.bold),
    ));
    final gText = [g, az.isEmpty ? '' : 'Az. $az']
        .where((s) => s.isNotEmpty)
        .join(' · ');
    zeilen.add(pw.TextSpan(
      text: gText,
      style: const pw.TextStyle(fontSize: 11),
    ));
  }
  return pw.RichText(text: pw.TextSpan(children: zeilen));
}

pw.Widget _introText(PdfDocumentData d) {
  final einleitung = d.kopftext?.trim().isNotEmpty == true
      ? d.kopftext!
      : _defaultEinleitung(d.dokumentTyp);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('Sehr geehrte Damen und Herren,',
          style: const pw.TextStyle(fontSize: 11)),
      pw.SizedBox(height: _mm(3)),
      pw.Text(einleitung, style: const pw.TextStyle(fontSize: 11)),
      if ((d.sachverhalt ?? d.betreff ?? '').trim().isNotEmpty) ...[
        pw.SizedBox(height: _mm(4)),
        pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: 'Sachverhalt: ',
                style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
              pw.TextSpan(
                text: (d.sachverhalt ?? d.betreff)!.trim(),
                style: const pw.TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ],
      if (_hatGerichtInfo(d)) ...[
        pw.SizedBox(height: _mm(3)),
        _gerichtsblock(d),
      ],
      if ((d.objektAdresse ?? '').trim().isNotEmpty) ...[
        pw.SizedBox(height: _mm(2)),
        pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: 'Objekt: ',
                style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
              pw.TextSpan(
                text: d.objektAdresse!.trim(),
                style: const pw.TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}

String _defaultEinleitung(String typ) {
  if (typ == 'Auftragsbestätigung') {
    return 'vielen Dank für den mir erteilten Auftrag, dessen Ausführung ich hiermit '
        'wie folgt bestätige:';
  }
  if (typ == 'Gutschrift' || typ == 'Rechnungskorrektur') {
    return 'bezugnehmend auf die oben genannte Original-Rechnung erhalten Sie '
        'hiermit die korrigierten Leistungen:';
  }
  if (typ.startsWith('Rechnung')) {
    return 'für die erbrachten sachverständigen Leistungen stelle ich Ihnen '
        'folgenden Betrag in Rechnung:';
  }
  // Angebot
  return 'vielen Dank für Ihre Anfrage. Ich biete Ihnen die nachfolgenden '
      'sachverständigen Leistungen wie folgt an:';
}

pw.Widget _positionenTabelle(List<Position> items, NumberFormat money) {
  if (items.isEmpty) {
    return pw.Text('Keine Positionen.',
        style: const pw.TextStyle(fontSize: 10));
  }
  final headers = ['Pos.', 'Bezeichnung', 'Menge', 'Einh.', 'EP €', 'Betrag €'];
  // Spalten-Breiten wie im Original (8/44/10/10/14/14).
  final colWidths = {
    0: const pw.FlexColumnWidth(8),
    1: const pw.FlexColumnWidth(44),
    2: const pw.FlexColumnWidth(10),
    3: const pw.FlexColumnWidth(10),
    4: const pw.FlexColumnWidth(14),
    5: const pw.FlexColumnWidth(14),
  };
  return pw.Table(
    columnWidths: colWidths,
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.4),
      top: pw.BorderSide(color: PdfColors.grey400, width: 0.6),
      bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.6),
    ),
    children: [
      // Kopfzeile
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey100),
        children: [
          for (var i = 0; i < headers.length; i++)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 4, vertical: 6),
              child: pw.Text(
                headers[i],
                textAlign: (i >= 2) ? pw.TextAlign.right : pw.TextAlign.left,
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
            ),
        ],
      ),
      for (var i = 0; i < items.length; i++) _posRow(i, items[i], money),
    ],
  );
}

pw.TableRow _posRow(int idx, Position p, NumberFormat money) {
  final kurz = p.bezeichnung;
  final langtext = p.langtext.trim();
  final posNr = p.posNr.isNotEmpty ? p.posNr : '${idx + 1}';
  final betragText = money.format(p.nettoBetrag);
  final einzelText = money.format(p.einzelpreis);
  return pw.TableRow(
    children: [
      _cell(p.optional ? '($posNr)' : posNr, alignRight: false),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                if (p.optional)
                  pw.Container(
                    margin: const pw.EdgeInsets.only(right: 4),
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.amber100,
                      borderRadius: pw.BorderRadius.circular(2),
                    ),
                    child: pw.Text('Optional',
                        style: pw.TextStyle(
                            fontSize: 7,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.amber900)),
                  ),
                pw.Expanded(
                  child: pw.Text(kurz,
                      style: const pw.TextStyle(fontSize: 10)),
                ),
              ],
            ),
            if (langtext.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text(
                langtext,
                style: pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ],
        ),
      ),
      _cell(_fmtMenge(p.menge), alignRight: true),
      _cell(p.einheit, alignRight: true),
      _cell(p.optional ? '($einzelText)' : einzelText, alignRight: true),
      _cell(p.optional ? '($betragText)' : betragText, alignRight: true),
    ],
  );
}

pw.Widget _cell(String text, {required bool alignRight}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    child: pw.Text(
      text,
      style: const pw.TextStyle(fontSize: 10),
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
    ),
  );
}

String _fmtMenge(double m) {
  final fmt = NumberFormat('#,##0.00', 'de');
  return fmt.format(m);
}

pw.Widget _summenBlock(PositionsTotals t, NumberFormat money, String typ) {
  String gesamtLabel;
  if (typ == 'Angebot' || typ == 'Auftragsbestätigung') {
    gesamtLabel = 'Angebotssumme';
  } else if (typ == 'Gutschrift') {
    gesamtLabel = 'Gutschrift-Betrag';
  } else {
    gesamtLabel = 'Rechnungsbetrag';
  }
  return pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.Container(
      width: _mm(90),
      child: pw.Column(
        children: [
          _summenZeile('Zwischensumme (netto)', money.format(t.netto)),
          if (t.ust > 0)
            _summenZeile(
              'zzgl. ${_fmtMenge(t.netto > 0 ? (t.ust / t.netto * 100) : 19).replaceAll(',00', '')}\u00a0% USt.',
              money.format(t.ust),
            ),
          pw.SizedBox(height: 2),
          pw.Container(
            padding: const pw.EdgeInsets.only(top: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: PdfColors.black, width: 0.6),
              ),
            ),
            child: _summenZeile(gesamtLabel, money.format(t.brutto),
                bold: true),
          ),
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

/// Skonto-Block auf der Rechnung: hellgraue Box mit Prozentsatz,
/// Stichtag und dem errechneten Zahlbetrag nach Skontoabzug.
pw.Widget _skontoBlock(
    PdfDocumentData d, NumberFormat money, DateFormat dateFmt) {
  final prozent = d.skontoProzent;
  final tage = d.skontoTage;
  if (prozent == null || tage == null) return pw.SizedBox.shrink();
  final brutto = d.brutto ?? 0;
  final abzug = brutto * (prozent / 100);
  final zuZahlen = brutto - abzug;
  final start = d.datum ?? DateTime.now();
  final bis = start.add(Duration(days: tage));
  return pw.Container(
    margin: pw.EdgeInsets.only(top: _mm(8)),
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey100,
      borderRadius:
          const pw.BorderRadius.all(pw.Radius.circular(4)),
      border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Skonto-Angebot',
            style: pw.TextStyle(
                fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(
          'Bei Zahlung bis zum ${dateFmt.format(bis)} '
          '(innerhalb von $tage Tagen) gewähren wir '
          '${prozent.toStringAsFixed(1).replaceAll('.', ',')} % Skonto.',
          style: const pw.TextStyle(fontSize: 10),
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                'Rechnungsbetrag: ${money.format(brutto)}',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                'Skonto ${prozent.toStringAsFixed(1).replaceAll('.', ',')} %: '
                '− ${money.format(abzug)}',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                'Zu zahlen: ${money.format(zuZahlen)}',
                style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey900),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Bar-Quittungsblock mit Linien für Datum und Unterschrift.
pw.Widget _barQuittungBlock(PdfDocumentData d, NumberFormat money) {
  final brutto = d.brutto ?? 0;
  return pw.Container(
    margin: pw.EdgeInsets.only(top: _mm(8)),
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: PdfColors.amber50,
      borderRadius:
          const pw.BorderRadius.all(pw.Radius.circular(4)),
      border: pw.Border.all(color: PdfColors.amber200, width: 0.5),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Barzahlung — Quittung',
          style: pw.TextStyle(
              fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Betrag in Höhe von ${money.format(brutto)} in bar erhalten.',
          style: const pw.TextStyle(fontSize: 10),
        ),
        pw.SizedBox(height: 14),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    height: 0.6,
                    color: PdfColors.grey600,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text('Datum',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey700)),
                ],
              ),
            ),
            pw.SizedBox(width: 20),
            pw.Expanded(
              flex: 2,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    height: 0.6,
                    color: PdfColors.grey600,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text('Unterschrift Empfänger',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey700)),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _sepaQrBlock(PdfDocumentData d, NumberFormat money) {
  final a = d.absender;
  final iban = (a?.iban ?? '').replaceAll(' ', '');
  if (iban.isEmpty || (d.brutto ?? 0) <= 0) return pw.SizedBox.shrink();
  final empfaenger = a?.firma?.trim().isNotEmpty == true
      ? a!.firma!.trim()
      : [a?.vorname, a?.nachname].whereType<String>().join(' ').trim();
  final bic = (a?.bic ?? '').trim();
  final verwendungszweck = d.dokumentNr == null
      ? d.dokumentTyp
      : '${d.dokumentTyp} ${d.dokumentNr}';
  final data = [
    'BCD',
    '002',
    '1',
    'SCT',
    bic,
    empfaenger,
    iban,
    'EUR${d.brutto!.toStringAsFixed(2)}',
    '',
    d.dokumentNr ?? '',
    verwendungszweck,
  ].join('\n');
  return pw.Padding(
    padding: pw.EdgeInsets.only(top: _mm(8)),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 90,
          height: 90,
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: data,
            drawText: false,
          ),
        ),
        pw.SizedBox(width: 14),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Bequem per SEPA-QR / GiroCode zahlen',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Empfänger: $empfaenger',
                  style: const pw.TextStyle(fontSize: 9)),
              pw.Text('IBAN: ${_formatIban(iban)}',
                  style: const pw.TextStyle(fontSize: 9)),
              if (bic.isNotEmpty)
                pw.Text('BIC: $bic',
                    style: const pw.TextStyle(fontSize: 9)),
              pw.Text('Betrag: ${money.format(d.brutto)}',
                  style: const pw.TextStyle(fontSize: 9)),
              pw.Text('Verwendungszweck: $verwendungszweck',
                  style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
      ],
    ),
  );
}

String _formatIban(String iban) {
  final buf = StringBuffer();
  for (var i = 0; i < iban.length; i += 4) {
    buf.write(iban.substring(i, i + 4 > iban.length ? iban.length : i + 4));
    if (i + 4 < iban.length) buf.write(' ');
  }
  return buf.toString();
}

/// Fußzeile mit 4 Spalten, wie in der SV-Software-Vorlage.
///
/// Spalte 1: Titel · Name (bold) · Bestellungstext 1
/// Spalte 2: Bestellungstext 2 · USt-IdNr. · Steuer-Nr.
/// Spalte 3: Anschrift · Tel · E-Mail · Website
/// Spalte 4: Kontoinhaber · Bank · IBAN · BIC
///
/// Dünner Strich (0.4pt) als Trennung oben, 3mm Abstand zum Text,
/// Schrift 7.5pt grau.
pw.Widget _footer(BenutzerData? a) {
  if (a == null) return pw.SizedBox.shrink();
  final name = [a.vorname, a.nachname]
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .join(' ');
  // Bestellungstext aus Einstellungen — wird in absenderFromSettings
  // aus firmaBestellung1 + firmaBestellung2 zu einem String zusammengebaut
  // ("\n\n" als Trenner).
  final bestellung = (a.bestellungsText ?? '').trim();
  final bestellParts = bestellung.split(RegExp(r'\n\s*\n'));
  final bestellung1 = bestellParts.isNotEmpty ? bestellParts[0] : '';
  final bestellung2 = bestellParts.length > 1 ? bestellParts[1] : '';

  final col1Lines = <String>[
    if ((a.titel ?? '').isNotEmpty) a.titel!,
    if (name.isNotEmpty) name, // bold im rendering
    if (bestellung1.isNotEmpty) bestellung1,
  ];
  final col2Lines = <String>[
    if (bestellung2.isNotEmpty) bestellung2,
    if ((a.ustId ?? '').isNotEmpty) 'USt-IdNr.: ${a.ustId}',
    if ((a.steuerNr ?? '').isNotEmpty) 'Steuer-Nr.: ${a.steuerNr}',
  ];
  final col3Lines = <String>[
    if ((a.strasse ?? '').isNotEmpty) a.strasse!,
    if (((a.plz ?? '').isNotEmpty) || ((a.ort ?? '').isNotEmpty))
      '${a.plz ?? ''} ${a.ort ?? ''}'.trim(),
    if ((a.telefon ?? '').isNotEmpty) 'Tel: ${a.telefon}',
    if ((a.mobil ?? '').isNotEmpty) 'Mobil: ${a.mobil}',
    if ((a.email ?? '').isNotEmpty) a.email!,
    if ((a.website ?? '').isNotEmpty) a.website!,
  ];
  final col4Lines = <String>[
    if ((a.bank ?? '').isNotEmpty) a.bank!,
    if ((a.iban ?? '').isNotEmpty) 'IBAN: ${a.iban}',
    if ((a.bic ?? '').isNotEmpty) 'BIC: ${a.bic}',
  ];

  pw.Widget col(List<String> lines, {int boldLineIndex = -1}) =>
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lines.length; i++)
              pw.Text(
                lines[i],
                style: pw.TextStyle(
                  fontSize: 7.5,
                  color: PdfColors.grey600,
                  fontWeight: i == boldLineIndex
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                  height: 1.35,
                ),
              ),
          ],
        ),
      );

  return pw.Container(
    padding: pw.EdgeInsets.only(top: _mm(3)),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(color: PdfColors.grey500, width: 0.4),
      ),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Spalte 1: Titel / Name (bold) / Bestellungstext 1
        col(col1Lines, boldLineIndex: col1Lines.indexOf(name)),
        pw.SizedBox(width: _mm(2)),
        col(col2Lines),
        pw.SizedBox(width: _mm(2)),
        col(col3Lines),
        pw.SizedBox(width: _mm(2)),
        col(col4Lines),
      ],
    ),
  );
}
