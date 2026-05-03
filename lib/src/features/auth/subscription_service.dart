import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/org_service.dart';

/// Lebenszyklus eines Mandanten-Abos.
enum SubscriptionStatus {
  /// Frischer Mandant — 14-Tage-Test läuft.
  trial,

  /// Test abgelaufen, kein Abo abgeschlossen — Schreibsperre.
  trialAbgelaufen,

  /// Aktives bezahltes Abo.
  aktiv,

  /// Manuell vom Super-Admin gekündigt / pausiert.
  gekuendigt,

  /// Master-Mandant des Super-Admins ("Bauelemente-Experte") — keine
  /// Abo-Logik nötig.
  master,
}

extension SubscriptionStatusX on SubscriptionStatus {
  String get label => switch (this) {
        SubscriptionStatus.trial => 'Test',
        SubscriptionStatus.trialAbgelaufen => 'Test abgelaufen',
        SubscriptionStatus.aktiv => 'Aktiv',
        SubscriptionStatus.gekuendigt => 'Gekündigt',
        SubscriptionStatus.master => 'Master',
      };

  /// `true` = der Mandant darf schreiben.
  bool get darfSchreiben =>
      this == SubscriptionStatus.aktiv ||
      this == SubscriptionStatus.trial ||
      this == SubscriptionStatus.master;

  static SubscriptionStatus fromRaw(String? raw) {
    switch (raw) {
      case 'trial':
        return SubscriptionStatus.trial;
      case 'trialAbgelaufen':
      case 'trial_expired':
        return SubscriptionStatus.trialAbgelaufen;
      case 'aktiv':
      case 'active':
        return SubscriptionStatus.aktiv;
      case 'gekuendigt':
      case 'cancelled':
        return SubscriptionStatus.gekuendigt;
      case 'master':
        return SubscriptionStatus.master;
      default:
        return SubscriptionStatus.trial;
    }
  }
}

/// Aggregierter Subscription-Zustand eines Mandanten.
class OrgSubscription {
  final String orgId;
  final SubscriptionStatus status;
  final DateTime? trialStartedAt;
  final DateTime? trialEndsAt;
  final int pricePerUserCents; // 790 = 7,90 €
  final int memberCount;

  const OrgSubscription({
    required this.orgId,
    required this.status,
    required this.trialStartedAt,
    required this.trialEndsAt,
    required this.pricePerUserCents,
    required this.memberCount,
  });

  /// Verbleibende Tage des Tests — negativ wenn schon abgelaufen.
  int? get tageVerbleibend {
    if (trialEndsAt == null) return null;
    final diff = trialEndsAt!.difference(DateTime.now());
    return diff.inDays;
  }

  /// Beschriftung wie "Test (12 Tage)" / "Aktiv (3 User · 23,70 €/Monat)".
  String get anzeigetext {
    switch (status) {
      case SubscriptionStatus.master:
        return 'Master-Mandant';
      case SubscriptionStatus.trial:
        final tage = tageVerbleibend;
        if (tage == null) return 'Test';
        if (tage < 0) return 'Test abgelaufen';
        return 'Test · noch $tage Tag${tage == 1 ? '' : 'e'}';
      case SubscriptionStatus.trialAbgelaufen:
        return 'Test abgelaufen';
      case SubscriptionStatus.aktiv:
        final summe = (memberCount * pricePerUserCents) / 100;
        return 'Aktiv · $memberCount User · ${summe.toStringAsFixed(2)} €/Monat';
      case SubscriptionStatus.gekuendigt:
        return 'Gekündigt';
    }
  }

  /// Berechnet aus den Org-Felder den effektiven Status: aus `trial` wird
  /// automatisch `trialAbgelaufen`, sobald die Frist überschritten ist.
  SubscriptionStatus get effektiverStatus {
    if (status == SubscriptionStatus.trial) {
      final ende = trialEndsAt;
      if (ende != null && ende.isBefore(DateTime.now())) {
        return SubscriptionStatus.trialAbgelaufen;
      }
    }
    return status;
  }

  factory OrgSubscription.fromOrgDoc(
    String orgId,
    Map<String, dynamic> data, {
    required int memberCount,
  }) {
    return OrgSubscription(
      orgId: orgId,
      status: SubscriptionStatusX.fromRaw(
          data['subscriptionStatus']?.toString()),
      trialStartedAt: (data['trialStartedAt'] as Timestamp?)?.toDate(),
      trialEndsAt: (data['trialEndsAt'] as Timestamp?)?.toDate(),
      pricePerUserCents:
          (data['pricePerUserCents'] as num?)?.toInt() ?? 790,
      memberCount: memberCount,
    );
  }
}

/// Stellt sicher, dass ein neu angelegter Mandant einen 14-Tage-Test
/// bekommt. Aufrufen direkt nach `set` des organizations-Doc.
Future<void> initialisiereTrial({
  required String orgId,
  bool isMaster = false,
}) async {
  final db = FirebaseFirestore.instance;
  final ref = db.collection('organizations').doc(orgId);
  final snap = await ref.get();
  if (!snap.exists) return;
  final data = snap.data() ?? {};
  if (data['subscriptionStatus'] != null) return; // bereits initialisiert
  if (isMaster) {
    await ref.update({
      'subscriptionStatus': 'master',
      'pricePerUserCents': 0,
    });
    return;
  }
  final now = DateTime.now();
  final ende = now.add(const Duration(days: 14));
  await ref.update({
    'subscriptionStatus': 'trial',
    'trialStartedAt': Timestamp.fromDate(now),
    'trialEndsAt': Timestamp.fromDate(ende),
    'pricePerUserCents': 790,
  });
}

/// Stream: Subscription-State des aktuell aktiven Mandanten.
final aktuelleOrgSubscriptionProvider =
    StreamProvider<OrgSubscription?>((ref) async* {
  final orgId = ref.watch(currentOrgIdProvider).valueOrNull;
  if (orgId == null) {
    yield null;
    return;
  }
  final db = FirebaseFirestore.instance;
  final orgRef = db.collection('organizations').doc(orgId);
  final memberCol = orgRef.collection('members');
  await for (final orgSnap in orgRef.snapshots()) {
    if (!orgSnap.exists) {
      yield null;
      continue;
    }
    final memSnap = await memberCol.get();
    yield OrgSubscription.fromOrgDoc(orgId, orgSnap.data() ?? {},
        memberCount: memSnap.size);
  }
});
