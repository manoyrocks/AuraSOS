import 'audio_engine.dart';
import 'dsp_bridge.dart';
import 'native_dsp.dart';

/// Native C++ engine with platform speaker output when the library loads, else pure Dart.
AudioEngine createPlatformEngine() {
  final NativeDsp? native = NativeDsp.tryLoad();
  if (native != null) {
    return native;
  }
  return PureDartDsp();
}
