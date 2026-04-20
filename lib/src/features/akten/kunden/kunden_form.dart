import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/seed/gerichte.dart';
import '../../system/konten/debitor_service.dart';
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
  late final _aktenpraefix = TextEditingController(text: widget.kunde?.aktenpraefix ?? '');
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
      _plz, _ort, _telefon, _mobil, _email, _ustId, _aktenpraefix, _notiz,
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
    // DATEV-Debitornummer automatisch vergeben (nur bei neuen Kunden
    // ohne bestehende Nummer).
    String? debitor = widget.kunde?.debitornummer;
    if (debitor == null || debitor.isEmpty) {
      debitor = await ref
          .read(debitorKreditorServiceProvider)
          .nextDebitornummer();
    }
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
      aktenpraefix: _nullableText(_aktenpraefix),
      debitornummer: Value(debitor),
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

  Future<void> _openGerichtsPicker() async {
    final picked = await showDialog<Gericht>(
      context: context,
      useRootNavigator: true,
      builder: (_) => const _GerichtePickerDialog(),
    );
    if (picked == null) return;
    setState(() {
      // Automatisch auf Typ „Gericht" umschalten, damit das Aktenzeichen-
      // Schema etc. passt.
      _typ = KundenTyp.gericht;
      _firma.text = picked.name;
      _strasse.text = picked.strasse;
      _plz.text = picked.plz;
      _ort.text = picked.ort;
      if (_telefon.text.isEmpty) _telefon.text = picked.telefon;
    });
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
          icon: Icons.group_outlined,
          onClose: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        const Divider(height: 1),
        Expanded(
          child: Container(
            color: Colors.white,
            child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FieldLabel('Typ'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in KundenTyp.values)
                        _TypChip(
                          label: t.label,
                          selected: _typ == t,
                          onTap: () => setState(() => _typ = t),
                        ),
                    ],
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
                  const SizedBox(height: 12),
                  _LabeledField(
                    label: 'Aktenzeichen-Präfix (z. B. "12 OH 4/26")',
                    child: TextFormField(controller: _aktenpraefix),
                  ),
                  const SizedBox(height: 8),
                  // Immer sichtbar — der Klick setzt automatisch typ=gericht
                  // und füllt Firma/Adresse/Telefon aus der Gerichtsdatenbank.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.balance_outlined, size: 18),
                      label:
                          const Text('Aus Gerichtsdatenbank wählen (158 Gerichte)'),
                      onPressed: _openGerichtsPicker,
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

/// Typ-Chip à la Tailwind: Orange wenn ausgewählt, Slate sonst.
/// Ersetzt den Flutter-Default-SegmentedButton, der optisch zu unauffällig war.
class _TypChip extends StatelessWidget {
  const _TypChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: selected ? accent : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? accent : const Color(0xFFE2E8F0),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : const Color(0xFF334155),
            ),
          ),
        ),
      ),
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
  const _DialogHeader(
      {required this.title, required this.onClose, this.icon});
  final String title;
  final VoidCallback? onClose;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
          ],
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

/// Dialog zum Durchsuchen der 158 portierten Gerichte.
class _GerichtePickerDialog extends StatefulWidget {
  const _GerichtePickerDialog();
  @override
  State<_GerichtePickerDialog> createState() =>
      _GerichtePickerDialogState();
}

class _GerichtePickerDialogState extends State<_GerichtePickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
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
                  Text('Gericht auswählen',
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
                  hintText: 'Name, Ort, PLZ, Typ …',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Gericht>>(
                future: GerichteRepository.instance.search(_query),
                builder: (_, snap) {
                  final items = snap.data ?? const <Gericht>[];
                  if (snap.connectionState == ConnectionState.waiting &&
                      items.isEmpty) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }
                  if (items.isEmpty) {
                    return const Center(child: Text('Keine Treffer'));
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final g = items[i];
                      return ListTile(
                        dense: true,
                        leading: Text(g.typ,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color:
                                  Theme.of(context).colorScheme.primary,
                            )),
                        title: Text(g.name),
                        subtitle: Text(
                            '${g.strasse} · ${g.plz} ${g.ort} · ${g.telefon}'),
                        onTap: () =>
                            Navigator.of(context, rootNavigator: true)
                                .pop(g),
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
