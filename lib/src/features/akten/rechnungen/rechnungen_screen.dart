import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftraege_repository.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../features/akten/kunden/kunden_repository.dart';
import '../../../features/akten/workflow/dokument_workflow.dart';
import '../../../features/system/einstellungen/absender_service.dart';
import '../../../features/system/einstellungen/einstellungen_repository.dart';
import '../../../features/system/einstellungen/nummernkreis_service.dart';
import '../../../shared/pdf/document_pdf.dart';
import '../../../shared/pdf/pdf_archiver.dart';
import '../../../shared/positionen/position_model.dart';
import '../../../shared/positionen/positions_editor.dart';
import '../../../features/system/konten/konto_picker.dart';
import '../../../shared/widgets/badges.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'rechnungen_positionen_helpers.dart';
import 'rechnungen_repository.dart';
import 'xrechnung.dart';

class RechnungenScreen extends ConsumerStatefulWidget {
  const RechnungenScreen({super.key});

  static const statusValues = RechnungStatusBadge.statusValues;
  static const typValues = ['privat', 'jveg', 'gutschrift', 'korrektur'];
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');
  static final _moneyFmt =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

  @override
  ConsumerState<RechnungenScreen> createState() => _RechnungenScreenState();
}

class _RechnungenScreenState extends ConsumerState<RechnungenScreen> {
  int _sortCol = 1;
  bool _sortAsc = false;
  String? _typFilter;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(rechnungenListProvider);
    final filter = ref.watch(rechnungenFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.request_page_outlined,
          title: 'Rechnungen',
          subtitle: 'Ausgangsrechnungen mit Positionen, USt, Zahlungsverfolgung',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neue Rechnung'),
              onPressed: () => _show(context),
            ),
          ],
          searchHint: 'Suche Rechnungsnummer, Kunde, Aktenzeichen …',
          onSearchChanged: (v) => ref
              .read(rechnungenFilterProvider.notifier)
              .update((f) => f.copyWith(query: v)),
          filters: [
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _typFilter,
                hint: const Text('Alle Typen'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Alle Typen')),
                  DropdownMenuItem(value: 'privat', child: Text('Privat')),
                  DropdownMenuItem(value: 'jveg', child: Text('JVEG')),
                  DropdownMenuItem(
                      value: 'gutschrift', child: Text('Gutschrift')),
                  DropdownMenuItem(
                      value: 'korrektur', child: Text('Korrektur')),
                ],
                onChanged: (v) => setState(() => _typFilter = v),
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: filter.status,
                hint: const Text('Alle Status'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Alle Status')),
                  for (final s in RechnungenScreen.statusValues)
                    DropdownMenuItem(
                        value: s,
                        child: Text(RechnungStatusBadge.label(s))),
                ],
                onChanged: (v) => ref
                    .read(rechnungenFilterProvider.notifier)
                    .update((f) => v == null
                        ? f.copyWith(clearStatus: true)
                        : f.copyWith(status: v)),
              ),
            ),
          ],
        ),
        async.maybeWhen(
          data: (items) => _KpiRow(items: _applyTypFilter(items)),
          orElse: () => const SizedBox.shrink(),
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) {
              final filtered = _applyTypFilter(items);
              return filtered.isEmpty
                  ? const EmptyListState(
                      icon: Icons.request_page_outlined,
                      title: 'Keine Rechnungen')
                  : _buildTable(context, _sorted(filtered));
            },
          ),
        ),
      ],
    );
  }

  List<RechnungWithKunde> _applyTypFilter(List<RechnungWithKunde> items) {
    if (_typFilter == null) return items;
    return items.where((r) => r.rechnung.typ == _typFilter).toList();
  }

  List<RechnungWithKunde> _sorted(List<RechnungWithKunde> items) {
    final list = [...items];
    int cmp<T extends Comparable>(T? a, T? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    }

    list.sort((a, b) {
      final c = switch (_sortCol) {
        0 => cmp(a.rechnung.rechnungsnummer, b.rechnung.rechnungsnummer),
        1 => cmp(a.rechnung.rechnungsdatum, b.rechnung.rechnungsdatum),
        2 => cmp(a.rechnung.typ, b.rechnung.typ),
        3 => cmp(a.auftrag?.aktenzeichen?.toLowerCase(),
            b.auftrag?.aktenzeichen?.toLowerCase()),
        4 => cmp(
            a.kunde == null ? null : kundeAnzeigename(a.kunde!).toLowerCase(),
            b.kunde == null ? null : kundeAnzeigename(b.kunde!).toLowerCase()),
        5 => cmp(a.rechnung.netto, b.rechnung.netto),
        6 => cmp(a.rechnung.brutto, b.rechnung.brutto),
        7 => cmp(a.rechnung.status, b.rechnung.status),
        _ => 0,
      };
      return _sortAsc ? c : -c;
    });
    return list;
  }

  Widget _buildTable(BuildContext context, List<RechnungWithKunde> items) {
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
          sortCol('Rg-Nr.', 0),
          sortCol('Datum', 1),
          sortCol('Typ', 2),
          sortCol('Aktenzeichen', 3),
          sortCol('Auftraggeber', 4),
          sortCol('Netto €', 5, numeric: true),
          sortCol('Brutto €', 6, numeric: true),
          sortCol('Status', 7),
          const DataColumn(label: Text('')),
        ],
        rows: [
          for (final r in items)
            DataRow(
              onSelectChanged: (_) => _show(context, r),
              cells: [
                DataCell(Text(
                  r.rechnung.rechnungsnummer ?? '',
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12),
                )),
                DataCell(Text(r.rechnung.rechnungsdatum == null
                    ? ''
                    : RechnungenScreen._dateFmt
                        .format(r.rechnung.rechnungsdatum!))),
                DataCell(RechnungTypBadge(r.rechnung.typ)),
                DataCell(Text(r.auftrag?.aktenzeichen ?? '')),
                DataCell(Text(r.kunde == null
                    ? '—'
                    : kundeAnzeigename(r.kunde!))),
                DataCell(Text(
                  RechnungenScreen._moneyFmt.format(r.rechnung.netto),
                )),
                DataCell(Text(
                  RechnungenScreen._moneyFmt.format(r.rechnung.brutto),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                )),
                DataCell(RechnungStatusBadge(r.rechnung.status)),
                DataCell(Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'PDF-Vorschau',
                      icon: const Icon(Icons.picture_as_pdf_outlined,
                          size: 20),
                      onPressed: () => _previewPdf(context, r),
                    ),
                    IconButton(
                      tooltip: r.rechnung.pdfStorageUrl != null
                          ? 'Archivierte PDF aktualisieren'
                          : 'PDF archivieren',
                      icon: Icon(
                        r.rechnung.pdfStorageUrl != null
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_upload_outlined,
                        size: 20,
                        color: r.rechnung.pdfStorageUrl != null
                            ? const Color(0xFF16A34A)
                            : null,
                      ),
                      onPressed: () => _archivePdf(context, r),
                    ),
                    IconButton(
                      tooltip: 'Löschen',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () async => ref
                          .read(rechnungenRepositoryProvider)
                          .delete(r.rechnung.id),
                    ),
                  ],
                )),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _show(BuildContext context, [RechnungWithKunde? r]) async {
    await showDialog(
      context: context,
      builder: (_) => _RechnungForm(eintrag: r),
    );
  }

  PdfDocumentData _buildPdfData(
      RechnungWithKunde r, BenutzerData absender, String? fuss) {
    return PdfDocumentData(
      dokumentTyp: _pdfTitleFor(r.rechnung.typ),
      dokumentNr: r.rechnung.rechnungsnummer,
      datum: r.rechnung.rechnungsdatum,
      faelligBis: r.rechnung.faelligAm,
      aktenzeichen: r.auftrag?.aktenzeichen,
      betreff: 'Aktenzeichen: ${r.auftrag?.aktenzeichen ?? '-'}',
      positionen: positionsFromJson(r.rechnung.positionenJson),
      kopftext: r.rechnung.kopftext,
      fusstext: r.rechnung.fusstext ?? fuss,
      absender: absender,
      empfaenger: r.kunde,
      brutto: r.rechnung.brutto,
      mitSepaQr: r.rechnung.typ != 'gutschrift',
    );
  }

  Future<void> _previewPdf(
      BuildContext context, RechnungWithKunde r) async {
    final absender = await absenderFromSettings(ref);
    final fuss = await ref
        .read(einstellungenRepositoryProvider)
        .get(SettingsKeys.rechnungFusstext);
    await previewDocumentPdf(_buildPdfData(r, absender, fuss));
  }

  Future<void> _archivePdf(
      BuildContext context, RechnungWithKunde r) async {
    final absender = await absenderFromSettings(ref);
    final fuss = await ref
        .read(einstellungenRepositoryProvider)
        .get(SettingsKeys.rechnungFusstext);
    final data = _buildPdfData(r, absender, fuss);
    final uploaded = await freezeRechnungAsBeleg(ref, r.rechnung, data);
    if (uploaded == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Upload nicht möglich — bitte anmelden / Cloud prüfen.')),
        );
      }
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Beleg archiviert: ${uploaded.dateiname}')));
    }
  }

  String _pdfTitleFor(String typ) => switch (typ) {
        'jveg' => 'Rechnung gemäß JVEG',
        'gutschrift' => 'Gutschrift',
        'korrektur' => 'Rechnungskorrektur',
        _ => 'Rechnung',
      };
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.items});
  final List<RechnungWithKunde> items;

  @override
  Widget build(BuildContext context) {
    const offenSet = ['entwurf', 'offen', 'versendet', 'teilbezahlt', 'ueberfaellig'];
    final offen = items
        .where((r) => offenSet.contains(r.rechnung.status))
        .fold<double>(0, (s, r) => s + (r.rechnung.brutto - r.rechnung.bezahlt));
    final bezahlt = items
        .where((r) => r.rechnung.status == 'bezahlt')
        .fold<double>(0, (s, r) => s + r.rechnung.brutto);
    final gesamt = items
        .where((r) => r.rechnung.status != 'storniert')
        .fold<double>(0, (s, r) => s + r.rechnung.brutto);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: KpiCard(
              icon: Icons.hourglass_empty,
              label: 'Offene Rechnungen',
              value: RechnungenScreen._moneyFmt.format(offen),
              accent: BadgeColors.amberFg,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: KpiCard(
              icon: Icons.check_circle_outline,
              label: 'Bezahlt',
              value: RechnungenScreen._moneyFmt.format(bezahlt),
              accent: BadgeColors.greenFg,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: KpiCard(
              icon: Icons.euro,
              label: 'Gesamtumsatz (brutto)',
              value: RechnungenScreen._moneyFmt.format(gesamt),
              accent: BadgeColors.blueFg,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showRechnungEditor(BuildContext context,
    {RechnungWithKunde? eintrag}) async {
  await showDialog(
    context: context,
    useRootNavigator: true,
    builder: (_) => _RechnungForm(eintrag: eintrag),
  );
}

class _RechnungForm extends ConsumerStatefulWidget {
  const _RechnungForm({this.eintrag});
  final RechnungWithKunde? eintrag;
  @override
  ConsumerState<_RechnungForm> createState() => _RechnungFormState();
}

class _RechnungFormState extends ConsumerState<_RechnungForm> {
  final _formKey = GlobalKey<FormState>();
  int? _kundeId;
  int? _auftragId;
  String? _kontonummer;
  DateTime? _rechnungsdatum;
  DateTime? _leistungsdatum;
  DateTime? _faelligAm;
  DateTime? _bezahltAm;
  String _status = 'entwurf';
  String _typ = 'privat';
  bool _kleinunternehmer = false;
  late List<Position> _positionen;
  late final _nr = TextEditingController(
      text: widget.eintrag?.rechnung.rechnungsnummer ?? '');
  late final _bezug = TextEditingController(
      text: widget.eintrag?.rechnung.bezugRechnung ?? '');
  late final _leistungszeitraum = TextEditingController(
      text: widget.eintrag?.rechnung.leistungszeitraum ?? '');
  late final _zahlungsziel = TextEditingController(
      text: (widget.eintrag?.rechnung.zahlungszielTage ?? 14).toString());
  late final _ust = TextEditingController(
      text: (widget.eintrag?.rechnung.ustSatz ?? 19).toStringAsFixed(0));
  late final _notiz = TextEditingController(
      text: widget.eintrag?.rechnung.notiz ?? '');
  late final _kopf =
      TextEditingController(text: widget.eintrag?.rechnung.kopftext ?? '');
  late final _fuss =
      TextEditingController(text: widget.eintrag?.rechnung.fusstext ?? '');
  late final _bezahlt = TextEditingController(
      text: widget.eintrag?.rechnung.bezahlt.toStringAsFixed(2) ?? '0.00');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.eintrag?.rechnung;
    _kundeId = r?.kundeId;
    _auftragId = r?.auftragId;
    _kontonummer = r?.kontonummer;
    _rechnungsdatum = r?.rechnungsdatum ?? DateTime.now();
    _leistungsdatum = r?.leistungsdatum;
    _faelligAm = r?.faelligAm ??
        DateTime.now().add(const Duration(days: 14));
    _bezahltAm = r?.bezahltAm;
    _status = r?.status ?? 'entwurf';
    _typ = r?.typ ?? 'privat';
    _kleinunternehmer = r?.kleinunternehmerHinweis ?? false;
    _positionen = positionsFromJson(r?.positionenJson);
    if (widget.eintrag == null) _prefill();
  }

  Future<void> _prefill() async {
    final repo = ref.read(rechnungenRepositoryProvider);
    final seq = await repo.nextSequenz();
    final pattern = await ref
        .read(einstellungenRepositoryProvider)
        .getOr(SettingsKeys.nummernkreisRechnung, '{YYYY}-###');
    final nr = _applyPattern(pattern, seq);
    if (mounted && _nr.text.isEmpty) _nr.text = nr;
    final fuss = await ref
        .read(einstellungenRepositoryProvider)
        .get(SettingsKeys.rechnungFusstext);
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
      _nr, _bezug, _leistungszeitraum, _zahlungsziel, _ust,
      _notiz, _kopf, _fuss, _bezahlt,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.eintrag != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    // Nummernkreis: wenn neue Rechnung + Nummer leer → automatisch vergeben.
    if (!_isEdit && _nr.text.trim().isEmpty) {
      final neu = await ref
          .read(nummernkreisServiceProvider)
          .nextNumber(NummernkreisTyp.rechnung);
      _nr.text = neu;
    }

    // Auto-Akte: wenn noch keine Akte verknüpft ist, eine neue mit nächster
    // AW-Nummer anlegen und den Kunden übernehmen.
    if (!_isEdit && _auftragId == null) {
      final aktenzeichen = await ref
          .read(nummernkreisServiceProvider)
          .nextNumber(NummernkreisTyp.akte);
      final betreff = _kopf.text.trim().isEmpty
          ? (_nr.text.trim().isEmpty
              ? 'Neue Akte'
              : 'Akte zu ${_nr.text.trim()}')
          : _kopf.text.trim();
      final newId =
          await ref.read(auftraegeRepositoryProvider).upsert(
                AuftraegeCompanion.insert(
                  aktenzeichen: Value(aktenzeichen),
                  betreff: Value(betreff),
                  kundeId: Value(_kundeId),
                  status: const Value('offen'),
                ),
              );
      _auftragId = newId;
    }

    final totals = PositionsTotals.fromList(_positionen);
    final bezahlt =
        double.tryParse(_bezahlt.text.replaceAll(',', '.')) ?? 0;
    final zahlungsziel = int.tryParse(_zahlungsziel.text.trim()) ?? 14;
    final ust = _kleinunternehmer
        ? 0.0
        : (double.tryParse(_ust.text.replaceAll(',', '.')) ?? 19);
    final companion = RechnungenCompanion(
      id: _isEdit ? Value(widget.eintrag!.rechnung.id) : const Value.absent(),
      rechnungsnummer: Value(_nr.text.trim()),
      typ: Value(_typ),
      bezugRechnung: _nt(_bezug),
      kundeId: Value(_kundeId),
      auftragId: Value(_auftragId),
      rechnungsdatum: Value(_rechnungsdatum),
      leistungsdatum: Value(_leistungsdatum),
      leistungszeitraum: _nt(_leistungszeitraum),
      faelligAm: Value(_faelligAm),
      bezahltAm: Value(_bezahltAm),
      zahlungszielTage: Value(zahlungsziel),
      kleinunternehmerHinweis: Value(_kleinunternehmer),
      status: Value(_status),
      ustSatz: Value(ust),
      netto: Value(totals.netto),
      ustBetrag: Value(_kleinunternehmer ? 0 : totals.ust),
      brutto: Value(_kleinunternehmer ? totals.netto : totals.brutto),
      bezahlt: Value(bezahlt),
      positionenJson: Value(positionsToJson(_positionen)),
      kopftext: _nt(_kopf),
      fusstext: _nt(_fuss),
      notiz: _nt(_notiz),
      kontonummer: Value(_kontonummer),
    );
    try {
      await ref.read(rechnungenRepositoryProvider).upsert(companion);
      if (mounted) Navigator.of(context, rootNavigator: true).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Value<String?> _nt(TextEditingController c) {
    final v = c.text.trim();
    return Value(v.isEmpty ? null : v);
  }

  double get _ustSatz =>
      double.tryParse(_ust.text.replaceAll(',', '.')) ?? 19;

  Future<PdfDocumentData> _buildPdfData() async {
    final absender = await absenderFromSettings(ref);
    final kundeId = _kundeId;
    final kunde = kundeId == null
        ? null
        : await ref.read(kundenRepositoryProvider).byId(kundeId);
    final fuss = await ref
        .read(einstellungenRepositoryProvider)
        .get(SettingsKeys.rechnungFusstext);
    final totals = PositionsTotals.fromList(_positionen);
    final brutto = _kleinunternehmer ? totals.netto : totals.brutto;
    final betreff = _leistungszeitraum.text.trim().isNotEmpty
        ? 'Leistungszeitraum: ${_leistungszeitraum.text.trim()}'
        : null;
    // Aktenzeichen aus dem verknüpften Auftrag ziehen (für Folgeseiten-Kopf).
    String? aktenzeichen;
    if (_auftragId != null) {
      final list =
          await ref.read(auftraegeRepositoryProvider).watchAll().first;
      aktenzeichen = list
          .where((a) => a.auftrag.id == _auftragId)
          .firstOrNull
          ?.auftrag
          .aktenzeichen;
    }
    return PdfDocumentData(
      dokumentTyp: _pdfTitleFor(_typ),
      dokumentNr: _nr.text.trim(),
      datum: _rechnungsdatum,
      faelligBis: _faelligAm,
      aktenzeichen: aktenzeichen,
      betreff: betreff,
      positionen: _positionen,
      kopftext: _kopf.text.trim().isEmpty ? null : _kopf.text,
      fusstext: _fuss.text.trim().isEmpty ? fuss : _fuss.text,
      absender: absender,
      empfaenger: kunde,
      brutto: brutto,
      mitSepaQr: _typ != 'gutschrift',
    );
  }

  Future<void> _previewPdf() async {
    await previewDocumentPdf(await _buildPdfData());
  }

  Future<void> _exportERechnung(ERechnungProfil profil) async {
    final r = widget.eintrag;
    if (r == null) return;
    final absender = await absenderFromSettings(ref);
    final repo = ref.read(einstellungenRepositoryProvider);
    final leitweg = await repo.get(SettingsKeys.leitwegId);
    final iban = await repo.get(SettingsKeys.bankIban);
    final bic = await repo.get(SettingsKeys.bankBic);
    final bankName = await repo.get(SettingsKeys.bankName);
    final positionen = positionsFromJson(r.rechnung.positionenJson);
    final xml = buildCiiXml(
      profil: profil,
      rechnung: r.rechnung,
      positionen: positionen,
      empfaenger: r.kunde,
      absender: absender,
      leitwegId: leitweg,
      bankIban: iban,
      bankBic: bic,
      bankName: bankName,
    );
    await shareCiiXml(
      xml,
      nummer: r.rechnung.rechnungsnummer ?? '${r.rechnung.id}',
      profil: profil,
    );
  }

  Future<void> _convertToGutschrift() async {
    if (!_isEdit) return;
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: const Text('Gutschrift erstellen?'),
        content: const Text(
            'Eine neue Gutschrift wird mit negierten Beträgen der aktuellen '
            'Rechnung angelegt. Bezug auf die Original-Rechnung wird gesetzt.'),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(true),
              child: const Text('Gutschrift erstellen')),
        ],
      ),
    );
    if (ok != true) return;
    final workflow = ref.read(dokumentWorkflowProvider);
    final gId =
        await workflow.rechnungToGutschrift(widget.eintrag!.rechnung);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gutschrift #$gId angelegt')));
      Navigator.of(context, rootNavigator: true).pop(true);
    }
  }

  Future<void> _archivePdfFromDialog() async {
    if (!_isEdit) return;
    final data = await _buildPdfData();
    final uploaded = await freezeRechnungAsBeleg(
        ref, widget.eintrag!.rechnung, data);
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

  String _pdfTitleFor(String typ) => switch (typ) {
        'jveg' => 'Rechnung gemäß JVEG',
        'gutschrift' => 'Gutschrift',
        'korrektur' => 'Rechnungskorrektur',
        _ => 'Rechnung',
      };

  String _typLabel(String typ) => switch (typ) {
        'jveg' => 'JVEG-Rechnung (Gericht)',
        'gutschrift' => 'Gutschrift',
        'korrektur' => 'Rechnungskorrektur',
        _ => 'Privat-Rechnung',
      };

  @override
  Widget build(BuildContext context) {
    return StandardFormDialog(
      title: _isEdit ? 'Rechnung bearbeiten' : 'Neue Rechnung',
      saving: _saving,
      maxWidth: 1100,
      maxHeight: 900,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(rechnungenRepositoryProvider)
              .delete(widget.eintrag!.rechnung.id)
          : null,
      footerLeading: Wrap(
        spacing: 6,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.remove_red_eye_outlined, size: 16),
            label: const Text('Vorschau / Drucken'),
            onPressed: _previewPdf,
          ),
          if (_isEdit)
            OutlinedButton.icon(
              icon: const Icon(Icons.cloud_upload_outlined, size: 16),
              label: const Text('PDF archivieren'),
              onPressed: _archivePdfFromDialog,
            ),
          if (_isEdit && _typ != 'gutschrift')
            OutlinedButton.icon(
              icon: const Icon(Icons.undo_outlined, size: 16),
              label: const Text('→ Gutschrift'),
              onPressed: _convertToGutschrift,
            ),
          if (_isEdit) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.description_outlined, size: 16),
              label: const Text('X-Rechnung (XML)'),
              onPressed: () =>
                  _exportERechnung(ERechnungProfil.xrechnung),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: const Text('ZUGFeRD (XML)'),
              onPressed: () =>
                  _exportERechnung(ERechnungProfil.zugferdBasic),
            ),
          ],
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Reihe 1: Rechnungstyp · Auftrag · Status
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: LabeledField(
                      'Rechnungstyp *',
                      DropdownButtonFormField<String>(
                        initialValue: _typ,
                        isDense: true,
                        items: [
                          for (final t in RechnungenScreen.typValues)
                            DropdownMenuItem(
                                value: t, child: Text(_typLabel(t))),
                        ],
                        onChanged: (v) =>
                            setState(() => _typ = v ?? 'privat'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: AuftragPickerField(
                      auftragId: _auftragId,
                      label: 'Auftrag *',
                      onChanged: (id) async {
                        setState(() => _auftragId = id);
                        // Kunde aus dem Auftrag mit-übernehmen (1:1).
                        if (id != null) {
                          final a = await ref
                              .read(auftraegeRepositoryProvider)
                              .byId(id);
                          if (mounted && a?.kundeId != null) {
                            setState(() => _kundeId = a!.kundeId);
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: LabeledField(
                      'Status',
                      Builder(builder: (_) {
                        final values = {
                          ...RechnungenScreen.statusValues,
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
                                      Text(RechnungStatusBadge.label(s))),
                          ],
                          onChanged: (v) =>
                              setState(() => _status = v ?? 'entwurf'),
                        );
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Reihe 2: Rechnungs-Nr. · Rechnungsdatum · Bezug zur Original-Rechnung
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: LabeledField(
                      'Rechnungs-Nr. *',
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
                      label: 'Rechnungsdatum *',
                      value: _rechnungsdatum,
                      onChanged: (v) =>
                          setState(() => _rechnungsdatum = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: LabeledField(
                      'Bezug zur Original-Rechnung (bei Gutschrift/Korrektur)',
                      TextFormField(
                        controller: _bezug,
                        decoration: const InputDecoration(
                          hintText: 'z. B. 2026-003 vom 01.04.2026',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Reihe 3: Leistungsdatum/-zeitraum · Zahlungsziel
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: LabeledField(
                      'Leistungsdatum / -zeitraum',
                      TextFormField(
                        controller: _leistungszeitraum,
                        decoration: const InputDecoration(
                            hintText: 'z. B. 04/2026 oder 22.04.2026'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledField(
                      'Zahlungsziel (Tage)',
                      TextFormField(
                        controller: _zahlungsziel,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: KontoPickerField(
                      kontonummer: _kontonummer,
                      filterKategorie: 'ertrag',
                      onChanged: (v) => setState(() => _kontonummer = v),
                      label: 'Erlöskonto',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Positionen mit Action-Chips (Honorar/JVEG/Artikel/+Position)
              PositionsEditor(
                positions: _positionen,
                onChanged: (list) => setState(() => _positionen = list),
                extraActions: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.timelapse, size: 16),
                    label: const Text('Honorar aus Stunden'),
                    onPressed: _auftragId == null
                        ? null
                        : () => _honorarAusStunden(),
                  ),
                  if (_typ == 'jveg')
                    OutlinedButton.icon(
                      icon: const Icon(Icons.account_balance, size: 16),
                      label: const Text('JVEG-Auslagen'),
                      onPressed: _jvegPreset,
                    ),
                  OutlinedButton.icon(
                    icon:
                        const Icon(Icons.receipt_long_outlined, size: 16),
                    label: const Text('Auslagen'),
                    onPressed: _auftragId == null
                        ? null
                        : () => _auslagenUebernehmen(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Schlusstext links · Summen-Karte rechts (wie im Original)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: LabeledField(
                      'Schlusstext / Zahlungshinweis',
                      TextFormField(
                        controller: _fuss,
                        minLines: 4,
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
                        summenLabel: 'Rechnungsbetrag',
                        kleinunternehmer: _kleinunternehmer,
                        onKleinunternehmerChanged: (v) =>
                            setState(() => _kleinunternehmer = v),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Zusatzfelder: Bezahlt-am / Betrag / Notiz
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DateField(
                      label: 'Bezahlt am',
                      value: _bezahltAm,
                      onChanged: (v) => setState(() => _bezahltAm = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledField(
                      'Bereits bezahlt (€)',
                      TextFormField(
                        controller: _bezahlt,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: LabeledField(
                      'Interne Notiz',
                      TextFormField(
                          controller: _notiz, minLines: 1, maxLines: 2),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _honorarAusStunden() async {
    final helper = ref.read(rechnungenPositionenHelperProvider);
    final neu = await helper.honorarAusStunden(
      auftragId: _auftragId!,
      rechnungTyp: _typ,
    );
    if (neu.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Keine Stunden für diesen Auftrag gefunden.')));
      }
      return;
    }
    setState(() => _positionen = [..._positionen, ...neu]);
  }

  Future<void> _jvegPreset() async {
    final helper = ref.read(rechnungenPositionenHelperProvider);
    final neu = await helper.jvegAuslagenPreset();
    setState(() => _positionen = [..._positionen, ...neu]);
  }

  Future<void> _auslagenUebernehmen() async {
    final helper = ref.read(rechnungenPositionenHelperProvider);
    final neu = await helper.auslagenAusAuftrag(auftragId: _auftragId!);
    if (neu.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Keine Auslagen für diesen Auftrag gefunden.')));
      }
      return;
    }
    setState(() => _positionen = [..._positionen, ...neu]);
  }
}
