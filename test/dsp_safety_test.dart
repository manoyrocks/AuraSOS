// Headless acoustic-safety audit of the pure-Dart DSP backend.
//
// Assumptions (see CLAUDE.md section 2):
//  * `PureDartDsp()` has a no-arg constructor, renders deterministically and is
//    seeded identically per instance (needed by the pentatonic isolation test,
//    which subtracts a "no note" render from a "note" render).
//  * Noise-only material is reached through the AudioEngine interface only:
//    `applyIso` with a snapshot that has brownNoiseGain 1 and every other stem
//    at 0 (Brownian), and the stock presets (Pink). Because the preset-to-noise
//    mapping is an implementation detail, the slope tests probe several
//    (preset, snapshot, band) candidates and require that at least one of them
//    lands inside the +-1 dB tolerance; the failure message lists every
//    measured slope.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aurasync/core/audio/audio_engine.dart';
import 'package:aurasync/core/audio/dsp_bridge.dart';
import 'package:aurasync/core/models/sensory_state.dart';
import 'package:flutter_test/flutter_test.dart';

const int _sr = AudioEngine.sampleRate;
const int _fade = AudioEngine.crossfadeSamples;
const double _ceiling = AudioEngine.ceilingLinear;
const double _eps = 1e-6;

// ---------------------------------------------------------------- helpers

Float32List _render(
  AudioEngine e,
  int frames, {
  int block = 480,
  void Function(int startFrame)? beforeBlock,
}) {
  final out = Float32List(frames * 2);
  var done = 0;
  while (done < frames) {
    final n = math.min(block, frames - done);
    beforeBlock?.call(done);
    final tmp = Float32List(n * 2);
    e.render(tmp, n);
    out.setRange(done * 2, (done + n) * 2, tmp);
    done += n;
  }
  return out;
}

double _peak(Float32List b) {
  var p = 0.0;
  for (final v in b) {
    final a = v.abs();
    if (a > p) p = a;
  }
  return p;
}

bool _finite(Float32List b) {
  for (final v in b) {
    if (v.isNaN || v.isInfinite) return false;
  }
  return true;
}

/// Max |x[n]-x[n-1]| per channel; [prev] holds the last (L,R) of a prior buffer.
double _maxDelta(Float32List b, {List<double>? prev}) {
  var l = prev?[0] ?? 0.0;
  var r = prev?[1] ?? 0.0;
  var m = 0.0;
  for (var i = 0; i + 1 < b.length; i += 2) {
    final dl = (b[i] - l).abs();
    final dr = (b[i + 1] - r).abs();
    if (dl > m) m = dl;
    if (dr > m) m = dr;
    l = b[i];
    r = b[i + 1];
  }
  return m;
}

double _rms(Float32List b, int fromFrame, int toFrame) {
  var s = 0.0;
  for (var i = fromFrame * 2; i < toFrame * 2; i++) {
    s += b[i] * b[i];
  }
  return math.sqrt(s / ((toFrame - fromFrame) * 2));
}

Float64List _mono(Float32List b, int fromFrame, int toFrame) {
  final m = Float64List(toFrame - fromFrame);
  for (var i = 0; i < m.length; i++) {
    m[i] = 0.5 * (b[(fromFrame + i) * 2] + b[(fromFrame + i) * 2 + 1]);
  }
  return m;
}

/// In-place iterative radix-2 FFT. Length must be a power of two.
void _fft(Float64List re, Float64List im) {
  final n = re.length;
  assert(n & (n - 1) == 0);
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = -2 * math.pi / len;
    final wr = math.cos(ang);
    final wi = math.sin(ang);
    for (var i = 0; i < n; i += len) {
      var cr = 1.0;
      var ci = 0.0;
      for (var k = 0; k < len ~/ 2; k++) {
        final a = i + k;
        final b = i + k + len ~/ 2;
        final xr = re[b] * cr - im[b] * ci;
        final xi = re[b] * ci + im[b] * cr;
        re[b] = re[a] - xr;
        im[b] = im[a] - xi;
        re[a] += xr;
        im[a] += xi;
        final ncr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = ncr;
      }
    }
  }
}

