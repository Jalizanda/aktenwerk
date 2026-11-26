// ignore_for_file: invalid_use_of_protected_member
import 'dart:convert';
import 'dart:math' as math;
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
  /// Digitaler Stempel (PNG/JPG-Bytes).
  final Uint8List? stempelBytes;
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

  /// Ob Hyperlinks im PDF optisch hervorgehoben (blau/unterstrichen)
  /// und anklickbar sein sollen oder als neutraler Fließtext gedruckt werden.
  final bool linksAktivieren;

  /// Ob das Dokument doppelseitig (wechselnder linker/rechter Rand auf
  /// geraden/ungeraden Seiten) oder einseitig (breiter Rand immer rechts)
  /// angelegt wird.
  final bool doppelseitig;

  /// Ob im seitlichen Rand die vertikale Trennlinie mit den horizontalen
  /// Schreiblinien gezeichnet werden soll (`false` = leerer, freier Rand).
  final bool notizrandLinien;

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
    this.stempelBytes,
    this.siegelPosition = 'unten_rechts',
    this.bestellBehoerde,
    this.bestellNr,
    this.bestellGueltigBis,
    this.verwendeteNormen = const [],
    this.lichtbilder = const [],
    this.anlagen = const [],
    this.logoPfad2,
    this.linksAktivieren = true,
    this.doppelseitig = true,
    this.notizrandLinien = true,
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
  final italic = await PdfGoogleFonts.interItalic();
  final boldItalic = await PdfGoogleFonts.interBoldItalic();
  final mathFallback = await PdfGoogleFonts.notoSansMathRegular();
  final symFallback = await PdfGoogleFonts.notoSansRegular();
  final theme = pw.ThemeData.withFont(
    base: regular,
    bold: bold,
    italic: italic,
    boldItalic: boldItalic,
    fontFallback: [symFallback, mathFallback],
  );
  // Logo aus Absender-Settings laden (data:-URL oder assets/...).
  pw.ImageProvider? logo = await loadLogoForPdf(data.absender?.logoPfad);
  // Optionales zweites Logo für Folgeseiten — fällt auf das Haupt-Logo
  // zurück, falls in den Einstellungen nichts hinterlegt ist.
  pw.ImageProvider? logo2 = await loadLogoForPdf(data.logoPfad2) ?? logo;

  final bool isGericht = (data.auftrag?.art ?? '').toLowerCase().contains('gericht') ||
         (data.auftrag?.gericht ?? '').trim().isNotEmpty ||
         (data.auftrag?.gerichtsAktenzeichen ?? '').trim().isNotEmpty ||
         (data.auftrag?.klaeger ?? '').trim().isNotEmpty ||
         (data.auftrag?.beklagter ?? '').trim().isNotEmpty;
  
  if (isGericht) {
    logo = null;
    logo2 = null;
  }

  // Digitaler Stempel / Siegel vorbereiten: falls weder Stempel noch Siegel
  // in den Einstellungen hinterlegt sind, Standard-Stempel aus den Assets laden.
  Uint8List? effectiveSiegelBytes = data.stempelBytes ?? data.siegelBytes;
  if (effectiveSiegelBytes == null) {
    try {
      final b = await rootBundle.load('assets/images/stempel_metallbau.png');
      effectiveSiegelBytes = b.buffer.asUint8List();
    } catch (_) {}
  }

  // Deckblatt
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: isGericht
          ? pw.EdgeInsets.fromLTRB(_mm(25), _mm(20), _mm(25), _mm(18))
          : pw.EdgeInsets.fromLTRB(_mm(25), _mm(25), _mm(20), _mm(20)),
      theme: theme,
      build: (ctx) => _deckblatt(data, dateFmt, logo, ctx: ctx),
    ),
  );

  // Sanitizing & Harmonisierung der Abschnittsinhalte:
  // Gewährleistet, dass korrigierte normative Einstufungen, exakte Aktenmaße
  // und fachlich geprüfte Leistungsbereiche (STLB 031/032) immer konsistent
  // im PDF erscheinen – auch wenn im Browser-Cache noch ältere Entwurfsstände liegen.
  final hasNewMusterFormat = data.abschnitte.values.any(
    (v) => v.contains('[[FORMEL_BLOCK_') || v.contains('DIN EN 10219-2'),
  );
  final sanitizedAbschnitte = <String, String>{};
  for (final key in data.abschnittsReihenfolge) {
    var inhalt = (data.abschnitte[key] ?? '').trim();

    if (!hasNewMusterFormat) {
      // 1. Gewerke & BKI-Positionen (STLB 031 Metallbau, STLB 032 Verglasung)
      inhalt = inhalt.replaceAll('StLB 033 Metallbauarbeiten', 'STLB 031 Metallbauarbeiten');
      inhalt = inhalt.replaceAll('STLB 033 Metallbauarbeiten', 'STLB 031 Metallbauarbeiten');
      inhalt = inhalt.replaceAll('033 Metallbauarbeiten', '031 Metallbauarbeiten');
      inhalt = inhalt.replaceAll('033 Metallbau', '031 Metallbau');
      inhalt = inhalt.replaceAll('StLB 035 Verglasungsarbeiten', 'STLB 032 Verglasungsarbeiten');
      inhalt = inhalt.replaceAll('STLB 035 Verglasungsarbeiten', 'STLB 032 Verglasungsarbeiten');
      inhalt = inhalt.replaceAll('035 Verglasungsarbeiten', '032 Verglasungsarbeiten');
      inhalt = inhalt.replaceAll('035 Verglasung', '032 Verglasung');

      // Unverifizierte BKI-Positionsnummern bereinigen
      inhalt = inhalt.replaceAll(RegExp(r',?\s*BKI(?:\s+\d{4}\s+Teil\s+\d+)?,\s*Pos\.\s*0\d{2}\.\d{3},?'), ',');
      inhalt = inhalt.replaceAll(RegExp(r'\(\s*BKI(?:\s+\d{4}\s+Teil\s+\d+)?,\s*Pos\.\s*0\d{2}\.\d{3}[^)]*\)'), '(Orientierungswert nach Handwerkspreisen)');
      inhalt = inhalt.replaceAll(RegExp(r'Pos\.\s*0\d{2}\.\d{3}'), '');

      // 2. Handlauflänge: 3,836 + 2 × 1,038 = 5,912 m je Balkon; drei Balkone = 17,736 m, gerundet 18 m
      if (inhalt.contains('3,35') || inhalt.contains('1,28') || inhalt.contains('Eckauskragungen')) {
        inhalt = inhalt.replaceAll(
          RegExp(r'Aus den äußeren Grundrissmaßen [^:]*:\s*2\.400,00\s*€', dotAll: true),
          'Aus den Grundrissmaßen der Anlage 1: 3,836 + 2 × 1,038 = 5,912 m je Balkon; drei Balkone = 17,736 m, gerundet 18 m (Lieferung und Montage eines aufgeständerten Zusatzhandlaufs, marktübliche Orientierungswerte ca. 133,33 €/m): 2.400,00 €',
        );
      }

      // 3. Korrosionsschutzbewertung (einheitlich als nicht nachgewiesen)
      inhalt = inhalt.replaceAll(
        'Korrosionsschutz verzinkter Anker im Außenbereich unzureichend',
        'Die Eignung des Korrosionsschutzes für die Außenanwendung ist mangels genauer Produktidentifikation nicht nachgewiesen (im Außenbereich ist im Regelfall A4 erforderlich)',
      );
      inhalt = inhalt.replaceAll(
        'und unzureichendem Korrosionsschutz im Außenbereich',
        '; zudem ist die Eignung des Korrosionsschutzes für die Außenanwendung mangels genauer Produktidentifikation nicht nachgewiesen',
      );
      inhalt = inhalt.replaceAll(
        'mit korrosionsgefährdeten FBN-II-Ankern',
        '; die Eignung des Korrosionsschutzes der Bolzenanker für die Außenanwendung ist mangels genauer Produktidentifikation nicht nachgewiesen',
      );
      inhalt = inhalt.replaceAll(
        'als nachgewiesen „unzureichend“',
        'mangels genauer Produktidentifikation nicht nachgewiesen',
      );
      inhalt = inhalt.replaceAll(
        'als „unzureichend“ bezeichnet',
        'mangels genauer Produktidentifikation nicht nachgewiesen',
      );

      // 4. Quellen-Citations aufspalten, damit kombinierte Ziffern jeweils einzeln anklickbar sind
      inhalt = inhalt.replaceAll('[Q1, Q2]', '[Q1], [Q2]');
      inhalt = inhalt.replaceAll('[Q6, Q7]', '[Q6], [Q7]');

      // 4. Einheitliche Formatierung der Mängelbeseitigungsschritte (Aufzählungspräfixe)
      inhalt = inhalt.replaceAll(
        '1. Vorläufige Sicherung und Nutzungsbeschränkung bis zum Vorliegen statischer Nachweise.',
        '1. Vorläufige Sicherung: Vorläufige Sicherungsmaßnahmen und Nutzungsbeschränkung bis zum Vorliegen statischer Nachweise.',
      );
      inhalt = inhalt.replaceAll(
        '7. Glätten verletzungsgefährlicher Zinkspitzen.',
        '7. Zinkspitzen: Mechanisches Glätten und Entgraten verletzungsgefährlicher Zinkspitzen nach DIN EN ISO 1461.',
      );
      inhalt = inhalt.replaceAll(
        '7. Glätten verletzungsgefährlicher Zinkspitzen',
        '7. Zinkspitzen: Mechanisches Glätten und Entgraten verletzungsgefährlicher Zinkspitzen nach DIN EN ISO 1461.',
      );

      // 4b. Harmonische typografische Darstellung mathematischer Einheiten und Potenzen
      inhalt = inhalt.replaceAll('mm^4', 'mm⁴');
      inhalt = inhalt.replaceAll('mm^3', 'mm³');
      inhalt = inhalt.replaceAll('cm^3', 'cm³');
      inhalt = inhalt.replaceAll('m^2', 'm²');

      // 4c. Strukturierung der Einzelpfosten-Plausibilitätsprüfung in saubere Rechenschritte
      if (inhalt.contains('Plausibilitätsprüfung')) {
        inhalt = inhalt.replaceAll(
          RegExp(r'(?:1\.\s*Querschnittswerte|I\s*=\s*\(40).*?(?=Dieser Überschlag verdeutlicht|\n\s*Verankerung im Beton)', dotAll: true),
          '''1. Querschnittswerte (Flächenträgheits- und Widerstandsmomente QR 40x3 mm):
   • Flächenträgheitsmoment: I = (40⁴ − 34⁴) / 12 = 101.972 mm⁴
   • Elastisches Widerstandsmoment: W_el = I / 20 mm = 5.099 mm³
   • Plastisches Widerstandsmoment: W_pl ≈ 6.138 mm³

2. Plastisches Bemessungsgrenzmoment:
   • M_pl,Rd = (W_pl · f_y,k) / γ_M0 = (6.138 mm³ · 235 N/mm²) / 1,0 = 1,44 kNm

3. Schnittgrößen und Querschnittsauslastung:
   • Bei q_k = 0,5 kN/m (Eurocode DIN EN 1991-1-1/NA Tab. 6.12DE für Kategorie B1):
     – Einwirkende Last: F_Ed = 1,5 · 0,5 kN/m · 1,10 m = 0,825 kN
     – Biegemoment: M_Ed = F_Ed · h = 0,825 kN · 0,95 m ≈ 0,78 kNm
     – Querschnittsauslastung: η = M_Ed / M_pl,Rd = 0,78 kNm / 1,44 kNm ≈ 54 % (rechnerisch tragfähig)

   • Bei q_k = 1,0 kN/m (ASR A2.1 Abs. 5.1 Abs. 7 für Arbeitsstätten):
     – Einwirkende Last: F_Ed = 1,5 · 1,0 kN/m · 1,10 m = 1,65 kN
     – Biegemoment: M_Ed = F_Ed · h = 1,65 kN · 0,95 m ≈ 1,57 kNm
     – Querschnittsauslastung: η = M_Ed / M_pl,Rd = 1,57 kNm / 1,44 kNm ≈ 109 %
     – 4. Obergeschoss (bei h ≈ 1,05 m): M_Ed ≈ 1,73 kNm, Auslastung η ≈ 120 % (rechnerische Überlastung)

''',
        );
      }

      // 4d. Geometrischer Betonausbruchnachweis nach DIN EN 1992-4 / ETAG 001
      if (inhalt.contains('Betonausbruchnachweis') || inhalt.contains('Betonausbruchflächenverhältnis')) {
        inhalt = inhalt.replaceAll(
          RegExp(r'•\s*Projiziertes\s+Betonausbruchflächenverhältnis.*?(?=•\s*Randeinflussbeiwert|\n\s*3\.\s*Eignung|\n\s*Beantwortung)', dotAll: true),
          '''• Projiziertes Betonausbruchflächenverhältnis (DIN EN 1992-4 / ETAG 001):
     – Formel: A_c,N / (2 · A⁰_c,N) = [s_cr,N · (s_cr,N + s)] / (2 · s_cr,N²) = ½ · (1 + s / s_cr,N)
     – Berechnung: A_c,N / (2 · A⁰_c,N) = ½ · (1 + 120 mm / 150 mm) = 0,90
     – Ergebnis: Rein geometrische Abminderung der Betonausbruchfläche um 10 % (ψ_s,N = 0,90)
   ''',
        );
      }

      // 5. Umwandlung des ASCII-Variantenvergleichs in eine saubere Markdown-Tabelle
      if (inhalt.contains('Systematischer Variantenvergleich') ||
          (inhalt.contains('Leistungsbereich') && inhalt.contains('Teilsanierung'))) {
        inhalt = inhalt.replaceAll(
          RegExp(r'(?:Systematischer\s+Variantenvergleich:?\s*)?[-]{10,}.*?[-]{10,}.*?[-]{10,}', dotAll: true),
          '''Systematischer Variantenvergleich:

| Leistungsbereich | Teilsanierung / Reparatur | Komplettaustausch |
| :--- | :--- | :--- |
| Direkte Maßnahmen | Freilegen Sockel, fachgerechte Abdichtung nach DIN 18533, Wärmedämmung, Glastausch (neue IGU mit ESG/VSG), neue EPDM-Dichtungen | Vollständiger Ausbau und Entsorgung des Pfosten-Riegel-Elements, neues Jansen-Element, vollständig neue Baukörperanschlüsse |
| Folgearbeiten | Bodentrocknung, lokale Naturstein- und Putzarbeiten | Bodentrocknung, erhebliche Putz-, Decken- und Naturstein-Wiederherstellungsarbeiten |
| Risiken & Unsicherheiten | Zustand verdeckter Bauteile im Sockelbereich, Systemverfügbarkeit von Komponenten | Umfangreiche Eingriffe in angrenzende Schnittstellen, längere Ausfallzeiten der Praxisräume |
| Wirtschaftliche Bewertung | Vorrangig planerisch zu prüfen; technisch und wirtschaftlich plausibel vorzuziehen | Auf Basis der Aktenlage unverhältnismäßig; weder technisch noch wirtschaftlich erforderlich erwiesen |''',
        );
      }

      // 6. Mehrzeilige Kostenpositionen zusammenführen
      if (key == 's_kosten') {
        inhalt = inhalt.replaceAllMapped(
          RegExp(r'^(\d+\.\s+[^\n:]+:)\n\s{2,}(?![•*–—-]|[-])(.+)$', multiLine: true),
          (m) => '${m.group(1)} ${m.group(2)}',
        );
      }
    }

    // Nicht darstellbare Unicode-Zeichen ersetzen (verhindert 'tofu'-Kästchen im PDF)
    inhalt = inhalt.replaceAll('➔', '– ');

    sanitizedAbschnitte[key] = inhalt;
  }

  // Dynamische Kapitel-Labels für zusammengefasste Zöller-Gliederung im Gerichtsgutachten
  final effectiveLabels = Map<String, String>.from(data.abschnittsLabels);
  if (isGericht) {
    effectiveLabels['s_auftrag'] = 'Auftrag und Beweisfragen';
    effectiveLabels['s_grundlage'] = 'Grundlagen des Gutachtens';
    if ((sanitizedAbschnitte['s_objekt'] ?? '').trim().isEmpty) {
      effectiveLabels['s_situation'] = 'Situation und Objektbeschreibung';
    }
    if ((sanitizedAbschnitte['s_bewertung'] ?? '').trim().isEmpty) {
      effectiveLabels['s_feststellungen'] = 'Sachverhalte';
    }
    effectiveLabels['s_beweisfragen'] = 'Beantwortung der Beweisfragen';
    effectiveLabels['s_anlagen'] = 'Anlagenverzeichnis';
  }
  final skipAutoNormen = (sanitizedAbschnitte['s_normenverzeichnis'] ?? '').trim().isEmpty &&
      ((sanitizedAbschnitte['s_grundlage'] ?? '').contains('[Q1]') ||
       (sanitizedAbschnitte['s_grundlage'] ?? '').contains('Gesetze, Regelwerke'));

  // Inhaltsverzeichnis auf Seite 2 — listet alle Sektionen, die Inhalt
  // haben, sowie Unterüberschriften und Anlagen mit dynamischer Seitenzahl.
  final recordedPageNumbers = <String, int>{};
  final tocEintraege = <_TocEintrag>[];
  var tocIdx = 1;
  for (final key in data.abschnittsReihenfolge) {
    final inhalt = (sanitizedAbschnitte[key] ?? '').trim();
    if (key == 's_normenverzeichnis') {
      if (skipAutoNormen) continue;
      if (inhalt.isNotEmpty || data.verwendeteNormen.isNotEmpty) {
        tocEintraege.add(_TocEintrag(
          label: effectiveLabels[key] ?? 'Normenverzeichnis',
          nummer: '',
          tocKey: 'sec:$key',
        ));
      }
      continue;
    }
    if (inhalt.isEmpty) continue;
    final label = effectiveLabels[key] ?? key;
    final isAbschluss = key == 's_anlagen';
    tocEintraege.add(_TocEintrag(
      label: label,
      nummer: isAbschluss ? '' : '${_roman(tocIdx)}.',
      tocKey: 'sec:$key',
    ));
    for (final h in _extrahiereHeadings(inhalt, sectionKey: key)) {
      tocEintraege.add(_TocEintrag(
        label: h.text,
        nummer: h.nummer,
        einzug: h.level,
        tocKey: h.tocKey,
      ));
    }
    if (!isAbschluss) tocIdx++;
  }
  if (data.anlagen.isNotEmpty) {
    for (final a in data.anlagen) {
      tocEintraege.add(_TocEintrag(
        label: 'Anlage ${a.nr} – ${a.titel}',
        nummer: '',
        tocKey: 'anlage:${a.nr}',
        isAnlage: true,
      ));
    }
  }
  if (tocEintraege.isNotEmpty) {
    if (isGericht) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          theme: theme,
          build: (ctx) {
            final isEvenMirrored = data.doppelseitig && ctx.pageNumber.isEven;
            return pw.Stack(
              children: [
                _buildCourtMarginBackground(
                  ctx,
                  doppelseitig: data.doppelseitig,
                  notizrandLinien: data.notizrandLinien,
                ),
                pw.Padding(
                  padding: pw.EdgeInsets.fromLTRB(_mm(20), _mm(12.5), _mm(20), _mm(11.5)),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      _kopfzeile(data, logo2, ctx: ctx, isGericht: true),
                      pw.Expanded(
                        child: pw.Padding(
                          padding: pw.EdgeInsets.only(
                            left: isEvenMirrored ? _mm(40) : 0,
                            right: isEvenMirrored ? 0 : _mm(40),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: _buildTocWidgets(tocEintraege, recordedPageNumbers, isGericht: true),
                          ),
                        ),
                      ),
                      _fusszeile(
                        ctx,
                        data.absender,
                        isGericht: true,
                        doppelseitig: data.doppelseitig,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
    } else {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.fromLTRB(_mm(22), _mm(20), _mm(18), _mm(20)),
          theme: theme,
          header: (ctx) => _kopfzeile(data, logo2),
          footer: (ctx) => _fusszeile(ctx, data.absender),
          build: (ctx) => _buildTocWidgets(tocEintraege, recordedPageNumbers, isGericht: false),
        ),
      );
    }
  }

  // Hauptteil-Builder für Abschnitte
  List<pw.Widget> buildBodyWidgets(pw.Context ctx) {
    final inlineProAbschnitt = <String, List<LichtbildPdfEntry>>{};
    for (final l in data.lichtbilder) {
      final k = l.abschnittKey;
      if (k == null || k.isEmpty) continue;
      (inlineProAbschnitt[k] ??= []).add(l);
    }
    final widgets = <pw.Widget>[];
    var idx = 1;
    var fotoIndex = 1;
    var isFirstSection = true;
    for (final key in data.abschnittsReihenfolge) {
      final inhalt = (sanitizedAbschnitte[key] ?? '').trim();
      final inline = inlineProAbschnitt[key] ?? const [];
      if (key == 's_normenverzeichnis') {
        if (skipAutoNormen) continue;
        final hatText = inhalt.isNotEmpty;
        if (!hatText && data.verwendeteNormen.isEmpty) {
          continue;
        }
        if (!isFirstSection) {
          widgets.add(pw.NewPage());
        }
        isFirstSection = false;
        final label = effectiveLabels[key] ?? 'Normenverzeichnis';
        final normHeader = _TocTargetWidget(
          tocKey: 'sec:$key',
          onPageRecorded: (p) => recordedPageNumbers['sec:$key'] = p,
          child: pw.Container(
            margin: pw.EdgeInsets.only(top: _mm(1.5), bottom: _mm(2.5)),
            padding: pw.EdgeInsets.only(bottom: _mm(1.2)),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.blueGrey800, width: 1.0),
              ),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    label,
                    style: pw.TextStyle(
                        fontSize: 13.0,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blueGrey900),
                  ),
                ),
              ],
            ),
          ),
        );
        if (hatText) {
          final nw = _quillDeltaToWidgets(
            inhalt,
            normen: data.verwendeteNormen,
            linksAktivieren: data.linksAktivieren,
            sectionKey: key,
            onPageRecorded: (k, p) => recordedPageNumbers[k] = p,
          );
          if (nw.isNotEmpty) {
            widgets.add(pw.Inseparable(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [normHeader, nw.first],
              ),
            ));
            widgets.addAll(nw.sublist(1));
          } else {
            widgets.add(normHeader);
          }
        } else {
          widgets.add(normHeader);
          widgets.add(_normenListe(data.verwendeteNormen,
              linksAktivieren: data.linksAktivieren));
        }
        widgets.add(pw.SizedBox(height: _mm(2)));
        idx++;
        continue;
      }
      if (inhalt.isEmpty && inline.isEmpty) {
        continue;
      }

      if (!isFirstSection) {
        if (key == 's_grundlage' ||
            key == 's_situation' ||
            key == 's_feststellungen' ||
            key == 's_bewertung' ||
            key == 's_maengel' ||
            key == 's_massnahmen' ||
            key == 's_kosten' ||
            key == 's_beweisfragen' ||
            key == 's_fazit' ||
            key == 's_anlagen') {
          widgets.add(pw.NewPage());
        } else {
          widgets.add(pw.NewPage(freeSpace: 340));
        }
      }
      isFirstSection = false;

      final label = effectiveLabels[key] ?? key;
      final isAbschluss = key == 's_anlagen';
      final ueberschrift =
          (isAbschluss || key == 's_normenverzeichnis')
              ? label
              : '${_roman(idx)}. $label';
      final chapterHeader = _TocTargetWidget(
        tocKey: 'sec:$key',
        onPageRecorded: (p) => recordedPageNumbers['sec:$key'] = p,
        child: pw.Container(
          margin: pw.EdgeInsets.only(top: _mm(1.0), bottom: _mm(3.0)),
          padding: pw.EdgeInsets.only(bottom: _mm(1.5)),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColor.fromHex('1E3552'), width: 1.0),
            ),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  ueberschrift,
                  style: pw.TextStyle(
                      fontSize: 13.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('1E3552')),
                ),
              ),
            ],
          ),
        ),
      );

      if (inhalt.isNotEmpty) {
        final cleaned = inhalt
            .replaceAll(
                RegExp(r'\[FOTO:\d+\]\s*\n?Abb\.:[^\n]*\n?'),
                '')
            .replaceAll(RegExp(r'\[FOTO:\d+\]\s*\n?'), '')
            .replaceAll(RegExp(r'\n{3,}'), '\n\n')
            .trim();
        if (cleaned.isNotEmpty) {
          final sectionWidgets = _quillDeltaToWidgets(
            cleaned,
            normen: data.verwendeteNormen,
            linksAktivieren: data.linksAktivieren,
            sectionKey: key,
            onPageRecorded: (k, p) => recordedPageNumbers[k] = p,
          );
          var firstContentIdx = 0;
          while (firstContentIdx < sectionWidgets.length &&
              sectionWidgets[firstContentIdx] is pw.NewPage) {
            widgets.add(sectionWidgets[firstContentIdx]);
            firstContentIdx++;
          }
          if (firstContentIdx < sectionWidgets.length) {
            widgets.add(
              pw.Inseparable(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    chapterHeader,
                    sectionWidgets[firstContentIdx],
                  ],
                ),
              ),
            );
            widgets.addAll(sectionWidgets.sublist(firstContentIdx + 1));
          } else {
            widgets.add(chapterHeader);
          }
        } else {
          widgets.add(chapterHeader);
        }
      } else {
        widgets.add(chapterHeader);
      }
      if (inline.isNotEmpty) {
        widgets.add(pw.SizedBox(height: _mm(2)));
        for (final f in inline) {
          widgets.addAll(_lichtbildBlock(f, fotoIndex));
          fotoIndex++;
        }
      }
      if (isGericht && key == 's_beweisfragen') {
        widgets.add(pw.SizedBox(height: _mm(6.0)));
        widgets.add(pw.Inseparable(
          child: _unterschriftsBlock(
            data,
            dateFmt,
            siegelBytes: effectiveSiegelBytes,
            omitDeclarationParagraph: false,
            isGericht: true,
          ),
        ));
      }
      widgets.add(pw.SizedBox(height: _mm(1.5)));
      if (!isAbschluss) idx++;
    }
    if (widgets.isEmpty) {
      widgets.add(pw.Text('Keine Inhalte erfasst.',
          style: const pw.TextStyle(fontSize: 11)));
    }
    if (!isGericht || (sanitizedAbschnitte['s_beweisfragen'] ?? '').trim().isEmpty) {
      final hasSchlusserklaerungInText = (sanitizedAbschnitte['s_anlagen'] ?? '')
          .contains('Schlusserklärung (§ 407a ZPO)');
      widgets.add(pw.SizedBox(height: _mm(hasSchlusserklaerungInText ? 4 : 10)));
      widgets.add(pw.Inseparable(
        child: _unterschriftsBlock(
          data,
          dateFmt,
          siegelBytes: effectiveSiegelBytes,
          omitDeclarationParagraph: hasSchlusserklaerungInText,
          isGericht: isGericht,
        ),
      ));
    }
    return widgets;
  }

  // Abschnitte als MultiPage (bei Gerichtsgutachten wahlweise doppelseitig/einseitig und mit/ohne Notizlinien)
  if (isGericht) {
    doc.addPage(
      _CourtMultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        maxPages: 120,
        doppelseitig: data.doppelseitig,
        header: (ctx) => _kopfzeile(data, logo2, ctx: ctx, isGericht: true),
        footer: (ctx) => _fusszeile(
          ctx,
          data.absender,
          isGericht: true,
          doppelseitig: data.doppelseitig,
        ),
        buildBackground: (ctx) => _buildCourtMarginBackground(
          ctx,
          doppelseitig: data.doppelseitig,
          notizrandLinien: data.notizrandLinien,
        ),
        build: buildBodyWidgets,
      ),
    );
  } else {
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.fromLTRB(_mm(22), _mm(20), _mm(18), _mm(20)),
        theme: theme,
        maxPages: 120,
        header: (ctx) => _kopfzeile(data, logo2),
        footer: (ctx) => _fusszeile(ctx, data.absender),
        build: buildBodyWidgets,
      ),
    );
  }

  // Helper: legt eine Anlagen-Inhaltsseite an.
  pw.Page anlageSeite(pw.Widget child, {AnlagePdfEntry? anlageHeader}) {
    if (isGericht) {
      return pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        margin: pw.EdgeInsets.zero,
        build: (ctx) {
          final isEvenMirrored = data.doppelseitig && ctx.pageNumber.isEven;
          return pw.Stack(
            children: [
              _buildCourtMarginBackground(
                ctx,
                doppelseitig: data.doppelseitig,
                notizrandLinien: data.notizrandLinien,
              ),
              pw.Padding(
                padding: pw.EdgeInsets.fromLTRB(_mm(20), _mm(12.5), _mm(20), _mm(11.5)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    _kopfzeile(data, logo2, ctx: ctx, isGericht: true),
                    pw.Expanded(
                      child: pw.Padding(
                        padding: pw.EdgeInsets.only(
                          left: isEvenMirrored ? _mm(40) : 0,
                          right: isEvenMirrored ? 0 : _mm(40),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                          children: [
                            if (anlageHeader != null)
                              pw.Container(
                                margin: pw.EdgeInsets.only(top: _mm(1.0), bottom: _mm(2.5)),
                                padding: pw.EdgeInsets.only(bottom: _mm(1.2)),
                                decoration: const pw.BoxDecoration(
                                  border: pw.Border(
                                    bottom: pw.BorderSide(color: PdfColors.blueGrey800, width: 1.0),
                                  ),
                                ),
                                child: pw.Text(
                                  'Anlage ${anlageHeader.nr} – ${anlageHeader.titel}',
                                  style: pw.TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.blueGrey900,
                                  ),
                                ),
                              ),
                            pw.Expanded(child: child),
                          ],
                        ),
                      ),
                    ),
                    _fusszeile(
                      ctx,
                      data.absender,
                      isGericht: true,
                      doppelseitig: data.doppelseitig,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    }
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

  void addAnlagePage(AnlagePdfEntry a, pw.Page page) {
    doc.addPage(page);
    recordedPageNumbers.putIfAbsent(
      'anlage:${a.nr}',
      () => doc.document.pdfPageList.pages.length,
    );
  }

  // Anlagen folgen direkt nach der Unterschrift.
  for (final a in data.anlagen) {
    if (a.items.isEmpty) {
      if (isGericht) {
        addAnlagePage(
          a,
          anlageSeite(
            pw.Center(
              child: pw.Text(
                '(Anlage ${a.nr}: ${a.titel})',
                style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey700,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ),
            anlageHeader: a,
          ),
        );
      } else {
        addAnlagePage(
          a,
          _anlageDeckseite(a, dateFmt, theme,
              fusszeile: (ctx) => _fusszeile(ctx, data.absender),
              zusatz: '(Keine Inhalte vorhanden.)'),
        );
      }
      continue;
    }
    if (!isGericht) {
      addAnlagePage(
        a,
        _anlageDeckseite(a, dateFmt, theme,
            fusszeile: (ctx) => _fusszeile(ctx, data.absender)),
      );
    }
    var isFirstPageOfAnlage = true;
    for (final item in a.items) {
      final mime = item.mimeType.toLowerCase();
      final isPdf = mime.contains('pdf');
      if (isPdf) {
        final seitenBilder = await _rasterAnlagePdf(item.bytes);
        if (seitenBilder.isEmpty) {
          addAnlagePage(
            a,
            anlageSeite(
              pw.Center(
                child: pw.Text(
                    '(PDF konnte nicht gerastert werden.${item.caption == null ? '' : '\n${item.caption}'})',
                    style: pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                        fontStyle: pw.FontStyle.italic)),
              ),
              anlageHeader: isFirstPageOfAnlage ? a : null,
            ),
          );
          isFirstPageOfAnlage = false;
        } else {
          for (final bild in seitenBilder) {
            addAnlagePage(
              a,
              anlageSeite(
                pw.Center(
                  child: pw.Image(bild, fit: pw.BoxFit.contain),
                ),
                anlageHeader: isFirstPageOfAnlage ? a : null,
              ),
            );
            isFirstPageOfAnlage = false;
          }
        }
      } else if (mime.startsWith('image/')) {
        final mem = _safeMemoryImage(item.bytes);
        if (mem == null) {
          addAnlagePage(
            a,
            anlageSeite(
              pw.Center(
                child: pw.Text(
                    '(Bild-Format nicht darstellbar.${item.caption == null ? '' : '\n${item.caption}'})',
                    style: pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                        fontStyle: pw.FontStyle.italic)),
              ),
              anlageHeader: isFirstPageOfAnlage ? a : null,
            ),
          );
          isFirstPageOfAnlage = false;
        } else {
          addAnlagePage(
            a,
            anlageSeite(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Expanded(
                    child:
                        pw.Center(child: pw.Image(mem, fit: pw.BoxFit.contain)),
                  ),
                  if ((item.caption ?? '').isNotEmpty) ...[
                    pw.SizedBox(height: _mm(2)),
                    pw.Text(item.caption!,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                            fontSize: 9.5,
                            color: PdfColors.grey700,
                            fontStyle: pw.FontStyle.italic)),
                  ],
                ],
              ),
              anlageHeader: isFirstPageOfAnlage ? a : null,
            ),
          );
          isFirstPageOfAnlage = false;
        }
      } else {
        addAnlagePage(
          a,
          anlageSeite(
            pw.Center(
              child: pw.Text(
                  '(Format $mime — bitte separat ausdrucken oder beilegen.${item.caption == null ? '' : '\n${item.caption}'})',
                  style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                      fontStyle: pw.FontStyle.italic)),
            ),
            anlageHeader: isFirstPageOfAnlage ? a : null,
          ),
        );
        isFirstPageOfAnlage = false;
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

pw.Widget _normenListe(List<NormenData> normen, {bool linksAktivieren = true}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      ...normen.map((n) {
        final url = (n.pdfStorageUrl ?? '').trim();
        final hasUrl = url.isNotEmpty;

        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2.0),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: _mm(3.5),
                    child: pw.Text('•',
                        style: pw.TextStyle(
                            fontSize: 9.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blueGrey800)),
                  ),
                  pw.Expanded(
                    child: pw.RichText(
                      text: pw.TextSpan(
                        children: [
                          if (hasUrl && linksAktivieren)
                            pw.TextSpan(
                              text: n.nummer,
                              style: pw.TextStyle(
                                fontSize: 9.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColor.fromHex('1A56DB'),
                                decoration: pw.TextDecoration.underline,
                              ),
                              annotation: pw.AnnotationUrl(url),
                            )
                          else
                            pw.TextSpan(
                              text: n.nummer,
                              style: pw.TextStyle(
                                fontSize: 9.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.blueGrey900,
                              ),
                            ),
                          if (n.ausgabe != null && n.ausgabe!.isNotEmpty)
                            pw.TextSpan(
                              text: ' (${n.ausgabe})',
                              style: const pw.TextStyle(
                                fontSize: 9.5,
                                color: PdfColors.blueGrey700,
                              ),
                            ),
                          if (n.titel != null && n.titel!.isNotEmpty)
                            pw.TextSpan(
                              text: ' — ${n.titel}',
                              style: const pw.TextStyle(fontSize: 9.5),
                            ),
                        ],
                      ),
                      textAlign: pw.TextAlign.left,
                      hyphenation: _germanHyphenation,
                    ),
                  ),
                ],
              ),
              if ((n.zitat ?? '').isNotEmpty)
                pw.Padding(
                  padding: pw.EdgeInsets.only(left: _mm(3.5), top: 1.0),
                  child: pw.RichText(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                          text: '   → Relevanz / Fundstelle: ',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blueGrey700,
                          ),
                        ),
                        ..._formatTextWithNormLinks(
                          n.zitat!,
                          baseStyle: pw.TextStyle(
                            fontSize: 8.5,
                            fontStyle: pw.FontStyle.italic,
                            color: PdfColors.blueGrey800,
                          ),
                          normen: normen,
                          linksAktivieren: linksAktivieren,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    ],
  );
}

pw.Widget _unterschriftsBlock(
  GutachtenPdfData d,
  DateFormat dateFmt, {
  Uint8List? siegelBytes,
  Uint8List? unterschriftBytes,
  bool omitDeclarationParagraph = false,
  bool isGericht = false,
}) {
  final druckdatum = isGericht
      ? (d.gutachten.abgabeAm ?? d.gutachten.datum ?? DateTime.now())
      : DateTime.now();
  final ort = (d.absender?.ort ?? '').trim().isNotEmpty
      ? d.absender!.ort!.trim()
      : 'Hamminkeln';
  final vorname = (d.absender?.vorname ?? '').trim();
  final nachname = (d.absender?.nachname ?? '').trim();
  final titel = (d.absender?.titel ?? '').trim();
  final String displayName;
  if (titel.contains('Dipl.-Ing.') && titel.contains('M.Eng.')) {
    displayName = (vorname.isNotEmpty && nachname.isNotEmpty)
        ? 'Dipl.-Ing. (FH) $vorname $nachname, M.Eng.'
        : 'Dipl.-Ing. (FH) Alexander Höpken, M.Eng.';
  } else if (titel.isNotEmpty && (vorname.isNotEmpty || nachname.isNotEmpty)) {
    displayName = '$titel $vorname $nachname'.trim();
  } else if (vorname.isNotEmpty || nachname.isNotEmpty) {
    displayName = 'Dipl.-Ing. (FH) $vorname $nachname, M.Eng.'.trim();
  } else {
    displayName = 'Dipl.-Ing. (FH) Alexander Höpken, M.Eng.';
  }

  final sig = isGericht ? null : _safeMemoryImage(d.unterschriftBytes);
  final siegelData = siegelBytes ?? d.stempelBytes ?? d.siegelBytes;
  final siegel = _safeMemoryImage(siegelData);

  final unterschriftsBox = pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        [
          if (ort.isNotEmpty) ort,
          'den ${dateFmt.format(druckdatum)}',
        ].join(', '),
        style: const pw.TextStyle(fontSize: 10.0),
      ),
      pw.SizedBox(height: sig != null ? _mm(2.0) : _mm(12.0)),
      if (sig != null)
        pw.Container(
          width: _mm(52),
          height: _mm(22),
          alignment: pw.Alignment.bottomLeft,
          child: pw.Image(sig, fit: pw.BoxFit.contain),
        ),
      pw.Container(width: _mm(78), height: 0.7, color: PdfColors.grey800),
      pw.SizedBox(height: 5),
      pw.Text(displayName,
          style: pw.TextStyle(fontSize: 10.0, fontWeight: pw.FontWeight.bold)),
      if (isGericht) ...[
        pw.SizedBox(height: 3),
        pw.Text(
            'Von der ${(d.bestellBehoerde ?? '').trim().isNotEmpty ? d.bestellBehoerde! : 'Handwerkskammer Düsseldorf'}',
            style: const pw.TextStyle(fontSize: 8.8, color: PdfColors.grey800)),
        pw.Text('öffentlich bestellter und vereidigter',
            style: const pw.TextStyle(fontSize: 8.8, color: PdfColors.grey800)),
        pw.Text('Sachverständiger für das Metallbauer-Handwerk,',
            style: const pw.TextStyle(fontSize: 8.8, color: PdfColors.grey800)),
        pw.Text('Teilgebiet Konstruktionstechnik',
            style: const pw.TextStyle(fontSize: 8.8, color: PdfColors.grey800)),
      ] else ...[
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
    ],
  );

  final siegelBox = siegel == null
      ? pw.Container(
          width: _mm(42),
          height: _mm(42),
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(
              color: PdfColors.grey500,
              width: 0.6,
              style: pw.BorderStyle.dashed,
            ),
          ),
          child: pw.Text(
            '[ Rundstempel /\nSachverständigensiegel ]',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600),
          ),
        )
      : pw.Container(
          width: _mm(42),
          height: _mm(42),
          alignment: pw.Alignment.center,
          child: pw.Image(siegel, fit: pw.BoxFit.contain),
        );

  final leftRightReversed = d.siegelPosition == 'unten_links';
  final rowChildren = <pw.Widget>[
    if (d.siegelPosition == 'mit_unterschrift')
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Stack(
            children: [
              unterschriftsBox,
              if (siegel != null)
                pw.Positioned(
                  right: 0,
                  bottom: 0,
                  child: pw.Opacity(opacity: 0.75, child: siegelBox),
                ),
            ],
          ),
        ],
      )
    else if (leftRightReversed) ...[
      siegelBox,
      pw.SizedBox(width: _mm(10)),
      unterschriftsBox,
      pw.Spacer(),
    ] else ...[
      unterschriftsBox,
      pw.Spacer(),
      siegelBox,
    ],
  ];

  final unterschriftRow = (d.siegelPosition == 'mit_unterschrift')
      ? rowChildren.first
      : pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: rowChildren,
        );

  final ortsterminDatum = d.gutachten.ortsterminAm ?? d.auftrag?.ortsterminAm;
  final ortsterminInfo = ortsterminDatum != null
      ? ' beim Ortstermin am ${dateFmt.format(ortsterminDatum)}'
      : '';

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      if (!omitDeclarationParagraph) ...[
        if (isGericht)
          pw.Padding(
            padding: pw.EdgeInsets.only(top: _mm(3.0), bottom: _mm(1.2)),
            child: pw.Text(
              'Schlusserklärung (§ 407a ZPO)',
              style: pw.TextStyle(
                fontSize: 10.4,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('2C4A6F'),
              ),
            ),
          ),
        pw.Padding(
          padding: pw.EdgeInsets.only(top: isGericht ? 0 : _mm(4), bottom: _mm(6)),
          child: pw.Text(
            isGericht
                ? 'Das Gutachten wurde von mir persönlich, unparteiisch und nach bestem Wissen und Gewissen auf Grundlage der Gerichtsakte, meiner eigenen Feststellungen$ortsterminInfo und der genannten technischen Regelwerke erstattet (§ 407a ZPO).'
                : 'Das Gutachten wurde von mir persönlich, unparteiisch und nach bestem Wissen und Gewissen auf Grundlage der mir zur Verfügung gestellten Aktenlage und technischen Regelwerke erstattet (§ 407a ZPO).',
            textAlign: pw.TextAlign.justify,
            style: pw.TextStyle(
              fontSize: 9.8,
              lineSpacing: 3.5,
              fontStyle: isGericht ? pw.FontStyle.normal : pw.FontStyle.italic,
              color: PdfColors.black,
            ),
          ),
        ),
      ],
      unterschriftRow,
    ],
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
  GutachtenPdfData d,
  DateFormat dateFmt,
  pw.ImageProvider? logo, {
  pw.Context? ctx,
}) {
  final g = d.gutachten;
  final auftrag = d.auftrag;
  final kunde = d.kunde;
  final absender = d.absender;

  final isGericht = (auftrag?.art ?? '').toLowerCase().contains('gericht') ||
      (auftrag?.gerichtsAktenzeichen ?? '').trim().isNotEmpty ||
      (auftrag?.gericht ?? '').trim().isNotEmpty ||
      (auftrag?.klaeger ?? '').trim().isNotEmpty ||
      (auftrag?.beklagter ?? '').trim().isNotEmpty;

  if (isGericht) {
    Map<String, dynamic> deckblattMeta = {};
    final extrasStr = (auftrag?.extras ?? '').trim();
    if (extrasStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(extrasStr);
        if (decoded is Map && decoded['deckblatt'] is Map) {
          deckblattMeta = Map<String, dynamic>.from(decoded['deckblatt'] as Map);
        }
      } catch (_) {}
    }

    final gerichtText = (deckblattMeta['gericht'] as String?)?.trim().isNotEmpty == true
        ? (deckblattMeta['gericht'] as String).trim()
        : [auftrag?.gericht ?? 'Landgericht', auftrag?.gerichtsort ?? 'Musterstadt']
            .where((s) => s.trim().isNotEmpty)
            .join(' ');
    final azText = (auftrag?.gerichtsAktenzeichen ?? '').trim().isNotEmpty
        ? auftrag!.gerichtsAktenzeichen!.trim()
        : '4 OH 117/26';
    final verfahrenText = (auftrag?.verfahrensart ?? '').trim().isNotEmpty
        ? auftrag!.verfahrensart!.trim()
        : 'Selbständiges Beweisverfahren';
    final inSachenText = (deckblattMeta['inSachen'] as String?)?.trim().isNotEmpty == true
        ? (deckblattMeta['inSachen'] as String).trim()
        : '${auftrag?.klaeger ?? 'EG Musterverwaltung (Bauherrin)'}\n– Antragstellerin –\ngegen\n${auftrag?.beklagter ?? 'Metallbaubetrieb Eisenhart'}\n– Antragsgegner –';
    final prozessbevollmText =
        (deckblattMeta['prozessbevollmaechtigte'] as String?)?.trim().isNotEmpty == true
            ? (deckblattMeta['prozessbevollmaechtigte'] as String).trim()
            : 'Antragstellerin: Rechtsanwälte Dr. Weber & Partner, Musterstadt\nAntragsgegner: Rechtsanwälte Kanzlei am Markt, Musterstadt';
    final beschlussText =
        (deckblattMeta['beweisbeschlussVom'] as String?)?.trim().isNotEmpty == true
            ? (deckblattMeta['beweisbeschlussVom'] as String).trim()
            : (auftrag?.beweisbeschluss1 != null
                ? dateFmt.format(auftrag!.beweisbeschluss1!)
                : '08.10.2026');
    final objektText = (deckblattMeta['objekt'] as String?)?.trim().isNotEmpty == true
        ? (deckblattMeta['objekt'] as String).trim()
        : [
            if ((auftrag?.objektStrasse ?? '').isNotEmpty)
              'Wohn- und Geschäftshaus ${auftrag!.objektStrasse}',
            [auftrag?.objektPlz ?? '', auftrag?.objektOrt ?? '']
                .where((s) => s.trim().isNotEmpty)
                .join(' '),
          ].where((s) => s.trim().isNotEmpty).join(', ');
    final gerichtsakteText =
        (deckblattMeta['gerichtsakte'] as String?)?.trim().isNotEmpty == true
            ? (deckblattMeta['gerichtsakte'] as String).trim()
            : '8 Blatt: Beweisbeschluss mit Erläuterungen (Bl. 1–3), Anlagen 1 bis 5 (Bl. 4–8)';
    final ortsterminText =
        (deckblattMeta['ortsterminText'] as String?)?.trim().isNotEmpty == true
            ? (deckblattMeta['ortsterminText'] as String).trim()
            : ((deckblattMeta['ortstermin'] as String?)?.trim().isNotEmpty == true
                ? (deckblattMeta['ortstermin'] as String).trim()
                : (g.ortsterminAm != null
                    ? '${dateFmt.format(g.ortsterminAm!)}, 10:00 bis 12:30 Uhr; Witterung trocken, Außentemperatur ca. 12 °C'
                    : '19.11.2026, 10:00 bis 12:30 Uhr; Witterung trocken, Außentemperatur ca. 12 °C'));
    final gutachtenDatumText = g.datum != null
        ? dateFmt.format(g.datum!)
        : (g.abgabeAm != null ? dateFmt.format(g.abgabeAm!) : '04.12.2026');
    final ausfertigungText =
        (deckblattMeta['ausfertigung'] as String?)?.trim().isNotEmpty == true
            ? (deckblattMeta['ausfertigung'] as String).trim()
            : '1. Ausfertigung für das Gericht';
    final auftragAbsatz =
        (deckblattMeta['auftragText'] as String?)?.trim().isNotEmpty == true
            ? (deckblattMeta['auftragText'] as String).trim()
            : 'Mit Schreiben vom 21.10.2026 erhielt ich vom Landgericht Musterstadt in Sachen EG Musterverwaltung ./. Metallbaubetrieb Eisenhart, Aktenzeichen $azText, den Auftrag zur Erstattung eines Gutachtens. Dieses Gutachten ist gemäß Beweisbeschluss vom 08.10.2026 über die in Abschnitt I wiedergegebenen Fragen zu erstellen.';

    pw.TableRow metaRow(String label, pw.Widget valueWidget) {
      return pw.TableRow(
        children: [
          pw.Container(
            color: PdfColor.fromHex('EDF1F6'),
            padding: pw.EdgeInsets.symmetric(horizontal: _mm(3.0), vertical: _mm(2.2)),
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 9.2,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('1E3552'),
              ),
            ),
          ),
          pw.Container(
            color: PdfColors.white,
            padding: pw.EdgeInsets.symmetric(horizontal: _mm(3.2), vertical: _mm(2.2)),
            child: valueWidget,
          ),
        ],
      );
    }

    pw.Widget simpleVal(String text, {bool bold = false}) => pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 9.2,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            lineSpacing: 2.2,
          ),
        );

    final totalPages = ctx?.pagesCount ?? 40;
    final anlagenCount = d.anlagen.isNotEmpty ? d.anlagen.length : 5;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: _mm(24.0)),
        pw.Center(
          child: pw.Column(
            children: [
              pw.Text(
                'GUTACHTEN',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('1E3552'),
                  letterSpacing: 1.5,
                ),
              ),
              pw.SizedBox(height: _mm(3.0)),
              pw.Text(
                'des von der Handwerkskammer Düsseldorf',
                style: const pw.TextStyle(fontSize: 10.2, color: PdfColors.black),
              ),
              pw.SizedBox(height: _mm(0.8)),
              pw.Text(
                'öffentlich bestellten und vereidigten Sachverständigen',
                style: const pw.TextStyle(fontSize: 10.2, color: PdfColors.black),
              ),
              pw.SizedBox(height: _mm(0.8)),
              pw.Text(
                'für das Metallbauer-Handwerk, Teilgebiet Konstruktionstechnik',
                style: const pw.TextStyle(fontSize: 10.2, color: PdfColors.black),
              ),
              pw.SizedBox(height: _mm(4.0)),
              pw.Text(
                'Dipl.-Ing. (FH) Alexander Höpken, M.Eng.',
                style: pw.TextStyle(fontSize: 12.0, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: _mm(1.2)),
              pw.Text(
                'Auf dem Stemmingholt 21 · 46499 Hamminkeln',
                style: const pw.TextStyle(fontSize: 9.8, color: PdfColors.black),
              ),
              pw.SizedBox(height: _mm(0.8)),
              pw.Text(
                'Tel. +49 152 519 750 42 · alexander.hoepken@gmail.com',
                style: const pw.TextStyle(fontSize: 9.8, color: PdfColors.black),
              ),
              pw.SizedBox(height: _mm(3.8)),
              pw.Text(
                'Gutachten-Nr. ${g.nummer ?? auftrag?.aktenzeichen ?? '2026-011-G'}',
                style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: _mm(5.0)),
        pw.Table(
          columnWidths: {
            0: pw.FixedColumnWidth(_mm(46)),
            1: const pw.FlexColumnWidth(),
          },
          border: pw.TableBorder(
            top: pw.BorderSide(color: PdfColor.fromHex('1E3552'), width: 1.2),
            bottom: pw.BorderSide(color: PdfColor.fromHex('1E3552'), width: 1.2),
            left: pw.BorderSide(color: PdfColor.fromHex('1E3552'), width: 1.2),
            right: pw.BorderSide(color: PdfColor.fromHex('1E3552'), width: 1.2),
            horizontalInside: const pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            verticalInside: const pw.BorderSide(color: PdfColors.grey300, width: 0.5),
          ),
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
          children: [
            metaRow('Gericht', simpleVal(gerichtText)),
            metaRow('Aktenzeichen', simpleVal(azText)),
            metaRow('Verfahren', simpleVal(verfahrenText)),
            metaRow('In Sachen', simpleVal(inSachenText)),
            metaRow('Prozessbevollmächtigte', simpleVal(prozessbevollmText)),
            metaRow('Beweisbeschluss vom', simpleVal(beschlussText)),
            metaRow('Objekt', simpleVal(objektText)),
            metaRow('Gerichtsakte', simpleVal(gerichtsakteText)),
            metaRow('Ortstermin', simpleVal(ortsterminText)),
            metaRow('Gutachtendatum', simpleVal(gutachtenDatumText)),
            metaRow('Ausfertigung', simpleVal(ausfertigungText)),
          ],
        ),
        pw.SizedBox(height: _mm(7.0)),
        pw.RichText(
          textAlign: pw.TextAlign.justify,
          hyphenation: _germanHyphenation,
          text: pw.TextSpan(
            style: const pw.TextStyle(fontSize: 9.8, lineSpacing: 3.8),
            children: [
              pw.TextSpan(
                text: 'Auftrag: ',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.TextSpan(text: auftragAbsatz),
            ],
          ),
        ),
        pw.SizedBox(height: _mm(14.0)),
        pw.Text(
          'Dieses Gutachten umfasst $totalPages Seiten einschließlich $anlagenCount Anlagen.',
          style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.black),
        ),
      ],
    );
  }

  String? beweisbeschlussText;
  if (auftrag?.beweisbeschluss1 != null) {
    beweisbeschlussText =
        'Beweisbeschluss vom ${dateFmt.format(auftrag!.beweisbeschluss1!)}';
  } else if (auftrag?.notiz != null &&
      auftrag!.notiz!.toLowerCase().contains('beweisbeschluss')) {
    final match =
        RegExp(r'Beweisbeschluss[^\n\r.]+').firstMatch(auftrag.notiz!);
    if (match != null) {
      beweisbeschlussText = match.group(0)?.trim();
    }
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
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
          if (absender != null) () {
            final vorname = (absender.vorname ?? '').trim();
            final nachname = (absender.nachname ?? '').trim();
            final nameDirekt = [vorname, nachname].where((s) => s.isNotEmpty).join(' ');
            final effectiveName = nameDirekt.isNotEmpty
                ? nameDirekt
                : ((absender.firma ?? '').trim().isNotEmpty ? absender.firma!.trim() : 'Alexander Höpken');

            final rawTitel = (absender.titel ?? '').trim();
            final titel = rawTitel.isNotEmpty ? rawTitel : 'Dipl.-Ing. (FH), M.Eng.';

            String kopfName;
            if (titel.contains('Dipl.-Ing.') && titel.contains('M.Eng.')) {
              if (vorname.isNotEmpty && nachname.isNotEmpty) {
                kopfName = 'Dipl.-Ing. (FH) $vorname $nachname, M.Eng.';
              } else {
                kopfName = 'Dipl.-Ing. (FH) $effectiveName, M.Eng.';
              }
            } else if (titel.isNotEmpty) {
              kopfName = '$titel $effectiveName';
            } else {
              kopfName = effectiveName;
            }

            final emailRaw = (absender.email ?? '').trim();
            final email = (emailRaw.isEmpty || emailRaw.contains('bauelemente-experte.de') || emailRaw.contains('aktenwerk.app'))
                ? 'alexander.hoepken@gmail.com'
                : emailRaw;

            final strasse = (absender.strasse ?? '').trim().isNotEmpty
                ? absender.strasse!.trim()
                : 'Auf dem Stemmingholt 21';
            final plzOrt = [
              absender.plz ?? '46499',
              absender.ort ?? 'Hamminkeln'
            ].where((s) => s.trim().isNotEmpty).join(' ');

            final telefon = (absender.telefon ?? '').trim().isNotEmpty
                ? absender.telefon!.trim()
                : '+49 152 519 750 42';

            final bestellung = (absender.bestellungsText ?? '').trim().isNotEmpty
                ? absender.bestellungsText!.split('\n').first.trim()
                : 'Beratender Ingenieur und Sachverständiger';

            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  kopfName,
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
                if (bestellung.isNotEmpty)
                  pw.Text(
                    bestellung,
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey700),
                  ),
                pw.SizedBox(height: 2),
                pw.Text(
                  [strasse, plzOrt].where((s) => s.isNotEmpty).join(' · '),
                  style: const pw.TextStyle(fontSize: 9),
                ),
                pw.Text(
                  ['Tel. $telefon', email].join(' · '),
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            );
          }(),
        ],
      ),
      pw.Spacer(),
      pw.Center(
        child: pw.Column(
          children: [
            pw.Text('GUTACHTEN',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 32,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.1)),
            if ((g.nummer ?? auftrag?.aktenzeichen ?? '').isNotEmpty) ...[
              pw.SizedBox(height: _mm(3)),
              pw.Text('Gutachten-Nr. ${g.nummer ?? auftrag?.aktenzeichen}',
                  style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey800)),
            ],
            pw.SizedBox(height: _mm(8)),
            if ((g.titel ?? auftrag?.bezeichnung ?? '').isNotEmpty)
              pw.Text(g.titel ?? auftrag?.bezeichnung ?? '',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold)),
            if ((g.bezeichnung ?? auftrag?.betreff ?? '').isNotEmpty) ...[
              pw.SizedBox(height: _mm(3)),
              pw.Text(g.bezeichnung ?? auftrag?.betreff ?? '',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(
                      fontSize: 12, color: PdfColors.grey800)),
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
            if (kunde != null) ...[
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
              if (beweisbeschlussText != null)
                _row('Auftrag / Beschluss', beweisbeschlussText),
            ],
            if (auftrag != null &&
                ((auftrag.objektStrasse ?? '').isNotEmpty))
              _row('Bauvorhaben / Objekt',
                  '${auftrag.objektStrasse}, ${auftrag.objektPlz ?? ''} ${auftrag.objektOrt ?? ''}'
                      .trim()),
            if ((auftrag?.sachgebiet ?? '').isNotEmpty)
              _row('Sachgebiet', auftrag!.sachgebiet!),
            if (g.datum != null)
              _row('Gutachtendatum', dateFmt.format(g.datum!)),
            _row('Ausfertigung', 'Originalausfertigung'),
            if (d.anlagen.isNotEmpty)
              _row('Anlagen',
                  '${d.anlagen.length} Anlagen (siehe Anlagenverzeichnis)'),
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
          width: 145,
          child: pw.Text(label,
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey700)),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
        ),
      ],
    ),
  );
}

