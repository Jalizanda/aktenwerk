import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/geo/plz_autofill.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../features/akten/auftraege/auto_akte.dart';
import '../../../features/akten/kunden/kunden_picker.dart';
import '../../../features/akten/kunden/kunden_repository.dart';
import '../../../features/akten/rechnungen/rechnungen_repository.dart';
import '../../../features/akten/rechnungen/rechnungen_screen.dart';
import '../../../features/akten/workflow/dokument_workflow.dart';
import '../../../features/system/benutzer/benutzer_repository.dart';
import '../../../features/system/einstellungen/absender_service.dart';
import '../../../features/system/einstellungen/einstellungen_repository.dart';
import '../../../features/system/einstellungen/nummernkreis_service.dart';
import '../../../shared/pdf/document_pdf.dart';
import '../../../shared/pdf/pdf_archiver.dart';
import '../../../shared/positionen/position_model.dart';
import '../../../shared/positionen/positions_editor.dart';
import '../../../shared/widgets/badges.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import '../angebote/angebote_repository.dart';

class AbFilter {
  final String query;
  const AbFilter({this.query = ''});
  AbFilter copyWith({String? query}) => AbFilter(query: query ?? this.query);
}

final abFilterProvider = StateProvider<AbFilter>((ref) => const AbFilter());

final abListProvider = StreamProvider<List<AngebotWithKunde>>((ref) {
  final f = ref.watch(abFilterProvider);
  return ref
      .watch(angeboteRepositoryProvider)
      .watchAll(query: f.query, status: 'auftragsbestaetigung');
});

class AuftragsbestaetigungenScreen extends ConsumerStatefulWidget {
  const AuftragsbestaetigungenScreen({super.key});

  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');
  static final _moneyFmt =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

  @override
  ConsumerState<AuftragsbestaetigungenScreen> createState() =>
      _AuftragsbestaetigungenScreenState();
}

