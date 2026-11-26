import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ai/norm_rag_service.dart';
import '../../../core/ai/normen_aktualitaet_ki_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/aw_tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../data/sync/auth_service.dart';
import '../../../data/sync/auto_sync_service.dart';
import '../../../data/sync/org_service.dart';
import '../../../data/sync/storage_service.dart';
import '../../../data/sync/sync_service.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import '../../shell/auto_sync_badge.dart';
import '../../system/org/org_switcher.dart';

import 'normen_chat_dialog.dart';
import 'normen_dubletten_dialog.dart';
import 'normen_rag_chat_dialog.dart';
import 'normen_import.dart';
import 'normen_pdf_bulk_dialog.dart';
import 'normen_repository.dart';

enum _MehrAktion { jsonImport, bulkUpload, aktualitaet, indexieren }

class NormenScreen extends ConsumerWidget {
  const NormenScreen({super.key, this.standalonePortal = false});

  /// Wenn `true` (z. B. unter `norm.aktenwerk.app`), wird die Normen-Bibliothek
  /// als eigenständige Vollbild-Seite ohne das übrige Aktenwerk-Hauptmenü geladen.
  final bool standalonePortal;

  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(normenListProvider);
    final filter = ref.watch(normenFilterProvider);
    final isMobile = MediaQuery.sizeOf(context).width < 650;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.menu_book_outlined,
          title: standalonePortal
              ? 'Aktenwerk · Normen-Bibliothek'
              : 'Normen',
          subtitle:
              'Normen-, Richtlinien- & Gesetze-Pool · Suche, KI-Chat & Gültigkeitshistorie (Von – Bis)',
          actions: isMobile
              ? [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: const Text('KI-Aktualität'),
                    onPressed: () => _openAktualitaetsDialog(context, ref),
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
                          title: Text('KI-Aktualität prüfen'),
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
                    label: const Text('Vollbild-KI-Chat'),
                    onPressed: () => _oeffneKiChat(context),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: const Text('JSON-Import'),
                    onPressed: () => _importJson(context, ref),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Dubletten prüfen'),
                    onPressed: () => showDialog(
                      context: context,
                      useRootNavigator: true,
                      builder: (_) => const NormenDublettenDialog(),
                    ),
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
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: const Text('KI-Aktualität prüfen'),
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
          searchHint:
              'Tabelle filtern: Nummer, Titel, Gewerk, Zeitraum (z. B. 2015), Nachfolgenorm …',
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
                hint: const Text('Jeder Gültigkeits-Status'),
                items: const [
                  DropdownMenuItem<String?>(
                      value: null, child: Text('Alle (Aktuell & Historisch)')),
                  DropdownMenuItem<String?>(
                      value: 'aktuell',
                      child: Text('Nur aktuell gültige')),
                  DropdownMenuItem<String?>(
                      value: 'veraltet',
                      child: Text('Historisch / ersetzt (im Pool)')),
                  DropdownMenuItem<String?>(
                      value: '_unbekannt_oder_leer',
                      child: Text('Noch nicht geprüft')),
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
        // Direkt oben integrierter KI-Chat über den gesamten Normen-Pool
        const _TopInlineNormenKiChatBar(),
        if (filter.kiTrefferNummern != null &&
            filter.kiTrefferNummern!.isNotEmpty)
          Container(
            color: const Color(0xFFEDE9FE),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.filter_alt,
                    size: 16, color: Color(0xFF5B21B6)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tabelle gefiltert auf ${filter.kiTrefferNummern!.length} Normen aus dem KI-Chat: '
                    '${filter.kiTrefferNummern!.join(", ")}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5B21B6),
                    ),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.close, size: 15),
                  label: const Text('Alle Normen zeigen'),
                  onPressed: () => ref
                      .read(normenFilterProvider.notifier)
                      .update((f) =>
                          f.copyWith(kiTrefferNummernOverride: null)),
                ),
              ],
            ),
          ),
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
                    title: 'Keine passenden Normen gefunden');
              }
              final aktive = items.where((n) => n.aktiv).toList();
              final inaktive = items.where((n) => !n.aktiv).toList();
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _NormenTabelle(
                      label:
                          'Normen-Pool (${aktive.length} Dokumente · aktuelle & historische Fassungen mit Gültigkeitszeitraum)',
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
                            'Ausgeblendete / inaktive Normen (${inaktive.length})',
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

    if (standalonePortal) {
      return _StandaloneNormenPortalShell(child: content);
    }
    return content;
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

/// Eigenständige Hülle für `norm.aktenwerk.app` (`/norm-portal`), die
/// automatisch den Standard-Mandanten („Bauelemente-Experte") setzt und
/// sofort die Normen-Bibliothek aus Firestore synchronisiert.
class _StandaloneNormenPortalShell extends ConsumerStatefulWidget {
  const _StandaloneNormenPortalShell({required this.child});
  final Widget child;

  @override
  ConsumerState<_StandaloneNormenPortalShell> createState() =>
      _StandaloneNormenPortalShellState();
}

class _StandaloneNormenPortalShellState
    extends ConsumerState<_StandaloneNormenPortalShell> {
  String? _lastSyncedOrgId;
  bool _initialPullRunning = false;
  bool _autoSyncStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureOrgAndSync();
    });
  }

  Future<void> _ensureOrgAndSync() async {
    if (!mounted) return;
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    final orgs = ref.read(myOrgsProvider).valueOrNull;
    var currentOrgId = ref.read(currentOrgIdProvider).valueOrNull;

    if (orgs != null && orgs.isNotEmpty) {
      final hasValidOrg =
          currentOrgId != null && orgs.any((o) => o.id == currentOrgId);
      if (!hasValidOrg) {
        final bevorzugteOrg = orgs.firstWhere(
          (o) => o.id != 'demo',
          orElse: () => orgs.first,
        );
        currentOrgId = bevorzugteOrg.id;
        await ref.read(currentOrgIdProvider.notifier).set(currentOrgId);
      }
    }

    if (currentOrgId != null && currentOrgId != _lastSyncedOrgId) {
      _lastSyncedOrgId = currentOrgId;
      await _pullNormenNow();
    }

    if (!_autoSyncStarted && mounted) {
      _autoSyncStarted = true;
      final aktiv = await AutoSyncService.istAktiviert();
      if (aktiv && mounted) {
        ref.read(autoSyncServiceProvider).start();
      }
    }
  }

  Future<void> _pullNormenNow() async {
    if (_initialPullRunning || !mounted) return;
    setState(() => _initialPullRunning = true);
    try {
      final sync = ref.read(syncServiceProvider);
      if (sync.enabled) {
        await sync.pullNormen();
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _initialPullRunning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateProvider, (_, _) => _ensureOrgAndSync());
    ref.listen(myOrgsProvider, (_, _) => _ensureOrgAndSync());
    ref.listen(currentOrgIdProvider, (_, _) => _ensureOrgAndSync());

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_user_outlined,
                      size: 16, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'Mandant:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slate500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const OrgSwitcher(),
                  const Spacer(),
                  if (_initialPullRunning) ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Synchronisiere Normen-Bibliothek …',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  const AutoSyncBadge(),
                ],
              ),
            ),
            Expanded(child: widget.child),
          ],
        ),
      ),
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
      case 0:
        return n.favorit ? 0 : 1;
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

    // ── Desktop: Resizable Table ─────────────────────────────────────────
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 24, top: 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: dimmed ? AppTheme.slate500 : AppTheme.slate900,
            ),
          ),
        ),
        _ResizableNormenTabelle(
          sortedItems: sorted,
          statusMap: statusMap,
          dimmed: dimmed,
          sortColumnIndex: _sortColumnIndex,
          sortAscending: _sortAscending,
          onSort: _onSort,
          onEdit: onEdit,
          onDelete: onDelete,
          onToggleFavorit: onToggleFavorit,
        ),
      ],
    );
  }
}

