import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../kunden/kunden_picker.dart';
import '../kunden/kunden_repository.dart';
import 'lv_repository.dart';

/// Dialog für die Bietergegenüberstellung. Zeigt:
/// - Liste vorhandener Bieter (mit Klon-Datum, Status, Gesamtsumme)
/// - Button „Neue Bieter-Antwort anlegen" → fragt Bietername, klont LV
/// - Button „Vergleichs-Tabelle öffnen" → zeigt Positionen × Bieter-Matrix
class LvBieterDialog extends ConsumerStatefulWidget {
  const LvBieterDialog({super.key, required this.kopf});
  final LvKopfData kopf;

  @override
  ConsumerState<LvBieterDialog> createState() => _LvBieterDialogState();
}

class _LvBieterDialogState extends ConsumerState<LvBieterDialog> {
  static final _money = NumberFormat.currency(
      locale: 'de_DE', symbol: '€', decimalDigits: 2);

  Future<void> _neuerBieter() async {
    final result = await showDialog<_BieterAnlegenResult>(
      context: context,
      builder: (_) => const _BieterAnlegenDialog(),
    );
    if (result == null) return;
    try {
      await ref.read(lvRepositoryProvider).kloneAlsBieter(
            basisLvId: widget.kopf.id,
            bieterName: result.name,
            kundeId: result.kundeId,
            datum: result.datum,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Bieter „${result.name}" angelegt.')));
      // Dialog bleibt offen — der neue Bieter erscheint per Stream-
      // Update in der Liste, der User kann ihn anklicken um Preise
      // einzutragen.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _zeigeVergleich() async {
    Navigator.pop(context);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _BieterVergleichTabelle(kopf: widget.kopf),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bieter = ref.watch(lvBieterProvider(widget.kopf.id));
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.compare_arrows),
                  const SizedBox(width: 10),
                  Text('Bietergegenüberstellung',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Du kannst dieses LV als Vorlage nehmen und für jede '
                'Bieter-Antwort einen Klon mit demselben Positionssatz '
                'anlegen — der Bieter trägt nur seine Preise ein. '
                'Die Vergleichstabelle stellt die Bieter dann nebeneinander.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: bieter.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Fehler: $e')),
                  data: (rows) {
                    if (rows.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Noch keine Bieter-Antworten zu diesem LV.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final b = rows[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.person_outline),
                          title: Text(b.bieterName ?? '(unbenannt)'),
                          subtitle: Text(
                              '${b.nummer ?? ""} · Status: ${b.status}'),
                          trailing: const Icon(Icons.open_in_new, size: 16),
                          onTap: () {
                            Navigator.pop(context);
                            GoRouter.of(context).go('/lv/${b.id}');
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Neue Bieter-Antwort'),
                    onPressed: _neuerBieter,
                  ),
                  bieter.maybeWhen(
                    data: (rows) => rows.isEmpty
                        ? const SizedBox()
                        : OutlinedButton.icon(
                            icon: const Icon(Icons.table_chart_outlined,
                                size: 16),
                            label: const Text('Vergleichs-Tabelle'),
                            onPressed: _zeigeVergleich,
                          ),
                    orElse: () => const SizedBox(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Volltext-Tabelle: Position × Bieter-Spalte mit Min/Max-Markierung.
class _BieterVergleichTabelle extends ConsumerWidget {
  const _BieterVergleichTabelle({required this.kopf});
  final LvKopfData kopf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bieterAsync = ref.watch(lvBieterProvider(kopf.id));
    final basisAsync = ref.watch(lvPositionenProvider(kopf.id));

    return bieterAsync.when(
      loading: () => const Dialog(
          child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()))),
      error: (e, _) => Dialog(child: Text('Fehler: $e')),
      data: (bieter) {
        if (bieter.isEmpty) {
          return Dialog(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Keine Bieter-Antworten vorhanden.'),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Schließen'),
                  ),
                ],
              ),
            ),
          );
        }
        return basisAsync.when(
          loading: () => const Dialog(
              child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()))),
          error: (e, _) => Dialog(child: Text('Fehler: $e')),
          data: (basisPos) => _buildTabelle(context, ref, basisPos, bieter),
        );
      },
    );
  }

  Widget _buildTabelle(BuildContext context, WidgetRef ref,
      List<LvPositionenData> basisPos, List<LvKopfData> bieter) {
    return Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            AppBar(
              title: Text('Bietervergleich · ${kopf.bezeichnung}'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: _vergleichDataTable(context, ref, basisPos, bieter),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vergleichDataTable(BuildContext context, WidgetRef ref,
      List<LvPositionenData> basisPos, List<LvKopfData> bieter) {
    final money = NumberFormat.currency(
        locale: 'de_DE', symbol: '€', decimalDigits: 2);

    // Bieter-Positionen über gaebUuid oder Kurztext mappen.
    return FutureBuilder<List<List<LvPositionenData>>>(
      future: Future.wait(
        bieter.map(
            (b) => ref.read(lvRepositoryProvider).getPositionen(b.id)),
      ),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final bieterPos = snap.data!;

        Map<int, LvPositionenData> bieterIndex(
            int bieterIdx, LvPositionenData basis) {
          final mapByUuid = <String, LvPositionenData>{};
          final mapByText = <String, LvPositionenData>{};
          for (final p in bieterPos[bieterIdx]) {
            if ((p.gaebUuid ?? '').isNotEmpty) {
              mapByUuid[p.gaebUuid!] = p;
            }
            mapByText[p.kurztext] = p;
          }
          final byUuid = (basis.gaebUuid ?? '').isNotEmpty
              ? mapByUuid[basis.gaebUuid!]
              : null;
          final m = <int, LvPositionenData>{};
          if (byUuid != null) m[bieterIdx] = byUuid;
          else {
            final byText = mapByText[basis.kurztext];
            if (byText != null) m[bieterIdx] = byText;
          }
          return m;
        }

        // Summen je Bieter (nur Mengen-Positionen, keine BP)
        final summen = <double>[];
        for (var i = 0; i < bieter.length; i++) {
          summen.add(bieterPos[i]
              .where((p) =>
                  p.art == 'normal' ||
                  p.art == 'eventual' ||
                  p.art == 'stundenlohn')
              .fold<double>(
                  0,
                  (s, p) =>
                      s + ((p.menge ?? 0) * (p.einzelpreis ?? 0))));
        }

        // Summe der Original-Kostenschätzung (Basis-LV) berechnen.
        final basisSumme = basisPos
            .where((p) =>
                p.art == 'normal' ||
                p.art == 'eventual' ||
                p.art == 'stundenlohn')
            .fold<double>(
                0,
                (s, p) =>
                    s + ((p.menge ?? 0) * (p.einzelpreis ?? 0)));

        // Min/Max-Berechnung über ALLE Spalten inkl. Original.
        final alleSummen = [basisSumme, ...summen];
        final minSumme = alleSummen.reduce((a, b) => a < b ? a : b);
        final maxSumme = alleSummen.reduce((a, b) => a > b ? a : b);

        return DataTable(
          headingRowColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surfaceContainerHighest),
          columns: [
            const DataColumn(label: Text('OZ')),
            const DataColumn(label: Text('Position')),
            const DataColumn(label: Text('Menge'), numeric: true),
            const DataColumn(
                label: Text('Kostenschätzung\n(Original)',
                    style: TextStyle(fontStyle: FontStyle.italic)),
                numeric: true),
            for (final b in bieter)
              DataColumn(
                  label: Text(b.bieterName ?? '?',
                      overflow: TextOverflow.ellipsis),
                  numeric: true),
          ],
          rows: [
            for (final p in basisPos)
              if (p.art != 'titel' && p.art != 'grundtext')
                DataRow(cells: [
                  DataCell(Text(p.oz ?? '')),
                  DataCell(SizedBox(
                      width: 240,
                      child: Text(p.kurztext,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis))),
                  DataCell(Text(
                      '${p.menge ?? 0} ${p.einheit ?? ""}',
                      textAlign: TextAlign.right)),
                  // Kostenschätzung (Original)
                  DataCell(Text(
                    money.format(
                        (p.menge ?? 0) * (p.einzelpreis ?? 0)),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.grey),
                  )),
                  for (var i = 0; i < bieter.length; i++)
                    DataCell(_zelle(p, bieterIndex(i, p)[i], money)),
                ]),
            // Summenzeile
            DataRow(
              color: WidgetStateProperty.all(
                  Theme.of(context).colorScheme.primaryContainer),
              cells: [
                const DataCell(Text('Σ',
                    style: TextStyle(fontWeight: FontWeight.w700))),
                const DataCell(Text('Gesamt netto',
                    style: TextStyle(fontWeight: FontWeight.w700))),
                const DataCell(Text('')),
                DataCell(Text(money.format(basisSumme),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                        color: basisSumme == minSumme
                            ? Colors.green[700]
                            : (basisSumme == maxSumme
                                ? Colors.red[700]
                                : null)))),
                for (var i = 0; i < bieter.length; i++)
                  DataCell(Text(
                      money.format(summen[i]),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: summen[i] == minSumme
                              ? Colors.green[700]
                              : (summen[i] == maxSumme
                                  ? Colors.red[700]
                                  : null)))),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _zelle(LvPositionenData basis, LvPositionenData? bieter,
      NumberFormat money) {
    if (bieter == null) {
      return const Text('—',
          textAlign: TextAlign.right,
          style: TextStyle(color: Colors.grey));
    }
    final ep = bieter.einzelpreis ?? 0;
    final gp = (basis.menge ?? 0) * ep;
    return Text(money.format(gp), textAlign: TextAlign.right);
  }
}

/// Daten aus dem Bieter-Anlegen-Dialog.
class _BieterAnlegenResult {
  final String name;
  final int? kundeId;
  final DateTime datum;
  const _BieterAnlegenResult({
    required this.name,
    required this.datum,
    this.kundeId,
  });
}

/// Anlege-Dialog: Bietername (oder Kontakt aus Kontakten ziehen),
/// Datum des Angebots, optional „Neuen Kontakt anlegen".
class _BieterAnlegenDialog extends ConsumerStatefulWidget {
  const _BieterAnlegenDialog();

  @override
  ConsumerState<_BieterAnlegenDialog> createState() =>
      _BieterAnlegenDialogState();
}

class _BieterAnlegenDialogState
    extends ConsumerState<_BieterAnlegenDialog> {
  final _name = TextEditingController();
  int? _kundeId;
  DateTime _datum = DateTime.now();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _kontaktVorschlagen() async {
    if (_kundeId == null) return;
    final kunde = await ref.read(kundenRepositoryProvider).byId(_kundeId!);
    if (kunde == null) return;
    final vorschlag = kundeAnzeigename(kunde);
    if (_name.text.trim().isEmpty) {
      _name.text = vorschlag;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_add_outlined),
                  const SizedBox(width: 10),
                  Text('Neue Bieter-Antwort',
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 12),
              KundenPickerField(
                kundeId: _kundeId,
                onChanged: (id) async {
                  setState(() => _kundeId = id);
                  await _kontaktVorschlagen();
                  if (mounted) setState(() {});
                },
                label:
                    'Kontakt (Handwerksbetrieb) — optional',
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Bietername',
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    hintText:
                        'Wird übernommen, wenn ein Kontakt gewählt ist — anpassbar',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 200,
                child: DateField(
                  label: 'Datum des Angebots',
                  value: _datum,
                  onChanged: (d) =>
                      setState(() => _datum = d ?? DateTime.now()),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Anlegen'),
                    onPressed: _name.text.trim().isEmpty &&
                            _kundeId == null
                        ? null
                        : () {
                            Navigator.pop(
                              context,
                              _BieterAnlegenResult(
                                name: _name.text.trim().isEmpty
                                    ? '(unbenannt)'
                                    : _name.text.trim(),
                                kundeId: _kundeId,
                                datum: _datum,
                              ),
                            );
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
