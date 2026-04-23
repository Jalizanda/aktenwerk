import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../features/akten/auftraege/auto_akte.dart';
import '../../../features/akten/kunden/kunden_picker.dart';
import '../../../features/akten/kunden/kunden_repository.dart';
import '../../../features/akten/workflow/dokument_workflow.dart';
import '../../../features/system/einstellungen/absender_service.dart';
import '../../../features/system/einstellungen/einstellungen_repository.dart';
import '../../../features/system/einstellungen/nummernkreis_service.dart';
import '../../../shared/pdf/pdf_archiver.dart';
import '../../../shared/pdf/document_pdf.dart';
import '../../../shared/positionen/position_model.dart';
import '../../../shared/positionen/positions_editor.dart';
import '../../../shared/widgets/badges.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'angebote_repository.dart';

class AngeboteScreen extends ConsumerStatefulWidget {
  const AngeboteScreen({super.key});

  static const statusValues = AngebotStatusBadge.statusValues;
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');
  static final _moneyFmt =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

  @override
  ConsumerState<AngeboteScreen> createState() => _AngeboteScreenState();
}

class _AngeboteScreenState extends ConsumerState<AngeboteScreen> {
  int _sortCol = 1; // Datum default
  bool _sortAsc = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(angeboteListProvider);
    final filter = ref.watch(angeboteFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.price_change_outlined,
          title: 'Angebote',
          subtitle: 'Angebotserstellung mit Positionen und Gültigkeit',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neues Angebot'),
              onPressed: () => _show(context),
            ),
          ],
          searchHint: 'Suche Angebotsnummer, Kunde, Betreff …',
          onSearchChanged: (v) => ref
              .read(angeboteFilterProvider.notifier)
              .update((f) => f.copyWith(query: v)),
          filters: [
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: filter.status,
                hint: const Text('Alle Status'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Alle Status')),
                  for (final s in AngeboteScreen.statusValues)
                    DropdownMenuItem(
                        value: s,
                        child: Text(AngebotStatusBadge.label(s))),
                ],
                onChanged: (v) => ref
                    .read(angeboteFilterProvider.notifier)
                    .update((f) => v == null
                        ? f.copyWith(clearStatus: true)
                        : f.copyWith(status: v)),
              ),
            ),
          ],
        ),
        async.maybeWhen(
          data: (items) => _KpiRow(items: items),
          orElse: () => const SizedBox.shrink(),
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) => items.isEmpty
                ? const EmptyListState(
                    icon: Icons.price_change_outlined,
                    title: 'Keine Angebote')
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
        3 => cmp(a.angebot.betreff?.toLowerCase(),
            b.angebot.betreff?.toLowerCase()),
        4 => cmp(a.angebot.gueltigBis, b.angebot.gueltigBis),
        5 => cmp(a.angebot.netto, b.angebot.netto),
        6 => cmp(a.angebot.brutto, b.angebot.brutto),
        7 => cmp(a.angebot.status, b.angebot.status),
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
          sortCol('Nr.', 0),
          sortCol('Datum', 1),
          sortCol('Kunde', 2),
          sortCol('Betreff', 3),
          sortCol('Gültig bis', 4),
          sortCol('Netto €', 5, numeric: true),
          sortCol('Brutto €', 6, numeric: true),
          sortCol('Status', 7),
          const DataColumn(label: Text('')),
        ],
        rows: [
          for (final a in items)
            DataRow(
              onSelectChanged: (_) => _show(context, a),
              cells: [
                DataCell(Text(
                  a.angebot.angebotsnummer ?? '',
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12),
                )),
                DataCell(
                    Text(AngeboteScreen._dateFmt.format(a.angebot.datum))),
                DataCell(Text(a.kunde == null
                    ? '—'
                    : kundeAnzeigename(a.kunde!))),
                DataCell(SizedBox(
                  width: 220,
                  child: Text(
                    a.angebot.betreff ?? '',
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
                DataCell(Text(a.angebot.gueltigBis == null
                    ? ''
                    : AngeboteScreen._dateFmt.format(a.angebot.gueltigBis!))),
                DataCell(Text(
                  AngeboteScreen._moneyFmt.format(a.angebot.netto),
                )),
                DataCell(Text(
                  AngeboteScreen._moneyFmt.format(a.angebot.brutto),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                )),
                DataCell(AngebotStatusBadge(a.angebot.status)),
                DataCell(Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Angebot als PDF',
                      icon: const Icon(Icons.picture_as_pdf_outlined,
                          size: 20),
                      onPressed: () => _previewPdf(context, a, false),
                    ),
                    IconButton(
                      tooltip: 'Auftragsbestätigung als PDF',
                      icon: const Icon(Icons.assignment_turned_in_outlined,
                          size: 20),
                      onPressed: () => _previewPdf(context, a, true),
                    ),
                    IconButton(
                      tooltip: a.angebot.pdfStorageUrl != null
                          ? 'Archivierte PDF aktualisieren'
                          : 'PDF archivieren',
                      icon: Icon(
                        a.angebot.pdfStorageUrl != null
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_upload_outlined,
                        size: 20,
                        color: a.angebot.pdfStorageUrl != null
                            ? const Color(0xFF16A34A)
                            : null,
                      ),
                      onPressed: () => _archivePdf(context, a),
                    ),
                    IconButton(
                      tooltip: 'Löschen',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () async => ref
                          .read(angeboteRepositoryProvider)
                          .delete(a.angebot.id),
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
      builder: (_) => _AngebotForm(eintrag: a),
    );
  }

  Future<PdfDocumentData> _buildPdfData(
      AngebotWithKunde a, bool alsAb) async {
    final absender = await absenderFromSettings(ref);
    final fuss = await ref
        .read(einstellungenRepositoryProvider)
        .get(SettingsKeys.angebotFusstext);
    return PdfDocumentData(
      dokumentTyp: alsAb ? 'Auftragsbestätigung' : 'Angebot',
      dokumentNr: a.angebot.angebotsnummer,
      datum: a.angebot.datum,
      faelligBis: a.angebot.gueltigBis,
      betreff: a.angebot.betreff,
      positionen: positionsFromJson(a.angebot.positionenJson),
      kopftext: a.angebot.kopftext,
      fusstext: a.angebot.fusstext ?? fuss,
      absender: absender,
      empfaenger: a.kunde,
      brutto: a.angebot.brutto,
    );
  }

  Future<void> _previewPdf(
      BuildContext context, AngebotWithKunde a, bool alsAb) async {
    await previewDocumentPdf(await _buildPdfData(a, alsAb));
  }

  Future<void> _archivePdf(
      BuildContext context, AngebotWithKunde a) async {
    final data = await _buildPdfData(a, false);
    final uploaded = await freezeAngebotAsBeleg(ref, a.angebot, data);
    if (uploaded == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Upload nicht möglich — bitte anmelden / Cloud prüfen.')));
      }
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Beleg archiviert: ${uploaded.dateiname}')));
    }
  }
}

/// KPI-Kacheln über der Tabelle: Pipeline (offen), Gewonnen, Conversion-Rate.
class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.items});
  final List<AngebotWithKunde> items;

  @override
  Widget build(BuildContext context) {
    const offen = ['anfrage', 'angebot', 'nachverhandlung'];
    final pipeline = items
        .where((a) => offen.contains(a.angebot.status))
        .fold<double>(0, (s, a) => s + a.angebot.brutto);
    final gewonnen = items
        .where((a) =>
            a.angebot.status == 'angenommen' ||
            a.angebot.status == 'auftragsbestaetigung')
        .fold<double>(0, (s, a) => s + a.angebot.brutto);
    final entschieden = items
        .where((a) =>
            a.angebot.status == 'angenommen' ||
            a.angebot.status == 'auftragsbestaetigung' ||
            a.angebot.status == 'abgelehnt' ||
            a.angebot.status == 'abgelaufen')
        .length;
    final angenommen = items
        .where((a) =>
            a.angebot.status == 'angenommen' ||
            a.angebot.status == 'auftragsbestaetigung')
        .length;
    final conv = entschieden == 0 ? 0.0 : angenommen / entschieden * 100;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: KpiCard(
              icon: Icons.pending_actions_outlined,
              label: 'Pipeline (offen)',
              value: AngeboteScreen._moneyFmt.format(pipeline),
              accent: BadgeColors.amberFg,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: KpiCard(
              icon: Icons.check_circle_outline,
              label: 'Gewonnen',
              value: AngeboteScreen._moneyFmt.format(gewonnen),
              accent: BadgeColors.greenFg,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: KpiCard(
              icon: Icons.show_chart,
              label: 'Conversion-Rate',
              value: '${conv.toStringAsFixed(0)} %',
              accent: BadgeColors.blueFg,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showAngebotEditor(BuildContext context,
    {AngebotWithKunde? eintrag}) async {
  await showDialog(
    context: context,
    useRootNavigator: true,
    builder: (_) => _AngebotForm(eintrag: eintrag),
  );
}

class _AngebotForm extends ConsumerStatefulWidget {
  const _AngebotForm({this.eintrag});
  final AngebotWithKunde? eintrag;
  @override
  ConsumerState<_AngebotForm> createState() => _AngebotFormState();
}

class _AngebotFormState extends ConsumerState<_AngebotForm> {
  final _formKey = GlobalKey<FormState>();
  int? _kundeId;
  int? _auftragId;
  DateTime _datum = DateTime.now();
  DateTime? _gueltigBis;
  String _status = 'anfrage';
  late List<Position> _positionen;
  late final _nr = TextEditingController(
      text: widget.eintrag?.angebot.angebotsnummer ?? '');
  late final _betreff = TextEditingController(
      text: widget.eintrag?.angebot.betreff ?? '');
  late final _anfrage = TextEditingController(
      text: widget.eintrag?.angebot.anfrage ?? '');
  late final _objStrasse = TextEditingController(
      text: widget.eintrag?.angebot.objektStrasse ?? '');
  late final _objPlz = TextEditingController(
      text: widget.eintrag?.angebot.objektPlz ?? '');
  late final _objOrt = TextEditingController(
      text: widget.eintrag?.angebot.objektOrt ?? '');
  late final _bedingungen = TextEditingController(
      text: widget.eintrag?.angebot.bedingungen ?? '');
  late final _ust = TextEditingController(
      text: (widget.eintrag?.angebot.ustSatz ?? 19).toStringAsFixed(0));
  late final _notiz = TextEditingController(
      text: widget.eintrag?.angebot.notiz ?? '');
  late final _kopf = TextEditingController(
      text: widget.eintrag?.angebot.kopftext ?? '');
  late final _fuss = TextEditingController(
      text: widget.eintrag?.angebot.fusstext ?? '');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.eintrag?.angebot;
    _kundeId = a?.kundeId;
    _auftragId = a?.auftragId;
    _datum = a?.datum ?? DateTime.now();
    _gueltigBis =
        a?.gueltigBis ?? DateTime.now().add(const Duration(days: 30));
    _status = a?.status ?? 'anfrage';
    _positionen = positionsFromJson(a?.positionenJson);
    if (widget.eintrag == null) _prefill();
  }

  Future<void> _prefill() async {
    final seq = await ref.read(angeboteRepositoryProvider).nextSequenz();
    final pattern = await ref
        .read(einstellungenRepositoryProvider)
        .getOr(SettingsKeys.nummernkreisAngebot, 'A{YYYY}-###');
    final nr = _applyPattern(pattern, seq);
    if (mounted && _nr.text.isEmpty) _nr.text = nr;
    final fuss = await ref
        .read(einstellungenRepositoryProvider)
        .get(SettingsKeys.angebotFusstext);
    if (mounted && _fuss.text.isEmpty && fuss != null) {
      _fuss.text = fuss;
    }
  }

  String _applyPattern(String pattern, int seq) {
    final now = DateTime.now();
    var out = pattern
        .replaceAll('{YYYY}', '${now.year}')
        .replaceAll('YYYY', '${now.year}')
        .replaceAll('{MM}', now.month.toString().padLeft(2, '0'))
        .replaceAll('MM', now.month.toString().padLeft(2, '0'));
    final m = RegExp(r'#+').firstMatch(out);
    if (m != null) {
      out = out.replaceFirst(
          m.group(0)!, seq.toString().padLeft(m.group(0)!.length, '0'));
    } else {
      out = '$out$seq';
    }
    return out;
  }

  @override
  void dispose() {
    for (final c in [
      _nr, _betreff, _anfrage, _objStrasse, _objPlz, _objOrt,
      _bedingungen, _ust, _notiz, _kopf, _fuss,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.eintrag != null;

  /// true, wenn dieses „Angebot"-Objekt eigentlich eine Auftragsbestätigung
  /// ist (Status `auftragsbestaetigung`). Dann wird der PDF-Typ AB gedruckt
  /// und der Button „→ Auftragsbestätigung" entfällt.
  bool get _istAb => _status == 'auftragsbestaetigung';

  Future<void> _save({bool close = true}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    if (!_isEdit && _nr.text.trim().isEmpty) {
      final neu = await ref
          .read(nummernkreisServiceProvider)
          .nextNumber(NummernkreisTyp.angebot);
      _nr.text = neu;
    }

    // Auto-Akte anlegen, falls das Angebot noch nicht mit einer Akte
    // verknüpft ist.
    if (!_isEdit && _auftragId == null) {
      _auftragId = await ensureAkte(
        ref,
        auftragId: null,
        kundeId: _kundeId,
        betreff: _betreff.text.trim().isEmpty
            ? 'Angebot ${_nr.text.trim()}'
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
      gueltigBis: Value(_gueltigBis),
      status: Value(_status),
      netto: Value(totals.netto),
      ustBetrag: Value(totals.ust),
      brutto: Value(totals.brutto),
      positionenJson: Value(positionsToJson(_positionen)),
      kopftext: _nt(_kopf),
      fusstext: _nt(_fuss),
    );
    try {
      await ref.read(angeboteRepositoryProvider).upsert(companion);
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

  Value<String?> _nt(TextEditingController c) {
    final v = c.text.trim();
    return Value(v.isEmpty ? null : v);
  }

  double get _ustSatz =>
      double.tryParse(_ust.text.replaceAll(',', '.')) ?? 19;

  Future<PdfDocumentData> _buildPdfData({required bool alsAb}) async {
    final absender = await absenderFromSettings(ref);
    final kundeId = _kundeId;
    final kunde = kundeId == null
        ? null
        : await ref.read(kundenRepositoryProvider).byId(kundeId);
    final fuss = await ref
        .read(einstellungenRepositoryProvider)
        .get(SettingsKeys.angebotFusstext);
    final objekt = [
      _objStrasse.text.trim(),
      '${_objPlz.text.trim()} ${_objOrt.text.trim()}'.trim(),
    ].where((s) => s.isNotEmpty).join(', ');
    return PdfDocumentData(
      dokumentTyp: alsAb ? 'Auftragsbestätigung' : 'Angebot',
      dokumentNr: _nr.text.trim(),
      datum: _datum,
      faelligBis: _gueltigBis,
      sachverhalt:
          _anfrage.text.trim().isEmpty ? _betreff.text : _anfrage.text,
      objektAdresse: objekt.isEmpty ? null : objekt,
      positionen: _positionen,
      kopftext: _kopf.text.trim().isEmpty ? null : _kopf.text,
      fusstext: _fuss.text.trim().isEmpty ? fuss : _fuss.text,
      absender: absender,
      empfaenger: kunde,
    );
  }

  Future<void> _previewPdf({required bool alsAb}) async {
    await previewDocumentPdf(await _buildPdfData(alsAb: alsAb));
  }

  /// Wandelt das Angebot in eine Auftragsbestätigung (AB) um. Legt ein
  /// neues Angebot-Objekt mit `status=auftragsbestaetigung` und einer
  /// AB-Nummer aus dem eigenen Nummernkreis an (Default AB{YYYY}-{NNN}).
  Future<void> _convertToAb() async {
    if (!_isEdit) return;
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: const Text('Auftragsbestätigung anlegen?'),
        content: const Text(
            'Es wird eine neue Auftragsbestätigung (eigener Nummernkreis, '
            'z.B. AB2026-001) mit den Positionen und Beträgen dieses Angebots '
            'erzeugt. Das Angebot bleibt unverändert. Aus der AB heraus kannst '
            'du später eine Rechnung erstellen.'),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(true),
              child: const Text('AB anlegen')),
        ],
      ),
    );
    if (ok != true) return;
    final workflow = ref.read(dokumentWorkflowProvider);
    final abId = await workflow.angebotToAb(widget.eintrag!.angebot);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Auftragsbestätigung #$abId angelegt')));
      Navigator.of(context, rootNavigator: true).pop(true);
    }
  }

  /// Legt aus diesem Angebot eine neue Akte (AW-Nummer) an, wenn noch keine
  /// zugeordnet ist.
  Future<void> _akteAnlegen() async {
    if (!_isEdit) return;
    final a = widget.eintrag!.angebot;
    if (a.auftragId != null) return;
    if (a.kundeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Angebot hat keinen Auftraggeber.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Akte anlegen?'),
        content: const Text(
            'Es wird eine neue Akte (AW-Nummer) aus diesem Angebot '
            'erzeugt. Das Angebot wird auf „Angenommen" gesetzt.'),
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
    await ref.read(angeboteRepositoryProvider).upsert(AngeboteCompanion(
          id: Value(a.id),
          status: const Value('angenommen'),
        ));
    final auftragId = await workflow.angebotToAuftrag(a);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Akte #$auftragId angelegt — im Akten-Modul bearbeiten.')));
      Navigator.of(context, rootNavigator: true).pop(true);
    }
  }

  Future<void> _convertToRechnung() async {
    if (!_isEdit) return;
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: const Text('Aus Angebot → Rechnung erstellen?'),
        content: const Text(
            'Eine neue Rechnung wird mit den Positionen dieses Angebots '
            'erzeugt. Du kannst sie anschließend bearbeiten.'),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(true),
              child: const Text('Rechnung erstellen')),
        ],
      ),
    );
    if (ok != true) return;
    final workflow = ref.read(dokumentWorkflowProvider);
    final rId = await workflow.angebotToRechnung(widget.eintrag!.angebot);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rechnung #$rId angelegt')));
      Navigator.of(context, rootNavigator: true).pop(true);
    }
  }

  Future<void> _archivePdfFromDialog() async {
    if (!_isEdit) return;
    final data = await _buildPdfData(alsAb: false);
    final uploaded = await freezeAngebotAsBeleg(
        ref, widget.eintrag!.angebot, data);
    if (uploaded == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Upload nicht möglich — bitte anmelden / Cloud prüfen.')));
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Beleg archiviert: ${uploaded.dateiname}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StandardFormDialog(
      title: _isEdit ? 'Angebot bearbeiten' : 'Neues Angebot',
      saving: _saving,
      maxWidth: 1100,
      maxHeight: 900,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(angeboteRepositoryProvider)
              .delete(widget.eintrag!.angebot.id)
          : null,
      footerLeading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.remove_red_eye_outlined, size: 16),
            label: const Text('Drucken'),
            onPressed: () => _previewPdf(alsAb: _istAb),
          ),
          const SizedBox(width: 6),
          if (_isEdit)
            OutlinedButton.icon(
              icon: const Icon(Icons.cloud_upload_outlined, size: 16),
              label: const Text('Archivieren'),
              onPressed: _archivePdfFromDialog,
            ),
          if (_isEdit) const SizedBox(width: 6),
          if (_isEdit)
            PopupMenuButton<String>(
              tooltip: 'Weiterer Schritt',
              position: PopupMenuPosition.under,
              onSelected: (value) async {
                switch (value) {
                  case 'ab':
                    await _convertToAb();
                  case 'rechnung':
                    await _convertToRechnung();
                  case 'akte':
                    await _akteAnlegen();
                }
              },
              itemBuilder: (_) => [
                if (!_istAb)
                  const PopupMenuItem(
                    value: 'ab',
                    child: Row(children: [
                      Icon(Icons.assignment_turned_in_outlined, size: 16),
                      SizedBox(width: 8),
                      Text('→ Auftragsbestätigung'),
                    ]),
                  ),
                const PopupMenuItem(
                  value: 'rechnung',
                  child: Row(children: [
                    Icon(Icons.receipt_long_outlined, size: 16),
                    SizedBox(width: 8),
                    Text('→ Rechnung'),
                  ]),
                ),
                if (widget.eintrag!.angebot.auftragId == null)
                  const PopupMenuItem(
                    value: 'akte',
                    child: Row(children: [
                      Icon(Icons.folder_open_outlined, size: 16),
                      SizedBox(width: 8),
                      Text('→ Akte anlegen'),
                    ]),
                  ),
              ],
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outline),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.forward, size: 16),
                    SizedBox(width: 6),
                    Text('Weiter zu …'),
                    SizedBox(width: 2),
                    Icon(Icons.arrow_drop_down, size: 18),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Reihe 1: Nr. · Datum · Gültig bis · Status
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: LabeledField(
                      'Angebots-Nr. *',
                      TextFormField(
                        controller: _nr,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Erforderlich'
                            : null,
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
                    child: DateField(
                      label: 'Gültig bis',
                      value: _gueltigBis,
                      onChanged: (v) => setState(() => _gueltigBis = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: LabeledField(
                      'Status',
                      Builder(builder: (_) {
                        final values = {
                          ...AngeboteScreen.statusValues,
                          _status,
                        }.toList();
                        return DropdownButtonFormField<String>(
                          initialValue: _status,
                          isDense: true,
                          items: [
                            for (final s in values)
                              DropdownMenuItem(
                                  value: s,
                                  child:
                                      Text(AngebotStatusBadge.label(s))),
                          ],
                          onChanged: (v) =>
                              setState(() => _status = v ?? 'anfrage'),
                        );
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Auftraggeber
              KundenPickerField(
                kundeId: _kundeId,
                onChanged: (id) => setState(() => _kundeId = id),
                label: 'Auftraggeber (vorhandener oder neuer)',
              ),
              const SizedBox(height: 14),
              // Akte (optional — wird sonst beim Speichern angelegt)
              AuftragPickerField(
                auftragId: _auftragId,
                onChanged: (id) => setState(() => _auftragId = id),
                label:
                    'Akte (optional — wird sonst automatisch angelegt)',
              ),
              const SizedBox(height: 14),
              // Anfrage / Sachverhalt
              LabeledField(
                'Anfrage-Beschreibung / Sachverhalt *',
                TextFormField(
                  controller: _anfrage,
                  minLines: 3,
                  maxLines: 6,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Erforderlich'
                      : null,
                ),
              ),
              const SizedBox(height: 14),
              // Objektadresse
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
              // Positionen
              PositionsEditor(
                title: 'Leistungspositionen',
                positions: _positionen,
                onChanged: (list) => setState(() => _positionen = list),
              ),
              const SizedBox(height: 20),
              // Bedingungen links · Summen rechts (wie im Original)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: LabeledField(
                      'Hinweise / AGB / Bedingungen',
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
                        onUstSatzChanged: (v) =>
                            setState(() => _ust.text = v.toStringAsFixed(0)),
                        summenLabel: 'Angebotssumme',
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
                'Fußtext',
                TextFormField(
                    controller: _fuss, minLines: 2, maxLines: 5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Erstellt aus einem angenommenen Angebot einen neuen Auftrag.
