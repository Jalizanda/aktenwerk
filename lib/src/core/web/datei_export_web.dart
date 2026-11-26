import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web: Datei über den Browser herunterladen.
Future<String?> dateiSpeichern(
  Uint8List bytes,
  String dateiname, {
  String mime = 'application/octet-stream',
  bool oeffnen = true,
}) async {
  final parts = <JSAny>[bytes.toJS].toJS;
  final blob = web.Blob(parts, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = dateiname;
  web.document.body?.append(a);
  a.click();
  a.remove();
  Timer(const Duration(seconds: 60), () => web.URL.revokeObjectURL(url));
  return dateiname;
}

/// Web: HEIC über den Bild-Decoder des Browsers in JPEG umwandeln.
/// Funktioniert in Safari (macOS/iOS); andere Browser liefern `null`.
Future<Uint8List?> heicZuJpeg(Uint8List bytes) async {
  try {
    final parts = <JSAny>[bytes.toJS].toJS;
    final blob = web.Blob(parts, web.BlobPropertyBag(type: 'image/heic'));
    final bmp = await web.window.createImageBitmap(blob).toDart;
    final canvas = web.OffscreenCanvas(bmp.width, bmp.height);
    final ctx =
        canvas.getContext('2d') as web.OffscreenCanvasRenderingContext2D;
    ctx.drawImage(bmp, 0, 0);
    final jpeg = await canvas
        .convertToBlob(web.ImageEncodeOptions(type: 'image/jpeg', quality: 0.85))
        .toDart;
    final ab = await jpeg.arrayBuffer().toDart;
    return JSUint8Array(ab).toDart;
  } catch (_) {
    return null;
  }
}
