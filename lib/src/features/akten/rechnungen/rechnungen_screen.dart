import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/aw_tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../features/akten/auftraege/auftraege_repository.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../features/akten/kunden/kunden_picker.dart';
import '../../../features/akten/kunden/kunden_repository.dart';
import '../../../features/akten/workflow/dokument_workflow.dart';
import '../../../features/system/benutzer/benutzer_repository.dart';
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
import 'zahlungsziel_vorlagen.dart';

class RechnungenScreen extends ConsumerStatefulWidget {
  const RechnungenScreen({super.key});

  static const statusValues = RechnungStatusBadge.statusValues;
  static const typValues = [
    'privat',
    'jveg',
    'akonto',
    'teilrechnung',
    'schlussrechnung',
    'gutschrift',
    'korrektur',
  ];
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
                      value: 'akonto',
                      child: Text('Akontoanforderung')),
                  DropdownMenuItem(
                      value: 'teilrechnung',
                      child: Text('Teil-/Abschlagsrechnung')),
                  DropdownMenuItem(
                      value: 'schlussrechnung',
                      child: Text('Schlussrechnung')),
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
                DataCell(
                  (r.rechnung.rechnungsnummer == null ||
                          r.rechnung.rechnungsnummer!.trim().isEmpty)
                      ? Text(
                          'Entwurf',
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey.shade500,
                          ),
                        )
                      : Text(
                          r.rechnung.rechnungsnummer!,
                          style: const TextStyle(
                            color: AwTokens.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                ),
                DataCell(Text(r.rechnung.rechnungsdatum == null
                    ? ''
                    : RechnungenScreen._dateFmt
                        .format(r.rechnung.rechnungsdatum!))),
                DataCell(RechnungTypBadge(r.rechnung.typ)),
                DataCell(Text(
                  r.auftrag?.aktenzeichen ?? '',
                  style: const TextStyle(
                    color: AwTokens.orange,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                )),
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
                      tooltip: 'PDF-Vorschau (ohne Archivierung)',
                      icon: const Icon(Icons.picture_as_pdf_outlined,
                          size: 20),
                      onPressed: () => _previewPdf(context, r),
                    ),
                    IconButton(
                      tooltip: r.rechnung.pdfStorageUrl != null
                          ? 'Erneut drucken (überschreibt Archiv)'
                          : 'Drucken + Beleg einfrieren',
                      icon: Icon(
                        r.rechnung.pdfStorageUrl != null
                            ? Icons.print
                            : Icons.print_outlined,
                        size: 20,
                        color: r.rechnung.pdfStorageUrl != null
                            ? AwTokens.green
                            : null,
                      ),
                      onPressed: () => _druckenUndEinfrieren(context, r),
                    ),
                    if (r.rechnung.pdfErstelltAm == null)
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
      // Akte/Aktenzeichen wird im Meta-Block oben rechts ausgewiesen;
      // kein zusätzlicher „Aktenzeichen:"-Betreff nötig.
      aktenzeichen: r.auftrag?.aktenzeichen,
      betreff: r.auftrag?.betreff,
      positionen: positionsFromJson(r.rechnung.positionenJson),
      kopftext: r.rechnung.kopftext,
      fusstext: r.rechnung.fusstext ?? fuss,
      absender: absender,
      empfaenger: r.kunde,
      brutto: r.rechnung.brutto,
      mitSepaQr: r.rechnung.typ != 'gutschrift',
      gericht: r.auftrag?.gericht,
      gerichtsAktenzeichen: r.auftrag?.gerichtsAktenzeichen,
      klaeger: r.auftrag?.klaeger,
      beklagter: r.auftrag?.beklagter,
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

  /// Aufruf aus der Liste: Druckvorschau öffnen + Beleg einfrieren.
  /// Damit wird das PDF in Firebase Storage archiviert, in den
  /// Akten-Dokumenten verlinkt und die Rechnung auf Status "versendet"
  /// gesetzt (aus "entwurf"). Ab dann sollte der Beleg nicht mehr
  /// bearbeitet werden.
  Future<void> _druckenUndEinfrieren(
      BuildContext context, RechnungWithKunde r) async {
    final absender = await absenderFromSettings(ref);
    final fuss = await ref
        .read(einstellungenRepositoryProvider)
        .get(SettingsKeys.rechnungFusstext);
    final data = _buildPdfData(r, absender, fuss);

    // Druckvorschau anzeigen — der Nutzer kann ggf. im Dialog drucken
    // oder als PDF speichern. Die eigentliche Archivierung passiert
    // danach (egal ob der Nutzer gedruckt hat — wir frieren beim Klick).
    await previewDocumentPdf(data);

    final uploaded = await freezeRechnungAsBeleg(ref, r.rechnung, data);
    if (!context.mounted) return;
    if (uploaded == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Druckvorschau gezeigt — Archivierung übersprungen (Cloud nicht bereit).')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Beleg gedruckt, archiviert und eingefroren: ${uploaded.dateiname}')));
    }
  }

  String _pdfTitleFor(String typ) => switch (typ) {
        'jveg' => 'Rechnung gemäß JVEG',
        'akonto' => 'Akontoanforderung',
        'teilrechnung' => 'Abschlagsrechnung',
        'schlussrechnung' => 'Schlussrechnung',
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
    {RechnungWithKunde? eintrag,
    int? prefillAuftragId,
    int? prefillKundeId}) async {
  await showDialog(
    context: context,
    useRootNavigator: true,
    builder: (_) => _RechnungForm(
      eintrag: eintrag,
      prefillAuftragId: prefillAuftragId,
      prefillKundeId: prefillKundeId,
    ),
  );
}

