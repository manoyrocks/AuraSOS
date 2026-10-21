import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../core/models/sensory_state.dart';

/// Lets the parent feed the most recent touch position (logical px) into the shader.
class ShaderTouchSource extends ChangeNotifier {
  Offset? last;

  void touch(Offset position) {
    last = position;
    notifyListeners();
  }
}

/// Renders one of the four sensory fragment shaders. Falls back to a pure-Canvas
/// painter if the shader cannot be loaded, so the child never sees an error.
///
/// Float uniform order: uSize.x, uSize.y, uTime, uSpeed, uDim, uTouch.x, uTouch.y, uTouch.z.
class SensoryShaderView extends StatefulWidget {
  const SensoryShaderView({
    super.key,
    required this.kind,
    this.speed = 1.0,
    this.dim = 1.0,
    this.touchSource,
  });

  final ShaderKind kind;

  /// Multiplier on the rate at which shader time advances.
  final double speed;

  /// In-shader brightness multiplier 0..1.
  final double dim;
  final ShaderTouchSource? touchSource;

  static String assetFor(ShaderKind kind) {
    switch (kind) {
      case ShaderKind.tunnel:
        return 'shaders/bioluminescent_tunnel.frag';
      case ShaderKind.bubbles:
        return 'shaders/classroom_bubbles.frag';
      case ShaderKind.lanterns:
        return 'shaders/oled_lanterns.frag';
      case ShaderKind.breathingOrb:
        return 'shaders/breathing_orb.frag';
      case ShaderKind.crystals:
        return 'shaders/crystal_polygons.frag';
      case ShaderKind.starfield:
        return 'shaders/starfield_3d.frag';
      case ShaderKind.aurora:
        return 'shaders/aurora_ribbons.frag';
      case ShaderKind.mandala:
        return 'shaders/mandala_polygons.frag';
    }
  }

  @override
  State<SensoryShaderView> createState() => _SensoryShaderViewState();
}

class _SensoryShaderViewState extends State<SensoryShaderView>
    with SingleTickerProviderStateMixin {
  static const double _touchLifeSec = 2.5;

  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  Duration _lastElapsed = Duration.zero;
  ui.FragmentShader? _shader;
  int _loadGeneration = 0;
  Offset? _touchPos;
  double _touchStartTime = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    widget.touchSource?.addListener(_onTouch);
    _load();
  }

  Future<void> _load() async {
    final int gen = ++_loadGeneration;
    try {
      final ui.FragmentProgram program = await ui.FragmentProgram.fromAsset(
          SensoryShaderView.assetFor(widget.kind));
      if (!mounted || gen != _loadGeneration) return;
      final ui.FragmentShader shader = program.fragmentShader();
      setState(() {
        _shader?.dispose();
        _shader = shader;
      });
    } catch (_) {
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _shader?.dispose();
        _shader = null;
      });
    }
  }

  void _onTick(Duration elapsed) {
    final double dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    // Clamp dt so a stalled frame can never cause a visual jump.
    _time.value += math.min(dt, 0.1) * widget.speed.clamp(0.0, 4.0);
  }

  void _onTouch() {
    _touchPos = widget.touchSource?.last;
    _touchStartTime = _time.value;
  }

  @override
  void didUpdateWidget(covariant SensoryShaderView old) {
    super.didUpdateWidget(old);
    if (old.touchSource != widget.touchSource) {
      old.touchSource?.removeListener(_onTouch);
      widget.touchSource?.addListener(_onTouch);
    }
    if (old.kind != widget.kind) {
      _load();
    }
  }

  @override
  void dispose() {
    widget.touchSource?.removeListener(_onTouch);
    _ticker.dispose();
    _time.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui.FragmentShader? shader = _shader;
    return RepaintBoundary(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: shader == null
              ? FallbackSensoryPainter(
                  kind: widget.kind, time: _time, dim: widget.dim)
              : _ShaderPainter(
                  shader: shader,
                  time: _time,
                  speed: widget.speed,
                  dim: widget.dim,
                  touchPos: () => _touchPos,
                  touchStart: () => _touchStartTime,
                  touchLifeSec: _touchLifeSec,
                ),
        ),
      ),
    );
  }
}

