import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'fotos_repository.dart';

class FotosScreen extends ConsumerWidget {
  const FotosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(fotosListProvider);
    final auftragFilter = ref.watch(fotosAuftragFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.photo_library_outlined,
          title: 'Fotos',
          subtitle: 'Lichtbildanlage je Auftrag',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Fotos hinzufügen'),
              onPressed: () => _pickAndAdd(context, ref),
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
            data: (items) => items.isEmpty
                ? const EmptyListState(
                    icon: Icons.photo_library_outlined,
                    title: 'Noch keine Fotos',
                    hint:
                        'Wähle oben einen Auftrag und klicke «Fotos hinzufügen».')
                : GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 260,
                      mainAxisExtent: 280,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _FotoCard(foto: items[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickAndAdd(BuildContext context, WidgetRef ref) async {
    final auftragFilter = ref.read(fotosAuftragFilterProvider);
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final repo = ref.read(fotosRepositoryProvider);
    for (final f in result.files) {
      if (f.bytes == null) continue;
      await repo.upsert(FotosCompanion.insert(
        titel: Value(f.name),
        daten: Value(f.bytes),
        mimeType: Value(_mime(f.name)),
        auftragId: Value(auftragFilter),
      ));
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('${result.files.length} Foto(s) hinzugefügt')),
      );
    }
  }

  String _mime(String name) {
    final ext = name.toLowerCase().split('.').last;
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
  }
}

class _FotoCard extends ConsumerWidget {
  const _FotoCard({required this.foto});
  final FotoWithAuftrag foto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = foto.foto.daten;
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
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: bytes == null
                  ? Icon(Icons.image_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline)
                  : Image.memory(
                      Uint8List.fromList(bytes),
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  foto.foto.titel ?? '',
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
                      onPressed: () async => ref
                          .read(fotosRepositoryProvider)
                          .delete(foto.foto.id),
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
    final beschreibung =
        TextEditingController(text: foto.foto.beschreibung ?? '');
    int? auftragId = foto.foto.auftragId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => StandardFormDialog(
          title: 'Foto bearbeiten',
          maxWidth: 520,
          maxHeight: 460,
          onCancel: () => Navigator.pop(ctx, false),
          onSave: () => Navigator.pop(ctx, true),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LabeledField('Titel', TextFormField(controller: titel)),
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
      await ref.read(fotosRepositoryProvider).upsert(FotosCompanion(
            id: Value(foto.foto.id),
            titel: Value(titel.text.trim()),
            beschreibung: Value(beschreibung.text.trim()),
            auftragId: Value(auftragId),
          ));
    }
  }
}