class _RechnungForm extends ConsumerStatefulWidget {
  const _RechnungForm({
    this.eintrag,
    this.prefillAuftragId,
    this.prefillKundeId,
  });
  final RechnungWithKunde? eintrag;
  final int? prefillAuftragId;
  final int? prefillKundeId;
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

  /// Werden gesetzt, wenn der Nutzer eine Zahlungsziel-Vorlage mit Skonto
  /// oder Barzahlung ausgewählt hat — steuert den Skonto-/Bar-Quittung-
  /// Block auf dem PDF.
  double? _skontoProzent;
  int? _skontoTage;
  bool _barzahlung = false;
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
  DateTime? _pdfErstelltAm;
  int? _savedId;
  String? _zahlungsbedingungKey;

  bool get _eingefroren => _pdfErstelltAm != null;

  @override
  void initState() {
    super.initState();
    final r = widget.eintrag?.rechnung;
    _kundeId = r?.kundeId ?? widget.prefillKundeId;
    _auftragId = r?.auftragId ?? widget.prefillAuftragId;
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
    _pdfErstelltAm = r?.pdfErstelltAm;
    _savedId = r?.id;
    if (widget.eintrag == null) _prefill();
  }

  Future<void> _prefill() async {
    // Rechnungsnummer wird NICHT vorab reserviert — erst beim Drucken &
    // Einfrieren wird die nächste Nummer aus dem Nummernkreis vergeben.
    final fuss = await ref
        .read(einstellungenRepositoryProvider)
        .get(SettingsKeys.rechnungFusstext);
    if (mounted && _fuss.text.isEmpty) {
      // Default-Schlusstext: hinterlegter Rechnungs-Fußtext aus den
      // Einstellungen — sonst „Mit freundlichen Grüßen" + Name + Titel
      // des aktiven Benutzers.
      if (fuss != null && fuss.trim().isNotEmpty) {
        _fuss.text = fuss;
      } else {
        try {
          final benutzer = await ref
              .read(benutzerRepositoryProvider)
              .getActive();
          final name = [benutzer?.vorname, benutzer?.nachname]
              .whereType<String>()
              .where((s) => s.trim().isNotEmpty)
              .join(' ');
          final titel = (benutzer?.titel ?? '').trim();
          final lines = <String>[
            'Mit freundlichen Grüßen',
            '',
            if (name.isNotEmpty) name,
            if (titel.isNotEmpty) titel,
          ];
          _fuss.text = lines.join('\n');
        } catch (_) {
          _fuss.text = 'Mit freundlichen Grüßen';
        }
      }
    }
  }

