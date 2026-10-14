import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class AktenExportService {
  AktenExportService(this._db);
  final AppDatabase _db;

  Future<void> exportAkte(int auftragId) async {
    final auftrag = await (_db.select(_db.auftraege)..where((t) => t.id.equals(auftragId))).getSingleOrNull();
    if (auftrag == null) return;

    final kunde = auftrag.kundeId != null
        ? await (_db.select(_db.kunden)..where((t) => t.id.equals(auftrag.kundeId!))).getSingleOrNull()
        : null;

    final stunden = await (_db.select(_db.stunden)..where((t) => t.auftragId.equals(auftragId))).get();
    final rechnungen = await (_db.select(_db.rechnungen)..where((t) => t.auftragId.equals(auftragId))).get();
    final gutachten = await (_db.select(_db.gutachten)..where((t) => t.auftragId.equals(auftragId))).get();
    final auslagen = await (_db.select(_db.auslagen)..where((t) => t.auftragId.equals(auftragId))).get();
    final notizen = await (_db.select(_db.rechercheNotizen)..where((t) => t.auftragId.equals(auftragId))).get();
    final fotos = await (_db.select(_db.fotos)..where((t) => t.auftragId.equals(auftragId))).get();
    final dokumente = await (_db.select(_db.dokumente)..where((t) => t.auftragId.equals(auftragId))).get();

    final archive = Archive();

    final jsonData = <String, dynamic>{
      'version': '1.0',
      'exportDatum': DateTime.now().toIso8601String(),
      'auftrag': auftrag.toJson(),
      'kunde': kunde?.toJson(),
      'stunden': stunden.map((e) => e.toJson()).toList(),
      'rechnungen': rechnungen.map((e) => e.toJson()).toList(),
      'gutachten': gutachten.map((e) => e.toJson()).toList(),
      'auslagen': auslagen.map((e) => e.toJson()).toList(),
      'rechercheNotizen': notizen.map((e) => e.toJson()).toList(),
      'fotos': fotos.map((e) {
        final map = e.toJson();
        map.remove('daten');
        return map;
      }).toList(),
      'dokumente': dokumente.map((e) {
        final map = e.toJson();
        map.remove('daten');
        return map;
      }).toList(),
    };

    final jsonBytes = utf8.encode(jsonEncode(jsonData));
    archive.addFile(ArchiveFile('akte_daten.json', jsonBytes.length, jsonBytes));

    const schemaText = '''
Aktenwerk - Export Schema Beschreibung
======================================
Dieses ZIP-Archiv enthält alle Daten einer Akte (Auftrag) zur Erfüllung der 10-jährigen Aufbewahrungspflicht.
- akte_daten.json: Enthält sämtliche strukturierten Metadaten, Buchungen, Rechnungen und Gutachtentexte.
- dokumente/: Beinhaltet alle in der Akte gespeicherten Dokumente (z.B. PDFs, Scans) im Originalformat.
- fotos/: Beinhaltet alle in der Akte gespeicherten Fotos im Originalformat.

Die JSON-Datei ist strukturiert in Listen für die jeweiligen Tabellen. Die Primärschlüssel (IDs) sind 
die internen Datenbank-IDs zum Zeitpunkt des Exports.
''';
    final schemaBytes = utf8.encode(schemaText);
    archive.addFile(ArchiveFile('import_schema_erklaerung.txt', schemaBytes.length, schemaBytes));

    for (final f in fotos) {
      if (f.daten != null && f.daten!.isNotEmpty) {
        final ext = f.pfad?.split('.').last ?? 'jpg';
        final name = 'fotos/${f.id}_${f.titel ?? "Foto"}.$ext'.replaceAll(RegExp(r'[^\w\.\-\/]'), '_');
        archive.addFile(ArchiveFile(name, f.daten!.length, f.daten!));
      }
    }

    for (final d in dokumente) {
      if (d.daten != null && d.daten!.isNotEmpty) {
        final name = 'dokumente/${d.id}_${d.titel ?? "Dokument.pdf"}'.replaceAll(RegExp(r'[^\w\.\-\/]'), '_');
        archive.addFile(ArchiveFile(name, d.daten!.length, d.daten!));
      }
    }

    final zipEncoder = ZipEncoder();
    final zipData = zipEncoder.encode(archive);

    final az = auftrag.aktenzeichen?.replaceAll(RegExp(r'[^\w\-]'), '_') ?? 'Akte_${auftrag.id}';
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    final filename = 'AktenExport_${az}_$date.zip';

    final xfile = XFile.fromData(
      Uint8List.fromList(zipData),
      name: filename,
      mimeType: 'application/zip',
    );
    await Share.shareXFiles([xfile], text: 'ZIP-Export der Akte $az');
  }
}

final aktenExportServiceProvider = Provider<AktenExportService>((ref) {
  return AktenExportService(ref.watch(appDatabaseProvider));
});
