import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/system/einstellungen/einstellungen_repository.dart';

/// Katalog der in der App verwendbaren Gemini-Modelle. Preise in USD
/// pro 1 Mio. Tokens (Stand 2026; Vertex-AI-Listenpreise für Text).
/// Preise nur als Orientierung — exakter Rechnungswert steht bei
/// Google Cloud Billing.
class KiModellInfo {
  const KiModellInfo({
    required this.id,
    required this.label,
    required this.beschreibung,
    required this.preisInput,
    required this.preisOutput,
    this.location = 'europe-west3',
  });
  final String id;
  final String label;
  final String beschreibung;

  /// USD pro 1.000.000 Input-Tokens.
  final double preisInput;

  /// USD pro 1.000.000 Output-Tokens.
  final double preisOutput;

  /// Google Cloud Vertex AI Rechenzentrums-Standort (z. B. 'europe-west3' für Frankfurt oder 'global').
  final String location;
}

const kiModelle = <KiModellInfo>[
  // ---------- Gemini 3.x (aktuelle Generation, 2026) ----------
  KiModellInfo(
    id: 'gemini-3.5-flash',
    label: 'Gemini 3.5 Flash',
    beschreibung:
        'Aktueller Allrounder — blitzschnell, hochintelligent und kosteneffizient. Gehostet in Frankfurt (europe-west3). Empfohlen für die meisten Aufgaben.',
    preisInput: 0.30,
    preisOutput: 2.50,
    location: 'europe-west3',
  ),
  KiModellInfo(
    id: 'gemini-3.1-pro-preview',
    label: 'Gemini 3.1 Pro (Preview)',
    beschreibung:
        'Höchste Reasoning- & Analyse-Fähigkeit — empfohlen für Normen-Chat, Beweisbeschluss-Prüfung und anspruchsvolle juristische Texte.',
    preisInput: 2.00,
    preisOutput: 12.00,
    location: 'global',
  ),
  // ---------- Gemini 2.5 (Vorgänger-Generation — Abschaltung 16. Oktober 2026) ----------
  KiModellInfo(
    id: 'gemini-2.5-flash',
    label: 'Gemini 2.5 Flash (Legacy)',
    beschreibung: 'Vorgängermodell — wird am 16. Oktober 2026 von Google eingestellt.',
    preisInput: 0.30,
    preisOutput: 2.50,
    location: 'europe-west1',
  ),
  KiModellInfo(
    id: 'gemini-2.5-pro',
    label: 'Gemini 2.5 Pro (Legacy)',
    beschreibung: 'Vorgängermodell — wird am 16. Oktober 2026 von Google eingestellt.',
    preisInput: 1.25,
    preisOutput: 10.00,
    location: 'europe-west1',
  ),
  KiModellInfo(
    id: 'gemini-2.5-flash-lite',
    label: 'Gemini 2.5 Flash-Lite (Legacy)',
    beschreibung: 'Vorgängermodell — wird am 16. Oktober 2026 von Google eingestellt.',
    preisInput: 0.10,
    preisOutput: 0.40,
    location: 'europe-west1',
  ),
];

const kiModellFallback = 'gemini-3.5-flash';

/// Liefert Modell-Info zu einer ID, oder den Flash-Default.
KiModellInfo kiModellInfo(String id) {
  return kiModelle.firstWhere(
    (m) => m.id == id,
    orElse: () => kiModelle.firstWhere((m) => m.id == kiModellFallback),
  );
}

/// Erzeugt ein [GenerativeModel] von Vertex AI mit der für das Modell passenden
/// Region (z.B. Frankfurt 'europe-west3' für Gemini 3.5 Flash oder 'global' für 3.1 Pro).
GenerativeModel getVertexGenerativeModel({
  required String modelId,
  Content? systemInstruction,
  GenerationConfig? generationConfig,
}) {
  final info = kiModellInfo(modelId);
  return FirebaseAI.vertexAI(location: info.location).generativeModel(
    model: info.id,
    systemInstruction: systemInstruction,
    generationConfig: generationConfig,
  );
}

/// Die in der App adressierbaren KI-Aufgaben. Jeder Typ hat einen
/// eigenen Settings-Key und einen sinnvollen Default.
enum KiAufgabe {
  korrektur,
  umformulieren,
  juristisch,
  kuerzen,
  erweitern,
  normenChat,
  audioTranskript,
  belegErfassung,
}

extension KiAufgabeKonfig on KiAufgabe {
  String get label => switch (this) {
        KiAufgabe.korrektur => 'Rechtschreibung & Grammatik',
        KiAufgabe.umformulieren => 'Umformulieren',
        KiAufgabe.juristisch => 'Rechtsanwalts-/Gerichtssprache',
        KiAufgabe.kuerzen => 'Kürzer fassen',
        KiAufgabe.erweitern => 'Ausführlicher fassen',
        KiAufgabe.normenChat => 'Normen-Chat (mit PDF-Lesen)',
        KiAufgabe.audioTranskript =>
          'Audio-Transkript (Ortstermin-Notizen)',
        KiAufgabe.belegErfassung =>
          'Belegerfassung (Eingangsrechnungen)',
      };

  String get settingsKey => switch (this) {
        KiAufgabe.korrektur => SettingsKeys.kiModellKorrektur,
        KiAufgabe.umformulieren => SettingsKeys.kiModellUmformulieren,
        KiAufgabe.juristisch => SettingsKeys.kiModellJuristisch,
        KiAufgabe.kuerzen => SettingsKeys.kiModellKuerzen,
        KiAufgabe.erweitern => SettingsKeys.kiModellErweitern,
        KiAufgabe.normenChat => SettingsKeys.kiModellNormenChat,
        KiAufgabe.audioTranskript =>
          SettingsKeys.kiModellAudioTranskript,
        KiAufgabe.belegErfassung =>
          SettingsKeys.kiModellBelegErfassung,
      };

  String get defaultModell => switch (this) {
        // Reasoning-lastige Features bekommen 3.1 Pro; allround Text-Transforms
        // laufen standardmäßig mit 3.5 Flash.
        KiAufgabe.juristisch => 'gemini-3.1-pro-preview',
        KiAufgabe.normenChat => 'gemini-3.1-pro-preview',
        _ => 'gemini-3.5-flash',
      };
}

/// Holt die gespeicherte Modell-ID für eine Aufgabe oder liefert den
/// passenden Default. Wird beim jedem KI-Aufruf aufgerufen.
Future<String> getKiModell(
  EinstellungenRepository repo,
  KiAufgabe aufgabe,
) async {
  final gespeicherteId = await repo.getOr(aufgabe.settingsKey, aufgabe.defaultModell);
  // Falls noch ein alter Name gespeichert ist (z.B. 'gemini-3-flash' oder 'gemini-3-pro'),
  // mappen wir automatisch auf die aktuellen gültigen Modell-IDs.
  if (gespeicherteId == 'gemini-3-flash') return 'gemini-3.5-flash';
  if (gespeicherteId == 'gemini-3-pro') return 'gemini-3.1-pro-preview';
  return gespeicherteId;
}

/// Riverpod-Provider für bequemen Zugriff (liefert die Modell-IDs aller
/// Aufgaben in einer Map — UI kann direkt darauf hören).
final kiModellMapProvider = FutureProvider<Map<KiAufgabe, String>>((ref) async {
  final repo = ref.watch(einstellungenRepositoryProvider);
  final map = <KiAufgabe, String>{};
  for (final a in KiAufgabe.values) {
    map[a] = await getKiModell(repo, a);
  }
  return map;
});
