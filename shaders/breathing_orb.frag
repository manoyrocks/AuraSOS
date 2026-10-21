// Breathing orb: 10 s cycle, 4 s inhale (grow) + 6 s exhale (shrink), cosine-eased.
// Uniform float order (setFloat indices): uSize.x=0 uSize.y=1, uTime=2, uSpeed=3, uDim=4,
// uTouch.x=5 uTouch.y=6 uTouch.z=7 (z = touch age 0..1; >= 1 means no active touch).
// uTime is already scaled by speed on the Dart side (use speed 1.0 for the true 4/6 s rhythm).
// Luminance follows the breath at 0.1 Hz; no strobing.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uSpeed;
uniform float uDim;
uniform vec3 uTouch;

out vec4 fragColor;

void main() {
  vec2 fc = FlutterFragCoord().xy;
  float m = max(min(uSize.x, uSize.y), 1.0);
  vec2 uv = (fc - 0.5 * uSize) / m;

  float t = mod(uTime, 10.0);
  float e;
  if (t < 4.0) {
    e = 0.5 - 0.5 * cos(3.14159265 * (t / 4.0));
  } else {
    e = 0.5 + 0.5 * cos(3.14159265 * ((t - 4.0) / 6.0));
  }

  float radius = mix(0.16, 0.34, e);
  float d = length(uv);

  vec3 bg = vec3(0.012, 0.02, 0.05);
  vec3 inner = mix(vec3(0.18, 0.45, 0.70), vec3(0.35, 0.72, 0.85), e);
  float body = smoothstep(radius, radius * 0.55, d);
  float halo = smoothstep(radius * 2.2, radius, d);
  float lum = 0.55 + 0.45 * e;

  vec3 col = bg + inner * (body * 0.85 + halo * 0.22) * lum;

  if (uTouch.z < 1.0) {
    float dt = length(fc - uTouch.xy) / m;
    float ringR = 0.03 + uTouch.z * 0.30;
    float ring = smoothstep(0.05, 0.0, abs(dt - ringR));
    col += vec3(0.4, 0.7, 0.85) * ring * (1.0 - uTouch.z) * 0.4;
  }

  // Slower protocol speeds also soften overall intensity slightly.
  col *= mix(0.92, 1.0, clamp(uSpeed, 0.0, 1.0));
  col *= clamp(uDim, 0.0, 1.0);
  fragColor = vec4(col, 1.0);
}
