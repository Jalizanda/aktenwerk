import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/werkzeuge/termine/termine_repository.dart';
import 'google_calendar_service.dart';
import 'google_calendar_sync.dart';

/// Auto-Sync-Wächter: startet einen Google-Kalender-Push
///
///   1) Einmalig beim App-Start, sobald die Termin-Liste das erste Mal
///      geliefert wird (dann ist Firebase-Auth + Drift bereit).
///   2) Entprellt (3 s) nach jeder Änderung der Termin-Liste.
///
/// Läuft nur, wenn der Nutzer einen Google-Kalender verbunden und einen
/// Zielkalender ausgewählt hat; ansonsten no-op.
final googleCalendarAutoSyncProvider = Provider<void>((ref) {
  Timer? debounce;
  var syncing = false;
  var hasDoneStartupSync = false;

  Future<void> runSync({required String ursache}) async {
    if (syncing) return;
    final svc = ref.read(googleCalendarServiceProvider);
    if (!await svc.isConnected()) return;
    final calId = await svc.getSelectedCalendarId();
    if (calId == null) return;

    syncing = true;
    try {
      final report = await ref
          .read(googleCalendarSyncServiceProvider)
          .syncAll(calendarId: calId);
      if (kDebugMode) {
        debugPrint('[gcal auto-sync · $ursache] ${report.summary}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[gcal auto-sync · $ursache] Fehler: $e');
    } finally {
      syncing = false;
    }
  }

  ref.listen<AsyncValue<List<TerminEintrag>>>(termineListProvider,
      (prev, next) {
    if (next.isLoading || next.hasError) return;

    // Erste Auslieferung der Termin-Liste -> einmaliger Start-Sync.
    if (!hasDoneStartupSync) {
      hasDoneStartupSync = true;
      scheduleMicrotask(() => runSync(ursache: 'start'));
      return;
    }

    // Folge-Änderungen: entprellt pushen, damit mehrere Edits hintereinander
    // nur eine Sync-Runde auslösen.
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 3),
        () => runSync(ursache: 'change'));
  }, fireImmediately: true);

  ref.onDispose(() => debounce?.cancel());
});
