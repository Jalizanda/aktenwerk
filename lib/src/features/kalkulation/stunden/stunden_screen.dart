import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../features/akten/partner/partner_repository.dart';
import '../../../features/system/benutzer/benutzer_repository.dart';
import '../../../features/system/einstellungen/einstellungen_repository.dart';
import '../../../features/system/einstellungen/honorargruppe_service.dart';
import '../../../data/database/database_provider.dart';
import '../../../shared/widgets/badges.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'stunden_repository.dart';

final stundenQueryProvider = StateProvider<String>((ref) => '');

class StundenScreen extends ConsumerStatefulWidget {
  const StundenScreen({super.key});

  @override
  ConsumerState<StundenScreen> createState() => _StundenScreenState();
}

class _StundenScreenState extends ConsumerState<StundenScreen> {
  int _sortCol = 0;
  bool _sortAsc = false;

  void _onSort(int col, bool asc) =>
      setState(() {
        _sortCol = col;
        _sortAsc = asc;
      });

  Comparable<Object> _key(StundenWithAuftrag s, int col) {
    String l(String? v) => (v ?? '').toLowerCase();
    return switch (col) {
      0 => s.stunde.datum.toIso8601String(),
      1 => l(s.auftrag?.aktenzeichen),
      2 => l(s.stunde.taetigkeit),
      3 => s.stunde.minuten,
      4 => s.stunde.satz ?? 0,
      5 => (s.stunde.minuten / 60.0) * (s.stunde.satz ?? 0),
      6 => s.stunde.abgerechnet ? '1' : '0',
      _ => s.stunde.datum.toIso8601String(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(stundenListProvider);
    final filter = ref.watch(stundenFilterProvider);
    final query = ref.watch(stundenQueryProvider).trim().toLowerCase();

    List<StundenWithAuftrag> applyQuery(List<StundenWithAuftrag> items) {
      if (query.isEmpty) return items;
      return items.where((s) {
        final parts = [
          s.stunde.taetigkeit,
          s.stunde.notiz,
          s.auftrag?.aktenzeichen,
          s.auftrag?.betreff,
          s.auftrag?.bezeichnung,
        ]
            .whereType<String>()
            .map((v) => v.toLowerCase())
            .join(' ');
        return parts.contains(query);
      }).toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.schedule_outlined,
          title: 'Stunden',
          subtitle: 'Zeiterfassung pro Auftrag',
          searchHint: 'Suche Tätigkeit, Notiz, Aktenzeichen, Betreff …',
          onSearchChanged: (v) =>
              ref.read(stundenQueryProvider.notifier).state = v,
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neuer Eintrag'),
              onPressed: () => _show(context, ref),
            ),
          ],
          filters: [
            DropdownButtonHideUnderline(
              child: DropdownButton<bool?>(
                value: filter.abgerechnet,
                hint: const Text('Alle Buchungen'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Alle Buchungen')),
                  DropdownMenuItem(value: false, child: Text('Nur offene')),
                  DropdownMenuItem(
                      value: true, child: Text('Nur abgerechnete')),
                ],
                onChanged: (v) => ref
                    .read(stundenFilterProvider.notifier)
                    .update((f) => v == null
                        ? f.copyWith(clearAbgerechnet: true)
                        : f.copyWith(abgerechnet: v)),
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        const _TimerBar(),
        const Divider(height: 1),
        async.maybeWhen(
          data: (items) => _AuftragSummary(items: applyQuery(items)),
          orElse: () => const SizedBox.shrink(),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (all) {
              final items = applyQuery(all);
              if (items.isEmpty) {
                return const EmptyListState(
                    icon: Icons.schedule_outlined,
                    title: 'Keine Zeit-Buchungen');
              }
              final sorted = [...items]..sort((a, b) {
                  final ka = _key(a, _sortCol);
                  final kb = _key(b, _sortCol);
                  final cmp = Comparable.compare(ka, kb);
                  return _sortAsc ? cmp : -cmp;
                });
              return DataTableCard(
                    child: DataTable(
              showCheckboxColumn: false,
                      sortColumnIndex: _sortCol,
                      sortAscending: _sortAsc,
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      columns: [
                        DataColumn(label: const Text('Datum'), onSort: _onSort),
                        DataColumn(label: const Text('Auftrag'), onSort: _onSort),
                        DataColumn(label: const Text('Tätigkeit'), onSort: _onSort),
                        DataColumn(label: const Text('Dauer'), numeric: true, onSort: _onSort),
                        DataColumn(label: const Text('Satz €'), numeric: true, onSort: _onSort),
                        DataColumn(label: const Text('Betrag €'), numeric: true, onSort: _onSort),
                        DataColumn(label: const Text('Abgerechnet'), onSort: _onSort),
                        const DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final s in sorted) _row(context, ref, s),
                      ],
                    ),
                  );
            },
          ),
        ),
      ],
    );
  }

