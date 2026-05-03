import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../features/system/konten/debitor_service.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'lieferanten_repository.dart';

class LieferantenScreen extends ConsumerWidget {
  const LieferantenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lieferantenListProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.local_shipping_outlined,
          title: 'Lieferanten',
          subtitle: 'Dienstleister, Labore, Materiallieferanten',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neuer Lieferant'),
              onPressed: () => _show(context, ref),
            ),
          ],
          searchHint: 'Suche Firma, Ort, Kategorie …',
          onSearchChanged: (v) =>
              ref.read(lieferantenQueryProvider.notifier).state = v,
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) => items.isEmpty
                ? const EmptyListState(
                    icon: Icons.local_shipping_outlined,
                    title: 'Keine Lieferanten erfasst')
                : DataTableCard(
                    child: DataTable(
              showCheckboxColumn: false,
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      columns: const [
                        DataColumn(label: Text('Firma')),
                        DataColumn(label: Text('Ansprechpartner')),
                        DataColumn(label: Text('Ort')),
                        DataColumn(label: Text('Kategorie')),
                        DataColumn(label: Text('Telefon')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final l in items)
                          DataRow(
                            onSelectChanged: (_) => _show(context, ref, l),
                            cells: [
                              DataCell(Text(l.firma)),
                              DataCell(Text(l.ansprechpartner ?? '')),
                              DataCell(Text(
                                  [l.plz, l.ort].whereType<String>().join(' '))),
                              DataCell(Text(l.kategorie ?? '')),
                              DataCell(Text(l.telefon ?? '')),
                              DataCell(IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                onPressed: () =>
                                    _confirm(context, ref, l),
                              )),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _show(BuildContext context, WidgetRef ref,
      [LieferantenData? l]) async {
    await showDialog(
      context: context,
      builder: (_) => _LieferantForm(lieferant: l),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref,
      LieferantenData l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Lieferant löschen?'),
        content: Text('«${l.firma}» wird gelöscht.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
              child: const Text('Abbrechen')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(lieferantenRepositoryProvider).delete(l.id);
    }
  }
}

class _LieferantForm extends ConsumerStatefulWidget {
  const _LieferantForm({this.lieferant});
  final LieferantenData? lieferant;
  @override
  ConsumerState<_LieferantForm> createState() => _LieferantFormState();
}

class _LieferantFormState extends ConsumerState<_LieferantForm> {
  final _formKey = GlobalKey<FormState>();
  late final _firma = _tec(widget.lieferant?.firma);
  late final _ansprech = _tec(widget.lieferant?.ansprechpartner);
  late final _strasse = _tec(widget.lieferant?.strasse);
  late final _plz = _tec(widget.lieferant?.plz);
  late final _ort = _tec(widget.lieferant?.ort);
  late final _land = _tec(widget.lieferant?.land);
  late final _telefon = _tec(widget.lieferant?.telefon);
  late final _email = _tec(widget.lieferant?.email);
  late final _website = _tec(widget.lieferant?.website);
  late final _kategorie = _tec(widget.lieferant?.kategorie);
  late final _kdnr = _tec(widget.lieferant?.kundennummer);
  late final _ustId = _tec(widget.lieferant?.ustId);
  late final _steuerNr = _tec(widget.lieferant?.steuerNr);
  late final _zahlungsziel = _tec(
      (widget.lieferant?.zahlungszielTage ?? 14).toString());
  late final _bank = _tec(widget.lieferant?.bank);
  late final _kontoinhaber = _tec(widget.lieferant?.kontoinhaber);
  late final _iban = _tec(widget.lieferant?.iban);
  late final _bic = _tec(widget.lieferant?.bic);
  late final _glaeubigerId = _tec(widget.lieferant?.glaeubigerId);
  late final _mandatRef = _tec(widget.lieferant?.mandatRef);
  late final _notiz = _tec(widget.lieferant?.notiz);
  String _zahlungsweise =
      _normZahl(null);
  bool _saving = false;

  TextEditingController _tec(String? v) =>
      TextEditingController(text: v ?? '');

  static String _normZahl(String? v) {
    const allowed = ['ueberweisung', 'lastschrift', 'kreditkarte', 'paypal'];
    return allowed.contains(v) ? v! : 'ueberweisung';
  }

  @override
  void initState() {
    super.initState();
    _zahlungsweise = _normZahl(widget.lieferant?.zahlungsweise);
  }

  @override
  void dispose() {
    for (final c in [
      _firma, _ansprech, _strasse, _plz, _ort, _land,
      _telefon, _email, _website,
      _kategorie, _kdnr, _ustId, _steuerNr, _zahlungsziel,
      _bank, _kontoinhaber, _iban, _bic,
      _glaeubigerId, _mandatRef, _notiz,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.lieferant != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final ziel = int.tryParse(_zahlungsziel.text.trim()) ?? 14;
    String? kreditor = widget.lieferant?.kreditornummer;
    if (kreditor == null || kreditor.isEmpty) {
      kreditor = await ref
          .read(debitorKreditorServiceProvider)
          .nextKreditornummer();
    }
    final companion = LieferantenCompanion(
      id: _isEdit ? Value(widget.lieferant!.id) : const Value.absent(),
      firma: Value(_firma.text.trim()),
      ansprechpartner: _nt(_ansprech),
      strasse: _nt(_strasse),
      plz: _nt(_plz),
      ort: _nt(_ort),
      land: _nt(_land),
      telefon: _nt(_telefon),
      email: _nt(_email),
      website: _nt(_website),
      kategorie: _nt(_kategorie),
      kundennummer: _nt(_kdnr),
      kreditornummer: Value(kreditor),
      ustId: _nt(_ustId),
      steuerNr: _nt(_steuerNr),
      zahlungszielTage: Value(ziel),
      zahlungsweise: Value(_zahlungsweise),
      bank: _nt(_bank),
      kontoinhaber: _nt(_kontoinhaber),
      iban: _nt(_iban),
      bic: _nt(_bic),
      glaeubigerId: _nt(_glaeubigerId),
      mandatRef: _nt(_mandatRef),
      notiz: _nt(_notiz),
    );
    try {
      await ref.read(lieferantenRepositoryProvider).upsert(companion);
      if (mounted) Navigator.of(context, rootNavigator: true).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Value<String?> _nt(TextEditingController c) {
    final v = c.text.trim();
    return Value(v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    return StandardFormDialog(
      title: _isEdit ? 'Lieferant bearbeiten' : 'Neuer Lieferant',
      saving: _saving,
      maxWidth: 900,
      maxHeight: 820,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(lieferantenRepositoryProvider)
              .delete(widget.lieferant!.id)
          : null,
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FormSection('Basis', children: [
                Row2(
                  left: LabeledField(
                    'Firma *',
                    TextFormField(
                      controller: _firma,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Erforderlich'
                          : null,
                    ),
                  ),
                  right: LabeledField(
                    'Kategorie',
                    _KategorieDropdown(
                      controller: _kategorie,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                LabeledField('Ansprechpartner',
                    TextFormField(controller: _ansprech)),
              ]),
              FormSection('Adresse', children: [
                LabeledField('Straße', TextFormField(controller: _strasse)),
                const SizedBox(height: 12),
                Row3(
                  a: LabeledField('PLZ', TextFormField(controller: _plz)),
                  b: LabeledField('Ort', TextFormField(controller: _ort)),
                  c: LabeledField('Land', TextFormField(controller: _land)),
                ),
              ]),
              FormSection('Kontakt', children: [
                Row2(
                  left: LabeledField(
                      'Telefon', TextFormField(controller: _telefon)),
                  right: LabeledField(
                      'E-Mail', TextFormField(controller: _email)),
                ),
                const SizedBox(height: 12),
                LabeledField(
                    'Website', TextFormField(controller: _website)),
              ]),
              FormSection('Steuer & Zahlung', children: [
                Row3(
                  a: LabeledField(
                      'Kundennr.', TextFormField(controller: _kdnr)),
                  b: LabeledField(
                      'USt-IdNr.', TextFormField(controller: _ustId)),
                  c: LabeledField(
                      'Steuer-Nr.', TextFormField(controller: _steuerNr)),
                ),
                const SizedBox(height: 12),
                Row2(
                  left: LabeledField(
                    'Zahlungsziel (Tage)',
                    TextFormField(
                      controller: _zahlungsziel,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  right: LabeledField(
                    'Zahlungsweise',
                    DropdownButtonFormField<String>(
                      initialValue: _zahlungsweise,
                      isDense: true,
                      items: const [
                        DropdownMenuItem(
                            value: 'ueberweisung', child: Text('Überweisung')),
                        DropdownMenuItem(
                            value: 'lastschrift', child: Text('Lastschrift')),
                        DropdownMenuItem(
                            value: 'kreditkarte', child: Text('Kreditkarte')),
                        DropdownMenuItem(
                            value: 'paypal', child: Text('PayPal')),
                      ],
                      onChanged: (v) =>
                          setState(() => _zahlungsweise = v ?? 'ueberweisung'),
                    ),
                  ),
                ),
              ]),
              FormSection('Bankverbindung', children: [
                Row2(
                  left: LabeledField(
                      'Bank', TextFormField(controller: _bank)),
                  right: LabeledField('Kontoinhaber',
                      TextFormField(controller: _kontoinhaber)),
                ),
                const SizedBox(height: 12),
                Row2(
                  flex: const (3, 1),
                  left: LabeledField(
                      'IBAN', TextFormField(controller: _iban)),
                  right: LabeledField(
                      'BIC', TextFormField(controller: _bic)),
                ),
                if (_zahlungsweise == 'lastschrift') ...[
                  const SizedBox(height: 12),
                  Row2(
                    left: LabeledField('Gläubiger-ID',
                        TextFormField(controller: _glaeubigerId)),
                    right: LabeledField('Mandatsreferenz',
                        TextFormField(controller: _mandatRef)),
                  ),
                ],
              ]),
              FormSection('Notiz', children: [
                TextFormField(
                    controller: _notiz, minLines: 2, maxLines: 5),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Standard-Kategorien für Lieferanten — gängige SV-Büro-Klassifizierung.
/// Der Anwender kann zusätzlich eigene über „Eigene Kategorie …" hinzufügen.
const _lieferantenKategorien = <String>[
  'Versicherung',
  'Telekommunikation',
  'EDV / Software',
  'Bürobedarf',
  'Werkzeug / Messtechnik',
  'Fortbildung',
  'Mobilität / KFZ',
  'Energie',
  'Wartung / Service',
  'Buch / Fachliteratur',
  'Beratung / Steuerberatung',
  'Reisekosten',
  'Bewirtung',
  'Porto / Versand',
  'Handwerk / Subunternehmer',
  'Gericht / Behörde',
  'Sachverständigen-Verband',
  'Bank / Finanzen',
  'Sonstiges',
];

class _KategorieDropdown extends StatefulWidget {
  const _KategorieDropdown({required this.controller});
  final TextEditingController controller;
  @override
  State<_KategorieDropdown> createState() => _KategorieDropdownState();
}

class _KategorieDropdownState extends State<_KategorieDropdown> {
  static const _eigeneOption = '__eigene__';

  String? _aktuelleAuswahl() {
    final t = widget.controller.text.trim();
    if (t.isEmpty) return null;
    return _lieferantenKategorien.contains(t) ? t : t;
  }

  @override
  Widget build(BuildContext context) {
    final cur = _aktuelleAuswahl();
    final isCustom = cur != null && !_lieferantenKategorien.contains(cur);
    return DropdownButtonFormField<String>(
      initialValue: cur,
      isExpanded: true,
      decoration: const InputDecoration(
        hintText: '— wählen —',
      ),
      items: [
        for (final k in _lieferantenKategorien)
          DropdownMenuItem(value: k, child: Text(k)),
        if (isCustom)
          DropdownMenuItem(
            value: cur,
            child: Text(cur, style: const TextStyle(fontStyle: FontStyle.italic)),
          ),
        const DropdownMenuItem(
          value: _eigeneOption,
          child: Row(children: [
            Icon(Icons.add, size: 14),
            SizedBox(width: 6),
            Text('Eigene Kategorie …'),
          ]),
        ),
      ],
      onChanged: (v) async {
        if (v == _eigeneOption) {
          final neu = await _frageEigeneKategorie();
          if (neu != null && neu.isNotEmpty) {
            setState(() => widget.controller.text = neu);
          }
          return;
        }
        if (v != null) {
          setState(() => widget.controller.text = v);
        }
      },
    );
  }

  Future<String?> _frageEigeneKategorie() async {
    final ctrl = TextEditingController();
    final ergebnis = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: const Text('Eigene Kategorie'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Bezeichnung',
              hintText: 'z. B. Hosting / Domain',
            ),
            onSubmitted: (v) => Navigator.of(context, rootNavigator: true)
                .pop(v.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context, rootNavigator: true)
                .pop(ctrl.text.trim()),
            child: const Text('Übernehmen'),
          ),
        ],
      ),
    );
    return ergebnis;
  }
}
