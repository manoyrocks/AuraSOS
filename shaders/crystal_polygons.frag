// Crystal polygons: three low-poly solids (octahedron, bevelled cube, tetrahedron) floating
// and turning very slowly in depth, flat-shaded in soft pastels. A touch moves the light.
// Uniform float order (setFloat indices): uSize.x=0 uSize.y=1, uTime=2, uSpeed=3, uDim=4,
// uTouch.x=5 uTouch.y=6 uTouch.z=7 (z = touch age 0..1; >= 1 means no active touch).
// Rotation is at most 0.11 rad/s and bobbing 0.05 Hz, so luminance changes stay < 0.2 Hz.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uSpeed;
uniform float uDim;
uniform vec3 uTouch;

out vec4 fragColor;

mat3 rotX(float a) {
  float c = cos(a);
  float s = sin(a);
  return mat3(1.0, 0.0, 0.0, 0.0, c, s, 0.0, -s, c);
}

mat3 rotY(float a) {
  float c = cos(a);
  float s = sin(a);
  return mat3(c, 0.0, -s, 0.0, 1.0, 0.0, s, 0.0, c);
}

mat3 rotZ(float a) {
  float c = cos(a);
  float s = sin(a);
  return mat3(c, s, 0.0, -s, c, 0.0, 0.0, 0.0, 1.0);
}

float sdOcta(vec3 p, float s) {
  p = abs(p);
  return (p.x + p.y + p.z - s) * 0.57735027;
}

float sdTetra(vec3 p, float s) {
  return (max(abs(p.x + p.y) - p.z, abs(p.x - p.y) + p.z) - s) * 0.57735027;
}

float sdBox(vec3 p, vec3 b) {
  vec3 q = abs(p) - b;
  return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// x = distance, y = shape id.
vec2 map(vec3 p, mat3 ra, mat3 rb, mat3 rc, vec3 bob, vec2 sp) {
  vec3 pa = ra * (p - vec3(-0.46 * sp.x, 0.26 * sp.y + bob.x, 0.15));
  vec3 pb = rb * (p - vec3(0.44 * sp.x, -0.30 * sp.y + bob.y, 0.0));
  vec3 pc = rc * (p - vec3(0.08 * sp.x, 0.62 * sp.y + bob.z, 0.85));
  float dA = sdOcta(vec3(pa.x, pa.y * 0.78, pa.z), 0.30);
  float dB = sdBox(pb, vec3(0.14)) - 0.02;
  float dC = sdTetra(pc, 0.25);
  vec2 r = vec2(dA, 0.0);
  if (dB < r.x) r = vec2(dB, 1.0);
  if (dC < r.x) r = vec2(dC, 2.0);
  return r;
}

#define MAP(p) map(p, ra, rb, rc, bob, sp)

void main() {
  vec2 fc = FlutterFragCoord().xy;
  float m = max(min(uSize.x, uSize.y), 1.0);
  vec2 uv = (fc - 0.5 * uSize) / m;
  uv.y = -uv.y;
  float aspect = uSize.x / max(uSize.y, 1.0);
  // Keep the composition filled on wide and on tall screens.
  vec2 sp = vec2(max(1.0, aspect * 0.9), max(1.0, (1.0 / max(aspect, 0.2)) * 0.8));

  float t = uTime;
  mat3 ra = rotY(t * 0.11) * rotX(t * 0.07 + 0.4);
  mat3 rb = rotY(-t * 0.09 + 0.6) * rotZ(t * 0.06) * rotX(0.5);
  mat3 rc = rotX(t * 0.08) * rotZ(-t * 0.10 + 1.0);
  vec3 bob = vec3(sin(t * 0.21) * 0.04, sin(t * 0.17 + 1.3) * 0.05, sin(t * 0.13 + 2.1) * 0.04);

  vec3 ro = vec3(0.0, 0.0, -2.2);
  vec3 rd = normalize(vec3(uv, 1.4));

  // Deep navy backdrop with a soft vertical gradient and vignette.
  vec3 bg = mix(vec3(0.020, 0.026, 0.065), vec3(0.070, 0.078, 0.160), clamp(0.5 + uv.y * 0.5, 0.0, 1.0));
  bg *= smoothstep(1.7, 0.2, length(uv));

  float tt = 0.0;
  float id = 0.0;
  float minD = 10.0;
  float glowId = 0.0;
  bool hit = false;
  for (int i = 0; i < 48; i++) {
    vec2 h = MAP(ro + rd * tt);
    if (h.x < minD) {
      minD = h.x;
      glowId = h.y;
    }
    if (h.x < 0.002) {
      hit = true;
      id = h.y;
      break;
    }
    tt += h.x;
    if (tt > 6.0) {
      break;
    }
  }

  vec3 teal = vec3(0.45, 0.86, 0.94);
  vec3 lavender = vec3(0.74, 0.64, 0.98);
  vec3 peach = vec3(0.99, 0.76, 0.70);
  vec3 glowCol = glowId < 0.5 ? teal : (glowId < 1.5 ? lavender : peach);
  vec3 col = bg + glowCol * exp(-max(minD, 0.0) * 9.0) * 0.07;

  if (hit) {
    vec3 p = ro + rd * tt;
    vec2 e = vec2(0.002, -0.002);
    vec3 n = normalize(e.xyy * MAP(p + e.xyy).x + e.yyx * MAP(p + e.yyx).x +
                       e.yxy * MAP(p + e.yxy).x + e.xxx * MAP(p + e.xxx).x);

    vec3 light = normalize(vec3(-0.5, 0.7, -0.6));
    if (uTouch.z < 1.0) {
      vec2 tp = (uTouch.xy - 0.5 * uSize) / m;
      light = normalize(vec3(tp.x * 1.6, -tp.y * 1.6, -0.7));
    }
    float diff = clamp(dot(n, light), 0.0, 1.0);
    float fres = pow(1.0 - clamp(dot(n, -rd), 0.0, 1.0), 3.0);
    vec3 refl = reflect(rd, n);
    float spec = pow(clamp(dot(refl, light), 0.0, 1.0), 28.0);

    vec3 base = id < 0.5 ? teal : (id < 1.5 ? lavender : peach);
    vec3 c = base * (0.30 + 0.58 * diff) + base * fres * 0.40 + vec3(0.9, 0.95, 1.0) * spec * 0.10;
    float fog = clamp(exp(-0.16 * (tt - 1.6)), 0.0, 1.0);
    col = mix(bg, c, fog);
  }

  // Slower protocol speeds also soften overall intensity slightly.
  col *= mix(0.92, 1.0, clamp(uSpeed, 0.0, 1.0));
  col *= clamp(uDim, 0.0, 1.0);
  fragColor = vec4(col, 1.0);
}
