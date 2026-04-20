import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../shared/widgets/file_upload_section.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'partner_repository.dart';

class PartnerScreen extends ConsumerWidget {
  const PartnerScreen({super.key});

  static final _money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(partnerListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.groups_outlined,
          title: 'Partner / Subunternehmer',
          subtitle:
              'Externe Fachkräfte für Statik, Labor, Thermografie usw.',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neuer Partner'),
              onPressed: () => _show(context, ref),
            ),
          ],
          searchHint: 'Suche Firma, Fachgebiet, Ort …',
          onSearchChanged: (v) =>
              ref.read(partnerQueryProvider.notifier).state = v,
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) => items.isEmpty
                ? const EmptyListState(
                    icon: Icons.groups_outlined,
                    title: 'Noch keine Partner angelegt.',
                    hint:
                        'Lege oben rechts einen Partner an (Statik-SV, Labor, Thermografie …).')
                : DataTableCard(
                    child: DataTable(
                      showCheckboxColumn: false,
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      columns: const [
                        DataColumn(label: Text('Firma')),
                        DataColumn(label: Text('Fachgebiet')),
                        DataColumn(label: Text('Ansprechpartner')),
                        DataColumn(label: Text('Ort')),
                        DataColumn(label: Text('Stundensatz'), numeric: true),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final p in items)
                          DataRow(
                            onSelectChanged: (_) =>
                                _show(context, ref, p),
                            cells: [
                              DataCell(Text(p.firma,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600))),
                              DataCell(Text(p.fachgebiet ?? '—')),
                              DataCell(
                                  Text(p.ansprechpartner ?? '')),
                              DataCell(Text(
                                  [p.plz, p.ort]
                                      .whereType<String>()
                                      .where((s) => s.isNotEmpty)
                                      .join(' '))),
                              DataCell(Text(
                                  p.stundensatz == 0
                                      ? ''
                                      : _money.format(p.stundensatz))),
                              DataCell(IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18),
                                onPressed: () => ref
                                    .read(partnerRepositoryProvider)
                                    .delete(p.id),
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
      [PartnerData? p]) async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => _PartnerForm(partner: p),
    );
  }
}

class _PartnerForm extends ConsumerStatefulWidget {
  const _PartnerForm({this.partner});
  final PartnerData? partner;
  @override
  ConsumerState<_PartnerForm> createState() => _PartnerFormState();
}

class _PartnerFormState extends ConsumerState<_PartnerForm> {
  final _formKey = GlobalKey<FormState>();
  late final _firma = _tec(widget.partner?.firma);
  late final _ansprech = _tec(widget.partner?.ansprechpartner);
  late final _fachgebiet = _tec(widget.partner?.fachgebiet);
  late final _qualifikationen = _tec(widget.partner?.qualifikationen);
  late final _stundensatz =
      _tec(widget.partner?.stundensatz.toStringAsFixed(2));
  late final _strasse = _tec(widget.partner?.strasse);
  late final _plz = _tec(widget.partner?.plz);
  late final _ort = _tec(widget.partner?.ort);
  late final _telefon = _tec(widget.partner?.telefon);
  late final _email = _tec(widget.partner?.email);
  late final _website = _tec(widget.partner?.website);
  late final _ustId = _tec(widget.partner?.ustId);
  late final _steuerNr = _tec(widget.partner?.steuerNr);
  late final _bankInhaber = _tec(widget.partner?.bankInhaber);
  late final _bankName = _tec(widget.partner?.bankName);
  late final _iban = _tec(widget.partner?.iban);
  late final _bic = _tec(widget.partner?.bic);
  late final _notiz = _tec(widget.partner?.notiz);
  UploadedFile? _rahmenvertrag;
  bool _aktiv = true;
  bool _saving = false;

  TextEditingController _tec(String? v) =>
      TextEditingController(text: v ?? '');

  @override
  void initState() {
    super.initState();
    _aktiv = widget.partner?.aktiv ?? true;
    final p = widget.partner;
    if (p?.rahmenvertragStorageUrl != null &&
        p!.rahmenvertragStorageUrl!.isNotEmpty) {
      _rahmenvertrag = UploadedFile(
        storageUrl: p.rahmenvertragStorageUrl!,
        dateiname: p.rahmenvertragDateiname ?? 'Rahmenvertrag',
        mimeType: p.rahmenvertragMimeType,
        groesse: p.rahmenvertragGroesse,
      );
    }
  }

