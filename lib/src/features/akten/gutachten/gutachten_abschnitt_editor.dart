import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, OrderingTerm, OrderingMode;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../../core/ai/rechtschreibung_service.dart';
import '../../../core/web/web_compat.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../akte/normen_picker_dialog.dart';
import '../lv/lv_insert_dialog.dart';
import 'gutachten_repository.dart';
import 'quill_image_embed.dart';

/// Standalone-Screen: Vollbild-Editor für einen einzelnen Gutachten-
/// Abschnitt mit Rich-Text-Editor (Quill), KI-Assistent und allen
/// Insert-Funktionen. Wird über einen eigenen Browser-Tab/-Fenster
/// geöffnet (Route `/gutachten/:id/abschnitt/:key`), damit der Nutzer
/// den ganzen Bildschirm bzw. einen zweiten Monitor nutzen kann.
class GutachtenAbschnittEditorScreen extends ConsumerStatefulWidget {
  const GutachtenAbschnittEditorScreen({
    super.key,
    required this.gutachtenId,
    required this.abschnittKey,
  });
  final int gutachtenId;
  final String abschnittKey;

  @override
  ConsumerState<GutachtenAbschnittEditorScreen> createState() =>
      _GutachtenAbschnittEditorScreenState();
}

class _GutachtenAbschnittEditorScreenState
    extends ConsumerState<GutachtenAbschnittEditorScreen> {
  quill.QuillController? _quill;
  GutachtenData? _gutachten;
  AuftraegeData? _auftrag;
  GutachtenAbschnitt? _abschnitt;
  bool _kiBusy = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  /// Auto-Save: Debounce-Timer + Status-Anzeige.
  Timer? _autoSaveTimer;
  bool _dirty = false;
  bool _autoSaving = false;
  DateTime? _zuletztGespeichert;
  static const _autoSaveDelay = Duration(seconds: 2);

  /// Fokus-Node für den Quill-Editor — wir reagieren auf Fokuswechsel,
  /// damit der orange Rahmen wie in den anderen Eingabefeldern erscheint.
  final FocusNode _editorFocus = FocusNode();
  final ScrollController _editorScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _editorFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _laden();
  }

  Future<void> _laden() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final g = await (db.select(db.gutachten)
            ..where((t) => t.id.equals(widget.gutachtenId)))
          .getSingleOrNull();
      if (g == null) {
        setState(() {
          _loading = false;
          _error =
              'Gutachten ${widget.gutachtenId} nicht gefunden — möglicherweise wurde es im anderen Tab inzwischen gelöscht.';
        });
        return;
      }
      final abschnitt = gutachtenAbschnitte
          .where((a) => a.key == widget.abschnittKey)
          .firstOrNull;
      AuftraegeData? auftrag;
      if (g.auftragId != null) {
        auftrag = await (db.select(db.auftraege)
              ..where((t) => t.id.equals(g.auftragId!)))
            .getSingleOrNull();
      }
      final inhalte = abschnitteFromJson(g.abschnitteJson);
      final raw = inhalte[widget.abschnittKey] ?? '';
      final controller = _buildController(raw);
      controller.document.changes.listen((_) => _onEditChange());
      if (!mounted) return;
      setState(() {
        _gutachten = g;
        _auftrag = auftrag;
        _abschnitt = abschnitt;
        _quill = controller;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Akzeptiert einen vorhandenen Plain-Text-Inhalt oder ein
  /// Quill-Delta-JSON-String und initialisiert den Quill-Controller.
  quill.QuillController _buildController(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return quill.QuillController.basic();
    if (t.startsWith('[') || t.startsWith('{')) {
      try {
        final decoded = jsonDecode(t);
        if (decoded is List) {
          return quill.QuillController(
            document: quill.Document.fromJson(decoded),
            selection: const TextSelection.collapsed(offset: 0),
          );
        }
      } catch (_) {}
    }
    // Plain-Text → Quill-Document mit nur Text.
    return quill.QuillController(
      document: quill.Document()..insert(0, t),
      selection: TextSelection.collapsed(offset: t.length),
    );
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _editorFocus.dispose();
    _editorScroll.dispose();
    // Letzte Änderungen flushen, falls der Nutzer das Fenster schließt
    // bevor der Debounce abgelaufen ist. Best-effort, kein await möglich.
    if (_dirty) {
      _persistAbschnitt();
    }
    super.dispose();
  }

  /// Wird vom Quill-Listener bei jeder Änderung aufgerufen. Debounced
  /// Auto-Save: 2 Sekunden Inaktivität → automatisch speichern.
  void _onEditChange() {
    if (!mounted) return;
    if (!_dirty) {
      setState(() => _dirty = true);
    }
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveDelay, _autoSave);
  }

  Future<void> _autoSave() async {
    if (!mounted || _autoSaving || _quill == null || _gutachten == null) return;
    setState(() => _autoSaving = true);
    try {
      await _persistAbschnitt();
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _zuletztGespeichert = DateTime.now();
      });
    } catch (_) {
      // Auto-Save: Fehler werden im Status-Indikator sichtbar (nicht
      // gespeichert seit …), aber wir reißen den Editor nicht mit einer
      // SnackBar auseinander. Manuelles _speichern() loggt den Fehler.
    } finally {
      if (mounted) setState(() => _autoSaving = false);
    }
  }

  /// Schreibt den aktuellen Quill-Delta-State in die DB. Gemeinsam genutzt
  /// von Auto-Save, manuellem Speichern und dem dispose()-Flush.
  Future<void> _persistAbschnitt() async {
    if (_quill == null || _gutachten == null) return;
    final db = ref.read(appDatabaseProvider);
    final inhalte = abschnitteFromJson(_gutachten!.abschnitteJson);
    // Wir speichern Quill-Delta-JSON, damit Formatierungen + Embeds
    // erhalten bleiben. Plain-Text wird aus dem Delta abgeleitet, wenn
    // gebraucht.
    final delta = _quill!.document.toDelta().toJson();
    inhalte[widget.abschnittKey] = jsonEncode(delta);
    await (db.update(db.gutachten)
          ..where((t) => t.id.equals(_gutachten!.id)))
        .write(GutachtenCompanion(
      abschnitteJson: Value(abschnitteToJson(inhalte)),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> _speichern({bool zurueck = true}) async {
    if (_quill == null || _gutachten == null) return;
    _autoSaveTimer?.cancel();
    setState(() => _saving = true);
    try {
      await _persistAbschnitt();
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _zuletztGespeichert = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Abschnitt gespeichert.')));
      if (zurueck) {
        // Der Editor läuft als eigenständiges Browser-Fenster (per
        // window.open geöffnet) — `Navigator.maybePop()` reicht nicht,
        // weil es nichts zum Pop'en gibt. Wir müssen zusätzlich
        // window.close() aufrufen, damit das Fenster wirklich zugeht.
        Navigator.of(context).maybePop();
        closeWindow();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _insertPlain(String text) {
    if (_quill == null) return;
    final sel = _quill!.selection;
    final base = sel.isValid ? sel.start : _quill!.document.length - 1;
    _quill!.document.insert(base, '\n$text\n');
    _quill!.updateSelection(
      TextSelection.collapsed(offset: base + text.length + 2),
      quill.ChangeSource.local,
    );
    setState(() {});
  }

  Future<void> _einfuegenTextbaustein() async {
    final db = ref.read(appDatabaseProvider);
    final liste = await (db.select(db.textbausteine)
          ..orderBy([(t) => OrderingTerm(expression: t.titel)]))
        .get();
    if (!mounted) return;
    final picked = await showDialog<TextbausteineData>(
      context: context,
      builder: (_) => _SimpleListPicker<TextbausteineData>(
        title: 'Textbaustein einfügen',
        items: liste,
        labelOf: (b) => b.titel,
        sublabelOf: (b) => b.kategorie ?? '',
      ),
    );
    if (picked == null) return;
    final raw = picked.inhalt ?? '';
    String plain;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        plain = quill.Document.fromJson(decoded).toPlainText().trim();
      } else {
        plain = raw;
      }
    } catch (_) {
      plain = raw;
    }
    if (plain.isNotEmpty) _insertPlain(plain);
  }

  Future<void> _einfuegenRecherche() async {
    final db = ref.read(appDatabaseProvider);
    final auftragId = _gutachten!.auftragId;
    // Wir holen alle und filtern client-seitig — das vermeidet Drift-
    // Operator-Magie und ist bei der erwarteten Listengröße günstig.
    final alle = await (db.select(db.rechercheNotizen)
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.createdAt, mode: OrderingMode.desc)
          ]))
        .get();
    final liste = auftragId == null
        ? alle
        : alle
            .where((n) => n.auftragId == null || n.auftragId == auftragId)
            .toList();
    if (!mounted) return;
    if (!mounted) return;
    final picked = await showDialog<RechercheNotizenData>(
      context: context,
      builder: (_) => _SimpleListPicker<RechercheNotizenData>(
        title: 'Recherche-Notiz einfügen',
        items: liste,
        labelOf: (n) => n.titel,
        sublabelOf: (n) => n.quelle ?? '',
      ),
    );
    if (picked == null) return;
    if (picked.inhalt.isNotEmpty) _insertPlain(picked.inhalt);
  }

  Future<void> _einfuegenLv() async {
    final t = await showLvInsertDialog(context,
        auftragId: _gutachten?.auftragId);
    if (t != null && t.isNotEmpty) _insertPlain(t);
  }

  Future<void> _einfuegenFoto() async {
    final db = ref.read(appDatabaseProvider);
    final fotos = await (db.select(db.fotos)
          ..where((t) => _gutachten!.auftragId == null
              ? t.id.isNotNull()
              : t.auftragId.equals(_gutachten!.auftragId!))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.aufnahmeAm, mode: OrderingMode.desc)
          ]))
        .get();
    if (!mounted) return;
    final picked = await showDialog<Foto>(
      context: context,
      builder: (_) => _FotoEinzelPicker(fotos: fotos),
    );
    if (picked == null) return;

    // Bytes aus DB oder — falls leer — aus Firebase-Storage nachladen.
    Uint8List? bytes = picked.daten;
    if (bytes == null || bytes.isEmpty) {
      final url = picked.storageUrl;
      if (url != null && url.isNotEmpty) {
        try {
          final resp = await http.get(Uri.parse(url));
          if (resp.statusCode == 200) bytes = resp.bodyBytes;
        } catch (_) {}
      }
    }
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Foto konnte nicht geladen werden.')));
      }
      return;
    }

    // Bild als Base64-Data-URL als Quill-Embed einfügen.
    final mime = picked.mimeType ?? 'image/jpeg';
    final base64Url = 'data:$mime;base64,${base64Encode(bytes)}';
    final sel = _quill!.selection;
    final pos = sel.isValid ? sel.start : _quill!.document.length - 1;
    _quill!.document.insert(pos, quill.BlockEmbed.image(base64Url));
    // Bildunterschrift unter das Bild.
    final caption =
        'Abb.: ${picked.titel ?? "Lichtbild Nr. ${picked.reihenfolge}"}'
        '${(picked.beschreibung ?? "").isEmpty ? "" : " — ${picked.beschreibung}"}';
    _quill!.document.insert(pos + 1, '\n$caption\n');
    _quill!.updateSelection(
      TextSelection.collapsed(offset: pos + caption.length + 2),
      quill.ChangeSource.local,
    );
    // Foto-Zuordnung in der DB setzen: gutachtenId verknüpft das Foto
    // mit dem Gutachten (Lichtbild-Anlage), gutachtenAbschnitt sorgt
    // dafür, dass das Bild im richtigen Abschnitt platziert wird (das
    // Gutachten-PDF nutzt diese Zuordnung für Inline-Lichtbilder).
    await (db.update(db.fotos)..where((t) => t.id.equals(picked.id))).write(
        FotosCompanion(
      gutachtenId: Value(widget.gutachtenId),
      gutachtenAbschnitt: Value(widget.abschnittKey),
    ));
    setState(() {});
  }

  Future<void> _einfuegenNorm() async {
    final db = ref.read(appDatabaseProvider);
    final normen = await (db.select(db.normen)
          ..where((t) => _gutachten!.auftragId == null
              ? t.id.isNotNull()
              : t.auftragId.equals(_gutachten!.auftragId!))
          ..orderBy([(t) => OrderingTerm(expression: t.nummer)]))
        .get();
    if (!mounted) return;
    final picked = await showDialog<NormenData>(
      context: context,
      builder: (_) => _SimpleListPicker<NormenData>(
        title: 'Norm einfügen',
        items: normen,
        labelOf: (n) => '${n.nummer} — ${n.titel ?? ""}',
        sublabelOf: (n) => n.kategorie ?? '',
        zusatzAction: _gutachten?.auftragId == null
            ? null
            : (
                'Aus Katalog ergänzen',
                () async {
                  Navigator.pop(context);
                  await showNormenKatalogPicker(context,
                      auftragId: _gutachten!.auftragId!);
                  await _laden();
                  if (!mounted) return;
                  await _einfuegenNorm();
                },
              ),
      ),
    );
    if (picked == null) return;
    final block = StringBuffer()
      ..writeln('Anwendbare Norm:')
      ..writeln('— ${picked.nummer}'
          '${(picked.ausgabe ?? "").isEmpty ? "" : ":${picked.ausgabe}"}'
          ' — ${picked.titel ?? ""}');
    if ((picked.zitat ?? '').isNotEmpty) {
      block.writeln('  „${picked.zitat}"');
    }
    _insertPlain(block.toString().trim());
  }

  Future<void> _einfuegenDokument() async {
    if (_gutachten == null) return;
    final db = ref.read(appDatabaseProvider);
    final dokumente = await (db.select(db.dokumente)
          ..where((t) => _gutachten!.auftragId == null
              ? t.id.isNotNull()
              : t.auftragId.equals(_gutachten!.auftragId!))
          ..orderBy([
            (t) => OrderingTerm(expression: t.datum, mode: OrderingMode.desc)
          ]))
        .get();
    if (!mounted) return;
    final picked = await showDialog<DokumenteData>(
      context: context,
      builder: (_) => _SimpleListPicker<DokumenteData>(
        title: 'Anlage / Dokument einfügen',
        items: dokumente,
        labelOf: (d) => d.titel ?? '(ohne Titel)',
        sublabelOf: (d) =>
            '${DateFormat('dd.MM.yyyy', 'de').format(d.datum)} · ${d.kategorie ?? ""}',
      ),
    );
    if (picked == null) return;

    // Anlagen-Liste am Gutachten pflegen: bestehende Einträge laden,
    // Doppel vermeiden (selber Dokument-Verweis bekommt selbe Nummer),
    // sonst nächste Nummer vergeben.
    final aktuelle = anlagenFromJson(_gutachten!.anlagenJson);
    GutachtenAnlage? eintrag = aktuelle
        .where((a) => a.dokumentId == picked.id)
        .firstOrNull;
    List<GutachtenAnlage> neuListe = aktuelle;
    if (eintrag == null) {
      final naechsteNr = aktuelle.isEmpty
          ? 1
          : aktuelle.map((a) => a.nr).reduce((a, b) => a > b ? a : b) + 1;
      eintrag = GutachtenAnlage(
        nr: naechsteNr,
        dokumentId: picked.id,
        titel: picked.titel ?? 'Dokument',
        kategorie: picked.kategorie,
        datum: picked.datum,
      );
      neuListe = [...aktuelle, eintrag];
      // Sofort persistieren, damit der PDF-Builder die Anlage findet.
      await (db.update(db.gutachten)
            ..where((t) => t.id.equals(_gutachten!.id)))
          .write(GutachtenCompanion(
        anlagenJson: Value(anlagenToJson(neuListe)),
        updatedAt: Value(DateTime.now()),
      ));
      // Lokale Kopie aktualisieren.
      final aktualisiert = await (db.select(db.gutachten)
            ..where((t) => t.id.equals(_gutachten!.id)))
          .getSingleOrNull();
      if (aktualisiert != null) {
        setState(() => _gutachten = aktualisiert);
      }
    }
    // Im Text nur einen Referenz-Marker setzen — der eigentliche Inhalt
    // hängt der PDF-Drucker hinten an.
    _insertPlain('[Anlage ${eintrag.nr} — ${eintrag.titel}]');
  }

  Future<void> _kiAnwenden(KiModus modus) async {
    if (_quill == null) return;
    final sel = _quill!.selection;
    final hasSel = sel.isValid && sel.start != sel.end;
    final input = hasSel
        ? _quill!.document
            .getPlainText(sel.start, sel.end - sel.start)
        : _quill!.document.toPlainText().trim();
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
        builder: (ctx) => AlertDialog(
          title: Text('KI-Vorschlag: ${modus.label}'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 480),
            child: SingleChildScrollView(
              child: SelectableText(ergebnis),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Verwerfen')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(hasSel
                    ? 'Selektion ersetzen'
                    : 'Gesamten Abschnitt ersetzen')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      if (hasSel) {
        _quill!.replaceText(
            sel.start, sel.end - sel.start, ergebnis, null);
      } else {
        _quill!.document = quill.Document()..insert(0, ergebnis);
      }
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('KI-Fehler: $e')));
    } finally {
      if (mounted) setState(() => _kiBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _abschnitt == null || _gutachten == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Abschnitt nicht ladbar')),
        body: Center(child: Text(_error ?? 'Abschnitt nicht gefunden.')),
      );
    }
    final label = _abschnitt!.nummer < 0
        ? _abschnitt!.label
        : '${_abschnitt!.nummer}. ${_abschnitt!.label}';
    final aktenzeichen = _auftrag?.aktenzeichen ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Text(label),
          const SizedBox(width: 12),
          if (aktenzeichen.isNotEmpty)
            Text(aktenzeichen,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 14)),
        ]),
        actions: [
          _AutoSaveStatus(
            autoSaving: _autoSaving,
            dirty: _dirty,
            zuletztGespeichert: _zuletztGespeichert,
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('Speichern (offen lassen)'),
            onPressed:
                _saving ? null : () => _speichern(zurueck: false),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check, size: 16),
            label: const Text('Speichern & schließen'),
            onPressed: _saving ? null : () => _speichern(zurueck: true),
          ),
          const SizedBox(width: 12),
        ],
      ),
      // Außen grau (passt zur Toolbar), das eigentliche Schreibfeld ist
      // innen weiß. Damit ist der Kontrast wie bei Google Docs / Word.
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      body: Column(
        children: [
          // Aktions-Toolbar (groß, mit Text-Labels — wir haben Platz)
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                    onPressed: _einfuegenTextbaustein,
                    icon: const Icon(Icons.article_outlined, size: 16),
                    label: const Text('Textbaustein')),
                OutlinedButton.icon(
                    onPressed: _einfuegenRecherche,
                    icon: const Icon(Icons.bookmark_outline, size: 16),
                    label: const Text('Recherche')),
                OutlinedButton.icon(
                    onPressed: _einfuegenLv,
                    icon: const Icon(Icons.list_alt_outlined, size: 16),
                    label: const Text('LV-Positionen')),
                OutlinedButton.icon(
                    onPressed: _einfuegenFoto,
                    icon: const Icon(Icons.image_outlined, size: 16),
                    label: const Text('Foto')),
                OutlinedButton.icon(
                    onPressed: _einfuegenNorm,
                    icon: const Icon(Icons.menu_book_outlined, size: 16),
                    label: const Text('Norm')),
                OutlinedButton.icon(
                    onPressed: _einfuegenDokument,
                    icon: const Icon(Icons.attach_file, size: 16),
                    label: const Text('Anlage')),
                Container(
                    width: 1, height: 24, color: Colors.grey.shade400),
                PopupMenuButton<KiModus>(
                  enabled: !_kiBusy,
                  tooltip: 'KI-Assistent',
                  position: PopupMenuPosition.under,
                  onSelected: _kiAnwenden,
                  itemBuilder: (_) => [
                    for (final m in KiModus.values)
                      PopupMenuItem(value: m, child: Text(m.label)),
                  ],
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: _kiBusy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome,
                            size: 16, color: Colors.amber),
                    label: const Text('KI-Assistent ▾'),
                  ),
                ),
              ],
            ),
          ),
          // Quill-Toolbar (Formatierung)
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: quill.QuillSimpleToolbar(
              controller: _quill!,
              config: quill.QuillSimpleToolbarConfig(
                buttonOptions: const quill.QuillSimpleToolbarButtonOptions(
                  fontFamily: quill.QuillToolbarFontFamilyButtonOptions(
                    initialValue: 'Standard',
                    items: {
                      'Standard': 'Inter',
                      'Arial': 'Arial',
                      'Times New Roman': 'Times New Roman',
                      'Helvetica': 'Helvetica',
                      'Courier New': 'Courier New',
                      'Georgia': 'Georgia',
                      'Verdana': 'Verdana',
                      'Zurücksetzen': 'Clear',
                    },
                    renderFontFamilies: true,
                  ),
                ),
                multiRowsDisplay: false,
                showFontFamily: true,
                showFontSize: true,
                showHeaderStyle: true,
                showColorButton: false,
                showBackgroundColorButton: false,
                showLink: false,
                showCodeBlock: false,
                showInlineCode: false,
                showQuote: true,
                showAlignmentButtons: true,
                showSearchButton: false,
                showDividers: true,
                showClearFormat: true,
                showSubscript: false,
                showSuperscript: false,
                showStrikeThrough: false,
                showIndent: true,
              ),
            ),
          ),
          const Divider(height: 1),
          // Editor füllt den Rest der Popup-Höhe. Außen liegt der graue
          // Scaffold-Hintergrund (Toolbar-Bereich), innen ist das Schreibfeld
          // weiß. Bei Fokus wird der Rahmen orange wie in den anderen
          // Eingabefeldern der App.
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(24, 14, 24, 16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _editorFocus.hasFocus
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade400,
                    width: _editorFocus.hasFocus ? 1.5 : 0.5,
                  ),
                ),
                child: quill.QuillEditor(
                  controller: _quill!,
                  focusNode: _editorFocus,
                  scrollController: _editorScroll,
                  config: const quill.QuillEditorConfig(
                    padding: EdgeInsets.all(16),
                    expands: true,
                    autoFocus: false,
                    embedBuilders: kAktenwerkEmbedBuilders,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleListPicker<T> extends StatelessWidget {
  const _SimpleListPicker({
    required this.title,
    required this.items,
    required this.labelOf,
    required this.sublabelOf,
    this.zusatzAction,
  });
  final String title;
  final List<T> items;
  final String Function(T) labelOf;
  final String Function(T) sublabelOf;
  /// Optional: zusätzliche Aktion neben „Schließen" (Label, Callback).
  final (String, VoidCallback)? zusatzAction;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                      child: Text(title,
                          style: Theme.of(context).textTheme.titleMedium)),
                  if (zusatzAction != null)
                    TextButton(
                        onPressed: zusatzAction!.$2,
                        child: Text(zusatzAction!.$1)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Text('Keine Einträge.'),
                      ),
                    )
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final it = items[i];
                        final lbl = labelOf(it);
                        final sub = sublabelOf(it);
                        return ListTile(
                          dense: true,
                          title:
                              Text(lbl, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: sub.isEmpty
                              ? null
                              : Text(sub, maxLines: 1),
                          onTap: () => Navigator.pop(context, it),
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

class _FotoEinzelPicker extends StatelessWidget {
  const _FotoEinzelPicker({required this.fotos});
  final List<Foto> fotos;

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
                Expanded(
                  child: Text('Foto inline einfügen',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: fotos.isEmpty
                  ? const Center(
                      child:
                          Padding(padding: EdgeInsets.all(40), child: Text('Keine Fotos.')))
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: fotos.length,
                      itemBuilder: (_, i) {
                        final f = fotos[i];
                        return InkWell(
                          onTap: () => Navigator.pop(context, f),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Column(
                              children: [
                                Expanded(
                                  child: _FotoVorschau(foto: f),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Text(
                                      f.titel ??
                                          'Lichtbild ${f.reihenfolge}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11)),
                                ),
                              ],
                            ),
                          ),
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

/// Foto-Vorschau im Picker-Grid: zeigt zuerst die in der DB gespeicherten
/// Bytes, fällt auf `storageUrl` (Firebase Storage) zurück. Ohne diesen
/// Fallback ist die Galerie für Web-only-uploads leer.
class _FotoVorschau extends StatelessWidget {
  const _FotoVorschau({required this.foto});
  final Foto foto;

  bool _looksLikeSvg(Uint8List bytes) {
    if (bytes.length < 5) return false;
    final head = String.fromCharCodes(
        bytes.take(200).where((b) => b > 0 && b < 128));
    return head.contains('<svg') || head.trimLeft().startsWith('<?xml');
  }

  @override
  Widget build(BuildContext context) {
    final daten = foto.daten;
    final mime = foto.mimeType ?? '';
    if (daten != null && daten.isNotEmpty) {
      if (mime == 'image/svg+xml' || _looksLikeSvg(daten)) {
        return SvgPicture.memory(daten,
            fit: BoxFit.cover, width: double.infinity);
      }
      return Image.memory(daten,
          fit: BoxFit.cover, width: double.infinity);
    }
    final url = foto.storageUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(url,
          fit: BoxFit.cover,
          width: double.infinity,
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
          errorBuilder: (_, _, _) =>
              const Icon(Icons.broken_image_outlined));
    }
    return const Icon(Icons.image_not_supported_outlined);
  }
}

/// Kleine Status-Anzeige rechts in der AppBar — ähnlich Google Docs.
/// Zeigt „Wird gespeichert …", „Nicht gespeichert" oder „Gespeichert vor …".
class _AutoSaveStatus extends StatelessWidget {
  const _AutoSaveStatus({
    required this.autoSaving,
    required this.dirty,
    required this.zuletztGespeichert,
  });
  final bool autoSaving;
  final bool dirty;
  final DateTime? zuletztGespeichert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    String text;
    IconData icon;
    if (autoSaving) {
      text = 'Wird gespeichert …';
      icon = Icons.cloud_upload_outlined;
    } else if (dirty) {
      text = 'Änderungen offen';
      icon = Icons.edit_note_outlined;
    } else if (zuletztGespeichert != null) {
      text =
          'Gespeichert ${DateFormat('HH:mm:ss').format(zuletztGespeichert!)}';
      icon = Icons.cloud_done_outlined;
    } else {
      text = 'Auto-Save aktiv';
      icon = Icons.cloud_outlined;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(text, style: style),
        ],
      ),
    );
  }
}
