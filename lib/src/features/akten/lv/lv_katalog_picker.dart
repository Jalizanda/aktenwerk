import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import 'lv_repository.dart';

/// Picker-Dialog für eine Katalog-Position. Liefert die ausgewählte
/// `LvKatalogData` zurück; der Aufrufer fügt sie als `LvPositionen` ins
/// LV ein und ruft `tickKatalog(id)` auf für die Häufigkeit-Sortierung.
Future<LvKatalogData?> zeigeKatalogPicker(BuildContext context) =>
    showDialog<LvKatalogData?>(
      context: context,
      useRootNavigator: true,
      builder: (_) => const _KatalogPickerDialog(),
    );

class _KatalogPickerDialog extends ConsumerStatefulWidget {
  const _KatalogPickerDialog();
  @override
  ConsumerState<_KatalogPickerDialog> createState() =>
      _KatalogPickerDialogState();
}

class _KatalogPickerDialogState
    extends ConsumerState<_KatalogPickerDialog> {
  String _query = '';
  static final _money = NumberFormat.currency(
      locale: 'de_DE', symbol: '€', decimalDigits: 2);

  @override
  Widget build(BuildContext context) {
    final liste = ref.watch(lvKatalogProvider(_query));
    return Dialog(
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
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
                      'Aus Katalog einfügen',
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Suche nach Kurztext, Gewerk, Tags …',
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: liste.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Fehler: $e')),
                data: (rows) {
                  if (rows.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 56,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant),
                            const SizedBox(height: 12),
                            Text(
                              _query.isEmpty
                                  ? 'Der Katalog ist noch leer.'
                                  : 'Keine Treffer für „$_query".',
                              style:
                                  Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Beim Anlegen einer Position kannst du sie '
                              'mit „Position zusätzlich in den eigenen '
                              'Katalog übernehmen" hier hinzufügen.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      final preisstand =
                          r.preisstand == null ? '' : ' · Stand ${DateFormat('MM/yyyy').format(r.preisstand!)}';
                      return ListTile(
                        title: Text(r.kurztext,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [
                            if ((r.gewerk ?? '').isNotEmpty) r.gewerk,
                            if ((r.din276 ?? '').isNotEmpty)
                              'KG ${r.din276}',
                            if (r.einzelpreis != null && r.einzelpreis! > 0)
                              '${_money.format(r.einzelpreis!)}/${r.einheit ?? ""}',
                            'verwendet ${r.verwendungsZaehler}×$preisstand',
                          ]
                              .whereType<String>()
                              .where((s) => s.isNotEmpty)
                              .join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context, rootNavigator: true).pop(r);
                        },
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
