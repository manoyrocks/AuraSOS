// Polygon mandala: concentric regular polygons (triangle up to a nonagon) turning slowly in
// opposite directions on a plane tilted into the distance, with a soft glow along each edge.
// A touch sends a ring of light outward.
// Uniform float order (setFloat indices): uSize.x=0 uSize.y=1, uTime=2, uSpeed=3, uDim=4,
// uTouch.x=5 uTouch.y=6 uTouch.z=7 (z = touch age 0..1; >= 1 means no active touch).
// Rings turn at most 0.06 rad/s and the tilt sways at 0.01 Hz: luminance is effectively steady.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uSpeed;
uniform float uDim;
uniform vec3 uTouch;

out vec4 fragColor;

// Signed distance to a regular n-gon with apothem r.
float polyD(vec2 p, float r, float n) {
  float a = atan(p.x, p.y) + 3.14159265;
  float b = 6.2831853 / n;
  return cos(floor(0.5 + a / b) * b - a) * length(p) - r;
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  float m = max(min(uSize.x, uSize.y), 1.0);
  vec2 uv = (fc - 0.5 * uSize) / m;
  uv.y = -uv.y;

  // Look down onto a plane tilted away from the viewer: higher on screen = farther.
  float tilt = 0.62 + 0.05 * sin(uTime * 0.06);
  float depth = 1.0 + uv.y * tilt * 1.5;
  vec2 q = vec2(uv.x, uv.y * 1.25) / max(depth, 0.25);

  vec3 col = mix(vec3(0.010, 0.012, 0.035), vec3(0.030, 0.026, 0.080), clamp(0.5 - uv.y * 0.5, 0.0, 1.0));
  col += vec3(0.05, 0.04, 0.12) * smoothstep(0.55, 0.0, length(q)) * 0.7;

  for (int i = 0; i < 7; i++) {
    float fi = float(i);
    float dir = mod(fi, 2.0) < 0.5 ? 1.0 : -1.0;
    float ang = uTime * (0.02 + 0.006 * fi) * dir + fi * 0.5;
    float ca = cos(ang);
    float sa = sin(ang);
    vec2 p = mat2(ca, -sa, sa, ca) * q;
    float r = 0.10 + 0.085 * fi;
    float d = abs(polyD(p, r, 3.0 + fi));
    // Soft, wide edges: a gaussian glow instead of a hard neon line.
    float line = exp(-(d * d) / 0.00020);
    float halo = exp(-(d * d) / 0.0040) * 0.30;
    vec3 hue = 0.5 + 0.5 * cos(6.2831853 * (vec3(0.0, 0.33, 0.67) + fi * 0.11 + uTime * 0.004));
    hue = mix(hue, vec3(dot(hue, vec3(0.33))), 0.50);
    hue = mix(hue, vec3(0.82, 0.86, 1.0), 0.22);
    float edgeFade = smoothstep(1.4, 0.4, r + length(q) * 0.2);
    col += hue * (line * 0.34 + halo * 0.62) * edgeFade;
  }

  // Touch: a soft ring of light travelling outward from the touch point.
  if (uTouch.z < 1.0) {
    float d = length((fc - uTouch.xy) / m);
    float ringR = 0.04 + uTouch.z * 0.4;
    float ring = smoothstep(0.07, 0.0, abs(d - ringR));
    col += vec3(0.60, 0.55, 0.95) * ring * (1.0 - uTouch.z) * 0.5;
  }

  col *= smoothstep(1.5, 0.3, length(uv));
  // Slower protocol speeds also soften overall intensity slightly.
  col *= mix(0.92, 1.0, clamp(uSpeed, 0.0, 1.0));
  col *= clamp(uDim, 0.0, 1.0);
  fragColor = vec4(col, 1.0);
}