  /// Baut die Briefanrede für einen Kunden — z. B. „Sehr geehrte Frau Müller,"
  /// oder „Sehr geehrter Herr Dr. Schmidt,". Bei Firma/Gericht ohne
  /// persönliche Anrede: „Sehr geehrte Damen und Herren,".
  String _briefanredeFuer(KundenData k) {
    final anrede = (k.anrede ?? '').trim();
    final titel = (k.titel ?? '').trim();
    final nachname = (k.nachname ?? '').trim();
    if (nachname.isEmpty || k.typ == 'gericht') {
      return 'Sehr geehrte Damen und Herren,';
    }
    final start = anrede.toLowerCase().contains('frau')
        ? 'Sehr geehrte Frau'
        : (anrede.toLowerCase().contains('herr')
            ? 'Sehr geehrter Herr'
            : 'Sehr geehrte/r');
    final mitTitel = titel.isEmpty ? nachname : '$titel $nachname';
    return '$start $mitTitel,';
  }

  /// Wendet eine Zahlungsziel-Vorlage an, indem sie die zugehörigen Felder
  /// (Tage, Fälligkeit, Skonto, Schlusstext) entsprechend setzt.
  Future<void> _applyZahlungsbedingungKey(String key) async {
    final list = await ref.read(zahlungszielVorlagenProvider.future);
    final v = list.firstWhere(
      (x) => x.key == key,
      orElse: () => list.isEmpty
          ? const ZahlungszielVorlage(
              key: '', label: '', tage: 14, text: '')
          : list.first,
    );
    if (!mounted || v.key.isEmpty) return;
    setState(() {
      _zahlungsbedingungKey = v.key;
      _zahlungsziel.text = v.tage.toString();
      _faelligAm = (_rechnungsdatum ?? DateTime.now())
          .add(Duration(days: v.tage));
      _skontoProzent = v.skontoProzent;
      _skontoTage = v.skontoTage;
      _barzahlung = v.bar;
      if (v.text.trim().isNotEmpty) _fuss.text = v.text.trim();
    });
  }

