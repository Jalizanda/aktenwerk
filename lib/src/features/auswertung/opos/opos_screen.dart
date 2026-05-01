import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../features/akten/kunden/kunden_repository.dart';
import '../../../features/akten/rechnungen/rechnungen_repository.dart';
import '../../../shared/widgets/badges.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'opos_zahlung_dialog.dart';

final oposQueryProvider = StateProvider<String>((ref) => '');

class OposScreen extends ConsumerWidget {
  const OposScreen({super.key});
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');
  static final _money = NumberFormat.currency(locale: 'de', symbol: '€');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rechnungenListProvider);
    final query = ref.watch(oposQueryProvider).trim().toLowerCase();
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.warning_amber_outlined,
          title: 'OPOS / Mahnwesen',
          subtitle: 'Offene Posten mit Alter und Mahnstufen',
          searchHint: 'Suche Nr., Kunde, Az., Betreff, Betrag …',
          onSearchChanged: (v) =>
              ref.read(oposQueryProvider.notifier).state = v,
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) {
              // Nur offene / teilbezahlte / überfällige Rechnungen, die
              // tatsächlich gedruckt+eingefroren sind. Entwürfe ohne
              // feste Belegnummer gehören NICHT in OPOS.
              final offen = items
                  .where((r) =>
                      r.rechnung.pdfErstelltAm != null &&
                      r.rechnung.status != 'bezahlt' &&
                      r.rechnung.status != 'storniert')
                  .where((r) {
                    if (query.isEmpty) return true;
                    final parts = [
                      r.rechnung.rechnungsnummer,
                      r.kunde == null ? null : kundeAnzeigename(r.kunde!),
                      r.auftrag?.aktenzeichen,
                      r.auftrag?.betreff,
                      r.auftrag?.bezeichnung,
                      r.rechnung.brutto.toStringAsFixed(2),
                    ]
                        .whereType<String>()
                        .map((s) => s.toLowerCase())
                        .join(' ');
                    return parts.contains(query);
                  })
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
              showCheckboxColumn: false,
                        headingRowColor: WidgetStateProperty.all(
                          Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                        ),
                        columns: const [
                          DataColumn(label: Text('Nr.')),
                          DataColumn(label: Text('Kunde')),
                          DataColumn(label: Text('Akte / Betreff')),
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
                            _row(context, ref, r, now),
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

  DataRow _row(BuildContext context, WidgetRef ref, RechnungWithKunde r,
      DateTime now) {
    final faellig = r.rechnung.faelligAm;
    final alter = faellig == null ? 0 : now.difference(faellig).inDays;
    final overdue = alter > 0;
    final offen = r.rechnung.brutto - r.rechnung.bezahlt;
    final stufe = _mahnstufe(alter);
    // Zeilenhintergrund nach Mahnstufe (wie im SV-Original):
    final rowBg = switch (stufe) {
      3 || 2 => BadgeColors.redBg.withValues(alpha: 0.5),
      1 => BadgeColors.amberBg.withValues(alpha: 0.5),
      _ => null,
    };
    return DataRow(
      color: rowBg == null
          ? null
          : WidgetStateProperty.all(rowBg),
      onSelectChanged: (_) =>
          showOposZahlungDialog(context, ref, rechnung: r),
      cells: [
        DataCell(Text(r.rechnung.rechnungsnummer ?? '',
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 12))),
        DataCell(SizedBox(
          width: 180,
          child: Text(
            r.kunde == null ? '—' : kundeAnzeigename(r.kunde!),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        )),
        DataCell(SizedBox(
          width: 220,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.auftrag?.aktenzeichen ?? '—',
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
              if ((r.auftrag?.betreff ?? r.auftrag?.bezeichnung ?? '')
                  .isNotEmpty)
                Text(
                  r.auftrag?.betreff ?? r.auftrag?.bezeichnung ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
            ],
          ),
        )),
        DataCell(Text(r.rechnung.rechnungsdatum == null
            ? ''
            : _dateFmt.format(r.rechnung.rechnungsdatum!))),
        DataCell(Text(faellig == null ? '' : _dateFmt.format(faellig))),
        DataCell(Text(
          overdue
              ? '+$alter\u00a0T'
              : (alter < 0 ? '${-alter}\u00a0T offen' : 'heute fällig'),
          style: TextStyle(
            color: overdue ? BadgeColors.redFg : null,
            fontWeight: overdue ? FontWeight.w700 : FontWeight.normal,
          ),
        )),
        DataCell(Text(_money.format(r.rechnung.brutto))),
        DataCell(Text(_money.format(r.rechnung.bezahlt))),
        DataCell(Text(_money.format(offen),
            style: const TextStyle(fontWeight: FontWeight.w600))),
        DataCell(_mahnstufeBadge(stufe)),
      ],
    );
  }

  Widget _mahnstufeBadge(int s) {
    if (s == 0) {
      return const PillBadge(
        text: 'im Ziel',
        background: BadgeColors.slateBg,
        foreground: BadgeColors.slateFg,
      );
    }
    final spec = switch (s) {
      1 => (
          'Erinnerung',
          BadgeColors.amberBg,
          BadgeColors.amberFg,
        ),
      2 => (
          '1. Mahnung',
          BadgeColors.redBg,
          BadgeColors.redFg,
        ),
      _ => (
          '2. Mahnung',
          BadgeColors.redBg,
          BadgeColors.redFg,
        ),
    };
    return PillBadge(
        text: spec.$1, background: spec.$2, foreground: spec.$3);
  }

  /// Mahnstufen-Skala wie im SV-Original
  /// (tageUeber > 0 / > 14 / > 35 → 1 / 2 / 3).
  int _mahnstufe(int alter) {
    if (alter > 35) return 3;
    if (alter > 14) return 2;
    if (alter > 0) return 1;
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
