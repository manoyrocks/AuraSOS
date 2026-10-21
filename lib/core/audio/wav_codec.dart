import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_engine.dart';

/// Decoded mono audio and the rate it was recorded at.
class WavData {
  const WavData(this.samples, this.sampleRate);

  final Float32List samples;
  final int sampleRate;
}

/// Parses a RIFF/WAVE file holding 16-bit PCM. Multi-channel input is averaged to mono.
/// Throws [FormatException] for anything malformed, truncated or unsupported.
WavData decodeWav16Mono(Uint8List bytes) {
  if (bytes.length < 12) throw const FormatException('WAV too short');
  final ByteData d = ByteData.sublistView(bytes);
  if (_tag(bytes, 0) != 'RIFF' || _tag(bytes, 8) != 'WAVE') {
    throw const FormatException('Not a RIFF/WAVE file');
  }
  int? rate;
  int channels = 0;
  int bits = 0;
  int format = 0;
  var pos = 12;
  while (pos + 8 <= bytes.length) {
    final String id = _tag(bytes, pos);
    final int size = d.getUint32(pos + 4, Endian.little);
    final int body = pos + 8;
    if (id == 'fmt ') {
      if (size < 16 || body + 16 > bytes.length) {
        throw const FormatException('Bad fmt chunk');
      }
      format = d.getUint16(body, Endian.little);
      channels = d.getUint16(body + 2, Endian.little);
      rate = d.getUint32(body + 4, Endian.little);
      bits = d.getUint16(body + 14, Endian.little);
      if (format == 0xFFFE && size >= 26 && body + 26 <= bytes.length) {
        format = d.getUint16(body + 24, Endian.little);
      }
    } else if (id == 'data') {
      if (rate == null) {
        throw const FormatException('data chunk before fmt chunk');
      }
      if (format != 1 || bits != 16) {
        throw const FormatException('Only 16-bit PCM is supported');
      }
      if (channels < 1 || channels > 8) {
        throw const FormatException('Bad channel count');
      }
      if (rate < 1000 || rate > 384000) {
        throw const FormatException('Bad sample rate');
      }
      final int available = bytes.length - body;
      // Streaming writers leave 0 or 0xFFFFFFFF here; clamp to what is really present.
      final int len = (size == 0 || size > available) ? available : size;
      final int frames = len ~/ (2 * channels);
      if (frames == 0) throw const FormatException('WAV has no audio');
      final Float32List out = Float32List(frames);
      var p = body;
      for (var i = 0; i < frames; i++) {
        var acc = 0;
        for (var c = 0; c < channels; c++) {
          acc += d.getInt16(p, Endian.little);
          p += 2;
        }
        out[i] = acc / channels / 32768.0;
      }
      return WavData(out, rate);
    }
    if (size > bytes.length) break;
    pos = body + size + (size & 1);
  }
  throw const FormatException('No audio data found');
}

/// Writes a canonical 44-byte-header 16-bit mono PCM WAV. Samples are clamped to [-1, 1].
Uint8List encodeWav16Mono(Float32List samples, int sampleRate) {
  if (sampleRate <= 0) throw ArgumentError.value(sampleRate, 'sampleRate');
  final int dataLen = samples.length * 2;
  final Uint8List out = Uint8List(44 + dataLen);
  final ByteData d = ByteData.sublistView(out);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      out[at + i] = s.codeUnitAt(i);
    }
  }

  tag(0, 'RIFF');
  d.setUint32(4, 36 + dataLen, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  d.setUint32(16, 16, Endian.little);
  d.setUint16(20, 1, Endian.little);
  d.setUint16(22, 1, Endian.little);
  d.setUint32(24, sampleRate, Endian.little);
  d.setUint32(28, sampleRate * 2, Endian.little);
  d.setUint16(32, 2, Endian.little);
  d.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  d.setUint32(40, dataLen, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final double v = samples[i];
    final double c = v.isFinite ? v.clamp(-1.0, 1.0).toDouble() : 0.0;
    d.setInt16(44 + 2 * i, (c * 32767.0).round(), Endian.little);
  }
  return out;
}

/// Resamples to 48 kHz with a windowed-sinc kernel (anti-aliased when downsampling).
Float32List resampleTo48k(Float32List input, int fromRate) {
  if (fromRate <= 0) throw ArgumentError.value(fromRate, 'fromRate');
  const int to = AudioEngine.sampleRate;
  if (fromRate == to || input.isEmpty) return Float32List.fromList(input);
  final int outLen = math.max(1, (input.length * to / fromRate).round());
  final Float32List out = Float32List(outLen);
  final double step = fromRate / to;
  // Cutoff relative to the input Nyquist; lowered when downsampling to avoid aliasing.
  final double cutoff = math.min(1.0, to / fromRate) * 0.97;
  const int taps = 12;
  final double half = taps * math.max(1.0, 1.0 / cutoff);
  for (var i = 0; i < outLen; i++) {
    final double t = i * step;
    final int lo = math.max(0, (t - half).ceil());
    final int hi = math.min(input.length - 1, (t + half).floor());
    var acc = 0.0;
    var norm = 0.0;
    for (var j = lo; j <= hi; j++) {
      final double x = j - t;
      final double u = x * cutoff;
      final double sinc = u == 0 ? 1.0 : math.sin(math.pi * u) / (math.pi * u);
      final double w = 0.5 * (1.0 + math.cos(math.pi * x / half));
      final double k = sinc * w;
      acc += input[j] * k;
      norm += k;
    }
    out[i] = norm.abs() < 1e-9 ? 0.0 : acc / norm;
  }
  return out;
}

String _tag(Uint8List b, int at) => String.fromCharCodes(b, at, at + 4);
