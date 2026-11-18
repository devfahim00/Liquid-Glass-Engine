/// Pure-Dart optics core for the Liquid Glass Engine.
///
/// This library is intentionally free of any `dart:ui` / Flutter dependency
/// so the physics is unit-testable on a plain Dart VM and reusable from any
/// rendering stack. The Flutter bindings live in
/// `package:liquid_glass_engine`.
///
/// The model implemented here is the QuickLiquid optics specification:
///
/// * Glass slab of refractive index `n` and thickness `T`, resting on the
///   backdrop plane.
/// * Convex circular-arc (quarter-ellipse) bezel of width `B` at the edge:
///   `z(s) = T*sqrt(s(2-s))`, slope `sigma(s) = (T/B)(1-s)/sqrt(s(2-s))`.
/// * Exact Snell refraction for an orthographic view ray, giving the
///   screen-space displacement `Delta(s) = z(s) * |t_xy / t_z|`.
/// * A 512-entry 1-D LUT of `Delta(s)` normalized by `Delta_max`, refcounted
///   per geometry so N same-shape elements share one build.
/// * A band-limited, mirror-symmetric, Bayer-dithered 8-bit displacement-map
///   rasterizer (parity with the original SVG-filter encoder).
library;

export 'src/bayer.dart';
export 'src/glass_metrics.dart';
export 'src/optics.dart';
export 'src/raster_map.dart';
export 'src/refraction_lut.dart';
export 'src/rounded_rect_sdf.dart';
export 'src/snell.dart';
