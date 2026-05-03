import 'package:drift/drift.dart' show OrderingTerm, OrderingMode, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ai/rechtschreibung_service.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../akte/normen_picker_dialog.dart';
import '../lv/lv_insert_dialog.dart';

/// Vollbild-Popup für einen Gutachten-Abschnitt: großer Editor mit
/// Insert-Toolbar (Textbaustein, Recherche, LV, Foto-Bezug, Norm,
/// Anlage). Liefert den finalen Text als Plain-Text zurück oder
/// `null` bei Abbruch.
Future<String?> showGutachtenAbschnittPopup(
  BuildContext context, {
  required String label,
  required String inhalt,
  required int? auftragId,
  required String abschnittKey,
  required Future<String?> Function() pickTextbaustein,
  required Future<String?> Function() pickRecherche,
}) =>
    showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _AbschnittPopup(
        label: label,
        inhalt: inhalt,
        auftragId: auftragId,
        abschnittKey: abschnittKey,
        pickTextbaustein: pickTextbaustein,
        pickRecherche: pickRecherche,
      ),
    );

class _AbschnittPopup extends ConsumerStatefulWidget {
  const _AbschnittPopup({
    required this.label,
    required this.inhalt,
    required this.auftragId,
    required this.abschnittKey,
    required this.pickTextbaustein,
    required this.pickRecherche,
  });
  final String label;
  final String inhalt;
  final int? auftragId;
  final String abschnittKey;
  final Future<String?> Function() pickTextbaustein;
  final Future<String?> Function() pickRecherche;

  @override
  ConsumerState<_AbschnittPopup> createState() =>
      _AbschnittPopupState();
}

class _AbschnittPopupState extends ConsumerState<_AbschnittPopup> {
  late final _ctrl = TextEditingController(text: widget.inhalt);
  bool _kiBusy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Wendet einen KI-Modus auf den aktuellen Text (oder die Selektion)
  /// an und zeigt das Ergebnis in einem Vorschau-Dialog vor der
  /// Übernahme.
  Future<void> _kiAnwenden(KiModus modus) async {
    final sel = _ctrl.selection;
    final hasSelection =
        sel.isValid && sel.start != sel.end && sel.start >= 0;
    final input = hasSelection
        ? _ctrl.text.substring(sel.start, sel.end)
        : _ctrl.text;
    if (input.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bitte erst Text markieren oder schreiben.')));
      return;
    }
    setState(() => _kiBusy = true);
    try {
      final ergebnis = await kiAnwenden(ref, input, modus);
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Icon(Icons.auto_awesome, color: Colors.amber),
                    const SizedBox(width: 8),
                    Text('KI-Vorschlag: ${modus.label}',
                        style: Theme.of(ctx).textTheme.titleMedium),
                  ]),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(ctx)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: SelectableText(ergebnis),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
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
                        label: Text(hasSelection
                            ? 'Selektion ersetzen'
                            : 'Gesamten Text ersetzen'),
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
      if (ok == true && mounted) {
        setState(() {
          if (hasSelection) {
            final neu = _ctrl.text.replaceRange(sel.start, sel.end, ergebnis);
            _ctrl.text = neu;
            _ctrl.selection = TextSelection.collapsed(
                offset: sel.start + ergebnis.length);
          } else {
            _ctrl.text = ergebnis;
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('KI-Fehler: $e')));
    } finally {
      if (mounted) setState(() => _kiBusy = false);
    }
  }

  /// Fügt einen Textblock am Cursor (oder am Ende) ein, mit Leerzeile davor.
  void _insertAtCursor(String block) {
    final selection = _ctrl.selection;
    final before = _ctrl.text;
    final pos = selection.isValid ? selection.baseOffset : before.length;
    final praefix = pos > 0 && before.substring(0, pos).trimRight().isNotEmpty
        ? '\n\n'
        : '';
    final neu = before.substring(0, pos) +
        praefix +
        block.trim() +
        before.substring(pos);
    _ctrl.text = neu;
    _ctrl.selection = TextSelection.collapsed(
        offset: pos + praefix.length + block.trim().length);
    setState(() {});
  }

  Future<void> _einfuegenTextbaustein() async {
    final t = await widget.pickTextbaustein();
    if (t != null && t.isNotEmpty) _insertAtCursor(t);
  }

  Future<void> _einfuegenRecherche() async {
    final t = await widget.pickRecherche();
    if (t != null && t.isNotEmpty) _insertAtCursor(t);
  }

  Future<void> _einfuegenLv() async {
    final t = await showLvInsertDialog(context, auftragId: widget.auftragId);
    if (t != null && t.isNotEmpty) _insertAtCursor(t);
  }

