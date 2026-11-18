/// Band-limited, mirror-symmetric, Bayer-dithered 8-bit displacement map.
///
/// This is the CPU encoder from the QuickLiquid specification (used for
/// parity tests, debugging, exporting maps for SVG-style
/// `feDisplacementMap` pipelines, and the map preview widget). The Flutter
/// GPU path does not quantize at all - it evaluates the exact optics in
/// float on the GPU - but this encoder proves the same "lowest possible
/// quality loss" bound documented for 8-bit pipelines.
///
/// * Pixels with `d >= B` (flat center) and `d <= 0` (outside) are exactly
///   neutral `(128, 128)`: the buffer is pre-filled with one fill and only
///   the bezel band is written - `~perimeter x B` pixels instead of `w x h`.
/// * The displacement field is odd under mirroring:
///   `dx(w-x, y) = -dx(x, y)`, `dy(x, h-y) = -dy(x, y)`.
///   One quadrant is computed; up to four pixels are written per evaluation.
/// * Map values are `Delta/Delta_max in [-1, 1]` over the full `0..255`
///   range, so the loss-minimizing filter scale is the smallest one that
///   still covers `+/-M`: `S = 2M`. The quantization step in offset space is
///   then `2M/255 ~= M/127` (e.g. 0.17 px at M = 22), independent of how much
///   of the value range the map uses.
/// * A 4x4 ordered Bayer dither (±½ LSB) decorrelates the residual
///   quantization into spatially white noise.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'bayer.dart';
import 'glass_metrics.dart';
import 'optics.dart';
import 'refraction_lut.dart';
import 'rounded_rect_sdf.dart';

/// A built displacement map plus its build statistics.
class DisplacementMap {
  const DisplacementMap({
    required this.bytes,
    required this.widthPx,
    required this.heightPx,
    required this.bandPixels,
    required this.bezelPx,
    required this.suggestedScale,
  });

  /// RGBA bytes, row-major, `widthPx * heightPx * 4`.
  ///
  /// R encodes `dx`, G encodes `dy` (each `Delta_hat in [-1, 1]` spread over
  /// `0..255`); B is neutral; A is opaque.
  final Uint8List bytes;

  final int widthPx;
  final int heightPx;

  /// Pixels actually written (the bezel band only).
  final int bandPixels;

  /// Full-resolution pixel count (`widthPx * heightPx`).
  int get fullPixels => widthPx * heightPx;

  /// The effective (clamped) bezel width used, in logical px.
  final double bezelPx;

  /// The loss-minimizing displacement scale for consumers of this map:
  /// `S = 2M` px, where `M` is the max displacement.
  final double suggestedScale;

  /// Byte index of pixel `(x, y)`.
  int byteIndex(int x, int y) => (y * widthPx + x) * 4;

  /// Decodes the normalized `dx` at pixel `(x, y)`: byte 128 == exactly 0.
  double decodeDx(int x, int y) =>
      (bytes[byteIndex(x, y)] - 128) / 127.5;

  /// Decodes the normalized `dy` at pixel `(x, y)`.
  double decodeDy(int x, int y) =>
      (bytes[byteIndex(x, y) + 1] - 128) / 127.5;
}

/// Builds [DisplacementMap]s with the band/mirror/dither optimizations.
class DisplacementMapRaster {
  const DisplacementMapRaster._();

  /// Neutral level of each displacement axis.
  static const int neutral = 128;

