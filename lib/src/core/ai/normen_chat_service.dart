import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show WidgetRef;
import 'package:http/http.dart' as http;

import '../../data/database/app_database.dart';
import '../../data/sync/auth_service.dart';
import '../../features/system/einstellungen/einstellungen_repository.dart';
import 'ki_modelle.dart';
import 'ki_usage_service.dart';

/// Antwort der Chat-KI mit Angabe, welche Normen im Kontext standen.
class NormenChatAntwort {
  const NormenChatAntwort({
    required this.text,
    required this.verwendeteNormen,
  });
  final String text;
  final List<NormenData> verwendeteNormen;
}

/// Eine Nachricht in der Chat-Historie.
class NormenChatNachricht {
  NormenChatNachricht({
    required this.rolle,
    required this.inhalt,
    this.verwendeteNormen = const [],
  });

  /// 'user' oder 'assistant'.
  final String rolle;
  final String inhalt;
  final List<NormenData> verwendeteNormen;
}

/// Chat-Session für die Normen-Bibliothek. Hält Historie + PDF-Cache.
/// Pro Frage werden:
/// 1. Alle Norm-Metadaten als System-Kontext mitgegeben (billig).
/// 2. Die Top-[maxPdfs] inhaltlich passenden Normen mit PDF als
///    Inline-Dokument an Gemini übergeben (die KI liest das PDF).
/// 3. Die Antwort wird zurückgegeben — die Zitate in runden Klammern
///    stammen direkt vom Modell.
class NormenChatSession {
  NormenChatSession(this.ref, this.alleNormen, {this.maxPdfs = 3});

  final WidgetRef ref;
  final List<NormenData> alleNormen;
  final int maxPdfs;

  final List<NormenChatNachricht> historie = [];
  final Map<int, Uint8List> _pdfCache = {};

  Future<NormenChatAntwort> frage(String frageText) async {
    final repo = ref.read(einstellungenRepositoryProvider);
    final modellId = await getKiModell(repo, KiAufgabe.normenChat);
    final kandidaten = _matchNormen(frageText);
    final mitPdf = <(NormenData, Uint8List)>[];
    for (final n in kandidaten) {
      if (mitPdf.length >= maxPdfs) break;
      final url = n.pdfStorageUrl;
      if (url == null || url.isEmpty) continue;
      final bytes = await _ladePdf(n.id, url);
      if (bytes != null) mitPdf.add((n, bytes));
    }

    final model = FirebaseAI.vertexAI(location: 'europe-west1').generativeModel(
      model: modellId,
      systemInstruction: Content.system(_systemPrompt()),
      generationConfig: GenerationConfig(
        temperature: 0.2,
        maxOutputTokens: 8192,
      ),
    );

    // Historie als Gemini-Content-Liste; frühere Nachrichten nur als Text.
    final contents = <Content>[];
    for (final m in historie) {
      if (m.rolle == 'user') {
        contents.add(Content.text(m.inhalt));
      } else {
        contents.add(Content.model([TextPart(m.inhalt)]));
      }
    }

    // Aktuelle Frage mit Metadaten + ggf. PDFs als Multi-Part.
    final parts = <Part>[
      TextPart(_metadatenBlock()),
      if (mitPdf.isNotEmpty)
        TextPart(
          '\nIm folgenden hängen die PDFs der vermutlich relevanten Normen '
          'an. Nutze ihren Volltext für die Antwort und zitiere Seiten/'
          'Abschnitte, wenn du dich darauf beziehst.\n',
        ),
      for (final (n, bytes) in mitPdf) ...[
        TextPart(
            '\n[Dokument: ${n.nummer}${n.titel != null ? ' — ${n.titel}' : ''}]\n'),
        InlineDataPart('application/pdf', bytes),
      ],
      TextPart('\nFrage: $frageText'),
    ];
    contents.add(Content.multi(parts));

    final response = await model.generateContent(contents);
    final antwort = (response.text ?? '').trim();

    // Usage protokollieren (fire-and-forget).
    final logger = ref.read(kiUsageLoggerProvider);
    final email =
        ref.read(authServiceProvider).currentUser?.email;
    await logger.log(
      aufgabe: KiAufgabe.normenChat,
      modellId: modellId,
      usage: response.usageMetadata,
      userEmail: email,
    );

    final verwendet = mitPdf.map((e) => e.$1).toList();
    historie.add(NormenChatNachricht(rolle: 'user', inhalt: frageText));
    historie.add(NormenChatNachricht(
        rolle: 'assistant',
        inhalt: antwort,
        verwendeteNormen: verwendet));

    return NormenChatAntwort(text: antwort, verwendeteNormen: verwendet);
  }

