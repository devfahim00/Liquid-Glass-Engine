# The optics: QuickLiquid math in this engine

This document is the specification the engine implements - the QuickLiquid
optics & optimization math - annotated with exactly where each piece lives
in this repository. Numbers below are the spec's; measured results for this
port are in [PERFORMANCE.md](PERFORMANCE.md).

---

## 1. The glass model

The element is modeled as a solid glass slab of refractive index `n` (config
`ior`, default 1.5) and thickness `T` (config `thickness`, CSS px), resting
directly on the backdrop plane. Its top face is flat in the center and rolls
off through a **convex circular-arc bezel** of width `B` (config
`bezelWidth`) at the shape's edge.

With `d` = distance from the shape boundary measured inward (from the
signed distance field) and `s = d / B in [0, 1]`:

```
height   z(s) = T . sqrt(s . (2 - s))            (quarter-ellipse arc, z(0)=0, z(1)=T)
slope    sigma(s) = |dz/dd| = (T/B) . (1 - s) / sqrt(s . (2 - s))
```

`sigma -> infinity` at the rim (vertical glass wall) and `sigma -> 0` at
`s = 1` where the bezel meets the flat top with C1 continuity - no visible
seam.

For pill/capsule shapes where `B > min(w,h)/2`, `B` is clamped to
`min(w,h)/2`, so `s` reaches exactly 1 on the medial axis with zero slope -
the bezel becomes a full smooth dome with no ridge artifact.

**Implementation:** `packages/liquid_glass_core/lib/src/snell.dart`
(`Snell.height`, `Snell.slope`), the clamp in
`packages/liquid_glass_core/lib/src/optics.dart`
(`GlassOptics.effectiveBezel`), and `snellDelta()` in
`packages/liquid_glass_engine/shaders/liquid_glass.frag`.

## 2. Exact Snell refraction

An orthographic view ray `v = (0, 0, -1)` strikes the tilted surface with
unit normal (in the cross-section plane spanned by the outward direction
`m_hat` and z):

```
n_hat = ( sigma . m_hat , 1 ) / sqrt(1 + sigma^2)
cos theta_i = 1/sqrt(1+sigma^2)        sin theta_i = sigma/sqrt(1+sigma^2)
```

Snell's law in vector form, with `eta = 1/n` (air -> glass):

```
sin theta_t = eta . sin theta_i
cos theta_t = sqrt(1 - sin^2 theta_t)
t = eta.v + (eta . cos theta_i - cos theta_t) . n_hat
```

Components of the refracted ray:

```
t_xy = (eta cos theta_i - cos theta_t) . sin theta_i      (lateral, sign < 0 => INWARD)
t_z  = -eta + (eta cos theta_i - cos theta_t) . cos theta_i (downward)
```

The ray then travels through glass depth `z(s)` to the (flat) bottom face;
the bottom interface adds no further lateral shift when the backdrop sits
at the exit plane. Total screen-space displacement:

```
Delta(s) = z(s) . |t_xy / t_z|
```

Properties that emerge (nothing is hand-tuned):

- `Delta(0) = 0` - the rim is continuous with the outside (`z -> 0` wins
  over `sigma -> infinity`; the limit of `z tan(phi)` is 0 because
  `tan(phi) -> sqrt(1-eta^2)/eta` is finite).
- `Delta(1) = 0` - flat center, perfectly clear glass.
- `Delta` peaks inside the bezel band -> the signature Apple "clear center,
  bent rim".
- Sampling is **inward** (magnifier / water-droplet behavior), matching real
  thick glass.

**Implementation:** `Snell.ray`, `Snell.displacement`, `Snell.rimRatio`
(core, unit-tested against an independent Python implementation), and the
same formulas in GLSL in `shaders/liquid_glass.frag` (`snellDelta`).

## 3. The 1-D reduction (LUT)

