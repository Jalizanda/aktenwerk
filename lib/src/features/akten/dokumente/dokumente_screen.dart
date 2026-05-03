import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../core/theme/aw_tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../data/sync/auth_service.dart';
import '../../../data/sync/storage_service.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'dokument_viewer.dart';
import 'dokumente_repository.dart';

/// Öffnet den Dokumente-Upload-Dialog von außerhalb des Dokumente-Screens
/// (z. B. aus dem Akten-Tab "Dokumente"). Optional kann eine Akte
/// vorbelegt werden — dann landet das hochgeladene Dokument direkt unter
/// dieser Akte.
Future<void> showDokumenteUploadDialog(
  BuildContext context, {
  int? auftragId,
}) async {
  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _UploadDialog(initialAuftragId: auftragId),
  );
}

class DokumenteScreen extends ConsumerWidget {
  const DokumenteScreen({super.key});
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dokumenteListProvider);
    final filter = ref.watch(dokumenteFilterProvider);
    final authAsync = ref.watch(authStateProvider);
    final loggedIn = authAsync.valueOrNull != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.folder_open_outlined,
          title: 'Dokumente',
          subtitle: loggedIn
              ? 'Beweisbeschlüsse, Schriftsätze, Belege — mit Cloud-Ablage'
              : 'Lokale Ablage (Login für Cloud-Upload erforderlich)',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Dokument hinzufügen'),
              onPressed: () => _openUploadDialog(context, ref),
            ),
          ],
          searchHint: 'Suche Titel, Kategorie, Beschreibung …',
          onSearchChanged: (v) => ref
              .read(dokumenteFilterProvider.notifier)
              .update((f) => f.copyWith(query: v)),
          filters: [
            SizedBox(
              width: 360,
              child: AuftragPickerField(
                auftragId: filter.auftragId,
                onChanged: (id) => ref
                    .read(dokumenteFilterProvider.notifier)
                    .update((f) => id == null
                        ? f.copyWith(clearAuftrag: true)
                        : f.copyWith(auftragId: id)),
                label: 'Auftrag-Filter',
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) => items.isEmpty
                ? const EmptyListState(
                    icon: Icons.folder_open_outlined,
                    title: 'Keine Dokumente',
                    hint: 'Klick oben auf "Dokumente hinzufügen".')
                : DataTableCard(
                    child: DataTable(
              showCheckboxColumn: false,
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      columns: const [
                        DataColumn(label: Text('Datum')),
                        DataColumn(label: Text('Titel / Datei')),
                        DataColumn(label: Text('Kategorie')),
                        DataColumn(label: Text('Auftrag')),
                        DataColumn(label: Text('Größe'), numeric: true),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final d in items)
                          _row(context, ref, d),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  DataRow _row(
      BuildContext context, WidgetRef ref, DokumentWithAuftrag d) {
    final url = d.dokument.storageUrl;
    final hasCloud = url != null && url.isNotEmpty;
    final hatBytes = (d.dokument.daten?.isNotEmpty ?? false);
    return DataRow(
      onSelectChanged: (hasCloud || hatBytes)
          ? (_) => openDokument(context, d.dokument)
          : (_) => _edit(context, ref, d),
      cells: [
        DataCell(Text(_dateFmt.format(d.dokument.datum))),
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasCloud
                  ? Icons.cloud_done_outlined
                  : Icons.description_outlined,
              size: 18,
              color: hasCloud
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(d.dokument.titel ?? '(ohne Titel)'),
          ],
        )),
        DataCell(Text(d.dokument.kategorie ?? '')),
        DataCell(Text(d.auftrag?.aktenzeichen ?? '')),
        DataCell(Text(_formatSize(d.dokument.dateigroesse))),
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasCloud || hatBytes)
              IconButton(
                tooltip: 'Öffnen / Vorschau',
                icon: const Icon(Icons.visibility_outlined, size: 20),
                onPressed: () => openDokument(context, d.dokument),
              ),
            IconButton(
              tooltip: 'Bearbeiten',
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _edit(context, ref, d),
            ),
            IconButton(
              tooltip: 'Löschen',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _delete(ref, d),
            ),
          ],
        )),
      ],
    );
  }

  String _formatSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _delete(WidgetRef ref, DokumentWithAuftrag d) async {
    final p = d.dokument.storagePfad;
    final storage = ref.read(storageServiceProvider);
    if (p != null && storage.enabled) {
      try { await storage.delete(p); } catch (_) {}
    }
    await ref.read(dokumenteRepositoryProvider).delete(d.dokument.id);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref,
      DokumentWithAuftrag d) async {
    await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _DokumentFormDialog(eintrag: d),
    );
  }

  Future<void> _openUploadDialog(
      BuildContext context, WidgetRef ref) async {
    final filter = ref.read(dokumenteFilterProvider);
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => _UploadDialog(initialAuftragId: filter.auftragId),
    );
  }

}

