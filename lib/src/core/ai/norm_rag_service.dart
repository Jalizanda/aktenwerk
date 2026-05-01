import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/database/app_database.dart';

/// Indexierungsstatus eines Norm-PDFs in der Cloud-Vector-DB.
enum NormIndexStatus { unbekannt, pending, indexing, indexed, failed }

extension NormIndexStatusX on NormIndexStatus {
  String get label => switch (this) {
        NormIndexStatus.unbekannt => 'Nicht indexiert',
        NormIndexStatus.pending => 'In Warteschlange',
        NormIndexStatus.indexing => 'Wird indexiert …',
        NormIndexStatus.indexed => 'Indexiert',
        NormIndexStatus.failed => 'Fehler',
      };

  static NormIndexStatus fromRaw(String? raw) {
    switch (raw) {
      case 'pending':
        return NormIndexStatus.pending;
      case 'indexing':
        return NormIndexStatus.indexing;
      case 'indexed':
        return NormIndexStatus.indexed;
      case 'failed':
        return NormIndexStatus.failed;
      default:
        return NormIndexStatus.unbekannt;
    }
  }
}

/// Eine Quellen-Zitation in einer Chat-Antwort. Verweist auf einen
/// einzelnen Chunk aus `norm_chunks`.
class NormChatQuelle {
  final String chunkId;
  final int? normId;
  final String nummer;
  final String titel;
  final int page;
  final String snippet;

  const NormChatQuelle({
    required this.chunkId,
    required this.normId,
    required this.nummer,
    required this.titel,
    required this.page,
    required this.snippet,
  });

  factory NormChatQuelle.fromMap(Map m) => NormChatQuelle(
        chunkId: m['chunkId']?.toString() ?? '',
        normId: _toIntOrNull(m['normId']),
        nummer: m['nummer']?.toString() ?? '',
        titel: m['titel']?.toString() ?? '',
        page: _toIntOrNull(m['page']) ?? 0,
        snippet: m['snippet']?.toString() ?? '',
      );
}

