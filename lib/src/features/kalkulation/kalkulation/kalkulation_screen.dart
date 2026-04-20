import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftraege_repository.dart';
import '../../../features/akten/kunden/kunden_repository.dart';
import '../../../features/akten/rechnungen/rechnungen_repository.dart';
import '../../../features/kalkulation/auslagen/auslagen_repository.dart';
import '../../../features/kalkulation/stunden/stunden_repository.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';

/// Kalkulation pro Auftrag: Tab 1 = Kostenschätzung (Positionen nach Gewerk),
/// Tab 2 = Ist/Soll-Übersicht mit aufgelaufenen Stunden/Auslagen/Rechnungen.
class KalkulationScreen extends ConsumerStatefulWidget {
  const KalkulationScreen({super.key});
  @override
  ConsumerState<KalkulationScreen> createState() =>
      _KalkulationScreenState();
}

class _KalkulationScreenState extends ConsumerState<KalkulationScreen>
    with SingleTickerProviderStateMixin {
  int? _auftragId;
  AuftragWithKunde? _auftrag;
  late final _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load(int id) async {
    final repo = ref.read(auftraegeRepositoryProvider);
    final kundenRepo = ref.read(kundenRepositoryProvider);
    final a = await repo.byId(id);
    if (a == null) {
      setState(() => _auftrag = null);
      return;
    }
    final k = a.kundeId == null ? null : await kundenRepo.byId(a.kundeId!);
    setState(() => _auftrag = AuftragWithKunde(a, k));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat.currency(locale: 'de', symbol: '€');
    final stundenFilter = ref.watch(stundenFilterProvider);
    final auslagenFilter = ref.watch(auslagenFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.functions_outlined,
          title: 'Kalkulation',
          subtitle: 'Ist-Kosten pro Auftrag (Stunden, Auslagen, Rechnungen)',
          filters: [
            SizedBox(
              width: 360,
              child: _AuftragDropdown(
                auftragId: _auftragId,
                onChanged: (id) {
                  setState(() {
                    _auftragId = id;
                    _auftrag = null;
                  });
                  if (id != null) _load(id);
                  ref
                      .read(stundenFilterProvider.notifier)
                      .update((f) => id == null
                          ? f.copyWith(clearAuftrag: true)
                          : f.copyWith(auftragId: id));
                  ref
                      .read(auslagenFilterProvider.notifier)
                      .update((f) => id == null
                          ? f.copyWith(clearAuftrag: true)
                          : f.copyWith(auftragId: id));
                },
              ),
            ),
          ],
        ),
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Kostenschätzung'),
            Tab(text: 'Ist-Kosten'),
          ],
          labelColor: theme.colorScheme.primary,
          indicatorColor: theme.colorScheme.primary,
        ),
        const Divider(height: 1),
        Expanded(
          child: _auftragId == null
              ? const EmptyListState(
                  icon: Icons.functions_outlined,
                  title: 'Bitte Auftrag wählen',
                  hint:
                      'Wähle oben einen Auftrag, um die Kalkulation zu sehen.',
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _KostenschaetzungTab(
                      key: ValueKey('kost_$_auftragId'),
                      auftragId: _auftragId!,
                      auftrag: _auftrag?.auftrag,
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: _KalkulationBody(
                        auftrag: _auftrag,
                        stunden:
                            ref.watch(stundenListProvider).valueOrNull ??
                                [],
                        auslagen:
                            ref.watch(auslagenListProvider).valueOrNull ??
                                [],
                        rechnungen: (ref
                                    .watch(rechnungenListProvider)
                                    .valueOrNull ??
                                [])
                            .where((r) => r.rechnung.auftragId == _auftragId)
                            .toList(),
                        money: money,
                        theme: theme,
                        filterActive:
                            stundenFilter.auftragId == _auftragId &&
                                auslagenFilter.auftragId == _auftragId,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _AuftragDropdown extends ConsumerWidget {
  const _AuftragDropdown(
      {required this.auftragId, required this.onChanged});
  final int? auftragId;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(auftraegeListProvider);
    return async.when(
      loading: () => const SizedBox(
        height: 48,
        child: Center(
            child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (e, _) => Text('Fehler: $e'),
      data: (items) => DropdownButtonFormField<int?>(
        initialValue: auftragId,
        isExpanded: true,
        decoration: const InputDecoration(
            labelText: 'Auftrag', isDense: true),
        items: [
          const DropdownMenuItem(
              value: null, child: Text('(kein Auftrag)')),
          for (final r in items)
            DropdownMenuItem(
              value: r.auftrag.id,
              child: Text(
                '${r.auftrag.aktenzeichen ?? '(o. A.)'} · ${r.kunde == null ? '—' : kundeAnzeigename(r.kunde!)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _KalkulationBody extends StatelessWidget {
  const _KalkulationBody({
    required this.auftrag,
    required this.stunden,
    required this.auslagen,
    required this.rechnungen,
    required this.money,
    required this.theme,
    required this.filterActive,
  });
  final AuftragWithKunde? auftrag;
  final List<StundenWithAuftrag> stunden;
  final List<AuslageWithAuftrag> auslagen;
  final List<RechnungWithKunde> rechnungen;
  final NumberFormat money;
  final ThemeData theme;
  final bool filterActive;

  @override
  Widget build(BuildContext context) {
    final stundenSumme = stunden.fold<double>(
        0,
        (acc, s) =>
            acc + (s.stunde.minuten / 60.0) * (s.stunde.satz ?? 0));
    final stundenMinuten =
        stunden.fold<int>(0, (acc, s) => acc + s.stunde.minuten);
    final auslagenSumme =
        auslagen.fold<double>(0, (acc, a) => acc + a.auslage.summe);
    final rechnungenSumme = rechnungen.fold<double>(
        0, (acc, r) => acc + r.rechnung.netto);
    final kostenLimit = auftrag?.auftrag.kostenLimit;
    final kostenvorschuss = auftrag?.auftrag.kostenvorschuss ?? 0;

    final gesamt = stundenSumme + auslagenSumme;
    final pct = kostenLimit == null || kostenLimit == 0
        ? null
        : (gesamt / kostenLimit).clamp(0.0, 1.5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!filterActive)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Einen Moment – Daten werden noch geladen …',
              style: theme.textTheme.bodySmall,
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Tile(
              label: 'Stunden gesamt',
              value:
                  '${(stundenMinuten / 60).toStringAsFixed(1)} Std',
              sub: money.format(stundenSumme),
            ),
            _Tile(
              label: 'Auslagen',
              value: money.format(auslagenSumme),
              sub: '${auslagen.length} Posten',
            ),
            _Tile(
              label: 'Ist-Kosten',
              value: money.format(gesamt),
              sub: 'Stunden + Auslagen',
              color: theme.colorScheme.primary,
            ),
            _Tile(
              label: 'Rechnungen (netto)',
              value: money.format(rechnungenSumme),
              sub: '${rechnungen.length} Rechnung(en)',
            ),
            _Tile(
              label: 'Kostenvorschuss',
              value: money.format(kostenvorschuss),
            ),
            if (kostenLimit != null)
              _Tile(
                label: 'Kostenlimit',
                value: money.format(kostenLimit),
                sub: pct == null
                    ? null
                    : '${(pct * 100).toStringAsFixed(0)} % ausgeschöpft',
                color: pct != null && pct >= 0.9
                    ? theme.colorScheme.error
                    : null,
              ),
          ],
        ),
        if (pct != null) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: pct > 1.0 ? 1.0 : pct.toDouble(),
            minHeight: 8,
            color: pct >= 0.9
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    this.sub,
    this.color,
  });
  final String label;
  final String value;
  final String? sub;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
              Text(value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      )),
              if (sub != null)
                Text(sub!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        )),
            ],
          ),
        ),
      ),
    );
  }
}

