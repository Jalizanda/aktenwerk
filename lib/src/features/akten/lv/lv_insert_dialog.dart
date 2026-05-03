import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import 'lv_repository.dart';

/// Dialog: aus einem LV der Akte einzelne Positionen wählen und sie
/// als formatierten Plain-Text-Block ins Gutachten (oder anderswo)
/// einfügen lassen. Liefert den fertigen Block-String zurück oder
/// `null` bei Abbruch.
Future<String?> showLvInsertDialog(
  BuildContext context, {
  required int? auftragId,
}) =>
    showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _LvInsertDialog(auftragId: auftragId),
    );

class _LvInsertDialog extends ConsumerStatefulWidget {
  const _LvInsertDialog({required this.auftragId});
  final int? auftragId;

  @override
  ConsumerState<_LvInsertDialog> createState() => _LvInsertDialogState();
}

enum _Format { tabellarisch, aufzaehlung, nurTexte }

class _LvInsertDialogState extends ConsumerState<_LvInsertDialog> {
  static final _money = NumberFormat.currency(
      locale: 'de_DE', symbol: '€', decimalDigits: 2);
  static final _menge = NumberFormat.decimalPattern('de_DE');

  int? _selectedLvId;
  final Set<int> _selectedPositionen = {};
  bool _mitPreisen = true;
  _Format _format = _Format.tabellarisch;

