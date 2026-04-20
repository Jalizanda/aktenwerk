import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Öffnet einen Picker mit allen aktiven Messgeräten. Der User hakt mehrere
/// Geräte an und sie werden über die Junction-Table `auftraege_geraete`
/// mit dem Auftrag verknüpft.
Future<void> showGeraeteKatalogPicker(
  BuildContext context, {
  required int auftragId,
}) async {
  await showDialog(
    context: context,
    useRootNavigator: true,
    builder: (_) => _GeraetePickerDialog(auftragId: auftragId),
  );
}

class _GeraetePickerDialog extends ConsumerStatefulWidget {
  const _GeraetePickerDialog({required this.auftragId});
  final int auftragId;
  @override
  ConsumerState<_GeraetePickerDialog> createState() =>
      _GeraetePickerDialogState();
}

class _GeraetePickerDialogState extends ConsumerState<_GeraetePickerDialog> {
  String _query = '';
  final Set<int> _selected = {};
  bool _saving = false;
  Set<int> _alreadyLinked = {};

  @override
  void initState() {
    super.initState();
    _loadLinked();
  }

  Future<void> _loadLinked() async {
    final db = ref.read(appDatabaseProvider);
    final rows = await (db.select(db.auftraegeGeraete)
          ..where((t) => t.auftragId.equals(widget.auftragId)))
        .get();
    if (mounted) {
      setState(() {
        _alreadyLinked = rows.map((r) => r.geraetId).toSet();
        _selected.addAll(_alreadyLinked);
      });
    }
  }

  Future<void> _zuordnen(AppDatabase db) async {
    setState(() => _saving = true);
    try {
      // Junction-Links synchronisieren: zuerst entfernte Links löschen,
      // dann neu angelegte einfügen.
      final toRemove = _alreadyLinked.difference(_selected);
      final toAdd = _selected.difference(_alreadyLinked);
      for (final id in toRemove) {
        await (db.delete(db.auftraegeGeraete)
              ..where((t) => t.auftragId.equals(widget.auftragId))
              ..where((t) => t.geraetId.equals(id)))
            .go();
      }
      for (final id in toAdd) {
        await db.into(db.auftraegeGeraete).insert(
              AuftraegeGeraeteCompanion.insert(
                auftragId: widget.auftragId,
                geraetId: id,
              ),
            );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Geräte-Zuordnung gespeichert (${_selected.length} Gerät(e)).')));
        Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);
    final katalog = (db.select(db.geraete)
          ..where((t) => t.aktiv.equals(true))
          ..orderBy([(t) => drift.OrderingTerm(expression: t.bezeichnung)]))
        .watch();
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.precision_manufacturing_outlined, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Messgeräte dem Auftrag zuordnen',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Suche Bezeichnung, Hersteller, Seriennummer …',
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<GeraeteData>>(
                stream: katalog,
                builder: (ctx, snap) {
                  final all = snap.data ?? const [];
                  final q = _query.trim().toLowerCase();
                  final filtered = q.isEmpty
                      ? all
                      : all.where((g) {
                          return g.bezeichnung.toLowerCase().contains(q) ||
                              (g.hersteller ?? '').toLowerCase().contains(q) ||
                              (g.seriennummer ?? '').toLowerCase().contains(q);
                        }).toList();
                  if (filtered.isEmpty) {
                    return const Center(
                        child: Text('Keine Geräte im Katalog.'));
                  }
                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final g = filtered[i];
                      final checked = _selected.contains(g.id);
                      return CheckboxListTile(
                        value: checked,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selected.add(g.id);
                            } else {
                              _selected.remove(g.id);
                            }
                          });
                        },
                        title: Text(g.bezeichnung,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          [
                            g.hersteller,
                            g.modell,
                            if ((g.seriennummer ?? '').isNotEmpty)
                              'SN ${g.seriennummer}'
                          ]
                              .whereType<String>()
                              .where((s) => s.isNotEmpty)
                              .join(' · '),
                          style: const TextStyle(fontSize: 12),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  Text(
                    '${_selected.length} ausgewählt',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.slate500),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context,
                            rootNavigator: true)
                        .pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: Text(_saving ? 'Speichere …' : 'Zuordnung speichern'),
                    onPressed: _saving ? null : () => _zuordnen(db),
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
