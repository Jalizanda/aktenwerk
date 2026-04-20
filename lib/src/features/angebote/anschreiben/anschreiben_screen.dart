import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../features/akten/kunden/kunden_picker.dart';
import '../../../features/akten/kunden/kunden_repository.dart';
import '../../../features/werkzeuge/textbausteine/textbausteine_repository.dart';
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
            OutlinedButton.icon(
              icon: const Icon(Icons.article_outlined, size: 16),
              label: const Text('Vorlagen'),
              onPressed: () => context.go('/textbausteine'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neues Anschreiben'),
              onPressed: () => _open(context, ref),
            ),
          ],
          searchHint: 'Suche Betreff, Kunde, Aktenzeichen …',
          onSearchChanged: (v) =>
              ref.read(anschreibenQueryProvider.notifier).state = v,
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
              showCheckboxColumn: false,
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
      useRootNavigator: true,
      builder: (_) => _AnschreibenEditor(eintrag: a),
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
  late final _anrede = TextEditingController(
      text: widget.eintrag?.anschreiben.anrede ?? '');
  late final _gruss = TextEditingController(
      text: widget.eintrag?.anschreiben.gruss ?? 'Mit freundlichen Grüßen');
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
    _anrede.dispose();
    _gruss.dispose();
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
      anrede: Value(
          _anrede.text.trim().isEmpty ? null : _anrede.text.trim()),
      gruss: Value(
          _gruss.text.trim().isEmpty ? null : _gruss.text.trim()),
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

  Future<void> _vorlageEinfuegen() async {
    final picked = await showDialog<TextbausteineData>(
      context: context,
      useRootNavigator: true,
      builder: (_) => const _AnschreibenVorlagePicker(),
    );
    if (picked == null) return;
    setState(() {
      if ((picked.titel).isNotEmpty && _betreff.text.trim().isEmpty) {
        _betreff.text = picked.titel;
      }
      // Inhalt übernehmen (JSON-Delta oder Plain-Text-Fallback).
      _inhaltJsonKey++; // erzwingt Reset des RichTextEditor
      _inhaltJson = picked.inhalt;
    });
  }

  int _inhaltJsonKey = 0;

  @override
  Widget build(BuildContext context) {
    return StandardFormDialog(
      title: _isEdit ? 'Anschreiben bearbeiten' : 'Neues Anschreiben',
      icon: Icons.drafts_outlined,
      maxWidth: 980,
      maxHeight: 820,
      saving: _saving,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(anschreibenRepositoryProvider)
              .delete(widget.eintrag!.anschreiben.id)
          : null,
      footerLeading: OutlinedButton.icon(
        icon: const Icon(Icons.article_outlined, size: 16),
        label: const Text('Vorlage einfügen …'),
        onPressed: _vorlageEinfuegen,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
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
            const SizedBox(height: 12),
            Row2(
              left: LabeledField(
                'Briefanrede',
                TextFormField(
                  controller: _anrede,
                  decoration: const InputDecoration(
                    hintText: 'Sehr geehrte Frau …,',
                  ),
                ),
              ),
              right: LabeledField(
                'Grußformel',
                TextFormField(
                    controller: _gruss, minLines: 2, maxLines: 4),
              ),
            ),
            const SizedBox(height: 16),
            Text('Inhalt',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            RichTextEditor(
              key: ValueKey('anschreiben-inhalt-$_inhaltJsonKey'),
              initialDeltaJson: _inhaltJson,
              onChanged: (json) => _inhaltJson = json,
              minHeight: 360,
              placeholder: 'Anschreiben hier verfassen …',
            ),
          ],
        ),
      ),
    );
  }
}

/// Vorlagen-Picker für Anschreiben — zeigt alle Textbausteine der
/// Kategorie "anschreiben", mit Suche. Auswählen übernimmt den Inhalt.
class _AnschreibenVorlagePicker extends ConsumerStatefulWidget {
  const _AnschreibenVorlagePicker();
  @override
  ConsumerState<_AnschreibenVorlagePicker> createState() =>
      _AnschreibenVorlagePickerState();
}

class _AnschreibenVorlagePickerState
    extends ConsumerState<_AnschreibenVorlagePicker> {
  String _query = '';
  bool _nurKategorie = true;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(textbausteineListProvider);
    return Dialog(
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.article_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Vorlage einfügen',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Vorlagen verwalten'),
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).pop();
                      GoRouter.of(context).go('/textbausteine');
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 20),
                        hintText: 'Titel oder Inhalt …',
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Row(
                    children: [
                      Checkbox(
                        value: _nurKategorie,
                        onChanged: (v) =>
                            setState(() => _nurKategorie = v ?? true),
                      ),
                      const Text('nur "anschreiben"',
                          style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Fehler: $e')),
                data: (items) {
                  final q = _query.trim().toLowerCase();
                  final filtered = items.where((b) {
                    if (_nurKategorie) {
                      final kat = (b.kategorie ?? '').toLowerCase();
                      final sg = (b.sachgebiet ?? '').toLowerCase();
                      if (kat != 'anschreiben' && sg != 'anschreiben') {
                        return false;
                      }
                    }
                    if (q.isEmpty) return true;
                    return b.titel.toLowerCase().contains(q) ||
                        (b.kategorie ?? '').toLowerCase().contains(q) ||
                        plainTextFromDeltaJson(b.inhalt)
                            .toLowerCase()
                            .contains(q);
                  }).toList();
                  if (filtered.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Keine Anschreiben-Vorlagen vorhanden.\n'
                          'Lege welche unter Werkzeuge → Textbausteine an '
                          '(Kategorie "anschreiben").',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final b = filtered[i];
                      final vorschau = plainTextFromDeltaJson(b.inhalt)
                          .replaceAll(RegExp(r'\s+'), ' ')
                          .trim();
                      return ListTile(
                        dense: true,
                        title: Text(b.titel,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          vorschau,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () =>
                            Navigator.of(context, rootNavigator: true)
                                .pop(b),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
