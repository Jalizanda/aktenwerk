import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'dart:typed_data';

import '../../../data/database/app_database.dart';
import 'dokumente_repository.dart';

/// Öffnet ein Akten-Dokument zur Anzeige. Strategie nach Dateityp:
/// - **Cloud-URL vorhanden** → öffnet die URL im neuen Browser-Tab.
/// - **PDF mit lokalen Bytes** → zeigt es im Print/Preview-Dialog
///   ([Printing.layoutPdf] kann auch nur Vorschau ohne Druck).
/// - **Bild mit lokalen Bytes** → modaler Bilddialog.
/// - **Sonstige Datei mit Bytes** → triggert Download über
///   [Printing.sharePdf] (funktioniert browser-seitig auch für andere
///   Mime-Types als „save as").
Future<void> openDokument(
  BuildContext context,
  DokumenteData d, [
  WidgetRef? ref,
]) async {
  // 1. Cloud-URL bevorzugt.
  final url = d.storageUrl;
  if (url != null && url.trim().isNotEmpty) {
    await launchUrlString(url);
    return;
  }

  final bytes = d.daten;
  if (bytes == null || bytes.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Keine Datei-Daten gespeichert (${d.titel ?? "Dokument"}).')));
    }
    return;
  }

  final mime = (d.mimeType ?? '').toLowerCase();
  final dateiname = d.titel ?? 'dokument';

  // 2. PDF → Druckvorschau (zeigt das Dokument im Browser-Viewer).
  if (mime == 'application/pdf') {
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: dateiname,
    );
    return;
  }

  // 3. Bild → modaler Vollbild-Dialog.
  if (mime.startsWith('image/')) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        child: Stack(
          children: [
            InteractiveViewer(
              maxScale: 6,
              child: Image.memory(bytes),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ref != null)
                    IconButton.filled(
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await _editImage(context, ref, d, bytes);
                      },
                    ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return;
  }

  // 4. Sonstige Dateien → Download im Browser.
  await Printing.sharePdf(bytes: bytes, filename: dateiname);
}

Future<void> _editImage(BuildContext context, WidgetRef ref, DokumenteData d, Uint8List bytes) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => ProImageEditor.memory(
        bytes,
        callbacks: ProImageEditorCallbacks(
          onImageEditingComplete: (Uint8List newBytes) async {
            await ref.read(dokumenteRepositoryProvider).upsert(
                  DokumenteCompanion(
                    id: Value(d.id),
                    daten: Value(newBytes),
                    dateigroesse: Value(newBytes.length),
                  ),
                );
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
    ),
  );
}