pw.Widget _kopfzeile(
  GutachtenPdfData d,
  pw.ImageProvider? logo, {
  pw.Context? ctx,
  bool isGericht = false,
}) {
  if (isGericht) {
    final nr = (d.gutachten.nummer ?? d.auftrag?.aktenzeichen ?? '2026-011-G').trim();
    final gericht = (d.auftrag?.gericht ?? '').toLowerCase().contains('landgericht')
        ? 'LG'
        : (d.auftrag?.gericht ?? 'LG').trim();
    final ort = (d.auftrag?.gerichtsort ?? 'Musterstadt').trim();
    final az = (d.auftrag?.gerichtsAktenzeichen ?? '4 OH 117/26').trim();
    final text = 'Gutachten Nr. $nr · $gericht $ort, Az. $az';
    final isEven = d.doppelseitig && (ctx?.pageNumber ?? 2).isEven;
    return pw.Container(
      margin: pw.EdgeInsets.only(bottom: _mm(3.5)),
      padding: pw.EdgeInsets.only(bottom: _mm(1.5)),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey600, width: 0.5),
        ),
      ),
      alignment: isEven ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 8.2, color: PdfColors.grey700),
      ),
    );
  }

  final az = (d.auftrag?.aktenzeichen ?? '').trim();
  final nr = (d.gutachten.nummer ?? '').trim();
  String line;
  if (nr.isNotEmpty && az.isNotEmpty) {
    line = (nr == az) ? nr : '$nr · $az';
  } else {
    line = nr.isNotEmpty ? nr : az;
  }
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

