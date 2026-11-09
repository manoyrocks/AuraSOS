import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'mode_icons.dart';

/// The app's loading indicator: the heart and ripples breathing on the app's own rhythm
/// (about 4 s in, 6 s out), instead of a spinning wheel. Static when the device asks for
/// reduced motion. Use it wherever something is loading for more than an instant.
class AuraLoader extends StatefulWidget {
  const AuraLoader({super.key, this.size = 96, this.semanticLabel = 'Loading'});

  final double size;
  final String semanticLabel;

  @override
  State<AuraLoader> createState() => _AuraLoaderState();
}

/// The loader's breathing curve, exposed so tests can pin its shape.
@visibleForTesting
class AuraLoaderProbe {
  AuraLoaderProbe._();

  static double breath(double t) => _AuraLoaderState.breath(t);
}

class _AuraLoaderState extends State<AuraLoader>
    with SingleTickerProviderStateMixin {
  static const Duration _cycle = Duration(seconds: 10);

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _cycle);
  bool _animate = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate = !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (_animate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 0 at rest, 1 fully breathed in: eased over 4 s in, 6 s out.
  static double breath(double t) {
    final double seconds = t * 10;
    if (seconds < 4) return 0.5 - 0.5 * math.cos(math.pi * seconds / 4);
    return 0.5 + 0.5 * math.cos(math.pi * (seconds - 4) / 6);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      liveRegion: true,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? _) {
              final double e = _animate ? breath(_controller.value) : 0.35;
              return Transform.scale(
                scale: 0.88 + 0.12 * e,
                child: Opacity(
                  opacity: 0.65 + 0.35 * e,
                  child: ModeIcon(kind: ModeIconKind.sos, size: widget.size),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
