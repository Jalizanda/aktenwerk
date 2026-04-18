import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../features/kalkulation/artikel/artikel_repository.dart';
import 'position_model.dart';

/// Editierbare Positions-Tabelle mit Artikel-Import und Summen-Zeile.
class PositionsEditor extends ConsumerStatefulWidget {
  const PositionsEditor({
    super.key,
    required this.positions,
    required this.onChanged,
  });

  final List<Position> positions;
  final ValueChanged<List<Position>> onChanged;

  @override
  ConsumerState<PositionsEditor> createState() => _PositionsEditorState();
}

class _PositionsEditorState extends ConsumerState<PositionsEditor> {
  late List<Position> _items;
  static final _money = NumberFormat.currency(locale: 'de', symbol: '€');

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.positions);
  }

  @override
  void didUpdateWidget(covariant PositionsEditor old) {
    super.didUpdateWidget(old);
    if (old.positions != widget.positions) {
      _items = List.of(widget.positions);
    }
  }

  void _update() {
    widget.onChanged(List.unmodifiable(_items));
  }

  void _addNeu({Position? from}) {
    setState(() {
      _items.add(from ?? const Position(bezeichnung: 'Neue Position'));
    });
    _update();
  }

  Future<void> _addAusArtikel() async {
    final picked = await showDialog<Position>(
      context: context,
      builder: (_) => const _ArtikelPickerDialog(),
    );
    if (picked != null) {
      setState(() => _items.add(picked));
      _update();
    }
  }

  void _remove(int i) {
    setState(() => _items.removeAt(i));
    _update();
  }

  void _edit(int i, Position p) {
    setState(() => _items[i] = p);
    _update();
  }

  @override
  Widget build(BuildContext context) {
    final totals = PositionsTotals.fromList(_items);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Positionen',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: _addAusArtikel,
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
              label: const Text('Aus Artikel'),
            ),
            TextButton.icon(
              onPressed: () => _addNeu(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Freie Position'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12)),
                ),
                child: const Row(
                  children: [
                    SizedBox(width: 32, child: Text('#')),
                    Expanded(flex: 5, child: Text('Bezeichnung')),
                    SizedBox(
                        width: 70,
                        child: Text('Menge',
                            textAlign: TextAlign.right)),
                    SizedBox(
                        width: 60,
                        child: Text('Einh.',
                            textAlign: TextAlign.right)),
                    SizedBox(
                        width: 90,
                        child: Text('Preis €',
                            textAlign: TextAlign.right)),
                    SizedBox(
                        width: 60,
                        child:
                            Text('USt %', textAlign: TextAlign.right)),
                    SizedBox(
                        width: 100,
                        child: Text('Summe €',
                            textAlign: TextAlign.right)),
                    SizedBox(width: 40),
                  ],
                ),
              ),
              if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Noch keine Positionen',
                    style: TextStyle(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (var i = 0; i < _items.length; i++)
                  _PositionRow(
                    index: i,
                    position: _items[i],
                    onChanged: (p) => _edit(i, p),
                    onRemove: () => _remove(i),
                  ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    const Spacer(),
                    _Total(label: 'Netto', value: _money.format(totals.netto)),
                    const SizedBox(width: 24),
                    _Total(label: 'USt', value: _money.format(totals.ust)),
                    const SizedBox(width: 24),
                    _Total(
                        label: 'Brutto',
                        value: _money.format(totals.brutto),
                        bold: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PositionRow extends StatefulWidget {
  const _PositionRow({
    required this.index,
    required this.position,
    required this.onChanged,
    required this.onRemove,
  });
  final int index;
  final Position position;
  final ValueChanged<Position> onChanged;
  final VoidCallback onRemove;

  @override
  State<_PositionRow> createState() => _PositionRowState();
}

class _PositionRowState extends State<_PositionRow> {
  late final _bez = TextEditingController(text: widget.position.bezeichnung);
  late final _menge =
      TextEditingController(text: widget.position.menge.toStringAsFixed(2));
  late final _einheit =
      TextEditingController(text: widget.position.einheit);
  late final _preis = TextEditingController(
      text: widget.position.einzelpreis.toStringAsFixed(2));
  late final _ust =
      TextEditingController(text: widget.position.ustSatz.toStringAsFixed(0));

  @override
  void dispose() {
    for (final c in [_bez, _menge, _einheit, _preis, _ust]) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() {
    widget.onChanged(Position(
      bezeichnung: _bez.text,
      menge: double.tryParse(_menge.text.replaceAll(',', '.')) ?? 0,
      einheit: _einheit.text,
      einzelpreis: double.tryParse(_preis.text.replaceAll(',', '.')) ?? 0,
      ustSatz: double.tryParse(_ust.text.replaceAll(',', '.')) ?? 19,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final summe = widget.position.nettoBetrag;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 32,
              child: Text('${widget.index + 1}',
                  style: Theme.of(context).textTheme.bodySmall)),
          Expanded(
            flex: 5,
            child: TextField(
              controller: _bez,
              decoration: const InputDecoration(
                  isDense: true, border: InputBorder.none),
              onChanged: (_) => _emit(),
            ),
          ),
          SizedBox(
            width: 70,
            child: TextField(
              controller: _menge,
              textAlign: TextAlign.right,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  isDense: true, border: InputBorder.none),
              onChanged: (_) => _emit(),
            ),
          ),
          SizedBox(
            width: 60,
            child: TextField(
              controller: _einheit,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                  isDense: true, border: InputBorder.none),
              onChanged: (_) => _emit(),
            ),
          ),
          SizedBox(
            width: 90,
            child: TextField(
              controller: _preis,
              textAlign: TextAlign.right,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  isDense: true, border: InputBorder.none),
              onChanged: (_) => _emit(),
            ),
          ),
          SizedBox(
            width: 60,
            child: TextField(
              controller: _ust,
              textAlign: TextAlign.right,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  isDense: true, border: InputBorder.none),
              onChanged: (_) => _emit(),
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              summe.toStringAsFixed(2),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: 40,
            child: IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: 'Position entfernen',
              onPressed: widget.onRemove,
            ),
          ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total(
      {required this.label, required this.value, this.bold = false});
  final String label;
  final String value;
  final bool bold;
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      fontSize: bold ? 16 : 14,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
        Text(value, style: style),
      ],
    );
  }
}

