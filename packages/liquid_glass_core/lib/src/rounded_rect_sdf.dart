/// Analytic rounded-rect signed distance field and its outward gradient.
///
/// The rounded-rect SDF and its gradient `m_hat` are analytic
/// (corner-circle branch + edge branches), so there are no finite-difference
/// probes - the previous engine used 4 extra SDF evaluations per pixel for
/// the gradient, a 5x overhead, removed.
///
/// Sign convention: `distance < 0` INSIDE the shape, `> 0` outside.
library;

import 'dart:math' as math;

/// Analytic rounded-rectangle SDF.
class RoundedRectSdf {
  const RoundedRectSdf._();

  /// Signed distance from `(px, py)` to the boundary of a rounded rect
  /// centered at the origin with half extents `halfW x halfH` and corner
  /// radius `radius`.
  ///
  /// Negative inside, positive outside, zero on the boundary.
  /// Edge branches: `min(max(qx, qy), 0)`; corner branch: `length(max(q, 0))`.
  static double distance(
    double px,
    double py,
    double halfW,
    double halfH,
    double radius,
  ) {
    // q is intentionally NOT clamped here: the negative values feed the
    // interior (edge) branch.
    final double qx = px.abs() - (halfW - radius);
    final double qy = py.abs() - (halfH - radius);
    final double cornerX = qx > 0 ? qx : 0.0;
    final double cornerY = qy > 0 ? qy : 0.0;
    final double inside = math.min(math.max(qx, qy), 0.0);
    return math.sqrt(cornerX * cornerX + cornerY * cornerY) + inside - radius;
  }

  /// Inward distance from the boundary (positive inside the shape).
  static double inwardDistance(
    double px,
    double py,
    double halfW,
    double halfH,
    double radius,
  ) =>
      -distance(px, py, halfW, halfH, radius);

  /// Unit outward direction `m_hat` at `(px, py)`.
  ///
  /// * Corner branch (`qx > 0 && qy > 0`): radial direction of the corner
  ///   circle, `normalize(qx, qy)` with the signs of `p`.
  /// * Edge branch: the axis of whichever side is nearest.
  ///
  /// Returns `(1, 0)` for interior points of the flat region (the value is
  /// unused there because `Delta = 0`).
  static (double, double) outwardDirection(
    double px,
    double py,
    double halfW,
    double halfH,
    double radius,
  ) {
    final double sx = px >= 0 ? 1.0 : -1.0;
    final double sy = py >= 0 ? 1.0 : -1.0;
    final double qx = px.abs() - (halfW - radius);
    final double qy = py.abs() - (halfH - radius);
    // Edge branch zeroes one axis; corner branch keeps both.
    double mx = sx * (qx > 0 ? qx : 0.0);
    double my = sy * (qy > 0 ? qy : 0.0);
    final double len = math.sqrt(mx * mx + my * my);
    if (len < 1e-12) return (sx, 0);
    mx /= len;
    my /= len;
    return (mx, my);
  }
}
