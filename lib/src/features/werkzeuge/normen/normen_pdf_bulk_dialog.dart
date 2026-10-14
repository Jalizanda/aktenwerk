import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/aw_tokens.dart';
import 'normen_pdf_bulk.dart';
import 'normen_repository.dart';

/// Dialog für den Massen-Upload von Normen-PDFs.
/// Ablauf:
/// 1. Datei-Picker auswählen (Multi-Select).
/// 2. Match-Tabelle zeigen — zugeordnet / nicht zugeordnet.
/// 3. Überschreibe-Option toggeln.
/// 4. Upload starten → Fortschritt → Ergebnis.
class NormenPdfBulkDialog extends ConsumerStatefulWidget {
  const NormenPdfBulkDialog({super.key});
  @override
  ConsumerState<NormenPdfBulkDialog> createState() =>
      _NormenPdfBulkDialogState();
}

enum _Phase { auswahl, vorschau, upload, fertig }

class _NormenPdfBulkDialogState
    extends ConsumerState<NormenPdfBulkDialog> {
  _Phase _phase = _Phase.auswahl;
  List<PdfMatchResult> _kandidaten = [];
  bool _ueberschreibe = true;

  // Fortschritt
  int _aktuell = 0;
  int _gesamt = 0;
  String _aktuelleDatei = '';

  // Ergebnis
  NormenPdfUploadReport? _ergebnis;
  String? _fehler;

  Future<void> _dateienWaehlen() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;

    final dateien = <String, Uint8List>{};
    for (final f in res.files) {
      if (f.bytes == null) continue;
      dateien[f.name] = f.bytes!;
    }
    if (dateien.isEmpty) return;

    final normenAsync = ref.read(normenListProvider);
    final normen = normenAsync.valueOrNull ?? const [];

    final matches = matchePdfs(dateien: dateien, normen: normen);
    setState(() {
      _kandidaten = matches;
      _phase = _Phase.vorschau;
    });
  }

  Future<void> _hochladen() async {
    setState(() {
      _phase = _Phase.upload;
      _aktuell = 0;
      _gesamt = _kandidaten.where((k) => k.hatZuordnung).length;
      _fehler = null;
    });
    try {
      final report = await ladePdfsHoch(
        ref: ref,
        kandidaten: _kandidaten,
        ueberschreibeVorhandene: _ueberschreibe,
        onFortschritt: (i, n, name) {
          if (!mounted) return;
          setState(() {
            _aktuell = i;
            _gesamt = n;
            _aktuelleDatei = name;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _ergebnis = report;
        _phase = _Phase.fertig;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fehler = e.toString();
        _phase = _Phase.fertig;
      });
    }
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
          Icon(Icons.cloud_upload_outlined, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'PDFs zu Normen hochladen',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _phase == _Phase.upload
                ? null
                : () => Navigator.of(context, rootNavigator: true).pop(),
          ),
        ],
      ),
    );
  }

  Widget _body(ColorScheme scheme) {
    if (_fehler != null && _phase == _Phase.fertig) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: scheme.error),
              const SizedBox(height: 16),
              Text('Fehler beim Upload',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_fehler!, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    switch (_phase) {
      case _Phase.auswahl:
        return _auswahl(scheme);
      case _Phase.vorschau:
        return _vorschau(scheme);
      case _Phase.upload:
        return _uploadProgress(scheme);
      case _Phase.fertig:
        return _fertig(scheme);
    }
  }

  Widget _auswahl(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 64, color: scheme.primary),
            const SizedBox(height: 16),
            Text('PDF-Dateien auswählen',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Wähle eine oder mehrere PDF-Dateien aus.\n'
              'Bestehende Katalog-Normen werden automatisch gematcht.\n'
              'Für noch nicht existierende Normen wird automatisch ein neuer Katalog-Eintrag angelegt.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('PDFs auswählen…'),
              onPressed: _dateienWaehlen,
            ),
          ],
        ),
      ),
    );
  }

  Widget _vorschau(ColorScheme scheme) {
    final bestehend =
        _kandidaten.where((k) => k.hatZuordnung && !k.istNeueNorm && !k.ist1zu1Dublette).length;
    final neuAnzulegen = _kandidaten.where((k) => k.istNeueNorm && !k.ist1zu1Dublette).length;
    final dubletten = _kandidaten.where((k) => k.ist1zu1Dublette).length;
    final gesamtGroesse =
        _kandidaten.fold<int>(0, (s, k) => s + k.groesse);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: scheme.surfaceContainerHighest,
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              _kennzahl(scheme, '${_kandidaten.length} Dateien',
                  '${(gesamtGroesse / 1024 / 1024).toStringAsFixed(1)} MB'),
              const SizedBox(width: 24),
              if (bestehend > 0) ...[
                _kennzahl(
                    scheme, '$bestehend bestehend', 'werden aktualisiert',
                    grun: true),
                const SizedBox(width: 24),
              ],
              if (neuAnzulegen > 0) ...[
                _kennzahl(
                    scheme, '$neuAnzulegen neu', 'werden neu angelegt',
                    blau: true),
                const SizedBox(width: 24),
              ],
              if (dubletten > 0) ...[
                _kennzahl(
                    scheme, '$dubletten Dubletten', 'werden übersprungen',
                    rot: true),
                const SizedBox(width: 24),
              ],
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _ueberschreibe,
                    onChanged: (v) =>
                        setState(() => _ueberschreibe = v ?? true),
                  ),
                  const Text('Vorhandene PDFs überschreiben',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _kandidaten.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final k = _kandidaten[i];
              final istDublette = k.ist1zu1Dublette;
              final istNeu = k.istNeueNorm;

              final IconData icon = istDublette
                  ? Icons.block
                  : (istNeu ? Icons.add_circle_outline : Icons.check_circle);
              final Color iconColor = istDublette
                  ? Colors.orange.shade800
                  : (istNeu ? Colors.blue.shade700 : scheme.primary);

              return ListTile(
                dense: true,
                leading: Icon(
                  icon,
                  color: iconColor,
                  size: 20,
                ),
                title: Text(k.dateiname,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        decoration: istDublette ? TextDecoration.lineThrough : null)),
                subtitle: Text(
                  istDublette
                      ? '🚫 1:1 Inhaltlich identische Dublette — wird übersprungen (${k.matchGrund})'
                      : (istNeu
                          ? '→ Neue Norm wird angelegt: ${k.zugeordneteNorm!.nummer}'
                              ' (${k.zugeordneteNorm!.herausgeber})'
                          : '→ Bestehende Norm: ${k.zugeordneteNorm!.nummer}'
                              '${k.zugeordneteNorm!.titel != null ? " · ${k.zugeordneteNorm!.titel}" : ""}'),
                  style: TextStyle(
                    fontSize: 11,
                    color: istDublette ? Colors.red.shade700 : null,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  '${(k.groesse / 1024).toStringAsFixed(0)} KB',
                  style: const TextStyle(
                      fontSize: 11,
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _uploadProgress(ColorScheme scheme) {
    final progress = _gesamt == 0 ? 0.0 : _aktuell / _gesamt;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_upload_outlined,
              size: 48, color: scheme.primary),
          const SizedBox(height: 14),
          Text('Lade hoch … $_aktuell / $_gesamt',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            _aktuelleDatei,
            style: TextStyle(
                fontSize: 12, color: scheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 400,
            child: LinearProgressIndicator(value: progress),
          ),
        ],
      ),
    );
  }

  Widget _fertig(ColorScheme scheme) {
    if (_fehler != null) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 14),
            const Text('Upload fehlgeschlagen',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            Text(_fehler!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.error, fontSize: 12)),
          ],
        ),
      );
    }
    final r = _ergebnis!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            r.fehler > 0 ? Icons.warning_amber_rounded : Icons.check_circle,
            size: 52,
            color: r.fehler > 0 ? AwTokens.orange : scheme.primary,
          ),
          const SizedBox(height: 12),
          Text('Upload abgeschlossen',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _zeile('Erfolgreich hochgeladen', '${r.erfolgreich}',
                    scheme.primary),
                if (r.uebersprungen > 0)
                  _zeile('Übersprungen (schon vorhanden)',
                      '${r.uebersprungen}', scheme.onSurfaceVariant),
                if (r.fehler > 0)
                  _zeile('Fehler', '${r.fehler}', scheme.error),
              ],
            ),
          ),
          if (r.fehlerListe.isNotEmpty) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Fehler-Details (${r.fehlerListe.length}):',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: scheme.error),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
                ),
                child: ListView.builder(
                  itemCount: r.fehlerListe.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '• ${r.fehlerListe[i]}',
                      style: TextStyle(
                          fontSize: 11,
                          color: scheme.onErrorContainer,
                          fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _zeile(String label, String wert, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
              width: 220,
              child:
                  Text(label, style: const TextStyle(fontSize: 13))),
          Text(wert,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }

  Widget _kennzahl(ColorScheme scheme, String wert, String label,
      {bool grun = false, bool rot = false, bool blau = false}) {
    final color = grun
        ? scheme.primary
        : rot
            ? scheme.error
            : blau
                ? Colors.blue.shade700
                : scheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(wert,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            )),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: scheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _footer(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_phase == _Phase.vorschau) ...[
            TextButton(
              onPressed: () => setState(() {
                _kandidaten = [];
                _phase = _Phase.auswahl;
              }),
              child: const Text('Zurück'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.cloud_upload, size: 16),
              label: Text(
                  'Hochladen (${_kandidaten.where((k) => k.hatZuordnung).length})'),
              onPressed:
                  _kandidaten.where((k) => k.hatZuordnung).isEmpty
                      ? null
                      : _hochladen,
            ),
          ] else if (_phase == _Phase.fertig) ...[
            FilledButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(),
              child: const Text('Fertig'),
            ),
          ] else if (_phase == _Phase.auswahl) ...[
            TextButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(),
              child: const Text('Abbrechen'),
            ),
          ],
        ],
      ),
    );
  }
}
