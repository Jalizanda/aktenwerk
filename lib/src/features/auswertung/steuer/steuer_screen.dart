import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/theme/app_theme.dart';
import '../../../features/akten/eingangsrechnungen/eingangsrechnungen_repository.dart';
import '../../../features/akten/rechnungen/rechnungen_repository.dart';
import '../../../features/system/einstellungen/absender_service.dart';
import '../../../features/system/einstellungen/einstellungen_repository.dart';
import '../../../shared/charts/chart_theme.dart';
import '../../../shared/pdf/document_pdf.dart';
import '../../../shared/positionen/position_model.dart';
import '../../../shared/widgets/module_scaffold.dart';
import '../datev/datev_export.dart';

class SteuerScreen extends ConsumerStatefulWidget {
  const SteuerScreen({super.key});
  @override
  ConsumerState<SteuerScreen> createState() => _SteuerScreenState();
}

class _SteuerScreenState extends ConsumerState<SteuerScreen> {
  int _jahr = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat.currency(locale: 'de', symbol: '€');
    final rechnungen = ref.watch(rechnungenListProvider);
    final eingangsrechnungen = ref.watch(eingangsrechnungenListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.query_stats_outlined,
          title: 'Steuer & Statistik',
          subtitle: 'USt-Voranmeldung & Einnahmen-Überschuss',
          filters: [
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _jahr,
                items: [
                  for (var y = DateTime.now().year; y >= DateTime.now().year - 5; y--)
                    DropdownMenuItem(value: y, child: Text('Jahr $y')),
                ],
                onChanged: (v) => setState(() => _jahr = v ?? DateTime.now().year),
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: (rechnungen.isLoading || eingangsrechnungen.isLoading)
              ? const Center(child: CircularProgressIndicator())
              : _buildContent(
                  context,
                  theme,
                  money,
                  rechnungen.valueOrNull ?? [],
                  eingangsrechnungen.valueOrNull ?? [],
                ),
        ),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    NumberFormat money,
    List<RechnungWithKunde> rechnungen,
    List<EingangsrechnungWithAuftrag> eingangs,
  ) {
    final einnahmen = List.filled(12, 0.0);
    final ausgaben = List.filled(12, 0.0);
    double jahresNetto = 0, jahresUst = 0;
    double vorsteuer = 0;
    double ausgabenJahr = 0;

    for (final r in rechnungen) {
      final d = r.rechnung.rechnungsdatum;
      if (d == null || d.year != _jahr) continue;
      einnahmen[d.month - 1] += r.rechnung.brutto;
      jahresNetto += r.rechnung.netto;
      jahresUst += r.rechnung.ustBetrag;
    }
    for (final e in eingangs) {
      final d = e.rechnung.rechnungsdatum;
      if (d == null || d.year != _jahr) continue;
      ausgaben[d.month - 1] += e.rechnung.brutto;
      ausgabenJahr += e.rechnung.netto;
      vorsteuer += e.rechnung.ustBetrag;
    }

    final ustZahllast = jahresUst - vorsteuer;
    final eurGewinn = jahresNetto - ausgabenJahr;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Stat(
                  label: 'Umsatz netto $_jahr',
                  value: money.format(jahresNetto),
                  color: theme.colorScheme.primary),
              _Stat(
                  label: 'USt eingenommen',
                  value: money.format(jahresUst)),
              _Stat(
                  label: 'Vorsteuer',
                  value: money.format(vorsteuer)),
              _Stat(
                  label: 'USt-Zahllast',
                  value: money.format(ustZahllast),
                  color: ustZahllast > 0 ? theme.colorScheme.error : null),
              _Stat(
                  label: 'Ausgaben netto',
                  value: money.format(ausgabenJahr)),
              _Stat(
                  label: 'Gewinn (EÜR)',
                  value: money.format(eurGewinn),
                  color: theme.colorScheme.tertiary),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: theme.colorScheme.outlineVariant),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Umsatz pro Monat',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                SizedBox(
                  height: 280,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      barTouchData: ChartStyle.barTouchData(
                        format: (v) => NumberFormat.currency(
                                locale: 'de_DE',
                                symbol: '€',
                                decimalDigits: 0)
                            .format(v),
                      ),
                      barGroups: [
                        for (var m = 0; m < 12; m++)
                          BarChartGroupData(x: m, barRods: [
                            ChartStyle.bar(einnahmen[m],
                                from: AppTheme.accent600,
                                to: AppTheme.accent500,
                                width: 12),
                            ChartStyle.bar(ausgaben[m],
                                from: const Color(0xFF1D4ED8),
                                to: const Color(0xFF3B82F6),
                                width: 12),
                          ]),
                      ],
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 60,
                                getTitlesWidget: (v, _) => Text(
                                    v.toStringAsFixed(0),
                                    style:
                                        const TextStyle(fontSize: 11)))),
                        rightTitles: ChartStyle.emptyAxis(),
                        topTitles: ChartStyle.emptyAxis(),
                        bottomTitles: ChartStyle.bottomLabels(const [
                          'J', 'F', 'M', 'A', 'M', 'J',
                          'J', 'A', 'S', 'O', 'N', 'D'
                        ]),
                      ),
                      gridData: ChartStyle.gridData(),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  _LegendItem(
                      color: AppTheme.accent600, label: 'Einnahmen'),
                  const SizedBox(width: 24),
                  _LegendItem(
                      color: const Color(0xFF1D4ED8), label: 'Ausgaben'),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _KategorienPie(
                  titel: 'Einnahmen nach Kategorie',
                  daten: _einnahmenNachKategorie(rechnungen),
                  orangePalette: true,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _KategorienPie(
                  titel: 'Ausgaben nach Kategorie',
                  daten: _ausgabenNachKategorie(eingangs),
                  orangePalette: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text('USt-Voranmeldung pro Quartal',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          _ustVoranmeldung(context, rechnungen, eingangs, money),
          const SizedBox(height: 24),
          Text('BWA-Monatsübersicht', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          _bwaMonatstabelle(context, rechnungen, eingangs, money),
          const SizedBox(height: 24),
          Text('Belegjournal — Monats-Sammelausdrucke',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Pro Monat aller Ausgangsrechnungen als eine PDF bündeln und herunterladen.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          _belegjournalMonate(context, rechnungen, money),
          const SizedBox(height: 28),
          Text('DATEV-Export für den Steuerberater',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Buchungsstapel-CSV (DATEV-Format „EXTF" v13) plus Belegjournal-ZIP '
            'mit allen PDFs und einer Übersichts-CSV — direkt importierbar in '
            'DATEV Kanzlei-Rechnungswesen oder DATEV Unternehmen Online.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _DatevExportSection(jahr: _jahr),
        ],
      ),
    );
  }

  /// Listet die 12 Monate des Jahres mit Anzahl Rechnungen + Brutto-
  /// Summe und einem „PDF-Sammelausdruck"-Button. Für jeden Monat mit
  /// mindestens einer Rechnung wird beim Klick ein kombiniertes PDF
  /// mit allen Belegen dieses Monats erzeugt.
  Widget _belegjournalMonate(
    BuildContext context,
    List<RechnungWithKunde> rechnungen,
    NumberFormat money,
  ) {
    final monate = <int, List<RechnungWithKunde>>{};
    for (final r in rechnungen) {
      final d = r.rechnung.rechnungsdatum;
      if (d == null || d.year != _jahr) continue;
      monate.putIfAbsent(d.month, () => []).add(r);
    }
    final monatsnamen = [
      'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
    ];
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: DataTable(
        showCheckboxColumn: false,
        columns: const [
          DataColumn(label: Text('Monat')),
          DataColumn(label: Text('Belege'), numeric: true),
          DataColumn(label: Text('Brutto €'), numeric: true),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (var m = 1; m <= 12; m++)
            DataRow(cells: [
              DataCell(Text('${monatsnamen[m - 1]} $_jahr')),
              DataCell(Text('${monate[m]?.length ?? 0}')),
              DataCell(Text(money.format((monate[m] ?? [])
                  .fold<double>(0, (a, r) => a + r.rechnung.brutto)))),
              DataCell(
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 14),
                  label: const Text('Sammel-PDF'),
                  onPressed: (monate[m] ?? []).isEmpty
                      ? null
                      : () => _monatsSammelPdf(
                          context, _jahr, m, monate[m]!),
                ),
              ),
            ]),
        ],
      ),
    );
  }

  Future<void> _monatsSammelPdf(
    BuildContext context,
    int jahr,
    int monat,
    List<RechnungWithKunde> rechnungen,
  ) async {
    final absender = await absenderFromSettings(ref);
    final fuss = await ref
        .read(einstellungenRepositoryProvider)
        .get(SettingsKeys.rechnungFusstext);
    final allData = <PdfDocumentData>[];
    for (final r in rechnungen) {
      allData.add(PdfDocumentData(
        dokumentTyp: _titelFuer(r.rechnung.typ),
        dokumentNr: r.rechnung.rechnungsnummer,
        datum: r.rechnung.rechnungsdatum,
        faelligBis: r.rechnung.faelligAm,
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
      ));
    }
    final merged = await buildMergedDocumentsPdf(allData);
    if (!context.mounted) return;
    final name =
        'belegjournal_${jahr}_${monat.toString().padLeft(2, '0')}.pdf';
    await Printing.sharePdf(bytes: merged, filename: name);
  }

  String _titelFuer(String typ) => switch (typ) {
        'jveg' => 'Rechnung gemäß JVEG',
        'akonto' => 'Akontoanforderung',
        'teilrechnung' => 'Abschlagsrechnung',
        'schlussrechnung' => 'Schlussrechnung',
        'gutschrift' => 'Gutschrift',
        'korrektur' => 'Rechnungskorrektur',
        _ => 'Rechnung',
      };

  /// USt-Voranmeldung pro Quartal: Anzahl Rechnungen, Erlöse netto,
  /// USt (Schuld), Vorsteuer, USt-Zahllast.
  Widget _ustVoranmeldung(
      BuildContext context,
      List<RechnungWithKunde> rechnungen,
      List<EingangsrechnungWithAuftrag> eingangs,
      NumberFormat money) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <_QRow>[];
    for (var q = 1; q <= 4; q++) {
      final monStart = (q - 1) * 3 + 1;
      final monEnd = q * 3;
      int anzahl = 0;
      double erloese = 0, ust = 0, vor = 0;
      for (final r in rechnungen) {
        final d = r.rechnung.rechnungsdatum;
        if (d == null || d.year != _jahr) continue;
        if (d.month < monStart || d.month > monEnd) continue;
        if (r.rechnung.status == 'storniert') continue;
        anzahl++;
        erloese += r.rechnung.netto;
        ust += r.rechnung.ustBetrag;
      }
      for (final e in eingangs) {
        final d = e.rechnung.rechnungsdatum;
        if (d == null || d.year != _jahr) continue;
        if (d.month < monStart || d.month > monEnd) continue;
        vor += e.rechnung.ustBetrag;
      }
      rows.add(_QRow(q, anzahl, erloese, ust, vor));
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DataTable(
              showCheckboxColumn: false,
        headingRowColor:
            WidgetStateProperty.all(scheme.surfaceContainerHighest),
        columns: const [
          DataColumn(label: Text('Quartal')),
          DataColumn(label: Text('Rechnungen'), numeric: true),
          DataColumn(label: Text('Erlöse netto €'), numeric: true),
          DataColumn(label: Text('USt (Schuld) €'), numeric: true),
          DataColumn(label: Text('Vorsteuer €'), numeric: true),
          DataColumn(label: Text('Zahllast €'), numeric: true),
        ],
        rows: [
          for (final r in rows)
            DataRow(cells: [
              DataCell(Text('Q${r.q} $_jahr',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
              DataCell(Text('${r.anzahl}')),
              DataCell(Text(money.format(r.erloese))),
              DataCell(Text(money.format(r.ust))),
              DataCell(Text(money.format(r.vor))),
              DataCell(Text(money.format(r.ust - r.vor),
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: (r.ust - r.vor) > 0
                          ? Theme.of(context).colorScheme.error
                          : null))),
            ]),
          // Jahres-Zeile
          DataRow(
            color: WidgetStateProperty.all(scheme.surfaceContainerHighest),
            cells: [
              const DataCell(Text('Jahr',
                  style: TextStyle(fontWeight: FontWeight.w700))),
              DataCell(Text('${rows.fold<int>(0, (a, r) => a + r.anzahl)}',
                  style: const TextStyle(fontWeight: FontWeight.w700))),
              DataCell(Text(
                  money.format(rows.fold<double>(0, (a, r) => a + r.erloese)),
                  style: const TextStyle(fontWeight: FontWeight.w700))),
              DataCell(Text(
                  money.format(rows.fold<double>(0, (a, r) => a + r.ust)),
                  style: const TextStyle(fontWeight: FontWeight.w700))),
              DataCell(Text(
                  money.format(rows.fold<double>(0, (a, r) => a + r.vor)),
                  style: const TextStyle(fontWeight: FontWeight.w700))),
              DataCell(Text(
                  money.format(rows.fold<double>(
                      0, (a, r) => a + r.ust - r.vor)),
                  style: const TextStyle(fontWeight: FontWeight.w700))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bwaMonatstabelle(
      BuildContext context,
      List<RechnungWithKunde> rechnungen,
      List<EingangsrechnungWithAuftrag> eingangs,
      NumberFormat money) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DataTable(
              showCheckboxColumn: false,
        headingRowColor:
            WidgetStateProperty.all(scheme.surfaceContainerHighest),
        columns: const [
          DataColumn(label: Text('Monat')),
          DataColumn(label: Text('Erlöse netto €'), numeric: true),
          DataColumn(label: Text('USt-Schuld €'), numeric: true),
          DataColumn(label: Text('Ausgaben netto €'), numeric: true),
          DataColumn(label: Text('Vorsteuer €'), numeric: true),
          DataColumn(label: Text('Ergebnis €'), numeric: true),
        ],
        rows: [
          for (var m = 1; m <= 12; m++) _bwaMonat(context, m, rechnungen, eingangs, money),
        ],
      ),
    );
  }

  DataRow _bwaMonat(
      BuildContext context,
      int m,
      List<RechnungWithKunde> rechnungen,
      List<EingangsrechnungWithAuftrag> eingangs,
      NumberFormat money) {
    double erl = 0, ust = 0, ausg = 0, vor = 0;
    for (final r in rechnungen) {
      final d = r.rechnung.rechnungsdatum;
      if (d == null || d.year != _jahr || d.month != m) continue;
      if (r.rechnung.status == 'storniert') continue;
      erl += r.rechnung.netto;
      ust += r.rechnung.ustBetrag;
    }
    for (final e in eingangs) {
      final d = e.rechnung.rechnungsdatum;
      if (d == null || d.year != _jahr || d.month != m) continue;
      ausg += e.rechnung.netto;
      vor += e.rechnung.ustBetrag;
    }
    return DataRow(cells: [
      DataCell(Text(_monat(m - 1))),
      DataCell(Text(money.format(erl))),
      DataCell(Text(money.format(ust))),
      DataCell(Text(money.format(ausg))),
      DataCell(Text(money.format(vor))),
      DataCell(Text(money.format(erl - ausg),
          style: const TextStyle(fontWeight: FontWeight.w600))),
    ]);
  }

  String _monat(int i) => const [
        'Jan',
        'Feb',
        'Mrz',
        'Apr',
        'Mai',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Okt',
        'Nov',
        'Dez'
      ][i];

  // ---------- Kategorien-Aggregation ----------

  Map<String, double> _einnahmenNachKategorie(
      List<RechnungWithKunde> rechnungen) {
    final m = <String, double>{};
    for (final r in rechnungen) {
      if (r.rechnung.status == 'storniert') continue;
      final d = r.rechnung.rechnungsdatum;
      if (d == null || d.year != _jahr) continue;
      // Kategorie aus Auftragsart ableiten: JVEG = Gericht, sonst Privat.
      final key = r.rechnung.typ == 'jveg'
          ? 'Gericht / JVEG'
          : r.rechnung.typ == 'gutschrift'
              ? 'Gutschrift'
              : r.rechnung.typ == 'korrektur'
                  ? 'Rechnungs-Korrektur'
                  : 'Privat-Rechnung';
      m[key] = (m[key] ?? 0) + r.rechnung.netto;
    }
    return m;
  }

  Map<String, double> _ausgabenNachKategorie(
      List<EingangsrechnungWithAuftrag> eingangs) {
    final m = <String, double>{};
    for (final e in eingangs) {
      if (e.rechnung.status == 'storniert') continue;
      final d = e.rechnung.rechnungsdatum;
      if (d == null || d.year != _jahr) continue;
      final key = (e.rechnung.kategorie ?? '').trim().isEmpty
          ? 'Sonstige Ausgaben'
          : e.rechnung.kategorie!.trim();
      m[key] = (m[key] ?? 0) + e.rechnung.netto;
    }
    return m;
  }
}

/// Pie-Chart mit Legende — zeigt Beträge pro Kategorie aufgeschlüsselt.
/// Orange-Palette für Einnahmen, Blau-Palette für Ausgaben.
class _KategorienPie extends StatelessWidget {
  const _KategorienPie({
    required this.titel,
    required this.daten,
    required this.orangePalette,
  });
  final String titel;
  final Map<String, double> daten;
  final bool orangePalette;

  static final _money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);

  List<Color> get _palette => orangePalette
      ? const [
          AppTheme.accent600,
          AppTheme.accent500,
          Color(0xFFFB923C),
          Color(0xFFFED7AA),
          Color(0xFFB45309),
          Color(0xFF7C2D12),
        ]
      : const [
          Color(0xFF1D4ED8),
          Color(0xFF3B82F6),
          Color(0xFF60A5FA),
          Color(0xFF93C5FD),
          Color(0xFF1E3A8A),
          Color(0xFF475569),
        ];

  @override
  Widget build(BuildContext context) {
    final entries = daten.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (s, e) => s + e.value);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titel,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 4),
          Text(_money.format(total),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: orangePalette
                      ? AppTheme.accent600
                      : const Color(0xFF1D4ED8))),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const SizedBox(
              height: 180,
              child: Center(
                child: Text('Keine Daten im aktuellen Jahr.',
                    style: TextStyle(fontSize: 12)),
              ),
            )
          else
            // Höhe nicht mehr fix — das Container wächst mit der
            // Legende mit, damit alle Kategorien sichtbar sind.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 180,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 30,
                          pieTouchData: PieTouchData(
                            touchCallback: (event, response) {},
                          ),
                          sections: [
                            for (var i = 0; i < entries.length; i++)
                              PieChartSectionData(
                                value: entries[i].value,
                                color: _palette[i % _palette.length],
                                title:
                                    '${(entries[i].value / total * 100).toStringAsFixed(0)}%',
                                radius: 55,
                                titleStyle: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < entries.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _palette[i % _palette.length],
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    entries[i].key,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                Text(
                                  _money.format(entries[i].value),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side:
              BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
              Text(value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      )),
            ],
          ),
        ),
      ),
    );
  }
}