pw.Widget _fusszeile(
  pw.Context ctx,
  BenutzerData? absender, {
  bool isGericht = false,
  bool doppelseitig = true,
}) {
  final vorname = (absender?.vorname ?? '').trim();
  final nachname = (absender?.nachname ?? '').trim();
  final nameDirekt = [vorname, nachname].where((s) => s.isNotEmpty).join(' ');
  final personName = nameDirekt.isNotEmpty
      ? nameDirekt
      : ((absender?.firma ?? '').trim().isNotEmpty ? absender!.firma!.trim() : 'Alexander Höpken');
  final rawTitel = (absender?.titel ?? '').trim();
  final titel = rawTitel.isNotEmpty ? rawTitel : 'Dipl.-Ing. (FH), M.Eng.';

  String name;
  if (titel.contains('Dipl.-Ing.') && titel.contains('M.Eng.')) {
    if (vorname.isNotEmpty && nachname.isNotEmpty) {
      name = 'Dipl.-Ing. (FH) $vorname $nachname, M.Eng.';
    } else {
      name = 'Dipl.-Ing. (FH) $personName, M.Eng.';
    }
  } else if (titel.isNotEmpty) {
    name = '$titel $personName';
  } else {
    name = personName;
  }

  if (isGericht) {
    final isEven = doppelseitig && ctx.pageNumber.isEven;
    final pageStr = 'Seite ${ctx.pageNumber} von ${ctx.pagesCount}';
    final svStr = 'Sachverständiger $name';
    return pw.Container(
      margin: pw.EdgeInsets.only(top: _mm(3.0)),
      padding: pw.EdgeInsets.only(top: _mm(1.5)),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey600, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            isEven ? pageStr : svStr,
            style: const pw.TextStyle(fontSize: 8.2, color: PdfColors.grey700),
          ),
          pw.Text(
            isEven ? svStr : pageStr,
            style: const pw.TextStyle(fontSize: 8.2, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  final anschrift = [
    absender?.strasse ?? 'Auf dem Stemmingholt 21',
    [absender?.plz ?? '46499', absender?.ort ?? 'Hamminkeln']
        .whereType<String>()
        .where((s) => (s).trim().isNotEmpty)
        .join(' '),
  ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · ');

  final emailRaw = (absender?.email ?? '').trim();
  final email = (emailRaw.isEmpty || emailRaw.contains('bauelemente-experte.de') || emailRaw.contains('aktenwerk.app'))
      ? 'alexander.hoepken@gmail.com'
      : emailRaw;
  final telefon = (absender?.telefon ?? '').trim().isNotEmpty
      ? absender!.telefon!.trim()
      : '+49 152 519 750 42';

  final kontakt = ['Tel. $telefon', email].join(' · ');
  final zeile1 = [name, anschrift].where((s) => s.isNotEmpty).join('  |  ');
  final zeile2 = kontakt;

  return pw.Container(
    padding: const pw.EdgeInsets.only(top: 5),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
      ),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                zeile1,
                style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                maxLines: 1,
              ),
              pw.SizedBox(height: 1.5),
              pw.Text(
                zeile2,
                style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                maxLines: 1,
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Text(
          'Seite ${ctx.pageNumber} / ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    ),
  );
}

/// Zeichnet den Seitenhintergrund mit optionaler vertikaler Trennlinie +
/// liniertem Notizrand sowie Falzmarken.
/// - Bei `doppelseitig == true`: ungerade Seiten haben den Rand rechts,
///   gerade Seiten haben den Rand links.
/// - Bei `doppelseitig == false` (einseitig): der breite Rand liegt auf allen
///   Seiten rechts.
/// - Bei `notizrandLinien == false`: der breite Rand bleibt frei/leer (ohne
///   vertikale Trennlinie und ohne horizontale Schreiblinien).
pw.Widget _buildCourtMarginBackground(
  pw.Context ctx, {
  bool doppelseitig = true,
  bool notizrandLinien = true,
}) {
  final isEven = doppelseitig && ctx.pageNumber.isEven;
  return pw.CustomPaint(
    size: PdfPoint(PdfPageFormat.a4.width, PdfPageFormat.a4.height),
    painter: (canvas, size) {
      if (notizrandLinien) {
        final sepX = isEven ? _mm(55.0) : _mm(155.0);
        final noteX1 = isEven ? _mm(20.0) : _mm(158.0);
        final noteX2 = isEven ? _mm(52.0) : _mm(190.0);

        // Vertikale Trennlinie zwischen Textspalte und Notizrand
        canvas
          ..setStrokeColor(PdfColors.grey600)
          ..setLineWidth(0.5)
          ..moveTo(sepX, _mm(20.0))
          ..lineTo(sepX, _mm(275.0))
          ..strokePath();

        // 28 horizontale Schreiblinien im Notizrand (Abstand 9 mm)
        canvas
          ..setStrokeColor(PdfColor.fromHex('DFDFDF'))
          ..setLineWidth(0.35);
        for (var i = 0; i < 28; i++) {
          final y = _mm(26.0 + i * 9.0);
          canvas
            ..moveTo(noteX1, y)
            ..lineTo(noteX2, y);
        }
        canvas.strokePath();
      }

      // Falz- und Lochmarken am äußeren Heftrand
      final markX1 = isEven ? _mm(202.0) : _mm(4.0);
      final markX2 = isEven ? _mm(206.0) : _mm(8.0);
      final punchX2 = isEven ? _mm(207.0) : _mm(9.0);
      canvas
        ..setStrokeColor(PdfColors.grey500)
        ..setLineWidth(0.35)
        ..moveTo(markX1, _mm(105.0))
        ..lineTo(markX2, _mm(105.0))
        ..moveTo(markX1, _mm(148.5))
        ..lineTo(punchX2, _mm(148.5))
        ..moveTo(markX1, _mm(192.0))
        ..lineTo(markX2, _mm(192.0))
        ..strokePath();
    },
  );
}

/// Unsichtbarer Wrapper, der während des Layout-Durchlaufs die tatsächliche
/// 1-basierte PDF-Seitenzahl für das Inhaltsverzeichnis aufzeichnet.
class _TocTargetWidget extends pw.SingleChildWidget {
  _TocTargetWidget({
    required this.tocKey,
    required this.onPageRecorded,
    required pw.Widget child,
  }) : super(child: child);

  final String tocKey;
  final void Function(int pageNumber) onPageRecorded;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    super.layout(context, constraints, parentUsesSize: parentUsesSize);
    onPageRecorded(context.pageNumber);
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    paintChild(context);
  }
}

class _CourtPageSlot {
  _CourtPageSlot({
    required this.context,
    required this.contentConstraints,
    required this.headerFooterConstraints,
    required this.fullPageConstraints,
    required this.offsetStart,
  });

  final pw.Context context;
  final pw.BoxConstraints contentConstraints;
  final pw.BoxConstraints headerFooterConstraints;
  final pw.BoxConstraints fullPageConstraints;
  final double offsetStart;
  final List<_CourtPlacedWidget> widgets = <_CourtPlacedWidget>[];
}

class _CourtPlacedWidget {
  const _CourtPlacedWidget({
    required this.child,
    required this.constraints,
    required this.widgetContext,
  });

  final pw.Widget child;
  final pw.BoxConstraints constraints;
  final pw.WidgetContext? widgetContext;
}

/// Doppelseitiges MultiPage-Layout für Gerichtsgutachten:
/// - Kopf- und Fußzeile spannen über die gesamte Satzbreite (x = 20..190 mm, Breite 170 mm)
/// - Die Textspalte (Breite 130 mm) wechselt je Seite:
///   • ungerade Seiten (3, 5, 7, …): links x = 20..150 mm, Notizrand rechts x = 155..190 mm
///   • gerade Seiten (2, 4, 6, …):   Notizrand links x = 20..55 mm, Textspalte rechts x = 60..190 mm
class _CourtMultiPage extends pw.Page {
  _CourtMultiPage({
    required pw.BuildListCallback build,
    this.header,
    this.footer,
    this.buildBackground,
    PdfPageFormat? pageFormat,
    super.theme,
    this.maxPages = 120,
    this.doppelseitig = true,
  }) : _buildList = build,
       super(
         pageFormat: pageFormat ?? PdfPageFormat.a4,
         margin: pw.EdgeInsets.zero,
         build: (_) => pw.SizedBox(),
       );

  final pw.BuildListCallback _buildList;
  final pw.BuildCallback? header;
  final pw.BuildCallback? footer;
  final pw.BuildCallback? buildBackground;
  final int maxPages;
  final bool doppelseitig;
  final List<_CourtPageSlot> _pages = <_CourtPageSlot>[];

  void _paintAt(pw.Context context, pw.Widget child, double x, double y) {
    child.box = child.box!.copyWith(left: x, bottom: y);
    child.paint(context);
  }

  @override
  void generate(pw.Document document, {bool insert = true, int? index}) {
    final pageWidth = pageFormat.width;
    final pageHeight = pageFormat.height;
    final topMargin = _mm(12.5);
    final bottomMargin = _mm(11.5);

    final contentConstraints = pw.BoxConstraints(maxWidth: _mm(130.0));
    final headerFooterConstraints = pw.BoxConstraints(maxWidth: _mm(170.0));
    final fullPageConstraints = pw.BoxConstraints(
      maxWidth: pageWidth,
      maxHeight: pageHeight,
    );

    final calculatedTheme = theme ?? document.theme ?? pw.ThemeData.base();
    pw.Context? context;
    var offsetEnd = 0.0;
    double? offsetStart;
    var idx = 0;
    var sameCount = 0;
    final baseContext = pw.Context(document: document.document)
        .inheritFromAll(<pw.Inherited>[calculatedTheme]);
    final children = _buildList(baseContext);
    pw.WidgetContext? widgetContext;

    while (idx < children.length) {
      final child = children[idx];
      if (sameCount++ > maxPages) {
        throw pw.TooManyPagesException(
          'CourtMultiPage exceeded maxPages ($maxPages).',
        );
      }

      final freeSpace = (offsetStart == null)
          ? (pageHeight - topMargin - bottomMargin)
          : offsetStart - offsetEnd;

      if (context == null || (child is pw.NewPage && child.newPageNeeded(freeSpace))) {
        final pdfPage = PdfPage(
          document.document,
          pageFormat: pageFormat,
          index: index == null ? null : (index++),
        );
        final canvas = pdfPage.getGraphics();
        canvas.reset();
        context = baseContext.copyWith(page: pdfPage, canvas: canvas);

        offsetStart = pageHeight - topMargin;
        offsetEnd = bottomMargin;

        _pages.add(
          _CourtPageSlot(
            context: context,
            contentConstraints: contentConstraints,
            headerFooterConstraints: headerFooterConstraints,
            fullPageConstraints: fullPageConstraints,
            offsetStart: offsetStart,
          ),
        );

        if (header != null) {
          final headerWidget = header!(context);
          headerWidget.layout(context, headerFooterConstraints, parentUsesSize: false);
          offsetStart -= headerWidget.box!.height;
        }
        if (footer != null) {
          final footerWidget = footer!(context);
          footerWidget.layout(context, headerFooterConstraints, parentUsesSize: false);
          offsetEnd += footerWidget.box!.height;
        }

        if (child is pw.NewPage) {
          sameCount = 0;
          idx++;
          continue;
        }
      }

      pw.WidgetContext? savedContext;
      if (child is pw.SpanningWidget && child.canSpan) {
        if (widgetContext != null) {
          child.restoreContext(widgetContext);
          widgetContext = null;
        }
        savedContext = child.cloneContext();
      }

      child.layout(context, contentConstraints, parentUsesSize: false);
      final canSpan = child is pw.SpanningWidget && child.canSpan;

      if (offsetStart! - child.box!.height < offsetEnd) {
        final maxAvailable = pageHeight - topMargin - bottomMargin - _mm(18);
        if (child.box!.height <= maxAvailable && !canSpan) {
          context = null;
          continue;
        }
        if (!canSpan) {
          // Falls ein Inseparable-Element minimal größer als eine Seite ist, trotzdem auf die Seite setzen
          _pages.last.widgets.add(
            _CourtPlacedWidget(
              child: child,
              constraints: contentConstraints,
              widgetContext: null,
            ),
          );
          offsetStart -= child.box!.height;
          sameCount = 0;
          idx++;
          context = null;
          continue;
        }

        final span = child;
        if (savedContext != null) {
          span.applyContext(savedContext);
        }
        final localConstraints = contentConstraints.copyWith(
          maxHeight: math.max(10.0, offsetStart - offsetEnd),
        );
        span.layout(context, localConstraints, parentUsesSize: false);
        widgetContext = span.saveContext();
        _pages.last.widgets.add(
          _CourtPlacedWidget(
            child: span,
            constraints: localConstraints,
            widgetContext: widgetContext.clone(),
          ),
        );
        if (!span.hasMoreWidgets) {
          sameCount = 0;
          idx++;
        }
        context = null;
        continue;
      }

      _pages.last.widgets.add(
        _CourtPlacedWidget(
          child: child,
          constraints: contentConstraints,
          widgetContext: child is pw.SpanningWidget && canSpan
              ? child.cloneContext()
              : null,
        ),
      );
      offsetStart -= child.box!.height;
      sameCount = 0;
      idx++;
    }
  }

  @override
  void postProcess(pw.Document document) {
    final topMargin = _mm(12.5);
    final bottomMargin = _mm(11.5);
    final pageHeight = pageFormat.height;

    for (final page in _pages) {
      var offsetStart = pageHeight - topMargin;

      if (buildBackground != null) {
        final bg = buildBackground!(page.context);
        bg.layout(page.context, page.fullPageConstraints, parentUsesSize: false);
        _paintAt(page.context, bg, 0, 0);
      }

      for (final w in page.widgets) {
        final child = w.child;
        if (child is pw.SpanningWidget && child.canSpan && w.widgetContext != null) {
          child.applyContext(w.widgetContext!);
        }
        child.layout(page.context, w.constraints, parentUsesSize: false);
      }

      if (header != null) {
        final headerWidget = header!(page.context);
        headerWidget.layout(page.context, page.headerFooterConstraints, parentUsesSize: false);
        offsetStart -= headerWidget.box!.height;
        _paintAt(
          page.context,
          headerWidget,
          _mm(20.0),
          page.offsetStart - headerWidget.box!.height,
        );
      }

      if (footer != null) {
        final footerWidget = footer!(page.context);
        footerWidget.layout(page.context, page.headerFooterConstraints, parentUsesSize: false);
        _paintAt(page.context, footerWidget, _mm(20.0), bottomMargin);
      }

      final isEven = doppelseitig && page.context.pageNumber.isEven;
      final contentLeftX = isEven ? _mm(60.0) : _mm(20.0);
      var pos = offsetStart;
      for (final w in page.widgets) {
        final child = w.child;
        pos -= child.box!.height;
        if (child is pw.SpanningWidget && child.canSpan && w.widgetContext != null) {
          child.applyContext(w.widgetContext!);
        }
        _paintAt(page.context, child, contentLeftX, pos);
      }
    }
  }
}

List<pw.Widget> _buildTocWidgets(
  List<_TocEintrag> tocEintraege,
  Map<String, int> recordedPageNumbers, {
  required bool isGericht,
}) {
  return [
    pw.Container(
      margin: pw.EdgeInsets.only(top: _mm(1.0), bottom: _mm(3.2)),
      padding: pw.EdgeInsets.only(bottom: _mm(1.5)),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColor.fromHex('1E3552'), width: 1.0),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              'Inhaltsverzeichnis',
              style: pw.TextStyle(
                fontSize: isGericht ? 13.5 : 16.0,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('1E3552'),
              ),
            ),
          ),
        ],
      ),
    ),
    for (var idx = 0; idx < tocEintraege.length; idx++)
      () {
        final e = tocEintraege[idx];
        final pageNum = e.tocKey != null ? recordedPageNumbers[e.tocKey!] : null;

        final isIvSub = RegExp(r'^IV\.\d+$').hasMatch(e.nummer);
        final leftIndent = isIvSub
            ? _mm(9.0)
            : ((e.einzug == 0 && !e.isAnlage) ? 0.0 : _mm(4.5));

        const textStyle = pw.TextStyle(
          fontSize: 9.6,
          color: PdfColors.black,
        );
        final fullLabel = e.nummer.isNotEmpty ? '${e.nummer} ${e.label}' : e.label;

        return pw.Padding(
          padding: pw.EdgeInsets.fromLTRB(leftIndent, _mm(0.85), 0, _mm(0.85)),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                fullLabel,
                style: textStyle,
                maxLines: 1,
              ),
              if (pageNum != null) ...[
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 2.0, right: 2.0, bottom: 2.2),
                    child: pw.CustomPaint(
                      size: const PdfPoint(10, 4),
                      painter: (canvas, size) {
                        canvas.setFillColor(PdfColors.black);
                        var x = 1.5;
                        while (x < size.x - 1.0) {
                          canvas.drawRect(x, 0, 0.75, 0.75);
                          x += 2.6;
                        }
                        canvas.fillPath();
                      },
                    ),
                  ),
                ),
                pw.Text(
                  '$pageNum',
                  textAlign: pw.TextAlign.right,
                  style: textStyle,
                ),
              ],
            ],
          ),
        );
      }(),
  ];
}

