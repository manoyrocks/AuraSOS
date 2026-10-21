// Classroom bubbles: pastel gradient with slowly rising translucent bubbles.
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

  // Soft vertical pastel gradient, slow drift (period ~25 s).
  float drift = 0.5 + 0.5 * sin(uTime * 0.25);
  vec3 top = mix(vec3(0.62, 0.78, 0.92), vec3(0.72, 0.70, 0.92), drift);
  vec3 bottom = mix(vec3(0.80, 0.90, 0.85), vec3(0.86, 0.84, 0.92), drift);
  vec3 col = mix(top, bottom, uv.y) * 0.62;

  for (int i = 0; i < 14; i++) {
    float fi = float(i);
    float h1 = hash11(fi + 1.0);
    float h2 = hash11(fi + 17.0);
    float h3 = hash11(fi + 33.0);
    float radius = 0.045 + 0.075 * h1;
    float rise = 0.012 + 0.020 * h2;
    // y runs from below the screen to above it, wrapping.
    float y = 1.0 + radius - fract(h3 + uTime * rise) * (1.0 + 2.0 * radius);
    float x = (0.1 + 0.8 * h2) * aspect + sin(uTime * 0.3 + fi * 2.1) * 0.03;
    float d = length(p - vec2(x, y));
    float body = smoothstep(radius, radius * 0.85, d) * 0.12;
    float rim = smoothstep(radius * 0.12, 0.0, abs(d - radius * 0.9)) * 0.38;
    vec2 hl = p - vec2(x - radius * 0.35, y - radius * 0.35);
    float spec = smoothstep(radius * 0.22, 0.0, length(hl)) * 0.35;
    vec3 tint = mix(vec3(0.85, 0.95, 1.0), vec3(1.0, 0.92, 0.96), h1);
    col += tint * (body + rim + spec);
  }

  if (uTouch.z < 1.0) {
    float d = length(fc - uTouch.xy) / max(min(uSize.x, uSize.y), 1.0);
    float ringR = 0.03 + uTouch.z * 0.30;
    float ring = smoothstep(0.06, 0.0, abs(d - ringR));
    col += vec3(0.9, 0.95, 1.0) * ring * (1.0 - uTouch.z) * 0.35;
  }

  // Slower protocol speeds also soften overall intensity slightly.
  col *= mix(0.92, 1.0, clamp(uSpeed, 0.0, 1.0));
  col *= clamp(uDim, 0.0, 1.0);
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
