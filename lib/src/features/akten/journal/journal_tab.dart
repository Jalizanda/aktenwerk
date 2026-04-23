import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../shared/widgets/form_widgets.dart';
import 'journal_repository.dart';

/// Chronologisches Projekt-Tagebuch je Akte.
class JournalTab extends ConsumerWidget {
  const JournalTab({super.key, required this.auftragId});
  final int auftragId;

  static final _fmt = DateFormat('dd.MM.yyyy HH:mm', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(journalByAkteProvider(auftragId));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Projekt-Tagebuch',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _open(context, ref),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Eintrag'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (items) => items.isEmpty
                  ? const EmptyListState(
                      icon: Icons.history_edu_outlined,
                      title: 'Noch keine Einträge',
                      hint:
                          'Telefonate, Anfragen, Zwischenbemerkungen — alles, was du später nachvollziehen willst.',
                    )
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1),
                      itemBuilder: (_, i) => _JournalTile(
                        eintrag: items[i],
                        onEdit: () =>
                            _open(context, ref, items[i]),
                        onDelete: () => ref
                            .read(journalRepositoryProvider)
                            .delete(items[i].id),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref,
      [JournaleintraegeData? eintrag]) async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) =>
          _JournalEditor(auftragId: auftragId, eintrag: eintrag),
    );
  }
}

class _JournalTile extends StatelessWidget {
  const _JournalTile({
    required this.eintrag,
    required this.onEdit,
    required this.onDelete,
  });
  final JournaleintraegeData eintrag;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 110,
              padding: const EdgeInsets.only(top: 2, right: 10),
              child: Text(
                JournalTab._fmt.format(eintrag.zeitpunkt),
                style: TextStyle(
                    fontSize: 12, color: AppTheme.slate500),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((eintrag.kategorie ?? '').isNotEmpty ||
                      (eintrag.kontakt ?? '').isNotEmpty)
                    Text(
                      [eintrag.kategorie, eintrag.kontakt]
                          .whereType<String>()
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accent600,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(eintrag.notiz,
                      style: const TextStyle(fontSize: 13, height: 1.4)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: 'Löschen',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalEditor extends ConsumerStatefulWidget {
  const _JournalEditor({required this.auftragId, this.eintrag});
  final int auftragId;
  final JournaleintraegeData? eintrag;
  @override
  ConsumerState<_JournalEditor> createState() => _JournalEditorState();
}

class _JournalEditorState extends ConsumerState<_JournalEditor> {
  static const _kategorien = [
    'Notiz',
    'Telefonat',
    'E-Mail',
    'Ortstermin',
    'Rückfrage',
    'Besprechung',
  ];

  late final _notiz = TextEditingController(text: widget.eintrag?.notiz ?? '');
  late final _kontakt =
      TextEditingController(text: widget.eintrag?.kontakt ?? '');
  late DateTime _zeitpunkt = widget.eintrag?.zeitpunkt ?? DateTime.now();
  late String _kategorie = widget.eintrag?.kategorie ?? 'Notiz';
  bool _saving = false;

  @override
  void dispose() {
    _notiz.dispose();
    _kontakt.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.eintrag != null;

  Future<void> _save() async {
    if (_notiz.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(journalRepositoryProvider).upsert(
            JournaleintraegeCompanion(
              id: _isEdit
                  ? Value(widget.eintrag!.id)
                  : const Value.absent(),
              auftragId: Value(widget.auftragId),
              zeitpunkt: Value(_zeitpunkt),
              kategorie: Value(_kategorie),
              kontakt: Value(_kontakt.text.trim().isEmpty
                  ? null
                  : _kontakt.text.trim()),
              notiz: Value(_notiz.text.trim()),
            ),
          );
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StandardFormDialog(
      title: _isEdit ? 'Eintrag bearbeiten' : 'Neuer Journal-Eintrag',
      icon: Icons.history_edu_outlined,
      maxWidth: 620,
      maxHeight: 560,
      saving: _saving,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(journalRepositoryProvider)
              .delete(widget.eintrag!.id)
          : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row2(
              left: LabeledField(
                'Zeitpunkt',
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _zeitpunkt,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime:
                          TimeOfDay.fromDateTime(_zeitpunkt),
                    );
                    if (!mounted) return;
                    setState(() {
                      _zeitpunkt = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time?.hour ?? _zeitpunkt.hour,
                        time?.minute ?? _zeitpunkt.minute,
                      );
                    });
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      suffixIcon: Icon(Icons.calendar_month_outlined),
                    ),
                    child: Text(DateFormat('dd.MM.yyyy HH:mm', 'de')
                        .format(_zeitpunkt)),
                  ),
                ),
              ),
              right: LabeledField(
                'Kategorie',
                DropdownButtonFormField<String>(
                  initialValue: _kategorie,
                  isDense: true,
                  items: [
                    for (final k in _kategorien)
                      DropdownMenuItem(value: k, child: Text(k)),
                  ],
                  onChanged: (v) =>
                      setState(() => _kategorie = v ?? 'Notiz'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            LabeledField(
              'Kontakt / Gesprächspartner (optional)',
              TextFormField(controller: _kontakt),
            ),
            const SizedBox(height: 12),
            LabeledField(
              'Notiz',
              TextFormField(
                controller: _notiz,
                minLines: 4,
                maxLines: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
