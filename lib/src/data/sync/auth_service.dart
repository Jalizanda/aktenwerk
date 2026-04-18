import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_init.dart';

/// Kapselt Firebase Auth.
///
/// Solange Firebase nicht initialisiert wurde, liefern die Methoden
/// entsprechende Fehler – die App selbst bleibt funktionsfähig.
class AuthService {
  FirebaseAuth get _auth => FirebaseAuth.instance;

  bool get enabled => FirebaseBootstrap.isReady;

  User? get currentUser => enabled ? _auth.currentUser : null;

  Stream<User?> authStateChanges() {
    if (!enabled) return const Stream.empty();
    return _auth.authStateChanges();
  }

  Future<UserCredential> signInAnonymously() {
    _require();
    return _auth.signInAnonymously();
  }

  Future<UserCredential> signInWithEmail(String email, String pw) {
    _require();
    return _auth.signInWithEmailAndPassword(email: email, password: pw);
  }

  Future<UserCredential> registerWithEmail(String email, String pw) {
    _require();
    return _auth.createUserWithEmailAndPassword(email: email, password: pw);
  }

  Future<void> sendPasswordReset(String email) {
    _require();
    return _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() {
    if (!enabled) return Future.value();
    return _auth.signOut();
  }

  void _require() {
    if (!enabled) {
      throw StateError(
          'Firebase ist nicht initialisiert (firebase_options.dart fehlt).');
    }
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});
