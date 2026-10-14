import 'dart:convert';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../shared/pdf/befangenheit_pdf.dart';
import '../../../shared/pdf/mehrkosten_pdf.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../angebote/anschreiben/anschreiben_repository.dart';
import '../../angebote/anschreiben/anschreiben_screen.dart';
import '../../system/einstellungen/absender_service.dart';

import '../../../core/ai/beweisbeschluss_scanner.dart';
import '../../../data/sync/storage_service.dart';
import '../auftraege/auftrag_gm_extras.dart';
import '../dokumente/dokumente_repository.dart';
import '../gutachten/gutachten_repository.dart';
import '../kunden/kunden_repository.dart';
import 'beweisfragen.dart';
import 'beweisfragen_chat_dialog.dart';

/// Tab "Gerichtssache" innerhalb der Akte. Bündelt drei gerichtsspezifische
/// Bereiche: Befangenheits-Erklärung (§§ 406/407 ZPO), Mehrkostenanzeige
/// (§ 8a Abs. 4 JVEG) und strukturierte Beweisfragen aus dem Beweisbeschluss.
class GerichtssacheTab extends ConsumerWidget {
  const GerichtssacheTab({super.key, required this.auftrag});
  final AuftraegeData auftrag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final istGericht = auftrag.art == 'gericht' ||
        auftrag.art == 'beweissicherung';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!istGericht)
            _hinweis(context),
          _BefangenheitCard(auftrag: auftrag),
          const SizedBox(height: 12),
          _MehrkostenCard(auftrag: auftrag),
          const SizedBox(height: 12),
          _GerichtsSchnellbriefeCard(auftrag: auftrag),
          const SizedBox(height: 12),
          _BeweisfragenCard(auftrag: auftrag),
        ],
      ),
    );
  }

  Widget _hinweis(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 16, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Diese Funktionen sind primär für Gerichtsakten relevant. '
              'Sie können sie bei dieser Akte trotzdem nutzen, falls passend.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Block 1: Befangenheits-Prüfung gem. §§ 406, 407 ZPO.
class _BefangenheitCard extends ConsumerStatefulWidget {
  const _BefangenheitCard({required this.auftrag});
  final AuftraegeData auftrag;

  @override
  ConsumerState<_BefangenheitCard> createState() =>
      _BefangenheitCardState();
}

class _BefangenheitCardState extends ConsumerState<_BefangenheitCard> {
  late DateTime? _geprueftAm = widget.auftrag.befangenheitsGeprueftAm;
  late String _ergebnis =
      widget.auftrag.befangenheitsErgebnis ?? 'unbefangen';
  late final _notiz = TextEditingController(
      text: widget.auftrag.befangenheitsNotiz ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _notiz.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _BefangenheitCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auftrag != widget.auftrag) {
      setState(() {
        _geprueftAm = widget.auftrag.befangenheitsGeprueftAm;
        _ergebnis = widget.auftrag.befangenheitsErgebnis ?? 'unbefangen';
        if (_notiz.text != (widget.auftrag.befangenheitsNotiz ?? '')) {
          _notiz.text = widget.auftrag.befangenheitsNotiz ?? '';
        }
      });
    }
  }

  Future<void> _speichern() async {
    setState(() => _saving = true);
    try {
      final db = ref.read(appDatabaseProvider);
      await (db.update(db.auftraege)
            ..where((t) => t.id.equals(widget.auftrag.id)))
          .write(AuftraegeCompanion(
        befangenheitsGeprueftAm: Value(_geprueftAm),
        befangenheitsErgebnis: Value(_ergebnis),
        befangenheitsNotiz: Value(_notiz.text.trim()),
        updatedAt: Value(DateTime.now()),
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Befangenheits-Prüfung gespeichert.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _druckenUndArchivieren() async {
    setState(() => _saving = true);
    try {
      await _speichern();
      final absender = await absenderFromSettings(ref);
      KundenData? gericht;
      if (widget.auftrag.kundeId != null) {
        gericht = await ref
            .read(kundenRepositoryProvider)
            .byId(widget.auftrag.kundeId!);
      }
      final daten = BefangenheitPdfData(
        auftrag: widget.auftrag,
        gericht: gericht,
        absender: absender,
        datum: DateTime.now(),
        ergebnis: _ergebnis,
        notiz: _notiz.text.trim(),
      );
      final bytes = await buildBefangenheitPdf(daten);
      final dateiname =
          'Befangenheit_${(widget.auftrag.aktenzeichen ?? "").replaceAll(RegExp(r"[^A-Za-z0-9-]"), "_")}.pdf';
      await ref.read(dokumenteRepositoryProvider).upsert(
            DokumenteCompanion.insert(
              titel: Value(dateiname),
              mimeType: const Value('application/pdf'),
              dateigroesse: Value(bytes.length),
              daten: Value(bytes),
              auftragId: Value(widget.auftrag.id),
              kategorie: const Value('Befangenheits-Erklärung'),
              datum: Value(DateTime.now()),
            ),
          );
      await previewBefangenheitPdf(daten);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Befangenheits-Erklärung als PDF in der Akte abgelegt.')));
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
    return _kartenRahmen(
      context,
      Icons.verified_user_outlined,
      'Befangenheits-Prüfung',
      '§§ 406, 407 ZPO — vom SV vor Annahme des Auftrags zu erklären.',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DateField(
                  label: 'Geprüft am',
                  value: _geprueftAm,
                  onChanged: (d) => setState(() => _geprueftAm = d),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LabeledField(
                  'Ergebnis',
                  DropdownButtonFormField<String>(
                    initialValue: _ergebnis,
                    items: const [
                      DropdownMenuItem(
                          value: 'unbefangen',
                          child: Text('Keine Befangenheit')),
                      DropdownMenuItem(
                          value: 'befangen',
                          child:
                              Text('Befangenheit angezeigt')),
                    ],
                    onChanged: (v) =>
                        setState(() => _ergebnis = v ?? 'unbefangen'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LabeledField(
            'Erläuterung (optional)',
            TextFormField(
              controller: _notiz,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText:
                    'z. B. „Keine persönlichen, geschäftlichen oder verwandtschaftlichen Beziehungen zu den Beteiligten."',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Spacer(),
              OutlinedButton.icon(
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('Speichern'),
                onPressed: _saving ? null : _speichern,
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.archive_outlined, size: 16),
                label: const Text('Drucken & in Akte ablegen'),
                onPressed: _saving ? null : _druckenUndArchivieren,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Block 2: Mehrkostenanzeige § 8a Abs. 4 JVEG.
class _MehrkostenCard extends ConsumerStatefulWidget {
  const _MehrkostenCard({required this.auftrag});
  final AuftraegeData auftrag;

  @override
  ConsumerState<_MehrkostenCard> createState() => _MehrkostenCardState();
}

class _MehrkostenCardState extends ConsumerState<_MehrkostenCard> {
  late DateTime? _angezeigtAm = widget.auftrag.mehrkostenAnzeigeAm;
  late final _bisher = TextEditingController(
      text: (widget.auftrag.kostenLimit ??
              widget.auftrag.kostenvorschuss ??
              0)
          .toStringAsFixed(2)
          .replaceAll('.', ','));
  late final _neu = TextEditingController(
      text: (widget.auftrag.mehrkostenBetrag ?? 0)
          .toStringAsFixed(2)
          .replaceAll('.', ','));
  late final _begruendung = TextEditingController(
      text: widget.auftrag.mehrkostenBegruendung ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _bisher.dispose();
    _neu.dispose();
    _begruendung.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _MehrkostenCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auftrag != widget.auftrag) {
      setState(() {
        _angezeigtAm = widget.auftrag.mehrkostenAnzeigeAm;
        final bisherNeu = (widget.auftrag.kostenLimit ?? widget.auftrag.kostenvorschuss ?? 0).toStringAsFixed(2).replaceAll('.', ',');
        if (_bisher.text != bisherNeu) _bisher.text = bisherNeu;
        final neuNeu = (widget.auftrag.mehrkostenBetrag ?? 0).toStringAsFixed(2).replaceAll('.', ',');
        if (_neu.text != neuNeu) _neu.text = neuNeu;
        if (_begruendung.text != (widget.auftrag.mehrkostenBegruendung ?? '')) {
          _begruendung.text = widget.auftrag.mehrkostenBegruendung ?? '';
        }
      });
    }
  }

  double _d(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.').trim()) ?? 0;

  Future<void> _speichern() async {
    setState(() => _saving = true);
    try {
      final db = ref.read(appDatabaseProvider);
      await (db.update(db.auftraege)
            ..where((t) => t.id.equals(widget.auftrag.id)))
          .write(AuftraegeCompanion(
        mehrkostenAnzeigeAm: Value(_angezeigtAm),
        mehrkostenBetrag: Value(_d(_neu)),
        mehrkostenBegruendung: Value(_begruendung.text.trim()),
        updatedAt: Value(DateTime.now()),
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mehrkostenanzeige gespeichert.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _druckenUndArchivieren() async {
    setState(() => _saving = true);
    try {
      await _speichern();
      final absender = await absenderFromSettings(ref);
      KundenData? gericht;
      if (widget.auftrag.kundeId != null) {
        gericht = await ref
            .read(kundenRepositoryProvider)
            .byId(widget.auftrag.kundeId!);
      }
      final daten = MehrkostenPdfData(
        auftrag: widget.auftrag,
        gericht: gericht,
        absender: absender,
        datum: _angezeigtAm ?? DateTime.now(),
        bisherigerKostenrahmen: _d(_bisher),
        neuerKostenrahmen: _d(_neu),
        begruendung: _begruendung.text.trim(),
      );
      final bytes = await buildMehrkostenPdf(daten);
      final dateiname =
          'Mehrkostenanzeige_${(widget.auftrag.aktenzeichen ?? "").replaceAll(RegExp(r"[^A-Za-z0-9-]"), "_")}.pdf';
      await ref.read(dokumenteRepositoryProvider).upsert(
            DokumenteCompanion.insert(
              titel: Value(dateiname),
              mimeType: const Value('application/pdf'),
              dateigroesse: Value(bytes.length),
              daten: Value(bytes),
              auftragId: Value(widget.auftrag.id),
              kategorie: const Value('Mehrkostenanzeige § 8a JVEG'),
              datum: Value(DateTime.now()),
            ),
          );
      await previewMehrkostenPdf(daten);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Mehrkostenanzeige als PDF in der Akte abgelegt.')));
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
    final money = NumberFormat.currency(
        locale: 'de_DE', symbol: '€', decimalDigits: 2);
    final differenz = _d(_neu) - _d(_bisher);
    return _kartenRahmen(
      context,
      Icons.trending_up_outlined,
      'Mehrkostenanzeige § 8a Abs. 4 JVEG',
      'Anzeige an das Gericht, wenn der bisher angesetzte Kostenrahmen überschritten wird.',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DateField(
                  label: 'Angezeigt am',
                  value: _angezeigtAm,
                  onChanged: (d) => setState(() => _angezeigtAm = d),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LabeledField(
                  'Bisheriger Rahmen (€)',
                  TextFormField(
                    controller: _bisher,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LabeledField(
                  'Neuer Rahmen (€)',
                  TextFormField(
                    controller: _neu,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 130,
                child: LabeledField(
                  'Mehrbedarf',
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 14),
                    decoration: BoxDecoration(
                      color: differenz > 0
                          ? Colors.orange.withValues(alpha: 0.12)
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      money.format(differenz),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: differenz > 0
                              ? Colors.orange[800]
                              : Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LabeledField(
            'Begründung des Mehraufwands',
            TextFormField(
              controller: _begruendung,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText:
                    'z. B. „Aufgrund der zusätzlich erforderlichen Bauteilöffnungen ergibt sich ein Mehraufwand von ca. 8 Stunden …"',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Spacer(),
              OutlinedButton.icon(
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('Speichern'),
                onPressed: _saving ? null : _speichern,
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.archive_outlined, size: 16),
                label: const Text('Drucken & in Akte ablegen'),
                onPressed: _saving ? null : _druckenUndArchivieren,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Block 3: Strukturierte Beweisfragen aus dem Beweisbeschluss.
class _BeweisfragenCard extends ConsumerStatefulWidget {
  const _BeweisfragenCard({required this.auftrag});
  final AuftraegeData auftrag;

  @override
  ConsumerState<_BeweisfragenCard> createState() =>
      _BeweisfragenCardState();
}

class _BeweisfragenCardState extends ConsumerState<_BeweisfragenCard> {
  late List<Beweisfrage> _liste = decodeBeweisfragen(
      widget.auftrag.beweisfragenJson);
  bool _saving = false;

  @override
  void didUpdateWidget(covariant _BeweisfragenCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auftrag != widget.auftrag) {
      setState(() {
        _liste = decodeBeweisfragen(widget.auftrag.beweisfragenJson);
      });
    }
  }

  Future<void> _speichern() async {
    setState(() => _saving = true);
    try {
      final db = ref.read(appDatabaseProvider);
      await (db.update(db.auftraege)
            ..where((t) => t.id.equals(widget.auftrag.id)))
          .write(AuftraegeCompanion(
        beweisfragenJson: Value(encodeBeweisfragen(_liste)),
        updatedAt: Value(DateTime.now()),
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_liste.length} Beweisfragen gespeichert.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

// ... (in _BeweisfragenCardState)
  Future<void> _scannen() async {
    final db = ref.read(appDatabaseProvider);
    final dokumente = await (db.select(db.dokumente)
          ..where((t) => t.auftragId.equals(widget.auftrag.id))
          )
        .get();

    if (!mounted) return;
    if (dokumente.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Keine PDF-Dokumente in dieser Akte gefunden.')));
      return;
    }

    final doc = await showDialog<DokumenteData>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Beweisbeschluss auswählen'),
        content: SizedBox(
          width: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: dokumente.length,
            itemBuilder: (ctx, i) {
              final d = dokumente[i];
              return ListTile(
                title: Text(d.titel ?? d.pfad ?? 'Unbenannt'),
                subtitle: Text(d.beschreibung ?? ''),
                onTap: () => Navigator.of(ctx).pop(d),
              );
            },
          ),
        ),
      ),
    );

    if (doc == null || !mounted) return;

    setState(() => _saving = true);
    try {
      Uint8List? bytes = doc.daten;
      if (bytes == null && doc.storagePfad != null) {
        final storage = ref.read(storageServiceProvider);
        bytes = await storage.downloadBytes(doc.storagePfad!);
      }
      if (bytes == null) throw Exception('Dokument konnte nicht geladen werden.');

      final fragenMaps = await extrahiereBeweisfragen(
        ref: ref,
        bytes: bytes,
        mimeType: doc.mimeType ?? 'application/pdf',
      );

      if (!mounted) return;
      if (fragenMaps.isEmpty) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Keine Fragen im Dokument gefunden.')));
         return;
      }
      
      setState(() {
        _liste = [
          ..._liste,
          ...fragenMaps.map((m) => Beweisfrage(
            nr: m['nr']?.toString() ?? '${_liste.length + 1}',
            frage: m['frage']?.toString() ?? '',
            einschaetzung: m['einschaetzung']?.toString(),
          ))
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${fragenMaps.length} Fragen extrahiert.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _chatOeffnen() {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => BeweisfragenChatDialog(fragen: _liste),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _kartenRahmen(
      context,
      Icons.gavel_outlined,
      'Beweisfragen aus dem Beweisbeschluss',
      'Strukturierte Liste — wird automatisch in Stellungnahmen und Gutachten als nummerierter Block übernommen.',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_liste.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Noch keine Beweisfragen erfasst.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            for (var i = 0; i < _liste.length; i++) _frageZeile(i),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Hinzufügen'),
                onPressed: () => setState(() {
                  _liste = [
                    ..._liste,
                    Beweisfrage(nr: '${_liste.length + 1}', frage: ''),
                  ];
                }),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.document_scanner_outlined, size: 16),
                label: const Text('Scannen'),
                onPressed: _saving ? null : _scannen,
              ),
              if (_liste.isNotEmpty) ...[
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: const Text('Mit KI diskutieren'),
                  onPressed: _saving ? null : _chatOeffnen,
                ),
              ],
              const Spacer(),
              FilledButton.icon(
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined, size: 16),
                label: const Text('Speichern'),
                onPressed: _saving ? null : _speichern,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _frageZeile(int i) {
    final f = _liste[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border:
            Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: TextFormField(
              initialValue: f.nr,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Nr.',
              ),
              onChanged: (v) => _liste[i] = f.copyWith(nr: v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  initialValue: f.frage,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Wortlaut der Beweisfrage …',
                  ),
                  onChanged: (v) => _liste[i] = f.copyWith(frage: v),
                ),
                if (f.einschaetzung != null && f.einschaetzung!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.auto_awesome, size: 14, color: Theme.of(context).colorScheme.onTertiaryContainer),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            f.einschaetzung!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Frage entfernen',
            onPressed: () =>
                setState(() => _liste = [..._liste]..removeAt(i)),
          ),
        ],
      ),
    );
  }
}

Widget _kartenRahmen(BuildContext context, IconData ic, String titel,
    String hinweis, Widget body) {
  return Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(ic, color: AppTheme.accent600),
              const SizedBox(width: 8),
              Text(titel, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 2),
          Text(hinweis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          body,
        ],
      ),
    ),
  );
}

/// Block 4: 1-Klick Gerichts-Schnellbriefe (mit automatischer Platzhalter-Auflösung
/// inkl. Gerichtsakten-Bänden, Ausfertigungen und Vorschuss).
class _GerichtsSchnellbriefeCard extends ConsumerWidget {
  const _GerichtsSchnellbriefeCard({required this.auftrag});
  final AuftraegeData auftrag;

  String _plainTextToQuillDelta(String text) {
    final zeilen = text.split('\n');
    final ops = <Map<String, dynamic>>[];
    for (final z in zeilen) {
      if (z.isNotEmpty) ops.add({'insert': z});
      ops.add({'insert': '\n'});
    }
    if (ops.isEmpty) ops.add({'insert': '\n'});
    return jsonEncode(ops);
  }

  Future<void> _erzeugeUndOeffne(
    BuildContext context,
    WidgetRef ref, {
    required String betreffTemplate,
    required String bodyTemplate,
  }) async {
    final db = ref.read(appDatabaseProvider);
    KundenData? gericht;
    if (auftrag.kundeId != null) {
      gericht = await ref
          .read(kundenRepositoryProvider)
          .byId(auftrag.kundeId!);
    }
    final betreff = applyVorlagenPlatzhalter(
      betreffTemplate,
      auftrag: auftrag,
      kunde: gericht,
    );
    final body = applyVorlagenPlatzhalter(
      bodyTemplate,
      auftrag: auftrag,
      kunde: gericht,
    );
    final delta = _plainTextToQuillDelta(body);
    final id = await db.into(db.anschreiben).insert(
          AnschreibenCompanion.insert(
            auftragId: Value(auftrag.id),
            kundeId: Value(auftrag.kundeId),
            datum: Value(DateTime.now()),
            betreff: Value(betreff),
            anrede: const Value('Sehr geehrte Damen und Herren,'),
            briefText: Value(body),
            inhaltJson: Value(delta),
            gruss: const Value('Mit freundlichen Grüßen'),
            status: const Value('entwurf'),
          ),
        );
    final saved = await (db.select(db.anschreiben)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (!context.mounted || saved == null) return;
    await showAnschreibenEditor(
      context,
      eintrag: AnschreibenWithKunde(saved, gericht, auftrag),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gm = AuftragGmExtras.fromAuftragExtras(auftrag.extras);
    final anzAusf = auftrag.anzahlAusfertigungen ?? 3;
    final hatBaende = gm.aktenbaende.isNotEmpty;

    return _kartenRahmen(
      context,
      Icons.mark_email_read_outlined,
      'Gerichts-Schnellbriefe (1-Klick-Schriftsätze)',
      'Erzeugt sofort ein fertig ausgefülltes Anschreiben an das Gericht inkl. Geschäftszeichen, Rubrum und Gerichtsakten-Bänden.',
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.assignment_turned_in_outlined, size: 16),
            label: const Text('Auftragseingangsbestätigung (§ 407a ZPO)'),
            onPressed: () => _erzeugeUndOeffne(
              context,
              ref,
              betreffTemplate:
                  r'Auftragseingangsbestätigung & Prüfung nach § 407a ZPO — Az.: $GerichtsAZ',
              bodyTemplate:
                  'In Sachen: {{sache}}\n'
                  'Geschäftszeichen: {{gerichts_az}}\n\n'
                  'in dem oben genannten Rechtsstreit bestätige ich den Eingang des Beweisbeschlusses{{beweisbeschluss1}} sowie der übersandten Gerichtsakten:\n'
                  '${hatBaende ? "{{aktenbaende_rueckgabe}}\n\n" : "\n"}'
                  'Gemäß § 407a ZPO habe ich unverzüglich geprüft, ob der Auftrag in mein Fachgebiet fällt und ob Gründe vorliegen, die geeignet sind, Misstrauen gegen meine Unparteilichkeit zu rechtfertigen. Solche Gründe liegen nicht vor.\n\n'
                  'Der Ortstermin wird in Kürze mit den Parteien abgestimmt; das Gericht erhält gesondert Nachricht.',
            ),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.euro_outlined, size: 16),
            label: const Text('Vorschussanforderung / Erinnerung'),
            onPressed: () => _erzeugeUndOeffne(
              context,
              ref,
              betreffTemplate:
                  r'Auslagenvorschuss — Az.: $GerichtsAZ ($Sache)',
              bodyTemplate:
                  'In Sachen: {{sache}}\n'
                  'Geschäftszeichen: {{gerichts_az}}\n\n'
                  'in dem oben genannten Verfahren bitte ich höflich um Mitteilung, ob der angeforderte Auslagenvorschuss${(auftrag.kostenvorschuss ?? 0) > 0 ? " in Höhe von {{vorschuss}}" : ""} bereits eingezahlt wurde bzw. um entsprechende Anforderung bei der beweispflichtigen Partei, damit mit der Vorbereitung und Durchführung des Ortstermins begonnen werden kann.',
            ),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_copy_outlined, size: 16),
            label: const Text('Akten- / Beiaktenanforderung'),
            onPressed: () => _erzeugeUndOeffne(
              context,
              ref,
              betreffTemplate:
                  r'Anforderung weiterer Unterlagen / Beiakten — Az.: $GerichtsAZ',
              bodyTemplate:
                  'In Sachen: {{sache}}\n'
                  'Geschäftszeichen: {{gerichts_az}}\n\n'
                  'zur sachgerechten Beantwortung der Beweisfragen werden noch folgende Unterlagen bzw. Beiakten benötigt:\n\n'
                  '• Baubeschreibung / Ausführungspläne\n'
                  '• Bautagebücher / Abnahmeprotokolle\n\n'
                  'Ich bitte das Gericht höflich, den Parteien die Vorlage der genannten Unterlagen aufzugeben.',
            ),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.more_time_outlined, size: 16),
            label: const Text('Antrag Fristverlängerung (§ 411 ZPO)'),
            onPressed: () => _erzeugeUndOeffne(
              context,
              ref,
              betreffTemplate:
                  r'Antrag auf Fristverlängerung — Az.: $GerichtsAZ ($Sache)',
              bodyTemplate:
                  'In Sachen: {{sache}}\n'
                  'Geschäftszeichen: {{gerichts_az}}\n\n'
                  'in dem oben genannten Verfahren wurde eine Frist zur Gutachtenerstattung${auftrag.fristAm != null ? " bis zum {{frist}}" : ""} gesetzt.\n\n'
                  'Aufgrund des Umfangs der erforderlichen Untersuchungen und der Terminabstimmung mit den Beteiligten bitte ich höflich, die Frist zur Einreichung des schriftlichen Gutachtens angemessen zu verlängern.',
            ),
          ),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.send_and_archive_outlined, size: 16),
            label: Text(
                'Gutachtenversand ($anzAusf-fach) & Aktenrückgabe'),
            onPressed: () => _erzeugeUndOeffne(
              context,
              ref,
              betreffTemplate:
                  r'Übersendung des Sachverständigengutachtens & Aktenrückgabe — Az.: $GerichtsAZ',
              bodyTemplate:
                  'In Sachen: {{sache}}\n'
                  'Geschäftszeichen: {{gerichts_az}}\n\n'
                  'in dem oben genannten Rechtsstreit überreiche ich anbei mein schriftliches Sachverständigengutachten in $anzAusf-facher Ausfertigung (1 Original für die Gerichtsakte sowie ${anzAusf > 1 ? "${anzAusf - 1} beglaubigte Abschriften für die Parteien" : "Abschriften"}).\n\n'
                  'Gleichzeitig reiche ich die mir überlassenen Gerichtsakten vollständig zu meiner Entlastung zurück:\n'
                  '${hatBaende ? "{{aktenbaende_rueckgabe}}" : "• Gerichtsakte zum Az. {{gerichts_az}}"}\n\n'
                  'Meine Liquidation gemäß JVEG füge ich mit der Bitte um Anweisung bei.',
            ),
          ),
        ],
      ),
    );
  }
}
