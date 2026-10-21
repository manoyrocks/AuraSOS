import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/audio/audio_engine.dart';

/// Pure, testable unlock gesture logic: BOTH top corner zones must be held at the same
/// time, continuously, for [holdMs]. Releasing (or sliding out of) either zone resets.
///
/// Time is supplied through [update]. The hold clock starts at the first [update] call
/// made after both zones become occupied (at most one frame after the second touch).
class KioskLockLogic {
  KioskLockLogic({this.cornerSize = 96, this.holdMs = 3000});

  final double cornerSize;
  final int holdMs;

  final Map<int, Offset> _pointers = <int, Offset>{};
  Size _size = Size.zero;
  bool _armed = false;
  int? _holdStartMs;
  int _lastNowMs = 0;
  bool _unlocked = false;

  bool get unlocked => _unlocked;

  /// 0..1 fraction of the hold completed (1.0 once unlocked).
  double get progress {
    if (_unlocked) return 1.0;
    final int? start = _holdStartMs;
    if (!_armed || start == null) return 0.0;
    return ((_lastNowMs - start) / holdMs).clamp(0.0, 1.0).toDouble();
  }

  bool get armed => _armed;

  void pointerDown(int id, Offset pos, Size size) {
    _size = size;
    _pointers[id] = pos;
    _reevaluate();
  }

  void pointerMove(int id, Offset pos, Size size) {
    if (!_pointers.containsKey(id)) return;
    _size = size;
    _pointers[id] = pos;
    _reevaluate();
  }

  void pointerUp(int id) {
    if (_pointers.remove(id) == null) return;
    _reevaluate();
  }

  void update(int nowMs) {
    _lastNowMs = nowMs;
    if (_unlocked) return;
    if (!_armed) {
      _holdStartMs = null;
      return;
    }
    _holdStartMs ??= nowMs;
    if (nowMs - _holdStartMs! >= holdMs) {
      _unlocked = true;
    }
  }

  /// Clears the unlock event and all tracked pointers; a fresh hold is then required.
  void consumeUnlock() {
    _pointers.clear();
    _armed = false;
    _holdStartMs = null;
    _unlocked = false;
  }

  bool _inLeft(Offset p) =>
      p.dx < cornerSize && p.dy < cornerSize && p.dy >= 0 && p.dx >= 0;

  bool _inRight(Offset p) =>
      p.dx > _size.width - cornerSize &&
      p.dx <= _size.width &&
      p.dy < cornerSize &&
      p.dy >= 0;

  void _reevaluate() {
    if (_unlocked) return;
    bool left = false;
    bool right = false;
    for (final Offset p in _pointers.values) {
      if (_inLeft(p)) left = true;
      if (_inRight(p)) right = true;
    }
    final bool both = left && right;
    if (!both) {
      _armed = false;
      _holdStartMs = null;
    } else if (!_armed) {
      _armed = true;
      _holdStartMs = null;
    }
  }
}

/// Wraps [child] in a child-proof touch lock: immersive, back blocked, touches make
/// ripples and soft kalimba plucks, and only the two-corner hold calls [onUnlocked].
class ChildTouchLockKiosk extends StatefulWidget {
  const ChildTouchLockKiosk({
    super.key,
    required this.audio,
    required this.child,
    required this.onUnlocked,
    this.cornerSize = 96,
    this.holdDuration = const Duration(seconds: 3),
    this.onTouch,
  });

  final AudioEngine audio;
  final Widget child;
  final VoidCallback onUnlocked;
  final double cornerSize;
  final Duration holdDuration;

  /// Optional hook for the position of each new touch (e.g. to feed a shader).
  final ValueChanged<Offset>? onTouch;

  @override
  State<ChildTouchLockKiosk> createState() => _ChildTouchLockKioskState();
}

class _Ripple {
  _Ripple(this.pos, this.startMs);
  final Offset pos;
  final int startMs;
}

