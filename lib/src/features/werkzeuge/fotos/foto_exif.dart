import 'dart:typed_data';

import 'package:exif/exif.dart';

import '../../../data/database/app_database.dart';

/// Aus JPEG-Bytes extrahierte EXIF-Informationen (GPS + Aufnahmedatum).
class FotoExifData {
  final double? lat;
  final double? lon;
  final DateTime? aufnahmeAm;
  const FotoExifData({this.lat, this.lon, this.aufnahmeAm});

  bool get isEmpty => lat == null && lon == null && aufnahmeAm == null;
}

/// Liest GPS-Koordinaten und Aufnahmedatum aus EXIF. Fehler werden
/// geschluckt — EXIF ist optional.
Future<FotoExifData> readExif(Uint8List bytes) async {
  try {
    final tags = await readExifFromBytes(bytes);
    if (tags.isEmpty) return const FotoExifData();
    return FotoExifData(
      lat: _exifCoord(
          tags['GPS GPSLatitude'], tags['GPS GPSLatitudeRef']),
      lon: _exifCoord(
          tags['GPS GPSLongitude'], tags['GPS GPSLongitudeRef']),
      aufnahmeAm: _exifDate(tags['EXIF DateTimeOriginal'] ??
          tags['Image DateTime'] ??
          tags['EXIF DateTimeDigitized']),
    );
  } catch (_) {
    return const FotoExifData();
  }
}

double? _exifCoord(IfdTag? coord, IfdTag? ref) {
  if (coord == null) return null;
  final values = coord.values.toList();
  if (values.length < 3) return null;
  double ratToDouble(dynamic v) {
    if (v is Ratio) {
      if (v.denominator == 0) return 0;
      return v.numerator / v.denominator;
    }
    if (v is num) return v.toDouble();
    return 0;
  }

  final deg = ratToDouble(values[0]);
  final min = ratToDouble(values[1]);
  final sec = ratToDouble(values[2]);
  var dd = deg + (min / 60.0) + (sec / 3600.0);
  final r = ref?.printable.trim().toUpperCase() ?? '';
  if (r == 'S' || r == 'W') dd = -dd;
  return dd;
}

DateTime? _exifDate(IfdTag? tag) {
  if (tag == null) return null;
  final s = tag.printable.trim();
  if (s.isEmpty) return null;
  // EXIF-Format "YYYY:MM:DD HH:MM:SS" → ISO umwandeln.
  final parts = s.split(' ');
  if (parts.length != 2) return null;
  final datum = parts[0].replaceAll(':', '-');
  try {
    return DateTime.parse('${datum}T${parts[1]}');
  } catch (_) {
    return null;
  }
}

/// Formatiert Dezimalgrade als "51.2345 °N, 6.7890 °E".
String formatCoords(double lat, double lon) {
  final ns = lat >= 0 ? 'N' : 'S';
  final ew = lon >= 0 ? 'E' : 'W';
  return '${lat.abs().toStringAsFixed(5)}\u00a0°$ns, '
      '${lon.abs().toStringAsFixed(5)}\u00a0°$ew';
}

/// Öffnet Google Maps mit den angegebenen Koordinaten.
Uri mapUri(double lat, double lon) =>
    Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');

/// Liefert die nächste `reihenfolge`-Nummer für Fotos eines Auftrags.
/// Zählt immer fortlaufend: max(reihenfolge) + 1.
Future<int> nextReihenfolgeFor(AppDatabase db, int? auftragId) async {
  if (auftragId == null) return 0;
  final rows = await (db.select(db.fotos)
        ..where((t) => t.auftragId.equals(auftragId)))
      .get();
  var max = 0;
  for (final r in rows) {
    if (r.reihenfolge > max) max = r.reihenfolge;
  }
  return max + 1;
}