  DataRow _row(
      BuildContext context, WidgetRef ref, StundenWithAuftrag s) {
    final dateFmt = DateFormat('dd.MM.yyyy', 'de');
    final dur = _formatDuration(s.stunde.minuten);
    final betrag = (s.stunde.minuten / 60.0) * (s.stunde.satz ?? 0);
    return DataRow(
      onSelectChanged: (_) => _show(context, ref, s),
      cells: [
        DataCell(Text(dateFmt.format(s.stunde.datum))),
        DataCell(Text(s.auftrag?.aktenzeichen ?? '—')),
        DataCell(Text(s.stunde.taetigkeit ?? '')),
        DataCell(Text(dur)),
        DataCell(Text(s.stunde.satz?.toStringAsFixed(2) ?? '')),
        DataCell(Text(betrag.toStringAsFixed(2))),
        DataCell(Checkbox(
          value: s.stunde.abgerechnet,
          onChanged: (v) async {
            await ref.read(stundenRepositoryProvider).upsert(
                  StundenCompanion(
                    id: Value(s.stunde.id),
                    abgerechnet: Value(v ?? false),
                  ),
                );
          },
        )),
        DataCell(IconButton(
          tooltip: 'Löschen',
          icon: const Icon(Icons.delete_outline, size: 20),
          onPressed: () async {
            await ref.read(stundenRepositoryProvider).delete(s.stunde.id);
          },
        )),
      ],
    );
  }

  Future<void> _show(BuildContext context, WidgetRef ref,
      [StundenWithAuftrag? s]) async {
    await showDialog(
      context: context,
      builder: (_) => _StundenForm(eintrag: s),
    );
  }
}

/// Öffnet den Stunden-Editor — auch aus anderen Modulen (z.B. Akten-Tab)
/// zum direkten Bearbeiten eines Eintrags aufrufbar.
Future<void> showStundenEditor(BuildContext context,
    {StundenWithAuftrag? eintrag, int? prefillAuftragId}) async {
  await showDialog(
    context: context,
    useRootNavigator: true,
    builder: (_) =>
        _StundenForm(eintrag: eintrag, prefillAuftragId: prefillAuftragId),
  );
}

String _formatDuration(int minuten) {
  final h = (minuten / 60).floor();
  final m = minuten % 60;
  return '${h.toString()}:${m.toString().padLeft(2, '0')}';
}

/// Summary-Tabelle pro Auftrag: Akt.-Zeichen, Auftraggeber, Anzahl Einträge,
/// Stunden, Netto-Betrag — plus Gesamt-KPI in einer Kopfzeile.
class _AuftragSummary extends StatelessWidget {
  const _AuftragSummary({required this.items});
  final List<StundenWithAuftrag> items;

  static final _money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final groups = <int?, _Agg>{};
    for (final s in items) {
      final key = s.stunde.auftragId;
      final agg = groups.putIfAbsent(key, () => _Agg(auftrag: s.auftrag));
      agg.minuten += s.stunde.minuten;
      agg.betrag += (s.stunde.minuten / 60.0) * (s.stunde.satz ?? 0);
      agg.count += 1;
    }
    final gesamtMin =
        items.fold<int>(0, (a, s) => a + s.stunde.minuten);
    final gesamtEur =
        items.fold<double>(0, (a, s) => a + (s.stunde.minuten / 60.0) * (s.stunde.satz ?? 0));

