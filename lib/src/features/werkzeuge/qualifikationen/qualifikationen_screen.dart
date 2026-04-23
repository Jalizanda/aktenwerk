import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../shared/widgets/badges.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/file_upload_section.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'qualifikationen_repository.dart';

class QualifikationenScreen extends ConsumerWidget {
  const QualifikationenScreen({super.key});
  static final _fmt = DateFormat('dd.MM.yyyy', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(qualifikationenListProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.workspace_premium_outlined,
          title: 'Qualifikationen',
          subtitle:
              'Diplome, Zertifikate, Prüfungen — als Anlage 1 am Gutachten anhängbar',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Qualifikation'),
              onPressed: () => _open(context, ref),
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
                    icon: Icons.workspace_premium_outlined,
                    title: 'Keine Qualifikationen',
                    hint:
                        'Lege Diplome, ift/BVS/BAFA-Zertifikate mit Ablaufdatum und PDF ab.')
                : DataTableCard(
                    child: DataTable(
                      showCheckboxColumn: false,
                      headingRowColor: WidgetStateProperty.all(
                          Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest),
                      columns: const [
                        DataColumn(label: Text('Titel')),
                        DataColumn(label: Text('Typ')),
                        DataColumn(label: Text('Aussteller')),
                        DataColumn(label: Text('Ausgestellt')),
                        DataColumn(label: Text('Gültig bis')),
                        DataColumn(label: Text('Anhang')),
                        DataColumn(label: Text('Nachweis')),
                      ],
                      rows: [
                        for (final q in items)
                          DataRow(
                            onSelectChanged: (_) => _open(context, ref, q),
                            cells: [
                              DataCell(Text(q.titel,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600))),
                              DataCell(Text(q.typ)),
                              DataCell(Text(q.aussteller ?? '')),
                              DataCell(Text(q.ausgestelltAm == null
                                  ? ''
                                  : _fmt.format(q.ausgestelltAm!))),
                              DataCell(_GueltigChip(bis: q.gueltigBis)),
                              DataCell(q.standardAnhang
                                  ? Icon(Icons.check_circle,
                                      size: 18,
                                      color: BadgeColors.greenFg)
                                  : const SizedBox.shrink()),
                              DataCell(
                                (q.nachweisStorageUrl ?? '').isEmpty
                                    ? Text('—',
                                        style: TextStyle(
                                            color: AppTheme.slate400))
                                    : const Icon(
                                        Icons.picture_as_pdf_outlined,
                                        size: 18),
                              ),
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

  Future<void> _open(BuildContext context, WidgetRef ref,
      [QualifikationenData? q]) async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => _QualifikationEditor(eintrag: q),
    );
  }
}

class _GueltigChip extends StatelessWidget {
  const _GueltigChip({this.bis});
  final DateTime? bis;
  @override
  Widget build(BuildContext context) {
    if (bis == null) {
      return Text('unbefristet',
          style: TextStyle(fontSize: 12, color: AppTheme.slate500));
    }
    final today = DateTime.now();
    final diffDays = bis!.difference(today).inDays;
    Color bg, fg;
    if (diffDays < 0) {
      bg = BadgeColors.redBg;
      fg = BadgeColors.redFg;
    } else if (diffDays < 90) {
      bg = BadgeColors.amberBg;
      fg = BadgeColors.amberFg;
    } else {
      bg = BadgeColors.greenBg;
      fg = BadgeColors.greenFg;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        DateFormat('dd.MM.yyyy', 'de').format(bis!),
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _QualifikationEditor extends ConsumerStatefulWidget {
  const _QualifikationEditor({this.eintrag});
  final QualifikationenData? eintrag;
  @override
  ConsumerState<_QualifikationEditor> createState() =>
      _QualifikationEditorState();
}

class _QualifikationEditorState
    extends ConsumerState<_QualifikationEditor> {
  late final _titel =
      TextEditingController(text: widget.eintrag?.titel ?? '');
  late final _aussteller =
      TextEditingController(text: widget.eintrag?.aussteller ?? '');
  late final _beschreibung =
      TextEditingController(text: widget.eintrag?.beschreibung ?? '');
  late DateTime? _ausgestelltAm = widget.eintrag?.ausgestelltAm;
  late DateTime? _gueltigBis = widget.eintrag?.gueltigBis;
  late String _typ = widget.eintrag?.typ ?? 'zertifikat';
  late bool _standardAnhang = widget.eintrag?.standardAnhang ?? false;
  late UploadedFile? _nachweis = (widget.eintrag?.nachweisStorageUrl ?? '')
          .isEmpty
      ? null
      : UploadedFile(
          storageUrl: widget.eintrag!.nachweisStorageUrl!,
          dateiname: widget.eintrag!.nachweisDateiname ?? 'Nachweis',
          mimeType: widget.eintrag!.nachweisMimeType,
          groesse: widget.eintrag!.nachweisGroesse,
        );
  bool _saving = false;

  bool get _isEdit => widget.eintrag != null;

  @override
  void dispose() {
    _titel.dispose();
    _aussteller.dispose();
    _beschreibung.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titel.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(qualifikationenRepositoryProvider).upsert(
            QualifikationenCompanion(
              id: _isEdit
                  ? Value(widget.eintrag!.id)
                  : const Value.absent(),
              titel: Value(_titel.text.trim()),
              aussteller: Value(_aussteller.text.trim().isEmpty
                  ? null
                  : _aussteller.text.trim()),
              ausgestelltAm: Value(_ausgestelltAm),
              gueltigBis: Value(_gueltigBis),
              typ: Value(_typ),
              beschreibung: Value(_beschreibung.text.trim().isEmpty
                  ? null
                  : _beschreibung.text.trim()),
              nachweisStorageUrl: Value(_nachweis?.storageUrl),
              nachweisDateiname: Value(_nachweis?.dateiname),
              nachweisMimeType: Value(_nachweis?.mimeType),
              nachweisGroesse: Value(_nachweis?.groesse),
              standardAnhang: Value(_standardAnhang),
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
      title:
          _isEdit ? 'Qualifikation bearbeiten' : 'Neue Qualifikation',
      icon: Icons.workspace_premium_outlined,
      maxWidth: 720,
      maxHeight: 760,
      saving: _saving,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(qualifikationenRepositoryProvider)
              .delete(widget.eintrag!.id)
          : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row2(
              left: LabeledField('Titel *',
                  TextFormField(controller: _titel)),
              right: LabeledField(
                'Typ',
                DropdownButtonFormField<String>(
                  initialValue: _typ,
                  isDense: true,
                  items: const [
                    DropdownMenuItem(
                        value: 'diplom', child: Text('Diplom / Master')),
                    DropdownMenuItem(
                        value: 'zertifikat', child: Text('Zertifikat')),
                    DropdownMenuItem(
                        value: 'pruefung', child: Text('Prüfung / Nachweis')),
                    DropdownMenuItem(
                        value: 'sonstiges', child: Text('Sonstiges')),
                  ],
                  onChanged: (v) =>
                      setState(() => _typ = v ?? 'zertifikat'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            LabeledField('Aussteller / Institution',
                TextFormField(controller: _aussteller)),
            const SizedBox(height: 12),
            Row2(
              left: DateField(
                label: 'Ausgestellt am',
                value: _ausgestelltAm,
                onChanged: (v) => setState(() => _ausgestelltAm = v),
              ),
              right: DateField(
                label: 'Gültig bis',
                value: _gueltigBis,
                onChanged: (v) => setState(() => _gueltigBis = v),
              ),
            ),
            const SizedBox(height: 12),
            LabeledField(
              'Beschreibung',
              TextFormField(
                  controller: _beschreibung, minLines: 2, maxLines: 4),
            ),
            const SizedBox(height: 14),
            CheckboxListTile(
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _standardAnhang,
              title: const Text(
                  'Standard-Anhang zum Gutachten (Anlage 1)'),
              onChanged: (v) =>
                  setState(() => _standardAnhang = v ?? false),
            ),
            const SizedBox(height: 14),
            FileUploadSection(
              title: 'Nachweis (PDF)',
              storagePrefix: 'qualifikationen',
              kind: UploadKind.pdf,
              file: _nachweis,
              hint: 'Zertifikat / Diplom als PDF hochladen.',
              onChanged: (f) => setState(() => _nachweis = f),
            ),
          ],
        ),
      ),
    );
  }
}
