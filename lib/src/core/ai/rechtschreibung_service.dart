import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show WidgetRef;

import '../../data/sync/auth_service.dart';
import '../../features/system/einstellungen/einstellungen_repository.dart';
import 'ki_modelle.dart';
import 'ki_usage_service.dart';

/// Die unterschiedlichen KI-Modi, die auf einen Text angewendet werden
/// können. Jeder Modus hat einen eigenen System-Prompt, der die
/// gewünschte Transformation beschreibt.
enum KiModus {
  /// Rechtschreibung, Grammatik und Zeichensetzung korrigieren — Stil
  /// und Struktur bleiben unverändert.
  korrektur,

  /// Den Text stilistisch umformulieren (gleiche Aussage, neue Formulierung).
  umformulieren,

  /// In juristische/gerichtssprachliche Diktion umformulieren.
  juristisch,

  /// Den Text inhaltlich unverändert, aber deutlich kürzer fassen.
  kuerzen,

  /// Den Text ausführlicher und konkreter fassen, ohne neue Fakten zu erfinden.
  erweitern,
}

extension KiModusLabel on KiModus {
  String get label => switch (this) {
        KiModus.korrektur => 'Rechtschreibung & Grammatik prüfen',
        KiModus.umformulieren => 'Umformulieren',
        KiModus.juristisch => 'In Rechtsanwalts-/Gerichtssprache',
        KiModus.kuerzen => 'Kürzer fassen',
        KiModus.erweitern => 'Ausführlicher fassen',
      };

  String get kurzLabel => switch (this) {
        KiModus.korrektur => 'Korrektur',
        KiModus.umformulieren => 'Umformulierung',
        KiModus.juristisch => 'Juristische Fassung',
        KiModus.kuerzen => 'Kurzfassung',
        KiModus.erweitern => 'Langfassung',
      };
}

String _systemPrompt(KiModus modus) => switch (modus) {
      KiModus.korrektur =>
        'Du bist ein deutscher Lektor für Geschäftsbriefe. Korrigiere '
            'ausschließlich Rechtschreib-, Grammatik- und Zeichensetzungsfehler '
            'im folgenden Text. Wichtige Regeln:\n'
            '1. Stil, Tonfall, Wortwahl und Satzstruktur bleiben unverändert.\n'
            '2. Zeilenumbrüche und Absätze bleiben exakt erhalten.\n'
            '3. Keine Umformulierungen, keine inhaltlichen Ergänzungen.\n'
            '4. Wenn der Text bereits korrekt ist, gib ihn wortgleich zurück.\n'
            '5. Antworte NUR mit dem korrigierten Text — ohne Vorwort, '
            'Anführungszeichen oder Markdown-Blöcke.',
      KiModus.umformulieren =>
        'Du formulierst Geschäftsbriefe eines Bausachverständigen sprachlich '
            'um. Formuliere den folgenden Text neu — gleiche Aussage, '
            'klarerer Ausdruck, geschmeidigerer Lesefluss. Wichtige Regeln:\n'
            '1. Inhalt und Kernaussagen bleiben unverändert — keine Fakten '
            'erfinden, weglassen oder verfälschen.\n'
            '2. Professioneller, sachlicher Ton.\n'
            '3. Zeilenumbrüche/Absätze bleiben inhaltlich sinnvoll — '
            'Absatzstruktur darf leicht angepasst werden.\n'
            '4. Antworte NUR mit dem neuformulierten Text — ohne Vorwort, '
            'Anführungszeichen oder Markdown-Blöcke.',
      KiModus.juristisch =>
        'Du bist Verfasser juristischer Schriftsätze und Schreiben an '
            'Gerichte, Anwälte und Behörden. Überführe den folgenden Text in '
            'die übliche juristische Diktion (Rechtsanwalts-/Gerichtssprache). '
            'Wichtige Regeln:\n'
            '1. Sachverhalt und Kernaussagen bleiben unverändert — keine '
            'Fakten hinzufügen, weglassen oder verändern.\n'
            '2. Verwende präzise, förmliche Formulierungen, die im '
            'gerichtlichen Schriftverkehr üblich sind. Wo passend, nutze '
            'Passivkonstruktionen und Nominalstil.\n'
            '3. Erhalte Absätze und Aufzählungen.\n'
            '4. Keine Paragrafen oder Gesetze erfinden. Bezeichnungen, die '
            'bereits im Originaltext stehen, dürfen übernommen werden.\n'
            '5. Antworte NUR mit dem neuformulierten Text — ohne Vorwort, '
            'Anführungszeichen oder Markdown-Blöcke.',
      KiModus.kuerzen =>
        'Du straffst Geschäftsbriefe eines Bausachverständigen. Fasse den '
            'folgenden Text deutlich kürzer — Ziel: etwa halbe Länge bei '
            'unverändertem Aussagegehalt. Wichtige Regeln:\n'
            '1. Keine Kernaussage, keine Namen, Daten oder Zahlen weglassen.\n'
            '2. Keine neuen Informationen oder Fakten hinzufügen.\n'
            '3. Entferne Redundanzen, Füllwörter und umständliche '
            'Formulierungen. Sachlicher, professioneller Ton.\n'
            '4. Absatzstruktur darf angepasst werden, bleibt aber lesbar.\n'
            '5. Antworte NUR mit dem gekürzten Text — ohne Vorwort, '
            'Anführungszeichen oder Markdown-Blöcke.',
      KiModus.erweitern =>
        'Du formulierst Geschäftsbriefe eines Bausachverständigen '
            'ausführlicher. Formuliere den folgenden Text konkreter und '
            'präziser aus — Ziel: etwa anderthalbfache Länge durch stärkere '
            'Ausformulierung bestehender Aussagen. Wichtige Regeln:\n'
            '1. Keine neuen Fakten, Namen, Zahlen oder Daten erfinden — '
            'ausschließlich das explizit Gesagte präzisieren und '
            'ausformulieren.\n'
            '2. Wenn eine Information fehlt, NICHT spekulieren, sondern '
            'die Stelle so lassen, wie sie im Original war.\n'
            '3. Sachlicher, professioneller Ton.\n'
            '4. Erhalte Absatzstruktur und Reihenfolge der Argumente.\n'
            '5. Antworte NUR mit dem ausführlicheren Text — ohne Vorwort, '
            'Anführungszeichen oder Markdown-Blöcke.',
    };

