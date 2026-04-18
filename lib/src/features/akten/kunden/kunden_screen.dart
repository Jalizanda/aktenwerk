import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import 'kunden_form.dart';
import 'kunden_repository.dart';

class KundenScreen extends ConsumerWidget {
  const KundenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(kundenListProvider);
    final filter = ref.watch(kundenFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(filter: filter),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Fehler beim Laden: $e'),
              ),
            ),
            data: (items) => items.isEmpty
                ? _EmptyState(hasFilter: _hasFilter(filter))
                : _KundenTable(items: items),
          ),
        ),
      ],
    );
  }

  bool _hasFilter(KundenFilter f) => f.query.isNotEmpty || f.typ != null;
}

class _Toolbar extends ConsumerStatefulWidget {
  const _Toolbar({required this.filter});
  final KundenFilter filter;

  @override
  ConsumerState<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends ConsumerState<_Toolbar> {
  late final _queryController =
      TextEditingController(text: widget.filter.query);

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          const Icon(Icons.people_outline, size: 28),
          const SizedBox(width: 10),
          Text('Auftraggeber',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(width: 24),
          SizedBox(
            width: 320,
            child: TextField(
              controller: _queryController,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Suche Name, Firma, Ort, PLZ, E-Mail',
                suffixIcon: widget.filter.query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _queryController.clear();
                          ref
                              .read(kundenFilterProvider.notifier)
                              .update((f) => f.copyWith(query: ''));
                        },
                      ),
              ),
              onChanged: (v) => ref
                  .read(kundenFilterProvider.notifier)
                  .update((f) => f.copyWith(query: v)),
            ),
          ),
          const SizedBox(width: 12),
          DropdownButtonHideUnderline(
            child: DropdownButton<KundenTyp?>(
              value: widget.filter.typ,
              hint: const Text('Alle Typen'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Alle Typen')),
                for (final t in KundenTyp.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (t) =>
                  ref.read(kundenFilterProvider.notifier).update((f) =>
                      t == null
                          ? f.copyWith(clearTyp: true)
                          : f.copyWith(typ: t)),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => showKundenFormDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Neuer Auftraggeber'),
          ),
        ],
      ),
    );
  }
}

class _KundenTable extends ConsumerWidget {
  const _KundenTable({required this.items});
  final List<KundenData> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side:
                BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            columns: const [
              DataColumn(label: Text('Typ')),
              DataColumn(label: Text('Name / Firma')),
              DataColumn(label: Text('Ort')),
              DataColumn(label: Text('Telefon')),
              DataColumn(label: Text('E-Mail')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final k in items) _row(context, ref, k),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _row(BuildContext context, WidgetRef ref, KundenData k) {
    return DataRow(
      onSelectChanged: (_) => showKundenFormDialog(context, kunde: k),
      cells: [
        DataCell(_TypBadge(typ: KundenTypX.fromDb(k.typ))),
        DataCell(Text(kundeAnzeigename(k))),
        DataCell(Text(
          [k.plz, k.ort].whereType<String>().join(' ').trim(),
        )),
        DataCell(Text(k.telefon ?? '')),
        DataCell(Text(k.email ?? '')),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Bearbeiten',
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () => showKundenFormDialog(context, kunde: k),
              ),
              IconButton(
                tooltip: 'Löschen',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _confirmDelete(context, ref, k),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, KundenData k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Auftraggeber löschen?'),
        content: Text(
            '«${kundeAnzeigename(k)}» wird dauerhaft gelöscht.\n'
            'Verknüpfte Aufträge verlieren die Referenz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(kundenRepositoryProvider).delete(k.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('«${kundeAnzeigename(k)}» gelöscht')),
        );
      }
    }
  }
}

class _TypBadge extends StatelessWidget {
  const _TypBadge({required this.typ});
  final KundenTyp typ;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (typ) {
      KundenTyp.privat => (scheme.surfaceContainerHighest, scheme.onSurface),
      KundenTyp.firma => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      KundenTyp.anwalt => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      KundenTyp.gericht => (scheme.primaryContainer, scheme.onPrimaryContainer),
      KundenTyp.versicherung => (scheme.errorContainer, scheme.onErrorContainer),
      KundenTyp.behoerde => (scheme.surfaceContainerHigh, scheme.onSurface),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        typ.label,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasFilter});
  final bool hasFilter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline,
                size: 64,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              hasFilter
                  ? 'Keine Treffer für diesen Filter'
                  : 'Noch keine Auftraggeber erfasst',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (!hasFilter)
              Text(
                'Lege oben rechts deinen ersten Auftraggeber an.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
      ),
    );
  }
}
