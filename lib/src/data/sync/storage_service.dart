import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_service.dart';
import 'firebase_init.dart';
import 'org_service.dart';

/// Service für Firebase Storage — Ablage unter `organizations/{orgId}/...`.
/// Nur Mitglieder der aktuellen Organisation haben Zugriff.
class StorageService {
  StorageService(this._auth, this._currentOrgId);
  final AuthService _auth;
  final String? _currentOrgId;

  FirebaseStorage get _storage => FirebaseStorage.instance;
  bool get enabled =>
      FirebaseBootstrap.isReady &&
      _currentOrgId != null &&
      _auth.currentUser != null;

  Reference? _orgRef(String path) {
    final orgId = _currentOrgId;
    if (!enabled || orgId == null) return null;
    return _storage
        .ref()
        .child('organizations')
        .child(orgId)
        .child(path);
  }

  Future<String?> uploadBytes(
    String path, {
    required Uint8List bytes,
    String? contentType,
  }) async {
    final ref = _orgRef(path);
    if (ref == null) return null;
    await ref.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    return ref.getDownloadURL();
  }

  Future<String?> uploadNamed(
    String prefix, {
    required String filename,
    required Uint8List bytes,
    String? contentType,
  }) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '$prefix/${ts}_$filename';
    return uploadBytes(path, bytes: bytes, contentType: contentType);
  }

  Future<Uint8List?> downloadBytes(String path) async {
    final ref = _orgRef(path);
    if (ref == null) return null;
    return ref.getData();
  }

  Future<void> delete(String path) async {
    final ref = _orgRef(path);
    if (ref == null) return;
    await ref.delete();
  }

  Future<List<Reference>> list(String prefix) async {
    final ref = _orgRef(prefix);
    if (ref == null) return const [];
    final result = await ref.listAll();
    return result.items;
  }
}

final storageServiceProvider = Provider<StorageService>((ref) {
  final orgId = ref.watch(currentOrgIdProvider).valueOrNull;
  return StorageService(ref.watch(authServiceProvider), orgId);
});
