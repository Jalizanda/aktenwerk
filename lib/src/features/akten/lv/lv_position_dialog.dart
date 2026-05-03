import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/lv_position_ai_service.dart';
import '../../../data/database/app_database.dart';
import '../../../shared/widgets/form_widgets.dart';
import 'din276_service.dart';
import 'lv_aufmass_panel.dart';
import 'lv_repository.dart';

/// Editor-Dialog für eine einzelne LV-Position. Fasst Kurztext, Langtext,
/// Menge/Einheit/EP, Positions-Art, DIN-276-Zuordnung und Gewerk in einem
/// Formular zusammen. Aus dem Dialog heraus kann die Position auch in
/// den Katalog übernommen werden (Bottom-Button).
class LvPositionDialog extends ConsumerStatefulWidget {
  const LvPositionDialog({
    super.key,
    required this.lvId,
    this.position,
    this.parentId,
    this.prefillKatalog,
  });
  final int lvId;
  final LvPositionenData? position;
  final int? parentId;
  final LvKatalogData? prefillKatalog;

  @override
  ConsumerState<LvPositionDialog> createState() =>
      _LvPositionDialogState();
}

class _LvPositionDialogState extends ConsumerState<LvPositionDialog> {
  late final _kurztext = TextEditingController(
      text: widget.position?.kurztext ?? widget.prefillKatalog?.kurztext ?? '');
  late final _langtext = TextEditingController(
      text: widget.position?.langtext ?? widget.prefillKatalog?.langtext ?? '');
  late final _menge = TextEditingController(
      text: widget.position?.menge == null
          ? ''
          : widget.position!.menge!.toStringAsFixed(2).replaceAll('.', ','));
  late final _einheit = TextEditingController(
      text: widget.position?.einheit ?? widget.prefillKatalog?.einheit ?? '');
  late final _einzelpreis = TextEditingController(
      text: (widget.position?.einzelpreis ??
                  widget.prefillKatalog?.einzelpreis) ==
              null
          ? ''
          : (widget.position?.einzelpreis ??
                  widget.prefillKatalog!.einzelpreis!)
              .toStringAsFixed(2)
              .replaceAll('.', ','));
  late final _gewerk = TextEditingController(
      text: widget.position?.gewerk ?? widget.prefillKatalog?.gewerk ?? '');
  late final _notiz =
      TextEditingController(text: widget.position?.notiz ?? '');

  late String _art = widget.position?.art ?? 'normal';
  late String? _din276 =
      widget.position?.din276 ?? widget.prefillKatalog?.din276;
  /// `null` = LV-Kopf-Default verwenden, sonst eigener Satz.
  late double? _ustSatz = widget.position?.ustSatz;
  bool _saving = false;
  bool _alsoZuKatalog = false;

  static const _einheitenVorschlaege = [
    'm', 'm²', 'm³', 'Stk', 'h', 'psch', 't', 'kg', 'l',
  ];

