import 'package:flutter/material.dart';

import 'aw_tokens.dart';

/// Theme nach Aktenwerk Design Guideline v1.0 (siehe `handoff/`).
/// Ink + Paper statt Slate, Orange `#F25C1F` (Brand), Geist-Schrift,
/// Borders via `--aw-line` (8 % Ink).
class AppTheme {
  // ---- Alt-API (Slate/Accent) — bleibt als Alias erhalten, damit die
  // ~120 bestehenden Referenzen weiterhin kompilieren. Intern sind die
  // Farben nun auf die AW-Guideline gemappt.
  static const slate50 = AwTokens.paper;
  static const slate100 = Color(0xFFF1F3F0); // leicht wärmer als ink-8%
  static const slate200 = AwTokens.line;
  static const slate300 = AwTokens.lineStrong;
  static const slate400 = AwTokens.muteSoft;
  static const slate500 = AwTokens.mute;
  static const slate600 = Color(0xFF4B5466);
  static const slate700 = Color(0xFF2E3848);
  static const slate800 = AwTokens.ink2;
  static const slate900 = AwTokens.ink;

  static const accent50 = Color(0xFFFEEFE7); // ~orange @ 10 % auf Weiß
  static const accent100 = Color(0xFFFCD9C7);
  static const accent400 = Color(0xFFF37A45);
  static const accent500 = AwTokens.orange;
  static const accent600 = AwTokens.orange;
  static const accent700 = AwTokens.orangeDeep;

