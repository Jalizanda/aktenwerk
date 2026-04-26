import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../../core/ai/beleg_extraktion_service.dart';
import '../../../core/theme/aw_tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../data/sync/storage_service.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../features/akten/lieferanten/lieferanten_repository.dart';
import '../../../features/system/konten/konto_picker.dart';
import '../../../shared/widgets/badges.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/file_upload_section.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'beleg_bulk_dialog.dart';
import 'eingangsrechnungen_repository.dart';
import 'sepa_export.dart';
import 'skr_kategorien.dart';

class EingangsrechnungenScreen extends ConsumerWidget {
  const EingangsrechnungenScreen({super.key});
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');

  static const statusValues = [
    'offen',
    'teilbezahlt',
    'bezahlt',
    'ueberfaellig',
    'storniert',
  ];

  static String _statusLabel(String s) => switch (s) {
        'offen' => 'offen',
        'teilbezahlt' => 'teilbezahlt',
        'bezahlt' => 'bezahlt',
        'ueberfaellig' => 'überfällig',
        'storniert' => 'storniert',
        _ => s,
      };

  /// Berechnet den effektiven Status inkl. automatischer Fälligkeits-
  /// Eskalation (offen + Zahlungsziel überschritten → überfällig).
  static String _effectiveStatus(EingangsrechnungenData r) {
    if (r.status == 'bezahlt' ||
        r.status == 'storniert' ||
        r.status == 'teilbezahlt') {
      return r.status;
    }
    final f = r.faelligAm;
    if (f != null && f.isBefore(DateTime.now())) return 'ueberfaellig';
    return 'offen';
  }

