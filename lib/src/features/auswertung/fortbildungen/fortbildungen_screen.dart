import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftraege_repository.dart';
import '../../../features/akten/kunden/kunden_repository.dart';
import '../../../shared/widgets/badges.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/file_upload_section.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'fortbildungen_repository.dart';

class FortbildungenScreen extends ConsumerStatefulWidget {
  const FortbildungenScreen({super.key});
  @override
  ConsumerState<FortbildungenScreen> createState() =>
      _FortbildungenScreenState();
}

class _FortbildungenScreenState
    extends ConsumerState<FortbildungenScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(fortbildungenListProvider);
    final summen = ref.watch(fortbildungenSummenProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.school_outlined,
          title: 'Fortbildungen & Befangenheit',
          subtitle: 'Nachweise für die Wiederbestellung + Befangenheits-Register',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neue Fortbildung'),
              onPressed: () => _show(context, ref),
            ),
          ],
          searchHint: 'Suche Titel, Veranstalter, Thema …',
          onSearchChanged: (v) => ref
              .read(fortbildungenFilterProvider.notifier)
              .update((f) => f.copyWith(query: v)),
        ),
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Fortbildungen'),
            Tab(text: 'Befangenheits-Register'),
          ],
          labelColor: Theme.of(context).colorScheme.primary,
          indicatorColor: Theme.of(context).colorScheme.primary,
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _FortbildungenTab(
                async: async,
                summen: summen,
                onShow: (f) => _show(context, ref, f),
              ),
              const _BefangenheitsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _show(BuildContext context, WidgetRef ref,
      [FortbildungenData? f]) async {
    await showDialog(
      context: context,
      builder: (_) => _FortbildungForm(fortbildung: f),
    );
  }
}

/// Fortbildungen-Tab (ursprünglicher Hauptinhalt).
class _FortbildungenTab extends ConsumerWidget {
  const _FortbildungenTab({
    required this.async,
    required this.summen,
    required this.onShow,
  });
  final AsyncValue<List<FortbildungenData>> async;
  final AsyncValue<Map<int, double>> summen;
  final void Function(FortbildungenData) onShow;

  static final _fmt = DateFormat('dd.MM.yyyy', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        summen.when(
          data: (s) => _SummenRow(summen: s),
          loading: () => const SizedBox(),
          error: (_, _) => const SizedBox(),
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) => items.isEmpty
                ? const EmptyListState(
                    icon: Icons.school_outlined,
                    title: 'Keine Fortbildungen erfasst')
                : DataTableCard(
                    child: DataTable(
              showCheckboxColumn: false,
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      columns: const [
                        DataColumn(label: Text('Titel')),
                        DataColumn(label: Text('Veranstalter')),
                        DataColumn(label: Text('Von')),
                        DataColumn(label: Text('Bis')),
                        DataColumn(label: Text('Stunden'), numeric: true),
                        DataColumn(label: Text('Kosten €'), numeric: true),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final f in items)
                          DataRow(
                            onSelectChanged: (_) => onShow(f),
                            cells: [
                              DataCell(Text(f.titel)),
                              DataCell(Text(f.veranstalter ?? '')),
                              DataCell(Text(f.datumVon == null
                                  ? ''
                                  : _fmt.format(f.datumVon!))),
                              DataCell(Text(f.datumBis == null
                                  ? ''
                                  : _fmt.format(f.datumBis!))),
                              DataCell(
                                  Text(f.stunden.toStringAsFixed(1))),
                              DataCell(Text(f.kosten.toStringAsFixed(2))),
                              DataCell(IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                onPressed: () =>
                                    _confirm(context, ref, f),
                              )),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirm(
      BuildContext context, WidgetRef ref, FortbildungenData f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Fortbildung löschen?'),
        content: Text('«${f.titel}» wird gelöscht.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
              child: const Text('Abbrechen')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(fortbildungenRepositoryProvider).delete(f.id);
    }
  }
}

class _SummenRow extends StatelessWidget {
  const _SummenRow({required this.summen});
  final Map<int, double> summen;
  @override
  Widget build(BuildContext context) {
    if (summen.isEmpty) return const SizedBox();
    final jahre = summen.keys.toList()..sort((a, b) => b.compareTo(a));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final j in jahre.take(4))
            Chip(
              label: Text('$j: ${summen[j]!.toStringAsFixed(1)} Std'),
              backgroundColor:
                  Theme.of(context).colorScheme.secondaryContainer,
            ),
        ],
      ),
    );
  }
}

