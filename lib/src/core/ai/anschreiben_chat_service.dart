import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show WidgetRef;

import '../../data/database/app_database.dart';
import '../../data/sync/auth_service.dart';
import '../../features/system/einstellungen/einstellungen_repository.dart';
import 'ki_modelle.dart';
import 'ki_usage_service.dart';

/// Kontext für einen KI-geführten Anschreiben-Entwurf: Empfänger und
/// Akte sind optional; wenn gesetzt, gibt die KI Anrede, Aktenzeichen
/// und Objekt-Referenz direkt an.
class AnschreibenKontext {
  const AnschreibenKontext({
    this.kunde,
    this.auftrag,
    this.absender,
    this.betreff,
  });
  final KundenData? kunde;
  final AuftraegeData? auftrag;
  final BenutzerData? absender;
  final String? betreff;
}

/// Eine Nachricht in der Chat-Historie.
class AnschreibenChatNachricht {
  AnschreibenChatNachricht({required this.rolle, required this.inhalt});
  final String rolle; // 'user' oder 'assistant'
  final String inhalt;
}

/// Chat-Session zum Entwerfen eines Anschreibens mit der KI. Der Nutzer
/// beschreibt per Prompt, was im Brief stehen soll; die KI liefert
/// jedes Mal einen vollständig überarbeiteten Brief-Text zurück. Der
/// zuletzt gesendete Entwurf kann per „Übernehmen" in den Anschreiben-
/// Editor kopiert werden.
class AnschreibenChatSession {
  AnschreibenChatSession(this.ref, this.kontext);

  final WidgetRef ref;
  final AnschreibenKontext kontext;

  final List<AnschreibenChatNachricht> historie = [];

  /// Letzter Brief-Entwurf der KI — wird beim Übernehmen in das
  /// Anschreiben übertragen.
  String? get letzterEntwurf {
    for (var i = historie.length - 1; i >= 0; i--) {
      if (historie[i].rolle == 'assistant') return historie[i].inhalt;
    }
    return null;
  }

  Future<String> frage(String nutzerText) async {
    final trimmed = nutzerText.trim();
    if (trimmed.isEmpty) return letzterEntwurf ?? '';
    final repo = ref.read(einstellungenRepositoryProvider);
    // „umformulieren" passt gut — Brief-Textgenerierung ist keine
    // Reasoning-intensive Aufgabe, Flash reicht.
    final modellId = await getKiModell(repo, KiAufgabe.umformulieren);

    final model = FirebaseAI.vertexAI(location: 'europe-west1').generativeModel(
      model: modellId,
      systemInstruction: Content.system(_systemPrompt()),
      generationConfig: GenerationConfig(
        temperature: 0.4,
        maxOutputTokens: 8192,
      ),
    );

    // Chat-Historie als Gemini-Content-Liste.
    final contents = <Content>[];
    contents.add(Content.text(_kontextBlock()));
    for (final m in historie) {
      if (m.rolle == 'user') {
        contents.add(Content.text(m.inhalt));
      } else {
        contents.add(Content.model([TextPart(m.inhalt)]));
      }
    }
    contents.add(Content.text(trimmed));

    final response = await model.generateContent(contents);
    final antwort = (response.text ?? '').trim();

    final logger = ref.read(kiUsageLoggerProvider);
    final email = ref.read(authServiceProvider).currentUser?.email;
    await logger.log(
      aufgabe: KiAufgabe.umformulieren,
      modellId: modellId,
      usage: response.usageMetadata,
      userEmail: email,
    );

    historie.add(AnschreibenChatNachricht(rolle: 'user', inhalt: trimmed));
    historie.add(
        AnschreibenChatNachricht(rolle: 'assistant', inhalt: antwort));
    return antwort;
  }

  String _systemPrompt() => '''
Du bist ein professioneller Schreibassistent für einen deutschen
Bausachverständigen. Du entwirfst formelle Anschreiben (Briefe) auf Basis
der Stichworte des Nutzers.

Regeln:
1. Antworte IMMER mit dem vollständigen, fertigen Brief-Text — bereit zum
   Einfügen in ein Anschreiben-Dokument. Keine Überschriften wie „Brief:",
   keine Vorworte, keine Erklärungen, kein Markdown, kein HTML — nur der
   reine Brief-Fließtext.
2. Beginne mit der passenden Anrede (z. B. „Sehr geehrter Herr Müller,"),
   gefolgt vom eigentlichen Brieftext. Schließe mit „Mit freundlichen
   Grüßen" auf einer neuen Zeile ab (ohne Namen — der Absender wird
   automatisch ergänzt).
3. Ton: sachlich, höflich, präzise. Keine juristischen Floskeln, es sei
   denn der Nutzer bittet darum.
4. Wenn der Nutzer Änderungswünsche äußert ("kürzer", "förmlicher",
   "Passage X ändern in …"), gib den Brief komplett neu zurück — nicht
   nur den geänderten Teil.
5. Nutze die Kontextdaten (Akte, Empfänger, Objekt) aktiv, wo sinnvoll —
   z. B. Aktenzeichen im Betreff-ähnlichen Einleitungssatz oder
   Objektadresse im ersten Absatz.
6. Wenn der Nutzer etwas fragt, das du ohne Rückfrage nicht beantworten
   kannst (z. B. fehlende Fakten), formuliere einen Platzhalter in
   eckigen Klammern, z. B. „[Datum der Besprechung ergänzen]".
''';

  String _kontextBlock() {
    final buf = StringBuffer();
    buf.writeln('--- Kontext für dieses Anschreiben ---');
    final k = kontext.kunde;
    if (k != null) {
      final empfaenger = [
        if ((k.firma ?? '').isNotEmpty) k.firma,
        [k.titel, k.vorname, k.nachname]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(' '),
      ].whereType<String>().where((s) => s.isNotEmpty).join(' / ');
      if (empfaenger.isNotEmpty) buf.writeln('Empfänger: $empfaenger');
      final adresse = [
        k.strasse,
        [k.plz, k.ort]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(' '),
      ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
      if (adresse.isNotEmpty) buf.writeln('Anschrift: $adresse');
    }
    final a = kontext.auftrag;
    if (a != null) {
      if ((a.aktenzeichen ?? '').isNotEmpty) {
        buf.writeln('Aktenzeichen: ${a.aktenzeichen}');
      }
      if ((a.gerichtsAktenzeichen ?? '').isNotEmpty) {
        buf.writeln('Gerichts-Az.: ${a.gerichtsAktenzeichen}');
      }
      final objekt = [
        a.objektStrasse,
        [a.objektPlz, a.objektOrt]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(' '),
      ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
      if (objekt.isNotEmpty) buf.writeln('Objekt: $objekt');
      if ((a.bezeichnung ?? '').isNotEmpty) {
        buf.writeln('Kurzbezeichnung der Akte: ${a.bezeichnung}');
      }
    }
    final abs = kontext.absender;
    if (abs != null) {
      final absName = [abs.vorname, abs.nachname]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join(' ');
      if (absName.isNotEmpty) buf.writeln('Absender: $absName');
      if ((abs.firma ?? '').isNotEmpty) {
        buf.writeln('Absender-Firma: ${abs.firma}');
      }
    }
    final b = (kontext.betreff ?? '').trim();
    if (b.isNotEmpty) buf.writeln('Betreff-Entwurf: $b');
    buf.writeln('--- Ende Kontext ---');
    buf.writeln();
    buf.writeln(
        'Der Nutzer beschreibt nun, was im Brief stehen soll. Nach jedem '
        'Prompt gibst du den vollständig neuen Brief zurück.');
    return buf.toString();
  }
}
