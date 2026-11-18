# Contributing

The engine is deliberately layered so changes stay contained:

- `packages/liquid_glass_core` - pure Dart optics. No `dart:ui` imports
  allowed; it must stay testable on a bare Dart VM. When changing physics,
  update `docs/MATH.md` and keep `scripts/crosscheck_optics.py` in
  agreement (the Python implementation is intentionally separate - it is
  the referee for the math).
- `packages/liquid_glass_engine` - Flutter rendering. Keep the public API
  additive-only (`LiquidGlass`, `LiquidGlassConfig`, `GlassOptics`,
  `LiquidGlassMode`, `LiquidGlassEngine`, `LiquidGlassProgram`,
  `LiquidGlassMapPreview`); integration must never require touching engine
  code.
- The fragment shader (`shaders/liquid_glass.frag`) is the exact optics in
  GLSL. Uniform slots 0..1 belong to the engine (the bound texture size);
  new uniforms continue from index 2, mirrored in
  `lib/src/render/liquid_glass.dart`.

Checks before opening a PR:

```sh
cd packages/liquid_glass_core && dart analyze && dart test
cd ../liquid_glass_engine && flutter analyze && flutter test
cd example && flutter analyze
```