  Future<void> _einfuegenFoto() async {
    final t = await _zeigeFotoPicker(
        context, ref, widget.auftragId, widget.abschnittKey);
    if (t != null && t.isNotEmpty) _insertAtCursor(t);
  }

  Future<void> _einfuegenNorm() async {
    final t = await _zeigeNormPicker(context, ref, widget.auftragId);
    if (t != null && t.isNotEmpty) _insertAtCursor(t);
  }

  Future<void> _einfuegenDokument() async {
    final t = await _zeigeDokumentPicker(context, ref, widget.auftragId);
    if (t != null && t.isNotEmpty) _insertAtCursor(t);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Column(
        children: [
          AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(widget.label),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Abbrechen'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Übernehmen'),
                onPressed: () => Navigator.pop(context, _ctrl.text),
              ),
              const SizedBox(width: 8),
            ],
          ),
          // Insert-Toolbar — kompakt mit Icon-Buttons + Tooltip.
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _iconBtn(Icons.article_outlined,
                    'Textbaustein einfügen', _einfuegenTextbaustein),
                _iconBtn(Icons.bookmark_outline,
                    'Recherche-Notiz einfügen', _einfuegenRecherche),
                _iconBtn(Icons.list_alt_outlined,
                    'LV-Positionen einfügen', _einfuegenLv),
                _iconBtn(Icons.image_outlined,
                    'Foto / Lichtbild einfügen', _einfuegenFoto),
                _iconBtn(Icons.menu_book_outlined, 'Norm einfügen',
                    _einfuegenNorm),
                _iconBtn(Icons.attach_file,
                    'Anlage / Dokument einfügen', _einfuegenDokument),
                const SizedBox(width: 8),
                Container(
                    width: 1, height: 24, color: Colors.grey.shade400),
                const SizedBox(width: 8),
                // KI-Toolbar: Popup-Menü mit allen KiModus-Werten.
                PopupMenuButton<KiModus>(
                  enabled: !_kiBusy,
                  tooltip:
                      'KI-Assistent (Korrektur, Umformulieren, Kürzen, Erweitern, Juristisch)',
                  position: PopupMenuPosition.under,
                  onSelected: _kiAnwenden,
                  itemBuilder: (_) => [
                    for (final m in KiModus.values)
                      PopupMenuItem(
                        value: m,
                        child: Row(
                          children: [
                            Icon(_kiIcon(m), size: 18),
                            const SizedBox(width: 10),
                            Text(m.label),
                          ],
                        ),
                      ),
                  ],
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                      child: _kiBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))
                          : const Icon(Icons.auto_awesome,
                              size: 20, color: Colors.amber),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 1000),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  child: TextField(
                    controller: _ctrl,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData ic, String tooltip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(ic, size: 20),
      tooltip: tooltip,
      onPressed: onTap,
    );
  }
}

IconData _kiIcon(KiModus m) {
  switch (m) {
    case KiModus.korrektur:
      return Icons.spellcheck;
    case KiModus.umformulieren:
      return Icons.shuffle;
    case KiModus.juristisch:
      return Icons.gavel;
    case KiModus.kuerzen:
      return Icons.compress;
    case KiModus.erweitern:
      return Icons.expand;
  }
}

// ---------- Foto-Picker ----------

Future<String?> _zeigeFotoPicker(BuildContext context, WidgetRef ref,
    int? auftragId, String abschnittKey) async {
  final db = ref.read(appDatabaseProvider);
  final fotos = await (db.select(db.fotos)
        ..where((t) =>
            auftragId == null ? t.id.isNotNull() : t.auftragId.equals(auftragId))
        ..orderBy([
          (t) =>
              OrderingTerm(expression: t.aufnahmeAm, mode: OrderingMode.desc),
        ]))
      .get();
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (ctx) => _FotoPickerDialog(
      fotos: fotos,
      abschnittKey: abschnittKey,
    ),
  );
}

class _FotoPickerDialog extends ConsumerStatefulWidget {
  const _FotoPickerDialog({
    required this.fotos,
    required this.abschnittKey,
  });
  final List<Foto> fotos;
  final String abschnittKey;

  @override
  ConsumerState<_FotoPickerDialog> createState() =>
      _FotoPickerDialogState();
}

