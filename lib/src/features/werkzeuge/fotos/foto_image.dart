import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/database/app_database.dart';

/// Einheitlicher Bild-Renderer für Fotos. Versucht in dieser Reihenfolge:
///
/// 1. `overrideBytes` (z. B. frisch bemaltes Bild aus dem Paint-Dialog)
/// 2. `storageUrl` (Firebase). Bei Ladefehler (CORS, 404, Token) wird
///    automatisch auf lokale Bytes zurückgefallen.
/// 3. Lokal gespeicherte Bytes (`foto.daten`) — SVG wird per `flutter_svg`
///    gerendert, alles andere per `Image.memory`.
/// 4. Platzhalter-Icon, wenn nichts vorhanden.
class FotoImage extends StatelessWidget {
  const FotoImage({
    super.key,
    required this.foto,
    this.overrideBytes,
    this.fit = BoxFit.cover,
  });

  final Foto foto;
  final Uint8List? overrideBytes;
  final BoxFit fit;

  bool _isSvgBytes(List<int> bytes) {
    if (bytes.length < 5) return false;
    // Ersten paar Bytes auf "<?xml" oder "<svg" prüfen.
    final head = String.fromCharCodes(
        bytes.take(200).where((b) => b > 0 && b < 128));
    return head.contains('<svg') || head.trimLeft().startsWith('<?xml');
  }

  Widget _localImage(BuildContext context) {
    final bytes = overrideBytes ??
        (foto.daten != null ? Uint8List.fromList(foto.daten!) : null);
    if (bytes == null || bytes.isEmpty) {
      return _placeholder(context);
    }
    final mime = foto.mimeType ?? '';
    if (mime == 'image/svg+xml' || _isSvgBytes(bytes)) {
      return SvgPicture.memory(bytes, fit: fit);
    }
    return Image.memory(bytes, fit: fit);
  }

  Widget _placeholder(BuildContext context) => Container(
        alignment: Alignment.center,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.image_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.outline,
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (overrideBytes != null) {
      return _localImage(context);
    }
    final url = foto.storageUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: fit,
        errorBuilder: (_, _, _) => _localImage(context),
        loadingBuilder: (ctx, child, progress) {
          if (progress == null) return child;
          return Container(
            alignment: Alignment.center,
            color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
            child: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      );
    }
    return _localImage(context);
  }
}