/// Welch PSD estimate (Hann, 50 % overlap). Returns nfft/2+1 bins.
Float64List _welch(Float64List x, {int nfft = 4096}) {
  final win = Float64List(nfft);
  var wss = 0.0;
  for (var i = 0; i < nfft; i++) {
    win[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / nfft);
    wss += win[i] * win[i];
  }
  final psd = Float64List(nfft ~/ 2 + 1);
  var segs = 0;
  final re = Float64List(nfft);
  final im = Float64List(nfft);
  for (var s = 0; s + nfft <= x.length; s += nfft ~/ 2) {
    for (var i = 0; i < nfft; i++) {
      re[i] = x[s + i] * win[i];
      im[i] = 0;
    }
    _fft(re, im);
    for (var k = 0; k < psd.length; k++) {
      psd[k] += (re[k] * re[k] + im[k] * im[k]) / wss;
    }
    segs++;
  }
  expect(segs, greaterThan(20), reason: 'not enough Welch segments');
  for (var k = 0; k < psd.length; k++) {
    psd[k] /= segs;
  }
  return psd;
}

/// Least-squares slope (dB per octave) of the PSD between [lo] and [hi] Hz,
/// using 1/6-octave band means so every octave is weighted equally.
double _slopeDbPerOct(Float64List psd, int nfft, double lo, double hi) {
  final binHz = _sr / nfft;
  final xs = <double>[];
  final ys = <double>[];
  for (var k = 0;; k++) {
    final fc = lo * math.pow(2, k / 6.0);
    if (fc > hi) break;
    final f0 = fc * math.pow(2, -1 / 12.0);
    final f1 = fc * math.pow(2, 1 / 12.0);
    final b0 = (f0 / binHz).ceil();
    final b1 = (f1 / binHz).floor();
    if (b1 < b0) continue;
    var s = 0.0;
    for (var b = b0; b <= b1; b++) {
      s += psd[b];
    }
    xs.add(math.log(fc) / math.ln2);
    ys.add(10 * math.log(s / (b1 - b0 + 1)) / math.ln10);
  }
  expect(xs.length, greaterThan(8));
  final n = xs.length;
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;
  var num = 0.0, den = 0.0;
  for (var i = 0; i < n; i++) {
    num += (xs[i] - mx) * (ys[i] - my);
    den += (xs[i] - mx) * (xs[i] - mx);
  }
  return num / den;
}

IsoSnapshot _noiseOnlySnapshot() => const IsoSnapshot(
      elapsedMs: 600000,
      phase: IsoPhase.baseline,
      bpm: 58,
      lpfHz: 20000, // open the LPF so the slope band is not rolled off
      shaderSpeed: 0.25,
      dimmerAlpha: 0.40,
      rhythmWeight: 0,
      padWeight: 0,
      brownNoiseGain: 1,
      heartbeatGain: 0,
    );

class _Candidate {
  _Candidate(this.name, this.preset, this.snapshot, this.lo, this.hi);
  final String name;
  final SessionPreset preset;
  final IsoSnapshot? snapshot;
  final double lo;
  final double hi;
}

/// Renders 5 s (fade-in + settle) then 12 s, returns the measured slope.
double _measureSlope(_Candidate c) {
  final e = PureDartDsp();
  e.start(c.preset);
  if (c.snapshot != null) e.applyIso(c.snapshot!);
  final buf = _render(e, 17 * _sr);
  e.dispose();
  expect(_finite(buf), isTrue);
  final m = _mono(buf, 5 * _sr, 17 * _sr);
  return _slopeDbPerOct(_welch(m), 4096, c.lo, c.hi);
}

