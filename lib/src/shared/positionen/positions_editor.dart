import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/database/app_database.dart';
import '../../features/kalkulation/artikel/artikel_repository.dart';
import '../../features/werkzeuge/textbausteine/textbausteine_repository.dart';
import '../richtext/quill_editor.dart';
import '../widgets/formel_text_field.dart';
import 'position_model.dart';

/// Positions-Editor im Stil der Original-SV-Software:
/// Pro Zeile zwei Text-Felder (Kurztext + optionaler Langtext als Textarea),
/// rechts Menge/Einheit/Einzelpreis/Betrag + Remove-Icon.
///
/// Keine USt-Spalte — die Umsatzsteuer wird dokumentweit im Summen-Block
/// gesteuert (siehe [PositionsSummaryCard]).
class PositionsEditor extends ConsumerStatefulWidget {
  const PositionsEditor({
    super.key,
    required this.positions,
    required this.onChanged,
    this.title = 'Positionen',
    this.extraActions = const <Widget>[],
  });

  final List<Position> positions;
  final ValueChanged<List<Position>> onChanged;
  final String title;
  final List<Widget> extraActions;

  @override
  ConsumerState<PositionsEditor> createState() => _PositionsEditorState();
}

class _PositionsEditorState extends ConsumerState<PositionsEditor> {
  late List<Position> _items;
  // Stabile, zeilenübergreifende IDs für jede Position — nötig, damit
  // `ValueKey` in der Liste die TextController einer Position auch nach
  // Move-Up/Move-Down dem korrekten Objekt zuordnet. Ohne dies zeigen die
  // Eingabefelder nach einem Move noch die alten Nachbar-Werte an.
  late List<int> _ids;
  int _nextId = 0;
  static final _money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.positions);
    _ids = List.generate(_items.length, (_) => _nextId++);
  }

  @override
  void didUpdateWidget(covariant PositionsEditor old) {
    super.didUpdateWidget(old);
    // WICHTIG: IDs NICHT pauschal neu vergeben, wenn sich nur Inhalte
    // geändert haben. Bei jedem Tastendruck baut _emit() eine neue Liste
    // mit copyWith-Instanzen — die Position-Objekte sind dann referenziell
    // verschieden, obwohl Reihenfolge und Anzahl gleich bleiben. Wenn wir
    // hier neue _ids generieren, wechselt der ValueKey jeder Zeile, der
    // _PositionRow-State (inkl. TextController + Fokus) wird verworfen,
    // und der Cursor springt nach jedem Zeichen aus dem Feld.
    //
    // Nur die Items selbst aktualisieren — IDs bleiben stabil. Bei
    // Längen-Änderungen (Hinzufügen/Entfernen) gleichen wir die ID-Liste
    // nur am Ende an.
    if (!identical(old.positions, widget.positions)) {
      _items = List.of(widget.positions);
      while (_ids.length < _items.length) {
        _ids.add(_nextId++);
      }
      while (_ids.length > _items.length) {
        _ids.removeLast();
      }
    }
  }

  void _emit() => widget.onChanged(List.unmodifiable(_items));

  int _issueId() => _nextId++;

  void _addNeu() {
    setState(() {
      _items.add(const Position());
      _ids.add(_issueId());
    });
    _emit();
  }

  Future<void> _addAusArtikel() async {
    final picked = await showDialog<Position>(
      context: context,
      builder: (_) => const _ArtikelPickerDialog(),
    );
    if (picked != null) {
      setState(() {
        _items.add(picked);
        _ids.add(_issueId());
      });
      _emit();
    }
  }

  Future<void> _addAusTextbaustein() async {
    final picked = await showDialog<TextbausteineData>(
      context: context,
      useRootNavigator: true,
      builder: (_) => const _TextbausteinPickerDialog(),
    );
    if (picked != null) {
      final p = Position(
        bezeichnung: picked.titel,
        langtext: picked.inhalt ?? '',
        menge: 1,
      );
      setState(() {
        _items.add(p);
        _ids.add(_issueId());
      });
      _emit();
    }
  }

  void _remove(int i) {
    setState(() {
      _items.removeAt(i);
      _ids.removeAt(i);
    });
    _emit();
  }

  void _edit(int i, Position p) {
    setState(() => _items[i] = p);
    _emit();
  }

  void _moveUp(int i) {
    if (i <= 0) return;
    setState(() {
      final p = _items.removeAt(i);
      final id = _ids.removeAt(i);
      _items.insert(i - 1, p);
      _ids.insert(i - 1, id);
    });
    _emit();
  }

  void _moveDown(int i) {
    if (i >= _items.length - 1) return;
    setState(() {
      final p = _items.removeAt(i);
      final id = _ids.removeAt(i);
      _items.insert(i + 1, p);
      _ids.insert(i + 1, id);
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Überschrift + Aktions-Buttons (wie im Original rechts in der Kopfzeile).
        Row(
          children: [
            Text(widget.title,
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            for (final a in widget.extraActions) ...[
              a,
              const SizedBox(width: 6),
            ],
            OutlinedButton.icon(
              onPressed: _addAusTextbaustein,
              icon: const Icon(Icons.text_snippet_outlined, size: 16),
              label: const Text('Textbaustein'),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              onPressed: _addAusArtikel,
              icon: const Icon(Icons.inventory_2_outlined, size: 16),
              label: const Text('Artikel einfügen'),
            ),
            const SizedBox(width: 6),
            FilledButton.icon(
              onPressed: _addNeu,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Position'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              // Kopfzeile.
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8)),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                        width: 40,
                        child: Text('Pos.',
                            style:
                                TextStyle(fontWeight: FontWeight.w600))),
                    SizedBox(width: 4),
                    SizedBox(
                        width: 36,
                        child: Tooltip(
                          message: 'Optional/Alternativ-Position',
                          child: Icon(Icons.check_box_outline_blank,
                              size: 16),
                        )),
                    SizedBox(width: 4),
                    Expanded(flex: 6, child: Text('Bezeichnung',
                        style: TextStyle(fontWeight: FontWeight.w600))),
                    SizedBox(
                        width: 80,
                        child: Text('Menge',
                            textAlign: TextAlign.right,
                            style:
                                TextStyle(fontWeight: FontWeight.w600))),
                    SizedBox(width: 8),
                    SizedBox(
                        width: 86,
                        child: Text('Einheit',
                            style:
                                TextStyle(fontWeight: FontWeight.w600))),
                    SizedBox(width: 8),
                    SizedBox(
                        width: 100,
                        child: Text('Einzelpreis €',
                            textAlign: TextAlign.right,
                            style:
                                TextStyle(fontWeight: FontWeight.w600))),
                    SizedBox(width: 8),
                    SizedBox(
                        width: 100,
                        child: Text('Betrag €',
                            textAlign: TextAlign.right,
                            style:
                                TextStyle(fontWeight: FontWeight.w600))),
                    SizedBox(width: 40),
                  ],
                ),
              ),
              if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'Noch keine Positionen. Nutze „+ Position" oder „Artikel einfügen".',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              else
                for (var i = 0; i < _items.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                  _PositionRow(
                    // Stabile ID pro Position, damit Controller nach Move
                    // nicht den Inhalt der Nachbarzeile zeigen.
                    key: ValueKey('pos_${_ids[i]}'),
                    position: _items[i],
                    onChanged: (p) => _edit(i, p),
                    onRemove: () => _remove(i),
                    onMoveUp: i > 0 ? () => _moveUp(i) : null,
                    onMoveDown: i < _items.length - 1
                        ? () => _moveDown(i)
                        : null,
                    money: _money,
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PositionRow extends StatefulWidget {
  const _PositionRow({
    super.key,
    required this.position,
    required this.onChanged,
    required this.onRemove,
    required this.money,
    this.onMoveUp,
    this.onMoveDown,
  });
  final Position position;
  final ValueChanged<Position> onChanged;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final NumberFormat money;

  @override
  State<_PositionRow> createState() => _PositionRowState();
}

class _PositionRowState extends State<_PositionRow> {
  late final _posNr =
      TextEditingController(text: widget.position.posNr);
  late final _bez = TextEditingController(text: widget.position.bezeichnung);
  late final _lang = TextEditingController(text: widget.position.langtext);
  late final _menge = TextEditingController(
      text: _stripZeros(widget.position.menge));
  late final _einheit =
      TextEditingController(text: widget.position.einheit);
  late final _preis = TextEditingController(
      text: _stripZeros(widget.position.einzelpreis));

  static String _stripZeros(double v) {
    final s = v.toStringAsFixed(2);
    if (s.endsWith('.00')) return s.substring(0, s.length - 3);
    if (s.endsWith('0')) return s.substring(0, s.length - 1);
    return s;
  }

  @override
  void dispose() {
    for (final c in [_posNr, _bez, _lang, _menge, _einheit, _preis]) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() {
    widget.onChanged(widget.position.copyWith(
      posNr: _posNr.text,
      bezeichnung: _bez.text,
      langtext: _lang.text,
      menge: parseMengeOrFormel(_menge.text),
      einheit: _einheit.text,
      einzelpreis: parseMengeOrFormel(_preis.text),
    ));
  }

  Future<void> _openLangtextPopup(BuildContext context) async {
    final initial = _lang.text;
    final result = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => _LangtextEditorDialog(
        initialDeltaJson: initial,
        bezeichnung: _bez.text,
      ),
    );
    if (result == null) return;
    setState(() {
      _lang.text = result;
    });
    _emit();
  }

  InputDecoration _dec({String? hint}) => InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final betrag = widget.position.nettoBetrag;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pos-Nr (optional, schmal).
          SizedBox(
            width: 40,
            child: TextField(
              controller: _posNr,
              decoration: _dec(hint: 'Nr.'),
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 12),
              onChanged: (_) => _emit(),
            ),
          ),
          const SizedBox(width: 4),
          // Optional/Alternativ-Checkbox
          Tooltip(
            message: widget.position.optional
                ? 'Optional/Alternativ-Position — Betrag wird in Klammern dargestellt und NICHT in Summe'
                : 'Optional/Alternativ-Position aktivieren',
            child: Checkbox(
              value: widget.position.optional,
              visualDensity: VisualDensity.compact,
              onChanged: (v) {
                widget.onChanged(
                    widget.position.copyWith(optional: v ?? false));
              },
            ),
          ),
          const SizedBox(width: 4),
          // Bezeichnung + Langtext.
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _bez,
                  decoration: _dec(),
                  onChanged: (_) => _emit(),
                ),
                const SizedBox(height: 4),
                // Doppelklick öffnet einen Quill-Rich-Text-Editor in einem
                // Popup; der Inline-TextField bleibt für schnelle Plain-
                // Text-Eingaben. Sobald der Inhalt eine Quill-Delta (JSON-
                // Array) ist, wird er hier readonly gerendert (Plain-Text-
                // Vorschau) und kann nur noch über das Popup editiert
                // werden — sonst würde Tippen die Formatierung zerstören.
                Builder(builder: (context) {
                  final isDelta = _lang.text.trim().startsWith('[');
                  final preview = isDelta
                      ? plainTextFromDeltaJson(_lang.text)
                      : null;
                  return GestureDetector(
                    onDoubleTap: () => _openLangtextPopup(context),
                    child: Stack(
                      alignment: Alignment.topRight,
                      children: [
                        TextField(
                          controller: _lang,
                          decoration: _dec(
                              hint: isDelta
                                  ? null
                                  : 'optionaler Langtext (Doppelklick → Rich-Text-Editor)'),
                          minLines: 2,
                          maxLines: 4,
                          readOnly: isDelta,
                          onChanged: (_) => _emit(),
                          style: const TextStyle(fontSize: 12),
                          // Bei delta zeigen wir den extrahierten Plain-Text;
                          // den realen Delta-JSON behalten wir im Controller
                          // verborgen — geht nicht direkt mit TextEditing-
                          // Controller, daher Overlay-Vorschau:
                        ),
                        if (isDelta)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                color: Theme.of(context)
                                    .scaffoldBackgroundColor,
                                padding: const EdgeInsets.fromLTRB(
                                    8, 6, 36, 6),
                                child: Text(
                                  preview ?? '',
                                  style: const TextStyle(fontSize: 12),
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          top: 2,
                          right: 4,
                          child: Material(
                            color: Colors.transparent,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              iconSize: 16,
                              constraints: const BoxConstraints(
                                  minWidth: 28, minHeight: 28),
                              tooltip:
                                  'Rich-Text-Editor öffnen (oder Doppelklick)',
                              icon: const Icon(
                                  Icons.edit_note_outlined),
                              onPressed: () =>
                                  _openLangtextPopup(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: FormelTextField(
              controller: _menge,
              decoration: _dec(hint: '= z.B. 3*2'),
              textAlign: TextAlign.right,
              onChanged: (_) => _emit(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 86,
            child: TextField(
              controller: _einheit,
              decoration: _dec(),
              onChanged: (_) => _emit(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: FormelTextField(
              controller: _preis,
              decoration: _dec(hint: '= z.B. 120/8'),
              textAlign: TextAlign.right,
              onChanged: (_) => _emit(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                widget.position.optional
                    ? '(${widget.money.format(betrag)})'
                    : widget.money.format(betrag),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontStyle: widget.position.optional
                      ? FontStyle.italic
                      : FontStyle.normal,
                  color: widget.position.optional
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 24),
                  tooltip: 'Nach oben',
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: widget.onMoveUp,
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 24),
                  tooltip: 'Nach unten',
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: widget.onMoveDown,
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 24),
                  tooltip: 'Position entfernen',
                  icon: const Icon(Icons.close),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Kompakte Summen-Karte im SV-Software-Stil:
/// Zwischensumme — USt-Satz (inline Input) — Gesamtbetrag.
class PositionsSummaryCard extends StatelessWidget {
  const PositionsSummaryCard({
    super.key,
    required this.positions,
    required this.ustSatz,
    required this.onUstSatzChanged,
    required this.summenLabel,
    this.kleinunternehmer = false,
    this.onKleinunternehmerChanged,
  });

  final List<Position> positions;
  final double ustSatz;
  final ValueChanged<double> onUstSatzChanged;
  final String summenLabel;
  final bool kleinunternehmer;
  final ValueChanged<bool>? onKleinunternehmerChanged;

  static final _money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final netto = positions.fold<double>(0, (s, p) => s + p.nettoBetrag);
    final effUst = kleinunternehmer ? 0.0 : ustSatz;
    final ustBetrag = netto * (effUst / 100);
    final brutto = netto + ustBetrag;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(
            label: 'Zwischensumme (netto)',
            value: _money.format(netto),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('zzgl.', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              SizedBox(
                width: 48,
                child: _UstSatzField(
                  initial: ustSatz,
                  enabled: !kleinunternehmer,
                  onChanged: onUstSatzChanged,
                ),
              ),
              const SizedBox(width: 4),
              const Text('% USt.',
                  style: TextStyle(fontSize: 13)),
              const Spacer(),
              Text(
                _money.format(ustBetrag),
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _row(
                label: summenLabel,
                value: _money.format(brutto),
                bold: true,
                fontSize: 15,
              ),
            ),
          ),
          if (onKleinunternehmerChanged != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: kleinunternehmer,
                    onChanged: (v) => onKleinunternehmerChanged!(v ?? false),
                  ),
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Hinweis nach §19 UStG (keine USt. ausweisen)',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _row({
    required String label,
    required String value,
    bool bold = false,
    double fontSize = 13,
  }) {
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
    );
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }
}

class _UstSatzField extends StatefulWidget {
  const _UstSatzField({
    required this.initial,
    required this.enabled,
    required this.onChanged,
  });
  final double initial;
  final bool enabled;
  final ValueChanged<double> onChanged;
  @override
  State<_UstSatzField> createState() => _UstSatzFieldState();
}

class _UstSatzFieldState extends State<_UstSatzField> {
  late final _ctrl = TextEditingController(
      text: widget.initial.toStringAsFixed(0).replaceAll(RegExp(r'\.?0+$'), ''));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      enabled: widget.enabled,
      textAlign: TextAlign.center,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      onChanged: (v) {
        final parsed = double.tryParse(v.replaceAll(',', '.'));
        if (parsed != null) widget.onChanged(parsed);
      },
    );
  }
}

class _ArtikelPickerDialog extends ConsumerStatefulWidget {
  const _ArtikelPickerDialog();
  @override
  ConsumerState<_ArtikelPickerDialog> createState() =>
      _ArtikelPickerDialogState();
}

class _ArtikelPickerDialogState
    extends ConsumerState<_ArtikelPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(artikelListProvider);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Text('Artikel auswählen',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Suche Artikel',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Fehler: $e')),
                data: (items) {
                  final filtered = _query.isEmpty
                      ? items
                      : items
                          .where((a) =>
                              a.bezeichnung
                                  .toLowerCase()
                                  .contains(_query.toLowerCase()) ||
                              (a.nummer ?? '').toLowerCase().contains(
                                  _query.toLowerCase()))
                          .toList();
                  if (filtered.isEmpty) {
                    return const Center(child: Text('Keine Treffer'));
                  }
                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final a = filtered[i];
                      return ListTile(
                        dense: true,
                        title: Text(a.bezeichnung),
                        subtitle: Text([
                          if (a.nummer != null) 'Nr. ${a.nummer}',
                          if (a.kategorie != null) a.kategorie!,
                          if (a.einheit != null) a.einheit!,
                        ].join(' · ')),
                        trailing: Text(
                            '${a.einzelpreis.toStringAsFixed(2)} €'),
                        onTap: () => Navigator.pop(
                          context,
                          Position(
                            bezeichnung: a.bezeichnung,
                            menge: 1,
                            einheit: a.einheit ?? '',
                            einzelpreis: a.einzelpreis,
                            ustSatz: a.ustSatz,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picker für Textbausteine — öffnet eine such-/filterbare Liste aller
/// Textbausteine. Der ausgewählte Eintrag wird zurückgegeben.
class _TextbausteinPickerDialog extends ConsumerStatefulWidget {
  const _TextbausteinPickerDialog();
  @override
  ConsumerState<_TextbausteinPickerDialog> createState() =>
      _TextbausteinPickerDialogState();
}

class _TextbausteinPickerDialogState
    extends ConsumerState<_TextbausteinPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(textbausteineListProvider);
    return Dialog(
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.text_snippet_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Textbaustein wählen',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Titel, Kategorie, Inhalt',
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Fehler: $e')),
                data: (items) {
                  final q = _query.trim().toLowerCase();
                  final filtered = q.isEmpty
                      ? items
                      : items.where((b) {
                          return b.titel.toLowerCase().contains(q) ||
                              (b.kategorie ?? '').toLowerCase().contains(q) ||
                              (b.inhalt ?? '').toLowerCase().contains(q);
                        }).toList();
                  if (filtered.isEmpty) {
                    return const Center(child: Text('Keine Treffer.'));
                  }
                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final b = filtered[i];
                      final vorschau = (b.inhalt ?? '')
                          .replaceAll(RegExp(r'\s+'), ' ')
                          .trim();
                      return ListTile(
                        title: Text(b.titel),
                        subtitle: vorschau.isEmpty
                            ? null
                            : Text(vorschau,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                        trailing: b.kategorie == null
                            ? null
                            : Chip(
                                label: Text(b.kategorie!),
                                visualDensity: VisualDensity.compact,
                              ),
                        onTap: () => Navigator.of(context,
                                rootNavigator: true)
                            .pop(b),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vollwertiger Quill-Rich-Text-Editor in einem Modal-Dialog. Wird per
/// Doppelklick auf das Langtext-Feld einer Position geöffnet. Speichert
/// den Inhalt als Quill-Delta-JSON (Array) zurück.
class _LangtextEditorDialog extends StatefulWidget {
  const _LangtextEditorDialog({
    required this.initialDeltaJson,
    required this.bezeichnung,
  });
  final String initialDeltaJson;
  final String bezeichnung;

  @override
  State<_LangtextEditorDialog> createState() =>
      _LangtextEditorDialogState();
}

class _LangtextEditorDialogState extends State<_LangtextEditorDialog> {
  late String _current = widget.initialDeltaJson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
              child: Row(
                children: [
                  Icon(Icons.edit_note_outlined,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Langtext bearbeiten',
                            style: theme.textTheme.titleLarge),
                        if (widget.bezeichnung.trim().isNotEmpty)
                          Text(
                            widget.bezeichnung,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Schließen',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: RichTextEditor(
                  initialDeltaJson: widget.initialDeltaJson,
                  onChanged: (v) => _current = v,
                  minHeight: 360,
                  placeholder:
                      'Beschreibe die Position ausführlich. '
                      'Formatierungen (Fett/Kursiv/Listen) werden im PDF '
                      'übernommen.',
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Langtext leeren'),
                    onPressed: () =>
                        Navigator.of(context).pop(''),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Übernehmen'),
                    onPressed: () => Navigator.of(context).pop(_current),
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
