import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../features/system/benutzer/benutzer_repository.dart';
import '../../../features/system/einstellungen/einstellungen_repository.dart';
import '../../../features/system/einstellungen/nummernkreis_service.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/file_upload_section.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../kunden/kunden_picker.dart';
import 'auftraege_repository.dart';

/// Öffnet den Stammdaten-Dialog für eine Akte / einen Auftrag.
///
/// Rückgabe: ID der gespeicherten Akte, oder `null` bei Abbruch.
Future<int?> showAuftragFormDialog(
  BuildContext context, {
  AuftraegeData? auftrag,
}) {
  return showDialog<int>(
    context: context,
    useRootNavigator: true,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 860),
        child: _AuftragFormDialog(auftrag: auftrag),
      ),
    ),
  );
}

class _AuftragFormDialog extends ConsumerStatefulWidget {
  const _AuftragFormDialog({this.auftrag});
  final AuftraegeData? auftrag;

  @override
  ConsumerState<_AuftragFormDialog> createState() =>
      _AuftragFormDialogState();
}

class _AuftragFormDialogState extends ConsumerState<_AuftragFormDialog>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TabController _tabs;

  // --- Zustände ---
  late AuftragArt _art;
  late AuftragStatus _status;
  int? _kundeId;
  String? _aufgabenJson;

  // Termine
  DateTime? _eingangAm;
  DateTime? _auftragAm;
  DateTime? _ortsterminAm;
  DateTime? _fristAm;
  DateTime? _abschlussAm;
  DateTime? _akteneingangAm;
  DateTime? _bb1;
  DateTime? _bb2;
  DateTime? _bb3;

  // Controller
  late final _aktenzeichen = _tec(widget.auftrag?.aktenzeichen);
  late final _azExtern = _tec(widget.auftrag?.azExtern);
  late final _betreff = _tec(widget.auftrag?.betreff);
  late final _bezeichnung = _tec(widget.auftrag?.bezeichnung);
  late final _objStrasse = _tec(widget.auftrag?.objektStrasse);
  late final _objPlz = _tec(widget.auftrag?.objektPlz);
  late final _objOrt = _tec(widget.auftrag?.objektOrt);
  late final _baujahr = _tec(widget.auftrag?.baujahr);
  late final _sachgebiet = _tec(widget.auftrag?.sachgebiet);
  late final _objektart = _tec(widget.auftrag?.objektart);
  late final _kategorie = _tec(widget.auftrag?.kategorie);
  late final _gericht = _tec(widget.auftrag?.gericht);
  late final _gerichtsort = _tec(widget.auftrag?.gerichtsort);
  late final _gerichtsAz = _tec(widget.auftrag?.gerichtsAktenzeichen);
  late final _verfahrensart = _tec(widget.auftrag?.verfahrensart);
  late final _ausfertigungen =
      _tec(widget.auftrag?.anzahlAusfertigungen?.toString());
  late final _aktenSeitenVon =
      _tec(widget.auftrag?.aktenSeitenVon?.toString());
  late final _aktenSeitenBis =
      _tec(widget.auftrag?.aktenSeitenBis?.toString());
  late final _richter = _tec(widget.auftrag?.richter);
  late final _richterAnrede = _tec(widget.auftrag?.richterAnrede);
  late final _richterBrief = _tec(widget.auftrag?.richterBriefanrede);
  late final _stundensatz = _tec(_money(widget.auftrag?.stundensatz));
  late final _kostenLimit = _tec(_money(widget.auftrag?.kostenLimit));
  late final _kostenvorschuss =
      _tec(_money(widget.auftrag?.kostenvorschuss));
  late final _aufwandSchaetzung =
      _tec(widget.auftrag?.aufwandSchaetzung?.toStringAsFixed(1));
  late final _honorargruppe = _tec(widget.auftrag?.honorargruppe);
  late final _notiz = _tec(widget.auftrag?.notiz);

  bool _saving = false;
  UploadedFile? _beweisbeschlussFile;
  UploadedFile? _objektFoto;

  TextEditingController _tec(String? v) =>
      TextEditingController(text: v ?? '');

  static const _objektarten = [
    'Einfamilienhaus',
    'Doppelhaushälfte',
    'Reihenhaus',
    'Mehrfamilienhaus',
    'Eigentumswohnung',
    'Gewerbeeinheit',
    'Bürogebäude',
    'Werkstatt / Halle',
    'Sonstiges',
  ];

  static const _kategorien = [
    'Schadensgutachten',
    'Mängelgutachten',
    'Bewertungsgutachten',
    'Beweissicherung',
    'Bauzustandsgutachten',
    'Wohnflächenberechnung',
    'Energetische Bewertung',
    'Sonstiges',
  ];

  static const _honorargruppen = ['M1', 'M2', 'M3', 'Sonstige'];

  static const _verfahrensarten = [
    'Zivilverfahren',
    'Selbstständiges Beweisverfahren',
    'Schiedsgutachten',
    'Strafverfahren',
    'Sonstiges',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    final a = widget.auftrag;
    _art = AuftragArtX.fromDb(a?.art);
    _aufgabenJson = a?.aufgabenJson;
    _status = AuftragStatusX.fromDb(a?.status);
    _kundeId = a?.kundeId;
    _eingangAm = a?.eingangAm;
    _auftragAm = a?.auftragAm;
    _ortsterminAm = a?.ortsterminAm;
    _fristAm = a?.fristAm;
    _abschlussAm = a?.abschlussAm;
    _akteneingangAm = a?.akteneingangAm;
    _bb1 = a?.beweisbeschluss1;
    _bb2 = a?.beweisbeschluss2;
    _bb3 = a?.beweisbeschluss3;
    if (a?.beweisbeschlussStorageUrl != null &&
        a!.beweisbeschlussStorageUrl!.isNotEmpty) {
      _beweisbeschlussFile = UploadedFile(
        storageUrl: a.beweisbeschlussStorageUrl!,
        dateiname: a.beweisbeschlussDateiname ?? 'Beweisbeschluss',
        mimeType: a.beweisbeschlussMimeType,
        groesse: a.beweisbeschlussGroesse,
      );
    }
    if (a?.objektFotoStorageUrl != null &&
        a!.objektFotoStorageUrl!.isNotEmpty) {
      _objektFoto = UploadedFile(
        storageUrl: a.objektFotoStorageUrl!,
        dateiname: a.objektFotoDateiname ?? 'Objekt-Foto',
        mimeType: 'image/jpeg',
      );
    }
    if (a == null) _prefill();
  }

  Future<void> _prefill() async {
    final zeichen = await ref
        .read(nummernkreisServiceProvider)
        .previewNumber(NummernkreisTyp.akte);
    if (mounted && _aktenzeichen.text.isEmpty) {
      _aktenzeichen.text = zeichen;
    }
    if (_stundensatz.text.isEmpty) {
      final settingSatz = await ref
          .read(einstellungenRepositoryProvider)
          .getDouble(SettingsKeys.standardStundensatz);
      final benutzer = await ref.read(benutzerRepositoryProvider).getActive();
      final satz = settingSatz ?? benutzer?.standardStundensatz;
      if (mounted && satz != null) {
        _stundensatz.text = satz.toStringAsFixed(2);
      }
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [
      _aktenzeichen, _azExtern, _betreff, _bezeichnung,
      _objStrasse, _objPlz, _objOrt, _baujahr, _sachgebiet,
      _objektart, _kategorie,
      _gericht, _gerichtsort, _gerichtsAz, _verfahrensart,
      _ausfertigungen, _aktenSeitenVon, _aktenSeitenBis,
      _richter, _richterAnrede, _richterBrief,
      _stundensatz, _kostenLimit, _kostenvorschuss,
      _aufwandSchaetzung, _honorargruppe, _notiz,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.auftrag != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    // Nummernkreis: wenn neue Akte und die Nummer im Feld noch der Preview
    // entspricht (oder leer ist), Zähler jetzt inkrementieren.
    if (!_isEdit) {
      final preview = await ref
          .read(nummernkreisServiceProvider)
          .previewNumber(NummernkreisTyp.akte);
      final currentText = _aktenzeichen.text.trim();
      if (currentText.isEmpty || currentText == preview) {
        final neu = await ref
            .read(nummernkreisServiceProvider)
            .nextNumber(NummernkreisTyp.akte);
        _aktenzeichen.text = neu;
      }
    }

    final companion = AuftraegeCompanion(
      id: _isEdit ? Value(widget.auftrag!.id) : const Value.absent(),
      aktenzeichen: _nt(_aktenzeichen),
      azExtern: _nt(_azExtern),
      aufgabenJson:
          Value(_aufgabenJson == null || _aufgabenJson!.isEmpty ? null : _aufgabenJson),
      art: Value(_art.dbValue),
      status: Value(_status.dbValue),
      kundeId: Value(_kundeId),
      betreff: _nt(_betreff),
      bezeichnung: _nt(_bezeichnung),
      objektStrasse: _nt(_objStrasse),
      objektPlz: _nt(_objPlz),
      objektOrt: _nt(_objOrt),
      objektart: _nt(_objektart),
      baujahr: _nt(_baujahr),
      sachgebiet: _nt(_sachgebiet),
      kategorie: _nt(_kategorie),
      honorargruppe: _nt(_honorargruppe),
      gerichtsAktenzeichen: _nt(_gerichtsAz),
      gericht: _nt(_gericht),
      gerichtsort: _nt(_gerichtsort),
      verfahrensart: _nt(_verfahrensart),
      anzahlAusfertigungen: Value(int.tryParse(_ausfertigungen.text.trim())),
      aktenSeitenVon: Value(int.tryParse(_aktenSeitenVon.text.trim())),
      aktenSeitenBis: Value(int.tryParse(_aktenSeitenBis.text.trim())),
      richter: _nt(_richter),
      richterAnrede: _nt(_richterAnrede),
      richterBriefanrede: _nt(_richterBrief),
      eingangAm: Value(_eingangAm),
      auftragAm: Value(_auftragAm),
      ortsterminAm: Value(_ortsterminAm),
      fristAm: Value(_fristAm),
      abschlussAm: Value(_abschlussAm),
      akteneingangAm: Value(_akteneingangAm),
      beweisbeschluss1: Value(_bb1),
      beweisbeschluss2: Value(_bb2),
      beweisbeschluss3: Value(_bb3),
      stundensatz: _nm(_stundensatz),
      kostenLimit: _nm(_kostenLimit),
      kostenvorschuss: _nm(_kostenvorschuss),
      aufwandSchaetzung: _nm(_aufwandSchaetzung),
      notiz: _nt(_notiz),
      beweisbeschlussStorageUrl: Value(_beweisbeschlussFile?.storageUrl),
      beweisbeschlussDateiname: Value(_beweisbeschlussFile?.dateiname),
      beweisbeschlussMimeType: Value(_beweisbeschlussFile?.mimeType),
      beweisbeschlussGroesse: Value(_beweisbeschlussFile?.groesse),
      objektFotoStorageUrl: Value(_objektFoto?.storageUrl),
      objektFotoDateiname: Value(_objektFoto?.dateiname),
      updatedAt: Value(DateTime.now()),
    );
    try {
      final id =
          await ref.read(auftraegeRepositoryProvider).upsert(companion);
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(id);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
        );
      }
    }
  }

  Value<String?> _nt(TextEditingController c) {
    final v = c.text.trim();
    return Value(v.isEmpty ? null : v);
  }

  Value<double?> _nm(TextEditingController c) {
    final v = c.text.trim().replaceAll(',', '.');
    if (v.isEmpty) return const Value(null);
    return Value(double.tryParse(v));
  }

  static String _money(double? v) => v == null ? '' : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DialogHeader(
          title: _isEdit
              ? 'Akte bearbeiten · ${widget.auftrag!.aktenzeichen ?? ''}'
              : 'Neue Akte',
          icon: Icons.folder_open_outlined,
          onClose: _saving
              ? null
              : () => Navigator.of(context, rootNavigator: true).pop(null),
        ),
        if (_isEdit)
          _GedruckteDocsHinweis(auftragId: widget.auftrag!.id),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Allgemein'),
            Tab(text: 'Objekt'),
            Tab(text: 'Gericht'),
            Tab(text: 'Termine & Honorar'),
            Tab(text: 'Aufgaben & Geräte'),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: Form(
            key: _formKey,
            child: TabBarView(
              controller: _tabs,
              children: [
                _allgemeinTab(),
                _objektTab(),
                _gerichtTab(),
                _termineTab(),
                _aufgabenGeraeteTab(),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        DialogFooter(
          onCancel: () =>
              Navigator.of(context, rootNavigator: true).pop(null),
          onSave: _save,
          saving: _saving,
        ),
      ],
    );
  }

  // -------------------- Tab 1 --------------------
  Widget _allgemeinTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row2(
            left: LabeledField(
              'Art',
              DropdownButtonFormField<AuftragArt>(
                initialValue: _art,
                isDense: true,
                items: [
                  for (final a in AuftragArt.values)
                    DropdownMenuItem(value: a, child: Text(a.label)),
                ],
                onChanged: (v) =>
                    setState(() => _art = v ?? AuftragArt.privat),
              ),
            ),
            right: LabeledField(
              'Status',
              DropdownButtonFormField<AuftragStatus>(
                initialValue: _status,
                isDense: true,
                items: [
                  for (final s in AuftragStatus.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (s) =>
                    setState(() => _status = s ?? AuftragStatus.offen),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row2(
            flex: const (2, 3),
            left: LabeledField(
              'Aktenzeichen (intern)',
              TextFormField(
                controller: _aktenzeichen,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Erforderlich' : null,
              ),
            ),
            right: LabeledField(
              'Geschäftszeichen Auftraggeber',
              TextFormField(controller: _azExtern),
            ),
          ),
          const SizedBox(height: 12),
          KundenPickerField(
            kundeId: _kundeId,
            onChanged: (id) => setState(() => _kundeId = id),
          ),
          const SizedBox(height: 12),
          LabeledField(
            'Betreff / Beweisthema',
            TextFormField(controller: _betreff),
          ),
          const SizedBox(height: 12),
          LabeledField(
            'Kurzbezeichnung (intern)',
            TextFormField(controller: _bezeichnung),
          ),
          const SizedBox(height: 12),
          Row2(
            left: LabeledField(
              'Sachgebiet',
              TextFormField(controller: _sachgebiet),
            ),
            right: LabeledField(
              'Kategorie',
              DropdownButtonFormField<String>(
                initialValue: _kategorien.contains(_kategorie.text)
                    ? _kategorie.text
                    : null,
                isDense: true,
                items: [
                  for (final k in _kategorien)
                    DropdownMenuItem(value: k, child: Text(k)),
                ],
                onChanged: (v) => setState(() => _kategorie.text = v ?? ''),
              ),
            ),
          ),
          const SizedBox(height: 12),
          LabeledField(
            'Notizen / Bemerkungen',
            TextFormField(controller: _notiz, minLines: 3, maxLines: 8),
          ),
        ],
      ),
    );
  }

  // -------------------- Tab 2 --------------------
  Widget _objektTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Objektadresse',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          LabeledField('Straße + Hausnr.',
              TextFormField(controller: _objStrasse)),
          const SizedBox(height: 12),
          Row2(
            flex: const (1, 3),
            left: LabeledField('PLZ', TextFormField(controller: _objPlz)),
            right: LabeledField('Ort', TextFormField(controller: _objOrt)),
          ),
          const SizedBox(height: 20),
          Text('Objekt-Details',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row2(
            left: LabeledField(
              'Objektart',
              DropdownButtonFormField<String>(
                initialValue: _objektarten.contains(_objektart.text)
                    ? _objektart.text
                    : null,
                isDense: true,
                items: [
                  for (final o in _objektarten)
                    DropdownMenuItem(value: o, child: Text(o)),
                ],
                onChanged: (v) =>
                    setState(() => _objektart.text = v ?? ''),
              ),
            ),
            right: LabeledField(
              'Baujahr',
              TextFormField(
                controller: _baujahr,
                keyboardType: TextInputType.number,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          FileUploadSection(
            title: 'Übersichts-/Objektfoto',
            storagePrefix: 'auftraege/objektfotos',
            kind: UploadKind.image,
            file: _objektFoto,
            hint: 'Hauptbild des begutachteten Objekts.',
            onChanged: (f) => setState(() => _objektFoto = f),
          ),
        ],
      ),
    );
  }

  // -------------------- Tab 3 --------------------
  Widget _gerichtTab() {
    // Gerichts-Tab auch für Schiedsgutachten und Beweissicherung aktiv.
    if (_art == AuftragArt.privat) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            'Dieser Auftrag ist als «Privatgutachten» markiert — '
            'Gerichtsfelder werden ausgeblendet.\n\n'
            'Ändere auf Reiter «Allgemein» die Art auf «Gerichtsgutachten», '
            'um diese Felder zu nutzen.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row2(
            left: LabeledField('Gericht',
                TextFormField(controller: _gericht)),
            right: LabeledField('Gerichtsort',
                TextFormField(controller: _gerichtsort)),
          ),
          const SizedBox(height: 12),
          Row2(
            left: LabeledField('Gerichtliches Aktenzeichen',
                TextFormField(controller: _gerichtsAz)),
            right: LabeledField(
              'Verfahrensart',
              DropdownButtonFormField<String>(
                initialValue: _verfahrensarten.contains(_verfahrensart.text)
                    ? _verfahrensart.text
                    : null,
                isDense: true,
                items: [
                  for (final v in _verfahrensarten)
                    DropdownMenuItem(value: v, child: Text(v)),
                ],
                onChanged: (v) =>
                    setState(() => _verfahrensart.text = v ?? ''),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Beweisbeschlüsse',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row3(
            a: DateField(
                label: '1. Beweisbeschluss',
                value: _bb1,
                onChanged: (v) => setState(() => _bb1 = v)),
            b: DateField(
                label: '2. Beweisbeschluss',
                value: _bb2,
                onChanged: (v) => setState(() => _bb2 = v)),
            c: DateField(
                label: '3. Beweisbeschluss',
                value: _bb3,
                onChanged: (v) => setState(() => _bb3 = v)),
          ),
          const SizedBox(height: 12),
          FileUploadSection(
            title: 'Beweisbeschluss (PDF)',
            storagePrefix: 'auftraege/beweisbeschluesse',
            kind: UploadKind.pdf,
            file: _beweisbeschlussFile,
            hint: 'Originaler Beweisbeschluss als PDF-Scan.',
            onChanged: (f) => setState(() => _beweisbeschlussFile = f),
          ),
          const SizedBox(height: 16),
          Text('Gerichtsakte & Ausfertigungen',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row3(
            a: DateField(
              label: 'Akteneingang am',
              value: _akteneingangAm,
              onChanged: (v) => setState(() => _akteneingangAm = v),
            ),
            b: LabeledField(
              'Akte-Seiten von',
              TextFormField(
                controller: _aktenSeitenVon,
                keyboardType: TextInputType.number,
              ),
            ),
            c: LabeledField(
              'Akte-Seiten bis',
              TextFormField(
                controller: _aktenSeitenBis,
                keyboardType: TextInputType.number,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row2(
            flex: const (1, 3),
            left: LabeledField(
              'Ausfertigungen',
              TextFormField(
                controller: _ausfertigungen,
                keyboardType: TextInputType.number,
              ),
            ),
            right: LabeledField(
              'Kosten lt. Beweisbeschluss (€)',
              TextFormField(
                controller: _kostenLimit,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Richter/in',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row3(
            a: LabeledField(
              'Anrede',
              TextFormField(controller: _richterAnrede),
            ),
            b: LabeledField(
              'Name',
              TextFormField(controller: _richter),
            ),
            c: LabeledField(
              'Briefanrede',
              TextFormField(controller: _richterBrief),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------- Tab 4 --------------------
  Widget _termineTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Termine', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row3(
            a: DateField(
              label: 'Eingang',
              value: _eingangAm,
              onChanged: (v) => setState(() => _eingangAm = v),
            ),
            b: DateField(
              label: 'Auftrag vom',
              value: _auftragAm,
              onChanged: (v) => setState(() => _auftragAm = v),
            ),
            c: DateField(
              label: 'Nächster Ortstermin',
              value: _ortsterminAm,
              onChanged: (v) => setState(() => _ortsterminAm = v),
            ),
          ),
          const SizedBox(height: 12),
          Row2(
            left: DateField(
              label: 'Fertigstellung bis',
              value: _fristAm,
              onChanged: (v) => setState(() => _fristAm = v),
            ),
            right: DateField(
              label: 'Abgeschlossen am',
              value: _abschlussAm,
              onChanged: (v) => setState(() => _abschlussAm = v),
            ),
          ),
          const SizedBox(height: 20),
          Text('Honorar', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row3(
            a: LabeledField(
              'Stundensatz (€)',
              TextFormField(
                controller: _stundensatz,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            b: LabeledField(
              'Voraussichtl. Aufwand (h)',
              TextFormField(
                controller: _aufwandSchaetzung,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            c: LabeledField(
              'JVEG-Honorargruppe',
              DropdownButtonFormField<String>(
                initialValue: _honorargruppen.contains(_honorargruppe.text)
                    ? _honorargruppe.text
                    : null,
                isDense: true,
                items: [
                  for (final h in _honorargruppen)
                    DropdownMenuItem(value: h, child: Text(h)),
                ],
                onChanged: (v) =>
                    setState(() => _honorargruppe.text = v ?? ''),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row2(
            left: LabeledField(
              'Kostenlimit (€)',
              TextFormField(
                controller: _kostenLimit,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            right: LabeledField(
              'Kostenvorschuss (€)',
              TextFormField(
                controller: _kostenvorschuss,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------- Tab 5 (Aufgaben & eingesetzte Geräte) --------------------
  Widget _aufgabenGeraeteTab() {
    final auftragId = widget.auftrag?.id;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Aufgaben-Liste',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _AufgabenEditor(
            initialJson: widget.auftrag?.aufgabenJson,
            onChanged: (json) => _aufgabenJson = json,
          ),
          const SizedBox(height: 24),
          Text('Eingesetzte Messgeräte',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Wird im Gutachten als Anlage gelistet. Verknüpfungen werden erst nach dem Speichern des Auftrags persistiert.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          if (auftragId == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Geräte können zugeordnet werden, sobald der Auftrag gespeichert ist.',
              ),
            )
          else
            _GeraeteZuordnungView(auftragId: auftragId),
        ],
      ),
    );
  }
}

/// Banner, der bei gedruckten Angeboten/Rechnungen daran erinnert, dass
/// bereits archivierte PDFs unverändert bleiben — neue Stammdaten wirken nur
/// auf zukünftige Dokumente.
class _GedruckteDocsHinweis extends ConsumerWidget {
  const _GedruckteDocsHinweis({required this.auftragId});
  final int auftragId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    return StreamBuilder<int>(
      stream: (db.select(db.rechnungen)
            ..where((t) => t.auftragId.equals(auftragId))
            ..where((t) => t.pdfStorageUrl.isNotNull()))
          .watch()
          .map((rows) => rows.length),
      builder: (_, snap) {
        final n = snap.data ?? 0;
        if (n == 0) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: scheme.tertiaryContainer,
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: scheme.onTertiaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Zu dieser Akte gibt es bereits $n archivierte Rechnungs-PDF'
                  '${n == 1 ? "" : "s"}. '
                  'Änderungen an den Stammdaten wirken nur auf zukünftige '
                  'Dokumente — bestehende PDFs bleiben wie sie sind.',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onTertiaryContainer),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// ---------------- Aufgaben-Editor ----------------

class _AufgabenEditor extends StatefulWidget {
  const _AufgabenEditor({required this.initialJson, required this.onChanged});
  final String? initialJson;
  final ValueChanged<String?> onChanged;
  @override
  State<_AufgabenEditor> createState() => _AufgabenEditorState();
}

class _AufgabenItem {
  String text;
  bool done;
  DateTime? doneAt;
  _AufgabenItem({required this.text, this.done = false, this.doneAt});
}

class _AufgabenEditorState extends State<_AufgabenEditor> {
  late List<_AufgabenItem> _items;
  final _newCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _items = _parse(widget.initialJson);
  }

  @override
  void dispose() {
    _newCtrl.dispose();
    super.dispose();
  }

  static List<_AufgabenItem> _parse(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => _AufgabenItem(
                text: (e['text'] as String?) ?? '',
                done: (e['done'] as bool?) ?? false,
                doneAt: e['doneAt'] == null
                    ? null
                    : DateTime.tryParse(e['doneAt'].toString()),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  String _encode() => jsonEncode(_items
      .map((i) => {
            'text': i.text,
            'done': i.done,
            if (i.doneAt != null) 'doneAt': i.doneAt!.toIso8601String(),
          })
      .toList());

  void _emit() => widget.onChanged(_items.isEmpty ? null : _encode());

  void _add() {
    final t = _newCtrl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _items.add(_AufgabenItem(text: t));
      _newCtrl.clear();
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newCtrl,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Neue Aufgabe (Enter zum Hinzufügen)',
                ),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Hinzufügen'),
              onPressed: _add,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('Noch keine Aufgaben.'),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _items.length; i++) _row(context, i),
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, int i) {
    final item = _items[i];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: item.done,
            onChanged: (v) {
              setState(() {
                item.done = v ?? false;
                item.doneAt = item.done ? DateTime.now() : null;
              });
              _emit();
            },
          ),
          Expanded(
            child: Text(
              item.text,
              style: TextStyle(
                decoration:
                    item.done ? TextDecoration.lineThrough : null,
                color: item.done
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : null,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Löschen',
            onPressed: () {
              setState(() => _items.removeAt(i));
              _emit();
            },
          ),
        ],
      ),
    );
  }
}

/// ---------------- Geräte-Zuordnung ----------------

class _GeraeteZuordnungView extends ConsumerStatefulWidget {
  const _GeraeteZuordnungView({required this.auftragId});
  final int auftragId;
  @override
  ConsumerState<_GeraeteZuordnungView> createState() =>
      _GeraeteZuordnungViewState();
}

class _GeraeteZuordnungViewState
    extends ConsumerState<_GeraeteZuordnungView> {
  List<int> _zugeordnet = [];
  List<GeraeteData> _alleGeraete = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDatabaseProvider);
    final geraete = await db.select(db.geraete).get();
    final linked = await (db.select(db.auftraegeGeraete)
          ..where((t) => t.auftragId.equals(widget.auftragId)))
        .get();
    if (!mounted) return;
    setState(() {
      _alleGeraete = geraete;
      _zugeordnet = linked.map((e) => e.geraetId).toList();
      _loading = false;
    });
  }

  Future<void> _toggle(GeraeteData g, bool an) async {
    final db = ref.read(appDatabaseProvider);
    if (an) {
      await db.into(db.auftraegeGeraete).insert(
          AuftraegeGeraeteCompanion.insert(
              auftragId: widget.auftragId, geraetId: g.id));
    } else {
      await (db.delete(db.auftraegeGeraete)
            ..where((t) => t.auftragId.equals(widget.auftragId))
            ..where((t) => t.geraetId.equals(g.id)))
          .go();
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final aktiv = _alleGeraete.where((g) => g.aktiv).toList();
    if (aktiv.isEmpty) {
      return const Text('Noch keine Geräte im Stamm. '
          'Lege sie unter „Werkzeuge → Geräte" an.');
    }
    return Container(
      decoration: BoxDecoration(
        border:
            Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          for (final g in aktiv) ...[
            CheckboxListTile(
              dense: true,
              value: _zugeordnet.contains(g.id),
              onChanged: (v) => _toggle(g, v ?? false),
              title: Text(g.bezeichnung),
              subtitle: Text([
                if ((g.hersteller ?? '').isNotEmpty) g.hersteller,
                if ((g.modell ?? '').isNotEmpty) g.modell,
                if ((g.inventarNr ?? '').isNotEmpty) 'Inv. ${g.inventarNr}',
              ].whereType<String>().join(' · ')),
            ),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}