/// Tolerantes Konvertieren — Cloud-Functions-Antworten kommen je nach
/// Plattform als int, double, num oder String zurück. Wir normieren das.
int? _toIntOrNull(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// Aggregierter Indexierungs-Fortschritt für die gesamte Normen-Bibliothek.
class NormIndexFortschritt {
  final int gesamt;
  final int indexed;
  final int indexing;
  final int pending;
  final int failed;
  final int unbekannt;
  final int chunks;

  const NormIndexFortschritt({
    required this.gesamt,
    required this.indexed,
    required this.indexing,
    required this.pending,
    required this.failed,
    required this.unbekannt,
    required this.chunks,
  });

  /// Anteil 0..1 für den Fortschrittsbalken.
  double get fortschritt =>
      gesamt == 0 ? 0 : (indexed / gesamt).clamp(0.0, 1.0);

  bool get istFertig => gesamt > 0 && indexed == gesamt;
  bool get laeuft => indexing > 0 || pending > 0;
}

/// Antwort der Cloud Function `norm_chat`.
class NormChatAntwort {
  final String antwort;
  final List<NormChatQuelle> quellen;
  final String modell;
  final int dauerMs;

  const NormChatAntwort({
    required this.antwort,
    required this.quellen,
    required this.modell,
    required this.dauerMs,
  });

  factory NormChatAntwort.fromMap(Map m) => NormChatAntwort(
        antwort: m['antwort']?.toString() ?? '',
        quellen: ((m['quellen'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => NormChatQuelle.fromMap(e))
            .toList(),
        modell: m['modell']?.toString() ?? '',
        dauerMs: _toIntOrNull(m['dauerMs']) ?? 0,
      );
}

/// Eintrag in der Chat-Historie für die UI.
class NormChatNachricht {
  final String rolle; // 'user' | 'assistant'
  final String text;
  final List<NormChatQuelle> quellen;
  final DateTime zeit;

  const NormChatNachricht({
    required this.rolle,
    required this.text,
    this.quellen = const [],
    required this.zeit,
  });
}

/// Service rund um die Norm-RAG-Funktionalität: triggert die Indexierung
/// neuer PDFs in der Cloud Function und ruft den Chat-Endpoint auf.
class NormRagService {
  NormRagService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    String? chatEndpoint,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _chatEndpoint = chatEndpoint ?? _defaultChatEndpoint();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final String _chatEndpoint;

  /// Auf Web wird der Hosting-Rewrite (`/api/normChat`) verwendet, sodass
  /// die App und der Function-Endpunkt unter derselben Origin sitzen — keine
  /// CORS-Probleme. Auf nicht-Web-Plattformen wird die Cloud Run Default-URL
  /// genutzt (kann via Konstruktor überschrieben werden).
  static String _defaultChatEndpoint() {
    if (kIsWeb) return '/api/normChat';
    return 'https://europe-west1-aktenwerk-88c35.cloudfunctions.net/normChatHttp';
  }

  /// Markiert ein hochgeladenes Norm-PDF als "zu indexieren". Schreibt das
  /// Steuer-Dokument unter `norm_pdfs/{key}` mit `status='pending'` —
  /// die Cloud Function `index_norm_pdf` triggert daraufhin automatisch.
  Future<void> markiereZurIndexierung(NormenData norm, {String? orgId}) async {
    final url = norm.pdfStorageUrl;
    if (url == null || url.isEmpty) return;
    final key = 'norm_${norm.id}';
    await _firestore.collection('norm_pdfs').doc(key).set({
      'normId': norm.id,
      'nummer': norm.nummer,
      'titel': norm.titel,
      'gewerk': norm.gewerk,
      'storageUrl': url,
      'storagePath': _pfadAusUrl(url),
      'mimeType': norm.pdfMimeType,
      'dateiname': norm.pdfDateiname,
      'orgId': orgId,
      'status': 'pending',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Markiert alle übergebenen Normen mit Storage-PDF zur Indexierung.
  /// `onlyMissing=true` (Default) überspringt Normen, deren `norm_pdfs`-Doc
  /// bereits auf `indexed` oder `indexing` steht — so wird die bestehende
  /// Bibliothek nur einmal initial verarbeitet.
  ///
  /// Schreibt in Batches (max. 400 pro Commit), damit das Anmelden auch
  /// für hunderte Normen in wenigen Sekunden durchläuft (eine einzelne
  /// `set()`-Pro-Norm wäre 1-2 Round-Trips × N und damit zu langsam).
  Future<({int angefordert, int uebersprungen})> markiereAlleZurIndexierung(
    List<NormenData> normen, {
    bool onlyMissing = true,
    String? orgId,
  }) async {
    // 1) Bestehende Status in EINER Query laden statt N Round-Trips.
    final Map<String, String?> bestehendeStatus = {};
    if (onlyMissing) {
      final snap = await _firestore.collection('norm_pdfs').get();
      for (final doc in snap.docs) {
        bestehendeStatus[doc.id] = doc.data()['status']?.toString();
      }
    }

    int angefordert = 0;
    int uebersprungen = 0;
    WriteBatch batch = _firestore.batch();
    int batchCount = 0;

    for (final n in normen) {
      final url = n.pdfStorageUrl;
      if (url == null || url.isEmpty) {
        uebersprungen++;
        continue;
      }
      final key = 'norm_${n.id}';
      if (onlyMissing) {
        final s = bestehendeStatus[key];
        if (s == 'indexed' || s == 'indexing') {
          uebersprungen++;
          continue;
        }
      }
      batch.set(
        _firestore.collection('norm_pdfs').doc(key),
        {
          'normId': n.id,
          'nummer': n.nummer,
          'titel': n.titel,
          'gewerk': n.gewerk,
          'storageUrl': url,
          'storagePath': _pfadAusUrl(url),
          'mimeType': n.pdfMimeType,
          'dateiname': n.pdfDateiname,
          'orgId': orgId,
          'status': 'pending',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      angefordert++;
      batchCount++;
      // Firestore-Batch-Limit: 500 Operationen. Bei 400 committen wir.
      if (batchCount >= 400) {
        await batch.commit();
        batch = _firestore.batch();
        batchCount = 0;
      }
    }
    if (batchCount > 0) {
      await batch.commit();
    }
    return (angefordert: angefordert, uebersprungen: uebersprungen);
  }

  /// Liest den Indexierungs-Status zurück (für Badge im UI).
  Stream<NormIndexStatus> watchStatus(int normId) {
    return _firestore
        .collection('norm_pdfs')
        .doc('norm_$normId')
        .snapshots()
        .map((snap) {
      if (!snap.exists) return NormIndexStatus.unbekannt;
      final raw = snap.data()?['status']?.toString();
      return NormIndexStatusX.fromRaw(raw);
    });
  }

  /// Liefert die Liste aller fehlgeschlagenen Indexierungen mit ihrer
  /// Fehlermeldung (für ein Diagnose-Dialog im UI).
  Future<List<({int? normId, String nummer, String error})>>
      ladeFehlgeschlagene() async {
    final snap = await _firestore
        .collection('norm_pdfs')
        .where('status', isEqualTo: 'failed')
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      final id = data['normId'];
      return (
        normId: id is int ? id : (id is num ? id.toInt() : null),
        nummer: (data['nummer'] ?? '').toString(),
        error: (data['errorMessage'] ?? 'Unbekannter Fehler').toString(),
      );
    }).toList();
  }

  /// Aggregierter Fortschritt für ALLE Norm-IDs mit hinterlegtem PDF.
  /// `gesamt` ist die Anzahl der Normen mit `pdfStorageUrl` aus der Drift-DB,
  /// die Status-Counts kommen aus `norm_pdfs`. Normen ohne Cloud-Doc gelten
  /// als `unbekannt` und bilden mit `failed` den Rest in der Anzeige.
  Stream<NormIndexFortschritt> watchFortschritt(List<int> normIdsMitPdf) {
    final gesamt = normIdsMitPdf.length;
    if (gesamt == 0) {
      return Stream.value(const NormIndexFortschritt(
        gesamt: 0,
        indexed: 0,
        indexing: 0,
        pending: 0,
        failed: 0,
        unbekannt: 0,
        chunks: 0,
      ));
    }
    return _firestore.collection('norm_pdfs').snapshots().map((snap) {
      int indexed = 0, indexing = 0, pending = 0, failed = 0, chunks = 0;
      final dokumentierteIds = <int>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final normId = data['normId'];
        if (normId is! int) continue;
        if (!normIdsMitPdf.contains(normId)) continue;
        dokumentierteIds.add(normId);
        final status = data['status']?.toString();
        switch (status) {
          case 'indexed':
            indexed++;
            final c = data['chunkCount'];
            if (c is int) chunks += c;
            break;
          case 'indexing':
            indexing++;
            break;
          case 'pending':
            pending++;
            break;
          case 'failed':
            failed++;
            break;
        }
      }
      final unbekannt = gesamt - dokumentierteIds.length;
      return NormIndexFortschritt(
        gesamt: gesamt,
        indexed: indexed,
        indexing: indexing,
        pending: pending,
        failed: failed,
        unbekannt: unbekannt,
        chunks: chunks,
      );
    });
  }

  /// Sendet eine Frage an die Cloud Function `norm_chat`.
  ///
  /// [historie] enthält Nachrichten mit `rolle` ('user'|'assistant') und
  /// `text` für mehrstufige Konversationen.
  /// [filterNormIds] beschränkt die Suche auf eine Norm-Auswahl
  /// (z.B. wenn der Nutzer "nur DIN 4108" anklickt).
  Future<NormChatAntwort> frage({
    required String frage,
    List<NormChatNachricht> historie = const [],
    List<int>? filterNormIds,
    String? orgId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Bitte zuerst anmelden.');
    }
    final idToken = await user.getIdToken();
    final body = jsonEncode({
      'frage': frage,
      'historie':
          historie.map((m) => {'rolle': m.rolle, 'text': m.text}).toList(),
      if (filterNormIds != null) 'normIds': filterNormIds,
      if (orgId != null) 'orgId': orgId,
    });
    final response = await http
        .post(
          Uri.parse(_chatEndpoint),
          headers: {
            'Content-Type': 'application/json',
            if (idToken != null) 'Authorization': 'Bearer $idToken',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 90));
    if (response.statusCode != 200) {
      throw Exception(
          'Chat-Aufruf fehlgeschlagen (${response.statusCode}): ${response.body}');
    }
    final raw = jsonDecode(response.body);
    if (raw is! Map) {
      throw Exception('Unerwartete Antwort vom Server.');
    }
    return NormChatAntwort.fromMap(raw);
  }

  /// Extrahiert den Storage-Object-Pfad aus einer Firebase-Download-URL.
  String? _pfadAusUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final regex = RegExp(r'/o/([^?]+)');
      final m = regex.firstMatch(uri.path);
      if (m == null) return null;
      return Uri.decodeComponent(m.group(1)!);
    } catch (_) {
      return null;
    }
  }
}

final normRagServiceProvider = Provider<NormRagService>((ref) {
  return NormRagService();
});

/// Live-Map normId → Indexierungsstatus, für Sortierung und Anzeige in der
/// Normen-Liste. Liest die `norm_pdfs`-Collection als Stream und projiziert
/// auf einen schnellen Lookup-Key.
final normIndexStatusMapProvider =
    StreamProvider<Map<int, NormIndexStatus>>((ref) {
  return FirebaseFirestore.instance
      .collection('norm_pdfs')
      .snapshots()
      .map((snap) {
    final result = <int, NormIndexStatus>{};
    for (final doc in snap.docs) {
      final id = doc.data()['normId'];
      if (id is int) {
        result[id] = NormIndexStatusX.fromRaw(doc.data()['status']?.toString());
      }
    }
    return result;
  });
});
