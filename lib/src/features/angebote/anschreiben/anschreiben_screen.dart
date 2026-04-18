import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../features/akten/kunden/kunden_picker.dart';
import '../../../features/akten/kunden/kunden_repository.dart';
import '../../../shared/richtext/quill_editor.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'anschreiben_repository.dart';

class AnschreibenScreen extends ConsumerWidget {
  const AnschreibenScreen({super.key});
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(anschreibenListProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.drafts_outlined,
          title: 'Anschreiben',
          subtitle: 'Individuelle Schreiben an Beteiligte und Gerichte',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neues Anschreiben'),
              onPressed: () => _open(context, ref),
            ),
          ],
          filters: [
            SizedBox(
              width: 320,
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Betreff, Kunde, Aktenzeichen',
                ),
                onChanged: (v) =>
                    ref.read(anschreibenQueryProvider.notifier).state = v,
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
                    icon: Icons.drafts_outlined,
                    title: 'Keine Anschreiben')
                : DataTableCard(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      columns: const [
                        DataColumn(label: Text('Datum')),
                        DataColumn(label: Text('Betreff')),
                        DataColumn(label: Text('Empfänger')),
                        DataColumn(label: Text('Aktenzeichen')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final a in items)
                          DataRow(
                            onSelectChanged: (_) => _open(context, ref, a),
                            cells: [
                              DataCell(Text(_dateFmt.format(a.anschreiben.datum))),
                              DataCell(Text(a.anschreiben.betreff ?? '')),
                              DataCell(Text(a.kunde == null
                                  ? ''
                                  : kundeAnzeigename(a.kunde!))),
                              DataCell(
                                  Text(a.auftrag?.aktenzeichen ?? '')),
                              DataCell(Text(a.anschreiben.status)),
                              DataCell(IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                onPressed: () async => ref
                                    .read(anschreibenRepositoryProvider)
                                    .delete(a.anschreiben.id),
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

  Future<void> _open(BuildContext context, WidgetRef ref,
      [AnschreibenWithKunde? a]) async {
    await showDialog(
      context: context,
      builder: (_) => Dialog.fullscreen(
        child: _AnschreibenEditor(eintrag: a),
      ),
    );
  }
}

class _AnschreibenEditor extends ConsumerStatefulWidget {
  const _AnschreibenEditor({this.eintrag});
  final AnschreibenWithKunde? eintrag;
  @override
  ConsumerState<_AnschreibenEditor> createState() =>
      _AnschreibenEditorState();
}

class _AnschreibenEditorState extends ConsumerState<_AnschreibenEditor> {
  late final _betreff = TextEditingController(
      text: widget.eintrag?.anschreiben.betreff ?? '');
  int? _kundeId;
  int? _auftragId;
  DateTime _datum = DateTime.now();
  String _status = 'entwurf';
  String? _inhaltJson;
  bool _saving = false;

  static const _statusValues = ['entwurf', 'versendet', 'abgelegt'];

  @override
  void initState() {
    super.initState();
    final a = widget.eintrag?.anschreiben;
    _kundeId = a?.kundeId;
    _auftragId = a?.auftragId;
    _datum = a?.datum ?? DateTime.now();
    _status = a?.status ?? 'entwurf';
    _inhaltJson = a?.inhaltJson;
  }

  @override
  void dispose() {
    _betreff.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.eintrag != null;

  Future<void> _save() async {
    setState(() => _saving = true);
    final companion = AnschreibenCompanion(
      id: _isEdit
          ? Value(widget.eintrag!.anschreiben.id)
          : const Value.absent(),
      kundeId: Value(_kundeId),
      auftragId: Value(_auftragId),
      datum: Value(_datum),
      status: Value(_status),
      betreff: Value(_betreff.text.trim().isEmpty
          ? null
          : _betreff.text.trim()),
      inhaltJson: Value(_inhaltJson),
    );
    try {
      await ref.read(anschreibenRepositoryProvider).upsert(companion);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Anschreiben gespeichert')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title:
            Text(_isEdit ? 'Anschreiben bearbeiten' : 'Neues Anschreiben'),
        actions: [
          IconButton(
            tooltip: 'Speichern',
            icon: const Icon(Icons.save_outlined),
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row3(
                a: DateField(
                    label: 'Datum',
                    value: _datum,
                    onChanged: (v) =>
                        setState(() => _datum = v ?? DateTime.now())),
                b: LabeledField(
                  'Status',
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    isDense: true,
                    items: [
                      for (final s in _statusValues)
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) =>
                        setState(() => _status = v ?? 'entwurf'),
                  ),
                ),
                c: KundenPickerField(
                  kundeId: _kundeId,
                  onChanged: (id) => setState(() => _kundeId = id),
                  label: 'Empfänger',
                ),
              ),
              const SizedBox(height: 12),
              Row2(
                left: AuftragPickerField(
                  auftragId: _auftragId,
                  onChanged: (id) => setState(() => _auftragId = id),
                ),
                right: LabeledField(
                  'Betreff',
                  TextFormField(controller: _betreff),
                ),
              ),
              const SizedBox(height: 16),
              Text('Inhalt',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              RichTextEditor(
                initialDeltaJson: _inhaltJson,
                onChanged: (json) => _inhaltJson = json,
                minHeight: 480,
                placeholder: 'Anschreiben hier verfassen …',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