  static Widget _statusBadge(BuildContext context, String eff) {
    final (bg, fg) = switch (eff) {
      'bezahlt' => (BadgeColors.greenBg, BadgeColors.greenFg),
      'teilbezahlt' => (BadgeColors.blueBg, BadgeColors.blueFg),
      'ueberfaellig' => (BadgeColors.redBg, BadgeColors.redFg),
      'storniert' => (BadgeColors.slateBg, BadgeColors.slateFg),
      _ => (BadgeColors.amberBg, BadgeColors.amberFg),
    };
    return PillBadge(
        text: _statusLabel(eff), background: bg, foreground: fg);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(eingangsrechnungenListProvider);
    final filter = ref.watch(eingangsrechnungenFilterProvider);

    final money =
        NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.receipt_long_outlined,
          title: 'Eingangsrechnungen',
          subtitle: 'Lieferantenrechnungen, Kategorien, Fälligkeiten',
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('KI-Belegerfassung (Massen)'),
              onPressed: () => showDialog(
                context: context,
                useRootNavigator: true,
                builder: (_) => const BelegBulkDialog(),
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.account_balance, size: 16),
              label: const Text('SEPA-Sammelüberweisung'),
              onPressed: () => _openSepaDialog(context, ref),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.file_download_outlined, size: 16),
              label: const Text('DATEV-CSV'),
              onPressed: () => _exportDatevCsv(context, ref),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neue Eingangsrechnung'),
              onPressed: () => _show(context, ref),
            ),
          ],
          searchHint: 'Suche Rechnungsnummer, Kategorie, Beschreibung …',
          onSearchChanged: (v) => ref
              .read(eingangsrechnungenFilterProvider.notifier)
              .update((f) => f.copyWith(query: v)),
          filters: [
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: filter.status,
                hint: const Text('Alle Status'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Alle Status')),
                  for (final s in statusValues)
                    DropdownMenuItem(
                        value: s, child: Text(_statusLabel(s))),
                ],
                onChanged: (v) => ref
                    .read(eingangsrechnungenFilterProvider.notifier)
                    .update((f) => v == null
                        ? f.copyWith(clearStatus: true)
                        : f.copyWith(status: v)),
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) {
              final netto =
                  items.fold<double>(0, (s, r) => s + r.rechnung.netto);
              final vorsteuer = items.fold<double>(
                  0, (s, r) => s + r.rechnung.ustBetrag);
              final brutto =
                  items.fold<double>(0, (s, r) => s + r.rechnung.brutto);
              final offen = items
                  .where((r) => _effectiveStatus(r.rechnung) != 'bezahlt' &&
                      _effectiveStatus(r.rechnung) != 'storniert')
                  .fold<double>(0, (s, r) => s + r.rechnung.brutto);

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Row(
                      children: [
                        Expanded(
                            child: KpiCard(
                                icon: Icons.euro,
                                label: 'Summe netto',
                                value: money.format(netto))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: KpiCard(
                                icon: Icons.percent,
                                label: 'Vorsteuer',
                                value: money.format(vorsteuer),
                                accent: BadgeColors.blueFg)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: KpiCard(
                                icon: Icons.receipt_long,
                                label: 'Summe brutto',
                                value: money.format(brutto))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: KpiCard(
                                icon: Icons.warning_amber_outlined,
                                label: 'Offen',
                                value: money.format(offen),
                                accent: BadgeColors.redFg)),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: items.isEmpty
                        ? const EmptyListState(
                            icon: Icons.receipt_long_outlined,
                            title: 'Keine Eingangsrechnungen')
                        : DataTableCard(
                            child: DataTable(
                              showCheckboxColumn: false,
                              headingRowColor: WidgetStateProperty.all(
                                Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                              ),
                              columns: const [
                                DataColumn(
                                    label: Tooltip(
                                        message: 'Geprüft',
                                        child: Icon(Icons.verified, size: 16))),
                                DataColumn(label: Text('Beleg-Nr.')),
                                DataColumn(label: Text('Datum')),
                                DataColumn(label: Text('Lieferant')),
                                DataColumn(label: Text('Kategorie')),
                                DataColumn(label: Text('SKR')),
                                DataColumn(label: Text('Akte')),
                                DataColumn(
                                    label: Text('Netto €'), numeric: true),
                                DataColumn(
                                    label: Text('USt €'), numeric: true),
                                DataColumn(
                                    label: Text('Brutto €'), numeric: true),
                                DataColumn(label: Text('Status')),
                                DataColumn(label: Text('')),
                              ],
                              rows: [
                                for (final e in items)
                                  _row(context, ref, e),
                              ],
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  DataRow _row(BuildContext context, WidgetRef ref,
      EingangsrechnungWithAuftrag e) {
    final r = e.rechnung;
    final kat = skrByKey(r.kategorie);
    // Ungeprüfte KI-Datensätze bekommen einen warmen Hintergrund, damit
    // der SV sie sofort als „bitte prüfen" erkennt.
    final ungeprueft = !r.geprueft;
    return DataRow(
      color: ungeprueft
          ? WidgetStateProperty.all(AwTokens.amberSoft)
          : null,
      onSelectChanged: (_) => _show(context, ref, e),
      cells: [
        DataCell(Tooltip(
          message: r.geprueft
              ? 'Manuell geprüft'
              : 'Noch nicht geprüft — Klick zum Freigeben',
          child: IconButton(
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            icon: Icon(
              r.geprueft ? Icons.check_circle : Icons.circle_outlined,
              color: r.geprueft ? AwTokens.green : AwTokens.orange,
            ),
            onPressed: () => ref
                .read(eingangsrechnungenRepositoryProvider)
                .setGeprueft(r.id, !r.geprueft),
          ),
        )),
        DataCell(Text(r.rechnungsnummer ?? '',
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 12))),
        DataCell(Text(r.rechnungsdatum == null
            ? ''
            : _dateFmt.format(r.rechnungsdatum!))),
        DataCell(SizedBox(
          width: 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(r.lieferantName ?? '—',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if ((r.beschreibung ?? '').isNotEmpty)
                Text(
                  r.beschreibung!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
            ],
          ),
        )),
        DataCell(SizedBox(
            width: 200,
            child: Text(kat.label,
                maxLines: 2, overflow: TextOverflow.ellipsis))),
        DataCell(Text(
          '${kat.skr03} / ${kat.skr04}',
          style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        )),
        DataCell(Text(e.auftrag?.aktenzeichen ?? '—',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
        DataCell(Text(r.netto.toStringAsFixed(2))),
        DataCell(Text(r.ustBetrag.toStringAsFixed(2),
            style: const TextStyle(color: AwTokens.blue))),
        DataCell(Text(r.brutto.toStringAsFixed(2),
            style: const TextStyle(fontWeight: FontWeight.w700))),
        DataCell(_statusBadge(context, _effectiveStatus(r))),
        DataCell(IconButton(
          tooltip: 'Löschen',
          icon: const Icon(Icons.delete_outline, size: 18),
          onPressed: () async => ref
              .read(eingangsrechnungenRepositoryProvider)
              .delete(r.id),
        )),
      ],
    );
  }

  Future<void> _openSepaDialog(BuildContext context, WidgetRef ref) async {
    await showSepaExportDialog(context, ref);
  }

  Future<void> _exportDatevCsv(
      BuildContext context, WidgetRef ref) async {
    await exportEingangsrechnungenDatevCsv(context, ref);
  }

  Future<void> _show(BuildContext context, WidgetRef ref,
      [EingangsrechnungWithAuftrag? e]) async {
    await showDialog(
      context: context,
      builder: (_) => _EingangsrechnungForm(eintrag: e),
    );
  }
}

class _EingangsrechnungForm extends ConsumerStatefulWidget {
  const _EingangsrechnungForm({this.eintrag});
  final EingangsrechnungWithAuftrag? eintrag;
  @override
  ConsumerState<_EingangsrechnungForm> createState() =>
      _EingangsrechnungFormState();
}

class _EingangsrechnungFormState
    extends ConsumerState<_EingangsrechnungForm> {
  final _formKey = GlobalKey<FormState>();

  int? _auftragId;
  int? _lieferantId;
  DateTime? _rechnungsdatum;
  DateTime? _leistungsdatum;
  DateTime? _eingangAm;
  DateTime? _faelligAm;
  DateTime? _bezahltAm;
  String _status = 'offen';
  String _zahlungsweise = 'ueberweisung';

  late final _nr = _tec(widget.eintrag?.rechnung.rechnungsnummer);
  late final _lieferantName = _tec(widget.eintrag?.rechnung.lieferantName);
  late final _lieferantStrasse =
      _tec(widget.eintrag?.rechnung.lieferantStrasse);
  late final _lieferantPlz = _tec(widget.eintrag?.rechnung.lieferantPlz);
  late final _lieferantOrt = _tec(widget.eintrag?.rechnung.lieferantOrt);
  late final _lieferantUstId =
      _tec(widget.eintrag?.rechnung.lieferantUstId);
  late final _beschreibung = _tec(widget.eintrag?.rechnung.beschreibung);
  late final _kategorie = _tec(widget.eintrag?.rechnung.kategorie);
  late final _datevKonto = _tec(widget.eintrag?.rechnung.datevKonto);
  late final _datevKost = _tec(widget.eintrag?.rechnung.datevKostenstelle);
  late final _zahlungsziel = _tec(
      (widget.eintrag?.rechnung.zahlungszielTage ?? 14).toString());
  late final _skontoProzent = _tec(
      (widget.eintrag?.rechnung.skontoProzent ?? 0).toStringAsFixed(1));
  late final _skontoFrist = _tec(
      (widget.eintrag?.rechnung.skontoFristTage ?? 0).toString());
  late final _netto =
      _tec(widget.eintrag?.rechnung.netto.toStringAsFixed(2));
  late final _ustSatz =
      _tec(widget.eintrag?.rechnung.ustSatz.toStringAsFixed(0) ?? '19');
  late final _brutto =
      _tec(widget.eintrag?.rechnung.brutto.toStringAsFixed(2));
  late final _belegPfad = _tec(widget.eintrag?.rechnung.belegPfad);
  late final _notiz = _tec(widget.eintrag?.rechnung.notiz);

  bool _saving = false;
  bool _kiLaeuft = false;

  /// Lädt das erste verfügbare Beleg-PDF/Bild via HTTP, schickt es an
  /// Gemini zur Extraktion und befüllt die Form-Felder mit dem, was
  /// zurückkommt. Schon ausgefüllte Felder bleiben unverändert —
  /// überschreibt werden nur leere / Null-Werte.
  Future<void> _felderAusKiFuellen() async {
    final firstUrl = _belege.isNotEmpty ? _belege.first.storageUrl : null;
    if (firstUrl == null || firstUrl.isEmpty) return;

    setState(() => _kiLaeuft = true);
    try {
      // Firebase Storage Download-URL ist bereits signiert — mit
      // einfachem http.get holen.
      final resp = await http.get(Uri.parse(firstUrl));
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final bytes = resp.bodyBytes;
      final mime = _belege.first.mimeType ?? 'application/pdf';
      final extr = await extrahiereBeleg(
          ref: ref, bytes: bytes, mimeType: mime);

      setState(() {
        if ((_nr.text).isEmpty && extr.rechnungsnummer != null) {
          _nr.text = extr.rechnungsnummer!;
        }
        if (_rechnungsdatum == null && extr.rechnungsdatum != null) {
          _rechnungsdatum = extr.rechnungsdatum;
        }
        if (_leistungsdatum == null && extr.leistungsdatum != null) {
          _leistungsdatum = extr.leistungsdatum;
        }
        if (_faelligAm == null && extr.faelligkeitsdatum != null) {
          _faelligAm = extr.faelligkeitsdatum;
        }
        if (_lieferantName.text.isEmpty && extr.lieferantName != null) {
          _lieferantName.text = extr.lieferantName!;
        }
        if (_lieferantStrasse.text.isEmpty &&
            extr.lieferantStrasse != null) {
          _lieferantStrasse.text = extr.lieferantStrasse!;
        }
        if (_lieferantPlz.text.isEmpty && extr.lieferantPlz != null) {
          _lieferantPlz.text = extr.lieferantPlz!;
        }
        if (_lieferantOrt.text.isEmpty && extr.lieferantOrt != null) {
          _lieferantOrt.text = extr.lieferantOrt!;
        }
        if (_lieferantUstId.text.isEmpty &&
            extr.lieferantUstId != null) {
          _lieferantUstId.text = extr.lieferantUstId!;
        }
        if (_netto.text.isEmpty && extr.netto != null) {
          _netto.text = extr.netto!.toStringAsFixed(2);
        }
        if ((_ustSatz.text.isEmpty ||
                double.tryParse(_ustSatz.text.replaceAll(',', '.')) ==
                    19) &&
            extr.ustSatz != null &&
            extr.ustSatz! >= 0) {
          _ustSatz.text = extr.ustSatz!.toStringAsFixed(0);
        }
        if (_brutto.text.isEmpty && extr.brutto != null) {
          _brutto.text = extr.brutto!.toStringAsFixed(2);
        }
        if (extr.zahlungsweise != null &&
            extr.zahlungsweise!.isNotEmpty) {
          _zahlungsweise = extr.zahlungsweise!;
        }
        if (_beschreibung.text.isEmpty && extr.beschreibung != null) {
          _beschreibung.text = extr.beschreibung!;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('KI-Extraktion fehlgeschlagen: $e')));
      }
    } finally {
      if (mounted) setState(() => _kiLaeuft = false);
    }
  }
  List<UploadedFile> _belege = [];

  TextEditingController _tec(String? v) =>
      TextEditingController(text: v ?? '');

  @override
  void initState() {
    super.initState();
    final r = widget.eintrag?.rechnung;
    _auftragId = r?.auftragId;
    _lieferantId = r?.lieferantId;
    _rechnungsdatum = r?.rechnungsdatum;
    _leistungsdatum = r?.leistungsdatum;
    _eingangAm = r?.eingangAm;
    _faelligAm = r?.faelligAm;
    _bezahltAm = r?.bezahltAm;
    _status = r?.status ?? 'offen';
    _zahlungsweise = _normZahl(r?.zahlungsweise);
    _belege = decodeUploadedFiles(r?.belegeJson);
  }

  static String _normZahl(String? v) {
    const allowed = ['ueberweisung', 'lastschrift', 'kreditkarte', 'paypal'];
    return allowed.contains(v) ? v! : 'ueberweisung';
  }

  @override
  void dispose() {
    for (final c in [
      _nr, _lieferantName, _lieferantStrasse, _lieferantPlz, _lieferantOrt,
      _lieferantUstId,
      _beschreibung, _kategorie,
      _datevKonto, _datevKost, _zahlungsziel, _skontoProzent, _skontoFrist,
      _netto, _ustSatz, _brutto,
      _belegPfad, _notiz,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.eintrag != null;

  void _recalcBrutto() {
    final n = double.tryParse(_netto.text.replaceAll(',', '.'));
    final u = double.tryParse(_ustSatz.text.replaceAll(',', '.')) ?? 19;
    if (n == null) return;
    final brutto = n * (1 + u / 100.0);
    _brutto.text = brutto.toStringAsFixed(2);
  }

  void _recalcFaelligkeit() {
    final rd = _rechnungsdatum;
    final ziel = int.tryParse(_zahlungsziel.text.trim());
    if (rd == null || ziel == null) return;
    setState(() => _faelligAm = rd.add(Duration(days: ziel)));
  }

  Future<void> _pickLieferant() async {
    final picked = await showDialog<LieferantenData>(
      context: context,
      builder: (_) => const _LieferantenPickerDialog(),
    );
    if (picked == null) return;
    setState(() {
      _lieferantId = picked.id;
      _lieferantName.text = picked.firma;
      _lieferantStrasse.text = picked.strasse ?? '';
      _lieferantPlz.text = picked.plz ?? '';
      _lieferantOrt.text = picked.ort ?? '';
      _lieferantUstId.text = picked.ustId ?? '';
      _zahlungsweise = _normZahl(picked.zahlungsweise);
      _zahlungsziel.text = picked.zahlungszielTage.toString();
    });
    _recalcFaelligkeit();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final netto = double.tryParse(_netto.text.replaceAll(',', '.')) ?? 0;
    final ust = double.tryParse(_ustSatz.text.replaceAll(',', '.')) ?? 19;
    final brutto =
        double.tryParse(_brutto.text.replaceAll(',', '.')) ??
            (netto * (1 + ust / 100));
    final ustBetrag = brutto - netto;
    final ziel = int.tryParse(_zahlungsziel.text.trim()) ?? 14;
    final skProz =
        double.tryParse(_skontoProzent.text.replaceAll(',', '.')) ?? 0;
    final skFrist = int.tryParse(_skontoFrist.text.trim()) ?? 0;
    final companion = EingangsrechnungenCompanion(
      id: _isEdit
          ? Value(widget.eintrag!.rechnung.id)
          : const Value.absent(),
      rechnungsnummer: _nt(_nr),
      lieferantId: Value(_lieferantId),
      auftragId: Value(_auftragId),
      lieferantName: _nt(_lieferantName),
      lieferantStrasse: _nt(_lieferantStrasse),
      lieferantPlz: _nt(_lieferantPlz),
      lieferantOrt: _nt(_lieferantOrt),
      lieferantUstId: _nt(_lieferantUstId),
      rechnungsdatum: Value(_rechnungsdatum),
      leistungsdatum: Value(_leistungsdatum),
      eingangAm: Value(_eingangAm),
      faelligAm: Value(_faelligAm),
      bezahltAm: Value(_bezahltAm),
      zahlungszielTage: Value(ziel),
      zahlungsweise: Value(_zahlungsweise),
      skontoProzent: Value(skProz),
      skontoFristTage: Value(skFrist),
      status: Value(_status),
      kategorie: _nt(_kategorie),
      beschreibung: _nt(_beschreibung),
      datevKonto: _nt(_datevKonto),
      datevKostenstelle: _nt(_datevKost),
      netto: Value(netto),
      ustSatz: Value(ust),
      ustBetrag: Value(ustBetrag),
      brutto: Value(brutto),
      belegPfad: _nt(_belegPfad),
      belegeJson: Value(_belege.isEmpty ? null : encodeUploadedFiles(_belege)),
      notiz: _nt(_notiz),
      // Manuelles Speichern bestätigt die Werte — als geprüft markieren.
      geprueft: const Value(true),
    );
    try {
      await ref
          .read(eingangsrechnungenRepositoryProvider)
          .upsert(companion);
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

  @override
  Widget build(BuildContext context) {
    return StandardFormDialog(
      title: _isEdit
          ? 'Eingangsrechnung bearbeiten'
          : 'Neue Eingangsrechnung',
      saving: _saving,
      maxWidth: 1000,
      maxHeight: 860,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(eingangsrechnungenRepositoryProvider)
              .delete(widget.eintrag!.rechnung.id)
          : null,
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FormSection('Lieferant', children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: 2,
                      child: LabeledField(
                        'Name',
                        TextFormField(controller: _lieferantName),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.search, size: 16),
                      label: const Text('Aus Stamm'),
                      onPressed: _pickLieferant,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row3(
                  a: LabeledField(
                      'Straße', TextFormField(controller: _lieferantStrasse)),
                  b: LabeledField('PLZ',
                      TextFormField(controller: _lieferantPlz)),
                  c: LabeledField('Ort',
                      TextFormField(controller: _lieferantOrt)),
                ),
                const SizedBox(height: 12),
                LabeledField('USt-IdNr.',
                    TextFormField(controller: _lieferantUstId)),
              ]),
              FormSection('Rechnung', children: [
                Row3(
                  a: LabeledField(
                      'Rechnungs-Nr.', TextFormField(controller: _nr)),
                  b: DateField(
                    label: 'Rechnungsdatum',
                    value: _rechnungsdatum,
                    onChanged: (v) {
                      setState(() => _rechnungsdatum = v);
                      _recalcFaelligkeit();
                    },
                  ),
                  c: DateField(
                    label: 'Leistungsdatum',
                    value: _leistungsdatum,
                    onChanged: (v) => setState(() => _leistungsdatum = v),
                  ),
                ),
                const SizedBox(height: 12),
                Row3(
                  a: DateField(
                    label: 'Eingang',
                    value: _eingangAm,
                    onChanged: (v) => setState(() => _eingangAm = v),
                  ),
                  b: DateField(
                    label: 'Fällig am',
                    value: _faelligAm,
                    onChanged: (v) => setState(() => _faelligAm = v),
                  ),
                  c: LabeledField(
                    'Status',
                    DropdownButtonFormField<String>(
                      initialValue: _status,
                      isDense: true,
                      items: const [
                        DropdownMenuItem(value: 'offen', child: Text('offen')),
                        DropdownMenuItem(
                            value: 'teilbezahlt', child: Text('teilbezahlt')),
                        DropdownMenuItem(
                            value: 'bezahlt', child: Text('bezahlt')),
                      ],
                      onChanged: (v) =>
                          setState(() => _status = v ?? 'offen'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AuftragPickerField(
                  auftragId: _auftragId,
                  onChanged: (id) => setState(() => _auftragId = id),
                  label: 'Auftrag (optional)',
                ),
              ]),
              FormSection('Beträge', children: [
                Row3(
                  a: LabeledField(
                    'Netto (€)',
                    TextFormField(
                      controller: _netto,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      onChanged: (_) => _recalcBrutto(),
                    ),
                  ),
                  b: LabeledField(
                    'USt (%)',
                    TextFormField(
                      controller: _ustSatz,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      onChanged: (_) => _recalcBrutto(),
                    ),
                  ),
                  c: LabeledField(
                    'Brutto (€)',
                    TextFormField(
                      controller: _brutto,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row3(
                  a: LabeledField(
                    'Skonto %',
                    TextFormField(
                      controller: _skontoProzent,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                  ),
                  b: LabeledField(
                    'Skonto-Frist (Tage)',
                    TextFormField(
                      controller: _skontoFrist,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  c: DateField(
                    label: 'Bezahlt am',
                    value: _bezahltAm,
                    onChanged: (v) => setState(() => _bezahltAm = v),
                  ),
                ),
              ]),
              FormSection('Zahlung', children: [
                Row2(
                  left: LabeledField(
                    'Zahlungsziel (Tage)',
                    TextFormField(
                      controller: _zahlungsziel,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _recalcFaelligkeit(),
                    ),
                  ),
                  right: LabeledField(
                    'Zahlungsweise',
                    DropdownButtonFormField<String>(
                      initialValue: _zahlungsweise,
                      isDense: true,
                      items: const [
                        DropdownMenuItem(
                            value: 'ueberweisung', child: Text('Überweisung')),
                        DropdownMenuItem(
                            value: 'lastschrift', child: Text('Lastschrift')),
                        DropdownMenuItem(
                            value: 'kreditkarte', child: Text('Kreditkarte')),
                        DropdownMenuItem(
                            value: 'paypal', child: Text('PayPal')),
                        DropdownMenuItem(
                            value: 'bar', child: Text('Bar')),
                      ],
                      onChanged: (v) =>
                          setState(() => _zahlungsweise = v ?? 'ueberweisung'),
                    ),
                  ),
                ),
              ]),
              FormSection('DATEV / SKR', children: [
                LabeledField(
                  'Kategorie',
                  DropdownButtonFormField<String>(
                    initialValue: skrKategorien.any(
                            (k) => k.key == _kategorie.text.trim())
                        ? _kategorie.text.trim()
                        : null,
                    isDense: true,
                    items: [
                      for (final k in skrKategorien)
                        DropdownMenuItem(
                          value: k.key,
                          child: Text(
                              '${k.label}  ·  ${k.skr03}/${k.skr04}'),
                        ),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _kategorie.text = v ?? '';
                        final k = skrByKey(v);
                        if (_datevKonto.text.isEmpty) {
                          _datevKonto.text = k.skr03;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row3(
                  a: LabeledField(
                      'Kategorie (frei)', TextFormField(controller: _kategorie)),
                  b: KontoPickerField(
                    kontonummer: _datevKonto.text.trim().isEmpty
                        ? null
                        : _datevKonto.text.trim(),
                    filterKategorie: 'aufwand',
                    onChanged: (v) =>
                        setState(() => _datevKonto.text = v ?? ''),
                    label: 'SKR-Konto (Aufwand)',
                  ),
                  c: LabeledField(
                      'Kostenstelle', TextFormField(controller: _datevKost)),
                ),
              ]),
              FormSection('Beleg & Notiz', children: [
                LabeledField(
                  'Beschreibung',
                  TextFormField(controller: _beschreibung),
                ),
                const SizedBox(height: 12),
                MultiFileUploadSection(
                  title: 'Beleg-Scans',
                  storagePrefix: 'eingangsrechnungen',
                  kind: UploadKind.any,
                  files: _belege,
                  hint:
                      'PDF oder Foto der Original-Rechnung. Mehrere Seiten möglich.',
                  onChanged: (list) => setState(() => _belege = list),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    icon: _kiLaeuft
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome, size: 16),
                    label: Text(_kiLaeuft
                        ? 'KI liest Beleg …'
                        : 'Felder per KI aus erstem Beleg ausfüllen'),
                    onPressed: (_belege.isEmpty || _kiLaeuft)
                        ? null
                        : _felderAusKiFuellen,
                  ),
                ),
                const SizedBox(height: 12),
                LabeledField(
                    'Beleg-Pfad (lokal, optional)',
                    TextFormField(controller: _belegPfad)),
                const SizedBox(height: 12),
                LabeledField(
                    'Notiz',
                    TextFormField(
                        controller: _notiz, minLines: 2, maxLines: 4)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modaler Picker für Lieferanten aus dem Stamm.
class _LieferantenPickerDialog extends ConsumerStatefulWidget {
  const _LieferantenPickerDialog();
  @override
  ConsumerState<_LieferantenPickerDialog> createState() =>
      _LieferantenPickerDialogState();
}

class _LieferantenPickerDialogState
    extends ConsumerState<_LieferantenPickerDialog> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final items = ref.watch(lieferantenListProvider).valueOrNull ?? const [];
    final filtered = _q.isEmpty
        ? items
        : items
            .where((l) =>
                l.firma.toLowerCase().contains(_q.toLowerCase()) ||
                (l.ort ?? '').toLowerCase().contains(_q.toLowerCase()))
            .toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(children: [
                Text('Lieferant auswählen',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ]),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Suche Firma / Ort',
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final l = filtered[i];
                  return ListTile(
                    dense: true,
                    title: Text(l.firma),
                    subtitle: Text([
                      if ((l.ansprechpartner ?? '').isNotEmpty)
                        l.ansprechpartner,
                      if ((l.ort ?? '').isNotEmpty) l.ort,
                      if ((l.kategorie ?? '').isNotEmpty) l.kategorie,
                    ].whereType<String>().join(' · ')),
                    onTap: () => Navigator.pop(context, l),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
