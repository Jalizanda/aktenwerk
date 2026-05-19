import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/seed/demo_seed.dart';
import 'backup_service.dart';

/// Einstellungen-Sektion: vollständige JSON-Sicherung aller lokalen Daten
/// herunterladen + wieder einspielen.
class BackupSection extends ConsumerStatefulWidget {
  const BackupSection({super.key});
  @override
  ConsumerState<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<BackupSection> {
  bool _busy = false;
  String? _lastReport;
  String? _error;

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _error = null;
      _lastReport = null;
    });
    try {
      final json = await ref.read(backupServiceProvider).exportAllAsJson();
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final bytes = Uint8List.fromList(utf8.encode(json));
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          name: 'aktenwerk_backup_$stamp.json',
          mimeType: 'application/json',
        ),
      ], subject: 'Aktenwerk-Backup');
      _lastReport =
          'Export erstellt: ${(bytes.length / 1024).toStringAsFixed(1)} KB';
    } catch (e) {
      _error = 'Export fehlgeschlagen: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: const Text('Backup einspielen?'),
        content: const Text(
          'Alle lokalen Daten im aktuellen Browser werden durch den Inhalt '
          'der Backup-Datei ersetzt. Das lässt sich NICHT rückgängig '
          'machen (außer durch ein anderes Backup). Fortfahren?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ja, einspielen'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _error = null;
      _lastReport = null;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      final bytes = picked?.files.single.bytes;
      if (bytes == null) {
        setState(() => _busy = false);
        return;
      }
      final json = utf8.decode(bytes);
      final report = await ref.read(backupServiceProvider).importFromJson(json);
      _lastReport = 'Import fertig: ${report.summary}';
    } catch (e) {
      _error = 'Import fehlgeschlagen: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importOldSystem() async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: const Text('Original-System (IndexedDB) importieren?'),
        content: const Text(
          'Alle lokalen Daten werden gelöscht und durch den Inhalt der ausgewählten '
          'JSON-Exportdatei der Original-Software ersetzt. Fortfahren?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ja, importieren'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _error = null;
      _lastReport = null;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      final bytes = picked?.files.single.bytes;
      if (bytes == null) {
        setState(() => _busy = false);
        return;
      }
      final jsonStr = utf8.decode(bytes);
      final report = await ref.read(demoSeederProvider).importJsonDump(jsonStr);
      _lastReport = 'Import fertig. Eingelesene Datensätze: ${report.total}';
    } catch (e) {
      _error = 'IndexedDB-Import fehlgeschlagen: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sicherung aller lokalen Aktenwerk-Daten als JSON-Datei — '
          'Stamm- und Programm-Daten. Beim Einspielen wird die aktuelle '
          'Datenbank vollständig ersetzt. Tipp: vor jedem Release einmal '
          'Export klicken und die Datei offline ablegen.',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download_outlined),
              label: const Text('Backup herunterladen (JSON)'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.file_upload_outlined, size: 16),
              label: const Text('Backup einspielen …'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _importOldSystem,
              icon: const Icon(Icons.drive_folder_upload_outlined, size: 16),
              label: const Text('IndexedDB-Import (Original) …'),
            ),
          ],
        ),
        if (_lastReport != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.slate50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.slate200),
            ),
            child: Text(_lastReport!, style: theme.textTheme.bodySmall),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _error!,
              style: TextStyle(
                color: theme.colorScheme.onErrorContainer,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
