import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import '../../../shared/widgets/date_field.dart';
import '../auftraege/auftrag_picker.dart';
import 'lv_repository.dart';

class LvScreen extends ConsumerStatefulWidget {
  const LvScreen({super.key});

  @override
  ConsumerState<LvScreen> createState() => _LvScreenState();
}

class _LvScreenState extends ConsumerState<LvScreen> {
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');
  int? _filterAuftragId;

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(lvListProvider(_filterAuftragId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.list_alt_outlined,
          title: 'Leistungsverzeichnisse',
          subtitle:
              'Kostenschätzungen und Ausschreibungen — mit GAEB-Export und Akten-Bezug',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neues LV'),
              onPressed: () => _neuesLv(context),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.bookmarks_outlined),
              label: const Text('Katalog'),
              onPressed: () => context.go('/lv/katalog'),
            ),
          ],
          filters: [
            SizedBox(
              width: 320,
              child: AuftragPickerField(
                auftragId: _filterAuftragId,
                onChanged: (v) =>
                    setState(() => _filterAuftragId = v),
                label: 'Akten-Filter',
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: list.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (rows) {
              if (rows.isEmpty) {
                return const EmptyListState(
                  icon: Icons.list_alt_outlined,
                  title: 'Keine LVs',
                  hint: 'Lege ein neues Leistungsverzeichnis an.',
                );
              }
              return DataTableCard(
                child: DataTable(
                  showCheckboxColumn: false,
                  columns: const [
                    DataColumn(label: Text('Datum')),
                    DataColumn(label: Text('Bezeichnung')),
                    DataColumn(label: Text('LV-Nr.')),
                    DataColumn(label: Text('Status')),
                  ],
                  rows: [
                    for (final r in rows)
                      DataRow(
                        onSelectChanged: (_) =>
                            context.go('/lv/${r.id}'),
                        cells: [
                          DataCell(Text(_dateFmt.format(r.datum))),
                          DataCell(Text(r.bezeichnung)),
                          DataCell(Text(r.nummer ?? '')),
                          DataCell(Text(r.status)),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _neuesLv(BuildContext context) async {
    final id = await showLvAnlegenDialog(context, auftragId: _filterAuftragId);
    if (id != null && context.mounted) context.go('/lv/$id');
  }
}

/// Kleiner Anlege-Dialog: Bezeichnung + Akte + LV-Nr. → erzeugt den
/// LV-Datensatz und liefert die ID.
Future<int?> showLvAnlegenDialog(
  BuildContext context, {
  int? auftragId,
}) async {
  return showDialog<int?>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _LvAnlegenDialog(initialAuftragId: auftragId),
  );
}

class _LvAnlegenDialog extends ConsumerStatefulWidget {
  const _LvAnlegenDialog({this.initialAuftragId});
  final int? initialAuftragId;

  @override
  ConsumerState<_LvAnlegenDialog> createState() =>
      _LvAnlegenDialogState();
}

class _LvAnlegenDialogState extends ConsumerState<_LvAnlegenDialog> {
  final _bezeichnung = TextEditingController();
  final _untertitel = TextEditingController();
  final _nummer = TextEditingController();
  int? _auftragId;
  DateTime _datum = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _auftragId = widget.initialAuftragId;
  }

  @override
  void dispose() {
    _bezeichnung.dispose();
    _untertitel.dispose();
    _nummer.dispose();
    super.dispose();
  }

  Future<void> _anlegen() async {
    if (_bezeichnung.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final id = await ref.read(lvRepositoryProvider).upsertKopf(
            LvKopfCompanion.insert(
              bezeichnung: _bezeichnung.text.trim(),
              untertitel: Value(_untertitel.text.trim().isEmpty
                  ? null
                  : _untertitel.text.trim()),
              nummer: Value(_nummer.text.trim().isEmpty
                  ? null
                  : _nummer.text.trim()),
              auftragId: Value(_auftragId),
              datum: Value(_datum),
            ),
          );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(id);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Neues Leistungsverzeichnis'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LabeledField(
              'Bezeichnung',
              TextFormField(
                controller: _bezeichnung,
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: 'z. B. Sanierung Kellerfeuchte AW-0001'),
              ),
            ),
            const SizedBox(height: 12),
            LabeledField(
              'Untertitel / Vorbemerkung',
              TextFormField(
                controller: _untertitel,
                minLines: 2,
                maxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AuftragPickerField(
                    auftragId: _auftragId,
                    onChanged: (v) => setState(() => _auftragId = v),
                    label: 'Akte (optional)',
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 160,
                  child: DateField(
                    label: 'LV-Datum',
                    value: _datum,
                    onChanged: (d) =>
                        setState(() => _datum = d ?? DateTime.now()),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 140,
                  child: LabeledField(
                    'LV-Nr.',
                    TextFormField(controller: _nummer),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context, rootNavigator: true).pop(null),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _saving ? null : _anlegen,
          child: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Anlegen'),
        ),
      ],
    );
  }
}
