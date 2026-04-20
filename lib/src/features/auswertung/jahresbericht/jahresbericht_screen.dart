import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../features/akten/auftraege/auftraege_repository.dart';
import '../../../features/akten/kunden/kunden_repository.dart';
import '../../../features/akten/rechnungen/rechnungen_repository.dart';
import '../../../features/auswertung/fortbildungen/fortbildungen_repository.dart';
import '../../../features/system/einstellungen/absender_service.dart';
import '../../../features/system/einstellungen/einstellungen_repository.dart';
import '../../../shared/charts/chart_theme.dart';
import '../../../shared/widgets/badges.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'jahresbericht_pdf.dart';
import 'taetigkeitsbericht_pdf.dart';

class JahresberichtScreen extends ConsumerStatefulWidget {
  const JahresberichtScreen({super.key});
  @override
  ConsumerState<JahresberichtScreen> createState() =>
      _JahresberichtScreenState();
}

class _JahresberichtScreenState
    extends ConsumerState<JahresberichtScreen> {
  int _jahr = DateTime.now().year;

  Future<void> _druckeTaetigkeitsbericht() async {
    final absender = await absenderFromSettings(ref);
    final repo = ref.read(einstellungenRepositoryProvider);
    final siegelB64 = await repo.get(SettingsKeys.siegelBase64);
    final beh = await repo.get(SettingsKeys.siegelBestellBehoerde);
    final nr = await repo.get(SettingsKeys.siegelBestellNr);
    final gueltigRaw = await repo.get(SettingsKeys.siegelGueltigBis);
    final empf = await repo.get(SettingsKeys.taetigkeitBerichtEmpfaenger);
    final vorwort = await repo.get(SettingsKeys.taetigkeitBerichtVorwort);
    final eides = await repo.get(SettingsKeys.taetigkeitBerichtEidesstatt);

    final allAuftraege = ref.read(auftraegeListProvider).valueOrNull ?? const [];
    final allRechnungen =
        ref.read(rechnungenListProvider).valueOrNull ?? const [];
    final allKunden = ref.read(kundenListProvider).valueOrNull ?? const [];
    final allFortbildungen =
        ref.read(fortbildungenListProvider).valueOrNull ?? const [];

    final jahresAuftraege = allAuftraege
        .map((a) => a.auftrag)
        .where((a) =>
            a.eingangAm != null && a.eingangAm!.year == _jahr)
        .toList();
    final jahresRechnungen = allRechnungen
        .map((r) => r.rechnung)
        .where((r) =>
            r.rechnungsdatum != null && r.rechnungsdatum!.year == _jahr)
        .toList();
    final jahresFortbildungen = allFortbildungen
        .where((f) =>
            (f.datumVon ?? f.datumBis) != null &&
            ((f.datumVon ?? f.datumBis)!.year == _jahr))
        .toList();

    await previewTaetigkeitsbericht(TaetigkeitsberichtData(
      jahr: _jahr,
      auftraege: jahresAuftraege,
      kunden: allKunden,
      rechnungen: jahresRechnungen,
      fortbildungen: jahresFortbildungen,
      absender: absender,
      siegelBytes: decodeSiegelBase64(siegelB64),
      bestellBehoerde: beh,
      bestellNr: nr,
      bestellGueltigBis:
          (gueltigRaw != null && gueltigRaw.isNotEmpty)
              ? DateTime.tryParse(gueltigRaw)
              : null,
      empfaenger: empf ?? '',
      vorwort: vorwort ?? '',
      eidesstattlich: eides ?? '',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final auftraege = ref.watch(auftraegeListProvider);
    final rechnungen = ref.watch(rechnungenListProvider);
    final fortbSummen = ref.watch(fortbildungenSummenProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.picture_as_pdf_outlined,
          title: 'Jahresbericht',
          subtitle: 'Zusammenfassung für IHK / Bestellungsbehörde',
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.verified_outlined, size: 18),
              label: const Text('Tätigkeitsbericht drucken'),
              onPressed: () => _druckeTaetigkeitsbericht(),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Als PDF exportieren'),
              onPressed: () async {
                final absender = await absenderFromSettings(ref);
                await previewJahresberichtPdf(JahresberichtPdfData(
                  jahr: _jahr,
                  auftraege: auftraege.valueOrNull ?? const [],
                  rechnungen: rechnungen.valueOrNull ?? const [],
                  fortbSummen: fortbSummen.valueOrNull ?? const {},
                  absender: absender,
                ));
              },
            ),
          ],
          filters: [
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _jahr,
                items: [
                  for (var y = DateTime.now().year;
                      y >= DateTime.now().year - 5;
                      y--)
                    DropdownMenuItem(value: y, child: Text('Jahr $y')),
                ],
                onChanged: (v) =>
                    setState(() => _jahr = v ?? DateTime.now().year),
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // KPI-Zeile
                  _KpiRow(
                    jahr: _jahr,
                    auftraege: auftraege.valueOrNull ?? const [],
                    rechnungen: rechnungen.valueOrNull ?? const [],
                    fortb: fortbSummen.valueOrNull ?? const {},
                  ),
                  const SizedBox(height: 20),
                  // Zwei Info-Boxen: Aufträge nach Art & nach Sachgebiet
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _block(
                          context,
                          'Gutachten nach Art',
                          auftraege.when(
                            data: (list) => _artBlock(list),
                            loading: () =>
                                const CircularProgressIndicator(),
                            error: (e, _) => Text('$e'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _block(
                          context,
                          'Gutachten nach Sachgebiet',
                          auftraege.when(
                            data: (list) => _sachgebietBlock(list),
                            loading: () =>
                                const CircularProgressIndicator(),
                            error: (e, _) => Text('$e'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Charts
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _block(
                          context,
                          'Umsatz pro Monat',
                          rechnungen.when(
                            data: (list) => _umsatzMonatChart(list),
                            loading: () =>
                                const CircularProgressIndicator(),
                            error: (e, _) => Text('$e'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _block(
                          context,
                          'Sachgebiete (Anteile)',
                          auftraege.when(
                            data: (list) => _sachgebietPie(list),
                            loading: () =>
                                const CircularProgressIndicator(),
                            error: (e, _) => Text('$e'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _block(
                    context,
                    'Fortbildungsstunden',
                    fortbSummen.when(
                      data: (m) => Column(children: [
                        _kv('Stunden $_jahr',
                            '${(m[_jahr] ?? 0).toStringAsFixed(1)} h'),
                        _kv(
                          'Vorjahr ${_jahr - 1}',
                          '${(m[_jahr - 1] ?? 0).toStringAsFixed(1)} h',
                        ),
                        _kv(
                          'Zwei Jahre zuvor ${_jahr - 2}',
                          '${(m[_jahr - 2] ?? 0).toStringAsFixed(1)} h',
                        ),
                      ]),
                      loading: () => const CircularProgressIndicator(),
                      error: (e, _) => Text('$e'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _artBlock(List<AuftragWithKunde> list) {
    final jahr = list
        .where((a) =>
            (a.auftrag.auftragAm ?? a.auftrag.eingangAm)?.year == _jahr)
        .toList();
    final privat =
        jahr.where((a) => a.auftrag.art == 'privat').length;
    final gericht =
        jahr.where((a) => a.auftrag.art == 'gericht').length;
    final schieds = jahr
        .where((a) => a.auftrag.art == 'schiedsgutachten')
        .length;
    final bewsich = jahr
        .where((a) => a.auftrag.art == 'beweissicherung')
        .length;
    return Column(children: [
      _kv('Privatgutachten', '$privat'),
      _kv('Gerichtsgutachten', '$gericht'),
      _kv('Schiedsgutachten', '$schieds'),
      _kv('Beweissicherung', '$bewsich'),
      _kv('Gesamt', '${jahr.length}', bold: true),
    ]);
  }

  Widget _sachgebietBlock(List<AuftragWithKunde> list) {
    final jahr = list.where((a) =>
        (a.auftrag.auftragAm ?? a.auftrag.eingangAm)?.year == _jahr);
    final m = <String, int>{};
    for (final a in jahr) {
      final k = (a.auftrag.sachgebiet ?? '').trim();
      if (k.isEmpty) continue;
      m[k] = (m[k] ?? 0) + 1;
    }
    final sorted = m.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.isEmpty) {
      return const Text('Keine Sachgebiete im Jahr erfasst.',
          style: TextStyle(fontSize: 12));
    }
    return Column(children: [
      for (final e in sorted.take(10))
        _kv(e.key, '${e.value}'),
    ]);
  }

  Widget _umsatzMonatChart(List<RechnungWithKunde> list) {
    final monate = List<double>.filled(12, 0);
    for (final r in list) {
      final d = r.rechnung.rechnungsdatum;
      if (d == null || d.year != _jahr) continue;
      monate[d.month - 1] += r.rechnung.netto;
    }
    final maxY = (monate.reduce((a, b) => a > b ? a : b)) * 1.2;
    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: maxY == 0 ? 100 : maxY,
          barTouchData: ChartStyle.barTouchData(
            format: (v) => NumberFormat.currency(
                    locale: 'de_DE', symbol: '€', decimalDigits: 0)
                .format(v),
          ),
          barGroups: [
            for (var i = 0; i < 12; i++)
              BarChartGroupData(x: i, barRods: [
                ChartStyle.bar(monate[i], width: 14),
              ]),
          ],
          borderData: FlBorderData(show: false),
          gridData: ChartStyle.gridData(),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (v, _) => Text(
                  NumberFormat.compactCurrency(
                          locale: 'de_DE', symbol: '€', decimalDigits: 0)
                      .format(v),
                  style: const TextStyle(fontSize: 9),
                ),
              ),
            ),
            bottomTitles: ChartStyle.bottomLabels(const [
              'J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'
            ]),
            rightTitles: ChartStyle.emptyAxis(),
            topTitles: ChartStyle.emptyAxis(),
          ),
        ),
      ),
    );
  }

  Widget _sachgebietPie(List<AuftragWithKunde> list) {
    final jahr = list.where((a) =>
        (a.auftrag.auftragAm ?? a.auftrag.eingangAm)?.year == _jahr);
    final m = <String, int>{};
    for (final a in jahr) {
      final k = (a.auftrag.sachgebiet ?? '').trim();
      if (k.isEmpty) continue;
      m[k] = (m[k] ?? 0) + 1;
    }
    final sorted = m.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(6).toList();
    if (top.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text('Keine Daten', style: TextStyle(fontSize: 12))),
      );
    }
    const palette = [
      Color(0xFFEA580C),
      Color(0xFF1D4ED8),
      Color(0xFF166534),
      Color(0xFFB45309),
      Color(0xFF991B1B),
      Color(0xFF4338CA),
    ];
    final total = top.fold<int>(0, (s, e) => s + e.value);
    return SizedBox(
      height: 200,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 28,
                sections: [
                  for (var i = 0; i < top.length; i++)
                    PieChartSectionData(
                      value: top[i].value.toDouble(),
                      color: palette[i % palette.length],
                      title:
                          '${(top[i].value / total * 100).toStringAsFixed(0)}%',
                      radius: 55,
                      titleStyle: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < top.length; i++)
                  Row(
                    children: [
                      Container(
                          width: 10,
                          height: 10,
                          color: palette[i % palette.length]),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text('${top[i].key} (${top[i].value})',
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _block(BuildContext context, String title, Widget body) =>
      Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context).textTheme.titleMedium),
              const Divider(),
              body,
            ],
          ),
        ),
      );

  Widget _kv(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(k, style: const TextStyle(fontSize: 13))),
            Text(v,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ],
        ),
      );
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.jahr,
    required this.auftraege,
    required this.rechnungen,
    required this.fortb,
  });
  final int jahr;
  final List<AuftragWithKunde> auftraege;
  final List<RechnungWithKunde> rechnungen;
  final Map<int, double> fortb;

  static final _money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

  @override
  Widget build(BuildContext context) {
    final auftraegeJahr = auftraege
        .where((a) =>
            (a.auftrag.auftragAm ?? a.auftrag.eingangAm)?.year == jahr)
        .toList();
    final abgeschlossen = auftraegeJahr
        .where((a) =>
            a.auftrag.status == 'abgeschlossen' ||
            a.auftrag.status == 'abgerechnet')
        .length;
    double umsatz = 0;
    for (final r in rechnungen) {
      if (r.rechnung.rechnungsdatum?.year != jahr) continue;
      if (r.rechnung.status == 'storniert') continue;
      umsatz += r.rechnung.netto;
    }
    return Row(
      children: [
        Expanded(
          child: KpiCard(
            icon: Icons.folder_open_outlined,
            label: 'Aufträge gesamt',
            value: '${auftraegeJahr.length}',
            accent: BadgeColors.blueFg,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: KpiCard(
            icon: Icons.check_circle_outline,
            label: 'davon abgeschlossen',
            value: '$abgeschlossen',
            accent: BadgeColors.greenFg,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: KpiCard(
            icon: Icons.euro,
            label: 'Umsatz netto',
            value: _money.format(umsatz),
            accent: BadgeColors.amberFg,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: KpiCard(
            icon: Icons.school_outlined,
            label: 'Fortbildungsstunden',
            value: '${(fortb[jahr] ?? 0).toStringAsFixed(1)} h',
            accent: BadgeColors.indigoFg,
          ),
        ),
      ],
    );
  }
}