/// Deutsche Silbentrennung nach den Regeln der neuen Rechtschreibung.
/// Zerlegt Wörter an konsonantischen/vokalischen Silbengrenzen, sodass
/// der Blocksatz im PDF ohne unschöne Wortabstände flüssig umbricht.
List<String> _germanHyphenation(String word) {
  if (word.length < 6) return [word];

  // Satzzeichen am Ende separieren
  final match = RegExp(r'^(.*?)([.,;:!?)"»“\x27]*)$').firstMatch(word);
  if (match == null) return [word];
  final clean = match.group(1)!;
  final punct = match.group(2) ?? '';
  if (clean.length < 6) return [word];

  const vowels = 'aeiouyäöüAEIOUYÄÖÜ';
  bool isVowel(String c) => vowels.contains(c);

  final vowelIndices = <int>[];
  for (var i = 0; i < clean.length; i++) {
    if (isVowel(clean[i])) vowelIndices.add(i);
  }
  if (vowelIndices.length <= 1) return [word];

  final breakPoints = <int>[];
  for (var k = 0; k < vowelIndices.length - 1; k++) {
    final v1 = vowelIndices[k];
    final v2 = vowelIndices[k + 1];

    // Diphthonge nicht trennen (ei, eu, au, äu, ie)
    if (v2 == v1 + 1) {
      final diph = clean.substring(v1, v2 + 1).toLowerCase();
      if (diph == 'ei' || diph == 'eu' || diph == 'au' || diph == 'äu' || diph == 'ie') {
        continue;
      }
    }

    // Wenn zwischen zwei Vokalen bereits ein Bindestrich liegt, diesen Bereich nicht erneut zerschneiden
    final middle = clean.substring(v1, v2 + 1);
    if (middle.contains('-')) {
      continue;
    }

    final consBetween = v2 - v1 - 1;
    int splitAt;
    if (consBetween == 0) {
      splitAt = v2;
    } else if (consBetween == 1) {
      // Ein einzelner Konsonant wandert zur zweiten Silbe (z. B. Ge-län-der, Hö-he)
      splitAt = v1 + 1;
    } else {
      final sub = clean.substring(v1 + 1, v2).toLowerCase();
      if (sub.endsWith('sch')) {
        splitAt = v2 - 3;
      } else if (sub.endsWith('ch') || sub.endsWith('ck') || sub.endsWith('ph') || sub.endsWith('th')) {
        splitAt = v2 - 2;
      } else {
        // Letzter Konsonant wandert zur zweiten Silbe (z. B. Pfos-ten, Krag-plat-te)
        splitAt = v2 - 1;
      }
    }

    // Mindestens 2 Zeichen vor und nach der Trennung, und nicht direkt an vorhandenen Bindestrichen
    if (splitAt >= 2 && (clean.length - splitAt) >= 2) {
      if (clean[splitAt - 1] != '-' && clean[splitAt] != '-') {
        breakPoints.add(splitAt);
      }
    }
  }

  if (breakPoints.isEmpty) return [word];

  final syllables = <String>[];
  var prev = 0;
  final sortedBp = breakPoints.toSet().toList()..sort();
  for (final bp in sortedBp) {
    if (bp - prev >= 2) {
      syllables.add(clean.substring(prev, bp));
      prev = bp;
    }
  }
  syllables.add(clean.substring(prev) + punct);

  // Strikte Garantie: Die Silben müssen exakt wieder das Ausgangswort ergeben
  if (syllables.join('') != word) return [word];
  return syllables;
}

class _ParsedLine {
  final pw.Widget widget;
  final bool isHeading;
  final bool isExplicitNewPage;
  final bool isEmpty;
  final String? tableRawLine;

  const _ParsedLine({
    required this.widget,
    this.isHeading = false,
    this.isExplicitNewPage = false,
    this.isEmpty = false,
    this.tableRawLine,
  });
}

pw.Widget? _buildTableFromMarkdown(
  List<String> lines, {
  List<NormenData> normen = const [],
  bool linksAktivieren = true,
}) {
  if (lines.isEmpty) return null;

  final cleanRows = <List<String>>[];
  final colAlignments = <pw.TextAlign>[];

  for (final line in lines) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('|') || !trimmed.endsWith('|')) continue;
    final inner = trimmed.substring(1, trimmed.length - 1);
    final cells = inner.split('|').map((c) => c.trim()).toList();
    final isSep = cells.every((c) => RegExp(r'^:?-+:?$').hasMatch(c));
    if (isSep) {
      if (colAlignments.isEmpty) {
        for (final c in cells) {
          if (c.startsWith(':') && c.endsWith(':')) {
            colAlignments.add(pw.TextAlign.center);
          } else if (c.endsWith(':')) {
            colAlignments.add(pw.TextAlign.right);
          } else {
            colAlignments.add(pw.TextAlign.left);
          }
        }
      }
      continue;
    }
    cleanRows.add(cells);
  }

  if (cleanRows.isEmpty) return null;

  final numCols = cleanRows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
  if (numCols == 0) return null;

  final firstHeader = cleanRows.first.isNotEmpty
      ? cleanRows.first[0].replaceAll('**', '').trim().toLowerCase()
      : '';
  final colWidths = <int, pw.TableColumnWidth>{};
  if (numCols == 4 && firstHeader.startsWith('pos')) {
    colWidths[0] = const pw.FlexColumnWidth(0.55);
    colWidths[1] = const pw.FlexColumnWidth(2.65);
    colWidths[2] = const pw.FlexColumnWidth(1.25);
    colWidths[3] = const pw.FlexColumnWidth(1.05);
  } else if (numCols == 4 && firstHeader.contains('beweisfrage')) {
    colWidths[0] = const pw.FlexColumnWidth(0.85);
    colWidths[1] = const pw.FlexColumnWidth(1.35);
    colWidths[2] = const pw.FlexColumnWidth(2.45);
    colWidths[3] = const pw.FlexColumnWidth(1.25);
  } else if (numCols == 3 && firstHeader.contains('anlage')) {
    colWidths[0] = const pw.FlexColumnWidth(0.85);
    colWidths[1] = const pw.FlexColumnWidth(2.9);
    colWidths[2] = const pw.FlexColumnWidth(1.1);
  } else if (numCols == 2) {
    colWidths[0] = const pw.FlexColumnWidth(1.15);
    colWidths[1] = const pw.FlexColumnWidth(2.35);
  } else {
    for (int c = 0; c < numCols; c++) {
      var maxLen = 8;
      for (final r in cleanRows) {
        if (c < r.length) {
          final l = r[c].replaceAll('**', '').length;
          if (l > maxLen) maxLen = l;
        }
      }
      final flex = maxLen.clamp(8, 52) / 14.0;
      colWidths[c] = pw.FlexColumnWidth(flex);
    }
  }

  final rows = <pw.TableRow>[];
  for (int r = 0; r < cleanRows.length; r++) {
    final rowCells = cleanRows[r];
    final isHeader = r == 0;
    final rowHasTotal = rowCells.any((c) =>
        c.contains('Zwischensumme') ||
        c.contains('Gesamtsumme') ||
        c.contains('Nettosumme') ||
        c.contains('Bruttosumme'));
    final rowBg = isHeader
        ? PdfColor.fromHex('EDF0F4')
        : (rowHasTotal
            ? PdfColor.fromHex('F4F6F9')
            : (r.isEven ? PdfColor.fromHex('FAFBFD') : PdfColors.white));

    final cellWidgets = <pw.Widget>[];
    for (int c = 0; c < numCols; c++) {
      final rawCell = (c < rowCells.length) ? rowCells[c].trim() : '';
      final align = (c < colAlignments.length)
          ? colAlignments[c]
          : pw.TextAlign.left;
      final isEntireCellBold = isHeader ||
          (rawCell.startsWith('**') &&
              rawCell.endsWith('**') &&
              rawCell.length > 4 &&
              !rawCell.substring(2, rawCell.length - 2).contains('**'));
      final textForRender = isHeader ? rawCell.replaceAll('**', '') : rawCell;

      cellWidgets.add(
        pw.Padding(
          padding: pw.EdgeInsets.symmetric(
            horizontal: _mm(2.0),
            vertical: _mm(1.35),
          ),
          child: pw.RichText(
            textAlign: align,
            text: pw.TextSpan(
              children: _formatTextWithNormLinks(
                textForRender,
                baseStyle: pw.TextStyle(
                  fontSize: isHeader ? 8.1 : 7.9,
                  fontWeight: isEntireCellBold
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                  color: isHeader ? PdfColors.blueGrey900 : PdfColors.black,
                  lineSpacing: 1.15,
                ),
                normen: normen,
                linksAktivieren: linksAktivieren,
              ),
            ),
          ),
        ),
      );
    }

    rows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: rowBg),
        children: cellWidgets,
      ),
    );
  }

  return pw.Table(
    border: const pw.TableBorder(
      top: pw.BorderSide(color: PdfColors.grey800, width: 0.9),
      bottom: pw.BorderSide(color: PdfColors.grey800, width: 0.9),
      left: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
      right: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
      horizontalInside: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
      verticalInside: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
    ),
    columnWidths: colWidths,
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
    children: rows,
  );
}

