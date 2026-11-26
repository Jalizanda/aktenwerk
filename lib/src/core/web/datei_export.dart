// Plattform-Brücke zum Speichern/Öffnen erzeugter Dateien (Word, ICS, PDF …)
// und zur Umwandlung von iPhone-Fotos (HEIC) in JPEG.
//
// * Web: Download über den Browser; HEIC-Umwandlung über den Browser-
//   Decoder (Safari kann HEIC, Chrome/Firefox nicht → Rückgabe `null`).
// * macOS/Windows/Linux: „Speichern unter“-Dialog, danach Öffnen mit der
//   Standard-App (z. B. Word); HEIC-Umwandlung auf dem Mac mit `sips`.
// * iOS/Android: Teilen-Dialog.
export 'datei_export_io.dart' if (dart.library.html) 'datei_export_web.dart';

/// Erkennt HEIC/HEIF an Dateiendung oder Signatur („ftypheic“ …).
bool istHeic(String dateiname, List<int> bytes) {
  final n = dateiname.toLowerCase();
  if (n.endsWith('.heic') || n.endsWith('.heif')) return true;
  if (bytes.length < 12) return false;
  final brand = String.fromCharCodes(bytes.sublist(4, 12));
  return brand == 'ftypheic' ||
      brand == 'ftypheix' ||
      brand == 'ftyphevc' ||
      brand == 'ftypmif1' ||
      brand == 'ftypmsf1';
}
