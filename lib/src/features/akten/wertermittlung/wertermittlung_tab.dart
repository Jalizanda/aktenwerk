import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import 'wertermittlung_repository.dart';

/// Verkehrswert-Rechner nach ImmoWertV (vereinfachtes Sachwert-Verfahren
/// + Vergleichswert + Marktanpassung).
class WertermittlungTab extends ConsumerStatefulWidget {
  const WertermittlungTab({super.key, required this.auftragId});
  final int auftragId;
  @override
  ConsumerState<WertermittlungTab> createState() =>
      _WertermittlungTabState();
}

class _WertermittlungTabState extends ConsumerState<WertermittlungTab> {
  static final _money = NumberFormat.currency(
      locale: 'de_DE', symbol: '€', decimalDigits: 2);

  final _bodenrichtwert = TextEditingController();
  final _grundstueckFlaeche = TextEditingController();
  final _bgf = TextEditingController();
  final _nhk = TextEditingController();
  final _alter = TextEditingController(text: '0');
  final _markt = TextEditingController(text: '1.00');
  final _vergleichswert = TextEditingController();
  final _bemerkung = TextEditingController();
  DateTime _stichtag = DateTime.now();
  bool _loaded = false;
  int? _eintragId;

  @override
  void dispose() {
    _bodenrichtwert.dispose();
    _grundstueckFlaeche.dispose();
    _bgf.dispose();
    _nhk.dispose();
    _alter.dispose();
    _markt.dispose();
    _vergleichswert.dispose();
    _bemerkung.dispose();
    super.dispose();
  }

  void _fillFrom(WertermittlungenData d) {
    _eintragId = d.id;
    _stichtag = d.stichtag;
    _bodenrichtwert.text = d.bodenrichtwert?.toString() ?? '';
    _grundstueckFlaeche.text = d.grundstueckFlaeche?.toString() ?? '';
    _bgf.text = d.bgf?.toString() ?? '';
    _nhk.text = d.nhk?.toString() ?? '';
    _alter.text = d.altersminderungFaktor?.toString() ?? '0';
    _markt.text = d.marktanpassungFaktor?.toString() ?? '1.00';
    _vergleichswert.text = d.vergleichswert?.toString() ?? '';
    _bemerkung.text = d.bemerkung ?? '';
  }

  double _parse(TextEditingController c) {
    return double.tryParse(c.text.replaceAll(',', '.').trim()) ?? 0;
  }

  // --- Berechnungen ---

  double get _bodenwert =>
      _parse(_bodenrichtwert) * _parse(_grundstueckFlaeche);
  double get _herstellungswert => _parse(_bgf) * _parse(_nhk);
  double get _herstellungswertAbzgl =>
      _herstellungswert * (1 - _parse(_alter).clamp(0, 1));
  double get _sachwert => _bodenwert + _herstellungswertAbzgl;
  double get _marktwert => _sachwert * _parse(_markt);

  Future<void> _save() async {
    await ref.read(wertermittlungRepositoryProvider).upsert(
          WertermittlungenCompanion(
            id: _eintragId == null
                ? const Value.absent()
                : Value(_eintragId!),
            auftragId: Value(widget.auftragId),
            stichtag: Value(_stichtag),
            bodenrichtwert: Value(_parse(_bodenrichtwert)),
            grundstueckFlaeche: Value(_parse(_grundstueckFlaeche)),
            bgf: Value(_parse(_bgf)),
            nhk: Value(_parse(_nhk)),
            altersminderungFaktor: Value(_parse(_alter)),
            marktanpassungFaktor: Value(_parse(_markt)),
            vergleichswert: Value(_parse(_vergleichswert)),
            sachwert: Value(_sachwert),
            marktwert: Value(_marktwert),
            bemerkung: Value(_bemerkung.text.trim().isEmpty
                ? null
                : _bemerkung.text.trim()),
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wertermittlung gespeichert')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(wertermittlungByAkteProvider(widget.auftragId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (d) {
        if (d != null && !_loaded) {
          _loaded = true;
          _fillFrom(d);
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('Wertermittlung nach ImmoWertV',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  FilledButton.icon(
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Speichern'),
                    onPressed: _save,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _Kachel(
                title: 'Stichtag & Grundstück',
                child: Column(
                  children: [
                    Row2(
                      left: DateField(
                          label: 'Wertermittlungsstichtag',
                          value: _stichtag,
                          onChanged: (v) => setState(
                              () => _stichtag = v ?? DateTime.now())),
                      right: LabeledField(
                        'Bodenrichtwert (€/m²)',
                        TextFormField(
                          controller: _bodenrichtwert,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row2(
                      left: LabeledField(
                        'Grundstücksfläche (m²)',
                        TextFormField(
                          controller: _grundstueckFlaeche,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      right: _Result(
                          label: 'Bodenwert',
                          wert: _money.format(_bodenwert)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Kachel(
                title: 'Sachwertverfahren',
                child: Column(
                  children: [
                    Row2(
                      left: LabeledField(
                        'Bruttogrundfläche BGF (m²)',
                        TextFormField(
                          controller: _bgf,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      right: LabeledField(
                        'Normalherstellungskosten (€/m²)',
                        TextFormField(
                          controller: _nhk,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row2(
                      left: LabeledField(
                        'Alterswertminderung (0 – 1)',
                        TextFormField(
                          controller: _alter,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      right: _Result(
                          label: 'Herstellungswert (nach Alter)',
                          wert: _money.format(_herstellungswertAbzgl)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Kachel(
                title: 'Vergleichswert & Marktanpassung',
                child: Column(
                  children: [
                    Row2(
                      left: LabeledField(
                        'Vergleichswert (€)',
                        TextFormField(
                          controller: _vergleichswert,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      right: LabeledField(
                        'Marktanpassungsfaktor (z.B. 0,90)',
                        TextFormField(
                          controller: _markt,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Kachel(
                title: 'Ergebnisse',
                child: Column(
                  children: [
                    _Result(
                        label: 'Sachwert',
                        wert: _money.format(_sachwert),
                        gross: true),
                    _Result(
                        label: 'Marktwert (Sachwert × Marktanpassung)',
                        wert: _money.format(_marktwert),
                        gross: true,
                        farbe: AppTheme.accent600),
                    if (_parse(_vergleichswert) > 0)
                      _Result(
                        label:
                            'Mittelwert aus Sachwert & Vergleichswert',
                        wert: _money.format(
                            (_marktwert + _parse(_vergleichswert)) / 2),
                        gross: true,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Kachel(
                title: 'Bemerkung',
                child: TextFormField(
                    controller: _bemerkung, minLines: 2, maxLines: 5),
              ),
              const SizedBox(height: 12),
              Text(
                'Hinweis: vereinfachtes Schema. Für belastbare Gutachten weitere '
                'Korrekturen (Marktanpassung je Lage, Bauweise) ergänzen.',
                style: TextStyle(fontSize: 11, color: AppTheme.slate500),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Kachel extends StatelessWidget {
  const _Kachel({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
          const Divider(),
          child,
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.label,
    required this.wert,
    this.gross = false,
    this.farbe,
  });
  final String label;
  final String wert;
  final bool gross;
  final Color? farbe;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: gross ? 14 : 12,
                    color: AppTheme.slate500)),
          ),
          Text(
            wert,
            style: TextStyle(
              fontSize: gross ? 18 : 13,
              fontWeight: FontWeight.w800,
              color: farbe ?? AppTheme.slate900,
            ),
          ),
        ],
      ),
    );
  }
}
