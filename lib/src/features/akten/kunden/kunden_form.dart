import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import 'kunden_repository.dart';

/// Dialog zum Anlegen/Bearbeiten eines Kunden.
///
/// Gibt `true` zurück, wenn gespeichert wurde, `false` bei Abbruch
/// und `null` bei Schließen ohne Aktion.
Future<bool?> showKundenFormDialog(
  BuildContext context, {
  KundenData? kunde,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
        child: _KundenFormDialog(kunde: kunde),
      ),
    ),
  );
}

class _KundenFormDialog extends ConsumerStatefulWidget {
  const _KundenFormDialog({this.kunde});
  final KundenData? kunde;

  @override
  ConsumerState<_KundenFormDialog> createState() => _KundenFormDialogState();
}

class _KundenFormDialogState extends ConsumerState<_KundenFormDialog> {
  late KundenTyp _typ;
  final _formKey = GlobalKey<FormState>();

  late final _anrede = TextEditingController(text: widget.kunde?.anrede ?? '');
  late final _titel = TextEditingController(text: widget.kunde?.titel ?? '');
  late final _vorname =
      TextEditingController(text: widget.kunde?.vorname ?? '');
  late final _nachname =
      TextEditingController(text: widget.kunde?.nachname ?? '');
  late final _firma = TextEditingController(text: widget.kunde?.firma ?? '');
  late final _strasse =
      TextEditingController(text: widget.kunde?.strasse ?? '');
  late final _plz = TextEditingController(text: widget.kunde?.plz ?? '');
  late final _ort = TextEditingController(text: widget.kunde?.ort ?? '');
  late final _telefon =
      TextEditingController(text: widget.kunde?.telefon ?? '');
  late final _mobil = TextEditingController(text: widget.kunde?.mobil ?? '');
  late final _email = TextEditingController(text: widget.kunde?.email ?? '');
  late final _ustId = TextEditingController(text: widget.kunde?.ustId ?? '');
  late final _notiz = TextEditingController(text: widget.kunde?.notiz ?? '');

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _typ = KundenTypX.fromDb(widget.kunde?.typ);
  }

  @override
  void dispose() {
    for (final c in [
      _anrede, _titel, _vorname, _nachname, _firma, _strasse,
      _plz, _ort, _telefon, _mobil, _email, _ustId, _notiz,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.kunde != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(kundenRepositoryProvider);
    final companion = KundenCompanion(
      id: _isEdit ? Value(widget.kunde!.id) : const Value.absent(),
      typ: Value(_typ.dbValue),
      anrede: _nullableText(_anrede),
      titel: _nullableText(_titel),
      vorname: _nullableText(_vorname),
      nachname: _nullableText(_nachname),
      firma: _nullableText(_firma),
      strasse: _nullableText(_strasse),
      plz: _nullableText(_plz),
      ort: _nullableText(_ort),
      telefon: _nullableText(_telefon),
      mobil: _nullableText(_mobil),
      email: _nullableText(_email),
      ustId: _nullableText(_ustId),
      notiz: _nullableText(_notiz),
      updatedAt: Value(DateTime.now()),
    );
    try {
      await repo.upsert(companion);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
        );
      }
    }
  }

  Value<String?> _nullableText(TextEditingController c) {
    final v = c.text.trim();
    return Value(v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showFirma =
        _typ != KundenTyp.privat || _firma.text.trim().isNotEmpty;
    final showPerson =
        _typ == KundenTyp.privat || _typ == KundenTyp.anwalt ||
            _vorname.text.isNotEmpty ||
            _nachname.text.isNotEmpty;

    return Column(
      children: [
        _DialogHeader(
          title: _isEdit ? 'Auftraggeber bearbeiten' : 'Neuer Auftraggeber',
          onClose: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        const Divider(height: 1),
        Expanded(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FieldLabel('Typ'),
                  SegmentedButton<KundenTyp>(
                    segments: [
                      for (final t in KundenTyp.values)
                        ButtonSegment(value: t, label: Text(t.label)),
                    ],
                    selected: {_typ},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        setState(() => _typ = s.first),
                  ),
                  const SizedBox(height: 16),
                  if (showFirma) ...[
                    _FieldLabel('Firma / Institution'),
                    TextFormField(
                      controller: _firma,
                      validator: (v) {
                        if (_typ != KundenTyp.privat &&
                            (v == null || v.trim().isEmpty)) {
                          return 'Firma / Gericht / Versicherung ist erforderlich';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (showPerson) ...[
                    _Row2(
                      left: _LabeledField(
                        label: 'Anrede',
                        child: TextFormField(controller: _anrede),
                      ),
                      right: _LabeledField(
                        label: 'Titel',
                        child: TextFormField(controller: _titel),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Row2(
                      left: _LabeledField(
                        label: 'Vorname',
                        child: TextFormField(controller: _vorname),
                      ),
                      right: _LabeledField(
                        label: 'Nachname',
                        child: TextFormField(
                          controller: _nachname,
                          validator: (v) {
                            if (_typ == KundenTyp.privat &&
                                (v == null || v.trim().isEmpty) &&
                                _firma.text.trim().isEmpty) {
                              return 'Nachname oder Firma erforderlich';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text('Adresse', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _LabeledField(
                    label: 'Straße',
                    child: TextFormField(controller: _strasse),
                  ),
                  const SizedBox(height: 12),
                  _Row2(
                    flex: const (1, 3),
                    left: _LabeledField(
                      label: 'PLZ',
                      child: TextFormField(controller: _plz),
                    ),
                    right: _LabeledField(
                      label: 'Ort',
                      child: TextFormField(controller: _ort),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Kontakt', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _Row2(
                    left: _LabeledField(
                      label: 'Telefon',
                      child: TextFormField(
                        controller: _telefon,
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                    right: _LabeledField(
                      label: 'Mobil',
                      child: TextFormField(
                        controller: _mobil,
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Row2(
                    left: _LabeledField(
                      label: 'E-Mail',
                      child: TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),
                    right: _LabeledField(
                      label: 'USt-ID',
                      child: TextFormField(controller: _ustId),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _LabeledField(
                    label: 'Notiz',
                    child: TextFormField(
                      controller: _notiz,
                      minLines: 2,
                      maxLines: 5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('Abbrechen'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Speichern'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
      );
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label),
          child,
        ],
      );
}

class _Row2 extends StatelessWidget {
  const _Row2({required this.left, required this.right, this.flex});
  final Widget left;
  final Widget right;
  final (int, int)? flex;
  @override
  Widget build(BuildContext context) {
    final (l, r) = flex ?? (1, 1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: l, child: left),
        const SizedBox(width: 12),
        Expanded(flex: r, child: right),
      ],
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.title, required this.onClose});
  final String title;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close),
            tooltip: 'Schließen',
          ),
        ],
      ),
    );
  }
}
