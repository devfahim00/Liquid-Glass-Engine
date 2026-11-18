/// The 1-D reduction of the exact refraction: a 512-entry LUT per geometry.
///
/// For fixed `(T, B, n)`, `Delta` depends only on `s` - not on position. The
/// engine therefore tabulates the exact traced `Delta(s)` into a 512-entry
/// [Float32List] once per geometry, normalizes it by
/// `Delta_max = max_s Delta(s)`, and per-pixel work collapses to:
///
/// ```text
/// SDF(x,y) -> d -> s -> lerp(LUT, s*512) -> dx,dy = -m_hat . Delta_hat(s)
/// ```
///
/// No trig, no sqrt (beyond the SDF's), no Snell per pixel.
library;

import 'dart:typed_data';

import 'glass_metrics.dart';
import 'optics.dart';
import 'snell.dart';

/// A normalized displacement profile for one geometry.
class RefractionLut {
  const RefractionLut._({
    required this.values,
    required this.deltaMaxPx,
    required this.peakS,
  });

  /// Number of entries (the QuickLiquid engine tabulates 512).
  static const int size = 512;

  /// `Delta(s) / Delta_max` sampled at `s = i / (size - 1)`, in `[0, 1]`.
  final Float32List values;

  /// `Delta_max` in logical px (the normalizer).
  final double deltaMaxPx;

  /// The `s` where `Delta` peaks (diagnostics; strictly inside `(0, 1)`).
  final double peakS;

  /// Builds the LUT for one geometry by tracing the exact Snell model.
  ///
  /// This is the only place the optics is evaluated; everything downstream
  /// (shader normalization, 8-bit encoder, tests) reads the table.
  static RefractionLut build(GlassLutKey key) {
    final Stopwatch watch = Stopwatch()..start();
    final Float32List raw = Float32List(size);
    double max = 0;
    int peakIndex = 0;
    for (int i = 0; i < size; i++) {
      final double s = i / (size - 1);
      final double v = Snell.displacement(
        s: s,
        thickness: key.thickness,
        bezel: key.bezel,
        ior: key.ior,
      );
      raw[i] = v;
      if (v > max) {
        max = v;
        peakIndex = i;
      }
    }
    watch.stop();
    glassMetrics.recordLutBuild(watch.elapsedMicroseconds);

    if (max <= 0) {
      // Degenerate geometry (e.g. bezel collapsed to zero): fully neutral.
      return RefractionLut._(
        values: Float32List(size),
        deltaMaxPx: 0,
        peakS: 0,
      );
    }
    final Float32List normalized = Float32List(size);
    for (int i = 0; i < size; i++) {
      normalized[i] = raw[i] / max;
    }
    return RefractionLut._(
      values: normalized,
      deltaMaxPx: max,
      peakS: peakIndex / (size - 1),
    );
  }

  /// Linearly interpolated `Delta(s)/Delta_max` at any `s` in `[0, 1]`.
  ///
  /// `lerp(LUT, s*512)` - the whole per-pixel lookup in one multiply.
  double at(double s) {
    if (s <= 0 || s >= 1) return 0;
    final double t = s * (size - 1);
    final int i = t.floor();
    if (i >= size - 1) return values[size - 1];
    final double frac = t - i;
    return values[i] + (values[i + 1] - values[i]) * frac;
  }

  /// Exact displacement in px at `s` for a given max-displacement `M`.
  double displacementAt(double s, double maxDisplacementPx) =>
      at(s) * maxDisplacementPx;
}

/// Refcounted, process-wide cache of [RefractionLut]s.
///
/// Maps are keyed by `(T, B_effective, n)` and refcounted: N same-optics
/// elements share one LUT and one generation cost. When the last user
/// releases a key the entry is evicted, so geometry changes never leak.
class RefractionLutCache {
  RefractionLutCache._();

  static final Map<GlassLutKey, _Entry> _entries = <GlassLutKey, _Entry>{};

  /// Returns the (possibly cached) LUT for [key], incrementing its refcount.
  static RefractionLut acquire(GlassLutKey key) {
    final _Entry? existing = _entries[key];
    if (existing != null) {
      existing.refs++;
      glassMetrics.recordLutCacheHit();
      return existing.lut;
    }
    final RefractionLut lut = RefractionLut.build(key);
    _entries[key] = _Entry(lut, 1);
    glassMetrics.recordLutEviction(false);
    return lut;
  }

  /// Drops one reference to [key]; evicts the entry when it hits zero.
  static void release(GlassLutKey key) {
    final _Entry? existing = _entries[key];
    if (existing == null) return;
    existing.refs--;
    if (existing.refs <= 0) {
      _entries.remove(key);
      glassMetrics.recordLutEviction(true);
    }
  }

  /// Number of live, shared LUTs (unique geometries currently in use).
  static int get activeLuts => _entries.length;

  /// Whether [key] is currently resident.
  static bool isCached(GlassLutKey key) => _entries.containsKey(key);

  static void debugReset() => _entries.clear();
}

class _Entry {
  _Entry(this.lut, this.refs);

  final RefractionLut lut;
  int refs;
}