For fixed `(T, B, n)`, `Delta` depends **only on `s`** - not on position.
The engine therefore tabulates the exact traced `Delta(s)` into a 512-entry
`Float32List` once per geometry, normalizes it by
`Delta_max = max_s Delta(s)`, and per-pixel work collapses to:

```
SDF(x,y) -> d -> s -> lerp(LUT, s*512) -> dx,dy = -m_hat . Delta_hat(s)
```

No trig, no sqrt (beyond the SDF's), no Snell per pixel. The rounded-rect
SDF and its gradient `m_hat` are analytic (corner-circle branch + edge
branches), so there are **no finite-difference probes** (the previous
engine used 4 extra SDF evaluations per pixel for the gradient - a 5x
overhead, removed).

**Implementation:** `RefractionLut` (512 entries, `at()` lerp) +
`RefractionLutCache` (refcounted) in
`packages/liquid_glass_core/lib/src/refraction_lut.dart`;
`RoundedRectSdf` (analytic SDF + `outwardDirection`) in
`packages/liquid_glass_core/lib/src/rounded_rect_sdf.dart`.

**Flutter GPU path divergence (an improvement):** the shader evaluates the
exact optics analytically per pixel - the LUT is still built (once per
geometry) as the single source of the `Delta_max` normalizer and for the
CPU parity path, but per-frame the GPU never fetches it. This makes the
per-pixel cost *strictly* the spec's "SDF -> s -> shift" while removing even
the lerp approximation.

## 4. Band-limited, mirrored rasterization

- Pixels with `d >= B` (flat center) and `d <= 0` (outside) are exactly
  neutral. The buffer is pre-filled with neutral `(128, 128)` via one fill
  and only the bezel band is iterated: `~perimeter x B` pixels instead of
  `w x h`.
- The displacement field is odd under mirroring:
  `dx(w-x, y) = -dx(x, y)`, `dy(x, h-y) = -dy(x, y)`. One quadrant is
  computed; four pixels are written per evaluation.

**Implementation:**
`DisplacementMapRaster.build` in
`packages/liquid_glass_core/lib/src/raster_map.dart` - band limiting, the
odd mirror writes with per-pixel dither, and the metrics counters.
Measured band ratios on this port are in [PERFORMANCE.md](PERFORMANCE.md)
(x5.8 fewer on a 522x621 panel at B = 26; x14.7 at B = 10).

## 5. Minimal-loss 8-bit encoding

`feDisplacementMap` samples `P(x + S.(R-0.5), y + S.(G-0.5))` with R, G
decoded from an 8-bit map. The quantization step in *offset space* is
`S/255` px - independent of how much of the value range the map uses.
Therefore, for a required max displacement `M`, the loss-minimizing choice
is the smallest scale that still covers `+/-M`:

```
map values  = Delta/Delta_max in [-1, 1]  -> full 0..255 range
filter scale S = 2 . M          (M = refractionStrength px)
=> quantization step = 2M/255 ~= M/127   (e.g. 0.17 px at M = 22)
```

Any fixed, larger `S` (the previous engine used raw strength with an
un-normalized map) wastes range and multiplies the step size. On top of
this, a 4x4 **ordered Bayer dither** (+/- half LSB, ~2 ops/px) decorrelates
the residual quantization into spatially white noise - banding contours
become physically invisible at 0.1-px amplitude.

**Implementation:** the byte codec in `raster_map.dart`
(`_toByte`/`decodeDx`: 128 == exactly 0; full-range `[-1, 1]`;
`suggestedScale = 2M`) and `packages/liquid_glass_core/lib/src/bayer.dart`
(the 4x4 pattern, bias-free over a tile). The CPU raster is the parity /
export / debug path (`LiquidGlassMapPreview`); the **GPU path skips the
8-bit quantization entirely** (float uniforms), so its effective step is 0
- strictly better than the 0.17 px bound that justified the original claim.

## 6. Chromatic aberration for the price of zero maps

Dispersion means `n` varies per wavelength => `Delta` scales (to first
order) linearly per channel. Since the scale attribute is exactly that
linear factor, CA needs **one shared map** and three scales:

```
S_R = S . (1 - 0.10 ca)     S_G = S     S_B = S . (1 + 0.14 ca)
```

(blue bends more; sampling is inward so blue gets the larger scale - real
crown-glass ordering). The previous engine generated three separate maps
with per-channel magnitudes baked in - 3x the generation work for a
mathematically identical result. Channel recombination stays in the filter
(`feComponentTransfer` isolation + `screen` blends, which is additive for
disjoint channels).

**Implementation:** in the shader, `tapAt(fc - shift.(1 -/+ ca))` per
channel - one shared LUT, one shared shader, three linear scales in the
same pass; in the CPU encoder the map is identical for all channels.

Bonus: because per-channel strength lives in the scale attribute, slider
changes to `refractionStrength` or `chromaticAberration` are
**attribute-only updates** - no map regeneration, no PNG encode, no
repaint of the map. In this Flutter port the same holds for `frost`,
`saturation`, `lightAngleDeg`, `rim` and `tint`: uniform writes, nothing
rebuilt.

## 7. Cache & sharing

Maps are keyed by `(map-res, element-size, radius, B, T, n)` and
refcounted. N same-size cards share one blob and one generation cost.

**Implementation:** `RefractionLutCache` - keyed by `(T, B_effective, n)`
with acquire/release refcounts. The element size enters only through the
`min(w,h)/2` bezel clamp, so same-optics elements of any size share one
LUT; the demo's four cards generate exactly one (verified by tests:
`lutBuilds == 1`, `lutCacheHits == 3`).

