// Bioluminescent tunnel: slow drifting teal/indigo glow flowing toward the viewer.
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

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

// Value noise whose x lattice repeats every `period` cells, so the angular coordinate can wrap
// around the tunnel without a visible seam.
float vnoiseP(vec2 p, float period) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float x0 = mod(i.x, period);
  float x1 = mod(i.x + 1.0, period);
  return mix(mix(hash(vec2(x0, i.y)), hash(vec2(x1, i.y)), u.x),
             mix(hash(vec2(x0, i.y + 1.0)), hash(vec2(x1, i.y + 1.0)), u.x), u.y);
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  float m = max(min(uSize.x, uSize.y), 1.0);
  vec2 uv = (fc - 0.5 * uSize) / m;

  float r = max(length(uv), 0.001);
  float a = atan(uv.y, uv.x);

  // Depth coordinate flows outward slowly (0.06 units/s of uTime).
  float depth = 0.28 / r - uTime * 0.06;
  vec2 q = vec2(a * 1.2732395 + sin(depth * 0.7) * 0.4, depth * 1.6);

  // q.x spans exactly 8 units around the circle: x2 -> 16 cells, x4 -> 32 cells, both wrap cleanly.
  float n = vnoiseP(q * 2.0, 16.0) * 0.6 + vnoiseP(q * 4.0 + vec2(7.1, 0.0), 32.0) * 0.4;
  float veins = smoothstep(0.52, 0.78, n);

  // Gentle breathing glow, period ~12.5 s (0.08 Hz).
  float breathe = 0.85 + 0.15 * sin(uTime * 0.5);

  vec3 deep = vec3(0.01, 0.03, 0.09);
  vec3 teal = vec3(0.05, 0.55, 0.62);
  vec3 violet = vec3(0.30, 0.22, 0.65);
  float hueMix = 0.5 + 0.5 * sin(depth * 0.9 + a);
  vec3 glow = mix(teal, violet, hueMix);

  vec3 col = deep + glow * veins * 0.55 * breathe;
  // Soft tunnel mouth in the center, vignette at the edges.
  col += vec3(0.02, 0.10, 0.14) * smoothstep(0.45, 0.0, r) * breathe;
  col *= smoothstep(1.1, 0.25, r) * 0.8 + 0.2;

  // Touch: a slow expanding soft ring.
  if (uTouch.z < 1.0) {
    float d = length(fc - uTouch.xy) / m;
    float ringR = 0.04 + uTouch.z * 0.35;
    float ring = smoothstep(0.07, 0.0, abs(d - ringR));
    col += vec3(0.25, 0.75, 0.80) * ring * (1.0 - uTouch.z) * 0.6;
  }

  // Slower protocol speeds also soften overall intensity slightly.
  col *= mix(0.92, 1.0, clamp(uSpeed, 0.0, 1.0));
  col *= clamp(uDim, 0.0, 1.0);
  fragColor = vec4(col, 1.0);
}