class _FotoPickerDialogState extends ConsumerState<_FotoPickerDialog> {
  static final _fmt = DateFormat('dd.MM.yyyy', 'de');
  final _selected = <int>{};
  /// `true` = Inline-Bilder (Marker `[FOTO:#]` wird im PDF durchs Bild
  /// ersetzt). `false` = nur Anlagenverweis.
  bool _inline = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.image_outlined),
                const SizedBox(width: 10),
                Text('Fotos einfügen',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: widget.fotos.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Text(
                            'Noch keine Fotos zur Akte. Über das Akten-Modul „Fotos" hinzufügen.'),
                      ),
                    )
                  : ListView.separated(
                      itemCount: widget.fotos.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final f = widget.fotos[i];
                        return CheckboxListTile(
                          value: _selected.contains(f.id),
                          onChanged: (_) => setState(() {
                            if (_selected.contains(f.id)) {
                              _selected.remove(f.id);
                            } else {
                              _selected.add(f.id);
                            }
                          }),
                          title: Text(f.titel ?? 'Foto ${f.reihenfolge}'),
                          subtitle: Text([
                            if (f.aufnahmeAm != null)
                              _fmt.format(f.aufnahmeAm!),
                            if ((f.beschreibung ?? '').isNotEmpty)
                              f.beschreibung!,
                          ].whereType<String>().join(' · ')),
                          secondary: f.daten == null
                              ? null
                              : Image.memory(f.daten!,
                                  width: 60, height: 60, fit: BoxFit.cover),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Modus-Wahl
                  Expanded(
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                            value: false,
                            label: Text('Verweis (Anlage)',
                                style: TextStyle(fontSize: 11)),
                            icon: Icon(Icons.format_list_bulleted, size: 16)),
                        ButtonSegment(
                            value: true,
                            label: Text('Inline-Bild',
                                style: TextStyle(fontSize: 11)),
                            icon: Icon(Icons.image_outlined, size: 16)),
                      ],
                      selected: {_inline},
                      onSelectionChanged: (s) =>
                          setState(() => _inline = s.first),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: Text('${_selected.length} einfügen'),
                    onPressed: _selected.isEmpty
                        ? null
                        : () async {
                            final selected = widget.fotos
                                .where((f) => _selected.contains(f.id))
                                .toList();
                            final buf = StringBuffer();
                            if (_inline) {
                              // Inline-Modus: Marker [FOTO:id] dient als
                              // visueller Anker für den Nutzer; gleichzeitig
                              // wird die Foto-DB-Spalte `gutachtenAbschnitt`
                              // gesetzt, damit der PDF-Builder das Bild
                              // tatsächlich inline rendert.
                              final db = ref.read(appDatabaseProvider);
                              for (final f in selected) {
                                buf.writeln('[FOTO:${f.id}]');
                                final caption = [
                                  f.titel ?? "Lichtbild Nr. ${f.reihenfolge}",
                                  if (f.aufnahmeAm != null)
                                    _fmt.format(f.aufnahmeAm!),
                                  if ((f.beschreibung ?? "").isNotEmpty)
                                    f.beschreibung,
                                ].whereType<String>().join(' · ');
                                buf.writeln('Abb.: $caption');
                                buf.writeln();
                                await (db.update(db.fotos)
                                      ..where((t) => t.id.equals(f.id)))
                                    .write(FotosCompanion(
                                  gutachtenAbschnitt:
                                      Value(widget.abschnittKey),
                                ));
                              }
                            } else {
                              buf.writeln('Lichtbilder (siehe Anlage):');
                              for (final f in selected) {
                                buf.writeln(
                                    '— ${f.titel ?? "Lichtbild Nr. ${f.reihenfolge}"}'
                                    '${f.aufnahmeAm != null ? " (${_fmt.format(f.aufnahmeAm!)})" : ""}'
                                    '${(f.beschreibung ?? "").isEmpty ? "" : ": ${f.beschreibung}"}');
                              }
                            }
                            if (!context.mounted) return;
                            Navigator.pop(context, buf.toString().trim());
                          },
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

// ---------- Norm-Picker ----------

Future<String?> _zeigeNormPicker(
    BuildContext context, WidgetRef ref, int? auftragId) async {
  final db = ref.read(appDatabaseProvider);
  final normen = await (db.select(db.normen)
        ..where((t) =>
            auftragId == null ? t.id.isNotNull() : t.auftragId.equals(auftragId))
        ..orderBy([(t) => OrderingTerm(expression: t.nummer)]))
      .get();
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (ctx) => _NormPickerDialog(
        normen: normen, auftragId: auftragId),
  );
}

class _NormPickerDialog extends StatefulWidget {
  const _NormPickerDialog({
    required this.normen,
    required this.auftragId,
  });
  final List<NormenData> normen;
  final int? auftragId;

  @override
  State<_NormPickerDialog> createState() => _NormPickerDialogState();
}

