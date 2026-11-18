/// Exact Snell refraction for the QuickLiquid glass model.
///
/// The element is a solid glass slab of refractive index `n` (config `ior`)
/// and thickness `T` (CSS px) resting directly on the backdrop plane. Its top
/// face is flat in the center and rolls off through a convex circular-arc
/// bezel of width `B` at the shape's edge.
///
/// With `d` = inward distance from the shape boundary and `s = d / B`:
///
/// ```text
/// height   z(s) = T . sqrt(s (2 - s))          (quarter-ellipse arc)
/// slope    sigma(s) = |dz/dd| = (T/B) (1 - s) / sqrt(s (2 - s))
/// ```
///
/// `sigma -> infinity` at the rim (vertical glass wall) and `sigma -> 0` at
/// `s = 1` where the bezel meets the flat top with C1 continuity - no visible
/// seam.
///
/// An orthographic view ray `v = (0, 0, -1)` strikes the tilted surface with
/// unit normal `n_hat = (sigma . m_hat, 1) / sqrt(1 + sigma^2)`. Snell's law
/// in vector form (eta = 1/n, air -> glass):
///
/// ```text
/// sin theta_i = sigma / sqrt(1 + sigma^2)      cos theta_i = 1 / sqrt(1+sigma^2)
/// sin theta_t = eta . sin theta_i               cos theta_t = sqrt(1 - sin^2 theta_t)
/// t = eta v + (eta cos theta_i - cos theta_t) . n_hat
///
/// t_xy = (eta cos theta_i - cos theta_t) . sin theta_i     (lateral, < 0 => INWARD)
/// t_z  = -eta + (eta cos theta_i - cos theta_t) cos theta_i (downward)
/// ```
///
/// The ray travels through glass depth `z(s)` to the flat bottom face; the
/// bottom interface adds no further lateral shift when the backdrop sits at
/// the exit plane, so the total screen-space displacement is
/// `Delta(s) = z(s) . |t_xy / t_z|`.
///
/// Properties that emerge (nothing is hand-tuned):
///
/// * `Delta(0) = 0` - the rim is continuous with the outside (`z -> 0` wins
///   over `sigma -> infinity`; the limit of `z tan(phi)` is 0 because
///   `tan(phi) -> sqrt(1-eta^2)/eta` is finite).
/// * `Delta(1) = 0` - flat center, perfectly clear glass.
/// * `Delta` peaks inside the bezel band - the signature
///   "clear center, bent rim".
/// * Sampling is inward (magnifier / water-droplet behavior).
library;

import 'dart:math' as math;

/// Cross-section components of the traced refracted ray at one `s`.
///
/// `tXy` is the lateral component along the outward direction `m_hat`
/// (negative => the ray bends INWARD), `tZ` the vertical component
/// (negative => downward into the glass).
class RefractedRay {
  const RefractedRay({
    required this.sinI,
    required this.cosI,
    required this.sinT,
    required this.cosT,
    required this.tXy,
    required this.tZ,
  });

  /// sin of the incidence angle (measured from the surface normal).
  final double sinI;

  /// cos of the incidence angle.
  final double cosI;

  /// sin of the transmitted (in-glass) angle.
  final double sinT;

  /// cos of the transmitted angle.
  final double cosT;

  /// Lateral component of the refracted direction, in units of `m_hat`.
  final double tXy;

  /// Vertical component of the refracted direction.
  final double tZ;

  /// Bend ratio: lateral drift magnitude per unit of vertical descent,
  /// `|tXy / tZ|`. Bounded by `Snell.rimRatio(ior)` for every `s`.
  double get bendRatio => (tXy / tZ).abs();
}

/// Static exact-Snell math. No state, no approximation.
class Snell {
  const Snell._();

  /// Glass surface height at bezel parameter `s`: `z(s) = T sqrt(s(2-s))`.
  ///
  /// `z(0) = 0` at the rim, `z(1) = T` where the bezel meets the flat top.
  static double height(double s, double thickness) {
    if (s <= 0) return 0;
    if (s >= 1) return thickness;
    return thickness * math.sqrt(s * (2 - s));
  }

  /// Surface slope `|dz/dd|` at bezel parameter `s`.
  ///
  /// Infinite at the rim (`s = 0`, vertical glass wall), zero at `s = 1`
  /// (C1 join with the flat top).
  static double slope(double s, double thickness, double bezel) {
    if (s <= 0) return double.infinity;
    if (s >= 1) return 0;
    return (thickness / bezel) * (1 - s) / math.sqrt(s * (2 - s));
  }

  /// Trace the refracted ray for an orthographic view ray at `s`.
  ///
  /// All inputs are in logical pixels; the returned components are unitless
  /// direction components of `t` (the refracted direction).
  static RefractedRay ray({
    required double s,
    required double thickness,
    required double bezel,
    required double ior,
  }) {
    final double sigma = slope(s, thickness, bezel);
    // cos theta_i = 1/sqrt(1+sigma^2), sin theta_i = sigma/sqrt(1+sigma^2).
    final double cosI = 1 / math.sqrt(1 + sigma * sigma);
    final double sinI = sigma * cosI;
    final double eta = 1 / ior;
    final double sinT = eta * sinI;
    final double cosT = math.sqrt(1 - sinT * sinT);
    final double k = eta * cosI - cosT; // < 0 for n > 1
    return RefractedRay(
      sinI: sinI,
      cosI: cosI,
      sinT: sinT,
      cosT: cosT,
      tXy: k * sinI,
      tZ: -eta + k * cosI,
    );
  }

  /// Exact screen-space displacement `Delta(s)` in logical px.
  ///
  /// Zero at the rim and at the flat top; peaks inside the bezel band.
  static double displacement({
    required double s,
    required double thickness,
    required double bezel,
    required double ior,
  }) {
    if (s <= 0 || s >= 1) return 0;
    final RefractedRay r = ray(
      s: s,
      thickness: thickness,
      bezel: bezel,
      ior: ior,
    );
    return height(s, thickness) * (r.tXy / r.tZ).abs();
  }

  /// The `sigma -> infinity` limit of `|t_xy / t_z|` at the rim:
  /// `sqrt(1 - eta^2) / eta`, finite for every `n > 1`.
  ///
  /// This is why `Delta(s)` is continuous with the outside: the surface
  /// height vanishes while the bend ratio stays bounded.
  static double rimRatio(double ior) {
    final double eta = 1 / ior;
    return math.sqrt(1 - eta * eta) / eta;
  }
}
