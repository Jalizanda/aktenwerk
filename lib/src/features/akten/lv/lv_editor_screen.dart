import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../shared/pdf/lv_pdf.dart';
import '../../../shared/pdf/pdf_preview_dialog.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../system/einstellungen/absender_service.dart';
import 'package:file_picker/file_picker.dart';

import '../dokumente/dokumente_repository.dart';
import '../kunden/kunden_repository.dart';
import 'gaeb_export.dart';
import 'gaeb_import.dart';
import 'lv_bieter_dialog.dart';
import 'lv_csv.dart';
import 'lv_indizierung_dialog.dart';
import 'lv_katalog_picker.dart';
import 'lv_position_dialog.dart';
import 'lv_repository.dart';

/// Editor für ein einzelnes Leistungsverzeichnis: Kopfdaten oben, Liste
/// der Positionen darunter mit Add/Edit/Delete und Druck-/Export-
/// Aktionen oben rechts.
class LvEditorScreen extends ConsumerStatefulWidget {
  const LvEditorScreen({
    super.key,
    required this.lvId,
  });
  final int lvId;

  @override
  ConsumerState<LvEditorScreen> createState() => _LvEditorScreenState();
}

class _LvEditorScreenState extends ConsumerState<LvEditorScreen> {
  static final _money = NumberFormat.currency(
      locale: 'de_DE', symbol: '€', decimalDigits: 2);
  static final _menge = NumberFormat.decimalPattern('de_DE');

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);
    return StreamBuilder<LvKopfData?>(
      stream: (db.select(db.lvKopf)
            ..where((t) => t.id.equals(widget.lvId)))
          .watchSingleOrNull(),
      builder: (ctx, snap) {
        final kopf = snap.data;
        if (kopf == null && snap.connectionState != ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('LV nicht gefunden.')),
          );
        }
        if (kopf == null) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return _LvEditorBody(kopf: kopf);
      },
    );
  }
}

class _LvEditorBody extends ConsumerStatefulWidget {
  const _LvEditorBody({required this.kopf});
  final LvKopfData kopf;

  @override
  ConsumerState<_LvEditorBody> createState() => _LvEditorBodyState();
}

class _LvEditorBodyState extends ConsumerState<_LvEditorBody> {
  late final _bezeichnung =
      TextEditingController(text: widget.kopf.bezeichnung);
  late final _untertitel =
      TextEditingController(text: widget.kopf.untertitel ?? '');
  late final _nummer =
      TextEditingController(text: widget.kopf.nummer ?? '');

  Future<void> _saveKopf() async {
    await ref.read(lvRepositoryProvider).upsertKopf(LvKopfCompanion(
          id: Value(widget.kopf.id),
          bezeichnung: Value(_bezeichnung.text.trim()),
          untertitel: Value(_untertitel.text.trim().isEmpty
              ? null
              : _untertitel.text.trim()),
          nummer: Value(_nummer.text.trim().isEmpty
              ? null
              : _nummer.text.trim()),
        ));
  }

  @override
  void dispose() {
    _bezeichnung.dispose();
    _untertitel.dispose();
    _nummer.dispose();
    super.dispose();
  }