  /// Setzt die Anrede im Kopftext, wenn das Feld noch leer ist oder den
  /// generischen Default-Text enthält. Damit überschreiben wir keine
  /// manuell angepasste Anrede.
  Future<void> _autoAnredeFuerKunde(int? kundeId) async {
    if (kundeId == null) return;
    final kunde =
        await ref.read(kundenRepositoryProvider).byId(kundeId);
    if (kunde == null || !mounted) return;
    final neue = _briefanredeFuer(kunde);
    final aktuell = _kopf.text.trim();
    final istLeer = aktuell.isEmpty;
    final istDefault = aktuell.startsWith('Sehr geehrte Damen und Herren');
    if (istLeer || istDefault) {
      // Hänge den Standard-Folgesatz an
      final folge = '\n\nfür meine sachverständigen Leistungen erlaube ich mir zu berechnen:';
      setState(() => _kopf.text = '$neue$folge');
    }
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

  Future<void> _save({bool close = true}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_kundeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bitte zuerst einen Auftraggeber auswählen.')));
      return;
    }
    setState(() => _saving = true);

    // Nummernkreis: wenn neue Rechnung + Nummer leer → automatisch vergeben.
    // Akontoanforderungen laufen in einem eigenen Kreis (AZ{YYYY}-{NNN}),
    // alles andere (Rechnung, JVEG, Teil-, Schluss-, Gutschrift, Korrektur)
    // nutzt den Standard-Rechnungskreis.
    if (_nr.text.trim().isEmpty) {
      final kreis = _typ == 'akonto'
          ? NummernkreisTyp.akonto
          : NummernkreisTyp.rechnung;
      // Sicherstellen, dass keine Doppelvergabe entsteht: existierende
      // Belegnummern aus der DB einlesen und den Zähler ggf. hochsetzen.
      final db = ref.read(appDatabaseProvider);
      final query = db.select(db.rechnungen);
      if (_typ == 'akonto') {
        query.where((t) => t.typ.equals('akonto'));
      } else {
        query.where((t) => t.typ.isNotIn(const ['akonto']));
      }
      final existing = await query.get();
      final svc = ref.read(nummernkreisServiceProvider);
      await svc.syncCounterToHighestUsed(
          kreis, existing.map((r) => r.rechnungsnummer));
      _nr.text = await svc.nextNumber(kreis);
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
      final id = await ref.read(rechnungenRepositoryProvider).upsert(companion);
      if (mounted) setState(() => _savedId = id);
      if (close && mounted) {
        Navigator.of(context, rootNavigator: true).pop(true);
      } else if (mounted) {
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Future<void> _druckenUndEinfrieren() async {
    if (!_formKey.currentState!.validate()) return;
    await _save(close: false);
    if (!mounted) return;
    final id = _savedId;
    if (id == null) return;
    final data = await _buildPdfData();
    // Vorschau + Druckmöglichkeit
    await previewDocumentPdf(data);
    if (!mounted) return;
    // Einfrieren in DB
    final db = ref.read(appDatabaseProvider);
    final now = DateTime.now();
    await (db.update(db.rechnungen)..where((t) => t.id.equals(id))).write(
      RechnungenCompanion(
        pdfErstelltAm: Value(now),
        status: _status == 'entwurf' ? const Value('versendet') : const Value.absent(),
        updatedAt: Value(now),
      ),
    );
    if (mounted) {
      setState(() {
        _pdfErstelltAm = now;
        if (_status == 'entwurf') _status = 'versendet';
      });
    }
    // PDF sofort lokal ablegen + Cloud-Upload im Hintergrund
    await archivePdfLokalUndCloud(
      ref,
      data,
      auftragId: _auftragId,
      prefix: 'belege/rechnungen',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Dokument eingefroren und in der Akte abgelegt.')));
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
    // Aktenzeichen + Gerichtsdaten aus dem verknüpften Auftrag ziehen.
    String? aktenzeichen;
    String? gericht;
    String? gerichtsAz;
    String? klaeger;
    String? beklagter;
    if (_auftragId != null) {
      final list =
          await ref.read(auftraegeRepositoryProvider).watchAll().first;
      final a = list
          .where((a) => a.auftrag.id == _auftragId)
          .firstOrNull
          ?.auftrag;
      aktenzeichen = a?.aktenzeichen;
      gericht = a?.gericht;
      gerichtsAz = a?.gerichtsAktenzeichen;
      klaeger = a?.klaeger;
      beklagter = a?.beklagter;
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
      mitSepaQr: _typ != 'gutschrift' && !_barzahlung,
      skontoProzent: _skontoProzent,
      skontoTage: _skontoTage,
      barzahlung: _barzahlung,
      gericht: gericht,
      gerichtsAktenzeichen: gerichtsAz,
      klaeger: klaeger,
      beklagter: beklagter,
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
    final workflow = ref.read(dokumentWorkflowProvider);
    final gId =
        await workflow.rechnungToGutschrift(widget.eintrag!.rechnung);
    if (!mounted) return;
    await _openNeueRechnung(gId);
  }

  Future<void> _convertToKorrektur() async {
    if (!_isEdit) return;
    final workflow = ref.read(dokumentWorkflowProvider);
    final kId =
        await workflow.rechnungToKorrektur(widget.eintrag!.rechnung);
    if (!mounted) return;
    await _openNeueRechnung(kId);
  }

  /// Lädt eine soeben aus dem Workflow erzeugte Rechnung samt Kunde/Akte
  /// und öffnet den Rechnungs-Editor mit den vorbelegten Daten.
  Future<void> _openNeueRechnung(int rId) async {
    final db = ref.read(appDatabaseProvider);
    final rechnung = await ref.read(rechnungenRepositoryProvider).byId(rId);
    if (rechnung == null || !mounted) return;
    final kunde = rechnung.kundeId == null
        ? null
        : await ref.read(kundenRepositoryProvider).byId(rechnung.kundeId!);
    final auftrag = rechnung.auftragId == null
        ? null
        : await (db.select(db.auftraege)
              ..where((t) => t.id.equals(rechnung.auftragId!)))
            .getSingleOrNull();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(true);
    await showRechnungEditor(context,
        eintrag: RechnungWithKunde(rechnung, kunde, auftrag));
  }

  String _pdfTitleFor(String typ) => switch (typ) {
        'jveg' => 'Rechnung gemäß JVEG',
        'akonto' => 'Akontoanforderung',
        'teilrechnung' => 'Abschlagsrechnung',
        'schlussrechnung' => 'Schlussrechnung',
        'gutschrift' => 'Gutschrift',
        'korrektur' => 'Rechnungskorrektur',
        _ => 'Rechnung',
      };

  String _typLabel(String typ) => switch (typ) {
        'jveg' => 'JVEG-Rechnung (Gericht)',
        'akonto' => 'Akontoanforderung',
        'teilrechnung' => 'Teil-/Abschlagsrechnung',
        'schlussrechnung' => 'Schlussrechnung',
        'gutschrift' => 'Gutschrift',
        'korrektur' => 'Rechnungskorrektur',
        _ => 'Privat-Rechnung',
      };

  @override
  Widget build(BuildContext context) {
    final archiviert = widget.eintrag?.rechnung.pdfStorageUrl != null &&
        widget.eintrag!.rechnung.pdfStorageUrl!.isNotEmpty;
    final titleStr = _eingefroren
        ? '${_pdfTitleFor(_typ)} (eingefroren)'
        : (archiviert
            ? 'Rechnung (festgeschrieben)'
            : (_isEdit ? 'Rechnung bearbeiten' : 'Neue Rechnung'));
    return StandardFormDialog(
      title: titleStr,
      saving: _saving,
      maxWidth: 1100,
      maxHeight: 900,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _eingefroren ? null : _save,
      onDelete: _isEdit && !_eingefroren
          ? () async => ref
              .read(rechnungenRepositoryProvider)
              .delete(widget.eintrag!.rechnung.id)
          : null,
      footerLeading: Wrap(
        spacing: 6,
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
              onPressed: _previewPdf,
            ),
            FilledButton.icon(
              icon: const Icon(Icons.print_outlined, size: 16),
              label: const Text('Drucken & einfrieren'),
              onPressed: _druckenUndEinfrieren,
            ),
          ],
          if (_isEdit &&
              _eingefroren &&
              _typ != 'gutschrift' &&
              _typ != 'korrektur')
            OutlinedButton.icon(
              icon: const Icon(Icons.undo_outlined, size: 16),
              label: const Text('→ Gutschrift'),
              onPressed: _convertToGutschrift,
            ),
          if (_isEdit &&
              _eingefroren &&
              _typ != 'gutschrift' &&
              _typ != 'korrektur')
            OutlinedButton.icon(
              icon: const Icon(Icons.edit_note_outlined, size: 16),
              label: const Text('→ Korrektur'),
              onPressed: _convertToKorrektur,
            ),
          if (_isEdit && !_eingefroren) ...[
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
              if (archiviert) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AwTokens.amberSoft,
                    border: Border.all(color: AwTokens.line),
                    borderRadius: BorderRadius.circular(AwTokens.radiusMd),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline,
                          color: AwTokens.amber, size: 18),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Beleg ist festgeschrieben — eine PDF-Version '
                          'wurde archiviert und in die Akte-Dokumente '
                          'gelegt. Änderungen sollten nur für Fehler '
                          'erfolgen; erstelle sonst eine Korrektur-Rechnung.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              // Reihe 1: Rechnungstyp · Status
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
              // Reihe 2: Auftraggeber · Auftrag (optional)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: KundenPickerField(
                      kundeId: _kundeId,
                      label: 'Auftraggeber *',
                      onChanged: (id) async {
                        setState(() => _kundeId = id);
                        await _autoAnredeFuerKunde(id);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AuftragPickerField(
                      auftragId: _auftragId,
                      label: 'Akte (optional)',
                      onChanged: (id) async {
                        setState(() => _auftragId = id);
                        if (id != null) {
                          final a = await ref
                              .read(auftraegeRepositoryProvider)
                              .byId(id);
                          if (a == null || !mounted) return;
                          if (a.kundeId != null) {
                            setState(() => _kundeId = a.kundeId);
                            await _autoAnredeFuerKunde(a.kundeId);
                          }
                          if (a.zahlungsbedingung != null && mounted) {
                            await _applyZahlungsbedingungKey(
                                a.zahlungsbedingung!);
                          }
                        }
                      },
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
                      'Rechnungs-Nr.',
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
              if (_typ == 'akonto' ||
                  _typ == 'teilrechnung' ||
                  _typ == 'schlussrechnung')
                _RechnungsTypHinweis(typ: _typ),
              if (_typ == 'schlussrechnung' && _auftragId != null) ...[
                const SizedBox(height: 12),
                _SchlussrechnungAbzuege(auftragId: _auftragId!),
              ],
              const SizedBox(height: 14),
              // Anrede / Einleitungstext (Kopftext im PDF) — VOR den Positionen.
              LabeledField(
                'Anrede',
                TextFormField(
                  controller: _kopf,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText:
                        'Sehr geehrte Damen und Herren,\n\nfür meine sachverständigen Leistungen erlaube ich mir zu berechnen:',
                  ),
                ),
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
                  if (_typ == 'schlussrechnung' && _auftragId != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.remove_circle_outline, size: 16),
                      label: const Text('Abzüge übernehmen'),
                      onPressed: () => _abzuegeInPositionenUebernehmen(),
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
              // Rechnungssumme links · Zahlungsbedingung rechts
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
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
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: _ZahlungszielAuswahlControlled(
                      activeKey: _zahlungsbedingungKey,
                      onApply: (vorlage) {
                        setState(() {
                          _zahlungsbedingungKey = vorlage.key;
                          _zahlungsziel.text = vorlage.tage.toString();
                          _faelligAm = (_rechnungsdatum ?? DateTime.now())
                              .add(Duration(days: vorlage.tage));
                          _skontoProzent = vorlage.skontoProzent;
                          _skontoTage = vorlage.skontoTage;
                          _barzahlung = vorlage.bar;
                          if (vorlage.text.trim().isNotEmpty) {
                            _fuss.text = vorlage.text.trim();
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Schlusstext in voller Breite unter der Rechnungssumme.
              LabeledField(
                'Schlusstext / Zahlungshinweis',
                TextFormField(
                  controller: _fuss,
                  minLines: 4,
                  maxLines: 8,
                ),
              ),
              const SizedBox(height: 14),
              // Bezahlt-Status (zwei Felder, gleich breit)
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
                ],
              ),
              const SizedBox(height: 14),
              // Interne Notiz ganz unten in voller Breite.
              LabeledField(
                'Interne Notiz',
                TextFormField(
                    controller: _notiz, minLines: 2, maxLines: 4),
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

  /// Für Schlussrechnung: liest alle bezahlten Akonto- und alle offenen
  /// Teilrechnungen dieses Auftrags und fügt sie als Abzugs-Positionen
  /// (negative Beträge) am Ende der Positionen-Liste ein. Referenz-
  /// Nummern werden in die Bezeichnung geschrieben.
  Future<void> _abzuegeInPositionenUebernehmen() async {
    if (_auftragId == null) return;
    final db = ref.read(appDatabaseProvider);
    final alle = await (db.select(db.rechnungen)
          ..where((t) => t.auftragId.equals(_auftragId!))
          ..where((t) => t.typ.isIn(const ['akonto', 'teilrechnung'])))
        .get();
    final relevant = alle.where((r) {
      if (r.typ == 'teilrechnung') return r.status != 'storniert';
      // Akonto: nur wenn bezahlt, sonst USt-technisch nicht relevant
      return r.bezahltAm != null || r.status == 'bezahlt';
    }).toList();

    if (relevant.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Keine Teilrechnungen oder bezahlten Akontorechnungen gefunden.')));
      }
      return;
    }

    final df = DateFormat('dd.MM.yyyy', 'de');
    final mf = NumberFormat.currency(
        locale: 'de_DE', symbol: '€', decimalDigits: 2);

    final abzuege = relevant.map((r) {
      final nr = r.rechnungsnummer ?? '';
      final datum =
          r.rechnungsdatum == null ? '' : 'vom ${df.format(r.rechnungsdatum!)}';
      final bezahlt =
          r.bezahltAm == null ? '' : 'bezahlt am ${df.format(r.bezahltAm!)}';
      final head = r.typ == 'akonto'
          ? 'Akontoanforderung $nr'
          : 'Teilrechnung $nr';
      final parts = [head, datum, bezahlt]
          .where((s) => s.isNotEmpty)
          .join(' · ');
      final langtext =
          'Netto ${mf.format(r.netto)} · zzgl. USt ${r.ustSatz.toStringAsFixed(0)} % '
          '${mf.format(r.ustBetrag)} = brutto ${mf.format(r.brutto)}';
      return Position(
        menge: 1,
        bezeichnung: parts.trim(),
        langtext: langtext,
        einheit: 'Pauschal',
        einzelpreis: -r.netto,
        ustSatz: r.ustSatz,
      );
    }).toList();

    setState(() => _positionen = [..._positionen, ...abzuege]);
  }

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

/// Wie [_ZahlungszielAuswahl], aber mit aktivem Wert (controlled), damit der
/// aktuell gewählte Eintrag im Dropdown sichtbar bleibt.
class _ZahlungszielAuswahlControlled extends ConsumerWidget {
  const _ZahlungszielAuswahlControlled({
    required this.activeKey,
    required this.onApply,
  });
  final String? activeKey;
  final void Function(ZahlungszielVorlage) onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(zahlungszielVorlagenProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Text('Zahlungsziel-Vorlagen: Fehler $e'),
      data: (list) {
        final value = list.any((v) => v.key == activeKey) ? activeKey : null;
        return LabeledField(
          'Zahlungsbedingung',
          DropdownButtonFormField<String>(
            initialValue: value,
            isDense: true,
            isExpanded: true,
            hint: const Text('Vorlage wählen …'),
            items: [
              for (final v in list)
                DropdownMenuItem(
                  value: v.key,
                  child: Text(v.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (key) {
              if (key == null) return;
              final v = list.firstWhere((x) => x.key == key,
                  orElse: () => list.first);
              onApply(v);
            },
          ),
        );
      },
    );
  }
}

/// Hinweis-Kachel beim Rechnungstyp „Akonto", „Teilrechnung" oder
/// „Schlussrechnung". Erklärt die USt-Besonderheit und wie Aktenwerk das
/// handhabt.
class _RechnungsTypHinweis extends StatelessWidget {
  const _RechnungsTypHinweis({required this.typ});
  final String typ;

  @override
  Widget build(BuildContext context) {
    final (titel, text, color) = _infoFuer(typ);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titel,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color)),
                const SizedBox(height: 4),
                Text(text, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (String, String, Color) _infoFuer(String typ) {
    switch (typ) {
      case 'akonto':
        return (
          'Akontoanforderung (Nummernkreis AZ{YYYY}-…)',
          'Reine Zahlungsaufforderung — USt-Pflicht entsteht erst mit Zahlungseingang (Zufluss-/Istversteuerung §13 Abs. 1 Nr. 1 b UStG). Sobald die Anforderung bezahlt ist, trägt sie zur USt-Bemessungsgrundlage bei und wird in der Schlussrechnung als „Bezahlte Akontoanforderung …" abgezogen.',
          AwTokens.amber,
        );
      case 'teilrechnung':
        return (
          'Teil-/Abschlagsrechnung',
          'USt-pflichtig mit Rechnungsdatum (Soll-Versteuerung §13 Abs. 1 Nr. 1 a UStG). Netto + USt werden sofort in der Voranmeldung geführt. Bezahlte Teilrechnungen werden in der Schlussrechnung als Abzug ausgewiesen.',
          AwTokens.blue,
        );
      case 'schlussrechnung':
        return (
          'Schlussrechnung',
          'Weist das volle Auftragshonorar aus und zieht alle vorangegangenen Teilrechnungen sowie bezahlten Akontorechnungen mit jeweiliger USt ab (§14 Abs. 5 UStG). Den Button „Abzüge übernehmen" klicken, um die Abzugs-Positionen automatisch anzulegen.',
          AwTokens.green,
        );
    }
    return ('', '', AwTokens.mute);
  }
}

/// Kleine Kachel, die die relevanten Akonto-/Teilrechnungen zur Akte
/// in der Schlussrechnung auflistet — bevor sie als Positionen übernommen
/// werden. So sieht der Nutzer, was Aktenwerk kennt.
class _SchlussrechnungAbzuege extends ConsumerWidget {
  const _SchlussrechnungAbzuege({required this.auftragId});
  final int auftragId;

  static final _money = NumberFormat.currency(
      locale: "de_DE", symbol: "€", decimalDigits: 2);
  static final _fmt = DateFormat("dd.MM.yyyy", "de");

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    return FutureBuilder<List<RechnungenData>>(
      future: (db.select(db.rechnungen)
            ..where((t) => t.auftragId.equals(auftragId))
            ..where((t) => t.typ.isIn(const ['akonto', 'teilrechnung'])))
          .get(),
      builder: (ctx, snap) {
        final list = snap.data ?? const [];
        if (list.isEmpty) {
          return const SizedBox.shrink();
        }
        double summe = 0;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AwTokens.greenSoft,
            border: Border.all(color: AwTokens.line),
            borderRadius: BorderRadius.circular(AwTokens.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text("Vorhandene Teil-/Akontorechnungen dieser Akte",
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final r in list) ...[
                Builder(builder: (_) {
                  final bezahlt = r.bezahltAm != null || r.status == "bezahlt";
                  final istAkonto = r.typ == "akonto";
                  final relevant = istAkonto ? bezahlt : r.status != "storniert";
                  if (relevant) summe += r.netto;
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          relevant
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 14,
                          color: relevant ? AwTokens.green : AwTokens.amber,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "${istAkonto ? "Akonto" : "Teilrg."} ${r.rechnungsnummer ?? ""} · ${r.rechnungsdatum == null ? "" : _fmt.format(r.rechnungsdatum!)} · ${bezahlt ? "bezahlt" : "offen"}",
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Text(_money.format(r.netto),
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  );
                }),
              ],
              const Divider(height: 14),
              Row(
                children: [
                  const Expanded(
                      child: Text("Summe abziehbar (netto)",
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700))),
                  Text(_money.format(summe),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

