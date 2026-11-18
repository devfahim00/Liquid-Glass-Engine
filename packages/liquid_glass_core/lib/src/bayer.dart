/// 4x4 ordered Bayer dither for the 8-bit displacement encoder.
///
/// A +/- half-LSB ordered dither (~2 ops/px) decorrelates the residual
/// quantization into spatially white noise - banding contours become
/// physically invisible at 0.1-px amplitude.
library;

/// Ordered-dither helper (4x4 Bayer matrix).
class BayerDither {
  const BayerDither._();

  static const List<List<int>> matrix4x4 = <List<int>>[
    <int>[0, 8, 2, 10],
    <int>[12, 4, 14, 6],
    <int>[3, 11, 1, 9],
    <int>[15, 7, 13, 5],
  ];

  /// Dither offset in LSB units for pixel `(x, y)`, in `[-0.5, 0.5)`.
  ///
  /// The pattern tiles every 4x4 px; the mean over one tile is exactly 0 so
  /// the dither is bias-free.
  static double offset(int x, int y) =>
      ((matrix4x4[y & 3][x & 3] + 0.5) / 16.0) - 0.5;

  /// Dither offset in normalized map units, where one LSB is [lsbValue].
  ///
  /// For an 8-bit map covering `[-1, 1]`, one LSB is `2/255`; pass that (or
  /// the equivalent for your encoding) and the returned offset is bounded by
  /// half a LSB.
  static double offsetNormalized(int x, int y, double lsbValue) =>
      offset(x, y) * lsbValue;
}
