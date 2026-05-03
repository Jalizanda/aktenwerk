import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../shared/pdf/stellungnahme_pdf.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../system/einstellungen/absender_service.dart';
import '../dokumente/dokumente_repository.dart';
import '../kunden/kunden_repository.dart';
import 'nachfragen_repository.dart';

/// Dialog zum Erfassen eines Schriftsatzes mit Nachfragen + dazugehöriger
/// Stellungnahme. Mehrere Q&A-Paare pro Schriftsatz möglich. Druck als
/// "Ergänzende Stellungnahme zum Gutachten" und Ablage in der Akte.
class NachfragenDialog extends ConsumerStatefulWidget {
  const NachfragenDialog({
    super.key,
    required this.auftrag,
    this.rueckfrage,
  });
  final AuftraegeData auftrag;
  final RueckfragenData? rueckfrage;

  @override
  ConsumerState<NachfragenDialog> createState() => _NachfragenDialogState();
}

class _NachfragenDialogState extends ConsumerState<NachfragenDialog> {
  late final _stellerName = TextEditingController(
      text: widget.rueckfrage?.stellerName ?? '');
  late final _betreff =
      TextEditingController(text: widget.rueckfrage?.betreff ?? '');
  late final _empfaenger =
      TextEditingController(text: widget.rueckfrage?.empfaenger ?? '');
  late final _gutachtenNummer = TextEditingController(
      text: widget.rueckfrage?.gutachtenBezugNummer ?? '');
  late final _bemerkung =
      TextEditingController(text: widget.rueckfrage?.bemerkung ?? '');

  late String _stellerArt = widget.rueckfrage?.stellerArt ?? 'gericht';
  late String _status = widget.rueckfrage?.status ?? 'offen';
  late DateTime? _schriftsatzVom = widget.rueckfrage?.schriftsatzVom;
  late DateTime? _gutachtenDatum = widget.rueckfrage?.gutachtenBezugDatum;

  late List<NachfrageEintrag> _fragen = _initialFragen();
  bool _saving = false;

  List<NachfrageEintrag> _initialFragen() {
    final r = widget.rueckfrage;
    if (r == null) {
      return [const NachfrageEintrag(nr: '1', frage: '', antwort: '')];
    }
    final list = decodeFragen(r.fragenJson);
    if (list.isNotEmpty) return List.of(list);
    // Migration aus altem Einzel-Frage-Schema
    if ((r.frage ?? '').isNotEmpty || (r.antwort ?? '').isNotEmpty) {
      return [
        NachfrageEintrag(
            nr: '1', frage: r.frage ?? '', antwort: r.antwort ?? ''),
      ];
    }
    return [const NachfrageEintrag(nr: '1', frage: '', antwort: '')];
  }

  @override
  void dispose() {
    _stellerName.dispose();
    _betreff.dispose();
    _empfaenger.dispose();
    _gutachtenNummer.dispose();
    _bemerkung.dispose();
    super.dispose();
  }

  Future<int> _speichern() async {
    final eintrag = RueckfragenCompanion(
      id: widget.rueckfrage == null
          ? const Value.absent()
          : Value(widget.rueckfrage!.id),
      auftragId: Value(widget.auftrag.id),
      datum: Value(widget.rueckfrage?.datum ?? DateTime.now()),
      stellerArt: Value(_stellerArt),
      stellerName: Value(_stellerName.text.trim()),
      schriftsatzVom: Value(_schriftsatzVom),
      empfaenger: Value(_empfaenger.text.trim()),
      betreff: Value(_betreff.text.trim()),
      bemerkung: Value(_bemerkung.text.trim()),
      status: Value(_status),
      gutachtenBezugDatum: Value(_gutachtenDatum),
      gutachtenBezugNummer: Value(_gutachtenNummer.text.trim()),
      fragenJson: Value(encodeFragen(_fragen)),
      erledigtAm: Value(_status == 'beantwortet' || _status == 'versendet'
          ? (widget.rueckfrage?.erledigtAm ?? DateTime.now())
          : null),
    );
    return ref.read(nachfragenRepositoryProvider).upsert(eintrag);
  }