Future<void> showDokumentEditor(BuildContext context,
    {required DokumentWithAuftrag eintrag}) async {
  await showDialog(
    context: context,
    useRootNavigator: true,
    builder: (_) => _DokumentFormDialog(eintrag: eintrag),
  );
}

class _DokumentFormDialog extends ConsumerStatefulWidget {
  const _DokumentFormDialog({required this.eintrag});
  final DokumentWithAuftrag eintrag;

  @override
  ConsumerState<_DokumentFormDialog> createState() =>
      _DokumentFormDialogState();
}

class _DokumentFormDialogState extends ConsumerState<_DokumentFormDialog> {
  late final _titel = TextEditingController(
      text: widget.eintrag.dokument.titel ?? '');
  late final _kategorie = TextEditingController(
      text: widget.eintrag.dokument.kategorie ?? '');
  late final _beschreibung = TextEditingController(
      text: widget.eintrag.dokument.beschreibung ?? '');
  int? _auftragId;
  bool _saving = false;

  static const _kategorien = [
    'Beweisbeschluss',
    'Vorkorrespondenz',
    'Schriftsatz',
    'Gutachten',
    'Rechnung',
    'Plan / Zeichnung',
    'Lichtbilder',
    'Gerichtspost',
    'Sonstiges',
  ];

  @override
  void initState() {
    super.initState();
    _auftragId = widget.eintrag.dokument.auftragId;
  }

  @override
  void dispose() {
    _titel.dispose();
    _kategorie.dispose();
    _beschreibung.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref.read(dokumenteRepositoryProvider).upsert(
          DokumenteCompanion(
            id: Value(widget.eintrag.dokument.id),
            titel: Value(_titel.text.trim()),
            kategorie: _nt(_kategorie),
            beschreibung: _nt(_beschreibung),
            auftragId: Value(_auftragId),
          ),
        );
    if (mounted) {
      setState(() => _saving = false);
      Navigator.of(context, rootNavigator: true).pop(true);
    }
  }

