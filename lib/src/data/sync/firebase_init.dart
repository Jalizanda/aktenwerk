import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../../firebase_options.dart';

/// reCAPTCHA-v3-Websiteschlüssel für Aktenwerk (aktenwerk-web). Der Key
/// ist öffentlich — darf im Client-Code stehen. Der zugehörige geheime
/// Schlüssel liegt in der Firebase App-Check-Konfiguration.
const _recaptchaV3SiteKey = '6LfeJcMsAAAAAFsqivn1QyhZiza6n781khMzcJ6S';

/// Initialisiert Firebase für alle Plattformen mit den von
/// `flutterfire configure` erzeugten Optionen. Aktiviert anschließend
/// App Check (Web: reCAPTCHA v3), damit nur Aufrufe vom echten
/// Aktenwerk-Client Vertex AI, Firestore usw. nutzen können.
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
      return;
    }

    // App Check separat aktivieren. Fehler hier dürfen Firebase NICHT als
    // „nicht bereit" markieren — Auth, Firestore, Mandantenwechsel etc.
    // funktionieren auch ohne App-Check-Token (wenn Enforce aus ist).
    try {
      await FirebaseAppCheck.instance.activate(
        webProvider: ReCaptchaV3Provider(_recaptchaV3SiteKey),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[FirebaseBootstrap] App-Check-Aktivierung '
            'fehlgeschlagen: $e');
        debugPrintStack(stackTrace: st, maxFrames: 5);
      }
    }
  }
}
