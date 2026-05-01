import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/aw_tokens.dart';
import '../../data/sync/auth_service.dart';
import '../../data/sync/storage_service.dart';

/// Datei-Eintrag: eine in Firebase Storage abgelegte Datei.
class UploadedFile {
  final String storageUrl;
  final String dateiname;
  final String? mimeType;
  final int? groesse;

  /// Lokale Roh-Bytes der Datei. Wird beim Upload gesetzt, damit Konsumenten
  /// (z. B. KI-Extraktion) die Bytes direkt nutzen können, ohne sie über
  /// Firebase Storage neu herunterladen zu müssen (CORS/Auth-Risiko). Nicht
  /// persistiert — nach dem Laden aus JSON ist `bytes` immer null.
  final Uint8List? bytes;

  const UploadedFile({
    required this.storageUrl,
    required this.dateiname,
    this.mimeType,
    this.groesse,
    this.bytes,
  });

  Map<String, dynamic> toJson() => {
        'storageUrl': storageUrl,
        'dateiname': dateiname,
        if (mimeType != null) 'mimeType': mimeType,
        if (groesse != null) 'groesse': groesse,
      };

  factory UploadedFile.fromJson(Map<String, dynamic> j) => UploadedFile(
        storageUrl: j['storageUrl']?.toString() ??
            j['url']?.toString() ??
            '',
        dateiname: j['dateiname']?.toString() ??
            j['filename']?.toString() ??
            j['name']?.toString() ??
            'Datei',
        mimeType: j['mimeType']?.toString(),
        groesse: j['groesse'] is int
            ? j['groesse'] as int
            : int.tryParse(j['groesse']?.toString() ?? ''),
      );

  bool get isImage => (mimeType ?? '').startsWith('image/');
  bool get isPdf => (mimeType ?? '').contains('pdf');
}

/// Kodiert/dekodiert eine Liste von Datei-Einträgen als JSON-String.
List<UploadedFile> decodeUploadedFiles(String? json) {
  if (json == null || json.trim().isEmpty) return const [];
  try {
    final parsed = jsonDecode(json);
    if (parsed is! List) return const [];
    return parsed
        .whereType<Map>()
        .map((e) => UploadedFile.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  } catch (_) {
    return const [];
  }
}

String encodeUploadedFiles(List<UploadedFile> files) =>
    jsonEncode(files.map((f) => f.toJson()).toList());

/// Typ des erwarteten Uploads.
enum UploadKind {
  /// Nur PDF akzeptieren.
  pdf,

  /// Nur Bilder akzeptieren.
  image,

  /// Dokumente & Bilder (PDF, Office, Bilder).
  any,
}

String _labelFor(UploadKind k) => switch (k) {
      UploadKind.pdf => 'PDF',
      UploadKind.image => 'Bild',
      UploadKind.any => 'Datei',
    };

List<String>? _extensionsFor(UploadKind k) => switch (k) {
      UploadKind.pdf => const ['pdf'],
      UploadKind.image => null, // File.image wird verwendet
      UploadKind.any => null,
    };

FileType _fileTypeFor(UploadKind k) => switch (k) {
      UploadKind.pdf => FileType.custom,
      UploadKind.image => FileType.image,
      UploadKind.any => FileType.any,
    };

/// Upload einer Datei über den FilePicker in Firebase Storage.
///
/// Gibt die hochgeladene Datei zurück (oder `null` bei Abbruch / Fehler).
/// Fehler werden per SnackBar angezeigt.
Future<UploadedFile?> pickAndUploadFile({
  required BuildContext context,
  required WidgetRef ref,
  required String storagePrefix,
  required UploadKind kind,
}) async {
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: false,
    withData: true,
    type: _fileTypeFor(kind),
    allowedExtensions: _extensionsFor(kind),
  );
  if (result == null || result.files.isEmpty) return null;
  final f = result.files.first;
  if (f.bytes == null) return null;

  final storage = ref.read(storageServiceProvider);
  final auth = ref.read(authServiceProvider);
  if (!storage.enabled || auth.currentUser == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cloud nicht verfügbar. Bitte zuerst anmelden.')));
    }
    return null;
  }

  final mime = f.extension == null ? null : _mimeForExt(f.extension!);
  final ts = DateTime.now().millisecondsSinceEpoch;
  final safeName = _sanitize(f.name);
  final path = '$storagePrefix/${ts}_$safeName';

  try {
    final url = await storage.uploadBytes(
      path,
      bytes: f.bytes!,
      contentType: mime,
    );
    if (url == null) throw Exception('Upload fehlgeschlagen');
    return UploadedFile(
      storageUrl: url,
      dateiname: f.name,
      mimeType: mime,
      groesse: f.size,
      bytes: f.bytes,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Upload: $e')));
    }
    return null;
  }
}

String _sanitize(String name) =>
    name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

String _mimeForExt(String ext) {
  switch (ext.toLowerCase()) {
    case 'pdf':
      return 'application/pdf';
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
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    default:
      return 'application/octet-stream';
  }
}

