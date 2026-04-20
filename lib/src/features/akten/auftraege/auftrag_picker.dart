import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/form_widgets.dart';
import '../kunden/kunden_repository.dart';
import 'auftraege_repository.dart';

/// Picker-Button für einen Auftrag mit Such-Dialog (Aktenzeichen + Bezeichnung + Kunde).
class AuftragPickerField extends ConsumerStatefulWidget {
  const AuftragPickerField({
    super.key,
    required this.auftragId,
    required this.onChanged,
    this.label = 'Auftrag',
  });

  final int? auftragId;
  final ValueChanged<int?> onChanged;
  final String label;

  @override
  ConsumerState<AuftragPickerField> createState() =>
      _AuftragPickerFieldState();
}

class _AuftragPickerFieldState extends ConsumerState<AuftragPickerField> {
  AuftragWithKunde? _resolved;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant AuftragPickerField old) {
    super.didUpdateWidget(old);
    if (old.auftragId != widget.auftragId) _resolve();
  }

  Future<void> _resolve() async {
    final id = widget.auftragId;
    if (id == null) {
      setState(() => _resolved = null);
      return;
    }
    final db = ref.read(auftraegeRepositoryProvider);
    final kundenRepo = ref.read(kundenRepositoryProvider);
    final a = await db.byId(id);
    if (a == null) {
      if (mounted) setState(() => _resolved = null);
      return;
    }
    final k = a.kundeId == null ? null : await kundenRepo.byId(a.kundeId!);
    if (mounted) setState(() => _resolved = AuftragWithKunde(a, k));
  }

  String _display(AuftragWithKunde r) {
    final az = r.auftrag.aktenzeichen ?? '(o. A.)';
    final kunde = r.kunde == null ? '' : ' · ${kundeAnzeigename(r.kunde!)}';
    final bez = (r.auftrag.bezeichnung ?? '').isEmpty
        ? ''
        : ' · ${r.auftrag.bezeichnung}';
    return '$az$kunde$bez';
  }

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      widget.label,
      InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_resolved != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => widget.onChanged(null),
                  tooltip: 'Entfernen',
                ),
              IconButton(
                icon: const Icon(Icons.search, size: 18),
                onPressed: _open,
                tooltip: 'Suchen',
              ),
            ],
          ),
        ),
        child: InkWell(
          onTap: _open,
          child: _resolved == null
              ? Text('Auswählen …',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant))
              : Text(_display(_resolved!), overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }

  Future<void> _open() async {
    final picked = await showDialog<AuftragWithKunde>(
      context: context,
      builder: (_) => const _AuftragPickerDialog(),
    );
    if (picked != null) widget.onChanged(picked.auftrag.id);
  }
}

class _AuftragPickerDialog extends ConsumerStatefulWidget {
  const _AuftragPickerDialog();
  @override
  ConsumerState<_AuftragPickerDialog> createState() =>
      _AuftragPickerDialogState();
}

class _AuftragPickerDialogState
    extends ConsumerState<_AuftragPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Text('Auftrag auswählen',
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
                  hintText: 'Aktenzeichen, Bezeichnung, Kunde …',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<AuftragWithKunde>>(
                stream: ref
                    .read(auftraegeRepositoryProvider)
                    .watchAll(query: _query),
                builder: (context, snap) {
                  final items = snap.data ?? const <AuftragWithKunde>[];
                  if (items.isEmpty) {
                    return const Center(child: Text('Keine Treffer'));
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = items[i];
                      return ListTile(
                        dense: true,
                        title: Text(r.auftrag.aktenzeichen ?? '(o. A.)'),
                        subtitle: Text([
                          r.kunde == null ? '' : kundeAnzeigename(r.kunde!),
                          r.auftrag.bezeichnung ?? '',
                        ].where((s) => s.isNotEmpty).join(' · ')),
                        trailing: Text(
                          AuftragStatusX.fromDb(r.auftrag.status).label,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        onTap: () => Navigator.of(context, rootNavigator: true).pop(r),
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
