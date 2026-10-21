import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

class PwaStatus {
  const PwaStatus({required this.isWeb, this.offlineReady = false});

  final bool isWeb;

  /// True once the service worker controls the page, i.e. the app is cached for offline use.
  final bool offlineReady;
}

/// `navigator.serviceWorker` does not exist outside secure contexts (plain http on a LAN),
/// so its presence is checked before it is touched.
PwaStatus readPwaStatus() {
  try {
    final bool supported =
        (web.window.navigator as JSObject).has('serviceWorker');
    final bool controlled =
        supported && web.window.navigator.serviceWorker.controller != null;
    return PwaStatus(isWeb: true, offlineReady: controlled);
  } catch (_) {
    return const PwaStatus(isWeb: true);
  }
}

/// Reloads the page so a waiting new version takes over.
void reloadApp() => web.window.location.reload();
