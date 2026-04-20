import 'package:drift/drift.dart' as drift;
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Öffnet einen Dialog mit der Norm-Bibliothek (alle Einträge ohne
/// `auftragId`). Der User kann mehrere Normen anhaken und per "Zuordnen"
/// werden Kopien dieser Normen mit der übergebenen `auftragId` angelegt
/// — so bleibt der Bibliotheks-Eintrag unberührt.
Future<void> showNormenKatalogPicker(
  BuildContext context, {
  required int auftragId,
}) async {
  await showDialog(
    context: context,
    useRootNavigator: true,
    builder: (_) => _NormenPickerDialog(auftragId: auftragId),
  );
}

class _NormenPickerDialog extends ConsumerStatefulWidget {
  const _NormenPickerDialog({required this.auftragId});
  final int auftragId;
  @override
  ConsumerState<_NormenPickerDialog> createState() =>
      _NormenPickerDialogState();
}

class _NormenPickerDialogState extends ConsumerState<_NormenPickerDialog> {
  String _query = '';
  final Set<int> _selected = {};
  bool _saving = false;

  Stream<List<NormenData>> _katalog(AppDatabase db) {
    return (db.select(db.normen)
          ..where((t) => t.auftragId.isNull())
          ..orderBy([(t) => drift.OrderingTerm(expression: t.nummer)]))
        .watch();
  }

  Future<void> _zuordnen(AppDatabase db, List<NormenData> katalog) async {
    setState(() => _saving = true);
    try {
      for (final n in katalog) {
        if (!_selected.contains(n.id)) continue;
        // Neuen Akten-spezifischen Norm-Eintrag anlegen (Kopie, auftragId gesetzt).
        await db.into(db.normen).insert(NormenCompanion.insert(
              auftragId: Value(widget.auftragId),
              nummer: n.nummer,
              titel: Value(n.titel),
              ausgabe: Value(n.ausgabe),
              kategorie: Value(n.kategorie),
              art: Value(n.art),
              herausgeber: Value(n.herausgeber),
              relevanz: Value(n.relevanz),
              zusammenfassung: Value(n.zusammenfassung),
              zitat: Value(n.zitat),
              beschreibung: Value(n.beschreibung),
              pdfStorageUrl: Value(n.pdfStorageUrl),
              pdfDateiname: Value(n.pdfDateiname),
              pdfMimeType: Value(n.pdfMimeType),
              pdfGroesse: Value(n.pdfGroesse),
            ));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${_selected.length} Norm(en) der Akte zugeordnet.')),
        );
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
                  const Icon(Icons.menu_book_outlined, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Normen aus Katalog zuordnen',
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
                  hintText: 'Suche Nummer, Titel, Kategorie …',
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<NormenData>>(
                stream: _katalog(db),
                builder: (ctx, snap) {
                  final all = snap.data ?? const [];
                  final q = _query.trim().toLowerCase();
                  final filtered = q.isEmpty
                      ? all
                      : all.where((n) {
                          return n.nummer.toLowerCase().contains(q) ||
                              (n.titel ?? '').toLowerCase().contains(q) ||
                              (n.kategorie ?? '').toLowerCase().contains(q);
                        }).toList();
                  if (filtered.isEmpty) {
                    return const Center(
                        child: Text('Keine Normen im Katalog.'));
                  }
                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final n = filtered[i];
                      final checked = _selected.contains(n.id);
                      return CheckboxListTile(
                        value: checked,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selected.add(n.id);
                            } else {
                              _selected.remove(n.id);
                            }
                          });
                        },
                        title: Row(
                          children: [
                            Text(n.nummer,
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(width: 8),
                            if ((n.ausgabe ?? '').isNotEmpty)
                              Text(n.ausgabe!,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.slate500)),
                          ],
                        ),
                        subtitle: Text(n.titel ?? '—',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        secondary: (n.kategorie ?? '').isEmpty
                            ? null
                            : Chip(
                                label: Text(n.kategorie!),
                                visualDensity: VisualDensity.compact,
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
                    label: Text(_saving ? 'Speichere …' : 'Zuordnen'),
                    onPressed: _saving || _selected.isEmpty
                        ? null
                        : () async {
                            final all = await _katalog(db).first;
                            await _zuordnen(db, all);
                          },
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
