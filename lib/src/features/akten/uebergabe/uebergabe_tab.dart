import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import 'uebergabe_repository.dart';

class UebergabeTab extends ConsumerWidget {
  const UebergabeTab({super.key, required this.auftragId});
  final int auftragId;

  static final _fmt = DateFormat('dd.MM.yyyy', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(uebergabenByAkteProvider(auftragId));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Aktenübergabe-Protokolle',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _open(context, ref),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Übergabe'),
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
                      icon: Icons.handshake_outlined,
                      title: 'Keine Übergaben',
                      hint:
                          'Dokumentiere Akten-/Gutachten-Übergabe an Kollegen mit Datum, Umfang und Unterschrift.',
                    )
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final u = items[i];
                        return ListTile(
                          onTap: () => _open(context, ref, u),
                          title: Text(
                            '${u.von ?? '—'}   →   ${u.an ?? '—'}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text([
                            _fmt.format(u.datum),
                            if ((u.umfang ?? '').isNotEmpty) u.umfang!,
                          ].join(' · ')),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => ref
                                .read(uebergabeRepositoryProvider)
                                .delete(u.id),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref,
      [UebergabenData? u]) async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => _UebergabeEditor(auftragId: auftragId, eintrag: u),
    );
  }
}

class _UebergabeEditor extends ConsumerStatefulWidget {
  const _UebergabeEditor({required this.auftragId, this.eintrag});
  final int auftragId;
  final UebergabenData? eintrag;
  @override
  ConsumerState<_UebergabeEditor> createState() =>
      _UebergabeEditorState();
}

class _UebergabeEditorState extends ConsumerState<_UebergabeEditor> {
  late final _von =
      TextEditingController(text: widget.eintrag?.von ?? '');
  late final _an = TextEditingController(text: widget.eintrag?.an ?? '');
  late final _umfang =
      TextEditingController(text: widget.eintrag?.umfang ?? '');
  late final _unterlagen =
      TextEditingController(text: widget.eintrag?.unterlagen ?? '');
  late final _bemerkung =
      TextEditingController(text: widget.eintrag?.bemerkung ?? '');
  late DateTime _datum = widget.eintrag?.datum ?? DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _von.dispose();
    _an.dispose();
    _umfang.dispose();
    _unterlagen.dispose();
    _bemerkung.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.eintrag != null;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(uebergabeRepositoryProvider).upsert(
            UebergabenCompanion(
              id: _isEdit
                  ? Value(widget.eintrag!.id)
                  : const Value.absent(),
              auftragId: Value(widget.auftragId),
              datum: Value(_datum),
              von: Value(_von.text.trim().isEmpty ? null : _von.text.trim()),
              an: Value(_an.text.trim().isEmpty ? null : _an.text.trim()),
              umfang: Value(_umfang.text.trim().isEmpty
                  ? null
                  : _umfang.text.trim()),
              unterlagen: Value(_unterlagen.text.trim().isEmpty
                  ? null
                  : _unterlagen.text.trim()),
              bemerkung: Value(_bemerkung.text.trim().isEmpty
                  ? null
                  : _bemerkung.text.trim()),
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
      title: _isEdit ? 'Übergabe bearbeiten' : 'Neue Übergabe',
      icon: Icons.handshake_outlined,
      maxWidth: 680,
      maxHeight: 720,
      saving: _saving,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(uebergabeRepositoryProvider)
              .delete(widget.eintrag!.id)
          : null,
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
              b: LabeledField('Von (übergibt)',
                  TextFormField(controller: _von)),
              c: LabeledField(
                  'An (übernimmt)', TextFormField(controller: _an)),
            ),
            const SizedBox(height: 12),
            LabeledField('Umfang der Übergabe',
                TextFormField(controller: _umfang, minLines: 2, maxLines: 3)),
            const SizedBox(height: 12),
            LabeledField(
              'Übergebene Unterlagen (eine pro Zeile)',
              TextFormField(
                  controller: _unterlagen, minLines: 3, maxLines: 6),
            ),
            const SizedBox(height: 12),
            LabeledField(
              'Bemerkung',
              TextFormField(
                  controller: _bemerkung, minLines: 2, maxLines: 4),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.slate50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.slate200),
              ),
              child: Text(
                'Hinweis: Unterschrift + gedrucktes Protokoll folgen in einer späteren Ausbaustufe.',
                style: TextStyle(fontSize: 12, color: AppTheme.slate500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
