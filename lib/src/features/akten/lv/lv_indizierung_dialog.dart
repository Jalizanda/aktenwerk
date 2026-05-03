import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../shared/widgets/form_widgets.dart';
import 'baupreisindex_service.dart';
import 'lv_repository.dart';

/// Dialog: alle Einzelpreise eines LV per Destatis-Baupreisindex auf
/// einen neuen Stichtag hochrechnen. Faktor = Index neu / Index alt.
class LvIndizierungDialog extends ConsumerStatefulWidget {
  const LvIndizierungDialog({super.key, required this.kopf});
  final LvKopfData kopf;

  @override
  ConsumerState<LvIndizierungDialog> createState() =>
      _LvIndizierungDialogState();
}

class _LvIndizierungDialogState
    extends ConsumerState<LvIndizierungDialog> {
  bool _busy = false;
  String? _error;
  Map<String, double>? _reihe;
  String? _zielStichtag;
  double? _zielWert;
  bool _manuell = false;
  final _basisStichtagCtrl = TextEditingController();
  final _basisWertCtrl = TextEditingController();
  final _zielStichtagCtrl = TextEditingController();
  final _zielWertCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _basisStichtagCtrl.text = widget.kopf.indexStichtag ?? '';
    _basisWertCtrl.text =
        widget.kopf.indexWert == null ? '' : widget.kopf.indexWert!.toStringAsFixed(1).replaceAll('.', ',');
    _ladeReihe();
  }

  @override
  void dispose() {
    _basisStichtagCtrl.dispose();
    _basisWertCtrl.dispose();
    _zielStichtagCtrl.dispose();
    _zielWertCtrl.dispose();
    super.dispose();
  }

  double _d(String s) =>
      double.tryParse(s.replaceAll(',', '.').trim()) ?? 0;

  Future<void> _ladeReihe() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final reihe = await ref
          .read(baupreisindexServiceProvider)
          .tabelleZeitreihe(BaupreisindexService.tabelleWohngebaeude);
      if (!mounted) return;
      setState(() {
        _reihe = reihe;
        if (reihe.isNotEmpty) {
          final keys = reihe.keys.toList()..sort();
          _zielStichtag = keys.last;
          _zielWert = reihe[_zielStichtag];
        } else {
          // Keine Werte (z. B. unkonfiguriert) → Manuell-Modus.
          _manuell = true;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = null;
          _manuell = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _anwenden() async {
    final basisWert = _manuell
        ? _d(_basisWertCtrl.text)
        : widget.kopf.indexWert;
    final basisStichtag = _manuell
        ? _basisStichtagCtrl.text.trim()
        : widget.kopf.indexStichtag;
    final zielWert = _manuell ? _d(_zielWertCtrl.text) : _zielWert;
    final zielStichtag =
        _manuell ? _zielStichtagCtrl.text.trim() : _zielStichtag;

    if (zielStichtag == null || zielStichtag.isEmpty || zielWert == null || zielWert == 0) {
      setState(() => _error = 'Bitte Ziel-Stichtag und Indexwert angeben.');
      return;
    }
    if (basisWert == null || basisWert == 0) {
      setState(() => _error =
          'Diesem LV ist kein Basis-Indexwert zugeordnet. Im Manuell-Modus bitte den Basis-Stichtag und -Wert eintragen, sonst erst im LV-Kopf hinterlegen.');
      return;
    }
    final faktor = zielWert / basisWert;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Preise indizieren?'),
        content: Text(
            'Alle Einzelpreise dieses LVs werden mit dem Faktor '
            '${faktor.toStringAsFixed(4)} multipliziert '
            '(${basisWert.toStringAsFixed(1)} → ${zielWert.toStringAsFixed(1)}). '
            'Der Stichtag wird auf $zielStichtag aktualisiert. '
            'Diese Aktion kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Anwenden')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final repo = ref.read(lvRepositoryProvider);
      final positionen = await repo.getPositionen(widget.kopf.id);
      for (final p in positionen) {
        if (p.einzelpreis == null) continue;
        final neu = p.einzelpreis! * faktor;
        await repo.upsertPosition(LvPositionenCompanion(
          id: Value(p.id),
          einzelpreis: Value(neu),
        ));
      }
      await repo.upsertKopf(LvKopfCompanion(
        id: Value(widget.kopf.id),
        indexStichtag: Value(zielStichtag),
        indexWert: Value(zielWert),
      ));
      // Falls manueller Modus → auch den Basis-Stichtag aktualisieren,
      // damit der LV-Kopf konsistent ist.
      if (_manuell && basisStichtag != null) {
        await repo.upsertKopf(LvKopfCompanion(
          id: Value(widget.kopf.id),
          indexStichtag: Value(zielStichtag),
          indexWert: Value(zielWert),
        ));
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'LV indiziert: Faktor ${faktor.toStringAsFixed(4)} angewandt.')));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
        locale: 'de_DE', symbol: '€', decimalDigits: 2);
    final basisStichtag = widget.kopf.indexStichtag;
    final basisWert = widget.kopf.indexWert;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.trending_up),
                  const SizedBox(width: 10),
                  Text('Preise indizieren (Destatis)',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                        'Basis-Stichtag des LV: ${basisStichtag ?? "—"}'
                        '${basisWert == null ? "" : " (Indexwert ${basisWert.toStringAsFixed(1)})"}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  Switch(
                    value: _manuell,
                    onChanged: (v) => setState(() => _manuell = v),
                  ),
                  const Text('Manuell',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
              const SizedBox(height: 12),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_manuell)
                _ManuellPanel(
                  basisStichtagCtrl: _basisStichtagCtrl,
                  basisWertCtrl: _basisWertCtrl,
                  zielStichtagCtrl: _zielStichtagCtrl,
                  zielWertCtrl: _zielWertCtrl,
                  onChange: () => setState(() {}),
                )
              else if (_reihe != null) ...[
                LabeledField(
                  'Ziel-Stichtag (auf den indiziert wird)',
                  DropdownButtonFormField<String>(
                    initialValue: _zielStichtag,
                    isExpanded: true,
                    items: [
                      for (final k in (_reihe!.keys.toList()..sort()))
                        DropdownMenuItem(
                            value: k,
                            child: Text(
                                '$k  →  ${_reihe![k]!.toStringAsFixed(1)}')),
                    ],
                    onChanged: (v) => setState(() {
                      _zielStichtag = v;
                      _zielWert = _reihe![v];
                    }),
                  ),
                ),
                const SizedBox(height: 12),
                if (basisWert != null && _zielWert != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Faktor: ${(_zielWert! / basisWert).toStringAsFixed(4)}',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                            'Eine Position mit EP ${money.format(100)} würde danach ${money.format(100 * (_zielWert! / basisWert))} kosten.',
                            style:
                                Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ] else if (basisWert == null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                        'Hinweis: Diesem LV fehlt der Basis-Indexwert. '
                        'Bitte erst im LV-Kopf den Stichtag und Indexwert '
                        'für den Erstellungs-Zeitpunkt hinterlegen — oder '
                        'auf „Manuell" wechseln.'),
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(_error!,
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onErrorContainer)),
                ),
              ],
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Schließen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Anwenden'),
                    onPressed: _busy ? null : _anwenden,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Manuelles Panel — wenn kein Destatis-Account verfügbar ist oder
