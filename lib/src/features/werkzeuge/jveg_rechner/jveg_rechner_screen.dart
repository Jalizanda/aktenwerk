import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';

/// JVEG-Rechner. Deckt § 9 (Honorar), § 5 (Fahrtkosten) und § 7 (Auslagen —
/// Schreibauslagen, Lichtbilder, Kopien) ab. Werte sind voreingestellt mit
/// den aktuellen JVEG-Sätzen, lassen sich aber im Dialog anpassen.
class JvegRechnerScreen extends ConsumerStatefulWidget {
  const JvegRechnerScreen({super.key});
  @override
  ConsumerState<JvegRechnerScreen> createState() =>
      _JvegRechnerScreenState();
}

class _JvegRechnerScreenState extends ConsumerState<JvegRechnerScreen> {
  // Honorargruppen JVEG § 9.
  // M1–M3 sind die üblichen Gruppen für Bau-Gutachten; darüber hinaus bis M12
  // als Vorgriff auf künftige Sachgebiete.
  static const Map<int, double> _honorarJeStunde = {
    1: 90, // M1
    2: 110, // M2
    3: 130, // M3
    4: 100,
    5: 105,
    6: 115,
    7: 120,
    8: 125,
    9: 135,
    10: 140,
    11: 150,
    12: 165,
  };

  int _stufe = 2; // M2 (110 €) als Default
  final _stunden = TextEditingController(text: '1,0');
  final _wartezeitStd = TextEditingController(text: '0,0');
  final _km = TextEditingController(text: '0');
  // § 7 Schreibauslagen: Anschläge in 1000er-Blöcken
  final _schreibAnschlaege = TextEditingController(text: '0');
  final _ausfertigungen = TextEditingController(text: '1');
  // § 7 Lichtbilder: Gesamtzahl
  final _lichtbilder = TextEditingController(text: '0');
  // § 7 Kopien
  final _kopien = TextEditingController(text: '0');
  final _kopienFarbe = TextEditingController(text: '0');
  double _satzKm = 0.42;

  static final _money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

