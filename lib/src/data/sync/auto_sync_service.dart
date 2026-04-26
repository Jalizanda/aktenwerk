import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/web/web_compat.dart' as web;

import 'sync_service.dart';

/// Status des Auto-Sync. Beobachtet die Top-Bar-Anzeige.
enum AutoSyncPhase { idle, syncing, erfolg, fehler, offline }

class AutoSyncStatus {
  const AutoSyncStatus({
    required this.phase,
    this.letzterSync,
    this.fehler,
    this.anzahlGepusht = 0,
    this.anzahlGezogen = 0,
  });
  final AutoSyncPhase phase;
  final DateTime? letzterSync;
  final String? fehler;
  final int anzahlGepusht;
  final int anzahlGezogen;

  AutoSyncStatus copyWith({
    AutoSyncPhase? phase,
    DateTime? letzterSync,
    String? fehler,
    int? anzahlGepusht,
    int? anzahlGezogen,
  }) =>
      AutoSyncStatus(
        phase: phase ?? this.phase,
        letzterSync: letzterSync ?? this.letzterSync,
        fehler: fehler,
        anzahlGepusht: anzahlGepusht ?? this.anzahlGepusht,
        anzahlGezogen: anzahlGezogen ?? this.anzahlGezogen,
      );
}

/// Läuft im Hintergrund und stößt Push/Pull automatisch an:
/// 1. Beim App-Start (mit 3 s Verzögerung, damit Auth/Firebase steht).
/// 2. Alle [intervall] Minuten (Default: 3 min).
/// 3. Wenn der Browser-Tab Fokus wiederbekommt (für schnelle Pulls
///    nach Pausen am Rechner).
/// 4. Wenn das OS meldet, dass wieder Netz da ist.
///
/// Push ist **inkrementell**: nur Rows mit `updatedAt > lastPush` gehen
/// in die Cloud. Pull ist immer vollständig — die Drift-Tabellen
/// schreiben via `insertOnConflictUpdate`, neuere Inhalte überschreiben
/// ältere.
class AutoSyncService {
  AutoSyncService(this._ref);
  final Ref _ref;

  static const _keyLastPush = 'auto_sync.last_push';
  static const _keyEnabled = 'auto_sync.enabled';
  static const _keyIntervallMinuten = 'auto_sync.intervall_minuten';

  /// Verfügbare Sync-Intervalle (in Minuten). Der Nutzer wählt daraus
  /// in den Einstellungen.
  static const intervallOptionen = [1, 3, 5, 10, 15, 30, 60];
  static const intervallDefault = 3;

  Timer? _timer;
  StreamSubscription<dynamic>? _onlineSub;
  StreamSubscription<dynamic>? _offlineSub;
  StreamSubscription<dynamic>? _focusSub;
  bool _laeuft = false;

  /// Aktueller Status — von UI-Komponenten beobachtbar.
  final status = ValueNotifier<AutoSyncStatus>(
      const AutoSyncStatus(phase: AutoSyncPhase.idle));

  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyEnabled) == false) return;

    // 1) Initial: nach 3 s ersten Sync
    Future<void>.delayed(const Duration(seconds: 3), _trigger);

    // 2) Periodisch — Intervall aus Einstellungen
    final minuten = prefs.getInt(_keyIntervallMinuten) ?? intervallDefault;
    _timer?.cancel();
    _timer = Timer.periodic(
        Duration(minutes: minuten.clamp(1, 240)), (_) => _trigger());

    // 3) Browser-Events (Web-only; auf Mobile-Platforms leere Streams)
    if (kIsWeb) {
      _focusSub = web.windowFocusStream.listen((_) => _trigger());
      _onlineSub = web.windowOnlineStream.listen((_) => _trigger());
      _offlineSub = web.windowOfflineStream.listen((_) {
        status.value = status.value.copyWith(
            phase: AutoSyncPhase.offline, fehler: 'offline');
      });
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    await _focusSub?.cancel();
    await _onlineSub?.cancel();
    await _offlineSub?.cancel();
  }

  /// Manueller Anstoß (z. B. wenn der Nutzer auf das Wolken-Icon klickt).
  Future<void> triggerManually() async {
    await _trigger();
  }

  Future<void> _trigger() async {
    if (_laeuft) return;
    final sync = _ref.read(syncServiceProvider);
    if (!sync.enabled) return;

    // Offline-Check (Web): wenn das Fenster offline ist, abbrechen.
    if (kIsWeb && !web.isBrowserOnline) {
      status.value = status.value.copyWith(phase: AutoSyncPhase.offline);
      return;
    }

    _laeuft = true;
    status.value = status.value.copyWith(phase: AutoSyncPhase.syncing);
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPushIso = prefs.getString(_keyLastPush);
      final lastPush = lastPushIso == null
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.tryParse(lastPushIso) ??
              DateTime.fromMillisecondsSinceEpoch(0);

      final vorPush = DateTime.now();
      final gepusht = await sync.pushChangedSince(lastPush);
      await prefs.setString(_keyLastPush, vorPush.toIso8601String());

      final report = await sync.pullAll();
      final gezogen =
          report.values.fold<int>(0, (a, b) => a + b);

      status.value = AutoSyncStatus(
        phase: AutoSyncPhase.erfolg,
        letzterSync: DateTime.now(),
        anzahlGepusht: gepusht,
        anzahlGezogen: gezogen,
      );
    } catch (e) {
      status.value = status.value.copyWith(
          phase: AutoSyncPhase.fehler, fehler: e.toString());
    } finally {
      _laeuft = false;
    }
  }

  /// Ein-/Ausschalten des Auto-Sync. Wird in SharedPreferences
  /// persistiert, gilt also nach Reload weiter.
  static Future<bool> istAktiviert() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? true;
  }

  Future<void> setAktiviert(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, value);
    if (value) {
      await start();
    } else {
      await stop();
    }
  }

  /// Aktuelles Sync-Intervall in Minuten (Default 3).
  static Future<int> intervallMinuten() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyIntervallMinuten) ?? intervallDefault;
  }

  /// Setzt das Sync-Intervall und startet den Timer neu, damit der
  /// neue Wert sofort greift.
  Future<void> setIntervallMinuten(int minuten) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyIntervallMinuten, minuten.clamp(1, 240));
    // Timer neu aufsetzen, falls Service schon läuft.
    if (prefs.getBool(_keyEnabled) != false) {
      await stop();
      await start();
    }
  }
}

final autoSyncServiceProvider = Provider<AutoSyncService>((ref) {
  final service = AutoSyncService(ref);
  ref.onDispose(() => service.stop());
  return service;
});
