import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../features/akten/kunden/kunden_repository.dart';
import '../../../features/akten/rechnungen/rechnungen_repository.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';

class OposScreen extends ConsumerWidget {
  const OposScreen({super.key});
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');
  static final _money = NumberFormat.currency(locale: 'de', symbol: '€');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rechnungenListProvider);
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ModuleHeader(
          icon: Icons.warning_amber_outlined,
          title: 'OPOS / Mahnwesen',
          subtitle: 'Offene Posten mit Alter und Mahnstufen',
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) {
              // Nur offene / teilbezahlte / überfällige Rechnungen
              final offen = items
                  .where((r) =>
                      r.rechnung.status != 'bezahlt' &&
                      r.rechnung.status != 'storniert')
                  .toList()
                ..sort((a, b) {
                  final af = a.rechnung.faelligAm ?? DateTime(2099);
                  final bf = b.rechnung.faelligAm ?? DateTime(2099);
                  return af.compareTo(bf);
                });

              double gesamtOffen = 0;
              double gesamtUeberfaellig = 0;
              for (final r in offen) {
                final offenBetrag = r.rechnung.brutto - r.rechnung.bezahlt;
                gesamtOffen += offenBetrag;
                if (r.rechnung.faelligAm != null &&
                    r.rechnung.faelligAm!.isBefore(now)) {
                  gesamtUeberfaellig += offenBetrag;
                }
              }

              if (offen.isEmpty) {
                return const EmptyListState(
                  icon: Icons.check_circle_outline,
                  title: 'Keine offenen Rechnungen',
                );
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Row(
                      children: [
                        _Stat(
                          label: 'Offen gesamt',
                          value: _money.format(gesamtOffen),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 16),
                        _Stat(
                          label: 'Davon überfällig',
                          value: _money.format(gesamtUeberfaellig),
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 16),
                        _Stat(
                          label: 'Anzahl offener Rechnungen',
                          value: '${offen.length}',
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: DataTableCard(
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                        ),
                        columns: const [
                          DataColumn(label: Text('Nr.')),
                          DataColumn(label: Text('Kunde')),
                          DataColumn(label: Text('Datum')),
                          DataColumn(label: Text('Fällig')),
                          DataColumn(label: Text('Alter'), numeric: true),
                          DataColumn(label: Text('Brutto €'), numeric: true),
                          DataColumn(label: Text('Bezahlt €'), numeric: true),
                          DataColumn(label: Text('Offen €'), numeric: true),
                          DataColumn(label: Text('Mahnstufe')),
                        ],
                        rows: [
                          for (final r in offen)
                            _row(context, r, now),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  DataRow _row(BuildContext context, RechnungWithKunde r, DateTime now) {
    final faellig = r.rechnung.faelligAm;
    final alter = faellig == null ? 0 : now.difference(faellig).inDays;
    final overdue = alter > 0;
    final offen = r.rechnung.brutto - r.rechnung.bezahlt;
    final mahnstufe = _mahnstufe(alter);
    final color = overdue ? Theme.of(context).colorScheme.error : null;
    return DataRow(
      cells: [
        DataCell(Text(r.rechnung.rechnungsnummer ?? '',
            style: TextStyle(color: color))),
        DataCell(Text(
          r.kunde == null ? '—' : kundeAnzeigename(r.kunde!),
          style: TextStyle(color: color),
        )),
        DataCell(Text(r.rechnung.rechnungsdatum == null
            ? ''
            : _dateFmt.format(r.rechnung.rechnungsdatum!))),
        DataCell(Text(faellig == null ? '' : _dateFmt.format(faellig))),
        DataCell(Text(overdue ? '+$alter' : (alter < 0 ? alter.toString() : '0'),
            style: TextStyle(color: color))),
        DataCell(Text(r.rechnung.brutto.toStringAsFixed(2))),
        DataCell(Text(r.rechnung.bezahlt.toStringAsFixed(2))),
        DataCell(Text(offen.toStringAsFixed(2),
            style:
                TextStyle(color: color, fontWeight: FontWeight.w600))),
        DataCell(mahnstufe == 0
            ? const Text('—')
            : Chip(
                label: Text('$mahnstufe. Mahnung'),
                visualDensity: VisualDensity.compact,
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                labelStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontSize: 12),
              )),
      ],
    );
  }

  int _mahnstufe(int alter) {
    if (alter > 60) return 3;
    if (alter > 30) return 2;
    if (alter > 14) return 1;
    return 0;
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
            Text(value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    )),
          ],
        ),
      ),
    );
  }
}
