import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_init.dart';

/// Kapselt Firebase Auth inkl. Google-Login.
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

  Future<UserCredential> signInWithEmail(String email, String pw) {
    _require();
    return _auth.signInWithEmailAndPassword(email: email, password: pw);
  }

  Future<UserCredential> registerWithEmail(String email, String pw) {
    _require();
    return _auth.createUserWithEmailAndPassword(email: email, password: pw);
  }

  /// Google-Login — verwendet im Web den Firebase-Popup-Flow, auf nativen
  /// Plattformen das `google_sign_in`-Package + FirebaseAuth-Credential.
  Future<UserCredential> signInWithGoogle() async {
    _require();
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..setCustomParameters({'prompt': 'select_account'});
      return _auth.signInWithPopup(provider);
    }
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'sign-in-cancelled',
        message: 'Google-Anmeldung wurde abgebrochen.',
      );
    }
    final auth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: auth.idToken,
      accessToken: auth.accessToken,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<void> sendPasswordReset(String email) {
    _require();
    return _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() async {
    if (!enabled) return;
    try {
      if (!kIsWeb) await GoogleSignIn().signOut();
    } catch (_) {}
    await _auth.signOut();
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
