import '../core/models/sensory_state.dart';

/// Short, child-readable names for the modes (the clinical names live in the report exporter).
String modeLabel(SessionPreset preset) {
  switch (preset) {
    case SessionPreset.isoDownRegulator:
      return 'Calm down';
    case SessionPreset.deepCrisisAnchor:
      return 'Deep calm';
    case SessionPreset.focusClassroom:
      return 'Focus';
    case SessionPreset.calmStim:
      return 'Play & calm';
  }
}

/// Where the calm-down is in its three stages, in plain words.
String phaseHint(IsoPhase phase) {
  switch (phase) {
    case IsoPhase.match:
      return 'Matching';
    case IsoPhase.thinning:
      return 'Easing';
    case IsoPhase.baseline:
      return 'Settled';
  }
}
