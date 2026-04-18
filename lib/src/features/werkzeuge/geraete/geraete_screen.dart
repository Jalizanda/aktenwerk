import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'geraete_repository.dart';

class GeraeteScreen extends ConsumerWidget {
  const GeraeteScreen({super.key});
  static final _fmt = DateFormat('dd.MM.yyyy', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(geraeteListProvider);
    final filter = ref.watch(geraeteFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.speed_outlined,
          title: 'Messgeräte',
          subtitle: 'Inventar mit Kalibrier-Verfolgung',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neues Gerät'),
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
                  hintText: 'Bezeichnung, Hersteller, Seriennummer',
                ),
                onChanged: (v) => ref
                    .read(geraeteFilterProvider.notifier)
                    .update((f) => f.copyWith(query: v)),
              ),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(
                value: filter.nurAktiv,
                onChanged: (v) => ref
                    .read(geraeteFilterProvider.notifier)
                    .update((f) => f.copyWith(nurAktiv: v ?? true)),
              ),
              const Text('Nur aktive'),
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
                    icon: Icons.speed_outlined,
                    title: 'Noch keine Messgeräte')
                : DataTableCard(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      columns: const [
                        DataColumn(label: Text('Bezeichnung')),
                        DataColumn(label: Text('Hersteller')),
                        DataColumn(label: Text('Seriennummer')),
                        DataColumn(label: Text('Nächste Kalibrierung')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final g in items)
                          DataRow(
                            onSelectChanged: (_) => _show(context, ref, g),
                            cells: [
                              DataCell(Text(g.bezeichnung)),
                              DataCell(Text(g.hersteller ?? '')),
                              DataCell(Text(g.seriennummer ?? '')),
                              DataCell(_kalibrierCell(context, g)),
                              DataCell(IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                onPressed: () =>
                                    _confirm(context, ref, g),
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

  Widget _kalibrierCell(BuildContext context, GeraeteData g) {
    final d = g.naechsteKalibrierung;
    if (d == null) return const Text('');
    final now = DateTime.now();
    final faellig = d.isBefore(now);
    final bald = d.isBefore(now.add(const Duration(days: 60)));
    final color = faellig
        ? Theme.of(context).colorScheme.error
        : bald
            ? Theme.of(context).colorScheme.tertiary
            : null;
    return Text(
      _fmt.format(d),
      style: TextStyle(
          color: color,
          fontWeight: faellig || bald ? FontWeight.w600 : null),
    );
  }

  Future<void> _show(BuildContext context, WidgetRef ref,
      [GeraeteData? g]) async {
    await showDialog(
      context: context,
      builder: (_) => _GeraetForm(geraet: g),
    );
  }

  Future<void> _confirm(
      BuildContext context, WidgetRef ref, GeraeteData g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Gerät löschen?'),
        content: Text('«${g.bezeichnung}» wird gelöscht.'),
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
    if (ok == true) await ref.read(geraeteRepositoryProvider).delete(g.id);
  }
}

class _GeraetForm extends ConsumerStatefulWidget {
  const _GeraetForm({this.geraet});
  final GeraeteData? geraet;
  @override
  ConsumerState<_GeraetForm> createState() => _GeraetFormState();
}

class _GeraetFormState extends ConsumerState<_GeraetForm> {
  final _formKey = GlobalKey<FormState>();
  late final _bez = _tec(widget.geraet?.bezeichnung);
  late final _hersteller = _tec(widget.geraet?.hersteller);
  late final _modell = _tec(widget.geraet?.modell);
  late final _seriennr = _tec(widget.geraet?.seriennummer);
  late final _messbereich = _tec(widget.geraet?.messbereich);
  late final _genauigkeit = _tec(widget.geraet?.genauigkeit);
  late final _standort = _tec(widget.geraet?.standort);
  late final _notiz = _tec(widget.geraet?.notiz);
  DateTime? _angeschafft;
  DateTime? _kalibriertAm;
  DateTime? _naechsteKalibrierung;
  bool _aktiv = true;
  bool _saving = false;

  TextEditingController _tec(String? v) =>
      TextEditingController(text: v ?? '');

  @override
  void initState() {
    super.initState();
    _angeschafft = widget.geraet?.angeschafftAm;
    _kalibriertAm = widget.geraet?.kalibriertAm;
    _naechsteKalibrierung = widget.geraet?.naechsteKalibrierung;
    _aktiv = widget.geraet?.aktiv ?? true;
  }

  @override
  void dispose() {
    for (final c in [
      _bez, _hersteller, _modell, _seriennr, _messbereich,
      _genauigkeit, _standort, _notiz,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.geraet != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final companion = GeraeteCompanion(
      id: _isEdit ? Value(widget.geraet!.id) : const Value.absent(),
      bezeichnung: Value(_bez.text.trim()),
      hersteller: _nt(_hersteller),
      modell: _nt(_modell),
      seriennummer: _nt(_seriennr),
      angeschafftAm: Value(_angeschafft),
      kalibriertAm: Value(_kalibriertAm),
      naechsteKalibrierung: Value(_naechsteKalibrierung),
      messbereich: _nt(_messbereich),
      genauigkeit: _nt(_genauigkeit),
      standort: _nt(_standort),
      aktiv: Value(_aktiv),
      notiz: _nt(_notiz),
    );
    try {
      await ref.read(geraeteRepositoryProvider).upsert(companion);
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
      title: _isEdit ? 'Gerät bearbeiten' : 'Neues Gerät',
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
                'Bezeichnung',
                TextFormField(
                  controller: _bez,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Erforderlich' : null,
                ),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                    'Hersteller', TextFormField(controller: _hersteller)),
                right: LabeledField(
                    'Modell', TextFormField(controller: _modell)),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                    'Seriennummer', TextFormField(controller: _seriennr)),
                right: LabeledField(
                    'Standort', TextFormField(controller: _standort)),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                    'Messbereich', TextFormField(controller: _messbereich)),
                right: LabeledField('Genauigkeit',
                    TextFormField(controller: _genauigkeit)),
              ),
              const SizedBox(height: 12),
              Row3(
                a: DateField(
                  label: 'Angeschafft am',
                  value: _angeschafft,
                  onChanged: (v) => setState(() => _angeschafft = v),
                ),
                b: DateField(
                  label: 'Kalibriert am',
                  value: _kalibriertAm,
                  onChanged: (v) => setState(() => _kalibriertAm = v),
                ),
                c: DateField(
                  label: 'Nächste Kalibrierung',
                  value: _naechsteKalibrierung,
                  onChanged: (v) =>
                      setState(() => _naechsteKalibrierung = v),
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Notiz',
                TextFormField(
                    controller: _notiz, minLines: 2, maxLines: 5),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Checkbox(
                    value: _aktiv,
                    onChanged: (v) => setState(() => _aktiv = v ?? true)),
                const Text('Aktiv / im Einsatz'),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
