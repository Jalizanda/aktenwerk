import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/seed/demo_merge_importer.dart';
import '../../../shared/richtext/quill_editor.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'sv_vorlagen_seed.dart';
import 'textbausteine_repository.dart';

class TextbausteineScreen extends ConsumerWidget {
  const TextbausteineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(textbausteineListProvider);
    final kats = ref.watch(textbausteinKategorienProvider);
    final filter = ref.watch(textbausteineFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.text_snippet_outlined,
          title: 'Textbausteine',
          subtitle:
              'Wiederverwendbare Textblöcke für Gutachten und Anschreiben',
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.library_books_outlined, size: 18),
              label: const Text('SV-Vorlagen laden'),
              onPressed: () => _importSvVorlagen(context, ref),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.cloud_download_outlined, size: 18),
              label: const Text('Demo-Bausteine laden'),
              onPressed: () => _importDemoBausteine(context, ref),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neuer Baustein'),
              onPressed: () => _show(context, ref),
            ),
          ],
          searchHint: 'Suche Titel oder Inhalt …',
          onSearchChanged: (v) => ref
              .read(textbausteineFilterProvider.notifier)
              .update((f) => f.copyWith(query: v)),
          filters: [
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: filter.kategorie,
                hint: const Text('Alle Kategorien'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Alle Kategorien')),
                  ...kats.valueOrNull
                          ?.map((k) =>
                              DropdownMenuItem(value: k, child: Text(k)))
                          .toList() ??
                      const <DropdownMenuItem<String?>>[],
                ],
                onChanged: (v) => ref
                    .read(textbausteineFilterProvider.notifier)
                    .update((f) => v == null
                        ? f.copyWith(clearKategorie: true)
                        : f.copyWith(kategorie: v)),
              ),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(
                value: filter.nurFavoriten,
                onChanged: (v) => ref
                    .read(textbausteineFilterProvider.notifier)
                    .update((f) => f.copyWith(nurFavoriten: v ?? false)),
              ),
              const Text('Nur Favoriten'),
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
                    icon: Icons.text_snippet_outlined,
                    title: 'Keine Textbausteine')
                : DataTableCard(
                    child: DataTable(
                      showCheckboxColumn: false,
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                      ),
                      columns: const [
                        DataColumn(
                            label: SizedBox(width: 28, child: Text(''))),
                        DataColumn(label: Text('Titel / Kürzel')),
                        DataColumn(label: Text('Kategorie')),
                        DataColumn(label: Text('Sachgebiet')),
                        DataColumn(label: Text('Inhalt (Vorschau)')),
                        DataColumn(
                            label: SizedBox(width: 28, child: Text(''))),
                        DataColumn(
                            label: SizedBox(width: 28, child: Text(''))),
                      ],
                      rows: [
                        for (final b in items)
                          DataRow(
                            onSelectChanged: (_) => _show(context, ref, b),
                            cells: [
                              DataCell(IconButton(
                                tooltip: b.favorit
                                    ? 'Favorit entfernen'
                                    : 'Als Favorit markieren',
                                icon: Icon(
                                  b.favorit
                                      ? Icons.star
                                      : Icons.star_outline,
                                  size: 18,
                                  color: b.favorit
                                      ? Theme.of(context)
                                          .colorScheme
                                          .tertiary
                                      : null,
                                ),
                                onPressed: () async {
                                  await ref
                                      .read(textbausteineRepositoryProvider)
                                      .upsert(TextbausteineCompanion(
                                        id: Value(b.id),
                                        favorit: Value(!b.favorit),
                                      ));
                                },
                              )),
                              DataCell(SizedBox(
                                width: 220,
                                child: Text(
                                  b.titel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              )),
                              DataCell(b.kategorie == null
                                  ? const Text('—')
                                  : _KatBadge(text: b.kategorie!)),
                              DataCell(Text(b.sachgebiet ?? '—',
                                  style: const TextStyle(fontSize: 12.5))),
                              DataCell(SizedBox(
                                width: 460,
                                child: Text(
                                  _vorschau(b.inhalt),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppTheme.slate500),
                                ),
                              )),
                              DataCell(IconButton(
                                tooltip: 'Bearbeiten',
                                icon: const Icon(Icons.edit_outlined,
                                    size: 18),
                                onPressed: () => _show(context, ref, b),
                              )),
                              DataCell(IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline,
                                    size: 18),
                                onPressed: () => _confirm(context, ref, b),
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

  /// Liefert den reinen Text (Quill-Delta → Plaintext) gekürzt für die Liste.
  String _vorschau(String? raw) {
    final plain = plainTextFromDeltaJson(raw);
    if (plain.isEmpty) return '—';
    return plain.replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _show(BuildContext context, WidgetRef ref,
      [TextbausteineData? b]) async {
    await showDialog(
        context: context,
        useRootNavigator: true,
        builder: (_) => _BausteinForm(baustein: b));
  }

  Future<void> _importSvVorlagen(
      BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: const Text('SV-Vorlagen Deutschland laden?'),
        content: Text(
          '${svVorlagen.length} Vorlagen (Gerichtsgutachten, JVEG/'
          'Hinweispflicht, Privatgutachten, Qualitätssicherung) werden '
          'zusätzlich zu deinen bestehenden Textbausteinen angelegt.\n\n'
          'Deine vorhandenen Bausteine bleiben unverändert. Vorlagen '
          'mit identischem Titel werden übersprungen — keine Duplikate.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(true),
            child: const Text('Vorlagen importieren'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final report = await ladeSvVorlagen(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(report.bereitsVorhanden == 0
                ? '${report.neu} SV-Vorlagen importiert.'
                : '${report.neu} neu angelegt · '
                    '${report.bereitsVorhanden} bereits vorhanden (übersprungen).'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import fehlgeschlagen: $e')),
        );
      }
    }
  }

  Future<void> _importDemoBausteine(
      BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: const Text('Demo-Textbausteine laden?'),
        content: const Text(
          'Die 95 Textbausteine aus den Demo-Daten werden zusätzlich '
          'in deinen Mandanten importiert. Bestehende Bausteine bleiben '
          'unverändert; Bausteine mit identischem Titel werden '
          'übersprungen.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(true),
            child: const Text('Importieren'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final res =
          await ref.read(demoMergeImporterProvider).importTextbausteine();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.skipped == 0
                ? '${res.added} Textbausteine importiert.'
                : '${res.added} neu angelegt · ${res.skipped} '
                    'übersprungen (bereits vorhanden).'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import fehlgeschlagen: $e')),
        );
      }
    }
  }

  Future<void> _confirm(
      BuildContext context, WidgetRef ref, TextbausteineData b) async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: const Text('Textbaustein löschen?'),
        content: Text('«${b.titel}» wird gelöscht.'),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(false),
              child: const Text('Abbrechen')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(textbausteineRepositoryProvider).delete(b.id);
    }
  }
}

class _KatBadge extends StatelessWidget {
  const _KatBadge({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.slate100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate500)),
    );
  }
}

