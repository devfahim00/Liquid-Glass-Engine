/// Engine metrics - the analog of the web engine's `__QUICK_LIQUID__.metrics()`.
library;

/// Global counters for cache behavior and raster work.
///
/// Read via `LiquidGlassEngine.metrics` from the Flutter package (or
/// `glassMetrics` directly from pure Dart).
class GlassMetrics {
  GlassMetrics();

  /// Total LUT builds (exact Snell tabulations).
  int lutBuilds = 0;

  /// Total LUT cache hits (a build was avoided and an entry shared).
  int lutCacheHits = 0;

  /// Live LUT cache entries (unique geometries currently in use).
  int get activeLuts => _activeLuts;
  int _activeLuts = 0;

  /// Total LUT evictions (last reference released).
  int lutEvictions = 0;

  /// Total time spent building LUTs, in microseconds.
  int lutBuildTimeUs = 0;

  /// Displacement-map rasters built (CPU/debug/export path).
  int rasterMapsBuilt = 0;

  /// Band pixels written by the rasterizer (vs [rasterFullPixels]).
  int rasterBandPixels = 0;

  /// Full-resolution pixel count of the rasterized maps.
  int rasterFullPixels = 0;

  /// Rasterization time, in microseconds.
  int rasterTimeUs = 0;

  /// Records one LUT build of [microseconds].
  void recordLutBuild(int microseconds) {
    lutBuilds++;
    lutBuildTimeUs += microseconds;
    _activeLuts++;
  }

  /// Records one cache hit.
  void recordLutCacheHit() => lutCacheHits++;

  /// Records a LUT cache eviction or insertion.
  void recordLutEviction(bool evicted) {
    if (evicted) {
      lutEvictions++;
      _activeLuts--;
    }
  }

  /// Records one displacement-map raster.
  void recordRaster({
    required int bandPixels,
    required int fullPixels,
    required int microseconds,
  }) {
    rasterMapsBuilt++;
    rasterBandPixels += bandPixels;
    rasterFullPixels += fullPixels;
    rasterTimeUs += microseconds;
  }

  /// Resets all counters (debugging/tests).
  void reset() {
    lutBuilds = 0;
    lutCacheHits = 0;
    _activeLuts = 0;
    lutEvictions = 0;
    lutBuildTimeUs = 0;
    rasterMapsBuilt = 0;
    rasterBandPixels = 0;
    rasterFullPixels = 0;
    rasterTimeUs = 0;
  }

  /// Human-readable summary, mirroring the web engine's metrics panel.
  String summary() {
    final StringBuffer b = StringBuffer('LiquidGlass metrics: ');
    b.write('lutBuilds=$lutBuilds');
    b.write(', lutCacheHits=$lutCacheHits');
    b.write(', activeLuts=$_activeLuts');
    b.write(', lutBuildTime=${lutBuildTimeUs}us');
    if (rasterMapsBuilt > 0) {
      final double ratio = rasterFullPixels / rasterBandPixels;
      b.write(', rasterMaps=$rasterMapsBuilt');
      b.write(', bandPixels=$rasterBandPixels/$rasterFullPixels');
      b.write(' (x${ratio.toStringAsFixed(1)} fewer)');
      b.write(', rasterTime=${rasterTimeUs}us');
    }
    return b.toString();
  }
}

/// The process-wide metrics instance.
final GlassMetrics glassMetrics = GlassMetrics();
