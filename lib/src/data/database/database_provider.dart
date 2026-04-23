import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sync/org_service.dart';
import 'app_database.dart';

/// Übersetzt eine Mandanten-ID in einen für IndexedDB erlaubten
/// Datenbank-Namen. Format: `aktenwerk_<orgId>`.
String _dbNameFor(String? orgId) {
  if (orgId == null || orgId.isEmpty) return 'aktenwerk';
  final safe = orgId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  return 'aktenwerk_$safe';
}

/// Flag-Key für die einmalige Legacy-Migration der alten `aktenwerk`-DB
/// in eine mandantengebundene DB pro Nutzer.
String _migrationFlagKey(String? orgId) =>
    'aktenwerk.legacy_migrated.${orgId ?? "_none_"}';

/// Die lokale Drift-Datenbank hängt ab `v18` am aktiven Mandanten. So
/// hält Aktenwerk die Daten von Demo- und Produktiv-Mandant physisch
/// getrennt (je eine eigene IndexedDB).
///
/// Wenn es lokal noch die alte, mandantenlose `aktenwerk`-DB gibt, wird
/// sie beim ersten Öffnen des neuen DB-Namens EINMALIG über
/// `customStatement`-Inserts in den neuen Mandanten gespiegelt. Dafür
/// braucht es keinen zweiten Drift-Anschluss — wir nutzen das
/// [LegacyMigration]-Helfer-Objekt, das die alte DB nur auf
/// Anforderung lädt.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final orgId = ref.watch(currentOrgIdProvider).valueOrNull;
  final dbName = _dbNameFor(orgId);
  final db = AppDatabase.named(dbName);
  ref.onDispose(db.close);

  // Legacy-Migration in einen Microtask verschieben — damit das Anlegen
  // der DB nicht blockiert. Läuft nur einmal pro Mandant/Browser.
  Future.microtask(() => _maybeMigrateLegacy(orgId, db));
  return db;
});

Future<void> _maybeMigrateLegacy(String? orgId, AppDatabase target) async {
  if (orgId == null || orgId.isEmpty) return; // nur mit aktiver Org
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_migrationFlagKey(orgId)) == true) return;

  // Prüfen, ob die aktuelle Mandanten-DB bereits Daten hat.
  try {
    final rows = await target
        .customSelect('SELECT COUNT(*) AS c FROM auftraege')
        .getSingleOrNull();
    final anzahl = rows?.data['c'] as int? ?? 0;
    if (anzahl > 0) {
      // Ziel-DB ist nicht leer → keine Migration, nur Flag setzen.
      await prefs.setBool(_migrationFlagKey(orgId), true);
      return;
    }
  } catch (_) {
    // Tabelle fehlt bei ganz frischem Setup — ignorieren und unten Flag setzen.
  }

  // Alte Legacy-DB parallel öffnen, alle Tabellen in die Zieldatenbank
  // kopieren. Bei Fehler wird die alte Legacy-DB nicht angefasst — das
  // Flag bleibt aus, so dass beim nächsten Start erneut versucht wird.
  AppDatabase? legacy;
  try {
    legacy = AppDatabase.named('aktenwerk');
    // Heuristik: wenn Legacy auch leer → kein Migrationsbedarf.
    final legacyRows = await legacy
        .customSelect('SELECT COUNT(*) AS c FROM auftraege')
        .getSingleOrNull();
    final legacyCount = legacyRows?.data['c'] as int? ?? 0;
    if (legacyCount == 0) {
      await prefs.setBool(_migrationFlagKey(orgId), true);
      return;
    }

    // Alle Tabellennamen zur Migration – identisch zum Backup-Service.
    const tableNames = <String>[
      'kunden',
      'auftraege',
      'auftraege_geraete',
      'gutachten',
      'rechnungen',
      'stunden',
      'fotos',
      'einstellungen',
      'anschreiben',
      'textbausteine',
      'dokumente',
      'kalkulationen',
      'rueckfragen',
      'auslagen',
      'angebote',
      'wiedervorlagen',
      'versand',
      'fortbildungen',
      'artikel',
      'benutzer',
      'geraete',
      'normen',
      'eingangsrechnungen',
      'lieferanten',
      'erlaeuterungen',
      'konten',
      'protokolle',
      'partner',
      'journaleintraege',
      'maengel',
      'uebergaben',
      'qualifikationen',
      'bauteiloeffnungen',
      'messwerte',
      'wertermittlungen',
    ];

    await target.transaction(() async {
      await target.customStatement('PRAGMA foreign_keys = OFF');
      try {
        for (final tn in tableNames) {
          try {
            final rows = await legacy!
                .customSelect('SELECT * FROM $tn')
                .get();
            if (rows.isEmpty) continue;
            // Zieltabelle leeren und alte Daten einspielen.
            await target.customStatement('DELETE FROM $tn');
            for (final r in rows) {
              final data = r.data;
              final cols = data.keys.toList();
              if (cols.isEmpty) continue;
              final placeholders = List.filled(cols.length, '?').join(', ');
              final sql =
                  'INSERT INTO $tn (${cols.join(', ')}) VALUES ($placeholders)';
              final args = cols.map((c) => data[c] as Object?).toList();
              await target.customStatement(sql, args);
            }
          } catch (_) {
            // Eine fehlende Tabelle in Legacy ist kein Abbruchgrund.
          }
        }
      } finally {
        await target.customStatement('PRAGMA foreign_keys = ON');
      }
    });

    await prefs.setBool(_migrationFlagKey(orgId), true);
  } catch (_) {
    // Migration fehlgeschlagen — nicht flaggen, später erneut versuchen.
  } finally {
    try {
      await legacy?.close();
    } catch (_) {}
  }
}
