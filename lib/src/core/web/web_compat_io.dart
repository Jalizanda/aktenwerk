/// IO-Stub (iOS, Android, macOS, Linux, Windows). Alle Methoden sind
/// No-Ops oder geben „nicht unterstützt" zurück.

/// Öffnet [url] in einem neuen Browser-Fenster (Web-only).
/// Auf nativen Plattformen ein No-Op — Aufrufer sollte vorher
/// `kIsWeb` prüfen oder einen Fallback anbieten.
void openInNewWindow(String url,
    {String name = '_blank', String features = ''}) {
  // Nicht unterstützt auf nativen Plattformen.
}

/// Aktuelle Origin der App (z. B. `https://aktenwerk-app.web.app`).
/// Auf nativen Plattformen leer.
String get appOrigin => '';

/// Pingt einen Stream, der ausgelöst wird, wenn der Browser-Tab den
/// Fokus erhält. Auf nativen Plattformen leerer Stream.
Stream<void> get windowFocusStream => const Stream.empty();

/// Stream für Browser-`online`-Events. Auf nativen Plattformen leer.
Stream<void> get windowOnlineStream => const Stream.empty();

/// Stream für Browser-`offline`-Events. Auf nativen Plattformen leer.
Stream<void> get windowOfflineStream => const Stream.empty();

/// Liefert `true` wenn der Browser online ist. Auf nativen Plattformen
/// `true` (Annahme: das OS regelt Connectivity selbst).
bool get isBrowserOnline => true;

// ---------------- Notifications (Web-only) ----------------

/// Aktueller Status der Browser-Notification-Permission.
/// Werte: 'granted' | 'denied' | 'default' | 'unsupported'.
String get notificationPermission => 'unsupported';

/// `true`, wenn die Browser-Notification-API nutzbar ist.
bool get notificationSupported => false;

/// Fragt die Browser-Notification-Permission ab.
Future<bool> requestNotificationPermission() async => false;

/// Zeigt eine Browser-Notification an.
void showBrowserNotification(String title,
    {String? body, String? tag, bool requireInteraction = false}) {
  // No-op
}
