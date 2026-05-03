import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Leichtgewichtiger Gmail-API-Client analog zum
/// [GoogleCalendarService]: nutzt Firebase-Auths
/// `reauthenticateWithPopup` mit Gmail-Scopes und legt das Access-Token
/// lokal ab. Verzichtet auf das google_sign_in-Web-Plugin, weil dessen
/// eager GIS-Initialisierung mit anderen Streams kollidiert.
///
/// **Phase 1**: `gmail.send` für ausgehende Mails mit Anhang.
/// **Phase 2** (später): `gmail.readonly` + `gmail.modify` für den
/// automatischen Import von Eingangsmails.
class GoogleMailService {
  GoogleMailService();

  static const _kAccessToken = 'gmail.accessToken';
  static const _kExpiresAt = 'gmail.expiresAtIso';
  static const _kUserEmail = 'gmail.userEmail';
  static const _kUserName = 'gmail.userName';
  static const _kReadonlyEnabled = 'gmail.readonlyEnabled';

  /// Scope für ausgehende Mails — schickt im Namen des angemeldeten
  /// Google-Accounts und legt die Mail in dessen "Gesendet"-Ordner ab.
  static const scopeSend = 'https://www.googleapis.com/auth/gmail.send';

  /// Scope zum Lesen der Inbox (für den künftigen Auto-Import).
  static const scopeReadonly =
      'https://www.googleapis.com/auth/gmail.readonly';

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
    if (DateTime.now()
        .add(const Duration(seconds: 60))
        .isAfter(_cachedExpiresAt!)) {
      return null;
    }
    return _cachedToken;
  }

  /// True, wenn ein gültiges Token mit zumindest `gmail.send` lokal
  /// vorliegt.
  Future<bool> isConnected() async {
    final t = await _currentAccessToken();
    return t != null;
  }

  Future<bool> isReadonlyEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kReadonlyEnabled) ?? false;
  }

  Future<String?> getUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUserEmail);
  }

  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUserName);
  }

  /// Verbindet das Gmail-Konto. Mit `withReadonly: true` wird zusätzlich
  /// der Lesescope angefordert (für Phase-2-Auto-Import).
  Future<bool> connect({bool withReadonly = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'consent'});
    provider.addScope(scopeSend);
    if (withReadonly) provider.addScope(scopeReadonly);

    UserCredential cred;
    try {
      cred = user != null
          ? await user.reauthenticateWithPopup(provider)
          : await FirebaseAuth.instance.signInWithPopup(provider);
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) debugPrint('Gmail auth error: ${e.code} ${e.message}');
      rethrow;
    }

    final oauth = cred.credential as OAuthCredential?;
    final token = oauth?.accessToken;
    if (token == null) return false;

    final expiresAt = DateTime.now().add(const Duration(minutes: 55));
    _cachedToken = token;
    _cachedExpiresAt = expiresAt;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessToken, token);
    await prefs.setString(_kExpiresAt, expiresAt.toIso8601String());
    await prefs.setBool(_kReadonlyEnabled, withReadonly);
    if (cred.user?.email != null) {
      await prefs.setString(_kUserEmail, cred.user!.email!);
    }
    if ((cred.user?.displayName ?? '').isNotEmpty) {
      await prefs.setString(_kUserName, cred.user!.displayName!);
    }
    return true;
  }

  Future<void> disconnect() async {
    _cachedToken = null;
    _cachedExpiresAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kExpiresAt);
    await prefs.remove(_kUserEmail);
    await prefs.remove(_kUserName);
    await prefs.remove(_kReadonlyEnabled);
  }

  Future<Map<String, String>> _authHeaders() async {
    var t = await _currentAccessToken();
    if (t == null) {
      final ok = await connect();
      if (!ok) {
        throw StateError(
            'Gmail-Token abgelaufen. Bitte erneut verbinden.');
      }
      t = _cachedToken;
    }
    return {
      'Authorization': 'Bearer $t',
      'Content-Type': 'application/json',
    };
  }

  /// Sendet eine Mail mit optionalem PDF-Anhang über die Gmail-API.
  /// Die Mail erscheint im "Gesendet"-Ordner des verbundenen Accounts.
  ///
  /// `to`, `cc`, `bcc` sind durch Komma getrennte Adressen — Format
  /// `name@example.com` oder `Name <name@example.com>`.
  Future<void> sendMessage({
    required String to,
    String? cc,
    String? bcc,
    required String subject,
    required String body,
    GmailAttachment? attachment,
  }) async {
    final raw = _buildRfc2822(
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      body: body,
      attachment: attachment,
    );
    // Gmail-API erwartet base64url-encodiertes RFC2822 ohne Padding.
    final encoded = base64Url
        .encode(utf8.encode(raw))
        .replaceAll('=', '');

    final r = await http.post(
      Uri.parse(
          'https://gmail.googleapis.com/gmail/v1/users/me/messages/send'),
      headers: await _authHeaders(),
      body: jsonEncode({'raw': encoded}),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw StateError(
          'Gmail-API ${r.statusCode}: ${r.body}');
    }
  }

  /// Baut eine RFC-2822-Nachricht mit optionalem Multipart-Anhang.
  String _buildRfc2822({
    required String to,
    String? cc,
    String? bcc,
    required String subject,
    required String body,
    GmailAttachment? attachment,
  }) {
    final boundary =
        'aktenwerk-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final headers = StringBuffer()
      ..writeln('To: $to')
      ..writeln('Subject: =?UTF-8?B?${base64.encode(utf8.encode(subject))}?=')
      ..writeln('MIME-Version: 1.0');
    if (cc != null && cc.trim().isNotEmpty) {
      headers.writeln('Cc: $cc');
    }
    if (bcc != null && bcc.trim().isNotEmpty) {
      headers.writeln('Bcc: $bcc');
    }

    if (attachment == null) {
      // Einfache Plaintext-Mail.
      headers.writeln('Content-Type: text/plain; charset=UTF-8');
      headers.writeln('Content-Transfer-Encoding: base64');
      headers.writeln();
      headers.writeln(_chunkBase64(base64.encode(utf8.encode(body))));
      return headers.toString();
    }

    // Multipart mit Anhang.
    headers.writeln('Content-Type: multipart/mixed; boundary="$boundary"');
    headers.writeln();
    headers.writeln('--$boundary');
    headers.writeln('Content-Type: text/plain; charset=UTF-8');
    headers.writeln('Content-Transfer-Encoding: base64');
    headers.writeln();
    headers.writeln(_chunkBase64(base64.encode(utf8.encode(body))));
    headers.writeln('--$boundary');
    headers.writeln(
        'Content-Type: ${attachment.mimeType}; name="${attachment.filename}"');
    headers.writeln('Content-Transfer-Encoding: base64');
    headers.writeln(
        'Content-Disposition: attachment; filename="${attachment.filename}"');
    headers.writeln();
    headers.writeln(_chunkBase64(base64.encode(attachment.bytes)));
    headers.writeln('--$boundary--');
    return headers.toString();
  }

  /// Bricht Base64-Strings auf 76-Zeichen-Zeilen um (RFC 2045).
  String _chunkBase64(String input) {
    final out = StringBuffer();
    for (var i = 0; i < input.length; i += 76) {
      final end = i + 76 > input.length ? input.length : i + 76;
      out.writeln(input.substring(i, end));
    }
    return out.toString();
  }
}

class GmailAttachment {
  final String filename;
  final String mimeType;
  final Uint8List bytes;
  const GmailAttachment({
    required this.filename,
    required this.mimeType,
    required this.bytes,
  });
}

final googleMailServiceProvider =
    Provider<GoogleMailService>((ref) => GoogleMailService());
