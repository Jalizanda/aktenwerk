/// Plattform-Brücke für Browser-spezifische APIs (window.open, focus
/// events, Notifications). Auf iOS/Android/macOS landet alles in
/// einem No-Op-Stub.
///
/// Standard-Pattern: das Interface lebt hier (in der Hauptdatei),
/// während der eigentliche Code in `web_compat_web.dart` (mit
/// `package:web`) oder `web_compat_io.dart` (Stub) liegt — der
/// `export`-Switch unten wählt die richtige Variante.
export 'web_compat_io.dart' if (dart.library.html) 'web_compat_web.dart';
