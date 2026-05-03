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
  });
  final String id;
  final String label;
  final String beschreibung;

  /// USD pro 1.000.000 Input-Tokens.
  final double preisInput;

  /// USD pro 1.000.000 Output-Tokens.
  final double preisOutput;
}

const kiModelle = <KiModellInfo>[
  // ---------- Gemini 3 (aktuelle Generation, Nov 2025) ----------
  KiModellInfo(
    id: 'gemini-3-flash',
    label: 'Gemini 3 Flash',
    beschreibung:
        'Aktueller Allrounder — schneller und besser als 2.5 Flash bei nahezu gleichem Preis. Empfohlen für die meisten Aufgaben.',
    preisInput: 0.30,
    preisOutput: 2.50,
  ),
  KiModellInfo(
    id: 'gemini-3-pro',
    label: 'Gemini 3 Pro',
    beschreibung:
        'Stärkste Reasoning-Fähigkeit aktuell — empfohlen für Normen-Chat, juristische Texte, lange Kontexte.',
    preisInput: 2.00,
    preisOutput: 12.00,
  ),
  // ---------- Gemini 2.5 (vorige Generation, weiterhin nutzbar) ----------
  KiModellInfo(
    id: 'gemini-2.5-flash-lite',
    label: 'Gemini 2.5 Flash-Lite',
    beschreibung:
        'Sehr günstig, schnell — reicht für simple Rechtschreibkorrektur.',
    preisInput: 0.10,
    preisOutput: 0.40,
  ),
  KiModellInfo(
    id: 'gemini-2.5-flash',
    label: 'Gemini 2.5 Flash',
    beschreibung: 'Vorgängermodell — etwas günstiger als 3 Flash.',
    preisInput: 0.30,
    preisOutput: 2.50,
  ),
  KiModellInfo(
    id: 'gemini-2.5-pro',
    label: 'Gemini 2.5 Pro',
    beschreibung: 'Vorgängermodell — etwas günstiger als 3 Pro.',
    preisInput: 1.25,
    preisOutput: 10.00,
  ),
];

const kiModellFallback = 'gemini-3-flash';

/// Liefert Modell-Info zu einer ID, oder den Flash-Default.
KiModellInfo kiModellInfo(String id) {
  return kiModelle.firstWhere(
    (m) => m.id == id,
    orElse: () => kiModelle.firstWhere((m) => m.id == kiModellFallback),
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
        // Reasoning-lastige Features brauchen Pro; simple Text-Transforms
        // laufen billig mit Flash.
        KiAufgabe.juristisch => 'gemini-3-pro',
        KiAufgabe.normenChat => 'gemini-3-pro',
        _ => 'gemini-3-flash',
      };
}

/// Holt die gespeicherte Modell-ID für eine Aufgabe oder liefert den
/// passenden Default. Wird beim jedem KI-Aufruf aufgerufen.
Future<String> getKiModell(
  EinstellungenRepository repo,
  KiAufgabe aufgabe,
) async {
  return repo.getOr(aufgabe.settingsKey, aufgabe.defaultModell);
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
