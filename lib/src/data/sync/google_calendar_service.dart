import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Leichtgewichtiger Google-Calendar-Client auf HTTP-Basis.
///
/// Verzichtet bewusst auf das `google_sign_in`-Web-Plugin (dessen
/// Konstruktor triggert eine eager GIS-Script-Initialisierung, die
/// in anderen Streams der App zu `Concurrent modification during
/// iteration` führen kann).
///
/// Stattdessen nutzen wir Firebase-Auths `reauthenticateWithPopup`
/// mit zusätzlichen Calendar-Scopes. Das OAuth2-Access-Token aus dem
/// Credential wird lokal gehalten (mit Ablaufzeit) und bei Bedarf neu
/// angefordert. Alle Calendar-Requests laufen als gewöhnliche
/// HTTPS-Aufrufe.
class GoogleCalendarService {
  GoogleCalendarService();

  static const _kAccessToken = 'gcal.accessToken';
  static const _kExpiresAt = 'gcal.expiresAtIso';
  static const _kCalendarId = 'gcal.selectedCalendarId';
  static const _kUserEmail = 'gcal.userEmail';
  static const _kUserName = 'gcal.userName';
  static const _kUserPhoto = 'gcal.userPhoto';

  static const _scopes = [
    'https://www.googleapis.com/auth/calendar.events',
    'https://www.googleapis.com/auth/calendar.readonly',
  ];

  String? _cachedToken;
  DateTime? _cachedExpiresAt;

  Future<void> _loadTokenFromPrefs() async {
    if (_cachedToken != null) return;
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString(_kAccessToken);
    final iso = prefs.getString(_kExpiresAt);
    _cachedExpiresAt = iso == null ? null : DateTime.tryParse(iso);
  }

  Future<String?> _currentAccessToken() async {
    await _loadTokenFromPrefs();
    if (_cachedToken == null) return null;
    if (_cachedExpiresAt == null) return _cachedToken;
    // Ein kleiner Sicherheitsabstand von 60s, damit laufende Requests
    // nicht kurz vor Ablauf scheitern.
    if (DateTime.now()
        .add(const Duration(seconds: 60))
        .isAfter(_cachedExpiresAt!)) {
      return null;
    }
    return _cachedToken;
  }

  /// True, wenn ein (vermutlich) gültiges Token lokal vorliegt.
  Future<bool> isConnected() async {
    final t = await _currentAccessToken();
    return t != null;
  }