class _ShaderPainter extends CustomPainter {
  _ShaderPainter({
    required this.shader,
    required this.time,
    required this.speed,
    required this.dim,
    required this.touchPos,
    required this.touchStart,
    required this.touchLifeSec,
  }) : super(repaint: time);

  final ui.FragmentShader shader;
  final ValueNotifier<double> time;
  final double speed;
  final double dim;
  final Offset? Function() touchPos;
  final double Function() touchStart;
  final double touchLifeSec;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset? tp = touchPos();
    // Age is measured in shader time, which already scales with speed; normalise by speed
    // so a ring lasts about the same wall-clock time at every protocol speed.
    final double s = speed <= 0.05 ? 0.05 : speed;
    final double age =
        tp == null ? 1.0 : ((time.value - touchStart()) / (touchLifeSec * s));
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time.value)
      ..setFloat(3, speed)
      ..setFloat(4, dim.clamp(0.0, 1.0).toDouble())
      ..setFloat(5, tp?.dx ?? 0.0)
      ..setFloat(6, tp?.dy ?? 0.0)
      ..setFloat(7, age.clamp(0.0, 1.0).toDouble());
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _ShaderPainter old) =>
      old.shader != shader || old.speed != speed || old.dim != dim;
}

const Color _white = Color(0xFFFFFFFF);

/// Pure-Canvas approximation of the shaders. Slow, low-contrast, no flicker.
class FallbackSensoryPainter extends CustomPainter {
  FallbackSensoryPainter(
      {required this.kind, required this.time, required this.dim})
      : super(repaint: time);

