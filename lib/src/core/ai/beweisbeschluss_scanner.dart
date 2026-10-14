import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/auth_service.dart';
import '../../features/system/einstellungen/einstellungen_repository.dart';
import 'ki_modelle.dart';
import 'ki_usage_service.dart';

Schema _buildFragenSchema() => Schema.object(properties: {
  'fragen': Schema.array(
    description: 'Liste der extrahierten Beweisfragen.',
    items: Schema.object(properties: {
      'nr': Schema.string(description: 'Nummer der Beweisfrage (falls vorhanden)'),
      'frage': Schema.string(description: 'Wortlaut der Beweisfrage'),
      'einschaetzung': Schema.string(description: 'Einschätzung der KI: Ist die Frage klar formuliert, beinhaltet sie unzulässige rechtliche Würdigungen oder liegt sie außerhalb des Sachgebiets?'),
    }),
  ),
});

Future<List<Map<String, dynamic>>> extrahiereBeweisfragen({
  required WidgetRef ref,
  required Uint8List bytes,
  required String mimeType,
}) async {
  final repo = ref.read(einstellungenRepositoryProvider);
  final sachgebiet = await repo.getOr(SettingsKeys.svSachgebiet, 'Allgemein');
  
  // Wir nutzen hier das juristische Modell (default 3-Pro), da es
  // oft komplexe Gerichtsbeschlüsse lesen muss.
  final modellId = await getKiModell(repo, KiAufgabe.juristisch);

  final model = getVertexGenerativeModel(
    modelId: modellId,
    systemInstruction: Content.system(
      'Du bist ein Assistent für Gerichtssachverständige. Dein Sachgebiet ist: "$sachgebiet".\n'
      'Lies den hochgeladenen Beweisbeschluss und extrahiere exakt die an den Sachverständigen gestellten Beweisfragen. '
      'Gebe sie wortwörtlich und unverändert im Feld "frage" zurück. '
      'Zusätzlich bewerte jede Frage kurz im Feld "einschaetzung": '
      '1. Ist die Frage richtig und verständlich gestellt? '
      '2. Vermischt die Frage unzulässigerweise tatsächliche Feststellungen mit rechtlichen Würdigungen (z.B. Schuldfragen)? '
      '3. Kann die Frage nach deinem Sachgebiet überhaupt beantwortet werden? '
      'Fasse dies in einem kurzen Satz zusammen (z.B. "Unproblematisch" oder "Achtung: Enthält rechtliche Würdigung").'
    ),
    generationConfig: GenerationConfig(
      temperature: 0.1,
      responseMimeType: 'application/json',
      responseSchema: _buildFragenSchema(),
    ),
  );

  final response = await model.generateContent([
    Content.multi([
      TextPart('Extrahiere die Beweisfragen und bewerte sie gemäß dem vorgegebenen JSON-Schema.'),
      InlineDataPart(mimeType, bytes),
    ]),
  ]);

  try {
    final logger = ref.read(kiUsageLoggerProvider);
    final email = ref.read(authServiceProvider).currentUser?.email;
    await logger.log(
      aufgabe: KiAufgabe.juristisch,
      modellId: modellId,
      usage: response.usageMetadata,
      userEmail: email,
    );
  } catch (_) {}

  String raw = (response.text ?? '').trim();
  raw = raw.replaceAll(RegExp(r'^```json\s*'), '').replaceAll(RegExp(r'\s*```$'), '');
  if (raw.isEmpty) {
    throw Exception('Leere Antwort vom Modell.');
  }
  final parsed = jsonDecode(raw);
  if (parsed is! Map || !parsed.containsKey('fragen')) {
    throw Exception('Antwort war kein gültiges JSON-Objekt mit einem "fragen" Array.');
  }

  final fragenList = parsed['fragen'] as List<dynamic>;
  return fragenList.map((e) {
    if (e is Map) {
      return e.map((k, v) => MapEntry(k.toString(), v));
    } else if (e is String) {
      return {'frage': e};
    }
    return <String, dynamic>{};
  }).toList();
}