  Future<String?> getUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUserEmail);
  }

  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUserName);
  }

  Future<String?> getUserPhoto() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUserPhoto);
  }

  Future<String?> getSelectedCalendarId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCalendarId);
  }

  Future<void> setSelectedCalendarId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_kCalendarId);
    } else {
      await prefs.setString(_kCalendarId, id);
    }
  }

  /// Führt einen OAuth-Popup via Firebase-Auth mit den Calendar-Scopes
  /// aus und speichert das zurückgegebene Access-Token lokal.
  Future<bool> connect() async {
    final user = FirebaseAuth.instance.currentUser;
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'consent'});
    for (final s in _scopes) {
      provider.addScope(s);
    }

    UserCredential cred;
    try {
      cred = user != null
          ? await user.reauthenticateWithPopup(provider)
          : await FirebaseAuth.instance.signInWithPopup(provider);
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) debugPrint('Calendar auth error: ${e.code} ${e.message}');
      rethrow;
    }

    final oauth = cred.credential as OAuthCredential?;
    final token = oauth?.accessToken;
    if (token == null) return false;

    // Firebase liefert keine Ablaufzeit — Google Access-Tokens sind
    // standardmäßig 1h gültig. Wir nehmen 55min als sichere Basis.
    final expiresAt = DateTime.now().add(const Duration(minutes: 55));
    _cachedToken = token;
    _cachedExpiresAt = expiresAt;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessToken, token);
    await prefs.setString(_kExpiresAt, expiresAt.toIso8601String());
    if (cred.user?.email != null) {
      await prefs.setString(_kUserEmail, cred.user!.email!);
    }
    if ((cred.user?.displayName ?? '').isNotEmpty) {
      await prefs.setString(_kUserName, cred.user!.displayName!);
    }
    if ((cred.user?.photoURL ?? '').isNotEmpty) {
      await prefs.setString(_kUserPhoto, cred.user!.photoURL!);
    }
    return true;
  }

  Future<void> disconnect() async {
    _cachedToken = null;
    _cachedExpiresAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kExpiresAt);
    await prefs.remove(_kCalendarId);
    await prefs.remove(_kUserEmail);
    await prefs.remove(_kUserName);
    await prefs.remove(_kUserPhoto);
  }

  Future<Map<String, String>> _authHeaders() async {
    var t = await _currentAccessToken();
    if (t == null) {
      // Token abgelaufen — versuche via reauth ein neues zu holen.
      final ok = await connect();
      if (!ok) {
        throw StateError(
            'Google-Calendar-Token abgelaufen. Bitte erneut verbinden.');
      }
      t = _cachedToken;
    }
    return {
      'Authorization': 'Bearer $t',
      'Content-Type': 'application/json',
    };
  }

  /// Liste aller Kalender, auf die der Nutzer Zugriff hat.
  Future<List<Map<String, dynamic>>> listCalendars() async {
    final r = await http.get(
      Uri.parse('https://www.googleapis.com/calendar/v3/users/me/calendarList'),
      headers: await _authHeaders(),
    );
    _checkResponse(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final items = (body['items'] as List?) ?? const [];
    return items.cast<Map<String, dynamic>>();
  }

  /// Liste Events im Zeitraum. Nutzt `privateExtendedProperty` als Filter,
  /// damit wir nur unsere eigenen Events laden.
  Future<List<Map<String, dynamic>>> listAktenwerkEvents({
    required String calendarId,
    required DateTime from,
    required DateTime to,
  }) async {
    final params = <String, String>{
      'timeMin': from.toUtc().toIso8601String(),
      'timeMax': to.toUtc().toIso8601String(),
      'singleEvents': 'true',
      'maxResults': '1000',
      'privateExtendedProperty': 'aktenwerk=1',
    };
    final qs = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final uri = Uri.parse(
        'https://www.googleapis.com/calendar/v3/calendars/$calendarId/events?$qs');
    final r = await http.get(uri, headers: await _authHeaders());
    _checkResponse(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final items = (body['items'] as List?) ?? const [];
    return items.cast<Map<String, dynamic>>();
  }

  /// Baut die Calendar-Events-URL. Wichtig: `@` und `.` im Calendar-ID
  /// dürfen im Pfad NICHT durch URL-Encoder in `%40`/`%2E` verwandelt
  /// werden — Googles Calendar-API matcht sonst kein Kalender-Resource.
  /// Daher stellen wir die URL von Hand zusammen.
  Uri _eventsUri(String calendarId, [String? eventId]) {
    final buf = StringBuffer('https://www.googleapis.com/calendar/v3/calendars/')
      ..write(calendarId)
      ..write('/events');
    if (eventId != null) buf.write('/$eventId');
    return Uri.parse(buf.toString());
  }

  Future<Map<String, dynamic>> insertEvent({
    required String calendarId,
    required Map<String, dynamic> event,
  }) async {
    final r = await http.post(
      _eventsUri(calendarId),
      headers: await _authHeaders(),
      body: jsonEncode(event),
    );
    _checkResponse(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateEvent({
    required String calendarId,
    required String eventId,
    required Map<String, dynamic> event,
  }) async {
    final r = await http.put(
      _eventsUri(calendarId, eventId),
      headers: await _authHeaders(),
      body: jsonEncode(event),
    );
    _checkResponse(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> deleteEvent({
    required String calendarId,
    required String eventId,
  }) async {
    final r = await http.delete(
      _eventsUri(calendarId, eventId),
      headers: await _authHeaders(),
    );
    if (r.statusCode == 404 || r.statusCode == 410) return;
    _checkResponse(r);
  }

  void _checkResponse(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    throw StateError('Calendar-API ${r.statusCode}: ${r.body}');
  }
}

final googleCalendarServiceProvider = Provider<GoogleCalendarService>((ref) {
  return GoogleCalendarService();
});

class GoogleCalendarConnectionState {
  const GoogleCalendarConnectionState({
    required this.connected,
    this.email,
    this.displayName,
    this.photoUrl,
  });
  final bool connected;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  static const disconnected = GoogleCalendarConnectionState(connected: false);
}

class GoogleCalendarConnectionNotifier
    extends StateNotifier<GoogleCalendarConnectionState> {
  GoogleCalendarConnectionNotifier(this._service)
      : super(GoogleCalendarConnectionState.disconnected);

  final GoogleCalendarService _service;

  /// Liest den zuletzt gespeicherten Zustand aus SharedPreferences.
  /// Löst KEINEN Popup aus — reines State-Laden.
  Future<void> refresh() async {
    final connected = await _service.isConnected();
    state = GoogleCalendarConnectionState(
      connected: connected,
      email: await _service.getUserEmail(),
      displayName: await _service.getUserName(),
      photoUrl: await _service.getUserPhoto(),
    );
  }

  Future<bool> connect() async {
    final ok = await _service.connect();
    await refresh();
    return ok;
  }

  Future<void> disconnect() async {
    await _service.disconnect();
    await refresh();
  }
}

final googleCalendarConnectionProvider = StateNotifierProvider<
    GoogleCalendarConnectionNotifier, GoogleCalendarConnectionState>((ref) {
  final svc = ref.watch(googleCalendarServiceProvider);
  return GoogleCalendarConnectionNotifier(svc);
});
