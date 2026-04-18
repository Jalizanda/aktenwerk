import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'artikel_repository.dart';

class ArtikelScreen extends ConsumerWidget {
  const ArtikelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(artikelListProvider);
    final filter = ref.watch(artikelFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.inventory_2_outlined,
          title: 'Artikel / Leistungen',
          subtitle: 'Leistungskatalog für Angebote und Rechnungen',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neuer Artikel'),
              onPressed: () => _showForm(context, ref),
            ),
          ],
          filters: [
            SizedBox(
              width: 320,
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Bezeichnung, Nummer, Kategorie',
                ),
                onChanged: (v) => ref
                    .read(artikelFilterProvider.notifier)
                    .update((f) => f.copyWith(query: v)),
              ),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(
                value: filter.nurAktiv,
                onChanged: (v) => ref
                    .read(artikelFilterProvider.notifier)
                    .update((f) => f.copyWith(nurAktiv: v ?? true)),
              ),
              const Text('Nur aktive'),
            ]),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) => items.isEmpty
                ? const EmptyListState(
                    icon: Icons.inventory_2_outlined,
                    title: 'Noch keine Artikel',
                    hint: 'Lege oben rechts deinen ersten Artikel an.')
                : DataTableCard(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      columns: const [
                        DataColumn(label: Text('Nr.')),
                        DataColumn(label: Text('Bezeichnung')),
                        DataColumn(label: Text('Kategorie')),
                        DataColumn(label: Text('Einheit')),
                        DataColumn(label: Text('Preis'), numeric: true),
                        DataColumn(label: Text('USt %'), numeric: true),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final a in items)
                          DataRow(
                            onSelectChanged: (_) =>
                                _showForm(context, ref, a),
                            cells: [
                              DataCell(Text(a.nummer ?? '')),
                              DataCell(Text(a.bezeichnung)),
                              DataCell(Text(a.kategorie ?? '')),
                              DataCell(Text(a.einheit ?? '')),
                              DataCell(Text(
                                  a.einzelpreis.toStringAsFixed(2))),
                              DataCell(Text(
                                  a.ustSatz.toStringAsFixed(0))),
                              DataCell(IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                onPressed: () =>
                                    _confirmDelete(context, ref, a),
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

  Future<void> _showForm(BuildContext context, WidgetRef ref,
      [ArtikelData? artikel]) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => _ArtikelFormDialog(artikel: artikel),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, ArtikelData a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Artikel löschen?'),
        content: Text('«${a.bezeichnung}» wird dauerhaft gelöscht.'),
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
    if (ok == true) {
      await ref.read(artikelRepositoryProvider).delete(a.id);
    }
  }
}

class _ArtikelFormDialog extends ConsumerStatefulWidget {
  const _ArtikelFormDialog({this.artikel});
  final ArtikelData? artikel;
  @override
  ConsumerState<_ArtikelFormDialog> createState() =>
      _ArtikelFormDialogState();
}

class _ArtikelFormDialogState extends ConsumerState<_ArtikelFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nr = _tec(widget.artikel?.nummer);
  late final _bez = _tec(widget.artikel?.bezeichnung);
  late final _beschreibung = _tec(widget.artikel?.beschreibung);
  late final _kategorie = _tec(widget.artikel?.kategorie);
  late final _einheit = _tec(widget.artikel?.einheit);
  late final _preis = _tec(widget.artikel?.einzelpreis.toStringAsFixed(2));
  late final _ust = _tec(widget.artikel?.ustSatz.toStringAsFixed(0));
  bool _aktiv = true;
  bool _saving = false;

  TextEditingController _tec(String? v) =>
      TextEditingController(text: v ?? '');

  @override
  void initState() {
    super.initState();
    _aktiv = widget.artikel?.aktiv ?? true;
  }

  @override
  void dispose() {
    for (final c in [_nr, _bez, _beschreibung, _kategorie, _einheit, _preis, _ust]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.artikel != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final preis = double.tryParse(_preis.text.replaceAll(',', '.')) ?? 0;
    final ust = double.tryParse(_ust.text.replaceAll(',', '.')) ?? 19;
    final companion = ArtikelCompanion(
      id: _isEdit ? Value(widget.artikel!.id) : const Value.absent(),
      nummer: _nt(_nr),
      bezeichnung: Value(_bez.text.trim()),
      beschreibung: _nt(_beschreibung),
      kategorie: _nt(_kategorie),
      einheit: _nt(_einheit),
      einzelpreis: Value(preis),
      ustSatz: Value(ust),
      aktiv: Value(_aktiv),
    );
    try {
      await ref.read(artikelRepositoryProvider).upsert(companion);
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
      title: _isEdit ? 'Artikel bearbeiten' : 'Neuer Artikel',
      maxWidth: 640,
      maxHeight: 620,
      saving: _saving,
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
                flex: const (1, 3),
                left: LabeledField('Nummer', TextFormField(controller: _nr)),
                right: LabeledField(
                  'Bezeichnung',
                  TextFormField(
                    controller: _bez,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Erforderlich' : null,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Beschreibung',
                TextFormField(
                    controller: _beschreibung,
                    minLines: 2,
                    maxLines: 5),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                    'Kategorie', TextFormField(controller: _kategorie)),
                right: LabeledField(
                    'Einheit', TextFormField(controller: _einheit)),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                  'Einzelpreis (€)',
                  TextFormField(
                    controller: _preis,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                right: LabeledField(
                  'USt-Satz (%)',
                  TextFormField(
                    controller: _ust,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Checkbox(
                    value: _aktiv,
                    onChanged: (v) => setState(() => _aktiv = v ?? true)),
                const Text('Aktiv'),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
