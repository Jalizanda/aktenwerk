import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/aw_tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../data/sync/auth_service.dart';
import '../../../data/sync/storage_service.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/web/web_compat.dart' as web;

import 'normen_chat_dialog.dart';
import 'normen_import.dart';
import 'normen_pdf_bulk_dialog.dart';
import 'normen_repository.dart';

class NormenScreen extends ConsumerWidget {
  const NormenScreen({super.key});

  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(normenListProvider);
    final filter = ref.watch(normenFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.menu_book_outlined,
          title: 'Normen',
          subtitle: 'Normen-, Richtlinien- & Gesetze-Katalog',
          actions: [
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
    if (kIsWeb) {
      // Eigenes Fenster — Aktenwerk bleibt parallel bedienbar.
      web.openInNewWindow(
        '${web.appOrigin}/normen/chat',
        name: 'aktenwerk_ki_chat',
        features: 'popup=yes,width=900,height=760,resizable=yes,scrollbars=yes',
      );
      return;
    }
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => const NormenChatDialog(),
    );
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

class _NormenTabelle extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
                  headingRowColor: WidgetStateProperty.all(
                    Theme.of(context).colorScheme.surfaceContainerLow,
                  ),
                  columns: const [
                    DataColumn(label: SizedBox(width: 24, child: Text(''))),
                    DataColumn(label: Text('Nummer')),
                    DataColumn(label: Text('Ausgabe')),
                    DataColumn(label: Text('Titel')),
                    DataColumn(label: Text('Gewerk')),
                    DataColumn(label: Text('Kategorie')),
                    DataColumn(label: Text('Aktualität')),
                    DataColumn(label: SizedBox(width: 28, child: Text(''))),
                    DataColumn(label: SizedBox(width: 28, child: Text(''))),
                    DataColumn(label: SizedBox(width: 28, child: Text(''))),
                  ],
                  rows: [
                    for (final n in items)
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

class _PdfCell extends StatelessWidget {
  const _PdfCell({required this.norm});
  final NormenData norm;
  @override
  Widget build(BuildContext context) {
    final url = norm.pdfStorageUrl;
    if (url == null || url.isEmpty) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: norm.pdfDateiname ?? 'PDF öffnen',
      icon: const Icon(Icons.picture_as_pdf,
          size: 20, color: AwTokens.red),
      onPressed: () async {
        final uri = Uri.tryParse(url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
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
      await ref.read(normenRepositoryProvider).upsert(companion);
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
