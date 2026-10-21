import 'audio_engine.dart';
import 'web_audio_engine.dart';

/// Browser: the pure-Dart engine rendered into a Web Audio graph.
AudioEngine createPlatformEngine() => WebAudioEngine();