  /// Builds the 8-bit displacement map for one element.
  ///
  /// `width`/`height`/`radius` are in logical px (map resolution 1:1);
  /// `optics` supplies the bezel/thickness/ior and the max displacement `M`
  /// (via [GlassOptics.refractionStrength]); `lut` must be the LUT built
  /// for `optics.toLutKey(width: width, height: height)`.
  static DisplacementMap build({
    required double width,
    required double height,
    required double radius,
    required GlassOptics optics,
    required RefractionLut lut,
    bool dither = true,
  }) {
    final int wPx = width.round();
    final int hPx = height.round();
    final int full = wPx * hPx;
    final Uint8List bytes = Uint8List(full * 4);

    // One pre-fill of neutral (128, 128) - outside and flat-center pixels
    // are exactly neutral and never touched again.
    final int neutralPacked = 0xFF808080; // A=255, B=128, G=128, R=128 (LE)
    final Uint32List words = bytes.buffer.asUint32List();
    words.fillRange(0, full, neutralPacked);

    final Stopwatch watch = Stopwatch()..start();

    final double bezel = optics.effectiveBezel(width, height);
    int bandPixels = 0;

    if (bezel > 0 && wPx > 0 && hPx > 0) {
      final double halfW = wPx / 2;
      final double halfH = hPx / 2;
      final double r = radius.clamp(0.0, math.min(halfW, halfH));

      // Iterate one quadrant; mirror x/y write the other three.
      for (int y = 0; y < (hPx + 1) >> 1; y++) {
        final double py = y - (hPx - 1) / 2;
        final int ym = hPx - 1 - y;
        final bool ySame = ym == y;
        for (int x = 0; x < (wPx + 1) >> 1; x++) {
          final double px = x - (wPx - 1) / 2;
          final int xm = wPx - 1 - x;
          final bool xSame = xm == x;

          final double d = RoundedRectSdf.inwardDistance(
            px,
            py,
            halfW,
            halfH,
            r,
          );
          // Band limiting: flat center and outside stay neutral.
          if (d <= 0 || d >= bezel) continue;

          final double s = (d / bezel).clamp(0.0, 1.0);
          final double deltaHat = lut.at(s);
          final (double, double) m = RoundedRectSdf.outwardDirection(
            px,
            py,
            halfW,
            halfH,
            r,
          );
          // Sampling is INWARD: dx,dy = -m_hat . Delta_hat(s).
          final double dx = -m.$1 * deltaHat;
          final double dy = -m.$2 * deltaHat;

          void write(int xx, int yy, {required bool flipX, required bool flipY}) {
            // The field is odd under mirroring: dx(w-x,y) = -dx(x,y) and
            // dy(x,h-y) = -dy(x,y), so mirrored writes flip the odd axes.
            final double wx = flipX ? -dx : dx;
            final double wy = flipY ? -dy : dy;
            final int i = (yy * wPx + xx) * 4;
            // Byte-space dither of +/- ½ LSB (the 4x4 Bayer pattern).
            // Byte-space dither of +/- ½ LSB: one byte step is 2/255 in
            // normalized units, so the Bayer phase is scaled accordingly.
            final double dth = dither
                ? BayerDither.offsetNormalized(xx, yy, 2.0 / 255.0)
                : 0.0;
            bytes[i] = _toByte(wx + dth);
            bytes[i + 1] = _toByte(wy + dth);
            bandPixels++;
          }

          write(x, y, flipX: false, flipY: false);
          if (!xSame) write(xm, y, flipX: true, flipY: false);
          if (!ySame) write(x, ym, flipX: false, flipY: true);
          if (!xSame && !ySame) write(xm, ym, flipX: true, flipY: true);
        }
      }
    }

    watch.stop();
    glassMetrics.recordRaster(
      bandPixels: bandPixels,
      fullPixels: full,
      microseconds: watch.elapsedMicroseconds,
    );

    return DisplacementMap(
      bytes: bytes,
      widthPx: wPx,
      heightPx: hPx,
      bandPixels: bandPixels,
      bezelPx: bezel,
      suggestedScale: 2 * optics.refractionStrength,
    );
  }

  /// Encodes a normalized displacement in [-1, 1] as a byte: 128 == 0.
  static int _toByte(double v) {
    final int b = (128.0 + v * 127.5).round();
    if (b < 0) return 0;
    if (b > 255) return 255;
    return b;
  }
}
