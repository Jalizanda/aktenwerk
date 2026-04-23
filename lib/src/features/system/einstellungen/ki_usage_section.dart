import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ai/ki_modelle.dart';
import '../../../core/ai/ki_usage_service.dart';

/// Einstellungssektion: Übersicht über den KI-Verbrauch des laufenden
/// Monats (Calls, Tokens, USD-Selbstkosten).
class KiUsageSection extends ConsumerWidget {
  const KiUsageSection({super.key});

  static final _fmt = NumberFormat.decimalPattern('de');
  static final _fmtUsd = NumberFormat.currency(
      locale: 'en_US', symbol: '\$', decimalDigits: 4);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(kiUsageAktuellerMonatProvider);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.query_stats_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text('KI-Verbrauch (aktueller Monat)',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Selbstkosten bei Google, exkl. Aufschlag an Endkunden. '
              'Basis sind die in der Firebase-Konsole eingestellten Preise.',
              style: TextStyle(
                  fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(),
              ),
              error: (e, _) => Text('Fehler: $e'),
              data: (eintraege) {
                if (eintraege.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Noch keine KI-Aufrufe in diesem Monat.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  );
                }
                final agg = aggregiere(eintraege);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _summeKachel(scheme, agg),
                    const SizedBox(height: 14),
                    _verteilungs(scheme, 'nach Modell', agg.proModell,
                        (id) => kiModellInfo(id).label),
                    const SizedBox(height: 8),
                    _verteilungs(scheme, 'nach Funktion', agg.proFeature,
                        _featureLabel),
                    const SizedBox(height: 14),
                    _jungsteCalls(scheme, eintraege.take(10).toList()),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _summeKachel(ColorScheme scheme, KiUsageMonatsAggregat agg) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _kennzahl(scheme, 'Aufrufe',
              _fmt.format(agg.gesamtCalls)),
          const SizedBox(width: 24),
          _kennzahl(scheme, 'Tokens In',
              _fmt.format(agg.gesamtTokensIn)),
          const SizedBox(width: 24),
          _kennzahl(scheme, 'Tokens Out',
              _fmt.format(agg.gesamtTokensOut)),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Selbstkosten',
                  style: TextStyle(
                      fontSize: 11, color: scheme.onPrimaryContainer)),
              Text(
                _fmtUsd.format(agg.gesamtKostenUsd),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimaryContainer,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kennzahl(ColorScheme scheme, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11, color: scheme.onPrimaryContainer)),
        Text(value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: scheme.onPrimaryContainer,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
      ],
    );
  }

  Widget _verteilungs(ColorScheme scheme, String titel,
      Map<String, double> map, String Function(String) label) {
    if (map.isEmpty) return const SizedBox.shrink();
    final gesamt = map.values.fold<double>(0, (s, v) => s + v);
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(titel,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        for (final e in sorted)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                    width: 200,
                    child: Text(label(e.key),
                        style: const TextStyle(fontSize: 12))),
                Expanded(
                  child: LinearProgressIndicator(
                    value: gesamt == 0 ? 0 : e.value / gesamt,
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: scheme.primary,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 70,
                  child: Text(_fmtUsd.format(e.value),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 12,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _jungsteCalls(ColorScheme scheme, List<KiUsageEintrag> calls) {
    final fmtZeit = DateFormat('dd.MM.yyyy HH:mm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Letzte Aufrufe',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        for (final c in calls)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 6),
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    fmtZeit.format(DateTime.fromMillisecondsSinceEpoch(
                        c.timestampMs)),
                    style: const TextStyle(
                        fontSize: 11,
                        fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: Text(_featureLabel(c.feature),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
                SizedBox(
                  width: 170,
                  child: Text(kiModellInfo(c.modellId).label,
                      style: const TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  child: Text(
                      '${_fmt.format(c.inputTokens)} in / '
                      '${_fmt.format(c.outputTokens)} out',
                      style: const TextStyle(
                          fontSize: 11,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ),
                SizedBox(
                  width: 90,
                  child: Text(_fmtUsd.format(c.kostenUsd),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _featureLabel(String key) {
    // key entspricht KiAufgabe.name (z.B. 'korrektur', 'normenChat')
    try {
      final a = KiAufgabe.values.firstWhere((e) => e.name == key);
      return a.label;
    } catch (_) {
      return key;
    }
  }
}
