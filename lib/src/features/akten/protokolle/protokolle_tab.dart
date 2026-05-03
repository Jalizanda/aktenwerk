import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../shared/richtext/quill_editor.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../akte/beteiligte_tab.dart' show decodeBeteiligte;
import 'protokoll_pdf.dart';
import 'protokolle_repository.dart';

/// Teilnehmer eines Ortstermins.
class Teilnehmer {
  String name;
  String rolle;
  String firma;
  String email;
  Teilnehmer({
    this.name = '',
    this.rolle = '',
    this.firma = '',
    this.email = '',
  });
  Map<String, dynamic> toJson() => {
        'name': name,
        'rolle': rolle,
        'firma': firma,
        'email': email,
      };
  static Teilnehmer fromJson(Map<String, dynamic> m) => Teilnehmer(
        name: m['name']?.toString() ?? '',
        rolle: m['rolle']?.toString() ?? '',
        firma: m['firma']?.toString() ?? '',
        email: m['email']?.toString() ?? '',
      );
}

List<Teilnehmer> _decodeTeilnehmer(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List;
    return list
        .whereType<Map<String, dynamic>>()
        .map(Teilnehmer.fromJson)
        .toList();
  } catch (_) {
    return [];
  }
}

String _encodeTeilnehmer(List<Teilnehmer> list) =>
    jsonEncode(list.map((t) => t.toJson()).toList());

class _TeilnehmerVorschlag {
  const _TeilnehmerVorschlag({
    required this.name,
    required this.rolle,
    required this.firma,
    required this.email,
  });
  final String name;
  final String rolle;
  final String firma;
  final String email;
}

class ProtokolleTab extends ConsumerWidget {
  const ProtokolleTab({super.key, required this.auftrag});
  final AuftraegeData auftrag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(protokolleForAuftragProvider(auftrag.id));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Ortstermin-Protokolle',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Neues Protokoll'),
                onPressed: () => _openForm(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (items) => items.isEmpty
                  ? const EmptyListState(
                      icon: Icons.fact_check_outlined,
                      title: 'Noch kein Protokoll',
                      hint:
                          'Nach einem Ortstermin hier ein Protokoll mit Teilnehmern und Verlauf anlegen.')
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) =>
                          _ProtokollTile(protokoll: items[i], auftrag: auftrag),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openForm(BuildContext context, WidgetRef ref,
      [ProtokolleData? p]) async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => _ProtokollForm(auftrag: auftrag, protokoll: p),
    );
  }
}

