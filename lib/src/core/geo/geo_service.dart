import 'dart:convert';

import 'package:http/http.dart' as http;

/// Ein Koordinatenpaar (WGS84).
class LatLon {
  const LatLon(this.lat, this.lon);
  final double lat;
  final double lon;

  @override
  String toString() => '$lat,$lon';
}

/// Ergebnis einer Strecken-Berechnung via OSRM.
class Strecke {
  const Strecke({required this.kilometer, required this.dauerMinuten});
  final double kilometer;
  final double dauerMinuten;
}

const _userAgent = 'Aktenwerk/1.0 (hello@aktenwerk.app)';

/// Wandelt eine Adresse in Lat/Lon um. Nutzt Nominatim (OpenStreetMap).
/// Ein User-Agent-Header ist von Nominatim verpflichtend.
Future<LatLon?> adresseZuKoordinaten(String adresse) async {
  final trimmed = adresse.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/search?format=json&limit=1&q=${Uri.encodeComponent(trimmed)}');
  try {
    final resp =
        await http.get(uri, headers: {'User-Agent': _userAgent});
    if (resp.statusCode != 200) return null;
    final list = jsonDecode(resp.body) as List;
    if (list.isEmpty) return null;
    final m = list.first as Map;
    final lat = double.tryParse(m['lat']?.toString() ?? '');
    final lon = double.tryParse(m['lon']?.toString() ?? '');
    if (lat == null || lon == null) return null;
    return LatLon(lat, lon);
  } catch (_) {
    return null;
  }
}

/// Einfache Straßenkilometer-Berechnung zwischen zwei Koordinaten via
/// OSRM-Demo-Server (öffentlich, kein API-Key, fair-use). Gibt `null`
/// zurück bei Fehlern.
Future<Strecke?> routeKm(LatLon start, LatLon ziel) async {
  final uri = Uri.parse(
    'https://router.project-osrm.org/route/v1/driving/'
    '${start.lon},${start.lat};${ziel.lon},${ziel.lat}'
    '?overview=false&alternatives=false&steps=false',
  );
  try {
    final resp = await http.get(uri);
    if (resp.statusCode != 200) return null;
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final routes = body['routes'] as List?;
    if (routes == null || routes.isEmpty) return null;
    final r = routes.first as Map<String, dynamic>;
    final meter = (r['distance'] as num?)?.toDouble();
    final sek = (r['duration'] as num?)?.toDouble();
    if (meter == null || sek == null) return null;
    return Strecke(kilometer: meter / 1000.0, dauerMinuten: sek / 60.0);
  } catch (_) {
    return null;
  }
}