class _BausteinForm extends ConsumerStatefulWidget {
  const _BausteinForm({this.baustein});
  final TextbausteineData? baustein;
  @override
  ConsumerState<_BausteinForm> createState() => _BausteinFormState();
}

class _BausteinFormState extends ConsumerState<_BausteinForm> {
  final _formKey = GlobalKey<FormState>();
  late final _titel =
      TextEditingController(text: widget.baustein?.titel ?? '');
  late final _kategorie =
      TextEditingController(text: widget.baustein?.kategorie ?? '');
  late final _sachgebiet =
      TextEditingController(text: widget.baustein?.sachgebiet ?? '');
  late final _tags =
      TextEditingController(text: widget.baustein?.tags ?? '');
  String? _inhaltJson;
  bool _favorit = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _favorit = widget.baustein?.favorit ?? false;
    _inhaltJson = widget.baustein?.inhalt;
  }

  @override
  void dispose() {
    _titel.dispose();
    _kategorie.dispose();
    _sachgebiet.dispose();
    _tags.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.baustein != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final inhaltTrimmed = (_inhaltJson ?? '').trim();
    final companion = TextbausteineCompanion(
      id: _isEdit ? Value(widget.baustein!.id) : const Value.absent(),
      titel: Value(_titel.text.trim()),
      kategorie: _nt(_kategorie),
      sachgebiet: _nt(_sachgebiet),
      tags: _nt(_tags),
      inhalt: Value(inhaltTrimmed.isEmpty ? null : inhaltTrimmed),
      favorit: Value(_favorit),
    );
    try {
      await ref.read(textbausteineRepositoryProvider).upsert(companion);
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
      title: _isEdit ? 'Textbaustein bearbeiten' : 'Neuer Textbaustein',
      saving: _saving,
      maxHeight: 680,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(textbausteineRepositoryProvider)
              .delete(widget.baustein!.id)
          : null,
      body: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row2(
                left: LabeledField(
                  'Titel / Kürzel',
                  TextFormField(
                    controller: _titel,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Erforderlich'
                        : null,
                  ),
                ),
                right: LabeledField(
                    'Kategorie', TextFormField(controller: _kategorie)),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                    'Sachgebiet', TextFormField(controller: _sachgebiet)),
                right: LabeledField(
                    'Tags (komma-getrennt)',
                    TextFormField(controller: _tags)),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Switch(
                    value: _favorit,
                    onChanged: (v) => setState(() => _favorit = v)),
                const SizedBox(width: 6),
                const Text('Favorit'),
              ]),
              const SizedBox(height: 12),
              Text('Inhalt',
                  style:
                      Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          )),
              const SizedBox(height: 6),
              Expanded(
                child: SingleChildScrollView(
                  child: RichTextEditor(
                    initialDeltaJson: _inhaltJson,
                    onChanged: (json) => _inhaltJson = json,
                    minHeight: 260,
                    placeholder:
                        'Text des Bausteins — wird in Gutachten / Anschreiben übernommen.',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
