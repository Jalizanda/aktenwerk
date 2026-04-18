import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'fortbildungen_repository.dart';

class FortbildungenScreen extends ConsumerWidget {
  const FortbildungenScreen({super.key});
  static final _fmt = DateFormat('dd.MM.yyyy', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(fortbildungenListProvider);
    final summen = ref.watch(fortbildungenSummenProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.school_outlined,
          title: 'Fortbildungen',
          subtitle: 'Nachweise für die Wiederbestellung',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neue Fortbildung'),
              onPressed: () => _show(context, ref),
            ),
          ],
        ),
        const Divider(height: 1),
        summen.when(
          data: (s) => _SummenRow(summen: s),
          loading: () => const SizedBox(),
          error: (_, _) => const SizedBox(),
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) => items.isEmpty
                ? const EmptyListState(
                    icon: Icons.school_outlined,
                    title: 'Keine Fortbildungen erfasst')
                : DataTableCard(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      columns: const [
                        DataColumn(label: Text('Titel')),
                        DataColumn(label: Text('Veranstalter')),
                        DataColumn(label: Text('Von')),
                        DataColumn(label: Text('Bis')),
                        DataColumn(label: Text('Stunden'), numeric: true),
                        DataColumn(label: Text('Kosten €'), numeric: true),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final f in items)
                          DataRow(
                            onSelectChanged: (_) => _show(context, ref, f),
                            cells: [
                              DataCell(Text(f.titel)),
                              DataCell(Text(f.veranstalter ?? '')),
                              DataCell(Text(f.datumVon == null
                                  ? ''
                                  : _fmt.format(f.datumVon!))),
                              DataCell(Text(f.datumBis == null
                                  ? ''
                                  : _fmt.format(f.datumBis!))),
                              DataCell(
                                  Text(f.stunden.toStringAsFixed(1))),
                              DataCell(Text(f.kosten.toStringAsFixed(2))),
                              DataCell(IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                onPressed: () =>
                                    _confirm(context, ref, f),
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
      [FortbildungenData? f]) async {
    await showDialog(
        context: context, builder: (_) => _FortbildungForm(fortbildung: f));
  }

  Future<void> _confirm(
      BuildContext context, WidgetRef ref, FortbildungenData f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Fortbildung löschen?'),
        content: Text('«${f.titel}» wird gelöscht.'),
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
      await ref.read(fortbildungenRepositoryProvider).delete(f.id);
    }
  }
}

class _SummenRow extends StatelessWidget {
  const _SummenRow({required this.summen});
  final Map<int, double> summen;
  @override
  Widget build(BuildContext context) {
    if (summen.isEmpty) return const SizedBox();
    final jahre = summen.keys.toList()..sort((a, b) => b.compareTo(a));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final j in jahre.take(4))
            Chip(
              label: Text('$j: ${summen[j]!.toStringAsFixed(1)} Std'),
              backgroundColor:
                  Theme.of(context).colorScheme.secondaryContainer,
            ),
        ],
      ),
    );
  }
}

class _FortbildungForm extends ConsumerStatefulWidget {
  const _FortbildungForm({this.fortbildung});
  final FortbildungenData? fortbildung;
  @override
  ConsumerState<_FortbildungForm> createState() => _FortbildungFormState();
}

class _FortbildungFormState extends ConsumerState<_FortbildungForm> {
  final _formKey = GlobalKey<FormState>();
  late final _titel =
      TextEditingController(text: widget.fortbildung?.titel ?? '');
  late final _veranstalter =
      TextEditingController(text: widget.fortbildung?.veranstalter ?? '');
  late final _ort =
      TextEditingController(text: widget.fortbildung?.ort ?? '');
  late final _thema =
      TextEditingController(text: widget.fortbildung?.thema ?? '');
  late final _stunden = TextEditingController(
      text: widget.fortbildung?.stunden.toStringAsFixed(1) ?? '');
  late final _kosten = TextEditingController(
      text: widget.fortbildung?.kosten.toStringAsFixed(2) ?? '');
  late final _notiz =
      TextEditingController(text: widget.fortbildung?.notiz ?? '');
  DateTime? _von;
  DateTime? _bis;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _von = widget.fortbildung?.datumVon;
    _bis = widget.fortbildung?.datumBis;
  }

  @override
  void dispose() {
    for (final c in [
      _titel, _veranstalter, _ort, _thema, _stunden, _kosten, _notiz,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.fortbildung != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final stunden =
        double.tryParse(_stunden.text.replaceAll(',', '.')) ?? 0;
    final kosten =
        double.tryParse(_kosten.text.replaceAll(',', '.')) ?? 0;
    final companion = FortbildungenCompanion(
      id: _isEdit ? Value(widget.fortbildung!.id) : const Value.absent(),
      titel: Value(_titel.text.trim()),
      veranstalter: _nt(_veranstalter),
      ort: _nt(_ort),
      thema: _nt(_thema),
      datumVon: Value(_von),
      datumBis: Value(_bis),
      stunden: Value(stunden),
      kosten: Value(kosten),
      notiz: _nt(_notiz),
    );
    try {
      await ref.read(fortbildungenRepositoryProvider).upsert(companion);
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
      title:
          _isEdit ? 'Fortbildung bearbeiten' : 'Neue Fortbildung',
      saving: _saving,
      maxHeight: 640,
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
                'Titel',
                TextFormField(
                  controller: _titel,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Erforderlich' : null,
                ),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                    'Veranstalter',
                    TextFormField(controller: _veranstalter)),
                right:
                    LabeledField('Ort', TextFormField(controller: _ort)),
              ),
              const SizedBox(height: 12),
              LabeledField(
                  'Thema / Fachgebiet', TextFormField(controller: _thema)),
              const SizedBox(height: 12),
              Row2(
                left: DateField(
                    label: 'Von',
                    value: _von,
                    onChanged: (v) => setState(() => _von = v)),
                right: DateField(
                    label: 'Bis',
                    value: _bis,
                    onChanged: (v) => setState(() => _bis = v)),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                  'Stunden',
                  TextFormField(
                      controller: _stunden,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true)),
                ),
                right: LabeledField(
                  'Kosten (€)',
                  TextFormField(
                      controller: _kosten,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true)),
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                  'Notiz',
                  TextFormField(
                      controller: _notiz, minLines: 2, maxLines: 4)),
            ],
          ),
        ),
      ),
    );
  }
}
