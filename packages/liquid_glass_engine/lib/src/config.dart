/// Presentation-layer configuration for the [LiquidGlass] widget.
///
/// The numeric physics live in [GlassOptics] (pure Dart, testable on the
/// VM); this class adds the Flutter-side knobs: shape, light direction,
/// rim intensity and tint.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:liquid_glass_core/liquid_glass_core.dart';

/// Shape of the glass element.
class LiquidGlassShape {
  const LiquidGlassShape._(this.kind, this.radius);

  /// Rounded rectangle with an explicit corner radius.
  const LiquidGlassShape.rounded(double radius)
      : this._(ShapeKind.roundedRect, radius);

  /// Capsule (pill): the radius is `min(w, h) / 2`.
  const LiquidGlassShape.capsule() : this._(ShapeKind.capsule, 0.0);

  /// Circle: a capsule whose width equals its height.
  const LiquidGlassShape.circle() : this._(ShapeKind.capsule, 0.0);

  final ShapeKind kind;

  /// Corner radius in logical px (only for [ShapeKind.roundedRect]).
  final double radius;

  /// Effective corner radius at a given element [size].
  ///
  /// Capsules clamp to `min(w, h) / 2`; rounded rects clamp their radius to
  /// the same bound so a large radius degrades into a capsule gracefully.
  double resolvedRadius(Size size) {
    final double cap = math.min(size.width, size.height) / 2;
    if (kind == ShapeKind.capsule) return cap;
    return radius.clamp(0.0, cap).toDouble();
  }
}

enum ShapeKind { roundedRect, capsule }

/// Everything the [LiquidGlass] widget needs to paint one element.
@immutable
class LiquidGlassConfig {
  const LiquidGlassConfig({
    this.shape = const LiquidGlassShape.rounded(24),
    this.optics = const GlassOptics(),
    this.lightAngleDeg = 135.0,
    this.rim = 1.0,
    this.tint = const Color(0x00000000),
  });

  /// Silhouette of the element (rounded rect, capsule, circle).
  final LiquidGlassShape shape;

  /// The optics: thickness `T`, bezel width `B`, `ior` `n`,
  /// `refractionStrength` `M`, `chromaticAberration`, `frost`,
  /// `saturation`. See [GlassOptics] for units and defaults.
  final GlassOptics optics;

  /// Direction of the rim light, in degrees clockwise from the +x axis
  /// measured on screen (0 = from the right, 135 = from the top-left, the
  /// classic highlight). Only affects the specular rim, never the lens.
  final double lightAngleDeg;

  /// Rim highlight intensity (0 disables the specular rim entirely).
  final double rim;

  /// Glass tint. Transparent by default; the tint is composited over the
  /// refracted backdrop with its own alpha.
  final Color tint;

  /// Unit light direction in logical (y-down) screen coordinates.
  Offset lightVector() {
    final double rad = lightAngleDeg * math.pi / 180.0;
    return Offset(math.cos(rad), -math.sin(rad));
  }

  LiquidGlassConfig copyWith({
    LiquidGlassShape? shape,
    GlassOptics? optics,
    double? lightAngleDeg,
    double? rim,
    Color? tint,
  }) =>
      LiquidGlassConfig(
        shape: shape ?? this.shape,
        optics: optics ?? this.optics,
        lightAngleDeg: lightAngleDeg ?? this.lightAngleDeg,
        rim: rim ?? this.rim,
        tint: tint ?? this.tint,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiquidGlassConfig &&
          other.shape == shape &&
          other.optics == optics &&
          other.lightAngleDeg == lightAngleDeg &&
          other.rim == rim &&
          other.tint == tint;

  @override
  int get hashCode => Object.hash(shape, optics, lightAngleDeg, rim, tint);

  @override
  String toString() =>
      'LiquidGlassConfig(shape=$shape, optics=$optics, light=$lightAngleDeg, '
      'rim=$rim, tint=$tint)';
}
