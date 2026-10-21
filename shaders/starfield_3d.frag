// Starfield 3D: layers of soft stars drifting gently toward the viewer, with a slow camera
// roll for depth. A touch nudges the view. Stars fade in and out smoothly (never pop).
// Uniform float order (setFloat indices): uSize.x=0 uSize.y=1, uTime=2, uSpeed=3, uDim=4,
// uTouch.x=5 uTouch.y=6 uTouch.z=7 (z = touch age 0..1; >= 1 means no active touch).
// A star takes about 28 s to cross a layer, so brightness changes are far below 0.2 Hz.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uSpeed;
uniform float uDim;
uniform vec3 uTouch;

out vec4 fragColor;

float hash21(vec2 p) {
  p = fract(p * vec2(233.34, 851.73));
  p += dot(p, p + 23.45);
  return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
  float n = hash21(p);
  return vec2(n, hash21(p + n + 19.19));
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
             mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  float m = max(min(uSize.x, uSize.y), 1.0);
  vec2 uv = (fc - 0.5 * uSize) / m;

  // Slow camera roll, plus a gentle push away from a touch.
  float a = uTime * 0.012;
  uv = mat2(cos(a), -sin(a), sin(a), cos(a)) * uv;
  if (uTouch.z < 1.0) {
    vec2 tp = (uTouch.xy - 0.5 * uSize) / m;
    uv += (tp * 0.06) * (1.0 - uTouch.z);
  }

  float t = uTime * 0.035;

  // Soft nebula so the background is never flat.
  float neb = vnoise(uv * 1.6 + vec2(uTime * 0.004, 3.0)) * 0.6 + vnoise(uv * 3.1 - 5.0) * 0.4;
  vec3 col = mix(vec3(0.010, 0.012, 0.035), vec3(0.060, 0.040, 0.110), neb * 0.7);
  col += vec3(0.02, 0.05, 0.09) * smoothstep(0.9, 0.0, length(uv)) * 0.6;

  for (int i = 0; i < 6; i++) {
    float fi = float(i);
    float z = fract(fi / 6.0 + t);
    float fade = smoothstep(0.0, 0.18, z) * smoothstep(1.0, 0.82, z);
    float scale = mix(16.0, 2.6, z);
    vec2 g = uv * scale + vec2(fi * 13.7, fi * 7.3);
    vec2 cell = floor(g);
    vec2 f = fract(g) - 0.5;
    vec2 h = hash22(cell);
    float present = step(0.55, hash21(cell + 91.7));
    // Keep each star well inside its cell so its glow is never clipped to a square.
    vec2 pos = (h - 0.5) * 0.5;
    float d = length(f - pos);
    float r = mix(0.028, 0.060, z) * (0.7 + 0.6 * h.x);
    float core = smoothstep(r, 0.0, d);
    float halo = exp(-(d * d) / (r * r * 3.0)) * 0.30;
    vec3 tint = mix(vec3(0.70, 0.82, 1.0), vec3(1.0, 0.86, 0.92), h.y);
    col += tint * (core + halo) * fade * present * 0.85;
  }

  // Slower protocol speeds also soften overall intensity slightly.
  col *= mix(0.92, 1.0, clamp(uSpeed, 0.0, 1.0));
  col *= clamp(uDim, 0.0, 1.0);
  fragColor = vec4(col, 1.0);
}
