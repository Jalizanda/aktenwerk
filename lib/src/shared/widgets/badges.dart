import 'package:flutter/material.dart';

/// Farbpalette der Original-Badges aus der SV-Software
/// (Tailwind-Werte: indigo/blue/red/green/amber jeweils 50er BG + 700/800 FG).
class BadgeColors {
  BadgeColors._();

  // Tailwind 50-BG + 700/800 FG
  static const indigoBg = Color(0xFFEEF2FF);
  static const indigoFg = Color(0xFF4338CA);
  static const blueBg = Color(0xFFEFF6FF);
  static const blueFg = Color(0xFF1D4ED8);
  static const redBg = Color(0xFFFEF2F2);
  static const redFg = Color(0xFF991B1B);
  static const greenBg = Color(0xFFF0FDF4);
  static const greenFg = Color(0xFF166534);
  static const amberBg = Color(0xFFFFFBEB);
  static const amberFg = Color(0xFFB45309);
  static const slateBg = Color(0xFFF1F5F9);
  static const slateFg = Color(0xFF334155);
}

/// Pill-Badge à la Tailwind (rounded-full, 11 px, fett, letter-spacing 0.01em).
class PillBadge extends StatelessWidget {
  const PillBadge({
    super.key,
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
          letterSpacing: 0.11,
        ),
      ),
    );
  }
}

/// Mapping: interner Status-Key → Label + Farbe.
class _BadgeSpec {
  final String label;
  final Color bg;
  final Color fg;
  const _BadgeSpec(this.label, this.bg, this.fg);
}

/// Status-Badge für **Angebote** (7 Stufen, 1:1 aus SV-Software).
class AngebotStatusBadge extends StatelessWidget {
  const AngebotStatusBadge(this.status, {super.key});
  final String status;

  static const _map = <String, _BadgeSpec>{
    'anfrage': _BadgeSpec('Anfrage', BadgeColors.blueBg, BadgeColors.blueFg),
    'angebot':
        _BadgeSpec('Angebot raus', BadgeColors.amberBg, BadgeColors.amberFg),
    'nachverhandlung': _BadgeSpec(
        'Nachverhandlung', BadgeColors.amberBg, BadgeColors.amberFg),
    'angenommen':
        _BadgeSpec('Angenommen', BadgeColors.greenBg, BadgeColors.greenFg),
    'auftragsbestaetigung': _BadgeSpec(
        'AB versendet', BadgeColors.greenBg, BadgeColors.greenFg),
    'abgelehnt':
        _BadgeSpec('Abgelehnt', BadgeColors.redBg, BadgeColors.redFg),
    'abgelaufen':
        _BadgeSpec('Abgelaufen', BadgeColors.redBg, BadgeColors.redFg),
    // Legacy-Werte, falls noch alte Datensätze vorliegen:
    'entwurf':
        _BadgeSpec('Entwurf', BadgeColors.slateBg, BadgeColors.slateFg),
    'versendet':
        _BadgeSpec('Versendet', BadgeColors.amberBg, BadgeColors.amberFg),
  };

  static String label(String status) => _map[status]?.label ?? status;

  static const statusValues = [
    'anfrage',
    'angebot',
    'nachverhandlung',
    'angenommen',
    'auftragsbestaetigung',
    'abgelehnt',
    'abgelaufen',
  ];

  @override
  Widget build(BuildContext context) {
    final s = _map[status] ??
        _BadgeSpec(status, BadgeColors.slateBg, BadgeColors.slateFg);
    return PillBadge(text: s.label, background: s.bg, foreground: s.fg);
  }
}

/// Status-Badge für **Rechnungen**. Wir decken sowohl die SV-Software-Werte
/// (entwurf/versendet/bezahlt/storniert) als auch die Zahlungs-tracking-Werte
/// (teilbezahlt/ueberfaellig) ab, die bereits in Aktenwerk existieren.
class RechnungStatusBadge extends StatelessWidget {
  const RechnungStatusBadge(this.status, {super.key});
  final String status;