  Future<void> _neuePosition({int? parentId}) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => LvPositionDialog(
        lvId: widget.kopf.id,
        parentId: parentId,
      ),
    );
  }

  Future<void> _ausKatalog() async {
    final eintrag = await zeigeKatalogPicker(context);
    if (eintrag == null) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => LvPositionDialog(
        lvId: widget.kopf.id,
        prefillKatalog: eintrag,
      ),
    );
    await ref.read(lvRepositoryProvider).tickKatalog(eintrag.id);
  }

  Future<LvPdfData> _baueDaten(LvPdfVariante variante) async {
    final db = ref.read(appDatabaseProvider);
    final positionen =
        await ref.read(lvRepositoryProvider).getPositionen(widget.kopf.id);
    AuftraegeData? auftrag;
    if (widget.kopf.auftragId != null) {
      auftrag = await (db.select(db.auftraege)
            ..where((t) => t.id.equals(widget.kopf.auftragId!)))
          .getSingleOrNull();
    }
    KundenData? empfaenger;
    if (auftrag?.kundeId != null) {
      empfaenger = await ref
          .read(kundenRepositoryProvider)
          .byId(auftrag!.kundeId!);
    }
    final absender = await absenderFromSettings(ref);
    return LvPdfData(
      kopf: widget.kopf,
      positionen: positionen,
      variante: variante,
      auftrag: auftrag,
      absender: absender,
      empfaenger: empfaenger,
    );
  }

  Future<void> _druckenPreisLv() async {
    final daten = await _baueDaten(LvPdfVariante.preisLv);
    if (!mounted) return;
    await showPdfPreviewDialog(
      context,
      title: 'Preis-LV: ${widget.kopf.bezeichnung}',
      builder: () => buildLvPdf(daten),
      dateiname:
          'Kostenschaetzung_${(daten.auftrag?.aktenzeichen ?? widget.kopf.bezeichnung).replaceAll(RegExp(r"[^A-Za-z0-9-]"), "_")}.pdf',
      csvBuilder: () async {
        final positionen = await ref
            .read(lvRepositoryProvider)
            .getPositionen(widget.kopf.id);
        return buildLvCsv(positionen);
      },
      csvDateiname:
          'LV_${widget.kopf.bezeichnung.replaceAll(RegExp(r"[^A-Za-z0-9-_]"), "_")}.csv',
    );
  }

  Future<void> _druckenBlanko() async {
    final daten = await _baueDaten(LvPdfVariante.blankoLv);
    if (!mounted) return;
    await showPdfPreviewDialog(
      context,
      title: 'Ausschreibung (Blanko-LV): ${widget.kopf.bezeichnung}',
      builder: () => buildLvPdf(daten),
      dateiname:
          'Ausschreibung_${(daten.auftrag?.aktenzeichen ?? widget.kopf.bezeichnung).replaceAll(RegExp(r"[^A-Za-z0-9-]"), "_")}.pdf',
      csvBuilder: () async {
        final positionen = await ref
            .read(lvRepositoryProvider)
            .getPositionen(widget.kopf.id);
        return buildLvCsv(positionen);
      },
      csvDateiname:
          'LV_${widget.kopf.bezeichnung.replaceAll(RegExp(r"[^A-Za-z0-9-_]"), "_")}.csv',
    );
  }

  Future<void> _archivieren(LvPdfVariante variante) async {
    try {
      final daten = await _baueDaten(variante);
      final bytes = await buildLvPdf(daten);
      final praefix = variante == LvPdfVariante.blankoLv
          ? 'Ausschreibung'
          : 'Kostenschaetzung';
      final dateiname =
          '${praefix}_${(daten.auftrag?.aktenzeichen ?? widget.kopf.bezeichnung).replaceAll(RegExp(r"[^A-Za-z0-9-]"), "_")}.pdf';
      if (widget.kopf.auftragId != null) {
        await ref.read(dokumenteRepositoryProvider).upsert(
              DokumenteCompanion.insert(
                titel: Value(dateiname),
                mimeType: const Value('application/pdf'),
                dateigroesse: Value(bytes.length),
                daten: Value(bytes),
                auftragId: Value(widget.kopf.auftragId!),
                kategorie: Value(variante == LvPdfVariante.blankoLv
                    ? 'Ausschreibung (Blanko-LV)'
                    : 'Kostenschätzung (LV)'),
                datum: Value(DateTime.now()),
                beschreibung: Value(widget.kopf.bezeichnung),
              ),
            );
      }
      await previewLvPdf(daten);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '$praefix als PDF in der Akte abgelegt (Tab „Dokumente").')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _bieterDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => LvBieterDialog(kopf: widget.kopf),
    );
  }

  Future<void> _csvExport() async {
    try {
      final positionen =
          await ref.read(lvRepositoryProvider).getPositionen(widget.kopf.id);
      final bytes = buildLvCsv(positionen);
      final fname =
          'LV_${widget.kopf.bezeichnung.replaceAll(RegExp(r"[^A-Za-z0-9-_]"), "_")}.csv';
      await Printing.sharePdf(bytes: bytes, filename: fname);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('CSV „$fname" zum Download bereit gestellt.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _csvImport() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowedExtensions: ['csv'],
      type: FileType.custom,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.single;
    if (f.bytes == null) return;
    final zeilen = parseLvCsv(f.bytes!);
    if (zeilen.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Keine Zeilen in der CSV gefunden.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CSV importieren?'),
        content: Text(
            '${zeilen.length} Zeilen gefunden. Werden ans Ende des LV angehängt.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Importieren')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final repo = ref.read(lvRepositoryProvider);
      var sort = await repo.nextSortIndex(widget.kopf.id, null);
      for (final z in zeilen) {
        await repo.upsertPosition(LvPositionenCompanion.insert(
          lvId: widget.kopf.id,
          sortIndex: Value(sort),
          art: Value(z.art ?? 'normal'),
          oz: Value(z.oz),
          kurztext: z.kurztext,
          langtext: Value(z.langtext),
          einheit: Value(z.einheit),
          menge: Value(z.menge),
          einzelpreis: Value(z.einzelpreis),
          din276: Value(z.din276),
          gewerk: Value(z.gewerk),
        ));
        sort += 10;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${zeilen.length} Positionen importiert.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _gaebImport() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowedExtensions: ['x81', 'x83', 'x84', 'xml'],
      type: FileType.custom,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.single;
    if (f.bytes == null) return;
    GaebImportResult? gaeb;
    try {
      gaeb = parseGaebXml(f.bytes!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Parse-Fehler: $e')));
      return;
    }
    if (gaeb.positionen.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Keine Positionen in der Datei gefunden.')));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.file_download_outlined),
                    const SizedBox(width: 10),
                    Text('GAEB-Import: ${f.name}',
                        style: Theme.of(ctx).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Erkannt: ${gaeb!.positionen.length} Positionen'
                  '${gaeb.phaseCode == null ? "" : ", Phase X${gaeb.phaseCode}"}'
                  '${gaeb.projektName == null ? "" : ', Projekt „${gaeb.projektName}"'}.\n\n'
                  'Die Positionen werden ans Ende des LV angehängt. Bestehende '
                  'Positionen bleiben unverändert.',
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Abbrechen'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Importieren'),
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
    if (ok != true) return;
    if (!mounted) return;

    try {
      final repo = ref.read(lvRepositoryProvider);
      // Top-Level-SortIndex fortlaufend ans Ende.
      var topSort = await repo.nextSortIndex(widget.kopf.id, null);
      // Map JSON-Index → neue Drift-ID, damit parent-Verweise auflösen.
      final idMap = <int, int>{};
      for (var i = 0; i < gaeb.positionen.length; i++) {
        final p = gaeb.positionen[i];
        final parentDriftId =
            p.parentIdx >= 0 ? idMap[p.parentIdx] : null;
        final sort = parentDriftId == null
            ? topSort
            : await repo.nextSortIndex(widget.kopf.id, parentDriftId);
        if (parentDriftId == null) topSort += 10;
        final id = await repo.upsertPosition(LvPositionenCompanion.insert(
          lvId: widget.kopf.id,
          parentId: Value(parentDriftId),
          sortIndex: Value(sort),
          art: Value(p.art),
          oz: Value(p.oz),
          kurztext: p.kurztext,
          langtext: Value(p.langtext),
          einheit: Value(p.einheit),
          menge: Value(p.menge),
          einzelpreis: Value(p.einzelpreis),
          gaebUuid: Value(p.gaebUuid),
        ));
        idMap[i] = id;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${gaeb.positionen.length} Positionen importiert.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Import-Fehler: $e')));
    }
  }

  Future<void> _gaebExport(GaebPhase phase) async {
    try {
      final positionen =
          await ref.read(lvRepositoryProvider).getPositionen(widget.kopf.id);
      final bytes = buildGaebX83(
        kopf: widget.kopf,
        positionen: positionen,
        phase: phase,
      );
      final phaseSuffix = switch (phase) {
        GaebPhase.d81 => 'x81',
        GaebPhase.d83 => 'x83',
        GaebPhase.d84 => 'x84',
      };
      final fname =
          '${widget.kopf.bezeichnung.replaceAll(RegExp(r"[^A-Za-z0-9-_]"), "_")}.$phaseSuffix';
      await Printing.sharePdf(bytes: bytes, filename: fname);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'GAEB-Datei „$fname" zum Download bereit gestellt.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final positionenAsync =
        ref.watch(lvPositionenProvider(widget.kopf.id));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (widget.kopf.auftragId != null) {
              context.go('/akte/${widget.kopf.auftragId}');
            } else {
              context.go('/lv');
            }
          },
        ),
        title: Text('LV: ${widget.kopf.bezeichnung}'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Druck / Export',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) async {
              switch (v) {
                case 'preis_vorschau':
                  await _druckenPreisLv();
                case 'preis_archiv':
                  await _archivieren(LvPdfVariante.preisLv);
                case 'blanko_vorschau':
                  await _druckenBlanko();
                case 'blanko_archiv':
                  await _archivieren(LvPdfVariante.blankoLv);
                case 'gaeb_d83':
                  await _gaebExport(GaebPhase.d83);
                case 'gaeb_d81':
                  await _gaebExport(GaebPhase.d81);
                case 'gaeb_import':
                  await _gaebImport();
                case 'indizieren':
                  await showDialog<void>(
                    context: context,
                    builder: (_) => LvIndizierungDialog(kopf: widget.kopf),
                  );
                case 'bieter':
                  await _bieterDialog();
                case 'csv_export':
                  await _csvExport();
                case 'csv_import':
                  await _csvImport();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'preis_vorschau',
                  child: ListTile(
                    leading: Icon(Icons.print_outlined),
                    title: Text('Preis-LV (Vorschau)'),
                    dense: true,
                  )),
              PopupMenuItem(
                  value: 'preis_archiv',
                  child: ListTile(
                    leading: Icon(Icons.archive_outlined),
                    title: Text('Preis-LV drucken & in Akte ablegen'),
                    dense: true,
                  )),
              PopupMenuDivider(),
              PopupMenuItem(
                  value: 'blanko_vorschau',
                  child: ListTile(
                    leading: Icon(Icons.description_outlined),
                    title: Text('Blanko-LV / Ausschreibung (Vorschau)'),
                    dense: true,
                  )),
              PopupMenuItem(
                  value: 'blanko_archiv',
                  child: ListTile(
                    leading: Icon(Icons.archive_outlined),
                    title:
                        Text('Blanko-LV drucken & in Akte ablegen'),
                    dense: true,
                  )),
              PopupMenuDivider(),
              PopupMenuItem(
                  value: 'gaeb_d83',
                  child: ListTile(
                    leading: Icon(Icons.file_download_outlined),
                    title: Text('GAEB X83 Export (Ausschreibung)'),
                    dense: true,
                  )),
              PopupMenuItem(
                  value: 'gaeb_d81',
                  child: ListTile(
                    leading: Icon(Icons.file_download_outlined),
                    title: Text('GAEB X81 Export (LV-Übergabe)'),
                    dense: true,
                  )),
              PopupMenuDivider(),
              PopupMenuItem(
                  value: 'gaeb_import',
                  child: ListTile(
                    leading: Icon(Icons.file_upload_outlined),
                    title: Text('GAEB Datei importieren …'),
                    subtitle: Text('X81 / X83 / X84 — von Architekt oder BKI'),
                    dense: true,
                  )),
              PopupMenuDivider(),
              PopupMenuItem(
                  value: 'indizieren',
                  child: ListTile(
                    leading: Icon(Icons.trending_up),
                    title: Text('Preise indizieren (Destatis)'),
                    dense: true,
                  )),
              PopupMenuItem(
                  value: 'bieter',
                  child: ListTile(
                    leading: Icon(Icons.compare_arrows),
                    title: Text('Bietergegenüberstellung …'),
                    dense: true,
                  )),
              PopupMenuDivider(),
              PopupMenuItem(
                  value: 'csv_export',
                  child: ListTile(
                    leading: Icon(Icons.table_chart_outlined),
                    title: Text('CSV-Export (Excel)'),
                    dense: true,
                  )),
              PopupMenuItem(
                  value: 'csv_import',
                  child: ListTile(
                    leading: Icon(Icons.upload_file_outlined),
                    title: Text('CSV-Import …'),
                    dense: true,
                  )),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Kopf-Felder
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                    flex: 4,
                    child: LabeledField(
                      'Bezeichnung',
                      TextFormField(
                        controller: _bezeichnung,
                        onChanged: (_) => _saveKopf(),
                      ),
                    )),
                const SizedBox(width: 12),
                Expanded(
                    flex: 4,
                    child: LabeledField(
                      'Untertitel / Vorbemerkung',
                      TextFormField(
                        controller: _untertitel,
                        onChanged: (_) => _saveKopf(),
                      ),
                    )),
                const SizedBox(width: 12),
                Expanded(
                    flex: 2,
                    child: LabeledField(
                      'LV-Nummer',
                      TextFormField(
                        controller: _nummer,
                        onChanged: (_) => _saveKopf(),
                      ),
                    )),
              ],
            ),
          ),
          const Divider(height: 1),
          // Toolbar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Neue Position'),
                  onPressed: () => _neuePosition(),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.bookmarks_outlined, size: 16),
                  label: const Text('Aus Katalog einfügen'),
                  onPressed: _ausKatalog,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.format_list_numbered, size: 16),
                  label: const Text('OZ neu nummerieren'),
                  onPressed: () async {
                    await ref
                        .read(lvRepositoryProvider)
                        .renumberOz(widget.kopf.id);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Ordnungszahlen neu nummeriert.')));
                  },
                ),
                const Spacer(),
                _SummeBadge(lvId: widget.kopf.id, mwst: widget.kopf.mwstSatz),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: positionenAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (positionen) {
                if (positionen.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.list_alt_outlined,
                              size: 56,
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant),
                          const SizedBox(height: 12),
                          Text('Noch keine Positionen.',
                              style:
                                  Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text(
                            'Lege eine neue Position an oder füge eine '
                            'aus dem Katalog ein.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                // Flache Druck-Reihenfolge (Top-Level + Kinder rekursiv).
                final flach = _flachReihenfolge(positionen);
                return ReorderableListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: flach.length,
                  buildDefaultDragHandles: false,
                  onReorder: (oldIdx, newIdx) async {
                    final p = flach[oldIdx];
                    var ziel = newIdx;
                    if (ziel > oldIdx) ziel -= 1;
                    await ref
                        .read(lvRepositoryProvider)
                        .verschiebeAufIndex(
                          positionId: p.id,
                          neuerIndex: ziel,
                          flacheReihenfolge: flach,
                        );
                  },
                  itemBuilder: (_, i) => Padding(
                    key: ValueKey(flach[i].id),
                    padding: EdgeInsets.zero,
                    child: _PositionsZeile(
                      index: i,
                      position: flach[i],
                      money: _LvEditorScreenState._money,
                      menge: _LvEditorScreenState._menge,
                      onTap: () async {
                        await showDialog<void>(
                          context: context,
                          useRootNavigator: true,
                          builder: (_) => LvPositionDialog(
                            lvId: widget.kopf.id,
                            position: flach[i],
                          ),
                        );
                      },
                      onUp: () async {
                        await ref
                            .read(lvRepositoryProvider)
                            .verschiebePosition(
                                positionId: flach[i].id,
                                nachOben: true);
                      },
                      onDown: () async {
                        await ref
                            .read(lvRepositoryProvider)
                            .verschiebePosition(
                                positionId: flach[i].id,
                                nachOben: false);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Bringt die hierarchische Positions-Liste in die Druck-Reihenfolge
/// (Top-Level zuerst, dann je Top-Level rekursiv die Kinder).
List<LvPositionenData> _flachReihenfolge(List<LvPositionenData> all) {
  final byParent = <int?, List<LvPositionenData>>{};
  for (final p in all) {
    byParent.putIfAbsent(p.parentId, () => []).add(p);
  }
  for (final list in byParent.values) {
    list.sort((a, b) {
      final c = a.sortIndex.compareTo(b.sortIndex);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  }
  final out = <LvPositionenData>[];
  void rec(int? parent) {
    final list = byParent[parent] ?? [];
    for (final p in list) {
      out.add(p);
      rec(p.id);
    }
  }
  rec(null);
  return out;
}

class _PositionsZeile extends ConsumerWidget {
  const _PositionsZeile({
    required this.index,
    required this.position,
    required this.money,
    required this.menge,
    required this.onTap,
    required this.onUp,
    required this.onDown,
  });
  final int index;
  final LvPositionenData position;
  final NumberFormat money;
  final NumberFormat menge;
  final VoidCallback onTap;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTitel = position.art == 'titel';
    final isGrundtext = position.art == 'grundtext';
    final isBedarf = position.art == 'bedarf';
    final isStunden = position.art == 'stundenlohn';
    final m = position.menge ?? 0;
    final ep = position.einzelpreis ?? 0;
    final gp = m * ep;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isTitel
            ? Theme.of(context).colorScheme.surfaceContainerHigh
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag-Handle für Drag-and-drop.
            ReorderableDragStartListener(
              index: index,
              child: const SizedBox(
                width: 24,
                height: 44,
                child: Icon(Icons.drag_indicator,
                    size: 18, color: Colors.grey),
              ),
            ),
            // Up/Down-Pfeile zum Sortieren innerhalb desselben parents.
            Column(
              children: [
                SizedBox(
                  width: 24,
                  height: 22,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 14,
                    tooltip: 'Nach oben',
                    icon: const Icon(Icons.keyboard_arrow_up),
                    onPressed: onUp,
                  ),
                ),
                SizedBox(
                  width: 24,
                  height: 22,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 14,
                    tooltip: 'Nach unten',
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: onDown,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            if (isBedarf || isStunden)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: isBedarf
                      ? Colors.orange.withValues(alpha: 0.18)
                      : Colors.blue.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(isBedarf ? 'BP' : 'Std',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isBedarf
                            ? Colors.orange[800]
                            : Colors.blue[800])),
              ),
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    position.kurztext,
                    style: TextStyle(
                      fontSize: isTitel ? 14 : 13,
                      fontWeight: isTitel
                          ? FontWeight.w700
                          : (isGrundtext
                              ? FontWeight.w600
                              : FontWeight.w500),
                    ),
                  ),
                  if ((position.langtext ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        position.langtext!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if ((position.din276 ?? '').isNotEmpty ||
                      (position.gewerk ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        [
                          if ((position.din276 ?? '').isNotEmpty)
                            'KG ${position.din276}',
                          if ((position.gewerk ?? '').isNotEmpty)
                            position.gewerk,
                        ].whereType<String>().join(' · '),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline),
                      ),
                    ),
                ],
              ),
            ),
            if (!isTitel && !isGrundtext) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: Text(
                  '${menge.format(m)} ${position.einheit ?? ""}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: Text(
                  money.format(ep),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: Text(
                  isBedarf ? '(BP)' : money.format(gp),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isBedarf
                          ? FontWeight.normal
                          : FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummeBadge extends ConsumerWidget {
  const _SummeBadge({required this.lvId, required this.mwst});
  final int lvId;
  final double mwst;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(lvPositionenProvider(lvId));
    return pos.maybeWhen(
      data: (rows) {
        final money = NumberFormat.currency(
            locale: 'de_DE', symbol: '€', decimalDigits: 2);
        final netto = rows
            .where((p) =>
                p.art == 'normal' ||
                p.art == 'eventual' ||
                p.art == 'stundenlohn')
            .fold<double>(
                0, (s, p) => s + ((p.menge ?? 0) * (p.einzelpreis ?? 0)));
        final brutto = netto * (1 + mwst / 100);
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Netto ${money.format(netto)} · Brutto ',
                  style: const TextStyle(fontSize: 12)),
              Text(money.format(brutto),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