/// Einzelposition der Kostenschätzung.
class _KostPos {
  String gewerk;
  String bezeichnung;
  double menge;
  String einheit;
  double einzelpreis;
  String bemerkung;
  _KostPos({
    this.gewerk = '',
    this.bezeichnung = '',
    this.menge = 1,
    this.einheit = 'Stk',
    this.einzelpreis = 0,
    this.bemerkung = '',
  });
  double get betrag => menge * einzelpreis;

  Map<String, dynamic> toJson() => {
        'gewerk': gewerk,
        'bezeichnung': bezeichnung,
        'menge': menge,
        'einheit': einheit,
        'einzelpreis': einzelpreis,
        'bemerkung': bemerkung,
      };
  factory _KostPos.fromJson(Map<String, dynamic> j) => _KostPos(
        gewerk: j['gewerk']?.toString() ?? '',
        bezeichnung: j['bezeichnung']?.toString() ?? '',
        menge: (j['menge'] as num?)?.toDouble() ?? 1,
        einheit: j['einheit']?.toString() ?? 'Stk',
        einzelpreis: (j['einzelpreis'] as num?)?.toDouble() ?? 0,
        bemerkung: j['bemerkung']?.toString() ?? '',
      );
}

class _Kostenschaetzung {
  String titel;
  double mwstSatz;
  List<_KostPos> positionen;
  _Kostenschaetzung({
    this.titel = 'Kostenschätzung',
    this.mwstSatz = 19,
    this.positionen = const [],
  });

