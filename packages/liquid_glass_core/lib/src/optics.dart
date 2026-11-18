/// Numeric optics configuration and derived geometry keys.
library;

import 'dart:math' as math;

/// Purely numeric glass configuration (the physics subset of
/// `LiquidGlassConfig` - no Flutter types, so it is testable on the VM).
///
/// Defaults mirror the QuickLiquid engine: `ior` 1.5, and a
/// `refractionStrength` of 22 px whose 8-bit quantization step is
/// `2M/255 ~= 0.17 px`.
class GlassOptics {
  const GlassOptics({
    this.thickness = 20.0,
    this.bezelWidth = 26.0,
    this.ior = 1.5,
    this.refractionStrength = 22.0,
    this.chromaticAberration = 0.0,
    this.frost = 0.0,
    this.saturation = 1.0,
  })  : assert(thickness > 0, 'thickness must be > 0'),
        assert(bezelWidth > 0, 'bezelWidth must be > 0'),
        assert(ior > 1.0, 'ior must be > 1 (glass is denser than air)'),
        assert(refractionStrength >= 0, 'refractionStrength must be >= 0'),
        assert(
          chromaticAberration >= 0 && chromaticAberration <= 1,
          'chromaticAberration must be in [0, 1]',
        ),
        assert(frost >= 0 && frost <= 1, 'frost must be in [0, 1]'),
        assert(saturation > 0, 'saturation must be > 0');

  /// Slab thickness `T` in logical px (config `thickness`).
  final double thickness;

  /// Bezel band width `B` in logical px (config `bezelWidth`).
  final double bezelWidth;

  /// Refractive index `n` (config `ior`, default 1.5).
  final double ior;

  /// Maximum displacement `M` in logical px (config `refractionStrength`).
  ///
  /// The physical profile `Delta(s)` is normalized by `Delta_max` and scaled
  /// linearly by `M`, so the slider is a pure linear zoom of the exact traced
  /// optics - identical to the SVG-filter engine's
  /// `map = Delta/Delta_max in [-1, 1]`, `scale S = 2M` encoding.
  final double refractionStrength;

  /// Chromatic aberration amount in [0, 1]. Dispersion is applied as the
  /// per-channel linear scales `S(1 - 0.10 ca)`, `S`, `S(1 + 0.14 ca)`
  /// (blue bends more; sampling is inward; real crown-glass ordering).
  final double chromaticAberration;

  /// Frost (surface blur) amount in [0, 1].
  final double frost;

  /// Backdrop saturation multiplier (1 = untouched).
  final double saturation;

  /// Bezel width clamped to `min(w, h)/2`.
  ///
  /// For pill/capsule shapes where `B > min(w,h)/2`, `B` is clamped so `s`
  /// reaches exactly 1 on the medial axis with zero slope - the bezel becomes
  /// a full smooth dome with no ridge artifact.
  double effectiveBezel(double width, double height) {
    final double cap = math.min(width, height) / 2;
    return bezelWidth.clamp(0.0, cap).toDouble();
  }

  /// LUT cache key for this optics at a given element size.
  ///
  /// `Delta(s)` depends only on `(T, B, n)` - never on position or element
  /// size - so the key is `(thickness, effectiveBezel, ior)`. The element
  /// size enters only through the `min(w,h)/2` clamp above.
  GlassLutKey toLutKey({required double width, required double height}) =>
      GlassLutKey(
        thickness: thickness,
        bezel: effectiveBezel(width, height),
        ior: ior,
      );

  GlassOptics copyWith({
    double? thickness,
    double? bezelWidth,
    double? ior,
    double? refractionStrength,
    double? chromaticAberration,
    double? frost,
    double? saturation,
  }) =>
      GlassOptics(
        thickness: thickness ?? this.thickness,
        bezelWidth: bezelWidth ?? this.bezelWidth,
        ior: ior ?? this.ior,
        refractionStrength: refractionStrength ?? this.refractionStrength,
        chromaticAberration: chromaticAberration ?? this.chromaticAberration,
        frost: frost ?? this.frost,
        saturation: saturation ?? this.saturation,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlassOptics &&
          other.thickness == thickness &&
          other.bezelWidth == bezelWidth &&
          other.ior == ior &&
          other.refractionStrength == refractionStrength &&
          other.chromaticAberration == chromaticAberration &&
          other.frost == frost &&
          other.saturation == saturation;

  @override
  int get hashCode => Object.hash(
        thickness,
        bezelWidth,
        ior,
        refractionStrength,
        chromaticAberration,
        frost,
        saturation,
      );

  @override
  String toString() =>
      'GlassOptics(T=$thickness, B=$bezelWidth, n=$ior, M=$refractionStrength, '
      'ca=$chromaticAberration, frost=$frost, sat=$saturation)';
}

/// Cache key of one refraction LUT: `(T, B_effective, n)`.
///
/// The displacement profile is scale-free with respect to element size, so
/// thousands of differently-positioned, same-optics elements share one LUT.
class GlassLutKey {
  const GlassLutKey({
    required this.thickness,
    required this.bezel,
    required this.ior,
  });

  final double thickness;
  final double bezel;
  final double ior;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlassLutKey &&
          other.thickness == thickness &&
          other.bezel == bezel &&
          other.ior == ior;

  @override
  int get hashCode => Object.hash(thickness, bezel, ior);

  @override
  String toString() => 'GlassLutKey(T=$thickness, B=$bezel, n=$ior)';
}