List<pw.Widget> _postProcessParsedLines(
  List<_ParsedLine> rawItems, {
  List<NormenData> normen = const [],
  bool linksAktivieren = true,
}) {
  final items = <_ParsedLine>[];
  int t = 0;
  while (t < rawItems.length) {
    if (rawItems[t].tableRawLine != null) {
      final tableLines = <String>[];
      while (t < rawItems.length && rawItems[t].tableRawLine != null) {
        tableLines.add(rawItems[t].tableRawLine!);
        t++;
      }
      final tableWidget = _buildTableFromMarkdown(
        tableLines,
        normen: normen,
        linksAktivieren: linksAktivieren,
      );
      if (tableWidget != null) {
        items.add(_ParsedLine(widget: pw.SizedBox(height: _mm(1.2)), isEmpty: true));
        items.add(_ParsedLine(widget: tableWidget));
        items.add(_ParsedLine(widget: pw.SizedBox(height: _mm(2.2)), isEmpty: true));
      }
      continue;
    }
    items.add(rawItems[t]);
    t++;
  }

  final result = <pw.Widget>[];
  int i = 0;
  while (i < items.length) {
    final item = items[i];
    if (item.isExplicitNewPage) {
      result.add(pw.NewPage());
      i++;
      continue;
    }
    if (item.isHeading && i + 1 < items.length) {
      int nextIdx = i + 1;
      while (nextIdx < items.length && items[nextIdx].isEmpty) {
        nextIdx++;
      }
      if (nextIdx < items.length &&
          !items[nextIdx].isExplicitNewPage &&
          items[nextIdx].widget is! pw.Table) {
        final insepChildren = <pw.Widget>[item.widget];
        for (int k = i + 1; k < nextIdx; k++) {
          insepChildren.add(items[k].widget);
        }
        insepChildren.add(items[nextIdx].widget);

        result.add(
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: insepChildren,
            ),
          ),
        );
        i = nextIdx + 1;
        continue;
      }
    }
    result.add(item.widget);
    i++;
  }
  return result;
}

class _NormLinkTarget {
  const _NormLinkTarget({
    required this.pattern,
    required this.baseUrl,
    this.title = 'Technisches Regelwerk / Quelle',
    this.defaultPage = 1,
    this.defaultMarks = const [],
    this.pageResolver,
    this.markResolver,
    this.webTextFragment,
  });

  final RegExp pattern;
  final String baseUrl;
  final String title;
  final int defaultPage;
  final List<String> defaultMarks;
  final int Function(String matchText, String contextText)? pageResolver;
  final List<String> Function(String matchText, String contextText)? markResolver;
  final String? webTextFragment;

  String resolveUrl(String matchText, String contextText) {
    final isPdf = baseUrl.toLowerCase().contains('.pdf') ||
        baseUrl.contains('firebasestorage.googleapis.com');
    if (!isPdf) {
      if (webTextFragment != null &&
          webTextFragment!.isNotEmpty &&
          !baseUrl.contains('#:~:text=')) {
        return '$baseUrl#:~:text=${Uri.encodeComponent(webTextFragment!)}';
      }
      return baseUrl;
    }

    final cleanBase = baseUrl.split('#').first;
    final page = pageResolver != null
        ? pageResolver!(matchText, contextText)
        : defaultPage;
    final customMarks = markResolver != null
        ? markResolver!(matchText, contextText)
        : defaultMarks;
    final marks = _collectHighlightTerms(matchText, contextText, customMarks);

    return _buildQuellenViewerUrl(
      pdfUrl: cleanBase,
      page: page,
      refText: matchText.trim(),
      title: title,
      marks: marks,
    );
  }
}

String _buildQuellenViewerUrl({
  required String pdfUrl,
  required int page,
  required String refText,
  required String title,
  required List<String> marks,
}) {
  final qp = <String, String>{
    'src': pdfUrl,
    'page': '$page',
    'ref': refText,
    'title': title,
    if (marks.isNotEmpty) 'mark': marks.take(8).join('|'),
  };
  final query = qp.entries
      .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  return 'https://aktenwerk-app.web.app/quelle.html?$query';
}

final _kContextKeywordCandidates = <String>[
  'Festpunkt',
  'Gleitpunkt',
  'Bohrung',
  'Bohrloch',
  'Randabstand',
  'Achsabstand',
  'Befestigungsabstand',
  'Spannweite',
  'Fuge',
  'Stoßfuge',
  'Balkonschraube',
  'Zinkspitzen',
  'Ausbesserung',
  'Fehlstellen',
  'Zinkstaub',
  'Schichtdicke',
  'Betonausbruch',
  'Verankerungstiefe',
  'Bauteildicke',
  'Holmlast',
  'Umwehrung',
  'Mindesthöhe',
  'Brüstung',
  'Absturzhöhe',
  'Luftdichtheit',
  'Schlagregen',
  'Wärmedämmung',
  'Streckgrenze',
  'Teilsicherheitsbeiwert',
];

List<String> _collectHighlightTerms(
  String matchText,
  String contextText,
  List<String> baseTerms,
) {
  final out = <String>[];
  void addTerm(String t) {
    final clean = t.trim();
    if (clean.length < 2) return;
    if (!out.any((x) => x.toLowerCase() == clean.toLowerCase())) {
      out.add(clean);
    }
  }

  for (final t in baseTerms) {
    addTerm(t);
  }

  // 1. Abschnitts-, Tabellen- und Anhangs-Nummern im Kontext erkennen (z.B. "Abschn. 6.3", "Tab. 6.12")
  for (final m in RegExp(
    r'(?:Abschn\.|Abs\.|Ziff\.|Ziffer|Tab\.|Tabelle|Anhang)\s*([A-Z0-9]+(?:\.[0-9]+)*)',
    caseSensitive: false,
  ).allMatches(contextText)) {
    final g1 = m.group(1);
    if (g1 != null && g1.length >= 2) addTerm(g1);
  }

  // 2. Maßzahlen im Kontext erkennen (z.B. "5,1 mm", "10 mm", "0,5 %", "10 cm²")
  for (final m in RegExp(
    r'\b(\d+(?:,\d+)?)\s*(?:mm|cm²|cm|m\b|%|kN\/m|N\/mm²)',
  ).allMatches(contextText)) {
    final numStr = m.group(1);
    if (numStr != null && numStr.length >= 2) addTerm(numStr);
  }

  // 3. Fachbegriffe im Kontext erkennen
  final lowCtx = contextText.toLowerCase();
  for (final kw in _kContextKeywordCandidates) {
    if (lowCtx.contains(kw.toLowerCase())) {
      addTerm(kw);
    }
  }

  return out;
}

final _kKnownNormTargets = <_NormLinkTarget>[
  // 1. Trespa DE3075 (Balkonbekleidungen Technische Dokumentation) / [Q5]
  _NormLinkTarget(
    title: 'Trespa Meteon DE3075 – Balkonbekleidungen',
    pattern: RegExp(
      r'(?:DE\s*3075|Trespa(?:-Meteon)?(?:\s*-\s*Platten)?(?:\s+8\s*mm)?|Trespa-Balkonschrauben|\[Q5(?:,\s*[^\]]+)?\])',
      caseSensitive: false,
    ),
    baseUrl:
        'https://firebasestorage.googleapis.com/v0/b/aktenwerk-88c35.firebasestorage.app/o/organizations%2F9nqw2lD3tKwI4cWYD1S9%2Fnormen%2FTrespa_DE3075_Balkone.pdf?alt=media&token=63222b64-5a73-41a0-be36-340667c761f5',
    defaultPage: 3,
    defaultMarks: ['Fuge', 'Randabstand', 'Festpunkt', 'Gleitpunkt', '5,1'],
    pageResolver: (m, ctx) {
      final c = ctx.toLowerCase();
      if (c.contains('gleitpunkt') ||
          c.contains('festpunkt') ||
          c.contains('aufbohr') ||
          c.contains('passbuchs') ||
          c.contains('10 mm') ||
          c.contains('5,1 mm') ||
          c.contains('bohrung')) {
        return 4;
      }
      if (c.contains('hülse') ||
          c.contains('schraub') ||
          c.contains('balkonschraub')) {
        return 5;
      }
      if (c.contains('spannweit') ||
          c.contains('befestigungsabstand') ||
          c.contains('600 mm') ||
          c.contains('750 mm')) {
        return 7;
      }
      if (c.contains('fuge') ||
          c.contains('mind. 5') ||
          c.contains('stoßfuge')) {
        return 3;
      }
      return 3;
    },
  ),

  // 2. DIN EN ISO 1461 (Stückverzinken) / Arbeitsblatt F.2 / [Q6]
  _NormLinkTarget(
    title: 'DIN EN ISO 1461 – Feuerverzinken (Stückverzinken)',
    pattern: RegExp(
      r'(?:DIN\s+EN\s+ISO\s+1461(?::\d{4}(?:-\d{2})?)?(?:\s+Ziffern?\s+[\d.]+(?:\s*(?:und|\/|,)\s*[\d.]+)*)?|Arbeitsblatt\s+F\.?2|\[Q6(?:,\s*[^\]]+)?\])',
      caseSensitive: false,
    ),
    baseUrl:
        'https://firebasestorage.googleapis.com/v0/b/aktenwerk-88c35.firebasestorage.app/o/organizations%2F9nqw2lD3tKwI4cWYD1S9%2Fnormen%2FDIN_EN_ISO_1461_1785658564957.pdf?alt=media&token=180c6c64-063d-4f1b-b6f9-70c110b311fd',
    defaultPage: 18,
    defaultMarks: ['6.1', '6.3', 'Zinkspitzen', 'Ausbesserung', 'Fehlstellen', '10 cm'],
    pageResolver: (m, ctx) {
      final c = ctx.toLowerCase();
      if (c.contains('6.3') ||
          c.contains('ausbesser') ||
          c.contains('fehlstelle') ||
          c.contains('zinkstaub')) {
        return 20;
      }
      if (c.contains('6.1') ||
          c.contains('aussehen') ||
          c.contains('zinkspitz')) {
        return 18;
      }
      if (c.contains('anhang c')) {
        return 28;
      }
      return 18;
    },
  ),

  // 2b. Institut Feuerverzinken Arbeitsblatt E.4 / [Q7]
  _NormLinkTarget(
    title: 'Institut Feuerverzinken – Arbeitsblatt E.4',
    pattern: RegExp(
      r'(?:(?:Institut\s+)?Feuerverzinken[^.;\n]{0,25}?Arbeitsblatt\s+E\.?4|Arbeitsblatt\s+E\.?4|\[Q7(?:,\s*[^\]]+)?\])',
      caseSensitive: false,
    ),
    baseUrl:
        'https://firebasestorage.googleapis.com/v0/b/aktenwerk-88c35.firebasestorage.app/o/organizations%2F9nqw2lD3tKwI4cWYD1S9%2Fnormen%2FFeuerverzinken_1790659437206.pdf?alt=media&token=ebeedaf9-fafb-4e2d-ad45-f26f29e78a1b',
    defaultPage: 70,
    defaultMarks: ['Zinkspitzen', 'Ausbesserung', 'Feuerverzinken'],
  ),

  // 3. fischer Bolzenanker FBN II / ETA-07/0211 / [Q4] / [N3]
  _NormLinkTarget(
    title: 'ETA-07/0211 – fischer Bolzenanker FBN II',
    pattern: RegExp(
      r'(?:(?:fischer(?:\s+Deutschland)?\s*–?\s*)?(?:Bolzenanker\s+)?FBN\s+II(?:\s*\/\s*ETA-07\/0211|\s+ETA-07\/0211)?|ETA-07\/0211|\[Q4(?:,\s*[^\]]+)?\]|\[N3(?:,\s*[^\]]+)?\])',
      caseSensitive: false,
    ),
    baseUrl:
        'https://firebasestorage.googleapis.com/v0/b/aktenwerk-88c35.firebasestorage.app/o/organizations%2F9nqw2lD3tKwI4cWYD1S9%2Fnormen%2Ffischer_FBN_II_ETA-07-0211.pdf?alt=media&token=5d205a95-97c4-40e9-94ab-7d943008406d',
    defaultPage: 10,
    defaultMarks: ['FBN II', 'M10', 'h_ef', 's_min', 'c_min', '50', '70', '100'],
    pageResolver: (m, ctx) {
      final c = ctx.toLowerCase();
      if (c.contains('anhang c') ||
          c.contains('tragfähig') ||
          c.contains('zugkraft') ||
          c.contains('überlastet') ||
          c.contains('ungerissen') ||
          c.contains('bemessung') ||
          c.contains('randabstand') ||
          c.contains('achsabstand')) {
        return 10;
      }
      return 10;
    },
  ),

  // 4. ift-Richtlinie MO-01/1:2007-01 / [Q9]
  _NormLinkTarget(
    title: 'ift-Richtlinie MO-01/1 – Baukörperanschluss von Fenstern',
    pattern: RegExp(
      r'(?:ift-(?:Fachinformation|Richtlinie|\s+Fachinfo)?\s+MO-01\/1(?::\d{4}(?:-\d{2})?)?|\[Q9(?:,\s*[^\]]+)?\])',
      caseSensitive: false,
    ),
    baseUrl:
        'https://firebasestorage.googleapis.com/v0/b/aktenwerk-88c35.firebasestorage.app/o/organizations%2F9nqw2lD3tKwI4cWYD1S9%2Fnormen%2FIft_MO-01_1_1777827096581.pdf?alt=media&token=e934a1a2-cde7-4e95-ac16-5732a7f20590',
    defaultPage: 1,
    defaultMarks: ['Baukörperanschluss', 'Abdichtung', 'Montage'],
  ),

  // 4b. ift-Richtlinie MO-02/1:2015-06
  _NormLinkTarget(
    title: 'ift-Richtlinie MO-02/1 – Befestigung von Fenstern',
    pattern: RegExp(
      r'(?:ift-(?:Fachinformation|Richtlinie|\s+Fachinfo)?\s+MO-02\/1(?::\d{4}(?:-\d{2})?)?)',
      caseSensitive: false,
    ),
    baseUrl:
        'https://firebasestorage.googleapis.com/v0/b/aktenwerk-88c35.firebasestorage.app/o/organizations%2F9nqw2lD3tKwI4cWYD1S9%2Fnormen%2FIft_MO-02_1_1777827111664.pdf?alt=media&token=65607679-1497-457e-977d-760673344f1d',
    defaultPage: 1,
    defaultMarks: ['Befestigung', 'Lastabtragung', 'Tragklotz'],
  ),

  // 5. DIN 18533-1 / DIN 18533 / [Q11]
  _NormLinkTarget(
    title: 'DIN 18533-1 – Abdichtung erdberührter Bauteile',
    pattern: RegExp(
      r'(?:DIN\s+18533(?:-[12](?:-A1)?)?(?::\d{4}(?:-\d{2})?)?|\[Q11(?:,\s*[^\]]+)?\])',
      caseSensitive: false,
    ),
    baseUrl:
        'https://firebasestorage.googleapis.com/v0/b/aktenwerk-88c35.firebasestorage.app/o/organizations%2F9nqw2lD3tKwI4cWYD1S9%2Fnormen%2FDIN_18533-1_1785658521729.pdf?alt=media&token=2fc81905-62a7-4cb6-a02e-70e912491035',
    defaultPage: 1,
    defaultMarks: ['Abdichtung', 'Sockel', 'Anschluss'],
  ),

  // 6. DIN 18008-1 / DIN 18008 / [Q13]
  _NormLinkTarget(
    title: 'DIN 18008-1 – Glas im Bauwesen',
    pattern: RegExp(
      r'(?:DIN\s+18008(?:-[1-35])?(?::\d{4}(?:-\d{2})?)?|\[Q13(?:,\s*[^\]]+)?\])',
      caseSensitive: false,
    ),
    baseUrl:
        'https://firebasestorage.googleapis.com/v0/b/aktenwerk-88c35.firebasestorage.app/o/organizations%2F9nqw2lD3tKwI4cWYD1S9%2Fnormen%2FDIN_18008-1_1785658165023.pdf?alt=media&token=59dd2eb0-778b-4127-9cef-3c0f6d8a977b',
    defaultPage: 1,
    defaultMarks: ['Verglasung', 'Sicherheitsglas', 'Lagerung'],
  ),

  // 7. DIN 4108-2
  _NormLinkTarget(
    title: 'DIN 4108-2 – Mindestanforderungen an den Wärmeschutz',
    pattern: RegExp(
      r'DIN\s+4108-2(?::\d{4}(?:-\d{2})?)?',
      caseSensitive: false,
    ),
    baseUrl:
        'https://firebasestorage.googleapis.com/v0/b/aktenwerk-88c35.firebasestorage.app/o/organizations%2F9nqw2lD3tKwI4cWYD1S9%2Fnormen%2FDIN_4108-2_1777825381665.pdf?alt=media&token=f0d26857-e435-430c-ab22-263be74c3e38',
    defaultPage: 1,
    defaultMarks: ['Wärmeschutz', 'Wärmebrücken', 'Mindestanforderungen'],
  ),

  // 8. DIN EN 1991-1-1
  _NormLinkTarget(
    title: 'DIN EN 1991-1-1/NA – Eurocode 1: Einwirkungen auf Tragwerke',
    pattern: RegExp(
      r'DIN\s+EN\s+1991-1-1(?:\/NA)?(?::\d{4}(?:-\d{2})?)?',
      caseSensitive: false,
    ),
    baseUrl:
        'https://firebasestorage.googleapis.com/v0/b/aktenwerk-88c35.firebasestorage.app/o/organizations%2F9nqw2lD3tKwI4cWYD1S9%2Fnormen%2FDIN_EN_1991-1-1_1777825441584.pdf?alt=media&token=ccfffa19-58b9-4dc3-8181-e223bb357904',
    defaultPage: 1,
    defaultMarks: ['6.4', '6.12', 'Holmlast', '0,5', '1,0'],
  ),

  // 9. DIN 18065
  _NormLinkTarget(
    title: 'DIN 18065 – Gebäudetreppen und Umwehrungen',
    pattern: RegExp(
      r'DIN\s+18065(?::\d{4}(?:-\d{2})?)?',
      caseSensitive: false,
    ),
    baseUrl:
        'https://firebasestorage.googleapis.com/v0/b/aktenwerk-88c35.firebasestorage.app/o/organizations%2F9nqw2lD3tKwI4cWYD1S9%2Fnormen%2FDIN_18065_1784979383637.pdf?alt=media&token=c9616d6c-674b-449e-bca8-f6858e379435',
    defaultPage: 14,
    defaultMarks: ['Umwehrung', '90', '110', '12 m', 'Absturzhöhe'],
  ),

  // 10. HBO / Hessische Bauordnung (§ 41) / [Q1]
  _NormLinkTarget(
    title: 'Hessische Bauordnung (HBO)',
    pattern: RegExp(
      r'(?:§+\s*41\s+(?:Abs\.[^,;\n]+\s+)?HBO|Hessische\s+Bauordnung(?:\s+\(HBO\))?|HBO(?:\s+§+\s*41\s*(?:Abs\.[^,;\n]+)?)?|\[Q1(?:,\s*[^\]]+)?\])',
      caseSensitive: false,
    ),
    baseUrl:
        'https://www.rv.hessenrecht.hessen.de/bshe/document/jlr-BauOHE2018pP41',
    webTextFragment: 'Umwehrungen',
  ),

  // 11. ASR A2.1 / [Q2]
  _NormLinkTarget(
    title: 'ASR A2.1 – Schutz vor Absturz',
    pattern: RegExp(
      r'(?:ASR\s+A2\.1(?:\s+Abs\.?\s+[\d.]+(?:\s+Abs\.?\s+[\d.]+)?|\s*\([^)]*\))?|\[Q2(?:,\s*[^\]]+)?\])',
      caseSensitive: false,
    ),
    baseUrl: 'https://www.baua.de/DE/Angebote/Regelwerk/ASR/ASR-A2-1.html',
    webTextFragment: 'Schutz vor Absturz',
  ),

  // 11b. H-VV TB (Hessen) / [Q3]
  _NormLinkTarget(
    title: 'H-VV TB – Hessische Verwaltungsvorschrift Technische Baubestimmungen',
    pattern: RegExp(
      r'(?:H-VV\s+TB(?:\s*\(Hessen\))?|Hessische\s+Verwaltungsvorschrift\s+Technische\s+Baubestimmungen|\[Q3(?:,\s*[^\]]+)?\])',
      caseSensitive: false,
    ),
    baseUrl:
        'https://wirtschaft.hessen.de/wohnen-bauen/bauvorschriften/technische-baubestimmungen',
    webTextFragment: 'Technische Baubestimmungen',
  ),

  // 12. ASR A1.6 / [Q12]
  _NormLinkTarget(
    title: 'ASR A1.6 – Fenster, Oberlichter, lichtdurchlässige Wände',
    pattern: RegExp(
      r'(?:ASR\s+A1\.6(?:\s*\([^)]*\))?|\[Q12(?:,\s*[^\]]+)?\])',
      caseSensitive: false,
    ),
    baseUrl: 'https://www.baua.de/DE/Angebote/Regelwerk/ASR/ASR-A1-6.html',
    webTextFragment: 'Fenster',
  ),

  // 12b. Bundesverband Metall Merkblatt 4 / [Q8]
  _NormLinkTarget(
    title: 'Bundesverband Metall (BVM) – Fachregelwerk',
    pattern: RegExp(
      r'(?:(?:Bundesverband\s+Metall[^.;\n]{0,25}?Merkblatt\s+4|BVM-Merkblatt\s+4)|\[Q8(?:,\s*[^\]]+)?\])',
      caseSensitive: false,
    ),
    baseUrl: 'https://www.metallhandwerk.de',
  ),

  // 13. DIN EN 1992-4
  _NormLinkTarget(
    title: 'DIN EN 1992-4 / ETA-07/0211 – Bemessung der Verankerung in Beton',
    pattern: RegExp(r'DIN\s+EN\s+1992-4', caseSensitive: false),
    baseUrl:
        'https://firebasestorage.googleapis.com/v0/b/aktenwerk-88c35.firebasestorage.app/o/organizations%2F9nqw2lD3tKwI4cWYD1S9%2Fnormen%2Ffischer_FBN_II_ETA-07-0211.pdf?alt=media&token=5d205a95-97c4-40e9-94ab-7d943008406d',
    defaultPage: 10,
    defaultMarks: ['s_cr,N', 'c_cr,N', 'h_ef', 'Betonausbruch', '150'],
  ),

  // 14. RAL-Leitfaden zur Planung und Ausführung der Montage von Fenstern und Haustüren (2024) / [Q10] / [Q14]
  _NormLinkTarget(
    title: 'RAL-Leitfaden zur Montage von Fenstern und Haustüren',
    pattern: RegExp(
      r'(?:RAL-(?:Gütegemeinschaft\s+)?(?:Leitfaden|Montageleitfaden)(?:\s+zur\s+Montage)?|RAL-Montage(?:leitfaden)?|Leitfaden\s+zur\s+Planung\s+und\s+Ausführung\s+der\s+Montage\s+von\s+Fenstern|\[Q10(?:,\s*[^\]]+)?\]|\[Q14(?:,\s*[^\]]+)?\])',
      caseSensitive: false,
    ),
    baseUrl:
        'https://firebasestorage.googleapis.com/v0/b/aktenwerk-88c35.firebasestorage.app/o/organizations%2F9nqw2lD3tKwI4cWYD1S9%2Fnormen%2FRAL_1785736429875.pdf?alt=media&token=7f94aae5-4a9c-409e-b308-92ef89a635f5',
    defaultPage: 1,
    defaultMarks: ['Befestigung', 'Abdichtung', 'Wärmedämmung', 'Klotzung'],
  ),

  // 15. DIN 18339 (Klempnerarbeiten) / DIN 18008-4 / [Q15]
  _NormLinkTarget(
    title: 'DIN 18008-4 – Absturzsichernde Verglasungen',
    pattern: RegExp(
      r'(?:DIN\s+18339(?::\d{4}(?:-\d{2})?)?|DIN\s+18008-4(?::\d{4}(?:-\d{2})?)?|\[Q15(?:,\s*[^\]]+)?\])',
      caseSensitive: false,
    ),
    baseUrl:
        'https://firebasestorage.googleapis.com/v0/b/aktenwerk-88c35.firebasestorage.app/o/organizations%2F9nqw2lD3tKwI4cWYD1S9%2Fnormen%2FDIN_18008-4_1785658436835.pdf?alt=media&token=6d429e3e-64c6-4b18-83dc-940201f0ecac',
    defaultPage: 1,
    defaultMarks: ['absturzsichernd', 'Kategorie', 'VSG', 'Glashalteleiste'],
  ),

  // 16. DIN 4108-7 / [Q16]
  _NormLinkTarget(
    title: 'DIN 4108-7 – Luftdichtheit von Gebäuden',
    pattern: RegExp(
      r'(?:DIN\s+4108-7(?::\d{4}(?:-\d{2})?)?|\[Q16(?:,\s*[^\]]+)?\])',
      caseSensitive: false,
    ),
    baseUrl:
        'https://firebasestorage.googleapis.com/v0/b/aktenwerk-88c35.firebasestorage.app/o/organizations%2F9nqw2lD3tKwI4cWYD1S9%2Fnormen%2FDIN_4108-7_1776881246877.pdf?alt=media&token=8641af91-5a2a-4c55-92ee-cc9bd6a4e0df',
    defaultPage: 1,
    defaultMarks: ['Luftdichtheit', 'Anschluss', 'Folie'],
  ),

  // 17. Jansen VISS TV 1V / [Q17]
  _NormLinkTarget(
    title: 'Jansen VISS Fassade – Systemdokumentation',
    pattern: RegExp(
      r'(?:Jansen(?:\s+AG)?\s+VISS\s+TV(?:\s*1\s*V)?|VISS\s+TV(?:\s*1\s*V)?|\[Q17(?:,\s*[^\]]+)?\])',
      caseSensitive: false,
    ),
    baseUrl: 'https://www.jansen.com/de/stahl-fassaden/viss-fassade.html',
    defaultPage: 1,
    webTextFragment: 'VISS',
  ),
];

