import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftraege_repository.dart';
import '../../../features/akten/kunden/kunden_repository.dart';
import '../../../shared/widgets/badges.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'befangenheit_repository.dart';

/// Top-Level-Seite „Befangenheits-Register". Aggregiert automatisch alle
/// Auftraggeber, Gerichte und Richter aus den Akten und ergänzt sie um
/// manuell hinterlegte Einträge (z. B. Geschäftspartner ohne eigene Akte).
class BefangenheitScreen extends ConsumerStatefulWidget {
  const BefangenheitScreen({super.key});
  @override
  ConsumerState<BefangenheitScreen> createState() =>
      _BefangenheitScreenState();
}

class _BefangenheitScreenState extends ConsumerState<BefangenheitScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final auftraege = ref.watch(auftraegeListProvider);
    final kundenAsync = ref.watch(kundenListProvider);
    final manuelleAsync = ref.watch(befangenheitsEintraegeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.gavel_outlined,
          title: 'Befangenheits-Register',
          subtitle:
              'Auftraggeber, Gerichte, Richter und manuell gepflegte Kontakte — '
              'Nachschlagewerk vor neuer Auftragsannahme.',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neuer Eintrag'),
              onPressed: () => _openEditor(),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: 'Suche nach Name / Firma / Ort / Aktenzeichen',
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        Expanded(
          child: Builder(builder: (_) {
            final a = auftraege.valueOrNull ?? const [];
            final k = kundenAsync.valueOrNull ?? const [];
            final manuell = manuelleAsync.valueOrNull ??
                const <BefangenheitsEintraegeData>[];

            final rows = <_RegisterRow>[];
            for (final kd in k) {
              rows.add(_RegisterRow(
                rolle: 'Auftraggeber',
                name: kundeAnzeigename(kd),
                ortAz: [kd.plz, kd.ort]
                    .whereType<String>()
                    .where((s) => s.isNotEmpty)
                    .join(' '),
                kontakt: kd.email ?? kd.telefon ?? '',
              ));
            }
            for (final aw in a) {
              if ((aw.auftrag.richter ?? '').isNotEmpty) {
                rows.add(_RegisterRow(
                  rolle: 'Richter',
                  name: aw.auftrag.richter!,
                  ortAz: aw.auftrag.gericht ?? '',
                  kontakt: aw.auftrag.aktenzeichen ?? '',
                ));
              }
              if ((aw.auftrag.gericht ?? '').isNotEmpty) {
                rows.add(_RegisterRow(
                  rolle: 'Gericht',
                  name: aw.auftrag.gericht!,
                  ortAz: aw.auftrag.gerichtsort ?? '',
                  kontakt: aw.auftrag.aktenzeichen ?? '',
                ));
              }
            }
            for (final m in manuell) {
              rows.add(_RegisterRow(
                rolle: m.rolle,
                name: [m.name, m.firma]
                    .whereType<String>()
                    .where((s) => s.isNotEmpty)
                    .join(' · '),
                ortAz: [m.plz, m.ort, m.aktenzeichen]
                    .whereType<String>()
                    .where((s) => s.isNotEmpty)
                    .join(' · '),
                kontakt: m.email ?? m.telefon ?? '',
                manuell: m,
              ));
            }
            final q = _query.toLowerCase();
            final filtered = q.isEmpty
                ? rows
                : rows.where((r) =>
                    r.name.toLowerCase().contains(q) ||
                    r.ortAz.toLowerCase().contains(q) ||
                    r.kontakt.toLowerCase().contains(q) ||
                    r.rolle.toLowerCase().contains(q)).toList();
            if (filtered.isEmpty) {
              return const EmptyListState(
                icon: Icons.gavel_outlined,
                title: 'Keine Einträge',
                hint: 'Sobald Auftraggeber, Gerichte oder manuelle Einträge '
                    'angelegt sind, erscheinen sie hier.',
              );
            }
            return DataTableCard(
              child: DataTable(
                showCheckboxColumn: false,
                headingRowColor: WidgetStateProperty.all(
                  Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                columns: const [
                  DataColumn(label: Text('Rolle')),
                  DataColumn(label: Text('Name / Firma')),
                  DataColumn(label: Text('Ort / Az.')),
                  DataColumn(label: Text('Kontakt')),
                  DataColumn(label: Text('')),
                ],
                rows: [
                  for (final r in filtered)
                    DataRow(
                      onSelectChanged: r.manuell == null
                          ? null
                          : (_) => _openEditor(eintrag: r.manuell),
                      cells: [
                        DataCell(_RolleBadge(rolle: r.rolle)),
                        DataCell(Text(r.name)),
                        DataCell(Text(r.ortAz)),
                        DataCell(Text(r.kontakt)),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (r.manuell != null) ...[
                              IconButton(
                                tooltip: 'Bearbeiten',
                                icon: const Icon(Icons.edit_outlined,
                                    size: 18),
                                onPressed: () =>
                                    _openEditor(eintrag: r.manuell),
                              ),
                              IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline,
                                    size: 18),
                                onPressed: () => ref
                                    .read(befangenheitRepositoryProvider)
                                    .delete(r.manuell!.id),
                              ),
                            ] else
                              const Tooltip(
                                message:
                                    'Eintrag stammt aus Akte/Auftrag — '
                                    'Bearbeitung dort.',
                                child: Icon(Icons.lock_outline,
                                    size: 16, color: Colors.grey),
                              ),
                          ],
                        )),
                      ],
                    ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  Future<void> _openEditor({BefangenheitsEintraegeData? eintrag}) async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => _BefangenheitsForm(eintrag: eintrag),
    );
  }
}

class _RegisterRow {
  final String rolle;
  final String name;
  final String ortAz;
  final String kontakt;
  final BefangenheitsEintraegeData? manuell;
  const _RegisterRow({
    required this.rolle,
    required this.name,
    required this.ortAz,
    required this.kontakt,
    this.manuell,
  });
}

class _RolleBadge extends StatelessWidget {
  const _RolleBadge({required this.rolle});
  final String rolle;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (rolle) {
      'Auftraggeber' => (BadgeColors.blueBg, BadgeColors.blueFg),
      'Richter' => (BadgeColors.redBg, BadgeColors.redFg),
      'Gericht' => (BadgeColors.amberBg, BadgeColors.amberFg),
      'Beteiligter' => (BadgeColors.indigoBg, BadgeColors.indigoFg),
      _ => (BadgeColors.slateBg, BadgeColors.slateFg),
    };
    return PillBadge(text: rolle, background: bg, foreground: fg);
  }
}

