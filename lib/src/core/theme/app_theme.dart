import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Theme entspricht 1:1 der Original-SV-Software
/// (Tailwind slate + accent orange, Inter-Font).
class AppTheme {
  // Brand / Slate
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);

  // Accent / Orange
  static const accent50 = Color(0xFFFFF7ED);
  static const accent100 = Color(0xFFFFEDD5);
  static const accent400 = Color(0xFFFB923C);
  static const accent500 = Color(0xFFF97316);
  static const accent600 = Color(0xFFEA580C);
  static const accent700 = Color(0xFFC2410C);

  static const brand = slate900;
  static const accent = accent600;

  static ThemeData light() {
    final scheme = const ColorScheme.light(
      primary: accent600,
      onPrimary: Colors.white,
      primaryContainer: accent50,
      onPrimaryContainer: accent700,
      secondary: slate700,
      onSecondary: Colors.white,
      secondaryContainer: slate100,
      onSecondaryContainer: slate800,
      tertiary: accent500,
      onTertiary: Colors.white,
      tertiaryContainer: accent100,
      onTertiaryContainer: accent700,
      error: Color(0xFFDC2626),
      onError: Colors.white,
      errorContainer: Color(0xFFFEE2E2),
      onErrorContainer: Color(0xFF991B1B),
      surface: Colors.white,
      onSurface: slate900,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: slate50,
      surfaceContainer: slate50,
      surfaceContainerHigh: slate100,
      surfaceContainerHighest: slate100,
      onSurfaceVariant: slate600,
      outline: slate300,
      outlineVariant: slate200,
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
    final baseText = GoogleFonts.interTextTheme(
      b == Brightness.light
          ? ThemeData.light().textTheme
          : ThemeData.dark().textTheme,
    ).apply(
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
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        hintStyle: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        labelStyle: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        floatingLabelStyle: const TextStyle(fontSize: 11),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: accent600, width: 2),
        ),
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
        headingTextStyle: textTheme.labelLarge?.copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
            letterSpacing: 0.1),
        dataTextStyle: textTheme.bodyMedium?.copyWith(fontSize: 12.5),
        headingRowHeight: 40,
        dataRowMinHeight: 38,
        dataRowMaxHeight: 48,
        columnSpacing: 18,
        horizontalMargin: 12,
        // Zeilen-Verhalten 1:1 wie die Sidebar-NavItems:
        // Hover = leicht grau, Selected/Pressed = orange-Hintergrund.
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent50;
          if (states.contains(WidgetState.pressed)) return accent50;
          if (states.contains(WidgetState.hovered)) return slate100;
          return null;
        }),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        elevation: 10,
      ),
    );
  }
}