class _QRow {
  final int q;
  final int anzahl;
  final double erloese;
  final double ust;
  final double vor;
  _QRow(this.q, this.anzahl, this.erloese, this.ust, this.vor);
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(width: 14, height: 14, color: color),
        const SizedBox(width: 6),
        Text(label),
      ]);
}

class _DatevExportSection extends ConsumerStatefulWidget {
  const _DatevExportSection({required this.jahr});
  final int jahr;
  @override
  ConsumerState<_DatevExportSection> createState() =>
      _DatevExportSectionState();
}

class _DatevExportSectionState
    extends ConsumerState<_DatevExportSection> {
  late DateTime _von = DateTime(widget.jahr, 1, 1);
  late DateTime _bis = DateTime(widget.jahr, 12, 31);
  final _berater = TextEditingController();
  final _mandant = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _berater.dispose();
    _mandant.dispose();
    super.dispose();
  }

  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    try {
      final bytes =
          await ref.read(datevExportServiceProvider).erstelleBuchungsstapel(
                vonDatum: _von,
                bisDatum: _bis,
                mandantNr: _mandant.text.trim(),
                beraterNr: _berater.text.trim(),
              );
      final fname =
          'DATEV_Buchungsstapel_${DateFormat('yyyyMMdd').format(_von)}_${DateFormat('yyyyMMdd').format(_bis)}.csv';
      await Printing.sharePdf(bytes: bytes, filename: fname);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportZip() async {
    setState(() => _busy = true);
    try {
      final bytes =
          await ref.read(datevExportServiceProvider).erstelleBelegjournalZip(
                vonDatum: _von,
                bisDatum: _bis,
              );
      final fname =
          'Belegjournal_${DateFormat('yyyyMMdd').format(_von)}_${DateFormat('yyyyMMdd').format(_bis)}.zip';
      await Printing.sharePdf(bytes: bytes, filename: fname);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy', 'de');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                      context: context,
                      initialDate: _von,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100));
                  if (picked != null) setState(() => _von = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Von'),
                  child: Text(fmt.format(_von)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                      context: context,
                      initialDate: _bis,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100));
                  if (picked != null) setState(() => _bis = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Bis'),
                  child: Text(fmt.format(_bis)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _berater,
                decoration: const InputDecoration(
                    labelText: 'Berater-Nr.',
                    hintText: 'optional, vom Steuerberater'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _mandant,
                decoration: const InputDecoration(
                    labelText: 'Mandanten-Nr.',
                    hintText: 'optional, vom Steuerberater'),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Buchungsstapel-CSV'),
                onPressed: _busy ? null : _exportCsv,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_zip_outlined, size: 18),
                label: const Text('Belegjournal als ZIP'),
                onPressed: _busy ? null : _exportZip,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
