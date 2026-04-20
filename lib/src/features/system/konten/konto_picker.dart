import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../shared/widgets/form_widgets.dart';
import 'konten_repository.dart';

/// Picker-Feld für ein DATEV-Konto. Zeigt den aktuellen Kontenrahmen
/// (SKR03/SKR04) aus den Einstellungen und öffnet beim Klick einen Such-
/// Dialog über alle Konten dieses Rahmens.
class KontoPickerField extends ConsumerWidget {
  const KontoPickerField({
    super.key,
    required this.kontonummer,
    required this.onChanged,
    this.label = 'DATEV-Konto',
    this.filterKategorie,
  });

  final String? kontonummer;
  final ValueChanged<String?> onChanged;
  final String label;

  /// Optional: nur Konten einer bestimmten Kategorie zeigen
  /// (z. B. `'aufwand'` für Eingangsrechnungen, `'ertrag'` für Ausgangs).
  final String? filterKategorie;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skr = ref.watch(aktuellerSkrProvider);
    final kontenAsync = ref.watch(kontenListProvider);

    final resolved = kontenAsync.valueOrNull
        ?.where((k) => k.nummer == kontonummer)
        .firstOrNull;

    return LabeledField(
      label,
      InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kontonummer != null && kontonummer!.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => onChanged(null),
                  tooltip: 'Entfernen',
                ),
              IconButton(
                icon: const Icon(Icons.search, size: 18),
                onPressed: () => _open(context, ref, skr),
                tooltip: 'Konto suchen',
              ),
            ],
          ),
        ),
        child: InkWell(
          onTap: () => _open(context, ref, skr),
          child: Text(
            resolved == null
                ? 'Auswählen … ($skr)'
                : '${resolved.nummer} · ${resolved.bezeichnung}',
            style: resolved == null
                ? TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)
                : null,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, String skr) async {
    final picked = await showDialog<KontenData>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _KontoPickerDialog(
        skr: skr,
        filterKategorie: filterKategorie,
      ),
    );
    if (picked != null) onChanged(picked.nummer);
  }
}

class _KontoPickerDialog extends ConsumerStatefulWidget {
  const _KontoPickerDialog({required this.skr, this.filterKategorie});
  final String skr;
  final String? filterKategorie;
  @override
  ConsumerState<_KontoPickerDialog> createState() =>
      _KontoPickerDialogState();
}

class _KontoPickerDialogState
    extends ConsumerState<_KontoPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(kontenListProvider);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 680),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined),
                  const SizedBox(width: 10),
                  Text('Konto auswählen (${widget.skr})',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
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
                  hintText: 'Nummer oder Bezeichnung …',
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
                  final filtered = items.where((k) {
                    if (widget.filterKategorie != null &&
                        k.kategorie != widget.filterKategorie) {
                      return false;
                    }
                    if (_query.isEmpty) return true;
                    final q = _query.toLowerCase();
                    return k.nummer.toLowerCase().contains(q) ||
                        k.bezeichnung.toLowerCase().contains(q);
                  }).toList();
                  if (filtered.isEmpty) {
                    return const Center(child: Text('Keine Treffer'));
                  }
                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final k = filtered[i];
                      return ListTile(
                        dense: true,
                        title: Text('${k.nummer} · ${k.bezeichnung}'),
                        subtitle: Text([
                          k.kategorie,
                          if (k.ustSatz != null)
                            '${k.ustSatz!.toStringAsFixed(0)} % USt',
                        ].join(' · ')),
                        onTap: () =>
                            Navigator.of(context, rootNavigator: true)
                                .pop(k),
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
