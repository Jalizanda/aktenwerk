import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/sync/auto_sync_service.dart';

/// Kleines Cloud-Icon in der Kopfleiste, das den Auto-Sync-Status
/// anzeigt: wird gerade synchronisiert (Spinner), zuletzt erfolgreich
/// gesynct (Haken), offline (durchgestrichen) oder Fehler.
/// Klick = manueller Sync-Anstoß.
class AutoSyncBadge extends ConsumerWidget {
  const AutoSyncBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(autoSyncServiceProvider);
    final scheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<AutoSyncStatus>(
      valueListenable: service.status,
      builder: (context, status, _) {
        final (icon, farbe, laufend) = _variante(status, scheme);
        return Tooltip(
          message: _tooltip(status),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: laufend ? null : service.triggerManually,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: laufend
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: farbe,
                      ),
                    )
                  : Icon(icon, color: farbe, size: 20),
            ),
          ),
        );
      },
    );
  }

  (IconData, Color, bool) _variante(
      AutoSyncStatus status, ColorScheme scheme) {
    switch (status.phase) {
      case AutoSyncPhase.syncing:
        return (Icons.sync, scheme.primary, true);
      case AutoSyncPhase.erfolg:
        return (Icons.cloud_done_outlined, scheme.primary, false);
      case AutoSyncPhase.fehler:
        return (Icons.sync_problem, scheme.error, false);
      case AutoSyncPhase.offline:
        return (Icons.cloud_off_outlined,
            scheme.onSurfaceVariant, false);
      case AutoSyncPhase.idle:
        return (Icons.cloud_queue_outlined,
            scheme.onSurfaceVariant, false);
    }
  }

  String _tooltip(AutoSyncStatus status) {
    switch (status.phase) {
      case AutoSyncPhase.syncing:
        return 'Synchronisiere …';
      case AutoSyncPhase.erfolg:
        final zeit = status.letzterSync == null
            ? ''
            : ' · ${_relativeZeit(status.letzterSync!)}';
        return 'Sync ok$zeit\n'
            'Letzter Lauf: ${status.anzahlGepusht} hochgeladen, '
            '${status.anzahlGezogen} geladen\n'
            '(Klick für manuellen Sync)';
      case AutoSyncPhase.fehler:
        return 'Sync-Fehler: ${status.fehler ?? "unbekannt"}\n'
            '(Klick für erneuten Versuch)';
      case AutoSyncPhase.offline:
        return 'Offline — Sync pausiert';
      case AutoSyncPhase.idle:
        return 'Auto-Sync bereit\n(Klick für manuellen Sync)';
    }
  }

  String _relativeZeit(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'vor wenigen Sekunden';
    if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min';
    if (diff.inHours < 24) return 'vor ${diff.inHours} Std';
    return DateFormat('dd.MM. HH:mm').format(t);
  }
}
