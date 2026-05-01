import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/norm_rag_service.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../data/sync/storage_service.dart';

/// Ein hochzuladender PDF-Kandidat mit Zuordnungs-Ergebnis.
class PdfMatchResult {
  const PdfMatchResult({
    required this.dateiname,
    required this.bytes,
    required this.zugeordneteNorm,
    required this.matchGrund,
  });
  final String dateiname;
  final Uint8List bytes;

  /// Null = keine Zuordnung möglich.
  final NormenData? zugeordneteNorm;

  /// Menschenlesbare Erklärung, wie die Zuordnung zustande kam.
  /// Beispiele: 'exakter Dateiname', 'Norm-Nummer enthalten', 'keine Zuordnung'.
  final String matchGrund;

  bool get hatZuordnung => zugeordneteNorm != null;
  int get groesse => bytes.lengthInBytes;
}

/// Matcht eine Liste von Datei-Namen gegen alle Katalog-Normen.
/// Match-Reihenfolge pro Datei:
/// 1. Exakter Match gegen `extras.erwarteterDateiname` (kommt aus JSON-Import)
/// 2. Exakter Match gegen Norm-Nummer (case-insensitive, `.pdf` abgeschnitten)
/// 3. Norm-Nummer (normalisiert) im Dateinamen enthalten — längste Nummer
///    zuerst, damit „DIN 18531-5" gewinnt gegen das kürzere „DIN 18531".
List<PdfMatchResult> matchePdfs({
  required Map<String, Uint8List> dateien,
  required List<NormenData> normen,
}) {
  // Precompute erwartete Dateinamen aus extras.
  final byErwarteterDateiname = <String, NormenData>{};
  for (final n in normen) {
    final erwartet = _erwarteterDateiname(n);
    if (erwartet != null && erwartet.isNotEmpty) {
      byErwarteterDateiname[erwartet.toLowerCase()] = n;
    }
  }

  // Nach Länge absteigend sortieren für Substring-Match.
  final normenNachLaengeLang = [...normen]
    ..sort((a, b) => b.nummer.length.compareTo(a.nummer.length));

  final results = <PdfMatchResult>[];
  for (final e in dateien.entries) {
    final dateiname = e.key;
    final bytes = e.value;

    // 1. Exakter Match auf erwarteter Dateiname.
    final exaktErwartet = byErwarteterDateiname[dateiname.toLowerCase()];
    if (exaktErwartet != null) {
      results.add(PdfMatchResult(
        dateiname: dateiname,
        bytes: bytes,
        zugeordneteNorm: exaktErwartet,
        matchGrund: 'exakter Dateiname-Match',
      ));
      continue;
    }

    // 2. Exakter Match gegen Norm-Nummer (ohne .pdf).
    final ohneExt = _ohneExtension(dateiname);
    final ohneExtLow = ohneExt.toLowerCase().trim();
    final exakteNummer = normen.firstWhere(
      (n) => n.nummer.trim().toLowerCase() == ohneExtLow,
      orElse: () => _leer,
    );
    if (exakteNummer != _leer) {
      results.add(PdfMatchResult(
        dateiname: dateiname,
        bytes: bytes,
        zugeordneteNorm: exakteNummer,
        matchGrund: 'Norm-Nummer exakt',
      ));
      continue;
    }

    // 3. Substring-Match — längste Nummer zuerst.
    final baseNorm = _normalisiere(ohneExt);
    NormenData? substringMatch;
    for (final n in normenNachLaengeLang) {
      final normNummer = _normalisiere(n.nummer);
      if (normNummer.isEmpty) continue;
      if (baseNorm.contains(normNummer)) {
        substringMatch = n;
        break;
      }
    }
    if (substringMatch != null) {
      results.add(PdfMatchResult(
        dateiname: dateiname,
        bytes: bytes,
        zugeordneteNorm: substringMatch,
        matchGrund: 'Norm-Nummer enthalten',
      ));
      continue;
    }

    results.add(PdfMatchResult(
      dateiname: dateiname,
      bytes: bytes,
      zugeordneteNorm: null,
      matchGrund: 'keine Zuordnung',
    ));
  }
  return results;
}

