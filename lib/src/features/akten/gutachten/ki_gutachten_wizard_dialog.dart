import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingMode, OrderingTerm, Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/ai/gutachten_wizard_ki_service.dart';
import '../../../core/theme/aw_tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../data/sync/storage_service.dart';
import '../../system/einstellungen/nummernkreis_service.dart';
import '../akte/beteiligte_tab.dart';
import '../auftraege/auftrag_gm_extras.dart';
import '../auftraege/auftraege_repository.dart';
import '../dokumente/dokumente_repository.dart';
import '../gerichtssache/beweisfragen.dart';
import '../kunden/kunden_repository.dart';
import 'gutachten_repository.dart';
import 'gutachten_screen.dart';
import 'gutachten_verzeichnisse_generator.dart';
import 'gutachten_wysiwyg_embeds.dart';
import 'quill_image_embed.dart';

/// Öffnet den mehrstufigen KI-Gutachten- & Akten-Wizard.
/// Gibt das angelegte oder aktualisierte [GutachtenData] zurück.
Future<GutachtenData?> showKiGutachtenWizardDialog(
  BuildContext context, {
  int? initialAuftragId,
  GutachtenData? existingGutachten,
}) {
  return showDialog<GutachtenData>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => _KiGutachtenWizardDialog(
      initialAuftragId: initialAuftragId,
      existingGutachten: existingGutachten,
    ),
  );
}

class _KiGutachtenWizardDialog extends ConsumerStatefulWidget {
  const _KiGutachtenWizardDialog({
    this.initialAuftragId,
    this.existingGutachten,
  });

  final int? initialAuftragId;
  final GutachtenData? existingGutachten;

  @override
  ConsumerState<_KiGutachtenWizardDialog> createState() =>
      _KiGutachtenWizardDialogState();
}