/// die API nicht funktioniert. User trägt Basis- und Ziel-Werte selbst.
class _ManuellPanel extends StatelessWidget {
  const _ManuellPanel({
    required this.basisStichtagCtrl,
    required this.basisWertCtrl,
    required this.zielStichtagCtrl,
    required this.zielWertCtrl,
    required this.onChange,
  });
  final TextEditingController basisStichtagCtrl;
  final TextEditingController basisWertCtrl;
  final TextEditingController zielStichtagCtrl;
  final TextEditingController zielWertCtrl;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    double parse(TextEditingController c) =>
        double.tryParse(c.text.replaceAll(',', '.').trim()) ?? 0;
    final bw = parse(basisWertCtrl);
    final zw = parse(zielWertCtrl);
    final faktor = (bw == 0 || zw == 0) ? 0.0 : zw / bw;
    final money = NumberFormat.currency(
        locale: 'de_DE', symbol: '€', decimalDigits: 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
              'Manueller Modus: Indexwerte selbst eintragen. Hilfreiche '
              'Quelle: www-genesis.destatis.de → Tabelle 61261-0001 '
              '(Baupreisindex Wohngebäude). Aktuelle Werte liegen meist '
              'bei 130–145 Punkten (Basis 2015 = 100).',
              style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            flex: 2,
            child: LabeledField(
              'Basis-Stichtag (alt)',
              TextField(
                controller: basisStichtagCtrl,
                decoration: const InputDecoration(
                    hintText: 'z. B. 2022-Q3'),
                onChanged: (_) => onChange(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LabeledField(
              'Basis-Index',
              TextField(
                controller: basisWertCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => onChange(),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            flex: 2,
            child: LabeledField(
              'Ziel-Stichtag (neu)',
              TextField(
                controller: zielStichtagCtrl,
                decoration: const InputDecoration(
                    hintText: 'z. B. 2026-Q1'),
                onChanged: (_) => onChange(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LabeledField(
              'Ziel-Index',
              TextField(
                controller: zielWertCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => onChange(),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (faktor > 0)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Faktor: ${faktor.toStringAsFixed(4)}',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                    'Eine Position mit EP ${money.format(100)} würde danach ${money.format(100 * faktor)} kosten.',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}