    return ExpansionTile(
      title: Row(
        children: [
          const Icon(Icons.summarize_outlined, size: 18),
          const SizedBox(width: 8),
          Text('Übersicht pro Auftrag',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: 16),
          Expanded(
            child: Wrap(
              spacing: 16,
              children: [
                _mini('Einträge', '${items.length}'),
                _mini('Stunden',
                    '${(gesamtMin / 60).toStringAsFixed(1)} h'),
                _mini('Betrag', _money.format(gesamtEur)),
              ],
            ),
          ),
        ],
      ),
      tilePadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      childrenPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DataTable(
              showCheckboxColumn: false,
            headingRowColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            columns: const [
              DataColumn(label: Text('Aktenzeichen')),
              DataColumn(label: Text('Auftraggeber')),
              DataColumn(label: Text('Betreff')),
              DataColumn(label: Text('Einträge'), numeric: true),
              DataColumn(label: Text('Stunden'), numeric: true),
              DataColumn(label: Text('Betrag €'), numeric: true),
            ],
            rows: [
              for (final g in groups.values)
                DataRow(cells: [
                  DataCell(Text(g.auftrag?.aktenzeichen ?? '—',
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12))),
                  DataCell(Text('—')),
                  DataCell(SizedBox(
                      width: 240,
                      child: Text(g.auftrag?.betreff ?? '',
                          overflow: TextOverflow.ellipsis))),
                  DataCell(Text('${g.count}')),
                  DataCell(Text('${(g.minuten / 60).toStringAsFixed(2)} h')),
                  DataCell(Text(_money.format(g.betrag),
                      style:
                          const TextStyle(fontWeight: FontWeight.w600))),
                ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mini(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
                color: BadgeColors.slateFg)),
        const SizedBox(width: 6),
        Text(value,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _Agg {
  _Agg({this.auftrag});
  final AuftraegeData? auftrag;
  int minuten = 0;
  double betrag = 0;
  int count = 0;
}

class _TimerBar extends ConsumerStatefulWidget {
  const _TimerBar();
  @override
  ConsumerState<_TimerBar> createState() => _TimerBarState();
}

class _TimerBarState extends ConsumerState<_TimerBar> {
  Timer? _tick;
  final _taetigkeitController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(stundenTimerProvider).running) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _taetigkeitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(stundenTimerProvider);
    final elapsed = state.startedAt == null
        ? Duration.zero
        : DateTime.now().difference(state.startedAt!);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.timer_outlined,
              color: state.running
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Text(
            _formatElapsed(elapsed),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: state.running
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: SizedBox(
              width: 260,
              child: AuftragPickerField(
                label: 'Auftrag',
                auftragId: state.auftragId,
                onChanged: (id) => ref
                    .read(stundenTimerProvider.notifier)
                    .update((s) => s.copyWith(auftragId: id)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 260,
            child: TextField(
              controller: _taetigkeitController,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Tätigkeit',
              ),
              onChanged: (v) => ref
                  .read(stundenTimerProvider.notifier)
                  .update((s) => s.copyWith(taetigkeit: v)),
            ),
          ),
          const SizedBox(width: 12),
          if (!state.running)
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start'),
              onPressed: state.auftragId == null
                  ? null
                  : () => ref
                      .read(stundenTimerProvider.notifier)
                      .update((s) => s.copyWith(startedAt: DateTime.now())),
            )
          else
            FilledButton.icon(
              icon: const Icon(Icons.stop),
              label: const Text('Buchen'),
              onPressed: () => _stopAndBook(elapsed, state),
            ),
          if (state.running) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.cancel_outlined),
              tooltip: 'Abbrechen',
              onPressed: () => ref
                  .read(stundenTimerProvider.notifier)
                  .update((s) => s.copyWith(reset: true)),
            ),
          ],
        ],
      ),
    );
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  Future<void> _stopAndBook(Duration elapsed, TimerState state) async {
    if (state.auftragId == null) return;
    final minuten = elapsed.inMinutes;
    final settingSatz = await ref
        .read(einstellungenRepositoryProvider)
        .getDouble(SettingsKeys.standardStundensatz);
    final benutzer = await ref.read(benutzerRepositoryProvider).getActive();
    final satz = settingSatz ?? benutzer?.standardStundensatz;
    await ref.read(stundenRepositoryProvider).upsert(StundenCompanion.insert(
          auftragId: Value(state.auftragId),
          datum: Value(DateTime.now()),
          beginn: Value(state.startedAt),
          ende: Value(DateTime.now()),
          minuten: Value(minuten == 0 ? 1 : minuten),
          satz: Value(satz),
          taetigkeit: Value(state.taetigkeit),
        ));
    ref.read(stundenTimerProvider.notifier).update((s) => s.copyWith(reset: true));
    _taetigkeitController.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$minuten Minuten gebucht')),
      );
    }
  }
}

class _StundenForm extends ConsumerStatefulWidget {
  const _StundenForm({this.eintrag, this.prefillAuftragId});
  final int? prefillAuftragId;
  final StundenWithAuftrag? eintrag;
  @override
  ConsumerState<_StundenForm> createState() => _StundenFormState();
}

