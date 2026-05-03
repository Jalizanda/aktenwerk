import 'package:drift/drift.dart' show Value, OrderingTerm, OrderingMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import 'versand_repository.dart';

/// Dialog zum Erfassen eines Versandvorgangs (Post / Einschreiben / EGVP /
/// E-Mail / Kurier / Persönlich) mit Empfänger, Anzahl Ausfertigungen,
/// Tracking-Nr. und optional dem Bezugs-Dokument aus der Akten-Ablage.
class VersandDialog extends ConsumerStatefulWidget {
  const VersandDialog({
    super.key,
    required this.auftrag,
    this.versand,
    this.bezugBezeichnung,
    this.dokumentId,
  });
  final AuftraegeData auftrag;
  final VersandData? versand;
  final String? bezugBezeichnung;
  final int? dokumentId;

  @override
  ConsumerState<VersandDialog> createState() => _VersandDialogState();
}

class _VersandDialogState extends ConsumerState<VersandDialog> {
  late final _empfaenger =
      TextEditingController(text: widget.versand?.empfaenger ?? '');
  late final _betreff =
      TextEditingController(text: widget.versand?.betreff ?? '');
  late final _trackingNr =
      TextEditingController(text: widget.versand?.trackingNr ?? '');
  late final _ausfertigungen = TextEditingController(
      text: (widget.versand?.anzahlAusfertigungen ??
              widget.auftrag.anzahlAusfertigungen ??
              1)
          .toString());
  late final _bezugBezeichnung = TextEditingController(
      text: widget.versand?.bezugBezeichnung ??
          widget.bezugBezeichnung ??
          '');
  late final _inhalt =
      TextEditingController(text: widget.versand?.inhalt ?? '');

  late String _art = widget.versand?.art ?? 'einschreiben';
  late String _status = widget.versand?.status ?? 'versendet';
  late DateTime _datum = widget.versand?.datum ?? DateTime.now();
  late int? _dokumentId =
      widget.versand?.dokumentId ?? widget.dokumentId;

  bool _saving = false;

  @override
  void dispose() {
    _empfaenger.dispose();
    _betreff.dispose();
    _trackingNr.dispose();
    _ausfertigungen.dispose();
    _bezugBezeichnung.dispose();
    _inhalt.dispose();
    super.dispose();
  }