/// Formatierer für das Ausgabejahr im Format JJJJ:MM.
String formatAusgabeJahr(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '—';
  final trimmed = raw.trim();

  final matchWithMonth = RegExp(r'^(\d{4})[\-.:/](\d{1,2})$').firstMatch(trimmed);
  if (matchWithMonth != null) {
    final year = matchWithMonth.group(1);
    final month = matchWithMonth.group(2)!.padLeft(2, '0');
    return '$year:$month';
  }

  final matchYearOnly = RegExp(r'^(\d{4})$').firstMatch(trimmed);
  if (matchYearOnly != null) {
    final year = matchYearOnly.group(1);
    return '$year:01';
  }

  final matchMonthYear = RegExp(r'^(\d{1,2})[\-.:/](\d{4})$').firstMatch(trimmed);
  if (matchMonthYear != null) {
    final month = matchMonthYear.group(1)!.padLeft(2, '0');
    final year = matchMonthYear.group(2);
    return '$year:$month';
  }

  return trimmed;
}

// ── Desktop: Resizable Custom Table ──────────────────────────────────
class _ResizableNormenTabelle extends StatefulWidget {
  const _ResizableNormenTabelle({
    required this.sortedItems,
    required this.statusMap,
    required this.dimmed,
    required this.sortColumnIndex,
    required this.sortAscending,
    required this.onSort,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleFavorit,
  });

  final List<NormenData> sortedItems;
  final Map<int, NormIndexStatus> statusMap;
  final bool dimmed;
  final int sortColumnIndex;
  final bool sortAscending;
  final void Function(int, bool) onSort;
  final void Function(NormenData) onEdit;
  final void Function(NormenData) onDelete;
  final void Function(NormenData) onToggleFavorit;

  @override
  State<_ResizableNormenTabelle> createState() => _ResizableNormenTabelleState();
}

class _ResizableNormenTabelleState extends State<_ResizableNormenTabelle> {
  // Vom Nutzer manuell veränderte Spaltenbreiten merken
  final Map<int, bool> _userResized = {};
  final _hScrollCtrl = ScrollController();

  @override
  void dispose() {
    _hScrollCtrl.dispose();
    super.dispose();
  }

  // Spaltenbreiten (Standard an Inhalt/Text angepasst)
  final Map<int, double> _colWidths = {
    0: 44.0,   // Fav
    1: 170.0,  // Nummer
    2: 100.0,  // Ausgabe
    3: 460.0,  // Titel (dynamisch erweitert)
    4: 150.0,  // Gewerk
    5: 130.0,  // Kategorie
    6: 215.0,  // Aktualität & Zeitraum (Von – Bis)
    7: 115.0,  // Indexiert
    8: 48.0,   // PDF
    9: 44.0,   // Edit
    10: 44.0,  // Delete
  };

