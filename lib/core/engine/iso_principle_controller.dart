import 'dart:async';

import '../audio/audio_engine.dart';
import '../models/sensory_state.dart';

/// Drives the Iso-Principle protocol (Match -> Thinning -> Baseline) as a pure
/// function of elapsed milliseconds, and pushes each snapshot into the audio engine.
class IsoPrincipleController {
  IsoPrincipleController(
      {required AudioEngine audio, void Function(IsoSnapshot)? onSnapshot})
      : _audio = audio,
        _onSnapshot = onSnapshot,
        _current = snapshotAt(0);

  static const int thinningStartMs = 180000;
  static const int baselineStartMs = 480000;

  /// Length of the final stretch of Thinning in which the baseline layers
  /// (Brownian bed, heartbeat, protocol dimmer) are faded in.
  static const int baselineRampMs = 60000;

  static const double _matchBpm = 104;
  static const double _thinBpm = 72;
  static const double _baselineBpm = 58;
  static const double _matchLpf = 2000;
  static const double _thinLpf = 900;
  static const double _baselineLpf = 500;
  static const double _sosLpf = 650;
  static const double _baselineDim = 0.40;

  final AudioEngine _audio;
  final void Function(IsoSnapshot)? _onSnapshot;
  IsoSnapshot _current;
  bool _deepCrisis = false;
  Timer? _timer;
  final Stopwatch _clock = Stopwatch();

  /// Deterministic protocol state at [elapsedMs] (negative values are treated as 0).
  static IsoSnapshot snapshotAt(int elapsedMs) {
    final e = elapsedMs < 0 ? 0 : elapsedMs;
    if (e < thinningStartMs) {
      return IsoSnapshot(
        elapsedMs: e,
        phase: IsoPhase.match,
        bpm: _matchBpm,
        lpfHz: _matchLpf,
        shaderSpeed: 1.0,
        dimmerAlpha: 0.0,
        rhythmWeight: 1.0,
        padWeight: 0.0,
        brownNoiseGain: 0.0,
        heartbeatGain: 0.0,
      );
    }
    if (e < baselineStartMs) {
      final t = (e - thinningStartMs) / (baselineStartMs - thinningStartMs);
      final ramp = ((e - (baselineStartMs - baselineRampMs)) / baselineRampMs)
          .clamp(0.0, 1.0)
          .toDouble();
      return IsoSnapshot(
        elapsedMs: e,
        phase: IsoPhase.thinning,
        bpm: _matchBpm + (_thinBpm - _matchBpm) * t,
        lpfHz: _matchLpf + (_thinLpf - _matchLpf) * t,
        shaderSpeed: 1.0 - 0.5 * t,
        dimmerAlpha: _baselineDim * ramp,
        rhythmWeight: 1.0 - t,
        padWeight: t,
        brownNoiseGain: ramp,
        heartbeatGain: ramp,
      );
    }
    return IsoSnapshot(
      elapsedMs: e,
      phase: IsoPhase.baseline,
      bpm: _baselineBpm,
      lpfHz: _baselineLpf,
      shaderSpeed: 0.25,
      dimmerAlpha: _baselineDim,
      rhythmWeight: 0.0,
      padWeight: 1.0,
      brownNoiseGain: 1.0,
      heartbeatGain: 1.0,
    );
  }

  /// Deep-Crisis snapshot: rhythm bypassed, Brownian bed (the engine adds the 110 Hz
  /// drone for that preset), 650 Hz ceiling, slowest visuals.
  static IsoSnapshot _deepCrisisAt(int elapsedMs) {
    return IsoSnapshot(
      elapsedMs: elapsedMs < 0 ? 0 : elapsedMs,
      phase: IsoPhase.baseline,
      bpm: _baselineBpm,
      lpfHz: _sosLpf,
      shaderSpeed: 0.25,
      dimmerAlpha: _baselineDim,
      rhythmWeight: 0.0,
      padWeight: 0.0,
      brownNoiseGain: 1.0,
      heartbeatGain: 0.0,
    );
  }

  IsoSnapshot get current => _current;

  bool get isRunning => _timer != null;

  bool get deepCrisis => _deepCrisis;

  /// Switches between the timed protocol and the Deep-Crisis bypass; re-applies immediately.
  set deepCrisis(bool value) {
    if (_deepCrisis == value) return;
    _deepCrisis = value;
    tick(_current.elapsedMs);
  }

  /// Starts the session clock at 0 and drives [tick] at ~60 Hz.
  void start() {
    if (_timer != null) return;
    _clock
      ..reset()
      ..start();
    tick(0);
    _timer = Timer.periodic(const Duration(microseconds: 16667), (_) {
      tick(_clock.elapsedMilliseconds);
    });
  }

  /// Stops the internal timer; the last snapshot stays available through [current].
  void stop() {
    _timer?.cancel();
    _timer = null;
    _clock.stop();
  }

  /// Computes the snapshot for [elapsedMs], hands it to the audio engine and the listener.
  void tick(int elapsedMs) {
    final snapshot =
        _deepCrisis ? _deepCrisisAt(elapsedMs) : snapshotAt(elapsedMs);
    _current = snapshot;
    _audio.applyIso(snapshot);
    _onSnapshot?.call(snapshot);
  }
}