  @override
  void dispose() {
    for (final c in [
      _firma, _ansprech, _fachgebiet, _qualifikationen, _stundensatz,
      _strasse, _plz, _ort, _telefon, _email, _website, _ustId, _steuerNr,
      _bankInhaber, _bankName, _iban, _bic, _notiz,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.partner != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(partnerRepositoryProvider).upsert(
            PartnerCompanion(
              id: _isEdit
                  ? Value(widget.partner!.id)
                  : const Value.absent(),
              firma: Value(_firma.text.trim()),
              ansprechpartner: _nt(_ansprech),
              fachgebiet: _nt(_fachgebiet),
              qualifikationen: _nt(_qualifikationen),
              stundensatz: Value(
                  double.tryParse(
                          _stundensatz.text.replaceAll(',', '.')) ??
                      0),
              strasse: _nt(_strasse),
              plz: _nt(_plz),
              ort: _nt(_ort),
              telefon: _nt(_telefon),
              email: _nt(_email),
              website: _nt(_website),
              ustId: _nt(_ustId),
              steuerNr: _nt(_steuerNr),
              bankInhaber: _nt(_bankInhaber),
              bankName: _nt(_bankName),
              iban: _nt(_iban),
              bic: _nt(_bic),
              rahmenvertragStorageUrl:
                  Value(_rahmenvertrag?.storageUrl),
              rahmenvertragDateiname: Value(_rahmenvertrag?.dateiname),
              rahmenvertragMimeType: Value(_rahmenvertrag?.mimeType),
              rahmenvertragGroesse: Value(_rahmenvertrag?.groesse),
              aktiv: Value(_aktiv),
              notiz: _nt(_notiz),
            ),
          );
      if (mounted) Navigator.of(context, rootNavigator: true).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Value<String?> _nt(TextEditingController c) {
    final v = c.text.trim();
    return Value(v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    return StandardFormDialog(
      title: _isEdit ? 'Partner bearbeiten' : 'Neuer Partner',
      icon: Icons.groups_outlined,
      maxWidth: 760,
      maxHeight: 760,
      saving: _saving,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(partnerRepositoryProvider)
              .delete(widget.partner!.id)
          : null,
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row2(
                flex: const (2, 1),
                left: LabeledField(
                  'Firma',
                  TextFormField(
                    controller: _firma,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Erforderlich'
                        : null,
                  ),
                ),
                right: LabeledField('Ansprechpartner',
                    TextFormField(controller: _ansprech)),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                  'Fachgebiet',
                  TextFormField(
                    controller: _fachgebiet,
                    decoration: const InputDecoration(
                      hintText: 'z. B. Statik, Schadstoff, Thermografie',
                    ),
                  ),
                ),
                right: LabeledField(
                  'Stundensatz (€)',
                  TextFormField(
                    controller: _stundensatz,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Qualifikationen / Zertifikate',
                TextFormField(
                    controller: _qualifikationen,
                    minLines: 2,
                    maxLines: 5),
              ),
              const SizedBox(height: 16),
              Text('Adresse',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Row2(
                flex: const (2, 1),
                left: LabeledField(
                    'Straße', TextFormField(controller: _strasse)),
                right: LabeledField(
                    'PLZ', TextFormField(controller: _plz)),
              ),
              const SizedBox(height: 12),
              LabeledField('Ort', TextFormField(controller: _ort)),
              const SizedBox(height: 12),
              Row3(
                a: LabeledField('Telefon',
                    TextFormField(controller: _telefon)),
                b: LabeledField('E-Mail',
                    TextFormField(controller: _email)),
                c: LabeledField('Website',
                    TextFormField(controller: _website)),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField('USt-IdNr.',
                    TextFormField(controller: _ustId)),
                right: LabeledField('Steuer-Nr.',
                    TextFormField(controller: _steuerNr)),
              ),
              const SizedBox(height: 16),
              Text('Bankverbindung',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Row2(
                left: LabeledField('Kontoinhaber',
                    TextFormField(controller: _bankInhaber)),
                right: LabeledField('Bank',
                    TextFormField(controller: _bankName)),
              ),
              const SizedBox(height: 12),
              Row2(
                flex: const (3, 1),
                left: LabeledField('IBAN',
                    TextFormField(controller: _iban)),
                right: LabeledField('BIC',
                    TextFormField(controller: _bic)),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              FileUploadSection(
                title: 'Rahmenvertrag',
                storagePrefix: 'partner/rahmenvertraege',
                kind: UploadKind.pdf,
                file: _rahmenvertrag,
                hint: 'PDF mit Konditionen, Geheimhaltung usw.',
                onChanged: (f) => setState(() => _rahmenvertrag = f),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Notiz',
                TextFormField(
                    controller: _notiz, minLines: 2, maxLines: 4),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Checkbox(
                    value: _aktiv,
                    onChanged: (v) => setState(() => _aktiv = v ?? true)),
                const Text('Aktiv / verfügbar'),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
