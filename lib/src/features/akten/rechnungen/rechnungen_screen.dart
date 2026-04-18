import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../features/akten/kunden/kunden_picker.dart';
import '../../../features/akten/kunden/kunden_repository.dart';
import '../../../features/system/benutzer/benutzer_repository.dart';
import '../../../features/system/einstellungen/einstellungen_repository.dart';
import '../../../shared/pdf/document_pdf.dart';
import '../../../shared/positionen/position_model.dart';
import '../../../shared/positionen/positions_editor.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'rechnungen_repository.dart';

class RechnungenScreen extends ConsumerWidget {
  const RechnungenScreen({super.key});
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');

  static const statusValues = ['offen', 'teilbezahlt', 'bezahlt', 'ueberfaellig', 'storniert'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rechnungenListProvider);
    final filter = ref.watch(rechnungenFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.request_page_outlined,
          title: 'Rechnungen',
          subtitle: 'Ausgangsrechnungen mit Positionen, USt, Zahlungsverfolgung',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neue Rechnung'),
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
                  hintText: 'Rechnungsnummer, Kunde, Aktenzeichen',
                ),
                onChanged: (v) => ref
                    .read(rechnungenFilterProvider.notifier)
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
                    .read(rechnungenFilterProvider.notifier)
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
                    icon: Icons.request_page_outlined,
                    title: 'Keine Rechnungen')
                : DataTableCard(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      columns: const [
                        DataColumn(label: Text('Nr.')),
                        DataColumn(label: Text('Datum')),
                        DataColumn(label: Text('Kunde')),
                        DataColumn(label: Text('Aktenzeichen')),
                        DataColumn(label: Text('Netto €'), numeric: true),
                        DataColumn(label: Text('Brutto €'), numeric: true),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final r in items)
                          DataRow(
                            onSelectChanged: (_) => _show(context, ref, r),
                            cells: [
                              DataCell(Text(r.rechnung.rechnungsnummer ?? '')),
                              DataCell(Text(r.rechnung.rechnungsdatum == null
                                  ? ''
                                  : _dateFmt
                                      .format(r.rechnung.rechnungsdatum!))),
                              DataCell(Text(r.kunde == null
                                  ? '—'
                                  : kundeAnzeigename(r.kunde!))),
                              DataCell(Text(r.auftrag?.aktenzeichen ?? '')),
                              DataCell(Text(
                                  r.rechnung.netto.toStringAsFixed(2))),
                              DataCell(Text(
                                  r.rechnung.brutto.toStringAsFixed(2))),
                              DataCell(Text(r.rechnung.status)),
                              DataCell(Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'PDF',
                                    icon: const Icon(
                                        Icons.picture_as_pdf_outlined,
                                        size: 20),
                                    onPressed: () =>
                                        _previewPdf(context, ref, r),
                                  ),
                                  IconButton(
                                    tooltip: 'Löschen',
                                    icon: const Icon(
                                        Icons.delete_outline,
                                        size: 20),
                                    onPressed: () async => ref
                                        .read(rechnungenRepositoryProvider)
                                        .delete(r.rechnung.id),
                                  ),
                                ],
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
      [RechnungWithKunde? r]) async {
    await showDialog(
      context: context,
      builder: (_) => _RechnungForm(eintrag: r),
    );
  }

  Future<void> _previewPdf(
      BuildContext context, WidgetRef ref, RechnungWithKunde r) async {
    final absender = await ref.read(benutzerRepositoryProvider).getActive();
    final fuss = await ref
        .read(einstellungenRepositoryProvider)
        .get(SettingsKeys.rechnungFusstext);
    await previewDocumentPdf(PdfDocumentData(
      dokumentTyp: 'Rechnung',
      dokumentNr: r.rechnung.rechnungsnummer,
      datum: r.rechnung.rechnungsdatum,
      faelligBis: r.rechnung.faelligAm,
      betreff: 'Aktenzeichen: ${r.auftrag?.aktenzeichen ?? '-'}',
      positionen: positionsFromJson(r.rechnung.positionenJson),
      kopftext: r.rechnung.kopftext,
      fusstext: r.rechnung.fusstext ?? fuss,
      absender: absender,
      empfaenger: r.kunde,
    ));
  }
}

class _RechnungForm extends ConsumerStatefulWidget {
  const _RechnungForm({this.eintrag});
  final RechnungWithKunde? eintrag;
  @override
  ConsumerState<_RechnungForm> createState() => _RechnungFormState();
}