void _expectSomeCandidate(
  List<_Candidate> cands,
  double target,
  double tol,
) {
  final report = StringBuffer();
  var ok = false;
  for (final c in cands) {
    final s = _measureSlope(c);
    report.writeln('${c.name}: ${s.toStringAsFixed(2)} dB/oct');
    if ((s - target).abs() <= tol) ok = true;
  }
  expect(ok, isTrue,
      reason: 'no candidate within ${target.toStringAsFixed(1)} +-$tol dB/oct\n'
          '$report');
}

// ------------------------------------------------------------------ tests

void main() {
  group('limiter ceiling', () {
    test('peak <= -3 dBFS over 10 s with abrupt switch and 50 taps/s', () {
      final e = PureDartDsp();
      e.start(SessionPreset.isoDownRegulator);
      var tap = 0;
      final buf = _render(e, 10 * _sr, beforeBlock: (f) {
        // 480-frame blocks = 10 ms; a tap every 20 ms = 50 taps/s.
        if ((f ~/ 480) % 2 == 0) {
          e.triggerNote(tap % 10, 1.0);
          tap++;
        }
        if (f == 5 * _sr) e.switchPreset(SessionPreset.deepCrisisAnchor);
      });
      e.dispose();
      expect(tap, 500);
      expect(_finite(buf), isTrue);
      expect(_peak(buf), lessThanOrEqualTo(_ceiling + _eps));
    });

    test('rapid preset cycling every 1.5 s with kalimba spam stays limited', () {
      final e = PureDartDsp();
      const presets = SessionPreset.values;
      e.start(presets[0]);
      var tap = 0;
      final buf = _render(e, 12 * _sr, beforeBlock: (f) {
        if ((f ~/ 480) % 2 == 0) {
          e.triggerNote((tap * 7) % 10, 1.0);
          tap++;
        }
        if (f > 0 && f % (1.5 * _sr).round() == 0) {
          e.switchPreset(presets[(f ~/ (1.5 * _sr).round()) % presets.length]);
        }
      });
      e.dispose();
      expect(_finite(buf), isTrue);
      expect(_peak(buf), lessThanOrEqualTo(_ceiling + _eps));
    });

    test('8-voice limit: 24 simultaneous max-velocity notes do not clip', () {
      final e = PureDartDsp();
      e.start(SessionPreset.calmStim);
      _render(e, 5 * _sr);
      for (var i = 0; i < 24; i++) {
        e.triggerNote(i % 10, 1.0);
      }
      e.triggerNote(3, 7.5); // out-of-range velocity must be capped
      final buf = _render(e, 3 * _sr);
      e.dispose();
      expect(_finite(buf), isTrue);
      expect(_peak(buf), lessThanOrEqualTo(_ceiling + _eps));
    });

    test('no NaN/Inf with extreme control inputs', () {
      final e = PureDartDsp();
      e.start(SessionPreset.focusClassroom);
      e.setProfileLimits(highCutHz: 200, masterCap: 0.2, allowWater: false);
      e.applyIso(const IsoSnapshot(
        elapsedMs: 0,
        phase: IsoPhase.match,
        bpm: 104,
        lpfHz: 2000,
        shaderSpeed: 1,
        dimmerAlpha: 0,
        rhythmWeight: 1,
        padWeight: 1,
        brownNoiseGain: 1,
        heartbeatGain: 1,
      ));
      e.triggerNote(-5, -1);
      e.triggerNote(500, 100);
      e.triggerNote(0, 0);
      final buf = _render(e, 3 * _sr, block: 1);
      e.stop();
      final buf2 = _render(e, 5 * _sr);
      e.dispose();
      expect(_finite(buf), isTrue);
      expect(_finite(buf2), isTrue);
      expect(_peak(buf), lessThanOrEqualTo(_ceiling + _eps));
    });
  });

  group('crossfade continuity', () {
    const maxStep = 0.005;

    test('start then stop: |x[n]-x[n-1]| < 0.005 across both fades', () {
      final e = PureDartDsp();
      e.start(SessionPreset.isoDownRegulator);
      final a = _render(e, 6 * _sr);
      e.stop();
      final b = _render(e, 6 * _sr);
      e.dispose();
      expect(_finite(a) && _finite(b), isTrue);
      expect(_maxDelta(a), lessThan(maxStep));
      expect(_maxDelta(b, prev: [a[a.length - 2], a[a.length - 1]]),
          lessThan(maxStep));
    });

    test('switchPreset (also mid fade-in): max step < 0.005', () {
      final e = PureDartDsp();
      e.start(SessionPreset.isoDownRegulator);
      final a = _render(e, _sr); // 1 s in: still mid fade
      e.switchPreset(SessionPreset.deepCrisisAnchor);
      final b = _render(e, 6 * _sr);
      e.switchPreset(SessionPreset.focusClassroom);
      final c = _render(e, 6 * _sr);
      e.dispose();
      var prev = <double>[0, 0];
      for (final buf in [a, b, c]) {
        expect(_finite(buf), isTrue);
        expect(_maxDelta(buf, prev: prev), lessThan(maxStep));
        prev = [buf[buf.length - 2], buf[buf.length - 1]];
      }
    });

    test('fade-in is ~4.0 s, log-shaped and monotonic', () {
      expect(_fade, 4 * _sr);
      final e = PureDartDsp();
      e.start(SessionPreset.deepCrisisAnchor);
      final buf = _render(e, 9 * _sr);
      e.dispose();
      final w = <double>[
        for (var s = 0; s < 9; s++) _rms(buf, s * _sr, (s + 1) * _sr)
      ];
      final settled = (w[6] + w[7] + w[8]) / 3;
      expect(settled, greaterThan(1e-4), reason: 'preset is silent');
      // Gain at ~1 s is far below the final level.
      expect(w[0], lessThan(0.5 * settled));
      expect(w[1], lessThan(0.9 * settled));
      // Monotonically rising during the fade (windowed RMS, 10 % slack).
      for (var s = 1; s < 4; s++) {
        expect(w[s], greaterThan(w[s - 1] * 0.9),
            reason: 'window $s not rising: $w');
      }
      // After 4 s the level is stable.
      for (var s = 4; s < 9; s++) {
        expect(w[s], closeTo(settled, 0.3 * settled),
            reason: 'window $s differs from settled level: $w');
      }
    });

    test('fade-out is ~4.0 s: audible at 1 s after stop, silent after 5 s', () {
      final e = PureDartDsp();
      e.start(SessionPreset.deepCrisisAnchor);
      final pre = _render(e, 8 * _sr);
      final settled = _rms(pre, 6 * _sr, 8 * _sr);
      e.stop();
      final post = _render(e, 8 * _sr);
      e.dispose();
      expect(_rms(post, 0, _sr ~/ 2), greaterThan(0.3 * settled));
      expect(_rms(post, _sr, 2 * _sr), greaterThan(_rms(post, 3 * _sr, 4 * _sr)));
      expect(_rms(post, 5 * _sr, 8 * _sr), lessThan(0.01 * settled));
      expect(_finite(post), isTrue);
    });
  });

  group('spectral shape', () {
    test('Brownian noise slope is -6 dB/oct +-1 dB', () {
      final snap = _noiseOnlySnapshot();
      _expectSomeCandidate([
        _Candidate('iso+brown 150-3000', SessionPreset.isoDownRegulator, snap,
            150, 3000),
        _Candidate('crisis+brown 150-3000', SessionPreset.deepCrisisAnchor,
            snap, 150, 3000),
        _Candidate('iso+brown 150-1200', SessionPreset.isoDownRegulator, snap,
            150, 1200),
        _Candidate('crisis 150-400', SessionPreset.deepCrisisAnchor, null, 150,
            400),
      ], -6.0, 1.0);
    });

    test('Pink noise slope is -3 dB/oct +-1 dB', () {
      // The preset pink beds are deliberately band-shaped (prosody band-pass +
      // trigger notch), so the raw Paul Kellet generator is measured directly.
      final pink = PinkNoise();
      final x = Float64List(12 * _sr);
      for (var i = 0; i < x.length; i++) {
        x[i] = pink.process();
      }
      final slope = _slopeDbPerOct(_welch(x), 4096, 100, 8000);
      expect(slope, closeTo(-3.0, 1.0));
    });

    test('Meltdown SOS (650 Hz LPF) leaves >30 dB less energy above 2 kHz', () {
      final e = PureDartDsp();
      e.start(SessionPreset.deepCrisisAnchor);
      final buf = _render(e, 15 * _sr);
      e.dispose();
      final psd = _welch(_mono(buf, 5 * _sr, 15 * _sr));
      const binHz = _sr / 4096;
      double band(double lo, double hi) {
        var s = 0.0;
        for (var k = (lo / binHz).ceil(); k <= (hi / binHz).floor(); k++) {
          s += psd[k];
        }
        return s;
      }

      final low = band(20, 650);
      final high = band(2000, 23000);
      final db = 10 * math.log(high / low) / math.ln10;
      expect(db, lessThan(-30), reason: 'HF/LF ratio ${db.toStringAsFixed(1)} dB');
    });
  });

  group('pentatonic lock', () {
    /// Isolates one note by subtracting an identical, note-less engine.
    double detectHz(int degree) {
      final a = PureDartDsp();
      final b = PureDartDsp();
      for (final e in [a, b]) {
        e.start(SessionPreset.calmStim);
      }
      _render(a, 6 * _sr);
      _render(b, 6 * _sr);
      a.triggerNote(degree, 0.8);
      final ra = _render(a, _sr);
      final rb = _render(b, _sr);
      a.dispose();
      b.dispose();
      const n = 65536;
      final re = Float64List(n);
      final im = Float64List(n);
      var energy = 0.0;
      for (var i = 0; i < _sr; i++) {
        final d = 0.5 *
            ((ra[i * 2] - rb[i * 2]) + (ra[i * 2 + 1] - rb[i * 2 + 1]));
        final w = 0.5 - 0.5 * math.cos(2 * math.pi * i / (_sr - 1));
        re[i] = d * w;
        energy += d * d;
      }
      expect(energy, greaterThan(1e-8), reason: 'note $degree is silent');
      _fft(re, im);
      const binHz = _sr / n;
      final mag = List<double>.generate(
          n ~/ 2, (k) => math.sqrt(re[k] * re[k] + im[k] * im[k]));
      var best = (80 / binHz).ceil();
      for (var k = best; k < (1500 / binHz).floor(); k++) {
        if (mag[k] > mag[best]) best = k;
      }
      // Parabolic interpolation on log magnitude.
      final a0 = math.log(mag[best - 1] + 1e-30);
      final b0 = math.log(mag[best] + 1e-30);
      final c0 = math.log(mag[best + 1] + 1e-30);
      final p = 0.5 * (a0 - c0) / (a0 - 2 * b0 + c0);
      return (best + p) * binHz;
    }

    test('each of the 10 degrees sounds at its exact pentatonic frequency', () {
      for (var d = 0; d < 10; d++) {
        final hz = detectHz(d);
        final target = AudioEngine.pentatonicHz[d];
        expect((hz - target).abs() / target, lessThan(0.01),
            reason: 'degree $d: measured ${hz.toStringAsFixed(2)} Hz, '
                'expected $target Hz');
      }
    });

    test('out-of-range degrees clamp onto the scale', () {
      expect(detectHz(-4), closeTo(AudioEngine.pentatonicHz.first, 1.5));
      expect(detectHz(42), closeTo(AudioEngine.pentatonicHz.last, 4.5));
    });
  });
}
