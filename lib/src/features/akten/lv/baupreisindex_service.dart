import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Liest den Baupreisindex aus der GENESIS-Online-API des Statistischen
/// Bundesamtes. Tabelle 61261-0001 = Preisindizes für den Neubau in
/// konventioneller Bauart - Wohngebäude. Die API ist kostenfrei nach
/// Registrierung; ein Nutzername/Passwort wird in den Aktenwerk-
/// Einstellungen hinterlegt.
///
/// Die Methode `aktuellerIndex` liefert den jüngsten Wert; `indexZum`
/// liefert den Wert für ein spezifisches Quartal (Format `2024-Q3`).
class BaupreisindexService {
  BaupreisindexService();

  static const _kBenutzer = 'destatis.benutzer';
  static const _kPasswort = 'destatis.passwort';

  static const baseUrl =
      'https://www-genesis.destatis.de/genesisWS/rest/2020';

  /// Tabellen-ID für „Preisindizes für den Neubau in konventioneller
  /// Bauart — Wohngebäude (Bauleistungen am Bauwerk)".
  static const tabelleWohngebaeude = '61261-0001';

  Future<({String? user, String? pw})> _credentials() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      user: prefs.getString(_kBenutzer),
      pw: prefs.getString(_kPasswort),
    );
  }

  Future<void> setCredentials(String? user, String? pw) async {
    final prefs = await SharedPreferences.getInstance();
    if (user == null || user.isEmpty) {
      await prefs.remove(_kBenutzer);
    } else {
      await prefs.setString(_kBenutzer, user);
    }
    if (pw == null || pw.isEmpty) {
      await prefs.remove(_kPasswort);
    } else {
      await prefs.setString(_kPasswort, pw);
    }
  }

  Future<bool> isConfigured() async {
    final c = await _credentials();
    return (c.user ?? '').isNotEmpty && (c.pw ?? '').isNotEmpty;
  }

  /// Holt eine Tabelle als CSV (semikolon-getrennt) und parst die
  /// Quartals-Werte. Geht über die Aktenwerk-Cloud-Function als CORS-
  /// Proxy, weil Destatis keine CORS-Header liefert. Liefert eine Map
  /// `Quartal-String → Index-Wert`.
  Future<Map<String, double>> tabelleZeitreihe(String tabellenId) async {
    final c = await _credentials();
    if ((c.user ?? '').isEmpty || (c.pw ?? '').isEmpty) {
      throw StateError(
          'Destatis-Zugangsdaten fehlen. Bitte in den Einstellungen '
          'unter „Baupreisindex" hinterlegen (kostenfreier Account).');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError(
          'Bitte erst in Aktenwerk anmelden — der Destatis-Proxy '
          'benötigt ein Auth-Token.');
    }
    final idToken = await user.getIdToken();
    final r = await http.post(
      Uri.parse('/api/destatis'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'username': c.user,
        'password': c.pw,
        'tableId': tabellenId,
      }),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw StateError(
          'Destatis-Proxy ${r.statusCode}: ${r.body.substring(0, r.body.length > 200 ? 200 : r.body.length)}');
    }
    return _parseGenesisCsv(r.body);
  }

  /// Sehr robuster CSV-Parser: sucht alle Zeilen, deren erstes Feld
  /// ein Quartal (z. B. "2024-Q3" / "2024-3" / "3. Vj. 2024") ist und
  /// extrahiert den ersten numerischen Wert in der Zeile.
  Map<String, double> _parseGenesisCsv(String csv) {
    final out = <String, double>{};
    final lines = const LineSplitter().convert(csv);
    final qRe = RegExp(r'(\d{4})\D+(?:Q?([1-4])|([1-4])\.\s*Vj)');
    for (final line in lines) {
      final fields = line.split(';');
      if (fields.length < 2) continue;
      final m = qRe.firstMatch(fields.first);
      if (m == null) continue;
      final year = m.group(1)!;
      final q = m.group(2) ?? m.group(3) ?? '';
      // Suche das letzte numerische Feld als Index-Wert.
      double? value;
      for (final f in fields.skip(1)) {
        final v =
            double.tryParse(f.replaceAll(',', '.').trim());
        if (v != null && v > 10 && v < 1000) value = v;
      }
      if (value != null) out['$year-Q$q'] = value;
    }
    return out;
  }

  Future<({String stichtag, double wert})?> aktuellerIndex(
      [String tabellenId = tabelleWohngebaeude]) async {
    final reihe = await tabelleZeitreihe(tabellenId);
    if (reihe.isEmpty) return null;
    final letzter = reihe.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final last = letzter.last;
    return (stichtag: last.key, wert: last.value);
  }
}

final baupreisindexServiceProvider =
    Provider<BaupreisindexService>((_) => BaupreisindexService());