class _KiGutachtenWizardDialogState
    extends ConsumerState<_KiGutachtenWizardDialog> {
  /// 0 = Upload & Aktenwahl
  /// 1 = KI-Analyse läuft
  /// 2 = Stammdaten, Beteiligte & Normen prüfen
  /// 3 = Beweisfragen & Foto-Befunde prüfen
  /// 4 = Gutachten-Abschnitte (WYSIWYG) prüfen & Speichern
  int _step = 0;

  bool _neueAkteAnlegen = true;
  int? _selectedAuftragId;
  List<AuftragWithKunde> _alleAkten = const [];

  final List<KiWizardFileInput> _files = [];
  final TextEditingController _notizenCtrl = TextEditingController();

  bool _analyzing = false;
  bool _saving = false;
  String _statusText = '';
  String? _errorMsg;

  // --- Schritt 3: Stammdaten-Controller ---
  String _art = 'gericht';
  final _betreffCtrl = TextEditingController();
  final _bezeichnungCtrl = TextEditingController();
  final _gerichtsAzCtrl = TextEditingController();
  final _gerichtCtrl = TextEditingController();
  final _gerichtsortCtrl = TextEditingController();
  final _verfahrensartCtrl =
      TextEditingController(text: 'Selbständiges Beweisverfahren');
  final _richterCtrl = TextEditingController();
  final _klaegerCtrl = TextEditingController();
  final _beklagterCtrl = TextEditingController();
  final _streitwertCtrl = TextEditingController();
  final _vorschussCtrl = TextEditingController();
  final _beweisbeschlussDatumCtrl = TextEditingController();
  final _objektStrasseCtrl = TextEditingController();
  final _objektPlzCtrl = TextEditingController();
  final _objektOrtCtrl = TextEditingController();
  final _objektartCtrl = TextEditingController();
  final _baujahrCtrl = TextEditingController();
  final _sachgebietCtrl = TextEditingController();

  List<KiWizardBeteiligter> _beteiligte = [];
  List<KiWizardNorm> _normen = [];
  List<KiWizardBeweisfrage> _beweisfragen = [];
  List<KiWizardFotoBefund> _fotoBefunde = [];

  final Map<String, TextEditingController> _abschnittCtrls = {
    for (final a in gutachtenAbschnitte) a.key: TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    if (widget.initialAuftragId != null) {
      _neueAkteAnlegen = false;
      _selectedAuftragId = widget.initialAuftragId;
    }
    _initLoadAkten();
  }

  Future<void> _initLoadAkten() async {
    final list = await ref.read(auftraegeRepositoryProvider).watchAll().first;
    if (!mounted) return;
    setState(() {
      _alleAkten = list;
    });
    if (_selectedAuftragId != null) {
      await _loadExistingFilesFromAkte(_selectedAuftragId!);
    }
  }

  Future<void> _loadExistingFilesFromAkte(int auftragId) async {
    final db = ref.read(appDatabaseProvider);
    final storage = ref.read(storageServiceProvider);

    final docs = await (db.select(db.dokumente)
          ..where((t) => t.auftragId.equals(auftragId))
          ..orderBy([(t) => OrderingTerm(expression: t.datum, mode: OrderingMode.desc)]))
        .get();

    final fotos = await (db.select(db.fotos)
          ..where((t) => t.auftragId.equals(auftragId))
          ..orderBy([(t) => OrderingTerm(expression: t.reihenfolge)]))
        .get();

    final loaded = <KiWizardFileInput>[];
    final loadedFotoBefunde = <KiWizardFotoBefund>[];
    for (final d in docs) {
      var bytes = d.daten;
      if ((bytes == null || bytes.isEmpty) && d.storagePfad != null) {
        try {
          bytes = await storage.downloadBytes(d.storagePfad!);
        } catch (_) {}
      }
      if ((bytes == null || bytes.isEmpty) &&
          d.storageUrl != null &&
          d.storageUrl!.isNotEmpty) {
        try {
          final resp = await http.get(Uri.parse(d.storageUrl!));
          if (resp.statusCode == 200) bytes = resp.bodyBytes;
        } catch (_) {}
      }
      loaded.add(
        KiWizardFileInput(
          filename: d.titel ?? d.pfad ?? 'Dokument_${d.id}.pdf',
          mimeType: d.mimeType ?? 'application/pdf',
          bytes: bytes ?? Uint8List(0),
          isPhoto: false,
          kategorie: d.kategorie ?? 'Gerichtsakte / Schriftsatz',
          existingId: d.id,
        ),
      );
    }

    var fotoIdx = 0;
    for (final f in fotos) {
      var bytes = f.daten;
      if ((bytes == null || bytes.isEmpty) && f.storagePfad != null) {
        try {
          bytes = await storage.downloadBytes(f.storagePfad!);
        } catch (_) {}
      }
      if ((bytes == null || bytes.isEmpty) &&
          f.storageUrl != null &&
          f.storageUrl!.isNotEmpty) {
        try {
          final resp = await http.get(Uri.parse(f.storageUrl!));
          if (resp.statusCode == 200) bytes = resp.bodyBytes;
        } catch (_) {}
      }
      final fname = f.titel ?? f.pfad ?? 'Lichtbild_${f.id}.jpg';
      loaded.add(
        KiWizardFileInput(
          filename: fname,
          mimeType: f.mimeType ?? 'image/jpeg',
          bytes: bytes ?? Uint8List(0),
          isPhoto: true,
          kategorie: 'Foto / Lichtbild',
          existingId: f.id,
        ),
      );
      loadedFotoBefunde.add(
        KiWizardFotoBefund(
          fotoIndex: fotoIdx++,
          dateiname: fname,
          titel: f.titel ?? fname,
          raum: f.raum ?? '',
          beschreibung: f.beschreibung ?? '',
          empfohlenerAbschnitt: f.gutachtenAbschnitt ?? 's_feststellungen',
        ),
      );
    }

    // Bestehende Stammdaten, Beteiligte, Beweisfragen, Normen & Gutachten der Akte vorladen
    final auftrag = await ref.read(auftraegeRepositoryProvider).byId(auftragId);
    final aktenNormen = await (db.select(db.normen)
          ..where((t) => t.auftragId.equals(auftragId))
          ..orderBy([(t) => OrderingTerm(expression: t.nummer)]))
        .get();
    final gutachtenList = await (db.select(db.gutachten)
          ..where((t) => t.auftragId.equals(auftragId)))
        .get();
    final bestGutachten = widget.existingGutachten ?? gutachtenList.firstOrNull;

    if (!mounted) return;
    setState(() {
      _files.removeWhere((f) => f.existingId != null);
      _files.insertAll(0, loaded);
      if (loadedFotoBefunde.isNotEmpty) {
        _fotoBefunde = loadedFotoBefunde;
      }
      if (auftrag != null) {
        _art = (auftrag.art == 'privat') ? 'privat' : 'gericht';
        _betreffCtrl.text = auftrag.betreff ?? auftrag.bezeichnung ?? '';
        _bezeichnungCtrl.text =
            bestGutachten?.bezeichnung ??
            bestGutachten?.titel ??
            auftrag.bezeichnung ??
            auftrag.betreff ??
            '';
        _gerichtsAzCtrl.text = auftrag.gerichtsAktenzeichen ?? '';
        _gerichtCtrl.text = auftrag.gericht ?? '';
        _gerichtsortCtrl.text = auftrag.gerichtsort ?? '';
        if ((auftrag.verfahrensart ?? '').isNotEmpty) {
          _verfahrensartCtrl.text = auftrag.verfahrensart!;
        }
        _richterCtrl.text = auftrag.richter ?? '';
        _klaegerCtrl.text = auftrag.klaeger ?? '';
        _beklagterCtrl.text = auftrag.beklagter ?? '';
        final gmExtras = AuftragGmExtras.fromExtras(auftrag.extras);
        _streitwertCtrl.text =
            (gmExtras.streitwert != null && gmExtras.streitwert! > 0)
                ? gmExtras.streitwert!.toStringAsFixed(2)
                : '';
        _vorschussCtrl.text =
            (auftrag.kostenvorschuss != null && auftrag.kostenvorschuss! > 0)
                ? auftrag.kostenvorschuss!.toStringAsFixed(2)
                : '';
        if (auftrag.beweisbeschluss1 != null) {
          final d = auftrag.beweisbeschluss1!;
          _beweisbeschlussDatumCtrl.text =
              '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        }
        _objektStrasseCtrl.text = auftrag.objektStrasse ?? '';
        _objektPlzCtrl.text = auftrag.objektPlz ?? '';
        _objektOrtCtrl.text = auftrag.objektOrt ?? '';
        _objektartCtrl.text = auftrag.objektart ?? '';
        _baujahrCtrl.text = auftrag.baujahr ?? '';
        _sachgebietCtrl.text = auftrag.sachgebiet ?? '';

        final bet = decodeBeteiligte(auftrag.beteiligteJson);
        if (bet.isNotEmpty) {
          _beteiligte = bet
              .map(
                (b) => KiWizardBeteiligter(
                  rolle: b.rolle,
                  anrede: b.anrede,
                  name: b.name,
                  strasse: b.strasse,
                  plz: b.plz,
                  ort: b.ort,
                  ihrZeichen: b.ihrZeichen,
                  vertritt: b.vertritt,
                ),
              )
              .toList();
        }
        final bfragen = decodeBeweisfragen(auftrag.beweisfragenJson);
        if (bfragen.isNotEmpty) {
          _beweisfragen = bfragen
              .map(
                (q) => KiWizardBeweisfrage(
                  nr: q.nr,
                  frage: q.frage,
                  einschaetzung: q.einschaetzung ?? '',
                ),
              )
              .toList();
        }
      }
      if (aktenNormen.isNotEmpty) {
        _normen = aktenNormen
            .map(
              (n) => KiWizardNorm(
                nummer: n.nummer,
                ausgabe: n.ausgabe ?? '',
                titel: n.titel ?? '',
                kategorie: n.kategorie ?? 'DIN / EN',
              ),
            )
            .toList();
      }
      if (bestGutachten != null) {
        final abschnitte = abschnitteFromJson(bestGutachten.abschnitteJson);
        for (final entry in abschnitte.entries) {
          final ctrl = _abschnittCtrls[entry.key];
          if (ctrl != null && entry.value.trim().isNotEmpty) {
            ctrl.text = entry.value.trim();
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _notizenCtrl.dispose();
    _betreffCtrl.dispose();
    _bezeichnungCtrl.dispose();
    _gerichtsAzCtrl.dispose();
    _gerichtCtrl.dispose();
    _gerichtsortCtrl.dispose();
    _verfahrensartCtrl.dispose();
    _richterCtrl.dispose();
    _klaegerCtrl.dispose();
    _beklagterCtrl.dispose();
    _streitwertCtrl.dispose();
    _vorschussCtrl.dispose();
    _beweisbeschlussDatumCtrl.dispose();
    _objektStrasseCtrl.dispose();
    _objektPlzCtrl.dispose();
    _objektOrtCtrl.dispose();
    _objektartCtrl.dispose();
    _baujahrCtrl.dispose();
    _sachgebietCtrl.dispose();
    for (final c in _abschnittCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _guessMimeType(String name, {required bool isPhoto}) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return isPhoto ? 'image/jpeg' : 'application/pdf';
  }

  String _guessDocCategory(String filename) {
    final lower = filename.toLowerCase();
    if (lower.contains('beschluss') || lower.contains('auftrag')) {
      return 'Beweisbeschluss / Auftrag';
    }
    if (lower.contains('angebot') ||
        lower.contains('rechnung') ||
        lower.contains('lv')) {
      return 'Angebot / Rechnung / LV';
    }
    if (lower.contains('plan') ||
        lower.contains('zeichnung') ||
        lower.contains('statik')) {
      return 'Plan / Technische Unterlage';
    }
    return 'Gerichtsakte / Schriftsatz';
  }

  Future<void> _pickDokumente() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (res == null || res.files.isEmpty) return;
    setState(() {
      for (final f in res.files) {
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        _files.add(
          KiWizardFileInput(
            filename: f.name,
            mimeType: _guessMimeType(f.name, isPhoto: false),
            bytes: bytes,
            isPhoto: false,
            kategorie: _guessDocCategory(f.name),
          ),
        );
      }
    });
  }

  Future<void> _pickFotos() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.image,
    );
    if (res == null || res.files.isEmpty) return;
    setState(() {
      for (final f in res.files) {
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        _files.add(
          KiWizardFileInput(
            filename: f.name,
            mimeType: _guessMimeType(f.name, isPhoto: true),
            bytes: bytes,
            isPhoto: true,
            kategorie: 'Foto / Lichtbild',
          ),
        );
      }
    });
  }

  Future<void> _startKiAnalyse() async {
    if (_files.isEmpty && _notizenCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bitte lade mindestens eine Unterlage, ein Foto oder Stichpunkte hoch.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _step = 1;
      _analyzing = true;
      _errorMsg = null;
      _statusText = 'Starte multimodale KI-Analyse …';
    });

    try {
      // Falls bereits Stammdaten oder Dokument-Beschreibungen aus einer gewählten Akte vorliegen,
      // als Zusatzkontext an die KI übergeben.
      final zusatzKontext = StringBuffer();
      if (_notizenCtrl.text.trim().isNotEmpty) {
        zusatzKontext.writeln(_notizenCtrl.text.trim());
      }
      if (!_neueAkteAnlegen && _selectedAuftragId != null) {
        final db = ref.read(appDatabaseProvider);
        final auf =
            await ref.read(auftraegeRepositoryProvider).byId(_selectedAuftragId!);
        final docs = await (db.select(db.dokumente)
              ..where((t) => t.auftragId.equals(_selectedAuftragId!)))
            .get();
        if (auf != null) {
          zusatzKontext.writeln('\n--- VORHANDENE AKTEN-STAMMDATEN ---');
          zusatzKontext.writeln(
              'Aktenzeichen: ${auf.aktenzeichen ?? ""}, Gericht: ${auf.gericht ?? ""} ${auf.gerichtsort ?? ""}, Gerichts-Az.: ${auf.gerichtsAktenzeichen ?? ""}');
          zusatzKontext.writeln(
              'Kläger: ${auf.klaeger ?? ""}, Beklagter: ${auf.beklagter ?? ""}, Richter: ${auf.richter ?? ""}');
          zusatzKontext.writeln(
              'Objekt: ${auf.objektStrasse ?? ""}, ${auf.objektPlz ?? ""} ${auf.objektOrt ?? ""} (${auf.objektart ?? ""}, Baujahr ${auf.baujahr ?? ""})');
          if ((auf.beweisfragenJson ?? '').isNotEmpty) {
            zusatzKontext.writeln('Beweisfragen-JSON: ${auf.beweisfragenJson}');
          }
          if ((auf.beteiligteJson ?? '').isNotEmpty) {
            zusatzKontext.writeln('Beteiligte-JSON: ${auf.beteiligteJson}');
          }
        }
        for (var i = 0; i < docs.length; i++) {
          final d = docs[i];
          if ((d.beschreibung ?? '').trim().isNotEmpty) {
            zusatzKontext.writeln(
                'Unterlage [A${i + 1}] ${d.titel ?? ""}: ${d.beschreibung}');
          }
        }
      }

      final result = await analysiereUnterlagenFuerGutachten(
        ref: ref,
        files: _files,
        freitextNotizen: zusatzKontext.toString(),
        onStatus: (s) {
          if (mounted) setState(() => _statusText = s);
        },
      );

      if (!mounted) return;
      _applyResultToControllers(result);
      _aktualisiereVerzeichnisseUndFotosVorschau();
      setState(() {
        _analyzing = false;
        _step = 2;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _errorMsg = e.toString();
        _step = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('KI-Analyse fehlgeschlagen: $e')),
      );
    }
  }

  void _applyResultToControllers(KiWizardResult res) {
    final s = res.stammdaten;
    _art = (s.art == 'privat') ? 'privat' : 'gericht';
    _betreffCtrl.text = s.betreff;
    _bezeichnungCtrl.text =
        s.bezeichnung.isNotEmpty ? s.bezeichnung : s.betreff;
    _gerichtsAzCtrl.text = s.gerichtsAktenzeichen;
    _gerichtCtrl.text = s.gericht;
    _gerichtsortCtrl.text = s.gerichtsort;
    if (s.verfahrensart.isNotEmpty) {
      _verfahrensartCtrl.text = s.verfahrensart;
    }
    _richterCtrl.text = s.richter;
    _klaegerCtrl.text = s.klaeger;
    _beklagterCtrl.text = s.beklagter;
    _streitwertCtrl.text =
        (s.streitwert != null && s.streitwert! > 0) ? s.streitwert!.toStringAsFixed(2) : '';
    _vorschussCtrl.text = (s.kostenvorschuss != null && s.kostenvorschuss! > 0)
        ? s.kostenvorschuss!.toStringAsFixed(2)
        : '';
    _beweisbeschlussDatumCtrl.text = s.beweisbeschlussVom;
    _objektStrasseCtrl.text = s.objektStrasse;
    _objektPlzCtrl.text = s.objektPlz;
    _objektOrtCtrl.text = s.objektOrt;
    _objektartCtrl.text = s.objektart;
    _baujahrCtrl.text = s.baujahr;
    _sachgebietCtrl.text = s.sachgebiet;

    _beteiligte = res.beteiligte;
    _normen = res.normen;
    _beweisfragen = res.beweisfragen;
    _fotoBefunde = res.fotoBefunde;

    for (final entry in res.abschnitte.entries) {
      final ctrl = _abschnittCtrls[entry.key];
      if (ctrl != null && entry.value.trim().isNotEmpty) {
        ctrl.text = entry.value.trim();
      }
    }
  }

  /// Bettet zugeordnete Fotos inline in die Ziel-Abschnitte ein und erzeugt
  /// automatisch `s_grundlage` (Unterlagen-, Quellen-, Ortstermin-, Abkürzungs- &
  /// Formelverzeichnis) sowie `s_anlagen` (Anlagenverzeichnis) für die Vorschau in Schritt 5.
  void _aktualisiereVerzeichnisseUndFotosVorschau() {
    final photos = _files.where((f) => f.isPhoto).toList();
    for (var i = 0; i < photos.length && i < _fotoBefunde.length; i++) {
      final p = photos[i];
      final bf = _fotoBefunde[i];
      if (p.bytes.isEmpty) continue;
      final targetKey = bf.empfohlenerAbschnitt.trim();
      if (targetKey.isEmpty) continue;
      final ctrl = _abschnittCtrls[targetKey];
      if (ctrl == null) continue;
      final marker = 'Bild ${i + 1}';
      if (!ctrl.text.contains(marker) && !ctrl.text.contains(bf.titel)) {
        final b64 = base64Encode(p.bytes);
        final caption = [
          'Bild ${i + 1}',
          if (bf.titel.trim().isNotEmpty) bf.titel.trim(),
          if (bf.beschreibung.trim().isNotEmpty) bf.beschreibung.trim(),
        ].join(' – ');
        final mdImg = '![$caption](data:${p.mimeType};base64,$b64)';
        ctrl.text = ctrl.text.trim().isEmpty
            ? mdImg
            : '${ctrl.text.trim()}\n\n$mdImg';
      }
    }

    final now = DateTime.now();
    final beteiligteList = _beteiligte
        .where((b) => b.selected && b.name.trim().isNotEmpty)
        .map(
          (b) => Beteiligter(
            rolle: b.rolle.trim(),
            anrede: b.anrede.trim(),
            name: b.name.trim(),
            strasse: b.strasse.trim(),
            plz: b.plz.trim(),
            ort: b.ort.trim(),
            ihrZeichen: b.ihrZeichen.trim(),
            vertritt: b.vertritt.trim(),
          ),
        )
        .toList();

    final tempAuftrag = AuftraegeData(
      id: _selectedAuftragId ?? 0,
      aktenzeichen: 'AZ-NEU',
      art: _art,
      status: 'in_bearbeitung',
      betreff: _betreffCtrl.text.trim(),
      bezeichnung: _bezeichnungCtrl.text.trim(),
      gericht: _gerichtCtrl.text.trim(),
      gerichtsort: _gerichtsortCtrl.text.trim(),
      gerichtsAktenzeichen: _gerichtsAzCtrl.text.trim(),
      verfahrensart: _verfahrensartCtrl.text.trim(),
      richter: _richterCtrl.text.trim(),
      klaeger: _klaegerCtrl.text.trim(),
      beklagter: _beklagterCtrl.text.trim(),
      beweisbeschluss1:
          DateTime.tryParse(_beweisbeschlussDatumCtrl.text.trim()),
      objektStrasse: _objektStrasseCtrl.text.trim(),
      objektPlz: _objektPlzCtrl.text.trim(),
      objektOrt: _objektOrtCtrl.text.trim(),
      objektart: _objektartCtrl.text.trim(),
      baujahr: _baujahrCtrl.text.trim(),
      sachgebiet: _sachgebietCtrl.text.trim(),
      beteiligteJson: encodeBeteiligte(beteiligteList),
      ortsterminAm: widget.existingGutachten?.ortsterminAm ?? now,
      createdAt: now,
      updatedAt: now,
    );

    final docs = _files.where((f) => !f.isPhoto).toList();
    final tempDocs = <DokumenteData>[];
    final tempAnlagen = <GutachtenAnlage>[];
    for (var i = 0; i < docs.length; i++) {
      final d = docs[i];
      final id = d.existingId ?? (i + 1);
      tempDocs.add(
        DokumenteData(
          id: id,
          auftragId: tempAuftrag.id,
          titel: d.filename,
          kategorie: d.kategorie,
          mimeType: d.mimeType,
          datum: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
      tempAnlagen.add(
        GutachtenAnlage(
          nr: i + 1,
          dokumentId: id,
          titel: d.filename,
          kategorie: d.kategorie,
          datum: now,
        ),
      );
    }

    final tempNormen = <NormenData>[
      for (var i = 0; i < _normen.length; i++)
        if (_normen[i].selected && _normen[i].nummer.trim().isNotEmpty)
          NormenData(
            id: i + 1,
            auftragId: tempAuftrag.id,
            nummer: _normen[i].nummer.trim(),
            titel: _normen[i].titel.trim(),
            ausgabe: _normen[i].ausgabe.trim(),
            kategorie: _normen[i].kategorie.trim(),
            relevanz: 'gutachten',
            aktiv: true,
            favorit: false,
            createdAt: now,
            updatedAt: now,
          ),
    ];

    final abschnittePlain = <String, String>{
      for (final e in _abschnittCtrls.entries) e.key: e.value.text,
    };

    final res = GutachtenVerzeichnisseGenerator.generate(
      abschnittePlain: abschnittePlain,
      auftrag: tempAuftrag,
      ortsterminAm: tempAuftrag.ortsterminAm,
      anlagen: tempAnlagen,
      aktenDokumente: tempDocs,
      aktenNormen: tempNormen,
    );

    _abschnittCtrls['s_grundlage']?.text = res.sGrundlageText;
    if (res.anzahlAnlagen > 0) {
      _abschnittCtrls['s_anlagen']?.text = res.sAnlagenText;
    }
  }

  /// Lädt das Mustergutachten (z. B. AW-0001-G1 / 4 O 218/25 Balkongeländer & PR-Fassade)
  /// samt Akten-Stammdaten, Beteiligten, Beweisfragen, Normen, Fotos und allen 13 Abschnitten
  /// direkt in den Wizard, damit das Endresultat Schritt für Schritt begutachtet werden kann.
  Future<void> _ladeMustergutachtenInWizard() async {
    final db = ref.read(appDatabaseProvider);
    final alleGutachten = await db.select(db.gutachten).get();
    final musterGutachten = alleGutachten
            .where((g) =>
                (g.nummer ?? '').contains('0001') ||
                (g.bezeichnung ?? '').toLowerCase().contains('balkon') ||
                (g.titel ?? '').toLowerCase().contains('balkon'))
            .firstOrNull ??
        alleGutachten.firstOrNull;

    if (musterGutachten != null && musterGutachten.auftragId != null) {
      setState(() {
        _neueAkteAnlegen = false;
        _selectedAuftragId = musterGutachten.auftragId;
      });
      await _loadExistingFilesFromAkte(musterGutachten.auftragId!);
      final abschnitte = abschnitteFromJson(musterGutachten.abschnitteJson);
      for (final entry in abschnitte.entries) {
        final ctrl = _abschnittCtrls[entry.key];
        if (ctrl != null && entry.value.trim().isNotEmpty) {
          ctrl.text = entry.value.trim();
        }
      }
      _aktualisiereVerzeichnisseUndFotosVorschau();
      if (!mounted) return;
      setState(() => _step = 2);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Mustergutachten „${musterGutachten.nummer ?? musterGutachten.bezeichnung ?? "Referenz"}“ samt Akte in den Wizard geladen (Schritte 3–5).',
          ),
        ),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kein Mustergutachten in der Datenbank gefunden.'),
        ),
      );
    }
  }

  Future<void> _saveCompleteDataset() async {
    setState(() {
      _saving = true;
      _statusText = 'Speichere Akte, Unterlagen, Fotos & Gutachten …';
    });

    try {
      final db = ref.read(appDatabaseProvider);
      final storage = ref.read(storageServiceProvider);
      final numService = ref.read(nummernkreisServiceProvider);

      // 1. Auftraggeber / Gericht als Kunde anlegen oder finden
      int? kundeId;
      final gerichtName = _gerichtCtrl.text.trim();
      final klaegerName = _klaegerCtrl.text.trim();
      final kundenFirma = _art == 'gericht' && gerichtName.isNotEmpty
          ? gerichtName
          : (klaegerName.isNotEmpty ? klaegerName : 'Auftraggeber');

      final alleKunden = await db.select(db.kunden).get();
      final existingKunde = alleKunden
          .where((k) => (k.firma ?? '').toLowerCase() == kundenFirma.toLowerCase())
          .firstOrNull;
      if (existingKunde != null) {
        kundeId = existingKunde.id;
      } else {
        kundeId = await ref.read(kundenRepositoryProvider).upsert(
              KundenCompanion.insert(
                typ: Value(_art == 'gericht' ? 'gericht' : 'privat'),
                firma: Value(kundenFirma),
                ort: Value(_gerichtsortCtrl.text.trim().isNotEmpty
                    ? _gerichtsortCtrl.text.trim()
                    : null),
                ansprechpartner: Value(_richterCtrl.text.trim().isNotEmpty
                    ? _richterCtrl.text.trim()
                    : null),
              ),
            );
      }

      // 2. Beteiligte-JSON und Beweisfragen-JSON aufbauen
      final beteiligteList = _beteiligte
          .where((b) => b.selected && b.name.trim().isNotEmpty)
          .map(
            (b) => Beteiligter(
              rolle: b.rolle.trim(),
              anrede: b.anrede.trim(),
              name: b.name.trim(),
              strasse: b.strasse.trim(),
              plz: b.plz.trim(),
              ort: b.ort.trim(),
              ihrZeichen: b.ihrZeichen.trim(),
              vertritt: b.vertritt.trim(),
            ),
          )
          .toList();
      final beteiligteJsonStr =
          jsonEncode(beteiligteList.map((e) => e.toJson()).toList());

      final beweisfragenList = _beweisfragen
          .where((q) => q.frage.trim().isNotEmpty)
          .map(
            (q) => Beweisfrage(
              nr: q.nr.trim(),
              frage: q.frage.trim(),
              einschaetzung:
                  q.einschaetzung.trim().isEmpty ? null : q.einschaetzung.trim(),
            ),
          )
          .toList();
      final beweisfragenJsonStr = encodeBeweisfragen(beweisfragenList);

      final streitwertVal = double.tryParse(
        _streitwertCtrl.text.replaceAll('.', '').replaceAll(',', '.').trim(),
      );
      final vorschussVal = double.tryParse(
        _vorschussCtrl.text.replaceAll('.', '').replaceAll(',', '.').trim(),
      );
      final beschlussDatum =
          DateTime.tryParse(_beweisbeschlussDatumCtrl.text.trim());

      final gmExtras = AuftragGmExtras(
        streitwert: streitwertVal,
        gerichtsaktenBaende: [
          GerichtsaktenBand(
            bandNr: 'Bd. I',
            bezeichnung: 'Hauptakte',
            eingangAm: DateTime.now(),
          ),
        ],
      );

      // 3. Akte (Auftrag) anlegen oder aktualisieren
      int auftragId;
      String aktenzeichen;
      if (!_neueAkteAnlegen && _selectedAuftragId != null) {
        auftragId = _selectedAuftragId!;
        final existingAuftrag =
            await ref.read(auftraegeRepositoryProvider).byId(auftragId);
        aktenzeichen = existingAuftrag?.aktenzeichen ??
            await numService.nextNumber(NummernkreisTyp.akte);
        final mergedExtras =
            gmExtras.mergeIntoExtras(existingAuftrag?.extras);
        await ref.read(auftraegeRepositoryProvider).upsert(
              AuftraegeCompanion(
                id: Value(auftragId),
                aktenzeichen: Value(aktenzeichen),
                art: Value(_art),
                kundeId: Value(existingAuftrag?.kundeId ?? kundeId),
                betreff: Value(_betreffCtrl.text.trim().isNotEmpty
                    ? _betreffCtrl.text.trim()
                    : existingAuftrag?.betreff),
                bezeichnung: Value(_bezeichnungCtrl.text.trim().isNotEmpty
                    ? _bezeichnungCtrl.text.trim()
                    : existingAuftrag?.bezeichnung),
                gerichtsAktenzeichen: Value(
                    _gerichtsAzCtrl.text.trim().isNotEmpty
                        ? _gerichtsAzCtrl.text.trim()
                        : existingAuftrag?.gerichtsAktenzeichen),
                azExtern: Value(_gerichtsAzCtrl.text.trim().isNotEmpty
                    ? _gerichtsAzCtrl.text.trim()
                    : existingAuftrag?.azExtern),
                gericht: Value(_gerichtCtrl.text.trim().isNotEmpty
                    ? _gerichtCtrl.text.trim()
                    : existingAuftrag?.gericht),
                gerichtsort: Value(_gerichtsortCtrl.text.trim().isNotEmpty
                    ? _gerichtsortCtrl.text.trim()
                    : existingAuftrag?.gerichtsort),
                verfahrensart: Value(_verfahrensartCtrl.text.trim().isNotEmpty
                    ? _verfahrensartCtrl.text.trim()
                    : existingAuftrag?.verfahrensart),
                richter: Value(_richterCtrl.text.trim().isNotEmpty
                    ? _richterCtrl.text.trim()
                    : existingAuftrag?.richter),
                klaeger: Value(_klaegerCtrl.text.trim().isNotEmpty
                    ? _klaegerCtrl.text.trim()
                    : existingAuftrag?.klaeger),
                beklagter: Value(_beklagterCtrl.text.trim().isNotEmpty
                    ? _beklagterCtrl.text.trim()
                    : existingAuftrag?.beklagter),
                kostenvorschuss:
                    Value(vorschussVal ?? existingAuftrag?.kostenvorschuss),
                beweisbeschluss1:
                    Value(beschlussDatum ?? existingAuftrag?.beweisbeschluss1),
                objektStrasse: Value(_objektStrasseCtrl.text.trim().isNotEmpty
                    ? _objektStrasseCtrl.text.trim()
                    : existingAuftrag?.objektStrasse),
                objektPlz: Value(_objektPlzCtrl.text.trim().isNotEmpty
                    ? _objektPlzCtrl.text.trim()
                    : existingAuftrag?.objektPlz),
                objektOrt: Value(_objektOrtCtrl.text.trim().isNotEmpty
                    ? _objektOrtCtrl.text.trim()
                    : existingAuftrag?.objektOrt),
                objektart: Value(_objektartCtrl.text.trim().isNotEmpty
                    ? _objektartCtrl.text.trim()
                    : existingAuftrag?.objektart),
                baujahr: Value(_baujahrCtrl.text.trim().isNotEmpty
                    ? _baujahrCtrl.text.trim()
                    : existingAuftrag?.baujahr),
                sachgebiet: Value(_sachgebietCtrl.text.trim().isNotEmpty
                    ? _sachgebietCtrl.text.trim()
                    : existingAuftrag?.sachgebiet),
                beteiligteJson: Value(beteiligteList.isNotEmpty
                    ? beteiligteJsonStr
                    : existingAuftrag?.beteiligteJson),
                beweisfragenJson: Value(beweisfragenList.isNotEmpty
                    ? beweisfragenJsonStr
                    : existingAuftrag?.beweisfragenJson),
                extras: Value(mergedExtras),
              ),
            );
      } else {
        aktenzeichen = await numService.nextNumber(NummernkreisTyp.akte);
        auftragId = await ref.read(auftraegeRepositoryProvider).upsert(
              AuftraegeCompanion.insert(
                aktenzeichen: Value(aktenzeichen),
                art: Value(_art),
                status: const Value('in_bearbeitung'),
                kundeId: Value(kundeId),
                betreff: Value(_betreffCtrl.text.trim()),
                bezeichnung: Value(_bezeichnungCtrl.text.trim().isNotEmpty
                    ? _bezeichnungCtrl.text.trim()
                    : _betreffCtrl.text.trim()),
                gerichtsAktenzeichen: Value(_gerichtsAzCtrl.text.trim()),
                azExtern: Value(_gerichtsAzCtrl.text.trim()),
                gericht: Value(_gerichtCtrl.text.trim()),
                gerichtsort: Value(_gerichtsortCtrl.text.trim()),
                verfahrensart: Value(_verfahrensartCtrl.text.trim()),
                richter: Value(_richterCtrl.text.trim()),
                klaeger: Value(_klaegerCtrl.text.trim()),
                beklagter: Value(_beklagterCtrl.text.trim()),
                kostenvorschuss: Value(vorschussVal),
                beweisbeschluss1: Value(beschlussDatum),
                eingangAm: Value(DateTime.now()),
                auftragAm: Value(beschlussDatum ?? DateTime.now()),
                objektStrasse: Value(_objektStrasseCtrl.text.trim()),
                objektPlz: Value(_objektPlzCtrl.text.trim()),
                objektOrt: Value(_objektOrtCtrl.text.trim()),
                objektart: Value(_objektartCtrl.text.trim()),
                baujahr: Value(_baujahrCtrl.text.trim()),
                sachgebiet: Value(_sachgebietCtrl.text.trim()),
                kategorie: const Value('Mängelgutachten'),
                beteiligteJson: Value(beteiligteJsonStr),
                beweisfragenJson: Value(beweisfragenJsonStr),
                extras: Value(gmExtras.mergeIntoExtras(null)),
              ),
            );
      }

      // 4. Dokumente speichern & Anlagen-Liste erstellen
      final docInputs = _files.where((f) => !f.isPhoto).toList();
      final anlagenListe = <GutachtenAnlage>[];
      for (var i = 0; i < docInputs.length; i++) {
        final d = docInputs[i];
        int dokId;
        if (d.existingId != null) {
          dokId = d.existingId!;
        } else {
          String? storageUrl;
          String? storagePfad;
          if (storage.enabled) {
            try {
              final ts = DateTime.now().millisecondsSinceEpoch;
              storagePfad = 'akten/$auftragId/dokumente/${ts}_${d.filename}';
              storageUrl = await storage.uploadBytes(
                storagePfad,
                bytes: d.bytes,
                contentType: d.mimeType,
              );
            } catch (_) {
              storagePfad = null;
              storageUrl = null;
            }
          }
          dokId = await ref.read(dokumenteRepositoryProvider).upsert(
                DokumenteCompanion.insert(
                  auftragId: Value(auftragId),
                  titel: Value(d.filename),
                  kategorie: Value(d.kategorie),
                  pfad: Value(d.filename),
                  mimeType: Value(d.mimeType),
                  dateigroesse: Value(d.bytes.length),
                  storagePfad: Value(storagePfad),
                  storageUrl: Value(storageUrl),
                  daten: Value(d.bytes),
                  datum: Value(DateTime.now()),
                ),
              );
        }
        anlagenListe.add(
          GutachtenAnlage(
            nr: i + 1,
            dokumentId: dokId,
            titel: d.filename,
            kategorie: d.kategorie,
            datum: DateTime.now(),
          ),
        );
      }

      // 5. Normen in die Akte übernehmen (inkl. PDF-URL-Abgleich aus Bibliothek)
      final alleLibraryNormen = await (db.select(db.normen)
            ..where((t) => t.auftragId.isNull()))
          .get();
      final vorhandeneAktenNormen = await (db.select(db.normen)
            ..where((t) => t.auftragId.equals(auftragId)))
          .get();

      for (final n in _normen.where((x) => x.selected && x.nummer.trim().isNotEmpty)) {
        final nrClean = n.nummer.trim();
        final existsInAkte = vorhandeneAktenNormen.any(
          (an) => an.nummer.toLowerCase() == nrClean.toLowerCase(),
        );
        if (existsInAkte) continue;

        final libMatch = alleLibraryNormen.where((ln) {
          final lNr = ln.nummer.toLowerCase();
          final qNr = nrClean.toLowerCase();
          return lNr == qNr || lNr.contains(qNr) || qNr.contains(lNr);
        }).firstOrNull;

        await db.into(db.normen).insert(
              NormenCompanion.insert(
                auftragId: Value(auftragId),
                nummer: nrClean,
                ausgabe: Value(n.ausgabe.trim().isNotEmpty
                    ? n.ausgabe.trim()
                    : libMatch?.ausgabe),
                titel: Value(n.titel.trim().isNotEmpty
                    ? n.titel.trim()
                    : libMatch?.titel),
                kategorie: Value(n.kategorie.trim().isNotEmpty
                    ? n.kategorie.trim()
                    : (libMatch?.kategorie ?? 'DIN / EN')),
                relevanz: const Value('gutachten'),
                pdfStorageUrl: Value(libMatch?.pdfStorageUrl),
                pdfPfad: Value(libMatch?.pdfPfad),
                pdfDateiname: Value(libMatch?.pdfDateiname),
                pdfMimeType: Value(libMatch?.pdfMimeType),
                pdfGroesse: Value(libMatch?.pdfGroesse),
              ),
            );
      }

      // 6. Gutachten-Datensatz vorab anlegen/aktualisieren, damit wir die gutachtenId für die Fotos haben
      final gutachtenNr = widget.existingGutachten?.nummer ??
          await numService.nextNumber(
            NummernkreisTyp.gutachten,
            aktenzeichen: aktenzeichen,
          );
      final abschnitteMap = <String, String>{
        for (final e in _abschnittCtrls.entries)
          if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
        '_opt_links': 'true',
        '_opt_doppelseitig': 'true',
        '_opt_notizrand_linien': 'true',
      };

      final gutachtenId = await ref.read(gutachtenRepositoryProvider).upsert(
            GutachtenCompanion(
              id: widget.existingGutachten != null
                  ? Value(widget.existingGutachten!.id)
                  : const Value.absent(),
              auftragId: Value(auftragId),
              nummer: Value(gutachtenNr),
              titel: Value(_bezeichnungCtrl.text.trim().isNotEmpty
                  ? _bezeichnungCtrl.text.trim()
                  : _betreffCtrl.text.trim()),
              bezeichnung: Value(_bezeichnungCtrl.text.trim().isNotEmpty
                  ? _bezeichnungCtrl.text.trim()
                  : _betreffCtrl.text.trim()),
              datum: Value(DateTime.now()),
              vorlage: const Value('frei'),
              status: const Value('entwurf'),
              abschnitteJson: Value(abschnitteToJson(abschnitteMap)),
              anlagenJson: Value(anlagenToJson(anlagenListe)),
            ),
          );

      // 7. Fotos speichern und mit Akte + Gutachten + KI-Befundtexten verknüpfen
      final photoInputs = _files.where((f) => f.isPhoto).toList();
      for (var i = 0; i < photoInputs.length; i++) {
        final p = photoInputs[i];
        final befund = i < _fotoBefunde.length ? _fotoBefunde[i] : null;
        final titel = befund?.titel.trim().isNotEmpty == true
            ? befund!.titel.trim()
            : p.filename;
        final raum = befund?.raum.trim().isNotEmpty == true
            ? befund!.raum.trim()
            : null;
        final beschr = befund?.beschreibung.trim().isNotEmpty == true
            ? befund!.beschreibung.trim()
            : null;
        final abschn = befund?.empfohlenerAbschnitt.trim().isNotEmpty == true
            ? befund!.empfohlenerAbschnitt.trim()
            : null;

        if (p.existingId != null) {
          await (db.update(db.fotos)..where((t) => t.id.equals(p.existingId!)))
              .write(
            FotosCompanion(
              auftragId: Value(auftragId),
              gutachtenId: Value(gutachtenId),
              gutachtenAbschnitt: Value(abschn),
              titel: Value(titel),
              raum: Value(raum),
              beschreibung: Value(beschr),
              reihenfolge: Value(i + 1),
            ),
          );
        } else {
          String? storageUrl;
          String? storagePfad;
          if (storage.enabled) {
            try {
              final ts = DateTime.now().millisecondsSinceEpoch;
              storagePfad = 'akten/$auftragId/fotos/${ts}_${p.filename}';
              storageUrl = await storage.uploadBytes(
                storagePfad,
                bytes: p.bytes,
                contentType: p.mimeType,
              );
            } catch (_) {
              storagePfad = null;
              storageUrl = null;
            }
          }
          await db.into(db.fotos).insert(
                FotosCompanion.insert(
                  auftragId: Value(auftragId),
                  gutachtenId: Value(gutachtenId),
                  gutachtenAbschnitt: Value(abschn),
                  titel: Value(titel),
                  raum: Value(raum),
                  beschreibung: Value(beschr),
                  pfad: Value(p.filename),
                  mimeType: Value(p.mimeType),
                  storagePfad: Value(storagePfad),
                  storageUrl: Value(storageUrl),
                  daten: Value(p.bytes),
                  aufnahmeAm: Value(DateTime.now()),
                  reihenfolge: Value(i + 1),
                ),
              );
        }
      }

      // 8. Verzeichnisse (Abkürzungen, Formelzeichen, Normen/Quellen, Anlagen) automatisch generieren
      final savedAuftrag =
          await ref.read(auftraegeRepositoryProvider).byId(auftragId);
      final savedNormen = await (db.select(db.normen)
            ..where((t) => t.auftragId.equals(auftragId))
            ..orderBy([(t) => OrderingTerm(expression: t.nummer)]))
          .get();
      final savedDokumente = await (db.select(db.dokumente)
            ..where((t) => t.auftragId.equals(auftragId)))
          .get();

      final verzeichnisse = GutachtenVerzeichnisseGenerator.generate(
        abschnittePlain: abschnitteMap,
        auftrag: savedAuftrag,
        ortsterminAm: widget.existingGutachten?.ortsterminAm ?? DateTime.now(),
        anlagen: anlagenListe,
        aktenDokumente: savedDokumente,
        aktenNormen: savedNormen,
      );

      abschnitteMap['s_grundlage'] = verzeichnisse.sGrundlageText;
      if (verzeichnisse.anzahlAnlagen > 0) {
        abschnitteMap['s_anlagen'] = verzeichnisse.sAnlagenText;
      }

      await ref.read(gutachtenRepositoryProvider).upsert(
            GutachtenCompanion(
              id: Value(gutachtenId),
              abschnitteJson: Value(abschnitteToJson(abschnitteMap)),
            ),
          );

      final finalGutachten = await (db.select(db.gutachten)
            ..where((t) => t.id.equals(gutachtenId)))
          .getSingleOrNull();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(finalGutachten);

      if (finalGutachten != null &&
          widget.existingGutachten == null &&
          context.mounted) {
        await showGutachtenEditor(context, gutachten: finalGutachten);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Speichern: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280, maxHeight: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            _buildStepIndicator(),
            const Divider(height: 1),
            Expanded(
              child: switch (_step) {
                0 => _buildStep0Upload(),
                1 => _buildStep1Analyzing(),
                2 => _buildStep2Stammdaten(),
                3 => _buildStep3FragenUndFotos(),
                _ => _buildStep4Abschnitte(),
              },
            ),
            const Divider(height: 1),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF1E3552),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KI-Akten- & Gutachten-Assistent (Schritt-für-Schritt-Wizard)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Unterlagen & Fotos hochladen → KI extrahiert Stammdaten, Beteiligte, Beweisfragen, Foto-Befunde & alle 13 Gutachten-Abschnitte',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          if (!_analyzing && !_saving)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    const labels = [
      '1. Unterlagen & Fotos',
      '2. KI-Analyse',
      '3. Akte, Beteiligte & Normen',
      '4. Beweisfragen & Fotos',
      '5. Gutachten-Entwurf (WYSIWYG)',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            InkWell(
              onTap: (_analyzing || _saving || i == 1 || (i > 1 && _step == 0))
                  ? null
                  : () {
                      if (i == 4) {
                        _aktualisiereVerzeichnisseUndFotosVorschau();
                      }
                      setState(() => _step = i);
                    },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _step == i
                      ? const Color(0xFF1E3552)
                      : (_step > i
                          ? const Color(0xFFE0F2FE)
                          : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_step > i)
                      const Padding(
                        padding: EdgeInsets.only(right: 5),
                        child: Icon(Icons.check_circle,
                            size: 14, color: Color(0xFF0369A1)),
                      ),
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _step == i
                            ? Colors.white
                            : (_step > i
                                ? const Color(0xFF0369A1)
                                : const Color(0xFF64748B)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i < labels.length - 1)
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Divider(color: Color(0xFFCBD5E1)),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // SCHRITT 0: UNTERLAGEN & FOTOS HOCHLADEN
  // -------------------------------------------------------------------------
  Widget _buildStep0Upload() {
    final docs = _files.where((f) => !f.isPhoto).toList();
    final photos = _files.where((f) => f.isPhoto).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMsg != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                'Fehler: $_errorMsg',
                style: TextStyle(color: Colors.red.shade900, fontSize: 12.5),
              ),
            ),

          // 1. Akten-Zuordnung
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AwTokens.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'SCHRITT 1A: AKTE WÄHLEN ODER NEU ANLEGEN',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: Color(0xFF1E3552),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _ladeMustergutachtenInWizard,
                      icon: const Icon(Icons.auto_awesome,
                          size: 15, color: AwTokens.amber),
                      label: const Text(
                        'Mustergutachten-Referenz im Wizard öffnen (4 O 218/25)',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text(
                        'Neue Akte automatisch aus Unterlagen anlegen',
                      ),
                      selected: _neueAkteAnlegen,
                      onSelected: (_) => setState(() => _neueAkteAnlegen = true),
                    ),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: const Text('Bestehende Akte verwenden'),
                      selected: !_neueAkteAnlegen,
                      onSelected: (_) =>
                          setState(() => _neueAkteAnlegen = false),
                    ),
                    if (!_neueAkteAnlegen) ...[
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _selectedAuftragId,
                          isDense: true,
                          decoration: const InputDecoration(
                            labelText: 'Bestehende Akte auswählen',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final a in _alleAkten)
                              DropdownMenuItem(
                                value: a.auftrag.id,
                                child: Text(
                                  '${a.auftrag.aktenzeichen ?? "—"} · ${a.auftrag.betreff ?? a.auftrag.bezeichnung ?? "Ohne Betreff"}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (id) async {
                            setState(() => _selectedAuftragId = id);
                            if (id != null) {
                              await _loadExistingFilesFromAkte(id);
                            }
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Zwei Spalten: Unterlagen (PDFs/Schriftsätze) & Fotos (Lichtbilder)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linke Spalte: Unterlagen / Dokumente
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AwTokens.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.description_outlined,
                              color: Color(0xFF1E3552)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Unterlagen & Akten (${docs.length})',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E3552),
                              ),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _pickDokumente,
                            icon: const Icon(Icons.upload_file, size: 16),
                            label: const Text('Unterlagen auswählen'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Beweisbeschluss, Gerichtsakte, Schriftsätze, Angebote, Rechnungen, Pläne oder Datenblätter (PDF / Bild)',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 12),
                      if (docs.isEmpty)
                        InkWell(
                          onTap: _pickDokumente,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 140,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFCBD5E1),
                              ),
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cloud_upload_outlined,
                                    size: 34, color: Color(0xFF64748B)),
                                SizedBox(height: 6),
                                Text(
                                  'Klicken, um PDFs / Unterlagen hinzuzufügen',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: docs.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final doc = docs[i];
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.picture_as_pdf,
                                    color: Colors.redAccent, size: 20),
                                title: Text(
                                  doc.filename,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  '${(doc.bytes.length / 1024).toStringAsFixed(0)} KB · ${doc.kategorie}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  onPressed: () =>
                                      setState(() => _files.remove(doc)),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Rechte Spalte: Fotos / Lichtbilder
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AwTokens.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.photo_camera_outlined,
                              color: Color(0xFF1E3552)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Fotos vom Ortstermin (${photos.length})',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E3552),
                              ),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _pickFotos,
                            icon:
                                const Icon(Icons.add_photo_alternate, size: 16),
                            label: const Text('Fotos auswählen'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Die KI erkennt Mängel und Bauteile auf den Fotos und erstellt automatisch Bildtitel & Befundtexte.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 12),
                      if (photos.isEmpty)
                        InkWell(
                          onTap: _pickFotos,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 140,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFCBD5E1),
                              ),
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_a_photo_outlined,
                                    size: 34, color: Color(0xFF64748B)),
                                SizedBox(height: 6),
                                Text(
                                  'Klicken, um Ortstermin-Fotos hinzuzufügen',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: GridView.builder(
                            shrinkWrap: true,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                            itemCount: photos.length,
                            itemBuilder: (_, i) {
                              final p = photos[i];
                              return Stack(
                                children: [
                                  Positioned.fill(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: p.bytes.isNotEmpty
                                          ? Image.memory(
                                              p.bytes,
                                              fit: BoxFit.cover,
                                            )
                                          : Container(
                                              color: const Color(0xFFE2E8F0),
                                              alignment: Alignment.center,
                                              padding: const EdgeInsets.all(4),
                                              child: Text(
                                                p.filename,
                                                maxLines: 2,
                                                textAlign: TextAlign.center,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 10),
                                              ),
                                            ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: InkWell(
                                      onTap: () =>
                                          setState(() => _files.remove(p)),
                                      child: const CircleAvatar(
                                        radius: 10,
                                        backgroundColor: Colors.black54,
                                        child: Icon(Icons.close,
                                            size: 12, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 3. Eigene Stichpunkte / Messwerte vom Ortstermin
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AwTokens.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'OPTIONAL: EIGENE STICHPUNKTE, MESSWERTE ODER BEOBACHTUNGEN VOM ORTSTERMIN',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: Color(0xFF1E3552),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notizenCtrl,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText:
                        'z. B. Ortstermin am 14.03.2026 um 10:00 Uhr · Geländerhöhe gemessen 969 mm (Soll 1.000 mm) · Pfosten RR 50x30x2,9 mm · fischer Bolzenanker FBN II M10 Randabstand 80 mm …',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // SCHRITT 1: KI-ANALYSE LÄUFT
  // -------------------------------------------------------------------------
  Widget _buildStep1Analyzing() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(strokeWidth: 3.5),
            ),
            const SizedBox(height: 24),
            const Text(
              'KI wertet Unterlagen & Fotos aus …',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E3552),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _statusText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AwTokens.line),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• Beweisbeschluss & Schriftsätze lesen',
                      style: TextStyle(fontSize: 12)),
                  SizedBox(height: 4),
                  Text('• Akten-Stammdaten, Parteien & Beteiligte extrahieren',
                      style: TextStyle(fontSize: 12)),
                  SizedBox(height: 4),
                  Text('• Fotos fachtechnisch beschreiben & zuordnen',
                      style: TextStyle(fontSize: 12)),
                  SizedBox(height: 4),
                  Text('• Einschlägige DIN-/EN-Normen ermitteln',
                      style: TextStyle(fontSize: 12)),
                  SizedBox(height: 4),
                  Text(
                      '• Alle 13 Gutachten-Abschnitte inkl. Soll-/Ist- und Kostentabellen entwerfen',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // SCHRITT 2: STAMMDATEN, BETEILIGTE & NORMEN PRÜFEN
  // -------------------------------------------------------------------------
  Widget _buildStep2Stammdaten() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Stammdaten
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AwTokens.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'EXTRAHIERTE AKTEN- & OBJEKT-STAMMDATEN',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E3552),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _tf(_bezeichnungCtrl, 'Gutachten-Titel / Bezeichnung'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _tf(_betreffCtrl, 'Kurz-Betreff / Beweisthema'),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 220,
                      child: _tf(_sachgebietCtrl, 'Sachgebiet'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _tf(_gerichtCtrl, 'Gericht / Auftraggeber'),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 180,
                      child: _tf(_gerichtsAzCtrl, 'Gerichts-Aktenzeichen'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _tf(_richterCtrl, 'Richter / Richterin'),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 160,
                      child: _tf(
                          _beweisbeschlussDatumCtrl, 'Beschluss vom (YYYY-MM-DD)'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _tf(_klaegerCtrl, 'Kläger / Antragsteller'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _tf(_beklagterCtrl, 'Beklagter / Antragsgegner'),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 150,
                      child: _tf(_streitwertCtrl, 'Streitwert (€)'),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 150,
                      child: _tf(_vorschussCtrl, 'Kostenvorschuss (€)'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _tf(_objektStrasseCtrl, 'Objekt-Straße & Hausnr.'),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 110,
                      child: _tf(_objektPlzCtrl, 'Objekt-PLZ'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _tf(_objektOrtCtrl, 'Objekt-Ort'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _tf(_objektartCtrl, 'Objektart'),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 110,
                      child: _tf(_baujahrCtrl, 'Baujahr'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Beteiligte & Normen nebeneinander
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Beteiligte
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AwTokens.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'ERKANNTE BETEILIGTE (${_beteiligte.length})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1E3552),
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _beteiligte.add(
                                  KiWizardBeteiligter(
                                    rolle: 'Beteiligter',
                                    name: '',
                                  ),
                                );
                              });
                            },
                            icon: const Icon(Icons.add, size: 15),
                            label: const Text('+ Beteiligter'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _beteiligte.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: _beteiligte[i].selected,
                                  onChanged: (v) => setState(
                                    () => _beteiligte[i].selected = v ?? true,
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_beteiligte[i].rolle}: ${_beteiligte[i].name}',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        [
                                          _beteiligte[i].strasse,
                                          '${_beteiligte[i].plz} ${_beteiligte[i].ort}'
                                              .trim(),
                                          if (_beteiligte[i]
                                              .ihrZeichen
                                              .isNotEmpty)
                                            'Az.: ${_beteiligte[i].ihrZeichen}',
                                        ].where((s) => s.isNotEmpty).join(', '),
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 16),
                                  onPressed: () =>
                                      setState(() => _beteiligte.removeAt(i)),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Normen
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AwTokens.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'EINSCHLÄGIGE NORMEN & REGELWERKE (${_normen.length})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1E3552),
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _normen.add(
                                  KiWizardNorm(nummer: 'DIN ', titel: ''),
                                );
                              });
                            },
                            icon: const Icon(Icons.add, size: 15),
                            label: const Text('+ Norm'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _normen.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: _normen[i].selected,
                                  onChanged: (v) => setState(
                                    () => _normen[i].selected = v ?? true,
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_normen[i].nummer}${_normen[i].ausgabe.isNotEmpty ? ":${_normen[i].ausgabe}" : ""}',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        _normen[i].titel,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 16),
                                  onPressed: () =>
                                      setState(() => _normen.removeAt(i)),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // SCHRITT 3: BEWEISFRAGEN & FOTO-BEFUNDE PRÜFEN
  // -------------------------------------------------------------------------
  Widget _buildStep3FragenUndFotos() {
    final photos = _files.where((f) => f.isPhoto).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Beweisfragen
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AwTokens.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'EXTRAHIERTE BEWEISFRAGEN (${_beweisfragen.length})',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E3552),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _beweisfragen.add(
                            KiWizardBeweisfrage(
                              nr: '${_beweisfragen.length + 1}.',
                              frage: '',
                            ),
                          );
                        });
                      },
                      icon: const Icon(Icons.add, size: 15),
                      label: const Text('+ Beweisfrage hinzufügen'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_beweisfragen.isEmpty)
                  const Text(
                    'Keine expliziten Beweisfragen erkannt — du kannst oben manuell Fragen ergänzen.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  )
                else
                  for (var i = 0; i < _beweisfragen.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 80,
                            child: TextFormField(
                              initialValue: _beweisfragen[i].nr,
                              decoration: const InputDecoration(
                                labelText: 'Nr.',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => _beweisfragen[i].nr = v,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  initialValue: _beweisfragen[i].frage,
                                  minLines: 1,
                                  maxLines: 3,
                                  decoration: const InputDecoration(
                                    labelText: 'Wortlaut der Beweisfrage',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (v) => _beweisfragen[i].frage = v,
                                ),
                                if (_beweisfragen[i].einschaetzung.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'KI-Einschätzung: ${_beweisfragen[i].einschaetzung}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF0369A1),
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () =>
                                setState(() => _beweisfragen.removeAt(i)),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Foto-Befunde
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AwTokens.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'KI-AUSWERTUNG DER FOTOS (${photos.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E3552),
                  ),
                ),
                const SizedBox(height: 10),
                if (photos.isEmpty)
                  const Text(
                    'Keine Fotos hochgeladen.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  )
                else
                  for (var i = 0; i < photos.length && i < _fotoBefunde.length; i++)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: photos[i].bytes.isNotEmpty
                                ? Image.memory(
                                    photos[i].bytes,
                                    width: 110,
                                    height: 85,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    width: 110,
                                    height: 85,
                                    color: const Color(0xFFE2E8F0),
                                    alignment: Alignment.center,
                                    child: const Icon(
                                        Icons.image_outlined,
                                        color: Color(0xFF64748B)),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        initialValue: _fotoBefunde[i].titel,
                                        decoration: const InputDecoration(
                                          labelText: 'Bildtitel (Lichtbildanlage)',
                                          isDense: true,
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (v) =>
                                            _fotoBefunde[i].titel = v,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextFormField(
                                        initialValue: _fotoBefunde[i].raum,
                                        decoration: const InputDecoration(
                                          labelText: 'Bauteil / Raum',
                                          isDense: true,
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (v) =>
                                            _fotoBefunde[i].raum = v,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        initialValue: const {
                                          's_objekt',
                                          's_feststellungen',
                                          '',
                                        }.contains(_fotoBefunde[i]
                                                .empfohlenerAbschnitt)
                                            ? _fotoBefunde[i]
                                                .empfohlenerAbschnitt
                                            : 's_feststellungen',
                                        isDense: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Abschnitts-Einbettung',
                                          isDense: true,
                                          border: OutlineInputBorder(),
                                        ),
                                        items: const [
                                          DropdownMenuItem(
                                            value: 's_feststellungen',
                                            child: Text('Feststellungen (IV)'),
                                          ),
                                          DropdownMenuItem(
                                            value: 's_objekt',
                                            child:
                                                Text('Objektbeschreibung (III)'),
                                          ),
                                          DropdownMenuItem(
                                            value: '',
                                            child: Text('Nur Lichtbildanlage'),
                                          ),
                                        ],
                                        onChanged: (v) => setState(() =>
                                            _fotoBefunde[i]
                                                    .empfohlenerAbschnitt =
                                                v ?? 's_feststellungen'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  initialValue: _fotoBefunde[i].beschreibung,
                                  minLines: 1,
                                  maxLines: 2,
                                  decoration: const InputDecoration(
                                    labelText:
                                        'Technische Befundbeschreibung zum Foto',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (v) =>
                                      _fotoBefunde[i].beschreibung = v,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // SCHRITT 4: GUTACHTEN-ABSCHNITTE (WYSIWYG) PRÜFEN
  // -------------------------------------------------------------------------
  Widget _buildStep4Abschnitte() {
    final hauptAbschnitte =
        gutachtenAbschnitte.where((a) => a.nummer > 0).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    color: Color(0xFF1D4ED8), size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Alle 13 Gutachten-Abschnitte inkl. Soll-/Ist-Tabellen, Formel-Blöcken, Foto-Einbettungen sowie dem kompletten Unterlagen-, Quellen-, Abkürzungs-, Formelzeichen- und Anlagenverzeichnis sind hier im WYSIWYG-Modus vorbereitet.',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF1E3A8A)),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(_aktualisiereVerzeichnisseUndFotosVorschau);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Verzeichnisse (Unterlagen, Normen/Quellen, Abkürzungen, Formelzeichen, Anlagen) & Foto-Einbettungen aktualisiert.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.fact_check_outlined, size: 16),
                  label: const Text('Verzeichnisse neu generieren'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final a in hauptAbschnitte) ...[
            Text(
              '${a.nummer}. ${a.label}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E3552),
              ),
            ),
            const SizedBox(height: 6),
            GutachtenInlineWysiwygField(
              controller: _abschnittCtrls[a.key]!,
              embedBuilders: kAktenwerkEmbedBuilders,
              minLines: 4,
              placeholder: a.placeholder ?? '',
              onChanged: (_) {},
              onOpenFullscreen: () {},
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          if (_step > 0 && !_analyzing && !_saving)
            OutlinedButton.icon(
              onPressed: () => setState(() => _step = _step == 2 ? 0 : _step - 1),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Zurück'),
            ),
          const Spacer(),
          TextButton(
            onPressed: (_analyzing || _saving)
                ? null
                : () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('Abbrechen'),
          ),
          const SizedBox(width: 10),
          if (_step == 0)
            FilledButton.icon(
              onPressed: _analyzing ? null : _startKiAnalyse,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text(
                'KI-Analyse starten & Datensatz ableiten',
              ),
            )
          else if (_step >= 2 && _step < 4)
            FilledButton.icon(
              onPressed: () {
                if (_step == 3) {
                  _aktualisiereVerzeichnisseUndFotosVorschau();
                }
                setState(() => _step++);
              },
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('Weiter zum nächsten Schritt'),
            )
          else if (_step == 4)
            FilledButton.icon(
              onPressed: _saving ? null : _saveCompleteDataset,
              icon: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: const Text(
                'Akte & Gutachten jetzt komplett anlegen',
              ),
            ),
        ],
      ),
    );
  }

  Widget _tf(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      style: const TextStyle(fontSize: 12.5),
    );
  }
}
