# Changelog

## 0.1.0 - 2026-11-18

Initial release: a faithful Flutter port of the QuickLiquid optics
specification.

### liquid_glass_core (pure Dart)

- Exact Snell refraction model: quarter-ellipse bezel height `z(s)`, slope
  `sigma(s)`, vector-form Snell ray, and the screen-space displacement
  `Delta(s) = z(s) . |t_xy / t_z|` with all emergent properties
  (`Delta(0) = Delta(1) = 0`, finite rim ratio, inward sampling).
- 512-entry normalized displacement LUT per `(T, B_effective, n)` with a
  refcounted process-wide cache: N same-optics elements share one build.
- Analytic rounded-rect SDF with corner-circle + edge branch gradient
  (no finite-difference probes).
- Band-limited, mirror-symmetric, Bayer-dithered 8-bit displacement-map
  encoder with the loss-minimizing `S = 2M` scale (parity with the
  SVG-filter pipeline; export/debug path).
- Engine metrics singleton (LUT builds/hits/sharing, raster band pixels,
  timings).
- 41 unit tests; LUT cross-checked against an independent Python
  implementation of the spec.

### liquid_glass_engine (Flutter)

- `LiquidGlass` widget: exact-Snell refraction over live backdrop via a
  single `BackdropFilter` layer whose filter is the engine's fragment
  shader (displacement + chromatic aberration + frost + saturation + rim
  lighting in one GPU pass).
- Live renderer probe (real `ImageFilter.shader` construction) selecting
  refraction vs soft fallback - no feature flags that lie.
- Attribute-only updates: strength / CA / frost / saturation / light angle /
  rim / tint are uniform writes; LUT rebuilds only on geometry change.
- Soft fallback surface (blur + painted rim light) for Flutter web,
  software renderers and Skia backends.
- `LiquidGlassEngine.warmUp()` / `.metrics`, debug
  `LiquidGlassMapPreview`, runnable demo app with live sliders and a
  metrics overlay.
