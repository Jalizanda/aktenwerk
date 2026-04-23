import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../shared/widgets/badges.dart';
import '../../../shared/widgets/form_widgets.dart';
import 'maengel_repository.dart';

/// Mängel-Register je Akte mit Priorität nach DIN 4426 (A/B/C).
class MaengelTab extends ConsumerWidget {
  const MaengelTab({super.key, required this.auftragId});
  final int auftragId;

  static final _money = NumberFormat.currency(
      locale: 'de_DE', symbol: '€', decimalDigits: 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(maengelByAkteProvider(auftragId));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Mängel-Register',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _open(context, ref),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Mangel'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyListState(
                    icon: Icons.report_gmailerrorred_outlined,
                    title: 'Keine Mängel erfasst',
                    hint:
                        'Lege Mängel mit Bauteil, Ursache, Folge und Priorität (A/B/C nach DIN 4426) an.',
                  );
                }
                final summeA = items
                    .where((m) => m.prioritaet == 'A')
                    .fold<double>(0, (a, m) => a + (m.aufwand ?? 0));
                final summeB = items
                    .where((m) => m.prioritaet == 'B')
                    .fold<double>(0, (a, m) => a + (m.aufwand ?? 0));
                final summeC = items
                    .where((m) => m.prioritaet == 'C')
                    .fold<double>(0, (a, m) => a + (m.aufwand ?? 0));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _KpiPill(
                            label: 'Priorität A (unverzüglich)',
                            wert: _money.format(summeA),
                            farbe: BadgeColors.redFg),
                        _KpiPill(
                            label: 'Priorität B (mittelfristig)',
                            wert: _money.format(summeB),
                            farbe: BadgeColors.amberFg),
                        _KpiPill(
                            label: 'Priorität C (langfristig)',
                            wert: _money.format(summeC),
                            farbe: BadgeColors.greenFg),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          showCheckboxColumn: false,
                          columns: const [
                            DataColumn(label: Text('Nr.')),
                            DataColumn(label: Text('Prio')),
                            DataColumn(label: Text('Bauteil')),
                            DataColumn(label: Text('Beschreibung')),
                            DataColumn(label: Text('Ursache')),
                            DataColumn(label: Text('Aufwand €')),
                            DataColumn(label: Text('')),
                          ],
                          rows: [
                            for (final m in items)
                              DataRow(
                                onSelectChanged: (_) =>
                                    _open(context, ref, m),
                                cells: [
                                  DataCell(Text(m.nummer ?? '',
                                      style: const TextStyle(
                                          fontFamily: 'monospace'))),
                                  DataCell(_PrioChip(prio: m.prioritaet)),
                                  DataCell(Text(m.bauteil ?? '')),
                                  DataCell(SizedBox(
                                    width: 320,
                                    child: Text(m.beschreibung,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                  )),
                                  DataCell(SizedBox(
                                    width: 200,
                                    child: Text(m.ursache ?? '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                  )),
                                  DataCell(Text(m.aufwand == null
                                      ? ''
                                      : m.aufwand!.toStringAsFixed(2))),
                                  DataCell(IconButton(
                                    icon: const Icon(
                                        Icons.delete_outline,
                                        size: 18),
                                    onPressed: () => ref
                                        .read(maengelRepositoryProvider)
                                        .delete(m.id),
                                  )),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref,
      [MaengelData? m]) async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) =>
          _MangelEditor(auftragId: auftragId, eintrag: m),
    );
  }
}

class _KpiPill extends StatelessWidget {
  const _KpiPill({required this.label, required this.wert, required this.farbe});
  final String label;
  final String wert;
  final Color farbe;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.slate200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: farbe, borderRadius: BorderRadius.circular(5))),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 10),
          Text(wert,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: farbe)),
        ],
      ),
    );
  }
}

