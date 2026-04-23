import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/firestore_service.dart';
import 'ki_modelle.dart';

/// Berechnet den USD-Preis eines einzelnen KI-Calls aus Token-Counts.
/// Werte orientieren sich an [KiModellInfo.preisInput] / .preisOutput
/// (USD pro 1.000.000 Tokens).
double berechneKostenUsd({
  required String modellId,
  required int inputTokens,
  required int outputTokens,
}) {
  final info = kiModellInfo(modellId);
  final inK = inputTokens / 1000000.0;
  final outK = outputTokens / 1000000.0;
  return inK * info.preisInput + outK * info.preisOutput;
}

/// Ein einzelner KI-Call (zur Anzeige im Usage-Dashboard).
class KiUsageEintrag {
  const KiUsageEintrag({
    required this.timestampMs,
    required this.feature,
    required this.modellId,
    required this.inputTokens,
    required this.outputTokens,
    required this.kostenUsd,
    this.userEmail,
  });
  final int timestampMs;
  final String feature;
  final String modellId;
  final int inputTokens;
  final int outputTokens;
  final double kostenUsd;
  final String? userEmail;

  int get totalTokens => inputTokens + outputTokens;

  Map<String, dynamic> toMap() => {
        'ts': timestampMs,
        'feature': feature,
        'modell': modellId,
        'in': inputTokens,
        'out': outputTokens,
        'usd': kostenUsd,
        if (userEmail != null) 'email': userEmail,
      };

  static KiUsageEintrag fromMap(Map<String, dynamic> m) => KiUsageEintrag(
        timestampMs: (m['ts'] as num?)?.toInt() ?? 0,
        feature: (m['feature'] as String?) ?? '',
        modellId: (m['modell'] as String?) ?? '',
        inputTokens: (m['in'] as num?)?.toInt() ?? 0,
        outputTokens: (m['out'] as num?)?.toInt() ?? 0,
        kostenUsd: (m['usd'] as num?)?.toDouble() ?? 0,
        userEmail: m['email'] as String?,
      );
}

/// Persistiert KI-Nutzung in Firestore unter
/// `organizations/{orgId}/ki_usage/{autoId}`. Im Offline-Fall geht der
/// Eintrag verloren — das ist akzeptabel, wir nutzen ihn rein zur
/// Kostentransparenz, nicht als Rechnungsgrundlage.
class KiUsageLogger {
  KiUsageLogger(this._fs);
  final FirestoreService _fs;

  Future<void> log({
    required KiAufgabe aufgabe,
    required String modellId,
    required UsageMetadata? usage,
    String? userEmail,
  }) async {
    if (usage == null) return;
    final inputTokens = usage.promptTokenCount ?? 0;
    final outputTokens = usage.candidatesTokenCount ?? 0;
    if (inputTokens == 0 && outputTokens == 0) return;
    final usd = berechneKostenUsd(
      modellId: modellId,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
    );
    final eintrag = KiUsageEintrag(
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      feature: aufgabe.name,
      modellId: modellId,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      kostenUsd: usd,
      userEmail: userEmail,
    );
    final col = _fs.orgCollection('ki_usage');
    if (col == null) return;
    // fire-and-forget — Logging blockiert nie die KI-Interaktion.
    try {
      await col.add(eintrag.toMap());
    } catch (_) {
      // Schlucken: Logging darf den User-Flow nicht stören.
    }
  }
}

final kiUsageLoggerProvider = Provider<KiUsageLogger>((ref) {
  return KiUsageLogger(ref.watch(firestoreServiceProvider));
});

/// Aggregat für den aktuellen Monat (für die Einstellungs-Übersicht).
class KiUsageMonatsAggregat {
  const KiUsageMonatsAggregat({
    required this.jahrMonat,
    required this.gesamtCalls,
    required this.gesamtTokensIn,
    required this.gesamtTokensOut,
    required this.gesamtKostenUsd,
    required this.proModell,
    required this.proFeature,
  });
  final String jahrMonat;
  final int gesamtCalls;
  final int gesamtTokensIn;
  final int gesamtTokensOut;
  final double gesamtKostenUsd;
  final Map<String, double> proModell;
  final Map<String, double> proFeature;
}

/// Liefert die Calls des laufenden Monats (max. 500) als Stream.
final kiUsageAktuellerMonatProvider =
    StreamProvider<List<KiUsageEintrag>>((ref) {
  final fs = ref.watch(firestoreServiceProvider);
  final col = fs.orgCollection('ki_usage');
  if (col == null) return const Stream.empty();
  final jetzt = DateTime.now();
  final monatsStart = DateTime(jetzt.year, jetzt.month, 1).millisecondsSinceEpoch;
  return col
      .where('ts', isGreaterThanOrEqualTo: monatsStart)
      .orderBy('ts', descending: true)
      .limit(500)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => KiUsageEintrag.fromMap(d.data()))
          .toList());
});

/// Rechnet eine Liste von Einträgen in ein Monats-Aggregat um.
KiUsageMonatsAggregat aggregiere(List<KiUsageEintrag> eintraege) {
  final jetzt = DateTime.now();
  final ym = '${jetzt.year}-${jetzt.month.toString().padLeft(2, '0')}';
  var calls = 0;
  var tIn = 0;
  var tOut = 0;
  var usd = 0.0;
  final proModell = <String, double>{};
  final proFeature = <String, double>{};
  for (final e in eintraege) {
    calls++;
    tIn += e.inputTokens;
    tOut += e.outputTokens;
    usd += e.kostenUsd;
    proModell[e.modellId] = (proModell[e.modellId] ?? 0) + e.kostenUsd;
    proFeature[e.feature] = (proFeature[e.feature] ?? 0) + e.kostenUsd;
  }
  return KiUsageMonatsAggregat(
    jahrMonat: ym,
    gesamtCalls: calls,
    gesamtTokensIn: tIn,
    gesamtTokensOut: tOut,
    gesamtKostenUsd: usd,
    proModell: proModell,
    proFeature: proFeature,
  );
}