## 8. Render-time cost model

Per composited frame, the browser evaluates the filter chain on the
backdrop: 1 displacement tap (or 3 with CA) + blur + saturate. The engine
keeps exactly **one** backdrop-filter layer per element (the previous dual
"edge frost" layer doubled backdrop readbacks and was removed).
Light-angle animation touches only two small conic-gradient layers - the
lens layer is never invalidated by pointer motion.

**Flutter analog:** exactly one `BackdropFilter` layer per element whose
filter *is* the shader (displacement + frost + saturation + rim lighting in
one pass); pointer-driven light changes write uniforms only - the lens
layer and the LUT are never invalidated.

## 9. Browser support & fallback (ported as renderer support & fallback)

`backdrop-filter: url(#...)` renders in Chromium. A live DOM probe (not
`CSS.supports`, which lies) detects support; unsupported engines fall back
to blur + saturate + lighting layers (`refractionMode: 'auto'`).

**Flutter analog:** the refraction path requires `ImageFilter.shader`
(Impeller). The engine runs a live construction probe - actually building
the filter, catching the `UnsupportedError` - and falls back to the soft
surface (blur + rim light) on Flutter web, software renderers, or Skia
backends. Two Chromium pitfalls that silently disable only the `url()` part
(having the glass host clipped by an ancestor that prevents resolving the
live backdrop) have their analog here too: keep the glass in the same
layer stack as its backdrop and avoid clipping ancestors that starve the
backdrop readback.

---

## Verification

* `packages/liquid_glass_core/test/` - 41 unit tests: quarter-circle height
  identity, slope limits, `Delta(0) = Delta(1) = 0`, unimodality, inward
  ray components, the finite rim ratio limit, SDF branch behavior, the
  bezel clamp, LUT normalization/sharing/refcounts, band/mirror/dither
  properties of the 8-bit encoder and its `2M/255` step bound.
* `packages/liquid_glass_engine/test/` - shader asset loads (GLSL compiles
  via the Flutter tool), the live probe resolves, the widget paints over a
  live backdrop in whichever mode the renderer picked, exactly one
  backdrop-filtered surface, config/shape resolution and metrics.
* `scripts/crosscheck_optics.py`-style double implementation: the LUT is
  cross-checked against an independent Python implementation of the spec
  (agreement at Float32 precision) - see [PERFORMANCE.md](PERFORMANCE.md).
