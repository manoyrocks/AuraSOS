import 'audio_engine.dart';
import 'engine_factory.dart';

export 'pure_dart_dsp.dart';

/// Chooses the native engine on mobile / desktop and Web Audio in the browser.
class DspBridge {
  DspBridge._();

  static AudioEngine create() => createPlatformEngine();
}