class _ProtokollTile extends ConsumerWidget {
  const _ProtokollTile({required this.protokoll, required this.auftrag});
  final ProtokolleData protokoll;
  final AuftraegeData auftrag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat('dd.MM.yyyy · HH:mm', 'de');
    final teilnehmer = _decodeTeilnehmer(protokoll.teilnehmerJson);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side:
            BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.fact_check_outlined, size: 20),
        ),
        title: Text(fmt.format(protokoll.datum)),
        subtitle: Text(
          '${teilnehmer.length} Teilnehmer · ${protokoll.dauerMinuten} min'
          '${(protokoll.ort ?? '').isNotEmpty ? " · ${protokoll.ort}" : ""}',
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              tooltip: 'PDF drucken',
              onPressed: () => previewProtokollPdf(protokoll, auftrag, teilnehmer),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () => showDialog(
                context: context,
                useRootNavigator: true,
                builder: (_) => _ProtokollForm(
                    auftrag: auftrag, protokoll: protokoll),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () async => ref
                  .read(protokolleRepositoryProvider)
                  .delete(protokoll.id),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProtokollForm extends ConsumerStatefulWidget {
  const _ProtokollForm({required this.auftrag, this.protokoll});
  final AuftraegeData auftrag;
  final ProtokolleData? protokoll;
  @override
  ConsumerState<_ProtokollForm> createState() => _ProtokollFormState();
}

class _ProtokollFormState extends ConsumerState<_ProtokollForm> {
  late DateTime _datum;
  late final _ort =
      TextEditingController(text: widget.protokoll?.ort ?? _objektOrt());
  late final _wetter = TextEditingController(text: widget.protokoll?.wetter ?? '');
  late final _dauer = TextEditingController(
      text: (widget.protokoll?.dauerMinuten ?? 60).toString());
  late final _notiz =
      TextEditingController(text: widget.protokoll?.notiz ?? '');
  late List<Teilnehmer> _teilnehmer;
  String? _protokollJson;
  bool _saving = false;

  bool get _isEdit => widget.protokoll != null;

  String _objektOrt() {
    final a = widget.auftrag;
    return [a.objektStrasse, a.objektPlz, a.objektOrt]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(', ');
  }

  @override
  void initState() {
    super.initState();
    _datum = widget.protokoll?.datum ??
        widget.auftrag.ortsterminAm ??
        DateTime.now();
    _teilnehmer =
        _decodeTeilnehmer(widget.protokoll?.teilnehmerJson);
    _protokollJson = widget.protokoll?.protokollJson;
  }

  @override
  void dispose() {
    for (final c in [_ort, _wetter, _dauer, _notiz]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Übernimmt die Akte-Beteiligten als Teilnehmer-Vorauswahl. Öffnet
  /// einen Picker mit Auftraggeber + allen Beteiligten, Anwender hakt
  /// die Anwesenden ab — die werden dann als Teilnehmer-Zeilen mit
  /// vorbefüllten Feldern angelegt.
  Future<void> _aktenBeteiligteUebernehmen() async {
    final db = ref.read(appDatabaseProvider);
    // Auftraggeber (= Kunde) der Akte
    final kunde = widget.auftrag.kundeId == null
        ? null
        : await (db.select(db.kunden)
              ..where((t) => t.id.equals(widget.auftrag.kundeId!)))
            .getSingleOrNull();
    // Beteiligte aus auftrag.beteiligteJson
    final beteiligte = decodeBeteiligte(widget.auftrag.beteiligteJson);
    // Richter / Kläger / Beklagter aus den Akten-Stammdaten als
    // zusätzliche Vorschläge.
    final extras = <_TeilnehmerVorschlag>[];
    if (kunde != null) {
      extras.add(_TeilnehmerVorschlag(
        name: [kunde.vorname, kunde.nachname]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(' '),
        rolle: 'Auftraggeber',
        firma: kunde.firma ?? '',
        email: kunde.email ?? '',
      ));
    }
    for (final b in beteiligte) {
      extras.add(_TeilnehmerVorschlag(
        name: b.name,
        rolle: b.rolle,
        firma: '',
        email: b.email,
      ));
    }
    if ((widget.auftrag.richter ?? '').isNotEmpty) {
      extras.add(_TeilnehmerVorschlag(
        name: widget.auftrag.richter!,
        rolle: 'Richter',
        firma: widget.auftrag.gericht ?? '',
        email: '',
      ));
    }
    if ((widget.auftrag.klaeger ?? '').isNotEmpty) {
      extras.add(_TeilnehmerVorschlag(
        name: widget.auftrag.klaeger!,
        rolle: 'Kläger',
        firma: '',
        email: '',
      ));
    }
    if ((widget.auftrag.beklagter ?? '').isNotEmpty) {
      extras.add(_TeilnehmerVorschlag(
        name: widget.auftrag.beklagter!,
        rolle: 'Beklagter',
        firma: '',
        email: '',
      ));
    }
    if (extras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Keine Beteiligten in der Akte hinterlegt — Tab „Beteiligte" nutzen.')));
      return;
    }
    final ausgewaehlt = <int>{
      for (var i = 0; i < extras.length; i++) i,
    };
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, set2) {
        return AlertDialog(
          title: const Text('Beteiligte als Teilnehmer übernehmen'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < extras.length; i++)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: ausgewaehlt.contains(i),
                      onChanged: (v) => set2(() {
                        if (v == true) {
                          ausgewaehlt.add(i);
                        } else {
                          ausgewaehlt.remove(i);
                        }
                      }),
                      title: Text(
                          '${extras[i].rolle} · ${extras[i].name}'),
                      subtitle: extras[i].email.isEmpty
                          ? null
                          : Text(extras[i].email,
                              style: const TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () =>
                    Navigator.of(ctx, rootNavigator: true).pop(false),
                child: const Text('Abbrechen')),
            FilledButton(
                onPressed: () =>
                    Navigator.of(ctx, rootNavigator: true).pop(true),
                child: const Text('Übernehmen')),
          ],
        );
      }),
    );
    if (ok != true || !mounted) return;
    setState(() {
      for (final i in ausgewaehlt) {
        final v = extras[i];
        // Doppelte Namen nicht zweimal hinzufügen.
        if (_teilnehmer.any((t) =>
            t.name.trim().toLowerCase() ==
            v.name.trim().toLowerCase())) {
          continue;
        }
        _teilnehmer.add(Teilnehmer(
          name: v.name,
          rolle: v.rolle,
          firma: v.firma,
          email: v.email,
        ));
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(protokolleRepositoryProvider).upsert(
            ProtokolleCompanion(
              id: _isEdit
                  ? Value(widget.protokoll!.id)
                  : const Value.absent(),
              auftragId: Value(widget.auftrag.id),
              datum: Value(_datum),
              ort: Value(_ort.text.trim().isEmpty ? null : _ort.text.trim()),
              wetter: Value(_wetter.text.trim().isEmpty
                  ? null
                  : _wetter.text.trim()),
              dauerMinuten:
                  Value(int.tryParse(_dauer.text.trim()) ?? 60),
              teilnehmerJson: Value(_encodeTeilnehmer(_teilnehmer)),
              protokollJson: Value(_protokollJson),
              notiz: Value(_notiz.text.trim().isEmpty ? null : _notiz.text.trim()),
            ),
          );
      if (mounted) Navigator.of(context, rootNavigator: true).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StandardFormDialog(
      title: _isEdit ? 'Protokoll bearbeiten' : 'Neues Protokoll',
      icon: Icons.fact_check_outlined,
      maxWidth: 820,
      maxHeight: 780,
      saving: _saving,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(protokolleRepositoryProvider)
              .delete(widget.protokoll!.id)
          : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row2(
              left: LabeledField(
                'Datum/Zeit',
                InkWell(
                  onTap: () async {
                    final rootContext = context;
                    final d = await showDatePicker(
                      context: rootContext,
                      initialDate: _datum,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (d == null || !mounted) return;
                    if (!rootContext.mounted) return;
                    final t = await showTimePicker(
                      context: rootContext,
                      initialTime: TimeOfDay.fromDateTime(_datum),
                    );
                    setState(() {
                      _datum = DateTime(
                          d.year,
                          d.month,
                          d.day,
                          t?.hour ?? _datum.hour,
                          t?.minute ?? _datum.minute);
                    });
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      suffixIcon: Icon(Icons.calendar_month_outlined),
                    ),
                    child: Text(DateFormat('dd.MM.yyyy · HH:mm', 'de')
                        .format(_datum)),
                  ),
                ),
              ),
              right: LabeledField(
                'Dauer (Minuten)',
                TextFormField(
                  controller: _dauer,
                  keyboardType: TextInputType.number,
                ),
              ),
            ),
            const SizedBox(height: 12),
            LabeledField('Ort / Adresse', TextFormField(controller: _ort)),
            const SizedBox(height: 12),
            LabeledField(
                'Wetter / Bedingungen', TextFormField(controller: _wetter)),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Teilnehmer',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.groups_outlined, size: 16),
                  label: const Text('Aus Beteiligten der Akte'),
                  onPressed: _aktenBeteiligteUebernehmen,
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Teilnehmer'),
                  onPressed: () => setState(() => _teilnehmer.add(Teilnehmer())),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_teilnehmer.isEmpty)
              Text('Noch keine Teilnehmer erfasst.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ))
            else
              for (var i = 0; i < _teilnehmer.length; i++)
                _TeilnehmerRow(
                  key: ValueKey(_teilnehmer[i]),
                  t: _teilnehmer[i],
                  onChanged: () => setState(() {}),
                  onRemove: () =>
                      setState(() => _teilnehmer.removeAt(i)),
                ),
            const SizedBox(height: 16),
            Text('Protokolltext',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            SizedBox(
              height: 240,
              child: RichTextEditor(
                initialDeltaJson: _protokollJson,
                onChanged: (json) => _protokollJson = json,
                placeholder:
                    'Ablauf, Feststellungen, getroffene Vereinbarungen …',
              ),
            ),
            const SizedBox(height: 12),
            LabeledField(
              'Interne Notiz',
              TextFormField(controller: _notiz, minLines: 2, maxLines: 4),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeilnehmerRow extends StatefulWidget {
  const _TeilnehmerRow({
    super.key,
    required this.t,
    required this.onChanged,
    required this.onRemove,
  });
  final Teilnehmer t;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  @override
  State<_TeilnehmerRow> createState() => _TeilnehmerRowState();
}

class _TeilnehmerRowState extends State<_TeilnehmerRow> {
  late final _name = TextEditingController(text: widget.t.name);
  late final _rolle = TextEditingController(text: widget.t.rolle);
  late final _firma = TextEditingController(text: widget.t.firma);
  late final _email = TextEditingController(text: widget.t.email);

  @override
  void dispose() {
    for (final c in [_name, _rolle, _firma, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _name,
              decoration: const InputDecoration(
                  isDense: true, labelText: 'Name', border: OutlineInputBorder()),
              onChanged: (v) {
                widget.t.name = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _rolle,
              decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Rolle',
                  hintText: 'Sachverständiger, Anwalt, Zeuge …',
                  border: OutlineInputBorder()),
              onChanged: (v) {
                widget.t.rolle = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _firma,
              decoration: const InputDecoration(
                  isDense: true, labelText: 'Firma', border: OutlineInputBorder()),
              onChanged: (v) {
                widget.t.firma = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: TextField(
              controller: _email,
              decoration: const InputDecoration(
                  isDense: true, labelText: 'E-Mail', border: OutlineInputBorder()),
              onChanged: (v) {
                widget.t.email = v;
                widget.onChanged();
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: Theme.of(context).colorScheme.error,
            onPressed: widget.onRemove,
          ),
        ],
      ),
    );
  }
}
