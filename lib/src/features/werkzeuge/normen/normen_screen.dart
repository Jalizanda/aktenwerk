import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ai/norm_rag_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/aw_tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../data/sync/auth_service.dart';
import '../../../data/sync/storage_service.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';

import 'normen_chat_dialog.dart';
import 'normen_rag_chat_dialog.dart';
import 'normen_import.dart';
import 'normen_pdf_bulk_dialog.dart';
import 'normen_repository.dart';

enum _MehrAktion { jsonImport, bulkUpload, aktualitaet, indexieren }

class NormenScreen extends ConsumerWidget {
  const NormenScreen({super.key});

  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(normenListProvider);
    final filter = ref.watch(normenFilterProvider);
    final isMobile = MediaQuery.sizeOf(context).width < 650;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.menu_book_outlined,
          title: 'Normen',
          subtitle: 'Normen-, Richtlinien- & Gesetze-Katalog',
          actions: isMobile
              ? [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.psychology_alt_outlined, size: 18),
                    label: const Text('KI-Frage'),
                    onPressed: () => _oeffneKiChat(context),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Neu'),
                    onPressed: () => _show(context, ref),
                  ),
                  PopupMenuButton<_MehrAktion>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'Weitere Aktionen',
                    onSelected: (a) => switch (a) {
                      _MehrAktion.jsonImport => _importJson(context, ref),
                      _MehrAktion.bulkUpload => showDialog(
                          context: context,
                          useRootNavigator: true,
                          builder: (_) => const NormenPdfBulkDialog(),
                        ),
                      _MehrAktion.aktualitaet =>
                        _openAktualitaetsDialog(context, ref),
                      _MehrAktion.indexieren =>
                        _bibliothekIndexieren(context, ref),
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _MehrAktion.jsonImport,
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.upload_file_outlined),
                          title: Text('JSON-Import'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _MehrAktion.bulkUpload,
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.cloud_upload_outlined),
                          title: Text('PDF-Massen-Upload'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _MehrAktion.aktualitaet,
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.fact_check_outlined),
                          title: Text('Aktualität prüfen'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _MehrAktion.indexieren,
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.cloud_sync_outlined),
                          title: Text('Bibliothek indexieren'),
                        ),
                      ),
                    ],
                  ),
                ]
              : [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.psychology_alt_outlined, size: 18),
                    label: const Text('KI-Frage stellen'),
                    onPressed: () => _oeffneKiChat(context),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: const Text('JSON-Import'),
                    onPressed: () => _importJson(context, ref),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: const Text('PDFs-Massen-Upload'),
                    onPressed: () => showDialog(
                      context: context,
                      useRootNavigator: true,
                      builder: (_) => const NormenPdfBulkDialog(),
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: const Text('Aktualität prüfen'),
                    onPressed: () => _openAktualitaetsDialog(context, ref),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.cloud_sync_outlined, size: 18),
                    label: const Text('Bibliothek indexieren'),
                    onPressed: () => _bibliothekIndexieren(context, ref),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Neue Norm'),
                    onPressed: () => _show(context, ref),
                  ),
                ],
          searchHint: 'Suche Nummer, Titel, Kategorie …',
          onSearchChanged: (v) => ref
              .read(normenFilterProvider.notifier)
              .update((f) => f.copyWith(query: v)),
          filters: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(
                value: filter.nurFavoriten,
                onChanged: (v) => ref
                    .read(normenFilterProvider.notifier)
                    .update((f) => f.copyWith(nurFavoriten: v ?? false)),
              ),
              const Text('Nur Favoriten'),
            ]),
            Consumer(builder: (_, ref, _) {
              final gewerkeAsync = ref.watch(normenGewerkeProvider);
              final gewerke = gewerkeAsync.valueOrNull ?? const <String>[];
              if (gewerke.isEmpty) return const SizedBox.shrink();
              return DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: filter.gewerk,
                  hint: const Text('Alle Gewerke'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Alle Gewerke')),
                    for (final g in gewerke)
                      DropdownMenuItem<String?>(value: g, child: Text(g)),
                  ],
                  onChanged: (v) => ref
                      .read(normenFilterProvider.notifier)
                      .update((f) => f.copyWith(gewerkOverride: v)),
                ),
              );
            }),
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: filter.kategorie,
                hint: const Text('Alle Kategorien'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Alle Kategorien')),
                  for (final k in normKategorien)
                    DropdownMenuItem<String?>(value: k, child: Text(k)),
                ],
                onChanged: (v) => ref
                    .read(normenFilterProvider.notifier)
                    .update((f) => f.copyWith(kategorieOverride: v)),
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: filter.aktualitaetStatus,
                hint: const Text('Jeder Status'),
                items: const [
                  DropdownMenuItem<String?>(
                      value: null, child: Text('Jeder Status')),
                  DropdownMenuItem<String?>(
                      value: 'aktuell',
                      child: Text('Nur aktuelle')),
                  DropdownMenuItem<String?>(
                      value: 'veraltet',
                      child: Text('Nur veraltete')),
                  DropdownMenuItem<String?>(
                      value: '_unbekannt_oder_leer',
                      child: Text('Nicht geprüft / unbekannt')),
                ],
                onChanged: (v) => ref
                    .read(normenFilterProvider.notifier)
                    .update((f) =>
                        f.copyWith(aktualitaetStatusOverride: v)),
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        async.maybeWhen(
          data: (items) => _IndexFortschrittWidget(
            normIdsMitPdf: items
                .where((n) =>
                    n.pdfStorageUrl != null &&
                    n.pdfStorageUrl!.trim().isNotEmpty)
                .map((n) => n.id)
                .toList(),
          ),
          orElse: () => const SizedBox.shrink(),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) {
              if (items.isEmpty) {
                return const EmptyListState(
                    icon: Icons.menu_book_outlined,
                    title: 'Keine Normen erfasst');
              }
              final aktive = items.where((n) => n.aktiv).toList();
              final inaktive = items.where((n) => !n.aktiv).toList();
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _NormenTabelle(
                      label: 'Aktive Normen',
                      items: aktive,
                      onEdit: (n) => _show(context, ref, n),
                      onDelete: (n) => _confirm(context, ref, n),
                      onToggleFavorit: (n) => ref
                          .read(normenRepositoryProvider)
                          .toggleFavorit(n.id, !n.favorit),
                    ),
                    if (inaktive.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _NormenTabelle(
                        label:
                            'Inaktive / abgelaufene Normen (${inaktive.length})',
                        items: inaktive,
                        dimmed: true,
                        onEdit: (n) => _show(context, ref, n),
                        onDelete: (n) => _confirm(context, ref, n),
                        onToggleFavorit: (n) => ref
                            .read(normenRepositoryProvider)
                            .toggleFavorit(n.id, !n.favorit),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _show(BuildContext context, WidgetRef ref,
      [NormenData? n]) async {
    await showDialog(
        context: context,
        useRootNavigator: true,
        builder: (_) => _NormForm(norm: n));
  }

  /// Öffnet den KI-Normen-Chat in einem eigenen Browser-Tab/Fenster
  /// (Web). Auf anderen Plattformen fallen wir auf einen normalen
  /// Dialog zurück, damit's dort nicht hart fehlschlägt.
  void _oeffneKiChat(BuildContext context) {
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (_) => const _NormenKiChatDialogTabs(),
    );
  }

  Future<void> _bibliothekIndexieren(
      BuildContext context, WidgetRef ref) async {
    final db = ref.read(appDatabaseProvider);
    final alle = await db.select(db.normen).get();
    final mitPdf = alle
        .where((n) =>
            n.pdfStorageUrl != null && n.pdfStorageUrl!.trim().isNotEmpty)
        .toList();
    if (!context.mounted) return;
    if (mitPdf.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'In der Bibliothek liegen keine Normen mit Storage-PDF.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Bibliothek indexieren?'),
        content: Text(
          'Es werden alle ${mitPdf.length} Normen mit hinterlegtem PDF zur '
          'Vektorisierung im Cloud-Backend angemeldet. Bereits indexierte '
          'Normen werden übersprungen — Doppelung ist nicht möglich. '
          'Die Indexierung läuft im Hintergrund; den Status zeigt der '
          'farbige Punkt am PDF-Symbol jeder Norm.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Starten')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Anmeldung läuft … das kann einen Moment dauern.'),
        duration: Duration(seconds: 3)));
    try {
      final report = await ref
          .read(normRagServiceProvider)
          .markiereAlleZurIndexierung(mitPdf);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Indexierung gestartet: ${report.angefordert} Normen angemeldet, '
              '${report.uebersprungen} übersprungen (bereits indexiert oder ohne PDF).')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Anmelden: $e')));
    }
  }

  Future<void> _importJson(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: const Text('Normen aus JSON importieren?'),
        content: const Text(
          'Wähle eine JSON-Datei mit Normen aus. Normen, deren Nummer '
          'bereits im Katalog vorhanden ist, werden aktualisiert — neue '
          'werden hinzugefügt. Deine auftragsspezifischen Normen '
          'bleiben unverändert.\n\n'
          'Erwartete Felder je Eintrag: "Nummer / Kennung", "Titel", '
          '"Ausgabe / Version", "Kategorie", "Art", "Herausgeber", '
          '"Relevanz", "Zusammenfassung / Kernaussage", '
          '"Zitat / Keywords / Meta-Tags", "Beschreibung / Gewerke".',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.file_open, size: 16),
            label: const Text('Datei wählen …'),
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(true),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final bytes = res.files.first.bytes;
    if (bytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Datei konnte nicht gelesen werden.')));
      }
      return;
    }

    try {
      final report = await importiereNormenJson(ref, bytes);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${report.neu} neu · ${report.aktualisiert} aktualisiert'
              '${report.uebersprungen > 0 ? " · ${report.uebersprungen} übersprungen" : ""}',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import fehlgeschlagen: $e')),
        );
      }
    }
  }

  Future<void> _confirm(
      BuildContext context, WidgetRef ref, NormenData n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Norm löschen?'),
        content: Text('«${n.nummer}» wird gelöscht.'),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(false),
              child: const Text('Abbrechen')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(normenRepositoryProvider).delete(n.id);
  }

  Future<void> _openAktualitaetsDialog(
      BuildContext context, WidgetRef ref) async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => const _AktualitaetsDialog(),
    );
  }
}

