import 'package:liquid_glass_core/liquid_glass_core.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    glassMetrics.reset();
    RefractionLutCache.debugReset();
  });

  const GlassOptics optics = GlassOptics(); // T=20, B=26, n=1.5, M=22
  final GlassLutKey key = optics.toLutKey(width: 522, height: 621);
  final RefractionLut lut = RefractionLutCache.acquire(key);

  DisplacementMap build(double w, double h, double r, {bool dither = true}) =>
      DisplacementMapRaster.build(
        width: w,
        height: h,
        radius: r,
        optics: optics,
        lut: lut,
        dither: dither,
      );

  group('Bayer dither', () {
    test('offsets live in [-0.5, 0.5) LSB units', () {
      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
          final double v = BayerDither.offset(x, y);
          expect(v, greaterThanOrEqualTo(-0.5));
          expect(v, lessThan(0.5));
        }
      }
    });

    test('tiles every 4x4 px and is bias-free over one tile', () {
      double sum = 0;
      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
          sum += BayerDither.offset(x, y);
          expect(BayerDither.offset(x, y), BayerDither.offset(x + 8, y + 12));
        }
      }
      expect(sum, closeTo(0.0, 1e-12));
    });

    test('all 16 phases are distinct', () {
      final Set<double> phases = <double>{
        for (int y = 0; y < 4; y++)
          for (int x = 0; x < 4; x++) BayerDither.offset(x, y),
      };
      expect(phases.length, 16);
    });
  });

  group('band-limited raster', () {
    test('neutral pre-fill: outside and flat-center stay (128, 128)', () {
      final DisplacementMap map = build(522, 621, 28);
      // Far corner (outside the shape): neutral.
      expect(map.decodeDx(1, 1), 0.0);
      expect(map.decodeDy(1, 1), 0.0);
      // Center (flat glass): neutral.
      expect(map.decodeDx(261, 310), 0.0);
      expect(map.decodeDy(261, 310), 0.0);

      // Count touched pixels by the geometric band definition (pixels whose
      // pixel-center inward distance is in (0, B)) - dithered writes can land
      // exactly on 128, so a byte scan would under-count.
      int band = 0;
      final double halfW = map.widthPx / 2;
      final double halfH = map.heightPx / 2;
      for (int y = 0; y < map.heightPx; y++) {
        final double py = y - (map.heightPx - 1) / 2;
        for (int x = 0; x < map.widthPx; x++) {
          final double px = x - (map.widthPx - 1) / 2;
          final double d = RoundedRectSdf.inwardDistance(
            px,
            py,
            halfW,
            halfH,
            28,
          );
          if (d > 0 && d < optics.effectiveBezel(522, 621)) band++;
        }
      }
      expect(band, map.bandPixels);
      expect(map.bandPixels, greaterThan(0));
    });

    test('522x621 panel iterates the band, not the full map', () {
      final DisplacementMap map = build(522, 621, 28);
      expect(map.fullPixels, 324162);
      // perimeter x B ~ 58k - several times fewer than full res.
      expect(map.fullPixels / map.bandPixels, greaterThan(4.0));
    });

    test('353x163 demo cards touch only the bezel band', () {
      final DisplacementMap map = build(353, 163, 26);
      expect(map.fullPixels, 353 * 163);
      // The whole height (163) is inside 2B (52), so the band dominates -
      // it is still strictly fewer than full-res pixels.
      expect(map.bandPixels, lessThan(map.fullPixels));
    });

    test('metrics record the raster work', () {
      glassMetrics.reset();
      build(522, 621, 28);
      expect(glassMetrics.rasterMapsBuilt, 1);
      expect(glassMetrics.rasterBandPixels, greaterThan(0));
      expect(glassMetrics.rasterFullPixels, 324162);
      expect(glassMetrics.rasterTimeUs, greaterThanOrEqualTo(0));
      expect(
        glassMetrics.summary(),
        contains('bandPixels=${glassMetrics.rasterBandPixels}'),
      );
    });

    test('degenerate bezel produces a fully neutral map', () {
      final GlassLutKey zeroKey = const GlassOptics(bezelWidth: 1e-9)
          .toLutKey(width: 64, height: 64);
      final DisplacementMap map = DisplacementMapRaster.build(
        width: 64,
        height: 64,
        radius: 16,
        optics: const GlassOptics(bezelWidth: 1e-9),
        lut: RefractionLutCache.acquire(zeroKey),
      );
      expect(map.bandPixels, 0);
      expect(map.bytes.every((int b) => b == 0x80 || b == 0xFF), isTrue);
    });
  });

  group('mirror symmetry (odd field)', () {
    test('without dither, dx(w-x, y) == -dx(x, y) to within rounding', () {
      final DisplacementMap map = build(353, 163, 26, dither: false);
      for (int y = 2; y < 160; y += 9) {
        for (int x = 3; x < 170; x += 7) {
          final int xm = 352 - x;
          // Byte rounding of the odd signal leaves at most 1/2 LSB on the sum.
          expect(
            (map.decodeDx(xm, y) + map.decodeDx(x, y)).abs(),
            lessThan(1.1 / 127.5),
            reason: 'x=$x y=$y',
          );
        }
      }
      for (int y = 3; y < 80; y += 7) {
        for (int x = 2; x < 350; x += 9) {
          final int ym = 162 - y;
          expect(
            (map.decodeDy(x, ym) + map.decodeDy(x, y)).abs(),
            lessThan(1.1 / 127.5),
            reason: 'x=$x y=$y',
          );
        }
      }
    });

    test('with dither on, the odd symmetry holds within 2 LSB', () {
      final DisplacementMap map = build(353, 163, 26);
      for (int y = 2; y < 160; y += 11) {
        for (int x = 3; x < 170; x += 13) {
          final int xm = 352 - x;
          final double sum = map.decodeDx(xm, y) + map.decodeDx(x, y);
          expect(sum.abs(), lessThan(2.0 / 127.5), reason: 'x=$x y=$y');
        }
      }
    });
  });

  group('minimal-loss 8-bit encoding', () {
    test('values cover the full 0..255 range (normalized [-1, 1])', () {
      final DisplacementMap map = build(353, 163, 26);
      int min = 255, max = 0;
      for (int i = 0; i < map.bytes.length; i += 4) {
        final int b = map.bytes[i];
        if (b < min) min = b;
        if (b > max) max = b;
      }
      expect(min, lessThanOrEqualTo(6)); // dx = -1 must saturate near 0
      expect(max, greaterThanOrEqualTo(249)); // dx = +1 near 255
    });

    test('quantization error stays within ½LSB + ½LSB dither', () {
      final DisplacementMap map = build(353, 163, 26);
      final double halfW = map.widthPx / 2;
      final double halfH = map.heightPx / 2;
      final double bezel = optics.effectiveBezel(353, 163);
      double worst = 0;
      for (int y = 0; y < map.heightPx; y += 1) {
        for (int x = 0; x < map.widthPx; x += 1) {
          final double px = x - (map.widthPx - 1) / 2;
          final double py = y - (map.heightPx - 1) / 2;
          final double d = RoundedRectSdf.inwardDistance(
            px,
            py,
            halfW,
            halfH,
            26,
          );
          if (d <= 0 || d >= bezel) continue;
          final double s = (d / bezel).clamp(0.0, 1.0);
          final double deltaHat = lut.at(s);
          final (double, double) m = RoundedRectSdf.outwardDirection(
            px,
            py,
            halfW,
            halfH,
            26,
          );
          final double err = (map.decodeDx(x, y) + m.$1 * deltaHat).abs();
          final double errY = (map.decodeDy(x, y) + m.$2 * deltaHat).abs();
          if (err > worst) worst = err;
          if (errY > worst) worst = errY;
        }
      }
      // ½ byte-LSB of quantization + ½ LSB of dither, in normalized units.
      expect(worst, lessThan(1.0 / 127.5 + 1e-9));
    });

    test('loss-minimizing filter scale is S = 2M (0.17 px step at M = 22)', () {
      final DisplacementMap map = build(353, 163, 26);
      expect(map.suggestedScale, 44.0);
      // Quantization step in offset space: S/255.
      final double stepPx = map.suggestedScale / 255;
      expect(stepPx, closeTo(44.0 / 255.0, 1e-12));
      expect(stepPx, lessThan(0.173)); // ~ M/127
    });

    test('four same-optics cards share one LUT build', () {
      glassMetrics.reset();
      RefractionLutCache.debugReset();
      final GlassLutKey k = optics.toLutKey(width: 353, height: 163);
      for (int i = 0; i < 4; i++) {
        RefractionLutCache.acquire(k);
      }
      expect(glassMetrics.lutBuilds, 1);
      expect(glassMetrics.lutCacheHits, 3);
      expect(glassMetrics.activeLuts, 1);
      for (int i = 0; i < 4; i++) {
        RefractionLutCache.release(k);
      }
      expect(glassMetrics.activeLuts, 0);
    });
  });
}
