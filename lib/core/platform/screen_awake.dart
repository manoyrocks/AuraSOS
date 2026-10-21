import 'package:flutter/services.dart';

/// Keeps the display on during a sensory session (native method channel, no plugin).
/// Safe on platforms without the channel (tests, desktop): calls are ignored.
class ScreenAwake {
  ScreenAwake._();

  static const MethodChannel _channel = MethodChannel('aurasync/screen');

  static Future<void> set(bool awake) async {
    try {
      await _channel.invokeMethod<void>('keepAwake', awake);
    } on MissingPluginException {
      // No native side on this platform.
    } on PlatformException {
      // Never surface errors to the child.
    }
  }
}