class _NormPickerDialogState extends State<_NormPickerDialog> {
  final _selected = <int>{};

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.menu_book_outlined),
                const SizedBox(width: 10),
                Text('Normen einfügen',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (widget.auftragId != null)
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Aus Katalog'),
                    onPressed: () async {
                      Navigator.pop(context);
                      await showNormenKatalogPicker(context,
                          auftragId: widget.auftragId!);
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: widget.normen.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Text(
                            'Keine Normen zur Akte zugeordnet. Aus dem Katalog hinzufügen oder im Modul „Normen" anlegen.'),
                      ),
                    )
                  : ListView.separated(
                      itemCount: widget.normen.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final n = widget.normen[i];
                        return CheckboxListTile(
                          value: _selected.contains(n.id),
                          onChanged: (_) => setState(() {
                            if (_selected.contains(n.id)) {
                              _selected.remove(n.id);
                            } else {
                              _selected.add(n.id);
                            }
                          }),
                          title: Text('${n.nummer} — ${n.titel ?? ""}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text([
                            if ((n.ausgabe ?? '').isNotEmpty) n.ausgabe,
                            if ((n.kategorie ?? '').isNotEmpty)
                              n.kategorie,
                          ].whereType<String>().join(' · ')),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: Text('${_selected.length} einfügen'),
                    onPressed: _selected.isEmpty
                        ? null
                        : () {
                            final selected = widget.normen
                                .where((n) => _selected.contains(n.id))
                                .toList();
                            final buf = StringBuffer();
                            buf.writeln(
                                'Anwendbare Normen / Regelwerke:');
                            for (final n in selected) {
                              buf.writeln(
                                  '— ${n.nummer}'
                                  '${(n.ausgabe ?? "").isEmpty ? "" : ":${n.ausgabe}"}'
                                  ' — ${n.titel ?? ""}');
                              if ((n.zitat ?? '').isNotEmpty) {
                                buf.writeln('  „${n.zitat}"');
                              }
                            }
                            Navigator.pop(context, buf.toString().trim());
                          },
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

// ---------- Dokument-Picker ----------

Future<String?> _zeigeDokumentPicker(
    BuildContext context, WidgetRef ref, int? auftragId) async {
  final db = ref.read(appDatabaseProvider);
  final dokumente = await (db.select(db.dokumente)
        ..where((t) =>
            auftragId == null ? t.id.isNotNull() : t.auftragId.equals(auftragId))
        ..orderBy([
          (t) =>
              OrderingTerm(expression: t.datum, mode: OrderingMode.desc),
        ]))
      .get();
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (ctx) => _DokumentPickerDialog(dokumente: dokumente),
  );
}

class _DokumentPickerDialog extends StatefulWidget {
  const _DokumentPickerDialog({required this.dokumente});
  final List<DokumenteData> dokumente;

  @override
  State<_DokumentPickerDialog> createState() =>
      _DokumentPickerDialogState();
}

class _DokumentPickerDialogState extends State<_DokumentPickerDialog> {
  static final _fmt = DateFormat('dd.MM.yyyy', 'de');
  final _selected = <int>{};

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.attach_file),
                const SizedBox(width: 10),
                Text('Anlagen / Dokumente einfügen',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: widget.dokumente.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Text(
                            'Keine Dokumente zur Akte. Über den Akten-Tab „Dokumente" hinzufügen.'),
                      ),
                    )
                  : ListView.separated(
                      itemCount: widget.dokumente.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final d = widget.dokumente[i];
                        return CheckboxListTile(
                          value: _selected.contains(d.id),
                          onChanged: (_) => setState(() {
                            if (_selected.contains(d.id)) {
                              _selected.remove(d.id);
                            } else {
                              _selected.add(d.id);
                            }
                          }),
                          title:
                              Text(d.titel ?? '(ohne Titel)'),
                          subtitle: Text([
                            _fmt.format(d.datum),
                            if ((d.kategorie ?? '').isNotEmpty)
                              d.kategorie,
                          ].whereType<String>().join(' · ')),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: Text('${_selected.length} einfügen'),
                    onPressed: _selected.isEmpty
                        ? null
                        : () {
                            final selected = widget.dokumente
                                .where((d) => _selected.contains(d.id))
                                .toList();
                            final buf = StringBuffer();
                            buf.writeln('Anlagen:');
                            for (final d in selected) {
                              buf.writeln(
                                  '— ${d.titel ?? "Dokument"}'
                                  '${(d.kategorie ?? "").isEmpty ? "" : " (${d.kategorie})"}'
                                  ' vom ${_fmt.format(d.datum)}');
                              if ((d.beschreibung ?? '').isNotEmpty) {
                                buf.writeln('  ${d.beschreibung}');
                              }
                            }
                            Navigator.pop(context, buf.toString().trim());
                          },
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