  Widget _buildHeaderCell(int index, String label, {bool sortable = true}) {
    final isSorted = widget.sortColumnIndex == index;
    final width = _colWidths[index] ?? 100.0;
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: sortable
                  ? () => widget.onSort(
                        index,
                        isSorted ? !widget.sortAscending : true,
                      )
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isSorted ? theme.colorScheme.primary : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSorted) ...[
                      const SizedBox(width: 4),
                      Icon(
                        widget.sortAscending
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: (details) {
              setState(() {
                _userResized[index] = true;
                final newW = (width + details.delta.dx).clamp(40.0, 1200.0);
                _colWidths[index] = newW;
              });
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: Container(
                width: 8,
                height: 24,
                color: Colors.transparent,
                child: Center(
                  child: Container(
                    width: 2,
                    height: 14,
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          // Titel-Spalte (index 3) dynamisch strecken, wenn der Nutzer sie nicht manuell skaliert hat
          if (_userResized[3] != true) {
            double fixedSum = 0;
            _colWidths.forEach((k, v) {
              if (k != 3) fixedSum += v;
            });
            final avail = totalWidth - fixedSum - 16;
            if (avail > 360.0) {
              _colWidths[3] = avail;
            }
          }

          return Card(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Opacity(
              opacity: widget.dimmed ? 0.72 : 1.0,
              child: SingleChildScrollView(
                controller: _hScrollCtrl,
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Sticky Header Row (Fixierter Tabellenkopf)
                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                      ),
                      child: Row(
                        children: [
                          _buildHeaderCell(0, '★', sortable: true),
                          _buildHeaderCell(1, 'Nummer'),
                          _buildHeaderCell(2, 'Ausgabe'),
                          _buildHeaderCell(3, 'Titel'),
                          _buildHeaderCell(4, 'Gewerk'),
                          _buildHeaderCell(5, 'Kategorie'),
                          _buildHeaderCell(6, 'Aktualität & Zeitraum'),
                          _buildHeaderCell(7, 'Indexiert'),
                          _buildHeaderCell(8, 'PDF', sortable: false),
                          _buildHeaderCell(9, '', sortable: false),
                          _buildHeaderCell(10, '', sortable: false),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Vertical Scrollable Data Rows
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: (MediaQuery.sizeOf(context).height - 230)
                            .clamp(650.0, 1600.0),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final n in widget.sortedItems)
                              InkWell(
                                onTap: () => widget.onEdit(n),
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                          color: theme.colorScheme.outlineVariant
                                              .withValues(alpha: 0.4),
                                          width: 0.5),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: _colWidths[0],
                                        child: IconButton(
                                          iconSize: 18,
                                          tooltip: n.favorit
                                              ? 'Favorit entfernen'
                                              : 'Als Favorit markieren',
                                          icon: Icon(
                                            n.favorit
                                                ? Icons.star
                                                : Icons.star_outline,
                                            color: n.favorit
                                                ? theme.colorScheme.tertiary
                                                : null,
                                          ),
                                          onPressed: () => widget.onToggleFavorit(n),
                                        ),
                                      ),
                                      SizedBox(
                                        width: _colWidths[1],
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          child: Text(
                                            n.nummer,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontFeatures: [
                                                FontFeature.tabularFigures()
                                              ],
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: _colWidths[2],
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          child: Text(
                                            formatAusgabeJahr(n.ausgabe),
                                            style: const TextStyle(
                                              fontFeatures: [
                                                FontFeature.tabularFigures()
                                              ],
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: _colWidths[3],
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 8),
                                          child: Text(
                                            n.titel ?? '—',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: _colWidths[4],
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          child: Text(
                                            n.gewerk ?? '—',
                                            style: const TextStyle(fontSize: 12),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: _colWidths[5],
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          child: _KategorieBadge(
                                              kategorie: n.kategorie),
                                        ),
                                      ),
                                      SizedBox(
                                        width: _colWidths[6],
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          child: _AktualitaetsPill(norm: n),
                                        ),
                                      ),
                                      SizedBox(
                                        width: _colWidths[7],
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          child: _IndexStatusZelle(
                                              status: widget.statusMap[n.id] ??
                                                  NormIndexStatus.unbekannt),
                                        ),
                                      ),
                                      SizedBox(
                                        width: _colWidths[8],
                                        child: _PdfCell(
                                          norm: n,
                                          status: widget.statusMap[n.id] ??
                                              NormIndexStatus.unbekannt,
                                        ),
                                      ),
                                      SizedBox(
                                        width: _colWidths[9],
                                        child: IconButton(
                                          tooltip: 'Bearbeiten',
                                          icon: const Icon(Icons.edit_outlined,
                                              size: 18),
                                          onPressed: () => widget.onEdit(n),
                                        ),
                                      ),
                                      SizedBox(
                                        width: _colWidths[10],
                                        child: IconButton(
                                          tooltip: 'Löschen',
                                          icon: const Icon(Icons.delete_outline,
                                              size: 18),
                                          onPressed: () => widget.onDelete(n),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
    final info = NormGueltigkeitInfo.fromNorm(norm);
    final zeitraum = info.zeitraumLabel(status);
    final (color, label, icon) = switch (status) {
      'aktuell' => (
          const Color(0xFF16A34A),
          'aktuell',
          Icons.check_circle
        ),
      'veraltet' => (
          const Color(0xFFD97706),
          'historisch',
          Icons.history
        ),
      'unbekannt' => (
          const Color(0xFFEAB308),
          'prüfen',
          Icons.help
        ),
      _ => (AppTheme.slate400, 'ungeprüft', Icons.radio_button_unchecked),
    };
    final geprueft = norm.aktualitaetGeprueftAm;
    final tooltipParts = <String>[
      if (status == 'aktuell')
        'Status: Aktuell gültige Ausgabe ($zeitraum)'
      else if (status == 'veraltet')
        'Status: Historische / ersetzte Fassung im Pool ($zeitraum)'
      else
        'Status: Noch nicht geprüft ($zeitraum)',
      if (info.ersetztDurch != null && info.ersetztDurch!.isNotEmpty)
        'Ersetzt durch: ${info.ersetztDurch}',
      if (geprueft != null)
        'Zuletzt geprüft: ${NormenScreen._dateFmt.format(geprueft)}',
      if (norm.aktualitaetNotiz != null &&
          norm.aktualitaetNotiz!.trim().isNotEmpty)
        norm.aktualitaetNotiz!,
    ];

    return Tooltip(
      message: tooltipParts.join('\n'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13.5, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  zeitraum != '—' ? '$label · $zeitraum' : label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          if (info.ersetztDurch != null && info.ersetztDurch!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                '↳ ${info.ersetztDurch}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppTheme.slate500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PdfCell extends StatelessWidget {
  const _PdfCell({required this.norm, required this.status});
  final NormenData norm;
  final NormIndexStatus status;
  @override
  Widget build(BuildContext context) {
    final url = norm.pdfStorageUrl;
    if (url == null || url.isEmpty) {
      return const SizedBox.shrink();
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip:
              '${norm.pdfDateiname ?? 'PDF öffnen'}\nIndexierung: ${status.label}',
          icon: const Icon(Icons.picture_as_pdf,
              size: 20, color: AwTokens.red),
          onPressed: () async {
            var target = url.trim();
            if (!target.startsWith(RegExp(r'https?://', caseSensitive: false))) {
              target = 'https://$target';
            }
            final uri = Uri.tryParse(target);
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

/// ------------- Direkt oben eingebetteter KI-Chat über alle Normen -------------

class _TopInlineNormenKiChatBar extends ConsumerStatefulWidget {
  const _TopInlineNormenKiChatBar();

  @override
  ConsumerState<_TopInlineNormenKiChatBar> createState() =>
      _TopInlineNormenKiChatBarState();
}

class _TopInlineNormenKiChatBarState
    extends ConsumerState<_TopInlineNormenKiChatBar> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  bool _autoFilterTable = true;
  bool _answerExpanded = true;
  String? _lastQuestion;
  NormChatAntwort? _lastAnswer;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _lastQuestion = q;
      _error = null;
      _answerExpanded = true;
    });

    try {
      final rag = ref.read(normRagServiceProvider);
      final res = await rag.frage(
        frage: q,
        fastMode: false,
      );
      if (!mounted) return;
      final nummern = res.quellen
          .map((s) => s.nummer.trim())
          .where((s) => s.isNotEmpty)
          .toSet();
      setState(() {
        _lastAnswer = res;
        _loading = false;
      });
      if (_autoFilterTable && nummern.isNotEmpty) {
        ref
            .read(normenFilterProvider.notifier)
            .update((f) => f.copyWith(kiTrefferNummernOverride: nummern));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'KI-Abfrage fehlgeschlagen: $e';
        _loading = false;
      });
    }
  }

  Future<void> _openQuelle(NormChatQuelle q) async {
    final rawUrl = q.storageUrl ?? '';
    if (rawUrl.isEmpty) return;
    final pageSuffix = q.page > 0 ? '#page=${q.page}' : '';
    final uri = Uri.tryParse('$rawUrl$pageSuffix');
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final quellenNummern = (_lastAnswer?.quellen ?? const [])
        .map((s) => s.nummer.trim())
        .where((s) => s.isNotEmpty)
        .toSet();

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 18, color: Color(0xFF5B21B6)),
              const SizedBox(width: 8),
              const Text(
                'KI-Chat über alle Normen:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF5B21B6),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  onSubmitted: (_) => _ask(),
                  decoration: InputDecoration(
                    hintText:
                        'Frage an den gesamten Normen-Pool stellen (z. B. „Welche Normen gelten für Geländerhöhe & Feuerverzinkung?") …',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    suffixIcon: _ctrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _ctrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: _loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send, size: 15),
                label: Text(_loading ? 'Suche…' : 'KI fragen'),
                onPressed: _loading ? null : _ask,
              ),
              const SizedBox(width: 10),
              Tooltip(
                message:
                    'Wenn aktiv, wird die Normen-Tabelle unten automatisch auf die von der KI gefundenen Normen gefiltert.',
                child: FilterChip(
                  selected: _autoFilterTable,
                  label: const Text('Tabelle filtern',
                      style: TextStyle(fontSize: 11.5)),
                  onSelected: (v) {
                    setState(() => _autoFilterTable = v);
                    if (v && quellenNummern.isNotEmpty) {
                      ref.read(normenFilterProvider.notifier).update(
                            (f) => f.copyWith(
                                kiTrefferNummernOverride: quellenNummern),
                          );
                    } else if (!v) {
                      ref.read(normenFilterProvider.notifier).update(
                            (f) =>
                                f.copyWith(kiTrefferNummernOverride: null),
                          );
                    }
                  },
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(fontSize: 12, color: AwTokens.red)),
          ],
          if (_lastAnswer != null) ...[
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF5B21B6).withValues(alpha: 0.25)),
              ),
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.psychology_alt_outlined,
                          size: 16, color: Color(0xFF5B21B6)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'KI-Antwort zu: „${_lastQuestion ?? ""}"',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF5B21B6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (quellenNummern.isNotEmpty)
                        TextButton.icon(
                          icon: const Icon(Icons.filter_list, size: 15),
                          label: Text(
                            'Tabelle auf ${quellenNummern.length} Treffer filtern',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          onPressed: () => ref
                              .read(normenFilterProvider.notifier)
                              .update((f) => f.copyWith(
                                  kiTrefferNummernOverride: quellenNummern)),
                        ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip:
                            _answerExpanded ? 'Antwort einklappen' : 'Antwort ausklappen',
                        icon: Icon(
                          _answerExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18,
                        ),
                        onPressed: () => setState(
                            () => _answerExpanded = !_answerExpanded),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'KI-Antwort schließen & Filter zurücksetzen',
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          setState(() {
                            _lastAnswer = null;
                            _lastQuestion = null;
                          });
                          ref.read(normenFilterProvider.notifier).update(
                                (f) => f.copyWith(
                                    kiTrefferNummernOverride: null),
                              );
                        },
                      ),
                    ],
                  ),
                  if (_answerExpanded) ...[
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _lastAnswer!.antwort,
                          style:
                              const TextStyle(fontSize: 13, height: 1.45),
                        ),
                      ),
                    ),
                    if (_lastAnswer!.quellen.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final q in _lastAnswer!.quellen)
                            InkWell(
                              onTap: () => _openQuelle(q),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                  border:
                                      Border.all(color: AppTheme.slate200),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.picture_as_pdf,
                                        size: 13, color: AwTokens.red),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${q.nummer}${q.page > 0 ? " · S. ${q.page}" : ""}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// ------------- KI-gestützter Aktualitäts- & Gültigkeitszeitraum-Dialog -------------

class _AktualitaetsDialog extends ConsumerStatefulWidget {
  const _AktualitaetsDialog();
  @override
  ConsumerState<_AktualitaetsDialog> createState() =>
      _AktualitaetsDialogState();
}

class _AktualitaetsDialogState extends ConsumerState<_AktualitaetsDialog> {
  bool _batchRunning = false;
  bool _cancelRequested = false;
  int _batchDone = 0;
  int _batchTotal = 0;
  String _filterStatus = 'alle'; // 'alle' | 'ungeprueft' | 'aktuell' | 'veraltet'
  String _searchQuery = '';
  final Set<int> _singleCheckingIds = {};
  String? _statusMsg;

  Future<void> _startKiBatchCheck({
    required List<NormenData> zuPruefen,
    required List<NormenData> kompletterPool,
  }) async {
    if (zuPruefen.isEmpty || _batchRunning) return;
    setState(() {
      _batchRunning = true;
      _cancelRequested = false;
      _batchDone = 0;
      _batchTotal = zuPruefen.length;
      _statusMsg = null;
    });

    final service = ref.read(normenAktualitaetKiServiceProvider);
    final normById = {for (final n in kompletterPool) n.id: n};
    const batchSize = 15;
    var aktualisiert = 0;

    try {
      for (var i = 0; i < zuPruefen.length; i += batchSize) {
        if (_cancelRequested || !mounted) break;
        final chunk = zuPruefen.skip(i).take(batchSize).toList();
        final ergebnisse = await service.pruefeBatch(
          chunk,
          kompletterPool: kompletterPool,
        );
        if (!mounted) break;
        await service.speichereErgebnisse(ergebnisse, normById);
        aktualisiert += ergebnisse.length;
        setState(() {
          _batchDone = (i + chunk.length).clamp(0, zuPruefen.length);
        });
      }
      if (!mounted) return;
      setState(() {
        _batchRunning = false;
        _statusMsg = _cancelRequested
            ? 'Prüfung gestoppt ($aktualisiert Normen aktualisiert).'
            : 'KI-Prüfung abgeschlossen: $aktualisiert Normen mit Gültigkeitszeitraum (Von – Bis) aktualisiert.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _batchRunning = false;
        _statusMsg = 'Fehler bei der KI-Prüfung: $e';
      });
    }
  }

  Future<void> _pruefeEinzeln(
    NormenData norm,
    List<NormenData> kompletterPool,
  ) async {
    if (_singleCheckingIds.contains(norm.id)) return;
    setState(() => _singleCheckingIds.add(norm.id));
    try {
      final service = ref.read(normenAktualitaetKiServiceProvider);
      final ergebnisse = await service.pruefeBatch(
        [norm],
        kompletterPool: kompletterPool,
      );
      await service.speichereErgebnisse(
        ergebnisse,
        {norm.id: norm},
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('KI-Prüfung fehlgeschlagen: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _singleCheckingIds.remove(norm.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(normenListProvider);
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 740),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.fact_check_outlined, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Globale KI-Aktualitätsprüfung & Gültigkeitszeiträume (Von – Bis)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'Alle Normen (auch historische/ersetzte) bleiben aktiv im Pool, erhalten aber ihren exakten Gültigkeitszeitraum und ihre Nachfolgenorm.',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.slate500),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: _batchRunning
                        ? null
                        : () =>
                            Navigator.of(context, rootNavigator: true).pop(),
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
                data: (items) {
                  final aktive = items.where((n) => n.aktiv).toList();
                  final ungepruefte = aktive
                      .where((n) =>
                          n.aktualitaetStatus == null ||
                          n.aktualitaetStatus == 'unbekannt')
                      .toList();
                  final aktuelleCount = aktive
                      .where((n) => n.aktualitaetStatus == 'aktuell')
                      .length;
                  final historischeCount = aktive
                      .where((n) => n.aktualitaetStatus == 'veraltet')
                      .length;

                  final filtered = aktive.where((n) {
                    if (_filterStatus == 'ungeprueft' &&
                        n.aktualitaetStatus != null &&
                        n.aktualitaetStatus != 'unbekannt') {
                      return false;
                    }
                    if (_filterStatus == 'aktuell' &&
                        n.aktualitaetStatus != 'aktuell') {
                      return false;
                    }
                    if (_filterStatus == 'veraltet' &&
                        n.aktualitaetStatus != 'veraltet') {
                      return false;
                    }
                    if (_searchQuery.trim().isNotEmpty) {
                      final q = _searchQuery.trim().toLowerCase();
                      final info = NormGueltigkeitInfo.fromNorm(n);
                      final hay =
                          '${n.nummer} ${n.ausgabe ?? ""} ${n.titel ?? ""} ${info.gueltigVon ?? ""} ${info.gueltigBis ?? ""} ${info.ersetztDurch ?? ""}'
                              .toLowerCase();
                      if (!hay.contains(q)) return false;
                    }
                    return true;
                  }).toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        color: scheme.surfaceContainerLowest,
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                FilledButton.icon(
                                  icon: const Icon(Icons.auto_awesome,
                                      size: 16),
                                  label: Text(
                                    'Ungeprüfte KI-prüfen (${ungepruefte.length})',
                                  ),
                                  onPressed:
                                      _batchRunning || ungepruefte.isEmpty
                                          ? null
                                          : () => _startKiBatchCheck(
                                                zuPruefen: ungepruefte,
                                                kompletterPool: aktive,
                                              ),
                                ),
                                OutlinedButton.icon(
                                  icon: const Icon(
                                      Icons.playlist_add_check,
                                      size: 18),
                                  label: Text(
                                    'Gesamten Pool KI-prüfen (${aktive.length})',
                                  ),
                                  onPressed: _batchRunning || aktive.isEmpty
                                      ? null
                                      : () => _startKiBatchCheck(
                                            zuPruefen: aktive,
                                            kompletterPool: aktive,
                                          ),
                                ),
                                if (_batchRunning)
                                  TextButton.icon(
                                    icon: const Icon(Icons.stop_circle,
                                        color: AwTokens.red, size: 18),
                                    label: const Text('Stopp',
                                        style:
                                            TextStyle(color: AwTokens.red)),
                                    onPressed: () => setState(
                                        () => _cancelRequested = true),
                                  ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: Text('Alle (${aktive.length})'),
                                  selected: _filterStatus == 'alle',
                                  onSelected: (_) => setState(
                                      () => _filterStatus = 'alle'),
                                ),
                                ChoiceChip(
                                  label: Text(
                                      'Ungeprüft (${ungepruefte.length})'),
                                  selected: _filterStatus == 'ungeprueft',
                                  onSelected: (_) => setState(
                                      () => _filterStatus = 'ungeprueft'),
                                ),
                                ChoiceChip(
                                  label: Text('Aktuell ($aktuelleCount)'),
                                  selected: _filterStatus == 'aktuell',
                                  onSelected: (_) => setState(
                                      () => _filterStatus = 'aktuell'),
                                ),
                                ChoiceChip(
                                  label: Text(
                                      'Historisch im Pool ($historischeCount)'),
                                  selected: _filterStatus == 'veraltet',
                                  onSelected: (_) => setState(
                                      () => _filterStatus = 'veraltet'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search, size: 18),
                                hintText:
                                    'In Liste suchen (Normnummer, Titel, Jahr, Nachfolgenorm …)',
                                isDense: true,
                              ),
                              onChanged: (v) =>
                                  setState(() => _searchQuery = v),
                            ),
                            if (_batchRunning) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'KI ermittelt Gültigkeitszeiträume (Von – Bis) & Nachfolgenormen: '
                                      '$_batchDone / $_batchTotal …',
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                value: _batchTotal == 0
                                    ? 0
                                    : _batchDone / _batchTotal,
                              ),
                            ],
                            if (_statusMsg != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _statusMsg!,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF16A34A),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(
                                child: Text('Keine Normen für diesen Filter.'),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                                itemCount: filtered.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final n = filtered[i];
                                  return _AktualitaetsRow(
                                    norm: n,
                                    checking:
                                        _singleCheckingIds.contains(n.id),
                                    onKiCheck: () =>
                                        _pruefeEinzeln(n, aktive),
                                  );
                                },
                              ),
                      ),
                    ],
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
                    onPressed: _batchRunning
                        ? null
                        : () =>
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
  const _AktualitaetsRow({
    required this.norm,
    required this.checking,
    required this.onKiCheck,
  });
  final NormenData norm;
  final bool checking;
  final VoidCallback onKiCheck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = NormGueltigkeitInfo.fromNorm(norm);
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
                    if (norm.ausgabe != null &&
                        norm.ausgabe!.trim().isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.slate100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Ausgabe ${norm.ausgabe!}',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.slate700),
                        ),
                      ),
                    ],
                  ],
                ),
                if (norm.titel != null && norm.titel!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(norm.titel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                  ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _AktualitaetsPill(norm: norm),
                    if (norm.aktualitaetNotiz != null &&
                        norm.aktualitaetNotiz!.trim().isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          norm.aktualitaetNotiz!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.slate500),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: checking
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome, size: 15),
            label: const Text('KI-Check', style: TextStyle(fontSize: 12)),
            onPressed: checking ? null : onKiCheck,
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip:
                'Gültigkeitszeitraum (Von – Bis) & Nachfolgenorm bearbeiten',
            icon: const Icon(Icons.date_range_outlined, size: 20),
            onPressed: () =>
                _editGueltigkeit(context, ref, norm, info),
          ),
          IconButton(
            tooltip: 'Im DIN-Katalog suchen',
            icon: const Icon(Icons.travel_explore, size: 20),
            onPressed: () => _recherchieren(norm),
          ),
          IconButton(
            tooltip: 'Als aktuell gültig markieren',
            icon: const Icon(Icons.check_circle,
                size: 22, color: Color(0xFF16A34A)),
            onPressed: () => ref
                .read(normenRepositoryProvider)
                .setAktualitaet(norm.id, status: 'aktuell'),
          ),
          IconButton(
            tooltip: 'Als historisch / ersetzt markieren (bleibt im Pool)',
            icon: const Icon(Icons.history,
                size: 22, color: Color(0xFFD97706)),
            onPressed: () =>
                _editGueltigkeit(context, ref, norm, info, preselectStatus: 'veraltet'),
          ),
        ],
      ),
    );
  }

  Future<void> _recherchieren(NormenData norm) async {
    final q = Uri.encodeQueryComponent(norm.nummer);
    final url = Uri.parse('https://www.din.de/de/meta/suche/62730!search?query=$q');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _editGueltigkeit(
    BuildContext context,
    WidgetRef ref,
    NormenData n,
    NormGueltigkeitInfo info, {
    String? preselectStatus,
  }) async {
    var status = preselectStatus ?? n.aktualitaetStatus ?? 'aktuell';
    final vonCtrl =
        TextEditingController(text: info.gueltigVon ?? n.ausgabe ?? '');
    final bisCtrl = TextEditingController(
      text: info.gueltigBis ?? (status == 'aktuell' ? 'heute' : ''),
    );
    final ersetztCtrl =
        TextEditingController(text: info.ersetztDurch ?? '');
    final notizCtrl = TextEditingController(text: n.aktualitaetNotiz ?? '');
    final quelleCtrl = TextEditingController(text: n.aktualitaetQuelle ?? '');

    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Gültigkeitszeitraum: ${n.nummer}'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'aktuell',
                      icon: Icon(Icons.check_circle_outline, size: 16),
                      label: Text('Aktuell gültig'),
                    ),
                    ButtonSegment(
                      value: 'veraltet',
                      icon: Icon(Icons.history, size: 16),
                      label: Text('Historisch (im Pool)'),
                    ),
                  ],
                  selected: {
                    status == 'veraltet' ? 'veraltet' : 'aktuell',
                  },
                  onSelectionChanged: (s) {
                    setDialogState(() {
                      status = s.first;
                      if (status == 'aktuell' && bisCtrl.text.trim().isEmpty) {
                        bisCtrl.text = 'heute';
                      }
                    });
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: vonCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Gültig von (JJJJ-MM)',
                          hintText: 'z. B. 2009-09',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: bisCtrl,
                        decoration: InputDecoration(
                          labelText: 'Gültig bis (JJJJ-MM)',
                          hintText: status == 'aktuell'
                              ? 'heute'
                              : 'z. B. 2022-12',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ersetztCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ersetzt durch (Nachfolgenorm & Ausgabe)',
                    hintText: 'z. B. DIN EN ISO 1461 (2022-12)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notizCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notiz zur Historie / Übergangsfrist',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: quelleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Quelle / URL (optional)',
                  ),
                ),
              ],
            ),
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
      ),
    );
    if (ok == true) {
      final updatedInfo = NormGueltigkeitInfo(
        gueltigVon: vonCtrl.text.trim(),
        gueltigBis: bisCtrl.text.trim(),
        ersetztDurch: ersetztCtrl.text.trim(),
        ersetztVorgaenger: info.ersetztVorgaenger,
      );
      final mergedExtras = updatedInfo.mergeIntoExtras(n.extras);
      final db = ref.read(appDatabaseProvider);
      await (db.update(db.normen)..where((t) => t.id.equals(n.id))).write(
        NormenCompanion(
          aktualitaetStatus: Value(status),
          aktualitaetGeprueftAm: Value(DateTime.now()),
          aktualitaetNotiz: Value(
              notizCtrl.text.trim().isEmpty ? null : notizCtrl.text.trim()),
          aktualitaetQuelle: Value(
              quelleCtrl.text.trim().isEmpty ? null : quelleCtrl.text.trim()),
          extras: Value(mergedExtras),
          aktiv: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
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
  late final _gueltigVonCtrl = TextEditingController(
    text: widget.norm != null
        ? (NormGueltigkeitInfo.fromNorm(widget.norm!).gueltigVon ?? '')
        : '',
  );
  late final _gueltigBisCtrl = TextEditingController(
    text: widget.norm != null
        ? (NormGueltigkeitInfo.fromNorm(widget.norm!).gueltigBis ?? '')
        : '',
  );
  late final _ersetztDurchCtrl = TextEditingController(
    text: widget.norm != null
        ? (NormGueltigkeitInfo.fromNorm(widget.norm!).ersetztDurch ?? '')
        : '',
  );

  String _art = 'DIN-Norm';
  String _kategorie = 'Norm';
  String _relevanz = 'referenz';
  String? _aktStatus;
  DateTime? _aktGeprueftAm;
  bool _aktiv = true;
  bool _favorit = false;
  bool _saving = false;
  bool _uploading = false;
  bool _kiChecking = false;

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
      _gueltigVonCtrl, _gueltigBisCtrl, _ersetztDurchCtrl,
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

  Future<void> _kiAktualitaetCheckForm() async {
    if (_nr.text.trim().isEmpty || _kiChecking) return;
    setState(() => _kiChecking = true);
    try {
      final pool = ref.read(normenListProvider).valueOrNull ?? const [];
      final tempNorm = NormenData(
        id: widget.norm?.id ?? -1,
        auftragId: null,
        nummer: _nr.text.trim(),
        titel: _titel.text.trim(),
        ausgabe: _ausgabe.text.trim(),
        kategorie: _kategorie,
        art: _art,
        herausgeber: _herausgeber.text.trim(),
        relevanz: _relevanz,
        zusammenfassung: null,
        zitat: null,
        beschreibung: null,
        notiz: null,
        gewerk: _gewerk.text.trim(),
        pdfPfad: null,
        pdfStorageUrl: _pdfStorageUrl,
        pdfMimeType: _pdfMimeType,
        pdfGroesse: _pdfGroesse,
        pdfDateiname: _pdfDateiname,
        aktiv: true,
        favorit: _favorit,
        aktualitaetStatus: _aktStatus,
        aktualitaetGeprueftAm: _aktGeprueftAm,
        aktualitaetQuelle: _aktQuelle.text.trim(),
        aktualitaetNotiz: _aktNotiz.text.trim(),
        extras: widget.norm?.extras,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final res = await ref
          .read(normenAktualitaetKiServiceProvider)
          .pruefeBatch([tempNorm], kompletterPool: pool);
      if (!mounted || res.isEmpty) return;
      final r = res.first;
      setState(() {
        _aktStatus = r.status;
        _aktGeprueftAm = DateTime.now();
        if (r.gueltigVon.isNotEmpty) _gueltigVonCtrl.text = r.gueltigVon;
        _gueltigBisCtrl.text =
            r.status == 'aktuell' ? 'heute' : r.gueltigBis;
        _ersetztDurchCtrl.text =
            r.status == 'aktuell' ? '' : r.ersetztDurch;
        if (r.notiz.isNotEmpty) _aktNotiz.text = r.notiz;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('KI-Aktualitätsprüfung fehlgeschlagen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _kiChecking = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final prevInfo = widget.norm != null
        ? NormGueltigkeitInfo.fromNorm(widget.norm!)
        : const NormGueltigkeitInfo();
    final updatedInfo = NormGueltigkeitInfo(
      gueltigVon: _gueltigVonCtrl.text.trim().isNotEmpty
          ? _gueltigVonCtrl.text.trim()
          : _ausgabe.text.trim(),
      gueltigBis: _gueltigBisCtrl.text.trim(),
      ersetztDurch: _ersetztDurchCtrl.text.trim(),
      ersetztVorgaenger: prevInfo.ersetztVorgaenger,
    );
    final mergedExtras = updatedInfo.mergeIntoExtras(widget.norm?.extras);

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
      extras: Value(mergedExtras),
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
    final url = Uri.parse('https://www.din.de/de/meta/suche/62730!search?query=$q');
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
                  if (s == 'aktuell' && _gueltigBisCtrl.text.trim().isEmpty) {
                    _gueltigBisCtrl.text = 'heute';
                  }
                }),
                gueltigVonCtrl: _gueltigVonCtrl,
                gueltigBisCtrl: _gueltigBisCtrl,
                ersetztDurchCtrl: _ersetztDurchCtrl,
                quelleCtrl: _aktQuelle,
                notizCtrl: _aktNotiz,
                onRecherche: _recherchieren,
                onKiCheck: _kiAktualitaetCheckForm,
                kiChecking: _kiChecking,
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
                onAdoptZusammenfassung: (text) {
                  setState(() => _zusammenfassung.text = text);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'KI-Zusammenfassung in das Feld „Zusammenfassung" übernommen.'),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(children: [
                Switch(
                    value: _aktiv,
                    onChanged: (v) => setState(() => _aktiv = v)),
                const SizedBox(width: 6),
                const Text('Im Normen-Pool aktiv'),
                const SizedBox(width: 20),
                Switch(
                    value: _favorit,
                    onChanged: (v) => setState(() => _favorit = v)),
                const SizedBox(width: 6),
                const Text('Favorit'),
                const Spacer(),
                if (!_aktiv)
                  Text('→ erscheint in Tabelle der ausgeblendeten Normen',
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

/// ------------- Aktualitäts- & Gültigkeitszeitraum-Section -------------

class _AktualitaetsSection extends StatelessWidget {
  const _AktualitaetsSection({
    required this.status,
    required this.geprueftAm,
    required this.onStatusChanged,
    required this.gueltigVonCtrl,
    required this.gueltigBisCtrl,
    required this.ersetztDurchCtrl,
    required this.quelleCtrl,
    required this.notizCtrl,
    required this.onRecherche,
    required this.onKiCheck,
    required this.kiChecking,
  });
  final String? status;
  final DateTime? geprueftAm;
  final ValueChanged<String> onStatusChanged;
  final TextEditingController gueltigVonCtrl;
  final TextEditingController gueltigBisCtrl;
  final TextEditingController ersetztDurchCtrl;
  final TextEditingController quelleCtrl;
  final TextEditingController notizCtrl;
  final VoidCallback onRecherche;
  final VoidCallback onKiCheck;
  final bool kiChecking;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy', 'de');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Aktualitäts-Status & Gültigkeitszeitraum (Von – Bis)',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _StatusButton(
              label: 'aktuell',
              color: const Color(0xFF16A34A),
              icon: Icons.check_circle,
              active: status == 'aktuell',
              onPressed: () => onStatusChanged('aktuell'),
            ),
            _StatusButton(
              label: 'historisch / ersetzt (im Pool)',
              color: const Color(0xFFD97706),
              icon: Icons.history,
              active: status == 'veraltet',
              onPressed: () => onStatusChanged('veraltet'),
            ),
            _StatusButton(
              label: 'unbekannt',
              color: const Color(0xFFEAB308),
              icon: Icons.help,
              active: status == 'unbekannt',
              onPressed: () => onStatusChanged('unbekannt'),
            ),
            FilledButton.tonalIcon(
              icon: kiChecking
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 16),
              label: Text(kiChecking ? 'Prüfe…' : 'KI-Aktualitäts-Check'),
              onPressed: kiChecking ? null : onKiCheck,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.travel_explore, size: 16),
              label: const Text('DIN-Katalog'),
              onPressed: onRecherche,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (geprueftAm != null)
          Text('Zuletzt geprüft: ${fmt.format(geprueftAm!)}',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.slate500)),
        const SizedBox(height: 12),
        Row2(
          left: LabeledField(
            'Gültig von (JJJJ-MM)',
            TextFormField(
              controller: gueltigVonCtrl,
              decoration: const InputDecoration(
                hintText: 'z. B. 2009-09',
              ),
            ),
          ),
          right: LabeledField(
            'Gültig bis (JJJJ-MM oder heute)',
            TextFormField(
              controller: gueltigBisCtrl,
              decoration: const InputDecoration(
                hintText: 'z. B. 2022-12 oder heute',
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        LabeledField(
          'Ersetzt durch (Nachfolgenorm & Ausgabe)',
          TextFormField(
            controller: ersetztDurchCtrl,
            decoration: const InputDecoration(
              hintText: 'z. B. DIN EN ISO 1461 (2022-12)',
            ),
          ),
        ),
        const SizedBox(height: 10),
        LabeledField(
            'Quelle / URL',
            TextFormField(
                controller: quelleCtrl,
                decoration: const InputDecoration(
                    hintText: 'https://www.beuth.de/…'))),
        const SizedBox(height: 10),
        LabeledField(
            'Notiz zur Aktualität / Historie',
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
                    var target = storageUrl!.trim();
                    if (!target.startsWith(RegExp(r'https?://', caseSensitive: false))) {
                      target = 'https://$target';
                    }
                    final uri = Uri.tryParse(target);
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

/// ------------- KI-Section (Zusammenfassung + Chat über NormRagService) -------------

class _KiSection extends ConsumerStatefulWidget {
  const _KiSection({
    required this.pdfUrl,
    required this.nummer,
    required this.titel,
    this.onAdoptZusammenfassung,
  });
  final String? pdfUrl;
  final String nummer;
  final String titel;
  final ValueChanged<String>? onAdoptZusammenfassung;

  @override
  ConsumerState<_KiSection> createState() => _KiSectionState();
}

class _KiSectionState extends ConsumerState<_KiSection> {
  String? _zusammenfassung;
  String? _zfError;
  bool _zfLoading = false;

  bool get _hasPdf => widget.pdfUrl != null && widget.pdfUrl!.isNotEmpty;

  Future<void> _generiereZusammenfassung() async {
    if (!_hasPdf) return;
    setState(() {
      _zfLoading = true;
      _zusammenfassung = null;
      _zfError = null;
    });
    try {
      final rag = ref.read(normRagServiceProvider);
      final res = await rag.frage(
        frage:
            'Erstelle eine strukturierte, fachlich präzise Zusammenfassung der Norm '
            '„${widget.nummer}${widget.titel.isNotEmpty ? " — ${widget.titel}" : ""}" '
            'für einen Bausachverständigen (1. Anwendungsbereich, 2. Wesentliche Anforderungen, '
            'Grenzwerte & Toleranzen, 3. Prüf- und Nachweisverfahren). Nenne Abschnitte und Seiten.',
        fastMode: false,
      );
      if (!mounted) return;
      setState(() {
        _zfLoading = false;
        _zusammenfassung = res.antwort.trim();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _zfLoading = false;
        _zfError = 'Fehler bei der KI-Zusammenfassung: $e';
      });
    }
  }

  Future<void> _frageStellen() async {
    if (!_hasPdf) return;
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => _KiChatDialog(
        nummer: widget.nummer,
        titel: widget.titel,
        pdfUrl: widget.pdfUrl,
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
              child: const Text('Vertex AI · RAG',
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
        if (_zfError != null) ...[
          const SizedBox(height: 10),
          Text(_zfError!,
              style: const TextStyle(fontSize: 12, color: AwTokens.red)),
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
                    Text('KI-Zusammenfassung',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slate500)),
                    const Spacer(),
                    if (widget.onAdoptZusammenfassung != null)
                      TextButton.icon(
                        icon: const Icon(Icons.download_done, size: 15),
                        label: const Text('In Zusammenfassung übernehmen',
                            style: TextStyle(fontSize: 11.5)),
                        onPressed: () =>
                            widget.onAdoptZusammenfassung!(_zusammenfassung!),
                      ),
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

/// KI-Chat-Dialog für eine einzelne Norm (echte Vertex-AI-RAG-Anbindung).
class _KiChatDialog extends ConsumerStatefulWidget {
  const _KiChatDialog({
    required this.nummer,
    required this.titel,
    this.pdfUrl,
  });
  final String nummer;
  final String titel;
  final String? pdfUrl;

  @override
  ConsumerState<_KiChatDialog> createState() => _KiChatDialogState();
}

class _KiChatMessage {
  final String role; // 'user' | 'assistant'
  final String text;
  final List<NormChatQuelle> quellen;
  const _KiChatMessage(
    this.role,
    this.text, {
    this.quellen = const [],
  });
}

class _KiChatDialogState extends ConsumerState<_KiChatDialog> {
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
          'Stelle mir eine Frage zu diesem Dokument — ich durchsuche den hinterlegten '
          'Volltext und zitiere dir die genauen Abschnitte und Seiten.',
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

    try {
      final rag = ref.read(normRagServiceProvider);
      final historie = _messages
          .skip(1) // Begrüßung überspringen
          .take(_messages.length - 2)
          .map(
            (m) => NormChatNachricht(
              rolle: m.role,
              text: m.text,
              zeit: DateTime.now(),
            ),
          )
          .toList();

      final normContextPrefix =
          '[Fokus-Norm: ${widget.nummer}${widget.titel.isNotEmpty ? " — ${widget.titel}" : ""}]\n';
      final res = await rag.frage(
        frage: '$normContextPrefix$text',
        historie: historie,
        fastMode: false,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(_KiChatMessage(
          'assistant',
          res.antwort.trim().isNotEmpty
              ? res.antwort.trim()
              : 'Keine passende Textstelle gefunden.',
          quellen: res.quellen,
        ));
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_KiChatMessage(
          'assistant',
          'Fehler bei der KI-Abfrage: $e',
        ));
        _sending = false;
      });
    }
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

  Future<void> _openQuelle(NormChatQuelle q) async {
    final rawUrl = (q.storageUrl != null && q.storageUrl!.isNotEmpty)
        ? q.storageUrl!
        : (widget.pdfUrl ?? '');
    if (rawUrl.isEmpty) return;
    final pageSuffix = q.page > 0 ? '#page=${q.page}' : '';
    final uri = Uri.tryParse('$rawUrl$pageSuffix');
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text('Durchsuche Norm-PDF…',
                              style: TextStyle(fontSize: 12.5)),
                        ],
                      ),
                    );
                  }
                  final m = _messages[i];
                  return _ChatBubble(
                    role: m.role,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          m.text,
                          style: const TextStyle(
                              fontSize: 13, height: 1.45),
                        ),
                        if (m.quellen.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final q in m.quellen)
                                InkWell(
                                  onTap: () => _openQuelle(q),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: AppTheme.slate200),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.picture_as_pdf,
                                            size: 13, color: AwTokens.red),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${q.nummer}${q.page > 0 ? " · S. ${q.page}" : ""}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
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
  bool _warAmLaufen = false;

  @override
  void dispose() {
    _collapseTimer?.cancel();
    super.dispose();
  }

  void _toggle() {
    _collapseTimer?.cancel();
    setState(() => _expanded = !_expanded);
  }

  void _syncExpandState(NormIndexFortschritt f) {
    if (f.laeuft && !_warAmLaufen) {
      _warAmLaufen = true;
      _collapseTimer?.cancel();
      if (!_expanded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _expanded = true);
        });
      }
    } else if (!f.laeuft && _warAmLaufen) {
      _warAmLaufen = false;
      if (f.istFertig && _expanded) {
        _collapseTimer?.cancel();
        _collapseTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _expanded = false);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.normIdsMitPdf.isEmpty) return const SizedBox.shrink();
    final snapAsync = ref.watch(normPdfsSnapshotProvider);
    final snap = snapAsync.valueOrNull;
    if (snap == null) return const SizedBox.shrink();

    final f = berechneNormIndexFortschritt(snap, widget.normIdsMitPdf);
    _syncExpandState(f);

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
                  if (liste.isNotEmpty)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Fehlgeschlagene erneut versuchen'),
                      onPressed: () async {
                        Navigator.of(dialogCtx).pop();
                        final db = ref.read(appDatabaseProvider);
                        final alle = await db.select(db.normen).get();
                        final fehlerNormIds = liste
                            .map((e) => e.normId)
                            .whereType<int>()
                            .toSet();
                        final betroffeneNormen = alle
                            .where((n) => fehlerNormIds.contains(n.id))
                            .toList();
                        if (betroffeneNormen.isNotEmpty) {
                          await ref
                              .read(normRagServiceProvider)
                              .markiereAlleZurIndexierung(
                                betroffeneNormen,
                                onlyMissing: false,
                              );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${betroffeneNormen.length} fehlgeschlagene Normen erneut zur Indexierung angemeldet.',
                                ),
                              ),
                            );
                          }
                        }
                      },
                    ),
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
