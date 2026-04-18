import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../features/akten/auftraege/auftraege_repository.dart';
import '../../../features/akten/kunden/kunden_repository.dart';
import '../../../features/akten/rechnungen/rechnungen_repository.dart';
import '../../../features/kalkulation/auslagen/auslagen_repository.dart';
import '../../../features/kalkulation/stunden/stunden_repository.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';

/// Ist/Soll-Übersicht pro Auftrag.
class KalkulationScreen extends ConsumerStatefulWidget {
  const KalkulationScreen({super.key});
  @override
  ConsumerState<KalkulationScreen> createState() =>
      _KalkulationScreenState();
}

class _KalkulationScreenState extends ConsumerState<KalkulationScreen> {
  int? _auftragId;
  AuftragWithKunde? _auftrag;

  Future<void> _load(int id) async {
    final repo = ref.read(auftraegeRepositoryProvider);
    final kundenRepo = ref.read(kundenRepositoryProvider);
    final a = await repo.byId(id);
    if (a == null) {
      setState(() => _auftrag = null);
      return;
    }
    final k = a.kundeId == null ? null : await kundenRepo.byId(a.kundeId!);
    setState(() => _auftrag = AuftragWithKunde(a, k));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat.currency(locale: 'de', symbol: '€');
    final stundenFilter = ref.watch(stundenFilterProvider);
    final auslagenFilter = ref.watch(auslagenFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.functions_outlined,
          title: 'Kalkulation',
          subtitle: 'Ist-Kosten pro Auftrag (Stunden, Auslagen, Rechnungen)',
          filters: [
            SizedBox(
              width: 360,
              child: _AuftragDropdown(
                auftragId: _auftragId,
                onChanged: (id) {
                  setState(() {
                    _auftragId = id;
                    _auftrag = null;
                  });
                  if (id != null) _load(id);
                  ref
                      .read(stundenFilterProvider.notifier)
                      .update((f) => id == null
                          ? f.copyWith(clearAuftrag: true)
                          : f.copyWith(auftragId: id));
                  ref
                      .read(auslagenFilterProvider.notifier)
                      .update((f) => id == null
                          ? f.copyWith(clearAuftrag: true)
                          : f.copyWith(auftragId: id));
                },
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: _auftragId == null
              ? const EmptyListState(
                  icon: Icons.functions_outlined,
                  title: 'Bitte Auftrag wählen',
                  hint:
                      'Wähle oben einen Auftrag, um die Kalkulation zu sehen.',
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _KalkulationBody(
                    auftrag: _auftrag,
                    stunden:
                        ref.watch(stundenListProvider).valueOrNull ?? [],
                    auslagen:
                        ref.watch(auslagenListProvider).valueOrNull ?? [],
                    rechnungen: (ref
                                .watch(rechnungenListProvider)
                                .valueOrNull ??
                            [])
                        .where((r) => r.rechnung.auftragId == _auftragId)
                        .toList(),
                    money: money,
                    theme: theme,
                    filterActive:
                        stundenFilter.auftragId == _auftragId &&
                            auslagenFilter.auftragId == _auftragId,
                  ),
                ),
        ),
      ],
    );
  }
}

class _AuftragDropdown extends ConsumerWidget {
  const _AuftragDropdown(
      {required this.auftragId, required this.onChanged});
  final int? auftragId;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(auftraegeListProvider);
    return async.when(
      loading: () => const SizedBox(
        height: 48,
        child: Center(
            child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (e, _) => Text('Fehler: $e'),
      data: (items) => DropdownButtonFormField<int?>(
        initialValue: auftragId,
        isExpanded: true,
        decoration: const InputDecoration(
            labelText: 'Auftrag', isDense: true),
        items: [
          const DropdownMenuItem(
              value: null, child: Text('(kein Auftrag)')),
          for (final r in items)
            DropdownMenuItem(
              value: r.auftrag.id,
              child: Text(
                '${r.auftrag.aktenzeichen ?? '(o. A.)'} · ${r.kunde == null ? '—' : kundeAnzeigename(r.kunde!)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _KalkulationBody extends StatelessWidget {
  const _KalkulationBody({
    required this.auftrag,
    required this.stunden,
    required this.auslagen,
    required this.rechnungen,
    required this.money,
    required this.theme,
    required this.filterActive,
  });
  final AuftragWithKunde? auftrag;
  final List<StundenWithAuftrag> stunden;
  final List<AuslageWithAuftrag> auslagen;
  final List<RechnungWithKunde> rechnungen;
  final NumberFormat money;
  final ThemeData theme;
  final bool filterActive;

  @override
  Widget build(BuildContext context) {
    final stundenSumme = stunden.fold<double>(
        0,
        (acc, s) =>
            acc + (s.stunde.minuten / 60.0) * (s.stunde.satz ?? 0));
    final stundenMinuten =
        stunden.fold<int>(0, (acc, s) => acc + s.stunde.minuten);
    final auslagenSumme =
        auslagen.fold<double>(0, (acc, a) => acc + a.auslage.summe);
    final rechnungenSumme = rechnungen.fold<double>(
        0, (acc, r) => acc + r.rechnung.netto);
    final kostenLimit = auftrag?.auftrag.kostenLimit;
    final kostenvorschuss = auftrag?.auftrag.kostenvorschuss ?? 0;

    final gesamt = stundenSumme + auslagenSumme;
    final pct = kostenLimit == null || kostenLimit == 0
        ? null
        : (gesamt / kostenLimit).clamp(0.0, 1.5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!filterActive)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Einen Moment – Daten werden noch geladen …',
              style: theme.textTheme.bodySmall,
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Tile(
              label: 'Stunden gesamt',
              value:
                  '${(stundenMinuten / 60).toStringAsFixed(1)} Std',
              sub: money.format(stundenSumme),
            ),
            _Tile(
              label: 'Auslagen',
              value: money.format(auslagenSumme),
              sub: '${auslagen.length} Posten',
            ),
            _Tile(
              label: 'Ist-Kosten',
              value: money.format(gesamt),
              sub: 'Stunden + Auslagen',
              color: theme.colorScheme.primary,
            ),
            _Tile(
              label: 'Rechnungen (netto)',
              value: money.format(rechnungenSumme),
              sub: '${rechnungen.length} Rechnung(en)',
            ),
            _Tile(
              label: 'Kostenvorschuss',
              value: money.format(kostenvorschuss),
            ),
            if (kostenLimit != null)
              _Tile(
                label: 'Kostenlimit',
                value: money.format(kostenLimit),
                sub: pct == null
                    ? null
                    : '${(pct * 100).toStringAsFixed(0)} % ausgeschöpft',
                color: pct != null && pct >= 0.9
                    ? theme.colorScheme.error
                    : null,
              ),
          ],
        ),
        if (pct != null) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: pct > 1.0 ? 1.0 : pct.toDouble(),
            minHeight: 8,
            color: pct >= 0.9
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    this.sub,
    this.color,
  });
  final String label;
  final String value;
  final String? sub;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant),
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
              if (sub != null)
                Text(sub!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        )),
            ],
          ),
        ),
      ),
    );
  }
}
