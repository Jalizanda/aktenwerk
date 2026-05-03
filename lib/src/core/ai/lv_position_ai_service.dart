import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show WidgetRef;

import '../../data/sync/auth_service.dart';
import '../../features/system/einstellungen/einstellungen_repository.dart';
import 'ki_modelle.dart';
import 'ki_usage_service.dart';

/// KI-gestützte Generierung eines fachlich korrekten Langtextes für
/// LV-Positionen. Eingabe: Kurztext + optional Gewerk + Einheit.
/// Ausgabe: ein 3–6-zeiliger Langtext mit Material, Verarbeitung,
/// Norm-Bezug (WTA/DIN), Aufmaßregel.
Future<String?> generiereLangtext(
  WidgetRef ref, {
  required String kurztext,
  String? gewerk,
  String? einheit,
}) async {
  final trimmed = kurztext.trim();
  if (trimmed.isEmpty) return null;

  final repo = ref.read(einstellungenRepositoryProvider);
  // Wir nutzen das gleiche Modell wie für „Erweitern" — der Auftrag ist
  // semantisch sehr ähnlich (kurzer Text → ausführliche Variante).
  final modellId =
      await getKiModell(repo, KiAufgabe.erweitern);

  final systemPrompt = '''
Du bist ein erfahrener Sachverständiger für Bauschäden und kennst die
einschlägigen Normen und Verarbeitungsregeln (WTA-Merkblätter, DIN 18299
ff., DIN 18533, DIN 55699, DIN 4108-2, DIN 18560, DIN 68800, GAEB).

Aufgabe: Aus einem Kurztext einer LV-Position formulierst du einen
fachlich präzisen Langtext im Stil eines Standardleistungsbuchs.

Regeln:
- 3 bis 6 Sätze, präzise und vollständig
- Material/Produktanforderung benennen (Norm, Hersteller-Kategorie, Klasse)
- Verarbeitung beschreiben (Untergrund, Schichten, Verarbeitungsregeln)
- Wenn relevant: Bezug zur Norm/Merkblatt explizit zitieren
- Aufmaßregel kurz erwähnen, wenn nicht offensichtlich (z. B.
  „Aufmaß als brutto Wandfläche, ohne Abzug Öffnungen < 0,5 m²")
- KEINE Preise nennen
- KEINE Einleitung wie „Hier ist der Langtext:" — direkt loslegen
- Sprache: deutsch, neutral, Fachsprache angemessen
- Maximal 600 Zeichen
''';

  final benutzerPrompt = '''
Kurztext: $trimmed
${gewerk == null || gewerk.isEmpty ? "" : "Gewerk: $gewerk\n"}${einheit == null || einheit.isEmpty ? "" : "Einheit: $einheit\n"}
Bitte generiere den passenden Langtext.
''';

  final model =
      FirebaseAI.vertexAI(location: 'europe-west1').generativeModel(
    model: modellId,
    systemInstruction: Content.system(systemPrompt),
    generationConfig: GenerationConfig(
      temperature: 0.4,
      maxOutputTokens: 1024,
    ),
  );

  final response = await model.generateContent([Content.text(benutzerPrompt)]);

  // Usage-Logging
  final logger = ref.read(kiUsageLoggerProvider);
  final email = ref.read(authServiceProvider).currentUser?.email;
  await logger.log(
    aufgabe: KiAufgabe.erweitern,
    modellId: modellId,
    usage: response.usageMetadata,
    userEmail: email,
  );

  final out = response.text?.trim();
  if (out == null || out.isEmpty) return null;
  return out;
}