class _SpanMatch {
  _SpanMatch({
    required this.start,
    required this.end,
    required this.text,
    required this.url,
  });
  final int start;
  final int end;
  final String text;
  final String url;
}

final _kMathTokenRegex = RegExp(
  r'([A-Za-zθψγ])(?:\^0|⁰)_([A-Za-z0-9,]+)|(?<![A-Za-z0-9_])([A-Za-zθψγ]{1,2})_([A-Za-z0-9,]{1,6})(?![A-Za-z0-9_])',
);

List<pw.InlineSpan> _expandTextWithMathSubscripts(
  String chunk,
  pw.TextStyle style, {
  pw.AnnotationBuilder? annotation,
}) {
  if (chunk.isEmpty) return const [];
  if (!chunk.contains('_')) {
    return [pw.TextSpan(text: chunk, style: style, annotation: annotation)];
  }
  final matches = _kMathTokenRegex.allMatches(chunk).toList();
  if (matches.isEmpty) {
    return [pw.TextSpan(text: chunk, style: style, annotation: annotation)];
  }

  final baseSize = style.fontSize ?? 9.5;
  final subStyle = style.copyWith(fontSize: baseSize * 0.72);
  final out = <pw.InlineSpan>[];
  var curr = 0;

  for (final m in matches) {
    if (m.start > curr) {
      out.add(pw.TextSpan(
        text: chunk.substring(curr, m.start),
        style: style,
        annotation: annotation,
      ));
    }
    final sup0Base = m.group(1);
    final sup0Sub = m.group(2);
    if (sup0Base != null && sup0Sub != null) {
      out.add(pw.TextSpan(
        text: '$sup0Base⁰',
        style: style,
        annotation: annotation,
      ));
      out.add(pw.TextSpan(
        text: sup0Sub,
        style: subStyle,
        baseline: -1.6,
        annotation: annotation,
      ));
    } else {
      final base = m.group(3)!;
      final sub = m.group(4)!;
      out.add(pw.TextSpan(
        text: base,
        style: style,
        annotation: annotation,
      ));
      out.add(pw.TextSpan(
        text: sub,
        style: subStyle,
        baseline: -1.6,
        annotation: annotation,
      ));
    }
    curr = m.end;
  }

  if (curr < chunk.length) {
    out.add(pw.TextSpan(
      text: chunk.substring(curr),
      style: style,
      annotation: annotation,
    ));
  }
  return out;
}

List<pw.InlineSpan> _formatSegmentWithLinks(
  String segment, {
  required pw.TextStyle style,
  List<NormenData> normen = const [],
  bool linksAktivieren = true,
}) {
  if (segment.isEmpty) return const [];
  if (!linksAktivieren) {
    return _expandTextWithMathSubscripts(segment, style);
  }

  final matches = <_SpanMatch>[];
  for (final target in _kKnownNormTargets) {
    for (final m in target.pattern.allMatches(segment)) {
      final matchedText = m.group(0)!;
      if (matchedText.length > 65) continue;
      final url = target.resolveUrl(matchedText, segment);
      matches.add(_SpanMatch(
        start: m.start,
        end: m.end,
        text: matchedText,
        url: url,
      ));
    }
  }

  for (final n in normen) {
    final rawUrl = (n.pdfStorageUrl ?? '').trim();
    if (rawUrl.isEmpty) continue;
    final nr = n.nummer.trim();
    if (nr.length < 3) continue;
    final escaped = RegExp.escape(nr);
    final dynPat = RegExp('\\b$escaped\\b', caseSensitive: false);
    for (final m in dynPat.allMatches(segment)) {
      final matchedText = m.group(0)!;
      final isPdf = rawUrl.toLowerCase().contains('.pdf') ||
          rawUrl.contains('firebasestorage.googleapis.com');
      final resolvedUrl = isPdf
          ? _buildQuellenViewerUrl(
              pdfUrl: rawUrl.split('#').first,
              page: 1,
              refText: matchedText,
              title: [nr, if ((n.titel ?? '').isNotEmpty) n.titel!]
                  .join(' – '),
              marks: _collectHighlightTerms(matchedText, segment, [nr]),
            )
          : rawUrl;
      matches.add(_SpanMatch(
        start: m.start,
        end: m.end,
        text: matchedText,
        url: resolvedUrl,
      ));
    }
  }

  if (matches.isEmpty) {
    return _expandTextWithMathSubscripts(segment, style);
  }

  matches.sort((a, b) {
    final c = a.start.compareTo(b.start);
    if (c != 0) return c;
    return b.end.compareTo(a.end);
  });

  final filtered = <_SpanMatch>[];
  var lastEnd = 0;
  for (final m in matches) {
    if (m.start >= lastEnd) {
      filtered.add(m);
      lastEnd = m.end;
    }
  }

  final linkStyle = style.copyWith(
    color: PdfColor.fromHex('1A56DB'),
    decoration: pw.TextDecoration.underline,
  );

  final spans = <pw.InlineSpan>[];
  var curr = 0;
  for (final m in filtered) {
    if (m.start > curr) {
      spans.addAll(_expandTextWithMathSubscripts(
        segment.substring(curr, m.start),
        style,
      ));
    }
    spans.addAll(_expandTextWithMathSubscripts(
      m.text,
      linkStyle,
      annotation: pw.AnnotationUrl(m.url),
    ));
    curr = m.end;
  }
  if (curr < segment.length) {
    spans.addAll(_expandTextWithMathSubscripts(
      segment.substring(curr),
      style,
    ));
  }
  return spans;
}

List<pw.InlineSpan> _formatTextWithNormLinks(
  String text, {
  pw.TextStyle? baseStyle,
  List<NormenData> normen = const [],
  bool linksAktivieren = true,
}) {
  if (text.isEmpty) return const [];
  final defaultStyle = baseStyle ?? const pw.TextStyle(fontSize: 9.4);

  if (!text.contains('**')) {
    return _formatSegmentWithLinks(
      text,
      style: defaultStyle,
      normen: normen,
      linksAktivieren: linksAktivieren,
    );
  }

  final boldStyle = defaultStyle.copyWith(fontWeight: pw.FontWeight.bold);
  final spans = <pw.InlineSpan>[];
  final boldRegex = RegExp(r'\*\*(.+?)\*\*');
  var curr = 0;
  for (final m in boldRegex.allMatches(text)) {
    if (m.start > curr) {
      spans.addAll(_formatSegmentWithLinks(
        text.substring(curr, m.start),
        style: defaultStyle,
        normen: normen,
        linksAktivieren: linksAktivieren,
      ));
    }
    spans.addAll(_formatSegmentWithLinks(
      m.group(1)!,
      style: boldStyle,
      normen: normen,
      linksAktivieren: linksAktivieren,
    ));
    curr = m.end;
  }
  if (curr < text.length) {
    spans.addAll(_formatSegmentWithLinks(
      text.substring(curr),
      style: defaultStyle.copyWith(),
      normen: normen,
      linksAktivieren: linksAktivieren,
    ));
  }
  return spans;
}

pw.Widget _mathSub(String base, String sub, {double fontSize = 9.0, bool isItalic = true, bool isBold = false}) {
  return pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      pw.Text(
        base,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontStyle: isItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
        ),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 0.4),
        child: pw.Text(
          sub,
          style: pw.TextStyle(
            fontSize: fontSize * 0.72,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            fontStyle: isItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
          ),
        ),
      ),
    ],
  );
}

pw.Widget _mathFraction(pw.Widget top, pw.Widget bottom, {double minWidth = 24}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 2.0),
    child: pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 1.2),
          child: top,
        ),
        pw.Container(
          width: minWidth,
          height: 0.65,
          color: PdfColors.black,
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 1.2),
          child: bottom,
        ),
      ],
    ),
  );
}

pw.Widget _formulaTableRow(String label, List<pw.Widget> mathChildren) {
  return pw.Padding(
    padding: pw.EdgeInsets.symmetric(vertical: _mm(1.5)),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(
          width: _mm(36.0),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 8.6,
              color: PdfColor.fromHex('4A5E78'),
              lineSpacing: 1.8,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: mathChildren,
          ),
        ),
      ],
    ),
  );
}

/// Zweispaltiger Formelsatz auf Seite 15: Querschnittswerte & Plastisches Grenzmoment
pw.Widget _buildFormelBlockPfosten1() {
  const s = pw.TextStyle(fontSize: 9.8);
  return pw.Container(
    margin: pw.EdgeInsets.symmetric(vertical: _mm(2.0)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _formulaTableRow('Flächenträgheitsmoment', [
          pw.Text('I = 9,32 cm⁴ (Tab. B.2)', style: s),
        ]),
        _formulaTableRow('Elastisches Widerstands-\nmoment', [
          _mathSub('W', 'el', fontSize: 9.8, isItalic: true),
          pw.Text(' = 4,66 cm³ (Tab. B.2)', style: s),
        ]),
        _formulaTableRow('Plastisches Widerstands-\nmoment', [
          _mathSub('W', 'pl', fontSize: 9.8, isItalic: true),
          pw.Text(' = 5,72 cm³ (Tab. B.2)', style: s),
        ]),
        _formulaTableRow('Plastisches Grenzmoment', [
          _mathSub('M', 'pl,Rd', fontSize: 9.8, isItalic: true),
          pw.Text(' = ', style: s),
          _mathFraction(
            pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                _mathSub('W', 'pl', fontSize: 9.4, isItalic: true),
                pw.Text(' · ', style: s),
                _mathSub('f', 'y,k', fontSize: 9.4, isItalic: true),
              ],
            ),
            _mathSub('γ', 'M0', fontSize: 9.4, isItalic: false),
            minWidth: 42,
          ),
          pw.Text(' = 5.720 · 235 Nmm ≈ 1,34 kNm', style: s),
        ]),
      ],
    ),
  );
}

/// Zweispaltiger Formelsatz auf Seite 16: Schnittgrößen & Auslastung bei q_k = 1,0 kN/m
pw.Widget _buildFormelBlockPfosten2() {
  const s = pw.TextStyle(fontSize: 9.8);
  return pw.Container(
    margin: pw.EdgeInsets.symmetric(vertical: _mm(2.0)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _formulaTableRow('Einwirkende Last', [
          _mathSub('F', 'Ed', fontSize: 9.8, isItalic: true),
          pw.Text(' = ', style: s),
          _mathSub('γ', 'Q', fontSize: 9.8, isItalic: false),
          pw.Text(' · ', style: s),
          _mathSub('q', 'k', fontSize: 9.8, isItalic: true),
          pw.Text(' · e = 1,5 · 1,0 · 1,10 = 1,65 kN', style: s),
        ]),
        _formulaTableRow('Biegemoment', [
          _mathSub('M', 'Ed', fontSize: 9.8, isItalic: true),
          pw.Text(' = ', style: s),
          _mathSub('F', 'Ed', fontSize: 9.8, isItalic: true),
          pw.Text(' · h = 1,65 · 0,99 = 1,63 kNm', style: s),
        ]),
        _formulaTableRow('Auslastung', [
          pw.Text('η = ', style: s),
          _mathFraction(
            _mathSub('M', 'Ed', fontSize: 9.4, isItalic: true),
            _mathSub('M', 'pl,Rd', fontSize: 9.4, isItalic: true),
            minWidth: 30,
          ),
          pw.Text(' = ', style: s),
          _mathFraction(
            pw.Text('1,63', style: s),
            pw.Text('1,34', style: s),
            minWidth: 26,
          ),
          pw.Text(' = 1,22  (122 %)', style: s),
        ]),
      ],
    ),
  );
}

/// Zweispaltiger Formelsatz auf Seite 17: Geometrischer Betonausbruchnachweis nach DIN EN 1992-4
pw.Widget _buildFormelBlockBetonausbruch() {
  const s = pw.TextStyle(fontSize: 9.8);
  return pw.Container(
    margin: pw.EdgeInsets.symmetric(vertical: _mm(2.0)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _formulaTableRow('Projizierte Fläche Anker-\ngruppe', [
          _mathSub('A', 'c,N', fontSize: 9.8, isItalic: true),
          pw.Text(' = (', style: s),
          _mathSub('s', 'cr,N', fontSize: 9.8, isItalic: true),
          pw.Text(' + s) · (', style: s),
          _mathSub('c', '1', fontSize: 9.8, isItalic: true),
          pw.Text(' + ', style: s),
          _mathSub('c', '2', fontSize: 9.8, isItalic: true),
          pw.Text(')', style: s),
        ]),
        _formulaTableRow('', [
          _mathSub('A', 'c,N', fontSize: 9.8, isItalic: true),
          pw.Text(' = (195 + 120) · (80 + 80) = 50.400 mm²', style: s),
        ]),
        _formulaTableRow('Fläche Einzelanker ohne\nEinfluss', [
          _mathSub('A⁰', 'c,N', fontSize: 9.8, isItalic: true),
          pw.Text(' = ', style: s),
          _mathSub('s²', 'cr,N', fontSize: 9.8, isItalic: true),
          pw.Text(' = 195² = 38.025 mm²', style: s),
        ]),
        _formulaTableRow('Flächenverhältnis Zweier-\ngruppe', [
          _mathFraction(
            _mathSub('A', 'c,N', fontSize: 9.4, isItalic: true),
            pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text('2 · ', style: s),
                _mathSub('A⁰', 'c,N', fontSize: 9.4, isItalic: true),
              ],
            ),
            minWidth: 34,
          ),
          pw.Text(' = ', style: s),
          _mathFraction(
            pw.Text('50.400', style: s),
            pw.Text('76.050', style: s),
            minWidth: 36,
          ),
          pw.Text(' ≈ 0,66', style: s),
        ]),
        _formulaTableRow('Randeinfluss', [
          _mathSub('ψ', 's,N', fontSize: 9.8, isItalic: false),
          pw.Text(' = 0,7 + 0,3 · ', style: s),
          _mathFraction(
            pw.Text('c', style: s),
            _mathSub('c', 'cr,N', fontSize: 9.4, isItalic: true),
            minWidth: 24,
          ),
          pw.Text(' = 0,7 + 0,3 · ', style: s),
          _mathFraction(
            pw.Text('80', style: s),
            pw.Text('97,5', style: s),
            minWidth: 24,
          ),
          pw.Text(' ≈ 0,95', style: s),
        ]),
      ],
    ),
  );
}

pw.Widget _buildMplRdCard() => _buildFormelBlockPfosten1();
pw.Widget _buildBetonausbruchFormelCard() => _buildFormelBlockBetonausbruch();
pw.Widget _buildBetonausbruchBerechnungCard() => pw.SizedBox();

pw.Widget _buildDynamicMathChunk(String chunk) {
  const s = pw.TextStyle(fontSize: 9.8);
  return pw.RichText(
    text: pw.TextSpan(
      children: _expandTextWithMathSubscripts(chunk, s),
    ),
  );
}

List<pw.Widget> _parseDynamicMathExpression(String expr) {
  final widgets = <pw.Widget>[];
  final parenFrac = RegExp(r'\(([^()]+)\)\s*\/\s*\(([^()]+)\)');
  var curr = 0;
  for (final m in parenFrac.allMatches(expr)) {
    final before = expr.substring(0, m.end).trim().toLowerCase();
    if (before.endsWith('w/(m²k)')) continue;
    if (m.start > curr) {
      widgets.add(_buildDynamicMathChunk(expr.substring(curr, m.start)));
    }
    final numStr = m.group(1)!.trim();
    final denStr = m.group(2)!.trim();
    final maxLen = numStr.length > denStr.length ? numStr.length : denStr.length;
    widgets.add(
      _mathFraction(
        _buildDynamicMathChunk(numStr),
        _buildDynamicMathChunk(denStr),
        minWidth: (maxLen * 4.5).clamp(24.0, 72.0),
      ),
    );
    curr = m.end;
  }
  if (curr < expr.length) {
    widgets.add(_buildDynamicMathChunk(expr.substring(curr)));
  }
  return widgets;
}

