import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

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
import '../../../features/akten/akte/normen_picker_dialog.dart';
import '../../../features/werkzeuge/recherche_ablage/recherche_ablage_repository.dart';
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
                        DataColumn(label: Text('Bezeichnung')),
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
                                g.gutachten.nummer ?? '—',
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
                              DataCell(SizedBox(
                                width: 340,
                                child: Text(
                                  g.gutachten.bezeichnung ??
                                      g.gutachten.titel ??
                                      '—',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
    _sektionCtrls = {
      for (final a in gutachtenAbschnitte)
        a.key: TextEditingController(text: _abschnitte[a.key] ?? ''),
    };
  }

  @override
  void dispose() {
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

    setState(() {
      for (final eintrag in geaendert.entries) {
        final ctrl = _sektionCtrls[eintrag.key];
        if (ctrl == null) continue;
        ctrl.text = eintrag.value.$2;
        _abschnitte[eintrag.key] = eintrag.value.$2;
      }
    });
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

  Future<void> _previewPdf({bool pdfA = false}) async {
    final absender = await absenderFromSettings(ref);
    AuftraegeData? auftrag;
    KundenData? kunde;
    if (_auftragId != null) {
      final list = await ref.read(auftraegeRepositoryProvider).watchAll().first;
      final match = list.where((a) => a.auftrag.id == _auftragId).firstOrNull;
      auftrag = match?.auftrag;
      kunde = match?.kunde;
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
      abschnitteJson: abschnitteToJson(_currentAbschnitte()),
      createdAt: widget.gutachten?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final repo = ref.read(einstellungenRepositoryProvider);
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
      try { siegelBytes = base64Decode(siegelB64); } catch (_) {}
    }
    Uint8List? sigBytes;
    if (sigB64 != null && sigB64.isNotEmpty) {
      try { sigBytes = base64Decode(sigB64); } catch (_) {}
    }
    // Akten-Normen als Quellenliste zum PDF.
    final normenDb = ref.read(appDatabaseProvider);
    final verwendeteNormen = _auftragId == null
        ? const <NormenData>[]
        : await (normenDb.select(normenDb.normen)
              ..where((t) => t.auftragId.equals(_auftragId!))
              ..orderBy(
                  [(t) => OrderingTerm(expression: t.nummer)]))
            .get();
    // Gutachten-Fotos → Bytes laden für Lichtbild-Anlage.
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
        lichtbilder.add(LichtbildPdfEntry(
          bytes: bytes,
          titel: f.titel,
          raum: f.raum,
          beschreibung: f.beschreibung,
          abschnittKey: f.gutachtenAbschnitt,
        ));
      }
    }
    await previewGutachtenPdf(GutachtenPdfData(
      gutachten: snapshot,
      abschnitte: _currentAbschnitte(),
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
      lichtbilder: lichtbilder,
    ), pdfA: pdfA);
  }

  Map<String, String> _currentAbschnitte() => {
        for (final e in _sektionCtrls.entries) e.key: e.value.text,
      };

  Future<void> _save() async {
    setState(() => _saving = true);

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
      abschnitteJson: Value(abschnitteToJson(_currentAbschnitte())),
    );
    try {
      await ref.read(gutachtenRepositoryProvider).upsert(companion);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gutachten gespeichert')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StandardFormDialog(
      title: _isEdit ? 'Gutachten bearbeiten' : 'Neues Gutachten',
      icon: Icons.gavel_outlined,
      maxWidth: 1200,
      maxHeight: 900,
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
        spacing: 6,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.search, size: 16),
            label: const Text('Sprach-Check'),
            onPressed: _saving ? null : _runSprachCheck,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.menu_book_outlined, size: 16),
            label: const Text('Normen hinzufügen'),
            onPressed: _auftragId == null
                ? null
                : () => showNormenKatalogPicker(context,
                    auftragId: _auftragId!),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.photo_library_outlined, size: 16),
            label: const Text('Fotos zum Gutachten'),
            onPressed: (_auftragId == null || !_isEdit)
                ? null
                : () => _fotosZuordnen(),
          ),
          PopupMenuButton<KiModus>(
            enabled: !_saving && !_kiLaeuft,
            tooltip: 'KI-Assistent — wendet auf alle Abschnitte an',
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
            child: OutlinedButton.icon(
              onPressed: null,
              icon: _kiLaeuft
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high, size: 16),
              label: Text(
                  _kiLaeuft ? 'KI arbeitet …' : 'KI-Assistent (alle)'),
              style: OutlinedButton.styleFrom(
                disabledForegroundColor:
                    Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.remove_red_eye_outlined, size: 16),
            label: const Text('Vorschau / Drucken'),
            onPressed: _saving ? null : () => _previewPdf(),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.archive_outlined, size: 16),
            label: const Text('PDF/A (Archiv)'),
            onPressed: _saving ? null : () => _previewPdf(pdfA: true),
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
          ],
        ),
        const SizedBox(height: 4),
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
                      final url = f.storageUrl;
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
                                child: url == null || url.isEmpty
                                    ? Container(
                                        color: scheme.surfaceContainerHighest,
                                        alignment: Alignment.center,
                                        child: const Icon(Icons.image),
                                      )
                                    : Image.network(url,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) =>
                                            Container(
                                              color:
                                                  scheme.surfaceContainerHighest,
                                              alignment: Alignment.center,
                                              child:
                                                  const Icon(Icons.broken_image),
                                            )),
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
