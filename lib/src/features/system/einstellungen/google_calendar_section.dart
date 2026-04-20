import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/sync/google_calendar_service.dart';
import '../../../data/sync/google_calendar_sync.dart';

/// Einstellungen-Kachel für die Google-Calendar-Integration.
/// Verbinden / trennen, Kalenderauswahl, manueller Sync, letzter Sync-Stand.
class GoogleCalendarSection extends ConsumerStatefulWidget {
  const GoogleCalendarSection({super.key});
  @override
  ConsumerState<GoogleCalendarSection> createState() =>
      _GoogleCalendarSectionState();
}

class _GoogleCalendarSectionState
    extends ConsumerState<GoogleCalendarSection> {
  bool _busy = false;
  String? _selectedCalendarId;
  String? _lastSync;
  List<Map<String, dynamic>> _calendars = const [];
  String? _lastReport;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final svc = ref.read(googleCalendarServiceProvider);
    final sync = ref.read(googleCalendarSyncServiceProvider);
    await ref
        .read(googleCalendarConnectionProvider.notifier)
        .refresh();
    _selectedCalendarId = await svc.getSelectedCalendarId();
    _lastSync = await sync.getLastSync();
    final connected =
        ref.read(googleCalendarConnectionProvider).connected;
    if (connected) {
      try {
        _calendars = await svc.listCalendars();
      } catch (e) {
        _error = 'Kalenderliste konnte nicht geladen werden: $e';
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await ref
          .read(googleCalendarConnectionProvider.notifier)
          .connect();
      if (ok) await _refresh();
    } catch (e) {
      _error = 'Verbindung fehlgeschlagen: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(googleCalendarConnectionProvider.notifier)
          .disconnect();
      _calendars = const [];
      _selectedCalendarId = null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    final calId = _selectedCalendarId;
    if (calId == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _lastReport = null;
    });
    try {
      final sync = ref.read(googleCalendarSyncServiceProvider);
      final report = await sync.syncAll(calendarId: calId);
      _lastReport = report.summary;
      await _refresh();
    } catch (e) {
      _error = 'Sync-Fehler: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(googleCalendarConnectionProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!conn.connected) ...[
          const Text(
            'Verknüpfe einen Google-Kalender, um Ortstermine, Fristen, '
            'Erläuterungstermine und Wiedervorlagen automatisch zu spiegeln.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _connect,
            icon: const Icon(Icons.link),
            label: const Text('Google-Kalender verbinden'),
          ),
        ] else ...[
          Row(
            children: [
              if (conn.photoUrl != null)
                CircleAvatar(
                    radius: 14,
                    backgroundImage: NetworkImage(conn.photoUrl!))
              else
                const CircleAvatar(
                    radius: 14, child: Icon(Icons.person, size: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(conn.displayName ?? conn.email ?? 'Verbunden',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if (conn.email != null)
                      Text(conn.email!,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _disconnect,
                icon: const Icon(Icons.link_off, size: 16),
                label: const Text('Trennen'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_calendars.isEmpty)
            OutlinedButton.icon(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Kalenderliste laden'),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: _selectedCalendarId,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Kalender für Sync',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final c in _calendars)
                  DropdownMenuItem(
                    value: c['id'] as String?,
                    child: Text(
                      '${c['summary'] ?? c['id'] ?? ''}'
                      '${c['primary'] == true ? "  (primär)" : ""}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) async {
                setState(() => _selectedCalendarId = v);
                await ref
                    .read(googleCalendarServiceProvider)
                    .setSelectedCalendarId(v);
              },
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: (_busy || _selectedCalendarId == null)
                    ? null
                    : _sync,
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync),
                label: const Text('Jetzt synchronisieren'),
              ),
              const SizedBox(width: 12),
              if (_lastSync != null)
                Flexible(
                  child: Text(
                    'Zuletzt: ${_lastSync!.split("T").first} '
                    '${_lastSync!.split("T").last.substring(0, 5)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          if (_lastReport != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(_lastReport!,
                  style: theme.textTheme.bodySmall),
            ),
          ],
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(_error!,
                style: TextStyle(
                    color: theme.colorScheme.onErrorContainer,
                    fontSize: 12)),
          ),
        ],
      ],
    );
  }
}
