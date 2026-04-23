import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../data/sync/wiedervorlagen_push.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'wiedervorlagen_repository.dart';

final _wiedervorlagenQueryProvider = StateProvider<String>((ref) => '');

class WiedervorlagenScreen extends ConsumerWidget {
  const WiedervorlagenScreen({super.key});
  static final _fmt = DateFormat('dd.MM.yyyy', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(wiedervorlagenListProvider);
    final scope = ref.watch(wiedervorlagenScopeProvider);
    final query = ref.watch(_wiedervorlagenQueryProvider).trim().toLowerCase();

    String scopeLabel(WiedervorlagenScope s) => switch (s) {
          WiedervorlagenScope.alle => 'Alle',
          WiedervorlagenScope.heute => 'Heute',
          WiedervorlagenScope.woche => 'Diese Woche',
          WiedervorlagenScope.ueberfaellig => 'Überfällig',
          WiedervorlagenScope.offen => 'Offen',
          WiedervorlagenScope.erledigt => 'Erledigt',
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.notifications_active_outlined,
          title: 'Wiedervorlagen',
          subtitle: 'Aufgaben mit Fälligkeit pro Auftrag',
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.notifications_outlined, size: 16),
              label: const Text('Benachrichtigungen'),
              onPressed: () async {
                final svc =
                    ref.read(wiedervorlagenPushServiceProvider);
                final ok = await svc.requestPermission();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok
                      ? 'Browser-Benachrichtigungen aktiviert.'
                      : 'Benachrichtigungen wurden nicht erlaubt.'),
                ));
                if (ok) await svc.checkAndNotify();
              },
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neue Wiedervorlage'),
              onPressed: () => _show(context, ref),
            ),
          ],
          searchHint: 'Suche Titel, Anlass, Akte …',
          onSearchChanged: (v) =>
              ref.read(_wiedervorlagenQueryProvider.notifier).state = v,
          filters: [
            SegmentedButton<WiedervorlagenScope>(
              segments: [
                for (final s in WiedervorlagenScope.values)
                  ButtonSegment(value: s, label: Text(scopeLabel(s))),
              ],
              selected: {scope},
              showSelectedIcon: false,
              onSelectionChanged: (s) => ref
                  .read(wiedervorlagenScopeProvider.notifier)
                  .state = s.first,
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (rawItems) {
              final items = query.isEmpty
                  ? rawItems
                  : rawItems.where((w) {
                      final s = [
                        w.eintrag.titel,
                        w.eintrag.anlass ?? '',
                        w.eintrag.beschreibung ?? '',
                        w.auftrag?.aktenzeichen ?? '',
                        w.auftrag?.betreff ?? '',
                      ].join(' ').toLowerCase();
                      return s.contains(query);
                    }).toList();
              return items.isEmpty
                  ? const EmptyListState(
                      icon: Icons.notifications_active_outlined,
                      title: 'Nichts zu tun')
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, i) => _Tile(
                        item: items[i],
                        dateFmt: _fmt,
                      ),
                    );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _show(BuildContext context, WidgetRef ref,
      [WiedervorlageWithAuftrag? w]) async {
    await showDialog(
      context: context,
      builder: (_) => _WiedervorlageForm(eintrag: w),
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.item, required this.dateFmt});
  final WiedervorlageWithAuftrag item;
  final DateFormat dateFmt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final faellig = item.eintrag.faelligAm;
    final overdue = !item.eintrag.erledigt && faellig.isBefore(DateTime.now());
    final color = overdue
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurface;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showDialog(
          context: context,
          builder: (_) => _WiedervorlageForm(eintrag: item),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Checkbox(
                value: item.eintrag.erledigt,
                onChanged: (v) => ref
                    .read(wiedervorlagenRepositoryProvider)
                    .toggleErledigt(item.eintrag.id, v ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.eintrag.titel,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: item.eintrag.erledigt
                            ? TextDecoration.lineThrough
                            : null,
                        color: color,
                      ),
                    ),
                    if ((item.eintrag.beschreibung ?? '').isNotEmpty)
                      Text(item.eintrag.beschreibung!,
                          style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Row(children: [
                      Icon(Icons.event_outlined, size: 14, color: color),
                      const SizedBox(width: 4),
                      Text(dateFmt.format(faellig),
                          style: TextStyle(color: color, fontSize: 12)),
                      if (item.auftrag != null) ...[
                        const SizedBox(width: 16),
                        Icon(Icons.assignment_outlined,
                            size: 14,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(item.auftrag!.aktenzeichen ?? '',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ]),
                  ],
                ),
              ),
              _Prioritaet(item.eintrag.prioritaet),
              IconButton(
                tooltip: 'Löschen',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => ref
                    .read(wiedervorlagenRepositoryProvider)
                    .delete(item.eintrag.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Prioritaet extends StatelessWidget {
  const _Prioritaet(this.prio);
  final String prio;
  @override
  Widget build(BuildContext context) {
    final color = switch (prio) {
      'hoch' => Theme.of(context).colorScheme.error,
      'niedrig' => Theme.of(context).colorScheme.onSurfaceVariant,
      _ => Theme.of(context).colorScheme.primary,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Chip(
        label: Text(prio),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: color),
        labelStyle: TextStyle(color: color, fontSize: 11),
      ),
    );
  }
}

class _WiedervorlageForm extends ConsumerStatefulWidget {
  const _WiedervorlageForm({this.eintrag});
  final WiedervorlageWithAuftrag? eintrag;
  @override
  ConsumerState<_WiedervorlageForm> createState() =>
      _WiedervorlageFormState();
}

class _WiedervorlageFormState
    extends ConsumerState<_WiedervorlageForm> {
  final _formKey = GlobalKey<FormState>();
  late final _titel =
      TextEditingController(text: widget.eintrag?.eintrag.titel ?? '');
  late final _anlass = TextEditingController(
      text: widget.eintrag?.eintrag.anlass ?? '');
  late final _beschreibung = TextEditingController(
      text: widget.eintrag?.eintrag.beschreibung ?? '');
  DateTime _faellig = DateTime.now();
  String _prio = 'normal';
  int? _auftragId;
  bool _erledigt = false;
  bool _saving = false;
  String _wiederholung = 'keine';
  List<_ChecklistItem> _checkliste = [];

  @override
  void initState() {
    super.initState();
    _faellig = widget.eintrag?.eintrag.faelligAm ?? DateTime.now();
    _prio = widget.eintrag?.eintrag.prioritaet ?? 'normal';
    _auftragId = widget.eintrag?.eintrag.auftragId;
    _erledigt = widget.eintrag?.eintrag.erledigt ?? false;
    _wiederholung =
        _rruleZuLabel(widget.eintrag?.eintrag.wiederholung);
    _checkliste =
        _ChecklistItem.parse(widget.eintrag?.eintrag.checklisteJson);
  }

  @override
  void dispose() {
    _titel.dispose();
    _anlass.dispose();
    _beschreibung.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.eintrag != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final companion = WiedervorlagenCompanion(
      id: _isEdit ? Value(widget.eintrag!.eintrag.id) : const Value.absent(),
      titel: Value(_titel.text.trim()),
      anlass: _nt(_anlass),
      beschreibung: _nt(_beschreibung),
      faelligAm: Value(_faellig),
      prioritaet: Value(_prio),
      auftragId: Value(_auftragId),
      erledigt: Value(_erledigt),
      erledigtAm: Value(_erledigt ? DateTime.now() : null),
      wiederholung: Value(_labelZuRrule(_wiederholung)),
      checklisteJson: Value(_ChecklistItem.encode(_checkliste)),
    );
    try {
      await ref.read(wiedervorlagenRepositoryProvider).upsert(companion);
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

  /// Mapping vom UI-Label zur iCal-RRULE-Kurzform.
  String? _labelZuRrule(String label) {
    switch (label) {
      case 'taeglich':
        return 'FREQ=DAILY';
      case 'woechentlich':
        return 'FREQ=WEEKLY';
      case 'monatlich':
        return 'FREQ=MONTHLY';
      default:
        return null;
    }
  }

  String _rruleZuLabel(String? rrule) {
    if (rrule == null || rrule.isEmpty) return 'keine';
    final r = rrule.toUpperCase();
    if (r.contains('FREQ=DAILY')) return 'taeglich';
    if (r.contains('FREQ=WEEKLY')) return 'woechentlich';
    if (r.contains('FREQ=MONTHLY')) return 'monatlich';
    return 'keine';
  }

  @override
  Widget build(BuildContext context) {
    return StandardFormDialog(
      title: _isEdit ? 'Wiedervorlage bearbeiten' : 'Neue Wiedervorlage',
      saving: _saving,
      maxHeight: 580,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(wiedervorlagenRepositoryProvider)
              .delete(widget.eintrag!.eintrag.id)
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
              LabeledField(
                'Anlass / Grund',
                TextFormField(controller: _anlass),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Beschreibung / Notiz',
                TextFormField(
                    controller: _beschreibung, minLines: 2, maxLines: 4),
              ),
              const SizedBox(height: 12),
              Row2(
                left: DateField(
                    label: 'Fällig am',
                    value: _faellig,
                    onChanged: (v) =>
                        setState(() => _faellig = v ?? DateTime.now())),
                right: LabeledField(
                  'Priorität',
                  DropdownButtonFormField<String>(
                    initialValue: _prio,
                    isDense: true,
                    items: const [
                      DropdownMenuItem(value: 'hoch', child: Text('hoch')),
                      DropdownMenuItem(
                          value: 'normal', child: Text('normal')),
                      DropdownMenuItem(
                          value: 'niedrig', child: Text('niedrig')),
                    ],
                    onChanged: (v) => setState(() => _prio = v ?? 'normal'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AuftragPickerField(
                auftragId: _auftragId,
                onChanged: (id) => setState(() => _auftragId = id),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Wiederholung',
                DropdownButtonFormField<String>(
                  initialValue: _wiederholung,
                  isDense: true,
                  items: const [
                    DropdownMenuItem(
                        value: 'keine', child: Text('Einmalig')),
                    DropdownMenuItem(
                        value: 'taeglich', child: Text('Täglich')),
                    DropdownMenuItem(
                        value: 'woechentlich', child: Text('Wöchentlich')),
                    DropdownMenuItem(
                        value: 'monatlich', child: Text('Monatlich')),
                  ],
                  onChanged: (v) =>
                      setState(() => _wiederholung = v ?? 'keine'),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Checkliste',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Punkt'),
                    onPressed: () => setState(() => _checkliste
                        .add(_ChecklistItem(text: '', erledigt: false))),
                  ),
                ],
              ),
              if (_checkliste.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '— keine Einträge —',
                    style: TextStyle(fontSize: 12),
                  ),
                )
              else
                for (var i = 0; i < _checkliste.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _checkliste[i].erledigt,
                          onChanged: (v) => setState(() =>
                              _checkliste[i].erledigt = v ?? false),
                        ),
                        Expanded(
                          child: TextFormField(
                            initialValue: _checkliste[i].text,
                            onChanged: (v) => _checkliste[i].text = v,
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: 'Prüfpunkt …',
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () =>
                              setState(() => _checkliste.removeAt(i)),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 12),
              Row(children: [
                Checkbox(
                    value: _erledigt,
                    onChanged: (v) =>
                        setState(() => _erledigt = v ?? false)),
                const Text('Erledigt'),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Einzelner Checklisten-Punkt in einer Wiedervorlage.
class _ChecklistItem {
  String text;
  bool erledigt;
  _ChecklistItem({required this.text, required this.erledigt});

  static List<_ChecklistItem> parse(String? json) {
    if (json == null || json.trim().isEmpty) return [];
    try {
      final list = jsonDecode(json);
      if (list is! List) return [];
      return list.whereType<Map>().map((m) {
        return _ChecklistItem(
          text: m['text']?.toString() ?? '',
          erledigt: m['erledigt'] == true,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static String? encode(List<_ChecklistItem> items) {
    if (items.isEmpty) return null;
    return jsonEncode(items
        .where((i) => i.text.trim().isNotEmpty)
        .map((i) => {'text': i.text, 'erledigt': i.erledigt})
        .toList());
  }
}