  static const brand = AwTokens.ink;
  static const accent = AwTokens.orange;

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: AwTokens.orange,
      onPrimary: AwTokens.white,
      primaryContainer: accent50,
      onPrimaryContainer: AwTokens.orangeDeep,
      secondary: AwTokens.ink,
      onSecondary: AwTokens.white,
      secondaryContainer: AwTokens.paper,
      onSecondaryContainer: AwTokens.ink,
      tertiary: AwTokens.orange,
      onTertiary: AwTokens.white,
      tertiaryContainer: accent100,
      onTertiaryContainer: AwTokens.orangeDeep,
      error: AwTokens.red,
      onError: AwTokens.white,
      errorContainer: Color(0xFFFEE2E2),
      onErrorContainer: Color(0xFF7F1D1D),
      surface: AwTokens.white,
      onSurface: AwTokens.ink,
      surfaceContainerLowest: AwTokens.white,
      surfaceContainerLow: AwTokens.paper,
      surfaceContainer: AwTokens.paper,
      surfaceContainerHigh: slate100,
      surfaceContainerHighest: slate100,
      onSurfaceVariant: AwTokens.mute,
      outline: AwTokens.lineStrong,
      outlineVariant: AwTokens.line,
    );
    return _base(scheme, Brightness.light);
  }

  static ThemeData dark() {
    final scheme = const ColorScheme.dark(
      primary: accent500,
      onPrimary: Colors.white,
      primaryContainer: accent700,
      onPrimaryContainer: accent50,
      secondary: slate300,
      onSecondary: slate900,
      secondaryContainer: slate700,
      onSecondaryContainer: slate100,
      tertiary: accent400,
      onTertiary: slate900,
      tertiaryContainer: accent700,
      onTertiaryContainer: accent50,
      error: Color(0xFFF87171),
      onError: slate900,
      errorContainer: Color(0xFF7F1D1D),
      onErrorContainer: Color(0xFFFECACA),
      surface: slate900,
      onSurface: slate50,
      surfaceContainerLowest: Color(0xFF020617),
      surfaceContainerLow: slate800,
      surfaceContainer: slate800,
      surfaceContainerHigh: slate700,
      surfaceContainerHighest: slate700,
      onSurfaceVariant: slate400,
      outline: slate600,
      outlineVariant: slate700,
    );
    return _base(scheme, Brightness.dark);
  }

  static ThemeData _base(ColorScheme scheme, Brightness b) {
    // Geist ist die Brand-Schrift (handoff/README §3). Wird auf Web
    // via `<link>` in `web/index.html` geladen und vom Browser-Text-
    // Engine verwendet. Auf Desktop/Mobile fällt Flutter auf die
    // System-Schrift zurück.
    final baseText = (b == Brightness.light
            ? ThemeData.light().textTheme
            : ThemeData.dark().textTheme)
        .apply(
      fontFamily: AwTokens.fontSans,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    // Kompaktere Text-Skala à la SV-Software / Tailwind (Body ~13 px statt
    // Flutter-Default 14 px, Überschriften entsprechend kleiner).
    final textTheme = baseText.copyWith(
      displayLarge:
          baseText.displayLarge?.copyWith(fontSize: 44, letterSpacing: -0.4),
      displayMedium:
          baseText.displayMedium?.copyWith(fontSize: 34, letterSpacing: -0.4),
      displaySmall:
          baseText.displaySmall?.copyWith(fontSize: 26, letterSpacing: -0.3),
      headlineLarge:
          baseText.headlineLarge?.copyWith(fontSize: 24, letterSpacing: -0.3),
      headlineMedium:
          baseText.headlineMedium?.copyWith(fontSize: 20, letterSpacing: -0.3),
      headlineSmall:
          baseText.headlineSmall?.copyWith(fontSize: 17, letterSpacing: -0.2),
      titleLarge: baseText.titleLarge?.copyWith(
          fontSize: 15, letterSpacing: -0.2, fontWeight: FontWeight.w700),
      titleMedium: baseText.titleMedium?.copyWith(
          fontSize: 13, fontWeight: FontWeight.w600),
      titleSmall: baseText.titleSmall?.copyWith(
          fontSize: 12, fontWeight: FontWeight.w600),
      bodyLarge: baseText.bodyLarge?.copyWith(fontSize: 13),
      bodyMedium: baseText.bodyMedium?.copyWith(fontSize: 12.5),
      bodySmall: baseText.bodySmall?.copyWith(fontSize: 11),
      labelLarge: baseText.labelLarge?.copyWith(
          fontSize: 12, fontWeight: FontWeight.w600),
      labelMedium: baseText.labelMedium
          ?.copyWith(fontSize: 11, fontWeight: FontWeight.w600),
      labelSmall: baseText.labelSmall
          ?.copyWith(fontSize: 10, fontWeight: FontWeight.w600),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surfaceContainerLow,
      visualDensity: VisualDensity.compact,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        margin: EdgeInsets.zero,
        color: b == Brightness.dark ? scheme.surface : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent600,
          foregroundColor: Colors.white,
          textStyle: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600, color: Colors.white),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent700),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      // AW-Guideline DIALOGS §4 „Felder":
      // - 34 px hoch, weißer BG, Line-Strong Border, 8 px Radius.
      // - Focus: Orange-Border, Text 12.5 px 500, Mute-Hint.
      // - Error: Red-Border, Red-Helper 11 px.
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: AwTokens.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        hintStyle: const TextStyle(fontSize: 12.5, color: AwTokens.mute),
        labelStyle: const TextStyle(fontSize: 12.5, color: AwTokens.mute),
        floatingLabelStyle: const TextStyle(fontSize: 11, color: AwTokens.mute),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AwTokens.radiusMd)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AwTokens.radiusMd),
          borderSide: const BorderSide(color: AwTokens.lineStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AwTokens.radiusMd),
          borderSide: const BorderSide(color: AwTokens.orange, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AwTokens.radiusMd),
          borderSide: const BorderSide(color: AwTokens.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AwTokens.radiusMd),
          borderSide: const BorderSide(color: AwTokens.red, width: 2),
        ),
        errorStyle: const TextStyle(fontSize: 11, color: AwTokens.red),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(6),
        ),
      ),
      // Checkbox-Spalte wird durch onSelectChanged automatisch erzeugt —
      // das globale Theme kann das leider nicht abschalten. Wir setzen
      // daher in jeder DataTable explizit `showCheckboxColumn: false`.
      // Alternative Lösung: DataTable-Wrapper. Hier wird das Default-Theme
      // angepasst, damit wenigstens die Klick-Ziele korrekt funktionieren.
      dataTableTheme: DataTableThemeData(
        // AW-Guideline §6 „Tabellen": Header-BG Paper, Text 10.5 px
        // uppercase 600 mute, letter-spacing 0.05em.
        headingRowColor: WidgetStateProperty.all(AwTokens.paper),
        headingTextStyle: textTheme.labelLarge?.copyWith(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: AwTokens.mute,
            letterSpacing: 10.5 * 0.05),
        dataTextStyle: textTheme.bodyMedium?.copyWith(fontSize: 12.5),
        headingRowHeight: 40,
        dataRowMinHeight: 38,
        dataRowMaxHeight: 48,
        columnSpacing: 18,
        horizontalMargin: 12,
        dividerThickness: 1,
        // Zeilen-Verhalten 1:1 wie die Sidebar-NavItems:
        // Hover = leicht grau, Selected/Pressed = orange-Hintergrund.
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AwTokens.orangeSoft;
          if (states.contains(WidgetState.pressed)) return AwTokens.orangeSoft;
          if (states.contains(WidgetState.hovered)) return AwTokens.paper;
          return null;
        }),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      // AW-Guideline §6 „Progress": 5 px, Paper-Track, Orange-Fill.
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AwTokens.orange,
        linearTrackColor: AwTokens.paper,
        linearMinHeight: 5,
      ),
      // AW-Guideline: TabBar-Active mit Orange-Underline (2 px),
      // Inactive mute, Label 13 px 500.
      tabBarTheme: const TabBarThemeData(
        indicatorColor: AwTokens.orange,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: AwTokens.ink,
        unselectedLabelColor: AwTokens.mute,
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        dividerColor: AwTokens.line,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AwTokens.radiusXl)),
        elevation: 10,
      ),
      // AW-Popup-Menü (Dropdowns, Kontextmenüs): weißes Panel,
      // 8 px Radius, mute-Text, Orange-Soft für Selected.
      popupMenuTheme: PopupMenuThemeData(
        color: AwTokens.white,
        surfaceTintColor: AwTokens.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AwTokens.radiusMd),
          side: const BorderSide(color: AwTokens.line),
        ),
        textStyle: const TextStyle(fontSize: 12.5, color: AwTokens.ink),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(AwTokens.white),
          surfaceTintColor: const WidgetStatePropertyAll(AwTokens.white),
          elevation: const WidgetStatePropertyAll(4),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AwTokens.radiusMd),
              side: const BorderSide(color: AwTokens.line),
            ),
          ),
        ),
      ),
      // AW-Snackbar / Toast (handoff/DIALOGS §7): Ink-BG, weißer
      // Text 12.5 px, 8 px Radius, 360 px max. Action-Link in Orange.
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AwTokens.ink,
        contentTextStyle: TextStyle(
            color: AwTokens.white, fontSize: 12.5, height: 1.35),
        actionTextColor: AwTokens.orange,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AwTokens.radiusMd)),
        ),
        insetPadding: EdgeInsets.all(20),
      ),
    );
  }
}
