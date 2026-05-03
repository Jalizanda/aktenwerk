import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../shared/widgets/badges.dart';
import '../../../core/geo/geo_service.dart';
import '../../../features/akten/auftraege/auftraege_repository.dart';
import '../../../features/system/einstellungen/einstellungen_repository.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/formel_text_field.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'auslagen_repository.dart';

final auslagenQueryProvider = StateProvider<String>((ref) => '');

class AuslagenScreen extends ConsumerStatefulWidget {
  const AuslagenScreen({super.key});

  @override
  ConsumerState<AuslagenScreen> createState() => _AuslagenScreenState();
}

class _AuslagenScreenState extends ConsumerState<AuslagenScreen> {
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');
  int _sortCol = 0;
  bool _sortAsc = false; // jüngstes Datum zuerst

  void _onSort(int col, bool asc) =>
      setState(() {
        _sortCol = col;
        _sortAsc = asc;
      });

  Comparable<Object> _key(AuslageWithAuftrag a, int col) {
    String s(String? v) => (v ?? '').toLowerCase();
    return switch (col) {
      0 => a.auslage.datum.toIso8601String(),
      1 => s(a.auftrag?.aktenzeichen),
      2 => s(a.auslage.kategorie),
      3 => s(a.auslage.beschreibung),
      4 => a.auslage.menge,
      5 => a.auslage.summe,
      6 => a.auslage.abgerechnet ? '1' : '0',
      _ => a.auslage.datum.toIso8601String(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(auslagenListProvider);
    final filter = ref.watch(auslagenFilterProvider);
    final query = ref.watch(auslagenQueryProvider).trim().toLowerCase();

    List<AuslageWithAuftrag> applyQuery(List<AuslageWithAuftrag> items) {
      if (query.isEmpty) return items;
      return items.where((a) {
        final parts = [
          a.auslage.kategorie,
          a.auslage.beschreibung,
          a.auslage.notiz,
          a.auslage.art,
          a.auslage.einheit,
          a.auftrag?.aktenzeichen,
          a.auftrag?.betreff,
        ]
            .whereType<String>()
            .map((v) => v.toLowerCase())
            .join(' ');
        return parts.contains(query);
      }).toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.payments_outlined,
          title: 'Auslagen',
          subtitle: 'Auslagen pro Auftrag (Fahrt, Porto, Kopien, Labor …)',
          searchHint: 'Suche Kategorie, Beschreibung, Aktenzeichen …',
          onSearchChanged: (v) =>
              ref.read(auslagenQueryProvider.notifier).state = v,
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neue Auslage'),
              onPressed: () => _show(context, ref),
            ),
          ],
          filters: [
            DropdownButtonHideUnderline(
              child: DropdownButton<bool?>(
                value: filter.abgerechnet,
                hint: const Text('Alle'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Alle')),
                  DropdownMenuItem(value: false, child: Text('Nur offen')),
                  DropdownMenuItem(value: true, child: Text('Nur abgerechnet')),
                ],
                onChanged: (v) => ref
                    .read(auslagenFilterProvider.notifier)
                    .update((f) => v == null
                        ? f.copyWith(clearAbgerechnet: true)
                        : f.copyWith(abgerechnet: v)),
              ),
            ),
          ],
        ),
        // Live-Filter durch Suchfeld + Art-Tile vorab anwenden, sonst stimmen
        // die KPI-Zahlen nicht zur sichtbaren Liste.
        async.maybeWhen(
          data: (all) => _KpiStrip(
            // ungefilterte Liste an die KPIs reichen, damit man immer alle
            // Arten als Tile sieht — auch wenn aktuell eine gefiltert ist
            items: applyQuery(all),
            aktiveArt: filter.art,
            onArt: (art) => ref
                .read(auslagenFilterProvider.notifier)
                .update((f) =>
                    art == null ? f.copyWith(clearArt: true) : f.copyWith(art: art)),
          ),
          orElse: () => const SizedBox.shrink(),
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (all) {
              final items = applyQuery(all);
              if (items.isEmpty) {
                return const EmptyListState(
                    icon: Icons.payments_outlined,
                    title: 'Keine Auslagen erfasst');
              }
              final sorted = [...items]..sort((a, b) {
                  final ka = _key(a, _sortCol);
                  final kb = _key(b, _sortCol);
                  final cmp = Comparable.compare(ka, kb);
                  return _sortAsc ? cmp : -cmp;
                });
              return DataTableCard(
                    child: DataTable(
              showCheckboxColumn: false,
                      sortColumnIndex: _sortCol,
                      sortAscending: _sortAsc,
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      columns: [
                        DataColumn(label: const Text('Datum'), onSort: _onSort),
                        DataColumn(label: const Text('Auftrag'), onSort: _onSort),
                        DataColumn(label: const Text('Kategorie'), onSort: _onSort),
                        DataColumn(label: const Text('Beschreibung'), onSort: _onSort),
                        DataColumn(label: const Text('Menge'), numeric: true, onSort: _onSort),
                        DataColumn(label: const Text('Summe €'), numeric: true, onSort: _onSort),
                        DataColumn(label: const Text('Abgerechnet'), onSort: _onSort),
                        const DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final a in sorted)
                          DataRow(
                            onSelectChanged: (_) => _show(context, ref, a),
                            cells: [
                              DataCell(Text(_dateFmt.format(a.auslage.datum))),
                              DataCell(Text(a.auftrag?.aktenzeichen ?? '—')),
                              DataCell(Text(a.auslage.kategorie ?? '')),
                              DataCell(Text(a.auslage.beschreibung ?? '')),
                              DataCell(Text(
                                  '${a.auslage.menge.toStringAsFixed(2)} ${a.auslage.einheit ?? ''}')),
                              DataCell(Text(
                                  a.auslage.summe.toStringAsFixed(2))),
                              DataCell(Checkbox(
                                value: a.auslage.abgerechnet,
                                onChanged: (v) async {
                                  await ref
                                      .read(auslagenRepositoryProvider)
                                      .upsert(AuslagenCompanion(
                                        id: Value(a.auslage.id),
                                        abgerechnet: Value(v ?? false),
                                      ));
                                },
                              )),
                              DataCell(IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                onPressed: () async => ref
                                    .read(auslagenRepositoryProvider)
                                    .delete(a.auslage.id),
                              )),
                            ],
                          ),
                      ],
                    ),
                  );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _show(BuildContext context, WidgetRef ref,
      [AuslageWithAuftrag? a]) async {
    await showDialog(
      context: context,
      builder: (_) => _AuslageForm(eintrag: a),
    );
  }
}

Future<void> showAuslageEditor(BuildContext context,
    {AuslageWithAuftrag? eintrag, int? prefillAuftragId}) async {
  await showDialog(
    context: context,
    useRootNavigator: true,
    builder: (_) => _AuslageForm(
        eintrag: eintrag, prefillAuftragId: prefillAuftragId),
  );
}

class _KpiStrip extends StatelessWidget {
  const _KpiStrip({
    required this.items,
    required this.aktiveArt,
    required this.onArt,
  });
  final List<AuslageWithAuftrag> items;

