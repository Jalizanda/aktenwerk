import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_service.dart';
import 'firebase_init.dart';
import 'org_service.dart';

/// Dünne Abstraktion über Firestore mit **Organisations**-gebundenem Pfad.
///
/// Jede Entität liegt unter `organizations/{orgId}/{collection}/{id}`.
/// Security-Rules stellen sicher, dass nur Mitglieder der Org Zugriff haben.
class FirestoreService {
  FirestoreService(this._auth, this._currentOrgId);
  final AuthService _auth;
  final String? _currentOrgId;

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  bool get enabled =>
      FirebaseBootstrap.isReady && _currentOrgId != null && _auth.currentUser != null;

  String? get currentOrgId => _currentOrgId;

  CollectionReference<Map<String, dynamic>>? orgCollection(String name) {
    final orgId = _currentOrgId;
    if (!enabled || orgId == null) return null;
    return _db.collection('organizations').doc(orgId).collection(name);
  }

  Future<void> upsert(
    String collection,
    String id,
    Map<String, dynamic> data,
  ) async {
    final col = orgCollection(collection);
    if (col == null) return;
    await col.doc(id).set(
      {
        ...data,
        '_updatedAt': FieldValue.serverTimestamp(),
        '_updatedByUid': _auth.currentUser?.uid,
      },
      SetOptions(merge: true),
    );
  }

  Future<void> delete(String collection, String id) async {
    final col = orgCollection(collection);
    if (col == null) return;
    await col.doc(id).delete();
  }

  Stream<List<Map<String, dynamic>>> watch(
    String collection, {
    int? limit,
  }) {
    final col = orgCollection(collection);
    if (col == null) return const Stream.empty();
    var q = col.orderBy('_updatedAt', descending: true);
    if (limit != null) q = q.limit(limit);
    return q.snapshots().map((s) => s.docs
        .map((d) => {
              'id': d.id,
              ...d.data(),
            })
        .toList());
  }
}

final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  final orgId = ref.watch(currentOrgIdProvider).valueOrNull;
  return FirestoreService(ref.watch(authServiceProvider), orgId);
});