class _PrioChip extends StatelessWidget {
  const _PrioChip({required this.prio});
  final String prio;
  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    switch (prio) {
      case 'A':
        bg = BadgeColors.redBg;
        fg = BadgeColors.redFg;
        break;
      case 'C':
        bg = BadgeColors.greenBg;
        fg = BadgeColors.greenFg;
        break;
      default:
        bg = BadgeColors.amberBg;
        fg = BadgeColors.amberFg;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(prio,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

class _MangelEditor extends ConsumerStatefulWidget {
  const _MangelEditor({required this.auftragId, this.eintrag});
  final int auftragId;
  final MaengelData? eintrag;
  @override
  ConsumerState<_MangelEditor> createState() => _MangelEditorState();
}

class _MangelEditorState extends ConsumerState<_MangelEditor> {
  late final _nummer =
      TextEditingController(text: widget.eintrag?.nummer ?? '');
  late final _bauteil =
      TextEditingController(text: widget.eintrag?.bauteil ?? '');
  late final _beschreibung =
      TextEditingController(text: widget.eintrag?.beschreibung ?? '');
  late final _ursache =
      TextEditingController(text: widget.eintrag?.ursache ?? '');
  late final _folge =
      TextEditingController(text: widget.eintrag?.folge ?? '');
  late final _aufwand = TextEditingController(
      text: widget.eintrag?.aufwand?.toStringAsFixed(2) ?? '');
  late String _prio = widget.eintrag?.prioritaet ?? 'B';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.eintrag == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final nr = await ref
            .read(maengelRepositoryProvider)
            .nextNummer(widget.auftragId);
        if (mounted) _nummer.text = nr;
      });
    }
  }

  @override
  void dispose() {
    _nummer.dispose();
    _bauteil.dispose();
    _beschreibung.dispose();
    _ursache.dispose();
    _folge.dispose();
    _aufwand.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.eintrag != null;

  Future<void> _save() async {
    if (_beschreibung.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(maengelRepositoryProvider).upsert(
            MaengelCompanion(
              id: _isEdit
                  ? Value(widget.eintrag!.id)
                  : const Value.absent(),
              auftragId: Value(widget.auftragId),
              nummer: Value(_nummer.text.trim().isEmpty
                  ? null
                  : _nummer.text.trim()),
              bauteil: Value(_bauteil.text.trim().isEmpty
                  ? null
                  : _bauteil.text.trim()),
              beschreibung: Value(_beschreibung.text.trim()),
              ursache: Value(_ursache.text.trim().isEmpty
                  ? null
                  : _ursache.text.trim()),
              folge: Value(_folge.text.trim().isEmpty
                  ? null
                  : _folge.text.trim()),
              prioritaet: Value(_prio),
              aufwand: Value(double.tryParse(
                  _aufwand.text.replaceAll(',', '.').trim())),
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
      title: _isEdit ? 'Mangel bearbeiten' : 'Neuer Mangel',
      icon: Icons.report_gmailerrorred_outlined,
      maxWidth: 680,
      maxHeight: 720,
      saving: _saving,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(maengelRepositoryProvider)
              .delete(widget.eintrag!.id)
          : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row3(
              a: LabeledField(
                  'Nummer', TextFormField(controller: _nummer)),
              b: LabeledField(
                'Priorität',
                DropdownButtonFormField<String>(
                  initialValue: _prio,
                  isDense: true,
                  items: const [
                    DropdownMenuItem(
                        value: 'A', child: Text('A — unverzüglich')),
                    DropdownMenuItem(
                        value: 'B', child: Text('B — mittelfristig')),
                    DropdownMenuItem(
                        value: 'C', child: Text('C — langfristig')),
                  ],
                  onChanged: (v) => setState(() => _prio = v ?? 'B'),
                ),
              ),
              c: LabeledField(
                'Aufwand (€, netto)',
                TextFormField(
                  controller: _aufwand,
                  keyboardType: TextInputType.number,
                ),
              ),
            ),
            const SizedBox(height: 12),
            LabeledField(
                'Bauteil / Ort', TextFormField(controller: _bauteil)),
            const SizedBox(height: 12),
            LabeledField(
              'Beschreibung',
              TextFormField(
                  controller: _beschreibung, minLines: 2, maxLines: 4),
            ),
            const SizedBox(height: 12),
            LabeledField(
              'Vermutete Ursache',
              TextFormField(
                  controller: _ursache, minLines: 2, maxLines: 3),
            ),
            const SizedBox(height: 12),
            LabeledField(
              'Folge bei Nicht-Beseitigung',
              TextFormField(
                  controller: _folge, minLines: 2, maxLines: 3),
            ),
          ],
        ),
      ),
    );
  }
}
