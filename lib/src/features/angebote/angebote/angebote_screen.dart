import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
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
import 'angebote_repository.dart';

class AngeboteScreen extends ConsumerWidget {
  const AngeboteScreen({super.key});
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');

  static const statusValues = ['entwurf', 'versendet', 'angenommen', 'abgelehnt', 'abgelaufen'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(angeboteListProvider);
    final filter = ref.watch(angeboteFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.price_change_outlined,
          title: 'Angebote',
          subtitle: 'Angebotserstellung mit Positionen und Gültigkeit',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neues Angebot'),
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
                  hintText: 'Angebotsnummer, Kunde, Betreff',
                ),
                onChanged: (v) => ref
                    .read(angeboteFilterProvider.notifier)
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
                    .read(angeboteFilterProvider.notifier)
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
                    icon: Icons.price_change_outlined,
                    title: 'Keine Angebote')
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
                        DataColumn(label: Text('Betreff')),
                        DataColumn(label: Text('Gültig bis')),
                        DataColumn(label: Text('Netto €'), numeric: true),
                        DataColumn(label: Text('Brutto €'), numeric: true),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final a in items)
                          DataRow(
                            onSelectChanged: (_) => _show(context, ref, a),
                            cells: [
                              DataCell(Text(a.angebot.angebotsnummer ?? '')),
                              DataCell(Text(_dateFmt.format(a.angebot.datum))),
                              DataCell(Text(a.kunde == null
                                  ? '—'
                                  : kundeAnzeigename(a.kunde!))),
                              DataCell(Text(a.angebot.betreff ?? '')),
                              DataCell(Text(a.angebot.gueltigBis == null
                                  ? ''
                                  : _dateFmt.format(a.angebot.gueltigBis!))),
                              DataCell(Text(
                                  a.angebot.netto.toStringAsFixed(2))),
                              DataCell(Text(
                                  a.angebot.brutto.toStringAsFixed(2))),
                              DataCell(Text(a.angebot.status)),
                              DataCell(Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'PDF',
                                    icon: const Icon(
                                        Icons.picture_as_pdf_outlined,
                                        size: 20),
                                    onPressed: () =>
                                        _previewPdf(context, ref, a),
                                  ),
                                  IconButton(
                                    tooltip: 'Löschen',
                                    icon: const Icon(
                                        Icons.delete_outline,
                                        size: 20),
                                    onPressed: () async => ref
                                        .read(angeboteRepositoryProvider)
                                        .delete(a.angebot.id),
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
      [AngebotWithKunde? a]) async {
    await showDialog(
      context: context,
      builder: (_) => _AngebotForm(eintrag: a),
    );
  }

  Future<void> _previewPdf(
      BuildContext context, WidgetRef ref, AngebotWithKunde a) async {
    final absender = await ref.read(benutzerRepositoryProvider).getActive();
    final fuss = await ref
        .read(einstellungenRepositoryProvider)
        .get(SettingsKeys.angebotFusstext);
    await previewDocumentPdf(PdfDocumentData(
      dokumentTyp: 'Angebot',
      dokumentNr: a.angebot.angebotsnummer,
      datum: a.angebot.datum,
      faelligBis: a.angebot.gueltigBis,
      betreff: a.angebot.betreff,
      positionen: positionsFromJson(a.angebot.positionenJson),
      kopftext: a.angebot.kopftext,
      fusstext: a.angebot.fusstext ?? fuss,
      absender: absender,
      empfaenger: a.kunde,
    ));
  }
}

class _AngebotForm extends ConsumerStatefulWidget {
  const _AngebotForm({this.eintrag});
  final AngebotWithKunde? eintrag;
  @override
  ConsumerState<_AngebotForm> createState() => _AngebotFormState();
}

class _AngebotFormState extends ConsumerState<_AngebotForm> {
  final _formKey = GlobalKey<FormState>();
  int? _kundeId;
  DateTime _datum = DateTime.now();
  DateTime? _gueltigBis;
  String _status = 'entwurf';
  late List<Position> _positionen;
  late final _nr = TextEditingController(
      text: widget.eintrag?.angebot.angebotsnummer ?? '');
  late final _betreff = TextEditingController(
      text: widget.eintrag?.angebot.betreff ?? '');
  late final _kopf = TextEditingController(
      text: widget.eintrag?.angebot.kopftext ?? '');
  late final _fuss = TextEditingController(
      text: widget.eintrag?.angebot.fusstext ?? '');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.eintrag?.angebot;
    _kundeId = a?.kundeId;
    _datum = a?.datum ?? DateTime.now();
    _gueltigBis =
        a?.gueltigBis ?? DateTime.now().add(const Duration(days: 30));
    _status = a?.status ?? 'entwurf';
    _positionen = positionsFromJson(a?.positionenJson);
    if (widget.eintrag == null) _prefill();
  }

  Future<void> _prefill() async {
    final seq =
        await ref.read(angeboteRepositoryProvider).nextSequenz();
    final pattern = await ref
        .read(einstellungenRepositoryProvider)
        .getOr(SettingsKeys.nummernkreisAngebot, 'A-YYYY-####');
    final nr = _applyPattern(pattern, seq);
    if (mounted && _nr.text.isEmpty) _nr.text = nr;
    final fuss = await ref
        .read(einstellungenRepositoryProvider)
        .get(SettingsKeys.angebotFusstext);
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
    for (final c in [_nr, _betreff, _kopf, _fuss]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.eintrag != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final totals = PositionsTotals.fromList(_positionen);
    final companion = AngeboteCompanion(
      id: _isEdit ? Value(widget.eintrag!.angebot.id) : const Value.absent(),
      angebotsnummer: Value(_nr.text.trim()),
      kundeId: Value(_kundeId),
      betreff: _nt(_betreff),
      datum: Value(_datum),
      gueltigBis: Value(_gueltigBis),
      status: Value(_status),
      netto: Value(totals.netto),
      ustBetrag: Value(totals.ust),
      brutto: Value(totals.brutto),
      positionenJson: Value(positionsToJson(_positionen)),
      kopftext: _nt(_kopf),
      fusstext: _nt(_fuss),
    );
    try {
      await ref.read(angeboteRepositoryProvider).upsert(companion);
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
          ? 'Angebot bearbeiten · ${widget.eintrag!.angebot.angebotsnummer ?? ''}'
          : 'Neues Angebot',
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
                  'Angebotsnummer',
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
                      for (final s in AngeboteScreen.statusValues)
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) =>
                        setState(() => _status = v ?? 'entwurf'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              KundenPickerField(
                kundeId: _kundeId,
                onChanged: (id) => setState(() => _kundeId = id),
              ),
              const SizedBox(height: 12),
              LabeledField(
                  'Betreff', TextFormField(controller: _betreff)),
              const SizedBox(height: 12),
              Row2(
                left: DateField(
                    label: 'Datum',
                    value: _datum,
                    onChanged: (v) =>
                        setState(() => _datum = v ?? DateTime.now())),
                right: DateField(
                    label: 'Gültig bis',
                    value: _gueltigBis,
                    onChanged: (v) => setState(() => _gueltigBis = v)),
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
