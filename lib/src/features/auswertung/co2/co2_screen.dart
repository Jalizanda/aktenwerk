import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../shared/widgets/module_scaffold.dart';

/// Klimabilanz-Tracker: rechnet Fahrtkilometer aus Auslagen und
/// Druckkopien aus JVEG-Auslagen in CO₂-Äquivalente um.
///
/// Faktoren (DEFRA / UBA 2024, gerundet):
/// - PKW-Diesel:   0,160 kg CO₂e / km
/// - Druck A4 SW:  0,0045 kg CO₂e / Seite
/// - Druck A4 col: 0,010  kg CO₂e / Seite
class Co2Screen extends ConsumerWidget {
  const Co2Screen({super.key});

  static const kgCo2ProKm = 0.160;
  static const kgCo2ProKopieSw = 0.0045;
  static const kgCo2ProKopieFarbe = 0.010;

  static final _nf = NumberFormat.decimalPattern('de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.eco_outlined,
          title: 'CO₂-Tracker',
          subtitle:
              'Klimabilanz aus Fahrt- und Druck-Auslagen. Faktoren: 160 g/km PKW, 4,5 g/Kopie SW, 10 g/Kopie Farbe.',
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<AuslagenData>>(
            future: db.select(db.auslagen).get(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final list = snap.data!;
              final kmGesamt = list
                  .where((a) => a.art == 'fahrt' || a.einheit == 'km')
                  .fold<double>(0, (acc, a) => acc + a.menge);
              final kopienSw = list
                  .where((a) =>
                      a.art == 'kopie_sw' || a.art == 'kopie' ||
                      a.einheit == 'Kopie SW')
                  .fold<double>(0, (acc, a) => acc + a.menge);
              final kopienFarbe = list
                  .where((a) =>
                      a.art == 'kopie_farbe' || a.einheit == 'Kopie Farbe')
                  .fold<double>(0, (acc, a) => acc + a.menge);

              final co2Fahrt = kmGesamt * kgCo2ProKm;
              final co2KopienSw = kopienSw * kgCo2ProKopieSw;
              final co2KopienFarbe = kopienFarbe * kgCo2ProKopieFarbe;
              final co2Gesamt = co2Fahrt + co2KopienSw + co2KopienFarbe;

              // Jahresaufsplittung für kompakte Auswertung.
              final byYear = <int, double>{};
              for (final a in list) {
                double c = 0;
                if (a.art == 'fahrt' || a.einheit == 'km') {
                  c += a.menge * kgCo2ProKm;
                } else if (a.art == 'kopie_sw' || a.art == 'kopie') {
                  c += a.menge * kgCo2ProKopieSw;
                } else if (a.art == 'kopie_farbe') {
                  c += a.menge * kgCo2ProKopieFarbe;
                }
                if (c > 0) {
                  byYear[a.datum.year] =
                      (byYear[a.datum.year] ?? 0) + c;
                }
              }

              if (list.isEmpty ||
                  (co2Gesamt < 0.01 &&
                      co2Fahrt < 0.01 &&
                      co2KopienSw < 0.01 &&
                      co2KopienFarbe < 0.01)) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.eco_outlined,
                            size: 64, color: AppTheme.slate300),
                        const SizedBox(height: 12),
                        const Text(
                          'Noch keine CO₂-relevanten Auslagen erfasst.',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Trage Fahrten (Einheit „km") und Kopien (Einheiten „Kopie SW" / "Kopie Farbe") unter Auslagen ein.',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.slate500),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _Kpi(
                        label: 'Gesamt',
                        wert: '${_nf.format(co2Gesamt.round())} kg CO₂e',
                        farbe: AppTheme.accent600,
                      ),
                      _Kpi(
                        label: 'aus Fahrten',
                        wert:
                            '${_nf.format(co2Fahrt.round())} kg · ${_nf.format(kmGesamt.round())} km',
                        farbe: AppTheme.slate700,
                      ),
                      _Kpi(
                        label: 'aus Kopien SW',
                        wert:
                            '${co2KopienSw.toStringAsFixed(1)} kg · ${_nf.format(kopienSw.round())} Seiten',
                        farbe: AppTheme.slate700,
                      ),
                      _Kpi(
                        label: 'aus Kopien Farbe',
                        wert:
                            '${co2KopienFarbe.toStringAsFixed(1)} kg · ${_nf.format(kopienFarbe.round())} Seiten',
                        farbe: AppTheme.slate700,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('nach Jahr',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.slate200),
                    ),
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Jahr')),
                        DataColumn(label: Text('CO₂e (kg)')),
                      ],
                      rows: [
                        for (final y in (byYear.keys.toList()..sort()))
                          DataRow(cells: [
                            DataCell(Text('$y')),
                            DataCell(Text(
                                _nf.format(byYear[y]!.round()))),
                          ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.slate50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.slate200),
                    ),
                    child: const Text(
                      'Hinweis: Die Werte basieren auf den Auslagen-Einträgen (Fahrt/Kopien). Jeder Eintrag '
                      'fließt so wie er gebucht ist ein — wenn Mengen oder Einheiten nicht zu Fahrten/Kopien '
                      'passen, werden sie ignoriert.',
                      style: TextStyle(fontSize: 12),
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
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.wert, required this.farbe});
  final String label;
  final String wert;
  final Color farbe;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      width: 260,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.slate200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: AppTheme.slate500)),
          const SizedBox(height: 4),
          Text(wert,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: farbe)),
        ],
      ),
    );
  }
}
