import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class AktenExportService {
  AktenExportService(this._db);
  final AppDatabase _db;

  Future<void> exportAkte(int auftragId) async {
    final archive = Archive();
    final jsonMap = <String, dynamic>{};

    // 1. Auftrag laden
    final auftrag = await (_db.select(_db.auftraege)..where((t) => t.id.equals(auftragId))).getSingleOrNull();
    if (auftrag == null) throw Exception('Akte nicht gefunden');
    jsonMap['auftrag'] = auftrag.toJson();

    // 2. Kunde laden
    if (auftrag.kundeId != null) {
      final kunde = await (_db.select(_db.kunden)..where((t) => t.id.equals(auftrag.kundeId!))).getSingleOrNull();
      if (kunde != null) {
        jsonMap['kunde'] = kunde.toJson();
      }
    }

    // 3. Gutachten
    final gutachtenList = await (_db.select(_db.gutachten)..where((t) => t.auftragId.equals(auftragId))).get();
    jsonMap['gutachten'] = gutachtenList.map((e) => e.toJson()).toList();

    // 4. Rechnungen
    final rechnungenList = await (_db.select(_db.rechnungen)..where((t) => t.auftragId.equals(auftragId))).get();
    jsonMap['rechnungen'] = rechnungenList.map((e) => e.toJson()).toList();

    // 5. Eingangsrechnungen
    final erList = await (_db.select(_db.eingangsrechnungen)..where((t) => t.auftragId.equals(auftragId))).get();
    jsonMap['eingangsrechnungen'] = erList.map((e) => e.toJson()).toList();

    // 6. Auslagen
    final auslagenList = await (_db.select(_db.auslagen)..where((t) => t.auftragId.equals(auftragId))).get();
    jsonMap['auslagen'] = auslagenList.map((e) => e.toJson()).toList();

    // 7. Stunden
    final stundenList = await (_db.select(_db.stunden)..where((t) => t.auftragId.equals(auftragId))).get();
    jsonMap['stunden'] = stundenList.map((e) => e.toJson()).toList();

    // 8. Angebote
    final angeboteList = await (_db.select(_db.angebote)..where((t) => t.auftragId.equals(auftragId))).get();
    jsonMap['angebote'] = angeboteList.map((e) => e.toJson()).toList();

    // 9. Fotos
    final fotosList = await (_db.select(_db.fotos)..where((t) => t.auftragId.equals(auftragId))).get();
    jsonMap['fotos'] = fotosList.map((e) => e.toJson()).toList();

    // 10. Dokumente
    final dokList = await (_db.select(_db.dokumente)..where((t) => t.auftragId.equals(auftragId))).get();
    jsonMap['dokumente'] = dokList.map((e) => e.toJson()).toList();

    // JSON Datei zum Archiv hinzufügen
    final jsonBytes = utf8.encode(jsonEncode(jsonMap));
    archive.addFile(ArchiveFile('akte_${auftrag.aktenzeichen ?? auftragId}.json', jsonBytes.length, jsonBytes));

    // Lade Dokumente und Fotos herunter
    int fileCounter = 1;
    Future<void> addFileToArchive(String? url, String defaultName) async {
      if (url == null || url.isEmpty) return;
      try {
        final resp = await http.get(Uri.parse(url));
        if (resp.statusCode == 200) {
          // Extrahiere Dateinamen aus URL oder nutze Standard
          String fname = defaultName;
          final uri = Uri.parse(url);
          if (uri.pathSegments.isNotEmpty) {
            final lastSegment = uri.pathSegments.last;
            if (lastSegment.contains('.')) {
              fname = lastSegment.split('?').first.split('/').last;
            }
          }
          final decodedFname = Uri.decodeComponent(fname);
          archive.addFile(ArchiveFile('dokumente/$fileCounter-$decodedFname', resp.bodyBytes.length, resp.bodyBytes));
          fileCounter++;
        }
      } catch (e) {
        // Log Error but continue
        print('Error downloading $url: $e');
      }
    }

    // PDFs aus Rechnungen
    for (final r in rechnungenList) {
      if (r.pdfStorageUrl != null) {
        await addFileToArchive(r.pdfStorageUrl, r.pdfDateiname ?? 'Rechnung_${r.rechnungsnummer}.pdf');
      }
    }

    // Beweisbeschluss + Objektfoto aus Auftrag
    await addFileToArchive(auftrag.beweisbeschlussStorageUrl, auftrag.beweisbeschlussDateiname ?? 'Beweisbeschluss.pdf');
    await addFileToArchive(auftrag.objektFotoStorageUrl, auftrag.objektFotoDateiname ?? 'Objektfoto.jpg');

    // PDFs aus Angeboten
    for (final a in angeboteList) {
      if (a.pdfStorageUrl != null) {
        await addFileToArchive(a.pdfStorageUrl, a.pdfDateiname ?? 'Angebot_${a.angebotsnummer}.pdf');
      }
    }

    // Belege aus Eingangsrechnungen (Achtung: belegeJson ist eine Liste von JSON Objekten)
    for (final er in erList) {
      if (er.belegeJson != null) {
        try {
          final list = jsonDecode(er.belegeJson!) as List;
          for (final b in list) {
            final url = b['storageUrl'] as String?;
            final fname = b['dateiname'] as String?;
            await addFileToArchive(url, fname ?? 'Eingangsbeleg.pdf');
          }
        } catch (_) {}
      }
    }

    // Belege aus Auslagen (belegPfad ist in der Regel eine URL, wenn es in der Cloud liegt, ansonsten lokal)
    for (final aus in auslagenList) {
      if (aus.belegPfad != null && aus.belegPfad!.startsWith('http')) {
        await addFileToArchive(aus.belegPfad, 'Auslagenbeleg.pdf');
      }
    }

    // Fotos
    for (final f in fotosList) {
      if (f.storageUrl != null) {
        await addFileToArchive(f.storageUrl, 'Foto_${f.id}.jpg');
      }
    }

    // Dokumente
    for (final d in dokList) {
      if (d.storagePfad != null && d.storagePfad!.startsWith('http')) {
        await addFileToArchive(d.storagePfad, d.titel ?? 'Dokument_${d.id}');
      }
    }

    // README hinzufügen
    final readme = '''
Akten-Export - 10-Jahres-Aufbewahrung

Dies ist der Export der Akte ${auftrag.aktenzeichen ?? auftragId} aus der Software Aktenwerk.
Dieses Archiv beinhaltet:
1. Eine JSON-Datei (akte_${auftrag.aktenzeichen ?? auftragId}.json) mit allen Stammdaten (Auftrag, Kunde, Gutachten, Rechnungen, Stunden etc.) in strukturierter Form.
2. Alle verknüpften Dokumente, PDFs, und Bilder, die sich im Ordner "dokumente/" befinden.

Import-Erklärung:
Das JSON Format kann verwendet werden, um die Daten wieder in Aktenwerk zu importieren oder in andere Software-Systeme zu übertragen.
Die Felder entsprechen der internen Datenbankstruktur (Drift SQLite).
- "auftrag": Die Kerndaten der Akte.
- "kunde": Die Stammdaten des Auftraggebers.
- "rechnungen", "eingangsrechnungen", "auslagen", "stunden", "angebote", "fotos", "dokumente": Listen mit verknüpften Einträgen.
    ''';
    final readmeBytes = utf8.encode(readme);
    archive.addFile(ArchiveFile('README.txt', readmeBytes.length, readmeBytes));

    // ZIP encoden
    final zipEncoder = ZipEncoder();
    final zipBytes = zipEncoder.encode(archive);
    if (zipBytes == null) throw Exception('Fehler beim Komprimieren');

    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final azSafe = (auftrag.aktenzeichen ?? auftrag.id.toString()).replaceAll('/', '-');
    final filename = 'Akte_${azSafe}_$stamp.zip';

    // Download / Teilen anstoßen
    await Share.shareXFiles(
      [XFile.fromData(Uint8List.fromList(zipBytes), name: filename, mimeType: 'application/zip')],
      subject: 'Export Akte $azSafe',
    );
  }
}

final aktenExportServiceProvider = Provider<AktenExportService>((ref) {
  return AktenExportService(ref.watch(appDatabaseProvider));
});
