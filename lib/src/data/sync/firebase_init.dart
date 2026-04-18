import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Initialisiert Firebase für alle Plattformen.
///
/// Sobald `flutterfire configure` gelaufen ist, existiert
/// `lib/firebase_options.dart` und enthält die plattform­spezifische
/// Konfiguration. Solange die Datei fehlt oder der Aufruf scheitert,
/// läuft die App trotzdem weiter – Cloud-Features werden dann einfach
/// nicht benutzt.
class FirebaseBootstrap {
  FirebaseBootstrap._();

  static bool _ready = false;
  static Object? _error;

  static bool get isReady => _ready;
  static Object? get error => _error;

  static Future<void> init() async {
    if (_ready) return;
    try {
      // Dynamischer Import via deferred library ist in Dart nicht nötig –
      // wir versuchen einfach, die Default-App zu initialisieren.
      // `DefaultFirebaseOptions.currentPlatform` kann hier noch nicht
      // hart referenziert werden, solange die Datei fehlen darf, daher
      // greifen wir auf `Firebase.initializeApp` ohne Options zurück
      // – das funktioniert auf iOS/Android, wenn die native Plist/
      // google-services.json vorhanden sind, und schlägt andernfalls
      // kontrolliert fehl.
      await Firebase.initializeApp();
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