  Future<void> _speichernUndSchliessen() async {
    setState(() => _saving = true);
    try {
      await _speichern();
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

  Future<StellungnahmePdfData> _baueDaten() async {
    final absender = await absenderFromSettings(ref);
    KundenData? gericht;
    if (widget.auftrag.kundeId != null) {
      gericht = await ref
          .read(kundenRepositoryProvider)
          .byId(widget.auftrag.kundeId!);
    }
    final id = await _speichern();
    final saved = await ref.read(nachfragenRepositoryProvider).byId(id);
    return StellungnahmePdfData(
      auftrag: widget.auftrag,
      gericht: gericht,
      absender: absender,
      datum: DateTime.now(),
      rueckfrage: saved!,
      fragen: _fragen,
    );
  }

  Future<void> _vorschau() async {
    setState(() => _saving = true);
    try {
      await previewStellungnahmePdf(await _baueDaten());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _druckenUndArchivieren() async {
    setState(() => _saving = true);
    try {
      final daten = await _baueDaten();
      final bytes = await buildStellungnahmePdf(daten);
      final dateiname =
          'Stellungnahme_${(widget.auftrag.aktenzeichen ?? "").replaceAll(RegExp(r"[^A-Za-z0-9-]"), "_")}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf';
      await ref.read(dokumenteRepositoryProvider).upsert(
            DokumenteCompanion.insert(
              titel: Value(dateiname),
              mimeType: const Value('application/pdf'),
              dateigroesse: Value(bytes.length),
              daten: Value(bytes),
              auftragId: Value(widget.auftrag.id),
              kategorie: const Value('Ergänzende Stellungnahme'),
              datum: Value(DateTime.now()),
              beschreibung: Value(
                  'Stellungnahme zu Schriftsatz ${_stellerName.text.trim()}'
                  ' vom ${_schriftsatzVom == null ? "—" : DateFormat('dd.MM.yyyy').format(_schriftsatzVom!)}'),
            ),
          );
      await previewStellungnahmePdf(daten);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Stellungnahme als PDF in der Akte abgelegt (Tab „Dokumente").')));
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
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 820),
        child: Column(
          children: [
            _kopf(context),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _kopfdaten(),
                    const SizedBox(height: 20),
                    _fragenBlock(),
                    const SizedBox(height: 12),
                    LabeledField(
                      'Interne Bemerkung (nicht im PDF)',
                      TextFormField(
                        controller: _bemerkung,
                        minLines: 2,
                        maxLines: 4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _fuss(context),
          ],
        ),
      ),
    );
  }

  Widget _kopf(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.help_outline),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.rueckfrage == null
                      ? 'Neuer Schriftsatz mit Nachfragen · ${widget.auftrag.aktenzeichen ?? ""}'
                      : 'Nachfragen bearbeiten · ${widget.auftrag.aktenzeichen ?? ""}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Fragen erfassen, Stellungnahme verfassen, als PDF drucken und in der Akte ablegen',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(),
          ),
        ],
      ),
    );
  }

