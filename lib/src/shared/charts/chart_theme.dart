import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';

/// Zentrale Chart-Farbwerte — greift auf die Logo-/Accent-Palette der App
/// zurück (Orange-Töne). Hover/Tooltip-Styling einheitlich.
class ChartStyle {
  static final _money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);

  /// Standard-Balken: Farbverlauf von accent600 (oben) nach accent500 (unten).
  static LinearGradient barGradient({Color? from, Color? to}) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          from ?? AppTheme.accent600,
          to ?? AppTheme.accent500,
        ],
      );

  /// Erzeugt einen einzelnen Balken mit Gradient und abgerundeten Ecken.
  static BarChartRodData bar(double value,
      {Color? from, Color? to, double width = 18}) {
    return BarChartRodData(
      toY: value,
      gradient: barGradient(from: from, to: to),
      width: width,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
    );
  }

  /// Tooltip: dunkelgrauer Hintergrund, Wert in Logo-Orange.
  static BarTouchData barTouchData({
    String Function(double)? format,
    Color? valueColor,
  }) {
    return BarTouchData(
      enabled: true,
      touchTooltipData: BarTouchTooltipData(
        getTooltipColor: (_) => const Color(0xFF1E293B), // slate-800
        tooltipPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        tooltipRoundedRadius: 6,
        getTooltipItem: (group, groupIdx, rod, rodIdx) {
          final text = format?.call(rod.toY) ?? _money.format(rod.toY);
          return BarTooltipItem(
            text,
            TextStyle(
              color: valueColor ?? AppTheme.accent500,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          );
        },
      ),
    );
  }

  /// Dünne horizontale Hilfslinien in hellem Grau.
  static FlGridData gridData() => FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: null,
        getDrawingHorizontalLine: (_) => FlLine(
          color: AppTheme.slate100,
          strokeWidth: 1,
          dashArray: const [2, 2],
        ),
      );

  /// Standard-Beschriftungen unten (Monatsnamen etc.).
  static AxisTitles bottomLabels(List<String> labels) => AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 22,
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= labels.length) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                labels[i],
                style: TextStyle(fontSize: 10, color: AppTheme.slate500),
              ),
            );
          },
        ),
      );

  static AxisTitles emptyAxis() => const AxisTitles(
        sideTitles: SideTitles(showTitles: false),
      );
}
