import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/file_upload_section.dart';
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
          searchHint: 'Suche Bezeichnung, Hersteller, Seriennummer …',
          onSearchChanged: (v) => ref
              .read(geraeteFilterProvider.notifier)
              .update((f) => f.copyWith(query: v)),
          filters: [
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
              showCheckboxColumn: false,
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
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
              child: const Text('Abbrechen')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
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
  late final _inv = _tec(widget.geraet?.inventarNr);
  late final _bez = _tec(widget.geraet?.bezeichnung);
  late final _kategorie = _tec(widget.geraet?.kategorie);
  late final _hersteller = _tec(widget.geraet?.hersteller);
  late final _modell = _tec(widget.geraet?.modell);
  late final _seriennr = _tec(widget.geraet?.seriennummer);
  late final _anschaffungspreis = _tec(
      widget.geraet?.anschaffungspreis?.toStringAsFixed(2));
  late final _messbereich = _tec(widget.geraet?.messbereich);
  late final _genauigkeit = _tec(widget.geraet?.genauigkeit);
  late final _norm = _tec(widget.geraet?.norm);
  late final _standort = _tec(widget.geraet?.standort);
  late final _pruefstelle = _tec(widget.geraet?.pruefstelle);
  late final _zertifikat = _tec(widget.geraet?.zertifikatNr);
  late final _intervall =
      _tec(widget.geraet?.eichungIntervall?.toString());
  late final _notiz = _tec(widget.geraet?.notiz);
  DateTime? _angeschafft;
  DateTime? _kalibriertAm;
  DateTime? _naechsteKalibrierung;
  String _status = 'aktiv';
  String _eichpflicht = 'empfohlen';
  bool _aktiv = true;
  bool _saving = false;
  UploadedFile? _kalibrierschein;
  UploadedFile? _handbuch;
  UploadedFile? _foto;

  static const _kategorien = [
    'Feuchtemessung',
    'Thermografie',
    'Längenmessung',
    'Schall / Vibration',
    'Elektrisch',
    'Chemisch / Schimmel',
    'Sonstiges',
  ];

  TextEditingController _tec(String? v) =>
      TextEditingController(text: v ?? '');

  static const _statusValues = [
    'aktiv',
    'reparatur',
    'ausser_betrieb',
    'verkauft'
  ];
  static const _eichpflichtValues = ['keine', 'empfohlen', 'pflicht'];

  @override
  void initState() {
    super.initState();
    _angeschafft = widget.geraet?.angeschafftAm;
    _kalibriertAm = widget.geraet?.kalibriertAm;
    _naechsteKalibrierung = widget.geraet?.naechsteKalibrierung;
    _aktiv = widget.geraet?.aktiv ?? true;
    final rawStatus = widget.geraet?.status ?? 'aktiv';
    _status =
        _statusValues.contains(rawStatus) ? rawStatus : 'aktiv';
    final rawEich = widget.geraet?.eichpflicht ?? 'empfohlen';
    _eichpflicht = _eichpflichtValues.contains(rawEich)
        ? rawEich
        : (rawEich == 'nein' ? 'keine' : 'empfohlen');
    final g = widget.geraet;
    if (g?.kalibrierscheinStorageUrl != null &&
        g!.kalibrierscheinStorageUrl!.isNotEmpty) {
      _kalibrierschein = UploadedFile(
        storageUrl: g.kalibrierscheinStorageUrl!,
        dateiname: g.kalibrierscheinDateiname ?? 'Kalibrierschein',
        mimeType: g.kalibrierscheinMimeType,
        groesse: g.kalibrierscheinGroesse,
      );
    }
    if (g?.handbuchStorageUrl != null && g!.handbuchStorageUrl!.isNotEmpty) {
      _handbuch = UploadedFile(
        storageUrl: g.handbuchStorageUrl!,
        dateiname: g.handbuchDateiname ?? 'Handbuch',
        mimeType: g.handbuchMimeType,
        groesse: g.handbuchGroesse,
      );
    }
    if (g?.fotoStorageUrl != null && g!.fotoStorageUrl!.isNotEmpty) {
      _foto = UploadedFile(
        storageUrl: g.fotoStorageUrl!,
        dateiname: g.fotoDateiname ?? 'Foto',
        mimeType: 'image/jpeg',
      );
    }
  }

  @override
  void dispose() {
    for (final c in [
      _inv, _bez, _kategorie, _hersteller, _modell, _seriennr,
      _anschaffungspreis, _messbereich, _genauigkeit, _norm,
      _standort, _pruefstelle, _zertifikat, _intervall, _notiz,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.geraet != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final anschaffungspreis =
        double.tryParse(_anschaffungspreis.text.replaceAll(',', '.'));
    final intervall = int.tryParse(_intervall.text.trim());
    final companion = GeraeteCompanion(
      id: _isEdit ? Value(widget.geraet!.id) : const Value.absent(),
      inventarNr: _nt(_inv),
      bezeichnung: Value(_bez.text.trim()),
      kategorie: _nt(_kategorie),
      hersteller: _nt(_hersteller),
      modell: _nt(_modell),
      seriennummer: _nt(_seriennr),
      angeschafftAm: Value(_angeschafft),
      anschaffungspreis: Value(anschaffungspreis),
      status: Value(_status),
      eichpflicht: Value(_eichpflicht),
      kalibriertAm: Value(_kalibriertAm),
      naechsteKalibrierung: Value(_naechsteKalibrierung),
      eichungIntervall: Value(intervall),
      pruefstelle: _nt(_pruefstelle),
      zertifikatNr: _nt(_zertifikat),
      messbereich: _nt(_messbereich),
      genauigkeit: _nt(_genauigkeit),
      norm: _nt(_norm),
      standort: _nt(_standort),
      aktiv: Value(_aktiv),
      notiz: _nt(_notiz),
      kalibrierscheinStorageUrl: Value(_kalibrierschein?.storageUrl),
      kalibrierscheinDateiname: Value(_kalibrierschein?.dateiname),
      kalibrierscheinMimeType: Value(_kalibrierschein?.mimeType),
      kalibrierscheinGroesse: Value(_kalibrierschein?.groesse),
      handbuchStorageUrl: Value(_handbuch?.storageUrl),
      handbuchDateiname: Value(_handbuch?.dateiname),
      handbuchMimeType: Value(_handbuch?.mimeType),
      handbuchGroesse: Value(_handbuch?.groesse),
      fotoStorageUrl: Value(_foto?.storageUrl),
      fotoDateiname: Value(_foto?.dateiname),
    );
    try {
      await ref.read(geraeteRepositoryProvider).upsert(companion);
      if (mounted) Navigator.of(context, rootNavigator: true).pop(true);
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
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(geraeteRepositoryProvider)
              .delete(widget.geraet!.id)
          : null,
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row2(
                flex: const (1, 3),
                left: LabeledField(
                    'Inventar-Nr.', TextFormField(controller: _inv)),
                right: LabeledField(
                  'Bezeichnung',
                  TextFormField(
                    controller: _bez,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Erforderlich'
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                  'Kategorie',
                  DropdownButtonFormField<String>(
                    initialValue: _kategorien.contains(_kategorie.text)
                        ? _kategorie.text
                        : null,
                    isDense: true,
                    items: [
                      for (final k in _kategorien)
                        DropdownMenuItem(value: k, child: Text(k)),
                    ],
                    onChanged: (v) =>
                        setState(() => _kategorie.text = v ?? ''),
                  ),
                ),
                right: LabeledField(
                  'Status',
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    isDense: true,
                    items: const [
                      DropdownMenuItem(value: 'aktiv', child: Text('aktiv')),
                      DropdownMenuItem(
                          value: 'reparatur', child: Text('in Reparatur')),
                      DropdownMenuItem(
                          value: 'ausser_betrieb',
                          child: Text('außer Betrieb')),
                      DropdownMenuItem(
                          value: 'verkauft', child: Text('verkauft')),
                    ],
                    onChanged: (v) =>
                        setState(() => _status = v ?? 'aktiv'),
                  ),
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
              const SizedBox(height: 16),
              Text('Eichung / Kalibrierung',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row2(
                left: LabeledField(
                  'Eichpflicht',
                  DropdownButtonFormField<String>(
                    initialValue: _eichpflicht,
                    isDense: true,
                    items: const [
                      DropdownMenuItem(
                          value: 'keine', child: Text('keine')),
                      DropdownMenuItem(
                          value: 'empfohlen', child: Text('empfohlen')),
                      DropdownMenuItem(
                          value: 'pflicht', child: Text('Pflicht')),
                    ],
                    onChanged: (v) =>
                        setState(() => _eichpflicht = v ?? 'empfohlen'),
                  ),
                ),
                right: LabeledField(
                  'Intervall (Monate)',
                  TextFormField(
                    controller: _intervall,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row3(
                a: DateField(
                  label: 'Angeschafft am',
                  value: _angeschafft,
                  onChanged: (v) => setState(() => _angeschafft = v),
                ),
                b: DateField(
                  label: 'Letzte Kalibrierung',
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
              Row2(
                left: LabeledField(
                  'Anschaffungspreis (€)',
                  TextFormField(
                    controller: _anschaffungspreis,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                  ),
                ),
                right: LabeledField(
                    'Prüfstelle / Labor',
                    TextFormField(controller: _pruefstelle)),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField('Zertifikats-Nr.',
                    TextFormField(controller: _zertifikat)),
                right: LabeledField(
                    'Norm / Messverfahren',
                    TextFormField(controller: _norm)),
              ),
              const SizedBox(height: 16),
              Text('Technische Angaben',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row2(
                left: LabeledField(
                    'Messbereich', TextFormField(controller: _messbereich)),
                right: LabeledField('Genauigkeit',
                    TextFormField(controller: _genauigkeit)),
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
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              FileUploadSection(
                title: 'Kalibrierschein',
                storagePrefix: 'geraete/kalibrierscheine',
                kind: UploadKind.pdf,
                file: _kalibrierschein,
                hint:
                    'PDF des letzten Kalibrierscheins / Zertifikats.',
                onChanged: (f) => setState(() => _kalibrierschein = f),
              ),
              const SizedBox(height: 16),
              FileUploadSection(
                title: 'Bedienungsanleitung / Handbuch',
                storagePrefix: 'geraete/handbuecher',
                kind: UploadKind.pdf,
                file: _handbuch,
                onChanged: (f) => setState(() => _handbuch = f),
              ),
              const SizedBox(height: 16),
              FileUploadSection(
                title: 'Geräte-Foto',
                storagePrefix: 'geraete/fotos',
                kind: UploadKind.image,
                file: _foto,
                hint: 'Produktbild des Geräts.',
                onChanged: (f) => setState(() => _foto = f),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
