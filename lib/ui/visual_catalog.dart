import '../core/models/sensory_state.dart';
import '../data/models.dart';
import 'screens/session_screen.dart';

/// What a caregiver sees when choosing the child's animation.
class VisualOption {
  const VisualOption(this.mode, this.title, this.description);

  final VisualMode mode;
  final String title;
  final String description;

  /// Shader behind this option; null for "automatic" (depends on the mode) and for the black screen.
  ShaderKind? get shader => mode == VisualMode.auto
      ? null
      : SessionScreen.visualFor(SessionPreset.calmStim, mode);
}

const List<VisualOption> kVisualOptions = <VisualOption>[
  VisualOption(
      VisualMode.auto, 'Automatic', 'The best animation for each mode'),
  VisualOption(VisualMode.crystals, 'Crystal polygons',
      '3D faceted shapes turning slowly in soft pastels'),
  VisualOption(VisualMode.mandala, 'Polygon mandala',
      'Rings of polygons turning in opposite directions'),
  VisualOption(VisualMode.starfield, 'Starfield',
      'Soft stars drifting gently toward you'),
  VisualOption(
      VisualMode.aurora, 'Aurora', 'Layered ribbons of light over still water'),
  VisualOption(VisualMode.tunnel, 'Light tunnel',
      'A glowing tunnel moving slowly forward'),
  VisualOption(VisualMode.bubbles, 'Rising bubbles',
      'Translucent bubbles floating upward'),
  VisualOption(VisualMode.lanterns, 'Lanterns',
      'Warm lanterns on a pure black background'),
  VisualOption(VisualMode.breathingOrb, 'Breathing orb',
      'A glowing orb that swells and softens with the breath'),
  VisualOption(
      VisualMode.blackScreen, 'Black screen', 'Sound only, nothing lit'),
];

VisualOption visualOptionFor(VisualMode mode) =>
    kVisualOptions.firstWhere((VisualOption o) => o.mode == mode);
