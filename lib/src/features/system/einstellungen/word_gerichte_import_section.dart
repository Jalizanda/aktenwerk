import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database_provider.dart';
import '../../../data/seed/gerichte.dart';
import 'einstellungen_repository.dart';
import 'gm_import.dart';

/// Einstellungen: Word-Briefkopf, Gerichtsverzeichnis-Import und
/// Datenübernahme aus dem Gutachten-Manager.
class WordGerichteImportSection extends ConsumerStatefulWidget {
  const WordGerichteImportSection({super.key});
  @override
  ConsumerState<WordGerichteImportSection> createState() =>
      _WordGerichteImportSectionState();
}

class _WordGerichteImportSectionState
    extends ConsumerState<WordGerichteImportSection> {
  String? _briefkopfName;
  int _gerichteImportiert = 0;
  bool _busy = false;
  String? _meldung;
  bool _fehler = false;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    final repo = ref.read(einstellungenRepositoryProvider);
    final name = await repo.get(SettingsKeys.wordBriefkopfName);
    final n = await GerichteRepository.instance.importierteAnzahl();
    if (mounted) {
      setState(() {
        _briefkopfName = name;
        _gerichteImportiert = n;
      });
    }
  }

  void _melde(String text, {bool fehler = false}) =>
      setState(() {
        _meldung = text;
        _fehler = fehler;
      });

  Future<void> _briefkopfWaehlen() async {
    final r = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['docx'], withData: true);
    final f = r?.files.firstOrNull;
    if (f?.bytes == null) return;
    if (f!.bytes!.length > 850 * 1024) {
      _melde('Die Briefkopf-Datei ist zu groß (max. 850 KB). Bitte Bilder darin verkleinern.',
          fehler: true);
      return;
    }
    final repo = ref.read(einstellungenRepositoryProvider);
    await repo.set(SettingsKeys.wordBriefkopfBase64, base64Encode(f.bytes!));
    await repo.set(SettingsKeys.wordBriefkopfName, f.name);
    setState(() => _briefkopfName = f.name);
    _melde('Briefkopf „${f.name}“ gespeichert.');
  }

  Future<void> _briefkopfEntfernen() async {
    final repo = ref.read(einstellungenRepositoryProvider);
    await repo.set(SettingsKeys.wordBriefkopfBase64, null);
    await repo.set(SettingsKeys.wordBriefkopfName, null);
    setState(() => _briefkopfName = null);
    _melde('Briefkopf entfernt.');
  }

  Future<void> _gerichteImportieren() async {
    final r = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['csv', 'json'], withData: true);
    final f = r?.files.firstOrNull;
    if (f?.bytes == null) return;
    try {
      final liste = parseGerichteDatei(f!.name, f.bytes!);
      if (liste.isEmpty) {
        _melde('In der Datei wurden keine Gerichte erkannt. Erwartet wird eine Spalte „name“ '
            '(oder „GerichtAnschrift1“) sowie Straße, PLZ, Ort.', fehler: true);
        return;
      }
      await GerichteRepository.instance.importieren(liste);
      setState(() => _gerichteImportiert = liste.length);
      final at = liste.where((g) => g.land == 'AT').length;
      _melde('${liste.length} Gerichte importiert${at > 0 ? ' (davon $at in Österreich)' : ''}.');
    } catch (e) {
      _melde('Import fehlgeschlagen: $e', fehler: true);
    }
  }

  Future<void> _gerichteLoeschen() async {
    await GerichteRepository.instance.importLoeschen();
    setState(() => _gerichteImportiert = 0);
    _melde('Importierte Gerichte entfernt. Es gilt wieder das mitgelieferte Verzeichnis.');
  }

  Future<void> _gmImport() async {
    final r = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['csv'], allowMultiple: true, withData: true);
    if (r == null || r.files.isEmpty) return;
    final dateien = <String, Uint8List>{
      for (final f in r.files)
        if (f.bytes != null) f.name: f.bytes!,
    };
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: const Text('Daten aus dem Gutachten-Manager übernehmen?'),
        content: Text(
          '${dateien.length} CSV-Dateien ausgewählt. Akten, Auftraggeber, Beteiligte, Zeiten und '
          'Auslagen werden neu angelegt. Akten mit bereits vorhandenem Aktenzeichen werden '
          'übersprungen. Rechnungen werden nicht übernommen.\n\n'
          'Tipp: Vorher unter „Backup & Wiederherstellung“ eine Sicherung erstellen.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Übernehmen')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final bericht = await gmImportAusfuehren(ref.read(appDatabaseProvider), dateien);
      _melde([bericht.toString(), ...bericht.hinweise].join('\n'),
          fehler: bericht.akten == 0 && bericht.uebersprungen == 0);
    } catch (e) {
      _melde('Übernahme fehlgeschlagen: $e', fehler: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget zeile(String titel, String text, List<Widget> knoepfe) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titel, style: t.titleSmall),
            const SizedBox(height: 2),
            Text(text, style: t.bodySmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: knoepfe),
          ]),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        zeile(
          'Word-Briefkopf',
          _briefkopfName == null
              ? 'Kein Briefkopf hinterlegt. Eine .docx mit deinem Briefkopf in Kopf- und Fußzeile; '
                  'sie wird beim Erstellen von Word-Dokumenten (Akte › Mehr › Word-Dokument) eingesetzt.'
              : 'Aktuell: $_briefkopfName',
          [
            OutlinedButton.icon(
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: Text(_briefkopfName == null ? 'Briefkopf hochladen' : 'Briefkopf ersetzen'),
              onPressed: _busy ? null : _briefkopfWaehlen,
            ),
            if (_briefkopfName != null)
              TextButton(onPressed: _busy ? null : _briefkopfEntfernen, child: const Text('Entfernen')),
          ],
        ),
        zeile(
          'Gerichtsverzeichnis',
          _gerichteImportiert == 0
              ? 'Mitgeliefert sind die wichtigsten Gerichte. Eine vollständige Liste (CSV oder JSON, '
                  'z. B. aus deinem Gutachten-Manager-Export) kannst du hier lokal ergänzen – '
                  'auch österreichische Gerichte.'
              : '$_gerichteImportiert Gerichte importiert (ergänzen das mitgelieferte Verzeichnis).',
          [
            OutlinedButton.icon(
              icon: const Icon(Icons.account_balance_outlined, size: 18),
              label: const Text('Gerichte importieren (CSV/JSON)'),
              onPressed: _busy ? null : _gerichteImportieren,
            ),
            if (_gerichteImportiert > 0)
              TextButton(onPressed: _busy ? null : _gerichteLoeschen, child: const Text('Import entfernen')),
          ],
        ),
        zeile(
          'Datenübernahme aus dem Gutachten-Manager',
          'Die Access-Datenbank (GutachterDBV80.mdb) zuerst als CSV exportieren – je Tabelle eine '
              'Datei, z. B. mit tool/gm_export.sh (mdbtools). Dann hier alle CSV-Dateien auswählen.',
          [
            FilledButton.tonalIcon(
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.move_down_outlined, size: 18),
              label: const Text('CSV-Dateien auswählen und übernehmen'),
              onPressed: _busy ? null : _gmImport,
            ),
          ],
        ),
        if (_meldung != null)
          Text(_meldung!,
              style: t.bodySmall?.copyWith(
                  color: _fehler ? Theme.of(context).colorScheme.error : Colors.green.shade700)),
      ],
    );
  }
}
