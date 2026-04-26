import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/beleg_extraktion_service.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../data/sync/storage_service.dart';

/// Dialog für die KI-basierte Massen-Belegerfassung.
/// Ablauf:
/// 1. Datei-Picker (Multi-Select, PDF + Bilder).
/// 2. Pro Datei: Upload zu Storage → KI-Extraktion → neuer
///    Eingangsrechnung-Datensatz (geprueft = false).
/// 3. Fortschrittsbalken + Ergebnis-Zusammenfassung.
class BelegBulkDialog extends ConsumerStatefulWidget {
  const BelegBulkDialog({super.key});

  @override
  ConsumerState<BelegBulkDialog> createState() =>
      _BelegBulkDialogState();
}

enum _Phase { auswahl, laufen, fertig }

class _BelegBulkDialogState extends ConsumerState<BelegBulkDialog> {
  _Phase _phase = _Phase.auswahl;
  List<PlatformFile> _dateien = [];

  int _aktuell = 0;
  int _gesamt = 0;
  String _aktuelleDatei = '';
  final _protokoll = <String>[];

  int _erfolg = 0;
  int _fehler = 0;

  Future<void> _dateienWaehlen() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final ok = res.files.where((f) => f.bytes != null).toList();
    if (ok.isEmpty) return;
    setState(() => _dateien = ok);
  }

  Future<void> _starten() async {
    setState(() {
      _phase = _Phase.laufen;
      _gesamt = _dateien.length;
      _aktuell = 0;
      _erfolg = 0;
      _fehler = 0;
      _protokoll.clear();
    });

    final storage = ref.read(storageServiceProvider);
    final db = ref.read(appDatabaseProvider);

    for (var i = 0; i < _dateien.length; i++) {
      final f = _dateien[i];
      setState(() {
        _aktuell = i + 1;
        _aktuelleDatei = f.name;
      });
      try {
        final bytes = f.bytes!;
        final mime = _mimeFor(f.name);

        // 1. Datei nach Firebase Storage
        final ts = DateTime.now().millisecondsSinceEpoch;
        final path = 'eingangsrechnungen/${ts}_${f.name}';
        final url = await storage.uploadBytes(
          path,
          bytes: bytes,
          contentType: mime,
        );

        // 2. KI-Extraktion (auch ohne erfolgreichen Upload — Datensatz
        //    wird trotzdem erstellt, dann zumindest mit extrahierten
        //    Werten).
        BelegExtraktion extr;
        try {
          extr = await extrahiereBeleg(
            ref: ref, bytes: bytes, mimeType: mime,
          );
        } catch (e) {
          _protokoll.add('FEHLER — ${f.name}: KI-Fehler: $e');
          _fehler++;
          continue;
        }

        // 3. Datensatz anlegen — geprueft = false, damit der SV die
        //    KI-Werte noch einmal durchgeht.
        final netto = extr.netto ?? 0;
        final ustSatz = extr.ustSatz ?? 19;
        final ustBetrag = extr.ustBetrag ?? _round(netto * ustSatz / 100);
        final brutto = extr.brutto ?? _round(netto + ustBetrag);
        final bezahlt = extr.bereitsBezahlt ? brutto : 0.0;
        final status = extr.bereitsBezahlt ? 'bezahlt' : 'offen';

        final companion = EingangsrechnungenCompanion.insert(
          rechnungsnummer: Value(extr.rechnungsnummer),
          rechnungsdatum: Value(extr.rechnungsdatum),
          leistungsdatum: Value(extr.leistungsdatum),
          faelligAm: Value(extr.faelligkeitsdatum),
          bezahltAm:
              extr.bereitsBezahlt && extr.rechnungsdatum != null
                  ? Value(extr.rechnungsdatum)
                  : const Value.absent(),
          zahlungsweise: Value(extr.zahlungsweise ?? 'ueberweisung'),
          lieferantName: Value(extr.lieferantName),
          lieferantStrasse: Value(extr.lieferantStrasse),
          lieferantPlz: Value(extr.lieferantPlz),
          lieferantOrt: Value(extr.lieferantOrt),
          lieferantUstId: Value(extr.lieferantUstId),
          netto: Value(netto),
          ustSatz: Value(ustSatz),
          ustBetrag: Value(ustBetrag),
          brutto: Value(brutto),
          bezahlt: Value(bezahlt),
          status: Value(status),
          kategorie: Value(extr.kategorie),
          beschreibung: Value(extr.beschreibung),
          belegPfad: url == null ? const Value.absent() : Value(url),
          belegeJson: url == null
              ? const Value.absent()
              : Value(
                  '[{"filename":"${_jsonEscape(f.name)}","storageUrl":"$url","mimeType":"$mime"}]'),
          geprueft: const Value(false),
        );

        await db.into(db.eingangsrechnungen).insert(companion);
        _erfolg++;
        _protokoll.add(
            'OK — ${f.name}: ${extr.lieferantName ?? "Lieferant unbekannt"} · ${brutto.toStringAsFixed(2)} €');
      } catch (e) {
        _fehler++;
        _protokoll.add('FEHLER — ${f.name}: $e');
      }
      setState(() {}); // Progress-UI refresh
    }

    if (!mounted) return;
    setState(() => _phase = _Phase.fertig);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(scheme),
            const Divider(height: 1),
            Expanded(child: _body(scheme)),
            const Divider(height: 1),
            _footer(scheme),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          Icon(Icons.document_scanner_outlined, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'KI-Belegerfassung (Massen)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _phase == _Phase.laufen
                ? null
                : () => Navigator.of(context, rootNavigator: true).pop(),
          ),
        ],
      ),
    );
  }

  Widget _body(ColorScheme scheme) {
    switch (_phase) {
      case _Phase.auswahl:
        return _auswahl(scheme);
      case _Phase.laufen:
        return _lauf(scheme);
      case _Phase.fertig:
        return _fertig(scheme);
    }
  }

  Widget _auswahl(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'PDFs oder Fotos von Belegen auswählen. Die KI '
                    'extrahiert Lieferant, Betrag, Datum, USt, '
                    'Zahlungsweise und Kategorie. Jeder Beleg wird als '
                    'eigene Eingangsrechnung angelegt und bleibt '
                    'markiert als „ungeprüft", bis du sie händisch '
                    'freigibst.',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            icon: const Icon(Icons.folder_open),
            label: Text(_dateien.isEmpty
                ? 'Belege auswählen …'
                : '${_dateien.length} Dateien geladen — andere wählen'),
            onPressed: _dateienWaehlen,
          ),
          if (_dateien.isNotEmpty) ...[
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: _dateien.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => ListTile(
                  dense: true,
                  leading: Icon(_istBild(_dateien[i].name)
                      ? Icons.image_outlined
                      : Icons.picture_as_pdf),
                  title: Text(_dateien[i].name,
                      style: const TextStyle(fontSize: 13)),
                  trailing: Text(
                    '${(_dateien[i].size / 1024).toStringAsFixed(0)} KB',
                    style: const TextStyle(
                        fontSize: 11,
                        fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lauf(ColorScheme scheme) {
    final progress = _gesamt == 0 ? 0.0 : _aktuell / _gesamt;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('KI verarbeitet … $_aktuell / $_gesamt',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(_aktuelleDatei,
              style: TextStyle(
                  fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 18),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: ListView.builder(
                itemCount: _protokoll.length,
                itemBuilder: (_, i) => Text(
                  _protokoll[i],
                  style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      height: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fertig(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: scheme.primary, size: 28),
              const SizedBox(width: 12),
              Text('Massen-Erfassung abgeschlossen',
                  style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _kachel('Erfolgreich', '$_erfolg', scheme.primary),
                const SizedBox(width: 24),
                if (_fehler > 0)
                  _kachel('Fehler', '$_fehler', scheme.error),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Die neuen Rechnungen erscheinen in der Liste mit orangefarbenem '
            'Rand. Geh sie bitte durch, korrigiere ggf. und setze den Haken '
            'bei „Geprüft", damit sie als fertig gelten.',
            style: TextStyle(
                fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: ListView.builder(
                itemCount: _protokoll.length,
                itemBuilder: (_, i) => Text(
                  _protokoll[i],
                  style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      height: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kachel(String label, String wert, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11)),
        Text(
          wert,
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: color),
        ),
      ],
    );
  }

  Widget _footer(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_phase == _Phase.auswahl) ...[
            TextButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(),
              child: const Text('Abbrechen'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.auto_awesome, size: 16),
              label:
                  Text('KI-Erfassung starten (${_dateien.length})'),
              onPressed:
                  _dateien.isEmpty ? null : _starten,
            ),
          ] else if (_phase == _Phase.fertig) ...[
            FilledButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(),
              child: const Text('Fertig'),
            ),
          ],
        ],
      ),
    );
  }

  String _mimeFor(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    return switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
  }

  bool _istBild(String name) {
    final l = name.toLowerCase();
    return l.endsWith('.png') ||
        l.endsWith('.jpg') ||
        l.endsWith('.jpeg') ||
        l.endsWith('.webp');
  }

  String _jsonEscape(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  double _round(double v) => (v * 100).round() / 100.0;

  // Ensures unused import silencing when bytes is used downstream.
  // ignore: unused_element
  Uint8List _dummy() => Uint8List(0);
}
