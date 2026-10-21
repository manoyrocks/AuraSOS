import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aurasync/core/audio/audio_engine.dart';
import 'package:aurasync/core/audio/dsp_bridge.dart';
import 'package:aurasync/core/audio/voice_weave.dart';
import 'package:aurasync/core/models/sensory_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _sr = AudioEngine.sampleRate;

Float32List _phrase() {
  final p = Float32List(2 * _sr);
  for (var i = 0; i < p.length; i++) {
    final t = i / _sr;
    p[i] = 0.5 * math.sin(2 * math.pi * 220 * t) * (0.6 + 0.4 * math.sin(2 * math.pi * 3 * t));
  }
  return p;
}

Float32List _render(PureDartDsp e, int seconds) {
  final out = Float32List(seconds * _sr * 2);
  const block = 480;
  final tmp = Float32List(block * 2);
  for (var f = 0; f < seconds * _sr; f += block) {
    e.render(tmp, block);
    out.setRange(f * 2, (f + block) * 2, tmp);
  }
  return out;
}

double _diffRms(Float32List a, Float32List b, double from, double to) {
  final lo = (from * _sr).round() * 2, hi = (to * _sr).round() * 2;
  var sum = 0.0;
  for (var i = lo; i < hi; i++) {
    final d = a[i] - b[i];
    sum += d * d;
  }
  return math.sqrt(sum / (hi - lo));
}

void main() {
  test('phrases are woven in on a schedule and respect the safety limits', () {
    final withVoice = PureDartDsp()..start(SessionPreset.isoDownRegulator);
    final plain = PureDartDsp()..start(SessionPreset.isoDownRegulator);
    withVoice.loadVoice(0, _phrase());
    withVoice.setVoiceWeave(enabled: true, gain: 0.12, intervalSec: 10);

    final a = _render(withVoice, 40);
    final b = _render(plain, 40);

    var peak = 0.0, maxDelta = 0.0;
    for (var i = 0; i < a.length; i++) {
      expect(a[i].isFinite, isTrue);
      peak = math.max(peak, a[i].abs());
      if (i >= 2) maxDelta = math.max(maxDelta, (a[i] - a[i - 2]).abs());
    }
    expect(peak, lessThanOrEqualTo(AudioEngine.ceilingLinear));
    expect(maxDelta, lessThan(0.005));

    expect(_diffRms(a, b, 0, 13.5), lessThan(1e-6), reason: 'no leak before first phrase');
    expect(_diffRms(a, b, 15, 16), greaterThan(1e-3), reason: 'first phrase audible');
    expect(_diffRms(a, b, 17, 22), lessThan(1e-4), reason: 'pause between phrases');
    expect(_diffRms(a, b, 26.8, 27.4), greaterThan(1e-3), reason: 'second phrase audible');
  });

  test('a cleared slot and a disabled weave stay silent', () {
    final cleared = PureDartDsp()..start(SessionPreset.calmStim);
    cleared.loadVoice(0, _phrase());
    cleared.setVoiceWeave(enabled: true, intervalSec: 10);
    cleared.clearVoice(0);
    final disabled = PureDartDsp()..start(SessionPreset.calmStim);
    disabled.loadVoice(0, _phrase());
    disabled.setVoiceWeave(enabled: false);
    final plain = PureDartDsp()..start(SessionPreset.calmStim);

    final p = _render(plain, 25);
    expect(_diffRms(_render(cleared, 25), p, 0, 25), 0);
    expect(_diffRms(_render(disabled, 25), p, 0, 25), 0);
  });

  test('hostile phrase data and arguments cannot break the ceiling or continuity', () {
    final e = PureDartDsp()..start(SessionPreset.deepCrisisAnchor);
    final bad = Float32List(_sr)..fillRange(0, _sr, 1e9);
    bad[100] = double.nan;
    e.loadVoice(1, bad);
    e.loadVoice(99, bad); // invalid slot ignored
    e.loadVoice(-1, bad);
    e.setVoiceWeave(enabled: true, gain: 99, intervalSec: 0);
    final a = _render(e, 40);
    var peak = 0.0, maxDelta = 0.0;
    for (var i = 0; i < a.length; i++) {
      expect(a[i].isFinite, isTrue);
      peak = math.max(peak, a[i].abs());
      if (i >= 2) maxDelta = math.max(maxDelta, (a[i] - a[i - 2]).abs());
    }
    expect(peak, lessThanOrEqualTo(AudioEngine.ceilingLinear));
    expect(maxDelta, lessThan(0.005));
  });

  test('phrases longer than 6 s are truncated, not rejected', () {
    final e = PureDartDsp();
    expect(() => e.loadVoice(0, Float32List(VoiceWeaveEngine.maxFrames * 2)), returnsNormally);
  });
}
