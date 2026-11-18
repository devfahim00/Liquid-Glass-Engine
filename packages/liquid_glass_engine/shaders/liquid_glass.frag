// Liquid Glass Engine - exact-Snell refraction fragment shader.
//
// This is the GPU port of the QuickLiquid optics specification
// (see docs/MATH.md). Per-pixel work is: SDF -> s -> exact Snell Delta ->
// inward sample, with chromatic aberration as per-channel linear scales,
// frost as a small ring blur, saturation/tint and analytic rim lighting.
// No LUT fetch, no trig tables, no per-pixel Dart work.
//
// ImageFilter.shader contract (dart:ui):
//   * uSize     - the FIRST uniform, a vec2, is set by the ENGINE to the
//                size (device px) of the bound backdrop texture.
//   * uBackdrop - the sampler2D receives the filter input (the backdrop).
//   * The engine-managed vec2 occupies float slots 0..1; every float the
//    engine sets below starts at index 2 (see shader_uniforms.dart).
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;           // ENGINE-SET: backdrop texture size (device px)
uniform sampler2D uBackdrop;  // ENGINE-SET: the filter input

uniform float uDpr;        // 2: device px per logical px
uniform float uRadius;     // 3: corner radius, logical px
uniform float uThickness;  // 4: T, logical px
uniform float uBezel;      // 5: B, logical px (already clamped)
uniform float uIor;        // 6: n
uniform float uStrength;   // 7: M, logical px (refractionStrength)
uniform float uDeltaMax;   // 8: Delta_max in logical px (from the LUT)
uniform float uCa;         // 9: chromaticAberration in [0, 1]
uniform float uFrost;      // 10: frost in [0, 1]
uniform float uSaturation; // 11: backdrop saturation (1 = untouched)
uniform vec2 uLight;       // 12, 13: unit direction toward the light
uniform float uRim;         // 14: rim highlight intensity
uniform vec4 uTint;        // 15..18: straight RGBA glass tint

out vec4 fragColor;

// The filter input is sampled through FlutterFragCoord-local coordinates
// (the same space as the bound texture), so `fragPos / uSize` is the
// identity mapping; displacement offsets are applied in that space.
vec3 tapAt(vec2 fragPos) {
  vec2 uv = fragPos / uSize;
  // Impeller on the GLES backend has a flipped texture y-axis.
  #ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
  #endif
  return texture(uBackdrop, uv).rgb;
}

// Signed distance to the rounded rect (negative inside).
// Edge branches: min(max(qx, qy), 0); corner branch: length(max(q, 0)).
float sdfRoundedRect(vec2 p, vec2 halfSize, float r) {
  vec2 q = abs(p) - halfSize + vec2(r);
  vec2 qp = max(q, vec2(0.0));
  return length(qp) + min(max(q.x, q.y), 0.0) - r;
}

// Exact Snell displacement Delta(s), logical px:
//   z(s)     = T sqrt(s (2 - s))
//   sigma(s) = (T/B) (1 - s) / sqrt(s (2 - s))
//   sinI = sigma / sqrt(1 + sigma^2), cosI = 1 / sqrt(1 + sigma^2)
//   sinT = eta sinI,  cosT = sqrt(1 - sinT^2),  eta = 1/n
//   t_xy = (eta cosI - cosT) sinI          (< 0, INWARD)
//   t_z  = -eta + (eta cosI - cosT) cosI   (< 0, downward)
//   Delta = z |t_xy / t_z|
float snellDelta(float s) {
  float arc = sqrt(s * (2.0 - s));
  float z = uThickness * arc;
  float sigma = (uThickness / uBezel) * (1.0 - s) / arc;
  float cosI = inversesqrt(1.0 + sigma * sigma);
  float sinI = sigma * cosI;
  float eta = 1.0 / uIor;
  float sinT = eta * sinI;
  float cosT = sqrt(max(0.0, 1.0 - sinT * sinT));
  float k = eta * cosI - cosT;      // < 0 for n > 1: bent inward
  float tXy = k * sinI;
  float tZ = -eta + k * cosI;
  return z * abs(tXy / tZ);
}