class _ArtikelPickerDialog extends ConsumerStatefulWidget {
  const _ArtikelPickerDialog();
  @override
  ConsumerState<_ArtikelPickerDialog> createState() =>
      _ArtikelPickerDialogState();
}

class _ArtikelPickerDialogState
    extends ConsumerState<_ArtikelPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(artikelListProvider);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Text('Artikel auswählen',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Suche Artikel',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Fehler: $e')),
                data: (items) {
                  final filtered = _query.isEmpty
                      ? items
                      : items
                          .where((a) =>
                              a.bezeichnung
                                  .toLowerCase()
                                  .contains(_query.toLowerCase()) ||
                              (a.nummer ?? '').toLowerCase().contains(
                                  _query.toLowerCase()))
                          .toList();
                  if (filtered.isEmpty) {
                    return const Center(child: Text('Keine Treffer'));
                  }
                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final a = filtered[i];
                      return ListTile(
                        dense: true,
                        title: Text(a.bezeichnung),
                        subtitle: Text([
                          if (a.nummer != null) 'Nr. ${a.nummer}',
                          if (a.kategorie != null) a.kategorie!,
                          if (a.einheit != null) a.einheit!,
                        ].join(' · ')),
                        trailing: Text(
                            '${a.einzelpreis.toStringAsFixed(2)} €'),
                        onTap: () => Navigator.pop(
                          context,
                          Position(
                            bezeichnung: a.bezeichnung,
                            menge: 1,
                            einheit: a.einheit ?? '',
                            einzelpreis: a.einzelpreis,
                            ustSatz: a.ustSatz,
                          ),
                        ),
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
