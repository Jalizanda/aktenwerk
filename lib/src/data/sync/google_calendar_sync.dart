import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/werkzeuge/termine/termine_repository.dart';
import 'google_calendar_service.dart';

class GoogleCalendarSyncReport {
  final int erstellt;
  final int aktualisiert;
  final int unveraendert;
  final int entfernt;
  final List<String> fehler;
  const GoogleCalendarSyncReport({
    this.erstellt = 0,
    this.aktualisiert = 0,
    this.unveraendert = 0,
    this.entfernt = 0,
    this.fehler = const [],
  });

  String get summary {
    final parts = <String>[];
    if (erstellt > 0) parts.add('$erstellt neu');
    if (aktualisiert > 0) parts.add('$aktualisiert aktualisiert');
    if (entfernt > 0) parts.add('$entfernt entfernt');
    if (unveraendert > 0) parts.add('$unveraendert unveraendert');
    if (parts.isEmpty) parts.add('keine Aenderungen');
    if (fehler.isNotEmpty) parts.add('${fehler.length} Fehler');
    return parts.join(' / ');
  }
}

/// Synchronisiert Aktenwerk-Termine in einen Google-Kalender.
/// Push-only mit Dedup über `aktenwerkRef` in
/// `extendedProperties.private`.
class GoogleCalendarSyncService {
  GoogleCalendarSyncService(this._calendar, this._termine);

  final GoogleCalendarService _calendar;
  final TermineRepository _termine;

  static const _kLastSyncPref = 'gcal.lastSyncIso';
  static const _propRef = 'aktenwerkRef';
  static const _propMarker = 'aktenwerk';

  Future<String?> getLastSync() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLastSyncPref);
  }

  Future<void> _setLastSync(DateTime when) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastSyncPref, when.toIso8601String());
  }

  Future<GoogleCalendarSyncReport> syncAll({
    required String calendarId,
  }) async {
    final from = DateTime.now().subtract(const Duration(days: 30));
    final to = DateTime.now().add(const Duration(days: 365));

    final locals = await _termine.watchAll(from: from, to: to).first;

    final remote = await _calendar.listAktenwerkEvents(
      calendarId: calendarId,
      from: from,
      to: to,
    );
    final byRef = <String, Map<String, dynamic>>{};
    for (final e in remote) {
      final ref = _readRef(e);
      if (ref != null) byRef[ref] = e;
    }

    var erstellt = 0, aktualisiert = 0, unveraendert = 0, entfernt = 0;
    final fehler = <String>[];

    final activeRefs = <String>{};
    for (final t in locals) {
      final ref = _refOf(t);
      if (ref == null) continue;
      activeRefs.add(ref);
      final payload = _toEvent(t, ref);
      final existing = byRef[ref];
      try {
        if (existing == null) {
          await _calendar.insertEvent(
              calendarId: calendarId, event: payload);
          erstellt++;
        } else if (_changed(existing, payload)) {
          final merged = _merge(existing, payload);
          await _calendar.updateEvent(
            calendarId: calendarId,
            eventId: existing['id'] as String,
            event: merged,
          );
          aktualisiert++;
        } else {
          unveraendert++;
        }
      } catch (e) {
        fehler.add('$ref: $e');
      }
    }

    for (final entry in byRef.entries) {
      if (activeRefs.contains(entry.key)) continue;
      try {
        await _calendar.deleteEvent(
          calendarId: calendarId,
          eventId: entry.value['id'] as String,
        );
        entfernt++;
      } catch (e) {
        fehler.add('${entry.key}(del): $e');
      }
    }

    await _setLastSync(DateTime.now());
    return GoogleCalendarSyncReport(
      erstellt: erstellt,
      aktualisiert: aktualisiert,
      unveraendert: unveraendert,
      entfernt: entfernt,
      fehler: fehler,
    );
  }

  static String? _refOf(TerminEintrag t) {
    if (t.quellId == null) return null;
    return '${t.typ}:${t.quellId}';
  }

  static String? _readRef(Map<String, dynamic> e) {
    final ext = e['extendedProperties'] as Map<String, dynamic>?;
    final priv = ext?['private'] as Map<String, dynamic>?;
    return priv?[_propRef] as String?;
  }

  Map<String, dynamic> _toEvent(TerminEintrag t, String ref) {
    final start = t.zeitpunkt;
    final end = t.ende ?? start.add(const Duration(hours: 1));
    final titel = t.aktenzeichen != null
        ? '${t.titel} · ${t.aktenzeichen}'
        : t.titel;
    return {
      'summary': titel,
      'start': {
        'dateTime': start.toIso8601String(),
        'timeZone': 'Europe/Berlin',
      },
      'end': {
        'dateTime': end.toIso8601String(),
        'timeZone': 'Europe/Berlin',
      },
      if ((t.ort ?? '').isNotEmpty) 'location': t.ort,
      'description': _buildBeschreibung(t),
      'extendedProperties': {
        'private': {
          _propMarker: '1',
          _propRef: ref,
          'aktenwerkTyp': t.typ,
          if (t.auftragId != null) 'aktenwerkAuftragId': '${t.auftragId}',
        },
      },
    };
  }

  String _buildBeschreibung(TerminEintrag t) {
    final lines = <String>[
      'Aktenwerk · ${t.typ}',
      if (t.aktenzeichen != null) 'Akte: ${t.aktenzeichen}',
      if ((t.telefon ?? '').isNotEmpty) 'Tel.: ${t.telefon}',
    ];
    return lines.join('\n');
  }

  bool _changed(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a['summary'] != b['summary']) return true;
    if ((a['location'] ?? '') != (b['location'] ?? '')) return true;
    if ((a['description'] ?? '') != (b['description'] ?? '')) return true;
    final aStart = (a['start'] as Map?)?['dateTime'];
    final bStart = (b['start'] as Map?)?['dateTime'];
    if (_normIso(aStart) != _normIso(bStart)) return true;
    final aEnd = (a['end'] as Map?)?['dateTime'];
    final bEnd = (b['end'] as Map?)?['dateTime'];
    if (_normIso(aEnd) != _normIso(bEnd)) return true;
    return false;
  }

  String? _normIso(Object? v) {
    if (v is! String) return null;
    return DateTime.tryParse(v)?.toUtc().toIso8601String();
  }

  Map<String, dynamic> _merge(
      Map<String, dynamic> existing, Map<String, dynamic> payload) {
    final merged = Map<String, dynamic>.from(existing);
    merged['summary'] = payload['summary'];
    merged['location'] = payload['location'];
    merged['description'] = payload['description'];
    merged['start'] = payload['start'];
    merged['end'] = payload['end'];
    final existingPriv = ((existing['extendedProperties']
            as Map<String, dynamic>?)?['private']
        as Map<String, dynamic>?) ??
        const {};
    final payloadPriv = ((payload['extendedProperties']
            as Map<String, dynamic>?)?['private']
        as Map<String, dynamic>?) ??
        const {};
    merged['extendedProperties'] = {
      'private': {...existingPriv, ...payloadPriv},
    };
    return merged;
  }
}

final googleCalendarSyncServiceProvider =
    Provider<GoogleCalendarSyncService>((ref) {
  final cal = ref.watch(googleCalendarServiceProvider);
  final term = ref.watch(termineRepositoryProvider);
  return GoogleCalendarSyncService(cal, term);
});