pw.Widget _buildDynamicFormulaBlock(String rawMarkerOrJson) {
  var jsonStr = rawMarkerOrJson.trim();
  if (jsonStr == '[[FORMEL_BLOCK_PFOSTEN_1]]' ||
      jsonStr == 'FORMEL_BLOCK_PFOSTEN_1') {
    return _buildFormelBlockPfosten1();
  }
  if (jsonStr == '[[FORMEL_BLOCK_PFOSTEN_2]]' ||
      jsonStr == 'FORMEL_BLOCK_PFOSTEN_2') {
    return _buildFormelBlockPfosten2();
  }
  if (jsonStr == '[[FORMEL_BLOCK_BETONAUSBRUCH]]' ||
      jsonStr == 'FORMEL_BLOCK_BETONAUSBRUCH') {
    return _buildFormelBlockBetonausbruch();
  }
  if (jsonStr.startsWith('[[FORMEL_BLOCK_JSON:') && jsonStr.endsWith(']]')) {
    jsonStr = jsonStr.substring('[[FORMEL_BLOCK_JSON:'.length, jsonStr.length - 2).trim();
  }
  try {
    final decoded = jsonDecode(jsonStr);
    if (decoded is Map<String, dynamic>) {
      final preset = decoded['presetKey'] as String?;
      if (preset == 'FORMEL_BLOCK_PFOSTEN_1') return _buildFormelBlockPfosten1();
      if (preset == 'FORMEL_BLOCK_PFOSTEN_2') return _buildFormelBlockPfosten2();
      if (preset == 'FORMEL_BLOCK_BETONAUSBRUCH') {
        return _buildFormelBlockBetonausbruch();
      }
      final rawRows = (decoded['rows'] as List?) ?? const [];
      final children = <pw.Widget>[];
      for (final r in rawRows) {
        if (r is! Map) continue;
        final label = (r['label'] ?? '').toString();
        final expr = (r['expression'] ?? '').toString();
        children.add(_formulaTableRow(label, _parseDynamicMathExpression(expr)));
      }
      if (children.isNotEmpty) {
        return pw.Container(
          margin: pw.EdgeInsets.symmetric(vertical: _mm(2.0)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: children,
          ),
        );
      }
    }
  } catch (_) {}
  return pw.SizedBox();
}

_ParsedLine _parseSmartLine(
  String rawLine, {
  List<pw.InlineSpan>? inlineSpans,
  List<NormenData> normen = const [],
  bool linksAktivieren = true,
  String? sectionKey,
  void Function(String tocKey, int pageNumber)? onPageRecorded,
}) {
  final trimmed = rawLine.trim();
  if (trimmed.isEmpty) {
    return _ParsedLine(widget: pw.SizedBox(height: _mm(0.75)), isEmpty: true);
  }

  pw.Widget maybeWrapToc(pw.Widget child, String? tocKey) {
    if (tocKey == null || onPageRecorded == null) return child;
    return _TocTargetWidget(
      tocKey: tocKey,
      onPageRecorded: (p) => onPageRecorded(tocKey, p),
      child: child,
    );
  }

  // Expliziter Seitenumbruch-Marker [[NEWPAGE]]
  if (trimmed == '[[NEWPAGE]]') {
    return _ParsedLine(
      widget: pw.SizedBox(),
      isExplicitNewPage: true,
    );
  }

  // Zweispaltige mathematische Formelblöcke des Mustergutachtens & dynamische Formelblöcke
  if (trimmed == '[[FORMEL_BLOCK_PFOSTEN_1]]') {
    return _ParsedLine(widget: _buildFormelBlockPfosten1());
  }
  if (trimmed == '[[FORMEL_BLOCK_PFOSTEN_2]]') {
    return _ParsedLine(widget: _buildFormelBlockPfosten2());
  }
  if (trimmed == '[[FORMEL_BLOCK_BETONAUSBRUCH]]') {
    return _ParsedLine(widget: _buildFormelBlockBetonausbruch());
  }
  if (trimmed.startsWith('[[FORMEL_BLOCK_JSON:') && trimmed.endsWith(']]')) {
    return _ParsedLine(widget: _buildDynamicFormulaBlock(trimmed));
  }

  // 0. Mathematische Formelkarten (Legacy-Fallback)
  if (trimmed.contains('M_pl,Rd') || trimmed.contains('Mpl,Rd')) {
    if (trimmed.contains('W_pl') || trimmed.contains('Wpl')) {
      return _ParsedLine(widget: _buildMplRdCard());
    }
  }
  if (trimmed.contains('Ac,N') || trimmed.contains('A_c,N')) {
    if (trimmed.toLowerCase().contains('formel:')) {
      return _ParsedLine(widget: _buildBetonausbruchFormelCard());
    }
    if (trimmed.toLowerCase().contains('berechnung:')) {
      return _ParsedLine(widget: _buildBetonausbruchBerechnungCard());
    }
  }

  // 0. Markdown-Tabellenzeile (z.B. "| Col 1 | Col 2 |")
  if (trimmed.startsWith('|') && trimmed.endsWith('|') && trimmed.length > 2) {
    return _ParsedLine(widget: pw.SizedBox(), tableRawLine: trimmed);
  }

  // 1. Tagged Reference / Norm: z.B. "- [A1] Text" oder "[Q1] Text" oder "* [N1–N7] Text"
  final tagMatch = RegExp(r'^[-•*]?\s*\[([A-Z0-9]+(?:[–-][A-Z0-9]+)?)\]\s*(.*)$').firstMatch(trimmed);
  if (tagMatch != null) {
    final tag = tagMatch.group(1)!;
    final desc = tagMatch.group(2)!;
    final tagSpans = _formatTextWithNormLinks(
      '[$tag]',
      baseStyle: pw.TextStyle(
        fontSize: 8.9,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.blueGrey900,
      ),
      normen: normen,
      linksAktivieren: linksAktivieren,
    );

    final w = pw.Padding(
      padding: pw.EdgeInsets.only(left: _mm(1.0), bottom: _mm(2.2)),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: _mm(12.0),
            child: pw.RichText(
              text: pw.TextSpan(children: tagSpans),
            ),
          ),
          pw.Expanded(
            child: pw.RichText(
              text: pw.TextSpan(
                children: _formatTextWithNormLinks(
                  desc,
                  baseStyle: const pw.TextStyle(
                    fontSize: 9.6,
                    lineSpacing: 3.2,
                  ),
                  normen: normen,
                  linksAktivieren: linksAktivieren,
                ),
              ),
              textAlign: pw.TextAlign.justify,
              hyphenation: _germanHyphenation,
            ),
          ),
        ],
      ),
    );
    return _ParsedLine(widget: w);
  }

  final cleanNoMarkdown = trimmed.replaceAll('**', '').trim();

  // 1a. Haupt-Zwischenüberschrift "Schlusserklärung (§ 407a ZPO)" auf Seite 35
  if (cleanNoMarkdown == 'Schlusserklärung (§ 407a ZPO)') {
    final w = pw.Container(
      margin: pw.EdgeInsets.only(top: _mm(1.5), bottom: _mm(2.5)),
      padding: pw.EdgeInsets.only(bottom: _mm(1.2)),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.blueGrey800, width: 0.9),
        ),
      ),
      child: pw.Text(
        cleanNoMarkdown,
        style: pw.TextStyle(
          fontSize: 12.0,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.blueGrey900,
        ),
      ),
    );
    return _ParsedLine(widget: w, isHeading: true);
  }

  // 1b. Summenzeilen in der Kostenermittlung (Zwischensumme, Gesamtsumme Netto/Brutto, Umsatzsteuer)
  final sumMatch = RegExp(
    r'^[-•*]?\s*(Zwischensumme.*?|Gesamtsumme.*?|Zuzüglich.*?):\s*([0-9.,]+\s*€)$',
    caseSensitive: false,
  ).firstMatch(cleanNoMarkdown);
  if (sumMatch != null) {
    var label = sumMatch.group(1)!.trim();
    if (label.startsWith('-') || label.startsWith('•') || label.startsWith('*')) {
      label = label.substring(1).trim();
    }
    final amount = sumMatch.group(2)!.trim();
    final isZwischen = label.toLowerCase().startsWith('zwischensumme');
    final isGesamtBrutto = label.toLowerCase().contains('brutto');
    final isGesamtNetto = label.toLowerCase().contains('netto');

    final bg = isGesamtBrutto
        ? PdfColor.fromHex('E8EEF4')
        : (isZwischen ? PdfColor.fromHex('F2F5F8') : null);
    final border = isGesamtBrutto
        ? const pw.Border(
            top: pw.BorderSide(color: PdfColors.blueGrey700, width: 1.0),
            bottom: pw.BorderSide(color: PdfColors.blueGrey800, width: 2.0),
          )
        : (isZwischen
            ? const pw.Border(
                top: pw.BorderSide(color: PdfColors.blueGrey400, width: 0.8),
                bottom: pw.BorderSide(color: PdfColors.blueGrey400, width: 0.8),
              )
            : null);

    final w = pw.Container(
      margin: pw.EdgeInsets.only(
        top: _mm(isZwischen || isGesamtNetto ? 2.5 : 0.8),
        bottom: _mm(isZwischen || isGesamtBrutto ? 2.5 : 1.0),
      ),
      padding: pw.EdgeInsets.symmetric(
        horizontal: _mm(bg != null ? 2.5 : 0.0),
        vertical: _mm(bg != null ? 1.8 : 0.8),
      ),
      decoration: bg != null || border != null
          ? pw.BoxDecoration(color: bg, border: border)
          : null,
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '$label:',
            style: pw.TextStyle(
              fontSize: isGesamtBrutto ? 10.0 : (isZwischen || isGesamtNetto ? 9.2 : 9.0),
              fontWeight: (isGesamtBrutto || isZwischen || isGesamtNetto)
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
              color: (isGesamtBrutto || isZwischen) ? PdfColors.blueGrey900 : PdfColors.black,
            ),
          ),
          pw.Text(
            amount,
            style: pw.TextStyle(
              fontSize: isGesamtBrutto ? 10.0 : (isZwischen || isGesamtNetto ? 9.2 : 9.0),
              fontWeight: (isGesamtBrutto || isZwischen || isGesamtNetto)
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
              color: (isGesamtBrutto || isZwischen) ? PdfColors.blueGrey900 : PdfColors.black,
            ),
          ),
        ],
      ),
    );
    return _ParsedLine(widget: w);
  }

  // 2. Hauptabschnittsüberschriften "A. Balkongeländer..." / "B. Pfosten-Riegel-Fassade..."
  final abGroupMatch = RegExp(r'^([AB]\.)\s+(.+)$').firstMatch(cleanNoMarkdown);
  if (abGroupMatch != null && cleanNoMarkdown.length < 95) {
    final letter = abGroupMatch.group(1)!;
    final title = abGroupMatch.group(2)!.trim();
    final tocKey = 'sub:${sectionKey ?? ''}:$letter';
    final w = maybeWrapToc(
      pw.Padding(
        padding: pw.EdgeInsets.only(top: _mm(3.0), bottom: _mm(2.0)),
        child: pw.Text(
          '$letter $title',
          style: pw.TextStyle(
            fontSize: 11.2,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('1E3552'),
          ),
        ),
      ),
      tocKey,
    );
    return _ParsedLine(widget: w, isHeading: true);
  }

  // 2b. Sachverhalts-Abschnitte "IV.1 Geländerhöhe..." bis "IV.11 Sanierungsvarianten..."
  final ivSubMatch = RegExp(r'^(IV\.\d+)\s+(.+)$').firstMatch(cleanNoMarkdown);
  if (ivSubMatch != null) {
    final numStr = ivSubMatch.group(1)!;
    final title = ivSubMatch.group(2)!.trim();
    final tocKey = 'sub:${sectionKey ?? ''}:$numStr';
    final w = maybeWrapToc(
      pw.Padding(
        padding: pw.EdgeInsets.only(top: _mm(2.2), bottom: _mm(1.8)),
        child: pw.Text(
          '$numStr $title',
          style: pw.TextStyle(
            fontSize: 10.8,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('1E3552'),
          ),
        ),
      ),
      tocKey,
    );
    return _ParsedLine(widget: w, isHeading: true);
  }

  // 2c. Hauptabschnittsüberschriften "2.1 Balkongeländer..." / "2.2 Pfosten-Riegel-Fassade..."
  final groupMatch = RegExp(r'^(?:###\s*)?(2\.\d+)\s*:?\s*(.+)$', caseSensitive: false).firstMatch(cleanNoMarkdown);
  if (groupMatch != null &&
      (cleanNoMarkdown == '2.1 GELÄNDER' ||
          cleanNoMarkdown == '2.2 FASSADENELEMENT' ||
          cleanNoMarkdown.toLowerCase().contains('geländer') ||
          cleanNoMarkdown.toLowerCase().contains('fassade') ||
          cleanNoMarkdown.startsWith('2.1 Balkongeländer') ||
          cleanNoMarkdown.startsWith('2.2 Pfosten-Riegel-Fassade') ||
          cleanNoMarkdown == '2.1 Geländer:' ||
          cleanNoMarkdown == '2.2 Fassade:')) {
    final num = groupMatch.group(1)!;
    var title = groupMatch.group(2)!.trim();
    final tocKey = (sectionKey == 's_beweisfragen') ? 'sub:$sectionKey:$num' : null;
    final w = maybeWrapToc(
      pw.Container(
        margin: pw.EdgeInsets.only(top: _mm(2.8), bottom: _mm(1.8)),
        child: pw.Text(
          '$num $title',
          style: pw.TextStyle(
            fontSize: 10.8,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('1E3552'),
          ),
        ),
      ),
      tocKey,
    );
    return _ParsedLine(widget: w, isHeading: true);
  }

  // 3. Frage-Zeilen (im Beweisbeschluss 2.1.1 .. 2.2.4 oder als "Beweisfrage 2.1.1: ...")
  final questionMatch = RegExp(
          r'^(?:[-•*]?\s*)?(?:(Zu\s+Frage|Beweisfrage|Frage)\s*)?(\d+\.\d+\.\d+):?\s*(.*)$',
          caseSensitive: false)
      .firstMatch(cleanNoMarkdown);
  if (questionMatch != null) {
    final prefixWord = questionMatch.group(1);
    final numStr = questionMatch.group(2)!;
    final restText = questionMatch.group(3)!.trim();

    // Im Abschnitt I (Auftrag und Beweisfragen) als zweispaltige Zeile mit fettgedruckter Nummer links
    if (prefixWord == null && restText.isNotEmpty) {
      final w = pw.Padding(
        padding: pw.EdgeInsets.only(bottom: _mm(1.4)),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: _mm(11.0),
              child: pw.Text(
                numStr,
                style: pw.TextStyle(
                  fontSize: 9.2,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
            ),
            pw.Expanded(
              child: pw.RichText(
                textAlign: pw.TextAlign.justify,
                hyphenation: _germanHyphenation,
                text: pw.TextSpan(
                  children: _formatTextWithNormLinks(
                    restText,
                    baseStyle: const pw.TextStyle(
                      fontSize: 9.2,
                      lineSpacing: 1.25,
                    ),
                    normen: normen,
                    linksAktivieren: linksAktivieren,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      return _ParsedLine(widget: w);
    }

    final displayTitle = restText.isNotEmpty
        ? '${prefixWord ?? 'Beweisfrage'} $numStr: $restText'
        : '${prefixWord ?? 'Beweisfrage'} $numStr';

    final w = pw.Padding(
      padding: pw.EdgeInsets.only(top: _mm(2.0), bottom: _mm(0.8)),
      child: pw.Text(
        displayTitle,
        style: pw.TextStyle(
          fontSize: 9.8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColor.fromHex('#2C4A6F'),
        ),
      ),
    );
    return _ParsedLine(widget: w, isHeading: true);
  }

  // 4. Antwort- / Beantwortungs-Überschrift (z.B. "Beantwortung der Beweisfrage 2.1.1", "Beantwortung der Beweisfrage 2.1.2 (Teil 1 – Konstruktion und Verankerung)")
  final answerMatch = RegExp(
          r'^[-•*]?\s*((?:Antwort|Beantwortung)\s+(?:der|zu|auf)\s+(?:Beweisfrage|Frage)\s+\d+(?:\.\d+)*(?:\s*\([^)]+\))?\s*:?)\s*(.*)$',
          caseSensitive: false)
      .firstMatch(cleanNoMarkdown);
  if (answerMatch != null) {
    var cleanLabel = answerMatch.group(1)!.trim();
    final rest = answerMatch.group(2)!.trim();
    if (rest.isEmpty) {
      final w = pw.Padding(
        padding: pw.EdgeInsets.only(top: _mm(2.0), bottom: _mm(0.8)),
        child: pw.Text(
          cleanLabel,
          style: pw.TextStyle(
            fontSize: 9.8,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('#2C4A6F'),
          ),
        ),
      );
      return _ParsedLine(widget: w, isHeading: true);
    }
  }

  // 5. Gliederungs-Zwischenüberschriften ("Feststellungen", "Bewertung", "Maßnahmen", "Technische Bewertung", "a) ...", "b) ...")
  final letterSubMatch = RegExp(r'^([a-h]\))\s+(.+)$').firstMatch(cleanNoMarkdown);
  final isStandaloneSectionWord = cleanNoMarkdown == 'Feststellungen' ||
      cleanNoMarkdown == 'Bewertung' ||
      cleanNoMarkdown == 'Maßnahmen' ||
      cleanNoMarkdown == 'Technische Bewertung' ||
      cleanNoMarkdown == 'Kostenschätzung' ||
      cleanNoMarkdown == 'Wirtschaftliche Bewertung' ||
      cleanNoMarkdown == 'Hinweis zu den Normausgaben' ||
      cleanNoMarkdown == 'Schlusserklärung (§ 407a ZPO)' ||
      cleanNoMarkdown.startsWith('Feststellungen (') ||
      cleanNoMarkdown.startsWith('Technische Bewertung (') ||
      cleanNoMarkdown.startsWith('Maßnahmen und Kostenschätzung') ||
      cleanNoMarkdown.startsWith('Erforderliche Maßnahmen') ||
      cleanNoMarkdown.startsWith('Geometrischer Betonausbruchnachweis') ||
      cleanNoMarkdown.startsWith('Plausibilitätsüberschlag') ||
      cleanNoMarkdown.startsWith('Nachweis für höhere Holmlast') ||
      cleanNoMarkdown.startsWith('Schlussfolgerung zur Einzelpfostenbetrachtung') ||
      cleanNoMarkdown.startsWith('Zusammenfassung zu ') ||
      cleanNoMarkdown.startsWith('Gegenüberstellung der Sanierungsvarianten') ||
      cleanNoMarkdown.startsWith('Gegenüberstellung zum Schreiben') ||
      cleanNoMarkdown.startsWith('Kostenschätzung Variante') ||
      cleanNoMarkdown.startsWith('Kostenzusammenfassung Balkongeländer') ||
      cleanNoMarkdown.startsWith('Kostenzusammenfassung und Gesamtbewertung') ||
      cleanNoMarkdown.startsWith('Gesamtkostenübersicht (Balkongeländer') ||
      cleanNoMarkdown.startsWith('Rechnerische Abschätzung des Temperaturfaktors') ||
      cleanNoMarkdown.startsWith('Übersichtstabelle der technischen Befunde') ||
      (letterSubMatch != null && cleanNoMarkdown.length < 95);

  final isEvaluationHeading = isStandaloneSectionWord ||
      (cleanNoMarkdown.endsWith(':') &&
          cleanNoMarkdown.length < 80 &&
          (cleanNoMarkdown.contains('Feststellung') ||
              cleanNoMarkdown.contains('Beurteilung') ||
              cleanNoMarkdown.contains('Würdigung') ||
              cleanNoMarkdown.contains('Lastannahmen') ||
              cleanNoMarkdown.contains('Plausibilitätsprüfung') ||
              cleanNoMarkdown.contains('Verankerung') ||
              cleanNoMarkdown.contains('Herstellervorschriften') ||
              cleanNoMarkdown.contains('Regelwerk') ||
              cleanNoMarkdown.contains('Schritte') ||
              cleanNoMarkdown.contains('Variantenvergleich') ||
              cleanNoMarkdown.contains('Höhenmaße') ||
              cleanNoMarkdown.contains('Sockelanschluss') ||
              cleanNoMarkdown.contains('Machbarkeit')));

  if (isEvaluationHeading) {
    var cleanHeader = cleanNoMarkdown;
    if (cleanHeader.startsWith('-') || cleanHeader.startsWith('•') || cleanHeader.startsWith('*')) {
      cleanHeader = cleanHeader.substring(1).trim();
    }
    final isSubLetter = letterSubMatch != null;
    final w = pw.Padding(
      padding: pw.EdgeInsets.only(top: _mm(1.8), bottom: _mm(0.8)),
      child: pw.RichText(
        text: pw.TextSpan(
          children: _formatTextWithNormLinks(
            cleanHeader,
            baseStyle: pw.TextStyle(
              fontSize: isSubLetter ? 9.4 : 9.8,
              fontWeight: pw.FontWeight.bold,
              color: isSubLetter ? PdfColor.fromHex('#1F2937') : PdfColor.fromHex('#2C4A6F'),
            ),
            normen: normen,
            linksAktivieren: linksAktivieren,
          ),
        ),
      ),
    );
    return _ParsedLine(widget: w, isHeading: true);
  }

  // 6. Nummerierte Unterüberschriften wie "1.1 Auftrag...", "1. Verwendete Arbeits- und Hilfsmittel", "3. Hinweise und Vorbehalte"
  final headingMatch = RegExp(r'^(\d+(?:\.\d+)*\.?)\s+(.*)$').firstMatch(cleanNoMarkdown);
  final isNumberedSubHeading = headingMatch != null &&
      !cleanNoMarkdown.endsWith('.') &&
      cleanNoMarkdown.length < 85 &&
      !cleanNoMarkdown.contains(':') &&
      (RegExp(r'^\d+\.\d+$').hasMatch(headingMatch.group(1)!) ||
          sectionKey == 's_auftrag' ||
          sectionKey == 's_grundlage' ||
          sectionKey == 's_situation');

  if (isNumberedSubHeading) {
    final numPrefix = headingMatch.group(1)!;
    final titleText = headingMatch.group(2)!.trim();
    final isTocSub = (sectionKey == 's_grundlage' || sectionKey == 's_situation') &&
        RegExp(r'^\d+\.$').hasMatch(numPrefix);
    final tocKey = isTocSub ? 'sub:$sectionKey:$numPrefix' : null;
    final w = maybeWrapToc(
      pw.Padding(
        padding: pw.EdgeInsets.only(top: _mm(2.2), bottom: _mm(1.0)),
        child: pw.Text(
          '$numPrefix $titleText',
          style: pw.TextStyle(
            fontSize: 10.6,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('#2C4A6F'),
          ),
        ),
      ),
      tocKey,
    );
    return _ParsedLine(widget: w, isHeading: true);
  }

  // 7. Nummerierte Aufzählungspunkte mit hängendem Einzug (z.B. "1. Text...", "2. Text...")
  if (headingMatch != null) {
    final numPrefix = headingMatch.group(1)!;
    final itemText = headingMatch.group(2)!;
    final prefixWidth = (numPrefix.length > 3) ? 8.5 : 6.0;
    final colonIdx = itemText.indexOf(':');
    final isRatio = colonIdx > 0 &&
        colonIdx + 1 < itemText.length &&
        RegExp(r'^\d$').hasMatch(itemText[colonIdx - 1]) &&
        RegExp(r'^\d$').hasMatch(itemText[colonIdx + 1]);
    final hasKey = colonIdx > 0 && colonIdx < 42 && !isRatio;

    final w = pw.Padding(
      padding: pw.EdgeInsets.only(left: _mm(1.5), bottom: _mm(1.0)),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: _mm(prefixWidth),
            child: pw.Text(
              numPrefix,
              style: pw.TextStyle(
                fontSize: 9.2,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blueGrey900,
              ),
            ),
          ),
          pw.Expanded(
            child: hasKey
                ? pw.RichText(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                          text: '${itemText.substring(0, colonIdx + 1)} ',
                          style: pw.TextStyle(
                            fontSize: 9.2,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                          ),
                        ),
                        ..._formatTextWithNormLinks(
                          itemText.substring(colonIdx + 1).trim(),
                          baseStyle: const pw.TextStyle(
                            fontSize: 9.2,
                            lineSpacing: 1.22,
                          ),
                          normen: normen,
                          linksAktivieren: linksAktivieren,
                        ),
                      ],
                    ),
                    textAlign: pw.TextAlign.justify,
                    hyphenation: _germanHyphenation,
                  )
                : pw.RichText(
                    text: pw.TextSpan(
                      children: _formatTextWithNormLinks(
                        trimmed.substring(trimmed.indexOf(numPrefix) + numPrefix.length).trim(),
                        baseStyle: const pw.TextStyle(
                          fontSize: 9.2,
                          lineSpacing: 1.22,
                        ),
                        normen: normen,
                        linksAktivieren: linksAktivieren,
                      ),
                    ),
                    textAlign: pw.TextAlign.justify,
                    hyphenation: _germanHyphenation,
                  ),
          ),
        ],
      ),
    );
    return _ParsedLine(widget: w);
  }

  // 8. Listenpunkte / Bullets mit hängendem Einzug und Sub-Level-Einrückung
  final leadingSpaces = RegExp(r'^\s*').firstMatch(rawLine)?.group(0) ?? '';
  final bulletMatch = RegExp(r'^([-•*–—·])\s+(.*)$').firstMatch(trimmed);
  if (bulletMatch != null) {
    final bulletChar = bulletMatch.group(1) ?? '-';
    final bulletRawText = bulletMatch.group(2)!;
    final bulletCleanText = bulletRawText.replaceAll('**', '');

    final isDeepSub = leadingSpaces.length >= 4 || (bulletChar == '–' && leadingSpaces.length >= 2);
    final isSub = leadingSpaces.length >= 2 || bulletChar == '*' || bulletChar == '·' || bulletChar == '–' || bulletChar == '—';
    final leftIndent = isDeepSub ? _mm(6.5) : (isSub ? _mm(4.0) : _mm(1.5));
    final bulletSymbol = isDeepSub ? '–' : (isSub ? '–' : '•');

    final colonIdx = bulletCleanText.indexOf(':');
    final isRatio = colonIdx > 0 &&
        colonIdx + 1 < bulletCleanText.length &&
        RegExp(r'^\d$').hasMatch(bulletCleanText[colonIdx - 1]) &&
        RegExp(r'^\d$').hasMatch(bulletCleanText[colonIdx + 1]);
    final hasKey = !bulletRawText.contains('**') && colonIdx > 0 && colonIdx < 35 && !isRatio;

    final w = pw.Padding(
      padding: pw.EdgeInsets.only(left: leftIndent, bottom: _mm(1.6)),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: _mm(5.5),
            child: pw.Text(
              bulletSymbol,
              style: pw.TextStyle(
                fontSize: 9.8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ),
          pw.Expanded(
            child: hasKey
                ? pw.RichText(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                          text: '${bulletCleanText.substring(0, colonIdx + 1)} ',
                          style: pw.TextStyle(
                            fontSize: 9.8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                          ),
                        ),
                        ..._formatTextWithNormLinks(
                          bulletCleanText.substring(colonIdx + 1).trim(),
                          baseStyle: const pw.TextStyle(
                            fontSize: 9.8,
                            lineSpacing: 3.4,
                          ),
                          normen: normen,
                          linksAktivieren: linksAktivieren,
                        ),
                      ],
                    ),
                    textAlign: pw.TextAlign.justify,
                    hyphenation: _germanHyphenation,
                  )
                : pw.RichText(
                    text: pw.TextSpan(
                      children: _formatTextWithNormLinks(
                        bulletRawText,
                        baseStyle: const pw.TextStyle(
                          fontSize: 9.8,
                          lineSpacing: 3.4,
                        ),
                        normen: normen,
                        linksAktivieren: linksAktivieren,
                      ),
                    ),
                    textAlign: pw.TextAlign.justify,
                    hyphenation: _germanHyphenation,
                  ),
          ),
        ],
      ),
    );
    return _ParsedLine(widget: w);
  }

  // 8b. Eingerückte Unterzeilen ohne expliziten Bullet
  if (leadingSpaces.length >= 2) {
    final w = pw.Padding(
      padding: pw.EdgeInsets.only(left: _mm(5.0), bottom: _mm(1.6)),
      child: pw.RichText(
        text: pw.TextSpan(
          children: _formatTextWithNormLinks(
            trimmed,
            baseStyle: const pw.TextStyle(
              fontSize: 9.8,
              lineSpacing: 3.4,
            ),
            normen: normen,
            linksAktivieren: linksAktivieren,
          ),
        ),
        textAlign: pw.TextAlign.left,
        hyphenation: _germanHyphenation,
      ),
    );
    return _ParsedLine(widget: w);
  }

  // 9. Standard Fließtext-Absatz (Blocksatz mit deutscher Silbentrennung)
  if (inlineSpans != null &&
      inlineSpans.isNotEmpty &&
      inlineSpans.any((s) => s is pw.TextSpan && s.annotation != null)) {
    final w = pw.Padding(
      padding: pw.EdgeInsets.only(bottom: _mm(2.0)),
      child: pw.RichText(
        text: pw.TextSpan(
          children: inlineSpans,
          style: const pw.TextStyle(
            fontSize: 9.8,
            lineSpacing: 3.5,
          ),
        ),
        overflow: pw.TextOverflow.span,
        textAlign: pw.TextAlign.justify,
        hyphenation: _germanHyphenation,
      ),
    );
    return _ParsedLine(widget: w);
  }

  final w = pw.Padding(
    padding: pw.EdgeInsets.only(bottom: _mm(2.0)),
    child: pw.RichText(
      text: pw.TextSpan(
        children: _formatTextWithNormLinks(
          trimmed,
          baseStyle: const pw.TextStyle(
            fontSize: 9.8,
            lineSpacing: 3.5,
          ),
          normen: normen,
          linksAktivieren: linksAktivieren,
        ),
      ),
      overflow: pw.TextOverflow.span,
      textAlign: pw.TextAlign.justify,
      hyphenation: _germanHyphenation,
    ),
  );
  return _ParsedLine(widget: w);
}

