import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingMode, OrderingTerm, Value;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'quill_image_embed.dart';

import '../../../core/web/web_compat.dart';

import '../../../core/ai/rechtschreibung_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/aw_tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../features/akten/auftraege/auftraege_repository.dart';
import '../../../features/system/einstellungen/absender_service.dart';
import '../../../features/system/einstellungen/einstellungen_repository.dart';
import '../../../features/system/einstellungen/nummernkreis_service.dart';
import '../../../features/akten/akte/beteiligte_tab.dart';
import '../../../features/akten/akte/normen_picker_dialog.dart';
import '../../../features/akten/dokumente/dokumente_repository.dart';
import '../../../features/akten/gutachten/gutachten_abschnitt_popup.dart';
import '../../../features/akten/lv/lv_insert_dialog.dart';
import '../../../features/werkzeuge/recherche_ablage/recherche_ablage_repository.dart';
import '../../../shared/pdf/document_pdf.dart' show rasterizeIfSvg;
import '../../../shared/pdf/pdf_preview_dialog.dart';
import '../../../features/werkzeuge/textbausteine/textbausteine_repository.dart';
import '../../../shared/richtext/quill_editor.dart';
import '../../../shared/pdf/gutachten_pdf.dart';
import '../../../shared/widgets/badges.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'gutachten_repository.dart';

class GutachtenScreen extends ConsumerWidget {
  const GutachtenScreen({super.key});
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');

  static String _kundeName(KundenData? k) {
    if (k == null) return '—';
    final firma = (k.firma ?? '').trim();
    if (firma.isNotEmpty) return firma;
    final voll =
        '${(k.vorname ?? '').trim()} ${(k.nachname ?? '').trim()}'.trim();
    return voll.isEmpty ? '—' : voll;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(gutachtenListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.gavel_outlined,
          title: 'Gutachten',
          subtitle:
              'Strukturierte Gutachten nach Zöller (13 Abschnitte) mit Textbausteinen',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neues Gutachten'),
              onPressed: () => _openEditor(context, ref),
            ),
          ],
          searchHint: 'Suche Nr., Bezeichnung, Az. …',
          onSearchChanged: (v) =>
              ref.read(gutachtenQueryProvider.notifier).state = v,
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) => items.isEmpty
                ? const EmptyListState(
                    icon: Icons.gavel_outlined,
                    title: 'Noch keine Gutachten')
                : DataTableCard(
                    child: DataTable(
                      showCheckboxColumn: false,
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context).colorScheme.surfaceContainerLow,
                      ),
                      columns: const [
                        DataColumn(label: Text('G-Nr.')),
                        DataColumn(label: Text('Datum')),
                        DataColumn(label: Text('Akte')),
                        DataColumn(label: Text('Gerichtsakte')),
                        DataColumn(label: Text('Auftrag')),
                        DataColumn(label: Text('Kunde')),
                        DataColumn(label: Text('Gericht')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final g in items)
                          DataRow(
                            onSelectChanged: (_) => _openEditor(
                                context, ref,
                                vorhanden: g.gutachten),
                            cells: [
                              DataCell(Text(
                                // G-Nr.: bevorzugt nummer, fällt auf
                                // bezeichnung/titel zurück (alte Demo-
                                // Datensätze hatten die G-Nr. nur dort).
                                g.gutachten.nummer ??
                                    g.gutachten.bezeichnung ??
                                    g.gutachten.titel ??
                                    '—',
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 12),
                              )),
                              DataCell(Text(
                                g.gutachten.datum == null
                                    ? '—'
                                    : _dateFmt.format(g.gutachten.datum!),
                                style: const TextStyle(fontSize: 12),
                              )),
                              DataCell(Text(
                                g.auftrag?.aktenzeichen ?? '—',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.accent700,
                                    fontWeight: FontWeight.w600),
                              )),
                              DataCell(Text(
                                g.auftrag?.gerichtsAktenzeichen ??
                                    g.auftrag?.azExtern ??
                                    '—',
                                style: const TextStyle(fontSize: 12),
                              )),
                              DataCell(SizedBox(
                                width: 220,
                                child: Text(
                                  g.auftrag?.bezeichnung ??
                                      g.auftrag?.betreff ??
                                      '—',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              )),
                              DataCell(SizedBox(
                                width: 180,
                                child: Text(
                                  _kundeName(g.kunde),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              )),
                              DataCell(SizedBox(
                                width: 180,
                                child: Text(
                                  g.auftrag?.gericht ?? '—',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              )),
                              DataCell(_StatusPill(status: g.gutachten.status)),
                              DataCell(Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Bearbeiten',
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 18),
                                    onPressed: () => _openEditor(
                                        context, ref,
                                        vorhanden: g.gutachten),
                                  ),
                                  IconButton(
                                    tooltip: 'Löschen',
                                    icon: const Icon(
                                        Icons.delete_outline,
                                        size: 18),
                                    onPressed: () async => ref
                                        .read(gutachtenRepositoryProvider)
                                        .delete(g.gutachten.id),
                                  ),
                                ],
                              )),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref,
      {GutachtenData? vorhanden}) async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => _GutachtenEditor(gutachten: vorhanden),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (status) {
      'entwurf' => (BadgeColors.amberBg, BadgeColors.amberFg, 'Entwurf'),
      'fertiggestellt' =>
        (BadgeColors.blueBg, BadgeColors.blueFg, 'Fertiggestellt'),
      'versendet' =>
        (BadgeColors.greenBg, BadgeColors.greenFg, 'Versendet'),
      _ => (BadgeColors.slateBg, BadgeColors.slateFg, status),
    };
    return PillBadge(text: label, background: bg, foreground: fg);
  }
}

/// ---------------------------- Editor ----------------------------

Future<void> showGutachtenEditor(BuildContext context,
    {GutachtenData? gutachten, int? prefillAuftragId}) async {
  await showDialog(
    context: context,
    useRootNavigator: true,
    builder: (_) => _GutachtenEditor(
        gutachten: gutachten, prefillAuftragId: prefillAuftragId),
  );
}

class _GutachtenEditor extends ConsumerStatefulWidget {
  const _GutachtenEditor({this.gutachten, this.prefillAuftragId});
  final GutachtenData? gutachten;
  final int? prefillAuftragId;
  @override
  ConsumerState<_GutachtenEditor> createState() => _GutachtenEditorState();
}