/// ------------- Gemeinsame Tabelle (Aktiv / Inaktiv) -------------

class _NormenTabelle extends ConsumerStatefulWidget {
  const _NormenTabelle({
    required this.label,
    required this.items,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleFavorit,
    this.dimmed = false,
  });
  final String label;
  final List<NormenData> items;
  final void Function(NormenData) onEdit;
  final void Function(NormenData) onDelete;
  final void Function(NormenData) onToggleFavorit;
  final bool dimmed;

  @override
  ConsumerState<_NormenTabelle> createState() => _NormenTabelleState();
}

class _NormenTabelleState extends ConsumerState<_NormenTabelle> {
  // Sort-State: Spalten-Index (entsprechend der `columns`-Reihenfolge) +
  // Richtung. -1 = keine Sortierung (Original-Reihenfolge).
  int _sortColumnIndex = -1;
  bool _sortAscending = true;

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  // Sortier-Schlüssel pro Spalte. Stringvergleich case-insensitive,
  // null bzw. leer wandert ans Ende (in beide Richtungen).
  Comparable<Object> _key(NormenData n, int col,
      Map<int, NormIndexStatus> statusMap) {
    String s(String? v) => (v ?? '').toLowerCase();
    switch (col) {
      case 1:
        return s(n.nummer);
      case 2:
        return s(n.ausgabe);
      case 3:
        return s(n.titel);
      case 4:
        return s(n.gewerk);
      case 5:
        return s(n.kategorie);
      case 6:
        // Aktualität: aktuell < veraltet < unbekannt/null
        final st = (n.aktualitaetStatus ?? '').toLowerCase();
        return st.isEmpty ? 'zzz' : st;
      case 7:
        // Indexiert-Status (sortiert nach Reihenfolge: indexed > indexing > pending > failed > unbekannt)
        final st = statusMap[n.id] ?? NormIndexStatus.unbekannt;
        return _statusSortRank(st);
      default:
        return s(n.nummer);
    }
  }

  String _statusSortRank(NormIndexStatus s) {
    return switch (s) {
      NormIndexStatus.indexed => '1',
      NormIndexStatus.indexing => '2',
      NormIndexStatus.pending => '3',
      NormIndexStatus.failed => '4',
      NormIndexStatus.unbekannt => '5',
    };
  }

