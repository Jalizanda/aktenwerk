import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/sync/auth_service.dart';
import '../../../data/sync/storage_service.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import '../../../data/database/database_provider.dart';
import 'foto_exif.dart';
import 'foto_image.dart';
import 'foto_paint_dialog.dart';
import 'foto_viewer_dialog.dart';
import 'fotos_repository.dart';

final _fotosQueryProvider = StateProvider<String>((ref) => '');

class FotosScreen extends ConsumerWidget {
  const FotosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(fotosListProvider);
    final auftragFilter = ref.watch(fotosAuftragFilterProvider);
    final query = ref.watch(_fotosQueryProvider).trim().toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.photo_library_outlined,
          title: 'Fotos',
          subtitle: 'Lichtbildanlage je Auftrag',
          searchHint: 'Suche Raum, Beschreibung, Akte …',
          onSearchChanged: (v) =>
              ref.read(_fotosQueryProvider.notifier).state = v,
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Fotos hinzufügen'),
              onPressed: () => showDialog(
                context: context,
                useRootNavigator: true,
                builder: (_) => _FotoUploadDialog(
                  initialAuftragId: auftragFilter,
                ),
              ),
            ),
          ],
          filters: [
            SizedBox(
              width: 360,
              child: AuftragPickerField(
                auftragId: auftragFilter,
                onChanged: (id) =>
                    ref.read(fotosAuftragFilterProvider.notifier).state = id,
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
            data: (rawItems) {
              final items = query.isEmpty
                  ? rawItems
                  : rawItems.where((f) {
                      final s = [
                        f.foto.titel ?? '',
                        f.foto.raum ?? '',
                        f.foto.beschreibung ?? '',
                        f.auftrag?.aktenzeichen ?? '',
                        f.auftrag?.betreff ?? '',
                      ].join(' ').toLowerCase();
                      return s.contains(query);
                    }).toList();
              if (items.isEmpty) {
                return const EmptyListState(
                  icon: Icons.photo_library_outlined,
                  title: 'Noch keine Fotos',
                  hint:
                      'Wähle oben einen Auftrag und klicke «Fotos hinzufügen».',
                );
              }
              // Wenn ein Auftrag-Filter aktiv ist oder alle Fotos ohne Akte
              // sind, zeigen wir flaches Grid. Sonst gruppieren wir nach Akte.
              if (auftragFilter != null) {
                return _FotoGrid(items: items);
              }
              return _GruppierteFotos(items: items);
            },
          ),
        ),
      ],
    );
  }
}

/// Flaches Grid, verwendet wenn nach einem konkreten Auftrag gefiltert wird.
class _FotoGrid extends StatelessWidget {
  const _FotoGrid({required this.items});
  final List<FotoWithAuftrag> items;
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisExtent: 280,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _FotoCard(foto: items[i]),
    );
  }
}

/// Gruppierte Darstellung: pro Akte ein Abschnitt mit Aktenzeichen-Kopf und
/// Link zur Akte, darunter die Fotos als Grid.
class _GruppierteFotos extends StatelessWidget {
  const _GruppierteFotos({required this.items});
  final List<FotoWithAuftrag> items;

