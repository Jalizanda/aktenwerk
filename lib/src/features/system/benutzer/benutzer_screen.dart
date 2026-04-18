import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import 'benutzer_repository.dart';

class BenutzerScreen extends ConsumerWidget {
  const BenutzerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activeBenutzerProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (b) => _BenutzerForm(key: ValueKey(b?.id ?? 'neu'), benutzer: b),
    );
  }
}

class _BenutzerForm extends ConsumerStatefulWidget {
  const _BenutzerForm({super.key, required this.benutzer});
  final BenutzerData? benutzer;

  @override
  ConsumerState<_BenutzerForm> createState() => _BenutzerFormState();
}

class _BenutzerFormState extends ConsumerState<_BenutzerForm> {
  final _formKey = GlobalKey<FormState>();

  late final _anrede = _tec(widget.benutzer?.anrede);
  late final _titel = _tec(widget.benutzer?.titel);
  late final _vorname = _tec(widget.benutzer?.vorname);
  late final _nachname = _tec(widget.benutzer?.nachname);
  late final _firma = _tec(widget.benutzer?.firma);
  late final _strasse = _tec(widget.benutzer?.strasse);
  late final _plz = _tec(widget.benutzer?.plz);
  late final _ort = _tec(widget.benutzer?.ort);
  late final _telefon = _tec(widget.benutzer?.telefon);
  late final _mobil = _tec(widget.benutzer?.mobil);
  late final _email = _tec(widget.benutzer?.email);
  late final _website = _tec(widget.benutzer?.website);
  late final _steuerNr = _tec(widget.benutzer?.steuerNr);
  late final _ustId = _tec(widget.benutzer?.ustId);
  late final _iban = _tec(widget.benutzer?.iban);
  late final _bic = _tec(widget.benutzer?.bic);
  late final _bank = _tec(widget.benutzer?.bank);
  late final _bestellungsText = _tec(widget.benutzer?.bestellungsText);
  late final _standardSatz =
      _tec(widget.benutzer?.standardStundensatz?.toStringAsFixed(2));

  bool _saving = false;

  TextEditingController _tec(String? v) => TextEditingController(text: v ?? '');

  @override
  void dispose() {
    for (final c in [
      _anrede, _titel, _vorname, _nachname, _firma,
      _strasse, _plz, _ort,
      _telefon, _mobil, _email, _website,
      _steuerNr, _ustId, _iban, _bic, _bank,
      _bestellungsText, _standardSatz,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(benutzerRepositoryProvider);
    final satz = double.tryParse(_standardSatz.text.trim().replaceAll(',', '.'));
    final companion = BenutzerCompanion(
      anrede: _nt(_anrede),
      titel: _nt(_titel),
      vorname: _nt(_vorname),
      nachname: _nt(_nachname),
      firma: _nt(_firma),
      strasse: _nt(_strasse),
      plz: _nt(_plz),
      ort: _nt(_ort),
      telefon: _nt(_telefon),
      mobil: _nt(_mobil),
      email: _nt(_email),
      website: _nt(_website),
      steuerNr: _nt(_steuerNr),
      ustId: _nt(_ustId),
      iban: _nt(_iban),
      bic: _nt(_bic),
      bank: _nt(_bank),
      bestellungsText: _nt(_bestellungsText),
      standardStundensatz:
          satz == null ? const Value(null) : Value(satz),
    );
    try {
      await repo.saveActive(companion);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil gespeichert')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Value<String?> _nt(TextEditingController c) {
    final v = c.text.trim();
    return Value(v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(
            children: [
              const Icon(Icons.account_circle_outlined, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Benutzer',
                        style: theme.textTheme.headlineMedium),
                    Text(
                      'Daten des Sachverständigen für Briefkopf, Rechnungen und Anschreiben',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: const Text('Speichern'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Section('Person', children: [
                      _Row2(
                        left: _L('Anrede', TextFormField(controller: _anrede)),
                        right: _L('Titel', TextFormField(controller: _titel)),
                      ),
                      const SizedBox(height: 12),
                      _Row2(
                        left: _L('Vorname',
                            TextFormField(controller: _vorname)),
                        right: _L('Nachname',
                            TextFormField(controller: _nachname)),
                      ),
                      const SizedBox(height: 12),
                      _L('Firma / Büro',
                          TextFormField(controller: _firma)),
                    ]),
                    _Section('Adresse', children: [
                      _L('Straße',
                          TextFormField(controller: _strasse)),
                      const SizedBox(height: 12),
                      _Row2(
                        flex: const (1, 3),
                        left:
                            _L('PLZ', TextFormField(controller: _plz)),
                        right: _L('Ort', TextFormField(controller: _ort)),
                      ),
                    ]),
                    _Section('Kontakt', children: [
                      _Row2(
                        left: _L(
                          'Telefon',
                          TextFormField(
                              controller: _telefon,
                              keyboardType: TextInputType.phone),
                        ),
                        right: _L(
                          'Mobil',
                          TextFormField(
                              controller: _mobil,
                              keyboardType: TextInputType.phone),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _Row2(
                        left: _L(
                          'E-Mail',
                          TextFormField(
                              controller: _email,
                              keyboardType:
                                  TextInputType.emailAddress),
                        ),
                        right: _L(
                          'Website',
                          TextFormField(
                              controller: _website,
                              keyboardType: TextInputType.url),
                        ),
                      ),
                    ]),
                    _Section('Steuer & Bank', children: [
                      _Row2(
                        left: _L('Steuer-Nr.',
                            TextFormField(controller: _steuerNr)),
                        right: _L('USt-ID',
                            TextFormField(controller: _ustId)),
                      ),
                      const SizedBox(height: 12),
                      _L('Bank', TextFormField(controller: _bank)),
                      const SizedBox(height: 12),
                      _Row2(
                        flex: const (3, 1),
                        left: _L('IBAN',
                            TextFormField(controller: _iban)),
                        right: _L('BIC',
                            TextFormField(controller: _bic)),
                      ),
                    ]),
                    _Section('Bestellung & Standardwerte', children: [
                      _L(
                        'Standard-Stundensatz (€)',
                        TextFormField(
                          controller: _standardSatz,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _L(
                        'Bestellungstext (für Briefkopf)',
                        TextFormField(
                          controller: _bestellungsText,
                          minLines: 3,
                          maxLines: 6,
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, {required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );
}

class _L extends StatelessWidget {
  const _L(this.label, this.child);
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ),
          child,
        ],
      );
}

class _Row2 extends StatelessWidget {
  const _Row2({required this.left, required this.right, this.flex});
  final Widget left;
  final Widget right;
  final (int, int)? flex;
  @override
  Widget build(BuildContext context) {
    final (l, r) = flex ?? (1, 1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: l, child: left),
        const SizedBox(width: 12),
        Expanded(flex: r, child: right),
      ],
    );
  }
}
