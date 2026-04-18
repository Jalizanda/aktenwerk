import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../features/akten/eingangsrechnungen/eingangsrechnungen_repository.dart';
import '../../../features/akten/rechnungen/rechnungen_repository.dart';
import '../../../shared/widgets/module_scaffold.dart';

class SteuerScreen extends ConsumerStatefulWidget {
  const SteuerScreen({super.key});
  @override
  ConsumerState<SteuerScreen> createState() => _SteuerScreenState();
}

class _SteuerScreenState extends ConsumerState<SteuerScreen> {
  int _jahr = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat.currency(locale: 'de', symbol: '€');
    final rechnungen = ref.watch(rechnungenListProvider);
    final eingangsrechnungen = ref.watch(eingangsrechnungenListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.query_stats_outlined,
          title: 'Steuer & Statistik',
          subtitle: 'USt-Voranmeldung & Einnahmen-Überschuss',
          filters: [
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _jahr,
                items: [
                  for (var y = DateTime.now().year; y >= DateTime.now().year - 5; y--)
                    DropdownMenuItem(value: y, child: Text('Jahr $y')),
                ],
                onChanged: (v) => setState(() => _jahr = v ?? DateTime.now().year),
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: (rechnungen.isLoading || eingangsrechnungen.isLoading)
              ? const Center(child: CircularProgressIndicator())
              : _buildContent(
                  context,
                  theme,
                  money,
                  rechnungen.valueOrNull ?? [],
                  eingangsrechnungen.valueOrNull ?? [],
                ),
        ),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    NumberFormat money,
    List<RechnungWithKunde> rechnungen,
    List<EingangsrechnungWithAuftrag> eingangs,
  ) {
    final einnahmen = List.filled(12, 0.0);
    final ausgaben = List.filled(12, 0.0);
    double jahresNetto = 0, jahresUst = 0;
    double vorsteuer = 0;
    double ausgabenJahr = 0;

    for (final r in rechnungen) {
      final d = r.rechnung.rechnungsdatum;
      if (d == null || d.year != _jahr) continue;
      einnahmen[d.month - 1] += r.rechnung.brutto;
      jahresNetto += r.rechnung.netto;
      jahresUst += r.rechnung.ustBetrag;
    }
    for (final e in eingangs) {
      final d = e.rechnung.rechnungsdatum;
      if (d == null || d.year != _jahr) continue;
      ausgaben[d.month - 1] += e.rechnung.brutto;
      ausgabenJahr += e.rechnung.netto;
      vorsteuer += e.rechnung.ustBetrag;
    }

    final ustZahllast = jahresUst - vorsteuer;
    final eurGewinn = jahresNetto - ausgabenJahr;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Stat(
                  label: 'Umsatz netto $_jahr',
                  value: money.format(jahresNetto),
                  color: theme.colorScheme.primary),
              _Stat(
                  label: 'USt eingenommen',
                  value: money.format(jahresUst)),
              _Stat(
                  label: 'Vorsteuer',
                  value: money.format(vorsteuer)),
              _Stat(
                  label: 'USt-Zahllast',
                  value: money.format(ustZahllast),
                  color: ustZahllast > 0 ? theme.colorScheme.error : null),
              _Stat(
                  label: 'Ausgaben netto',
                  value: money.format(ausgabenJahr)),
              _Stat(
                  label: 'Gewinn (EÜR)',
                  value: money.format(eurGewinn),
                  color: theme.colorScheme.tertiary),
            ],
          ),
          const SizedBox(height: 24),
          Text('Umsatz pro Monat',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          SizedBox(
            height: 280,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                barGroups: [
                  for (var m = 0; m < 12; m++)
                    BarChartGroupData(x: m, barRods: [
                      BarChartRodData(
                          toY: einnahmen[m],
                          color: theme.colorScheme.primary,
                          width: 14),
                      BarChartRodData(
                          toY: ausgaben[m],
                          color: theme.colorScheme.error,
                          width: 14),
                    ]),
                ],
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 60,
                          getTitlesWidget: (v, _) => Text(
                              v.toStringAsFixed(0),
                              style: const TextStyle(fontSize: 11)))),
                  rightTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, _) => Text(
                                _monat(v.toInt()),
                                style: const TextStyle(fontSize: 11),
                              ))),
                ),
                gridData: FlGridData(show: true),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            _LegendItem(
                color: theme.colorScheme.primary, label: 'Einnahmen'),
            const SizedBox(width: 24),
            _LegendItem(
                color: theme.colorScheme.error, label: 'Ausgaben'),
          ]),
        ],
      ),
    );
  }

  String _monat(int i) => const [
        'Jan',
        'Feb',
        'Mrz',
        'Apr',
        'Mai',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Okt',
        'Nov',
        'Dez'
      ][i];
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side:
              BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
              Text(value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      )),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(width: 14, height: 14, color: color),
        const SizedBox(width: 6),
        Text(label),
      ]);
}
