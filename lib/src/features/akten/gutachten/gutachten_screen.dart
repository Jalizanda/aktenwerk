import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../shared/richtext/quill_editor.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'gutachten_repository.dart';

class GutachtenScreen extends ConsumerWidget {
  const GutachtenScreen({super.key});
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(gutachtenListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.description_outlined,
          title: 'Gutachten',
          subtitle: '13 Abschnitte nach Zöller, Rich-Text-Editor',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neues Gutachten'),
              onPressed: () => _openEditor(context, ref),
            ),
          ],
          filters: [
            SizedBox(
              width: 320,
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Titel, Aktenzeichen',
                ),
                onChanged: (v) =>
                    ref.read(gutachtenQueryProvider.notifier).state = v,
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
                    icon: Icons.description_outlined,
                    title: 'Noch keine Gutachten')
                : DataTableCard(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      columns: const [
                        DataColumn(label: Text('Titel')),
                        DataColumn(label: Text('Aktenzeichen')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Ortstermin')),
                        DataColumn(label: Text('Abgabe')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final g in items)
                          DataRow(
                            onSelectChanged: (_) => _openEditor(
                                context, ref,
                                vorhanden: g.gutachten),
                            cells: [
                              DataCell(Text(g.gutachten.titel ?? '(ohne Titel)')),
                              DataCell(
                                  Text(g.auftrag?.aktenzeichen ?? '')),
                              DataCell(Text(g.gutachten.status)),
                              DataCell(Text(g.gutachten.ortsterminAm == null
                                  ? ''
                                  : _dateFmt.format(g.gutachten.ortsterminAm!))),
                              DataCell(Text(g.gutachten.abgabeAm == null
                                  ? ''
                                  : _dateFmt.format(g.gutachten.abgabeAm!))),
                              DataCell(IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                onPressed: () async => ref
                                    .read(gutachtenRepositoryProvider)
                                    .delete(g.gutachten.id),
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

  Future<void> _openEditor(BuildContext context, WidgetRef ref,
      {GutachtenData? vorhanden}) async {
    await showDialog(
      context: context,
      builder: (_) => Dialog.fullscreen(
        child: _GutachtenEditor(gutachten: vorhanden),
      ),
    );
  }
}

class _GutachtenEditor extends ConsumerStatefulWidget {
  const _GutachtenEditor({this.gutachten});
  final GutachtenData? gutachten;
  @override
  ConsumerState<_GutachtenEditor> createState() => _GutachtenEditorState();
}

class _GutachtenEditorState extends ConsumerState<_GutachtenEditor> {
  late final _titel =
      TextEditingController(text: widget.gutachten?.titel ?? '');
  String _status = 'entwurf';
  int? _auftragId;
  DateTime? _ortstermin;
  DateTime? _abgabe;
  late Map<String, String> _abschnitte;
  String _aktuellerAbschnitt = gutachtenAbschnitte.first;
  bool _saving = false;

  static const _statusValues = [
    'entwurf',
    'in_arbeit',
    'review',
    'fertig',
    'abgegeben',
  ];

  @override
  void initState() {
    super.initState();
    final g = widget.gutachten;
    _status = g?.status ?? 'entwurf';
    _auftragId = g?.auftragId;
    _ortstermin = g?.ortsterminAm;
    _abgabe = g?.abgabeAm;
    _abschnitte = abschnitteFromJson(g?.abschnitteJson);
  }

  @override
  void dispose() {
    _titel.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.gutachten != null;

  Future<void> _save() async {
    setState(() => _saving = true);
    final companion = GutachtenCompanion(
      id: _isEdit ? Value(widget.gutachten!.id) : const Value.absent(),
      titel: Value(_titel.text.trim().isEmpty ? null : _titel.text.trim()),
      status: Value(_status),
      auftragId: Value(_auftragId),
      ortsterminAm: Value(_ortstermin),
      abgabeAm: Value(_abgabe),
      abschnitteJson: Value(abschnitteToJson(_abschnitte)),
    );
    try {
      await ref.read(gutachtenRepositoryProvider).upsert(companion);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gutachten gespeichert')),
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
        title: Text(_isEdit ? 'Gutachten bearbeiten' : 'Neues Gutachten'),
        actions: [
          IconButton(
            tooltip: 'Speichern',
            icon: const Icon(Icons.save_outlined),
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 260,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: ListView(
                children: [
                  for (final k in gutachtenAbschnitte)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        _abschnitte[k]?.isNotEmpty == true
                            ? Icons.check_circle_outline
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: _aktuellerAbschnitt == k
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(k,
                          style: TextStyle(
                            fontWeight: _aktuellerAbschnitt == k
                                ? FontWeight.w600
                                : FontWeight.w400,
                          )),
                      selected: _aktuellerAbschnitt == k,
                      onTap: () => setState(() => _aktuellerAbschnitt = k),
                    ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row2(
                    flex: const (3, 1),
                    left: LabeledField(
                        'Titel', TextFormField(controller: _titel)),
                    right: LabeledField(
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
                  ),
                  const SizedBox(height: 12),
                  Row3(
                    a: AuftragPickerField(
                      auftragId: _auftragId,
                      onChanged: (id) => setState(() => _auftragId = id),
                    ),
                    b: DateField(
                      label: 'Ortstermin',
                      value: _ortstermin,
                      onChanged: (v) => setState(() => _ortstermin = v),
                    ),
                    c: DateField(
                      label: 'Abgabe',
                      value: _abgabe,
                      onChanged: (v) => setState(() => _abgabe = v),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(_aktuellerAbschnitt,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  RichTextEditor(
                    initialDeltaJson:
                        _abschnitte[_aktuellerAbschnitt] ?? '',
                    onChanged: (json) {
                      _abschnitte[_aktuellerAbschnitt] = json;
                    },
                    minHeight: 420,
                    placeholder:
                        'Text für «$_aktuellerAbschnitt» hier eingeben …',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
