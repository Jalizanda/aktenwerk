import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/file_upload_section.dart';
import '../../../shared/widgets/form_widgets.dart';
import 'bauteiloeffnung_repository.dart';

class BauteiloeffnungTab extends ConsumerWidget {
  const BauteiloeffnungTab({super.key, required this.auftragId});
  final int auftragId;

  static final _fmt = DateFormat('dd.MM.yyyy', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(bauteiloeffnungenByAkteProvider(auftragId));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Bauteilöffnungen',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _open(context, ref),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Öffnung'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (items) => items.isEmpty
                  ? const EmptyListState(
                      icon: Icons.construction_outlined,
                      title: 'Keine Öffnungen dokumentiert',
                      hint:
                          'Dokumentiere jede Bauteilöffnung mit Lage, Methode, Befund und Fotos vor/nach.',
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 360,
                        mainAxisExtent: 220,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final o = items[i];
                        return InkWell(
                          onTap: () => _open(context, ref, o),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: AppTheme.slate200),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Text(_fmt.format(o.datum),
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.slate500)),
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.delete_outline,
                                          size: 18),
                                      onPressed: () => ref
                                          .read(
                                              bauteiloeffnungRepositoryProvider)
                                          .delete(o.id),
                                    ),
                                  ],
                                ),
                                if ((o.lage ?? '').isNotEmpty)
                                  Text(o.lage!,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight:
                                              FontWeight.w700)),
                                if ((o.methode ?? '').isNotEmpty)
                                  Text(o.methode!,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.slate500)),
                                if ((o.befund ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(o.befund!,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          height: 1.4)),
                                ],
                                const Spacer(),
                                Row(
                                  children: [
                                    _Thumb(
                                        label: 'vor',
                                        url: o.fotoVorStorageUrl),
                                    const SizedBox(width: 8),
                                    _Thumb(
                                        label: 'nach',
                                        url: o.fotoNachStorageUrl),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref,
      [BauteiloeffnungenData? o]) async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) =>
          _OeffnungEditor(auftragId: auftragId, eintrag: o),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.label, required this.url});
  final String label;
  final String? url;
  @override
  Widget build(BuildContext context) {
    final has = (url ?? '').isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: has ? Colors.white : AppTheme.slate50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(has ? Icons.image_outlined : Icons.image_not_supported_outlined,
              size: 14,
              color: has ? AppTheme.accent600 : AppTheme.slate400),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _OeffnungEditor extends ConsumerStatefulWidget {
  const _OeffnungEditor({required this.auftragId, this.eintrag});
  final int auftragId;
  final BauteiloeffnungenData? eintrag;
  @override
  ConsumerState<_OeffnungEditor> createState() => _OeffnungEditorState();
}

class _OeffnungEditorState extends ConsumerState<_OeffnungEditor> {
  late final _lage =
      TextEditingController(text: widget.eintrag?.lage ?? '');
  late final _methode =
      TextEditingController(text: widget.eintrag?.methode ?? '');
  late final _anwesend =
      TextEditingController(text: widget.eintrag?.anwesend ?? '');
  late final _befund =
      TextEditingController(text: widget.eintrag?.befund ?? '');
  late final _bemerkung =
      TextEditingController(text: widget.eintrag?.bemerkung ?? '');
  late DateTime _datum = widget.eintrag?.datum ?? DateTime.now();
  UploadedFile? _fotoVor;
  UploadedFile? _fotoNach;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.eintrag;
    if (e != null) {
      if ((e.fotoVorStorageUrl ?? '').isNotEmpty) {
        _fotoVor = UploadedFile(
            storageUrl: e.fotoVorStorageUrl!,
            dateiname: 'Foto vor',
            mimeType: 'image/jpeg');
      }
      if ((e.fotoNachStorageUrl ?? '').isNotEmpty) {
        _fotoNach = UploadedFile(
            storageUrl: e.fotoNachStorageUrl!,
            dateiname: 'Foto nach',
            mimeType: 'image/jpeg');
      }
    }
  }

  @override
  void dispose() {
    _lage.dispose();
    _methode.dispose();
    _anwesend.dispose();
    _befund.dispose();
    _bemerkung.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.eintrag != null;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(bauteiloeffnungRepositoryProvider).upsert(
            BauteiloeffnungenCompanion(
              id: _isEdit
                  ? Value(widget.eintrag!.id)
                  : const Value.absent(),
              auftragId: Value(widget.auftragId),
              datum: Value(_datum),
              lage: Value(_lage.text.trim().isEmpty ? null : _lage.text.trim()),
              methode: Value(_methode.text.trim().isEmpty
                  ? null
                  : _methode.text.trim()),
              anwesend: Value(_anwesend.text.trim().isEmpty
                  ? null
                  : _anwesend.text.trim()),
              befund: Value(_befund.text.trim().isEmpty
                  ? null
                  : _befund.text.trim()),
              bemerkung: Value(_bemerkung.text.trim().isEmpty
                  ? null
                  : _bemerkung.text.trim()),
              fotoVorStorageUrl: Value(_fotoVor?.storageUrl),
              fotoNachStorageUrl: Value(_fotoNach?.storageUrl),
            ),
          );
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StandardFormDialog(
      title: _isEdit
          ? 'Bauteilöffnung bearbeiten'
          : 'Neue Bauteilöffnung',
      icon: Icons.construction_outlined,
      maxWidth: 760,
      maxHeight: 820,
      saving: _saving,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(bauteiloeffnungRepositoryProvider)
              .delete(widget.eintrag!.id)
          : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row3(
              a: DateField(
                  label: 'Datum',
                  value: _datum,
                  onChanged: (v) =>
                      setState(() => _datum = v ?? DateTime.now())),
              b: LabeledField(
                  'Lage / Position', TextFormField(controller: _lage)),
              c: LabeledField(
                  'Methode', TextFormField(controller: _methode)),
            ),
            const SizedBox(height: 12),
            LabeledField(
                'Anwesende Personen (eine pro Zeile)',
                TextFormField(
                    controller: _anwesend, minLines: 2, maxLines: 4)),
            const SizedBox(height: 12),
            LabeledField(
                'Befund',
                TextFormField(
                    controller: _befund, minLines: 3, maxLines: 6)),
            const SizedBox(height: 12),
            LabeledField(
                'Bemerkung',
                TextFormField(
                    controller: _bemerkung, minLines: 2, maxLines: 4)),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: FileUploadSection(
                    title: 'Foto vor Öffnung',
                    storagePrefix: 'bauteil/vor',
                    kind: UploadKind.image,
                    file: _fotoVor,
                    onChanged: (f) => setState(() => _fotoVor = f),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FileUploadSection(
                    title: 'Foto nach Öffnung',
                    storagePrefix: 'bauteil/nach',
                    kind: UploadKind.image,
                    file: _fotoNach,
                    onChanged: (f) => setState(() => _fotoNach = f),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
