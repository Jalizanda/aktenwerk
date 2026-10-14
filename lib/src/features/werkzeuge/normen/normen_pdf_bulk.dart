import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
    this.sha256Hash = '',
    this.ist1zu1Dublette = false,
  });
  final String dateiname;
  final Uint8List bytes;

  /// Null = keine Zuordnung oder Ersterfassung möglich.
  final NormenData? zugeordneteNorm;

  /// Menschenlesbare Erklärung, wie die Zuordnung zustande kam.
  /// Beispiele: 'exakter Dateiname', '1:1 Inhaltlich identische Dublette', 'Neue Norm wird angelegt'.
  final String matchGrund;
  final String sha256Hash;
  final bool ist1zu1Dublette;

  bool get hatZuordnung => zugeordneteNorm != null && !ist1zu1Dublette;
  bool get istNeueNorm => zugeordneteNorm != null && zugeordneteNorm!.id == -1 && !ist1zu1Dublette;
  int get groesse => bytes.lengthInBytes;
}

/// Extrahiert Metadaten (Norm-Nummer, Ausgabedatum, Herausgeber) aus einem Dateinamen.
/// Beispiele:
/// "DIN 18065_2020-08-00_DE_3157023.pdf" -> Nummer: "DIN 18065", Ausgabe: "2020-08"
/// "DIN EN 1090-1.pdf" -> Nummer: "DIN EN 1090-1"
NormenData extrahiereMetadatenAusDateiname(String dateiname) {
  final ohneExt = _ohneExtension(dateiname).trim();

  // 1. Ausgabedatum suchen (z. B. 2020-08 oder 2020_08)
  String ausgabe = '';
  final ausgabeMatch = RegExp(r'\b(19\d\d|20\d\d)[\-_](0[1-9]|1[0-2])\b').firstMatch(ohneExt);
  if (ausgabeMatch != null) {
    ausgabe = '${ausgabeMatch.group(1)}-${ausgabeMatch.group(2)}';
  }

  // 2. Norm-Nummer extrahieren (z. B. "DIN 18065" oder "DIN EN ISO 1461" oder "DIN EN 1993-1-8-NA")
  String nummer = ohneExt;
  final nummerMatch = RegExp(r'\b((?:DIN(?:\s+EN)?(?:\s+ISO)?(?:\s+CEN)?|VDI|DVS|DAfStb|EN|ISO)\s+[0-9]+[A-Za-z0-9\-\/.]*)', caseSensitive: false).firstMatch(ohneExt);
  if (nummerMatch != null) {
    nummer = nummerMatch.group(1)!.trim();
  } else {
    // Fallback: Erste Segment vor Unterstrich
    final teile = ohneExt.split('_');
    if (teile.isNotEmpty && teile[0].trim().isNotEmpty) {
      nummer = teile[0].trim();
    }
  }

  // Normalize National Annex notation: -NA -> /NA
  nummer = nummer.replaceAll(RegExp(r'[\-_]NA\b', caseSensitive: false), '/NA');

  // 3. Herausgeber ermitteln
  String herausgeber = 'DIN';
  final numUpper = nummer.toUpperCase();
  if (numUpper.startsWith('DIN EN ISO')) {
    herausgeber = 'DIN / EN / ISO';
  } else if (numUpper.startsWith('DIN EN')) {
    herausgeber = 'DIN / EN';
  } else if (numUpper.startsWith('DIN')) {
    herausgeber = 'DIN Deutsches Institut für Normung e. V.';
  } else if (numUpper.startsWith('VDI')) {
    herausgeber = 'VDI Verein Deutscher Ingenieure e. V.';
  } else if (numUpper.startsWith('DVS')) {
    herausgeber = 'DVS Deutscher Verband für Schweißen';
  } else if (numUpper.startsWith('EN')) {
    herausgeber = 'CEN Europäisches Komitee für Normung';
  } else if (numUpper.startsWith('ISO')) {
    herausgeber = 'ISO International Organization for Standardization';
  }

  return NormenData(
    id: -1,
    nummer: nummer,
    titel: '$nummer (Ersterfassung aus PDF)',
    ausgabe: ausgabe.isNotEmpty ? ausgabe : null,
    kategorie: 'Norm',
    herausgeber: herausgeber,
    aktiv: true,
    favorit: false,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

/// Extrahiert den SHA-256 Hash aus dem extras-JSON-Feld einer Norm.
String? getSha256AusNorm(NormenData n) {
  final raw = n.extras;
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final m = jsonDecode(raw);
    if (m is Map && m['sha256'] is String) {
      return (m['sha256'] as String).trim();
    }
  } catch (_) {}
  return null;
}

/// Matcht eine Liste von Datei-Namen gegen alle Katalog-Normen.
/// Match-Reihenfolge pro Datei:
/// 0. 1zu1 Inhaltlicher SHA-256-Hash-Vergleich (verhindert doppelte Dokumente in DB & Auswahl)
/// 1. Exakter Match gegen `extras.erwarteterDateiname` (kommt aus JSON-Import)
/// 2. Exakter Match gegen Norm-Nummer (case-insensitive, `.pdf` abgeschnitten)
/// 3. Norm-Nummer (normalisiert) im Dateinamen enthalten — längste Nummer
///    zuerst, damit „DIN 18531-5" gewinnt gegen das kürzere „DIN 18531".
/// 4. Fallback: Neue Norm automatisch aus PDF-Dateinamen anlegen!
List<PdfMatchResult> matchePdfs({
  required Map<String, Uint8List> dateien,
  required List<NormenData> normen,
}) {
  // Precompute SHA-256 Hashes aus bestehenden DB-Einträgen.
  final sha256ToNorm = <String, NormenData>{};
  for (final n in normen) {
    final h = getSha256AusNorm(n);
    if (h != null && h.isNotEmpty) {
      sha256ToNorm[h] = n;
    }
  }

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

  final batchHashes = <String, String>{};
  final results = <PdfMatchResult>[];

  for (final e in dateien.entries) {
    final dateiname = e.key;
    final bytes = e.value;
    final hash = sha256.convert(bytes).toString();

    // 0. SHA-256 1zu1 Dubletten-Prüfung gegen bestehende DB-Katalogeinträge
    final inDbMatch = sha256ToNorm[hash];
    if (inDbMatch != null) {
      results.add(PdfMatchResult(
        dateiname: dateiname,
        bytes: bytes,
        zugeordneteNorm: inDbMatch,
        matchGrund: '1:1 Inhaltlich identische Dublette (bereits in DB)',
        sha256Hash: hash,
        ist1zu1Dublette: true,
      ));
      continue;
    }

    // 0b. SHA-256 1zu1 Dubletten-Prüfung innerhalb der aktuellen Auswahl
    if (batchHashes.containsKey(hash)) {
      results.add(PdfMatchResult(
        dateiname: dateiname,
        bytes: bytes,
        zugeordneteNorm: null,
        matchGrund: '1:1 Inhaltlich identische Dublette (Doppelung in Auswahl mit ${batchHashes[hash]})',
        sha256Hash: hash,
        ist1zu1Dublette: true,
      ));
      continue;
    }
    batchHashes[hash] = dateiname;

    // 1. Exakter Match auf erwarteter Dateiname.
    final exaktErwartet = byErwarteterDateiname[dateiname.toLowerCase()];
    if (exaktErwartet != null) {
      results.add(PdfMatchResult(
        dateiname: dateiname,
        bytes: bytes,
        zugeordneteNorm: exaktErwartet,
        matchGrund: 'exakter Dateiname-Match',
        sha256Hash: hash,
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
        sha256Hash: hash,
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
        sha256Hash: hash,
      ));
      continue;
    }

    // 4. Automatische Ersterstellung für unzugeordnete PDFs!
    final neuErfasst = extrahiereMetadatenAusDateiname(dateiname);
    results.add(PdfMatchResult(
      dateiname: dateiname,
      bytes: bytes,
      zugeordneteNorm: neuErfasst,
      matchGrund: 'Neue Norm wird angelegt',
      sha256Hash: hash,
    ));
  }
  return results;
}

/// Lädt alle zugeordneten PDFs nach Firebase Storage und setzt die
/// PDF-Felder der jeweiligen Norm.
class NormenPdfUploadReport {
  const NormenPdfUploadReport({
    required this.erfolgreich,
    required this.fehler,
    required this.uebersprungen,
    this.fehlerListe = const [],
  });
  final int erfolgreich;
  final int fehler;
  final int uebersprungen;
  final List<String> fehlerListe;
}

Future<NormenPdfUploadReport> ladePdfsHoch({
  required WidgetRef ref,
  required List<PdfMatchResult> kandidaten,
  required bool ueberschreibeVorhandene,
  void Function(int aktuell, int gesamt, String dateiname)? onFortschritt,
}) async {
  final storage = ref.read(storageServiceProvider);
  final db = ref.read(appDatabaseProvider);

  // Dubletten gar nicht erst hochladen
  final zuLaden = kandidaten.where((k) => k.hatZuordnung && !k.ist1zu1Dublette).toList();
  var ok = 0;
  var fehler = 0;
  var uebersprungen = kandidaten.where((k) => k.ist1zu1Dublette).length;
  final fehlerListe = <String>[];

  for (var i = 0; i < zuLaden.length; i++) {
    final k = zuLaden[i];
    onFortschritt?.call(i + 1, zuLaden.length, k.dateiname);
    try {
      NormenData n = k.zugeordneteNorm!;

      // Extras-JSON für SHA-256 vorbereiten
      final Map<String, dynamic> extrasMap = {};
      if (n.extras != null && n.extras!.isNotEmpty) {
        try {
          extrasMap.addAll(jsonDecode(n.extras!) as Map<String, dynamic>);
        } catch (_) {}
      }
      if (k.sha256Hash.isNotEmpty) {
        extrasMap['sha256'] = k.sha256Hash;
      }
      final extrasJson = jsonEncode(extrasMap);

      // 1. Wenn es sich um eine neue Norm handelt (id == -1): Zuerst in DB anlegen!
      if (k.istNeueNorm) {
        final neuId = await db.into(db.normen).insert(
              NormenCompanion.insert(
                nummer: n.nummer,
                titel: Value(n.titel),
                ausgabe: Value(n.ausgabe),
                kategorie: Value(n.kategorie),
                herausgeber: Value(n.herausgeber),
                extras: Value(extrasJson),
                aktiv: const Value(true),
                favorit: const Value(false),
              ),
            );
        final angelegt = await (db.select(db.normen)..where((t) => t.id.equals(neuId))).getSingleOrNull();
        if (angelegt == null) {
          fehler++;
          fehlerListe.add('${k.dateiname}: Datenbankeintrag konnte nicht angelegt werden.');
          continue;
        }
        n = angelegt;
      } else if (!ueberschreibeVorhandene &&
          n.pdfStorageUrl != null &&
          n.pdfStorageUrl!.isNotEmpty) {
        uebersprungen++;
        continue;
      }

      // 2. PDF in Firebase Storage hochladen
      final ts = DateTime.now().millisecondsSinceEpoch;
      final cleanNummer = n.nummer.replaceAll(RegExp(r'[^A-Za-z0-9.\-]'), '_');
      final storagePfad = 'normen/${cleanNummer}_$ts.pdf';
      final url = await storage.uploadBytes(
        storagePfad,
        bytes: k.bytes,
        contentType: 'application/pdf',
      );

      if (url != null) {
        await (db.update(db.normen)..where((t) => t.id.equals(n.id))).write(
          NormenCompanion(
            pdfStorageUrl: Value(url),
            pdfDateiname: Value(k.dateiname),
            pdfMimeType: const Value('application/pdf'),
            pdfGroesse: Value(k.bytes.lengthInBytes),
            extras: Value(extrasJson),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        fehler++;
        fehlerListe.add('${k.dateiname}: Firebase Storage gab eine leere Download-URL zurück.');
        continue;
      }

      // 3. RAG-Indexierung im Cloud-Backend anstoßen (best-effort)
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
    } catch (e) {
      fehler++;
      fehlerListe.add('${k.dateiname}: $e');
    }
  }

  return NormenPdfUploadReport(
    erfolgreich: ok,
    fehler: fehler,
    uebersprungen: uebersprungen,
    fehlerListe: fehlerListe,
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
  final withNa = s.replaceAll(RegExp(r'[\-_]na\b', caseSensitive: false), '/na');
  return withNa.toLowerCase().replaceAll(RegExp(r'[\s_.]+'), '');
}