  Map<String, dynamic> toJson() => {
        'titel': titel,
        'mwstSatz': mwstSatz,
        'positionen': positionen.map((p) => p.toJson()).toList(),
      };
  factory _Kostenschaetzung.fromJson(Map<String, dynamic> j) =>
      _Kostenschaetzung(
        titel: j['titel']?.toString() ?? 'Kostenschätzung',
        mwstSatz: (j['mwstSatz'] as num?)?.toDouble() ?? 19,
        positionen: (j['positionen'] as List<dynamic>? ?? [])
            .map((e) => _KostPos.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static _Kostenschaetzung fromExtras(String? extras) {
    if (extras == null || extras.isEmpty) return _Kostenschaetzung();
    try {
      final map = jsonDecode(extras) as Map<String, dynamic>;
      final k = map['kostenschaetzung'];
      if (k is Map<String, dynamic>) return _Kostenschaetzung.fromJson(k);
    } catch (_) {}
    return _Kostenschaetzung();
  }

  /// Hängt die Kostenschätzung an bestehende Auftrag-extras an.
  static String mergeExtras(String? current, _Kostenschaetzung k) {
    Map<String, dynamic> map = {};
    if (current != null && current.isNotEmpty) {
      try {
        final decoded = jsonDecode(current);
        if (decoded is Map<String, dynamic>) map = decoded;
      } catch (_) {}
    }
    map['kostenschaetzung'] = k.toJson();
    return jsonEncode(map);
  }
}

/// Tab für die Kostenschätzung: Positionen mit Gewerk, Summen pro Gewerk,
/// Gesamtsumme (netto + USt + brutto). Speichert in Auftrag.extras als JSON.
class _KostenschaetzungTab extends ConsumerStatefulWidget {
  const _KostenschaetzungTab({
    super.key,
    required this.auftragId,
    required this.auftrag,
  });
  final int auftragId;
  final AuftraegeData? auftrag;
  @override
  ConsumerState<_KostenschaetzungTab> createState() =>
      _KostenschaetzungTabState();
}

class _KostenschaetzungTabState
    extends ConsumerState<_KostenschaetzungTab> {
  late _Kostenschaetzung _kost;
  late final _titelCtrl = TextEditingController(text: _kost.titel);
  late final _mwstCtrl = TextEditingController(text: _kost.mwstSatz.toStringAsFixed(0));
  bool _saving = false;
  static final _money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _kost = _Kostenschaetzung.fromExtras(widget.auftrag?.extras);
    _titelCtrl.text = _kost.titel;
    _mwstCtrl.text = _kost.mwstSatz.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _titelCtrl.dispose();
    _mwstCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    _kost.titel = _titelCtrl.text.trim();
    _kost.mwstSatz =
        double.tryParse(_mwstCtrl.text.replaceAll(',', '.')) ?? 19;
    final mergedExtras =
        _Kostenschaetzung.mergeExtras(widget.auftrag?.extras, _kost);
    final repo = ref.read(auftraegeRepositoryProvider);
    await repo.upsert(AuftraegeCompanion(
      id: Value(widget.auftragId),
      extras: Value(mergedExtras),
    ));
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kostenschätzung gespeichert')));
    }
  }

  void _addPos([String? gewerk]) {
    setState(() => _kost.positionen = [
          ..._kost.positionen,
          _KostPos(gewerk: gewerk ?? ''),
        ]);
  }

  void _update(int i, _KostPos p) {
    setState(() {
      final copy = List<_KostPos>.from(_kost.positionen);
      copy[i] = p;
      _kost.positionen = copy;
    });
  }

  void _remove(int i) {
    setState(() {
      final copy = List<_KostPos>.from(_kost.positionen)..removeAt(i);
      _kost.positionen = copy;
    });
  }