  @override
  Widget build(BuildContext context) {
    final lvs = ref.watch(lvListProvider(widget.auftragId));
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.list_alt_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'LV-Positionen ins Gutachten einfügen',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: lvs.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Fehler: $e')),
                data: (rows) {
                  if (rows.isEmpty) {
                    return _emptyView(
                        'Keine LVs zur Akte gefunden. Lege erst ein LV an.');
                  }
                  return Row(
                    children: [
                      // Linke Spalte: LV-Auswahl
                      SizedBox(
                        width: 280,
                        child: _LvList(
                          lvs: rows,
                          selectedId: _selectedLvId,
                          onSelect: (id) => setState(() {
                            _selectedLvId = id;
                            _selectedPositionen.clear();
                          }),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      // Rechte Spalte: Positionen + Format-Optionen
                      Expanded(
                        child: _selectedLvId == null
                            ? _emptyView(
                                'LV links auswählen, dann Positionen hier ankreuzen.')
                            : _PositionsSelection(
                                lvId: _selectedLvId!,
                                selected: _selectedPositionen,
                                onToggle: (id) => setState(() {
                                  if (_selectedPositionen.contains(id)) {
                                    _selectedPositionen.remove(id);
                                  } else {
                                    _selectedPositionen.add(id);
                                  }
                                }),
                                onSelectAll: (positionen) =>
                                    setState(() {
                                  if (_selectedPositionen.length ==
                                      positionen.length) {
                                    _selectedPositionen.clear();
                                  } else {
                                    _selectedPositionen
                                      ..clear()
                                      ..addAll(positionen.map((p) => p.id));
                                  }
                                }),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            // Format-Optionen + Footer-Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Format: ',
                          style: TextStyle(fontSize: 13)),
                      DropdownButton<_Format>(
                        value: _format,
                        items: const [
                          DropdownMenuItem(
                              value: _Format.tabellarisch,
                              child: Text('Tabellarisch')),
                          DropdownMenuItem(
                              value: _Format.aufzaehlung,
                              child: Text('Aufzählung')),
                          DropdownMenuItem(
                              value: _Format.nurTexte,
                              child: Text('Nur Texte (Fließtext)')),
                        ],
                        onChanged: (v) =>
                            setState(() => _format = v ?? _format),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _mitPreisen,
                        onChanged: (v) =>
                            setState(() => _mitPreisen = v ?? true),
                      ),
                      const Text('mit Preisen'),
                    ],
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Abbrechen'),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(
                        '${_selectedPositionen.length} Positionen einfügen'),
                    onPressed: _selectedPositionen.isEmpty
                        ? null
                        : _einfuegen,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _einfuegen() async {
    final repo = ref.read(lvRepositoryProvider);
    final positionen = await repo.getPositionen(_selectedLvId!);
    final auswahl = positionen
        .where((p) => _selectedPositionen.contains(p.id))
        .toList();
    final block = _formatBlock(auswahl);
    if (!mounted) return;
    Navigator.of(context).pop(block);
  }

  String _formatBlock(List<LvPositionenData> rows) {
    final buf = StringBuffer();
    double summe = 0;

    switch (_format) {
      case _Format.tabellarisch:
        for (final p in rows) {
          if (p.art == 'titel') {
            buf.writeln();
            buf.writeln('${p.oz ?? ""}  ${p.kurztext.toUpperCase()}');
            buf.writeln('-' * 50);
            continue;
          }
          if (p.art == 'grundtext') {
            buf.writeln();
            buf.writeln(p.kurztext);
            if ((p.langtext ?? '').isNotEmpty) {
              buf.writeln(p.langtext);
            }
            continue;
          }
          final m = p.menge ?? 0;
          final ep = p.einzelpreis ?? 0;
          final gp = m * ep;
          final isBp = p.art == 'bedarf';
          final mengeStr =
              '${_menge.format(m)} ${p.einheit ?? ""}'.trim();
          if (_mitPreisen) {
            buf.writeln(
                '${p.oz ?? ""}  ${p.kurztext}  —  $mengeStr × ${_money.format(ep)} = ${isBp ? "(BP)" : _money.format(gp)}');
          } else {
            buf.writeln('${p.oz ?? ""}  ${p.kurztext}  —  $mengeStr');
          }
          if ((p.langtext ?? '').isNotEmpty) {
            buf.writeln('  ${p.langtext}');
          }
          if (!isBp) summe += gp;
        }
        if (_mitPreisen && summe > 0) {
          buf.writeln();
          buf.writeln('-' * 50);
          buf.writeln(
              'Summe (netto, ohne Bedarfspositionen): ${_money.format(summe)}');
        }
      case _Format.aufzaehlung:
        for (final p in rows) {
          if (p.art == 'titel') {
            buf.writeln();
            buf.writeln('• ${p.kurztext}');
            continue;
          }
          if (p.art == 'grundtext') {
            buf.writeln('  ${p.kurztext}');
            if ((p.langtext ?? '').isNotEmpty) {
              buf.writeln('    ${p.langtext}');
            }
            continue;
          }
          final m = p.menge ?? 0;
          final ep = p.einzelpreis ?? 0;
          final gp = m * ep;
          final isBp = p.art == 'bedarf';
          final mengeStr =
              '${_menge.format(m)} ${p.einheit ?? ""}'.trim();
          final preisStr = _mitPreisen
              ? ' (${isBp ? "BP" : _money.format(gp)})'
              : '';
          buf.writeln('  – ${p.kurztext}: $mengeStr$preisStr');
          if (!isBp) summe += gp;
        }
        if (_mitPreisen && summe > 0) {
          buf.writeln();
          buf.writeln('Gesamtaufwand (netto): ${_money.format(summe)}');
        }
      case _Format.nurTexte:
        for (final p in rows) {
          if (p.art == 'titel') {
            buf.writeln();
            buf.writeln(p.kurztext);
            continue;
          }
          buf.writeln(p.kurztext);
          if ((p.langtext ?? '').isNotEmpty) {
            buf.writeln(p.langtext);
          }
          buf.writeln();
        }
    }
    return buf.toString().trim();
  }

  Widget _emptyView(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _LvList extends StatelessWidget {
  const _LvList({
    required this.lvs,
    required this.selectedId,
    required this.onSelect,
  });
  final List<LvKopfData> lvs;
  final int? selectedId;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy', 'de');
    return ListView.builder(
      itemCount: lvs.length,
      itemBuilder: (_, i) {
        final l = lvs[i];
        final selected = l.id == selectedId;
        return ListTile(
          selected: selected,
          dense: true,
          title: Text(l.bezeichnung,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${l.nummer ?? ""} · ${fmt.format(l.datum)} · ${l.status}',
              style: const TextStyle(fontSize: 11)),
          onTap: () => onSelect(l.id),
        );
      },
    );
  }
}

class _PositionsSelection extends ConsumerWidget {
  const _PositionsSelection({
    required this.lvId,
    required this.selected,
    required this.onToggle,
    required this.onSelectAll,
  });
  final int lvId;
  final Set<int> selected;
  final ValueChanged<int> onToggle;
  final ValueChanged<List<LvPositionenData>> onSelectAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positionen = ref.watch(lvPositionenProvider(lvId));
    return positionen.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('LV ohne Positionen.'));
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Text('${rows.length} Positionen',
                      style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.checklist, size: 16),
                    label: Text(selected.length == rows.length
                        ? 'Auswahl leeren'
                        : 'Alle wählen'),
                    onPressed: () => onSelectAll(rows),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final p = rows[i];
                  return CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: selected.contains(p.id),
                    onChanged: (_) => onToggle(p.id),
                    title: Text(
                      '${p.oz ?? ""}  ${p.kurztext}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        if (p.art == 'titel') 'Titel',
                        if (p.art == 'bedarf') 'BP',
                        if (p.art == 'stundenlohn') 'Stundenlohn',
                        if (p.art == 'grundtext') 'Grundtext',
                        if (p.menge != null && p.menge! > 0)
                          '${p.menge} ${p.einheit ?? ""}',
                      ]
                          .whereType<String>()
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