class _ChildTouchLockKioskState extends State<ChildTouchLockKiosk>
    with SingleTickerProviderStateMixin {
  static const int _maxRipples = 12;
  static const int _rippleLifeMs = 1600;
  static const int _minPluckGapMs = 125; // ~8 plucks per second
  static const int _minMoveRippleGapMs = 90;
  static const double _maxVelocity = 0.6;

  late final KioskLockLogic _logic;
  late final Ticker _ticker;
  final _FrameClock _clock = _FrameClock();
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  final List<_Ripple> _ripples = <_Ripple>[];
  Size _size = Size.zero;
  int _lastPluckMs = -100000;
  int _lastMoveRippleMs = -100000;
  bool _hasCornerRings = false;

  @override
  void initState() {
    super.initState();
    _logic = KioskLockLogic(
      cornerSize: widget.cornerSize,
      holdMs: widget.holdDuration.inMilliseconds,
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    _clock.elapsedMilliseconds = elapsed.inMilliseconds;
    final int now = _clock.elapsedMilliseconds;
    _logic.update(now);
    _ripples.removeWhere((_Ripple r) => now - r.startMs > _rippleLifeMs);
    if (_logic.unlocked) {
      _logic.consumeUnlock();
      widget.onUnlocked();
    }
    final bool rings = _logic.progress > 0;
    if (_ripples.isNotEmpty || rings || _hasCornerRings) {
      _hasCornerRings = rings;
      _frame.value++;
    }
  }

  void _addRipple(Offset pos, int now) {
    _ripples.add(_Ripple(pos, now));
    while (_ripples.length > _maxRipples) {
      _ripples.removeAt(0);
    }
  }

  void _pluck(Offset pos, int now) {
    if (now - _lastPluckMs < _minPluckGapMs || _size.width <= 0) return;
    _lastPluckMs = now;
    final int degree = (pos.dx / _size.width * 10).floor().clamp(0, 9).toInt();
    final double velocity = math.min(
        _maxVelocity, 0.30 + 0.25 * (pos.dy / math.max(_size.height, 1)));
    widget.audio.triggerNote(degree, velocity);
  }

  void _down(PointerDownEvent e) {
    final int now = _clock.elapsedMilliseconds;
    _logic.pointerDown(e.pointer, e.localPosition, _size);
    _addRipple(e.localPosition, now);
    _pluck(e.localPosition, now);
    widget.onTouch?.call(e.localPosition);
    _frame.value++;
  }

  void _move(PointerMoveEvent e) {
    final int now = _clock.elapsedMilliseconds;
    _logic.pointerMove(e.pointer, e.localPosition, _size);
    if (now - _lastMoveRippleMs >= _minMoveRippleGapMs) {
      _lastMoveRippleMs = now;
      _addRipple(e.localPosition, now);
    }
    _pluck(e.localPosition, now);
  }

  void _up(PointerEvent e) {
    _logic.pointerUp(e.pointer);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          _size = constraints.biggest;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _up,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                widget.child,
                IgnorePointer(
                  child: CustomPaint(
                    painter: _KioskOverlayPainter(
                      frame: _frame,
                      ripples: _ripples,
                      clock: _clock,
                      logic: _logic,
                      cornerSize: widget.cornerSize,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _KioskOverlayPainter extends CustomPainter {
  _KioskOverlayPainter({
    required this.frame,
    required this.ripples,
    required this.clock,
    required this.logic,
    required this.cornerSize,
  }) : super(repaint: frame);

  final ValueListenable<int> frame;
  final List<_Ripple> ripples;
  final _FrameClock clock;
  final KioskLockLogic logic;
  final double cornerSize;

  @override
  void paint(Canvas canvas, Size size) {
    final int now = clock.elapsedMilliseconds;
    for (final _Ripple r in ripples) {
      final double age =
          ((now - r.startMs) / 1600.0).clamp(0.0, 1.0).toDouble();
      final double eased = 1.0 - (1.0 - age) * (1.0 - age);
      final int alpha = ((1.0 - age) * 110).round().clamp(0, 255).toInt();
      final Paint p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0 + 3.0 * (1.0 - age)
        ..color = Color.fromARGB(alpha, 200, 235, 255);
      canvas.drawCircle(r.pos, 14 + 110 * eased, p);
      if (age < 0.7) {
        canvas.drawCircle(r.pos, 8 + 60 * eased, p..strokeWidth = 2.0);
      }
    }

    final double prog = logic.progress;
    if (prog > 0) {
      final double radius = cornerSize * 0.42;
      final Paint ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4
        ..color = const Color(0x55FFFFFF);
      for (final Offset c in <Offset>[
        Offset(cornerSize / 2, cornerSize / 2),
        Offset(size.width - cornerSize / 2, cornerSize / 2),
      ]) {
        canvas.drawArc(Rect.fromCircle(center: c, radius: radius), -math.pi / 2,
            2 * math.pi * prog, false, ring);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KioskOverlayPainter old) => false;
}

/// Millisecond clock advanced by the kiosk's ticker, so hold timing follows frame time
/// (identical on device, deterministic under fake-async tests).
class _FrameClock {
  int elapsedMilliseconds = 0;
}
