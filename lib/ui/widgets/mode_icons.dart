import 'dart:math' as math;

import 'package:flutter/material.dart';

enum ModeIconKind { sos, focus, calm, deep }

/// Custom-drawn mode icons: soft gradients, a gentle glow and rounded forms, instead of the
/// stock glyphs. Drawn in a unit square so they scale crisply to any size.
class ModeIcon extends StatelessWidget {
  const ModeIcon({super.key, required this.kind, required this.size});

  final ModeIconKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _ModeIconPainter(kind),
      ),
    );
  }
}

class _ModeIconPainter extends CustomPainter {
  const _ModeIconPainter(this.kind);

  final ModeIconKind kind;

  static const Color _hi = Color(0xFFFFFFFF);
  static const Color _lo = Color(0xFFD7E6FF);

  Shader _fill(Rect r) => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[_hi, _lo],
      ).createShader(r);

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.shortestSide;
    canvas.save();
    canvas.scale(s);
    switch (kind) {
      case ModeIconKind.sos:
        _heart(canvas, s);
      case ModeIconKind.focus:
        _bubbles(canvas, s);
      case ModeIconKind.calm:
        _lotus(canvas, s);
      case ModeIconKind.deep:
        _moon(canvas, s);
    }
    canvas.restore();
  }

  Paint _glow(double s, double alpha) => Paint()
    ..color = Color.fromARGB((alpha * 255).round(), 255, 255, 255)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.05);

  void _heart(Canvas canvas, double s) {
    final Path heart = Path()
      ..moveTo(0.5, 0.84)
      ..cubicTo(0.14, 0.60, 0.08, 0.34, 0.26, 0.23)
      ..cubicTo(0.38, 0.16, 0.48, 0.22, 0.5, 0.30)
      ..cubicTo(0.52, 0.22, 0.62, 0.16, 0.74, 0.23)
      ..cubicTo(0.92, 0.34, 0.86, 0.60, 0.5, 0.84)
      ..close();
    // Calm ripples spreading from the heart.
    for (final (double r, double a) in <(double, double)>[
      (0.40, 0.30),
      (0.47, 0.14)
    ]) {
      canvas.drawCircle(
        const Offset(0.5, 0.53),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.022
          ..color = Color.fromARGB((a * 255).round(), 255, 255, 255),
      );
    }
    canvas.drawPath(heart, _glow(s, 0.35));
    canvas.drawPath(
        heart, Paint()..shader = _fill(const Rect.fromLTWH(0, 0, 1, 1)));
    // Soft highlight on the upper-left lobe.
    canvas.drawPath(
      Path()
        ..moveTo(0.22, 0.36)
        ..quadraticBezierTo(0.24, 0.28, 0.32, 0.27),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 0.035
        ..color = const Color(0x66FFFFFF),
    );
  }

  void _bubbles(Canvas canvas, double s) {
    final List<(Offset, double)> bubbles = <(Offset, double)>[
      (const Offset(0.40, 0.60), 0.25),
      (const Offset(0.70, 0.34), 0.16),
      (const Offset(0.72, 0.72), 0.10),
    ];
    for (final (Offset c, double r) in bubbles) {
      final Rect rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawCircle(c, r, _glow(s, 0.18));
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.4, -0.5),
            colors: <Color>[Color(0xCCFFFFFF), Color(0x40FFFFFF)],
          ).createShader(rect),
      );
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.02
          ..color = const Color(0xEEFFFFFF),
      );
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 0.62),
        math.pi * 1.05,
        math.pi * 0.45,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 0.024
          ..color = const Color(0xBBFFFFFF),
      );
    }
  }

  void _lotus(Canvas canvas, double s) {
    Path petal() => Path()
      ..moveTo(0.5, 0.20)
      ..cubicTo(0.70, 0.40, 0.68, 0.64, 0.5, 0.76)
      ..cubicTo(0.32, 0.64, 0.30, 0.40, 0.5, 0.20)
      ..close();
    final Paint fill = Paint()..shader = _fill(const Rect.fromLTWH(0, 0, 1, 1));
    for (final double angle in <double>[-0.95, 0.95]) {
      canvas.save();
      canvas.translate(0.5, 0.76);
      canvas.rotate(angle);
      canvas.scale(0.86);
      canvas.translate(-0.5, -0.76);
      canvas.drawPath(petal(), Paint()..color = const Color(0x99FFFFFF));
      canvas.restore();
    }
    canvas.drawPath(petal(), _glow(s, 0.3));
    canvas.drawPath(petal(), fill);
    // A calm wave beneath the flower.
    canvas.drawPath(
      Path()
        ..moveTo(0.18, 0.86)
        ..quadraticBezierTo(0.34, 0.80, 0.5, 0.86)
        ..quadraticBezierTo(0.66, 0.92, 0.82, 0.86),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 0.03
        ..color = const Color(0xCCFFFFFF),
    );
  }

  void _moon(Canvas canvas, double s) {
    final Path crescent = Path.combine(
      PathOperation.difference,
      Path()
        ..addOval(
            Rect.fromCircle(center: const Offset(0.46, 0.52), radius: 0.32)),
      Path()
        ..addOval(
            Rect.fromCircle(center: const Offset(0.60, 0.44), radius: 0.28)),
    );
    canvas.drawPath(crescent, _glow(s, 0.35));
    canvas.drawPath(
        crescent, Paint()..shader = _fill(const Rect.fromLTWH(0, 0, 1, 1)));
    for (final (Offset c, double r) in <(Offset, double)>[
      (const Offset(0.74, 0.26), 0.085),
      (const Offset(0.84, 0.50), 0.05),
    ]) {
      final Path star = Path()
        ..moveTo(c.dx, c.dy - r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
        ..close();
      canvas.drawPath(star, _glow(s, 0.4));
      canvas.drawPath(star, Paint()..color = const Color(0xFFFFFFFF));
    }
  }

  @override
  bool shouldRepaint(_ModeIconPainter old) => old.kind != kind;
}
