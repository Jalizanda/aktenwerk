import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/formel_text_field.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'artikel_repository.dart';

/// Eine Kalkulations-Unterposition eines Artikels.
class _Unterposition {
  String bezeichnung;
  double menge;
  String einheit;
  double einzelpreis;
  _Unterposition({
    this.bezeichnung = '',
    this.menge = 1,
    this.einheit = 'h',
    this.einzelpreis = 0,
  });

  double get summe => menge * einzelpreis;

  Map<String, dynamic> toJson() => {
        'bezeichnung': bezeichnung,
        'menge': menge,
        'einheit': einheit,
        'einzelpreis': einzelpreis,
      };

  static _Unterposition fromJson(Map<String, dynamic> m) => _Unterposition(
        bezeichnung: (m['bezeichnung'] ?? m['bez'] ?? '').toString(),
        menge: ((m['menge'] as num?) ?? 0).toDouble(),
        einheit: (m['einheit'] ?? '').toString(),
        einzelpreis:
            ((m['einzelpreis'] as num?) ?? (m['ep'] as num?) ?? 0).toDouble(),
      );
}

List<_Unterposition> _unterFromJson(String? raw) {
  if (raw == null || raw.trim().isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(_Unterposition.fromJson)
          .toList();
    }
  } catch (_) {}
  return [];
}

String _unterToJson(List<_Unterposition> list) =>
    jsonEncode(list.map((p) => p.toJson()).toList());

final _numberFmt =
    NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

