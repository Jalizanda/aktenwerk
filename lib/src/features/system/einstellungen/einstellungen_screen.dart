import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_theme.dart';
import '../konten/datev_export.dart';
import '../sync/sync_section.dart';
import 'demo_seed_section.dart';
import 'einstellungen_repository.dart';
import 'google_calendar_section.dart';
import 'stammdaten_seed.dart';

class EinstellungenScreen extends ConsumerWidget {
  const EinstellungenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(einstellungenProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (map) =>
          _EinstellungenForm(key: ValueKey(map.length), values: map),
    );
  }
}

class _EinstellungenForm extends ConsumerStatefulWidget {
  const _EinstellungenForm({super.key, required this.values});
  final Map<String, String> values;

  @override
  ConsumerState<_EinstellungenForm> createState() =>
      _EinstellungenFormState();
}

class _EinstellungenFormState
    extends ConsumerState<_EinstellungenForm> {
  // ---------- Stammdaten ----------
  late final _firmaName = _tec(SettingsKeys.firmaName, '');
  late final _firmaTitel = _tec(SettingsKeys.firmaTitel, '');
  late final _firmaAnschrift = _tec(SettingsKeys.firmaAnschrift, '');
  late final _firmaTelefon = _tec(SettingsKeys.firmaTelefon, '');
  late final _firmaEmail = _tec(SettingsKeys.firmaEmail, '');
  late final _firmaWebsite = _tec(SettingsKeys.firmaWebsite, '');
  late final _bestellung1 = _tec(SettingsKeys.firmaBestellung1, '');
  late final _bestellung2 = _tec(SettingsKeys.firmaBestellung2, '');

  // ---------- Steuer ----------
  late final _ustId = _tec(SettingsKeys.steuerUstId, '');
  late final _steuerNr = _tec(SettingsKeys.steuerNr, '');
  late String _kleinunternehmer;

  // ---------- Bank ----------
  late final _bankInhaber = _tec(SettingsKeys.bankInhaber, '');
  late final _bankName = _tec(SettingsKeys.bankName, '');
  late final _iban = _tec(SettingsKeys.bankIban, '');
  late final _bic = _tec(SettingsKeys.bankBic, '');

  // ---------- Honorar ----------
  late final _satz = _tec(SettingsKeys.standardStundensatz, '95');
  late final _satzJveg = _tec(SettingsKeys.stundensatzJveg, '130');
  late final _ust = _tec(SettingsKeys.standardUstSatz, '19');
  late final _zahlungsziel =
      _tec(SettingsKeys.standardZahlungszielTage, '14');

  // ---------- JVEG ----------
  late final _jvegKm = _tec(SettingsKeys.jvegKmSatz, '0.42');
  late final _jvegSchreib = _tec(SettingsKeys.jvegSchreibsatz, '1.80');
  late final _jvegKopieSw = _tec(SettingsKeys.jvegKopieSw, '0.50');
  late final _jvegKopieFarbe = _tec(SettingsKeys.jvegKopieFarbe, '1.00');
  late final _jvegFotoErst = _tec(SettingsKeys.jvegLichtbildErstes, '2.00');
  late final _jvegFotoWeit = _tec(SettingsKeys.jvegLichtbildWeitere, '1.00');

  // ---------- Nummernkreise ----------
  late final _nkAkte = _tec(SettingsKeys.nummernkreisAktenzeichen, '{YYYY}-{NNN}');
  late final _nkAkteNext =
      _tec(SettingsKeys.nummernkreisAktenzeichenNaechste, '1');
  late String _nkAkteReset;

  late final _nkRn =
      _tec(SettingsKeys.nummernkreisRechnung, 'R{YYYY}-{NNN}');
  late final _nkRnNext = _tec(SettingsKeys.nummernkreisRechnungNaechste, '1');
  late String _nkRnReset;

  late final _nkAng =
      _tec(SettingsKeys.nummernkreisAngebot, 'A{YYYY}-{NNN}');
  late final _nkAngNext = _tec(SettingsKeys.nummernkreisAngebotNaechste, '1');
  late String _nkAngReset;

  late final _nkGut =
      _tec(SettingsKeys.nummernkreisGutachten, '{aktenzeichen}-G{N}');
  late final _nkGutNext = _tec(SettingsKeys.nummernkreisGutachtenNaechste, '1');
  late String _nkGutReset;

  late final _nkFB =
      _tec(SettingsKeys.nummernkreisFortbildung, 'FB{YYYY}-{NN}');
  late final _nkFBNext =
      _tec(SettingsKeys.nummernkreisFortbildungNaechste, '1');
  late String _nkFBReset;

  // ---------- Texte ----------
  late final _rnFoot = _tec(SettingsKeys.rechnungFusstext, '');
  late final _rnSchluss = _tec(SettingsKeys.rechnungSchlusstext,
      'Bitte überweisen Sie den Rechnungsbetrag innerhalb des Zahlungsziels auf das unten genannte Konto. Vielen Dank für Ihren Auftrag.');
  late final _angFoot = _tec(SettingsKeys.angebotFusstext, '');

  // ---------- Logo ----------
  String? _logoBase64;
  String? _logoMime;

  // ---------- Siegel ----------
  String? _siegelBase64;
  String? _siegelMime;
  String _siegelPosition = 'unten_rechts';
  late final _siegelBehoerde =
      _tec(SettingsKeys.siegelBestellBehoerde, '');
  late final _siegelNr = _tec(SettingsKeys.siegelBestellNr, '');
  late final _siegelGueltigBis =
      _tec(SettingsKeys.siegelGueltigBis, '');
  String? _unterschriftBase64;
  String? _unterschriftMime;

  // ---------- E-Rechnung + Kalkulation ----------
  late final _leitwegId = _tec(SettingsKeys.leitwegId, '');
  late final _internerKostensatz =
      _tec(SettingsKeys.internerKostensatz, '65');

  // ---------- Tätigkeitsbericht IHK/HWK ----------
  late final _tbEmpfaenger = _tec(
      SettingsKeys.taetigkeitBerichtEmpfaenger,
      'IHK Düsseldorf\nErnst-Schneider-Platz 1\n40212 Düsseldorf');
  late final _tbVorwort =
      _tec(SettingsKeys.taetigkeitBerichtVorwort, '');
  late final _tbEides = _tec(
      SettingsKeys.taetigkeitBerichtEidesstatt,
      'Ich versichere, dass die vorstehenden Angaben vollständig und '
          'wahrheitsgemäß sind. Die im Berichtsjahr durchgeführten Gutachten '
          'wurden unparteiisch, weisungsfrei und nach bestem Wissen und '
          'Gewissen erstellt.');

  String _theme = 'system';
  String _datevSkr = 'SKR03';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _theme = widget.values[SettingsKeys.theme] ?? 'system';
    _datevSkr = widget.values[SettingsKeys.datevKontenrahmen] ?? 'SKR03';
    _kleinunternehmer =
        widget.values[SettingsKeys.steuerKleinunternehmer] ?? 'nein';
    _nkAkteReset =
        widget.values[SettingsKeys.nummernkreisAktenzeichenReset] ?? 'nie';
    _nkRnReset =
        widget.values[SettingsKeys.nummernkreisRechnungReset] ?? 'jahr';
    _nkAngReset =
        widget.values[SettingsKeys.nummernkreisAngebotReset] ?? 'jahr';
    _nkGutReset =
        widget.values[SettingsKeys.nummernkreisGutachtenReset] ?? 'nie';
    _nkFBReset =
        widget.values[SettingsKeys.nummernkreisFortbildungReset] ?? 'jahr';
    final logo = widget.values[SettingsKeys.firmaLogoBase64];
    _logoBase64 = (logo == null || logo.isEmpty) ? null : logo;
    _logoMime = widget.values[SettingsKeys.firmaLogoMime];
    final siegel = widget.values[SettingsKeys.siegelBase64];
    _siegelBase64 = (siegel == null || siegel.isEmpty) ? null : siegel;
    _siegelMime = widget.values[SettingsKeys.siegelMime];
    _siegelPosition =
        widget.values[SettingsKeys.siegelPosition] ?? 'unten_rechts';
    final unterschrift = widget.values[SettingsKeys.unterschriftBase64];
    _unterschriftBase64 =
        (unterschrift == null || unterschrift.isEmpty) ? null : unterschrift;
    _unterschriftMime = widget.values[SettingsKeys.unterschriftMime];
  }

  TextEditingController _tec(String key, String fallback) {
    final v = widget.values[key];
    return TextEditingController(
        text: v != null && v.isNotEmpty ? v : fallback);
  }

  @override
  void dispose() {
    for (final c in [
      _firmaName, _firmaTitel, _firmaAnschrift, _firmaTelefon, _firmaEmail,
      _firmaWebsite, _bestellung1, _bestellung2,
      _ustId, _steuerNr,
      _bankInhaber, _bankName, _iban, _bic,
      _satz, _satzJveg, _ust, _zahlungsziel,
      _jvegKm, _jvegSchreib, _jvegKopieSw, _jvegKopieFarbe,
      _jvegFotoErst, _jvegFotoWeit,
      _nkAkte, _nkAkteNext, _nkRn, _nkRnNext,
      _nkAng, _nkAngNext, _nkGut, _nkGutNext, _nkFB, _nkFBNext,
      _rnFoot, _rnSchluss, _angFoot,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'],
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null || f.bytes!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Datei konnte nicht gelesen werden.')));
      }
      return;
    }
    if (f.size > 2 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Logo max. 2 MB — bitte kleinere Datei wählen.')));
      }
      return;
    }
    final mime = _mimeForExt(f.extension);
    setState(() {
      _logoBase64 = base64Encode(f.bytes!);
      _logoMime = mime;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Logo geladen: ${f.name} (${(f.size / 1024).toStringAsFixed(0)} KB) — jetzt "Speichern" klicken.')));
    }
  }

  String _mimeForExt(String? ext) {
    switch ((ext ?? '').toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'svg':
        return 'image/svg+xml';
      default:
        return 'image/png';
    }
  }

  void _removeLogo() {
    setState(() {
      _logoBase64 = null;
      _logoMime = null;
    });
  }

  Future<void> _pickSiegel() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'svg'],
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null || f.size > 2 * 1024 * 1024) return;
    setState(() {
      _siegelBase64 = base64Encode(f.bytes!);
      _siegelMime = _mimeForExt(f.extension);
    });
  }

  void _removeSiegel() {
    setState(() {
      _siegelBase64 = null;
      _siegelMime = null;
    });
  }

  Future<void> _pickUnterschrift() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'svg'],
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null || f.size > 1 * 1024 * 1024) return;
    setState(() {
      _unterschriftBase64 = base64Encode(f.bytes!);
      _unterschriftMime = _mimeForExt(f.extension);
    });
  }

  void _removeUnterschrift() {
    setState(() {
      _unterschriftBase64 = null;
      _unterschriftMime = null;
    });
  }

  Future<void> _ladeProfil(StammdatenProfil p) async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: Text('Profil „${p.label}" laden?'),
        content: const Text(
            'Aktuelle Einstellungen werden mit den Profil-Werten überschrieben. '
            'Nicht im Profil enthaltene Felder bleiben unverändert.'),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(true),
              child: const Text('Laden')),
        ],
      ),
    );
    if (ok != true) return;
    await applyStammdatenProfil(
        ref.read(einstellungenRepositoryProvider), p);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Profil „${p.label}" geladen – '
              'bitte Seite neu öffnen um Werte zu sehen.')));
    }
  }

  Future<void> _exportDatev(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    var von = DateTime(now.year, 1, 1);
    var bis = DateTime(now.year, 12, 31);
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('DATEV-Export'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Von'),
                subtitle: Text(
                    '${von.day.toString().padLeft(2, "0")}.${von.month.toString().padLeft(2, "0")}.${von.year}'),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: von,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setLocal(() => von = d);
                },
              ),
              ListTile(
                title: const Text('Bis'),
                subtitle: Text(
                    '${bis.day.toString().padLeft(2, "0")}.${bis.month.toString().padLeft(2, "0")}.${bis.year}'),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: bis,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setLocal(() => bis = d);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Exportieren')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final result = await ref
        .read(datevExportServiceProvider)
        .export(von: von, bis: bis);
    await result.share(
        'datev_${von.year}${von.month.toString().padLeft(2, "0")}_${bis.year}${bis.month.toString().padLeft(2, "0")}.csv');
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(einstellungenRepositoryProvider);

    // Stammdaten
    await repo.set(SettingsKeys.firmaName, _firmaName.text.trim());
    await repo.set(SettingsKeys.firmaTitel, _firmaTitel.text.trim());
    await repo.set(SettingsKeys.firmaAnschrift, _firmaAnschrift.text.trim());
    await repo.set(SettingsKeys.firmaTelefon, _firmaTelefon.text.trim());
    await repo.set(SettingsKeys.firmaEmail, _firmaEmail.text.trim());
    await repo.set(SettingsKeys.firmaWebsite, _firmaWebsite.text.trim());
    await repo.set(SettingsKeys.firmaBestellung1, _bestellung1.text.trim());
    await repo.set(SettingsKeys.firmaBestellung2, _bestellung2.text.trim());
    await repo.set(SettingsKeys.firmaLogoBase64, _logoBase64);
    await repo.set(SettingsKeys.firmaLogoMime, _logoMime);

    // Steuer
    await repo.set(SettingsKeys.steuerUstId, _ustId.text.trim());
    await repo.set(SettingsKeys.steuerNr, _steuerNr.text.trim());
    await repo.set(SettingsKeys.steuerKleinunternehmer, _kleinunternehmer);

    // Bank
    await repo.set(SettingsKeys.bankInhaber, _bankInhaber.text.trim());
    await repo.set(SettingsKeys.bankName, _bankName.text.trim());
    await repo.set(SettingsKeys.bankIban, _iban.text.trim());
    await repo.set(SettingsKeys.bankBic, _bic.text.trim());

    // Honorar
    await repo.set(SettingsKeys.standardStundensatz, _satz.text.trim());
    await repo.set(SettingsKeys.stundensatzJveg, _satzJveg.text.trim());
    await repo.set(SettingsKeys.standardUstSatz, _ust.text.trim());
    await repo.set(SettingsKeys.standardZahlungszielTage,
        _zahlungsziel.text.trim());

    // JVEG
    await repo.set(SettingsKeys.jvegKmSatz, _jvegKm.text.trim());
    await repo.set(SettingsKeys.jvegSchreibsatz, _jvegSchreib.text.trim());
    await repo.set(SettingsKeys.jvegKopieSw, _jvegKopieSw.text.trim());
    await repo.set(SettingsKeys.jvegKopieFarbe, _jvegKopieFarbe.text.trim());
    await repo.set(
        SettingsKeys.jvegLichtbildErstes, _jvegFotoErst.text.trim());
    await repo.set(
        SettingsKeys.jvegLichtbildWeitere, _jvegFotoWeit.text.trim());

    // Nummernkreise
    await repo.set(SettingsKeys.nummernkreisAktenzeichen, _nkAkte.text.trim());
    await repo.set(SettingsKeys.nummernkreisAktenzeichenNaechste,
        _nkAkteNext.text.trim());
    await repo.set(SettingsKeys.nummernkreisAktenzeichenReset, _nkAkteReset);

    await repo.set(SettingsKeys.nummernkreisRechnung, _nkRn.text.trim());
    await repo.set(SettingsKeys.nummernkreisRechnungNaechste,
        _nkRnNext.text.trim());
    await repo.set(SettingsKeys.nummernkreisRechnungReset, _nkRnReset);

    await repo.set(SettingsKeys.nummernkreisAngebot, _nkAng.text.trim());
    await repo.set(SettingsKeys.nummernkreisAngebotNaechste,
        _nkAngNext.text.trim());
    await repo.set(SettingsKeys.nummernkreisAngebotReset, _nkAngReset);

    await repo.set(SettingsKeys.nummernkreisGutachten, _nkGut.text.trim());
    await repo.set(SettingsKeys.nummernkreisGutachtenNaechste,
        _nkGutNext.text.trim());
    await repo.set(SettingsKeys.nummernkreisGutachtenReset, _nkGutReset);

    await repo.set(SettingsKeys.nummernkreisFortbildung, _nkFB.text.trim());
    await repo.set(SettingsKeys.nummernkreisFortbildungNaechste,
        _nkFBNext.text.trim());
    await repo.set(SettingsKeys.nummernkreisFortbildungReset, _nkFBReset);

    // Texte
    await repo.set(SettingsKeys.rechnungFusstext, _rnFoot.text.trim());
    await repo.set(SettingsKeys.rechnungSchlusstext, _rnSchluss.text.trim());
    await repo.set(SettingsKeys.angebotFusstext, _angFoot.text.trim());

    // UI + DATEV
    await repo.set(SettingsKeys.theme, _theme);
    await repo.set(SettingsKeys.datevKontenrahmen, _datevSkr);

    // E-Rechnung / Kostensatz
    await repo.set(SettingsKeys.leitwegId, _leitwegId.text.trim());
    await repo.set(
        SettingsKeys.internerKostensatz, _internerKostensatz.text.trim());

    // Tätigkeitsbericht
    await repo.set(
        SettingsKeys.taetigkeitBerichtEmpfaenger, _tbEmpfaenger.text.trim());
    await repo.set(
        SettingsKeys.taetigkeitBerichtVorwort, _tbVorwort.text.trim());
    await repo.set(
        SettingsKeys.taetigkeitBerichtEidesstatt, _tbEides.text.trim());

    // Siegel + Unterschrift
    await repo.set(SettingsKeys.siegelBase64, _siegelBase64);
    await repo.set(SettingsKeys.siegelMime, _siegelMime);
    await repo.set(SettingsKeys.siegelPosition, _siegelPosition);
    await repo.set(SettingsKeys.siegelBestellBehoerde, _siegelBehoerde.text.trim());
    await repo.set(SettingsKeys.siegelBestellNr, _siegelNr.text.trim());
    await repo.set(SettingsKeys.siegelGueltigBis, _siegelGueltigBis.text.trim());
    await repo.set(SettingsKeys.unterschriftBase64, _unterschriftBase64);
    await repo.set(SettingsKeys.unterschriftMime, _unterschriftMime);

    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Einstellungen gespeichert')),
      );
    }
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
              const Icon(Icons.tune_outlined, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Einstellungen',
                        style: theme.textTheme.headlineMedium),
                    Text(
                      'Firma, Bank, Honorar, Nummernkreise und PDF-Texte',
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Section(
                    'Sachverständigen-Stammdaten',
                    subtitle:
                        'Diese Angaben erscheinen im Briefkopf, auf Rechnungen, Angeboten und im Gutachten.',
                    children: [
                      _Row2(
                        left: _L('Name *',
                            TextField(controller: _firmaName)),
                        right: _L(
                            'Titel / Akad. Grad',
                            TextField(controller: _firmaTitel)),
                      ),
                      const SizedBox(height: 12),
                      _L(
                        'Anschrift (mehrzeilig)',
                        TextField(
                          controller: _firmaAnschrift,
                          minLines: 3,
                          maxLines: 4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _Row3(
                        a: _L('Telefon',
                            TextField(controller: _firmaTelefon)),
                        b: _L('E-Mail',
                            TextField(controller: _firmaEmail)),
                        c: _L('Website',
                            TextField(controller: _firmaWebsite)),
                      ),
                      const SizedBox(height: 16),
                      Text('Logo / Briefkopf-Grafik',
                          style: theme.textTheme.labelMedium?.copyWith(
                              color:
                                  theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      _LogoPanel(
                        logoBase64: _logoBase64,
                        logoMime: _logoMime,
                        onPick: _pickLogo,
                        onRemove: _removeLogo,
                      ),
                      const SizedBox(height: 16),
                      _Row2(
                        left: _L(
                          'Bestellungstext — Spalte 1 (Fußzeile)',
                          TextField(
                              controller: _bestellung1,
                              minLines: 4,
                              maxLines: 8),
                        ),
                        right: _L(
                          'Bestellungstext — Spalte 2 (Fußzeile)',
                          TextField(
                              controller: _bestellung2,
                              minLines: 4,
                              maxLines: 8),
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    'Steuerdaten',
                    subtitle:
                        'USt-IdNr. bevorzugt; wenn nicht gesetzt, wird die Steuernummer angezeigt.',
                    children: [
                      _Row3(
                        a: _L('USt-IdNr.',
                            TextField(controller: _ustId)),
                        b: _L('Steuernummer',
                            TextField(controller: _steuerNr)),
                        c: _L(
                          'Kleinunternehmer (§19 UStG)',
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'nein', label: Text('Nein')),
                              ButtonSegment(value: 'ja', label: Text('Ja')),
                            ],
                            selected: {_kleinunternehmer},
                            showSelectedIcon: false,
                            onSelectionChanged: (s) =>
                                setState(() => _kleinunternehmer = s.first),
                          ),
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    'Bankverbindung',
                    subtitle:
                        'Wird auf Rechnungen im Zahlungsteil abgedruckt.',
                    children: [
                      _Row2(
                        left: _L('Kontoinhaber',
                            TextField(controller: _bankInhaber)),
                        right: _L('Bank',
                            TextField(controller: _bankName)),
                      ),
                      const SizedBox(height: 12),
                      _Row2(
                        left: _L('IBAN',
                            TextField(controller: _iban)),
                        right: _L('BIC',
                            TextField(controller: _bic)),
                      ),
                    ],
                  ),
                  _Section(
                    'Honorar & Umsatzsteuer',
                    children: [
                      _Row2(
                        left: _L(
                          'Standard-Stundensatz Privat (€)',
                          TextField(
                            controller: _satz,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                          ),
                        ),
                        right: _L(
                          'JVEG-Stundensatz (€)',
                          _InfoField(
                            hint: 'z. B. M3 = 130 €',
                            child: TextField(
                              controller: _satzJveg,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _Row2(
                        left: _L(
                          'MwSt-Satz (%)',
                          TextField(
                            controller: _ust,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                          ),
                        ),
                        right: _L(
                          'Standard-Zahlungsziel (Tage)',
                          TextField(
                            controller: _zahlungsziel,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    'JVEG-Sätze (§§ 5, 7 JVEG)',
                    subtitle:
                        'Werden in Gerichts-Rechnungen und im Ortstermin-Rechner verwendet.',
                    children: [
                      _Row3(
                        a: _L(
                          'Fahrtkosten (€/km)',
                          TextField(
                            controller: _jvegKm,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                          ),
                        ),
                        b: _L(
                          'Schreibauslagen je 1.000 Anschläge (€)',
                          TextField(
                            controller: _jvegSchreib,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                          ),
                        ),
                        c: _L(
                          'Kopie/Ausdruck S/W (€/Seite)',
                          TextField(
                            controller: _jvegKopieSw,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _Row3(
                        a: _L(
                          'Kopie/Ausdruck Farbe (€/Seite)',
                          TextField(
                            controller: _jvegKopieFarbe,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                          ),
                        ),
                        b: _L(
                          'Lichtbild — erstes (€)',
                          TextField(
                            controller: _jvegFotoErst,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                          ),
                        ),
                        c: _L(
                          'Lichtbild — jedes weitere (€)',
                          TextField(
                            controller: _jvegFotoWeit,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                          ),
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    'Nummernkreise',
                    subtitle:
                        'Platzhalter: {YYYY}=Jahr (4-stellig), {YY}=Jahr (2-stellig), '
                        '{N}/{NN}/{NNN}/{NNNN}=Zähler mit Mindest-Stellen. '
                        'Beim Gutachten zusätzlich: {aktenzeichen}.',
                    children: [
                      _NkRow(
                        label: 'Akten-/Aktenzeichen',
                        muster: _nkAkte,
                        naechste: _nkAkteNext,
                        reset: _nkAkteReset,
                        onResetChanged: (v) =>
                            setState(() => _nkAkteReset = v),
                      ),
                      const SizedBox(height: 12),
                      _NkRow(
                        label: 'Angebots-Nr.',
                        muster: _nkAng,
                        naechste: _nkAngNext,
                        reset: _nkAngReset,
                        onResetChanged: (v) =>
                            setState(() => _nkAngReset = v),
                      ),
                      const SizedBox(height: 12),
                      _NkRow(
                        label: 'Rechnungs-Nr.',
                        muster: _nkRn,
                        naechste: _nkRnNext,
                        reset: _nkRnReset,
                        onResetChanged: (v) =>
                            setState(() => _nkRnReset = v),
                      ),
                      const SizedBox(height: 12),
                      _NkRow(
                        label: 'Gutachten-Nr.',
                        muster: _nkGut,
                        naechste: _nkGutNext,
                        reset: _nkGutReset,
                        onResetChanged: (v) =>
                            setState(() => _nkGutReset = v),
                      ),
                      const SizedBox(height: 12),
                      _NkRow(
                        label: 'Fortbildungs-Nr.',
                        muster: _nkFB,
                        naechste: _nkFBNext,
                        reset: _nkFBReset,
                        onResetChanged: (v) =>
                            setState(() => _nkFBReset = v),
                      ),
                    ],
                  ),
                  _Section(
                    'Rechnungstexte',
                    subtitle:
                        'Schlusstext erscheint unterhalb der Rechnungspositionen, '
                        'Fußtext ganz unten auf der Seite.',
                    children: [
                      _L(
                        'Schlusstext Rechnung',
                        TextField(
                            controller: _rnSchluss,
                            minLines: 3,
                            maxLines: 6),
                      ),
                      const SizedBox(height: 12),
                      _L(
                        'Fußtext Rechnung',
                        TextField(
                            controller: _rnFoot, minLines: 3, maxLines: 6),
                      ),
                      const SizedBox(height: 12),
                      _L(
                        'Fußtext Angebot',
                        TextField(
                            controller: _angFoot, minLines: 3, maxLines: 6),
                      ),
                    ],
                  ),
                  _Section(
                    'DATEV / Buchhaltung',
                    subtitle:
                        'Kontenrahmen auswählen. Debitoren/Kreditoren werden '
                        'beim Speichern automatisch nummeriert. CSV-Export '
                        'bringt Ausgangs- und Eingangsrechnungen in '
                        'einem von Steuerberatern üblich importierbaren '
                        'Format aus.',
                    children: [
                      _L(
                        'Kontenrahmen',
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                                value: 'SKR03', label: Text('SKR03')),
                            ButtonSegment(
                                value: 'SKR04', label: Text('SKR04')),
                          ],
                          selected: {_datevSkr},
                          showSelectedIcon: false,
                          onSelectionChanged: (s) =>
                              setState(() => _datevSkr = s.first),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.file_download_outlined),
                            label: const Text('DATEV-Export (CSV) …'),
                            onPressed: () => _exportDatev(context, ref),
                          ),
                        ],
                      ),
                    ],
                  ),
                  _Section(
                    'Sachverständigen-Siegel & Unterschrift',
                    subtitle:
                        'Siegel wird auf dem Unterschriftsblock des Gutachtens '
                        'und bei Bedarf im Briefkopf angezeigt. '
                        'PNG mit transparentem Hintergrund empfohlen.',
                    children: [
                      _L(
                        'Siegel-Bild',
                        _LogoPanel(
                          logoBase64: _siegelBase64,
                          logoMime: _siegelMime,
                          onPick: _pickSiegel,
                          onRemove: _removeSiegel,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _L(
                        'Unterschrifts-Scan',
                        _LogoPanel(
                          logoBase64: _unterschriftBase64,
                          logoMime: _unterschriftMime,
                          onPick: _pickUnterschrift,
                          onRemove: _removeUnterschrift,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _L(
                        'Position im Gutachten',
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                                value: 'unten_links',
                                label: Text('unten links')),
                            ButtonSegment(
                                value: 'unten_rechts',
                                label: Text('unten rechts')),
                            ButtonSegment(
                                value: 'mit_unterschrift',
                                label: Text('mit Unterschrift')),
                          ],
                          selected: {_siegelPosition},
                          showSelectedIcon: false,
                          onSelectionChanged: (s) =>
                              setState(() => _siegelPosition = s.first),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _L('Bestellungsbehörde',
                          TextFormField(controller: _siegelBehoerde)),
                      const SizedBox(height: 12),
                      _L('Bestellnummer',
                          TextFormField(controller: _siegelNr)),
                      const SizedBox(height: 12),
                      _L(
                        'Bestellung gültig bis (JJJJ-MM-TT)',
                        TextFormField(
                          controller: _siegelGueltigBis,
                          decoration: const InputDecoration(
                            hintText: '2028-12-31',
                          ),
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    'Tätigkeitsbericht IHK / HWK',
                    subtitle:
                        'Vorlagen für den Jahres-Tätigkeitsbericht an die '
                        'bestellende Kammer. Erzeugt wird das PDF im '
                        'Jahresbericht-Modul.',
                    children: [
                      _L(
                        'Empfänger / Kammer',
                        TextFormField(
                            controller: _tbEmpfaenger,
                            minLines: 2,
                            maxLines: 4),
                      ),
                      const SizedBox(height: 12),
                      _L(
                        'Vorwort (optional)',
                        TextFormField(
                            controller: _tbVorwort,
                            minLines: 3,
                            maxLines: 8),
                      ),
                      const SizedBox(height: 12),
                      _L(
                        'Eidesstattliche Erklärung',
                        TextFormField(
                            controller: _tbEides,
                            minLines: 3,
                            maxLines: 8),
                      ),
                    ],
                  ),
                  _Section(
                    'E-Rechnung (XRechnung / ZUGFeRD)',
                    subtitle:
                        'Leitweg-ID ist Pflicht für Rechnungen an Behörden. '
                        'Wird in der XRechnung als BuyerReference übernommen.',
                    children: [
                      _L(
                        'Leitweg-ID (Standard-Empfänger)',
                        TextFormField(
                          controller: _leitwegId,
                          decoration: const InputDecoration(
                            hintText: 'z. B. 991-33333M-34',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _L(
                        'Interner Kostensatz (€/Std) für Deckungsbeitrag',
                        TextFormField(
                          controller: _internerKostensatz,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ],
                  ),
                  _Section('Erscheinungsbild', children: [
                    _L(
                      'Theme',
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'system', label: Text('System')),
                          ButtonSegment(value: 'light', label: Text('Hell')),
                          ButtonSegment(value: 'dark', label: Text('Dunkel')),
                        ],
                        selected: {_theme},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) =>
                            setState(() => _theme = s.first),
                      ),
                    ),
                  ]),
                  _Section(
                    'Vorlagen laden',
                    subtitle:
                        'Ersetzt die aktuellen Einstellungen mit einem vorgefertigten Profil. '
                        'Für den Produktiv-Mandanten „Bauelemente-Experte" oder zum Testen.',
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.download_outlined, size: 18),
                            label: Text(
                                'Profil „${stammdatenBauelementeExperte.label}" laden'),
                            onPressed: () =>
                                _ladeProfil(stammdatenBauelementeExperte),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.download_outlined, size: 18),
                            label: Text(
                                'Profil „${stammdatenDemo.label}" laden'),
                            onPressed: () => _ladeProfil(stammdatenDemo),
                          ),
                        ],
                      ),
                    ],
                  ),
                  _Section('Datensicherung',
                      children: const [DemoSeedSection()]),
                  _Section('Cloud', children: const [SyncSection()]),
                  _Section(
                    'Google Kalender',
                    subtitle:
                        'Ortstermine, Fristen, Erläuterungen & Wiedervorlagen in einen Google-Kalender spiegeln.',
                    children: const [GoogleCalendarSection()],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// ---------------- Hilfs-Widgets ----------------

class _Section extends StatelessWidget {
  const _Section(this.title, {this.subtitle, required this.children});
  final String title;
  final String? subtitle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.slate200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!,
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.slate500)),
              ],
              const SizedBox(height: 16),
              ...children,
            ],
          ),
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
  const _Row2({required this.left, required this.right});
  final Widget left;
  final Widget right;
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      );
}

class _Row3 extends StatelessWidget {
  const _Row3({required this.a, required this.b, required this.c});
  final Widget a;
  final Widget b;
  final Widget c;
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: 12),
          Expanded(child: b),
          const SizedBox(width: 12),
          Expanded(child: c),
        ],
      );
}

class _InfoField extends StatelessWidget {
  const _InfoField({required this.hint, required this.child});
  final String hint;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child,
          const SizedBox(height: 4),
          Text(hint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
        ],
      );
}

/// Nummernkreis-Zeile: Muster + Nächste + Reset.
class _NkRow extends StatelessWidget {
  const _NkRow({
    required this.label,
    required this.muster,
    required this.naechste,
    required this.reset,
    required this.onResetChanged,
  });
  final String label;
  final TextEditingController muster;
  final TextEditingController naechste;
  final String reset;
  final ValueChanged<String> onResetChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          flex: 3,
          child: _L(label, TextField(controller: muster)),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: _L(
            'Nächste Nummer',
            TextField(
              controller: naechste,
              keyboardType: TextInputType.number,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: _L(
            'Reset',
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'jahr', label: Text('jährlich 01.01.')),
                ButtonSegment(value: 'nie', label: Text('nie')),
              ],
              selected: {reset},
              showSelectedIcon: false,
              onSelectionChanged: (s) => onResetChanged(s.first),
            ),
          ),
        ),
      ],
    );
  }
}

/// Logo-Preview + Upload/Remove.
class _LogoPanel extends StatelessWidget {
  const _LogoPanel({
    required this.logoBase64,
    required this.logoMime,
    required this.onPick,
    required this.onRemove,
  });
  final String? logoBase64;
  final String? logoMime;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final hasLogo = logoBase64 != null && logoBase64!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.slate200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.slate50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.slate200),
            ),
            alignment: Alignment.center,
            child: hasLogo
                ? _LogoImage(base64: logoBase64!, mime: logoMime)
                : Icon(Icons.image_outlined,
                    size: 28, color: AppTheme.slate400),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasLogo
                      ? 'Logo hinterlegt (${logoMime ?? 'image'})'
                      : 'Noch kein Logo gewählt',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'PNG oder JPG, idealerweise transparent. Max. 2 MB. '
                  'Wird oben rechts im Briefkopf angezeigt.',
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.slate500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (hasLogo)
            IconButton(
              tooltip: 'Logo entfernen',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: onRemove,
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.upload_file, size: 16),
            label: Text(hasLogo ? 'Ersetzen' : 'Logo auswählen'),
            onPressed: onPick,
          ),
        ],
      ),
    );
  }
}

class _LogoImage extends StatelessWidget {
  const _LogoImage({required this.base64, this.mime});
  final String base64;
  final String? mime;

  bool _isSvgBytes(List<int> bytes) {
    if (bytes.length < 5) return false;
    final head = String.fromCharCodes(
        bytes.take(200).where((b) => b > 0 && b < 128));
    return head.contains('<svg') || head.trimLeft().startsWith('<?xml');
  }

  @override
  Widget build(BuildContext context) {
    final bytes = base64Decode(base64);
    final isSvg = mime == 'image/svg+xml' || _isSvgBytes(bytes);
    if (isSvg) {
      return SvgPicture.memory(bytes, fit: BoxFit.contain);
    }
    return Image.memory(bytes, fit: BoxFit.contain);
  }
}
