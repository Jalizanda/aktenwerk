import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

import '../../features/werkzeuge/wiedervorlagen/wiedervorlagen_repository.dart';

/// Einfacher Web-Notification-Dienst für heute/überfällige Wiedervorlagen.
///
/// Nutzt die Browser-`Notification`-API direkt (kein FCM). Läuft nur
/// während die Aktenwerk-Tab-Seite offen ist — sobald die Tab-Seite
/// geschlossen wird, gibt es keine Hintergrund-Pushes mehr. Für echte
/// Hintergrund-Benachrichtigungen wäre eine Service-Worker/FCM-Integration
/// nötig; das ist bewusst ausgelagert.
class WiedervorlagenPushService {
  WiedervorlagenPushService(this._wv);
  final WiedervorlagenRepository _wv;

  static const _prefGezeigt = 'wv.push.gezeigt.v1';

  bool get _supported {
    if (!kIsWeb) return false;
    try {
      // `Notification.permission` ist ein statischer Getter — wenn die API
      // nicht existiert, wirft der Zugriff eine Exception. Einfacher
      // Feature-Check ohne Inline-JS.
      web.Notification.permission;
      return true;
    } catch (_) {
      return false;
    }
  }

  String get permission {
    if (!_supported) return 'unsupported';
    return web.Notification.permission.toString();
  }

  Future<bool> requestPermission() async {
    if (!_supported) return false;
    final completer = Completer<String>();
    web.Notification.requestPermission(((String p) {
      if (!completer.isCompleted) completer.complete(p);
    }).toJS);
    final result = await completer.future
        .timeout(const Duration(seconds: 30), onTimeout: () => 'denied');
    return result == 'granted';
  }

  /// Prüft alle offenen Wiedervorlagen und zeigt Browser-Pushes für
  /// heute und überfällige, die wir heute noch nicht gezeigt haben.
  Future<void> checkAndNotify() async {
    if (!_supported) return;
    if (web.Notification.permission.toString() != 'granted') return;

    final prefs = await SharedPreferences.getInstance();
    final heute = _heuteIso();
    final gezeigt = prefs.getStringList(_prefGezeigt) ?? const [];

    final offene = await _wv
        .watchAll(scope: WiedervorlagenScope.offen)
        .first;

    final now = DateTime.now();
    final heuteStart = DateTime(now.year, now.month, now.day);
    final heuteEnde =
        heuteStart.add(const Duration(days: 1, seconds: -1));
    final fmt = DateFormat('dd.MM.', 'de');

    final neuGezeigt = <String>[];
    for (final w in offene) {
      final eintrag = w.eintrag;
      final key = '$heute:${eintrag.id}';
      if (gezeigt.contains(key)) {
        neuGezeigt.add(key);
        continue;
      }
      // Heute fällig oder überfällig.
      final faellig = eintrag.faelligAm;
      if (faellig.isAfter(heuteEnde)) continue;

      final prefix =
          faellig.isBefore(heuteStart) ? '⚠️ Überfällig' : '🔔 Heute';
      final body = [
        if (w.auftrag?.aktenzeichen != null)
          'Akte ${w.auftrag!.aktenzeichen}',
        if ((eintrag.anlass ?? '').isNotEmpty) eintrag.anlass!,
        'Fällig: ${fmt.format(faellig)}',
      ].join(' · ');

      try {
        web.Notification(
          '$prefix: ${eintrag.titel}',
          web.NotificationOptions(
            body: body,
            tag: 'wv-${eintrag.id}',
            requireInteraction: false,
          ),
        );
        neuGezeigt.add(key);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[wv-push] Fehler: $e');
        }
      }
    }

    await prefs.setStringList(_prefGezeigt, neuGezeigt);
  }

  String _heuteIso() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }
}

final wiedervorlagenPushServiceProvider =
    Provider<WiedervorlagenPushService>((ref) {
  return WiedervorlagenPushService(ref.watch(wiedervorlagenRepositoryProvider));
});

/// Aktiviert den Push-Wächter: läuft initial beim App-Start einmal, danach
/// alle 10 Minuten, solange die App offen ist.
final wiedervorlagenPushAutoProvider = Provider<void>((ref) {
  Timer? poll;
  scheduleMicrotask(() async {
    final svc = ref.read(wiedervorlagenPushServiceProvider);
    await svc.checkAndNotify();
  });
  poll = Timer.periodic(const Duration(minutes: 10), (_) async {
    try {
      await ref.read(wiedervorlagenPushServiceProvider).checkAndNotify();
    } catch (_) {}
  });
  ref.onDispose(() => poll?.cancel());
});
