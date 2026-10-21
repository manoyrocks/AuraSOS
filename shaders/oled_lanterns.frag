// OLED lanterns: pure black background (vec3(0.0)) with a few dim, slowly rising warm lanterns.
// Uniform float order (setFloat indices): uSize.x=0 uSize.y=1, uTime=2, uSpeed=3, uDim=4,
// uTouch.x=5 uTouch.y=6 uTouch.z=7 (z = touch age 0..1; >= 1 means no active touch).
// uTime is already scaled by speed on the Dart side. All luminance modulation is < 0.2 Hz.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uSpeed;
uniform float uDim;
uniform vec3 uTouch;

out vec4 fragColor;

float hash11(float n) {
  return fract(sin(n * 127.1) * 43758.5453);
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  float aspect = uSize.x / max(uSize.y, 1.0);
  vec2 uv = fc / max(uSize, vec2(1.0));
  vec2 p = vec2(uv.x * aspect, uv.y);

  vec3 col = vec3(0.0);

  for (int i = 0; i < 6; i++) {
    float fi = float(i);
    float h1 = hash11(fi + 3.0);
    float h2 = hash11(fi + 41.0);
    float h3 = hash11(fi + 77.0);
    float radius = 0.10 + 0.07 * h1;
    float rise = 0.008 + 0.010 * h2;
    float y = 1.0 + radius - fract(h3 + uTime * rise) * (1.0 + 2.0 * radius);
    float x = (0.15 + 0.7 * h2) * aspect + sin(uTime * 0.2 + fi * 1.7) * 0.025;
    float d = length(p - vec2(x, y));
    // Compact support: exactly zero beyond radius, so untouched pixels stay pure black.
    float falloff = smoothstep(radius, 0.0, d);
    float core = falloff * falloff;
    // Slow flicker-free pulse, ~0.07 Hz.
    float pulse = 0.8 + 0.2 * sin(uTime * 0.45 + fi * 1.3);
    vec3 warm = mix(vec3(0.55, 0.20, 0.04), vec3(0.75, 0.38, 0.08), h1);
    col += warm * core * pulse * 0.55;
  }

  if (uTouch.z < 1.0) {
    float d = length(fc - uTouch.xy) / max(min(uSize.x, uSize.y), 1.0);
    float ringR = 0.03 + uTouch.z * 0.30;
    float ring = smoothstep(0.05, 0.0, abs(d - ringR));
    col += vec3(0.5, 0.25, 0.07) * ring * (1.0 - uTouch.z) * 0.5;
  }

  // Slower protocol speeds also soften overall intensity slightly.
  col *= mix(0.92, 1.0, clamp(uSpeed, 0.0, 1.0));
  col *= clamp(uDim, 0.0, 1.0);
  fragColor = vec4(col, 1.0);
}
