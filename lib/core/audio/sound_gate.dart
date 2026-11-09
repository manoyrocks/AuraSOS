import 'package:flutter/foundation.dart';

/// Optional capability of an [AudioEngine] whose output the platform can hold back until the user
/// touches the screen (browser autoplay rules, or a suspended audio session after a call).
abstract class SoundGate {
  /// True while a session wants sound but the platform has not let it play yet.
  ValueListenable<bool> get soundBlocked;
}
