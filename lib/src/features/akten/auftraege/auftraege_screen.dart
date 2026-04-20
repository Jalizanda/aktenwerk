import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/badges.dart';
import '../kunden/kunden_repository.dart';
import 'auftraege_form.dart';
import 'auftraege_repository.dart';

class AuftraegeScreen extends ConsumerWidget {
  const AuftraegeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(auftraegeListProvider);
    final filter = ref.watch(auftraegeFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(filter: filter),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) => items.isEmpty
                ? _EmptyState(hasFilter: filter.isActive)
                : _AuftraegeTable(items: items),
          ),
        ),
      ],
    );
  }
}

class _Toolbar extends ConsumerStatefulWidget {
  const _Toolbar({required this.filter});
  final AuftraegeFilter filter;

  @override
  ConsumerState<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends ConsumerState<_Toolbar> {
  late final _controller =
      TextEditingController(text: widget.filter.query);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.assignment_outlined, size: 28),
              const SizedBox(width: 10),
              Text('Aufträge',
                  style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
          SizedBox(
            width: 320,
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Aktenzeichen, Bezeichnung, Ort …',
                suffixIcon: widget.filter.query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _controller.clear();
                          ref
                              .read(auftraegeFilterProvider.notifier)
                              .update((f) => f.copyWith(query: ''));
                        },
                      ),
              ),
              onChanged: (v) => ref
                  .read(auftraegeFilterProvider.notifier)
                  .update((f) => f.copyWith(query: v)),
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<AuftragArt?>(
              value: widget.filter.art,
              hint: const Text('Alle Arten'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Alle Arten')),
                for (final a in AuftragArt.values)
                  DropdownMenuItem(value: a, child: Text(a.label)),
              ],
              onChanged: (v) =>
                  ref.read(auftraegeFilterProvider.notifier).update((f) =>
                      v == null
                          ? f.copyWith(clearArt: true)
                          : f.copyWith(art: v)),
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<AuftragStatus?>(
              value: widget.filter.status,
              hint: const Text('Alle Status'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Alle Status')),
                for (final s in AuftragStatus.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (v) =>
                  ref.read(auftraegeFilterProvider.notifier).update((f) =>
                      v == null
                          ? f.copyWith(clearStatus: true)
                          : f.copyWith(status: v)),
            ),
          ),
          FilledButton.icon(
            onPressed: () => showAuftragFormDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Neuer Auftrag'),
          ),
        ],
      ),
    );
  }
}

class _AuftraegeTable extends ConsumerWidget {
  const _AuftraegeTable({required this.items});
  final List<AuftragWithKunde> items;

  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: DataTable(
              showCheckboxColumn: false,
            headingRowColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            columns: const [
              DataColumn(label: Text('Aktenzeichen')),
              DataColumn(label: Text('Art')),
              DataColumn(label: Text('Auftraggeber')),
              DataColumn(label: Text('Objekt')),
              DataColumn(label: Text('Eingang')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('')),
            ],
            rows: [for (final r in items) _row(context, ref, r)],
          ),
        ),
      ),
    );
  }

  DataRow _row(BuildContext context, WidgetRef ref, AuftragWithKunde r) {
    final a = r.auftrag;
    final kunde = r.kunde;
    return DataRow(
      onSelectChanged: (_) => showAuftragFormDialog(context, auftrag: a),
      cells: [
        DataCell(Text(a.aktenzeichen ?? '—',
            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))),
        DataCell(Text(AuftragArtX.fromDb(a.art).label)),
        DataCell(Text(
            kunde == null ? '—' : kundeAnzeigename(kunde))),
        DataCell(Text([
          a.objektStrasse,
          [a.objektPlz, a.objektOrt]
              .whereType<String>()
              .join(' ')
              .trim(),
        ].whereType<String>().where((s) => s.isNotEmpty).join(', '))),
        DataCell(
          Text(a.eingangAm == null ? '' : _dateFmt.format(a.eingangAm!)),
        ),
        DataCell(_StatusBadge(status: AuftragStatusX.fromDb(a.status))),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Bearbeiten',
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () =>
                    showAuftragFormDialog(context, auftrag: a),
              ),
              IconButton(
                tooltip: 'Löschen',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _confirmDelete(context, ref, r),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, AuftragWithKunde r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Auftrag löschen?'),
        content: Text(
          'Auftrag ${r.auftrag.aktenzeichen ?? ''} wird dauerhaft gelöscht. '
          'Verknüpfte Gutachten, Stunden, Auslagen werden ebenfalls entfernt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref
          .read(auftraegeRepositoryProvider)
          .delete(r.auftrag.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Auftrag ${r.auftrag.aktenzeichen ?? ''} gelöscht')),
        );
      }
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final AuftragStatus status;

  @override
  Widget build(BuildContext context) {
    // Farbpalette 1:1 aus der Original-SV-Software (.badge-status-*).
    final (bg, fg) = switch (status) {
      AuftragStatus.offen => (BadgeColors.blueBg, BadgeColors.blueFg),
      AuftragStatus.inArbeit => (BadgeColors.amberBg, BadgeColors.amberFg),
      AuftragStatus.wartet => (BadgeColors.slateBg, BadgeColors.slateFg),
      AuftragStatus.abgeschlossen =>
        (BadgeColors.greenBg, BadgeColors.greenFg),
      AuftragStatus.abgerechnet =>
        (BadgeColors.greenBg, BadgeColors.greenFg),
      AuftragStatus.storniert => (BadgeColors.redBg, BadgeColors.redFg),
    };
    return PillBadge(text: status.label, background: bg, foreground: fg);
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
            Icon(Icons.assignment_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              hasFilter
                  ? 'Keine Aufträge für diesen Filter'
                  : 'Noch keine Aufträge erfasst',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (!hasFilter)
              Text(
                'Lege oben rechts einen neuen Auftrag an.',
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
