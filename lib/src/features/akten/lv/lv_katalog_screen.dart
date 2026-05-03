import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'din276_service.dart';
import 'lv_repository.dart';

/// Verwaltungs-Screen für den eigenen Positions-Katalog. Liste mit Suche,
/// Erstellen/Bearbeiten/Löschen. Aus dem LV-Editor heraus wird der
/// Picker-Dialog verwendet — hier geht's um die Pflege des Katalogs.
class LvKatalogScreen extends ConsumerStatefulWidget {
  const LvKatalogScreen({super.key});

  @override
  ConsumerState<LvKatalogScreen> createState() => _LvKatalogScreenState();
}

class _LvKatalogScreenState extends ConsumerState<LvKatalogScreen> {
  static final _money = NumberFormat.currency(
      locale: 'de_DE', symbol: '€', decimalDigits: 2);
  static final _dateFmt = DateFormat('MM/yyyy', 'de');
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final liste = ref.watch(lvKatalogProvider(_query));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.bookmarks_outlined,
          title: 'Positions-Katalog',
          subtitle:
              'Wiederverwendbare Leistungstexte und Marktpreise — wächst organisch beim Erstellen von LVs.',
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Standard-Katalog importieren'),
              onPressed: () => _importStandard(context),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neue Katalog-Position'),
              onPressed: () => _editor(context, null),
            ),
          ],
          searchHint: 'Suche Kurztext, Gewerk, Tags …',
          onSearchChanged: (v) => setState(() => _query = v),
        ),
        const Divider(height: 1),
        Expanded(
          child: liste.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (rows) {
              if (rows.isEmpty) {
                return EmptyListState(
                  icon: Icons.bookmarks_outlined,
                  title: _query.isEmpty
                      ? 'Katalog ist leer'
                      : 'Keine Treffer für „$_query"',
                  hint: _query.isEmpty
                      ? 'Beim Anlegen einer LV-Position kannst du sie '
                          'mit „in den Katalog übernehmen" hier hinzufügen.'
                      : null,
                );
              }
              return DataTableCard(
                child: DataTable(
                  showCheckboxColumn: false,
                  columns: const [
                    DataColumn(label: Text('Kurztext')),
                    DataColumn(label: Text('Gewerk')),
                    DataColumn(label: Text('KG')),
                    DataColumn(label: Text('Einheit')),
                    DataColumn(label: Text('EP'), numeric: true),
                    DataColumn(label: Text('Stand')),
                    DataColumn(label: Text('Verwendet'), numeric: true),
                    DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (final r in rows)
                      DataRow(
                        onSelectChanged: (_) => _editor(context, r),
                        cells: [
                          DataCell(Text(r.kurztext,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                          DataCell(Text(r.gewerk ?? '')),
                          DataCell(Text(r.din276 ?? '')),
                          DataCell(Text(r.einheit ?? '')),
                          DataCell(Text(r.einzelpreis == null
                              ? ''
                              : _money.format(r.einzelpreis))),
                          DataCell(Text(r.preisstand == null
                              ? ''
                              : _dateFmt.format(r.preisstand!))),
                          DataCell(Text('${r.verwendungsZaehler}')),
                          DataCell(IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 18),
                            tooltip: 'Löschen',
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text(
                                      'Katalog-Position löschen?'),
                                  content: Text(
                                      'Position „${r.kurztext}" wird '
                                      'aus dem Katalog entfernt. '
                                      'Bestehende LV-Positionen bleiben '
                                      'erhalten.'),
                                  actions: [
                                    TextButton(
                                        onPressed: () => Navigator.pop(
                                            context, false),
                                        child:
                                            const Text('Abbrechen')),
                                    FilledButton(
                                        style: FilledButton.styleFrom(
                                            backgroundColor: Colors.red),
                                        onPressed: () => Navigator.pop(
                                            context, true),
                                        child: const Text('Löschen')),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                await ref
                                    .read(lvRepositoryProvider)
                                    .deleteKatalog(r.id);
                              }
                            },
                          )),
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

  Future<void> _editor(BuildContext context, LvKatalogData? eintrag) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _KatalogEditorDialog(eintrag: eintrag),
    );
  }

  Future<void> _importStandard(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_download_outlined, size: 22),
                    const SizedBox(width: 10),
                    Text('Standard-Katalog importieren?',
                        style: Theme.of(ctx).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                    'Aktenwerk liefert einen Sanierungs-Standard-Katalog mit ca. '
                    '200 Positionen aus 17 Gewerken (Erdarbeiten, Abdichtung, '
                    'Wärmedämmung, Mauerwerk, Putz, Maler, Trockenbau, Fenster/'
                    'Türen, Dach, Sanitär, Heizung, Lüftung, Elektro, Boden, '
                    'Schadstoff, Außenanlagen, Baunebenkosten) mit Marktpreisen '
                    'Stand 2024/2025.\n\n'
                    'Bestehende Katalog-Einträge mit identischem Kurztext werden '
                    'NICHT überschrieben — der Import ist additiv.'),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Abbrechen'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.cloud_download_outlined,
                          size: 16),
                      label: const Text('Importieren'),
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    try {
      final neue =
          await ref.read(lvRepositoryProvider).importStandardKatalog();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '$neue Positionen importiert (Duplikate wurden übersprungen).')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }
}

class _KatalogEditorDialog extends ConsumerStatefulWidget {
  const _KatalogEditorDialog({this.eintrag});
  final LvKatalogData? eintrag;

  @override
  ConsumerState<_KatalogEditorDialog> createState() =>
      _KatalogEditorDialogState();
}

class _KatalogEditorDialogState
    extends ConsumerState<_KatalogEditorDialog> {
  late final _kurztext = TextEditingController(
      text: widget.eintrag?.kurztext ?? '');
  late final _langtext = TextEditingController(
      text: widget.eintrag?.langtext ?? '');
  late final _einheit = TextEditingController(
      text: widget.eintrag?.einheit ?? '');
  late final _ep = TextEditingController(
      text: widget.eintrag?.einzelpreis == null
          ? ''
          : widget.eintrag!.einzelpreis!
              .toStringAsFixed(2)
              .replaceAll('.', ','));
  late final _gewerk = TextEditingController(
      text: widget.eintrag?.gewerk ?? '');
  late final _tags =
      TextEditingController(text: widget.eintrag?.tags ?? '');
  late String? _din276 = widget.eintrag?.din276;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_kurztext, _langtext, _einheit, _ep, _gewerk, _tags]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _speichern() async {
    if (_kurztext.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(lvRepositoryProvider).upsertKatalog(LvKatalogCompanion(
            id: widget.eintrag == null
                ? const Value.absent()
                : Value(widget.eintrag!.id),
            kurztext: Value(_kurztext.text.trim()),
            langtext: Value(_langtext.text.trim().isEmpty
                ? null
                : _langtext.text.trim()),
            einheit: Value(_einheit.text.trim().isEmpty
                ? null
                : _einheit.text.trim()),
            einzelpreis: Value(double.tryParse(
                _ep.text.replaceAll(',', '.').trim())),
            gewerk: Value(_gewerk.text.trim().isEmpty
                ? null
                : _gewerk.text.trim()),
            tags: Value(
                _tags.text.trim().isEmpty ? null : _tags.text.trim()),
            din276:
                Value((_din276 ?? '').isEmpty ? null : _din276),
            quelle: Value(widget.eintrag?.quelle ?? 'eigen'),
            preisstand: Value(widget.eintrag?.preisstand ?? DateTime.now()),
          ));
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.bookmarks_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.eintrag == null
                          ? 'Neue Katalog-Position'
                          : 'Katalog-Position bearbeiten',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LabeledField(
                      'Kurztext',
                      TextFormField(controller: _kurztext, autofocus: true),
                    ),
                    const SizedBox(height: 12),
                    LabeledField(
                      'Langtext (Detail-Beschreibung)',
                      TextFormField(
                        controller: _langtext,
                        minLines: 4,
                        maxLines: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: LabeledField(
                            'Einheit',
                            TextFormField(controller: _einheit),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: LabeledField(
                            'Einzelpreis (€)',
                            TextFormField(
                              controller: _ep,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: LabeledField(
                            'Gewerk',
                            TextFormField(controller: _gewerk),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Din276Dropdown(
                            current: _din276,
                            onChanged: (v) => setState(() => _din276 = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LabeledField(
                      'Tags (Komma-getrennt)',
                      TextFormField(
                        controller: _tags,
                        decoration: const InputDecoration(
                            hintText: 'feuchte, keller, abdichtung'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (widget.eintrag != null)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Löschen'),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.red),
                      onPressed: _saving
                          ? null
                          : () async {
                              await ref
                                  .read(lvRepositoryProvider)
                                  .deleteKatalog(widget.eintrag!.id);
                              if (!mounted) return;
                              Navigator.of(context, rootNavigator: true)
                                  .pop();
                            },
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Speichern'),
                    onPressed: _saving ? null : _speichern,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Din276Dropdown extends ConsumerWidget {
  const _Din276Dropdown({required this.current, required this.onChanged});
  final String? current;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(din276ListProvider);
    return list.when(
      loading: () => LabeledField(
          'DIN 276', const LinearProgressIndicator()),
      error: (e, _) => LabeledField('DIN 276', Text('Fehler: $e')),
      data: (eintraege) => LabeledField(
        'DIN-276-Kostengruppe',
        DropdownButtonFormField<String?>(
          initialValue: current,
          isExpanded: true,
          items: [
            const DropdownMenuItem<String?>(
                value: null, child: Text('— keine —')),
            for (final e in eintraege)
              DropdownMenuItem<String?>(
                value: e.nr,
                child: Text(
                  '${e.ebene == 1 ? "" : (e.ebene == 2 ? "  " : "      ")}${e.label}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
