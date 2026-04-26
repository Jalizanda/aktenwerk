// Einmal-Script: rendert das Aktenwerk-Mark als PNG in verschiedenen
// Größen. Kein SVG-Parser nötig — wir zeichnen die 3 Rechtecke direkt
// mit package:image (pure Dart, läuft headless).
//
// Aufruf: dart run tools/generate_favicons.dart
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final sizes = <(String, int)>[
    ('web/favicon.png', 32),
    ('web/icons/Icon-192.png', 192),
    ('web/icons/Icon-512.png', 512),
    ('web/icons/Icon-maskable-192.png', 192),
    ('web/icons/Icon-maskable-512.png', 512),
  ];
  for (final (path, size) in sizes) {
    final image = _drawMark(size);
    File(path).writeAsBytesSync(img.encodePng(image));
    stdout.writeln('${path.padRight(42)} ${size}x$size');
  }
}

img.Image _drawMark(int size) {
  // Zeichnet das Aktenwerk-Mark (64×64-Vorlage auf beliebige Kantenlänge).
  //   Background: Ink #0B1220 mit ~16 % Rundung
  //   Outline-Rect (stroke #FAFAF7): x 14..42, y 18..40, Radius 3
  //   Orange-Rect (fill #F25C1F):    x 22..50, y 26..48, Radius 3
  final s = size;
  final scale = s / 64.0;
  final image = img.Image(width: s, height: s);

  // Ink-Hintergrund mit abgerundeten Ecken.
  final r = (10 * scale).round();
  img.fillRect(image,
      x1: 0,
      y1: 0,
      x2: s - 1,
      y2: s - 1,
      color: img.ColorRgb8(0x0B, 0x12, 0x20),
      radius: r);

  // Outline-Rechteck (weiß).
  final strokeCol = img.ColorRgb8(0xFA, 0xFA, 0xF7);
  final strokeW = (2.5 * scale).round().clamp(1, 12);
  final sx1 = (14 * scale).round();
  final sy1 = (18 * scale).round();
  final sx2 = (42 * scale).round();
  final sy2 = (40 * scale).round();
  final sr = (3 * scale).round();
  img.drawRect(image,
      x1: sx1,
      y1: sy1,
      x2: sx2,
      y2: sy2,
      color: strokeCol,
      thickness: strokeW,
      radius: sr);

  // Orange-Rechteck (gefüllt, überdeckt Teil der Outline für Layer-Look).
  final orangeCol = img.ColorRgb8(0xF2, 0x5C, 0x1F);
  img.fillRect(image,
      x1: (22 * scale).round(),
      y1: (26 * scale).round(),
      x2: (50 * scale).round(),
      y2: (48 * scale).round(),
      color: orangeCol,
      radius: sr);

  return image;
}
