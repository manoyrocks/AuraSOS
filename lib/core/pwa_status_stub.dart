/// Native builds have no service worker; the About section hides the offline row.
class PwaStatus {
  const PwaStatus({required this.isWeb, this.offlineReady = false});

  final bool isWeb;

  /// True once the service worker controls the page, i.e. the app is cached for offline use.
  final bool offlineReady;
}

PwaStatus readPwaStatus() => const PwaStatus(isWeb: false);

void reloadApp() {}