  Value<String?> _nt(TextEditingController c) {
    final v = c.text.trim();
    return Value(v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.eintrag.dokument.storageUrl;
    final hatDaten = (widget.eintrag.dokument.daten?.isNotEmpty ?? false);
    return StandardFormDialog(
      title: 'Dokument bearbeiten',
      saving: _saving,
      maxWidth: 640,
      maxHeight: 560,
      onCancel: () =>
          Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _save,
      footerLeading: (url != null || hatDaten)
          ? OutlinedButton.icon(
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('Datei öffnen / Vorschau'),
              onPressed: () =>
                  openDokument(context, widget.eintrag.dokument),
            )
          : null,
      onDelete: () async {
        final storage = ref.read(storageServiceProvider);
        final p = widget.eintrag.dokument.storagePfad;
        if (p != null) {
          try {
            await storage.delete(p);
          } catch (_) {}
        }
        await ref
            .read(dokumenteRepositoryProvider)
            .delete(widget.eintrag.dokument.id);
      },
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (url != null)
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                      color: Theme.of(context).colorScheme.primary),
                ),
                child: ListTile(
                  leading: Icon(Icons.cloud_done_outlined,
                      color: Theme.of(context).colorScheme.primary),
                  title: const Text('In der Cloud verfügbar'),
                  subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => launchUrlString(url),
                  ),
                ),
              ),
            LabeledField('Titel', TextFormField(controller: _titel)),
            const SizedBox(height: 12),
            LabeledField(
              'Kategorie',
              DropdownButtonFormField<String>(
                initialValue:
                    _kategorien.contains(_kategorie.text) ? _kategorie.text : null,
                isDense: true,
                items: [
                  for (final k in _kategorien)
                    DropdownMenuItem(value: k, child: Text(k)),
                ],
                onChanged: (v) =>
                    setState(() => _kategorie.text = v ?? ''),
              ),
            ),
            const SizedBox(height: 12),
            AuftragPickerField(
              auftragId: _auftragId,
              onChanged: (id) => setState(() => _auftragId = id),
            ),
            const SizedBox(height: 12),
            LabeledField(
              'Beschreibung',
              TextFormField(
                  controller: _beschreibung, minLines: 2, maxLines: 5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog zum Mehrfach-Upload von Dokumenten.
/// Zeigt einen Button „Dokumente hochladen" → öffnet FilePicker (multi-select).
/// Upload läuft batchweise in Firebase Storage bzw. lokal. Bereits hoch-
/// geladene Dateien erscheinen in einer Liste; User kann „Weitere hinzufügen"
/// klicken bis er fertig ist.
class _UploadDialog extends ConsumerStatefulWidget {
  const _UploadDialog({this.initialAuftragId});
  final int? initialAuftragId;
  @override
  ConsumerState<_UploadDialog> createState() => _UploadDialogState();
}

/// Vordefinierte Kategorien für die schnelle Zuordnung beim Upload.
class _DokumenteScreenKategorien {
  static const werte = <String>[
    'Eingangsmail',
    'Ausgangsmail',
    'Beweisbeschluss',
    'Schriftsatz',
    'Anschreiben (Eingang)',
    'Anschreiben (Ausgang)',
    'Anlage',
    'Foto',
    'Sonstiges',
  ];
}

class _UploadDialogState extends ConsumerState<_UploadDialog> {
  final List<_UploadEntry> _uploaded = [];
  bool _uploading = false;
  int? _auftragId;
  String _kategorie = '';
  final _kategorieCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _auftragId = widget.initialAuftragId;
  }

  @override
  void dispose() {
    _kategorieCtrl.dispose();
    super.dispose();
  }

  String _mime(String name) {
    final ext = name.toLowerCase().split('.').last;
    return switch (ext) {
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'eml' => 'message/rfc822',
      'msg' => 'application/vnd.ms-outlook',
      _ => 'application/octet-stream',
    };
  }

  String _fmtSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _pick() async {
    setState(() => _uploading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final storage = ref.read(storageServiceProvider);
      final auth = ref.read(authServiceProvider);
      final cloudReady = storage.enabled && auth.currentUser != null;
      final repo = ref.read(dokumenteRepositoryProvider);

      for (final f in result.files) {
        if (f.bytes == null) continue;
        final mime = _mime(f.name);
        // Wenn keine Kategorie gewählt wurde und die Datei eine Mail ist,
        // automatisch als "Eingangsmail" markieren.
        if (_kategorie.isEmpty &&
            (mime == 'message/rfc822' ||
                mime == 'application/vnd.ms-outlook')) {
          _kategorie = 'Eingangsmail';
          _kategorieCtrl.text = _kategorie;
        }
        String? storageUrl;
        String? storagePfad;
        if (cloudReady) {
          try {
            storagePfad =
                'dokumente/${DateTime.now().millisecondsSinceEpoch}_${f.name}';
            storageUrl = await storage.uploadBytes(
              storagePfad,
              bytes: f.bytes!,
              contentType: mime,
            );
          } catch (_) {
            storageUrl = null;
            storagePfad = null;
          }
        }
        await repo.upsert(DokumenteCompanion.insert(
          titel: Value(f.name),
          mimeType: Value(mime),
          dateigroesse: Value(f.size),
          storageUrl: Value(storageUrl),
          storagePfad: Value(storagePfad),
          daten: Value(storageUrl != null ? null : f.bytes),
          auftragId: Value(_auftragId),
          kategorie: _kategorie.isEmpty ? const Value(null) : Value(_kategorie),
        ));
        if (mounted) {
          setState(() {
            _uploaded.add(_UploadEntry(
              name: f.name,
              size: f.size,
              cloud: storageUrl != null,
            ));
          });
        }
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.upload_file_outlined, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Dokumente hochladen',
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
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: AuftragPickerField(
                auftragId: _auftragId,
                onChanged: (id) => setState(() => _auftragId = id),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StatefulBuilder(builder: (ctx, setSt) {
                    return Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final k in _DokumenteScreenKategorien.werte)
                          ChoiceChip(
                            label: Text(k, style: const TextStyle(fontSize: 12)),
                            selected: _kategorie == k,
                            onSelected: (sel) => setSt(() {
                              _kategorie = sel ? k : '';
                              _kategorieCtrl.text = _kategorie;
                            }),
                          ),
                      ],
                    );
                  }),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _kategorieCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Kategorie (optional, eigene Eingabe möglich)',
                      hintText:
                          'z. B. Beweisbeschluss, Schriftsatz, Eingangsmail, Anlage',
                      isDense: true,
                    ),
                    onChanged: (v) => _kategorie = v.trim(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _uploaded.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_upload_outlined,
                                size: 48,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline),
                            const SizedBox(height: 12),
                            const Text(
                                'Noch keine Datei hochgeladen.',
                                style: TextStyle(fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(
                              'Eine oder mehrere Dateien per Button auswählen.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      itemCount: _uploaded.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = _uploaded[i];
                        return ListTile(
                          leading: Icon(
                            e.cloud
                                ? Icons.cloud_done_outlined
                                : Icons.save_outlined,
                            color: e.cloud
                                ? AwTokens.green
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                          ),
                          title: Text(e.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${_fmtSize(e.size)} · '
                            '${e.cloud ? "in der Cloud" : "lokal gespeichert"}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing:
                              const Icon(Icons.check_circle,
                                  color: AwTokens.green),
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
                  Text(
                    _uploaded.isEmpty
                        ? ''
                        : '${_uploaded.length} Datei(en) hochgeladen',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    icon: _uploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : Icon(_uploaded.isEmpty
                            ? Icons.upload_file
                            : Icons.add),
                    label: Text(_uploaded.isEmpty
                        ? 'Dokument hochladen'
                        : 'Weitere hinzufügen'),
                    onPressed: _uploading ? null : _pick,
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                    child: const Text('Fertig'),
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

class _UploadEntry {
  final String name;
  final int size;
  final bool cloud;
  const _UploadEntry({
    required this.name,
    required this.size,
    required this.cloud,
  });
}
