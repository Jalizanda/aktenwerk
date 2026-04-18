import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
          filters: [
            SizedBox(
              width: 320,
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Gericht, Richter, Aktenzeichen',
                ),
                onChanged: (v) =>
                    ref.read(erlaeuterungenQueryProvider.notifier).state = v,
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
                    icon: Icons.gavel_outlined,
                    title: 'Keine Erläuterungstermine')
                : DataTableCard(
                    child: DataTable(
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
  TimeOfDay _uhrzeit = const TimeOfDay(hour: 9, minute: 0);
  String _status = 'geplant';
  late final _gericht = _tec(widget.eintrag?.eintrag.gericht);
  late final _saal = _tec(widget.eintrag?.eintrag.saal);
  late final _richter = _tec(widget.eintrag?.eintrag.richter);
  late final _ort = _tec(widget.eintrag?.eintrag.ort);
  late final _vorbereitung = _tec(widget.eintrag?.eintrag.vorbereitung);
  late final _notiz = _tec(widget.eintrag?.eintrag.notiz);
  late final _protokoll = _tec(widget.eintrag?.eintrag.protokoll);
  bool _saving = false;

  TextEditingController _tec(String? v) =>
      TextEditingController(text: v ?? '');

  @override
  void initState() {
    super.initState();
    _auftragId = widget.eintrag?.eintrag.auftragId;
    final t = widget.eintrag?.eintrag.terminAm;
    _termin = t;
    if (t != null) {
      _uhrzeit = TimeOfDay(hour: t.hour, minute: t.minute);
    }
    _status = widget.eintrag?.eintrag.status ?? 'geplant';
  }

  @override
  void dispose() {
    for (final c in [
      _gericht, _saal, _richter, _ort, _vorbereitung, _notiz, _protokoll,
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final companion = ErlaeuterungenCompanion(
      id: _isEdit
          ? Value(widget.eintrag!.eintrag.id)
          : const Value.absent(),
      auftragId: Value(_auftragId),
      terminAm: Value(_combined()),
      ort: _nt(_ort),
      gericht: _nt(_gericht),
      saal: _nt(_saal),
      richter: _nt(_richter),
      status: Value(_status),
      vorbereitung: _nt(_vorbereitung),
      notiz: _nt(_notiz),
      protokoll: _nt(_protokoll),
    );
    try {
      await ref
          .read(erlaeuterungenRepositoryProvider)
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
      title:
          _isEdit ? 'Erläuterungstermin bearbeiten' : 'Neuer Erläuterungstermin',
      saving: _saving,
      maxWidth: 840,
      maxHeight: 780,
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
                c: LabeledField(
                  'Status',
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    isDense: true,
                    items: const [
                      DropdownMenuItem(
                          value: 'geplant', child: Text('geplant')),
                      DropdownMenuItem(
                          value: 'durchgefuehrt',
                          child: Text('durchgeführt')),
                      DropdownMenuItem(
                          value: 'verschoben',
                          child: Text('verschoben')),
                      DropdownMenuItem(
                          value: 'abgesagt', child: Text('abgesagt')),
                    ],
                    onChanged: (v) =>
                        setState(() => _status = v ?? 'geplant'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                  'Gericht',
                  TextFormField(controller: _gericht),
                ),
                right: LabeledField(
                  'Saal',
                  TextFormField(controller: _saal),
                ),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                  'Richter/in',
                  TextFormField(controller: _richter),
                ),
                right: LabeledField(
                  'Ort / Adresse',
                  TextFormField(controller: _ort),
                ),
              ),
              const SizedBox(height: 16),
              LabeledField(
                'Vorbereitung',
                TextFormField(
                    controller: _vorbereitung, minLines: 3, maxLines: 5),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Notiz',
                TextFormField(controller: _notiz, minLines: 2, maxLines: 4),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Protokoll',
                TextFormField(
                    controller: _protokoll, minLines: 3, maxLines: 6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
