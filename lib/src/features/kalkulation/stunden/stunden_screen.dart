import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../features/system/benutzer/benutzer_repository.dart';
import '../../../features/system/einstellungen/einstellungen_repository.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'stunden_repository.dart';

class StundenScreen extends ConsumerWidget {
  const StundenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(stundenListProvider);
    final filter = ref.watch(stundenFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.schedule_outlined,
          title: 'Stunden',
          subtitle: 'Zeiterfassung pro Auftrag',
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
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) => items.isEmpty
                ? const EmptyListState(
                    icon: Icons.schedule_outlined,
                    title: 'Keine Zeit-Buchungen')
                : DataTableCard(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      columns: const [
                        DataColumn(label: Text('Datum')),
                        DataColumn(label: Text('Auftrag')),
                        DataColumn(label: Text('Tätigkeit')),
                        DataColumn(label: Text('Dauer'), numeric: true),
                        DataColumn(label: Text('Satz €'), numeric: true),
                        DataColumn(label: Text('Betrag €'), numeric: true),
                        DataColumn(label: Text('Abgerechnet')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final s in items) _row(context, ref, s),
                      ],
                    ),
                  ),
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

String _formatDuration(int minuten) {
  final h = (minuten / 60).floor();
  final m = minuten % 60;
  return '${h.toString()}:${m.toString().padLeft(2, '0')}';
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
  const _StundenForm({this.eintrag});
  final StundenWithAuftrag? eintrag;
  @override
  ConsumerState<_StundenForm> createState() => _StundenFormState();
}

class _StundenFormState extends ConsumerState<_StundenForm> {
  final _formKey = GlobalKey<FormState>();
  int? _auftragId;
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
    _auftragId = widget.eintrag?.stunde.auftragId;
    _datum = widget.eintrag?.stunde.datum ?? DateTime.now();
    _abgerechnet = widget.eintrag?.stunde.abgerechnet ?? false;
    _prefillSatz();
  }

  Future<void> _prefillSatz() async {
    if (_satz.text.isNotEmpty) return;
    final settingSatz = await ref
        .read(einstellungenRepositoryProvider)
        .getDouble(SettingsKeys.standardStundensatz);
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
      datum: Value(_datum),
      minuten: Value(minuten),
      satz: Value(satz),
      taetigkeit: _nt(_taetigkeit),
      notiz: _nt(_notiz),
      abgerechnet: Value(_abgerechnet),
    );
    try {
      await ref.read(stundenRepositoryProvider).upsert(companion);
      if (mounted) Navigator.pop(context, true);
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
      onCancel: () => Navigator.pop(context, false),
      onSave: _save,
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuftragPickerField(
                auftragId: _auftragId,
                onChanged: (id) => setState(() => _auftragId = id),
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
              LabeledField(
                  'Tätigkeit', TextFormField(controller: _taetigkeit)),
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