class _RechnungFormState extends ConsumerState<_RechnungForm> {
  final _formKey = GlobalKey<FormState>();
  int? _kundeId;
  int? _auftragId;
  DateTime? _rechnungsdatum;
  DateTime? _leistungsdatum;
  DateTime? _faelligAm;
  DateTime? _bezahltAm;
  String _status = 'offen';
  late List<Position> _positionen;
  late final _nr = TextEditingController(
      text: widget.eintrag?.rechnung.rechnungsnummer ?? '');
  late final _kopf =
      TextEditingController(text: widget.eintrag?.rechnung.kopftext ?? '');
  late final _fuss =
      TextEditingController(text: widget.eintrag?.rechnung.fusstext ?? '');
  late final _bezahlt = TextEditingController(
      text: widget.eintrag?.rechnung.bezahlt.toStringAsFixed(2) ?? '0.00');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.eintrag?.rechnung;
    _kundeId = r?.kundeId;
    _auftragId = r?.auftragId;
    _rechnungsdatum = r?.rechnungsdatum ?? DateTime.now();
    _leistungsdatum = r?.leistungsdatum;
    _faelligAm = r?.faelligAm ??
        DateTime.now().add(const Duration(days: 14));
    _bezahltAm = r?.bezahltAm;
    _status = r?.status ?? 'offen';
    _positionen = positionsFromJson(r?.positionenJson);
    if (widget.eintrag == null) _prefill();
  }

  Future<void> _prefill() async {
    final repo = ref.read(rechnungenRepositoryProvider);
    final seq = await repo.nextSequenz();
    final pattern = await ref
        .read(einstellungenRepositoryProvider)
        .getOr(SettingsKeys.nummernkreisRechnung, 'YYYY-####');
    final nr = _applyPattern(pattern, seq);
    if (mounted && _nr.text.isEmpty) _nr.text = nr;
    final fuss = await ref
        .read(einstellungenRepositoryProvider)
        .get(SettingsKeys.rechnungFusstext);
    if (mounted && _fuss.text.isEmpty && fuss != null) {
      _fuss.text = fuss;
    }
  }

  String _applyPattern(String pattern, int seq) {
    final now = DateTime.now();
    var out = pattern
        .replaceAll('YYYY', '${now.year}')
        .replaceAll('MM', now.month.toString().padLeft(2, '0'));
    final m = RegExp(r'#+').firstMatch(out);
    if (m != null) {
      out = out.replaceFirst(
          m.group(0)!, seq.toString().padLeft(m.group(0)!.length, '0'));
    } else {
      out = '$out$seq';
    }
    return out;
  }

  @override
  void dispose() {
    for (final c in [_nr, _kopf, _fuss, _bezahlt]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.eintrag != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final totals = PositionsTotals.fromList(_positionen);
    final bezahlt =
        double.tryParse(_bezahlt.text.replaceAll(',', '.')) ?? 0;
    final companion = RechnungenCompanion(
      id: _isEdit ? Value(widget.eintrag!.rechnung.id) : const Value.absent(),
      rechnungsnummer: Value(_nr.text.trim()),
      kundeId: Value(_kundeId),
      auftragId: Value(_auftragId),
      rechnungsdatum: Value(_rechnungsdatum),
      leistungsdatum: Value(_leistungsdatum),
      faelligAm: Value(_faelligAm),
      bezahltAm: Value(_bezahltAm),
      status: Value(_status),
      netto: Value(totals.netto),
      ustBetrag: Value(totals.ust),
      brutto: Value(totals.brutto),
      bezahlt: Value(bezahlt),
      positionenJson: Value(positionsToJson(_positionen)),
      kopftext: _nt(_kopf),
      fusstext: _nt(_fuss),
    );
    try {
      await ref.read(rechnungenRepositoryProvider).upsert(companion);
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
          ? 'Rechnung bearbeiten · ${widget.eintrag!.rechnung.rechnungsnummer ?? ''}'
          : 'Neue Rechnung',
      saving: _saving,
      maxWidth: 1100,
      maxHeight: 840,
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
                  TextFormField(
                    controller: _nr,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Erforderlich' : null,
                  ),
                ),
                right: LabeledField(
                  'Status',
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    isDense: true,
                    items: [
                      for (final s in RechnungenScreen.statusValues)
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) => setState(() => _status = v ?? 'offen'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row2(
                left: KundenPickerField(
                  kundeId: _kundeId,
                  onChanged: (id) => setState(() => _kundeId = id),
                ),
                right: AuftragPickerField(
                  auftragId: _auftragId,
                  onChanged: (id) => setState(() => _auftragId = id),
                ),
              ),
              const SizedBox(height: 12),
              Row3(
                a: DateField(
                  label: 'Rechnungsdatum',
                  value: _rechnungsdatum,
                  onChanged: (v) => setState(() => _rechnungsdatum = v),
                ),
                b: DateField(
                  label: 'Leistungsdatum',
                  value: _leistungsdatum,
                  onChanged: (v) => setState(() => _leistungsdatum = v),
                ),
                c: DateField(
                  label: 'Fällig am',
                  value: _faelligAm,
                  onChanged: (v) => setState(() => _faelligAm = v),
                ),
              ),
              const SizedBox(height: 12),
              Row2(
                left: DateField(
                  label: 'Bezahlt am',
                  value: _bezahltAm,
                  onChanged: (v) => setState(() => _bezahltAm = v),
                ),
                right: LabeledField(
                  'Bereits bezahlt (€)',
                  TextFormField(
                    controller: _bezahlt,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              PositionsEditor(
                positions: _positionen,
                onChanged: (list) => setState(() => _positionen = list),
              ),
              const SizedBox(height: 20),
              LabeledField(
                'Kopftext',
                TextFormField(
                    controller: _kopf, minLines: 2, maxLines: 4),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Fußtext',
                TextFormField(
                    controller: _fuss, minLines: 2, maxLines: 5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
