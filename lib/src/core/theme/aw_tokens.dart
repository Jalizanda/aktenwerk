import 'package:flutter/material.dart';

/// Aktenwerk Design Tokens — Dart-Mirror von `handoff/tokens.css` und
/// `handoff/tokens.ts`. Farben, Radien, Typo-Spacings, Status-Zuordnung.
///
/// Regel: Orange ist Akzent, nie Fläche. Nur Primary-Button, Badge-BG,
/// Progress-Fill, 2.5px Accent-Bar, Logo-Layer. Niemals als Hintergrund
/// ganzer Panels.
class AwTokens {
  AwTokens._();

  // ---------- Brand ----------
  static const orange = Color(0xFFF25C1F);
  static const orangeDeep = Color(0xFFD94810);
  static const orangeSoft = Color(0x1AF25C1F); // 10 %
  static const orangeBorder = Color(0x47F25C1F); // 28 %

  static const ink = Color(0xFF0B1220);
  static const ink2 = Color(0xFF1A2235);

  // ---------- Neutrals ----------
  static const paper = Color(0xFFFAFAF7);
  static const white = Color(0xFFFFFFFF);
  static const mute = Color(0x8C0B1220); // 55 %
  static const muteSoft = Color(0x590B1220); // 35 %
  static const line = Color(0x140B1220); // 8 %
  static const lineStrong = Color(0x240B1220); // 14 %

  // ---------- Status ----------
  static const green = Color(0xFF16794A);
  static const greenSoft = Color(0x1A16794A);
  static const amber = Color(0xFFB45309);
  static const amberSoft = Color(0x1AB45309);
  static const red = Color(0xFFB42318);
  static const redSoft = Color(0x1AB42318);
  static const blue = Color(0xFF1E4ED8);
  static const blueSoft = Color(0x141E4ED8); // 8 %

  // ---------- Radius ----------
  static const radiusXs = 4.0;
  static const radiusSm = 6.0;
  static const radiusMd = 8.0;
  static const radiusLg = 10.0;
  static const radiusXl = 14.0;

  // ---------- Typografie ----------
  static const fontSans = 'Geist';
  static const fontMono = 'Geist Mono';

  // Pixel-Größen direkt aus handoff/README.md.
  static const textXs = 10.5;
  static const textSm = 11.5;
  static const textBase = 12.5;
  static const textMd = 13.0;
  static const textLg = 14.0;
  static const textXl = 16.0;
  static const textH2 = 20.0;
  static const textH1 = 24.0;

  static const trackingTight = -0.025 * 12.5; // em → px rechnen wir pro Style
  static const trackingBody = -0.01;
  static const trackingEyebrow = 0.05;
  static const trackingMicro = 0.12;

  // ---------- Dialog-Größen (handoff/DIALOGS §1) ----------
  static const dialogSm = 420.0;
  static const dialogMd = 640.0;
  static const dialogLg = 880.0;
  static const dialogXl = 1120.0;
  static const sideSheetWidth = 520.0;

  // ---------- Shadows ----------
  static const shadowSm = [
    BoxShadow(
      color: Color(0x0A0B1220),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];
  static const shadowMd = [
    BoxShadow(
      color: Color(0x0F0B1220),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];
  static const shadowLg = [
    BoxShadow(
      color: Color(0x190B1220),
      blurRadius: 32,
      offset: Offset(0, 12),
    ),
  ];
}

/// Status-Badge-Typen — Mapping aus `handoff/tokens.ts → statusMap`.
enum AwBadgeKind {
  inProgress,
  todo,
  done,
  overdue,
  draft,
  info,
}

extension AwBadgeKindColors on AwBadgeKind {
  Color get fg => switch (this) {
        AwBadgeKind.inProgress => AwTokens.orange,
        AwBadgeKind.todo => AwTokens.amber,
        AwBadgeKind.done => AwTokens.green,
        AwBadgeKind.overdue => AwTokens.red,
        AwBadgeKind.draft => AwTokens.mute,
        AwBadgeKind.info => AwTokens.blue,
      };

  Color get bg => switch (this) {
        AwBadgeKind.inProgress => AwTokens.orangeSoft,
        AwBadgeKind.todo => AwTokens.amberSoft,
        AwBadgeKind.done => AwTokens.greenSoft,
        AwBadgeKind.overdue => AwTokens.redSoft,
        AwBadgeKind.draft => AwTokens.paper,
        AwBadgeKind.info => AwTokens.blueSoft,
      };
}

/// Mapping Status-String → Badge-Typ (aus handoff/tokens.ts statusMap).
AwBadgeKind? awBadgeForStatus(String status) {
  switch (status.toLowerCase()) {
    case 'in bearbeitung':
      return AwBadgeKind.inProgress;
    case 'zu prüfen':
    case 'zu pruefen':
      return AwBadgeKind.todo;
    case 'abgeschlossen':
    case 'bezahlt':
    case 'versendet':
      return AwBadgeKind.done;
    case 'überfällig':
    case 'ueberfaellig':
    case 'mahnung 1':
    case 'mahnung 2':
    case 'mahnung 3':
      return AwBadgeKind.overdue;
    case 'entwurf':
      return AwBadgeKind.draft;
    case 'ortstermin':
    case 'offen':
      return AwBadgeKind.info;
  }
  return null;
}