  Widget _kopfdaten() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: LabeledField(
                'Steller',
                DropdownButtonFormField<String>(
                  initialValue: _stellerArt,
                  items: const [
                    DropdownMenuItem(value: 'gericht', child: Text('Gericht')),
                    DropdownMenuItem(
                        value: 'anwalt_klaeger',
                        child: Text('Anwalt Kläger')),
                    DropdownMenuItem(
                        value: 'anwalt_beklagter',
                        child: Text('Anwalt Beklagter')),
                    DropdownMenuItem(
                        value: 'auftraggeber', child: Text('Auftraggeber')),
                    DropdownMenuItem(
                        value: 'versicherung', child: Text('Versicherung')),
                    DropdownMenuItem(
                        value: 'sonstiges', child: Text('Sonstiges')),
                  ],
                  onChanged: (v) =>
                      setState(() => _stellerArt = v ?? 'gericht'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: LabeledField(
                'Steller-Name (Richter, Anwalt …)',
                TextFormField(controller: _stellerName),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DateField(
                label: 'Schriftsatz vom',
                value: _schriftsatzVom,
                onChanged: (d) => setState(() => _schriftsatzVom = d),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: LabeledField(
                'Empfänger der Stellungnahme (Briefanrede)',
                TextFormField(
                  controller: _empfaenger,
                  decoration: const InputDecoration(
                    hintText: 'z. B. „Sehr geehrter Herr Richter Dr. …"',
                  ),
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
                    DropdownMenuItem(value: 'offen', child: Text('offen')),
                    DropdownMenuItem(
                        value: 'in_bearbeitung',
                        child: Text('in Bearbeitung')),
                    DropdownMenuItem(
                        value: 'beantwortet', child: Text('beantwortet')),
                    DropdownMenuItem(
                        value: 'versendet', child: Text('versendet')),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'offen'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LabeledField(
          'Betreff',
          TextFormField(
            controller: _betreff,
            decoration: const InputDecoration(
                hintText: 'z. B. „Nachfragen zum Gutachten vom 15.04.2026"'),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: LabeledField(
                'Bezugs-Gutachten · Nummer',
                TextFormField(
                  controller: _gutachtenNummer,
                  decoration: const InputDecoration(
                      hintText: 'z. B. AW-0001-G1'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DateField(
                label: 'Bezugs-Gutachten · Datum',
                value: _gutachtenDatum,
                onChanged: (d) => setState(() => _gutachtenDatum = d),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _fragenBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Fragen & Stellungnahme',
                style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Frage hinzufügen'),
              onPressed: () => setState(() {
                _fragen = [
                  ..._fragen,
                  NachfrageEintrag(
                    nr: '${_fragen.length + 1}',
                    frage: '',
                    antwort: '',
                  ),
                ];
              }),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < _fragen.length; i++) _frageCard(i),
      ],
    );
  }

  Widget _frageCard(int i) {
    final f = _fragen[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 80,
                child: TextFormField(
                  initialValue: f.nr,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Nr.',
                  ),
                  onChanged: (v) => _fragen[i] = f.copyWith(nr: v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Frage ${i + 1}',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Frage entfernen',
                onPressed: _fragen.length <= 1
                    ? null
                    : () => setState(() => _fragen = [..._fragen]..removeAt(i)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: f.frage,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Frage des Stellers',
              hintText:
                  'Wortlaut der Frage / des Beweisbeschluss-Abschnitts …',
            ),
            onChanged: (v) => _fragen[i] = f.copyWith(frage: v),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: f.antwort,
            minLines: 3,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Stellungnahme / Antwort',
              hintText: 'Sachverständige Antwort …',
            ),
            onChanged: (v) => _fragen[i] = f.copyWith(antwort: v),
          ),
        ],
      ),
    );
  }

  Widget _fuss(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          if (widget.rueckfrage != null)
            TextButton.icon(
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Löschen'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: _saving ? null : () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Schriftsatz löschen?'),
                    content: const Text(
                        'Der Schriftsatz und alle erfassten Fragen werden entfernt.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Abbrechen')),
                      FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.red),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Löschen')),
                    ],
                  ),
                );
                if (ok == true) {
                  await ref
                      .read(nachfragenRepositoryProvider)
                      .delete(widget.rueckfrage!.id);
                  if (!mounted) return;
                  Navigator.of(context, rootNavigator: true).pop();
                }
              },
            ),
          const Spacer(),
          TextButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('Abbrechen'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('Speichern'),
            onPressed: _saving ? null : _speichernUndSchliessen,
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.print_outlined, size: 16),
            label: const Text('Vorschau'),
            onPressed: _saving ? null : _vorschau,
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.archive_outlined, size: 16),
            label: const Text('Drucken & in Akte ablegen'),
            onPressed: _saving ? null : _druckenUndArchivieren,
          ),
        ],
      ),
    );
  }
}