  @override
  Widget build(BuildContext context) {
    final statusMapAsync = ref.watch(normIndexStatusMapProvider);
    final statusMap = statusMapAsync.valueOrNull ?? const <int, NormIndexStatus>{};
    final items = widget.items;
    final dimmed = widget.dimmed;
    final label = widget.label;
    final onEdit = widget.onEdit;
    final onDelete = widget.onDelete;
    final onToggleFavorit = widget.onToggleFavorit;

    final sorted = _sortColumnIndex < 0
        ? items
        : ([...items]..sort((a, b) {
            final ka = _key(a, _sortColumnIndex, statusMap);
            final kb = _key(b, _sortColumnIndex, statusMap);
            final cmp = Comparable.compare(ka, kb);
            return _sortAscending ? cmp : -cmp;
          }));
    final isMobile = MediaQuery.sizeOf(context).width < 650;

    // ── Mobile: Kachel-Liste ──────────────────────────────────────────────
    if (isMobile) {
      return Opacity(
        opacity: dimmed ? 0.72 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: dimmed ? AppTheme.slate500 : AppTheme.slate900,
                  ),
                ),
              ),
              for (final n in sorted)
                _NormMobileKachel(
                  norm: n,
                  indexStatus:
                      statusMap[n.id] ?? NormIndexStatus.unbekannt,
                  onEdit: () => onEdit(n),
                  onDelete: () => onDelete(n),
                  onToggleFavorit: () => onToggleFavorit(n),
                ),
            ],
          ),
        ),
      );
    }

    // ── Desktop: DataTable ────────────────────────────────────────────────
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: dimmed ? AppTheme.slate500 : AppTheme.slate900,
              ),
            ),
          ),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Opacity(
              opacity: dimmed ? 0.72 : 1.0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  showCheckboxColumn: false,
                  sortColumnIndex:
                      _sortColumnIndex < 0 ? null : _sortColumnIndex,
                  sortAscending: _sortAscending,
                  headingRowColor: WidgetStateProperty.all(
                    Theme.of(context).colorScheme.surfaceContainerLow,
                  ),
                  columns: [
                    const DataColumn(
                        label: SizedBox(width: 24, child: Text(''))),
                    DataColumn(label: const Text('Nummer'), onSort: _onSort),
                    DataColumn(label: const Text('Ausgabe'), onSort: _onSort),
                    DataColumn(label: const Text('Titel'), onSort: _onSort),
                    DataColumn(label: const Text('Gewerk'), onSort: _onSort),
                    DataColumn(label: const Text('Kategorie'), onSort: _onSort),
                    DataColumn(label: const Text('Aktualität'), onSort: _onSort),
                    DataColumn(label: const Text('Indexiert'), onSort: _onSort),
                    const DataColumn(
                        label: SizedBox(width: 28, child: Text(''))),
                    const DataColumn(
                        label: SizedBox(width: 28, child: Text(''))),
                  ],
                  rows: [
                    for (final n in sorted)
                      DataRow(
                        onSelectChanged: (_) => onEdit(n),
                        cells: [
                          DataCell(IconButton(
                            tooltip: n.favorit
                                ? 'Favorit entfernen'
                                : 'Als Favorit markieren',
                            icon: Icon(
                              n.favorit ? Icons.star : Icons.star_outline,
                              size: 18,
                              color: n.favorit
                                  ? Theme.of(context).colorScheme.tertiary
                                  : null,
                            ),
                            onPressed: () => onToggleFavorit(n),
                          )),
                          DataCell(Text(n.nummer,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: [
                                    FontFeature.tabularFigures()
                                  ]))),
                          DataCell(Text(n.ausgabe ?? '—')),
                          DataCell(SizedBox(
                            width: 380,
                            child: Text(
                              n.titel ?? '—',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                          DataCell(SizedBox(
                            width: 160,
                            child: Text(
                              n.gewerk ?? '—',
                              style: const TextStyle(fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                          DataCell(_KategorieBadge(kategorie: n.kategorie)),
                          DataCell(_AktualitaetsPill(norm: n)),
                          DataCell(_IndexStatusZelle(
                              status: statusMap[n.id] ??
                                  NormIndexStatus.unbekannt)),
                          DataCell(_PdfCell(norm: n)),
                          DataCell(IconButton(
                            tooltip: 'Bearbeiten',
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: () => onEdit(n),
                          )),
                          DataCell(IconButton(
                            tooltip: 'Löschen',
                            icon:
                                const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => onDelete(n),
                          )),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ------------- Mobile Kachel -------------

class _NormMobileKachel extends ConsumerWidget {
  const _NormMobileKachel({
    required this.norm,
    required this.indexStatus,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleFavorit,
  });
  final NormenData norm;
  final NormIndexStatus indexStatus;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPdf =
        norm.pdfStorageUrl != null && norm.pdfStorageUrl!.trim().isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.8),
      ),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Favorit-Button
              GestureDetector(
                onTap: onToggleFavorit,
                child: Padding(
                  padding: const EdgeInsets.only(top: 1, right: 6),
                  child: Icon(
                    norm.favorit ? Icons.star : Icons.star_outline,
                    size: 18,
                    color: norm.favorit
                        ? Theme.of(context).colorScheme.tertiary
                        : AppTheme.slate400,
                  ),
                ),
              ),
              // Inhalt
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nummer + Kategorie
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            norm.nummer,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _KategorieBadge(kategorie: norm.kategorie),
                      ],
                    ),
                    // Titel
                    if ((norm.titel ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        norm.titel!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, color: AppTheme.slate700),
                      ),
                    ],
                    // Ausgabe + Aktualität + PDF-Dot
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if ((norm.ausgabe ?? '').isNotEmpty) ...[
                          Text(norm.ausgabe!,
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.slate500)),
                          const SizedBox(width: 8),
                        ],
                        _AktualitaetsPill(norm: norm),
                        if (hasPdf) ...[
                          const SizedBox(width: 8),
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(Icons.picture_as_pdf,
                                  size: 16, color: AwTokens.red),
                              Positioned(
                                right: -3,
                                bottom: -3,
                                child: _IndexStatusDot(status: indexStatus),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Löschen-Button
              IconButton(
                icon:
                    const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Löschen',
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ------------- Cell-Widgets -------------

class _KategorieBadge extends StatelessWidget {
  const _KategorieBadge({required this.kategorie});
  final String? kategorie;

  @override
  Widget build(BuildContext context) {
    if (kategorie == null || kategorie!.trim().isEmpty) {
      return const Text('—');
    }
    final (bg, fg) = switch (kategorie) {
      'Norm' => (const Color(0xFFDBEAFE), const Color(0xFF1E40AF)),
      'Richtlinie' => (const Color(0xFFFEF3C7), const Color(0xFF92400E)),
      'Merkblatt' => (const Color(0xFFE0F2FE), const Color(0xFF075985)),
      'Gesetz' => (const Color(0xFFFECACA), const Color(0xFF991B1B)),
      'Verordnung' => (const Color(0xFFFED7AA), const Color(0xFF9A3412)),
      'Leitfaden' => (const Color(0xFFE0E7FF), const Color(0xFF3730A3)),
      'Fachregel' => (const Color(0xFFDCFCE7), const Color(0xFF166534)),
      'Rechtsprechung' => (const Color(0xFFEDE9FE), const Color(0xFF5B21B6)),
      _ => (AppTheme.slate100, AppTheme.slate500),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(kategorie!,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

class _AktualitaetsPill extends StatelessWidget {
  const _AktualitaetsPill({required this.norm});
  final NormenData norm;

  @override
  Widget build(BuildContext context) {
    final status = norm.aktualitaetStatus;
    final (color, label, icon) = switch (status) {
      'aktuell' => (
          const Color(0xFF16A34A),
          'aktuell',
          Icons.check_circle
        ),
      'veraltet' => (
          AwTokens.red,
          'veraltet',
          Icons.cancel
        ),
      'unbekannt' => (
          const Color(0xFFEAB308),
          'prüfen',
          Icons.help
        ),
      _ => (AppTheme.slate400, 'nicht geprüft', Icons.radio_button_unchecked),
    };
    final geprueft = norm.aktualitaetGeprueftAm;
    return Tooltip(
      message: geprueft == null
          ? 'Noch nicht geprüft'
          : 'Zuletzt geprüft: ${NormenScreen._dateFmt.format(geprueft)}'
              '${norm.aktualitaetNotiz == null ? '' : '\n${norm.aktualitaetNotiz}'}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

class _PdfCell extends ConsumerWidget {
  const _PdfCell({required this.norm});
  final NormenData norm;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = norm.pdfStorageUrl;
    if (url == null || url.isEmpty) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<NormIndexStatus>(
      stream: ref.read(normRagServiceProvider).watchStatus(norm.id),
      builder: (context, snap) {
        final status = snap.data ?? NormIndexStatus.unbekannt;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip:
                  '${norm.pdfDateiname ?? 'PDF öffnen'}\nIndexierung: ${status.label}',
              icon: const Icon(Icons.picture_as_pdf,
                  size: 20, color: AwTokens.red),
              onPressed: () async {
                final uri = Uri.tryParse(url);
                if (uri != null) {
                  await launchUrl(uri,
                      mode: LaunchMode.externalApplication);
                }
              },
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: _IndexStatusDot(status: status),
            ),
          ],
        );
      },
    );
  }
}

/// Zellen-Variante des Index-Status: kleines Icon + sprechendes Label,
/// damit man in der Tabelle direkt erkennt, ob die Norm im Cloud-Index ist.
class _IndexStatusZelle extends StatelessWidget {
  const _IndexStatusZelle({required this.status});
  final NormIndexStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (status) {
      NormIndexStatus.indexed => (AwTokens.green, Icons.check_circle, 'Indexiert'),
      NormIndexStatus.indexing => (AwTokens.blue, Icons.hourglass_top, 'Läuft …'),
      NormIndexStatus.pending => (AwTokens.amber, Icons.schedule, 'Wartet'),
      NormIndexStatus.failed => (AwTokens.red, Icons.error_outline, 'Fehler'),
      NormIndexStatus.unbekannt => (
          Theme.of(context).colorScheme.outline,
          Icons.cloud_off_outlined,
          '—',
        ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w500, color: color)),
      ],
    );
  }
}

class _IndexStatusDot extends StatelessWidget {
  const _IndexStatusDot({required this.status});
  final NormIndexStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      NormIndexStatus.indexed => (AwTokens.green, Icons.check),
      NormIndexStatus.indexing => (AwTokens.blue, Icons.hourglass_top),
      NormIndexStatus.pending => (AwTokens.amber, Icons.schedule),
      NormIndexStatus.failed => (AwTokens.red, Icons.error_outline),
      NormIndexStatus.unbekannt => (
          Theme.of(context).colorScheme.outlineVariant,
          Icons.cloud_off_outlined,
        ),
    };
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
            color: Theme.of(context).colorScheme.surface, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 8, color: Colors.white),
    );
  }
}

/// ------------- Aktualitäts-Prüf-Dialog -------------

class _AktualitaetsDialog extends ConsumerStatefulWidget {
  const _AktualitaetsDialog();
  @override
  ConsumerState<_AktualitaetsDialog> createState() =>
      _AktualitaetsDialogState();
}

class _AktualitaetsDialogState extends ConsumerState<_AktualitaetsDialog> {
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(normenListProvider);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.fact_check_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Aktualität prüfen',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                'Klicke auf „Recherchieren", um die Norm im DIN-Katalog '
                'und bei Beuth in einem neuen Tab zu öffnen. Anschließend '
                'kannst du den Status per Ampel-Button setzen.',
                style: TextStyle(fontSize: 12, color: AppTheme.slate500),
              ),
            ),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Fehler: $e')),
                data: (items) {
                  final aktive = items.where((n) => n.aktiv).toList();
                  if (aktive.isEmpty) {
                    return const Center(
                        child: Text('Keine aktiven Normen.'));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: aktive.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _AktualitaetsRow(norm: aktive[i]),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                    child: const Text('Schließen'),
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

class _AktualitaetsRow extends ConsumerWidget {
  const _AktualitaetsRow({required this.norm});
  final NormenData norm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(norm.nummer,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace')),
                    if (norm.ausgabe != null) ...[
                      const SizedBox(width: 8),
                      Text(norm.ausgabe!,
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.slate500)),
                    ],
                  ],
                ),
                if (norm.titel != null)
                  Text(norm.titel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                _AktualitaetsPill(norm: norm),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Im DIN-Katalog suchen',
            icon: const Icon(Icons.travel_explore, size: 20),
            onPressed: () => _recherchieren(norm),
          ),
          IconButton(
            tooltip: 'Als aktuell markieren',
            icon: const Icon(Icons.check_circle,
                size: 22, color: Color(0xFF16A34A)),
            onPressed: () => ref
                .read(normenRepositoryProvider)
                .setAktualitaet(norm.id, status: 'aktuell'),
          ),
          IconButton(
            tooltip: 'Als veraltet markieren',
            icon: const Icon(Icons.cancel,
                size: 22, color: AwTokens.red),
            onPressed: () => _markVeraltet(context, ref, norm),
          ),
        ],
      ),
    );
  }

  Future<void> _recherchieren(NormenData norm) async {
    final q = Uri.encodeQueryComponent(norm.nummer);
    final url = Uri.parse('https://www.beuth.de/de/suche?query=$q');
    await launchUrl(url, mode: LaunchMode.externalApplication);
    final url2 = Uri.parse('https://www.dinmedia.de/de/suche/-/search/$q');
    await launchUrl(url2, mode: LaunchMode.externalApplication);
  }

  Future<void> _markVeraltet(
      BuildContext context, WidgetRef ref, NormenData n) async {
    final notizCtrl = TextEditingController(text: n.aktualitaetNotiz ?? '');
    final quelleCtrl = TextEditingController(text: n.aktualitaetQuelle ?? '');
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: Text('${n.nummer} als veraltet markieren'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: notizCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Hinweis (z. B. ersetzt durch …)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: quelleCtrl,
              decoration: const InputDecoration(
                labelText: 'Quelle / URL der neuen Fassung',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(normenRepositoryProvider).setAktualitaet(
            n.id,
            status: 'veraltet',
            notiz: notizCtrl.text,
            quelle: quelleCtrl.text,
          );
    }
  }
}

