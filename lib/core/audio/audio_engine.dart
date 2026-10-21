import 'dart:typed_data';

import '../models/sensory_state.dart';

/// Contract between UI / controllers and the DSP backend (native FFI or pure Dart).
/// All level changes are internally routed through the 4.0 s logarithmic crossfade.
abstract class AudioEngine {
  static const int sampleRate = 48000;
  static const int crossfadeSamples = 192000;
  static const double ceilingLinear = 0.70794578;
  static const List<double> pentatonicHz = [
    130.81,
    146.83,
    164.81,
    196.00,
    220.00,
    261.63,
    293.66,
    329.63,
    392.00,
    440.00,
  ];

  /// Begin a preset: fades in over 4.0 s.
  void start(SessionPreset preset);

  /// Fade out over 4.0 s, then silence.
  void stop();

  /// Crossfade to another preset over 4.0 s.
  void switchPreset(SessionPreset preset);

  /// Apply the Iso-Principle parameters (BPM, LPF, stem weights). Smoothed internally.
  void applyIso(IsoSnapshot snapshot);

  /// Parent-profile limits. [highCutHz] <= 0 means none. [masterCap] is 0..1 linear.
  void setProfileLimits(
      {double highCutHz = 0, double masterCap = 1.0, bool allowWater = true});

  /// Pentatonic stim pluck. [degree] 0..9 (clamped), [velocity] 0..1 (capped internally).
  void triggerNote(int degree, double velocity);

  /// Deterministically render [frames] stereo frames (interleaved, length frames*2) into [out].
  /// Used by the platform audio callback and by headless tests.
  void render(Float32List out, int frames);

  void dispose();
}