  @override
  Widget build(BuildContext context) {
    // In Reihenfolge des ersten Auftritts gruppieren.
    final keys = <int?>[];
    final groups = <int?, List<FotoWithAuftrag>>{};
    for (final f in items) {
      final id = f.auftrag?.id;
      if (!groups.containsKey(id)) {
        keys.add(id);
        groups[id] = [];
      }
      groups[id]!.add(f);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: keys.length,
      itemBuilder: (ctx, idx) {
        final k = keys[idx];
        final groupItems = groups[k]!;
        final auftrag = groupItems.first.auftrag;
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GruppeKopf(auftrag: auftrag, anzahl: groupItems.length),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 260,
                  mainAxisExtent: 280,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: groupItems.length,
                itemBuilder: (_, i) => _FotoCard(foto: groupItems[i]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GruppeKopf extends StatelessWidget {
  const _GruppeKopf({required this.auftrag, required this.anzahl});
  final AuftraegeData? auftrag;
  final int anzahl;
  @override
  Widget build(BuildContext context) {
    final hasAkte = auftrag != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        children: [
          Icon(
            hasAkte
                ? Icons.folder_open_outlined
                : Icons.photo_album_outlined,
            size: 18,
            color: hasAkte ? AppTheme.accent600 : AppTheme.slate500,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasAkte
                      ? (auftrag!.aktenzeichen ?? '(ohne Aktenzeichen)')
                      : 'Ohne Akte',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace'),
                ),
                if (hasAkte &&
                    (auftrag!.betreff ?? auftrag!.bezeichnung ?? '')
                        .isNotEmpty)
                  Text(
                    auftrag!.betreff ?? auftrag!.bezeichnung ?? '',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.slate500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Text('$anzahl Fotos',
              style:
                  TextStyle(fontSize: 12, color: AppTheme.slate500)),
          if (hasAkte) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 14),
              label: const Text('zur Akte'),
              onPressed: () =>
                  GoRouter.of(context).go('/akte/${auftrag!.id}'),
            ),
          ],
        ],
      ),
    );
  }
}

class _FotoCard extends ConsumerWidget {
  const _FotoCard({required this.foto});
  final FotoWithAuftrag foto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = foto.foto.storageUrl;
    final preview = FotoImage(foto: foto.foto);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                InkWell(
                  onTap: () => showFotoViewer(context, foto.foto,
                      auftrag: foto.auftrag),
                  child: Container(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: preview,
                  ),
                ),
                if (foto.foto.reihenfolge > 0)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.accent600,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Nr. ${foto.foto.reihenfolge}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ),
                  ),
                if (foto.foto.lat != null && foto.foto.lon != null)
                  Positioned(
                    bottom: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.place_outlined,
                              size: 12, color: Colors.white),
                          SizedBox(width: 3),
                          Text('GPS',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                if (url != null)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_done_outlined,
                              size: 12, color: Colors.white),
                          SizedBox(width: 4),
                          Text('Cloud',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [foto.foto.titel, foto.foto.raum]
                      .whereType<String>()
                      .where((s) => s.isNotEmpty)
                      .join(' · '),
                  style: Theme.of(context).textTheme.labelMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (foto.auftrag != null)
                  Text(
                    'Auftrag ${foto.auftrag!.aktenzeichen ?? ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit'),
                      onPressed: () => _edit(context, ref),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Löschen',
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () async {
                        final storage = ref.read(storageServiceProvider);
                        final p = foto.foto.storagePfad;
                        if (p != null && storage.enabled) {
                          try { await storage.delete(p); } catch (_) {}
                        }
                        await ref
                            .read(fotosRepositoryProvider)
                            .delete(foto.foto.id);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final titel = TextEditingController(text: foto.foto.titel ?? '');
    final raum = TextEditingController(text: foto.foto.raum ?? '');
    final beschreibung =
        TextEditingController(text: foto.foto.beschreibung ?? '');
    int? auftragId = foto.foto.auftragId;
    Uint8List? overridenBytes; // nach Bemalen
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => StandardFormDialog(
          title: 'Foto bearbeiten',
          maxWidth: 620,
          maxHeight: 720,
          onCancel: () => Navigator.pop(ctx, false),
          onSave: () => Navigator.pop(ctx, true),
          onDelete: () async {
            final storage = ref.read(storageServiceProvider);
            final p = foto.foto.storagePfad;
            if (p != null) {
              try {
                await storage.delete(p);
              } catch (_) {}
            }
            await ref
                .read(fotosRepositoryProvider)
                .delete(foto.foto.id);
          },
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EditPreview(
                  foto: foto.foto,
                  overrideBytes: overridenBytes,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.brush_outlined),
                      label: const Text('Bemalen'),
                      onPressed: () async {
                        final bytes = overridenBytes ??
                            await _loadFotoBytes(ref, foto.foto);
                        if (bytes == null) return;
                        if (!context.mounted) return;
                        final result =
                            await showFotoPaintDialog(context, bytes);
                        if (result != null) {
                          setState(() => overridenBytes = result);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row2(
                  left: LabeledField(
                      'Titel', TextFormField(controller: titel)),
                  right: LabeledField(
                    'Raum / Ort (z. B. "Schlafzimmer OG")',
                    TextFormField(controller: raum),
                  ),
                ),
                const SizedBox(height: 12),
                LabeledField(
                    'Beschreibung',
                    TextFormField(
                        controller: beschreibung,
                        minLines: 3,
                        maxLines: 5)),
                const SizedBox(height: 12),
                AuftragPickerField(
                  auftragId: auftragId,
                  onChanged: (id) => setState(() => auftragId = id),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok == true) {
      if (overridenBytes != null) {
        // "Bemalen" speichert immer als PNG **lokal** — Original wird
        // (falls noch nicht gesichert) in originalDaten/originalStorageUrl
        // parallel abgelegt. So geht nichts verloren; Nutzer kann im
        // Viewer zwischen Original und bemalter Fassung umschalten.
        final originalExists = foto.foto.originalDaten != null ||
            (foto.foto.originalStorageUrl ?? '').isNotEmpty;
        await ref.read(fotosRepositoryProvider).upsert(FotosCompanion(
              id: Value(foto.foto.id),
              titel: Value(titel.text.trim()),
              raum: Value(raum.text.trim().isEmpty ? null : raum.text.trim()),
              beschreibung: Value(beschreibung.text.trim()),
              auftragId: Value(auftragId),
              daten: Value(overridenBytes),
              mimeType: const Value('image/png'),
              // Storage-Ablage der bemalten Version löschen wir NICHT — die
              // Anzeige fällt auf `daten` zurück (FotoImage-Helper).
              // Original-Fallback: erstmalig sichern.
              originalDaten: originalExists
                  ? const Value.absent()
                  : Value(foto.foto.daten == null
                      ? null
                      : Uint8List.fromList(foto.foto.daten!)),
              originalStorageUrl: originalExists
                  ? const Value.absent()
                  : Value(foto.foto.storageUrl),
              originalStoragePfad: originalExists
                  ? const Value.absent()
                  : Value(foto.foto.storagePfad),
            ));
      } else {
        await ref.read(fotosRepositoryProvider).upsert(FotosCompanion(
              id: Value(foto.foto.id),
              titel: Value(titel.text.trim()),
              raum: Value(raum.text.trim().isEmpty ? null : raum.text.trim()),
              beschreibung: Value(beschreibung.text.trim()),
              auftragId: Value(auftragId),
            ));
      }
    }
  }
}

/// Dialog zum Foto-Upload mit Kontext-Eingabe (Auftrag, Raum, Beschreibung)
/// BEVOR der File-Picker geöffnet wird. Mehrere Dateien auf einmal
/// möglich — alle übernehmen denselben Kontext.
class _FotoUploadDialog extends ConsumerStatefulWidget {
  const _FotoUploadDialog({this.initialAuftragId});
  final int? initialAuftragId;
  @override
  ConsumerState<_FotoUploadDialog> createState() =>
      _FotoUploadDialogState();
}

class _FotoUploadDialogState extends ConsumerState<_FotoUploadDialog> {
  int? _auftragId;
  final _raum = TextEditingController();
  final _beschreibung = TextEditingController();
  bool _uploading = false;
  int _hochgeladen = 0;

  @override
  void initState() {
    super.initState();
    _auftragId = widget.initialAuftragId;
  }

  @override
  void dispose() {
    _raum.dispose();
    _beschreibung.dispose();
    super.dispose();
  }

  String _mimeFor(String name) {
    final ext = name.toLowerCase().split('.').last;
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _uploading = true);
    final repo = ref.read(fotosRepositoryProvider);
    final storage = ref.read(storageServiceProvider);
    final auth = ref.read(authServiceProvider);
    final cloudReady = storage.enabled && auth.currentUser != null;

    final db = ref.read(appDatabaseProvider);
    for (final f in result.files) {
      if (f.bytes == null) continue;
      final mime = _mimeFor(f.name);
      String? storageUrl;
      String? storagePfad;
      if (cloudReady) {
        try {
          storagePfad =
              'fotos/${DateTime.now().millisecondsSinceEpoch}_${f.name}';
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
      final exif = await readExif(f.bytes!);
      final reihenfolge = await nextReihenfolgeFor(db, _auftragId);
      // Bytes immer lokal speichern: dient als Offline-Cache und Fallback,
      // falls der Browser die Storage-URL wegen CORS nicht laden kann.
      await repo.upsert(FotosCompanion.insert(
        titel: Value(f.name),
        raum: _raum.text.trim().isEmpty
            ? const Value.absent()
            : Value(_raum.text.trim()),
        beschreibung: _beschreibung.text.trim().isEmpty
            ? const Value.absent()
            : Value(_beschreibung.text.trim()),
        daten: Value(f.bytes),
        mimeType: Value(mime),
        storageUrl: Value(storageUrl),
        storagePfad: Value(storagePfad),
        auftragId: Value(_auftragId),
        aufnahmeAm: Value(exif.aufnahmeAm ?? DateTime.now()),
        lat: Value(exif.lat),
        lon: Value(exif.lon),
        reihenfolge: Value(reihenfolge),
      ));
      if (mounted) setState(() => _hochgeladen++);
    }
    if (mounted) {
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$_hochgeladen Foto(s) gespeichert.')));
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.add_photo_alternate_outlined, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Fotos hinzufügen',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AuftragPickerField(
                auftragId: _auftragId,
                onChanged: (id) => setState(() => _auftragId = id),
                label: 'Auftrag *',
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Raum / Bauteil',
                TextFormField(
                  controller: _raum,
                  decoration: const InputDecoration(
                    hintText:
                        'z. B. Keller Außenwand Nord · Schlafzimmer OG · Fassade Süd',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Beschreibung',
                TextFormField(
                  controller: _beschreibung,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText:
                        'Was zeigt das Foto? (wird in Gutachten-Lichtbildanlage übernommen)',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file),
                label: Text(_uploading
                    ? 'Lade hoch … ($_hochgeladen)'
                    : 'Fotos auswählen und hochladen'),
                onPressed: _uploading || _auftragId == null ? null : _pick,
              ),
              if (_auftragId == null) ...[
                const SizedBox(height: 8),
                Text('Bitte zuerst einen Auftrag auswählen.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EditPreview extends StatelessWidget {
  const _EditPreview({required this.foto, required this.overrideBytes});
  final Foto foto;
  final Uint8List? overrideBytes;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        height: 220,
        alignment: Alignment.center,
        child: FotoImage(
          foto: foto,
          overrideBytes: overrideBytes,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

Future<Uint8List?> _loadFotoBytes(WidgetRef ref, Foto foto) async {
  if (foto.daten != null) return Uint8List.fromList(foto.daten!);
  final url = foto.storageUrl;
  if (url != null && url.isNotEmpty) {
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) return resp.bodyBytes;
    } catch (_) {}
  }
  return null;
}