class _GutachtenEditorState extends ConsumerState<_GutachtenEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _titel =
      TextEditingController(text: widget.gutachten?.titel ?? '');
  late final _nummer =
      TextEditingController(text: widget.gutachten?.nummer ?? '');
  late final _bezeichnung =
      TextEditingController(text: widget.gutachten?.bezeichnung ?? '');

  String _status = 'entwurf';
  String _vorlage = '';
  int? _auftragId;
  DateTime? _datum;
  DateTime? _ortstermin;
  DateTime? _abgabe;
  late Map<String, String> _abschnitte;

  /// Separate Controller pro Abschnitts-Textarea, damit Cursor &
  /// Undo-Historie nicht bei jedem Tipp-Event resettet werden.
  late Map<String, TextEditingController> _sektionCtrls;

  /// Initiale Controller-Werte beim Öffnen des Dialogs. Wir vergleichen
  /// damit beim Speichern, um zu erkennen welche Abschnitte lokal im
  /// Dialog editiert wurden vs. welche unverändert geblieben sind. Letztere
  /// dürfen wir nicht in die DB zurückschreiben, weil sie evtl. inzwischen
  /// im Popup-Editor mit Quill-Deltas (inkl. Bilder) befüllt wurden.
  Map<String, String> _initialAbschnitte = const {};

  /// Rohes Quill-Delta-JSON pro Abschnitt — wird nur befüllt wenn der
  /// Abschnitt im Popup-Editor mit Rich-Text gespeichert wurde (enthält
  /// z. B. Bilder oder Formatierungen). Wir nutzen das hier, um den
  /// Abschnitt im Dialog als read-only Quill-Editor zu rendern, damit
  /// der Anwender Text und Bilder direkt sieht statt nur Plain-Text.
  Map<String, String> _richDeltas = {};

  /// Stream auf den Gutachten-Datensatz: sobald der Popup-Editor in einem
  /// anderen Browser-Fenster speichert, kommt hier eine neue Version an
  /// und wir aktualisieren die Dialog-Felder, deren Inhalt der Nutzer im
  /// Dialog selbst nicht angefasst hat.
  StreamSubscription<GutachtenData?>? _gutachtenSub;

  /// Debounced Auto-Save bei jeder Tipp-Aktivität in den Sektionsfeldern.
  /// Spart einen manuellen „Speichern"-Klick — der Anwender schreibt
  /// einfach weiter, nach 2 s Inaktivität wird in die DB geschrieben.
  Timer? _autoSaveTimer;
  static const _autoSaveDelay = Duration(seconds: 2);

  bool _saving = false;
  bool _kiLaeuft = false;
  List<SprachCheckTreffer>? _sprachTreffer;

  static const _statusValues = ['entwurf', 'fertiggestellt', 'versendet'];
  static const _statusLabels = {
    'entwurf': 'Entwurf',
    'fertiggestellt': 'Fertiggestellt',
    'versendet': 'Versendet',
  };
  static const _vorlagenLabels = {
    '': '— keine Vorlage —',
    'bauschaden': 'Bauschaden-Gutachten',
    'beweissicherung': 'Beweissicherungs-Gutachten',
    'maengel': 'Mängelgutachten',
  };

  @override
  void initState() {
    super.initState();
    final g = widget.gutachten;
    _status = g?.status ?? 'entwurf';
    _auftragId = g?.auftragId ?? widget.prefillAuftragId;
    _datum = g?.datum ?? DateTime.now();
    _ortstermin = g?.ortsterminAm;
    _abgabe = g?.abgabeAm;
    _abschnitte = abschnitteFromJson(g?.abschnitteJson);
    // Beim Initialisieren extrahieren wir aus jedem Abschnitt den
    // anzeigbaren Plain-Text und merken uns separat das volle Quill-Delta
    // (für Read-Only-Rendering im Dialog inkl. Bilder).
    final plain = <String, String>{};
    for (final a in gutachtenAbschnitte) {
      plain[a.key] = _quillOderPlain(_abschnitte[a.key] ?? '', key: a.key);
    }
    _sektionCtrls = {
      for (final a in gutachtenAbschnitte)
        a.key: TextEditingController(text: plain[a.key] ?? ''),
    };
    _initialAbschnitte = {
      for (final a in gutachtenAbschnitte) a.key: plain[a.key] ?? '',
    };
    _gutachtenSub = _maybeWatchGutachten();
    // Auto-Save: bei jeder Tipp-Aktivität in den Sektionsfeldern den
    // Debounce-Timer zurücksetzen — nach 2 s Stille fließt der Stand in
    // die DB. Auch andere Felder (Nummer, Titel, Bezeichnung) lösen den
    // Trigger aus.
    for (final c in _sektionCtrls.values) {
      c.addListener(_planeAutoSave);
    }
    _titel.addListener(_planeAutoSave);
    _nummer.addListener(_planeAutoSave);
    _bezeichnung.addListener(_planeAutoSave);
    // Normenverzeichnis einmalig auto-befüllen, wenn der Anwender es noch
    // nicht selbst editiert hat. Asynchron, damit der Dialog sofort
    // erscheint und die Normen nachgezogen werden.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoFillNormenverzeichnisFallsLeer();
    });
  }

  void _planeAutoSave() {
    // Nicht speichern solange das Gutachten noch keine ID hat — sonst
    // legen wir bei jedem Buchstaben einen leeren Datensatz an.
    if (!_isEdit) return;
    if (_saving) return;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveDelay, () {
      if (!mounted) return;
      _save(silent: true);
    });
  }

  Future<void> _autoFillNormenverzeichnisFallsLeer() async {
    if (!mounted) return;
    final ctrl = _sektionCtrls['s_normenverzeichnis'];
    if (ctrl == null || ctrl.text.trim().isNotEmpty) return;
    if (_auftragId == null) return;
    final db = ref.read(appDatabaseProvider);
    final normen = await (db.select(db.normen)
          ..where((t) => t.auftragId.equals(_auftragId!))
          ..orderBy([(t) => OrderingTerm(expression: t.nummer)]))
        .get();
    final text = _formatNormenListe(normen);
    if (!mounted || text.isEmpty) return;
    setState(() {
      ctrl.text = text;
      _abschnitte['s_normenverzeichnis'] = text;
      // Initial-Wert nachziehen, damit das spätere Diff (lokal getippt
      // vs. unverändert) im _save-Merge nicht denkt, der Anwender hätte
      // das Feld manuell befüllt.
      _initialAbschnitte = {..._initialAbschnitte, 's_normenverzeichnis': text};
    });
  }

  /// Reagiert auf DB-Änderungen am gleichen Gutachten — typisch wenn der
  /// Standalone-Popup-Editor in einem zweiten Fenster speichert. Wir
  /// aktualisieren nur die Felder, die der Nutzer im Dialog nicht selbst
  /// editiert hat (Vergleich gegen `_initialAbschnitte`), damit lokales
  /// Tippen nicht überschrieben wird.
  StreamSubscription<GutachtenData?>? _maybeWatchGutachten() {
    final id = widget.gutachten?.id;
    if (id == null) return null;
    final db = ref.read(appDatabaseProvider);
    final stream = (db.select(db.gutachten)
          ..where((t) => t.id.equals(id)))
        .watchSingleOrNull();
    return stream.listen((row) {
      if (!mounted || row == null) return;
      final neuAbschnitte = abschnitteFromJson(row.abschnitteJson);
      var changed = false;
      for (final a in gutachtenAbschnitte) {
        final ctrl = _sektionCtrls[a.key];
        if (ctrl == null) continue;
        final lokalGetippt = ctrl.text != (_initialAbschnitte[a.key] ?? '');
        if (lokalGetippt) continue;
        // Quill-Delta in Plain-Text wandeln, damit das Material-TextField
        // sinnvoll anzeigt. Reine Plain-Text-Inhalte bleiben unverändert.
        final dbVal = neuAbschnitte[a.key] ?? '';
        final neuPlain = _quillOderPlain(dbVal, key: a.key);
        if (ctrl.text != neuPlain) {
          ctrl.text = neuPlain;
          _initialAbschnitte = {..._initialAbschnitte, a.key: neuPlain};
          changed = true;
        }
      }
      if (changed) setState(() {});
    });
  }

  /// Wenn `value` ein Quill-Delta-JSON ist, extrahiere den reinen Text.
  /// Sonst gib den Wert unverändert zurück. Setzt zusätzlich `key` in
  /// [_richDeltas], wenn das Delta wirklich Rich-Content enthält
  /// (Bild-Embeds oder Formatierungs-Attribute), damit der Dialog für
  /// diesen Abschnitt einen Quill-Reader rendern kann.
  String _quillOderPlain(String value, {String? key}) {
    final t = value.trim();
    if (t.isEmpty) {
      if (key != null) _richDeltas.remove(key);
      return '';
    }
    if (!(t.startsWith('[') || t.startsWith('{'))) {
      if (key != null) _richDeltas.remove(key);
      return value;
    }
    try {
      final decoded = jsonDecode(t);
      if (decoded is! List) {
        if (key != null) _richDeltas.remove(key);
        return value;
      }
      final buf = StringBuffer();
      var hatRich = false;
      for (final op in decoded) {
        if (op is! Map) continue;
        final insert = op['insert'];
        if (insert is String) {
          buf.write(insert);
        } else if (insert is Map && insert['image'] != null) {
          buf.write('[Bild]');
          hatRich = true;
        }
        if (op['attributes'] != null) hatRich = true;
      }
      if (key != null) {
        if (hatRich) {
          _richDeltas[key] = value;
        } else {
          _richDeltas.remove(key);
        }
      }
      return buf.toString();
    } catch (_) {
      if (key != null) _richDeltas.remove(key);
      return value;
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    // Letzten Stand noch flushen, falls der Anwender den Dialog
    // schließt bevor der Debounce abgelaufen ist.
    if (_isEdit) {
      // Best-effort: kein await im dispose möglich. Speichert i.d.R.
      // erfolgreich, weil die Drift-DB lokal ist.
      _save(silent: true);
    }
    _gutachtenSub?.cancel();
    _titel.dispose();
    _nummer.dispose();
    _bezeichnung.dispose();
    for (final c in _sektionCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.gutachten != null;

  /// Vorlagen-Wahl → nur leere Abschnitte mit Platzhalter-Ersetzung füllen.
  Future<void> _anwendenVorlage(String vorlage) async {
    if (vorlage.isEmpty) return;
    final v = gutachtenVorlagen[vorlage];
    if (v == null) return;
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: Text('Vorlage „${_vorlagenLabels[vorlage]}" anwenden?'),
        content: const Text(
            'Vorlage wird in alle leeren Abschnitte eingefügt. '
            'Bereits ausgefüllte Felder bleiben erhalten.'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(true),
            child: const Text('Vorlage einfügen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    AuftraegeData? auftrag;
    KundenData? kunde;
    if (_auftragId != null) {
      final list = await ref.read(auftraegeRepositoryProvider).watchAll().first;
      final match = list.where((a) => a.auftrag.id == _auftragId).firstOrNull;
      auftrag = match?.auftrag;
      kunde = match?.kunde;
    }
    setState(() {
      v.forEach((key, value) {
        final ctrl = _sektionCtrls[key];
        if (ctrl == null) return;
        if (ctrl.text.trim().isEmpty) {
          final text = applyVorlagenPlatzhalter(value,
              auftrag: auftrag, kunde: kunde);
          ctrl.text = text;
          _abschnitte[key] = text;
        }
      });
    });
  }

  Future<void> _pickTextbaustein(GutachtenAbschnitt abschnitt) async {
    final picked = await showDialog<TextbausteineData>(
      context: context,
      useRootNavigator: true,
      builder: (_) =>
          _TextbausteinPickerDialog(kategorie: abschnitt.textbausteinKategorie),
    );
    if (picked == null) return;
    AuftraegeData? auftrag;
    KundenData? kunde;
    if (_auftragId != null) {
      final list = await ref.read(auftraegeRepositoryProvider).watchAll().first;
      final match = list.where((a) => a.auftrag.id == _auftragId).firstOrNull;
      auftrag = match?.auftrag;
      kunde = match?.kunde;
    }
    final inhalt = applyVorlagenPlatzhalter(
        plainTextFromDeltaJson(picked.inhalt),
        auftrag: auftrag, kunde: kunde);
    final ctrl = _sektionCtrls[abschnitt.key]!;
    final aktuell = ctrl.text.trim();
    setState(() {
      ctrl.text = aktuell.isEmpty ? inhalt : '$aktuell\n\n$inhalt';
      _abschnitte[abschnitt.key] = ctrl.text;
    });
  }

  /// Öffnet den Recherche-Ablage-Picker. Nur Notizen der aktuellen
  /// Akte plus globale Notizen (ohne Auftrag-Zuordnung) werden gezeigt.
  /// Der ausgewählte Eintrag wird als Absatz ans Abschnitts-Feld
  /// angehängt und im Status „verwendet" markiert.
  Future<void> _pickRecherche(GutachtenAbschnitt abschnitt) async {
    final picked = await showDialog<RechercheNotizenData>(
      context: context,
      useRootNavigator: true,
      builder: (_) =>
          _RechercheAblagePicker(auftragId: _auftragId),
    );
    if (picked == null) return;
    final ctrl = _sektionCtrls[abschnitt.key]!;
    final aktuell = ctrl.text.trim();
    setState(() {
      ctrl.text = aktuell.isEmpty
          ? picked.inhalt
          : '$aktuell\n\n${picked.inhalt}';
      _abschnitte[abschnitt.key] = ctrl.text;
    });

    // Aus den strukturierten Norm-Referenzen die zitierten Normen
    // (samt Seitenangaben) als Akten-spezifische Normen anlegen, falls
    // sie nicht schon in der Akte stehen. So sind sie im Gutachten-PDF
    // mit Dokument-Nr., Ausgabe und Titel sauber als Quelle vermerkt.
    await _uebernehmeReferenzNormen(picked);

    // fire-and-forget — Fehler hier sind nicht kritisch
    await ref
        .read(rechercheAblageRepositoryProvider)
        .setVerwendet(picked.id, true);
  }

  /// Liefert den ausgewählten Textbaustein als Plain-Text mit Platz-
  /// halter-Ersetzung — für die Verwendung im Vollbild-Popup, das den
  /// Text direkt am Cursor einfügen will.
  Future<String?> _holeTextbausteinText() async {
    final picked = await showDialog<TextbausteineData>(
      context: context,
      useRootNavigator: true,
      builder: (_) => const _TextbausteinPickerDialog(kategorie: null),
    );
    if (picked == null) return null;
    AuftraegeData? auftrag;
    KundenData? kunde;
    if (_auftragId != null) {
      final list =
          await ref.read(auftraegeRepositoryProvider).watchAll().first;
      final match =
          list.where((a) => a.auftrag.id == _auftragId).firstOrNull;
      auftrag = match?.auftrag;
      kunde = match?.kunde;
    }
    return applyVorlagenPlatzhalter(
      plainTextFromDeltaJson(picked.inhalt),
      auftrag: auftrag,
      kunde: kunde,
    );
  }

  /// Liefert den ausgewählten Recherche-Eintrag als Plain-Text. Markiert
  /// die Notiz als verwendet und übernimmt referenzierte Normen.
  Future<String?> _holeRechercheText() async {
    final picked = await showDialog<RechercheNotizenData>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _RechercheAblagePicker(auftragId: _auftragId),
    );
    if (picked == null) return null;
    await _uebernehmeReferenzNormen(picked);
    await ref
        .read(rechercheAblageRepositoryProvider)
        .setVerwendet(picked.id, true);
    return picked.inhalt;
  }

  /// Öffnet den Abschnitt im eigenen Browser-Tab/-Fenster (Quill-Rich-
  /// Text-Editor mit Bild-Einbindung). Voraussetzung: Gutachten ist
  /// gespeichert (sonst keine ID). Nach dem Speichern in der neuen
  /// Tab muss der Nutzer das aktuelle Gutachten-Dialog manuell neu
  /// laden, damit die Änderung im Edit-Dialog erscheint — Drift-
  /// IndexedDB ist tab-übergreifend, aber TextEditingController nicht
  /// reaktiv.
  Future<void> _vergroessern(GutachtenAbschnitt abschnitt) async {
    // Vor dem Öffnen des Vollbild-Editors immer speichern — sonst sieht
    // das neue Fenster den Stand der DB, nicht den frisch im Dialog
    // eingegebenen Text. (Beim ersten Speichern entsteht außerdem die
    // Gutachten-ID, die wir in der URL brauchen.)
    _autoSaveTimer?.cancel();
    await _save(silent: true);
    if (!mounted) return;
    final id = widget.gutachten?.id;
    if (id == null) return;
    // Flutter Web nutzt Hash-Routing — der Hash muss mit in der URL
    // sein, damit go_router die Route im neuen Fenster auflösen kann.
    final url = '/#/gutachten-abschnitt/$id/${abschnitt.key}';
    // openInNewWindow nutzt window.open mit Popup-Hint — die meisten
    // Browser öffnen daraufhin ein eigenes Fenster (kein Tab) das man
    // auf den 2. Monitor schieben kann. Ist die Browser-Konfig strenger,
    // wird's ein Tab — dann kann der Nutzer ihn per Drag aus dem
    // Browser-Fenster herausziehen.
    openInNewWindow(
      url,
      name: 'aktenwerk-abschnitt-$id-${abschnitt.key}',
      features: 'popup,width=1260,height=900,menubar=no,toolbar=no,location=no',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Abschnitts-Editor in eigenem Fenster geöffnet. Nach dem Speichern den Gutachten-Dialog hier neu öffnen, damit Änderungen sichtbar werden.')));
    }
  }

  /// Öffnet den LV-Insert-Dialog und fügt die ausgewählten Positionen
  /// formatiert (tabellarisch / Aufzählung / Fließtext, mit/ohne Preise)
  /// als Block ans Abschnitts-Feld an.
  Future<void> _pickLvPositionen(GutachtenAbschnitt abschnitt) async {
    final block = await showLvInsertDialog(context, auftragId: _auftragId);
    if (block == null || block.isEmpty) return;
    final ctrl = _sektionCtrls[abschnitt.key]!;
    final aktuell = ctrl.text.trim();
    setState(() {
      ctrl.text = aktuell.isEmpty ? block : '$aktuell\n\n$block';
      _abschnitte[abschnitt.key] = ctrl.text;
    });
  }

  /// Übernimmt die Beteiligten + Auftraggeber aus der Akte und fügt sie
  /// formatiert in den aktuellen Abschnitt ein. Antwort: ein Block der
  /// Form „Beteiligte:\n— Rolle: Name, Anschrift\n…".
  Future<void> _pickBeteiligte(GutachtenAbschnitt abschnitt) async {
    final auftragId = _auftragId;
    if (auftragId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Kein Auftrag verknüpft — Beteiligte stehen erst zur '
                  'Verfügung, wenn das Gutachten einer Akte zugeordnet ist.')));
      return;
    }
    final list = await ref.read(auftraegeRepositoryProvider).watchAll().first;
    final match = list.where((a) => a.auftrag.id == auftragId).firstOrNull;
    if (match == null) return;
    final auftrag = match.auftrag;
    final kunde = match.kunde;

    final zeilen = <String>[];

    // 1) Auftraggeber (= Kunde der Akte)
    if (kunde != null) {
      final name = [kunde.firma, '${kunde.vorname ?? ''} ${kunde.nachname ?? ''}'.trim()]
          .where((s) => s != null && s.isNotEmpty)
          .join(' / ');
      final adresse = [
        kunde.strasse,
        '${kunde.plz ?? ''} ${kunde.ort ?? ''}'.trim(),
      ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
      if (name.isNotEmpty || adresse.isNotEmpty) {
        zeilen.add('— Auftraggeber: ${[name, adresse].where((s) => s.isNotEmpty).join(', ')}');
      }
    }

    // 2) Weitere Beteiligte aus beteiligteJson
    final weitere = decodeBeteiligte(auftrag.beteiligteJson);
    for (final b in weitere) {
      final teile = <String>[
        if (b.name.isNotEmpty) b.name,
        if (b.anschrift.isNotEmpty) b.anschrift,
        if (b.telefon.isNotEmpty) 'Tel. ${b.telefon}',
        if (b.email.isNotEmpty) b.email,
      ];
      if (teile.isEmpty) continue;
      final rolle = b.rolle.isEmpty ? 'Beteiligter' : b.rolle;
      zeilen.add('— $rolle: ${teile.join(', ')}');
    }

    // 3) Richter / Streitparteien aus den Akte-Stammdaten
    if ((auftrag.richter ?? '').isNotEmpty) {
      zeilen.add('— Richter: ${auftrag.richter}');
    }
    if ((auftrag.klaeger ?? '').isNotEmpty) {
      zeilen.add('— Kläger: ${auftrag.klaeger}');
    }
    if ((auftrag.beklagter ?? '').isNotEmpty) {
      zeilen.add('— Beklagter: ${auftrag.beklagter}');
    }

    if (zeilen.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Keine Beteiligten in der Akte hinterlegt. Tab „Beteiligte" '
              'öffnen und dort eintragen.')));
      return;
    }
    final block = 'Beteiligte:\n${zeilen.join('\n')}';
    final ctrl = _sektionCtrls[abschnitt.key]!;
    final aktuell = ctrl.text.trim();
    setState(() {
      ctrl.text = aktuell.isEmpty ? block : '$aktuell\n\n$block';
      _abschnitte[abschnitt.key] = ctrl.text;
    });
  }

  /// Liest die Normen der Akte und schreibt eine formatierte Liste in
  /// das Normenverzeichnis-Feld. Überschreibt einen evtl. vorhandenen
  /// Inhalt — der Anwender kann danach manuell ergänzen.
  Future<void> _normenAusAkteEinfuegen(GutachtenAbschnitt abschnitt) async {
    if (_auftragId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Erst Akte verknüpfen — dann lassen sich die Normen einfügen.')));
      return;
    }
    final db = ref.read(appDatabaseProvider);
    final normen = await (db.select(db.normen)
          ..where((t) => t.auftragId.equals(_auftragId!))
          ..orderBy([(t) => OrderingTerm(expression: t.nummer)]))
        .get();
    final text = _formatNormenListe(normen);
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Keine Normen in der Akte hinterlegt. Tab „Normen" der Akte öffnen und eintragen.')));
      return;
    }
    final ctrl = _sektionCtrls[abschnitt.key]!;
    setState(() {
      ctrl.text = text;
      _abschnitte[abschnitt.key] = ctrl.text;
    });
  }

  /// Plain-Text-Formatierung der Normenliste — eine Zeile pro Norm.
  String _formatNormenListe(List<NormenData> normen) {
    if (normen.isEmpty) return '';
    return normen.map((n) {
      final teile = <String>[
        n.nummer,
        if ((n.ausgabe ?? '').isNotEmpty) '(${n.ausgabe})',
        if ((n.titel ?? '').isNotEmpty) '— ${n.titel}',
      ];
      return '• ${teile.join(' ')}';
    }).join('\n');
  }

  /// Öffnet einen Picker mit allen Fotos + Dokumenten der Akte. Der
  /// Anwender wählt aus, was als Anlage ans Gutachten gehängt werden
  /// soll. Beim Bestätigen werden:
  ///   • die Foto-Zuordnungen (gutachtenId-Spalte) in der DB gepflegt,
  ///   • die Dokumente in `gutachten.anlagenJson` gepflegt,
  ///   • das Anlagenverzeichnis-Feld mit der aktuellen Liste gefüllt.
  Future<void> _pickAnlagenAusAkte(GutachtenAbschnitt abschnitt) async {
    if (_auftragId == null || widget.gutachten == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Erst Akte verknüpfen + Gutachten speichern, dann Anlagen auswählen.')));
      return;
    }
    final neu = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _AnlagenAusAktePicker(
        auftragId: _auftragId!,
        gutachtenId: widget.gutachten!.id,
      ),
    );
    if (neu == null) return;
    final ctrl = _sektionCtrls[abschnitt.key]!;
    setState(() {
      ctrl.text = neu;
      _abschnitte[abschnitt.key] = ctrl.text;
    });
  }

  /// Liest `referenzNormenJson` der gewählten Notiz und legt für jede
  /// referenzierte Library-Norm eine akten-spezifische Kopie an, sofern
  /// noch keine mit gleicher Nummer für diesen Auftrag existiert.
  Future<void> _uebernehmeReferenzNormen(RechercheNotizenData notiz) async {
    final auftragId = _auftragId;
    if (auftragId == null) return;
    final raw = notiz.referenzNormenJson;
    if (raw == null || raw.trim().isEmpty) return;
    List<dynamic> liste;
    try {
      liste = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return;
    }
    if (liste.isEmpty) return;
    final db = ref.read(appDatabaseProvider);
    int uebernommen = 0;
    for (final entry in liste) {
      // Backwards-Kompatibilität: alte Format `[12, 47]` sind nur IDs.
      int? normId;
      List<int> seiten = const [];
      if (entry is num) {
        normId = entry.toInt();
      } else if (entry is Map) {
        final id = entry['normId'];
        if (id is num) normId = id.toInt();
        final s = entry['seiten'];
        if (s is List) {
          seiten = s.whereType<num>().map((e) => e.toInt()).toList();
        }
      }
      if (normId == null) continue;
      // Library-Norm laden
      final library = await (db.select(db.normen)
            ..where((t) => t.id.equals(normId!)))
          .getSingleOrNull();
      if (library == null) continue;
      // Schon in der Akte?
      final vorhandenQuery = db.select(db.normen)
        ..where((t) => t.auftragId.equals(auftragId))
        ..where((t) => t.nummer.equals(library.nummer));
      final vorhanden = await vorhandenQuery.getSingleOrNull();
      if (vorhanden != null) continue;
      // Akten-Norm anlegen — alle Stammdaten kopieren, Seitenangaben als
      // `zitat`-Feld („S. 12, S. 17") und `relevanz='gutachten'`.
      final seitenStr = seiten.isEmpty
          ? null
          : 'Zitiert: ${(seiten..sort()).map((p) => 'S. $p').join(', ')}';
      await db.into(db.normen).insert(NormenCompanion.insert(
            auftragId: Value(auftragId),
            nummer: library.nummer,
            titel: Value(library.titel),
            ausgabe: Value(library.ausgabe),
            kategorie: Value(library.kategorie),
            art: Value(library.art),
            herausgeber: Value(library.herausgeber),
            relevanz: const Value('gutachten'),
            zusammenfassung: Value(library.zusammenfassung),
            zitat: Value(seitenStr),
            beschreibung: Value(library.beschreibung),
            gewerk: Value(library.gewerk),
            pdfPfad: Value(library.pdfPfad),
            pdfStorageUrl: Value(library.pdfStorageUrl),
            pdfMimeType: Value(library.pdfMimeType),
            pdfGroesse: Value(library.pdfGroesse),
            pdfDateiname: Value(library.pdfDateiname),
          ));
      uebernommen++;
    }
    if (uebernommen > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '$uebernommen Norm${uebernommen == 1 ? '' : 'en'} in die Akte übernommen.')));
    }
  }

  IconData _kiIcon(KiModus m) => switch (m) {
        KiModus.korrektur => Icons.spellcheck,
        KiModus.umformulieren => Icons.edit_note,
        KiModus.juristisch => Icons.gavel,
        KiModus.kuerzen => Icons.compress,
        KiModus.erweitern => Icons.expand,
      };

  /// Wendet den gewählten KI-Modus parallel auf alle nicht-leeren
  /// Abschnittsfelder an. Zeigt anschließend einen Review-Dialog mit
  /// allen geänderten Abschnitten nebeneinander — der Nutzer kann
  /// komplett übernehmen oder abbrechen.
  Future<void> _kiAnwendenAlle(KiModus modus) async {
    // Aktuelle Feld-Inhalte einsammeln; nur nicht-leere Sektionen verarbeiten.
    final eintraege = <String, String>{};
    for (final e in _sektionCtrls.entries) {
      final t = e.value.text.trim();
      if (t.isNotEmpty) eintraege[e.key] = t;
    }
    if (eintraege.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Keine Abschnitte mit Inhalt gefunden.')));
      return;
    }

    setState(() => _kiLaeuft = true);
    Map<String, String> ergebnisse;
    try {
      // Parallel ausführen — Gemini-Flash ist schnell, 13 Calls brauchen
      // typischerweise 2–4 Sekunden gesamt.
      final futures = eintraege.entries
          .map((e) async =>
              MapEntry(e.key, await kiAnwenden(ref, e.value, modus)));
      final results = await Future.wait(futures);
      ergebnisse = Map.fromEntries(results);
    } catch (e) {
      if (mounted) {
        setState(() => _kiLaeuft = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('KI-Aufruf fehlgeschlagen: $e')));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _kiLaeuft = false);

    // Nur geänderte Abschnitte im Review zeigen.
    final geaendert = <String, (String, String)>{};
    for (final a in gutachtenAbschnitte) {
      final orig = eintraege[a.key];
      final neu = ergebnisse[a.key];
      if (orig == null || neu == null) continue;
      if (orig.trim() == neu.trim()) continue;
      geaendert[a.key] = (orig, neu);
    }
    if (geaendert.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(modus == KiModus.korrektur
              ? 'Keine Fehler gefunden — Text bleibt unverändert.'
              : 'KI hat keine Änderung vorgeschlagen.')));
      return;
    }

    final uebernehmen = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _GutachtenKiReviewDialog(
        modus: modus,
        geaendert: geaendert,
      ),
    );
    if (uebernehmen != true) return;

    // Rich-Sektionen (mit Bild-Embeds) speichern wir als gemergten
    // Quill-Delta direkt in die DB — der Controller bleibt mit dem
    // Plain-Text für die Anzeige, die DB hält Text + Bilder. Plain-Text-
    // Sektionen wie bisher nur über den Controller.
    final db = ref.read(appDatabaseProvider);
    final aktualisierteRichDeltas = <String, String>{};
    final dbSchreibSet = <String, String>{};
    for (final eintrag in geaendert.entries) {
      final neuPlain = eintrag.value.$2;
      final originalDelta = _richDeltas[eintrag.key];
      if (originalDelta != null) {
        final neuDelta = _kiBuildDeltaMitBildern(neuPlain, originalDelta);
        if (neuDelta != null) {
          dbSchreibSet[eintrag.key] = neuDelta;
          aktualisierteRichDeltas[eintrag.key] = neuDelta;
        }
      }
    }
    // DB-Update für Rich-Sektionen sofort ausführen — sonst überschreibt
    // das spätere _save() (mit Controller-Plain-Text) die Bilder.
    if (_isEdit && dbSchreibSet.isNotEmpty) {
      final dbGutachten = await (db.select(db.gutachten)
            ..where((t) => t.id.equals(widget.gutachten!.id)))
          .getSingleOrNull();
      if (dbGutachten != null) {
        final neueAbschnitte = {
          ...abschnitteFromJson(dbGutachten.abschnitteJson),
          ...dbSchreibSet,
        };
        await (db.update(db.gutachten)
              ..where((t) => t.id.equals(widget.gutachten!.id)))
            .write(GutachtenCompanion(
          abschnitteJson: Value(abschnitteToJson(neueAbschnitte)),
          updatedAt: Value(DateTime.now()),
        ));
      }
    }
    if (!mounted) return;
    setState(() {
      for (final eintrag in geaendert.entries) {
        final ctrl = _sektionCtrls[eintrag.key];
        if (ctrl == null) continue;
        ctrl.text = eintrag.value.$2;
        _abschnitte[eintrag.key] = eintrag.value.$2;
        // Initial nachziehen, damit das spätere _save() die Sektion nicht
        // als „lokal getippt" sieht und den frisch geschriebenen Delta
        // mit Plain-Text überschreibt.
        if (aktualisierteRichDeltas.containsKey(eintrag.key)) {
          _initialAbschnitte = {
            ..._initialAbschnitte,
            eintrag.key: eintrag.value.$2,
          };
          _richDeltas[eintrag.key] = aktualisierteRichDeltas[eintrag.key]!;
        }
      }
    });
  }

  /// Baut aus dem KI-Plain-Text und dem ursprünglichen Quill-Delta
  /// (mit Bild-Embeds) ein neues Delta: zuerst der neue Text, danach
  /// alle Bild-Embeds aus dem Original. Liefert `null`, wenn das
  /// Original kein Quill-Delta ist.
  String? _kiBuildDeltaMitBildern(String neuPlain, String originalDelta) {
    final t = originalDelta.trim();
    if (!(t.startsWith('[') || t.startsWith('{'))) return null;
    dynamic decoded;
    try {
      decoded = jsonDecode(t);
    } catch (_) {
      return null;
    }
    if (decoded is! List) return null;
    final imageOps = <Map<String, dynamic>>[];
    for (final op in decoded) {
      if (op is! Map) continue;
      final insert = op['insert'];
      if (insert is Map && insert['image'] != null) {
        imageOps.add(<String, dynamic>{'insert': {'image': insert['image']}});
      }
    }
    if (imageOps.isEmpty) return null;
    final neueOps = <Map<String, dynamic>>[
      {'insert': '$neuPlain\n'},
      for (final img in imageOps) ...[
        img,
        {'insert': '\n'},
      ],
    ];
    return jsonEncode(neueOps);
  }

  void _runSprachCheck() {
    // Aktuelle Feld-Inhalte einsammeln und prüfen.
    final map = <String, String>{
      for (final e in _sektionCtrls.entries) e.key: e.value.text,
    };
    final treffer = runSprachCheck(map);
    setState(() => _sprachTreffer = treffer);
    if (treffer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Sprach-Check: Keine typischen Floskeln gefunden — sehr gut.')));
    }
  }

  /// Druck-und-Archivieren-Workflow:
  /// 1) Falls Gutachten noch keine Nummer hat → eine aus dem
  ///    Gutachten-Nummernkreis ziehen (Default `{aktenzeichen}-G{N}`).
  /// 2) Status auf „versendet" setzen.
  /// 3) PDF/A (Langzeit-Archiv-Format) generieren.
  /// 4) Als Akten-Dokument unter Kategorie „Gutachten" ablegen.
  /// 5) Druck-Dialog öffnen.
  Future<void> _druckenUndArchivieren() async {
    if (!_isEdit) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Bitte erst speichern, dann drucken & ablegen.')));
      return;
    }
    setState(() => _saving = true);
    try {
      // 1) Nummer ggf. ziehen
      var nummer = _nummer.text.trim();
      if (nummer.isEmpty) {
        AuftraegeData? auftrag;
        if (_auftragId != null) {
          final list = await ref
              .read(auftraegeRepositoryProvider)
              .watchAll()
              .first;
          final match = list
              .where((a) => a.auftrag.id == _auftragId)
              .firstOrNull;
          auftrag = match?.auftrag;
        }
        nummer = await ref
            .read(nummernkreisServiceProvider)
            .nextNumber(NummernkreisTyp.gutachten,
                aktenzeichen: auftrag?.aktenzeichen);
        _nummer.text = nummer;
      }

      // 2+3) Speichern + Status setzen — die lokalen Controller-Werte
      // landen in der DB. Dadurch sind alle Edits aus dem Dialog plus
      // alle Edits aus dem Popup-Editor (die direkt in die DB
      // geschrieben haben) konsistent.
      _status = 'versendet';
      await _save(silent: true);

      // 4) PDF erzeugen
      final bytes = await _baueGutachtenPdfBytes(pdfA: true);

      // 5) Im Akten-Archiv ablegen
      if (_auftragId != null) {
        final dateiname =
            'Gutachten_${nummer.replaceAll(RegExp(r"[^A-Za-z0-9-]"), "_")}.pdf';
        await ref.read(dokumenteRepositoryProvider).upsert(
              DokumenteCompanion.insert(
                titel: Value(dateiname),
                mimeType: const Value('application/pdf'),
                dateigroesse: Value(bytes.length),
                daten: Value(bytes),
                auftragId: Value(_auftragId!),
                kategorie: const Value('Gutachten'),
                datum: Value(DateTime.now()),
                beschreibung: Value(_titel.text.trim()),
              ),
            );
      }

      // 6) Vorschau / Druck-Dialog
      if (!mounted) return;
      await showPdfPreviewDialog(
        context,
        title: 'Gutachten $nummer',
        builder: () async => bytes,
        dateiname:
            'Gutachten_${nummer.replaceAll(RegExp(r"[^A-Za-z0-9-]"), "_")}.pdf',
        maxWidth: MediaQuery.of(context).size.width * 0.42,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Gutachten $nummer als PDF/A in der Akte abgelegt (Tab „Dokumente").')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Baut die PDF-Bytes — gemeinsam genutzt für Vorschau und Archiv.
  Future<Uint8List> _baueGutachtenPdfBytes({bool pdfA = false}) async {
    final daten = await _baueGutachtenPdfData();
    return buildGutachtenPdf(daten, pdfA: pdfA);
  }

  Future<GutachtenPdfData> _baueGutachtenPdfData() async {
    final absender = await absenderFromSettings(ref);
    AuftraegeData? auftrag;
    KundenData? kunde;
    if (_auftragId != null) {
      final list =
          await ref.read(auftraegeRepositoryProvider).watchAll().first;
      final match =
          list.where((a) => a.auftrag.id == _auftragId).firstOrNull;
      auftrag = match?.auftrag;
      kunde = match?.kunde;
    }
    // Abschnitte aus DB neu lesen, lokale Dialog-Edits per Merge erhalten:
    // Schlüssel, die im Dialog editiert wurden, gewinnen; alle anderen
    // werden aus der DB übernommen (dort liegen u. a. Quill-Deltas mit
    // Bildern, die der Popup-Editor geschrieben hat).
    final mergedAbschnitte = await _mergeAbschnitteMitDb();
    // SVG-Bilder in Quill-Embeds vor dem PDF-Build rastern — sonst kann
    // das pdf-Paket sie nicht einbetten („Unable to guess the image type").
    final aktuelleAbschnitte = <String, String>{};
    for (final e in mergedAbschnitte.entries) {
      aktuelleAbschnitte[e.key] = await _rasterSvgEmbeds(e.value);
    }
    final snapshot = GutachtenData(
      id: widget.gutachten?.id ?? 0,
      auftragId: _auftragId,
      nummer: _nummer.text.trim().isEmpty ? null : _nummer.text.trim(),
      datum: _datum,
      titel: _titel.text.trim().isEmpty ? null : _titel.text.trim(),
      bezeichnung: _bezeichnung.text.trim().isEmpty
          ? null
          : _bezeichnung.text.trim(),
      vorlage: _vorlage.isEmpty ? 'frei' : _vorlage,
      status: _status,
      ortsterminAm: _ortstermin,
      abgabeAm: _abgabe,
      abschnitteJson: abschnitteToJson(aktuelleAbschnitte),
      createdAt: widget.gutachten?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final repo = ref.read(einstellungenRepositoryProvider);
    // Optionales zweites Logo (Briefkopf-Einstellungen). Wir bauen die
    // data:-URL zusammen — `loadLogoForPdf` versteht das gleiche Format
    // wie für das Haupt-Logo.
    String? logoPfad2;
    final logo2B64 = await repo.get(SettingsKeys.firmaLogo2Base64);
    if (logo2B64 != null && logo2B64.isNotEmpty) {
      final logo2Mime =
          await repo.get(SettingsKeys.firmaLogo2Mime) ?? 'image/png';
      logoPfad2 = 'data:$logo2Mime;base64,$logo2B64';
    }
    final siegelB64 = await repo.get(SettingsKeys.siegelBase64);
    final sigB64 = await repo.get(SettingsKeys.unterschriftBase64);
    final pos = await repo.get(SettingsKeys.siegelPosition);
    final beh = await repo.get(SettingsKeys.siegelBestellBehoerde);
    final nr = await repo.get(SettingsKeys.siegelBestellNr);
    final gueltigBisRaw = await repo.get(SettingsKeys.siegelGueltigBis);
    final gueltigBis = (gueltigBisRaw != null && gueltigBisRaw.isNotEmpty)
        ? DateTime.tryParse(gueltigBisRaw)
        : null;
    Uint8List? siegelBytes;
    if (siegelB64 != null && siegelB64.isNotEmpty) {
      try {
        siegelBytes = base64Decode(siegelB64);
      } catch (_) {}
    }
    Uint8List? sigBytes;
    if (sigB64 != null && sigB64.isNotEmpty) {
      try {
        sigBytes = base64Decode(sigB64);
      } catch (_) {}
    }
    final normenDb = ref.read(appDatabaseProvider);
    final verwendeteNormen = _auftragId == null
        ? const <NormenData>[]
        : await (normenDb.select(normenDb.normen)
              ..where((t) => t.auftragId.equals(_auftragId!))
              ..orderBy([(t) => OrderingTerm(expression: t.nummer)]))
            .get();
    final lichtbilder = <LichtbildPdfEntry>[];
    if (_isEdit) {
      final fotos = await (normenDb.select(normenDb.fotos)
            ..where((t) => t.gutachtenId.equals(widget.gutachten!.id))
            ..orderBy([
              (t) => OrderingTerm(expression: t.reihenfolge),
              (t) => OrderingTerm(expression: t.id),
            ]))
          .get();
      for (final f in fotos) {
        Uint8List? bytes;
        if (f.daten != null && f.daten!.isNotEmpty) {
          bytes = f.daten;
        } else if ((f.storageUrl ?? '').isNotEmpty) {
          try {
            final resp = await http.get(Uri.parse(f.storageUrl!));
            if (resp.statusCode == 200) bytes = resp.bodyBytes;
          } catch (_) {}
        }
        if (bytes == null || bytes.isEmpty) continue;
        // SVG → PNG rastern, weil das pdf-Paket nur Raster-Formate kennt.
        bytes = await rasterizeIfSvg(bytes);
        if (bytes == null || bytes.isEmpty) continue;
        lichtbilder.add(LichtbildPdfEntry(
          bytes: bytes,
          titel: f.titel,
          raum: f.raum,
          beschreibung: f.beschreibung,
          abschnittKey: f.gutachtenAbschnitt,
        ));
      }
    }

    // Anlagen für den PDF-Anhang aufbauen. Reihenfolge ist:
    //   1) Lichtbildanlage (alle dem Gutachten zugeordneten Fotos die
    //      NICHT inline in einem Abschnitt stehen) — sammelt sie als ein
    //      einzelnes Anlagenheft mit N Seiten.
    //   2) Dokumente aus `gutachten.anlagenJson` — jede als eigene Anlage.
    // Lichtbild-Inline-Fotos (mit `gutachtenAbschnitt`) bleiben weiter im
    // Abschnittstext und tauchen NICHT in den Anhängen auf.
    final anlagen = <AnlagePdfEntry>[];
    var anlageNr = 1;
    // Alle dem Gutachten zugeordneten Fotos kommen in die Lichtbildanlage —
    // unabhängig davon, ob sie zusätzlich inline in einem Abschnitt
    // referenziert sind. Damit ist der Anhang vollständig und der Leser
    // findet jedes erwähnte Bild auch hinten gesammelt.
    final fotoItems = lichtbilder
        .map((l) => AnlageItem(
              bytes: l.bytes,
              mimeType: 'image/png',
              caption: [
                if ((l.titel ?? '').isNotEmpty) l.titel,
                if ((l.raum ?? '').isNotEmpty) l.raum,
                if ((l.beschreibung ?? '').isNotEmpty) l.beschreibung,
              ].whereType<String>().where((s) => s.isNotEmpty).join(' — '),
            ))
        .toList();
    if (fotoItems.isNotEmpty) {
      anlagen.add(AnlagePdfEntry(
        nr: anlageNr++,
        titel: 'Lichtbilddokumentation',
        items: fotoItems,
      ));
    }
    if (_isEdit) {
      final db = ref.read(appDatabaseProvider);
      final dbGutachten = await (db.select(db.gutachten)
            ..where((t) => t.id.equals(widget.gutachten!.id)))
          .getSingleOrNull();
      // anlagenFromJson liefert bereits nach `nr` sortiert.
      final liste = anlagenFromJson(dbGutachten?.anlagenJson);
      for (final a in liste) {
        final dok = await (db.select(db.dokumente)
              ..where((t) => t.id.equals(a.dokumentId)))
            .getSingleOrNull();
        if (dok == null) continue;
        Uint8List? bytes;
        if (dok.daten != null && dok.daten!.isNotEmpty) {
          bytes = dok.daten;
        } else if ((dok.storageUrl ?? '').isNotEmpty) {
          try {
            final resp = await http.get(Uri.parse(dok.storageUrl!));
            if (resp.statusCode == 200) bytes = resp.bodyBytes;
          } catch (_) {}
        }
        // Auch ohne Bytes immer eine Anlage erzeugen — die Deckseite
        // erscheint trotzdem („Anlage N — Titel"), damit der Anwender
        // erkennt, dass die Datei zwar referenziert ist, aber der
        // tatsächliche Inhalt fehlt (z. B. Demo-Dokumente ohne PDF-
        // Daten oder offline gestellter Storage).
        final items = <AnlageItem>[];
        if (bytes != null && bytes.isNotEmpty) {
          items.add(AnlageItem(
            bytes: bytes,
            mimeType: dok.mimeType ?? 'application/octet-stream',
          ));
        }
        anlagen.add(AnlagePdfEntry(
          nr: anlageNr++,
          titel: a.titel,
          items: items,
          kategorie: a.kategorie,
          datum: a.datum ?? dok.datum,
        ));
      }
    }

    return GutachtenPdfData(
      gutachten: snapshot,
      abschnitte: aktuelleAbschnitte,
      abschnittsReihenfolge:
          gutachtenAbschnitte.map((a) => a.key).toList(),
      abschnittsLabels: {
        for (final a in gutachtenAbschnitte) a.key: a.label,
      },
      auftrag: auftrag,
      kunde: kunde,
      absender: absender,
      siegelBytes: siegelBytes,
      unterschriftBytes: sigBytes,
      siegelPosition: pos ?? 'unten_rechts',
      bestellBehoerde: beh,
      bestellNr: nr,
      bestellGueltigBis: gueltigBis,
      verwendeteNormen: verwendeteNormen,
      // Inline-Fotos (mit `abschnittKey`) bleiben für den Hauptteil
      // erhalten — die `lichtbilder`-Liste enthält ALLE gutachten-
      // zugeordneten Fotos, der PDF-Builder filtert intern auf
      // abschnittKey für Inline-Darstellung. Zusätzlich erscheinen ALLE
      // Fotos hinten als „Lichtbilddokumentation" (siehe `anlagen[0]`).
      lichtbilder: lichtbilder,
      anlagen: anlagen,
      logoPfad2: logoPfad2,
    );
  }

  /// Vorschau ohne Archivierung. Verwendet immer PDF/A — Aktenwerk legt
  /// alle Dokumente GoBD-konform im Langzeit-Archivformat ab; ein
  /// Mischbetrieb wäre nur Verwirrung. Nutzt den In-App-Preview-Dialog
  /// (statt `Printing.layoutPdf`), weil das System-Druck-Fenster im Web
  /// häufig vom Popup-Blocker verschluckt wird, wenn der Aufruf aus einem
  /// asynchronen Callback heraus erfolgt.
  Future<void> _previewPdf({bool pdfA = true}) async {
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final daten = await _baueGutachtenPdfData();
      if (!mounted) return;
      final nummer = _nummer.text.trim().isEmpty ? '' : _nummer.text.trim();
      await showPdfPreviewDialog(
        context,
        title: nummer.isEmpty ? 'Gutachten-Vorschau' : 'Gutachten $nummer',
        builder: () => buildGutachtenPdf(daten, pdfA: pdfA),
        dateiname: nummer.isEmpty
            ? 'Gutachten_Vorschau.pdf'
            : 'Gutachten_${nummer.replaceAll(RegExp(r"[^A-Za-z0-9-]"), "_")}.pdf',
        // 60 % der Bildschirmbreite — schmaler als die Standard-Vorschau,
        // weil A4 hochkant in einem riesigen Dialog überdimensioniert wirkt.
        maxWidth: MediaQuery.of(context).size.width * 0.42,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Vorschau-Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, String> _currentAbschnitte() => {
        for (final e in _sektionCtrls.entries) e.key: e.value.text,
      };

  Future<void> _save({bool silent = false}) async {
    if (!silent) setState(() => _saving = true);

    // Nummernkreis: wenn neu + leer, Nummer vorschlagen.
    if (!_isEdit && _nummer.text.trim().isEmpty) {
      String? aktenzeichen;
      if (_auftragId != null) {
        final list =
            await ref.read(auftraegeRepositoryProvider).watchAll().first;
        aktenzeichen = list
            .where((a) => a.auftrag.id == _auftragId)
            .firstOrNull
            ?.auftrag
            .aktenzeichen;
      }
      final neu = await ref.read(nummernkreisServiceProvider).nextNumber(
            NummernkreisTyp.gutachten,
            aktenzeichen: aktenzeichen,
          );
      _nummer.text = neu;
    }

    // Abschnitte zusammenführen: lokal editierte Controller-Werte gewinnen,
    // unverändert gebliebene Schlüssel behalten den DB-Wert (kann z. B. ein
    // im Popup-Editor geschriebenes Quill-Delta mit Bildern sein).
    final mergedAbschnitte = await _mergeAbschnitteMitDb();
    final companion = GutachtenCompanion(
      id: _isEdit ? Value(widget.gutachten!.id) : const Value.absent(),
      nummer:
          Value(_nummer.text.trim().isEmpty ? null : _nummer.text.trim()),
      titel: Value(_titel.text.trim().isEmpty ? null : _titel.text.trim()),
      bezeichnung: Value(_bezeichnung.text.trim().isEmpty
          ? null
          : _bezeichnung.text.trim()),
      datum: Value(_datum),
      vorlage: Value(_vorlage.isEmpty ? 'frei' : _vorlage),
      status: Value(_status),
      auftragId: Value(_auftragId),
      ortsterminAm: Value(_ortstermin),
      abgabeAm: Value(_abgabe),
      abschnitteJson: Value(abschnitteToJson(mergedAbschnitte)),
    );
    try {
      await ref.read(gutachtenRepositoryProvider).upsert(companion);
      // Initialwerte nachziehen, damit nachfolgende Saves nur erneut
      // geänderte Felder als „lokal editiert" erkennen.
      _initialAbschnitte = {
        for (final e in _sektionCtrls.entries) e.key: e.value.text,
      };
      if (mounted) {
        if (!silent) setState(() => _saving = false);
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gutachten gespeichert')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        if (!silent) setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    }
  }

  /// Sucht in einem Quill-Delta-JSON nach `{insert: {image: 'data:image/svg…'}}`
  /// und ersetzt die SVG-Data-URLs durch PNG-Data-URLs (rasterisiert),
  /// damit das pdf-Paket sie einbetten kann. Andere Werte bleiben gleich.
  Future<String> _rasterSvgEmbeds(String value) async {
    final t = value.trim();
    if (t.isEmpty) return value;
    if (!(t.startsWith('[') || t.startsWith('{'))) return value;
    dynamic decoded;
    try {
      decoded = jsonDecode(t);
    } catch (_) {
      return value;
    }
    if (decoded is! List) return value;
    var changed = false;
    for (var i = 0; i < decoded.length; i++) {
      final op = decoded[i];
      if (op is! Map) continue;
      final insert = op['insert'];
      if (insert is! Map) continue;
      final src = insert['image'];
      if (src is! String) continue;
      if (!src.startsWith('data:image/svg')) continue;
      final comma = src.indexOf(',');
      if (comma < 0) continue;
      try {
        final svgBytes = base64Decode(src.substring(comma + 1));
        final png = await rasterizeIfSvg(svgBytes);
        if (png == null || png.isEmpty) continue;
        final neuUrl = 'data:image/png;base64,${base64Encode(png)}';
        insert['image'] = neuUrl;
        changed = true;
      } catch (_) {}
    }
    return changed ? jsonEncode(decoded) : value;
  }

  /// Liest aktuellen DB-Stand der Abschnitte und überschreibt nur die
  /// Schlüssel, die im Dialog tatsächlich angefasst wurden. So bleiben
  /// im Popup-Editor gespeicherte Quill-Deltas (mit Bildern) erhalten,
  /// auch wenn parallel der Dialog ein silent _save() ausführt.
  Future<Map<String, String>> _mergeAbschnitteMitDb() async {
    final lokal = _currentAbschnitte();
    if (!_isEdit) return lokal;
    final db = ref.read(appDatabaseProvider);
    final dbGutachten = await (db.select(db.gutachten)
          ..where((t) => t.id.equals(widget.gutachten!.id)))
        .getSingleOrNull();
    if (dbGutachten == null) return lokal;
    final dbAbschnitte = abschnitteFromJson(dbGutachten.abschnitteJson);
    final merged = <String, String>{...dbAbschnitte};
    for (final e in lokal.entries) {
      final initial = _initialAbschnitte[e.key] ?? '';
      // Nur überschreiben, wenn der Nutzer im Dialog tatsächlich getippt hat.
      if (e.value != initial) {
        merged[e.key] = e.value;
      }
    }
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    return StandardFormDialog(
      title: _isEdit ? 'Gutachten bearbeiten' : 'Neues Gutachten',
      icon: Icons.gavel_outlined,
      maxWidth: 1440,
      maxHeight: 1080,
      saving: _saving,
      onCancel: () =>
          Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(gutachtenRepositoryProvider)
              .delete(widget.gutachten!.id)
          : null,
      footerLeading: Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Kompakte Icon-Buttons mit Tooltip.
          IconButton(
            icon: const Icon(Icons.spellcheck),
            tooltip: 'Sprach-Check (Rechtschreibung & Grammatik)',
            onPressed: _saving ? null : _runSprachCheck,
          ),
          IconButton(
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: 'Normen hinzufügen (aus dem Katalog)',
            onPressed: _auftragId == null
                ? null
                : () => showNormenKatalogPicker(context,
                    auftragId: _auftragId!),
          ),
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'Fotos zum Gutachten zuordnen',
            onPressed: (_auftragId == null || !_isEdit)
                ? null
                : () => _fotosZuordnen(),
          ),
          PopupMenuButton<KiModus>(
            enabled: !_saving && !_kiLaeuft,
            tooltip:
                'KI-Assistent — wendet auf alle Abschnitte an (Korrektur, Umformulieren …)',
            position: PopupMenuPosition.under,
            onSelected: _kiAnwendenAlle,
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
              width: 40,
              height: 40,
              child: Center(
                child: _kiLaeuft
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome,
                        color: Colors.amber),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 24, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.remove_red_eye_outlined, size: 16),
            label: const Text('Vorschau'),
            onPressed: _saving ? null : () => _previewPdf(),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.archive_outlined, size: 16),
            label: const Text('Drucken & in Akte ablegen'),
            onPressed: _saving ? null : _druckenUndArchivieren,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildMeta(),
              const SizedBox(height: 16),
              _buildNormenChips(context),
              _buildFotosChips(context),
              _buildInfobox(context),
              if (_sprachTreffer != null && _sprachTreffer!.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildSprachReport(),
              ],
              const SizedBox(height: 24),
              _buildSektionsGruppe(
                'Basis',
                gutachtenAbschnitte
                    .where((a) => a.gruppe == 'basis')
                    .toList(),
              ),
              const SizedBox(height: 28),
              _buildSektionsGruppe(
                'Sachverhalt — Feststellungen, Bewertung, Maßnahmen, Verantwortlichkeit',
                gutachtenAbschnitte
                    .where((a) => a.gruppe == 'sachverhalt')
                    .toList(),
              ),
              const SizedBox(height: 28),
              _buildSektionsGruppe(
                'Abschluss',
                gutachtenAbschnitte
                    .where((a) => a.gruppe == 'abschluss')
                    .toList(),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMeta() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row3(
          a: LabeledField(
            'Gutachten-Nr. *',
            TextFormField(
              controller: _nummer,
              decoration: const InputDecoration(
                hintText: 'z. B. AZ-2026-014-G1',
              ),
            ),
          ),
          b: DateField(
            label: 'Datum *',
            value: _datum,
            onChanged: (v) => setState(() => _datum = v ?? DateTime.now()),
          ),
          c: LabeledField(
            'Status',
            DropdownButtonFormField<String>(
              initialValue: _status,
              isDense: true,
              items: [
                for (final s in _statusValues)
                  DropdownMenuItem(value: s, child: Text(_statusLabels[s]!)),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'entwurf'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row2(
          flex: const (2, 1),
          left: LabeledField(
            'Bezeichnung / Titel',
            TextFormField(
              controller: _bezeichnung,
              decoration: const InputDecoration(
                hintText:
                    'z. B. Gutachten zu Feuchtigkeitsschäden im Kellergeschoss',
              ),
            ),
          ),
          right: LabeledField(
            'Vorlage anwenden',
            DropdownButtonFormField<String>(
              initialValue: _vorlage,
              isDense: true,
              items: [
                for (final e in _vorlagenLabels.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) async {
                if (v == null || v.isEmpty) {
                  setState(() => _vorlage = '');
                  return;
                }
                await _anwendenVorlage(v);
                if (mounted) setState(() => _vorlage = '');
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row3(
          a: AuftragPickerField(
            auftragId: _auftragId,
            onChanged: (id) => setState(() => _auftragId = id),
          ),
          b: DateField(
            label: 'Ortstermin',
            value: _ortstermin,
            onChanged: (v) => setState(() => _ortstermin = v),
          ),
          c: DateField(
            label: 'Abgabe',
            value: _abgabe,
            onChanged: (v) => setState(() => _abgabe = v),
          ),
        ),
      ],
    );
  }

  /// Zeigt die dieser Akte bereits zugeordneten Normen als Chips.
  /// Der „Normen hinzufügen"-Button im Footer öffnet den bestehenden
  /// Katalog-Picker, der die Auswahl als akten-spezifische Normen-
  /// Kopien speichert — hier stream-en wir alle Normen der aktuellen
  /// Akte live ein.
  Widget _buildNormenChips(BuildContext context) {
    if (_auftragId == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<List<NormenData>>(
      stream: _aktenNormenStream(),
      builder: (ctx, snap) {
        final list = snap.data ?? const <NormenData>[];
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'Noch keine Normen zugeordnet. Über „Normen hinzufügen" '
              'unten im Footer Einträge aus dem Katalog auswählen — '
              'diese erscheinen dann auch als Quellenliste im PDF.',
              style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Verwendete Normen (${list.length}) — werden als '
                'Quellen ins PDF übernommen:',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final n in list)
                    Tooltip(
                      message: n.titel ?? '',
                      child: Chip(
                        avatar: Icon(Icons.menu_book,
                            size: 14,
                            color: scheme.onSecondaryContainer),
                        backgroundColor: scheme.secondaryContainer,
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          n.ausgabe != null && n.ausgabe!.isNotEmpty
                              ? '${n.nummer} (${n.ausgabe})'
                              : n.nummer,
                          style: const TextStyle(fontSize: 11),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () async {
                          await (ref
                              .read(appDatabaseProvider)
                              .delete(ref.read(appDatabaseProvider).normen)
                            ..where((t) => t.id.equals(n.id)))
                              .go();
                        },
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Stream<List<NormenData>> _aktenNormenStream() {
    final db = ref.read(appDatabaseProvider);
    return (db.select(db.normen)
          ..where((t) => t.auftragId.equals(_auftragId!))
          ..orderBy([
            (t) => OrderingTerm(expression: t.nummer),
          ]))
        .watch();
  }

  /// Öffnet einen Picker mit allen Fotos der aktuellen Akte und
  /// ordnet die gewählten dem aktuellen Gutachten zu (setzt deren
  /// `gutachtenId`). Im Gutachten-Editor erscheinen die Fotos dann als
  /// Chip-Leiste; im PDF als Lichtbild-Anlage am Ende.
  Future<void> _fotosZuordnen() async {
    if (widget.gutachten == null || _auftragId == null) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _FotosFuerGutachtenPicker(
        gutachtenId: widget.gutachten!.id,
        auftragId: _auftragId!,
      ),
    );
  }

  Stream<List<Foto>> _gutachtenFotosStream() {
    if (widget.gutachten == null) return const Stream.empty();
    final db = ref.read(appDatabaseProvider);
    return (db.select(db.fotos)
          ..where((t) => t.gutachtenId.equals(widget.gutachten!.id))
          ..orderBy([
            (t) => OrderingTerm(expression: t.reihenfolge),
            (t) => OrderingTerm(expression: t.id),
          ]))
        .watch();
  }

  /// Zeigt die dem Gutachten zugeordneten Fotos als Thumbnail-Chip-
  /// Leiste. Pro Foto gibt es ein Popup zum Setzen des Gutachten-
  /// Abschnitts (Inline-Platzierung) oder zum Entfernen der
  /// Zuordnung. Fotos ohne Abschnitt landen in der Lichtbildanlage.
  Widget _buildFotosChips(BuildContext context) {
    if (!_isEdit || widget.gutachten == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<List<Foto>>(
      stream: _gutachtenFotosStream(),
      builder: (ctx, snap) {
        final fotos = snap.data ?? const <Foto>[];
        if (fotos.isEmpty) return const SizedBox.shrink();
        final inlineKeys = {
          for (final f in fotos)
            if ((f.gutachtenAbschnitt ?? '').isNotEmpty) f.gutachtenAbschnitt!
        };
        final anlageAnzahl = fotos
            .where((f) => (f.gutachtenAbschnitt ?? '').isEmpty)
            .length;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fotos (${fotos.length}) — ${inlineKeys.length} inline '
                'in Abschnitten · $anlageAnzahl in Lichtbildanlage. '
                'Klick auf Foto → Abschnitt zuordnen.',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: fotos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final f = fotos[i];
                    final url = f.storageUrl;
                    final abschnittKey = f.gutachtenAbschnitt;
                    final abschnitt = abschnittKey == null
                        ? null
                        : gutachtenAbschnitte
                            .where((a) => a.key == abschnittKey)
                            .firstOrNull;
                    final badgeText = abschnitt == null
                        ? 'Anlage'
                        : abschnitt.nummer < 0
                            ? abschnitt.label
                            : '§ ${abschnitt.nummer}';
                    return InkWell(
                      onTap: () => _waehleAbschnittFuerFoto(f),
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 100,
                            height: 78,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: abschnitt != null
                                      ? scheme.primary
                                      : scheme.outlineVariant,
                                  width: abschnitt != null ? 2 : 1),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: url == null || url.isEmpty
                                  ? Center(
                                      child: Icon(Icons.image_outlined,
                                          color: scheme.onSurfaceVariant))
                                  : Image.network(url,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Center(
                                          child: Icon(Icons.broken_image,
                                              color: scheme.error))),
                            ),
                          ),
                          Positioned(
                            top: -4,
                            right: -4,
                            child: IconButton(
                              iconSize: 16,
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Zuordnung entfernen',
                              icon: CircleAvatar(
                                radius: 10,
                                backgroundColor: scheme.surface,
                                child: Icon(Icons.close,
                                    size: 12, color: scheme.onSurface),
                              ),
                              onPressed: () async {
                                final db = ref.read(appDatabaseProvider);
                                await (db.update(db.fotos)
                                      ..where((t) => t.id.equals(f.id)))
                                    .write(const FotosCompanion(
                                        gutachtenId: Value(null),
                                        gutachtenAbschnitt: Value(null)));
                              },
                            ),
                          ),
                          Positioned(
                            bottom: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('Bild ${i + 1}',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: abschnitt != null
                                    ? scheme.primary
                                    : Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(badgeText,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Dialog: Foto einem Gutachten-Abschnitt zuordnen (oder „— als
  /// allgemeine Anlage —", d. h. Abschnitt = null).
  Future<void> _waehleAbschnittFuerFoto(Foto foto) async {
    final gewaehlt = await showDialog<_AbschnittWahl>(
      context: context,
      useRootNavigator: true,
      builder: (_) => SimpleDialog(
        title: const Text('Foto einem Abschnitt zuordnen'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context, rootNavigator: true)
                .pop(const _AbschnittWahl(key: null)),
            child: const Row(
              children: [
                Icon(Icons.collections_outlined, size: 18),
                SizedBox(width: 10),
                Text('— Lichtbildanlage am Ende —'),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final a in gutachtenAbschnitte)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context, rootNavigator: true)
                  .pop(_AbschnittWahl(key: a.key)),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      a.nummer < 0 ? '·' : '${a.nummer}.',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(child: Text(a.label)),
                  if (foto.gutachtenAbschnitt == a.key)
                    const Icon(Icons.check, size: 16),
                ],
              ),
            ),
        ],
      ),
    );
    if (gewaehlt == null) return;
    final db = ref.read(appDatabaseProvider);
    await (db.update(db.fotos)..where((t) => t.id.equals(foto.id))).write(
      FotosCompanion(gutachtenAbschnitt: Value(gewaehlt.key)),
    );
  }

  Widget _buildInfobox(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AwTokens.blueSoft,
        border: Border.all(color: AwTokens.line),
        borderRadius: BorderRadius.circular(AwTokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AwTokens.blue),
          const SizedBox(width: 8),
          const Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Gliederung nach Zöller (Handbuch für Bausachverständige): ',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  TextSpan(
                    text:
                        'Auftrag → Grundlage → Situation → Beteiligte → Sachverhalte '
                        '(Feststellungen/Bewertung/Maßnahmen/Verantwortlichkeit) → '
                        'Beantwortung der Beweisfragen → Anlagen.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            icon: const Icon(Icons.search, size: 14),
            label: const Text('Sprach-Check'),
            onPressed: _runSprachCheck,
          ),
        ],
      ),
    );
  }

  Widget _buildSprachReport() {
    final treffer = _sprachTreffer!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AwTokens.amberSoft,
        border: Border.all(color: AwTokens.line),
        borderRadius: BorderRadius.circular(AwTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_outlined,
                  size: 18, color: AwTokens.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sprach-Check: ${treffer.length} Floskel(n) oder unpräzise Formulierungen gefunden',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AwTokens.amber),
                ),
              ),
              IconButton(
                tooltip: 'Schließen',
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => setState(() => _sprachTreffer = null),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final t in treffer)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ',
                      style: TextStyle(color: AwTokens.amber)),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${t.abschnittLabel}: ',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                          TextSpan(
                            text: '"${t.fundstelle}" — ',
                            style: const TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: AwTokens.amber),
                          ),
                          TextSpan(
                            text: t.hinweis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSektionsGruppe(String titel, List<GutachtenAbschnitt> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AwTokens.line)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              titel.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.08 * 10.5,
                color: AppTheme.slate500,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final a in items) ...[
          _buildSektion(a),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildSektion(GutachtenAbschnitt a) {
    final labelText =
        a.nummer < 0 ? a.label : '${a.nummer}. ${a.label}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                labelText,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.article_outlined, size: 14),
              label: const Text('Baustein'),
              onPressed: () => _pickTextbaustein(a),
            ),
            TextButton.icon(
              icon: const Icon(Icons.bookmark_outline, size: 14),
              label: const Text('Recherche'),
              onPressed: () => _pickRecherche(a),
            ),
            // LV-Positionen nur in Sektion 10 (Kostenschätzung) sinnvoll —
            // dort listen die meisten Gutachter ihre Mängelbeseitigungs-
            // Aufwände auf.
            if (a.key == 's_kosten')
              TextButton.icon(
                icon: const Icon(Icons.list_alt_outlined, size: 14),
                label: const Text('LV-Positionen'),
                onPressed: () => _pickLvPositionen(a),
              ),
            // Beteiligte nur in Sektion 5 (Angaben von Beteiligten) — dort
            // dokumentiert der SV, wer beim Ortstermin was gesagt hat.
            if (a.key == 's_beteiligte_aussagen')
              TextButton.icon(
                icon: const Icon(Icons.groups_outlined, size: 14),
                label: const Text('Beteiligte'),
                onPressed: () => _pickBeteiligte(a),
              ),
            if (a.key == 's_anlagen')
              TextButton.icon(
                icon: const Icon(Icons.attach_file, size: 14),
                label: const Text('Fotos + Dokumente'),
                onPressed: () => _pickAnlagenAusAkte(a),
              ),
            if (a.key == 's_normenverzeichnis')
              TextButton.icon(
                icon: const Icon(Icons.menu_book_outlined, size: 14),
                label: const Text('Aus Normen der Akte'),
                onPressed: () => _normenAusAkteEinfuegen(a),
              ),
            IconButton(
              icon: const Icon(Icons.open_in_full, size: 16),
              tooltip:
                  'Im Vollbild-Editor öffnen (Bausteine, Fotos, Normen, Anlagen einfügen)',
              onPressed: () => _vergroessern(a),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_richDeltas.containsKey(a.key))
          _RichSektionView(
            deltaJson: _richDeltas[a.key]!,
            onEdit: () => _vergroessern(a),
          )
        else
          TextFormField(
            controller: _sektionCtrls[a.key],
            minLines: a.rows,
            maxLines: a.rows + 4,
            decoration: InputDecoration(
              hintText: a.placeholder,
              alignLabelWithHint: true,
            ),
            onChanged: (v) => _abschnitte[a.key] = v,
          ),
      ],
    );
  }
}

/// Read-Only-Quill-View für einen Abschnitt, der Rich-Content enthält
/// (Bild-Embeds oder Formatierungen). Direkte Bearbeitung ist hier nicht
/// möglich — der Anwender wird via Klick in den Vollbild-Editor geleitet.
class _RichSektionView extends StatefulWidget {
  const _RichSektionView({required this.deltaJson, required this.onEdit});
  final String deltaJson;
  final VoidCallback onEdit;

  @override
  State<_RichSektionView> createState() => _RichSektionViewState();
}

class _RichSektionViewState extends State<_RichSektionView> {
  late quill.QuillController _ctrl;
  late ScrollController _scroll;
  late FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = _build(widget.deltaJson);
    _scroll = ScrollController();
    _focus = FocusNode(canRequestFocus: false);
  }

  @override
  void didUpdateWidget(covariant _RichSektionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deltaJson != widget.deltaJson) {
      _ctrl.dispose();
      _ctrl = _build(widget.deltaJson);
    }
  }

  quill.QuillController _build(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return quill.QuillController(
          document: quill.Document.fromJson(decoded),
          selection: const TextSelection.collapsed(offset: 0),
          readOnly: true,
        );
      }
    } catch (_) {}
    return quill.QuillController.basic();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onEdit,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 320, minHeight: 80),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Stack(
          children: [
            quill.QuillEditor(
              controller: _ctrl,
              focusNode: _focus,
              scrollController: _scroll,
              config: const quill.QuillEditorConfig(
                padding: EdgeInsets.zero,
                showCursor: false,
                embedBuilders: kAktenwerkEmbedBuilders,
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: TextButton.icon(
                icon: const Icon(Icons.open_in_full, size: 14),
                label: const Text('Im Editor öffnen'),
                onPressed: widget.onEdit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------- Textbaustein-Picker ----------------

class _TextbausteinPickerDialog extends ConsumerStatefulWidget {
  const _TextbausteinPickerDialog({this.kategorie});
  final String? kategorie;
  @override
  ConsumerState<_TextbausteinPickerDialog> createState() =>
      _TextbausteinPickerDialogState();
}

class _TextbausteinPickerDialogState
    extends ConsumerState<_TextbausteinPickerDialog> {
  String _query = '';
  bool _nurKategorie = true;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(textbausteineListProvider);
    return Dialog(
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.article_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Textbaustein einfügen',
                            style:
                                Theme.of(context).textTheme.titleMedium),
                        if (widget.kategorie != null)
                          Text(
                            'Kategorie: ${widget.kategorie}',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.slate500),
                          ),
                      ],
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 20),
                        hintText: 'Titel, Kategorie, Inhalt …',
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  if (widget.kategorie != null) ...[
                    const SizedBox(width: 10),
                    Row(
                      children: [
                        Checkbox(
                          value: _nurKategorie,
                          onChanged: (v) =>
                              setState(() => _nurKategorie = v ?? false),
                        ),
                        const Text('nur Kategorie',
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ],
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
                  final kat = widget.kategorie?.toLowerCase();
                  final filtered = items.where((b) {
                    if (_nurKategorie &&
                        kat != null &&
                        (b.kategorie ?? '').toLowerCase() != kat &&
                        (b.sachgebiet ?? '').toLowerCase() != kat) {
                      return false;
                    }
                    if (q.isEmpty) return true;
                    return b.titel.toLowerCase().contains(q) ||
                        (b.kategorie ?? '').toLowerCase().contains(q) ||
                        plainTextFromDeltaJson(b.inhalt)
                            .toLowerCase()
                            .contains(q);
                  }).toList();
                  if (filtered.isEmpty) {
                    return const Center(child: Text('Keine Treffer.'));
                  }
                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final b = filtered[i];
                      final vorschau = plainTextFromDeltaJson(b.inhalt)
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

/// Review-Dialog für die multi-Abschnitt-KI-Transformation. Zeigt jeden
/// veränderten Abschnitt mit Label + Original/Vorschlag nebeneinander.
class _GutachtenKiReviewDialog extends StatelessWidget {
  const _GutachtenKiReviewDialog({
    required this.modus,
    required this.geaendert,
  });
  final KiModus modus;

  /// Key → (original, korrigiert). Reihenfolge nach Abschnitts-Definition.
  final Map<String, (String, String)> geaendert;

  String _abschnittLabel(String key) {
    final match =
        gutachtenAbschnitte.where((a) => a.key == key).firstOrNull;
    return match?.label ?? key;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reihenfolge = gutachtenAbschnitte
        .where((a) => geaendert.containsKey(a.key))
        .toList();
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.auto_fix_high, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'KI-Vorschlag: ${modus.label} · '
                      '${geaendert.length} Abschnitt${geaendert.length == 1 ? '' : 'e'}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context,
                            rootNavigator: true)
                        .pop(false),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: reihenfolge.length,
                separatorBuilder: (_, _) => const SizedBox(height: 16),
                itemBuilder: (_, i) {
                  final key = reihenfolge[i].key;
                  final (orig, neu) = geaendert[key]!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _abschnittLabel(key),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _GutachtenTextBox(
                                label: 'Original',
                                text: orig,
                                farbe: scheme.surfaceContainerHighest,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _GutachtenTextBox(
                                label: modus.kurzLabel,
                                text: neu,
                                farbe: scheme.primaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text(
                    'Alle Änderungen werden beim Übernehmen in die jeweiligen '
                    'Abschnittsfelder übertragen.',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context,
                            rootNavigator: true)
                        .pop(false),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Alle übernehmen'),
                    onPressed: () => Navigator.of(context,
                            rootNavigator: true)
                        .pop(true),
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

class _GutachtenTextBox extends StatelessWidget {
  const _GutachtenTextBox({
    required this.label,
    required this.text,
    required this.farbe,
  });
  final String label;
  final String text;
  final Color farbe;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: farbe,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: SelectableText(
            text,
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
        ),
      ],
    );
  }
}

/// ---------------- Recherche-Ablage-Picker ----------------

class _RechercheAblagePicker extends ConsumerStatefulWidget {
  const _RechercheAblagePicker({this.auftragId});
  final int? auftragId;
  @override
  ConsumerState<_RechercheAblagePicker> createState() =>
      _RechercheAblagePickerState();
}

class _RechercheAblagePickerState
    extends ConsumerState<_RechercheAblagePicker> {
  String _query = '';
  bool _nurAktuelleAkte = true;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(rechercheAblageProvider);
    return Dialog(
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.bookmark_outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Aus Recherche-Ablage einfügen',
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
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 20),
                        hintText: 'Suche Titel oder Inhalt',
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (widget.auftragId != null)
                    Row(
                      children: [
                        Checkbox(
                          value: _nurAktuelleAkte,
                          onChanged: (v) => setState(
                              () => _nurAktuelleAkte = v ?? true),
                        ),
                        const Text('nur diese Akte',
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Fehler: $e')),
                data: (alle) {
                  final q = _query.trim().toLowerCase();
                  final gefiltert = alle.where((n) {
                    if (widget.auftragId != null && _nurAktuelleAkte) {
                      // Nur Treffer der aktuellen Akte + globale Notizen
                      if (n.auftragId != null &&
                          n.auftragId != widget.auftragId) {
                        return false;
                      }
                    }
                    if (q.isEmpty) return true;
                    return n.titel.toLowerCase().contains(q) ||
                        n.inhalt.toLowerCase().contains(q);
                  }).toList();
                  if (gefiltert.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Keine Notizen in der Ablage.\n'
                          'Speichere Antworten aus dem Normen-KI-Chat '
                          'über „Zu Recherche-Ablage hinzufügen".',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: gefiltert.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final n = gefiltert[i];
                      final vorschau = n.inhalt
                          .replaceAll(RegExp(r'\s+'), ' ')
                          .trim();
                      return ListTile(
                        dense: true,
                        leading: n.verwendet
                            ? const Icon(Icons.check_circle,
                                size: 16, color: Colors.green)
                            : const Icon(Icons.bookmark_outline, size: 16),
                        title: Text(n.titel,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          vorschau,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: n.quelle == null
                            ? null
                            : Chip(
                                label: Text(n.quelle!,
                                    style: const TextStyle(fontSize: 10)),
                                visualDensity: VisualDensity.compact,
                              ),
                        onTap: () => Navigator.of(context,
                                rootNavigator: true)
                            .pop(n),
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

/// Ergebnis der Abschnitts-Wahl für ein Foto. `key == null` → allgemeine
/// Lichtbildanlage am Ende.
class _AbschnittWahl {
  const _AbschnittWahl({required this.key});
  final String? key;
}

/// ---------------- Fotos-Picker fürs Gutachten ----------------

class _FotosFuerGutachtenPicker extends ConsumerStatefulWidget {
  const _FotosFuerGutachtenPicker({
    required this.gutachtenId,
    required this.auftragId,
  });
  final int gutachtenId;
  final int auftragId;
  @override
  ConsumerState<_FotosFuerGutachtenPicker> createState() =>
      _FotosFuerGutachtenPickerState();
}

class _FotosFuerGutachtenPickerState
    extends ConsumerState<_FotosFuerGutachtenPicker> {
  final Set<int> _toggled = {};

  Stream<List<Foto>> _akteFotos() {
    final db = ref.read(appDatabaseProvider);
    return (db.select(db.fotos)
          ..where((t) => t.auftragId.equals(widget.auftragId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.reihenfolge),
            (t) => OrderingTerm(expression: t.aufnahmeAm),
          ]))
        .watch();
  }

  Future<void> _speichern(List<Foto> fotos) async {
    final db = ref.read(appDatabaseProvider);
    await db.transaction(() async {
      for (final f in fotos) {
        final aktuell = f.gutachtenId == widget.gutachtenId;
        final toggled = _toggled.contains(f.id);
        // Der Toggle gilt gegenüber dem Ausgangszustand — wenn aktuell
        // bereits zugeordnet und toggled: entfernen; wenn nicht und
        // toggled: zuordnen. Rows, die gar nicht toggled sind, bleiben
        // unberührt.
        if (!toggled) continue;
        final neueZuordnung = !aktuell;
        await (db.update(db.fotos)..where((t) => t.id.equals(f.id))).write(
          FotosCompanion(
            gutachtenId:
                Value(neueZuordnung ? widget.gutachtenId : null),
          ),
        );
      }
    });
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: 900, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.photo_library_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Fotos dem Gutachten zuordnen',
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
              child: StreamBuilder<List<Foto>>(
                stream: _akteFotos(),
                builder: (ctx, snap) {
                  final fotos = snap.data ?? const <Foto>[];
                  if (fotos.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Keine Fotos in dieser Akte.\n'
                          'Nutze das Modul „Fotos" oder den Ortstermin-Modus, '
                          'um Lichtbilder hochzuladen.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 1,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: fotos.length,
                    itemBuilder: (_, i) {
                      final f = fotos[i];
                      final aktuellZugeordnet =
                          f.gutachtenId == widget.gutachtenId;
                      final toggled = _toggled.contains(f.id);
                      // effektiver Zustand = XOR
                      final effektiv = aktuellZugeordnet != toggled;
                      return InkWell(
                        onTap: () => setState(() {
                          if (toggled) {
                            _toggled.remove(f.id);
                          } else {
                            _toggled.add(f.id);
                          }
                        }),
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: effektiv
                                      ? scheme.primary
                                      : scheme.outlineVariant,
                                  width: effektiv ? 3 : 1,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: _FotoThumb(foto: f),
                              ),
                            ),
                            if (effektiv)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: CircleAvatar(
                                  radius: 12,
                                  backgroundColor: scheme.primary,
                                  child: const Icon(Icons.check,
                                      color: Colors.white, size: 14),
                                ),
                              ),
                            if ((f.titel ?? '').isNotEmpty)
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  color: Colors.black54,
                                  child: Text(
                                    f.titel!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.white),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text('${_toggled.length} Änderungen',
                      style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant)),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Übernehmen'),
                    onPressed: _toggled.isEmpty
                        ? null
                        : () async {
                            final all = await _akteFotos().first;
                            await _speichern(all);
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

/// Thumbnail für die Foto-Picker im Gutachten-Dialog. Bevorzugt
/// Storage-URL (Produktivdaten), fällt auf in der DB gespeicherte Bytes
/// zurück (Demo-Mandant + Web-only-Uploads).

/// Picker für die Anlagen-Auswahl: zeigt alle Fotos + Dokumente der Akte
/// in zwei Spalten, der Anwender pickt, was als Anlage ans Gutachten
/// gehängt werden soll. Beim Bestätigen werden DB-Beziehungen gepflegt
/// und die textliche Anlagenliste an den Aufrufer zurückgegeben.
class _AnlagenAusAktePicker extends ConsumerStatefulWidget {
  const _AnlagenAusAktePicker({
    required this.auftragId,
    required this.gutachtenId,
  });
  final int auftragId;
  final int gutachtenId;
  @override
  ConsumerState<_AnlagenAusAktePicker> createState() =>
      _AnlagenAusAktePickerState();
}

class _AnlagenAusAktePickerState
    extends ConsumerState<_AnlagenAusAktePicker> {
  Set<int> _fotoIds = {};
  Set<int> _dokIds = {};
  List<Foto> _fotos = const [];
  List<DokumenteData> _dokumente = const [];
  bool _laden = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _initLoad();
  }

  Future<void> _initLoad() async {
    final db = ref.read(appDatabaseProvider);
    final fotos = await (db.select(db.fotos)
          ..where((t) => t.auftragId.equals(widget.auftragId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.reihenfolge),
            (t) => OrderingTerm(expression: t.id),
          ]))
        .get();
    final dokumente = await (db.select(db.dokumente)
          ..where((t) => t.auftragId.equals(widget.auftragId))
          ..orderBy([(t) =>
              OrderingTerm(expression: t.datum, mode: OrderingMode.desc)]))
        .get();
    final gutachten = await (db.select(db.gutachten)
          ..where((t) => t.id.equals(widget.gutachtenId)))
        .getSingleOrNull();
    if (!mounted) return;
    setState(() {
      _fotos = fotos;
      _dokumente = dokumente;
      _fotoIds = fotos
          .where((f) => f.gutachtenId == widget.gutachtenId)
          .map((f) => f.id)
          .toSet();
      _dokIds = anlagenFromJson(gutachten?.anlagenJson)
          .map((a) => a.dokumentId)
          .toSet();
      _laden = false;
    });
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    final db = ref.read(appDatabaseProvider);
    // 1) Foto-Zuordnung syncen
    for (final f in _fotos) {
      final shouldBe = _fotoIds.contains(f.id);
      final isLinked = f.gutachtenId == widget.gutachtenId;
      if (shouldBe && !isLinked) {
        await (db.update(db.fotos)..where((t) => t.id.equals(f.id))).write(
            FotosCompanion(gutachtenId: Value(widget.gutachtenId)));
      } else if (!shouldBe && isLinked) {
        await (db.update(db.fotos)..where((t) => t.id.equals(f.id))).write(
            const FotosCompanion(gutachtenId: Value(null)));
      }
    }
    // 2) Anlagen-Liste am Gutachten neu setzen, Reihenfolge =
    //    Reihenfolge der Auswahl in der Picker-Liste.
    final neuListe = <GutachtenAnlage>[];
    var nr = 1;
    for (final d in _dokumente) {
      if (!_dokIds.contains(d.id)) continue;
      neuListe.add(GutachtenAnlage(
        nr: nr++,
        dokumentId: d.id,
        titel: d.titel ?? 'Dokument',
        kategorie: d.kategorie,
        datum: d.datum,
      ));
    }
    await (db.update(db.gutachten)
          ..where((t) => t.id.equals(widget.gutachtenId)))
        .write(GutachtenCompanion(
      anlagenJson: Value(anlagenToJson(neuListe)),
      updatedAt: Value(DateTime.now()),
    ));
    // 3) Section-Text aufbauen
    final zeilen = <String>[];
    var anlageNr = 1;
    if (_fotoIds.isNotEmpty) {
      zeilen.add(
          'Anlage ${anlageNr++} – Lichtbilddokumentation (${_fotoIds.length} Fotos)');
    }
    for (final a in neuListe) {
      zeilen.add(
          'Anlage ${anlageNr++} – ${a.titel}${(a.kategorie ?? '').isEmpty ? '' : ' (${a.kategorie})'}');
    }
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop(zeilen.join('\n'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.attach_file),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Fotos und Dokumente als Anlagen wählen',
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
              child: _laden
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _AnlagenSpalte(
                            titel: 'Fotos der Akte',
                            leer: 'Keine Fotos.',
                            children: [
                              for (final f in _fotos)
                                CheckboxListTile(
                                  dense: true,
                                  value: _fotoIds.contains(f.id),
                                  onChanged: (v) => setState(() {
                                    if (v == true) {
                                      _fotoIds.add(f.id);
                                    } else {
                                      _fotoIds.remove(f.id);
                                    }
                                  }),
                                  secondary: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: _FotoThumb(foto: f),
                                  ),
                                  title: Text(
                                      f.titel ?? 'Foto ${f.reihenfolge}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: (f.beschreibung ?? '').isEmpty
                                      ? null
                                      : Text(f.beschreibung!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11)),
                                ),
                            ],
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: _AnlagenSpalte(
                            titel: 'Dokumente der Akte',
                            leer: 'Keine Dokumente.',
                            children: [
                              for (final d in _dokumente)
                                CheckboxListTile(
                                  dense: true,
                                  value: _dokIds.contains(d.id),
                                  onChanged: (v) => setState(() {
                                    if (v == true) {
                                      _dokIds.add(d.id);
                                    } else {
                                      _dokIds.remove(d.id);
                                    }
                                  }),
                                  secondary: const Icon(
                                      Icons.description_outlined),
                                  title: Text(d.titel ?? 'Dokument',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                      '${DateFormat('dd.MM.yyyy', 'de').format(d.datum)} · ${d.kategorie ?? ''}',
                                      style: const TextStyle(fontSize: 11)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Text(
                      '${_fotoIds.length} Fotos · ${_dokIds.length} Dokumente',
                      style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context, rootNavigator: true)
                            .pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check, size: 16),
                    label: const Text('Übernehmen'),
                    onPressed: _saving ? null : _confirm,
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

class _AnlagenSpalte extends StatelessWidget {
  const _AnlagenSpalte({
    required this.titel,
    required this.leer,
    required this.children,
  });
  final String titel;
  final String leer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(titel,
              style: Theme.of(context).textTheme.titleSmall),
        ),
        const Divider(height: 1),
        Expanded(
          child: children.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(leer,
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ),
                )
              : ListView(children: children),
        ),
      ],
    );
  }
}

/// zurück (Demo-Mandant + Web-only-Uploads). SVG wird via flutter_svg
/// gerendert, sonst kommt nur ein Platzhalter-Icon.
class _FotoThumb extends StatelessWidget {
  const _FotoThumb({required this.foto});
  final Foto foto;

  bool _looksLikeSvg(Uint8List bytes) {
    if (bytes.length < 5) return false;
    final head = String.fromCharCodes(
        bytes.take(200).where((b) => b > 0 && b < 128));
    return head.contains('<svg') || head.trimLeft().startsWith('<?xml');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget placeholder() => Container(
          color: scheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const Icon(Icons.image),
        );
    Widget broken() => Container(
          color: scheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image),
        );
    final url = foto.storageUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(url, fit: BoxFit.cover,
          errorBuilder: (_, _, _) => broken());
    }
    final daten = foto.daten;
    final mime = foto.mimeType ?? '';
    if (daten != null && daten.isNotEmpty) {
      if (mime == 'image/svg+xml' || _looksLikeSvg(daten)) {
        return SvgPicture.memory(daten, fit: BoxFit.cover);
      }
      return Image.memory(daten, fit: BoxFit.cover,
          errorBuilder: (_, _, _) => broken());
    }
    return placeholder();
  }
}