String _fmtSize(int? b) {
  if (b == null) return '';
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// ---------------- Single-File Upload ----------------

/// Wiederverwendbare Sektion: zeigt eine hochgeladene Datei (PDF-Icon oder
/// Bild-Thumbnail) mit „Öffnen"- und „Entfernen"-Buttons bzw. einen Upload-
/// Button wenn leer. Ziel: Firebase Storage unter `storagePrefix/...`.
class FileUploadSection extends ConsumerStatefulWidget {
  const FileUploadSection({
    super.key,
    required this.title,
    required this.storagePrefix,
    required this.kind,
    required this.file,
    required this.onChanged,
    this.hint,
  });

  final String title;
  final String storagePrefix;
  final UploadKind kind;
  final UploadedFile? file;
  final ValueChanged<UploadedFile?> onChanged;
  final String? hint;

  @override
  ConsumerState<FileUploadSection> createState() => _FileUploadSectionState();
}

class _FileUploadSectionState extends ConsumerState<FileUploadSection> {
  bool _uploading = false;

  Future<void> _pick() async {
    setState(() => _uploading = true);
    final f = await pickAndUploadFile(
      context: context,
      ref: ref,
      storagePrefix: widget.storagePrefix,
      kind: widget.kind,
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (f != null) widget.onChanged(f);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title,
            style: Theme.of(context).textTheme.titleSmall),
        if (widget.hint != null) ...[
          const SizedBox(height: 4),
          Text(widget.hint!,
              style:
                  TextStyle(fontSize: 11, color: AppTheme.slate500)),
        ],
        const SizedBox(height: 10),
        if (widget.file != null)
          _FileTile(
            file: widget.file!,
            onOpen: () => _openFile(widget.file!),
            onReplace: _uploading ? null : _pick,
            onRemove: () => widget.onChanged(null),
          )
        else
          OutlinedButton.icon(
            icon: _uploading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(
                    widget.kind == UploadKind.image
                        ? Icons.image_outlined
                        : Icons.upload_file,
                    size: 18,
                  ),
            label: Text(_uploading
                ? 'Lade hoch…'
                : '${_labelFor(widget.kind)} hochladen'),
            onPressed: _uploading ? null : _pick,
          ),
      ],
    );
  }
}

/// ---------------- Multi-File Upload ----------------

/// Wiederverwendbare Sektion für mehrere Dateien (z. B. Belege zu einer
/// Eingangsrechnung). Speichert als JSON-Array im übergebenden Feld.
class MultiFileUploadSection extends ConsumerStatefulWidget {
  const MultiFileUploadSection({
    super.key,
    required this.title,
    required this.storagePrefix,
    required this.kind,
    required this.files,
    required this.onChanged,
    this.hint,
    this.maxFiles,
  });

  final String title;
  final String storagePrefix;
  final UploadKind kind;
  final List<UploadedFile> files;
  final ValueChanged<List<UploadedFile>> onChanged;
  final String? hint;
  final int? maxFiles;

  @override
  ConsumerState<MultiFileUploadSection> createState() =>
      _MultiFileUploadSectionState();
}

class _MultiFileUploadSectionState
    extends ConsumerState<MultiFileUploadSection> {
  bool _uploading = false;

  Future<void> _pick() async {
    setState(() => _uploading = true);
    final f = await pickAndUploadFile(
      context: context,
      ref: ref,
      storagePrefix: widget.storagePrefix,
      kind: widget.kind,
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (f != null) {
      widget.onChanged([...widget.files, f]);
    }
  }

  void _remove(int i) {
    final list = [...widget.files];
    list.removeAt(i);
    widget.onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = widget.maxFiles == null ||
        widget.files.length < widget.maxFiles!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.title,
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            Text('${widget.files.length}'
                '${widget.maxFiles == null ? '' : ' / ${widget.maxFiles}'}',
                style: TextStyle(
                    fontSize: 11, color: AppTheme.slate500)),
          ],
        ),
        if (widget.hint != null) ...[
          const SizedBox(height: 4),
          Text(widget.hint!,
              style:
                  TextStyle(fontSize: 11, color: AppTheme.slate500)),
        ],
        const SizedBox(height: 10),
        ...widget.files.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FileTile(
                file: e.value,
                onOpen: () => _openFile(e.value),
                onReplace: null,
                onRemove: () => _remove(e.key),
              ),
            )),
        if (canAdd)
          OutlinedButton.icon(
            icon: _uploading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add, size: 18),
            label: Text(_uploading
                ? 'Lade hoch…'
                : widget.files.isEmpty
                    ? '${_labelFor(widget.kind)} hinzufügen'
                    : 'Weitere Datei hinzufügen'),
            onPressed: _uploading ? null : _pick,
          ),
      ],
    );
  }
}

/// ---------------- Gemeinsame Tile-Darstellung ----------------

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.file,
    required this.onOpen,
    required this.onReplace,
    required this.onRemove,
  });
  final UploadedFile file;
  final VoidCallback onOpen;
  final VoidCallback? onReplace;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.slate200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _Thumb(file: file),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.dateiname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                if (file.groesse != null)
                  Text(_fmtSize(file.groesse),
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.slate500)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Im neuen Tab öffnen',
            icon: const Icon(Icons.open_in_new, size: 18),
            onPressed: onOpen,
          ),
          if (onReplace != null)
            IconButton(
              tooltip: 'Ersetzen',
              icon: const Icon(Icons.upload_file, size: 18),
              onPressed: onReplace,
            ),
          IconButton(
            tooltip: 'Entfernen',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.file});
  final UploadedFile file;
  @override
  Widget build(BuildContext context) {
    const size = 40.0;
    if (file.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(
            file.storageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.image_outlined, size: 22),
          ),
        ),
      );
    }
    if (file.isPdf) {
      return const SizedBox(
        width: size,
        height: size,
        child: Icon(Icons.picture_as_pdf, size: 28, color: AwTokens.red),
      );
    }
    return const SizedBox(
      width: size,
      height: size,
      child: Icon(Icons.description_outlined, size: 26),
    );
  }
}

Future<void> _openFile(UploadedFile f) async {
  final uri = Uri.tryParse(f.storageUrl);
  if (uri != null) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// Ensure Uint8List import is used (avoids tree-shake lint).
// ignore: unused_element
Uint8List _noop() => Uint8List(0);
