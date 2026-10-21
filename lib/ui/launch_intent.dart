import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A session to start straight away, requested by a home-screen shortcut: `?mode=sos` on the web,
/// the long-press menu on the Android and iOS app icons.
enum LaunchMode { sos, focus, calm, deep }

/// Parses a shortcut's mode value; unknown or missing values mean "just show the home screen".
LaunchMode? launchModeFrom(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'sos':
      return LaunchMode.sos;
    case 'focus':
      return LaunchMode.focus;
    case 'calm':
      return LaunchMode.calm;
    case 'deep':
      return LaunchMode.deep;
  }
  return null;
}

/// Shortcut taps that arrive while the app is already running. The home screen consumes a value
/// (and resets it to null) if it is the screen being shown.
class ShortcutRequests extends ValueNotifier<LaunchMode?> {
  ShortcutRequests() : super(null);
}

/// Bridge to the native app-icon menus (`MainActivity.kt`, `AppDelegate.swift` / `SceneDelegate.swift`).
class LaunchChannel {
  LaunchChannel._();

  static const MethodChannel channel = MethodChannel('aurasync/launch');

  /// Starts listening for taps while the app is open, then asks which shortcut (if any) started
  /// the app. Safe on platforms without the native side (web, desktop, tests): returns null.
  static Future<LaunchMode?> attach(ShortcutRequests requests) async {
    channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'launchMode') {
        final LaunchMode? mode = launchModeFrom(call.arguments as String?);
        if (mode != null) requests.value = mode;
      }
      return null;
    });
    try {
      return launchModeFrom(await channel.invokeMethod<String>('initialMode'));
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