  String _systemPrompt() => '''
Du bist Recherche-Assistent für einen deutschen Bausachverständigen. Du hast
Zugriff auf seine kuratierte Normen-Bibliothek (Normen, Richtlinien, Merkblätter,
Gesetze). Deine Aufgaben:

1. Beantworte Fragen fachlich korrekt und auf den Punkt, in deutscher Sprache,
   nüchterner Ton.
2. Stütze dich auf die Norm-Metadaten, die dir als Liste vorliegen, und —
   wenn PDFs angehängt sind — auf deren Volltext.
3. **Immer Quellen angeben.** Beziehst du dich auf eine Norm, schreibe die
   Fundstelle direkt in Klammern in den Satz, z. B.:
   „…gemäß DIN 18195-4, Abschnitt 5.2 (S. 12)." Bei Metadaten-Treffern ohne
   PDF-Volltext: „…siehe DIN 18195 (Kurzfassung in der Bibliothek)."
4. Wenn die Antwort in den verfügbaren Quellen NICHT gedeckt ist, sage das
   klar und erfinde nichts. Biete an, die Frage umzuformulieren oder weitere
   Normen einzubinden.
5. Halte dich kurz — maximal 3–6 Sätze pro Antwort, es sei denn der Nutzer
   fragt explizit nach einer ausführlichen Darstellung.
''';

  String _metadatenBlock() {
    final buf = StringBuffer();
    buf.writeln('--- Verfügbare Normen-Bibliothek (Metadaten) ---');
    for (final n in alleNormen) {
      final teile = <String>[];
      teile.add(n.nummer);
      if (n.ausgabe != null && n.ausgabe!.isNotEmpty) {
        teile.add('(${n.ausgabe})');
      }
      if (n.titel != null && n.titel!.isNotEmpty) teile.add('— ${n.titel}');
      if (n.kategorie != null && n.kategorie!.isNotEmpty) {
        teile.add('[${n.kategorie}]');
      }
      if (n.aktualitaetStatus != null) {
        teile.add('[${n.aktualitaetStatus}]');
      }
      if (n.pdfStorageUrl != null && n.pdfStorageUrl!.isNotEmpty) {
        teile.add('[PDF vorhanden]');
      }
      buf.writeln('- ${teile.join(' ')}');
      final zf = (n.zusammenfassung ?? '').trim();
      if (zf.isNotEmpty) buf.writeln('    Zusammenfassung: $zf');
      final besch = (n.beschreibung ?? '').trim();
      if (besch.isNotEmpty && besch != zf) {
        buf.writeln('    Beschreibung: ${_kurz(besch, 280)}');
      }
      final zitat = (n.zitat ?? '').trim();
      if (zitat.isNotEmpty) {
        buf.writeln('    Zitat: ${_kurz(zitat, 280)}');
      }
    }
    buf.writeln('--- Ende Bibliothek ---');
    return buf.toString();
  }

  String _kurz(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max).trimRight()}…';

  /// Einfacher Wort-Overlap-Score zwischen Frage und Norm-Feldern.
  /// Gibt die Normen absteigend nach Trefferzahl sortiert zurück.
  List<NormenData> _matchNormen(String frage) {
    final tokens = _tokens(frage);
    if (tokens.isEmpty) {
      // Ohne Tokens gar keine PDFs anhängen — Metadaten reichen dann.
      return [];
    }
    final scored = <(NormenData, int)>[];
    for (final n in alleNormen) {
      final suchtext = [
        n.nummer,
        n.titel ?? '',
        n.kategorie ?? '',
        n.art ?? '',
        n.herausgeber ?? '',
        n.zusammenfassung ?? '',
        n.beschreibung ?? '',
        n.zitat ?? '',
      ].join(' ').toLowerCase();
      final textTokens = _tokens(suchtext);
      var treffer = 0;
      for (final t in tokens) {
        // Volltreffer oder Teilstring (für Normnummern-Varianten)
        if (textTokens.contains(t) || suchtext.contains(t)) {
          treffer++;
        }
      }
      if (treffer > 0) scored.add((n, treffer));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.map((e) => e.$1).toList();
  }

  /// Tokenisiert und filtert sehr kurze/häufige Wörter heraus, damit
  /// „die/der/das/…" nicht jedes Match dominieren.
  static const _stopworte = {
    'und', 'oder', 'aber', 'der', 'die', 'das', 'den', 'dem', 'des',
    'ein', 'eine', 'einen', 'einem', 'einer', 'eines',
    'mit', 'ohne', 'bei', 'auf', 'für', 'von', 'in', 'im', 'an',
    'zu', 'zur', 'zum', 'ist', 'sind', 'war', 'waren', 'wie', 'was',
    'wo', 'wer', 'wenn', 'dass', 'nicht', 'auch', 'schon',
    'ich', 'du', 'er', 'sie', 'es', 'wir', 'ihr',
    'mir', 'mich', 'dir', 'dich', 'sich',
  };

  Set<String> _tokens(String s) {
    final raw = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zäöüß0-9\-\s]'), ' ')
        .split(RegExp(r'\s+'));
    return raw
        .where((t) => t.length >= 3 && !_stopworte.contains(t))
        .toSet();
  }

  Future<Uint8List?> _ladePdf(int id, String url) async {
    final cached = _pdfCache[id];
    if (cached != null) return cached;
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) return null;
      _pdfCache[id] = resp.bodyBytes;
      return resp.bodyBytes;
    } catch (_) {
      return null;
    }
  }
}