  @override
  void dispose() {
    for (final c in [
      _kurztext,
      _langtext,
      _menge,
      _einheit,
      _einzelpreis,
      _gewerk,
      _notiz,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _d(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.').trim()) ?? 0;

  Future<void> _speichern() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(lvRepositoryProvider);
      final isMengenpos = _art != 'titel' && _art != 'grundtext';
      final companion = LvPositionenCompanion(
        id: widget.position == null
            ? const Value.absent()
            : Value(widget.position!.id),
        lvId: Value(widget.lvId),
        parentId: widget.position == null
            ? Value(widget.parentId)
            : Value(widget.position!.parentId),
        sortIndex: widget.position == null
            ? Value(await repo.nextSortIndex(widget.lvId, widget.parentId))
            : Value(widget.position!.sortIndex),
        art: Value(_art),
        kurztext: Value(_kurztext.text.trim()),
        langtext: Value(
            _langtext.text.trim().isEmpty ? null : _langtext.text.trim()),
        einheit: Value(isMengenpos
            ? (_einheit.text.trim().isEmpty ? null : _einheit.text.trim())
            : null),
        menge: Value(isMengenpos ? _d(_menge) : null),
        einzelpreis: Value(isMengenpos ? _d(_einzelpreis) : null),
        din276: Value((_din276 ?? '').isEmpty ? null : _din276),
        gewerk: Value(
            _gewerk.text.trim().isEmpty ? null : _gewerk.text.trim()),
        ustSatz: Value(_ustSatz),
        notiz: Value(_notiz.text.trim().isEmpty ? null : _notiz.text.trim()),
      );
      await repo.upsertPosition(companion);

      if (_alsoZuKatalog) {
        await repo.upsertKatalog(LvKatalogCompanion.insert(
          kurztext: _kurztext.text.trim(),
          langtext: Value(_langtext.text.trim().isEmpty
              ? null
              : _langtext.text.trim()),
          einheit: Value(_einheit.text.trim().isEmpty
              ? null
              : _einheit.text.trim()),
          einzelpreis: Value(_d(_einzelpreis)),
          din276: Value((_din276 ?? '').isEmpty ? null : _din276),
          gewerk: Value(
              _gewerk.text.trim().isEmpty ? null : _gewerk.text.trim()),
          quelle: const Value('eigen'),
          preisstand: Value(DateTime.now()),
        ));
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMengenpos = _art != 'titel' && _art != 'grundtext';
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.list_alt_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.position == null
                          ? 'Neue Position'
                          : 'Position bearbeiten',
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LabeledField(
                      'Positions-Art',
                      DropdownButtonFormField<String>(
                        initialValue: _art,
                        items: const [
                          DropdownMenuItem(
                              value: 'titel',
                              child: Text(
                                  'Titel (Strukturzeile, ohne Preis)')),
                          DropdownMenuItem(
                              value: 'normal',
                              child: Text('Normalposition (NP)')),
                          DropdownMenuItem(
                              value: 'bedarf',
                              child: Text('Bedarfsposition (BP)')),
                          DropdownMenuItem(
                              value: 'eventual',
                              child: Text('Eventualposition (EP)')),
                          DropdownMenuItem(
                              value: 'stundenlohn',
                              child: Text('Stundenlohnposition')),
                          DropdownMenuItem(
                              value: 'grundtext',
                              child: Text(
                                  'Grundtext (Beschreibung ohne Preis)')),
                        ],
                        onChanged: (v) =>
                            setState(() => _art = v ?? 'normal'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    LabeledField(
                      'Kurztext',
                      TextFormField(
                        controller: _kurztext,
                        decoration: const InputDecoration(
                          hintText: 'Bezeichnung der Leistung',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('Langtext (Detail-Beschreibung)',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontWeight: FontWeight.w500)),
                        const Spacer(),
                        _KiLangtextButton(
                          kurztextCtrl: _kurztext,
                          gewerkCtrl: _gewerk,
                          einheitCtrl: _einheit,
                          onUebernehmen: (txt) {
                            setState(() {
                              _langtext.text = txt;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _langtext,
                      minLines: 4,
                      maxLines: 12,
                      decoration: const InputDecoration(
                        hintText:
                            'Ausführliche Leistungsbeschreibung — Material, Verarbeitung, Norm-Bezug, Aufmaß-Regel.',
                      ),
                    ),
                    if (isMengenpos) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: LabeledField(
                              'Menge',
                              TextFormField(
                                controller: _menge,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: LabeledField(
                              'Einheit',
                              Autocomplete<String>(
                                initialValue: TextEditingValue(
                                    text: _einheit.text),
                                optionsBuilder: (val) {
                                  if (val.text.isEmpty) {
                                    return _einheitenVorschlaege;
                                  }
                                  return _einheitenVorschlaege.where((e) =>
                                      e.toLowerCase().contains(
                                          val.text.toLowerCase()));
                                },
                                onSelected: (v) => _einheit.text = v,
                                fieldViewBuilder: (
                                  ctx,
                                  controller,
                                  focus,
                                  onSubmit,
                                ) {
                                  controller.text = _einheit.text;
                                  return TextFormField(
                                    controller: controller,
                                    focusNode: focus,
                                    onChanged: (v) => _einheit.text = v,
                                    decoration: const InputDecoration(
                                        hintText: 'm, m², Stk., …'),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: LabeledField(
                              'Einzelpreis (€)',
                              TextFormField(
                                controller: _einzelpreis,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: LabeledField(
                              'USt-Satz',
                              DropdownButtonFormField<double?>(
                                initialValue: _ustSatz,
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem<double?>(
                                      value: null,
                                      child: Text('LV-Standard')),
                                  DropdownMenuItem<double?>(
                                      value: 19, child: Text('19 %')),
                                  DropdownMenuItem<double?>(
                                      value: 7, child: Text('7 %')),
                                  DropdownMenuItem<double?>(
                                      value: 0,
                                      child: Text('0 % (steuerfrei)')),
                                ],
                                onChanged: (v) =>
                                    setState(() => _ustSatz = v),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _Din276Picker(
                            currentNr: _din276,
                            onChanged: (v) =>
                                setState(() => _din276 = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: LabeledField(
                            'Gewerk',
                            TextFormField(
                              controller: _gewerk,
                              decoration: const InputDecoration(
                                hintText:
                                    'z. B. Maurerarbeiten, Putz, Maler …',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LabeledField(
                      'Interne Notiz',
                      TextFormField(
                        controller: _notiz,
                        minLines: 2,
                        maxLines: 4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (widget.position == null && isMengenpos)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _alsoZuKatalog,
                        onChanged: (v) =>
                            setState(() => _alsoZuKatalog = v ?? false),
                        title: const Text(
                            'Position zusätzlich in den eigenen Katalog übernehmen'),
                        subtitle: const Text(
                            'Beim nächsten LV per Picker schnell wieder einfügbar.'),
                      ),
                    // Aufmaß-Panel nur bei bestehender Position mit
                    // Mengen-Feld — neue Positionen erst speichern, dann
                    // erneut öffnen, um Aufmaße zu erfassen.
                    if (widget.position != null && isMengenpos) ...[
                      const SizedBox(height: 16),
                      LvAufmassPanel(
                        positionId: widget.position!.id,
                        einheit: _einheit.text.trim().isEmpty
                            ? null
                            : _einheit.text.trim(),
                        onSummeUebernehmen: (s) {
                          setState(() {
                            _menge.text =
                                s.toStringAsFixed(2).replaceAll('.', ',');
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Summe als Menge übernommen — bitte „Speichern".')));
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (widget.position != null)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Position löschen'),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.red),
                      onPressed: _saving
                          ? null
                          : () async {
                              await ref
                                  .read(lvRepositoryProvider)
                                  .deletePosition(widget.position!.id);
                              if (!mounted) return;
                              Navigator.of(context, rootNavigator: true)
                                  .pop();
                            },
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Speichern'),
                    onPressed: _saving ? null : _speichern,
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

class _Din276Picker extends ConsumerWidget {
  const _Din276Picker({required this.currentNr, required this.onChanged});
  final String? currentNr;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(din276ListProvider);
    return list.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          LabeledField('DIN 276', Text('Fehler: $e')),
      data: (eintraege) {
        return LabeledField(
          'DIN-276-Kostengruppe',
          DropdownButtonFormField<String?>(
            initialValue: currentNr,
            isExpanded: true,
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('— keine —')),
              for (final e in eintraege)
                DropdownMenuItem<String?>(
                  value: e.nr,
                  child: Text(
                    '${e.ebene == 1 ? "" : (e.ebene == 2 ? "  " : "      ")}${e.label}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: e.ebene == 1
                          ? FontWeight.bold
                          : (e.ebene == 2
                              ? FontWeight.w500
                              : FontWeight.normal),
                    ),
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
        );
      },
    );
  }
}

/// KI-Button: aus Kurztext + Gewerk einen fachlichen Langtext generieren.
/// Liefert das Ergebnis erst in einem Vorschau-Dialog, der Nutzer klickt
/// dann „Übernehmen" — damit das bestehende Langtext-Feld nicht
/// überschrieben wird, ohne dass der User das gesehen hat.
class _KiLangtextButton extends ConsumerStatefulWidget {
  const _KiLangtextButton({
    required this.kurztextCtrl,
    required this.gewerkCtrl,
    required this.einheitCtrl,
    required this.onUebernehmen,
  });
  final TextEditingController kurztextCtrl;
  final TextEditingController gewerkCtrl;
  final TextEditingController einheitCtrl;
  final ValueChanged<String> onUebernehmen;

  @override
  ConsumerState<_KiLangtextButton> createState() =>
      _KiLangtextButtonState();
}

class _KiLangtextButtonState extends ConsumerState<_KiLangtextButton> {
  bool _busy = false;

  Future<void> _generieren() async {
    final kurztext = widget.kurztextCtrl.text.trim();
    final gewerk = widget.gewerkCtrl.text.trim();
    final einheit = widget.einheitCtrl.text.trim();
    if (kurztext.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Bitte erst einen Kurztext eintragen.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final ergebnis = await generiereLangtext(
        ref,
        kurztext: kurztext,
        gewerk: gewerk.isEmpty ? null : gewerk,
        einheit: einheit.isEmpty ? null : einheit,
      );
      if (!mounted) return;
      if (ergebnis == null || ergebnis.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('KI hat keinen Text geliefert.')));
        return;
      }
      // Vorschau-Dialog
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: Colors.amber),
                      const SizedBox(width: 8),
                      Text('KI-generierter Langtext',
                          style: Theme.of(ctx).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(ergebnis),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Hinweis: KI-generierte Texte bitte fachlich prüfen, '
                    'bevor sie in einer Ausschreibung an Handwerker oder '
                    'in einem Gerichtsgutachten verwendet werden.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.outline,
                        fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Verwerfen'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Übernehmen'),
                        onPressed: () => Navigator.pop(ctx, true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (ok == true) {
        widget.onUebernehmen(ergebnis);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('KI-Fehler: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      icon: _busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.auto_awesome, size: 16, color: Colors.amber),
      label: const Text('KI-Langtext'),
      onPressed: _busy ? null : _generieren,
    );
  }
}
