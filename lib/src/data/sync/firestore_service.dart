import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_service.dart';
import 'firebase_init.dart';

/// Dünne Abstraktion über Firestore mit Benutzer-gebundenem Pfad.
///
/// Jede Entität liegt unter `users/{uid}/{collection}/{id}` – damit sind die
/// Security-Rules einfach und Multi-Device-Sync pro Benutzer möglich.
class FirestoreService {
  FirestoreService(this._auth);
  final AuthService _auth;

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  bool get enabled => FirebaseBootstrap.isReady;
  String? get _uid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? userCollection(String name) {
    final uid = _uid;
    if (!enabled || uid == null) return null;
    return _db.collection('users').doc(uid).collection(name);
  }

  Future<void> upsert(
    String collection,
    String id,
    Map<String, dynamic> data,
  ) async {
    final col = userCollection(collection);
    if (col == null) return;
    await col.doc(id).set(
      {
        ...data,
        '_updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> delete(String collection, String id) async {
    final col = userCollection(collection);
    if (col == null) return;
    await col.doc(id).delete();
  }

  Stream<List<Map<String, dynamic>>> watch(
    String collection, {
    int? limit,
  }) {
    final col = userCollection(collection);
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
  return FirestoreService(ref.watch(authServiceProvider));
});