  final ShaderKind kind;
  final ValueListenable<double> time;
  final double dim;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = time.value;
    final double d = dim.clamp(0.0, 1.0).toDouble();
    final Rect rect = Offset.zero & size;
    switch (kind) {
      case ShaderKind.lanterns:
        canvas.drawRect(rect, Paint()..color = const Color(0xFF000000));
        _lanterns(canvas, size, t, d);
        break;
      case ShaderKind.breathingOrb:
        canvas.drawRect(
            rect, Paint()..color = _scale(const Color(0xFF03050D), d));
        _orb(canvas, size, t, d);
        break;
      case ShaderKind.bubbles:
        canvas.drawRect(
          rect,
          Paint()
            ..shader =
                ui.Gradient.linear(rect.topCenter, rect.bottomCenter, <Color>[
              _scale(const Color(0xFF9FC7E8), d * 0.62),
              _scale(const Color(0xFFCCE6D9), d * 0.62),
            ]),
        );
        _bubbles(canvas, size, t, d);
        break;
      case ShaderKind.tunnel:
        canvas.drawRect(
            rect, Paint()..color = _scale(const Color(0xFF030817), d));
        _tunnel(canvas, size, t, d);
        break;
      case ShaderKind.crystals:
        canvas.drawRect(
          rect,
          Paint()
            ..shader =
                ui.Gradient.linear(rect.topCenter, rect.bottomCenter, <Color>[
              _scale(const Color(0xFF0B0F26), d),
              _scale(const Color(0xFF05071A), d),
            ]),
        );
        _crystals(canvas, size, t, d);
        break;
      case ShaderKind.starfield:
        canvas.drawRect(
            rect, Paint()..color = _scale(const Color(0xFF05061A), d));
        _starfield(canvas, size, t, d);
        break;
      case ShaderKind.aurora:
        canvas.drawRect(
            rect, Paint()..color = _scale(const Color(0xFF040716), d));
        _aurora(canvas, size, t, d);
        break;
      case ShaderKind.mandala:
        canvas.drawRect(
            rect, Paint()..color = _scale(const Color(0xFF070718), d));
        _mandala(canvas, size, t, d);
        break;
    }
  }

  static Color _scale(Color c, double f) =>
      Color.lerp(const Color(0xFF000000), c, f.clamp(0.0, 1.0).toDouble())!;

  void _tunnel(Canvas canvas, Size size, double t, double d) {
    final Offset c = size.center(Offset.zero);
    final double maxR = size.longestSide * 0.6;
    for (int i = 0; i < 7; i++) {
      final double phase = ((i / 7.0) + t * 0.02) % 1.0;
      final double r = maxR * phase * phase;
      final double alpha = math.sin(phase * math.pi) * 0.35 * d;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6 + 26 * phase
          ..color = const Color(0xFF1AA3B0)
              .withAlpha((alpha * 255).round().clamp(0, 255)),
      );
    }
  }

  void _bubbles(Canvas canvas, Size size, double t, double d) {
    for (int i = 0; i < 12; i++) {
      final double h1 = _h(i + 1.0);
      final double h2 = _h(i + 17.0);
      final double h3 = _h(i + 33.0);
      final double rad = size.shortestSide * (0.04 + 0.06 * h1);
      final double rise = 0.012 + 0.02 * h2;
      final double y = size.height * (1.0 - ((h3 + t * rise) % 1.0));
      final double x =
          size.width * (0.1 + 0.8 * h2) + math.sin(t * 0.3 + i) * 10;
      final Offset c = Offset(x, y);
      canvas.drawCircle(
          c, rad, Paint()..color = _white.withAlpha((40 * d).round()));
      canvas.drawCircle(
        c,
        rad,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _white.withAlpha((110 * d).round()),
      );
    }
  }

  void _lanterns(Canvas canvas, Size size, double t, double d) {
    for (int i = 0; i < 6; i++) {
      final double h1 = _h(i + 3.0);
      final double h2 = _h(i + 41.0);
      final double h3 = _h(i + 77.0);
      final double rad = size.shortestSide * (0.10 + 0.07 * h1);
      final double rise = 0.008 + 0.01 * h2;
      final double y = size.height * (1.0 - ((h3 + t * rise) % 1.0));
      final double x =
          size.width * (0.15 + 0.7 * h2) + math.sin(t * 0.2 + i) * 8;
      final double pulse = 0.8 + 0.2 * math.sin(t * 0.45 + i * 1.3);
      final Offset c = Offset(x, y);
      canvas.drawCircle(
        c,
        rad,
        Paint()
          ..shader = ui.Gradient.radial(c, rad, <Color>[
            Color.fromARGB(
                (150 * pulse * d).round().clamp(0, 255), 190, 90, 20),
            const Color(0x00000000),
          ]),
      );
    }
  }

  void _orb(Canvas canvas, Size size, double t, double d) {
    final double cyc = t % 10.0;
    final double e = cyc < 4.0
        ? 0.5 - 0.5 * math.cos(math.pi * cyc / 4.0)
        : 0.5 + 0.5 * math.cos(math.pi * (cyc - 4.0) / 6.0);
    final double rad = size.shortestSide * (0.16 + 0.18 * e);
    final Offset c = size.center(Offset.zero);
    final int a = ((0.55 + 0.45 * e) * 255 * d).round().clamp(0, 255);
    canvas.drawCircle(
      c,
      rad * 2.2,
      Paint()
        ..shader = ui.Gradient.radial(c, rad * 2.2, <Color>[
          Color.fromARGB((a * 0.5).round(), 70, 150, 190),
          const Color(0x00000000),
        ]),
    );
    canvas.drawCircle(c, rad, Paint()..color = Color.fromARGB(a, 70, 150, 200));
  }

  Path _polygon(Offset c, double r, int sides, double rot) {
    final Path p = Path();
    for (int i = 0; i < sides; i++) {
      final double a = rot + i * 2 * math.pi / sides - math.pi / 2;
      final Offset v = c + Offset(math.cos(a), math.sin(a)) * r;
      i == 0 ? p.moveTo(v.dx, v.dy) : p.lineTo(v.dx, v.dy);
    }
    return p..close();
  }

  void _crystals(Canvas canvas, Size size, double t, double d) {
    final double u = size.shortestSide;
    final List<(Offset, double, int, Color, double)> shapes =
        <(Offset, double, int, Color, double)>[
      (
        Offset(size.width * 0.30, size.height * 0.36),
        u * 0.20,
        4,
        const Color(0xFF5CC6DB),
        0.10
      ),
      (
        Offset(size.width * 0.70, size.height * 0.62),
        u * 0.17,
        6,
        const Color(0xFFA890F0),
        -0.08
      ),
      (
        Offset(size.width * 0.52, size.height * 0.22),
        u * 0.13,
        3,
        const Color(0xFFF5AB9E),
        0.12
      ),
    ];
    for (final (Offset c, double r, int sides, Color col, double speed)
        in shapes) {
      final Path poly = _polygon(c, r, sides, t * speed);
      canvas.drawPath(
        poly,
        Paint()
          ..shader =
              ui.Gradient.linear(c - Offset(r, r), c + Offset(r, r), <Color>[
            _scale(col, d),
            _scale(col, d * 0.35),
          ]),
      );
      canvas.drawPath(
        poly,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = _white.withAlpha((90 * d).round()),
      );
    }
  }

  void _starfield(Canvas canvas, Size size, double t, double d) {
    final Offset c = size.center(Offset.zero);
    final double reach = size.longestSide * 0.6;
    for (int i = 0; i < 60; i++) {
      final double ang = _h(i + 5.0) * 2 * math.pi;
      final double phase = (_h(i + 29.0) + t * 0.03) % 1.0;
      final double r = reach * phase * phase;
      final double fade = math.sin(phase * math.pi);
      final Offset p = c + Offset(math.cos(ang), math.sin(ang)) * r;
      canvas.drawCircle(
        p,
        0.6 + 2.6 * phase,
        Paint()
          ..color = _white.withAlpha((210 * fade * d).round().clamp(0, 255)),
      );
    }
  }

  void _aurora(Canvas canvas, Size size, double t, double d) {
    const List<Color> palette = <Color>[
      Color(0xFF1ECFA0),
      Color(0xFF6F8BE8),
      Color(0xFFC06AE8),
    ];
    for (int k = 0; k < 3; k++) {
      final double base = size.height * (0.30 + 0.12 * k);
      final Path ribbon = Path()..moveTo(0, size.height);
      ribbon.lineTo(0, base);
      for (double x = 0; x <= size.width; x += 8) {
        final double y = base +
            math.sin(x / size.width * (3 + k) + t * 0.08 + k) *
                size.height *
                0.05;
        ribbon.lineTo(x, y);
      }
      ribbon.lineTo(size.width, size.height);
      ribbon.close();
      canvas.drawPath(
        ribbon,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, base - size.height * 0.15),
            Offset(0, base + size.height * 0.25),
            <Color>[
              palette[k].withAlpha((150 * d).round()),
              palette[k].withAlpha(0),
            ],
          ),
      );
    }
  }

  void _mandala(Canvas canvas, Size size, double t, double d) {
    final Offset c = size.center(Offset.zero);
    final double u = size.shortestSide;
    for (int i = 0; i < 7; i++) {
      final double dir = i.isEven ? 1.0 : -1.0;
      final Path poly =
          _polygon(c, u * (0.10 + 0.065 * i), 3 + i, t * 0.03 * dir + i * 0.5);
      canvas.drawPath(
        poly,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color =
              HSVColor.fromAHSV(0.8 * d, (i * 48.0 + 200) % 360, 0.35, 0.95)
                  .toColor(),
      );
    }
  }

  static double _h(double n) {
    final double v = math.sin(n * 127.1) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  bool shouldRepaint(covariant FallbackSensoryPainter old) =>
      old.kind != kind || old.dim != dim;
}
