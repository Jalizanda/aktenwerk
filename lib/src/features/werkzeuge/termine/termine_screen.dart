import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'termine_repository.dart';

class TermineScreen extends ConsumerWidget {
  const TermineScreen({super.key});
  static final _dateFmt = DateFormat('EEEE, dd.MM.yyyy', 'de');
  static final _timeFmt = DateFormat('HH:mm', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(termineListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ModuleHeader(
          icon: Icons.event_outlined,
          title: 'Termine',
          subtitle:
              'Erläuterungstermine und Wiedervorlagen zusammengeführt',
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) {
              if (items.isEmpty) {
                return const EmptyListState(
                  icon: Icons.event_outlined,
                  title: 'Keine anstehenden Termine',
                );
              }
              final grouped = <String, List<TerminEintrag>>{};
              for (final t in items) {
                final key = _dateFmt.format(t.zeitpunkt);
                grouped.putIfAbsent(key, () => []).add(t);
              }
              final keys = grouped.keys.toList();
              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                itemCount: keys.length,
                itemBuilder: (_, i) {
                  final k = keys[i];
                  final group = grouped[k]!;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(k,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium),
                            const SizedBox(height: 4),
                            for (final t in group)
                              _TerminRow(eintrag: t, timeFmt: _timeFmt),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TerminRow extends StatelessWidget {
  const _TerminRow({required this.eintrag, required this.timeFmt});
  final TerminEintrag eintrag;
  final DateFormat timeFmt;

  @override
  Widget build(BuildContext context) {
    final isWV = eintrag.typ == 'Wiedervorlage';
    final isPast = eintrag.zeitpunkt.isBefore(DateTime.now());
    final color = isPast
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            timeFmt.format(eintrag.zeitpunkt),
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: color),
          ),
          const SizedBox(width: 12),
          Chip(
            label: Text(eintrag.typ,
                style: const TextStyle(fontSize: 11)),
            visualDensity: VisualDensity.compact,
            backgroundColor: isWV
                ? Theme.of(context).colorScheme.tertiaryContainer
                : Theme.of(context).colorScheme.primaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(eintrag.titel, style: TextStyle(color: color)),
                if ((eintrag.ort ?? '').isNotEmpty ||
                    (eintrag.aktenzeichen ?? '').isNotEmpty)
                  Text(
                    [eintrag.aktenzeichen, eintrag.ort]
                        .whereType<String>()
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                    style:
                        Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
