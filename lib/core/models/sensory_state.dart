// Immutable shared models for AuraSOS. Contract file — do not change signatures.

enum IsoPhase { match, thinning, baseline }

enum SessionPreset {
  isoDownRegulator,
  deepCrisisAnchor,
  focusClassroom,
  calmStim,
}

enum ShaderKind {
  tunnel,
  bubbles,
  lanterns,
  breathingOrb,
  crystals,
  starfield,
  aurora,
  mandala,
}

enum EfficacyRating { effective, neutral, escalated }

/// Everything the audio, shader and dimmer layers need at one instant.
class IsoSnapshot {
  const IsoSnapshot({
    required this.elapsedMs,
    required this.phase,
    required this.bpm,
    required this.lpfHz,
    required this.shaderSpeed,
    required this.dimmerAlpha,
    required this.rhythmWeight,
    required this.padWeight,
    required this.brownNoiseGain,
    required this.heartbeatGain,
  });

  final int elapsedMs;
  final IsoPhase phase;
  final double bpm;
  final double lpfHz;

  /// Multiplier applied to shader `uTime` advance (1.0, 0.5, 0.25).
  final double shaderSpeed;

  /// Black overlay alpha 0..1 contributed by the protocol (0.40 in phase 3).
  final double dimmerAlpha;

  /// Stem mix weights, each 0..1.
  final double rhythmWeight;
  final double padWeight;
  final double brownNoiseGain;
  final double heartbeatGain;
}