void main() {
  vec2 fc = FlutterFragCoord().xy;

  if (uSize.x < 1.0 || uSize.y < 1.0) {
    fragColor = vec4(0.0);
    return;
  }

  // Logical-space geometry, origin at the rect center (the filter region is
  // the element rect itself, so fc spans [0, uSize]).
  vec2 p = (fc - 0.5 * uSize) / uDpr;
  vec2 halfSize = 0.5 * uSize / uDpr;
  float radius = min(uRadius, min(halfSize.x, halfSize.y));
  float dist = sdfRoundedRect(p, halfSize, radius);

  // Outside the shape: pass the backdrop through untouched (the clip layer
  // crops everything beyond the rounded rect anyway).
  if (dist > 0.75) {
    fragColor = vec4(tapAt(fc), 1.0);
    return;
  }

  // Outward direction mHat: corner-circle branch + edge branches, analytic.
  vec2 q = abs(p) - halfSize + vec2(radius);
  vec2 mHat = normalize(max(sign(p) * max(q, vec2(0.0)), vec2(1e-6)));

  // Bezel parameter s in [eps, 1]: d <= 0 (outside) and d >= B (flat top)
  // are exactly neutral - clamping handles both, since Delta(0) = Delta(1)
  // = 0. The eps keeps sigma finite at the rim (the ratio itself stays
  // bounded: |t_xy/t_z| -> sqrt(1-eta^2)/eta).
  float d = -dist;
  float s = clamp(d / max(uBezel, 1e-6), 1e-4, 1.0);

  // Exact optics scaled linearly by M / Delta_max (attribute-only update:
  // strength and CA are pure uniforms, never a LUT rebuild).
  float delta = snellDelta(s) * (uStrength / max(uDeltaMax, 1e-6));

  // Sampling is INWARD (magnifier / water-droplet behavior):
  // sample at (x, y) - mHat * delta. CA is the per-channel linear scale
  // S(1 - 0.10 ca), S, S(1 + 0.14 ca) - blue bends more (crown glass).
  vec2 shift = mHat * delta * uDpr; // device px
  vec3 col;
  if (uCa > 0.0) {
    col = vec3(
      tapAt(fc - shift * (1.0 - 0.10 * uCa)).r,
      tapAt(fc - shift).g,
      tapAt(fc - shift * (1.0 + 0.14 * uCa)).b);
  } else {
    col = tapAt(fc - shift);
  }

  // Frost: a small 5-tap ring blur around the refracted sample.
  if (uFrost > 0.0) {
    float rDev = uFrost * 3.0 * uDpr;
    vec2 fcG = fc - shift;
    vec3 blur = col
      + tapAt(fcG + vec2(rDev, 0.0))
      + tapAt(fcG - vec2(rDev, 0.0))
      + tapAt(fcG + vec2(0.0, rDev))
      + tapAt(fcG - vec2(0.0, rDev));
    col = mix(col, blur * 0.2, clamp(uFrost, 0.0, 1.0));
  }

  // Saturation and tint.
  float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
  col = mix(vec3(luma), col, uSaturation);
  col = mix(col, uTint.rgb, uTint.a);

  // Rim lighting from the real surface normal n = (sigma mHat, 1)/|.| -
  // a Blinn-Phong lobe toward the light plus a soft edge lift. The flat
  // center (sigma -> 0) keeps the highlight invisible: clear glass.
  float arc = sqrt(s * (2.0 - s));
  float sigma = (uThickness / uBezel) * (1.0 - s) / arc;
  vec3 n = normalize(vec3(mHat * sigma, 1.0));
  vec3 l = normalize(vec3(uLight, 0.75));
  vec3 h = normalize(l + vec3(0.0, 0.0, 1.0)); // view = +z (toward viewer)
  float spec = pow(max(dot(n, h), 0.0), 48.0) * uRim;
  float edge = pow(1.0 - s, 3.0);
  col += spec * (1.0 + 0.6 * edge);
  col += edge * 0.05 * uRim;

  // Shape anti-aliasing; premultiplied output.
  float alpha = 1.0 - smoothstep(-1.0, 0.75, dist);
  fragColor = vec4(col * alpha, alpha);
}
