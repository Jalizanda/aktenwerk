/// Web-Implementation. Kapselt `package:web` + `dart:js_interop` so,
/// dass die rufende Stelle nichts davon mitbekommt.
import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

void openInNewWindow(String url,
    {String name = '_blank', String features = ''}) {
  web.window.open(url, name, features);
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
