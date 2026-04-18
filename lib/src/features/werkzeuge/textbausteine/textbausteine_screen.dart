import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
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
          subtitle: 'Wiederverwendbare Textblöcke für Gutachten und Anschreiben',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neuer Baustein'),
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
                  hintText: 'Titel oder Inhalt',
                ),
                onChanged: (v) => ref
                    .read(textbausteineFilterProvider.notifier)
                    .update((f) => f.copyWith(query: v)),
              ),
            ),
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
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 8),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        _BausteinTile(baustein: items[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _show(BuildContext context, WidgetRef ref,
      [TextbausteineData? b]) async {
    await showDialog(
        context: context, builder: (_) => _BausteinForm(baustein: b));
  }
}

class _BausteinTile extends ConsumerWidget {
  const _BausteinTile({required this.baustein});
  final TextbausteineData baustein;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showDialog(
          context: context,
          builder: (_) => _BausteinForm(baustein: baustein),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      baustein.favorit ? Icons.star : Icons.star_outline,
                      size: 20,
                      color: baustein.favorit
                          ? Theme.of(context).colorScheme.tertiary
                          : null,
                    ),
                    onPressed: () async {
                      await ref
                          .read(textbausteineRepositoryProvider)
                          .upsert(TextbausteineCompanion(
                            id: Value(baustein.id),
                            favorit: Value(!baustein.favorit),
                          ));
                    },
                  ),
                  Expanded(
                    child: Text(
                      baustein.titel,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (baustein.kategorie != null)
                    Chip(
                      label: Text(baustein.kategorie!),
                      visualDensity: VisualDensity.compact,
                    ),
                  IconButton(
                    tooltip: 'Löschen',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () async {
                      await ref
                          .read(textbausteineRepositoryProvider)
                          .delete(baustein.id);
                    },
                  ),
                ],
              ),
              if ((baustein.inhalt ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  baustein.inhalt!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
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
  late final _inhalt =
      TextEditingController(text: widget.baustein?.inhalt ?? '');
  bool _favorit = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _favorit = widget.baustein?.favorit ?? false;
  }

  @override
  void dispose() {
    _titel.dispose();
    _kategorie.dispose();
    _inhalt.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.baustein != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final companion = TextbausteineCompanion(
      id: _isEdit ? Value(widget.baustein!.id) : const Value.absent(),
      titel: Value(_titel.text.trim()),
      kategorie: _nt(_kategorie),
      inhalt: _nt(_inhalt),
      favorit: Value(_favorit),
    );
    try {
      await ref.read(textbausteineRepositoryProvider).upsert(companion);
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
      title: _isEdit ? 'Textbaustein bearbeiten' : 'Neuer Textbaustein',
      saving: _saving,
      maxHeight: 620,
      onCancel: () => Navigator.pop(context, false),
      onSave: _save,
      body: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row2(
                left: LabeledField(
                  'Titel',
                  TextFormField(
                    controller: _titel,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Erforderlich' : null,
                  ),
                ),
                right: LabeledField(
                    'Kategorie', TextFormField(controller: _kategorie)),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Checkbox(
                    value: _favorit,
                    onChanged: (v) => setState(() => _favorit = v ?? false)),
                const Text('Favorit'),
              ]),
              const SizedBox(height: 8),
              Expanded(
                child: LabeledField(
                  'Inhalt',
                  TextFormField(
                    controller: _inhalt,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
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
