import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';

/// JVEG-Rechner (Stand 2026: M-Stufen, Fahrtkosten-Pauschalen, Kopien).
/// Werte können per Eingabe angepasst werden.
class JvegRechnerScreen extends ConsumerStatefulWidget {
  const JvegRechnerScreen({super.key});
  @override
  ConsumerState<JvegRechnerScreen> createState() =>
      _JvegRechnerScreenState();
}

class _JvegRechnerScreenState extends ConsumerState<JvegRechnerScreen> {
  // Honorargruppen JVEG §9 (Werte 2026, können aus Einstellungen überschrieben werden)
  static const Map<int, double> _honorarJeStunde = {
    1: 80,
    2: 85,
    3: 90,
    4: 100,
    5: 105,
    6: 110,
    7: 115,
    8: 120,
    9: 130,
    10: 140,
    11: 150,
    12: 165,
  };

  int _stufe = 5;
  final _stunden = TextEditingController(text: '1,0');
  final _wartezeitStd = TextEditingController(text: '0,0');
  final _km = TextEditingController(text: '0');
  final _kopien = TextEditingController(text: '0');
  final _kopienFarbe = TextEditingController(text: '0');
  double _satzKm = 0.42;

  @override
  void dispose() {
    for (final c in [_stunden, _wartezeitStd, _km, _kopien, _kopienFarbe]) {
      c.dispose();
    }
    super.dispose();
  }

  double _parse(TextEditingController c, [double fallback = 0]) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? fallback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat.currency(locale: 'de', symbol: '€');

    final satz = _honorarJeStunde[_stufe] ?? 0;
    final stunden = _parse(_stunden);
    final wartezeit = _parse(_wartezeitStd);
    final km = _parse(_km);
    final kopienSW = _parse(_kopien).toInt();
    final kopienFarbe = _parse(_kopienFarbe).toInt();

    final honorar = satz * stunden;
    final wartezeitBetrag = satz * wartezeit;
    final fahrt = km * _satzKm;

    // Kopien: je 0,50 € für erste 50 (SW), danach 0,15 €; Farbe je +0,50 €
    final kopSwBetrag = kopienSW <= 50
        ? kopienSW * 0.50
        : 50 * 0.50 + (kopienSW - 50) * 0.15;
    final kopFarbeBetrag = kopienFarbe * 1.0;

    final summeNetto =
        honorar + wartezeitBetrag + fahrt + kopSwBetrag + kopFarbeBetrag;
    final ust = summeNetto * 0.19;
    final summeBrutto = summeNetto + ust;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ModuleHeader(
          icon: Icons.balance_outlined,
          title: 'JVEG-Rechner',
          subtitle: 'Honorar nach Justizvergütungs- und -entschädigungsgesetz',
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Honorar',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Row2(
                          left: LabeledField(
                            'Honorarstufe',
                            DropdownButtonFormField<int>(
                              initialValue: _stufe,
                              isDense: true,
                              items: [
                                for (final s
                                    in _honorarJeStunde.keys.toList()
                                      ..sort())
                                  DropdownMenuItem(
                                    value: s,
                                    child: Text(
                                        'M$s · ${money.format(_honorarJeStunde[s])}'),
                                  ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _stufe = v ?? 5),
                            ),
                          ),
                          right: LabeledField(
                            'Tatsächliche Arbeitsstunden',
                            TextFormField(
                              controller: _stunden,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text('Wartezeit / Fahrt',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Row2(
                          left: LabeledField(
                            'Wartezeit (Std.)',
                            TextFormField(
                              controller: _wartezeitStd,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          right: LabeledField(
                            'Gefahrene Kilometer',
                            TextFormField(
                              controller: _km,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          const Text('Kilometersatz '),
                          DropdownButton<double>(
                            value: _satzKm,
                            items: const [
                              DropdownMenuItem(
                                  value: 0.42, child: Text('0,42 €/km (JVEG)')),
                              DropdownMenuItem(
                                  value: 0.30, child: Text('0,30 €/km')),
                              DropdownMenuItem(
                                  value: 0.50, child: Text('0,50 €/km')),
                            ],
                            onChanged: (v) =>
                                setState(() => _satzKm = v ?? 0.42),
                          ),
                        ]),
                        const SizedBox(height: 24),
                        Text('Kopien',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Row2(
                          left: LabeledField(
                            'Kopien S/W',
                            TextFormField(
                              controller: _kopien,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          right: LabeledField(
                            'Kopien Farbe',
                            TextFormField(
                              controller: _kopienFarbe,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 320,
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                            color: theme.colorScheme.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Berechnung',
                                style: theme.textTheme.titleMedium),
                            const Divider(),
                            _row('Honorar', money.format(honorar)),
                            _row('Wartezeit',
                                money.format(wartezeitBetrag)),
                            _row(
                                'Fahrtkosten (${km.toStringAsFixed(0)} km × ${money.format(_satzKm)})',
                                money.format(fahrt)),
                            _row('Kopien S/W', money.format(kopSwBetrag)),
                            _row('Kopien Farbe',
                                money.format(kopFarbeBetrag)),
                            const Divider(),
                            _row('Netto', money.format(summeNetto),
                                bold: true),
                            _row('USt 19 %', money.format(ust)),
                            _row('Brutto',
                                money.format(summeBrutto),
                                bold: true),
                          ],
                        ),
                      ),
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

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
}
