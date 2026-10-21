import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A rainbow arc that slowly vanishes as time runs out. Wordless: the child reads
/// "how much is left" from the arc length alone.
class VisualTransitionTimer extends StatefulWidget {
  const VisualTransitionTimer({
    super.key,
    required this.duration,
    required this.onFinished,
    this.onResolutionCadence,
    this.resolutionLead = const Duration(seconds: 30),
    this.diameter = 220,
  });

  final Duration duration;
  final VoidCallback onFinished;

  /// Fired once, [resolutionLead] before the end (immediately if the timer is shorter),
  /// so audio can resolve harmonically.
  final VoidCallback? onResolutionCadence;
  final Duration resolutionLead;
  final double diameter;

  @override
  State<VisualTransitionTimer> createState() => _VisualTransitionTimerState();
}

class _VisualTransitionTimerState extends State<VisualTransitionTimer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _cadenceFired = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addListener(_onTick)
      ..addStatusListener(_onStatus)
      ..forward();
  }

  void _onTick() {
    if (_cadenceFired) return;
    final int remainingMs =
        (widget.duration.inMilliseconds * (1.0 - _controller.value)).round();
    if (remainingMs <= widget.resolutionLead.inMilliseconds) {
      _cadenceFired = true;
      widget.onResolutionCadence?.call();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_finished) {
      _finished = true;
      widget.onFinished();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: widget.diameter,
        height: widget.diameter / 2 + 16,
        child: CustomPaint(
          painter: _RainbowArcPainter(_controller),
        ),
      ),
    );
  }
}

class _RainbowArcPainter extends CustomPainter {
  _RainbowArcPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  static const List<Color> _bands = <Color>[
    Color(0xFFE57373),
    Color(0xFFFFB74D),
    Color(0xFFFFF176),
    Color(0xFF81C784),
    Color(0xFF64B5F6),
    Color(0xFF9575CD),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final double remaining = (1.0 - progress.value).clamp(0.0, 1.0).toDouble();
    if (remaining <= 0) return;
    final double outer = math.min(size.width / 2, size.height - 8);
    final Offset center = Offset(size.width / 2, size.height - 8);
    final double bandW = outer / (_bands.length * 1.6);
    final double sweep = math.pi * remaining;
    for (int i = 0; i < _bands.length; i++) {
      final double r = outer - bandW * (i + 0.5);
      final Paint p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = bandW
        ..color = _bands[i].withAlpha(150);
      // The arc retreats from the right end toward the left.
      canvas.drawArc(
          Rect.fromCircle(center: center, radius: r), math.pi, sweep, false, p);
    }
  }

  @override
  bool shouldRepaint(covariant _RainbowArcPainter old) =>
      old.progress != progress;
}
