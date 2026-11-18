/// Public API of `package:liquid_glass_engine`.
///
/// Import this package and wrap any subtree with [LiquidGlass] - there is
/// nothing to configure in the engine itself, no code to touch: the widget
/// probes the renderer, builds and shares caches, and degrades gracefully.
library;

import 'package:liquid_glass_core/liquid_glass_core.dart'
    show GlassMetrics, glassMetrics;

import 'src/render/program_loader.dart';

export 'src/render/program_loader.dart' show LiquidGlassProgram;

export 'package:liquid_glass_core/liquid_glass_core.dart'
    show
        BayerDither,
        DisplacementMap,
        DisplacementMapRaster,
        GlassLutKey,
        GlassOptics,
        RefractionLut,
        RefractionLutCache,
        RoundedRectSdf,
        Snell,
        RefractedRay;

export 'src/config.dart' show LiquidGlassConfig, LiquidGlassShape, ShapeKind;
export 'src/debug/map_preview.dart' show LiquidGlassMapPreview;
export 'src/render/liquid_glass.dart'
    show LiquidGlass, LiquidGlassMode;

/// Engine-level entry points.
///
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await LiquidGlassEngine.warmUp(); // compile the shader before frame 1
///   runApp(const MyApp());
/// }
/// ```
abstract final class LiquidGlassEngine {
  /// Compiles and caches the fragment program before the first frame.
  ///
  /// Safe to call multiple times; the load is memoized. Elements painted
  /// before warm-up simply render the soft fallback for a frame.
  static Future<void> warmUp() => LiquidGlassProgram.load();

  /// Live engine metrics - the analog of the web engine's
  /// `__QUICK_LIQUID__.metrics()`: LUT builds, cache hits/sharing, raster
  /// work (CPU encoder path) and timings.
  static GlassMetrics get metrics => glassMetrics;
}