/// ------------- Form-Dialog -------------

class _NormForm extends ConsumerStatefulWidget {
  const _NormForm({this.norm});
  final NormenData? norm;
  @override
  ConsumerState<_NormForm> createState() => _NormFormState();
}

class _NormFormState extends ConsumerState<_NormForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nr = TextEditingController(text: widget.norm?.nummer ?? '');
  late final _titel =
      TextEditingController(text: widget.norm?.titel ?? '');
  late final _ausgabe =
      TextEditingController(text: widget.norm?.ausgabe ?? '');
  late final _herausgeber =
      TextEditingController(text: widget.norm?.herausgeber ?? '');
  late final _zusammenfassung =
      TextEditingController(text: widget.norm?.zusammenfassung ?? '');
  late final _zitat =
      TextEditingController(text: widget.norm?.zitat ?? '');
  late final _beschreibung =
      TextEditingController(text: widget.norm?.beschreibung ?? '');
  late final _gewerk =
      TextEditingController(text: widget.norm?.gewerk ?? '');
  late final _aktQuelle =
      TextEditingController(text: widget.norm?.aktualitaetQuelle ?? '');
  late final _aktNotiz =
      TextEditingController(text: widget.norm?.aktualitaetNotiz ?? '');

  String _art = 'DIN-Norm';
  String _kategorie = 'Norm';
  String _relevanz = 'referenz';
  String? _aktStatus;
  DateTime? _aktGeprueftAm;
  bool _aktiv = true;
  bool _favorit = false;
  bool _saving = false;
  bool _uploading = false;

  String? _pdfStorageUrl;
  String? _pdfDateiname;
  String? _pdfMimeType;
  int? _pdfGroesse;

  static const _artValues = [
    'DIN-Norm',
    'DIN EN',
    'DIN EN ISO',
    'WTA-Merkblatt',
    'VOB/C ATV',
    'VDI-Richtlinie',
    'BGB / HOAI / JVEG',
    'Sonstiges',
  ];

  @override
  void initState() {
    super.initState();
    final n = widget.norm;
    _aktiv = n?.aktiv ?? true;
    _favorit = n?.favorit ?? false;
    _art = n?.art ?? 'DIN-Norm';
    _kategorie = (n?.kategorie != null && normKategorien.contains(n!.kategorie))
        ? n.kategorie!
        : 'Norm';
    _relevanz = n?.relevanz ?? 'referenz';
    _aktStatus = n?.aktualitaetStatus;
    _aktGeprueftAm = n?.aktualitaetGeprueftAm;
    _pdfStorageUrl = n?.pdfStorageUrl;
    _pdfDateiname = n?.pdfDateiname;
    _pdfMimeType = n?.pdfMimeType;
    _pdfGroesse = n?.pdfGroesse;
  }

  @override
  void dispose() {
    for (final c in [
      _nr, _titel, _ausgabe, _herausgeber,
      _zusammenfassung, _zitat, _beschreibung, _gewerk,
      _aktQuelle, _aktNotiz,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.norm != null;

  Future<void> _pickAndUploadPdf() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;

    final storage = ref.read(storageServiceProvider);
    final auth = ref.read(authServiceProvider);
    if (!storage.enabled || auth.currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Cloud nicht verfügbar. Bitte zuerst anmelden.')));
      }
      return;
    }

    setState(() => _uploading = true);
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = 'normen/${ts}_${f.name}';
      final url = await storage.uploadBytes(
        path,
        bytes: f.bytes!,
        contentType: 'application/pdf',
      );
      if (url == null) {
        throw Exception('Upload fehlgeschlagen');
      }
      setState(() {
        _pdfStorageUrl = url;
        _pdfDateiname = f.name;
        _pdfMimeType = 'application/pdf';
        _pdfGroesse = f.size;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler beim Upload: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _removePdf() {
    setState(() {
      _pdfStorageUrl = null;
      _pdfDateiname = null;
      _pdfMimeType = null;
      _pdfGroesse = null;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final companion = NormenCompanion(
      id: _isEdit ? Value(widget.norm!.id) : const Value.absent(),
      nummer: Value(_nr.text.trim()),
      titel: _nt(_titel),
      ausgabe: _nt(_ausgabe),
      kategorie: Value(_kategorie),
      art: Value(_art),
      herausgeber: _nt(_herausgeber),
      relevanz: Value(_relevanz),
      zusammenfassung: _nt(_zusammenfassung),
      zitat: _nt(_zitat),
      beschreibung: _nt(_beschreibung),
      gewerk: _nt(_gewerk),
      aktiv: Value(_aktiv),
      favorit: Value(_favorit),
      pdfStorageUrl: Value(_pdfStorageUrl),
      pdfDateiname: Value(_pdfDateiname),
      pdfMimeType: Value(_pdfMimeType),
      pdfGroesse: Value(_pdfGroesse),
      aktualitaetStatus: Value(_aktStatus),
      aktualitaetGeprueftAm: Value(_aktGeprueftAm),
      aktualitaetQuelle: _nt(_aktQuelle),
      aktualitaetNotiz: _nt(_aktNotiz),
    );
    try {
      final id = await ref.read(normenRepositoryProvider).upsert(companion);
      // Wenn ein PDF hochgeladen wurde: Indexierung im Cloud-Backend anstoßen.
      if (_pdfStorageUrl != null && _pdfStorageUrl!.isNotEmpty) {
        try {
          final db = ref.read(appDatabaseProvider);
          final norm = await (db.select(db.normen)
                ..where((t) => t.id.equals(id)))
              .getSingleOrNull();
          if (norm != null) {
            await ref.read(normRagServiceProvider).markiereZurIndexierung(norm);
          }
        } catch (_) {/* Indexierung ist optional, blockiert den Save nicht */}
      }
      if (mounted) Navigator.of(context, rootNavigator: true).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Value<String?> _nt(TextEditingController c) {
    final v = c.text.trim();
    return Value(v.isEmpty ? null : v);
  }

  Future<void> _recherchieren() async {
    final n = _nr.text.trim();
    if (n.isEmpty) return;
    final q = Uri.encodeQueryComponent(n);
    final url = Uri.parse('https://www.beuth.de/de/suche?query=$q');
    await launchUrl(url, mode: LaunchMode.externalApplication);
    setState(() => _aktGeprueftAm = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return StandardFormDialog(
      title: _isEdit ? 'Norm / Richtlinie bearbeiten' : 'Neue Norm / Richtlinie',
      saving: _saving,
      maxHeight: 780,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _save,
      onDelete: _isEdit
          ? () async {
              await ref
                  .read(normenRepositoryProvider)
                  .delete(widget.norm!.id);
            }
          : null,
      deleteConfirmText:
          _isEdit ? '«${widget.norm!.nummer}» wird gelöscht.' : null,
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row2(
                flex: const (2, 3),
                left: LabeledField(
                  'Nummer / Kennung',
                  TextFormField(
                    controller: _nr,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Erforderlich' : null,
                  ),
                ),
                right: LabeledField(
                  'Ausgabe / Version',
                  TextFormField(controller: _ausgabe),
                ),
              ),
              const SizedBox(height: 12),
              LabeledField('Titel', TextFormField(controller: _titel)),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                  'Kategorie',
                  DropdownButtonFormField<String>(
                    initialValue: _kategorie,
                    isDense: true,
                    items: [
                      for (final v in normKategorien)
                        DropdownMenuItem(value: v, child: Text(v)),
                    ],
                    onChanged: (v) =>
                        setState(() => _kategorie = v ?? 'Norm'),
                  ),
                ),
                right: LabeledField(
                  'Art',
                  DropdownButtonFormField<String>(
                    initialValue: _art,
                    isDense: true,
                    items: [
                      for (final v in _artValues)
                        DropdownMenuItem(value: v, child: Text(v)),
                    ],
                    onChanged: (v) => setState(() => _art = v ?? 'DIN-Norm'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField('Herausgeber',
                    TextFormField(controller: _herausgeber)),
                right: LabeledField(
                  'Relevanz',
                  DropdownButtonFormField<String>(
                    initialValue: _relevanz,
                    isDense: true,
                    items: const [
                      DropdownMenuItem(
                          value: 'gutachten', child: Text('Gutachten')),
                      DropdownMenuItem(
                          value: 'referenz', child: Text('Referenz')),
                      DropdownMenuItem(
                          value: 'beweis', child: Text('Beweismittel')),
                    ],
                    onChanged: (v) =>
                        setState(() => _relevanz = v ?? 'referenz'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Zusammenfassung / Kernaussage',
                TextFormField(
                    controller: _zusammenfassung,
                    minLines: 2,
                    maxLines: 4),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Zitat / Text-Auszug',
                TextFormField(
                    controller: _zitat, minLines: 2, maxLines: 6),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Beschreibung / Notiz',
                TextFormField(
                    controller: _beschreibung,
                    minLines: 2,
                    maxLines: 5),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Gewerk (primär)',
                TextFormField(
                  controller: _gewerk,
                  decoration: const InputDecoration(
                    hintText: 'z. B. Fenster/Türen, Abdichtung, Schallschutz/Akustik',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              _AktualitaetsSection(
                status: _aktStatus,
                geprueftAm: _aktGeprueftAm,
                onStatusChanged: (s) => setState(() {
                  _aktStatus = s;
                  _aktGeprueftAm = DateTime.now();
                }),
                quelleCtrl: _aktQuelle,
                notizCtrl: _aktNotiz,
                onRecherche: _recherchieren,
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              _PdfSection(
                storageUrl: _pdfStorageUrl,
                dateiname: _pdfDateiname,
                groesse: _pdfGroesse,
                uploading: _uploading,
                onPick: _pickAndUploadPdf,
                onRemove: _removePdf,
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              _KiSection(
                pdfUrl: _pdfStorageUrl,
                nummer: _nr.text,
                titel: _titel.text,
              ),
              const SizedBox(height: 16),
              Row(children: [
                Switch(
                    value: _aktiv,
                    onChanged: (v) => setState(() => _aktiv = v)),
                const SizedBox(width: 6),
                const Text('Aktiv'),
                const SizedBox(width: 20),
                Switch(
                    value: _favorit,
                    onChanged: (v) => setState(() => _favorit = v)),
                const SizedBox(width: 6),
                const Text('Favorit'),
                const Spacer(),
                if (!_aktiv)
                  Text('→ erscheint in Tabelle der inaktiven Normen',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.slate500)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// ------------- Aktualitäts-Section -------------

class _AktualitaetsSection extends StatelessWidget {
  const _AktualitaetsSection({
    required this.status,
    required this.geprueftAm,
    required this.onStatusChanged,
    required this.quelleCtrl,
    required this.notizCtrl,
    required this.onRecherche,
  });
  final String? status;
  final DateTime? geprueftAm;
  final ValueChanged<String> onStatusChanged;
  final TextEditingController quelleCtrl;
  final TextEditingController notizCtrl;
  final VoidCallback onRecherche;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy', 'de');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Aktualitäts-Status',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        Row(
          children: [
            _StatusButton(
              label: 'aktuell',
              color: const Color(0xFF16A34A),
              icon: Icons.check_circle,
              active: status == 'aktuell',
              onPressed: () => onStatusChanged('aktuell'),
            ),
            const SizedBox(width: 8),
            _StatusButton(
              label: 'veraltet',
              color: AwTokens.red,
              icon: Icons.cancel,
              active: status == 'veraltet',
              onPressed: () => onStatusChanged('veraltet'),
            ),
            const SizedBox(width: 8),
            _StatusButton(
              label: 'unbekannt',
              color: const Color(0xFFEAB308),
              icon: Icons.help,
              active: status == 'unbekannt',
              onPressed: () => onStatusChanged('unbekannt'),
            ),
            const Spacer(),
            OutlinedButton.icon(
              icon: const Icon(Icons.travel_explore, size: 16),
              label: const Text('Online recherchieren'),
              onPressed: onRecherche,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (geprueftAm != null)
          Text('Zuletzt geprüft: ${fmt.format(geprueftAm!)}',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.slate500)),
        const SizedBox(height: 10),
        LabeledField(
            'Quelle / URL',
            TextFormField(
                controller: quelleCtrl,
                decoration: const InputDecoration(
                    hintText: 'https://www.beuth.de/…'))),
        const SizedBox(height: 10),
        LabeledField(
            'Notiz zur Aktualität',
            TextFormField(
                controller: notizCtrl, minLines: 1, maxLines: 3)),
      ],
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.active,
    required this.onPressed,
  });
  final String label;
  final Color color;
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: active ? Colors.white : color),
      label: Text(label,
          style: TextStyle(
              color: active ? Colors.white : color,
              fontWeight: FontWeight.w700)),
      style: OutlinedButton.styleFrom(
        backgroundColor: active ? color : Colors.white,
        side: BorderSide(color: color),
      ),
    );
  }
}

/// ------------- PDF-Section -------------

class _PdfSection extends StatelessWidget {
  const _PdfSection({
    required this.storageUrl,
    required this.dateiname,
    required this.groesse,
    required this.uploading,
    required this.onPick,
    required this.onRemove,
  });
  final String? storageUrl;
  final String? dateiname;
  final int? groesse;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  String _fmtSize(int? b) {
    if (b == null) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final hasPdf = storageUrl != null && storageUrl!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PDF / Dokument',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        if (hasPdf)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppTheme.slate200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.picture_as_pdf,
                    color: AwTokens.red, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dateiname ?? 'PDF',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      if (groesse != null)
                        Text(_fmtSize(groesse),
                            style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.slate500)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Im neuen Tab öffnen',
                  icon: const Icon(Icons.open_in_new, size: 18),
                  onPressed: () async {
                    final uri = Uri.tryParse(storageUrl!);
                    if (uri != null) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                ),
                IconButton(
                  tooltip: 'PDF entfernen',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: onRemove,
                ),
              ],
            ),
          )
        else
          OutlinedButton.icon(
            icon: uploading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file, size: 18),
            label: Text(uploading ? 'Lade hoch…' : 'PDF hochladen'),
            onPressed: uploading ? null : onPick,
          ),
      ],
    );
  }
}

/// ------------- KI-Section (Zusammenfassung + Chat, Placeholder) -------------

class _KiSection extends StatefulWidget {
  const _KiSection({
    required this.pdfUrl,
    required this.nummer,
    required this.titel,
  });
  final String? pdfUrl;
  final String nummer;
  final String titel;

  @override
  State<_KiSection> createState() => _KiSectionState();
}

class _KiSectionState extends State<_KiSection> {
  String? _zusammenfassung;
  bool _zfLoading = false;

  bool get _hasPdf => widget.pdfUrl != null && widget.pdfUrl!.isNotEmpty;

  Future<void> _generiereZusammenfassung() async {
    if (!_hasPdf) return;
    setState(() {
      _zfLoading = true;
      _zusammenfassung = null;
    });
    // TODO: echte KI-Anbindung. Aktuell Mock.
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _zfLoading = false;
      _zusammenfassung =
          'KI-Zusammenfassung wird in einer späteren Version generiert.\n\n'
          'Die Analyse wird auf Basis des hinterlegten PDFs erfolgen und '
          'die wichtigsten Aussagen, Anwendungsbereich, Prüfverfahren und '
          'Grenzwerte zu „${widget.nummer}${widget.titel.isNotEmpty ? " — ${widget.titel}" : ""}" strukturiert zusammenfassen.';
    });
  }

  Future<void> _frageStellen() async {
    if (!_hasPdf) return;
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => _KiChatDialog(
        nummer: widget.nummer,
        titel: widget.titel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final disabledHint = !_hasPdf
        ? 'Bitte zuerst ein PDF hochladen, damit die KI darauf arbeiten kann.'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('KI-Assistent',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEDE9FE),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Beta',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF5B21B6))),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: _zfLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_fix_high, size: 18),
              label: Text(_zfLoading
                  ? 'Analysiere…'
                  : 'KI-Zusammenfassung'),
              onPressed: _hasPdf && !_zfLoading
                  ? _generiereZusammenfassung
                  : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('KI-Frage stellen'),
              onPressed: _hasPdf ? _frageStellen : null,
            ),
          ],
        ),
        if (disabledHint != null) ...[
          const SizedBox(height: 6),
          Text(disabledHint,
              style: TextStyle(fontSize: 11, color: AppTheme.slate500)),
        ],
        if (_zusammenfassung != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppTheme.slate200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_fix_high,
                        size: 14, color: Color(0xFF5B21B6)),
                    const SizedBox(width: 6),
                    Text('Zusammenfassung',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slate500)),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  _zusammenfassung!,
                  style: const TextStyle(fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// KI-Chat-Dialog (Placeholder, echte Anbindung folgt).
class _KiChatDialog extends StatefulWidget {
  const _KiChatDialog({required this.nummer, required this.titel});
  final String nummer;
  final String titel;
  @override
  State<_KiChatDialog> createState() => _KiChatDialogState();
}

class _KiChatMessage {
  final String role; // 'user' | 'assistant'
  final String text;
  const _KiChatMessage(this.role, this.text);
}

class _KiChatDialogState extends State<_KiChatDialog> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_KiChatMessage> _messages = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messages.add(_KiChatMessage(
      'assistant',
      'Hallo — ich bin dein KI-Assistent für '
          '„${widget.nummer}${widget.titel.isNotEmpty ? " — ${widget.titel}" : ""}".\n'
          'Stelle mir eine Frage zum Dokument. (Die Anbindung an das echte '
          'Sprachmodell erfolgt in einer späteren Version — aktuell Platzhalter.)',
    ));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _messages.add(_KiChatMessage('user', text));
      _input.clear();
      _sending = true;
    });
    _scrollDown();
    // TODO: echte KI-Anbindung.
    await Future.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    setState(() {
      _messages.add(const _KiChatMessage(
        'assistant',
        '(Platzhalter-Antwort) Diese Frage wird später von der KI '
            'beantwortet. Die Antwort stützt sich auf das hinterlegte PDF.',
      ));
      _sending = false;
    });
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 680),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('KI-Frage zu ${widget.nummer}',
                            style:
                                Theme.of(context).textTheme.titleMedium),
                        if (widget.titel.isNotEmpty)
                          Text(widget.titel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.slate500)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context,
                            rootNavigator: true)
                        .pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + (_sending ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  if (_sending && i == _messages.length) {
                    return const _ChatBubble(
                      role: 'assistant',
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final m = _messages[i];
                  return _ChatBubble(
                    role: m.role,
                    child: SelectableText(
                      m.text,
                      style: const TextStyle(
                          fontSize: 13, height: 1.4),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Frage zur Norm stellen …',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.send, size: 16),
                    label: const Text('Senden'),
                    onPressed: _sending ? null : _send,
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

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.role, required this.child});
  final String role;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    return Row(
      mainAxisAlignment:
          isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isUser
                  ? const Color(0xFFEDE9FE)
                  : Colors.white,
              border: Border.all(color: AppTheme.slate200),
              borderRadius: BorderRadius.circular(10),
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// Collapsible Indexierungs-Status: kleiner Chip wenn ruhig, voller Balken
/// wenn aktiv. Blendet sich bei laufender Indexierung automatisch ein und
/// nach Abschluss wieder aus (nach 4 Sekunden).
class _IndexFortschrittWidget extends ConsumerStatefulWidget {
  const _IndexFortschrittWidget({required this.normIdsMitPdf});
  final List<int> normIdsMitPdf;

  @override
  ConsumerState<_IndexFortschrittWidget> createState() =>
      _IndexFortschrittWidgetState();
}

class _IndexFortschrittWidgetState
    extends ConsumerState<_IndexFortschrittWidget> {
  bool _expanded = false;
  Timer? _collapseTimer;
  StreamSubscription<NormIndexFortschritt>? _sub;
  NormIndexFortschritt? _letzter;

  @override
  void initState() {
    super.initState();
    if (widget.normIdsMitPdf.isEmpty) return;
    _sub = ref
        .read(normRagServiceProvider)
        .watchFortschritt(widget.normIdsMitPdf)
        .listen((f) {
      if (!mounted) return;
      setState(() => _letzter = f);
      if (f.laeuft && !_expanded) {
        _collapseTimer?.cancel();
        setState(() => _expanded = true);
      } else if (f.istFertig && _expanded) {
        _collapseTimer?.cancel();
        _collapseTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _expanded = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _collapseTimer?.cancel();
    super.dispose();
  }

  void _toggle() {
    _collapseTimer?.cancel();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.normIdsMitPdf.isEmpty) return const SizedBox.shrink();
    final f = _letzter;
    if (f == null) return const SizedBox.shrink();

    if (!_expanded) {
      // Kompakter Status-Chip — immer sichtbar, Tap öffnet den Balken.
      final (chipColor, chipIcon) = f.istFertig
          ? (AwTokens.green, Icons.check_circle_outline)
          : f.laeuft
              ? (AwTokens.blue, Icons.cloud_sync_outlined)
              : f.failed > 0
                  ? (AwTokens.red, Icons.error_outline)
                  : (AwTokens.mute, Icons.cloud_off_outlined);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _toggle,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: chipColor.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(chipIcon, size: 14, color: chipColor),
                  const SizedBox(width: 5),
                  Text(
                    'KI-Index: ${f.indexed}/${f.gesamt}'
                    '${f.failed > 0 ? '  ·  ${f.failed} ✕' : ''}',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: chipColor,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_more, size: 14, color: chipColor),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Voller Balken
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerLowest,
      padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            f.istFertig
                ? Icons.check_circle
                : (f.laeuft ? Icons.cloud_sync : Icons.cloud_off_outlined),
            size: 18,
            color: f.istFertig
                ? AwTokens.green
                : (f.laeuft ? AwTokens.blue : AwTokens.mute),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'KI-Indexierung: ${f.indexed} / ${f.gesamt} Normen',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    if (f.chunks > 0)
                      Text('· ${f.chunks} Textstellen',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: f.fortschritt,
                    minHeight: 6,
                    backgroundColor: scheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(
                        f.istFertig ? AwTokens.green : AwTokens.orange),
                  ),
                ),
                if (f.laeuft || f.failed > 0 || f.unbekannt > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 14,
                      children: [
                        if (f.indexing > 0)
                          _StatusZahl(
                              icon: Icons.hourglass_top,
                              color: AwTokens.blue,
                              label: '${f.indexing} läuft'),
                        if (f.pending > 0)
                          _StatusZahl(
                              icon: Icons.schedule,
                              color: AwTokens.amber,
                              label: '${f.pending} wartet'),
                        if (f.failed > 0)
                          Builder(
                            builder: (ctx) => InkWell(
                              onTap: () => _zeigeFehlerDialog(ctx, ref),
                              child: _StatusZahl(
                                  icon: Icons.error_outline,
                                  color: AwTokens.red,
                                  label: '${f.failed} fehlgeschlagen ›'),
                            ),
                          ),
                        if (f.unbekannt > 0)
                          _StatusZahl(
                              icon: Icons.cloud_off_outlined,
                              color: AwTokens.mute,
                              label: '${f.unbekannt} nicht angemeldet'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.expand_less, size: 18),
            tooltip: 'Einklappen',
            onPressed: _toggle,
          ),
        ],
      ),
    );
  }
}

class _StatusZahl extends StatelessWidget {
  const _StatusZahl({
    required this.icon,
    required this.color,
    required this.label,
  });
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11.5,
                color: color,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

/// Modaler Dialog mit zwei Tabs:
///  - **RAG (neu)**: Vector-Search gegen indexierte Chunks + Quellen
///  - **Klassisch**: bisheriger Chat, der ganze PDFs an Gemini schickt
class _NormenKiChatDialogTabs extends StatefulWidget {
  const _NormenKiChatDialogTabs();
  @override
  State<_NormenKiChatDialogTabs> createState() =>
      _NormenKiChatDialogTabsState();
}

class _NormenKiChatDialogTabsState extends State<_NormenKiChatDialogTabs>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 650;
    return Dialog(
      insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: isMobile
            ? BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width,
                maxHeight: MediaQuery.sizeOf(context).height,
              )
            : const BoxConstraints(maxWidth: 960, maxHeight: 800),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  20, isMobile ? MediaQuery.paddingOf(context).top + 8 : 14, 8, 0),
              child: Row(
                children: [
                  Text('Normen-Chat',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Schließen',
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(icon: Icon(Icons.auto_awesome, size: 18), text: 'RAG (neu)'),
                Tab(
                    icon: Icon(Icons.chat_bubble_outline, size: 18),
                    text: 'Klassisch'),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: const [
                  NormenRagChatDialog(embedded: true),
                  NormenChatDialog(embedded: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Zeigt die fehlgeschlagenen Norm-Indexierungen mit ihren Fehlermeldungen.
Future<void> _zeigeFehlerDialog(BuildContext context, WidgetRef ref) async {
  final liste = await ref.read(normRagServiceProvider).ladeFehlgeschlagene();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (dialogCtx) => Dialog(
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AwTokens.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        'Fehlgeschlagene Indexierungen (${liste.length})',
                        style: Theme.of(dialogCtx).textTheme.titleMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: liste.isEmpty
                  ? const Center(child: Text('Keine Fehler'))
                  : ListView.separated(
                      itemCount: liste.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = liste[i];
                        return ListTile(
                          dense: true,
                          title: Text(e.nummer.isEmpty
                              ? 'Norm #${e.normId ?? '?'}'
                              : e.nummer),
                          subtitle: Text(e.error,
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontFamily: 'monospace')),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    child: const Text('Schließen'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
