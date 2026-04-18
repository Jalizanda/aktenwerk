import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'lieferanten_repository.dart';

class LieferantenScreen extends ConsumerWidget {
  const LieferantenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lieferantenListProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.local_shipping_outlined,
          title: 'Lieferanten',
          subtitle: 'Dienstleister, Labore, Materiallieferanten',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neuer Lieferant'),
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
                  hintText: 'Firma, Ort, Kategorie',
                ),
                onChanged: (v) =>
                    ref.read(lieferantenQueryProvider.notifier).state = v,
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) => items.isEmpty
                ? const EmptyListState(
                    icon: Icons.local_shipping_outlined,
                    title: 'Keine Lieferanten erfasst')
                : DataTableCard(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      columns: const [
                        DataColumn(label: Text('Firma')),
                        DataColumn(label: Text('Ansprechpartner')),
                        DataColumn(label: Text('Ort')),
                        DataColumn(label: Text('Kategorie')),
                        DataColumn(label: Text('Telefon')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final l in items)
                          DataRow(
                            onSelectChanged: (_) => _show(context, ref, l),
                            cells: [
                              DataCell(Text(l.firma)),
                              DataCell(Text(l.ansprechpartner ?? '')),
                              DataCell(Text(
                                  [l.plz, l.ort].whereType<String>().join(' '))),
                              DataCell(Text(l.kategorie ?? '')),
                              DataCell(Text(l.telefon ?? '')),
                              DataCell(IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                onPressed: () =>
                                    _confirm(context, ref, l),
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
      [LieferantenData? l]) async {
    await showDialog(
      context: context,
      builder: (_) => _LieferantForm(lieferant: l),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref,
      LieferantenData l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Lieferant löschen?'),
        content: Text('«${l.firma}» wird gelöscht.'),
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
      await ref.read(lieferantenRepositoryProvider).delete(l.id);
    }
  }
}

class _LieferantForm extends ConsumerStatefulWidget {
  const _LieferantForm({this.lieferant});
  final LieferantenData? lieferant;
  @override
  ConsumerState<_LieferantForm> createState() => _LieferantFormState();
}

class _LieferantFormState extends ConsumerState<_LieferantForm> {
  final _formKey = GlobalKey<FormState>();
  late final _firma = _tec(widget.lieferant?.firma);
  late final _ansprech = _tec(widget.lieferant?.ansprechpartner);
  late final _strasse = _tec(widget.lieferant?.strasse);
  late final _plz = _tec(widget.lieferant?.plz);
  late final _ort = _tec(widget.lieferant?.ort);
  late final _telefon = _tec(widget.lieferant?.telefon);
  late final _email = _tec(widget.lieferant?.email);
  late final _website = _tec(widget.lieferant?.website);
  late final _kategorie = _tec(widget.lieferant?.kategorie);
  late final _kdnr = _tec(widget.lieferant?.kundennummer);
  late final _ustId = _tec(widget.lieferant?.ustId);
  late final _iban = _tec(widget.lieferant?.iban);
  late final _bic = _tec(widget.lieferant?.bic);
  late final _notiz = _tec(widget.lieferant?.notiz);
  bool _saving = false;

  TextEditingController _tec(String? v) =>
      TextEditingController(text: v ?? '');

  @override
  void dispose() {
    for (final c in [
      _firma, _ansprech, _strasse, _plz, _ort, _telefon, _email, _website,
      _kategorie, _kdnr, _ustId, _iban, _bic, _notiz,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.lieferant != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final companion = LieferantenCompanion(
      id: _isEdit ? Value(widget.lieferant!.id) : const Value.absent(),
      firma: Value(_firma.text.trim()),
      ansprechpartner: _nt(_ansprech),
      strasse: _nt(_strasse),
      plz: _nt(_plz),
      ort: _nt(_ort),
      telefon: _nt(_telefon),
      email: _nt(_email),
      website: _nt(_website),
      kategorie: _nt(_kategorie),
      kundennummer: _nt(_kdnr),
      ustId: _nt(_ustId),
      iban: _nt(_iban),
      bic: _nt(_bic),
      notiz: _nt(_notiz),
    );
    try {
      await ref.read(lieferantenRepositoryProvider).upsert(companion);
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
      title: _isEdit ? 'Lieferant bearbeiten' : 'Neuer Lieferant',
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
              LabeledField(
                'Firma',
                TextFormField(
                  controller: _firma,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Erforderlich' : null,
                ),
              ),
              const SizedBox(height: 12),
              LabeledField('Ansprechpartner',
                  TextFormField(controller: _ansprech)),
              const SizedBox(height: 12),
              LabeledField('Straße', TextFormField(controller: _strasse)),
              const SizedBox(height: 12),
              Row2(
                flex: const (1, 3),
                left: LabeledField('PLZ', TextFormField(controller: _plz)),
                right: LabeledField('Ort', TextFormField(controller: _ort)),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                    'Telefon', TextFormField(controller: _telefon)),
                right: LabeledField(
                    'E-Mail', TextFormField(controller: _email)),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                    'Website', TextFormField(controller: _website)),
                right: LabeledField(
                    'Kategorie', TextFormField(controller: _kategorie)),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                    'Kundennummer', TextFormField(controller: _kdnr)),
                right: LabeledField(
                    'USt-ID', TextFormField(controller: _ustId)),
              ),
              const SizedBox(height: 12),
              Row2(
                flex: const (3, 1),
                left: LabeledField(
                    'IBAN', TextFormField(controller: _iban)),
                right: LabeledField(
                    'BIC', TextFormField(controller: _bic)),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Notiz',
                TextFormField(controller: _notiz, minLines: 2, maxLines: 5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