  /// Aktuell aktive Filter-Art (`null` = keine Filterung).
  final String? aktiveArt;

  /// Callback: `null` schaltet Filter aus, sonst wird auf die Art gefiltert.
  final ValueChanged<String?> onArt;

  static final _money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

  /// Reihenfolge + Labels der Auslagen-Arten (entspricht den JVEG-Posten,
  /// plus Sonstiges am Ende).
  static const _arten = <(String, String, IconData)>[
    ('fahrt', 'Fahrt', Icons.directions_car_outlined),
    ('schreibauslagen', 'Schreibauslagen', Icons.edit_note),
    ('kopie_sw', 'Kopie s/w', Icons.content_copy),
    ('kopie_farbe', 'Kopie farbig', Icons.palette_outlined),
    ('lichtbilder', 'Lichtbilder', Icons.photo_camera_outlined),
    ('porto', 'Porto', Icons.local_post_office_outlined),
    ('fremdleistung', 'Fremdleistung', Icons.handyman_outlined),
    ('sonstiges', 'Sonstiges', Icons.more_horiz),
  ];

  @override
  Widget build(BuildContext context) {
    final gesamt = items.fold<double>(0, (s, a) => s + a.auslage.summe);
    final offen = items
        .where((a) => !a.auslage.abgerechnet)
        .fold<double>(0, (s, a) => s + a.auslage.summe);
    final byArt = <String, ({double summe, int anzahl})>{};
    for (final a in items) {
      final k = a.auslage.art ?? 'sonstiges';
      final cur = byArt[k];
      byArt[k] = (
        summe: (cur?.summe ?? 0) + a.auslage.summe,
        anzahl: (cur?.anzahl ?? 0) + 1,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: KpiCard(
                  icon: Icons.euro,
                  label: 'Gesamt',
                  value: _money.format(gesamt),
                  accent: BadgeColors.blueFg,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: KpiCard(
                  icon: Icons.hourglass_empty,
                  label: 'noch offen',
                  value: _money.format(offen),
                  accent: BadgeColors.amberFg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Per-Art-Tiles: Klick filtert die Liste; nochmaliger Klick auf
          // den aktiven Tile entfernt den Filter wieder.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (key, label, icon) in _arten)
                _ArtTile(
                  label: label,
                  icon: icon,
                  anzahl: byArt[key]?.anzahl ?? 0,
                  summe: byArt[key]?.summe ?? 0,
                  aktiv: aktiveArt == key,
                  onTap: () => onArt(aktiveArt == key ? null : key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArtTile extends StatelessWidget {
  const _ArtTile({
    required this.label,
    required this.icon,
    required this.anzahl,
    required this.summe,
    required this.aktiv,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final int anzahl;
  final double summe;
  final bool aktiv;
  final VoidCallback onTap;

  static final _money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = anzahl == 0;
    return Material(
      color: aktiv
          ? scheme.primaryContainer
          : (muted
              ? scheme.surfaceContainerLow
              : scheme.surfaceContainerHigh),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: anzahl == 0 ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16,
                  color: aktiv
                      ? scheme.onPrimaryContainer
                      : (muted
                          ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
                          : scheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: aktiv ? FontWeight.w700 : FontWeight.w500,
                  color: aktiv
                      ? scheme.onPrimaryContainer
                      : (muted
                          ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
                          : scheme.onSurface),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: aktiv
                      ? Colors.white.withValues(alpha: 0.4)
                      : scheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$anzahl',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: muted ? scheme.onSurfaceVariant : null,
                    )),
              ),
              const SizedBox(width: 8),
              Text(_money.format(summe),
                  style: TextStyle(
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: muted ? scheme.onSurfaceVariant : null,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuslageForm extends ConsumerStatefulWidget {
  const _AuslageForm({this.eintrag, this.prefillAuftragId});
  final int? prefillAuftragId;
  final AuslageWithAuftrag? eintrag;
  @override
  ConsumerState<_AuslageForm> createState() => _AuslageFormState();
}

class _AuslageFormState extends ConsumerState<_AuslageForm> {
  final _formKey = GlobalKey<FormState>();
  int? _auftragId;
  DateTime _datum = DateTime.now();
  String _art = 'sonstiges';
  late final _kat =
      TextEditingController(text: widget.eintrag?.auslage.kategorie ?? '');
  late final _beschreibung = TextEditingController(
      text: widget.eintrag?.auslage.beschreibung ?? '');
  late final _menge = TextEditingController(
      text: widget.eintrag?.auslage.menge.toStringAsFixed(2) ?? '1,00');
  late final _einheit =
      TextEditingController(text: widget.eintrag?.auslage.einheit ?? '');
  late final _einzel = TextEditingController(
      text: widget.eintrag?.auslage.einzelpreis.toStringAsFixed(2) ?? '');
  late final _notiz =
      TextEditingController(text: widget.eintrag?.auslage.notiz ?? '');
  bool _abgerechnet = false;
  bool _saving = false;

  static const _artOptions = [
    ('fahrt', 'Fahrtkosten'),
    ('schreibauslagen', 'Schreibauslagen'),
    ('kopie_sw', 'Kopie s/w'),
    ('kopie_farbe', 'Kopie Farbe'),
    ('lichtbilder', 'Lichtbilder'),
    ('porto', 'Porto'),
    ('fremdleistung', 'Fremdleistung'),
    ('sonstiges', 'Sonstiges'),
  ];

  @override
  void initState() {
    super.initState();
    _auftragId = widget.eintrag?.auslage.auftragId ?? widget.prefillAuftragId;
    _datum = widget.eintrag?.auslage.datum ?? DateTime.now();
    _abgerechnet = widget.eintrag?.auslage.abgerechnet ?? false;
    final rawArt = widget.eintrag?.auslage.art ?? 'sonstiges';
    final allowed = _artOptions.map((t) => t.$1).toSet();
    _art = allowed.contains(rawArt) ? rawArt : 'sonstiges';
  }

  @override
  void dispose() {
    for (final c in [_kat, _beschreibung, _menge, _einheit, _einzel, _notiz]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.eintrag != null;

  /// Öffnet den km-Rechner. Ermittelt Firma-Adresse aus Einstellungen
  /// und (falls Auftrag gewählt) Objekt/Kunde/Gericht des Auftrags als
  /// Ziel-Optionen. Rechnet via Nominatim+OSRM, bietet Hin+Rück-Checkbox
  /// und übernimmt die km in das Mengen-Feld.
  Future<void> _oeffneKmRechner() async {
    final repo = ref.read(einstellungenRepositoryProvider);
    final firmaName = await repo.getOr('firma.name', '');
    final firmaAnschrift = await repo.getOr('firma.anschrift', '');
    if (firmaAnschrift.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Bitte zuerst unter Einstellungen → Profil die '
              'Firmen-Anschrift hinterlegen.')));
      return;
    }

    AuftraegeData? auftrag;
    KundenData? kunde;
    if (_auftragId != null) {
      final list =
          await ref.read(auftraegeRepositoryProvider).watchAll().first;
      final match =
          list.where((a) => a.auftrag.id == _auftragId).firstOrNull;
      auftrag = match?.auftrag;
      kunde = match?.kunde;
    }

    final jvegKmSatz = await repo.getOr('jveg.km_satz', '0.42');

    if (!mounted) return;
    final ergebnis = await showDialog<(double, String)>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _KmRechnerDialog(
        startLabel: firmaName.isEmpty ? firmaAnschrift : firmaName,
        startAdresse: firmaAnschrift,
        auftrag: auftrag,
        kunde: kunde,
      ),
    );
    if (ergebnis == null) return;
    final (km, beschreibung) = ergebnis;
    setState(() {
      _menge.text = km.toStringAsFixed(0);
      if (_einheit.text.trim().isEmpty) _einheit.text = 'km';
      if (_einzel.text.trim().isEmpty) _einzel.text = jvegKmSatz;
      if (_beschreibung.text.trim().isEmpty) {
        _beschreibung.text = 'Fahrt: $beschreibung';
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final menge = parseMengeOrFormel(_menge.text);
    final ep = parseMengeOrFormel(_einzel.text);
    final summe = menge * ep;
    final companion = AuslagenCompanion(
      id: _isEdit ? Value(widget.eintrag!.auslage.id) : const Value.absent(),
      auftragId: Value(_auftragId),
      datum: Value(_datum),
      art: Value(_art),
      kategorie: _nt(_kat),
      beschreibung: _nt(_beschreibung),
      menge: Value(menge),
      einheit: _nt(_einheit),
      einzelpreis: Value(ep),
      summe: Value(summe),
      notiz: _nt(_notiz),
      abgerechnet: Value(_abgerechnet),
    );
    try {
      await ref.read(auslagenRepositoryProvider).upsert(companion);
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
      title: _isEdit ? 'Auslage bearbeiten' : 'Neue Auslage',
      saving: _saving,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(auslagenRepositoryProvider)
              .delete(widget.eintrag!.auslage.id)
          : null,
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuftragPickerField(
                auftragId: _auftragId,
                onChanged: (id) => setState(() => _auftragId = id),
              ),
              const SizedBox(height: 12),
              Row3(
                a: DateField(
                    label: 'Datum',
                    value: _datum,
                    onChanged: (v) =>
                        setState(() => _datum = v ?? DateTime.now())),
                b: LabeledField(
                  'Art',
                  DropdownButtonFormField<String>(
                    initialValue: _art,
                    isDense: true,
                    items: [
                      for (final (key, label) in _artOptions)
                        DropdownMenuItem(value: key, child: Text(label)),
                    ],
                    onChanged: (v) =>
                        setState(() => _art = v ?? 'sonstiges'),
                  ),
                ),
                c: LabeledField(
                    'Kategorie', TextFormField(controller: _kat)),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Beschreibung',
                TextFormField(controller: _beschreibung),
              ),
              const SizedBox(height: 12),
              Row3(
                a: LabeledField(
                  'Menge',
                  Row(
                    children: [
                      Expanded(
                        child: FormelTextField(
                          controller: _menge,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                        ),
                      ),
                      if (_art == 'fahrt') ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message:
                              'Kilometer vom Firmensitz aus berechnen',
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.route, size: 20),
                            onPressed: _oeffneKmRechner,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                b: LabeledField(
                    'Einheit', TextFormField(controller: _einheit)),
                c: LabeledField(
                  'Einzelpreis (€)',
                  FormelTextField(
                    controller: _einzel,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Notiz',
                TextFormField(controller: _notiz, minLines: 2, maxLines: 4),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Checkbox(
                    value: _abgerechnet,
                    onChanged: (v) =>
                        setState(() => _abgerechnet = v ?? false)),
                const Text('bereits abgerechnet'),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// ------------- km-Rechner-Dialog -------------

enum _ZielTyp { objekt, kunde, gericht, frei }

class _KmRechnerDialog extends StatefulWidget {
  const _KmRechnerDialog({
    required this.startLabel,
    required this.startAdresse,
    required this.auftrag,
    required this.kunde,
  });
  final String startLabel;
  final String startAdresse;
  final AuftraegeData? auftrag;
  final KundenData? kunde;

  @override
  State<_KmRechnerDialog> createState() => _KmRechnerDialogState();
}

class _KmRechnerDialogState extends State<_KmRechnerDialog> {
  _ZielTyp _zielTyp = _ZielTyp.objekt;
  bool _hinRueck = true;
  bool _berechne = false;
  double? _einfacheKm;
  double? _dauerMin;
  String? _fehler;
  String? _zielBeschreibung;
  final _freieAdresseCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Vorauswahl: Objekt > Kunde > Gericht > frei
    if (_objektAdresse() != null) {
      _zielTyp = _ZielTyp.objekt;
    } else if (_kundenAdresse() != null) {
      _zielTyp = _ZielTyp.kunde;
    } else if ((widget.auftrag?.gericht ?? '').isNotEmpty) {
      _zielTyp = _ZielTyp.gericht;
    } else {
      _zielTyp = _ZielTyp.frei;
    }
  }

  @override
  void dispose() {
    _freieAdresseCtrl.dispose();
    super.dispose();
  }

  String? _objektAdresse() {
    final a = widget.auftrag;
    if (a == null) return null;
    final teile = <String>[
      if ((a.objektStrasse ?? '').trim().isNotEmpty) a.objektStrasse!,
      [
        if ((a.objektPlz ?? '').trim().isNotEmpty) a.objektPlz!,
        if ((a.objektOrt ?? '').trim().isNotEmpty) a.objektOrt!,
      ].join(' ').trim(),
    ].where((s) => s.trim().isNotEmpty).toList();
    if (teile.isEmpty) return null;
    return teile.join(', ');
  }

  String? _kundenAdresse() {
    final k = widget.kunde;
    if (k == null) return null;
    final teile = <String>[
      if ((k.strasse ?? '').trim().isNotEmpty) k.strasse!,
      [
        if ((k.plz ?? '').trim().isNotEmpty) k.plz!,
        if ((k.ort ?? '').trim().isNotEmpty) k.ort!,
      ].join(' ').trim(),
    ].where((s) => s.trim().isNotEmpty).toList();
    if (teile.isEmpty) return null;
    return teile.join(', ');
  }

  String _kundenLabel() {
    final k = widget.kunde;
    if (k == null) return 'Kunde (kein Auftrag gewählt)';
    final name = [k.vorname, k.nachname, k.firma]
        .where((s) => (s ?? '').isNotEmpty)
        .join(' ');
    return name.trim().isEmpty ? 'Auftraggeber' : name.trim();
  }

  String? _zielAdresse() => switch (_zielTyp) {
        _ZielTyp.objekt => _objektAdresse(),
        _ZielTyp.kunde => _kundenAdresse(),
        _ZielTyp.gericht => (widget.auftrag?.gericht ?? '').trim().isEmpty
            ? null
            : widget.auftrag!.gericht!.trim(),
        _ZielTyp.frei => _freieAdresseCtrl.text.trim().isEmpty
            ? null
            : _freieAdresseCtrl.text.trim(),
      };

  String _zielLabel() => switch (_zielTyp) {
        _ZielTyp.objekt => 'Objektadresse',
        _ZielTyp.kunde => _kundenLabel(),
        _ZielTyp.gericht =>
          widget.auftrag?.gericht ?? 'Gericht',
        _ZielTyp.frei => 'Freie Adresse',
      };

  Future<void> _berechnen() async {
    final ziel = _zielAdresse();
    if (ziel == null) {
      setState(() =>
          _fehler = 'Keine Zieladresse verfügbar — bitte eingeben.');
      return;
    }
    setState(() {
      _berechne = true;
      _fehler = null;
      _einfacheKm = null;
      _dauerMin = null;
      _zielBeschreibung = ziel;
    });

    try {
      final start = await adresseZuKoordinaten(widget.startAdresse);
      final zielCoord = await adresseZuKoordinaten(ziel);
      if (start == null) {
        setState(() => _fehler =
            'Start-Adresse konnte nicht geokodiert werden.');
        return;
      }
      if (zielCoord == null) {
        setState(
            () => _fehler = 'Ziel-Adresse konnte nicht geokodiert werden.');
        return;
      }
      final strecke = await routeKm(start, zielCoord);
      if (strecke == null) {
        setState(() => _fehler = 'Routenberechnung fehlgeschlagen.');
        return;
      }
      setState(() {
        _einfacheKm = strecke.kilometer;
        _dauerMin = strecke.dauerMinuten;
      });
    } catch (e) {
      setState(() => _fehler = 'Fehler: $e');
    } finally {
      if (mounted) setState(() => _berechne = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final km = _einfacheKm;
    final gesamt = km == null ? null : (_hinRueck ? km * 2 : km);
    final gerichtVorhanden =
        (widget.auftrag?.gericht ?? '').trim().isNotEmpty;

    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.route, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Kilometer berechnen',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context,
                            rootNavigator: true)
                        .pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Startpunkt', style: Theme.of(context).textTheme.labelSmall),
              Text(widget.startAdresse,
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 14),
              Text('Ziel', style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 4),
              _zielOption(_ZielTyp.objekt, 'Objektadresse',
                  _objektAdresse(), Icons.home_outlined),
              _zielOption(_ZielTyp.kunde, _kundenLabel(),
                  _kundenAdresse(), Icons.person_outline),
              _zielOption(_ZielTyp.gericht, 'Gericht',
                  gerichtVorhanden ? widget.auftrag!.gericht : null,
                  Icons.gavel_outlined),
              RadioListTile<_ZielTyp>(
                value: _ZielTyp.frei,
                groupValue: _zielTyp,
                dense: true,
                title: const Text('Freie Adresse',
                    style: TextStyle(fontSize: 13)),
                onChanged: (v) => setState(() => _zielTyp = v!),
              ),
              if (_zielTyp == _ZielTyp.frei)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 0, 8),
                  child: TextField(
                    controller: _freieAdresseCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Straße, PLZ Ort',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Row(children: [
                Checkbox(
                    value: _hinRueck,
                    onChanged: (v) =>
                        setState(() => _hinRueck = v ?? true)),
                const Expanded(
                  child: Text(
                    'Hin- und Rückfahrt berücksichtigen (× 2) — '
                    'nach §5 JVEG werden die tatsächlich gefahrenen km vergütet.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              if (_fehler != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_fehler!,
                      style: TextStyle(
                          fontSize: 12,
                          color: scheme.onErrorContainer)),
                ),
              if (km != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Einfache Strecke: ${km.toStringAsFixed(1)} km '
                          '(${_dauerMin?.toStringAsFixed(0) ?? "—"} Min)',
                          style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        _hinRueck
                            ? 'Hin + Rück: ${gesamt!.toStringAsFixed(0)} km'
                            : 'Einfach: ${gesamt!.toStringAsFixed(0)} km',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimaryContainer,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context,
                            rootNavigator: true)
                        .pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  if (km == null)
                    FilledButton.icon(
                      icon: _berechne
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : const Icon(Icons.route, size: 16),
                      label: Text(_berechne ? 'Rechne …' : 'Berechnen'),
                      onPressed: _berechne ? null : _berechnen,
                    )
                  else
                    FilledButton.icon(
                      icon: const Icon(Icons.check, size: 16),
                      label: Text(
                          '${gesamt!.toStringAsFixed(0)} km übernehmen'),
                      onPressed: () => Navigator.of(context,
                              rootNavigator: true)
                          .pop((gesamt, _zielBeschreibung ?? _zielLabel())),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _zielOption(_ZielTyp typ, String label, String? adresse,
      IconData icon) {
    final aktiv = adresse != null && adresse.isNotEmpty;
    return RadioListTile<_ZielTyp>(
      value: typ,
      groupValue: _zielTyp,
      dense: true,
      title: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: aktiv ? null : Colors.grey)),
          ),
        ],
      ),
      subtitle: adresse == null
          ? const Text('— nicht hinterlegt —',
              style: TextStyle(fontSize: 11, color: Colors.grey))
          : Text(adresse, style: const TextStyle(fontSize: 11)),
      onChanged: aktiv ? (v) => setState(() => _zielTyp = v!) : null,
    );
  }
}