  static const _map = <String, _BadgeSpec>{
    'entwurf':
        _BadgeSpec('Entwurf', BadgeColors.blueBg, BadgeColors.blueFg),
    'offen': _BadgeSpec('Offen', BadgeColors.blueBg, BadgeColors.blueFg),
    'versendet':
        _BadgeSpec('Versendet', BadgeColors.amberBg, BadgeColors.amberFg),
    'teilbezahlt':
        _BadgeSpec('Teilbezahlt', BadgeColors.amberBg, BadgeColors.amberFg),
    'bezahlt':
        _BadgeSpec('Bezahlt', BadgeColors.greenBg, BadgeColors.greenFg),
    'ueberfaellig':
        _BadgeSpec('Überfällig', BadgeColors.redBg, BadgeColors.redFg),
    'storniert':
        _BadgeSpec('Storniert', BadgeColors.redBg, BadgeColors.redFg),
  };

  static String label(String status) => _map[status]?.label ?? status;

  static const statusValues = [
    'entwurf',
    'versendet',
    'teilbezahlt',
    'bezahlt',
    'ueberfaellig',
    'storniert',
  ];

  @override
  Widget build(BuildContext context) {
    final s = _map[status] ??
        _BadgeSpec(status, BadgeColors.slateBg, BadgeColors.slateFg);
    return PillBadge(text: s.label, background: s.bg, foreground: s.fg);
  }
}

/// Typ-Badge für Rechnungen: Privat (blau), JVEG (rot), Gutschrift/Korrektur (amber).
class RechnungTypBadge extends StatelessWidget {
  const RechnungTypBadge(this.typ, {super.key});
  final String typ;

  static const _map = <String, _BadgeSpec>{
    'privat': _BadgeSpec('Privat', BadgeColors.blueBg, BadgeColors.blueFg),
    'jveg': _BadgeSpec('JVEG', BadgeColors.redBg, BadgeColors.redFg),
    'gutschrift':
        _BadgeSpec('Gutschrift', BadgeColors.amberBg, BadgeColors.amberFg),
    'korrektur':
        _BadgeSpec('Korrektur', BadgeColors.amberBg, BadgeColors.amberFg),
  };

  @override
  Widget build(BuildContext context) {
    final s = _map[typ] ??
        _BadgeSpec(typ, BadgeColors.slateBg, BadgeColors.slateFg);
    return PillBadge(text: s.label, background: s.bg, foreground: s.fg);
  }
}

/// Typ-Badge für Kunden.
class KundeTypBadge extends StatelessWidget {
  const KundeTypBadge(this.typ, {super.key});
  final String typ;

  static const _map = <String, _BadgeSpec>{
    'privat': _BadgeSpec('Privat', BadgeColors.blueBg, BadgeColors.blueFg),
    'firma': _BadgeSpec('Firma', BadgeColors.amberBg, BadgeColors.amberFg),
    'anwalt':
        _BadgeSpec('Anwalt', BadgeColors.indigoBg, BadgeColors.indigoFg),
    'gericht':
        _BadgeSpec('Gericht', BadgeColors.redBg, BadgeColors.redFg),
    'versicherung': _BadgeSpec(
        'Versicherung', BadgeColors.greenBg, BadgeColors.greenFg),
    'behoerde':
        _BadgeSpec('Behörde', BadgeColors.amberBg, BadgeColors.amberFg),
  };

  @override
  Widget build(BuildContext context) {
    final s = _map[typ] ??
        _BadgeSpec(typ, BadgeColors.slateBg, BadgeColors.slateFg);
    return PillBadge(text: s.label, background: s.bg, foreground: s.fg);
  }
}

/// KPI-Kachel im Stil der SV-Software: Wert in farbiger Pill-Box,
/// Label darüber als kleines uppercased Kürzel.
///
/// [accent] steuert sowohl Text- als auch Hintergrundfarbe der Wert-Box.
/// Wir leiten uns die helle Hintergrundvariante aus einer Mapping-Tabelle ab,
/// damit Grün/Amber/Blau/Rot/Indigo jeweils passen.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.accent,
    this.icon,
  });
  final String label;
  final String value;
  final Color? accent;
  final IconData? icon;

  static const _bgFor = <int, Color>{
    0xFFB45309: BadgeColors.amberBg,
    0xFF166534: BadgeColors.greenBg,
    0xFF1D4ED8: BadgeColors.blueBg,
    0xFF991B1B: BadgeColors.redBg,
    0xFF4338CA: BadgeColors.indigoBg,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = accent ?? scheme.onSurface;
    final bg = _bgFor[fg.toARGB32()] ?? BadgeColors.slateBg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
              ],
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.08 * 10.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Wert-Pill in der Akzentfarbe.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
