import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Uint8List;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/database/app_database.dart';
import '../../../shared/widgets/form_widgets.dart';

import 'messwerte_repository.dart';

class MesswerteTab extends ConsumerWidget {
  const MesswerteTab({super.key, required this.auftragId});
  final int auftragId;

  static final _fmt = DateFormat('dd.MM. HH:mm', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(messwerteByAkteProvider(auftragId));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Messwert-Logger',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              OutlinedButton.icon(
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: const Text('CSV-Export'),
                onPressed: () => _exportCsv(
                    context, async.valueOrNull ?? const []),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _open(context, ref),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Messwert'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyListState(
                    icon: Icons.show_chart,
                    title: 'Noch keine Messwerte',
                    hint:
                        'Erfasse Temperatur-, Feuchte-, Schall- oder BlowerDoor-Messungen mit Zeitstempel.',
                  );
                }
                final groesseGrouped =
                    <String, List<MesswerteData>>{};
                for (final m in items) {
                  groesseGrouped
                      .putIfAbsent(m.groesse, () => [])
                      .add(m);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 220,
                      child: _Chart(gruppen: groesseGrouped),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Zeit')),
                            DataColumn(label: Text('Größe')),
                            DataColumn(label: Text('Wert')),
                            DataColumn(label: Text('Einheit')),
                            DataColumn(label: Text('Serie')),
                            DataColumn(label: Text('Ort')),
                            DataColumn(label: Text('')),
                          ],
                          rows: [
                            for (final m in items.reversed)
                              DataRow(cells: [
                                DataCell(Text(_fmt.format(m.zeitpunkt))),
                                DataCell(Text(m.groesse)),
                                DataCell(Text(m.wert.toStringAsFixed(2))),
                                DataCell(Text(m.einheit ?? '')),
                                DataCell(Text(m.serie ?? '')),
                                DataCell(Text(m.ort ?? '')),
                                DataCell(IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18),
                                  onPressed: () => ref
                                      .read(messwerteRepositoryProvider)
                                      .delete(m.id),
                                )),
                              ]),
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
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => _MesswertEditor(auftragId: auftragId),
    );
  }

  Future<void> _exportCsv(
      BuildContext context, List<MesswerteData> list) async {
    final rows = <List<String>>[
      ['Zeit', 'Groesse', 'Wert', 'Einheit', 'Serie', 'Ort', 'Bemerkung'],
      for (final m in list)
        [
          m.zeitpunkt.toIso8601String(),
          m.groesse,
          m.wert.toString(),
          m.einheit ?? '',
          m.serie ?? '',
          m.ort ?? '',
          m.bemerkung ?? '',
        ],
    ];
    final csv = rows
        .map((r) =>
            r.map((c) => '"${c.replaceAll('"', '""')}"').join(';'))
        .join('\r\n');
    await Share.shareXFiles(
      [
        XFile.fromData(
          Uint8List.fromList(utf8.encode(csv)),
          name:
              'messwerte_akte_$auftragId.csv',
          mimeType: 'text/csv',
        ),
      ],
      subject: 'Messwerte-Export',
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({required this.gruppen});
  final Map<String, List<MesswerteData>> gruppen;

  static const _farben = [
    Color(0xFFF97316),
    Color(0xFF2563EB),
    Color(0xFF16A34A),
    Color(0xFFDB2777),
    Color(0xFF7C3AED),
  ];

  @override
  Widget build(BuildContext context) {
    final series = <LineChartBarData>[];
    int farbeI = 0;
    DateTime? tmin, tmax;
    double? ymin, ymax;
    for (final entry in gruppen.entries) {
      final list = entry.value;
      for (final m in list) {
        if (tmin == null || m.zeitpunkt.isBefore(tmin)) tmin = m.zeitpunkt;
        if (tmax == null || m.zeitpunkt.isAfter(tmax)) tmax = m.zeitpunkt;
        if (ymin == null || m.wert < ymin) ymin = m.wert;
        if (ymax == null || m.wert > ymax) ymax = m.wert;
      }
      final farbe = _farben[farbeI % _farben.length];
      farbeI++;
      series.add(LineChartBarData(
        spots: [
          for (final m in list)
            FlSpot(m.zeitpunkt.millisecondsSinceEpoch.toDouble(), m.wert),
        ],
        isCurved: false,
        color: farbe,
        barWidth: 2,
        dotData: const FlDotData(show: true),
      ));
    }
    if (series.isEmpty || tmin == null || tmax == null) {
      return const SizedBox.shrink();
    }

    return LineChart(
      LineChartData(
        minX: tmin.millisecondsSinceEpoch.toDouble(),
        maxX: tmax.millisecondsSinceEpoch.toDouble(),
        minY: ymin,
        maxY: ymax,
        lineBarsData: series,
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
          rightTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, _) {
                final d =
                    DateTime.fromMillisecondsSinceEpoch(v.toInt());
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(DateFormat('dd.MM.').format(d),
                      style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}

class _MesswertEditor extends ConsumerStatefulWidget {
  const _MesswertEditor({required this.auftragId});
  final int auftragId;
  @override
  ConsumerState<_MesswertEditor> createState() => _MesswertEditorState();
}

class _MesswertEditorState extends ConsumerState<_MesswertEditor> {
  final _groesse = TextEditingController(text: 'Temperatur');
  final _einheit = TextEditingController(text: '°C');
  final _wert = TextEditingController();
  final _serie = TextEditingController();
  final _ort = TextEditingController();
  final _bemerkung = TextEditingController();
  DateTime _zeitpunkt = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _groesse.dispose();
    _einheit.dispose();
    _wert.dispose();
    _serie.dispose();
    _ort.dispose();
    _bemerkung.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final val = double.tryParse(_wert.text.replaceAll(',', '.').trim());
    if (val == null || _groesse.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(messwerteRepositoryProvider).insert(
            MesswerteCompanion.insert(
              auftragId: widget.auftragId,
              zeitpunkt: Value(_zeitpunkt),
              groesse: _groesse.text.trim(),
              einheit: Value(_einheit.text.trim()),
              wert: val,
              serie: Value(_serie.text.trim().isEmpty
                  ? null
                  : _serie.text.trim()),
              ort: Value(_ort.text.trim().isEmpty ? null : _ort.text.trim()),
              bemerkung: Value(_bemerkung.text.trim().isEmpty
                  ? null
                  : _bemerkung.text.trim()),
            ),
          );
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StandardFormDialog(
      title: 'Neuer Messwert',
      icon: Icons.show_chart,
      maxWidth: 640,
      maxHeight: 620,
      saving: _saving,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(),
      onSave: _save,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row3(
              a: LabeledField(
                'Zeitpunkt',
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _zeitpunkt,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (d == null || !context.mounted) return;
                    final t = await showTimePicker(
                      context: context,
                      initialTime:
                          TimeOfDay.fromDateTime(_zeitpunkt),
                    );
                    if (!mounted) return;
                    setState(() {
                      _zeitpunkt = DateTime(
                        d.year,
                        d.month,
                        d.day,
                        t?.hour ?? _zeitpunkt.hour,
                        t?.minute ?? _zeitpunkt.minute,
                      );
                    });
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      suffixIcon: Icon(Icons.calendar_month_outlined),
                    ),
                    child: Text(DateFormat('dd.MM.yyyy HH:mm', 'de')
                        .format(_zeitpunkt)),
                  ),
                ),
              ),
              b: LabeledField(
                  'Größe (z.B. Temperatur)',
                  TextFormField(controller: _groesse)),
              c: LabeledField('Einheit',
                  TextFormField(controller: _einheit)),
            ),
            const SizedBox(height: 12),
            Row3(
              a: LabeledField('Wert',
                  TextFormField(controller: _wert, autofocus: true)),
              b: LabeledField('Serie / Kanal',
                  TextFormField(controller: _serie)),
              c: LabeledField(
                  'Ort (z.B. Raum OG)',
                  TextFormField(controller: _ort)),
            ),
            const SizedBox(height: 12),
            LabeledField(
                'Bemerkung',
                TextFormField(
                    controller: _bemerkung, minLines: 2, maxLines: 3)),
          ],
        ),
      ),
    );
  }
}