class ArtikelScreen extends ConsumerWidget {
  const ArtikelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(artikelListProvider);
    final filter = ref.watch(artikelFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.inventory_2_outlined,
          title: 'Artikel / Leistungen',
          subtitle: 'Leistungskatalog für Angebote und Rechnungen',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neuer Artikel'),
              onPressed: () => _showForm(context, ref),
            ),
          ],
          searchHint: 'Suche Nr., Bezeichnung, Kategorie …',
          onSearchChanged: (v) => ref
              .read(artikelFilterProvider.notifier)
              .update((f) => f.copyWith(query: v)),
          filters: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(
                value: filter.nurAktiv,
                onChanged: (v) => ref
                    .read(artikelFilterProvider.notifier)
                    .update((f) => f.copyWith(nurAktiv: v ?? true)),
              ),
              const Text('Nur aktive'),
            ]),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) => items.isEmpty
                ? const EmptyListState(
                    icon: Icons.inventory_2_outlined,
                    title: 'Noch keine Artikel',
                    hint: 'Lege oben rechts deinen ersten Artikel an.')
                : Column(
                    children: [
                      _ArtikelKpiRow(items: items),
                      Expanded(
                        child: DataTableCard(
                          child: DataTable(
                            showCheckboxColumn: false,
                            headingRowColor: WidgetStateProperty.all(
                              Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                            ),
                            dataRowMaxHeight: 72,
                            columns: const [
                              DataColumn(label: Text('Nr.')),
                              DataColumn(label: Text('Kurztext / Langtext')),
                              DataColumn(label: Text('Kategorie')),
                              DataColumn(label: Text('Einheit')),
                              DataColumn(label: Text('Preis'), numeric: true),
                              DataColumn(label: Text('USt %'), numeric: true),
                              DataColumn(label: Text('Pos.'), numeric: true),
                              DataColumn(label: Text('')),
                            ],
                            rows: [
                              for (final a in items)
                                DataRow(
                                  onSelectChanged: (_) =>
                                      _showForm(context, ref, a),
                                  cells: [
                                    DataCell(Text(a.nummer ?? '',
                                        style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11.5))),
                                    DataCell(SizedBox(
                                      width: 340,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            a.bezeichnung,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if ((a.beschreibung ?? '').isNotEmpty)
                                            Text(
                                              a.beschreibung!,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                    )),
                                    DataCell(Text(a.kategorie ?? '')),
                                    DataCell(Text(a.einheit ?? '')),
                                    DataCell(Text(
                                        _numberFmt.format(a.einzelpreis))),
                                    DataCell(Text(
                                        a.ustSatz.toStringAsFixed(0))),
                                    DataCell(Text(_unterFromJson(
                                            a.kalkulationJson)
                                        .length
                                        .toString())),
                                    DataCell(IconButton(
                                      tooltip: 'Löschen',
                                      icon: const Icon(
                                          Icons.delete_outline,
                                          size: 20),
                                      onPressed: () => _confirmDelete(
                                          context, ref, a),
                                    )),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _showForm(BuildContext context, WidgetRef ref,
      [ArtikelData? artikel]) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => _ArtikelFormDialog(artikel: artikel),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, ArtikelData a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Artikel löschen?'),
        content: Text('«${a.bezeichnung}» wird dauerhaft gelöscht.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
              child: const Text('Abbrechen')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(artikelRepositoryProvider).delete(a.id);
    }
  }
}

class _ArtikelFormDialog extends ConsumerStatefulWidget {
  const _ArtikelFormDialog({this.artikel});
  final ArtikelData? artikel;
  @override
  ConsumerState<_ArtikelFormDialog> createState() =>
      _ArtikelFormDialogState();
}

class _ArtikelFormDialogState extends ConsumerState<_ArtikelFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nr = _tec(widget.artikel?.nummer);
  late final _bez = _tec(widget.artikel?.bezeichnung);
  late final _beschreibung = _tec(widget.artikel?.beschreibung);
  late final _kategorie = _tec(widget.artikel?.kategorie);
  late final _tags = _tec(widget.artikel?.tags);
  late final _einheit = _tec(widget.artikel?.einheit);
  late final _preis = _tec(widget.artikel?.einzelpreis.toStringAsFixed(2));
  late final _aufschlag =
      _tec(widget.artikel?.aufschlag.toStringAsFixed(1));
  late final _standardMenge =
      _tec(widget.artikel?.standardMenge.toStringAsFixed(2));
  late final _ust = _tec(widget.artikel?.ustSatz.toStringAsFixed(0));
  late List<_Unterposition> _unter;
  bool _aktiv = true;
  bool _saving = false;

  static final _money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

  TextEditingController _tec(String? v) =>
      TextEditingController(text: v ?? '');

  @override
  void initState() {
    super.initState();
    _aktiv = widget.artikel?.aktiv ?? true;
    _unter = _unterFromJson(widget.artikel?.kalkulationJson);
  }

  double get _kalkSumme =>
      _unter.fold<double>(0, (s, p) => s + p.summe);

  void _addUnterposition() {
    setState(() => _unter.add(_Unterposition()));
  }

  void _removeUnterposition(int i) {
    setState(() => _unter.removeAt(i));
  }

  void _uebernehmeKalkSummeAlsPreis() {
    final auf =
        double.tryParse(_aufschlag.text.replaceAll(',', '.')) ?? 0;
    final preis = _kalkSumme * (1 + auf / 100);
    setState(() => _preis.text = preis.toStringAsFixed(2));
  }

  @override
  void dispose() {
    for (final c in [
      _nr, _bez, _beschreibung, _kategorie, _tags,
      _einheit, _preis, _aufschlag, _standardMenge, _ust,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.artikel != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final preis = double.tryParse(_preis.text.replaceAll(',', '.')) ?? 0;
    final ust = double.tryParse(_ust.text.replaceAll(',', '.')) ?? 19;
    final aufschlag =
        double.tryParse(_aufschlag.text.replaceAll(',', '.')) ?? 0;
    final standardMenge =
        double.tryParse(_standardMenge.text.replaceAll(',', '.')) ?? 1;
    final companion = ArtikelCompanion(
      id: _isEdit ? Value(widget.artikel!.id) : const Value.absent(),
      nummer: _nt(_nr),
      bezeichnung: Value(_bez.text.trim()),
      beschreibung: _nt(_beschreibung),
      kategorie: _nt(_kategorie),
      tags: _nt(_tags),
      einheit: _nt(_einheit),
      einzelpreis: Value(preis),
      aufschlag: Value(aufschlag),
      standardMenge: Value(standardMenge),
      ustSatz: Value(ust),
      aktiv: Value(_aktiv),
      kalkulationJson:
          Value(_unter.isEmpty ? null : _unterToJson(_unter)),
    );
    try {
      await ref.read(artikelRepositoryProvider).upsert(companion);
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
      title: _isEdit ? 'Artikel bearbeiten' : 'Neuer Artikel',
      icon: Icons.inventory_2_outlined,
      maxWidth: 900,
      maxHeight: 820,
      saving: _saving,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(artikelRepositoryProvider)
              .delete(widget.artikel!.id)
          : null,
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row2(
                flex: const (1, 3),
                left: LabeledField('Nummer', TextFormField(controller: _nr)),
                right: LabeledField(
                  'Bezeichnung',
                  TextFormField(
                    controller: _bez,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Erforderlich' : null,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Beschreibung',
                TextFormField(
                    controller: _beschreibung,
                    minLines: 2,
                    maxLines: 5),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                    'Kategorie', TextFormField(controller: _kategorie)),
                right: LabeledField('Tags (komma-getrennt)',
                    TextFormField(controller: _tags)),
              ),
              const SizedBox(height: 12),
              Row3(
                a: LabeledField(
                  'Einheit',
                  TextFormField(controller: _einheit),
                ),
                b: LabeledField(
                  'Standard-Menge',
                  FormelTextField(
                    controller: _standardMenge,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                c: LabeledField(
                  'Aufschlag (%)',
                  TextFormField(
                    controller: _aufschlag,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                  'Einzelpreis (€)',
                  FormelTextField(
                    controller: _preis,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                right: LabeledField(
                  'USt-Satz (%)',
                  TextFormField(
                    controller: _ust,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Divider(),
              Row(
                children: [
                  Text('Kalkulation aus Leistungspositionen',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(width: 8),
                  Text('(oder direkten Einzelpreis oben setzen)',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Leistungsposition'),
                    onPressed: _addUnterposition,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _UnterpositionenTabelle(
                positionen: _unter,
                onChanged: () => setState(() {}),
                onRemove: _removeUnterposition,
                money: _money,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Kalkulationssumme: ',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(_money.format(_kalkSumme),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()])),
                  const Spacer(),
                  if (_unter.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.price_change_outlined,
                          size: 16),
                      label: const Text(
                          'Summe als Einzelpreis übernehmen'),
                      onPressed: _uebernehmeKalkSummeAlsPreis,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(children: [
                Checkbox(
                    value: _aktiv,
                    onChanged: (v) => setState(() => _aktiv = v ?? true)),
                const Text('Aktiv'),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// KPI-Zeile über der Artikel-Liste: Gesamtzahl + Split nach Kategorie.
class _ArtikelKpiRow extends StatelessWidget {
  const _ArtikelKpiRow({required this.items});
  final List<ArtikelData> items;

  @override
  Widget build(BuildContext context) {
    final byKat = <String, int>{};
    for (final a in items) {
      final k = (a.kategorie ?? '').trim();
      final key = k.isEmpty ? '(ohne Kategorie)' : k;
      byKat.update(key, (v) => v + 1, ifAbsent: () => 1);
    }
    final sorted = byKat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalPreis =
        items.fold<double>(0, (s, a) => s + a.einzelpreis);
    final avgPreis = items.isEmpty ? 0.0 : totalPreis / items.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          _Stat(
              icon: Icons.list_alt_outlined,
              label: 'Artikel gesamt',
              value: items.length.toString()),
          _Stat(
              icon: Icons.euro,
              label: 'Durchschnittspreis',
              value: _numberFmt.format(avgPreis)),
          for (final e in sorted.take(6))
            _Stat(
              icon: Icons.label_outline,
              label: e.key,
              value: e.value.toString(),
              muted: true,
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    this.muted = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool muted;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: muted
            ? Theme.of(context).colorScheme.surfaceContainerLow
            : Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 16,
              color: muted
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.onPrimaryContainer),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                fontSize: 11.5,
                color: muted
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Theme.of(context).colorScheme.onPrimaryContainer,
              )),
          const SizedBox(width: 6),
          Text(value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: muted
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onPrimaryContainer,
              )),
        ],
      ),
    );
  }
}

/// Tabelle mit editierbaren Leistungspositionen (Bezeichnung · Menge ·
/// Einheit · EP · Betrag · Löschen).
class _UnterpositionenTabelle extends StatelessWidget {
  const _UnterpositionenTabelle({
    required this.positionen,
    required this.onChanged,
    required this.onRemove,
    required this.money,
  });
  final List<_Unterposition> positionen;
  final VoidCallback onChanged;
  final void Function(int index) onRemove;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    if (positionen.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Text(
          'Keine Leistungspositionen — reiner Pauschal-Artikel.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 5, child: Text('Leistung',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700))),
                SizedBox(
                    width: 80,
                    child: Text('Menge',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700))),
                SizedBox(width: 8),
                SizedBox(
                    width: 60,
                    child: Text('Einh.',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700))),
                SizedBox(
                    width: 90,
                    child: Text('EP €',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700))),
                SizedBox(width: 8),
                SizedBox(
                    width: 90,
                    child: Text('Betrag',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700))),
                SizedBox(width: 36),
              ],
            ),
          ),
          for (var i = 0; i < positionen.length; i++)
            _UnterpositionZeile(
              key: ValueKey(positionen[i]),
              pos: positionen[i],
              onChanged: onChanged,
              onRemove: () => onRemove(i),
              money: money,
            ),
        ],
      ),
    );
  }
}

class _UnterpositionZeile extends StatefulWidget {
  const _UnterpositionZeile({
    super.key,
    required this.pos,
    required this.onChanged,
    required this.onRemove,
    required this.money,
  });
  final _Unterposition pos;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final NumberFormat money;

  @override
  State<_UnterpositionZeile> createState() => _UnterpositionZeileState();
}

class _UnterpositionZeileState extends State<_UnterpositionZeile> {
  late final _bez = TextEditingController(text: widget.pos.bezeichnung);
  late final _menge =
      TextEditingController(text: widget.pos.menge.toString());
  late final _einheit = TextEditingController(text: widget.pos.einheit);
  late final _ep =
      TextEditingController(text: widget.pos.einzelpreis.toString());

  @override
  void dispose() {
    for (final c in [_bez, _menge, _einheit, _ep]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: TextField(
              controller: _bez,
              decoration: const InputDecoration(
                  isDense: true, border: OutlineInputBorder()),
              onChanged: (v) {
                widget.pos.bezeichnung = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 80,
            child: FormelTextField(
              controller: _menge,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              decoration: const InputDecoration(
                  isDense: true, border: OutlineInputBorder()),
              onChanged: (v) {
                widget.pos.menge = parseMengeOrFormel(v);
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 60,
            child: TextField(
              controller: _einheit,
              decoration: const InputDecoration(
                  isDense: true, border: OutlineInputBorder()),
              onChanged: (v) {
                widget.pos.einheit = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 90,
            child: FormelTextField(
              controller: _ep,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              decoration: const InputDecoration(
                  isDense: true, border: OutlineInputBorder()),
              onChanged: (v) {
                widget.pos.einzelpreis = parseMengeOrFormel(v);
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 90,
            child: Text(
              widget.money.format(widget.pos.summe),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: Theme.of(context).colorScheme.error,
            onPressed: widget.onRemove,
          ),
        ],
      ),
    );
  }
}
