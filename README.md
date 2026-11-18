# Liquid Glass Engine

**Physically exact liquid-glass refraction for Flutter.** One widget, zero
engine-code changes to integrate, exact Snell optics evaluated per pixel on
the GPU - butter-smooth by construction, not by tuning.

[![CI](https://github.com/devfahim00/Liquid-Glass-Engine/actions/workflows/ci.yml/badge.svg)](https://github.com/devfahim00/Liquid-Glass-Engine/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Flutter](https://img.shields.io/badge/Flutter-%E2%89%A53.27-02569B?logo=flutter)

This is a faithful Flutter port of the QuickLiquid optics specification
(the full derivation lives in [docs/MATH.md](docs/MATH.md)):

* a glass slab of refractive index `n` and thickness `T`, resting on the
  backdrop plane, with a **convex circular-arc bezel** of width `B` at the
  edge - flat, perfectly clear center;
* **exact Snell refraction** of an orthographic view ray per pixel, giving
  the signature "clear center, bent rim" with nothing hand-tuned;
* a **512-entry 1-D LUT** of the traced displacement, refcounted per
  geometry so N same-shape elements share one build;
* chromatic aberration for the price of **zero extra maps** (per-channel
  linear scales), band-limited/mirrored/dithered 8-bit encoding on the CPU
  parity path, and a graceful blur fallback where shaders cannot run.

---

## Why it is butter-smooth

| Optimization (spec) | In this engine |
| --- | --- |
| 1-D reduction: `Delta(s)` depends only on `s` (spec section 3) | LUT built once per geometry, **30 us** measured; the GPU path evaluates the exact optics analytically per pixel - no LUT fetch, no trig |
| Band-limited raster (spec section 4) | CPU encoder touches only `~perimeter x B` pixels (measured: **x5.8 - x14.7 fewer** than full res); the GPU path never rasters a map at all |
| Minimal-loss 8-bit encoding (spec section 5) | CPU parity path keeps the exact `S = 2M` scale + Bayer dither; the **GPU path skips quantization entirely** (float uniforms) |
| CA via per-channel scale (spec section 6) | one shared LUT, three per-channel scales in the shader; `refractionStrength` / `chromaticAberration` changes are **attribute-only updates** - no rebuild, no re-encode |
| Cache & sharing (spec section 7) | LUTs keyed by `(T, B, n)` and refcounted; 4 same-optics cards = 1 build + 3 cache hits (verified in tests) |
| Render-time cost (spec section 8) | exactly **one** `BackdropFilter` layer per element; light-angle animation touches uniforms only, never the lens layer |
| No finite-difference probes (spec section 3) | analytic SDF gradient `m_hat` (corner-circle + edge branches) - no 4-extra-SDF-evals gradient hack |
| Honest capability probe (spec section 9) | a live `ImageFilter.shader` construction probe decides refraction vs fallback - feature flags that lie are never trusted |

Measured numbers and methodology: [docs/PERFORMANCE.md](docs/PERFORMANCE.md).
Full derivation: [docs/MATH.md](docs/MATH.md).

---

## Install

Requires **Flutter 3.27+**. The exact-refraction path additionally needs the
Impeller renderer (default everywhere modern); everything else degrades
gracefully (see [Platform support](#platform-support)).

Add the package to any Flutter app - **no engine code is touched, ever**:

```yaml
dependencies:
  liquid_glass_engine:
    git:
      url: https://github.com/devfahim00/Liquid-Glass-Engine.git
      path: packages/liquid_glass_engine
```

`flutter pub get` and you are done - the shader is declared in the package's
`flutter: shaders:` section, so the Flutter tool compiles and bundles it
with your app automatically. You never list the shader, the core package,
or any asset yourself.

## Quick start

1. Warm the engine up once, before the first frame:

```dart
import 'package:liquid_glass_engine/liquid_glass_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiquidGlassEngine.warmUp(); // compiles the shader, zero-jank frame 1
  runApp(const MyApp());
}
```

2. Paint something beneath the glass, then place a `LiquidGlass` over it
   (it needs bounded dimensions and a backdrop in the same stack):

```dart
import 'package:flutter/material.dart';
import 'package:liquid_glass_engine/liquid_glass_engine.dart';

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Any content - scrolling lists, photos, gradients...
          ListView(children: [ /* ... */ ]),

          // The glass element, floating above it.
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: 420,
                height: 64,
                child: LiquidGlass(
                  config: const LiquidGlassConfig(
                    shape: LiquidGlassShape.capsule(),
                    optics: GlassOptics(
                      thickness: 20,
                      bezelWidth: 26,
                      ior: 1.5,
                      refractionStrength: 22,
                      chromaticAberration: 0.0,
                    ),
                    lightAngleDeg: 135,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [Icon(Icons.home, color: Colors.white)],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

A runnable demo with live sliders and a metrics overlay lives in
[packages/liquid_glass_engine/example](packages/liquid_glass_engine/example):

```sh
cd packages/liquid_glass_engine/example
flutter run
```

---

## Integration guide (any Flutter app, without touching the engine)

**Step 1 - depend.** Add the git dependency above to the target app's
`pubspec.yaml`. Nothing else is added to the app's `flutter:` section.

**Step 2 - import once.**

```dart
import 'package:liquid_glass_engine/liquid_glass_engine.dart';
```

The public surface is intentionally small: `LiquidGlass`,
`LiquidGlassConfig`, `LiquidGlassShape`, `GlassOptics`,
`LiquidGlassMode`, `LiquidGlassEngine` (plus the pure-Dart optics from
`liquid_glass_core` if you want to reuse the math).

**Step 3 - wrap.** Put a `LiquidGlass` anywhere it has (a) bounded size and
(b) painted content beneath it. Typical placements:

* `Positioned` / `Positioned.fill` inside a `Stack` (overlay toolbars,
  floating panels, cards over scrolling content);
* a fixed-height bar at the bottom of a `Column` above an `Expanded`
  content area;
* inside an `AspectRatio` / `SizedBox` for hero cards.

**Step 4 - style via config, never via engine edits.** Every visual knob is
a constructor parameter (see the reference below). Configs are immutable
values - animate them, lerp them, swap them at runtime; the widget resolves
what to rebuild (uniforms only, unless the geometry actually changed).

**Step 5 - (optional) observe.** `LiquidGlassEngine.metrics` is the live
counter panel (LUT builds, cache hits, band pixels...), the analog of the
web engine's `__QUICK_LIQUID__.metrics()`:

```dart
print(LiquidGlassEngine.metrics.summary());
// lutBuilds=1, lutCacheHits=3, activeLuts=1, lutBuildTime=30us, ...
```

That is the whole integration. There is no setup object, no controller to
dispose (the widget manages its LUT lease and shader lifetime itself), no
platform channel, no code generation.

---

## API reference

### `LiquidGlass`

| Property | Type | Default | Notes |
| --- | --- | --- | --- |
| `config` | `LiquidGlassConfig` | `LiquidGlassConfig()` | optics + presentation |
| `child` | `Widget?` | - | content painted on the glass surface |
| `mode` | `LiquidGlassMode` | `auto` | `auto` / `refraction` / `soft` |

### `LiquidGlassConfig`

| Property | Type | Default | Meaning |
| --- | --- | --- | --- |
| `shape` | `LiquidGlassShape` | `rounded(24)` | silhouette (see below) |
| `optics` | `GlassOptics` | see below | the physics |
| `lightAngleDeg` | `double` | `135` | rim-light direction, degrees on screen (135 = top-left) |
| `rim` | `double` | `1.0` | rim highlight intensity (0 = off) |
| `tint` | `Color` | transparent | glass tint composited over the refracted backdrop |

### `GlassOptics` (the physics)

| Property | Type | Default | Range | Meaning |
| --- | --- | --- | --- | --- |
| `thickness` | `double` | `20` | `> 0` | slab thickness `T`, logical px |
| `bezelWidth` | `double` | `26` | `> 0` | bezel band width `B`, logical px (auto-clamps to `min(w,h)/2`; a big `B` becomes a smooth dome - no ridge) |
| `ior` | `double` | `1.5` | `> 1` | refractive index `n` |
| `refractionStrength` | `double` | `22` | `>= 0` | max displacement `M`, logical px - a linear zoom of the exact profile |
| `chromaticAberration` | `double` | `0` | `0..1` | per-channel scales `S(1-0.10ca)`, `S`, `S(1+0.14ca)` (blue bends more, crown-glass ordering) |
| `frost` | `double` | `0` | `0..1` | surface blur over the refracted sample |
| `saturation` | `double` | `1.0` | `> 0` | backdrop saturation multiplier |

`refractionStrength`, `chromaticAberration`, `frost`, `saturation`,
`lightAngleDeg`, `rim` and `tint` are **uniform-only updates**: changing
them at slider speed never rebuilds a LUT, re-encodes a map, or re-creates
the backdrop layer. The LUT rebuilds only when `(T, B, n)` changes - and
that build is 512 exact Snell evaluations, measured at ~30 us.

### `LiquidGlassShape`

* `LiquidGlassShape.rounded(radius)` - rounded rectangle (radius clamps to
  `min(w, h)/2`);
* `LiquidGlassShape.capsule()` - pill, radius `= min(w, h)/2`;
* `LiquidGlassShape.circle()` - capsule with equal width and height.

### `LiquidGlassMode`

* `auto` (default) - exact refraction where the live probe succeeds, soft
  fallback otherwise;
* `refraction` - force the shader path (still degrades if unsupported);
* `soft` - force blur + rim-light fallback (useful for debugging and for
  "frosty glass" looks on purpose).

### `LiquidGlassEngine`

* `LiquidGlassEngine.warmUp()` - compile the shader before frame 1;
* `LiquidGlassEngine.metrics` - live counters (`.summary()`, `.reset()`).

### Debug: `LiquidGlassMapPreview`

Renders the CPU encoder's 8-bit displacement map (R = dx, G = dy) so you
can inspect exactly what a `feDisplacementMap`-style pipeline would
consume - band pixels, mirror symmetry, dither noise:

```dart
const LiquidGlassMapPreview(width: 353, height: 163),
```

---

## Platform support

| Platform | Refraction path | Notes |
| --- | --- | --- |
| Android / iOS / macOS (Impeller) | full exact optics | default everywhere modern |
| Windows / Linux (Vulkan-capable, Impeller) | full exact optics | falls back automatically when Impeller is unavailable |
| Flutter web, software renderers, Skia backends | soft fallback (blur + rim light) | the live probe throws on construction, the engine never lies to itself |

The fallback mirrors the web engine's `refractionMode: 'auto'`: a real
construction probe - not `CSS.supports`-style feature flags that lie - runs
once per widget lifetime and decides the path.

## Troubleshooting

* **The glass shows nothing / does not refract** - something must be painted
  *beneath* it in the same layer stack; a glass over an empty
  `Scaffold` background still works (it refracts the background color), a
  glass over nothing cannot bend what is not there.
* **Unbounded layout** - `LiquidGlass` needs bounded dimensions
  (`SizedBox`, `Positioned`, tight constraints). It shrinks silently
  instead of throwing on unbounded axes.
* **Keep the glass host free of clipping that eats the backdrop** - the
  exact-refraction path needs the live backdrop, so ancestors that clip or
  repaint away the layer beneath (an opacity sandwich, an offstage
  repainter) can starve it. Prefer placing `LiquidGlass` directly in the
  same `Stack` as the backdrop - the analog of the original engine's
  "keep the glass host free of clipping rules" pitfall.
* **First frame looks frosted for one frame** - call
  `LiquidGlassEngine.warmUp()` in `main()` before `runApp`.
* **Slider changes feel instant because they are** - attribute-only
  uniform updates; watch `LiquidGlassEngine.metrics` to confirm `lutBuilds`
  is not moving.

## Repository layout

```
Liquid-Glass-Engine/
├── docs/                      # MATH.md, PERFORMANCE.md
├── packages/
│   ├── liquid_glass_core/     # pure Dart: exact Snell, LUT, cache, Bayer,
│   │                          #   raster encoder, metrics (41 unit tests)
│   └── liquid_glass_engine/   # Flutter: LiquidGlass widget, GLSL shader,
│       │                      #   loader, fallback, debug tools, tests
│   └── example/               # runnable demo with live sliders
└── .github/workflows/ci.yml   # dart test + flutter analyze/test
```

## License

MIT - see [LICENSE](LICENSE).