  @override
  Widget build(BuildContext context) {
    final netto = _kost.positionen.fold<double>(0, (s, p) => s + p.betrag);
    final mwst = netto * _kost.mwstSatz / 100;
    final brutto = netto + mwst;
    // Gruppierung nach Gewerk für die Darstellung
    final groups = <String, List<_KostPos>>{};
    for (final p in _kost.positionen) {
      groups.putIfAbsent(p.gewerk.isEmpty ? '(ohne Gewerk)' : p.gewerk, () => [])
          .add(p);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: LabeledField(
                  'Titel der Kostenschätzung',
                  TextFormField(controller: _titelCtrl),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 140,
                child: LabeledField(
                  'MwSt-Satz (%)',
                  TextFormField(
                    controller: _mwstCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined, size: 16),
                onPressed: _saving ? null : _save,
                label: const Text('Speichern'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Position'),
                onPressed: () => _addPos(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_kost.positionen.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('Noch keine Positionen. Füge oben eine neue Position hinzu.'),
              ),
            )
          else
            for (final entry in groups.entries) _buildGroup(entry.key, entry.value),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _sumRow('Zwischensumme (netto)', _money.format(netto)),
                      _sumRow(
                          'zzgl. ${_kost.mwstSatz.toStringAsFixed(0)} % USt.',
                          _money.format(mwst)),
                      const Divider(),
                      _sumRow('Geschätzte Gesamtsumme',
                          _money.format(brutto),
                          bold: true),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroup(String gewerk, List<_KostPos> list) {
    final summe = list.fold<double>(0, (s, p) => s + p.betrag);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border:
            Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(
                bottom: BorderSide(color: AppTheme.slate200),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.construction_outlined, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(gewerk,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Text('${list.length} Pos. · ${_money.format(summe)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Position ergänzen',
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => _addPos(
                      gewerk == '(ohne Gewerk)' ? '' : gewerk),
                ),
              ],
            ),
          ),
          for (final p in list)
            _KostRow(
              key: ValueKey(p),
              pos: p,
              onChanged: (np) => _update(_kost.positionen.indexOf(p), np),
              onRemove: () => _remove(_kost.positionen.indexOf(p)),
            ),
        ],
      ),
    );
  }

  Widget _sumRow(String label, String value, {bool bold = false}) {
    final style = TextStyle(
        fontSize: bold ? 14 : 12.5,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ]),
    );
  }
}

class _KostRow extends StatefulWidget {
  const _KostRow(
      {super.key,
      required this.pos,
      required this.onChanged,
      required this.onRemove});
  final _KostPos pos;
  final ValueChanged<_KostPos> onChanged;
  final VoidCallback onRemove;
  @override
  State<_KostRow> createState() => _KostRowState();
}

class _KostRowState extends State<_KostRow> {
  late final _gewerk = TextEditingController(text: widget.pos.gewerk);
  late final _bez = TextEditingController(text: widget.pos.bezeichnung);
  late final _menge = TextEditingController(
      text: widget.pos.menge.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), ''));
  late final _einheit = TextEditingController(text: widget.pos.einheit);
  late final _preis = TextEditingController(
      text: widget.pos.einzelpreis
          .toStringAsFixed(2)
          .replaceAll(RegExp(r'\.?0+$'), ''));

  @override
  void dispose() {
    for (final c in [_gewerk, _bez, _menge, _einheit, _preis]) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() {
    widget.onChanged(_KostPos(
      gewerk: _gewerk.text,
      bezeichnung: _bez.text,
      menge: double.tryParse(_menge.text.replaceAll(',', '.')) ?? 0,
      einheit: _einheit.text,
      einzelpreis: double.tryParse(_preis.text.replaceAll(',', '.')) ?? 0,
      bemerkung: widget.pos.bemerkung,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final money =
        NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
    final betrag =
        (double.tryParse(_menge.text.replaceAll(',', '.')) ?? 0) *
            (double.tryParse(_preis.text.replaceAll(',', '.')) ?? 0);
    InputDecoration dec() => const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: TextField(
              controller: _gewerk,
              decoration: dec().copyWith(hintText: 'Gewerk'),
              onChanged: (_) {
                _emit();
                setState(() {});
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _bez,
              decoration: dec().copyWith(hintText: 'Bezeichnung'),
              onChanged: (_) => _emit(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: TextField(
              controller: _menge,
              textAlign: TextAlign.right,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: dec(),
              onChanged: (_) {
                _emit();
                setState(() {});
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: TextField(
              controller: _einheit,
              decoration: dec(),
              onChanged: (_) => _emit(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: TextField(
              controller: _preis,
              textAlign: TextAlign.right,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: dec(),
              onChanged: (_) {
                _emit();
                setState(() {});
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(money.format(betrag),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: widget.onRemove,
          ),
        ],
      ),
    );
  }
}
