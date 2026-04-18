import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'normen_repository.dart';

class NormenScreen extends ConsumerWidget {
  const NormenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(normenListProvider);
    final filter = ref.watch(normenFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.menu_book_outlined,
          title: 'Normen',
          subtitle: 'Normen-Katalog (DIN, EN, ISO, VOB)',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neue Norm'),
              onPressed: () => _show(context, ref),
            ),
          ],
          filters: [
            SizedBox(
              width: 320,
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Nummer, Titel, Kategorie',
                ),
                onChanged: (v) => ref
                    .read(normenFilterProvider.notifier)
                    .update((f) => f.copyWith(query: v)),
              ),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(
                value: filter.nurFavoriten,
                onChanged: (v) => ref
                    .read(normenFilterProvider.notifier)
                    .update((f) => f.copyWith(nurFavoriten: v ?? false)),
              ),
              const Text('Nur Favoriten'),
            ]),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) => items.isEmpty
                ? const EmptyListState(
                    icon: Icons.menu_book_outlined,
                    title: 'Keine Normen erfasst')
                : DataTableCard(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      columns: const [
                        DataColumn(label: Text('')),
                        DataColumn(label: Text('Nummer')),
                        DataColumn(label: Text('Titel')),
                        DataColumn(label: Text('Ausgabe')),
                        DataColumn(label: Text('Kategorie')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final n in items)
                          DataRow(
                            onSelectChanged: (_) => _show(context, ref, n),
                            cells: [
                              DataCell(IconButton(
                                icon: Icon(
                                  n.favorit
                                      ? Icons.star
                                      : Icons.star_outline,
                                  size: 20,
                                  color: n.favorit
                                      ? Theme.of(context)
                                          .colorScheme
                                          .tertiary
                                      : null,
                                ),
                                onPressed: () => ref
                                    .read(normenRepositoryProvider)
                                    .toggleFavorit(n.id, !n.favorit),
                              )),
                              DataCell(Text(n.nummer)),
                              DataCell(Text(n.titel ?? '')),
                              DataCell(Text(n.ausgabe ?? '')),
                              DataCell(Text(n.kategorie ?? '')),
                              DataCell(IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                onPressed: () =>
                                    _confirm(context, ref, n),
                              )),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _show(BuildContext context, WidgetRef ref,
      [NormenData? n]) async {
    await showDialog(
        context: context, builder: (_) => _NormForm(norm: n));
  }

  Future<void> _confirm(
      BuildContext context, WidgetRef ref, NormenData n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Norm löschen?'),
        content: Text('«${n.nummer}» wird gelöscht.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(normenRepositoryProvider).delete(n.id);
  }
}

class _NormForm extends ConsumerStatefulWidget {
  const _NormForm({this.norm});
  final NormenData? norm;
  @override
  ConsumerState<_NormForm> createState() => _NormFormState();
}

class _NormFormState extends ConsumerState<_NormForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nr = TextEditingController(text: widget.norm?.nummer ?? '');
  late final _titel =
      TextEditingController(text: widget.norm?.titel ?? '');
  late final _ausgabe =
      TextEditingController(text: widget.norm?.ausgabe ?? '');
  late final _kategorie =
      TextEditingController(text: widget.norm?.kategorie ?? '');
  late final _beschreibung =
      TextEditingController(text: widget.norm?.beschreibung ?? '');
  bool _aktiv = true;
  bool _favorit = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _aktiv = widget.norm?.aktiv ?? true;
    _favorit = widget.norm?.favorit ?? false;
  }

  @override
  void dispose() {
    for (final c in [_nr, _titel, _ausgabe, _kategorie, _beschreibung]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.norm != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final companion = NormenCompanion(
      id: _isEdit ? Value(widget.norm!.id) : const Value.absent(),
      nummer: Value(_nr.text.trim()),
      titel: _nt(_titel),
      ausgabe: _nt(_ausgabe),
      kategorie: _nt(_kategorie),
      beschreibung: _nt(_beschreibung),
      aktiv: Value(_aktiv),
      favorit: Value(_favorit),
    );
    try {
      await ref.read(normenRepositoryProvider).upsert(companion);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Value<String?> _nt(TextEditingController c) {
    final v = c.text.trim();
    return Value(v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    return StandardFormDialog(
      title: _isEdit ? 'Norm bearbeiten' : 'Neue Norm',
      saving: _saving,
      maxHeight: 560,
      onCancel: () => Navigator.pop(context, false),
      onSave: _save,
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row2(
                flex: const (2, 3),
                left: LabeledField(
                  'Nummer',
                  TextFormField(
                    controller: _nr,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Erforderlich' : null,
                  ),
                ),
                right: LabeledField(
                    'Ausgabe', TextFormField(controller: _ausgabe)),
              ),
              const SizedBox(height: 12),
              LabeledField('Titel', TextFormField(controller: _titel)),
              const SizedBox(height: 12),
              LabeledField(
                  'Kategorie', TextFormField(controller: _kategorie)),
              const SizedBox(height: 12),
              LabeledField(
                'Beschreibung',
                TextFormField(
                    controller: _beschreibung,
                    minLines: 2,
                    maxLines: 5),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Checkbox(
                    value: _aktiv,
                    onChanged: (v) => setState(() => _aktiv = v ?? true)),
                const Text('Aktiv'),
                const SizedBox(width: 16),
                Checkbox(
                    value: _favorit,
                    onChanged: (v) => setState(() => _favorit = v ?? false)),
                const Text('Favorit'),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