/// Lädt alle zugeordneten PDFs nach Firebase Storage und setzt die
/// PDF-Felder der jeweiligen Norm.
///
/// [onFortschritt] wird nach jeder bearbeiteten Datei aufgerufen
/// (aktuellerIndex = 1..n, gesamt = n, letzteDatei).
class NormenPdfUploadReport {
  const NormenPdfUploadReport({
    required this.erfolgreich,
    required this.fehler,
    required this.uebersprungen,
  });
  final int erfolgreich;
  final int fehler;
  final int uebersprungen;
}

Future<NormenPdfUploadReport> ladePdfsHoch({
  required WidgetRef ref,
  required List<PdfMatchResult> kandidaten,
  required bool ueberschreibeVorhandene,
  void Function(int aktuell, int gesamt, String dateiname)? onFortschritt,
}) async {
  final storage = ref.read(storageServiceProvider);
  final db = ref.read(appDatabaseProvider);

  final zuLaden = kandidaten.where((k) => k.hatZuordnung).toList();
  var ok = 0;
  var fehler = 0;
  var uebersprungen = 0;

  for (var i = 0; i < zuLaden.length; i++) {
    final k = zuLaden[i];
    onFortschritt?.call(i + 1, zuLaden.length, k.dateiname);
    try {
      final n = k.zugeordneteNorm!;
      if (!ueberschreibeVorhandene &&
          n.pdfStorageUrl != null &&
          n.pdfStorageUrl!.isNotEmpty) {
        uebersprungen++;
        continue;
      }

      final ts = DateTime.now().millisecondsSinceEpoch;
      final cleanNummer = n.nummer.replaceAll(RegExp(r'[^A-Za-z0-9.\-]'), '_');
      final storagePfad = 'normen/${cleanNummer}_$ts.pdf';
      final url = await storage.uploadBytes(
        storagePfad,
        bytes: k.bytes,
        contentType: 'application/pdf',
      );
      if (url == null) {
        fehler++;
        continue;
      }

      await (db.update(db.normen)..where((t) => t.id.equals(n.id))).write(
        NormenCompanion(
          pdfStorageUrl: Value(url),
          pdfDateiname: Value(k.dateiname),
          pdfMimeType: const Value('application/pdf'),
          pdfGroesse: Value(k.bytes.lengthInBytes),
          updatedAt: Value(DateTime.now()),
        ),
      );
      // RAG-Indexierung im Cloud-Backend anstoßen (best-effort).
      try {
        final aktualisiert = await (db.select(db.normen)
              ..where((t) => t.id.equals(n.id)))
            .getSingleOrNull();
        if (aktualisiert != null) {
          await ref
              .read(normRagServiceProvider)
              .markiereZurIndexierung(aktualisiert);
        }
      } catch (_) {/* Indexierung ist optional */}
      ok++;
    } catch (_) {
      fehler++;
    }
  }

  return NormenPdfUploadReport(
    erfolgreich: ok,
    fehler: fehler,
    uebersprungen: uebersprungen,
  );
}

// ------------------------------------------------------------------
// Hilfsfunktionen
// ------------------------------------------------------------------

final NormenData _leer = NormenData(
  id: -1,
  nummer: '',
  aktiv: false,
  favorit: false,
  createdAt: DateTime(1970),
  updatedAt: DateTime(1970),
);

String? _erwarteterDateiname(NormenData n) {
  final raw = n.extras;
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final m = jsonDecode(raw);
    if (m is Map && m['erwarteterDateiname'] is String) {
      return (m['erwarteterDateiname'] as String).trim();
    }
  } catch (_) {}
  return null;
}

String _ohneExtension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return name;
  return name.substring(0, dot);
}

/// Nimmt Leerzeichen, Unterstriche und Punkte raus — Dashes bleiben,
/// weil sie in Norm-Nummern wie „DIN 18531-5" bedeutungstragend sind.
String _normalisiere(String s) {
  return s.toLowerCase().replaceAll(RegExp(r'[\s_.]+'), '');
}
