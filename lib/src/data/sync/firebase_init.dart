import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../../firebase_options.dart';

/// Initialisiert Firebase für alle Plattformen mit den von
/// `flutterfire configure` erzeugten Optionen.
class FirebaseBootstrap {
  FirebaseBootstrap._();

  static bool _ready = false;
  static Object? _error;

  static bool get isReady => _ready;
  static Object? get error => _error;

  static Future<void> init() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _ready = true;
    } catch (e, st) {
      _ready = false;
      _error = e;
      if (kDebugMode) {
        debugPrint('[FirebaseBootstrap] init fehlgeschlagen: $e');
        debugPrintStack(stackTrace: st, maxFrames: 5);
      }
    }
  }
}
