import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../features/system/benutzer/benutzer_repository.dart';
import '../../../features/system/einstellungen/einstellungen_repository.dart';
import '../../../shared/widgets/date_field.dart';
import '../kunden/kunden_picker.dart';
import 'auftraege_repository.dart';

Future<bool?> showAuftragFormDialog(
  BuildContext context, {
  AuftraegeData? auftrag,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840, maxHeight: 820),
        child: _AuftragFormDialog(auftrag: auftrag),
      ),
    ),
  );
}

class _AuftragFormDialog extends ConsumerStatefulWidget {
  const _AuftragFormDialog({this.auftrag});
  final AuftraegeData? auftrag;

  @override
  ConsumerState<_AuftragFormDialog> createState() =>
      _AuftragFormDialogState();
}

class _AuftragFormDialogState extends ConsumerState<_AuftragFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late AuftragArt _art;
  late AuftragStatus _status;
  int? _kundeId;
  DateTime? _eingangAm;
  DateTime? _auftragAm;
  DateTime? _abschlussAm;

  late final _aktenzeichen =
      TextEditingController(text: widget.auftrag?.aktenzeichen ?? '');
  late final _bezeichnung =
      TextEditingController(text: widget.auftrag?.bezeichnung ?? '');
  late final _objStrasse =
      TextEditingController(text: widget.auftrag?.objektStrasse ?? '');
  late final _objPlz =
      TextEditingController(text: widget.auftrag?.objektPlz ?? '');
  late final _objOrt =
      TextEditingController(text: widget.auftrag?.objektOrt ?? '');
  late final _gerichtsAz = TextEditingController(
      text: widget.auftrag?.gerichtsAktenzeichen ?? '');
  late final _richter =
      TextEditingController(text: widget.auftrag?.richter ?? '');
  late final _stundensatz = TextEditingController(
      text: _money(widget.auftrag?.stundensatz));
  late final _kostenLimit = TextEditingController(
      text: _money(widget.auftrag?.kostenLimit));
  late final _kostenvorschuss = TextEditingController(
      text: _money(widget.auftrag?.kostenvorschuss));
  late final _notiz =
      TextEditingController(text: widget.auftrag?.notiz ?? '');

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.auftrag;
    _art = AuftragArtX.fromDb(a?.art);
    _status = AuftragStatusX.fromDb(a?.status);
    _kundeId = a?.kundeId;
    _eingangAm = a?.eingangAm;
    _auftragAm = a?.auftragAm;
    _abschlussAm = a?.abschlussAm;
    if (a == null) {
      _prefillAktenzeichen();
    }
  }

  Future<void> _prefillAktenzeichen() async {
    final seq = await ref.read(auftraegeRepositoryProvider).nextAktenzeichenSeq();
    final pattern = await ref
        .read(einstellungenRepositoryProvider)
        .getOr(SettingsKeys.nummernkreisAktenzeichen, 'YYYY/####');
    final zeichen = _applyPattern(pattern, seq);
    if (mounted && _aktenzeichen.text.isEmpty) {
      _aktenzeichen.text = zeichen;
    }

    if (_stundensatz.text.isEmpty) {
      final settingSatz = await ref
          .read(einstellungenRepositoryProvider)
          .getDouble(SettingsKeys.standardStundensatz);
      final benutzer = await ref.read(benutzerRepositoryProvider).getActive();
      final satz = settingSatz ?? benutzer?.standardStundensatz;
      if (mounted && satz != null) {
        _stundensatz.text = satz.toStringAsFixed(2);
      }
    }
  }

  String _applyPattern(String pattern, int seq) {
    final now = DateTime.now();
    var out = pattern
        .replaceAll('YYYY', '${now.year}')
        .replaceAll('YY', now.year.toString().substring(2))
        .replaceAll('MM', now.month.toString().padLeft(2, '0'));
    final hashes = RegExp(r'#+').firstMatch(out);
    if (hashes != null) {
      final width = hashes.group(0)!.length;
      out = out.replaceFirst(hashes.group(0)!, seq.toString().padLeft(width, '0'));
    } else {
      out = '$out$seq';
    }
    return out;
  }

  @override
  void dispose() {
    for (final c in [
      _aktenzeichen, _bezeichnung, _objStrasse, _objPlz, _objOrt,
      _gerichtsAz, _richter, _stundensatz, _kostenLimit, _kostenvorschuss,
      _notiz,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.auftrag != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(auftraegeRepositoryProvider);
    final companion = AuftraegeCompanion(
      id: _isEdit ? Value(widget.auftrag!.id) : const Value.absent(),
      aktenzeichen: _nullableText(_aktenzeichen),
      art: Value(_art.dbValue),
      status: Value(_status.dbValue),
      kundeId: Value(_kundeId),
      bezeichnung: _nullableText(_bezeichnung),
      objektStrasse: _nullableText(_objStrasse),
      objektPlz: _nullableText(_objPlz),
      objektOrt: _nullableText(_objOrt),
      gerichtsAktenzeichen: _nullableText(_gerichtsAz),
      richter: _nullableText(_richter),
      eingangAm: Value(_eingangAm),
      auftragAm: Value(_auftragAm),
      abschlussAm: Value(_abschlussAm),
      stundensatz: _nullableMoney(_stundensatz),
      kostenLimit: _nullableMoney(_kostenLimit),
      kostenvorschuss: _nullableMoney(_kostenvorschuss),
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

  Value<double?> _nullableMoney(TextEditingController c) {
    final v = c.text.trim().replaceAll(',', '.');
    if (v.isEmpty) return const Value(null);
    return Value(double.tryParse(v));
  }

  static String _money(double? v) => v == null ? '' : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _DialogHeader(
          title: _isEdit
              ? 'Auftrag bearbeiten · ${widget.auftrag!.aktenzeichen ?? ''}'
              : 'Neuer Auftrag',
          onClose: _saving ? null : () => Navigator.pop(context, false),
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
                  _Row2(
                    left: _Labeled(
                      'Art',
                      SegmentedButton<AuftragArt>(
                        segments: [
                          for (final a in AuftragArt.values)
                            ButtonSegment(value: a, label: Text(a.label)),
                        ],
                        selected: {_art},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) =>
                            setState(() => _art = s.first),
                      ),
                    ),
                    right: _Labeled(
                      'Status',
                      DropdownButtonFormField<AuftragStatus>(
                        initialValue: _status,
                        isDense: true,
                        items: [
                          for (final s in AuftragStatus.values)
                            DropdownMenuItem(value: s, child: Text(s.label)),
                        ],
                        onChanged: (s) =>
                            setState(() => _status = s ?? AuftragStatus.offen),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Row2(
                    flex: const (2, 3),
                    left: _Labeled(
                      'Aktenzeichen',
                      TextFormField(
                        controller: _aktenzeichen,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty)
                                ? 'Erforderlich'
                                : null,
                      ),
                    ),
                    right: _Labeled(
                      'Kurzbezeichnung',
                      TextFormField(controller: _bezeichnung),
                    ),
                  ),
                  const SizedBox(height: 12),
                  KundenPickerField(
                    kundeId: _kundeId,
                    onChanged: (id) => setState(() => _kundeId = id),
                  ),
                  const SizedBox(height: 20),
                  Text('Objekt', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _Labeled(
                    'Straße',
                    TextFormField(controller: _objStrasse),
                  ),
                  const SizedBox(height: 12),
                  _Row2(
                    flex: const (1, 3),
                    left: _Labeled('PLZ', TextFormField(controller: _objPlz)),
                    right: _Labeled('Ort', TextFormField(controller: _objOrt)),
                  ),
                  if (_art == AuftragArt.gericht) ...[
                    const SizedBox(height: 20),
                    Text('Gericht', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    _Row2(
                      left: _Labeled(
                        'Gerichtliches Aktenzeichen',
                        TextFormField(controller: _gerichtsAz),
                      ),
                      right: _Labeled(
                        'Richter/in',
                        TextFormField(controller: _richter),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text('Termine', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _Row3(
                    a: DateField(
                      label: 'Eingang',
                      value: _eingangAm,
                      onChanged: (v) => setState(() => _eingangAm = v),
                    ),
                    b: DateField(
                      label: 'Auftrag',
                      value: _auftragAm,
                      onChanged: (v) => setState(() => _auftragAm = v),
                    ),
                    c: DateField(
                      label: 'Abschluss',
                      value: _abschlussAm,
                      onChanged: (v) => setState(() => _abschlussAm = v),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Honorar', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _Row3(
                    a: _Labeled(
                      'Stundensatz (€)',
                      TextFormField(
                        controller: _stundensatz,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                    ),
                    b: _Labeled(
                      'Kostenlimit (€)',
                      TextFormField(
                        controller: _kostenLimit,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                    ),
                    c: _Labeled(
                      'Kostenvorschuss (€)',
                      TextFormField(
                        controller: _kostenvorschuss,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Labeled(
                    'Notiz',
                    TextFormField(
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
                onPressed:
                    _saving ? null : () => Navigator.pop(context, false),
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

class _Labeled extends StatelessWidget {
  const _Labeled(this.label, this.child);
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ),
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

class _Row3 extends StatelessWidget {
  const _Row3({required this.a, required this.b, required this.c});
  final Widget a;
  final Widget b;
  final Widget c;
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: 12),
          Expanded(child: b),
          const SizedBox(width: 12),
          Expanded(child: c),
        ],
      );
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.title, required this.onClose});
  final String title;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close),
              tooltip: 'Schließen',
            ),
          ],
        ),
      );
}