/// Ordnet KiModus → KiAufgabe zu (für Modell-Auswahl in Einstellungen).
KiAufgabe _modusZuAufgabe(KiModus m) => switch (m) {
      KiModus.korrektur => KiAufgabe.korrektur,
      KiModus.umformulieren => KiAufgabe.umformulieren,
      KiModus.juristisch => KiAufgabe.juristisch,
      KiModus.kuerzen => KiAufgabe.kuerzen,
      KiModus.erweitern => KiAufgabe.erweitern,
    };

/// Wendet den gewählten KI-Modus auf den Text an und gibt das Ergebnis
/// zurück. Das verwendete Modell stammt aus den Einstellungen und kann
/// pro Aufgabe separat gewählt werden.
Future<String> kiAnwenden(
  WidgetRef ref,
  String text,
  KiModus modus,
) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return text;

  final repo = ref.read(einstellungenRepositoryProvider);
  final modellId = await getKiModell(repo, _modusZuAufgabe(modus));

  final model = FirebaseAI.vertexAI(location: 'europe-west1').generativeModel(
    model: modellId,
    systemInstruction: Content.system(_systemPrompt(modus)),
    generationConfig: GenerationConfig(
      temperature: modus == KiModus.korrektur ? 0.1 : 0.4,
      maxOutputTokens: 8192,
    ),
  );

  final response = await model.generateContent([Content.text(trimmed)]);

  // Usage protokollieren (fire-and-forget).
  final logger = ref.read(kiUsageLoggerProvider);
  final email =
      ref.read(authServiceProvider).currentUser?.email;
  await logger.log(
    aufgabe: _modusZuAufgabe(modus),
    modellId: modellId,
    usage: response.usageMetadata,
    userEmail: email,
  );

  final ergebnis = response.text?.trim();
  if (ergebnis == null || ergebnis.isEmpty) return text;
  return ergebnis;
}
