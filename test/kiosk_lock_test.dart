// Child touch-lock kiosk audit (CLAUDE.md section 5).
//
// Assumptions: `KioskLockLogic()` has a default constructor with cornerSize 96
// and a 3000 ms hold; timing is driven by `update(nowMs)` (the hold timer
// starts at the first update after both corners are down). Widget tests pump in
// small steps so a ticker/timer based implementation sees continuous frames.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aurasync/core/audio/audio_engine.dart';
import 'package:aurasync/core/models/sensory_state.dart';
import 'package:aurasync/ui/widgets/child_touch_lock_kiosk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _NullAudio implements AudioEngine {
  int notes = 0;

  @override
  void applyIso(IsoSnapshot snapshot) {}
  @override
  void dispose() {}
  @override
  void render(Float32List out, int frames) {}
  @override
  void setProfileLimits(
      {double highCutHz = 0, double masterCap = 1.0, bool allowWater = true}) {}
  @override
  void start(SessionPreset preset) {}
  @override
  void stop() {}
  @override
  void switchPreset(SessionPreset preset) {}
  @override
  void triggerNote(int degree, double velocity) => notes++;
}

const Size _size = Size(1000, 800);
const Offset _left = Offset(40, 40);
const Offset _right = Offset(960, 40);

void main() {
  group('KioskLockLogic', () {
    test('both corners held 3000 ms unlocks', () {
      final k = KioskLockLogic();
      k.pointerDown(1, _left, _size);
      k.pointerDown(2, _right, _size);
      k.update(0);
      for (var t = 100; t < 3000; t += 100) {
        k.update(t);
        expect(k.unlocked, isFalse, reason: 'at $t ms');
      }
      k.update(3000);
      expect(k.unlocked, isTrue);
      expect(k.progress, closeTo(1.0, 1e-9));
    });

    test('2999 ms does not unlock', () {
      final k = KioskLockLogic();
      k.pointerDown(1, _left, _size);
      k.pointerDown(2, _right, _size);
      k.update(0);
      k.update(2999);
      expect(k.unlocked, isFalse);
      expect(k.progress, lessThan(1.0));
    });

    test('progress rises roughly linearly while both corners are held', () {
      final k = KioskLockLogic();
      k.pointerDown(1, _left, _size);
      k.pointerDown(2, _right, _size);
      k.update(0);
      k.update(1500);
      expect(k.progress, closeTo(0.5, 0.05));
    });

    test('one corner only never unlocks', () {
      for (final pos in [_left, _right]) {
        final k = KioskLockLogic();
        k.pointerDown(1, pos, _size);
        for (var t = 0; t <= 30000; t += 50) {
          k.update(t);
        }
        expect(k.unlocked, isFalse);
        expect(k.progress, 0);
      }
    });

    test('two fingers in the same corner never unlock', () {
      final k = KioskLockLogic();
      k.pointerDown(1, const Offset(10, 10), _size);
      k.pointerDown(2, const Offset(60, 60), _size);
      for (var t = 0; t <= 10000; t += 50) {
        k.update(t);
      }
      expect(k.unlocked, isFalse);
    });

    test('corner size is 96 px: a touch at 100 px is not a corner', () {
      final k = KioskLockLogic();
      k.pointerDown(1, const Offset(100, 50), _size);
      k.pointerDown(2, Offset(_size.width - 100, 50), _size);
      for (var t = 0; t <= 6000; t += 50) {
        k.update(t);
      }
      expect(k.unlocked, isFalse);
    });

    test('releasing either corner resets the hold', () {
      final k = KioskLockLogic();
      k.pointerDown(1, _left, _size);
      k.pointerDown(2, _right, _size);
      k.update(0);
      k.update(2000);
      expect(k.progress, greaterThan(0.5));
      k.pointerUp(2);
      k.update(2100);
      expect(k.progress, 0);
      k.pointerDown(3, _right, _size);
      k.update(2200);
      k.update(5100); // only 2900 ms since re-press
      expect(k.unlocked, isFalse);
      k.update(5300);
      expect(k.unlocked, isTrue);
    });

    test('releasing the left corner also resets', () {
      final k = KioskLockLogic();
      k.pointerDown(1, _left, _size);
      k.pointerDown(2, _right, _size);
      k.update(0);
      k.update(2900);
      k.pointerUp(1);
      k.update(2950);
      k.pointerDown(1, _left, _size);
      k.update(3000);
      k.update(3500);
      expect(k.unlocked, isFalse);
    });

    test('sliding a finger out of its corner resets the hold', () {
      final k = KioskLockLogic();
      k.pointerDown(1, _left, _size);
      k.pointerDown(2, _right, _size);
      k.update(0);
      k.update(2000);
      k.pointerMove(2, const Offset(500, 400), _size);
      k.update(2100);
      k.update(6000);
      expect(k.unlocked, isFalse);
    });

    test('50 random taps/s for 60 s never unlock and never throw', () {
      final rnd = math.Random(20240607);
      final k = KioskLockLogic();
      var id = 0;
      expect(() {
        for (var tap = 0; tap < 3000; tap++) {
          final t = tap * 20;
          // Bias a third of the taps into the two corners.
          final r = rnd.nextInt(3);
          final pos = r == 0
              ? Offset(rnd.nextDouble() * 96, rnd.nextDouble() * 96)
              : r == 1
                  ? Offset(_size.width - rnd.nextDouble() * 96,
                      rnd.nextDouble() * 96)
                  : Offset(rnd.nextDouble() * _size.width,
                      rnd.nextDouble() * _size.height);
          id++;
          k.pointerDown(id, pos, _size);
          k.update(t);
          if (rnd.nextBool()) {
            k.pointerMove(id, Offset(pos.dx + 3, pos.dy + 3), _size);
          }
          k.update(t + 10);
          k.pointerUp(id);
          k.update(t + 11);
          expect(k.unlocked, isFalse, reason: 'tap $tap');
        }
      }, returnsNormally);
      expect(k.unlocked, isFalse);
    });

    test('taps alternating between the two corners never unlock', () {
      final k = KioskLockLogic();
      var id = 0;
      for (var tap = 0; tap < 6000; tap++) {
        final t = tap * 20;
        id++;
        k.pointerDown(id, tap.isEven ? _left : _right, _size);
        k.update(t);
        k.update(t + 15);
        k.pointerUp(id);
        k.update(t + 16);
      }
      expect(k.unlocked, isFalse);
    });

    test('alternating long holds (never simultaneous) never unlock', () {
      final k = KioskLockLogic();
      var t = 0;
      for (var i = 0; i < 20; i++) {
        final pos = i.isEven ? _left : _right;
        k.pointerDown(i + 1, pos, _size);
        for (var s = 0; s <= 4000; s += 100) {
          k.update(t + s);
        }
        k.pointerUp(i + 1);
        t += 4100;
      }
      expect(k.unlocked, isFalse);
    });
  });

  group('ChildTouchLockKiosk widget', () {
    Future<void> pumpKiosk(
      WidgetTester tester,
      _NullAudio audio,
      VoidCallback onUnlocked,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChildTouchLockKiosk(
            audio: audio,
            onUnlocked: onUnlocked,
            child: const SizedBox.expand(),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> hold(WidgetTester tester, int ms) async {
      for (var t = 0; t < ms; t += 50) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('spam tapping never unlocks; dual-corner 3 s hold unlocks once',
        (tester) async {
      var unlocked = 0;
      final audio = _NullAudio();
      await pumpKiosk(tester, audio, () => unlocked++);

      final rnd = math.Random(7);
      for (var i = 0; i < 300; i++) {
        final corner = rnd.nextInt(4);
        final pos = corner == 0
            ? Offset(rnd.nextDouble() * 90, rnd.nextDouble() * 90)
            : corner == 1
                ? Offset(800 - rnd.nextDouble() * 90, rnd.nextDouble() * 90)
                : Offset(rnd.nextDouble() * 800, rnd.nextDouble() * 600);
        await tester.tapAt(pos);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await hold(tester, 4000);
      expect(unlocked, 0);

      final g1 = await tester.startGesture(const Offset(40, 40));
      final g2 = await tester.startGesture(const Offset(760, 40));
      await hold(tester, 2800);
      expect(unlocked, 0, reason: 'must not unlock before 3 s');
      await hold(tester, 400);
      expect(unlocked, 1);
      await hold(tester, 2000);
      expect(unlocked, 1, reason: 'onUnlocked must fire exactly once');
      await g1.up();
      await g2.up();
      await hold(tester, 500);
      expect(unlocked, 1);
    });

    testWidgets('releasing one corner at 2 s resets; a one-corner hold never unlocks',
        (tester) async {
      var unlocked = 0;
      await pumpKiosk(tester, _NullAudio(), () => unlocked++);

      final g1 = await tester.startGesture(const Offset(40, 40));
      final g2 = await tester.startGesture(const Offset(760, 40));
      await hold(tester, 2000);
      await g2.up();
      await hold(tester, 5000);
      expect(unlocked, 0);
      await g1.up();

      final solo = await tester.startGesture(const Offset(760, 40));
      await hold(tester, 6000);
      expect(unlocked, 0);
      await solo.up();
      await hold(tester, 200);
    });
  });
}
