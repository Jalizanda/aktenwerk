// Erzeugt alle benötigten iOS-App-Icon-PNGs aus dem Aktenwerk-Mark.
// Aufruf: dart run tools/generate_app_icons.dart
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  // Alle iOS-Icon-Dateinamen + Pixel-Größen (aus Contents.json).
  const iosTargets = <String, int>{
    'Icon-App-20x20@1x.png': 20,
    'Icon-App-20x20@2x.png': 40,
    'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29,
    'Icon-App-29x29@2x.png': 58,
    'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40,
    'Icon-App-40x40@2x.png': 80,
    'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120,
    'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76,
    'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
  };
  const iosDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  for (final entry in iosTargets.entries) {
    final image = _drawMark(entry.value, rounded: false);
    File('$iosDir/${entry.key}').writeAsBytesSync(img.encodePng(image));
    stdout.writeln(
        '$iosDir/${entry.key}'.padRight(70) + ' ${entry.value}x${entry.value}');
  }

  // Android-Launcher-Icons (mipmap-* mit ldpi/mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi).
  const androidTargets = <String, int>{
    'mipmap-mdpi/ic_launcher.png': 48,
    'mipmap-hdpi/ic_launcher.png': 72,
    'mipmap-xhdpi/ic_launcher.png': 96,
    'mipmap-xxhdpi/ic_launcher.png': 144,
    'mipmap-xxxhdpi/ic_launcher.png': 192,
  };
  const androidDir = 'android/app/src/main/res';
  for (final entry in androidTargets.entries) {
    final path = '$androidDir/${entry.key}';
    final dir = Directory(path).parent;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final image = _drawMark(entry.value, rounded: true);
    File(path).writeAsBytesSync(img.encodePng(image));
    stdout.writeln(path.padRight(70) + ' ${entry.value}x${entry.value}');
  }
}

img.Image _drawMark(int size, {required bool rounded}) {
  // Zeichnet das Aktenwerk-Mark (64×64-Vorlage skaliert).
  // iOS: keine eigene Rundung — iOS rundet selbst (rounded: false).
  // Android: mit Rundung, da der adaptive Layer fehlt.
  final s = size;
  final scale = s / 64.0;
  final image = img.Image(width: s, height: s);

  final r = rounded ? (10 * scale).round() : 0;
  img.fillRect(image,
      x1: 0,
      y1: 0,
      x2: s - 1,
      y2: s - 1,
      color: img.ColorRgb8(0x0B, 0x12, 0x20),
      radius: r);

  final strokeCol = img.ColorRgb8(0xFA, 0xFA, 0xF7);
  final strokeW = (2.5 * scale).round().clamp(1, 16);
  img.drawRect(image,
      x1: (14 * scale).round(),
      y1: (18 * scale).round(),
      x2: (42 * scale).round(),
      y2: (40 * scale).round(),
      color: strokeCol,
      thickness: strokeW,
      radius: (3 * scale).round());

  img.fillRect(image,
      x1: (22 * scale).round(),
      y1: (26 * scale).round(),
      x2: (50 * scale).round(),
      y2: (48 * scale).round(),
      color: img.ColorRgb8(0xF2, 0x5C, 0x1F),
      radius: (3 * scale).round());

  return image;
}
