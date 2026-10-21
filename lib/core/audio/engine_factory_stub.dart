import 'audio_engine.dart';
import 'dsp_bridge.dart';

/// Fallback for platforms with neither FFI nor a browser: the silent-capable pure-Dart engine.
AudioEngine createPlatformEngine() => PureDartDsp();