class _FortbildungForm extends ConsumerStatefulWidget {
  const _FortbildungForm({this.fortbildung});
  final FortbildungenData? fortbildung;
  @override
  ConsumerState<_FortbildungForm> createState() => _FortbildungFormState();
}

class _FortbildungFormState extends ConsumerState<_FortbildungForm> {
  final _formKey = GlobalKey<FormState>();
  late final _titel =
      TextEditingController(text: widget.fortbildung?.titel ?? '');
  late final _veranstalter =
      TextEditingController(text: widget.fortbildung?.veranstalter ?? '');
  late final _ort =
      TextEditingController(text: widget.fortbildung?.ort ?? '');
  late final _sachgebiet =
      TextEditingController(text: widget.fortbildung?.sachgebiet ?? '');
  late final _thema =
      TextEditingController(text: widget.fortbildung?.thema ?? '');
  late final _stunden = TextEditingController(
      text: widget.fortbildung?.stunden.toStringAsFixed(1) ?? '');
  late final _gebuehr = TextEditingController(
      text: widget.fortbildung?.gebuehr.toStringAsFixed(2) ?? '');
  late final _kosten = TextEditingController(
      text: widget.fortbildung?.kosten.toStringAsFixed(2) ?? '');
  late final _notiz =
      TextEditingController(text: widget.fortbildung?.notiz ?? '');
  DateTime? _von;
  DateTime? _bis;
  bool _saving = false;
  UploadedFile? _nachweis;

  @override
  void initState() {
    super.initState();
    _von = widget.fortbildung?.datumVon;
    _bis = widget.fortbildung?.datumBis;
    final url = widget.fortbildung?.nachweisStorageUrl;
    if (url != null && url.isNotEmpty) {
      _nachweis = UploadedFile(
        storageUrl: url,
        dateiname: widget.fortbildung?.nachweisDateiname ?? 'Nachweis',
        mimeType: widget.fortbildung?.nachweisMimeType,
        groesse: widget.fortbildung?.nachweisGroesse,
      );
    }
  }

