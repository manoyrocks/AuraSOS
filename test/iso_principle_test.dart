// Iso-Principle protocol audit (CLAUDE.md section 3).
//
// Assumptions: `IsoPrincipleController.snapshotAt(int)` is a pure static
// function; the stateful controller is built with `IsoPrincipleController(audio:)`.
// `tick(ms)` is only used in a way that is identical whether it means "delta"
// or "absolute elapsed" (a single tick directly after start()). `deepCrisis`
// is driven through a setter, falling back to a one-argument method.
import 'dart:typed_data';

import 'package:aurasync/core/audio/audio_engine.dart';
import 'package:aurasync/core/engine/iso_principle_controller.dart';
import 'package:aurasync/core/models/sensory_state.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAudio implements AudioEngine {
  final List<IsoSnapshot> applied = [];

  @override
  void applyIso(IsoSnapshot snapshot) => applied.add(snapshot);
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
  void triggerNote(int degree, double velocity) {}
}

IsoSnapshot _at(int ms) => IsoPrincipleController.snapshotAt(ms);

void _setDeepCrisis(IsoPrincipleController c, bool on) {
  final d = c as dynamic;
  try {
    d.deepCrisis = on;
  } on NoSuchMethodError {
    d.deepCrisis(on);
  }
}

void main() {
  group('phase table', () {
    test('t=0: Match, 104 BPM, 2000 Hz, 1.0x, no protocol dimming', () {
      final s = _at(0);
      expect(s.phase, IsoPhase.match);
      expect(s.bpm, 104);
      expect(s.lpfHz, 2000);
      expect(s.shaderSpeed, 1.0);
      expect(s.dimmerAlpha, isNot(0.40));
      expect(s.heartbeatGain, 0);
      expect(s.rhythmWeight, greaterThan(s.padWeight));
    });

    test('t=179999 ms is still Match with unchanged parameters', () {
      final s = _at(179999);
      expect(s.phase, IsoPhase.match);
      expect(s.bpm, 104);
      expect(s.lpfHz, 2000);
      expect(s.shaderSpeed, 1.0);
      expect(s.dimmerAlpha, isNot(0.40));
    });

    test('t=180000 ms enters Thinning at the Match values', () {
      final s = _at(180000);
      expect(s.phase, IsoPhase.thinning);
      expect(s.bpm, closeTo(104, 1e-9));
      expect(s.lpfHz, closeTo(2000, 1e-9));
      expect(s.shaderSpeed, closeTo(1.0, 1e-9));
      expect(s.dimmerAlpha, isNot(0.40));
    });

    test('t=330000 ms (midpoint) is linear: 88 BPM, 1450 Hz', () {
      final s = _at(330000);
      expect(s.phase, IsoPhase.thinning);
      expect(s.bpm, closeTo(88, 0.01));
      expect(s.lpfHz, closeTo(1450, 0.5));
      expect(s.shaderSpeed, inInclusiveRange(0.5, 1.0));
      expect(s.shaderSpeed, lessThan(1.0));
      expect(s.dimmerAlpha, isNot(0.40));
    });

    test('t=479999 ms is the end of Thinning: ~72 BPM, ~900 Hz, ~0.5x', () {
      final s = _at(479999);
      expect(s.phase, IsoPhase.thinning);
      expect(s.bpm, closeTo(72, 0.01));
      expect(s.lpfHz, closeTo(900, 0.5));
      expect(s.shaderSpeed, closeTo(0.5, 0.01));
      expect(s.dimmerAlpha, isNot(0.40));
    });

    test('t=480000 ms enters Baseline: 58 BPM, 500 Hz, 0.25x, dimmer 0.40', () {
      final s = _at(480000);
      expect(s.phase, IsoPhase.baseline);
      expect(s.bpm, 58);
      expect(s.lpfHz, 500);
      expect(s.shaderSpeed, 0.25);
      expect(s.dimmerAlpha, 0.40);
      expect(s.heartbeatGain, greaterThan(0));
      expect(s.brownNoiseGain, greaterThan(0));
      expect(s.rhythmWeight, lessThan(s.padWeight));
    });

    test('t >= 720000 ms stays at Baseline forever', () {
      for (final ms in [720000, 900000, 3600000, 86400000]) {
        final s = _at(ms);
        expect(s.phase, IsoPhase.baseline, reason: '$ms');
        expect(s.bpm, 58);
        expect(s.lpfHz, 500);
        expect(s.shaderSpeed, 0.25);
        expect(s.dimmerAlpha, 0.40);
      }
    });

    test('stem weights stay within 0..1 across the whole timeline', () {
      for (var ms = 0; ms <= 800000; ms += 1000) {
        final s = _at(ms);
        for (final v in [
          s.rhythmWeight,
          s.padWeight,
          s.brownNoiseGain,
          s.heartbeatGain
        ]) {
          expect(v, inInclusiveRange(0.0, 1.0), reason: 'at $ms ms');
        }
      }
    });
  });

  group('monotonicity', () {
    test('BPM, LPF and shader speed never increase; dimmer 0.40 only at baseline',
        () {
      var prev = _at(0);
      for (var ms = 0; ms <= 800000; ms += 500) {
        final s = _at(ms);
        expect(s.elapsedMs, ms);
        expect(s.bpm, lessThanOrEqualTo(prev.bpm), reason: 'bpm at $ms');
        expect(s.lpfHz, lessThanOrEqualTo(prev.lpfHz), reason: 'lpf at $ms');
        expect(s.shaderSpeed, lessThanOrEqualTo(prev.shaderSpeed),
            reason: 'speed at $ms');
        if (s.phase == IsoPhase.baseline) {
          expect(s.dimmerAlpha, 0.40, reason: 'dimmer at $ms');
        } else {
          expect(s.dimmerAlpha, isNot(0.40), reason: 'dimmer at $ms');
        }
        prev = s;
      }
    });

    test('phase order never regresses', () {
      var idx = 0;
      for (var ms = 0; ms <= 800000; ms += 250) {
        final i = _at(ms).phase.index;
        expect(i, greaterThanOrEqualTo(idx));
        idx = i;
      }
    });
  });

  group('determinism', () {
    test('snapshotAt is a pure function of elapsed ms', () {
      for (final ms in [0, 1, 179999, 180000, 300000, 479999, 480000, 999999]) {
        final a = _at(ms);
        final b = _at(ms);
        expect(a.phase, b.phase);
        expect(a.bpm, b.bpm);
        expect(a.lpfHz, b.lpfHz);
        expect(a.shaderSpeed, b.shaderSpeed);
        expect(a.dimmerAlpha, b.dimmerAlpha);
        expect(a.rhythmWeight, b.rhythmWeight);
        expect(a.padWeight, b.padWeight);
        expect(a.brownNoiseGain, b.brownNoiseGain);
        expect(a.heartbeatGain, b.heartbeatGain);
      }
    });

    test('two controllers fed the same input produce identical output', () {
      final a1 = _RecordingAudio();
      final a2 = _RecordingAudio();
      final c1 = IsoPrincipleController(audio: a1)..start();
      final c2 = IsoPrincipleController(audio: a2)..start();
      c1.tick(300000);
      c2.tick(300000);
      expect(c1.current.elapsedMs, 300000);
      expect(c1.current.bpm, c2.current.bpm);
      expect(c1.current.lpfHz, c2.current.lpfHz);
      expect(c1.current.phase, c2.current.phase);
      expect(c1.current.bpm, closeTo(_at(300000).bpm, 1e-9));
      expect(a1.applied, isNotEmpty);
      expect(a1.applied.length, a2.applied.length);
      c1.stop();
      c2.stop();
    });
  });

  group('deep crisis', () {
    test('bypasses rhythm: Brownian anchor with 650 Hz LPF', () {
      final audio = _RecordingAudio();
      final c = IsoPrincipleController(audio: audio)..start();
      _setDeepCrisis(c, true);
      c.tick(1000);
      final s = c.current;
      expect(s.lpfHz, 650);
      expect(s.rhythmWeight, 0);
      expect(s.brownNoiseGain, greaterThan(0));
      expect(audio.applied, isNotEmpty);
      expect(audio.applied.last.lpfHz, 650);
      expect(audio.applied.last.rhythmWeight, 0);
      c.stop();
    });

    test('stays at 650 Hz / no rhythm regardless of elapsed time', () {
      final c = IsoPrincipleController(audio: _RecordingAudio())..start();
      _setDeepCrisis(c, true);
      c.tick(100000);
      expect(c.current.lpfHz, 650);
      expect(c.current.rhythmWeight, 0);
      c.stop();
    });
  });
}