  Future<void> _speichern() async {
    setState(() => _saving = true);
    try {
      final eintrag = VersandCompanion(
        id: widget.versand == null
            ? const Value.absent()
            : Value(widget.versand!.id),
        auftragId: Value(widget.auftrag.id),
        datum: Value(_datum),
        art: Value(_art),
        empfaenger: Value(_empfaenger.text.trim()),
        betreff: Value(_betreff.text.trim()),
        inhalt: Value(_inhalt.text.trim()),
        trackingNr: Value(_trackingNr.text.trim()),
        anzahlAusfertigungen:
            Value(int.tryParse(_ausfertigungen.text.trim())),
        dokumentId: Value(_dokumentId),
        bezugBezeichnung: Value(_bezugBezeichnung.text.trim()),
        status: Value(_status),
      );
      await ref.read(versandRepositoryProvider).upsert(eintrag);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.local_shipping_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.versand == null
                          ? 'Versand erfassen · ${widget.auftrag.aktenzeichen ?? ""}'
                          : 'Versand bearbeiten · ${widget.auftrag.aktenzeichen ?? ""}',
                      style: Theme.of(context).textTheme.titleMedium,
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
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DateField(
                            label: 'Versanddatum',
                            value: _datum,
                            onChanged: (d) =>
                                setState(() => _datum = d ?? DateTime.now()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: LabeledField(
                            'Versandart',
                            DropdownButtonFormField<String>(
                              initialValue: _art,
                              items: const [
                                DropdownMenuItem(
                                    value: 'einschreiben',
                                    child: Text('Einschreiben (Wert)')),
                                DropdownMenuItem(
                                    value: 'einschreiben_rs',
                                    child:
                                        Text('Einschreiben Rückschein')),
                                DropdownMenuItem(
                                    value: 'post',
                                    child: Text('Standard-Post')),
                                DropdownMenuItem(
                                    value: 'egvp',
                                    child: Text('EGVP / beA')),
                                DropdownMenuItem(
                                    value: 'email',
                                    child: Text('E-Mail')),
                                DropdownMenuItem(
                                    value: 'kurier',
                                    child: Text('Kurier')),
                                DropdownMenuItem(
                                    value: 'persoenlich',
                                    child: Text('Persönliche Übergabe')),
                              ],
                              onChanged: (v) =>
                                  setState(() => _art = v ?? 'post'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LabeledField(
                      'Empfänger',
                      TextFormField(
                        controller: _empfaenger,
                        decoration: const InputDecoration(
                            hintText:
                                'z. B. Amtsgericht Duisburg / RA Krüger'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    LabeledField(
                      'Betreff',
                      TextFormField(
                        controller: _betreff,
                        decoration: const InputDecoration(
                            hintText:
                                'z. B. „Gutachten in der Sache 12 OH 4/26"'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 140,
                          child: LabeledField(
                            'Anzahl Ausfertigungen',
                            TextFormField(
                              controller: _ausfertigungen,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: LabeledField(
                            'Tracking-/Sendungs-Nr.',
                            TextFormField(
                              controller: _trackingNr,
                              decoration: const InputDecoration(
                                  hintText: 'optional'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: LabeledField(
                            'Status',
                            DropdownButtonFormField<String>(
                              initialValue: _status,
                              items: const [
                                DropdownMenuItem(
                                    value: 'versendet',
                                    child: Text('versendet')),
                                DropdownMenuItem(
                                    value: 'zugestellt',
                                    child: Text('zugestellt')),
                                DropdownMenuItem(
                                    value: 'unzustellbar',
                                    child: Text('unzustellbar')),
                              ],
                              onChanged: (v) => setState(
                                  () => _status = v ?? 'versendet'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LabeledField(
                      'Inhalt / Bezeichnung',
                      TextFormField(
                        controller: _bezugBezeichnung,
                        decoration: const InputDecoration(
                            hintText:
                                'z. B. „Gutachten AW-0001-G1 (5 Hefte)"'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _DokumentPicker(
                      auftragId: widget.auftrag.id,
                      currentId: _dokumentId,
                      onChanged: (d) => setState(() {
                        _dokumentId = d?.id;
                        if (d != null && _bezugBezeichnung.text.isEmpty) {
                          _bezugBezeichnung.text = d.titel ?? '';
                        }
                      }),
                    ),
                    const SizedBox(height: 8),
                    LabeledField(
                      'Bemerkung',
                      TextFormField(
                        controller: _inhalt,
                        minLines: 2,
                        maxLines: 4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (widget.versand != null)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Löschen'),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.red),
                      onPressed: _saving
                          ? null
                          : () async {
                              await ref
                                  .read(versandRepositoryProvider)
                                  .delete(widget.versand!.id);
                              if (!mounted) return;
                              Navigator.of(context, rootNavigator: true)
                                  .pop();
                            },
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Speichern'),
                    onPressed: _saving ? null : _speichern,
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

class _DokumentPicker extends ConsumerWidget {
  const _DokumentPicker({
    required this.auftragId,
    required this.currentId,
    required this.onChanged,
  });
  final int auftragId;
  final int? currentId;
  final ValueChanged<DokumenteData?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    return StreamBuilder<List<DokumenteData>>(
      stream: (db.select(db.dokumente)
            ..where((t) => t.auftragId.equals(auftragId))
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.datum, mode: OrderingMode.desc),
            ]))
          .watch(),
      builder: (ctx, snap) {
        final liste = snap.data ?? const <DokumenteData>[];
        return LabeledField(
          'Verknüpftes Akten-Dokument (optional)',
          DropdownButtonFormField<int?>(
            initialValue: currentId,
            isExpanded: true,
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('— kein Bezug —'),
              ),
              for (final d in liste)
                DropdownMenuItem<int?>(
                  value: d.id,
                  child: Text(
                    '${d.titel ?? "(ohne Titel)"}${d.kategorie == null ? "" : " · ${d.kategorie}"}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) {
              if (v == null) {
                onChanged(null);
                return;
              }
              onChanged(liste.firstWhere((d) => d.id == v));
            },
          ),
        );
      },
    );
  }
}
