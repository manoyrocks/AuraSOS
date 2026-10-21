import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aurasync/core/audio/wav_codec.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List sine(double hz, int rate, int n) => Float32List.fromList(
    List<double>.generate(n, (i) => 0.5 * math.sin(2 * math.pi * hz * i / rate)));

/// Dominant frequency via zero-crossing count.
double estimateHz(Float32List x, int rate) {
  var crossings = 0;
  for (var i = 1; i < x.length; i++) {
    if (x[i - 1] < 0 && x[i] >= 0) crossings++;
  }
  return crossings * rate / x.length;
}

void main() {
  test('encode/decode round-trips within 16-bit quantisation', () {
    final src = sine(440, 16000, 8000);
    final wav = decodeWav16Mono(encodeWav16Mono(src, 16000));
    expect(wav.sampleRate, 16000);
    expect(wav.samples.length, src.length);
    for (var i = 0; i < src.length; i++) {
      expect(wav.samples[i], closeTo(src[i], 1e-4));
    }
  });

  test('encode clamps and sanitises out-of-range samples', () {
    final wav = decodeWav16Mono(
        encodeWav16Mono(Float32List.fromList([2.0, -2.0, double.nan]), 48000));
    expect(wav.samples[0], closeTo(1.0, 1e-3));
    expect(wav.samples[1], closeTo(-1.0, 1e-3));
    expect(wav.samples[2], 0.0);
  });

  test('stereo input is averaged to mono', () {
    final bytes = encodeWav16Mono(Float32List.fromList([0.5, 0.5]), 48000);
    final b = ByteData.sublistView(bytes);
    b.setUint16(22, 2, Endian.little); // two channels: frames become (0.5, 0.5)
    final wav = decodeWav16Mono(bytes);
    expect(wav.samples.length, 1);
    expect(wav.samples[0], closeTo(0.5, 1e-3));
  });

  test('resample length and pitch are preserved', () {
    for (final rate in [16000, 44100]) {
      final out = resampleTo48k(sine(500, rate, rate), rate);
      expect(out.length, 48000);
      expect(estimateHz(out, 48000), closeTo(500, 3));
      expect(out.reduce(math.max), closeTo(0.5, 0.02));
    }
  });

  test('resample at 48 kHz is identity and empty input is empty', () {
    final src = sine(300, 48000, 100);
    expect(resampleTo48k(src, 48000), orderedEquals(src));
    expect(resampleTo48k(Float32List(0), 16000), isEmpty);
  });

  test('malformed input throws FormatException', () {
    final good = encodeWav16Mono(sine(440, 48000, 100), 48000);
    expect(() => decodeWav16Mono(Uint8List(0)), throwsFormatException);
    expect(() => decodeWav16Mono(Uint8List(11)), throwsFormatException);
    expect(() => decodeWav16Mono(Uint8List(100)), throwsFormatException);
    expect(() => decodeWav16Mono(Uint8List.sublistView(good, 0, 30)), throwsFormatException);
    expect(() => decodeWav16Mono(Uint8List.sublistView(good, 0, 44)), throwsFormatException);
    final eightBit = Uint8List.fromList(good);
    ByteData.sublistView(eightBit).setUint16(34, 8, Endian.little);
    expect(() => decodeWav16Mono(eightBit), throwsFormatException);
    final noFmt = Uint8List.fromList(good)..setRange(12, 16, 'junk'.codeUnits);
    expect(() => decodeWav16Mono(noFmt), throwsFormatException);
  });

  test('truncated data chunk decodes what is present', () {
    final good = encodeWav16Mono(sine(440, 48000, 100), 48000);
    final wav = decodeWav16Mono(Uint8List.sublistView(good, 0, 44 + 50 * 2 + 1));
    expect(wav.samples.length, 50);
  });
}
