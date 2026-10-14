/// Web-Implementation. Kapselt `package:web` + `dart:js_interop` so,
/// dass die rufende Stelle nichts davon mitbekommt.
import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

void openInNewWindow(String url,
    {String name = '_blank', String features = ''}) {
  web.window.open(url, name, features);
}

/// Schließt das aktuelle Browser-Fenster — funktioniert nur, wenn das
/// Fenster per Skript (window.open) geöffnet wurde, sonst ignoriert
/// der Browser den Aufruf.
void closeWindow() {
  try {
    web.window.close();
  } catch (_) {
    // Browser blockt den Close-Aufruf, wenn das Fenster nicht per
    // Skript geöffnet wurde — dann passiert einfach nichts.
  }
}

String get appOrigin => web.window.location.origin;

Stream<void> get windowFocusStream =>
    web.EventStreamProviders.focusEvent.forTarget(web.window).map((_) {});

Stream<void> get windowOnlineStream =>
    web.EventStreamProviders.onlineEvent.forTarget(web.window).map((_) {});

Stream<void> get windowOfflineStream =>
    web.EventStreamProviders.offlineEvent.forTarget(web.window).map((_) {});

bool get isBrowserOnline => web.window.navigator.onLine;

String get notificationPermission {
  try {
    return web.Notification.permission.toString();
  } catch (_) {
    return 'unsupported';
  }
}

bool get notificationSupported {
  try {
    web.Notification.permission;
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> requestNotificationPermission() async {
  if (!notificationSupported) return false;
  final completer = Completer<String>();
  web.Notification.requestPermission(((String p) {
    if (!completer.isCompleted) completer.complete(p);
  }).toJS);
  final result = await completer.future
      .timeout(const Duration(seconds: 30), onTimeout: () => 'denied');
  return result == 'granted';
}

void showBrowserNotification(String title,
    {String? body, String? tag, bool requireInteraction = false}) {
  if (!notificationSupported) return;
  if (notificationPermission != 'granted') return;
  try {
    web.Notification(
      title,
      web.NotificationOptions(
        body: body ?? '',
        tag: tag ?? '',
        requireInteraction: requireInteraction,
      ),
    );
  } catch (_) {
    // ignore
  }
}

// ---------------- Viewport & Virtual Keyboard (iOS / iPadOS) ----------------

/// Berechnet den Versatz (Bottom-Inset in CSS-Pixeln), den die virtuelle
/// Software-Tastatur auf mobilen Web-Browsern (insb. Safari auf iOS / iPadOS)
/// erzeugt, indem der VisualViewport mit der Fensterhöhe verglichen wird.
/// Gibt 0.0 zurück, wenn die Differenz vernachlässigbar klein ist (< 60px).
double get visualViewportKeyboardInset {
  try {
    final vv = web.window.visualViewport;
    if (vv == null) return 0.0;
    final winH = web.window.innerHeight;
    final vvH = vv.height;
    final diff = winH - vvH;
    // Tastaturhöhe auf Mobilgeräten typischerweise 150px - 450px.
    // Schwellenwert 60px filtert URL-Leisten-Änderungen in Safari heraus.
    if (diff > 60 && diff < winH * 0.85) {
      return diff.toDouble();
    }
    return 0.0;
  } catch (_) {
    return 0.0;
  }
}

/// Stream für Änderungen des VisualViewports (z. B. Tastatur auf-/zugeklappt
/// auf iPadOS / iOS Safari).
Stream<double> get visualViewportKeyboardStream {
  try {
    final vv = web.window.visualViewport;
    if (vv == null) return const Stream.empty();
    return web.EventStreamProviders.resizeEvent
        .forTarget(vv)
        .map((_) => visualViewportKeyboardInset);
  } catch (_) {
    return const Stream.empty();
  }
}

/// Setzt das Window-Scroll-Offset auf (0, 0) zurück. Verhindert, dass WebKit
/// bei Fokus auf ein Textfeld das gesamte Flutter-Canvas unerwünscht nach oben schiebt.
void resetWindowScroll() {
  try {
    web.window.scrollTo(0.toJS, 0);
  } catch (_) {}
}

/// Prüft, ob der Browser auf einem iOS- oder iPadOS-Gerät läuft.
/// Erkennt auch iPads ab iPadOS 13, die sich als Desktop-Safari (Macintosh)
/// ausgeben, aber Multi-Touch unterstützen.
bool get isIOSorIPad {
  try {
    final ua = web.window.navigator.userAgent;
    if (ua.contains('iPad') || ua.contains('iPhone') || ua.contains('iPod')) {
      return true;
    }
    if (ua.contains('Macintosh') && web.window.navigator.maxTouchPoints > 1) {
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

