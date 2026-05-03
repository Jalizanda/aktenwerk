import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ai/anschreiben_chat_service.dart';
import '../../../core/ai/rechtschreibung_service.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../data/sync/google_mail_service.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../features/akten/dokumente/dokumente_repository.dart';
import '../../../features/akten/gutachten/gutachten_repository.dart';
import '../../../features/akten/kunden/kunden_picker.dart';
import '../../../features/akten/kunden/kunden_repository.dart';
import '../../../features/werkzeuge/textbausteine/textbausteine_repository.dart';
import '../../../shared/pdf/document_pdf.dart';
import '../../../shared/richtext/quill_editor.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../features/system/einstellungen/absender_service.dart';
import '../../../features/system/einstellungen/nummernkreis_service.dart';
import '../../../shared/widgets/module_scaffold.dart';
import 'anschreiben_chat_dialog.dart';
import 'anschreiben_repository.dart';

class AnschreibenScreen extends ConsumerWidget {
  const AnschreibenScreen({super.key});
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(anschreibenListProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.drafts_outlined,
          title: 'Anschreiben',
          subtitle: 'Individuelle Schreiben an Beteiligte und Gerichte',
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.article_outlined, size: 16),
              label: const Text('Vorlagen'),
              onPressed: () => context.go('/textbausteine'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neues Anschreiben'),
              onPressed: () => _open(context, ref),
            ),
          ],
          searchHint: 'Suche Betreff, Kunde, Aktenzeichen …',
          onSearchChanged: (v) =>
              ref.read(anschreibenQueryProvider.notifier).state = v,
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (items) => items.isEmpty
                ? const EmptyListState(
                    icon: Icons.drafts_outlined,
                    title: 'Keine Anschreiben')
                : DataTableCard(
                    child: DataTable(
              showCheckboxColumn: false,
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      columns: const [
                        DataColumn(label: Text('Datum')),
                        DataColumn(label: Text('Betreff')),
                        DataColumn(label: Text('Empfänger')),
                        DataColumn(label: Text('Aktenzeichen')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final a in items)
                          DataRow(
                            onSelectChanged: (_) => _open(context, ref, a),
                            cells: [
                              DataCell(Text(_dateFmt.format(a.anschreiben.datum))),
                              DataCell(Text(a.anschreiben.betreff ?? '')),
                              DataCell(Text(a.kunde == null
                                  ? ''
                                  : kundeAnzeigename(a.kunde!))),
                              DataCell(
                                  Text(a.auftrag?.aktenzeichen ?? '')),
                              DataCell(Text(a.anschreiben.status)),
                              DataCell(IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                onPressed: () async => ref
                                    .read(anschreibenRepositoryProvider)
                                    .delete(a.anschreiben.id),
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

  Future<void> _open(BuildContext context, WidgetRef ref,
      [AnschreibenWithKunde? a]) async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => _AnschreibenEditor(eintrag: a),
    );
  }
}

/// Öffnet den Anschreiben-Editor als Dialog. Wird auch aus dem
/// Akten-Tab aufgerufen — dann werden `prefillAuftragId` und
/// `prefillKundeId` als Vorbelegung mitgegeben.
Future<void> showAnschreibenEditor(
  BuildContext context, {
  AnschreibenWithKunde? eintrag,
  int? prefillAuftragId,
  int? prefillKundeId,
}) async {
  await showDialog(
    context: context,
    useRootNavigator: true,
    builder: (_) => _AnschreibenEditor(
      eintrag: eintrag,
      prefillAuftragId: prefillAuftragId,
      prefillKundeId: prefillKundeId,
    ),
  );
}

class _AnschreibenEditor extends ConsumerStatefulWidget {
  const _AnschreibenEditor({
    this.eintrag,
    this.prefillAuftragId,
    this.prefillKundeId,
  });
  final AnschreibenWithKunde? eintrag;
  final int? prefillAuftragId;
  final int? prefillKundeId;
  @override
  ConsumerState<_AnschreibenEditor> createState() =>
      _AnschreibenEditorState();
}

class _AnschreibenEditorState extends ConsumerState<_AnschreibenEditor> {
  late final _betreff = TextEditingController(
      text: widget.eintrag?.anschreiben.betreff ?? '');
  late final _anrede = TextEditingController(
      text: widget.eintrag?.anschreiben.anrede ?? '');
  late final _gruss = TextEditingController(
      text: widget.eintrag?.anschreiben.gruss ?? 'Mit freundlichen Grüßen');
  int? _kundeId;
  int? _auftragId;
  DateTime _datum = DateTime.now();
  String _status = 'entwurf';
  String? _inhaltJson;
  bool _saving = false;
  bool _pruefeLaeuft = false;

  static const _statusValues = ['entwurf', 'versendet', 'abgelegt'];

  @override
  void initState() {
    super.initState();
    final a = widget.eintrag?.anschreiben;
    _kundeId = a?.kundeId ?? widget.prefillKundeId;
    _auftragId = a?.auftragId ?? widget.prefillAuftragId;
    _datum = a?.datum ?? DateTime.now();
    _status = a?.status ?? 'entwurf';
    _inhaltJson = a?.inhaltJson;
  }

  @override
  void dispose() {
    _betreff.dispose();
    _anrede.dispose();
    _gruss.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.eintrag != null;

  Future<void> _save() async {
    setState(() => _saving = true);
    final companion = AnschreibenCompanion(
      id: _isEdit
          ? Value(widget.eintrag!.anschreiben.id)
          : const Value.absent(),
      kundeId: Value(_kundeId),
      auftragId: Value(_auftragId),
      datum: Value(_datum),
      status: Value(_status),
      betreff: Value(_betreff.text.trim().isEmpty
          ? null
          : _betreff.text.trim()),
      anrede: Value(
          _anrede.text.trim().isEmpty ? null : _anrede.text.trim()),
      gruss: Value(
          _gruss.text.trim().isEmpty ? null : _gruss.text.trim()),
      inhaltJson: Value(_inhaltJson),
    );
    try {
      await ref.read(anschreibenRepositoryProvider).upsert(companion);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Anschreiben gespeichert')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    }
  }

  /// Baut die Anschreiben-PDF-Daten (Empfänger, Akte, Absender) aus dem
  /// aktuellen Editor-Stand zusammen. Optional mit überschriebener
  /// Belegnummer (für den Druck-Pfad, der erst die D-Nummer vergibt).
  Future<AnschreibenPdfData> _baueAnschreibenPdfData({
    String? dokumentNr,
  }) async {
    final db = ref.read(appDatabaseProvider);
    KundenData? kunde;
    final kid = _kundeId;
    if (kid != null) {
      kunde = await (db.select(db.kunden)..where((t) => t.id.equals(kid)))
          .getSingleOrNull();
    }
    AuftraegeData? auftrag;
    if (_auftragId != null) {
      auftrag = await (db.select(db.auftraege)
            ..where((t) => t.id.equals(_auftragId!)))
          .getSingleOrNull();
    }
    final absender = await absenderFromSettings(ref);
    final brieftext = plainTextFromDeltaJson(_inhaltJson);
    return AnschreibenPdfData(
      dokumentNr: dokumentNr ?? widget.eintrag?.anschreiben.belegNr,
      datum: _datum,
      betreff: _betreff.text.trim().isEmpty ? null : _betreff.text.trim(),
      aktenzeichen: auftrag?.aktenzeichen,
      anrede: _anrede.text.trim().isEmpty ? null : _anrede.text.trim(),
      briefText: brieftext.isEmpty ? null : brieftext,
      gruss: _gruss.text.trim().isEmpty ? null : _gruss.text.trim(),
      absender: absender,
      empfaenger: kunde,
      gericht: auftrag?.gericht,
      gerichtsAktenzeichen: auftrag?.gerichtsAktenzeichen,
      klaeger: auftrag?.klaeger,
      beklagter: auftrag?.beklagter,
    );
  }

  /// Öffnet die PDF-Vorschau (Print-Dialog) für das aktuell angezeigte
  /// Anschreiben. Speichert vorher NICHT — du siehst den aktuellen
  /// Editor-Stand.
  Future<void> _previewPdf() async {
    final daten = await _baueAnschreibenPdfData();
    if (!mounted) return;
    await previewAnschreibenPdf(daten);
  }

  /// Druckt das Anschreiben, vergibt eine fortlaufende D-Nummer aus dem
  /// Dokument-Nummernkreis, friert das Anschreiben ein (Status „versendet"
  /// + `gedrucktAm`) und legt das PDF als Akten-Dokument unter Kategorie
  /// „Anschreiben (Ausgang)" ab.
  Future<int?> _druckenUndArchivieren() async {
    if (_saving) return null;
    setState(() => _saving = true);
    try {
      final repo = ref.read(anschreibenRepositoryProvider);
      // Erst speichern, falls noch nicht im _save() durchgelaufen.
      final db = ref.read(appDatabaseProvider);
      // Belegnummer: bestehende behalten, sonst neue ziehen.
      var belegNr = widget.eintrag?.anschreiben.belegNr;
      if (belegNr == null || belegNr.isEmpty) {
        belegNr = await ref
            .read(nummernkreisServiceProvider)
            .nextNumber(NummernkreisTyp.dokument);
      }
      final companion = AnschreibenCompanion(
        id: _isEdit
            ? Value(widget.eintrag!.anschreiben.id)
            : const Value.absent(),
        kundeId: Value(_kundeId),
        auftragId: Value(_auftragId),
        datum: Value(_datum),
        status: const Value('versendet'),
        gedrucktAm: Value(DateTime.now()),
        belegNr: Value(belegNr),
        betreff: Value(_betreff.text.trim().isEmpty
            ? null
            : _betreff.text.trim()),
        anrede: Value(
            _anrede.text.trim().isEmpty ? null : _anrede.text.trim()),
        gruss: Value(
            _gruss.text.trim().isEmpty ? null : _gruss.text.trim()),
        inhaltJson: Value(_inhaltJson),
      );
      final id = await repo.upsert(companion);

      // PDF erzeugen.
      final daten = await _baueAnschreibenPdfData(dokumentNr: belegNr);
      final bytes = await buildAnschreibenPdf(daten);

      // PDF in der Akte ablegen — Kategorie „Anschreiben (Ausgang)".
      if (_auftragId != null) {
        final dateiname =
            '${belegNr}_${(_betreff.text.trim().isEmpty ? "Anschreiben" : _betreff.text.trim()).replaceAll(RegExp(r"[^A-Za-z0-9-_]"), "_")}.pdf';
        await ref.read(dokumenteRepositoryProvider).upsert(
              DokumenteCompanion.insert(
                titel: Value(dateiname),
                mimeType: const Value('application/pdf'),
                dateigroesse: Value(bytes.length),
                daten: Value(bytes),
                auftragId: Value(_auftragId!),
                kategorie: const Value('Anschreiben (Ausgang)'),
                datum: Value(DateTime.now()),
                beschreibung: Value(_betreff.text.trim()),
              ),
            );
      }

      // Editor-State aktualisieren, damit Folgeklicks die D-Nummer sehen.
      if (mounted) {
        setState(() {
          _status = 'versendet';
        });
      }

      // Druck-Dialog öffnen.
      await previewAnschreibenPdf(daten);

      // Counter an höchste vergebene D-Nummer angleichen (defensiv,
      // wenn jemand den Zähler manuell verändert hat).
      final all = await db.select(db.anschreiben).get();
      await ref
          .read(nummernkreisServiceProvider)
          .syncCounterToHighestUsed(
              NummernkreisTyp.dokument, all.map((a) => a.belegNr));

      if (!mounted) return id;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Anschreiben $belegNr eingefroren und als PDF in der Akte abgelegt.')));
      return id;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Lädt das aktuelle PDF herunter und öffnet das Standard-Mailprogramm
  /// vorbefüllt mit Empfänger-Mail, Betreff und einem kurzen Begleittext.
  /// Anhang muss aus dem Download-Ordner manuell angefügt werden — ein
  /// Browser kann mit `mailto:` keine Attachments übergeben.
  Future<void> _mailen() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // Erst drucken & archivieren, damit eine D-Nummer existiert und
      // das PDF im Download-Ordner liegt.
      final daten = await _baueAnschreibenPdfData(
          dokumentNr: widget.eintrag?.anschreiben.belegNr);
      final bytes = await buildAnschreibenPdf(daten);
      final dateiname =
          '${daten.dokumentNr ?? "Anschreiben"}_${(daten.betreff ?? "Anschreiben").replaceAll(RegExp(r"[^A-Za-z0-9-_]"), "_")}.pdf';
      await Printing.sharePdf(bytes: bytes, filename: dateiname);

      // Mailto öffnen.
      final empfaengerMail = daten.empfaenger?.email ?? '';
      final betreff = daten.betreff ?? 'Schreiben';
      final body = StringBuffer()
        ..writeln(daten.anrede ?? 'Sehr geehrte Damen und Herren,')
        ..writeln()
        ..writeln(
            'anbei übersende ich Ihnen das Schreiben${(daten.aktenzeichen ?? "").isNotEmpty ? " in der Sache ${daten.aktenzeichen}" : ""}.')
        ..writeln()
        ..writeln(
            'Den heruntergeladenen PDF-Anhang ($dateiname) bitte vor dem Senden manuell anhängen.')
        ..writeln()
        ..writeln(daten.gruss ?? 'Mit freundlichen Grüßen')
        ..writeln(
            [daten.absender?.vorname, daten.absender?.nachname].whereType<String>().where((s) => s.trim().isNotEmpty).join(' '));

      final uri = Uri(
        scheme: 'mailto',
        path: empfaengerMail,
        query: _encodeMailtoQuery({
          'subject': betreff,
          'body': body.toString(),
        }),
      );
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Kein Mailprogramm gefunden. PDF wurde heruntergeladen.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _encodeMailtoQuery(Map<String, String> params) =>
      params.entries
          .map((e) =>
              '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');

  /// Sendet das Anschreiben direkt über Gmail mit angehängtem PDF.
  /// Vergibt vorher (falls noch nicht geschehen) eine D-Belegnummer und
  /// archiviert das PDF in der Akte — analog zum „Drucken & in Akte
  /// ablegen"-Flow. Setzt den Status auf „versendet".
  Future<void> _gmailSenden() async {
    if (_saving) return;
    final mailService = ref.read(googleMailServiceProvider);
    final connected = await mailService.isConnected();
    if (!connected) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (_) => AlertDialog(
          title: const Text('Gmail verbinden?'),
          content: const Text(
              'Aktenwerk benötigt einmalig die Berechtigung „E-Mails in '
              'deinem Namen senden", um Anschreiben mit Anhang direkt '
              'aus der App zu verschicken. Die Mail erscheint danach in '
              'deinem Gmail-„Gesendet"-Ordner.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Gmail verbinden')),
          ],
        ),
      );
      if (ok != true) return;
      try {
        final ok2 = await mailService.connect();
        if (!ok2) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Gmail-Verbindung abgebrochen.')));
          return;
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(anschreibenRepositoryProvider);

      // Belegnummer ziehen, falls noch nicht vorhanden.
      var belegNr = widget.eintrag?.anschreiben.belegNr;
      if (belegNr == null || belegNr.isEmpty) {
        belegNr = await ref
            .read(nummernkreisServiceProvider)
            .nextNumber(NummernkreisTyp.dokument);
      }

      // Editor-State persistieren (eingefroren).
      final companion = AnschreibenCompanion(
        id: _isEdit
            ? Value(widget.eintrag!.anschreiben.id)
            : const Value.absent(),
        kundeId: Value(_kundeId),
        auftragId: Value(_auftragId),
        datum: Value(_datum),
        status: const Value('versendet'),
        gedrucktAm: Value(DateTime.now()),
        belegNr: Value(belegNr),
        betreff: Value(_betreff.text.trim().isEmpty
            ? null
            : _betreff.text.trim()),
        anrede: Value(
            _anrede.text.trim().isEmpty ? null : _anrede.text.trim()),
        gruss: Value(
            _gruss.text.trim().isEmpty ? null : _gruss.text.trim()),
        inhaltJson: Value(_inhaltJson),
      );
      await repo.upsert(companion);

      // PDF erzeugen + in Akte ablegen.
      final daten = await _baueAnschreibenPdfData(dokumentNr: belegNr);
      final bytes = await buildAnschreibenPdf(daten);
      final empfaengerEmail = (daten.empfaenger?.email ?? '').trim();
      if (empfaengerEmail.isEmpty) {
        throw StateError(
            'Empfänger hat keine E-Mail-Adresse hinterlegt. '
            'Bitte zuerst beim Kontakt eintragen.');
      }
      final betreff = daten.betreff?.isNotEmpty == true
          ? daten.betreff!
          : 'Schreiben';
      final dateiname =
          '${belegNr}_${betreff.replaceAll(RegExp(r"[^A-Za-z0-9-_]"), "_")}.pdf';

      if (_auftragId != null) {
        await ref.read(dokumenteRepositoryProvider).upsert(
              DokumenteCompanion.insert(
                titel: Value(dateiname),
                mimeType: const Value('application/pdf'),
                dateigroesse: Value(bytes.length),
                daten: Value(bytes),
                auftragId: Value(_auftragId!),
                kategorie: const Value('Anschreiben (Ausgang)'),
                datum: Value(DateTime.now()),
                beschreibung: Value(betreff),
              ),
            );
      }

      // Mail-Body bauen.
      final body = StringBuffer()
        ..writeln(daten.anrede ?? 'Sehr geehrte Damen und Herren,')
        ..writeln()
        ..writeln(
            'anbei übersende ich Ihnen das Schreiben${(daten.aktenzeichen ?? "").isNotEmpty ? " in der Sache ${daten.aktenzeichen}" : ""} (Beleg-Nr. $belegNr).')
        ..writeln()
        ..writeln(daten.gruss ?? 'Mit freundlichen Grüßen')
        ..writeln(
            [daten.absender?.vorname, daten.absender?.nachname].whereType<String>().where((s) => s.trim().isNotEmpty).join(' '));

      await mailService.sendMessage(
        to: empfaengerEmail,
        subject: betreff,
        body: body.toString(),
        attachment: GmailAttachment(
          filename: dateiname,
          mimeType: 'application/pdf',
          bytes: bytes,
        ),
      );

      if (mounted) {
        setState(() => _status = 'versendet');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Anschreiben $belegNr per Gmail an $empfaengerEmail versendet und in der Akte abgelegt.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Öffnet den KI-Chat zum Entwerfen eines Anschreibens. Nimmt dem
  /// Editor-Kontext (Empfänger, Akte, Betreff, Absender) mit, damit
  /// Anrede, Aktenzeichen und Objektreferenz direkt korrekt gesetzt
  /// werden. Beim Übernehmen wird der Entwurf als Quill-Delta in den
  /// Editor geladen.
  Future<void> _kiEntwerfen() async {
    final db = ref.read(appDatabaseProvider);
    AuftraegeData? auftrag;
    if (_auftragId != null) {
      auftrag = await (db.select(db.auftraege)
            ..where((t) => t.id.equals(_auftragId!)))
          .getSingleOrNull();
    }
    KundenData? kunde;
    final kid = _kundeId ?? auftrag?.kundeId;
    if (kid != null) {
      kunde = await (db.select(db.kunden)..where((t) => t.id.equals(kid)))
          .getSingleOrNull();
    }
    final absender = await absenderFromSettings(ref);
    if (!mounted) return;
    final entwurf = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AnschreibenChatDialog(
        kontext: AnschreibenKontext(
          kunde: kunde,
          auftrag: auftrag,
          absender: absender,
          betreff: _betreff.text.trim().isEmpty ? null : _betreff.text.trim(),
        ),
      ),
    );
    if (entwurf == null || entwurf.trim().isEmpty) return;
    if (!mounted) return;
    setState(() {
      _inhaltJsonKey++;
      _inhaltJson = _plaintextZuDelta(entwurf.trim());
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('KI-Entwurf übernommen — bei Bedarf noch anpassen.')),
    );
  }

  Future<void> _vorlageEinfuegen() async {
    final picked = await showDialog<TextbausteineData>(
      context: context,
      useRootNavigator: true,
      builder: (_) => const _AnschreibenVorlagePicker(),
    );
    if (picked == null) return;

    // Akte/Kunde laden, um Platzhalter wie {{aktenzeichen}}, {{gericht}},
    // {{heute}} etc. automatisch zu füllen. Läuft leer, wenn nichts gewählt
    // ist — die Platzhalter bleiben dann einfach als Text stehen.
    final db = ref.read(appDatabaseProvider);
    AuftraegeData? auftrag;
    if (_auftragId != null) {
      auftrag = await (db.select(db.auftraege)
            ..where((t) => t.id.equals(_auftragId!)))
          .getSingleOrNull();
    }
    KundenData? kunde;
    final kid = _kundeId ?? auftrag?.kundeId;
    if (kid != null) {
      kunde = await (db.select(db.kunden)..where((t) => t.id.equals(kid)))
          .getSingleOrNull();
    }

    final raw = picked.inhalt ?? '';
    final isDelta = raw.trim().startsWith('[');
    final substituiert = isDelta
        ? applyVorlagenPlatzhalterImDelta(raw, auftrag: auftrag, kunde: kunde)
        : applyVorlagenPlatzhalter(raw, auftrag: auftrag, kunde: kunde);
    final betreffSubst = applyVorlagenPlatzhalter(picked.titel,
        auftrag: auftrag, kunde: kunde);

    if (!mounted) return;
    setState(() {
      if (_betreff.text.trim().isEmpty && betreffSubst.isNotEmpty) {
        _betreff.text = betreffSubst;
      }
      _inhaltJsonKey++;
      _inhaltJson = substituiert;
    });
  }

  int _inhaltJsonKey = 0;

  /// Ruft den gewählten KI-Modus auf, zeigt einen Review-Dialog und
  /// übernimmt das Ergebnis in den Editor, wenn der Nutzer zustimmt.
  Future<void> _kiAnwenden(KiModus modus) async {
    final original = plainTextFromDeltaJson(_inhaltJson);
    if (original.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Bitte zuerst einen Text eingeben.')),
      );
      return;
    }

    setState(() => _pruefeLaeuft = true);
    String ergebnis;
    try {
      ergebnis = await kiAnwenden(ref, original, modus);
    } catch (e) {
      if (mounted) {
        setState(() => _pruefeLaeuft = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('KI-Aufruf fehlgeschlagen: $e')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _pruefeLaeuft = false);

    if (ergebnis.trim() == original.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(modus == KiModus.korrektur
              ? 'Keine Fehler gefunden — Text bleibt unverändert.'
              : 'KI hat keine Änderung vorgeschlagen.'),
        ),
      );
      return;
    }

    final uebernehmen = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _KorrekturReviewDialog(
        modus: modus,
        original: original,
        korrigiert: ergebnis,
      ),
    );
    if (uebernehmen != true) return;

    // Ergebnis als neues Quill-Delta ablegen. Jeder Absatz wird
    // als eigener Insert gespeichert. Formatierungen (fett, kursiv etc.)
    // gehen dabei verloren — Anschreiben sind typischerweise Fließtext.
    final neuesDelta = _plaintextZuDelta(ergebnis);
    setState(() {
      _inhaltJsonKey++;
      _inhaltJson = neuesDelta;
    });
  }

  IconData _kiIcon(KiModus m) => switch (m) {
        KiModus.korrektur => Icons.spellcheck,
        KiModus.umformulieren => Icons.edit_note,
        KiModus.juristisch => Icons.gavel,
        KiModus.kuerzen => Icons.compress,
        KiModus.erweitern => Icons.expand,
      };

  /// Baut ein Quill-Delta-JSON aus reinem Text. Jede Zeile wird als
  /// eigener Insert mit abschließendem `\n` gespeichert.
  String _plaintextZuDelta(String text) {
    final zeilen = text.split('\n');
    final ops = <Map<String, dynamic>>[];
    for (var i = 0; i < zeilen.length; i++) {
      final z = zeilen[i];
      if (z.isNotEmpty) ops.add({'insert': z});
      ops.add({'insert': '\n'});
    }
    if (ops.isEmpty) ops.add({'insert': '\n'});
    return jsonEncode(ops);
  }

  @override
  Widget build(BuildContext context) {
    return StandardFormDialog(
      title: _isEdit ? 'Anschreiben bearbeiten' : 'Neues Anschreiben',
      icon: Icons.drafts_outlined,
      maxWidth: 980,
      maxHeight: 820,
      saving: _saving,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(false),
      onSave: _save,
      onDelete: _isEdit
          ? () async => ref
              .read(anschreibenRepositoryProvider)
              .delete(widget.eintrag!.anschreiben.id)
          : null,
      footerLeading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.remove_red_eye_outlined, size: 16),
            label: const Text('Vorschau'),
            onPressed: _saving ? null : _previewPdf,
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            icon: const Icon(Icons.article_outlined, size: 16),
            label: const Text('Vorlage einfügen …'),
            onPressed: _vorlageEinfuegen,
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            icon: const Icon(Icons.send_outlined, size: 16),
            label: const Text('Mit Gmail senden'),
            onPressed: _saving ? null : _gmailSenden,
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            icon: const Icon(Icons.email_outlined, size: 16),
            label: const Text('Mail-App'),
            onPressed: _saving ? null : _mailen,
          ),
          const SizedBox(width: 6),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row3(
              a: DateField(
                  label: 'Datum',
                  value: _datum,
                  onChanged: (v) =>
                      setState(() => _datum = v ?? DateTime.now())),
              b: LabeledField(
                'Status',
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  isDense: true,
                  items: [
                    for (final s in _statusValues)
                      DropdownMenuItem(value: s, child: Text(s)),
                  ],
                  onChanged: (v) =>
                      setState(() => _status = v ?? 'entwurf'),
                ),
              ),
              c: KundenPickerField(
                kundeId: _kundeId,
                onChanged: (id) => setState(() => _kundeId = id),
                label: 'Empfänger',
              ),
            ),
            const SizedBox(height: 12),
            Row2(
              left: AuftragPickerField(
                auftragId: _auftragId,
                label: 'Akte',
                onChanged: (id) => setState(() => _auftragId = id),
              ),
              right: LabeledField(
                'Betreff',
                TextFormField(controller: _betreff),
              ),
            ),
            const SizedBox(height: 12),
            Row2(
              left: LabeledField(
                'Briefanrede',
                TextFormField(
                  controller: _anrede,
                  decoration: const InputDecoration(
                    hintText: 'Sehr geehrte Frau …,',
                  ),
                ),
              ),
              right: LabeledField(
                'Grußformel',
                TextFormField(
                    controller: _gruss, minLines: 2, maxLines: 4),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Inhalt',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('KI Schreiben entwerfen'),
                  onPressed: _pruefeLaeuft ? null : _kiEntwerfen,
                ),
                const SizedBox(width: 8),
                PopupMenuButton<KiModus>(
                  enabled: !_pruefeLaeuft,
                  tooltip: 'KI-Assistent',
                  position: PopupMenuPosition.under,
                  onSelected: _kiAnwenden,
                  itemBuilder: (_) => [
                    for (final m in KiModus.values)
                      PopupMenuItem(
                        value: m,
                        child: Row(
                          children: [
                            Icon(_kiIcon(m), size: 18),
                            const SizedBox(width: 10),
                            Text(m.label),
                          ],
                        ),
                      ),
                  ],
                  child: OutlinedButton.icon(
                    onPressed: null, // Button dient nur als Anker fürs Popup
                    icon: _pruefeLaeuft
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high, size: 16),
                    label: Text(
                        _pruefeLaeuft ? 'KI arbeitet …' : 'KI-Assistent'),
                    style: OutlinedButton.styleFrom(
                      disabledForegroundColor:
                          Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            RichTextEditor(
              key: ValueKey('anschreiben-inhalt-$_inhaltJsonKey'),
              initialDeltaJson: _inhaltJson,
              onChanged: (json) => _inhaltJson = json,
              minHeight: 360,
              placeholder: 'Anschreiben hier verfassen …',
            ),
          ],
        ),
      ),
    );
  }
}

/// Vorlagen-Picker für Anschreiben — zeigt alle Textbausteine der
/// Kategorie "anschreiben", mit Suche. Auswählen übernimmt den Inhalt.
class _AnschreibenVorlagePicker extends ConsumerStatefulWidget {
  const _AnschreibenVorlagePicker();
  @override
  ConsumerState<_AnschreibenVorlagePicker> createState() =>
      _AnschreibenVorlagePickerState();
}

class _AnschreibenVorlagePickerState
    extends ConsumerState<_AnschreibenVorlagePicker> {
  String _query = '';
  bool _nurKategorie = true;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(textbausteineListProvider);
    return Dialog(
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.article_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Vorlage einfügen',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Vorlagen verwalten'),
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).pop();
                      GoRouter.of(context).go('/textbausteine');
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 20),
                        hintText: 'Titel oder Inhalt …',
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Row(
                    children: [
                      Checkbox(
                        value: _nurKategorie,
                        onChanged: (v) =>
                            setState(() => _nurKategorie = v ?? true),
                      ),
                      const Text('nur "anschreiben"',
                          style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Fehler: $e')),
                data: (items) {
                  final q = _query.trim().toLowerCase();
                  final filtered = items.where((b) {
                    if (_nurKategorie) {
                      final kat = (b.kategorie ?? '').toLowerCase();
                      final sg = (b.sachgebiet ?? '').toLowerCase();
                      if (kat != 'anschreiben' && sg != 'anschreiben') {
                        return false;
                      }
                    }
                    if (q.isEmpty) return true;
                    return b.titel.toLowerCase().contains(q) ||
                        (b.kategorie ?? '').toLowerCase().contains(q) ||
                        plainTextFromDeltaJson(b.inhalt)
                            .toLowerCase()
                            .contains(q);
                  }).toList();
                  if (filtered.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Keine Anschreiben-Vorlagen vorhanden.\n'
                          'Lege welche unter Werkzeuge → Textbausteine an '
                          '(Kategorie "anschreiben").',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final b = filtered[i];
                      final vorschau = plainTextFromDeltaJson(b.inhalt)
                          .replaceAll(RegExp(r'\s+'), ' ')
                          .trim();
                      return ListTile(
                        dense: true,
                        title: Text(b.titel,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          vorschau,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () =>
                            Navigator.of(context, rootNavigator: true)
                                .pop(b),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Zeigt den Original- und den KI-Vorschlag nebeneinander. Der Nutzer
/// bestätigt mit „Übernehmen" oder verwirft mit „Abbrechen".
class _KorrekturReviewDialog extends StatelessWidget {
  const _KorrekturReviewDialog({
    required this.modus,
    required this.original,
    required this.korrigiert,
  });
  final KiModus modus;
  final String original;
  final String korrigiert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.auto_fix_high, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'KI-Vorschlag: ${modus.label}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context,
                            rootNavigator: true)
                        .pop(false),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _TextSpalte(
                        label: 'Original',
                        text: original,
                        farbe: scheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _TextSpalte(
                        label: modus.kurzLabel,
                        text: korrigiert,
                        farbe: scheme.primaryContainer,
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
                  Text(
                    'Hinweis: Inline-Formatierungen (fett, kursiv, Listen) '
                    'gehen beim Übernehmen verloren.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context,
                            rootNavigator: true)
                        .pop(false),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Übernehmen'),
                    onPressed: () => Navigator.of(context,
                            rootNavigator: true)
                        .pop(true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextSpalte extends StatelessWidget {
  const _TextSpalte({
    required this.label,
    required this.text,
    required this.farbe,
  });
  final String label;
  final String text;
  final Color farbe;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: farbe,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                text,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