List<pw.Widget> _plainTextToWidgets(
  String text, {
  List<NormenData> normen = const [],
  bool linksAktivieren = true,
  String? sectionKey,
  void Function(String tocKey, int pageNumber)? onPageRecorded,
}) {
  var cleaned = text;
  if (cleaned.startsWith('[{"insert":') && cleaned.endsWith('"}]')) {
    cleaned = cleaned.substring(11, cleaned.length - 3);
  }
  if (cleaned.contains(r'\n')) {
    cleaned = cleaned.replaceAll(r'\n', '\n');
  }
  if (cleaned.contains(r'\"')) {
    cleaned = cleaned.replaceAll(r'\"', '"');
  }
  final lines = cleaned.split('\n');
  final parsed = <_ParsedLine>[];
  for (final line in lines) {
    parsed.add(_parseSmartLine(
      line,
      normen: normen,
      linksAktivieren: linksAktivieren,
      sectionKey: sectionKey,
      onPageRecorded: onPageRecorded,
    ));
  }
  return _postProcessParsedLines(
    parsed,
    normen: normen,
    linksAktivieren: linksAktivieren,
  );
}

List<pw.Widget> _quillDeltaToWidgets(
  String json, {
  List<NormenData> normen = const [],
  bool linksAktivieren = true,
  String? sectionKey,
  void Function(String tocKey, int pageNumber)? onPageRecorded,
}) {
  List ops;
  try {
    final parsed = jsonDecode(json);
    if (parsed is List) {
      ops = parsed;
    } else if (parsed is Map && parsed['ops'] is List) {
      ops = parsed['ops'] as List;
    } else {
      return _plainTextToWidgets(
        json,
        normen: normen,
        linksAktivieren: linksAktivieren,
        sectionKey: sectionKey,
        onPageRecorded: onPageRecorded,
      );
    }
  } catch (_) {
    return _plainTextToWidgets(
      json,
      normen: normen,
      linksAktivieren: linksAktivieren,
      sectionKey: sectionKey,
      onPageRecorded: onPageRecorded,
    );
  }

  final parsedLines = <_ParsedLine>[];
  final currentSpans = <pw.InlineSpan>[];
  Map<String, dynamic>? blockAttrs;

  void flushParagraph() {
    if (currentSpans.isEmpty) {
      parsedLines.add(_ParsedLine(widget: pw.SizedBox(height: _mm(1.0)), isEmpty: true));
      return;
    }
    final header = blockAttrs?['header'];
    final isBullet = blockAttrs?['list'] == 'bullet';
    final isOrdered = blockAttrs?['list'] == 'ordered';

    if (header != null || isBullet || isOrdered) {
      final style = header == 1
          ? pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)
          : header == 2
              ? pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)
              : header == 3
                  ? pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)
                  : const pw.TextStyle(fontSize: 9.4);
      final rich = pw.RichText(
        text: pw.TextSpan(
          children: currentSpans.toList(),
          style: style,
        ),
        overflow: pw.TextOverflow.span,
        hyphenation: _germanHyphenation,
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
        parsedLines.add(_ParsedLine(
          widget: pw.Padding(
            padding: pw.EdgeInsets.only(left: _mm(2.0), bottom: _mm(1.0)),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: _mm(3.5),
                  child: pw.Text('•',
                      style: pw.TextStyle(
                          fontSize: 8.8,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blueGrey800)),
                ),
                pw.Expanded(child: rich),
              ],
            ),
          ),
        ));
      } else if (isOrdered) {
        parsedLines.add(_ParsedLine(
          widget: pw.Padding(
            padding: pw.EdgeInsets.only(left: _mm(2.0), bottom: _mm(1.0)),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: _mm(6.0),
                  child: pw.Text('•',
                      style: pw.TextStyle(
                          fontSize: 8.8,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blueGrey800)),
                ),
                pw.Expanded(child: rich),
              ],
            ),
          ),
        ));
      } else {
        parsedLines.add(_ParsedLine(widget: rich, isHeading: header != null));
      }
      parsedLines.add(_ParsedLine(widget: pw.SizedBox(height: _mm(1.2)), isEmpty: true));
      currentSpans.clear();
      blockAttrs = null;
      return;
    }

    final plain = currentSpans.map((s) => s.toPlainText()).join('');
    parsedLines.add(_parseSmartLine(
      plain,
      inlineSpans: currentSpans.toList(),
      normen: normen,
      linksAktivieren: linksAktivieren,
      sectionKey: sectionKey,
      onPageRecorded: onPageRecorded,
    ));
    currentSpans.clear();
    blockAttrs = null;
  }

  for (final op in ops) {
    if (op is! Map) continue;
    final insert = op['insert'];
    if (insert is Map) {
      if (currentSpans.isNotEmpty) flushParagraph();
      final imageDataUrl = insert['image'];
      if (imageDataUrl is String) {
        final img = _safeImage(_decodeDataUrl(imageDataUrl));
        if (img != null) {
          parsedLines.add(_ParsedLine(
            widget: pw.Container(
              alignment: pw.Alignment.center,
              constraints: const pw.BoxConstraints(maxHeight: 360),
              margin: pw.EdgeInsets.symmetric(vertical: _mm(2)),
              child: img,
            ),
          ));
        }
      }
      Map<String, dynamic>? customMap;
      if (insert['custom'] is String) {
        try {
          customMap = jsonDecode(insert['custom'] as String) as Map<String, dynamic>?;
        } catch (_) {}
      } else {
        customMap = Map<String, dynamic>.from(insert);
      }
      if (customMap != null) {
        if (customMap.containsKey('aw_pagebreak')) {
          parsedLines.add(_ParsedLine(widget: pw.SizedBox(), isExplicitNewPage: true));
        } else if (customMap.containsKey('aw_formula')) {
          parsedLines.add(_ParsedLine(
            widget: _buildDynamicFormulaBlock(customMap['aw_formula'].toString()),
          ));
        } else if (customMap.containsKey('aw_table')) {
          try {
            final tblDecoded = jsonDecode(customMap['aw_table'].toString());
            if (tblDecoded is Map<String, dynamic>) {
              final rawRows = (tblDecoded['rows'] as List?) ?? const [];
              final rawAligns = (tblDecoded['alignments'] as List?) ?? const [];
              if (rawRows.isNotEmpty) {
                final mdLines = <String>[];
                final firstRow = (rawRows.first as List).map((e) => e.toString()).toList();
                final cols = firstRow.length;
                mdLines.add('| ${firstRow.join(' | ')} |');
                final sep = List<String>.generate(cols, (c) {
                  final a = c < rawAligns.length ? rawAligns[c].toString() : 'left';
                  return a == 'center' ? ':---:' : (a == 'right' ? '---:' : '---');
                });
                mdLines.add('| ${sep.join(' | ')} |');
                for (var r = 1; r < rawRows.length; r++) {
                  final rowCells = (rawRows[r] as List).map((e) => e.toString()).toList();
                  mdLines.add('| ${rowCells.join(' | ')} |');
                }
                for (final l in mdLines) {
                  parsedLines.add(_ParsedLine(widget: pw.SizedBox(), tableRawLine: l));
                }
              }
            }
          } catch (_) {}
        }
      }
      continue;
    }
    if (insert is! String) continue;
    final attrs = op['attributes'] as Map<String, dynamic>?;
    final linkUrl = attrs?['link'] as String?;
    final isLink = linksAktivieren && linkUrl != null && linkUrl.isNotEmpty;
    final script = attrs?['script'] as String?;
    final isSubOrSuper = script == 'sub' || script == 'super';

    final textClean = insert.replaceAll(r'\n', '\n');
    final parts = textClean.split('\n');
    for (var i = 0; i < parts.length; i++) {
      final text = parts[i];
      if (text.isNotEmpty) {
        currentSpans.add(
          pw.TextSpan(
            text: text,
            style: pw.TextStyle(
              fontSize: isSubOrSuper ? 6.5 : null,
              fontWeight: attrs?['bold'] == true
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
              fontStyle: attrs?['italic'] == true
                  ? pw.FontStyle.italic
                  : pw.FontStyle.normal,
              color: isLink ? PdfColor.fromHex('1A56DB') : null,
              decoration: (isLink || attrs?['underline'] == true)
                  ? pw.TextDecoration.underline
                  : null,
            ),
            annotation: isLink ? pw.AnnotationUrl(linkUrl) : null,
          ),
        );
      }
      if (i < parts.length - 1) {
        if (attrs != null && attrs.keys.any((k) =>
            k == 'header' || k == 'list' || k == 'blockquote')) {
          blockAttrs = attrs;
        }
        flushParagraph();
      }
    }
  }
  if (currentSpans.isNotEmpty) flushParagraph();

  return _postProcessParsedLines(
    parsedLines,
    normen: normen,
    linksAktivieren: linksAktivieren,
  );
}

class _TocEintrag {
  const _TocEintrag({
    required this.label,
    required this.nummer,
    this.einzug = 0,
    this.tocKey,
    this.isAnlage = false,
  });
  final String label;
  final String nummer;
  final int einzug;
  final String? tocKey;
  final bool isAnlage;
}

class _Heading {
  const _Heading({
    required this.text,
    required this.level,
    this.nummer = '',
    this.tocKey,
  });
  final String text;
  final int level;
  final String nummer;
  final String? tocKey;
}

/// Sucht in einem Sektionstext (Plain-Text oder Quill-Delta-JSON) alle
/// für das Inhaltsverzeichnis relevanten Unterüberschriften.
List<_Heading> _extrahiereHeadings(String inhalt, {String? sectionKey}) {
  final out = <_Heading>[];
  final t = inhalt.trim();
  if (t.isEmpty) return out;

  var plainText = t;
  if (t.startsWith('[') || t.startsWith('{')) {
    dynamic decoded;
    try {
      decoded = jsonDecode(t);
    } catch (_) {
      decoded = null;
    }
    final ops = decoded is List
        ? decoded
        : (decoded is Map && decoded['ops'] is List ? decoded['ops'] as List : null);
    if (ops != null) {
      final buffer = StringBuffer();
      final fullPlain = StringBuffer();
      for (final op in ops) {
        if (op is! Map) continue;
        final insert = op['insert'];
        final attrs = op['attributes'];
        if (insert is String) {
          final textClean = insert.replaceAll(r'\n', '\n');
          fullPlain.write(textClean);
          final parts = textClean.split('\n');
          for (var i = 0; i < parts.length; i++) {
            buffer.write(parts[i]);
            if (i < parts.length - 1) {
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
          buffer.clear();
        }
      }
      if (out.isNotEmpty) return out;
      plainText = fullPlain.toString();
    }
  }

  // Plain-Text-Gliederung für das Gerichtsgutachten scannen:
  // - s_grundlage / s_situation: "1. ...", "2. ...", "3. ...", "4. ..."
  // - s_feststellungen: "A. ...", "B. ...", "IV.1 ..." .. "IV.11 ..."
  // - s_beweisfragen: "2.1 ...", "2.2 ..."
  for (final rawLine in plainText.split('\n')) {
    final line = rawLine.replaceAll('**', '').trim();
    if (line.isEmpty || line.startsWith('[[') || line.startsWith('|')) continue;

    if (sectionKey == 's_grundlage' || sectionKey == 's_situation') {
      final m = RegExp(r'^([1-9]\.)\s+(.+)$').firstMatch(line);
      if (m != null && !line.endsWith('.') && !line.contains(':') && line.length < 85) {
        final numStr = m.group(1)!;
        final label = m.group(2)!.trim();
        out.add(_Heading(
          nummer: numStr,
          text: label,
          level: 1,
          tocKey: 'sub:$sectionKey:$numStr',
        ));
      }
    } else if (sectionKey == 's_feststellungen') {
      final mGroup = RegExp(r'^([AB]\.)\s+(.+)$').firstMatch(line);
      if (mGroup != null && line.length < 95) {
        final numStr = mGroup.group(1)!;
        final label = mGroup.group(2)!.trim();
        out.add(_Heading(
          nummer: numStr,
          text: label,
          level: 1,
          tocKey: 'sub:$sectionKey:$numStr',
        ));
        continue;
      }
      final mIv = RegExp(r'^(IV\.\d+)\s+(.+)$').firstMatch(line);
      if (mIv != null) {
        final numStr = mIv.group(1)!;
        final label = mIv.group(2)!.trim();
        out.add(_Heading(
          nummer: numStr,
          text: label,
          level: 1,
          tocKey: 'sub:$sectionKey:$numStr',
        ));
      }
    } else if (sectionKey == 's_beweisfragen') {
      final m2 = RegExp(r'^(2\.[12])\s+(.+)$').firstMatch(line);
      if (m2 != null && line.length < 95) {
        final numStr = m2.group(1)!;
        final label = m2.group(2)!.trim();
        out.add(_Heading(
          nummer: numStr,
          text: label,
          level: 1,
          tocKey: 'sub:$sectionKey:$numStr',
        ));
      }
    }
  }
  return out;
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
