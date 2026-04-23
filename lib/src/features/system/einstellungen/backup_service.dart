import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Legt vollständige JSON-Backups aller Drift-Tabellen an und spielt sie
/// wieder ein. Dient als Sicherheitsnetz, falls bei einem Release oder
/// Browser-Umzug lokale Daten verloren gehen.
class BackupService {
  BackupService(this._db);
  final AppDatabase _db;

  /// Liste aller Tabellen, die ge-/backupped werden. Wenn eine neue Tabelle
  /// dazu kommt, hier ergänzen.
  List<TableInfo> _alleTabellen() => [
        _db.kunden,
        _db.auftraege,
        _db.auftraegeGeraete,
        _db.gutachten,
        _db.rechnungen,
        _db.stunden,
        _db.fotos,
        _db.einstellungen,
        _db.anschreiben,
        _db.textbausteine,
        _db.dokumente,
        _db.kalkulationen,
        _db.rueckfragen,
        _db.auslagen,
        _db.angebote,
        _db.wiedervorlagen,
        _db.versand,
        _db.fortbildungen,
        _db.artikel,
        _db.benutzer,
        _db.geraete,
        _db.normen,
        _db.eingangsrechnungen,
        _db.lieferanten,
        _db.erlaeuterungen,
        _db.konten,
        _db.protokolle,
        _db.partner,
        _db.journaleintraege,
        _db.maengel,
        _db.uebergaben,
        _db.qualifikationen,
        _db.bauteiloeffnungen,
        _db.messwerte,
        _db.wertermittlungen,
      ];

  /// Exportiert alle Tabellen als JSON.
  Future<String> exportAllAsJson() async {
    final result = <String, dynamic>{
      'version': _db.schemaVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'tables': <String, List<Map<String, dynamic>>>{},
    };
    final tables = result['tables'] as Map<String, List<Map<String, dynamic>>>;
    for (final t in _alleTabellen()) {
      final rows = await _db.customSelect('SELECT * FROM ${t.actualTableName}').get();
      tables[t.actualTableName] = rows.map((r) => _rowToJson(r.data)).toList();
    }
    return const JsonEncoder.withIndent('  ').convert(result);
  }

  /// Importiert aus JSON. Vor dem Einspielen werden alle bestehenden
  /// Einträge der zu importierenden Tabellen gelöscht (pro-Tabelle-Reset).
  /// Tabellen, die im Backup fehlen, bleiben unangetastet.
  Future<BackupImportReport> importFromJson(String json) async {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup-Datei hat unerwartetes Format.');
    }
    final tables = decoded['tables'];
    if (tables is! Map) {
      throw const FormatException('Schlüssel "tables" fehlt.');
    }

    final tabellen = {for (final t in _alleTabellen()) t.actualTableName: t};
    final report = BackupImportReport();

    await _db.transaction(() async {
      // Foreign-Key-Checks temporär aus, sonst kollidieren Inserts in
      // umgekehrter Reihenfolge.
      await _db.customStatement('PRAGMA foreign_keys = OFF');
      try {
        for (final entry in tables.entries) {
          final tableName = entry.key.toString();
          final rows = entry.value;
          if (rows is! List) continue;
          final info = tabellen[tableName];
          if (info == null) {
            report.unbekannteTabellen.add(tableName);
            continue;
          }
          await _db.customStatement('DELETE FROM $tableName');
          for (final r in rows) {
            if (r is! Map) continue;
            await _insertRow(tableName, info, r.cast<String, dynamic>());
            report.insertedProTabelle[tableName] =
                (report.insertedProTabelle[tableName] ?? 0) + 1;
          }
        }
      } finally {
        await _db.customStatement('PRAGMA foreign_keys = ON');
      }
    });
    return report;
  }

  Future<void> _insertRow(String tableName, TableInfo info,
      Map<String, dynamic> row) async {
    final cols = info.$columns.map((c) => c.$name).toSet();
    final filtered = <String, dynamic>{
      for (final e in row.entries)
        if (cols.contains(e.key)) e.key: _fromJson(e.value),
    };
    if (filtered.isEmpty) return;
    final fields = filtered.keys.toList();
    final placeholders = List.filled(fields.length, '?').join(', ');
    final sql =
        'INSERT INTO $tableName (${fields.join(', ')}) VALUES ($placeholders)';
    final args = fields.map((f) => filtered[f] as Object?).toList();
    await _db.customStatement(sql, args);
  }

  /// Konvertiert Zeilen-Daten in JSON-freundliche Typen.
  Map<String, dynamic> _rowToJson(Map<String, dynamic> data) {
    final out = <String, dynamic>{};
    data.forEach((k, v) {
      if (v == null) {
        out[k] = null;
      } else if (v is DateTime) {
        // Drift speichert DateTime intern als Millis oder ISO — wir
        // serialisieren immer als Millis (unix).
        out[k] = v.millisecondsSinceEpoch;
      } else if (v is bool) {
        out[k] = v;
      } else if (v is num || v is String) {
        out[k] = v;
      } else {
        out[k] = v.toString();
      }
    });
    return out;
  }

  Object? _fromJson(Object? v) {
    // Drift-Inserts erwarten Primitive — Maps/Listen wandeln wir in Strings.
    if (v is Map || v is List) return jsonEncode(v);
    return v;
  }
}

class BackupImportReport {
  final Map<String, int> insertedProTabelle = {};
  final List<String> unbekannteTabellen = [];

  int get totalRows =>
      insertedProTabelle.values.fold<int>(0, (a, b) => a + b);

  String get summary {
    final tabellen = insertedProTabelle.length;
    final unknown = unbekannteTabellen.isEmpty
        ? ''
        : ' · unbekannt (übersprungen): ${unbekannteTabellen.join(', ')}';
    return 'Importiert: $totalRows Zeilen aus $tabellen Tabellen$unknown';
  }
}

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref.watch(appDatabaseProvider));
});