  @override
  void dispose() {
    for (final c in [
      _stunden,
      _wartezeitStd,
      _km,
      _schreibAnschlaege,
      _ausfertigungen,
      _lichtbilder,
      _kopien,
      _kopienFarbe,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _parse(TextEditingController c, [double fallback = 0]) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? fallback;
  int _parseInt(TextEditingController c, [int fallback = 0]) =>
      int.tryParse(c.text.trim()) ?? fallback;

  _Berechnung _berechne() {
    final satz = _honorarJeStunde[_stufe] ?? 0;
    final stunden = _parse(_stunden);
    final wartezeit = _parse(_wartezeitStd);
    final km = _parse(_km);
    final anschlaege = _parseInt(_schreibAnschlaege);
    final ausfertigungen = _parseInt(_ausfertigungen, 1).clamp(1, 99);
    final lichtbilder = _parseInt(_lichtbilder);
    final kopSW = _parseInt(_kopien);
    final kopFarbe = _parseInt(_kopienFarbe);

    final honorar = satz * stunden;
    final wartezeitBetrag = satz * wartezeit;
    final fahrt = km * _satzKm;

    // § 7 Abs. 1 JVEG: Schreibauslagen
    //  - Erstexemplar: 1,80 € pro 1000 Anschläge (oder angefangener 1000er)
    //  - Je weitere Ausfertigung: 0,50 € pro 1000 Anschläge
    final blocks = (anschlaege / 1000).ceil();
    final schreibErst = blocks * 1.80;
    final schreibWeitere = (ausfertigungen - 1) * blocks * 0.50;
    final schreibauslagen = schreibErst + schreibWeitere;

    // § 7 Abs. 2 JVEG: Lichtbilder
    //  - 1. Stück: 2,00 €; weitere: 1,00 €
    final lichtbilderBetrag = lichtbilder <= 0
        ? 0.0
        : 2.00 + (lichtbilder - 1) * 1.00;

    // § 7 Abs. 2 JVEG: Kopien/Ausdrucke
    //  - S/W: 0,50 € je Seite (1–50), dann 0,15 €
    //  - Farbe: 1,00 € je Seite (1–50), dann 0,30 €
    final kopSWBetrag = kopSW <= 50
        ? kopSW * 0.50
        : 50 * 0.50 + (kopSW - 50) * 0.15;
    final kopFarbeBetrag = kopFarbe <= 50
        ? kopFarbe * 1.00
        : 50 * 1.00 + (kopFarbe - 50) * 0.30;

    final netto = honorar +
        wartezeitBetrag +
        fahrt +
        schreibauslagen +
        lichtbilderBetrag +
        kopSWBetrag +
        kopFarbeBetrag;
    final ust = netto * 0.19;
    final brutto = netto + ust;

    return _Berechnung(
      satz: satz,
      stunden: stunden,
      wartezeit: wartezeit,
      km: km,
      kmSatz: _satzKm,
      honorar: honorar,
      wartezeitBetrag: wartezeitBetrag,
      fahrt: fahrt,
      schreibauslagen: schreibauslagen,
      schreibBlocks: blocks,
      ausfertigungen: ausfertigungen,
      lichtbilder: lichtbilder,
      lichtbilderBetrag: lichtbilderBetrag,
      kopienSW: kopSW,
      kopSWBetrag: kopSWBetrag,
      kopienFarbe: kopFarbe,
      kopFarbeBetrag: kopFarbeBetrag,
      netto: netto,
      ust: ust,
      brutto: brutto,
    );
  }

  Future<void> _toClipboard(_Berechnung b) async {
    final buf = StringBuffer();
    buf.writeln('JVEG-Aufstellung');
    buf.writeln('—' * 40);
    buf.writeln('§ 9 Honorar (M$_stufe · ${_money.format(b.satz)}/h)');
    buf.writeln(
        '  ${b.stunden.toStringAsFixed(2)} h × ${_money.format(b.satz)} = ${_money.format(b.honorar)}');
    if (b.wartezeit > 0) {
      buf.writeln(
          '  Wartezeit ${b.wartezeit.toStringAsFixed(2)} h = ${_money.format(b.wartezeitBetrag)}');
    }
    if (b.km > 0) {
      buf.writeln(
          '§ 5 Fahrtkosten: ${b.km.toStringAsFixed(0)} km × ${_money.format(b.kmSatz)} = ${_money.format(b.fahrt)}');
    }
    if (b.schreibauslagen > 0) {
      buf.writeln(
          '§ 7 Schreibauslagen (${b.schreibBlocks}× 1000 Anschläge, ${b.ausfertigungen} Ausf.): ${_money.format(b.schreibauslagen)}');
    }
    if (b.lichtbilderBetrag > 0) {
      buf.writeln(
          '§ 7 Lichtbilder (${b.lichtbilder}): ${_money.format(b.lichtbilderBetrag)}');
    }
    if (b.kopSWBetrag > 0) {
      buf.writeln(
          '§ 7 Kopien s/w (${b.kopienSW}): ${_money.format(b.kopSWBetrag)}');
    }
    if (b.kopFarbeBetrag > 0) {
      buf.writeln(
          '§ 7 Kopien farbig (${b.kopienFarbe}): ${_money.format(b.kopFarbeBetrag)}');
    }
    buf.writeln('—' * 40);
    buf.writeln('Netto:  ${_money.format(b.netto)}');
    buf.writeln('USt 19 %: ${_money.format(b.ust)}');
    buf.writeln('Brutto: ${_money.format(b.brutto)}');
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aufstellung in Zwischenablage kopiert')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = _berechne();

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
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('§ 9 Honorar', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Row2(
                          left: LabeledField(
                            'Honorarstufe',
                            DropdownButtonFormField<int>(
                              initialValue: _stufe,
                              isDense: true,
                              items: [
                                for (final s in _honorarJeStunde.keys.toList()
                                  ..sort())
                                  DropdownMenuItem(
                                    value: s,
                                    child: Text(
                                        'M$s · ${_money.format(_honorarJeStunde[s])}'),
                                  ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _stufe = v ?? 2),
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
                        Text('§ 5 Fahrt & Wartezeit',
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
                                  value: 0.42,
                                  child: Text('0,42 €/km (JVEG)')),
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
                        Text('§ 7 Schreibauslagen',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Row2(
                          left: LabeledField(
                            'Anschläge (ca.)',
                            TextFormField(
                              controller: _schreibAnschlaege,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          right: LabeledField(
                            'Ausfertigungen',
                            TextFormField(
                              controller: _ausfertigungen,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '1,80 € je 1000 Anschläge (Erstausfertigung) · '
                          '0,50 € je 1000 Anschläge (weitere)',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 24),
                        Text('§ 7 Lichtbilder & Kopien',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Row3(
                          a: LabeledField(
                            'Lichtbilder',
                            TextFormField(
                              controller: _lichtbilder,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          b: LabeledField(
                            'Kopien s/w',
                            TextFormField(
                              controller: _kopien,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          c: LabeledField(
                            'Kopien farbig',
                            TextFormField(
                              controller: _kopienFarbe,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Lichtbilder: 2 € (1.) / 1 € (weitere) · '
                          'Kopien s/w: 0,50 € (1–50) / 0,15 € · '
                          'farbig: 1 € / 0,30 €',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 340,
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
                            Row(
                              children: [
                                Expanded(
                                  child: Text('Berechnung',
                                      style: theme.textTheme.titleMedium),
                                ),
                                IconButton(
                                  tooltip: 'Aufstellung kopieren',
                                  icon: const Icon(Icons.copy, size: 18),
                                  onPressed: () => _toClipboard(b),
                                ),
                              ],
                            ),
                            const Divider(),
                            _row('§ 9 Honorar', _money.format(b.honorar)),
                            if (b.wartezeitBetrag > 0)
                              _row('Wartezeit',
                                  _money.format(b.wartezeitBetrag)),
                            if (b.fahrt > 0)
                              _row(
                                  '§ 5 Fahrt (${b.km.toStringAsFixed(0)} km)',
                                  _money.format(b.fahrt)),
                            if (b.schreibauslagen > 0)
                              _row(
                                  '§ 7 Schreibauslagen',
                                  _money.format(b.schreibauslagen)),
                            if (b.lichtbilderBetrag > 0)
                              _row('§ 7 Lichtbilder (${b.lichtbilder})',
                                  _money.format(b.lichtbilderBetrag)),
                            if (b.kopSWBetrag > 0)
                              _row('§ 7 Kopien s/w (${b.kopienSW})',
                                  _money.format(b.kopSWBetrag)),
                            if (b.kopFarbeBetrag > 0)
                              _row('§ 7 Kopien farbig (${b.kopienFarbe})',
                                  _money.format(b.kopFarbeBetrag)),
                            const Divider(),
                            _row('Netto', _money.format(b.netto), bold: true),
                            _row('USt 19 %', _money.format(b.ust)),
                            _row('Brutto', _money.format(b.brutto),
                                bold: true, large: true),
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

  Widget _row(String label, String value,
          {bool bold = false, bool large = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: TextStyle(fontSize: large ? 14 : 12.5))),
            Text(
              value,
              style: TextStyle(
                fontSize: large ? 15 : 12.5,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
}

class _Berechnung {
  final double satz;
  final double stunden;
  final double wartezeit;
  final double km;
  final double kmSatz;
  final double honorar;
  final double wartezeitBetrag;
  final double fahrt;
  final double schreibauslagen;
  final int schreibBlocks;
  final int ausfertigungen;
  final int lichtbilder;
  final double lichtbilderBetrag;
  final int kopienSW;
  final double kopSWBetrag;
  final int kopienFarbe;
  final double kopFarbeBetrag;
  final double netto;
  final double ust;
  final double brutto;
  const _Berechnung({
    required this.satz,
    required this.stunden,
    required this.wartezeit,
    required this.km,
    required this.kmSatz,
    required this.honorar,
    required this.wartezeitBetrag,
    required this.fahrt,
    required this.schreibauslagen,
    required this.schreibBlocks,
    required this.ausfertigungen,
    required this.lichtbilder,
    required this.lichtbilderBetrag,
    required this.kopienSW,
    required this.kopSWBetrag,
    required this.kopienFarbe,
    required this.kopFarbeBetrag,
    required this.netto,
    required this.ust,
    required this.brutto,
  });
}