class _AuftragsbestaetigungenScreenState
    extends ConsumerState<AuftragsbestaetigungenScreen> {
  int _sortCol = 1;
  bool _sortAsc = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(abListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.assignment_turned_in_outlined,
          title: 'Auftragsbestätigungen',
          subtitle: 'Eigenständig oder aus Angeboten erstellt',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neue AB'),
              onPressed: () => _show(context),
            ),
          ],
          searchHint: 'Suche AB-Nummer, Kunde, Betreff …',
          onSearchChanged: (v) =>
              ref.read(abFilterProvider.notifier).update((f) => f.copyWith(query: v)),
        ),
        async.maybeWhen(
          data: (items) => _AbKpiRow(items: items),
          orElse: () => const SizedBox.shrink(),
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) => items.isEmpty
                ? const EmptyListState(
                    icon: Icons.assignment_turned_in_outlined,
                    title: 'Keine Auftragsbestätigungen')
                : _buildTable(context, _sorted(items)),
          ),
        ),
      ],
    );
  }

  List<AngebotWithKunde> _sorted(List<AngebotWithKunde> items) {
    final list = [...items];
    int cmp<T extends Comparable>(T? a, T? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    }

    list.sort((a, b) {
      final c = switch (_sortCol) {
        0 => cmp(a.angebot.angebotsnummer, b.angebot.angebotsnummer),
        1 => cmp(a.angebot.datum, b.angebot.datum),
        2 => cmp(
            a.kunde == null ? null : kundeAnzeigename(a.kunde!).toLowerCase(),
            b.kunde == null ? null : kundeAnzeigename(b.kunde!).toLowerCase()),
        3 => cmp(
            (a.angebot.betreff ?? '').toLowerCase(),
            (b.angebot.betreff ?? '').toLowerCase()),
        4 => cmp(a.angebot.netto, b.angebot.netto),
        5 => cmp(a.angebot.brutto, b.angebot.brutto),
        _ => 0,
      };
      return _sortAsc ? c : -c;
    });
    return list;
  }

  Widget _buildTable(BuildContext context, List<AngebotWithKunde> items) {
    DataColumn sortCol(String label, int i, {bool numeric = false}) =>
        DataColumn(
          label: Text(label),
          numeric: numeric,
          onSort: (col, asc) => setState(() {
            _sortCol = col;
            _sortAsc = asc;
          }),
        );
    return DataTableCard(
      child: DataTable(
        sortColumnIndex: _sortCol,
        sortAscending: _sortAsc,
        showCheckboxColumn: false,
        headingRowColor: WidgetStateProperty.all(
          Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        columns: [
          sortCol('AB-Nr.', 0),
          sortCol('Datum', 1),
          sortCol('Kunde', 2),
          sortCol('Betreff', 3),
          sortCol('Netto €', 4, numeric: true),
          sortCol('Brutto €', 5, numeric: true),
          const DataColumn(label: Text('Status')),
          const DataColumn(label: Text('')),
        ],
        rows: [
          for (final a in items)
            DataRow(
              onSelectChanged: (_) => _show(context, a),
              cells: [
                DataCell(
                  a.angebot.angebotsnummer != null
                      ? Text(
                          a.angebot.angebotsnummer!,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12),
                        )
                      : Text(
                          'Entwurf',
                          style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey.shade500),
                        ),
                ),
                DataCell(Text(AuftragsbestaetigungenScreen._dateFmt
                    .format(a.angebot.datum))),
                DataCell(
                    Text(a.kunde == null ? '—' : kundeAnzeigename(a.kunde!))),
                DataCell(SizedBox(
                  width: 280,
                  child: Text(
                    a.angebot.betreff ?? '',
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
                DataCell(Text(
                  AuftragsbestaetigungenScreen._moneyFmt
                      .format(a.angebot.netto),
                )),
                DataCell(Text(
                  AuftragsbestaetigungenScreen._moneyFmt
                      .format(a.angebot.brutto),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                )),
                DataCell(
                    _AbStatusBadge(pdfErstelltAm: a.angebot.pdfErstelltAm)),
                DataCell(Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'PDF-Vorschau',
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                      onPressed: () => _previewPdf(context, a),
                    ),
                    IconButton(
                      tooltip: 'Löschen',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () async =>
                          ref.read(angeboteRepositoryProvider).delete(a.angebot.id),
                    ),
                  ],
                )),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _show(BuildContext context, [AngebotWithKunde? a]) async {
    await showDialog(
      context: context,
      builder: (_) => _AbForm(eintrag: a),
    );
  }

  Future<void> _previewPdf(BuildContext context, AngebotWithKunde a) async {
    final absender = await absenderFromSettings(ref);
    final data = PdfDocumentData(
      dokumentTyp: 'Auftragsbestätigung',
      dokumentNr: a.angebot.angebotsnummer,
      datum: a.angebot.datum,
      betreff: a.angebot.betreff,
      positionen: positionsFromJson(a.angebot.positionenJson),
      kopftext: a.angebot.kopftext,
      fusstext: a.angebot.fusstext,
      absender: absender,
      empfaenger: a.kunde,
      brutto: a.angebot.brutto,
      zahlungsbedingungen: a.angebot.bedingungen,
    );
    await previewDocumentPdf(data);
  }
}

class _AbStatusBadge extends StatelessWidget {
  const _AbStatusBadge({required this.pdfErstelltAm});
  final DateTime? pdfErstelltAm;

  @override
  Widget build(BuildContext context) {
    if (pdfErstelltAm != null) {
      return const PillBadge(
        text: 'Eingefroren',
        background: BadgeColors.greenBg,
        foreground: BadgeColors.greenFg,
      );
    }
    return const PillBadge(
      text: 'Entwurf',
      background: BadgeColors.blueBg,
      foreground: BadgeColors.blueFg,
    );
  }
}

class _AbKpiRow extends StatelessWidget {
  const _AbKpiRow({required this.items});
  final List<AngebotWithKunde> items;

  static final _moneyFmt =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

  @override
  Widget build(BuildContext context) {
    final aktiv = items.where((a) => a.angebot.pdfErstelltAm == null).toList();
    final eingefroren =
        items.where((a) => a.angebot.pdfErstelltAm != null).toList();

    final aktivSumme =
        aktiv.fold<double>(0, (s, a) => s + a.angebot.brutto);
    final eingefrorenSumme =
        eingefroren.fold<double>(0, (s, a) => s + a.angebot.brutto);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: KpiCard(
              icon: Icons.pending_actions_outlined,
              label: 'In Bearbeitung',
              value: _moneyFmt.format(aktivSumme),
              accent: BadgeColors.amberFg,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: KpiCard(
              icon: Icons.check_circle_outline,
              label: 'Versendet (eingefroren)',
              value: _moneyFmt.format(eingefrorenSumme),
              accent: BadgeColors.greenFg,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: KpiCard(
              icon: Icons.assignment_turned_in_outlined,
              label: 'Gesamt ABs',
              value: '${items.length}',
              accent: BadgeColors.blueFg,
            ),
          ),
        ],
      ),
    );
  }
}

class _AbForm extends ConsumerStatefulWidget {
  const _AbForm({this.eintrag});
  final AngebotWithKunde? eintrag;
  @override
  ConsumerState<_AbForm> createState() => _AbFormState();
}

class _AbFormState extends ConsumerState<_AbForm> {
  final _formKey = GlobalKey<FormState>();
  int? _kundeId;
  int? _auftragId;
  DateTime _datum = DateTime.now();
  late List<Position> _positionen;
  late final _nr =
      TextEditingController(text: widget.eintrag?.angebot.angebotsnummer ?? '');
  late final _betreff =
      TextEditingController(text: widget.eintrag?.angebot.betreff ?? '');
  late final _anfrage =
      TextEditingController(text: widget.eintrag?.angebot.anfrage ?? '');
  late final _objStrasse =
      TextEditingController(text: widget.eintrag?.angebot.objektStrasse ?? '');
  late final _objPlz =
      TextEditingController(text: widget.eintrag?.angebot.objektPlz ?? '');
  late final _objOrt =
      TextEditingController(text: widget.eintrag?.angebot.objektOrt ?? '');
  late final _bedingungen =
      TextEditingController(text: widget.eintrag?.angebot.bedingungen ?? '');
  late final _ust = TextEditingController(
      text: (widget.eintrag?.angebot.ustSatz ?? 19).toStringAsFixed(0));
  late final _notiz =
      TextEditingController(text: widget.eintrag?.angebot.notiz ?? '');
  late final _kopf =
      TextEditingController(text: widget.eintrag?.angebot.kopftext ?? '');
  late final _fuss =
      TextEditingController(text: widget.eintrag?.angebot.fusstext ?? '');
  bool _saving = false;
  DateTime? _pdfErstelltAm;
  int? _savedId;
  late final VoidCallback _plzAutoFillDispose;

  bool get _eingefroren => _pdfErstelltAm != null;
  bool get _isEdit => widget.eintrag != null;

  @override
  void initState() {
    super.initState();
    final a = widget.eintrag?.angebot;
    _kundeId = a?.kundeId;
    _auftragId = a?.auftragId;
    _datum = a?.datum ?? DateTime.now();
    _positionen = positionsFromJson(a?.positionenJson);
    _pdfErstelltAm = a?.pdfErstelltAm;
    _savedId = a?.id;
    _plzAutoFillDispose = attachPlzAutoFill(_objPlz, _objOrt);
    if (widget.eintrag == null) _prefill();
  }

  Future<void> _prefill() async {
    // Nummer wird NICHT vorab reserviert — sie wird erst beim
    // Drucken & Einfrieren vergeben (verhindert Lücken im Nummernkreis).
    final fuss = await ref
        .read(einstellungenRepositoryProvider)
        .get(SettingsKeys.angebotFusstext);
    if (mounted && _fuss.text.isEmpty) {
      if (fuss != null && fuss.trim().isNotEmpty) {
        _fuss.text = fuss;
      } else {
        try {
          final benutzer =
              await ref.read(benutzerRepositoryProvider).getActive();
          final name = [benutzer?.vorname, benutzer?.nachname]
              .whereType<String>()
              .where((s) => s.trim().isNotEmpty)
              .join(' ');
          final titel = (benutzer?.titel ?? '').trim();
          _fuss.text = [
            'Mit freundlichen Grüßen',
            '',
            if (name.isNotEmpty) name,
            if (titel.isNotEmpty) titel,
          ].join('\n');
        } catch (_) {
          _fuss.text = 'Mit freundlichen Grüßen';
        }
      }
    }
  }

  @override
  void dispose() {
    _plzAutoFillDispose();
    for (final c in [
      _nr, _betreff, _anfrage, _objStrasse, _objPlz, _objOrt,
      _bedingungen, _ust, _notiz, _kopf, _fuss,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save({bool close = true}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    if (!_isEdit && _auftragId == null) {
      _auftragId = await ensureAkte(
        ref,
        auftragId: null,
        kundeId: _kundeId,
        betreff: _betreff.text.trim().isEmpty
            ? (_nr.text.trim().isEmpty ? 'Neue Akte' : 'AB ${_nr.text.trim()}')
            : _betreff.text.trim(),
      );
    }

    final totals = PositionsTotals.fromList(_positionen);
    final ust = double.tryParse(_ust.text.replaceAll(',', '.')) ?? 19;
    final companion = AngeboteCompanion(
      id: _isEdit ? Value(widget.eintrag!.angebot.id) : const Value.absent(),
      angebotsnummer: Value(_nr.text.trim()),
      kundeId: Value(_kundeId),
      auftragId: Value(_auftragId),
      betreff: _nt(_betreff),
      anfrage: _nt(_anfrage),
      objektStrasse: _nt(_objStrasse),
      objektPlz: _nt(_objPlz),
      objektOrt: _nt(_objOrt),
      bedingungen: _nt(_bedingungen),
      notiz: _nt(_notiz),
      ustSatz: Value(ust),
      datum: Value(_datum),
      status: const Value('auftragsbestaetigung'),
      netto: Value(totals.netto),
      ustBetrag: Value(totals.ust),
      brutto: Value(totals.brutto),
      positionenJson: Value(positionsToJson(_positionen)),
      kopftext: _nt(_kopf),
      fusstext: _nt(_fuss),
    );
    try {
      final id = await ref.read(angeboteRepositoryProvider).upsert(companion);
      if (mounted) setState(() => _savedId = id);
      if (close && mounted) {
        Navigator.of(context, rootNavigator: true).pop(true);
      } else if (mounted) {
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Future<void> _druckenUndEinfrieren() async {
    if (!_formKey.currentState!.validate()) return;
    // Belegnummer erst jetzt vergeben – verhindert Lücken durch abgebrochene Entwürfe
    if (_nr.text.trim().isEmpty) {
      final nr = await ref
          .read(nummernkreisServiceProvider)
          .nextNumber(NummernkreisTyp.auftragsbestaetigung);
      if (mounted) setState(() => _nr.text = nr);
    }
    await _save(close: false);
    if (!mounted) return;
    final id = _savedId;
    if (id == null) return;
    final data = await _buildPdfData();
    await previewDocumentPdf(data);
    if (!mounted) return;
    final db = ref.read(appDatabaseProvider);
    final now = DateTime.now();
    await (db.update(db.angebote)..where((t) => t.id.equals(id))).write(
      AngeboteCompanion(pdfErstelltAm: Value(now), updatedAt: Value(now)),
    );
    if (mounted) setState(() => _pdfErstelltAm = now);
    await archivePdfLokalUndCloud(
      ref,
      data,
      auftragId: _auftragId,
      prefix: 'belege/auftragsbestaetigungen',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('AB eingefroren und in der Akte abgelegt.')));
    }
  }

  Value<String?> _nt(TextEditingController c) {
    final v = c.text.trim();
    return Value(v.isEmpty ? null : v);
  }

  double get _ustSatz => double.tryParse(_ust.text.replaceAll(',', '.')) ?? 19;

  Future<PdfDocumentData> _buildPdfData() async {
    final absender = await absenderFromSettings(ref);
    final kundeId = _kundeId;
    final kunde = kundeId == null
        ? null
        : await ref.read(kundenRepositoryProvider).byId(kundeId);
    final fuss = await ref
        .read(einstellungenRepositoryProvider)
        .get(SettingsKeys.angebotFusstext);
    String? aktenzeichen;
    if (_auftragId != null) {
      final db = ref.read(appDatabaseProvider);
      final auftrag = await (db.select(db.auftraege)
            ..where((t) => t.id.equals(_auftragId!)))
          .getSingleOrNull();
      aktenzeichen = auftrag?.aktenzeichen;
    }
    final objekt = [
      _objStrasse.text.trim(),
      '${_objPlz.text.trim()} ${_objOrt.text.trim()}'.trim(),
    ].where((s) => s.isNotEmpty).join(', ');
    return PdfDocumentData(
      dokumentTyp: 'Auftragsbestätigung',
      dokumentNr: _nr.text.trim(),
      datum: _datum,
      betreff: _betreff.text.trim().isEmpty ? null : _betreff.text.trim(),
      aktenzeichen: aktenzeichen,
      sachverhalt:
          _anfrage.text.trim().isEmpty ? _betreff.text : _anfrage.text,
      objektAdresse: objekt.isEmpty ? null : objekt,
      positionen: _positionen,
      kopftext: _kopf.text.trim().isEmpty ? null : _kopf.text,
      fusstext: _fuss.text.trim().isEmpty ? fuss : _fuss.text,
      absender: absender,
      empfaenger: kunde,
      zahlungsbedingungen:
          _bedingungen.text.trim().isEmpty ? null : _bedingungen.text,
    );
  }

  Future<void> _convertToRechnung() async {
    // Save if not yet persisted; skip if already in DB (e.g. frozen)
    if (_savedId == null) {
      await _save(close: false);
      if (!mounted) return;
    }
    final id = _savedId;
    if (id == null) return;

    final db = ref.read(appDatabaseProvider);
    final abData = await (db.select(db.angebote)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (abData == null || !mounted) return;

    final workflow = ref.read(dokumentWorkflowProvider);
    final rId = await workflow.angebotToRechnung(abData, auftragId: _auftragId);
    if (!mounted) return;

    final rechnung = await ref.read(rechnungenRepositoryProvider).byId(rId);
    if (rechnung == null || !mounted) return;

    final kunde =
        _kundeId == null ? null : await ref.read(kundenRepositoryProvider).byId(_kundeId!);
    final auftrag = _auftragId == null
        ? null
        : await (db.select(db.auftraege)
              ..where((t) => t.id.equals(_auftragId!)))
            .getSingleOrNull();

    if (!mounted) return;
    await showRechnungEditor(
        context, eintrag: RechnungWithKunde(rechnung, kunde, auftrag));
    if (mounted) Navigator.of(context, rootNavigator: true).pop(true);
  }

  Future<void> _akteAnlegen() async {
    if (!_isEdit) return;
    final a = widget.eintrag!.angebot;
    if (a.auftragId != null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Akte anlegen?'),
        content: const Text(
            'Es wird eine neue Akte (AW-Nummer) aus dieser Auftragsbestätigung erzeugt.'),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(true),
              child: const Text('Akte anlegen')),
        ],
      ),
    );
    if (ok != true) return;
    final workflow = ref.read(dokumentWorkflowProvider);
    final auftragId =
        await workflow.angebotToAuftrag(widget.eintrag!.angebot);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Akte #$auftragId angelegt.')));
      Navigator.of(context, rootNavigator: true).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _eingefroren
        ? (_isEdit
            ? 'Auftragsbestätigung (eingefroren)'
            : 'Neue AB (eingefroren)')
        : (_isEdit
            ? 'Auftragsbestätigung bearbeiten'
            : 'Neue Auftragsbestätigung');
    return StandardFormDialog(
      title: title,
      saving: _saving,
      maxWidth: 1100,
      maxHeight: 900,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _eingefroren ? null : _save,
      onDelete: _isEdit && !_eingefroren
          ? () async => ref
              .read(angeboteRepositoryProvider)
              .delete(widget.eintrag!.angebot.id)
          : null,
      footerLeading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_eingefroren)
            OutlinedButton.icon(
              icon: const Icon(Icons.print_outlined, size: 16),
              label: const Text('Erneut drucken'),
              onPressed: () async {
                final data = await _buildPdfData();
                await previewDocumentPdf(data);
              },
            )
          else ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.remove_red_eye_outlined, size: 16),
              label: const Text('Vorschau'),
              onPressed: () async {
                final data = await _buildPdfData();
                await previewDocumentPdf(data);
              },
            ),
            const SizedBox(width: 6),
            FilledButton.icon(
              icon: const Icon(Icons.print_outlined, size: 16),
              label: const Text('Drucken & einfrieren'),
              onPressed: _druckenUndEinfrieren,
            ),
          ],
          const SizedBox(width: 6),
          if (_eingefroren)
            FilledButton.icon(
              icon: const Icon(Icons.receipt_long_outlined, size: 16),
              label: const Text('Umwandeln in Rechnung'),
              onPressed: _convertToRechnung,
            )
          else
            OutlinedButton.icon(
              icon: const Icon(Icons.receipt_long_outlined, size: 16),
              label: const Text('Umwandeln in Rechnung'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
                side: BorderSide(color: Colors.grey.shade400),
              ),
              onPressed: _convertToRechnung,
            ),
          if (_isEdit && widget.eintrag?.angebot.auftragId == null) ...[
            const SizedBox(width: 6),
            OutlinedButton.icon(
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: const Text('→ Akte anlegen'),
              onPressed: _akteAnlegen,
            ),
          ],
        ],
      ),
      body: Form(
        key: _formKey,
        child: Stack(
          children: [
            SingleChildScrollView(
              padding:
                  EdgeInsets.fromLTRB(20, _eingefroren ? 52 : 20, 20, 20),
              child: AbsorbPointer(
                absorbing: _eingefroren,
                child: Opacity(
                  opacity: _eingefroren ? 0.6 : 1.0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: LabeledField(
                              'AB-Nr.',
                              TextFormField(
                                controller: _nr,
                                decoration: const InputDecoration(
                                  hintText: 'wird beim Einfrieren vergeben',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: DateField(
                              label: 'Datum *',
                              value: _datum,
                              onChanged: (v) =>
                                  setState(() => _datum = v ?? DateTime.now()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: LabeledField(
                              'USt.-Satz %',
                              TextFormField(controller: _ust),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: KundenPickerField(
                              kundeId: _kundeId,
                              onChanged: (id) =>
                                  setState(() => _kundeId = id),
                              label: 'Auftraggeber',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AuftragPickerField(
                              auftragId: _auftragId,
                              onChanged: (id) =>
                                  setState(() => _auftragId = id),
                              label: 'Akte (optional)',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: LabeledField(
                              'Betreff',
                              TextFormField(
                                controller: _betreff,
                                minLines: 4,
                                maxLines: 8,
                                decoration: const InputDecoration(
                                  hintText:
                                      'z. B. Auftragsbestätigung Bauschadensgutachten …',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: LabeledField(
                              'Anrede / Kopftext',
                              TextFormField(
                                controller: _kopf,
                                minLines: 4,
                                maxLines: 8,
                                decoration: const InputDecoration(
                                  hintText:
                                      'Sehr geehrte Damen und Herren,\n\nhiermit bestätigen wir Ihren Auftrag wie folgt:',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: LabeledField('Objektadresse',
                                TextFormField(controller: _objStrasse)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: LabeledField(
                                'PLZ', TextFormField(controller: _objPlz)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: LabeledField(
                                'Ort', TextFormField(controller: _objOrt)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      PositionsEditor(
                        title: 'Leistungspositionen',
                        positions: _positionen,
                        onChanged: (list) =>
                            setState(() => _positionen = list),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: LabeledField(
                              'Hinweise / Bedingungen',
                              TextFormField(
                                controller: _bedingungen,
                                minLines: 5,
                                maxLines: 8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 22),
                              child: PositionsSummaryCard(
                                positions: _positionen,
                                ustSatz: _ustSatz,
                                onUstSatzChanged: (v) => setState(
                                    () => _ust.text = v.toStringAsFixed(0)),
                                summenLabel: 'Auftragssumme',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      LabeledField(
                        'Interne Notiz',
                        TextFormField(
                            controller: _notiz, minLines: 1, maxLines: 3),
                      ),
                      const SizedBox(height: 14),
                      LabeledField(
                        'Fußtext (Grußformel)',
                        TextFormField(
                          controller: _fuss,
                          minLines: 2,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            hintText: 'Mit freundlichen Grüßen\n\n{Name}',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_eingefroren)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _FrozenBanner(_pdfErstelltAm!),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> showAbEditor(BuildContext context,
    {AngebotWithKunde? eintrag}) async {
  await showDialog(
    context: context,
    useRootNavigator: true,
    builder: (_) => _AbForm(eintrag: eintrag),
  );
}

class _FrozenBanner extends StatelessWidget {
  const _FrozenBanner(this.seit);
  final DateTime seit;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy – HH:mm', 'de');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.amber.shade100,
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Gedruckt und eingefroren am ${fmt.format(seit)} · Dokument ist nur noch lesbar.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