class _BefangenheitsForm extends ConsumerStatefulWidget {
  const _BefangenheitsForm({this.eintrag});
  final BefangenheitsEintraegeData? eintrag;
  @override
  ConsumerState<_BefangenheitsForm> createState() => _BefangenheitsFormState();
}

class _BefangenheitsFormState extends ConsumerState<_BefangenheitsForm> {
  late final _name = TextEditingController(text: widget.eintrag?.name);
  late final _firma = TextEditingController(text: widget.eintrag?.firma);
  late final _anschrift =
      TextEditingController(text: widget.eintrag?.anschrift);
  late final _plz = TextEditingController(text: widget.eintrag?.plz);
  late final _ort = TextEditingController(text: widget.eintrag?.ort);
  late final _telefon = TextEditingController(text: widget.eintrag?.telefon);
  late final _email = TextEditingController(text: widget.eintrag?.email);
  late final _aktenzeichen =
      TextEditingController(text: widget.eintrag?.aktenzeichen);
  late final _gericht = TextEditingController(text: widget.eintrag?.gericht);
  late final _notiz = TextEditingController(text: widget.eintrag?.notiz);
  late String _rolle = widget.eintrag?.rolle ?? 'Beteiligter';
  bool _saving = false;

  static const _rollen = [
    'Auftraggeber',
    'Antragsteller',
    'Antragsgegner',
    'Kläger',
    'Beklagter',
    'Anwalt Kläger',
    'Anwalt Beklagter',
    'Richter',
    'Gericht',
    'Beteiligter',
    'Sachverständiger',
    'Sonstiger',
  ];

  @override
  void dispose() {
    for (final c in [
      _name, _firma, _anschrift, _plz, _ort, _telefon, _email,
      _aktenzeichen, _gericht, _notiz,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bitte mindestens den Namen angeben.')));
      return;
    }
    setState(() => _saving = true);
    final companion = BefangenheitsEintraegeCompanion(
      id: widget.eintrag == null
          ? const Value.absent()
          : Value(widget.eintrag!.id),
      rolle: Value(_rolle),
      name: Value(_name.text.trim()),
      firma: Value(_firma.text.trim().isEmpty ? null : _firma.text.trim()),
      anschrift: Value(_anschrift.text.trim().isEmpty
          ? null
          : _anschrift.text.trim()),
      plz: Value(_plz.text.trim().isEmpty ? null : _plz.text.trim()),
      ort: Value(_ort.text.trim().isEmpty ? null : _ort.text.trim()),
      telefon:
          Value(_telefon.text.trim().isEmpty ? null : _telefon.text.trim()),
      email: Value(_email.text.trim().isEmpty ? null : _email.text.trim()),
      aktenzeichen: Value(_aktenzeichen.text.trim().isEmpty
          ? null
          : _aktenzeichen.text.trim()),
      gericht:
          Value(_gericht.text.trim().isEmpty ? null : _gericht.text.trim()),
      notiz: Value(_notiz.text.trim().isEmpty ? null : _notiz.text.trim()),
    );
    try {
      await ref.read(befangenheitRepositoryProvider).upsert(companion);
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.gavel_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.eintrag == null
                          ? 'Neuer Eintrag im Befangenheits-Register'
                          : 'Eintrag bearbeiten',
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
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _rolle,
                      decoration: const InputDecoration(labelText: 'Rolle'),
                      items: [
                        for (final r in _rollen)
                          DropdownMenuItem(value: r, child: Text(r)),
                      ],
                      onChanged: (v) => setState(() => _rolle = v ?? _rolle),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                          labelText: 'Name *',
                          hintText: 'z. B. Max Mustermann'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _firma,
                      decoration: const InputDecoration(
                          labelText: 'Firma / Behörde',
                          hintText: 'z. B. Musterbau GmbH'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _anschrift,
                      decoration: const InputDecoration(
                          labelText: 'Straße / Anschrift'),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _plz,
                          decoration:
                              const InputDecoration(labelText: 'PLZ'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _ort,
                          decoration:
                              const InputDecoration(labelText: 'Ort'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _telefon,
                          decoration:
                              const InputDecoration(labelText: 'Telefon'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _email,
                          decoration:
                              const InputDecoration(labelText: 'E-Mail'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _aktenzeichen,
                          decoration: const InputDecoration(
                              labelText: 'Aktenzeichen'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _gericht,
                          decoration: const InputDecoration(
                              labelText: 'Gericht / Behörde'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notiz,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          labelText: 'Notiz / Befangenheitsgrund'),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () =>
                            Navigator.of(context, rootNavigator: true).pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check, size: 16),
                    label: const Text('Speichern'),
                    onPressed: _saving ? null : _save,
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
