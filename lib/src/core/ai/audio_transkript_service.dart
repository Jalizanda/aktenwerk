import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show WidgetRef;

import '../../data/sync/auth_service.dart';
import '../../features/system/einstellungen/einstellungen_repository.dart';
import 'ki_modelle.dart';
import 'ki_usage_service.dart';

/// Ergebnis einer Audio-Transkription: wortgetreues Transkript und
/// eine sachliche Zusammenfassung.
class AudioTranskript {
  const AudioTranskript({
    required this.transkript,
    required this.zusammenfassung,
  });
  final String transkript;
  final String zusammenfassung;

  /// Kombinierter Text zum Ablegen als Notiz.
  String kombiniert(int nummer) =>
      'Transkript von Audio-Aufnahme $nummer\n\n'
      '$zusammenfassung\n\n'
      '— — — Wortlaut — — —\n'
      '$transkript';
}

/// Schickt eine Audio-Datei an Gemini und bekommt wortgetreues
/// Transkript + saubere Zusammenfassung zurück. Die Zuordnung Modell ↔
/// Aufgabe kommt aus den Einstellungen ([KiAufgabe.audioTranskript]).
Future<AudioTranskript> transkribiereAudio(
  WidgetRef ref,
  Uint8List bytes,
  String mimeType,
) async {
  final repo = ref.read(einstellungenRepositoryProvider);
  final modellId = await getKiModell(repo, KiAufgabe.audioTranskript);

  final model = FirebaseAI.vertexAI(location: 'europe-west1').generativeModel(
    model: modellId,
    systemInstruction: Content.system(
      'Du bist Transkriptions-Assistent für einen deutschen '
      'Bausachverständigen. Er nimmt vor Ort Notizen per Diktat auf.\n\n'
      'Deine Aufgabe:\n'
      '1. Transkribiere das Audio wortgetreu ins Deutsche. Erhalte '
      'Fachbegriffe, Maße, Zahlen, Hausnummern exakt.\n'
      '2. Fasse den Inhalt anschließend sachlich und knapp in '
      'Stichpunkten zusammen (Feststellungen, Maße, Schäden, '
      'geplante Maßnahmen, nächste Schritte).\n'
      '3. Wenn Stellen unverständlich sind, kennzeichne sie mit [unklar].\n'
      '4. Antworte STRIKT in genau diesem Format — keine Markdown-'
      'Überschriften, nur diese zwei Marker:\n\n'
      'TRANSKRIPT:\n'
      '<wortgetreues Transkript>\n\n'
      'ZUSAMMENFASSUNG:\n'
      '- <Stichpunkt>\n'
      '- <Stichpunkt>\n'
      '- …',
    ),
    generationConfig: GenerationConfig(
      temperature: 0.1,
      maxOutputTokens: 4096,
    ),
  );

  final response = await model.generateContent([
    Content.multi([
      TextPart(
          'Bitte dieses Audio transkribieren und zusammenfassen.'),
      InlineDataPart(mimeType, bytes),
    ]),
  ]);

  // Usage protokollieren.
  final logger = ref.read(kiUsageLoggerProvider);
  final email = ref.read(authServiceProvider).currentUser?.email;
  await logger.log(
    aufgabe: KiAufgabe.audioTranskript,
    modellId: modellId,
    usage: response.usageMetadata,
    userEmail: email,
  );

  final text = (response.text ?? '').trim();
  if (text.isEmpty) {
    throw Exception('Leere Antwort vom Modell.');
  }
  return _parseAntwort(text);
}

AudioTranskript _parseAntwort(String text) {
  final transMarker = RegExp(r'TRANSKRIPT\s*:\s*\n', caseSensitive: false);
  final zusammenMarker =
      RegExp(r'ZUSAMMENFASSUNG\s*:\s*\n', caseSensitive: false);

  final transMatch = transMarker.firstMatch(text);
  final zusMatch = zusammenMarker.firstMatch(text);

  String transkript = '';
  String zusammenfassung = '';

  if (transMatch != null && zusMatch != null) {
    transkript = text.substring(transMatch.end, zusMatch.start).trim();
    zusammenfassung = text.substring(zusMatch.end).trim();
  } else if (transMatch != null) {
    transkript = text.substring(transMatch.end).trim();
  } else if (zusMatch != null) {
    zusammenfassung = text.substring(zusMatch.end).trim();
    transkript = text.substring(0, zusMatch.start).trim();
  } else {
    // Kein Marker — Antwort als Zusammenfassung nehmen.
    zusammenfassung = text;
  }
  return AudioTranskript(
    transkript: transkript,
    zusammenfassung: zusammenfassung,
  );
}
