// Aurora ribbons: layered translucent curtains of teal, violet and rose drifting slowly over
// a still, dark water reflection. Nearer layers move more than distant ones (parallax depth).
// A touch sends a soft ripple through the colour.
// Uniform float order (setFloat indices): uSize.x=0 uSize.y=1, uTime=2, uSpeed=3, uDim=4,
// uTouch.x=5 uTouch.y=6 uTouch.z=7 (z = touch age 0..1; >= 1 means no active touch).
// Ribbon motion is at most 0.15 rad/s (0.024 Hz); no luminance modulation is faster.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uSpeed;
uniform float uDim;
uniform vec3 uTouch;

out vec4 fragColor;

vec3 ribbons(vec2 p, float t) {
  vec3 acc = vec3(0.0);
  for (int k = 0; k < 4; k++) {
    float fk = float(k);
    float near = 1.0 - fk / 4.0; // 1 = closest layer
    float amp = mix(0.03, 0.09, near);
    float freq = mix(2.4, 3.6, 1.0 - near) + fk * 0.35;
    float drift = t * (0.05 + near * 0.10);
    float base = 0.20 + fk * 0.09;
    float curve = base + amp * sin(p.x * freq + drift + fk * 1.7) +
                  0.5 * amp * sin(p.x * freq * 2.3 - drift * 0.7 + fk);
    float dist = p.y - curve;
    // A curtain: brightest along its lower edge, melting upward into the dark.
    float body = smoothstep(-0.018, 0.0, dist) * exp(-max(dist, 0.0) * mix(2.4, 4.2, 1.0 - near));
    float streak = 0.80 + 0.20 * sin(p.x * 38.0 + fk * 3.0 + t * 0.03);
    vec3 hue = mix(vec3(0.16, 0.82, 0.66), vec3(0.56, 0.38, 0.94), clamp(fk / 3.0 + 0.25 * sin(p.x * 2.0 + t * 0.04), 0.0, 1.0));
    hue = mix(hue, vec3(0.96, 0.52, 0.74), smoothstep(0.55, 1.0, 0.5 + 0.5 * sin(p.x * 1.3 + t * 0.03 + fk)) * 0.4);
    acc += hue * body * streak * mix(0.42, 0.85, near);
  }
  return acc;
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec2 p = fc / max(uSize, vec2(1.0));
  p.y = 1.0 - p.y; // y up, 0 at the bottom
  float m = max(min(uSize.x, uSize.y), 1.0);
  p.x = (p.x - 0.5) * (uSize.x / m) * 0.9 + 0.5;

  float horizon = 0.24;
  float t = uTime;

  vec3 sky = mix(vec3(0.030, 0.040, 0.090), vec3(0.006, 0.008, 0.026), smoothstep(0.2, 1.0, p.y));
  vec3 col = sky;

  if (p.y >= horizon) {
    vec2 q = vec2(p.x, (p.y - horizon) / (1.0 - horizon));
    col += ribbons(q, t);
  } else {
    // Still, dark water mirroring the sky above, rippled very slightly.
    float depth = (horizon - p.y) / horizon;
    vec2 q = vec2(p.x + sin(p.y * 36.0 + t * 0.12) * 0.005 * depth, depth * 0.62);
    col = mix(vec3(0.012, 0.018, 0.042), sky, 0.5) + ribbons(q, t) * (0.40 * (1.0 - depth * 0.7));
  }

  // Touch: a slow soft ripple of light.
  if (uTouch.z < 1.0) {
    float d = length((fc - uTouch.xy) / m);
    float ringR = 0.05 + uTouch.z * 0.4;
    float ring = smoothstep(0.08, 0.0, abs(d - ringR));
    col += vec3(0.35, 0.80, 0.75) * ring * (1.0 - uTouch.z) * 0.45;
  }

  col *= smoothstep(1.4, 0.35, length((fc / uSize - 0.5) * vec2(1.0, 1.1)));
  // Slower protocol speeds also soften overall intensity slightly.
  col *= mix(0.92, 1.0, clamp(uSpeed, 0.0, 1.0));
  col *= clamp(uDim, 0.0, 1.0);
  fragColor = vec4(col, 1.0);
}