  @override
  void dispose() {
    for (final c in [
      _titel, _veranstalter, _ort, _sachgebiet, _thema,
      _stunden, _gebuehr, _kosten, _notiz,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.fortbildung != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final stunden =
        double.tryParse(_stunden.text.replaceAll(',', '.')) ?? 0;
    final gebuehr =
        double.tryParse(_gebuehr.text.replaceAll(',', '.')) ?? 0;
    final kosten =
        double.tryParse(_kosten.text.replaceAll(',', '.')) ?? gebuehr;
    final companion = FortbildungenCompanion(
      id: _isEdit ? Value(widget.fortbildung!.id) : const Value.absent(),
      titel: Value(_titel.text.trim()),
      veranstalter: _nt(_veranstalter),
      ort: _nt(_ort),
      sachgebiet: _nt(_sachgebiet),
      thema: _nt(_thema),
      datumVon: Value(_von),
      datumBis: Value(_bis),
      stunden: Value(stunden),
      gebuehr: Value(gebuehr),
      kosten: Value(kosten),
      notiz: _nt(_notiz),
      nachweisStorageUrl: Value(_nachweis?.storageUrl),
      nachweisDateiname: Value(_nachweis?.dateiname),
      nachweisMimeType: Value(_nachweis?.mimeType),
      nachweisGroesse: Value(_nachweis?.groesse),
    );
    try {
      await ref.read(fortbildungenRepositoryProvider).upsert(companion);
      if (mounted) Navigator.of(context, rootNavigator: true).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Value<String?> _nt(TextEditingController c) {
    final v = c.text.trim();
    return Value(v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    return StandardFormDialog(
      title:
          _isEdit ? 'Fortbildung bearbeiten' : 'Neue Fortbildung',
      saving: _saving,
      maxHeight: 640,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(fortbildungenRepositoryProvider)
              .delete(widget.fortbildung!.id)
          : null,
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabeledField(
                'Titel',
                TextFormField(
                  controller: _titel,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Erforderlich' : null,
                ),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                    'Veranstalter',
                    TextFormField(controller: _veranstalter)),
                right:
                    LabeledField('Ort', TextFormField(controller: _ort)),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                    'Sachgebiet',
                    TextFormField(controller: _sachgebiet)),
                right: LabeledField(
                    'Thema (Details)',
                    TextFormField(controller: _thema)),
              ),
              const SizedBox(height: 12),
              Row2(
                left: DateField(
                    label: 'Von',
                    value: _von,
                    onChanged: (v) => setState(() => _von = v)),
                right: DateField(
                    label: 'Bis',
                    value: _bis,
                    onChanged: (v) => setState(() => _bis = v)),
              ),
              const SizedBox(height: 12),
              Row3(
                a: LabeledField(
                  'Stunden (UE à 45 Min.)',
                  TextFormField(
                      controller: _stunden,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true)),
                ),
                b: LabeledField(
                  'Gebühr (€)',
                  TextFormField(
                      controller: _gebuehr,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true)),
                ),
                c: LabeledField(
                  'Gesamtkosten (€)',
                  TextFormField(
                      controller: _kosten,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true)),
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                  'Notiz',
                  TextFormField(
                      controller: _notiz, minLines: 2, maxLines: 4)),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              FileUploadSection(
                title: 'Teilnahmebescheinigung / Zertifikat',
                storagePrefix: 'fortbildungen',
                kind: UploadKind.pdf,
                file: _nachweis,
                hint:
                    'PDF der Bescheinigung wird zu dieser Fortbildung gespeichert.',
                onChanged: (f) => setState(() => _nachweis = f),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Befangenheits-Register: Liste aller Auftraggeber + Beteiligten aus Aufträgen.
/// Dient als Nachschlagewerk vor neuer Auftragsannahme.
class _BefangenheitsTab extends ConsumerStatefulWidget {
  const _BefangenheitsTab();
  @override
  ConsumerState<_BefangenheitsTab> createState() =>
      _BefangenheitsTabState();
}

class _BefangenheitsTabState extends ConsumerState<_BefangenheitsTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final auftraege = ref.watch(auftraegeListProvider);
    final kundenAsync = ref.watch(kundenListProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: 'Suche nach Name / Firma / Ort / Aktenzeichen',
                  ),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Builder(builder: (_) {
            final a = auftraege.valueOrNull ?? const [];
            final k = kundenAsync.valueOrNull ?? const [];
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
              // Richter + Gerichte aus Auftrag-Gerichtsdaten
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
            final q = _query.toLowerCase();
            final filtered = q.isEmpty
                ? rows
                : rows.where((r) =>
                    r.name.toLowerCase().contains(q) ||
                    r.ortAz.toLowerCase().contains(q) ||
                    r.kontakt.toLowerCase().contains(q) ||
                    r.rolle.toLowerCase().contains(q)).toList();
            final capped = filtered.take(100).toList();
            if (capped.isEmpty) {
              return const EmptyListState(
                icon: Icons.gavel_outlined,
                title: 'Keine Einträge',
                hint: 'Sobald Auftraggeber oder Gerichte angelegt sind, erscheinen '
                    'sie hier.',
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
                ],
                rows: [
                  for (final r in capped)
                    DataRow(cells: [
                      DataCell(_RolleBadge(rolle: r.rolle)),
                      DataCell(Text(r.name)),
                      DataCell(Text(r.ortAz)),
                      DataCell(Text(r.kontakt)),
                    ]),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _RegisterRow {
  final String rolle;
  final String name;
  final String ortAz;
  final String kontakt;
  const _RegisterRow({
    required this.rolle,
    required this.name,
    required this.ortAz,
    required this.kontakt,
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
