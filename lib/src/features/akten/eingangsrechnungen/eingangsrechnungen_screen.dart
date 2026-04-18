import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'eingangsrechnungen_repository.dart';

class EingangsrechnungenScreen extends ConsumerWidget {
  const EingangsrechnungenScreen({super.key});
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');

  static const statusValues = ['offen', 'teilbezahlt', 'bezahlt'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(eingangsrechnungenListProvider);
    final filter = ref.watch(eingangsrechnungenFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.receipt_long_outlined,
          title: 'Eingangsrechnungen',
          subtitle: 'Lieferantenrechnungen, Kategorien, Fälligkeiten',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neue Eingangsrechnung'),
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
                  hintText: 'Rechnungsnummer, Kategorie, Beschreibung',
                ),
                onChanged: (v) => ref
                    .read(eingangsrechnungenFilterProvider.notifier)
                    .update((f) => f.copyWith(query: v)),
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: filter.status,
                hint: const Text('Alle Status'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Alle Status')),
                  for (final s in statusValues)
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: (v) => ref
                    .read(eingangsrechnungenFilterProvider.notifier)
                    .update((f) => v == null
                        ? f.copyWith(clearStatus: true)
                        : f.copyWith(status: v)),
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
                    icon: Icons.receipt_long_outlined,
                    title: 'Keine Eingangsrechnungen')
                : DataTableCard(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      columns: const [
                        DataColumn(label: Text('Rechnungs-Nr.')),
                        DataColumn(label: Text('Datum')),
                        DataColumn(label: Text('Beschreibung')),
                        DataColumn(label: Text('Kategorie')),
                        DataColumn(label: Text('Auftrag')),
                        DataColumn(label: Text('Brutto €'), numeric: true),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final e in items)
                          DataRow(
                            onSelectChanged: (_) => _show(context, ref, e),
                            cells: [
                              DataCell(Text(e.rechnung.rechnungsnummer ?? '')),
                              DataCell(Text(e.rechnung.rechnungsdatum == null
                                  ? ''
                                  : _dateFmt.format(e.rechnung.rechnungsdatum!))),
                              DataCell(Text(e.rechnung.beschreibung ?? '')),
                              DataCell(Text(e.rechnung.kategorie ?? '')),
                              DataCell(
                                  Text(e.auftrag?.aktenzeichen ?? '')),
                              DataCell(Text(
                                  e.rechnung.brutto.toStringAsFixed(2))),
                              DataCell(Text(e.rechnung.status)),
                              DataCell(IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                onPressed: () async => ref
                                    .read(
                                        eingangsrechnungenRepositoryProvider)
                                    .delete(e.rechnung.id),
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
      [EingangsrechnungWithAuftrag? e]) async {
    await showDialog(
      context: context,
      builder: (_) => _EingangsrechnungForm(eintrag: e),
    );
  }
}

class _EingangsrechnungForm extends ConsumerStatefulWidget {
  const _EingangsrechnungForm({this.eintrag});
  final EingangsrechnungWithAuftrag? eintrag;
  @override
  ConsumerState<_EingangsrechnungForm> createState() =>
      _EingangsrechnungFormState();
}

class _EingangsrechnungFormState
    extends ConsumerState<_EingangsrechnungForm> {
  final _formKey = GlobalKey<FormState>();

  int? _auftragId;
  DateTime? _rechnungsdatum;
  DateTime? _eingangAm;
  DateTime? _faelligAm;
  DateTime? _bezahltAm;
  String _status = 'offen';

  late final _nr = _tec(widget.eintrag?.rechnung.rechnungsnummer);
  late final _beschreibung = _tec(widget.eintrag?.rechnung.beschreibung);
  late final _kategorie = _tec(widget.eintrag?.rechnung.kategorie);
  late final _netto =
      _tec(widget.eintrag?.rechnung.netto.toStringAsFixed(2));
  late final _ustSatz =
      _tec(widget.eintrag?.rechnung.ustSatz.toStringAsFixed(0) ?? '19');
  late final _brutto =
      _tec(widget.eintrag?.rechnung.brutto.toStringAsFixed(2));
  late final _belegPfad = _tec(widget.eintrag?.rechnung.belegPfad);
  late final _notiz = _tec(widget.eintrag?.rechnung.notiz);

  bool _saving = false;

  TextEditingController _tec(String? v) =>
      TextEditingController(text: v ?? '');

  @override
  void initState() {
    super.initState();
    final r = widget.eintrag?.rechnung;
    _auftragId = r?.auftragId;
    _rechnungsdatum = r?.rechnungsdatum;
    _eingangAm = r?.eingangAm;
    _faelligAm = r?.faelligAm;
    _bezahltAm = r?.bezahltAm;
    _status = r?.status ?? 'offen';
  }

  @override
  void dispose() {
    for (final c in [
      _nr, _beschreibung, _kategorie, _netto, _ustSatz, _brutto,
      _belegPfad, _notiz
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.eintrag != null;

  void _recalcBrutto() {
    final n = double.tryParse(_netto.text.replaceAll(',', '.'));
    final u = double.tryParse(_ustSatz.text.replaceAll(',', '.')) ?? 19;
    if (n == null) return;
    final brutto = n * (1 + u / 100.0);
    _brutto.text = brutto.toStringAsFixed(2);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final netto = double.tryParse(_netto.text.replaceAll(',', '.')) ?? 0;
    final ust = double.tryParse(_ustSatz.text.replaceAll(',', '.')) ?? 19;
    final brutto =
        double.tryParse(_brutto.text.replaceAll(',', '.')) ?? (netto * (1 + ust / 100));
    final ustBetrag = brutto - netto;
    final companion = EingangsrechnungenCompanion(
      id: _isEdit
          ? Value(widget.eintrag!.rechnung.id)
          : const Value.absent(),
      rechnungsnummer: _nt(_nr),
      auftragId: Value(_auftragId),
      rechnungsdatum: Value(_rechnungsdatum),
      eingangAm: Value(_eingangAm),
      faelligAm: Value(_faelligAm),
      bezahltAm: Value(_bezahltAm),
      status: Value(_status),
      kategorie: _nt(_kategorie),
      beschreibung: _nt(_beschreibung),
      netto: Value(netto),
      ustSatz: Value(ust),
      ustBetrag: Value(ustBetrag),
      brutto: Value(brutto),
      belegPfad: _nt(_belegPfad),
      notiz: _nt(_notiz),
    );
    try {
      await ref
          .read(eingangsrechnungenRepositoryProvider)
          .upsert(companion);
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
      title: _isEdit
          ? 'Eingangsrechnung bearbeiten'
          : 'Neue Eingangsrechnung',
      saving: _saving,
      maxWidth: 840,
      maxHeight: 760,
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
                left: LabeledField(
                  'Rechnungsnummer',
                  TextFormField(controller: _nr),
                ),
                right: LabeledField(
                  'Status',
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    isDense: true,
                    items: [
                      for (final s in ['offen', 'teilbezahlt', 'bezahlt'])
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) => setState(() => _status = v ?? 'offen'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AuftragPickerField(
                auftragId: _auftragId,
                onChanged: (id) => setState(() => _auftragId = id),
                label: 'Auftrag (optional)',
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Beschreibung',
                TextFormField(controller: _beschreibung),
              ),
              const SizedBox(height: 12),
              LabeledField(
                  'Kategorie', TextFormField(controller: _kategorie)),
              const SizedBox(height: 16),
              Text('Daten',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row2(
                left: DateField(
                  label: 'Rechnungsdatum',
                  value: _rechnungsdatum,
                  onChanged: (v) => setState(() => _rechnungsdatum = v),
                ),
                right: DateField(
                  label: 'Eingang',
                  value: _eingangAm,
                  onChanged: (v) => setState(() => _eingangAm = v),
                ),
              ),
              const SizedBox(height: 12),
              Row2(
                left: DateField(
                  label: 'Fällig am',
                  value: _faelligAm,
                  onChanged: (v) => setState(() => _faelligAm = v),
                ),
                right: DateField(
                  label: 'Bezahlt am',
                  value: _bezahltAm,
                  onChanged: (v) => setState(() => _bezahltAm = v),
                ),
              ),
              const SizedBox(height: 16),
              Text('Beträge',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row3(
                a: LabeledField(
                  'Netto (€)',
                  TextFormField(
                    controller: _netto,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _recalcBrutto(),
                  ),
                ),
                b: LabeledField(
                  'USt (%)',
                  TextFormField(
                    controller: _ustSatz,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _recalcBrutto(),
                  ),
                ),
                c: LabeledField(
                  'Brutto (€)',
                  TextFormField(
                    controller: _brutto,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                  'Beleg-Pfad', TextFormField(controller: _belegPfad)),
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
