// Zusätzliche Akten-Aktionen (Menü „Mehr“ im Akten-Kopf):
// Word-Dokument aus Vorlage, Aktendeckel, Leistungs-/Kostennachweis,
// Ortstermin als Kalenderdatei (.ics) und Zusatzfelder.

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/web/datei_export.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../shared/docx/word_platzhalter.dart';
import '../../../shared/docx/word_vorlagen_engine.dart';
import '../../../shared/pdf/akten_nachweise_pdf.dart';
import '../../system/einstellungen/einstellungen_repository.dart';
import '../auftraege/auftrag_gm_extras.dart';
import '../auftraege/zusatzfelder.dart';
import '../dokumente/dokumente_repository.dart';
import 'beteiligte_tab.dart';

const _mimeDocx =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

/// Schaltfläche „Mehr“ für den Akten-Kopf.
class AkteMehrMenu extends ConsumerWidget {
  const AkteMehrMenu({super.key, required this.auftrag, this.kunde});
  final AuftraegeData auftrag;
  final KundenData? kunde;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Weitere Aktionen',
      onSelected: (v) => _ausfuehren(context, ref, v),
      itemBuilder: (_) => const [
        PopupMenuItem(
            value: 'word',
            child: ListTile(
                dense: true,
                leading: Icon(Icons.description_outlined),
                title: Text('Word-Dokument aus Vorlage …'))),
        PopupMenuDivider(),
        PopupMenuItem(
            value: 'deckel',
            child: ListTile(
                dense: true,
                leading: Icon(Icons.folder_outlined),
                title: Text('Aktendeckel (PDF)'))),
        PopupMenuItem(
            value: 'leistung',
            child: ListTile(
                dense: true,
                leading: Icon(Icons.schedule_outlined),
                title: Text('Leistungsnachweis (PDF)'))),
        PopupMenuItem(
            value: 'kosten',
            child: ListTile(
                dense: true,
                leading: Icon(Icons.receipt_long_outlined),
                title: Text('Kostennachweis (PDF)'))),
        PopupMenuDivider(),
        PopupMenuItem(
            value: 'ics',
            child: ListTile(
                dense: true,
                leading: Icon(Icons.event_outlined),
                title: Text('Ortstermin in Kalender (.ics)'))),
        PopupMenuItem(
            value: 'zusatz',
            child: ListTile(
                dense: true,
                leading: Icon(Icons.playlist_add_outlined),
                title: Text('Zusatzfelder …'))),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.more_horiz, size: 18),
          SizedBox(width: 4),
          Text('Mehr'),
        ]),
      ),
    );
  }

  Future<void> _ausfuehren(BuildContext context, WidgetRef ref, String v) async {
    final db = ref.read(appDatabaseProvider);
    final name = (auftrag.aktenzeichen ?? 'Akte').replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_');
    switch (v) {
      case 'word':
        await showDialog(
          context: context,
          useRootNavigator: true,
          builder: (_) => WordDokumentDialog(auftrag: auftrag, kunde: kunde),
        );
        break;
      case 'deckel':
        await Printing.layoutPdf(
          name: 'Aktendeckel_$name.pdf',
          onLayout: (_) => buildAktendeckelPdf(auftrag: auftrag, auftraggeber: kunde),
        );
        break;
      case 'leistung':
        final stunden = await (db.select(db.stunden)
              ..where((t) => t.auftragId.equals(auftrag.id)))
            .get();
        if (stunden.isEmpty) {
          if (!context.mounted) return;
          _hinweis(context, 'Für diese Akte sind noch keine Zeiten erfasst.');
          return;
        }
        await Printing.layoutPdf(
          name: 'Leistungsnachweis_$name.pdf',
          onLayout: (_) => buildLeistungsnachweisPdf(auftrag: auftrag, stunden: stunden),
        );
        break;
      case 'kosten':
        final auslagen = await (db.select(db.auslagen)
              ..where((t) => t.auftragId.equals(auftrag.id)))
            .get();
        if (auslagen.isEmpty) {
          if (!context.mounted) return;
          _hinweis(context, 'Für diese Akte sind noch keine Auslagen erfasst.');
          return;
        }
        await Printing.layoutPdf(
          name: 'Kostennachweis_$name.pdf',
          onLayout: (_) => buildKostennachweisPdf(auftrag: auftrag, auslagen: auslagen),
        );
        break;
      case 'ics':
        if (auftrag.ortsterminAm == null) {
          _hinweis(context, 'Für diese Akte ist noch kein Ortstermin eingetragen.');
          return;
        }
        final bytes = Uint8List.fromList(utf8.encode(ortsterminIcs(auftrag)));
        await dateiSpeichern(bytes, 'Ortstermin_$name.ics', mime: 'text/calendar');
        break;
      case 'zusatz':
        await showZusatzfelderDialog(context, ref, auftrag);
        break;
    }
  }

  void _hinweis(BuildContext context, String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

/// Ortstermin als iCalendar-Datei (Apple Kalender, Outlook, Google).
String ortsterminIcs(AuftraegeData a) {
  final gm = AuftragGmExtras.fromAuftragExtras(a.extras);
  DateTime start = a.ortsterminAm!;
  DateTime? zeit(String hhmm, DateTime tag) {
    final m = RegExp(r'^(\d{1,2})[:.](\d{2})').firstMatch(hhmm.trim());
    if (m == null) return null;
    return DateTime(tag.year, tag.month, tag.day, int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  start = zeit(gm.ortsterminUhrzeitVon, start) ?? start;
  final ganztags = start.hour == 0 && start.minute == 0 && gm.ortsterminUhrzeitVon.trim().isEmpty;
  final ende = zeit(gm.ortsterminUhrzeitBis, start) ?? start.add(const Duration(hours: 2));
  String lokal(DateTime d) => DateFormat("yyyyMMdd'T'HHmmss").format(d);
  String esc(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\n', '\\n');
  final objekt = [a.objektStrasse, [a.objektPlz, a.objektOrt].whereType<String>().join(' ')]
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .join(', ');
  final geladen = decodeBeteiligte(a.beteiligteJson)
      .where((b) => b.zumOrtsterminLaden && b.name.trim().isNotEmpty)
      .map((b) => '${b.rolle}: ${b.name}')
      .join('\n');
  final sache = buildSacheKurzbezeichnung(a);
  final zeilen = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Aktenwerk//Ortstermin//DE',
    'CALSCALE:GREGORIAN',
    'BEGIN:VEVENT',
    'UID:aktenwerk-ortstermin-${a.id}@aktenwerk.app',
    'DTSTAMP:${DateFormat("yyyyMMdd'T'HHmmss'Z'").format(DateTime.now().toUtc())}',
    if (ganztags) ...[
      'DTSTART;VALUE=DATE:${DateFormat('yyyyMMdd').format(start)}',
      'DTEND;VALUE=DATE:${DateFormat('yyyyMMdd').format(start.add(const Duration(days: 1)))}',
    ] else ...[
      'DTSTART;TZID=Europe/Berlin:${lokal(start)}',
      'DTEND;TZID=Europe/Berlin:${lokal(ende)}',
    ],
    'SUMMARY:${esc('Ortstermin ${a.aktenzeichen ?? ''} ${sache.isEmpty ? '' : '– $sache'}'.trim())}',
    if (objekt.isNotEmpty) 'LOCATION:${esc(objekt)}',
    'DESCRIPTION:${esc([
      if ((a.gerichtsAktenzeichen ?? '').isNotEmpty) 'Gerichts-Az.: ${a.gerichtsAktenzeichen}',
      if (geladen.isNotEmpty) 'Geladen:\n$geladen',
    ].join('\n'))}',
    'BEGIN:VALARM',
    'TRIGGER:-P1D',
    'ACTION:DISPLAY',
    'DESCRIPTION:Ortstermin morgen',
    'END:VALARM',
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return '${zeilen.join('\r\n')}\r\n';
}

/// Dialog: Word-Vorlage wählen, mit Aktendaten füllen, speichern/öffnen.
class WordDokumentDialog extends ConsumerStatefulWidget {
  const WordDokumentDialog({super.key, required this.auftrag, this.kunde});
  final AuftraegeData auftrag;
  final KundenData? kunde;
  @override
  ConsumerState<WordDokumentDialog> createState() => _WordDokumentDialogState();
}

class _WordDokumentDialogState extends ConsumerState<WordDokumentDialog> {
  Uint8List? _vorlage;
  String _vorlageName = '';
  bool _serienFelder = false;
  bool _serienbrief = true;
  bool _auftraggeberAuch = false;
  bool _briefkopf = true;
  bool _hatBriefkopf = false;
  bool _arbeitet = false;
  String? _fehler;
  final _titel = TextEditingController();

  @override
  void initState() {
    super.initState();
    ref.read(einstellungenRepositoryProvider).get(SettingsKeys.wordBriefkopfBase64).then((v) {
      if (mounted) setState(() => _hatBriefkopf = (v ?? '').isNotEmpty);
    });
  }

  @override
  void dispose() {
    _titel.dispose();
    super.dispose();
  }

  Future<void> _waehlen() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx'],
      withData: true,
    );
    final f = r?.files.firstOrNull;
    if (f == null || f.bytes == null) return;
    setState(() {
      _vorlage = f.bytes;
      _vorlageName = f.name;
      _serienFelder = vorlageHatSerienbriefFelder(f.bytes!);
      _titel.text =
          '${DateFormat('yyyy-MM-dd').format(DateTime.now())} ${f.name.replaceAll(RegExp(r'\.docx$', caseSensitive: false), '')}';
      _fehler = null;
    });
  }

  Future<void> _erzeugen() async {
    if (_vorlage == null) return;
    setState(() {
      _arbeitet = true;
      _fehler = null;
    });
    try {
      final settings = ref.read(einstellungenRepositoryProvider);
      final daten = await baueWordAktenDaten(
        auftrag: widget.auftrag,
        kunde: widget.kunde,
        settings: settings,
        auftraggeberAlsEmpfaenger: _auftraggeberAuch,
      );
      Uint8List? bk;
      if (_briefkopf && _hatBriefkopf) {
        final b64 = await settings.get(SettingsKeys.wordBriefkopfBase64);
        if (b64 != null && b64.isNotEmpty) bk = base64Decode(b64);
      }
      final bytes = erzeugeWordDokument(
        vorlage: _vorlage!,
        resolver: daten.resolver,
        personen: daten.personen,
        empfaenger: _serienFelder && _serienbrief ? daten.empfaenger : null,
        raute: daten.raute,
        briefkopf: bk,
        felderAktualisieren: RegExp('gutachten', caseSensitive: false).hasMatch(_vorlageName),
      );
      final dateiname =
          '${_titel.text.trim().isEmpty ? 'Dokument' : _titel.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')}.docx';
      // In der Akte ablegen (Reiter Dokumente)
      await ref.read(dokumenteRepositoryProvider).upsert(DokumenteCompanion.insert(
            titel: Value(dateiname),
            mimeType: const Value(_mimeDocx),
            dateigroesse: Value(bytes.length),
            daten: Value(bytes),
            auftragId: Value(widget.auftrag.id),
            kategorie: const Value('Word-Dokument'),
          ));
      await dateiSpeichern(bytes, dateiname, mime: _mimeDocx);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _fehler = 'Das Dokument konnte nicht erzeugt werden: $e');
    } finally {
      if (mounted) setState(() => _arbeitet = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final empfaenger = decodeBeteiligte(widget.auftrag.beteiligteJson)
        .where((b) => b.zumOrtsterminLaden && b.name.trim().isNotEmpty)
        .toList();
    return AlertDialog(
      title: const Text('Word-Dokument aus Vorlage'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Wähle eine Word-Vorlage (.docx). Platzhalter wie \$Sache, \$Aktenzeichen, '
              '\$GutachtenNr, \$Adresse, {{gerichts_az}} oder Seriendruckfelder «Name» '
              'werden mit den Daten dieser Akte gefüllt. Vorlagen aus dem Gutachten-Manager '
              'funktionieren ohne Anpassung.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: Text(_vorlage == null ? 'Vorlage wählen …' : _vorlageName),
              onPressed: _arbeitet ? null : _waehlen,
            ),
            if (_vorlage != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _titel,
                decoration: const InputDecoration(labelText: 'Dateiname', isDense: true),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _briefkopf && _hatBriefkopf,
                onChanged: _hatBriefkopf ? (v) => setState(() => _briefkopf = v ?? true) : null,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Briefkopf aus den Einstellungen einsetzen'),
                subtitle: _hatBriefkopf
                    ? null
                    : const Text('Kein Word-Briefkopf hinterlegt (Einstellungen › Word-Vorlagen)'),
              ),
              if (_serienFelder) ...[
                CheckboxListTile(
                  value: _serienbrief,
                  onChanged: (v) => setState(() => _serienbrief = v ?? true),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text('Serienbrief: ein Brief je geladenem Beteiligten (${empfaenger.length})'),
                  subtitle: empfaenger.isEmpty
                      ? const Text('Keine Beteiligten zum Ortstermin geladen.')
                      : Text(empfaenger.map((b) => b.name).join(', '),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                if (widget.kunde != null)
                  CheckboxListTile(
                    value: _auftraggeberAuch,
                    onChanged: _serienbrief ? (v) => setState(() => _auftraggeberAuch = v ?? false) : null,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Auftraggeber/Gericht zusätzlich als ersten Empfänger'),
                  ),
              ],
            ],
            if (_fehler != null) ...[
              const SizedBox(height: 8),
              Text(_fehler!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _arbeitet ? null : () => Navigator.of(context).pop(),
            child: const Text('Abbrechen')),
        FilledButton.icon(
          icon: _arbeitet
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.description_outlined, size: 18),
          label: const Text('Erstellen und öffnen'),
          onPressed: _vorlage == null || _arbeitet ? null : _erzeugen,
        ),
      ],
    );
  }
}
