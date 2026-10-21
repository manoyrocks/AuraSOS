import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_engine.dart';

/// Offline processor for a parent's recorded voice (mono Float32 PCM).
///
/// Chain: peak normalisation -> split-band de-esser (sibilance above [deEssCutoffHz] is
/// compressed when it rises over [deEssThreshold]) -> peak normalisation to [targetPeak] -> short
/// raised-cosine fades so playback never starts or ends with a step.
class FamiliarVoiceProcessor {
  const FamiliarVoiceProcessor({
    this.sampleRate = AudioEngine.sampleRate,
    this.deEssCutoffHz = 4000.0,
    this.deEssThreshold = 0.03,
    this.deEssRatio = 6.0,
    this.maxReduction = 0.15,
    this.targetPeak = 0.5,
    this.fadeMs = 10.0,
  });

  final int sampleRate;
  final double deEssCutoffHz;

  /// Linear level of the >cutoff band above which attenuation starts.
  final double deEssThreshold;
  final double deEssRatio;

  /// Lowest gain the de-esser may apply to the sibilance band (linear).
  final double maxReduction;

  /// Peak after normalisation, clamped to the acoustic ceiling.
  final double targetPeak;
  final double fadeMs;

  /// Returns a new buffer; [input] is left untouched.
  Float32List process(Float32List input) {
    final n = input.length;
    final out = Float32List(n);
    if (n == 0) return out;

    final x = Float64List(n);
    for (var i = 0; i < n; i++) {
      final v = input[i];
      x[i] = v.isFinite ? v : 0.0;
    }

    _normalize(x);
    _deEss(x);
    _normalize(x);
    _fade(x);

    for (var i = 0; i < n; i++) {
      out[i] = x[i];
    }
    return out;
  }

  void _deEss(Float64List x) {
    final fc = math.min(deEssCutoffHz, 0.45 * sampleRate);
    final g = math.tan(math.pi * fc / sampleRate);
    const k = 1.4142135623730951; // 1 / Q, Butterworth
    final a1 = 1.0 / (1.0 + g * (g + k));
    final a2 = g * a1;
    final a3 = g * a2;
    // Two cascaded high-pass sections for a steeper split.
    var s1a = 0.0, s2a = 0.0, s1b = 0.0, s2b = 0.0;
    var env = 0.0;
    final attack = 1.0 - math.exp(-1.0 / (0.001 * sampleRate));
    final release = 1.0 - math.exp(-1.0 / (0.030 * sampleRate));
    final slope = 1.0 - 1.0 / math.max(1.0, deEssRatio);

    for (var i = 0; i < x.length; i++) {
      final v = x[i];
      final v3a = v - s2a;
      final v1a = a1 * s1a + a2 * v3a;
      final v2a = s2a + a2 * s1a + a3 * v3a;
      s1a = 2.0 * v1a - s1a;
      s2a = 2.0 * v2a - s2a;
      final h1 = v - k * v1a - v2a;

      final v3b = h1 - s2b;
      final v1b = a1 * s1b + a2 * v3b;
      final v2b = s2b + a2 * s1b + a3 * v3b;
      s1b = 2.0 * v1b - s1b;
      s2b = 2.0 * v2b - s2b;
      final sib = h1 - k * v1b - v2b;

      final level = sib.abs();
      env += (level - env) * (level > env ? attack : release);
      var gain = 1.0;
      if (env > deEssThreshold) {
        gain = math.pow(deEssThreshold / env, slope).toDouble();
        if (gain < maxReduction) gain = maxReduction;
      }
      x[i] = (v - sib) + sib * gain;
    }
  }

  void _normalize(Float64List x) {
    var peak = 0.0;
    for (final v in x) {
      final a = v.abs();
      if (a > peak) peak = a;
    }
    if (peak < 1e-9) return;
    final target = math.min(targetPeak, AudioEngine.ceilingLinear);
    final gain = target / peak;
    for (var i = 0; i < x.length; i++) {
      x[i] *= gain;
    }
  }

  void _fade(Float64List x) {
    final len = math.min((fadeMs * 0.001 * sampleRate).round(), x.length ~/ 2);
    for (var i = 0; i < len; i++) {
      final w = 0.5 * (1.0 - math.cos(math.pi * i / len));
      x[i] *= w;
      x[x.length - 1 - i] *= w;
    }
  }
}
