import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../features/akten/dokumente/dokumente_repository.dart';
import '../../../features/system/einstellungen/absender_service.dart';
import '../../../features/system/einstellungen/einstellungen_repository.dart';
import '../../../features/system/einstellungen/honorargruppe_service.dart';
import '../../../shared/pdf/kostenvorschuss_pdf.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../kunden/kunden_repository.dart';

/// Dialog für den Kostenvorschuss-Antrag (§ 17 JVEG). Zieht Akten- und
/// Stammdaten automatisch, lässt den Sachverständigen den geschätzten
/// Aufwand eintragen und erzeugt einen druckfertigen Antrag.
class KostenvorschussDialog extends ConsumerStatefulWidget {
  const KostenvorschussDialog({super.key, required this.auftrag, this.kunde});
  final AuftraegeData auftrag;
  final KundenData? kunde;

  @override
  ConsumerState<KostenvorschussDialog> createState() =>
      _KostenvorschussDialogState();
}

class _KostenvorschussDialogState
    extends ConsumerState<KostenvorschussDialog> {
  late final _stunden = TextEditingController(text: '12');
  late final _stundensatz = TextEditingController(text: '');
  late final _ust = TextEditingController(text: '19');
  late final _begruendung = TextEditingController();

  // Auslagen-Posten — vorab mit typischen JVEG-Schätzwerten gefüllt.
  late final _fahrtKm = TextEditingController(text: '0');
  late final _fahrtSatz = TextEditingController(text: '0,42');
  late final _schreibSeiten = TextEditingController(text: '0');
  late final _schreibSatz = TextEditingController(text: '1,80');
  late final _kopieAnzahl = TextEditingController(text: '0');
  late final _kopieSatz = TextEditingController(text: '0,50');
  late final _lichtbilder = TextEditingController(text: '0');
  late final _lichtbildSatzErstes = TextEditingController(text: '2,00');
  late final _lichtbildSatzWeitere = TextEditingController(text: '1,00');
  late final _porto = TextEditingController(text: '5,00');
  late final _sonstiges = TextEditingController(text: '0');
  late final _sonstigesBezeichnung =
      TextEditingController(text: 'Sonstige Auslagen');

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ladeStandardwerte();
  }

  Future<void> _ladeStandardwerte() async {
    final repo = ref.read(einstellungenRepositoryProvider);
    Future<String?> g(String key) async => repo.get(key);
    // Stundensatz aus Honorargruppe der Akte ziehen — fällt auf den
    // generischen Default-Satz zurück, wenn keine Gruppe gesetzt ist.
    final hgSatz =
        await stundensatzFuerHonorargruppe(repo, widget.auftrag.honorargruppe);
    final km = await g(SettingsKeys.jvegKmSatz);
    final schreib = await g(SettingsKeys.jvegSchreibsatz);
    final kopieSw = await g(SettingsKeys.jvegKopieSw);
    final lbErstes = await g(SettingsKeys.jvegLichtbildErstes);
    final lbWeitere = await g(SettingsKeys.jvegLichtbildWeitere);
    if (!mounted) return;
    setState(() {
      _stundensatz.text = hgSatz.toStringAsFixed(0);
      if (km != null) _fahrtSatz.text = km.replaceAll('.', ',');
      if (schreib != null) _schreibSatz.text = schreib.replaceAll('.', ',');
      if (kopieSw != null) _kopieSatz.text = kopieSw.replaceAll('.', ',');
      if (lbErstes != null) {
        _lichtbildSatzErstes.text = lbErstes.replaceAll('.', ',');
      }
      if (lbWeitere != null) {
        _lichtbildSatzWeitere.text = lbWeitere.replaceAll('.', ',');
      }
    });
  }

  @override
  void dispose() {
    for (final c in [
      _stunden,
      _stundensatz,
      _ust,
      _begruendung,
      _fahrtKm,
      _fahrtSatz,
      _schreibSeiten,
      _schreibSatz,
      _kopieAnzahl,
      _kopieSatz,
      _lichtbilder,
      _lichtbildSatzErstes,
      _lichtbildSatzWeitere,
      _porto,
      _sonstiges,
      _sonstigesBezeichnung,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _d(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.').trim()) ?? 0;

  /// Baut die Auslagen-Liste mit allen Positionen, die einen Betrag > 0 haben.
  List<KostenvorschussPosten> _auslagenListe() {
    final out = <KostenvorschussPosten>[];
    final fahrtKm = _d(_fahrtKm);
    if (fahrtKm > 0) {
      final betrag = fahrtKm * _d(_fahrtSatz);
      out.add(KostenvorschussPosten(
        'Fahrtkosten ${fahrtKm.toStringAsFixed(0)} km × ${_fahrtSatz.text} €/km',
        betrag,
      ));
    }
    final schreib = _d(_schreibSeiten);
    if (schreib > 0) {
      final betrag = (schreib / 1000.0) * _d(_schreibSatz);
      out.add(KostenvorschussPosten(
        'Schreibauslagen ${schreib.toStringAsFixed(0)} Anschläge à ${_schreibSatz.text} €/1000',
        betrag,
      ));
    }
    final kopien = _d(_kopieAnzahl);
    if (kopien > 0) {
      final betrag = kopien * _d(_kopieSatz);
      out.add(KostenvorschussPosten(
        'Kopien ${kopien.toStringAsFixed(0)} × ${_kopieSatz.text} €',
        betrag,
      ));
    }
    final lb = _d(_lichtbilder);
    if (lb > 0) {
      final ersterSatz = _d(_lichtbildSatzErstes);
      final weitereSatz = _d(_lichtbildSatzWeitere);
      final betrag =
          ersterSatz + (lb > 1 ? (lb - 1) * weitereSatz : 0);
      out.add(KostenvorschussPosten(
        'Lichtbilder ${lb.toStringAsFixed(0)} (erstes ${ersterSatz.toStringAsFixed(2)} €, weitere ${weitereSatz.toStringAsFixed(2)} €)',
        betrag,
      ));
    }
    final porto = _d(_porto);
    if (porto > 0) {
      out.add(KostenvorschussPosten('Porto / Versand', porto));
    }
    final sonst = _d(_sonstiges);
    if (sonst > 0) {
      out.add(KostenvorschussPosten(_sonstigesBezeichnung.text.trim(), sonst));
    }
    return out;
  }

  /// Erzeugt das PDF, legt es als Akten-Dokument ab (Tab „Dokumente") und
  /// vermerkt den Brutto-Betrag im Akten-Feld `kostenvorschuss`.
  Future<void> _druckenUndArchivieren() async {
    setState(() => _saving = true);
    try {
      final daten = await _baueDaten();
      final bytes = await buildKostenvorschussPdf(daten);
      // Direkt in die Akten-Dokumente speichern.
      final dateiname =
          'Kostenvorschuss_${(widget.auftrag.aktenzeichen ?? "").replaceAll(RegExp(r"[^A-Za-z0-9-]"), "_")}.pdf';
      await ref.read(dokumenteRepositoryProvider).upsert(
            DokumenteCompanion.insert(
              titel: Value(dateiname),
              mimeType: const Value('application/pdf'),
              dateigroesse: Value(bytes.length),
              daten: Value(bytes),
              auftragId: Value(widget.auftrag.id),
              kategorie: const Value('Kostenvorschuss-Antrag'),
              datum: Value(DateTime.now()),
            ),
          );
      // Brutto-Betrag in der Akte vermerken.
      final db = ref.read(appDatabaseProvider);
      final brutto = (_d(_stunden) * _d(_stundensatz) +
              _auslagenListe().fold<double>(0, (s, p) => s + p.netto)) *
          (1 + _d(_ust) / 100);
      await (db.update(db.auftraege)
            ..where((t) => t.id.equals(widget.auftrag.id)))
          .write(AuftraegeCompanion(
        kostenvorschuss: Value(brutto),
        updatedAt: Value(DateTime.now()),
      ));
      // Druck-Dialog parallel öffnen.
      await previewKostenvorschussPdf(daten);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Antrag in der Akte abgelegt (Tab „Dokumente") und ${brutto.toStringAsFixed(2)} € als Vorschuss vermerkt.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<KostenvorschussPdfData> _baueDaten() async {
    final absender = await absenderFromSettings(ref);
    KundenData? gericht = widget.kunde;
    if (gericht == null && widget.auftrag.kundeId != null) {
      gericht = await ref
          .read(kundenRepositoryProvider)
          .byId(widget.auftrag.kundeId!);
    }
    return KostenvorschussPdfData(
      auftrag: widget.auftrag,
      gericht: gericht,
      absender: absender,
      datum: DateTime.now(),
      stunden: _d(_stunden),
      stundensatz: _d(_stundensatz),
      auslagen: _auslagenListe(),
      ustSatz: _d(_ust),
      begruendung:
          _begruendung.text.trim().isEmpty ? null : _begruendung.text.trim(),
    );
  }

  Future<void> _vorschau() async {
    setState(() => _saving = true);
    try {
      await previewKostenvorschussPdf(await _baueDaten());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _speichernAlsKostenvorschuss() async {
    setState(() => _saving = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final brutto = (_d(_stunden) * _d(_stundensatz) +
              _auslagenListe().fold<double>(0, (s, p) => s + p.netto)) *
          (1 + _d(_ust) / 100);
      await (db.update(db.auftraege)
            ..where((t) => t.id.equals(widget.auftrag.id)))
          .write(AuftraegeCompanion(
        kostenvorschuss: Value(brutto),
        updatedAt: Value(DateTime.now()),
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Kostenvorschuss ${brutto.toStringAsFixed(2)} € in der Akte vermerkt.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stundenBetrag = _d(_stunden) * _d(_stundensatz);
    final auslagen = _auslagenListe();
    final auslagenSumme =
        auslagen.fold<double>(0, (s, p) => s + p.netto);
    final netto = stundenBetrag + auslagenSumme;
    final ust = netto * _d(_ust) / 100;
    final brutto = netto + ust;

    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Kostenvorschuss-Antrag · ${widget.auftrag.aktenzeichen ?? ""}',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text('Schätzung des voraussichtlichen Aufwands gem. § 17 JVEG',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Honorar-Block
                    Text('Honorar',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: LabeledField(
                            'Voraussichtliche Stunden',
                            TextFormField(
                              controller: _stunden,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: LabeledField(
                            'JVEG-Satz €/h (Honorargruppe ${widget.auftrag.honorargruppe ?? "—"})',
                            TextFormField(
                              controller: _stundensatz,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: LabeledField(
                            'USt %',
                            TextFormField(
                              controller: _ust,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Auslagen-Block
                    Text('Voraussichtliche Auslagen (JVEG)',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    _AuslagenZeile(
                      titel: 'Fahrt',
                      mengeCtrl: _fahrtKm,
                      satzCtrl: _fahrtSatz,
                      mengeLabel: 'km',
                      satzLabel: '€/km',
                      onChange: () => setState(() {}),
                    ),
                    _AuslagenZeile(
                      titel: 'Schreibauslagen',
                      mengeCtrl: _schreibSeiten,
                      satzCtrl: _schreibSatz,
                      mengeLabel: 'Anschläge',
                      satzLabel: '€/1000',
                      onChange: () => setState(() {}),
                    ),
                    _AuslagenZeile(
                      titel: 'Kopien',
                      mengeCtrl: _kopieAnzahl,
                      satzCtrl: _kopieSatz,
                      mengeLabel: 'Stk.',
                      satzLabel: '€/Stk.',
                      onChange: () => setState(() {}),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const SizedBox(width: 110, child: Text('Lichtbilder')),
                          Expanded(
                            child: TextFormField(
                              controller: _lichtbilder,
                              decoration: const InputDecoration(
                                  isDense: true, hintText: 'Anzahl'),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _lichtbildSatzErstes,
                              decoration: const InputDecoration(
                                  isDense: true,
                                  hintText: '1. Bild € (z. B. 2,00)'),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _lichtbildSatzWeitere,
                              decoration: const InputDecoration(
                                  isDense: true,
                                  hintText: 'weitere € (z. B. 1,00)'),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const SizedBox(width: 110, child: Text('Porto')),
                          Expanded(
                            child: TextFormField(
                              controller: _porto,
                              decoration: const InputDecoration(
                                  isDense: true, hintText: 'Pauschale €'),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const SizedBox(width: 110, child: Text('Sonstiges')),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _sonstigesBezeichnung,
                              decoration: const InputDecoration(
                                  isDense: true, hintText: 'Bezeichnung'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _sonstiges,
                              decoration: const InputDecoration(
                                  isDense: true, hintText: 'Betrag €'),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Begründung
                    LabeledField(
                      'Optionale Begründung (überschreibt Standardtext)',
                      TextFormField(
                        controller: _begruendung,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          hintText:
                              'z.B. Aufwand ergibt sich aus den umfangreichen Bauakten…',
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Summe
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _summenZeile('Honorar',
                              '${stundenBetrag.toStringAsFixed(2)} €'),
                          _summenZeile('Auslagen',
                              '${auslagenSumme.toStringAsFixed(2)} €'),
                          const Divider(),
                          _summenZeile(
                              'Netto', '${netto.toStringAsFixed(2)} €'),
                          _summenZeile(
                              'USt ${_d(_ust).toStringAsFixed(0)} %',
                              '${ust.toStringAsFixed(2)} €'),
                          const SizedBox(height: 4),
                          _summenZeile(
                              'Beantragter Vorschuss (brutto)',
                              '${brutto.toStringAsFixed(2)} €',
                              bold: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('In Akte vermerken'),
                    onPressed:
                        _saving ? null : _speichernAlsKostenvorschuss,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.print_outlined, size: 16),
                    label: const Text('Vorschau'),
                    onPressed: _saving ? null : _vorschau,
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.archive_outlined, size: 16),
                    label: const Text('Drucken & in Akte ablegen'),
                    onPressed: _saving ? null : _druckenUndArchivieren,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summenZeile(String l, String w, {bool bold = false}) {
    final style = TextStyle(
      fontSize: bold ? 14 : 12.5,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(l, style: style)),
          Text(w, style: style),
        ],
      ),
    );
  }
}

class _AuslagenZeile extends StatelessWidget {
  const _AuslagenZeile({
    required this.titel,
    required this.mengeCtrl,
    required this.satzCtrl,
    required this.mengeLabel,
    required this.satzLabel,
    required this.onChange,
  });
  final String titel;
  final TextEditingController mengeCtrl;
  final TextEditingController satzCtrl;
  final String mengeLabel;
  final String satzLabel;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(titel)),
          Expanded(
            child: TextFormField(
              controller: mengeCtrl,
              decoration: InputDecoration(isDense: true, hintText: mengeLabel),
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              onChanged: (_) => onChange(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: satzCtrl,
              decoration: InputDecoration(isDense: true, hintText: satzLabel),
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              onChanged: (_) => onChange(),
            ),
          ),
        ],
      ),
    );
  }
}
