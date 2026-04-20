import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../shared/widgets/form_widgets.dart';
import 'kunden_form.dart';
import 'kunden_repository.dart';

/// Kompakter Picker-Button, der einen Kunden per Such-Dialog auswählt.
class KundenPickerField extends ConsumerStatefulWidget {
  const KundenPickerField({
    super.key,
    required this.kundeId,
    required this.onChanged,
    this.label = 'Auftraggeber',
    this.onlyTypen,
  });

  final int? kundeId;
  final ValueChanged<int?> onChanged;
  final String label;
  final List<KundenTyp>? onlyTypen;

  @override
  ConsumerState<KundenPickerField> createState() =>
      _KundenPickerFieldState();
}

class _KundenPickerFieldState extends ConsumerState<KundenPickerField> {
  KundenData? _resolved;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant KundenPickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kundeId != widget.kundeId) _resolve();
  }

  Future<void> _resolve() async {
    if (widget.kundeId == null) {
      setState(() => _resolved = null);
      return;
    }
    final k = await ref.read(kundenRepositoryProvider).byId(widget.kundeId!);
    if (mounted) setState(() => _resolved = k);
  }

  @override
  Widget build(BuildContext context) {
    final k = _resolved;
    return LabeledField(
      widget.label,
      InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (k != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Entfernen',
                  onPressed: () => widget.onChanged(null),
                ),
              IconButton(
                icon: const Icon(Icons.search, size: 18),
                tooltip: 'Suchen',
                onPressed: _openSearch,
              ),
            ],
          ),
        ),
        child: InkWell(
          onTap: _openSearch,
          child: k == null
              ? Text(
                  'Auswählen …',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                )
              : Text(kundeAnzeigename(k)),
        ),
      ),
    );
  }

  Future<void> _openSearch() async {
    final picked = await showDialog<KundenData>(
      context: context,
      builder: (_) => _KundenPickerDialog(onlyTypen: widget.onlyTypen),
    );
    if (picked != null) widget.onChanged(picked.id);
  }
}

class _KundenPickerDialog extends ConsumerStatefulWidget {
  const _KundenPickerDialog({this.onlyTypen});
  final List<KundenTyp>? onlyTypen;

  @override
  ConsumerState<_KundenPickerDialog> createState() =>
      _KundenPickerDialogState();
}

class _KundenPickerDialogState extends ConsumerState<_KundenPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(kundenRepositoryProvider);
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
                  Text('Auftraggeber auswählen',
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
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Name, Firma, Ort …',
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<KundenData>>(
                stream: repo.watchAll(query: _query),
                builder: (context, snap) {
                  final items = (snap.data ?? const <KundenData>[])
                      .where((k) =>
                          widget.onlyTypen == null ||
                          widget.onlyTypen!
                              .map((t) => t.dbValue)
                              .contains(k.typ))
                      .toList();
                  if (items.isEmpty) {
                    return const Center(
                      child: Text('Keine Treffer'),
                    );
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final k = items[i];
                      return ListTile(
                        dense: true,
                        title: Text(kundeAnzeigename(k)),
                        subtitle: Text([
                          KundenTypX.fromDb(k.typ).label,
                          [k.plz, k.ort]
                              .whereType<String>()
                              .join(' ')
                              .trim(),
                        ].where((s) => s.isNotEmpty).join(' · ')),
                        onTap: () => Navigator.of(context, rootNavigator: true).pop(k),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Neuer Auftraggeber'),
                    onPressed: () async {
                      final ok = await showKundenFormDialog(context);
                      if (ok == true && mounted) {
                        setState(() {});
                      }
                    },
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
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