class _StundenFormState extends ConsumerState<_StundenForm> {
  final _formKey = GlobalKey<FormState>();
  int? _auftragId;
  int? _partnerId;
  DateTime _datum = DateTime.now();
  late final _minuten = TextEditingController(
      text: widget.eintrag?.stunde.minuten.toString() ?? '60');
  late final _satz = TextEditingController(
      text: widget.eintrag?.stunde.satz?.toStringAsFixed(2) ?? '');
  late final _taetigkeit = TextEditingController(
      text: widget.eintrag?.stunde.taetigkeit ?? '');
  late final _notiz =
      TextEditingController(text: widget.eintrag?.stunde.notiz ?? '');
  bool _abgerechnet = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _auftragId = widget.eintrag?.stunde.auftragId ?? widget.prefillAuftragId;
    _partnerId = widget.eintrag?.stunde.partnerId;
    _datum = widget.eintrag?.stunde.datum ?? DateTime.now();
    _abgerechnet = widget.eintrag?.stunde.abgerechnet ?? false;
    _prefillSatz();
  }

  Future<void> _prefillSatz() async {
    if (_satz.text.isNotEmpty) return;
    final repo = ref.read(einstellungenRepositoryProvider);
    // 1) Wenn die zugeordnete Akte einer JVEG-Honorargruppe (M1/M2/M3)
    //    angehört, deren Satz aus den Einstellungen ziehen.
    if (_auftragId != null) {
      final db = ref.read(appDatabaseProvider);
      final auftrag = await (db.select(db.auftraege)
            ..where((t) => t.id.equals(_auftragId!)))
          .getSingleOrNull();
      final hg = auftrag?.honorargruppe;
      if (hg != null && hg.trim().isNotEmpty) {
        final hgSatz = await stundensatzFuerHonorargruppe(repo, hg);
        if (mounted && hgSatz > 0) {
          _satz.text = hgSatz.toStringAsFixed(2);
          return;
        }
      }
    }
    // 2) Fallback: Standard-Stundensatz aus Einstellungen / Benutzer.
    final settingSatz = await repo.getDouble(SettingsKeys.standardStundensatz);
    final benutzer = await ref.read(benutzerRepositoryProvider).getActive();
    final s = settingSatz ?? benutzer?.standardStundensatz;
    if (mounted && s != null) _satz.text = s.toStringAsFixed(2);
  }

  @override
  void dispose() {
    for (final c in [_minuten, _satz, _taetigkeit, _notiz]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.eintrag != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final minuten = int.tryParse(_minuten.text.trim()) ?? 0;
    final satz =
        double.tryParse(_satz.text.replaceAll(',', '.'));
    final companion = StundenCompanion(
      id: _isEdit ? Value(widget.eintrag!.stunde.id) : const Value.absent(),
      auftragId: Value(_auftragId),
      partnerId: Value(_partnerId),
      datum: Value(_datum),
      minuten: Value(minuten),
      satz: Value(satz),
      taetigkeit: _nt(_taetigkeit),
      notiz: _nt(_notiz),
      abgerechnet: Value(_abgerechnet),
    );
    try {
      await ref.read(stundenRepositoryProvider).upsert(companion);
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
      title: _isEdit ? 'Zeit-Buchung bearbeiten' : 'Neue Zeit-Buchung',
      saving: _saving,
      maxHeight: 620,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(stundenRepositoryProvider)
              .delete(widget.eintrag!.stunde.id)
          : null,
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: AuftragPickerField(
                      auftragId: _auftragId,
                      onChanged: (id) =>
                          setState(() => _auftragId = id),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: LabeledField(
                      'Tätigkeit',
                      TextFormField(controller: _taetigkeit),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row3(
                a: DateField(
                  label: 'Datum',
                  value: _datum,
                  onChanged: (v) =>
                      setState(() => _datum = v ?? DateTime.now()),
                ),
                b: LabeledField(
                  'Dauer (Minuten)',
                  TextFormField(
                    controller: _minuten,
                    keyboardType: TextInputType.number,
                    validator: (v) =>
                        int.tryParse(v ?? '') == null ? 'Zahl' : null,
                  ),
                ),
                c: LabeledField(
                  'Satz (€)',
                  TextFormField(
                    controller: _satz,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _PartnerDropdown(
                partnerId: _partnerId,
                onChanged: (v) => setState(() => _partnerId = v),
              ),
              const SizedBox(height: 12),
              LabeledField(
                  'Notiz',
                  TextFormField(
                      controller: _notiz, minLines: 2, maxLines: 4)),
              const SizedBox(height: 12),
              Row(children: [
                Checkbox(
                    value: _abgerechnet,
                    onChanged: (v) =>
                        setState(() => _abgerechnet = v ?? false)),
                const Text('bereits abgerechnet'),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartnerDropdown extends ConsumerWidget {
  const _PartnerDropdown({required this.partnerId, required this.onChanged});
  final int? partnerId;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(partnerListProvider);
    return LabeledField(
      'Durch Partner/Subunternehmer (optional — zählt dann als Fremdleistung)',
      async.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Partner laden fehlgeschlagen: $e'),
        data: (items) => DropdownButtonFormField<int?>(
          initialValue: items.any((p) => p.id == partnerId) ? partnerId : null,
          isDense: true,
          items: [
            const DropdownMenuItem<int?>(
                value: null, child: Text('— Eigenleistung —')),
            for (final p in items)
              DropdownMenuItem<int?>(
                value: p.id,
                child: Text(
                    '${p.firma}${(p.fachgebiet ?? "").isEmpty ? "" : " · ${p.fachgebiet}"}'),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
