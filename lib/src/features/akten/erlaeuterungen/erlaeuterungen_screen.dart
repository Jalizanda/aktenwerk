import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'erlaeuterungen_repository.dart';

class ErlaeuterungenScreen extends ConsumerWidget {
  const ErlaeuterungenScreen({super.key});
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');
  static final _timeFmt = DateFormat('HH:mm', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(erlaeuterungenListProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.gavel_outlined,
          title: 'Erläuterungstermine',
          subtitle: 'Mündliche Erläuterung vor Gericht',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neuer Termin'),
              onPressed: () => _show(context, ref),
            ),
          ],
          searchHint: 'Suche Gericht, Richter, Aktenzeichen …',
          onSearchChanged: (v) =>
              ref.read(erlaeuterungenQueryProvider.notifier).state = v,
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) => items.isEmpty
                ? const EmptyListState(
                    icon: Icons.gavel_outlined,
                    title: 'Keine Erläuterungstermine')
                : DataTableCard(
                    child: DataTable(
              showCheckboxColumn: false,
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      columns: const [
                        DataColumn(label: Text('Datum')),
                        DataColumn(label: Text('Uhrzeit')),
                        DataColumn(label: Text('Gericht')),
                        DataColumn(label: Text('Saal')),
                        DataColumn(label: Text('Richter/in')),
                        DataColumn(label: Text('Aktenzeichen')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final e in items)
                          DataRow(
                            onSelectChanged: (_) => _show(context, ref, e),
                            cells: [
                              DataCell(Text(e.eintrag.terminAm == null
                                  ? ''
                                  : _dateFmt.format(e.eintrag.terminAm!))),
                              DataCell(Text(e.eintrag.terminAm == null
                                  ? ''
                                  : _timeFmt.format(e.eintrag.terminAm!))),
                              DataCell(Text(e.eintrag.gericht ?? '')),
                              DataCell(Text(e.eintrag.saal ?? '')),
                              DataCell(Text(e.eintrag.richter ?? '')),
                              DataCell(
                                  Text(e.auftrag?.aktenzeichen ?? '')),
                              DataCell(Text(e.eintrag.status)),
                              DataCell(IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                onPressed: () async => ref
                                    .read(erlaeuterungenRepositoryProvider)
                                    .delete(e.eintrag.id),
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
      [ErlaeuterungWithAuftrag? e]) async {
    await showDialog(
        context: context, builder: (_) => _ErlaeuterungForm(eintrag: e));
  }
}

Future<void> showErlaeuterungEditor(BuildContext context,
    {ErlaeuterungWithAuftrag? eintrag}) async {
  await showDialog(
    context: context,
    useRootNavigator: true,
    builder: (_) => _ErlaeuterungForm(eintrag: eintrag),
  );
}

class _ErlaeuterungForm extends ConsumerStatefulWidget {
  const _ErlaeuterungForm({this.eintrag});
  final ErlaeuterungWithAuftrag? eintrag;
  @override
  ConsumerState<_ErlaeuterungForm> createState() =>
      _ErlaeuterungFormState();
}

class _ErlaeuterungFormState extends ConsumerState<_ErlaeuterungForm> {
  final _formKey = GlobalKey<FormState>();
  int? _auftragId;
  DateTime? _termin;
  DateTime? _ladungsdatum;
  DateTime? _vergueteAm;
  TimeOfDay _uhrzeit = const TimeOfDay(hour: 9, minute: 0);
  String _status = 'geplant';
  String _honorargruppe = 'M2';

  late final _gericht = _tec(widget.eintrag?.eintrag.gericht);
  late final _gerichtsort = _tec(widget.eintrag?.eintrag.gerichtsort);
  late final _saal = _tec(widget.eintrag?.eintrag.saal);
  late final _richter = _tec(widget.eintrag?.eintrag.richter);
  late final _ort = _tec(widget.eintrag?.eintrag.ort);
  late final _azExtern = _tec(widget.eintrag?.eintrag.azExtern);
  late final _parteien = _tec(widget.eintrag?.eintrag.parteien);
  late final _vorbereitung = _tec(widget.eintrag?.eintrag.vorbereitung);
  late final _notiz = _tec(widget.eintrag?.eintrag.notiz);
  late final _protokoll = _tec(widget.eintrag?.eintrag.protokoll);
  late final _dauerStd = _tec(
      (widget.eintrag?.eintrag.dauerStunden ?? 1).toStringAsFixed(1));
  late final _wartezeitStd = _tec(
      (widget.eintrag?.eintrag.wartezeitStunden ?? 0).toStringAsFixed(1));
  late final _fahrtKm = _tec(
      (widget.eintrag?.eintrag.fahrtKm ?? 0).toStringAsFixed(0));
  late final _kmSatz = _tec(
      (widget.eintrag?.eintrag.kmSatz ?? 0.42).toStringAsFixed(2));
  late final _stundensatz = _tec(
      (widget.eintrag?.eintrag.stundensatz ?? 110).toStringAsFixed(2));
  bool _saving = false;

  TextEditingController _tec(String? v) =>
      TextEditingController(text: v ?? '');

  @override
  void initState() {
    super.initState();
    final e = widget.eintrag?.eintrag;
    _auftragId = e?.auftragId;
    final t = e?.terminAm;
    _termin = t;
    if (t != null) {
      _uhrzeit = TimeOfDay(hour: t.hour, minute: t.minute);
    }
    _ladungsdatum = e?.ladungsdatum;
    _vergueteAm = e?.vergueteAm;
    _status = e?.status ?? 'geplant';
    _honorargruppe = e?.honorargruppe ?? 'M2';
  }

  @override
  void dispose() {
    for (final c in [
      _gericht, _gerichtsort, _saal, _richter, _ort,
      _azExtern, _parteien,
      _vorbereitung, _notiz, _protokoll,
      _dauerStd, _wartezeitStd, _fahrtKm, _kmSatz, _stundensatz,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.eintrag != null;

  DateTime? _combined() {
    if (_termin == null) return null;
    return DateTime(_termin!.year, _termin!.month, _termin!.day,
        _uhrzeit.hour, _uhrzeit.minute);
  }

  double _num(TextEditingController c, double fb) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? fb;

  _VergBerechnung _berechne() {
    final dauer = _num(_dauerStd, 0);
    final wartezeit = _num(_wartezeitStd, 0);
    final km = _num(_fahrtKm, 0);
    final kms = _num(_kmSatz, 0.42);
    final satz = _num(_stundensatz, 0);
    final termin = satz * (dauer + wartezeit);
    final fahrt = km * kms;
    final netto = termin + fahrt;
    final ust = netto * 0.19;
    final brutto = netto + ust;
    return _VergBerechnung(
      dauer: dauer,
      wartezeit: wartezeit,
      km: km,
      kmSatz: kms,
      satz: satz,
      termin: termin,
      fahrt: fahrt,
      netto: netto,
      ust: ust,
      brutto: brutto,
    );
  }

  void _applyHonorargruppe(String g) {
    // M1 = 90 €, M2 = 110 €, M3 = 130 € (JVEG § 9)
    final map = {'M1': '90', 'M2': '110', 'M3': '130'};
    if (map.containsKey(g)) {
      setState(() {
        _honorargruppe = g;
        _stundensatz.text = map[g]!;
      });
    } else {
      setState(() => _honorargruppe = g);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final companion = ErlaeuterungenCompanion(
      id: _isEdit
          ? Value(widget.eintrag!.eintrag.id)
          : const Value.absent(),
      auftragId: Value(_auftragId),
      terminAm: Value(_combined()),
      ladungsdatum: Value(_ladungsdatum),
      vergueteAm: Value(_vergueteAm),
      ort: _nt(_ort),
      gericht: _nt(_gericht),
      gerichtsort: _nt(_gerichtsort),
      saal: _nt(_saal),
      richter: _nt(_richter),
      azExtern: _nt(_azExtern),
      parteien: _nt(_parteien),
      status: Value(_status),
      honorargruppe: Value(_honorargruppe),
      dauerStunden: Value(_num(_dauerStd, 0)),
      wartezeitStunden: Value(_num(_wartezeitStd, 0)),
      fahrtKm: Value(_num(_fahrtKm, 0)),
      kmSatz: Value(_num(_kmSatz, 0.42)),
      stundensatz: Value(_num(_stundensatz, 0)),
      vorbereitung: _nt(_vorbereitung),
      notiz: _nt(_notiz),
      protokoll: _nt(_protokoll),
    );
    try {
      await ref
          .read(erlaeuterungenRepositoryProvider)
          .upsert(companion);
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
    final b = _berechne();
    final money =
        NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
    return StandardFormDialog(
      title: _isEdit
          ? 'Erläuterungstermin bearbeiten'
          : 'Neuer Erläuterungstermin',
      saving: _saving,
      maxWidth: 1000,
      maxHeight: 880,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(erlaeuterungenRepositoryProvider)
              .delete(widget.eintrag!.eintrag.id)
          : null,
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FormSection('Termin', children: [
                Row3(
                  a: DateField(
                    label: 'Datum',
                    value: _termin,
                    onChanged: (v) => setState(() => _termin = v),
                  ),
                  b: LabeledField(
                    'Uhrzeit',
                    InkWell(
                      onTap: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: _uhrzeit,
                        );
                        if (t != null) setState(() => _uhrzeit = t);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(isDense: true),
                        child: Text(
                            '${_uhrzeit.hour.toString().padLeft(2, '0')}:${_uhrzeit.minute.toString().padLeft(2, '0')}'),
                      ),
                    ),
                  ),
                  c: DateField(
                    label: 'Ladungsdatum',
                    value: _ladungsdatum,
                    onChanged: (v) => setState(() => _ladungsdatum = v),
                  ),
                ),
                const SizedBox(height: 12),
                Row2(
                  left: LabeledField(
                    'Status',
                    DropdownButtonFormField<String>(
                      initialValue: _status,
                      isDense: true,
                      items: const [
                        DropdownMenuItem(
                            value: 'geplant', child: Text('geplant')),
                        DropdownMenuItem(
                            value: 'geladen', child: Text('geladen')),
                        DropdownMenuItem(
                            value: 'vorbereitet',
                            child: Text('vorbereitet')),
                        DropdownMenuItem(
                            value: 'durchgefuehrt',
                            child: Text('durchgeführt')),
                        DropdownMenuItem(
                            value: 'verguetet',
                            child: Text('vergütet')),
                        DropdownMenuItem(
                            value: 'abgesagt', child: Text('abgesagt')),
                      ],
                      onChanged: (v) =>
                          setState(() => _status = v ?? 'geplant'),
                    ),
                  ),
                  right: AuftragPickerField(
                    auftragId: _auftragId,
                    onChanged: (id) => setState(() => _auftragId = id),
                  ),
                ),
              ]),
              FormSection('Gericht / Ort', children: [
                Row2(
                  left: LabeledField(
                      'Gericht', TextFormField(controller: _gericht)),
                  right: LabeledField(
                      'Gerichtsort',
                      TextFormField(controller: _gerichtsort)),
                ),
                const SizedBox(height: 12),
                Row3(
                  a: LabeledField(
                      'Saal', TextFormField(controller: _saal)),
                  b: LabeledField('Richter/in',
                      TextFormField(controller: _richter)),
                  c: LabeledField(
                      'Ort / Adresse', TextFormField(controller: _ort)),
                ),
              ]),
              FormSection('Verfahren', children: [
                Row2(
                  left: LabeledField('Geschäftszeichen',
                      TextFormField(controller: _azExtern)),
                  right: LabeledField(
                      'Parteien / Rubrum',
                      TextFormField(controller: _parteien)),
                ),
              ]),
              FormSection('JVEG-Vergütung', children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row2(
                            left: LabeledField(
                              'Honorargruppe (§ 9)',
                              DropdownButtonFormField<String>(
                                initialValue: _honorargruppe,
                                isDense: true,
                                items: const [
                                  DropdownMenuItem(
                                      value: 'M1',
                                      child: Text('M1 (90 €/h)')),
                                  DropdownMenuItem(
                                      value: 'M2',
                                      child: Text('M2 (110 €/h)')),
                                  DropdownMenuItem(
                                      value: 'M3',
                                      child: Text('M3 (130 €/h)')),
                                  DropdownMenuItem(
                                      value: 'custom',
                                      child: Text('frei')),
                                ],
                                onChanged: (v) =>
                                    _applyHonorargruppe(v ?? 'M2'),
                              ),
                            ),
                            right: LabeledField(
                              'Stundensatz (€)',
                              TextFormField(
                                controller: _stundensatz,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row2(
                            left: LabeledField(
                              'Termindauer (Std.)',
                              TextFormField(
                                controller: _dauerStd,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            right: LabeledField(
                              'Wartezeit (Std.)',
                              TextFormField(
                                controller: _wartezeitStd,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row2(
                            left: LabeledField(
                              'Fahrt (km)',
                              TextFormField(
                                controller: _fahrtKm,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            right: LabeledField(
                              '€/km (§ 5)',
                              TextFormField(
                                controller: _kmSatz,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DateField(
                            label: 'Vergütet am',
                            value: _vergueteAm,
                            onChanged: (v) =>
                                setState(() => _vergueteAm = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: _VergSumCard(b: b, money: money),
                    ),
                  ],
                ),
              ]),
              FormSection('Vorbereitung / Protokoll', children: [
                LabeledField(
                  'Vorbereitung',
                  TextFormField(
                      controller: _vorbereitung, minLines: 3, maxLines: 5),
                ),
                const SizedBox(height: 12),
                LabeledField(
                  'Protokoll',
                  TextFormField(
                      controller: _protokoll, minLines: 3, maxLines: 6),
                ),
                const SizedBox(height: 12),
                LabeledField(
                  'Notiz',
                  TextFormField(controller: _notiz, minLines: 2, maxLines: 3),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _VergBerechnung {
  final double dauer;
  final double wartezeit;
  final double km;
  final double kmSatz;
  final double satz;
  final double termin;
  final double fahrt;
  final double netto;
  final double ust;
  final double brutto;
  const _VergBerechnung({
    required this.dauer,
    required this.wartezeit,
    required this.km,
    required this.kmSatz,
    required this.satz,
    required this.termin,
    required this.fahrt,
    required this.netto,
    required this.ust,
    required this.brutto,
  });
}

class _VergSumCard extends StatelessWidget {
  const _VergSumCard({required this.b, required this.money});
  final _VergBerechnung b;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Live-Berechnung',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          _row('Termin',
              '${b.dauer.toStringAsFixed(1)} h × ${money.format(b.satz)}',
              money.format(b.satz * b.dauer)),
          if (b.wartezeit > 0)
            _row('Wartezeit',
                '${b.wartezeit.toStringAsFixed(1)} h × ${money.format(b.satz)}',
                money.format(b.satz * b.wartezeit)),
          if (b.km > 0)
            _row('Fahrt',
                '${b.km.toStringAsFixed(0)} km × ${money.format(b.kmSatz)}',
                money.format(b.fahrt)),
          const Divider(),
          _row('Netto', '', money.format(b.netto), bold: true),
          _row('USt 19 %', '', money.format(b.ust)),
          _row('Brutto', '', money.format(b.brutto), bold: true, large: true),
        ],
      ),
    );
  }

  Widget _row(String l, String sub, String v,
      {bool bold = false, bool large = false}) {
    final s = TextStyle(
      fontSize: large ? 14 : 12.5,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l, style: s),
                if (sub.isNotEmpty)
                  Text(sub,
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.slate500)),
              ],
            ),
          ),
          Text(v, style: s),
        ],
      ),
    );
  }
}
