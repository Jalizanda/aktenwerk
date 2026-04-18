import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'auslagen_repository.dart';

class AuslagenScreen extends ConsumerWidget {
  const AuslagenScreen({super.key});
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(auslagenListProvider);
    final filter = ref.watch(auslagenFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.payments_outlined,
          title: 'Auslagen',
          subtitle: 'Auslagen pro Auftrag (Fahrt, Porto, Kopien, Labor …)',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neue Auslage'),
              onPressed: () => _show(context, ref),
            ),
          ],
          filters: [
            DropdownButtonHideUnderline(
              child: DropdownButton<bool?>(
                value: filter.abgerechnet,
                hint: const Text('Alle'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Alle')),
                  DropdownMenuItem(value: false, child: Text('Nur offen')),
                  DropdownMenuItem(value: true, child: Text('Nur abgerechnet')),
                ],
                onChanged: (v) => ref
                    .read(auslagenFilterProvider.notifier)
                    .update((f) => v == null
                        ? f.copyWith(clearAbgerechnet: true)
                        : f.copyWith(abgerechnet: v)),
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
                    icon: Icons.payments_outlined,
                    title: 'Keine Auslagen erfasst')
                : DataTableCard(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      columns: const [
                        DataColumn(label: Text('Datum')),
                        DataColumn(label: Text('Auftrag')),
                        DataColumn(label: Text('Kategorie')),
                        DataColumn(label: Text('Beschreibung')),
                        DataColumn(label: Text('Menge'), numeric: true),
                        DataColumn(label: Text('Summe €'), numeric: true),
                        DataColumn(label: Text('Abgerechnet')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final a in items)
                          DataRow(
                            onSelectChanged: (_) => _show(context, ref, a),
                            cells: [
                              DataCell(Text(_dateFmt.format(a.auslage.datum))),
                              DataCell(Text(a.auftrag?.aktenzeichen ?? '—')),
                              DataCell(Text(a.auslage.kategorie ?? '')),
                              DataCell(Text(a.auslage.beschreibung ?? '')),
                              DataCell(Text(
                                  '${a.auslage.menge.toStringAsFixed(2)} ${a.auslage.einheit ?? ''}')),
                              DataCell(Text(
                                  a.auslage.summe.toStringAsFixed(2))),
                              DataCell(Checkbox(
                                value: a.auslage.abgerechnet,
                                onChanged: (v) async {
                                  await ref
                                      .read(auslagenRepositoryProvider)
                                      .upsert(AuslagenCompanion(
                                        id: Value(a.auslage.id),
                                        abgerechnet: Value(v ?? false),
                                      ));
                                },
                              )),
                              DataCell(IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                onPressed: () async => ref
                                    .read(auslagenRepositoryProvider)
                                    .delete(a.auslage.id),
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
      [AuslageWithAuftrag? a]) async {
    await showDialog(
      context: context,
      builder: (_) => _AuslageForm(eintrag: a),
    );
  }
}

class _AuslageForm extends ConsumerStatefulWidget {
  const _AuslageForm({this.eintrag});
  final AuslageWithAuftrag? eintrag;
  @override
  ConsumerState<_AuslageForm> createState() => _AuslageFormState();
}

class _AuslageFormState extends ConsumerState<_AuslageForm> {
  final _formKey = GlobalKey<FormState>();
  int? _auftragId;
  DateTime _datum = DateTime.now();
  late final _kat =
      TextEditingController(text: widget.eintrag?.auslage.kategorie ?? '');
  late final _beschreibung = TextEditingController(
      text: widget.eintrag?.auslage.beschreibung ?? '');
  late final _menge = TextEditingController(
      text: widget.eintrag?.auslage.menge.toStringAsFixed(2) ?? '1,00');
  late final _einheit =
      TextEditingController(text: widget.eintrag?.auslage.einheit ?? '');
  late final _einzel = TextEditingController(
      text: widget.eintrag?.auslage.einzelpreis.toStringAsFixed(2) ?? '');
  late final _notiz =
      TextEditingController(text: widget.eintrag?.auslage.notiz ?? '');
  bool _abgerechnet = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _auftragId = widget.eintrag?.auslage.auftragId;
    _datum = widget.eintrag?.auslage.datum ?? DateTime.now();
    _abgerechnet = widget.eintrag?.auslage.abgerechnet ?? false;
  }

  @override
  void dispose() {
    for (final c in [_kat, _beschreibung, _menge, _einheit, _einzel, _notiz]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.eintrag != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final menge = double.tryParse(_menge.text.replaceAll(',', '.')) ?? 1;
    final ep =
        double.tryParse(_einzel.text.replaceAll(',', '.')) ?? 0;
    final summe = menge * ep;
    final companion = AuslagenCompanion(
      id: _isEdit ? Value(widget.eintrag!.auslage.id) : const Value.absent(),
      auftragId: Value(_auftragId),
      datum: Value(_datum),
      kategorie: _nt(_kat),
      beschreibung: _nt(_beschreibung),
      menge: Value(menge),
      einheit: _nt(_einheit),
      einzelpreis: Value(ep),
      summe: Value(summe),
      notiz: _nt(_notiz),
      abgerechnet: Value(_abgerechnet),
    );
    try {
      await ref.read(auslagenRepositoryProvider).upsert(companion);
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
      title: _isEdit ? 'Auslage bearbeiten' : 'Neue Auslage',
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
              AuftragPickerField(
                auftragId: _auftragId,
                onChanged: (id) => setState(() => _auftragId = id),
              ),
              const SizedBox(height: 12),
              Row2(
                left: DateField(
                    label: 'Datum',
                    value: _datum,
                    onChanged: (v) =>
                        setState(() => _datum = v ?? DateTime.now())),
                right: LabeledField(
                    'Kategorie', TextFormField(controller: _kat)),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Beschreibung',
                TextFormField(controller: _beschreibung),
              ),
              const SizedBox(height: 12),
              Row3(
                a: LabeledField(
                  'Menge',
                  TextFormField(
                    controller: _menge,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                b: LabeledField(
                    'Einheit', TextFormField(controller: _einheit)),
                c: LabeledField(
                  'Einzelpreis (€)',
                  TextFormField(
                    controller: _einzel,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Notiz',
                TextFormField(controller: _notiz, minLines: 2, maxLines: 4),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Checkbox(
                    value: _abgerechnet,
                    onChanged: (v) =>
                        setState(() => _abgerechnet = v ?? false)),
                const Text('bereits abgerechnet'),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
