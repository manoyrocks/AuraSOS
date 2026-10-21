import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const shaders = [
    'bioluminescent_tunnel',
    'classroom_bubbles',
    'oled_lanterns',
    'breathing_orb',
    'crystal_polygons',
    'starfield_3d',
    'aurora_ribbons',
    'mandala_polygons',
  ];

  for (final name in shaders) {
    group(name, () {
      late String src;
      setUpAll(() => src = File('shaders/$name.frag').readAsStringSync());

      test('is Impeller-compatible GLSL with the shared uniforms', () {
        expect(src, contains('#version 460 core'));
        expect(src, contains('#include <flutter/runtime_effect.glsl>'));
        for (final u in [
          'uniform vec2 uSize;',
          'uniform float uTime;',
          'uniform float uSpeed;',
          'uniform float uDim;',
          'uniform vec3 uTouch;',
        ]) {
          expect(src, contains(u), reason: 'missing $u');
        }
        expect(src, contains('out vec4 fragColor'));
      });

      test('never strobes: no high-frequency time modulation', () {
        // Any sin/cos of uTime multiplied by a factor > 1.2 rad/s would exceed 0.2 Hz.
        final timeTerms = RegExp(r'(?:sin|cos)\s*\(([^;]*?)uTime([^;]*?)\)');
        for (final m in timeTerms.allMatches(src)) {
          final expr = m.group(0)!;
          for (final k in RegExp(r'uTime\s*\*\s*([0-9.]+)|([0-9.]+)\s*\*\s*uTime')
              .allMatches(expr)) {
            final factor = double.parse(k.group(1) ?? k.group(2)!);
            expect(factor, lessThanOrEqualTo(1.2),
                reason: 'fast oscillation in `$expr` (> 0.2 Hz)');
          }
        }
      });
    });
  }

  test('OLED lanterns background is exactly black', () {
    final src = File('shaders/oled_lanterns.frag').readAsStringSync();
    expect(src, contains('vec3(0.0)'));
  });

  test('breathing orb runs a 10 s cycle with a 4 s inhale', () {
    final src = File('shaders/breathing_orb.frag').readAsStringSync();
    expect(src, contains('mod(uTime'));
    expect(src, contains('10.0'));
    expect(src, contains('4.0'));
  });

  test('all shaders are registered in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final name in shaders) {
      expect(pubspec, contains('shaders/$name.frag'));
    }
  });
}
