import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../features/akten/auftraege/auftraege_repository.dart';
import '../../../features/system/einstellungen/absender_service.dart';
import '../../../features/system/einstellungen/einstellungen_repository.dart';
import '../../../features/system/einstellungen/nummernkreis_service.dart';
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
      builder: (_) => Dialog.fullscreen(
        child: _GutachtenEditor(gutachten: vorhanden),
      ),
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
    {GutachtenData? gutachten}) async {
  await showDialog(
    context: context,
    useRootNavigator: true,
    builder: (_) => _GutachtenEditor(gutachten: gutachten),
  );
}

class _GutachtenEditor extends ConsumerStatefulWidget {
  const _GutachtenEditor({this.gutachten});
  final GutachtenData? gutachten;
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
    _auftragId = g?.auftragId;
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
              '✅ Sprach-Check: Keine typischen Floskeln gefunden — sehr gut!')));
    }
  }

  Future<void> _previewPdf() async {
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
    await previewGutachtenPdf(GutachtenPdfData(
      gutachten: snapshot,
      abschnitte: _currentAbschnitte(),
      abschnittsReihenfolge:
          gutachtenAbschnitte.map((a) => a.label).toList(),
      auftrag: auftrag,
      kunde: kunde,
      absender: absender,
      siegelBytes: siegelBytes,
      unterschriftBytes: sigBytes,
      siegelPosition: pos ?? 'unten_rechts',
      bestellBehoerde: beh,
      bestellNr: nr,
      bestellGueltigBis: gueltigBis,
    ));
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Icon(Icons.gavel_outlined),
            const SizedBox(width: 10),
            Text(_isEdit ? 'Gutachten bearbeiten' : 'Neues Gutachten'),
          ],
        ),
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.search, size: 16),
            label: const Text('Sprach-Check'),
            onPressed: _saving ? null : _runSprachCheck,
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            icon: const Icon(Icons.remove_red_eye_outlined, size: 16),
            label: const Text('Vorschau / Drucken'),
            onPressed: _saving ? null : _previewPdf,
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('Speichern'),
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildMeta(),
                const SizedBox(height: 16),
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

  Widget _buildInfobox(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: Color(0xFF1D4ED8)),
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
        color: const Color(0xFFFEF9C3),
        border: Border.all(color: const Color(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_outlined,
                  size: 18, color: Color(0xFF854D0E)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sprach-Check: ${treffer.length} Floskel(n) oder unpräzise Formulierungen gefunden',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFF854D0E)),
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
                      style: TextStyle(color: Color(0xFF854D0E))),
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
                                color: Color(0xFF854D0E)),
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
            border: Border(
              top: BorderSide(color: Color(0xFFE2E8F0)),
            ),
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
