import 'package:liquid_glass_core/liquid_glass_core.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    glassMetrics.reset();
    RefractionLutCache.debugReset();
  });

  const GlassLutKey key = GlassLutKey(thickness: 20, bezel: 26, ior: 1.5);

  group('RefractionLut', () {
    test('has 512 entries', () {
      expect(RefractionLut.size, 512);
      final RefractionLut lut = RefractionLut.build(key);
      expect(lut.values.length, 512);
    });

    test('normalized: max entry == 1, endpoints == 0', () {
      final RefractionLut lut = RefractionLut.build(key);
      expect(lut.values.first, 0.0);
      expect(lut.values.last, 0.0);
      final double max = lut.values.reduce(
        (double a, double b) => a > b ? a : b,
      );
      expect(max, closeTo(1.0, 1e-6));
    });

    test('peakS is strictly inside the bezel', () {
      final RefractionLut lut = RefractionLut.build(key);
      expect(lut.peakS, greaterThan(0.02));
      expect(lut.peakS, lessThan(0.98));
    });

    test('lerp lookup reproduces the exact trace within grid error', () {
      final RefractionLut lut = RefractionLut.build(key);
      double worst = 0;
      for (int i = 0; i <= 1000; i++) {
        final double s = i / 1000;
        final double exact = Snell.displacement(
          s: s,
          thickness: key.thickness,
          bezel: key.bezel,
          ior: key.ior,
        );
        final double lerped = lut.at(s) * lut.deltaMaxPx;
        final double err = (lerped - exact).abs();
        if (err > worst) worst = err;
      }
      // The profile rises steeply in the first rim cell (Delta goes 0 -> 1.2
      // px between s=0 and s=1/511 at the default config), so a uniform
      // 512-entry grid carries a sub-pixel worst-case lerp error there.
      // The Flutter GPU path evaluates the exact optics analytically per
      // pixel, so this bound only governs the CPU parity/encoder path.
      expect(worst, lessThan(0.35));
    });

    test('deterministic: identical rebuild', () {
      final RefractionLut a = RefractionLut.build(key);
      final RefractionLut b = RefractionLut.build(key);
      expect(a.deltaMaxPx, b.deltaMaxPx);
      for (int i = 0; i < RefractionLut.size; i++) {
        expect(a.values[i], b.values[i]);
      }
    });
  });

  group('RefractionLutCache (sharing & refcounts)', () {
    test('N same-optics elements share one LUT and one build', () {
      const GlassOptics optics = GlassOptics();
      final GlassLutKey k = optics.toLutKey(width: 353, height: 163);
      final List<RefractionLut> luts = List<RefractionLut>.generate(
        4,
        (_) => RefractionLutCache.acquire(k),
      );
      // One build, three cache hits, one live entry.
      expect(glassMetrics.lutBuilds, 1);
      expect(glassMetrics.lutCacheHits, 3);
      expect(glassMetrics.activeLuts, 1);
      expect(glassMetrics.lutEvictions, 0);

      // All four widgets hold the very same instance.
      for (final RefractionLut lut in luts) {
        expect(identical(lut, luts.first), isTrue);
      }

      // Release one of the four: still resident.
      RefractionLutCache.release(k);
      expect(RefractionLutCache.isCached(k), isTrue);
      expect(glassMetrics.activeLuts, 1);

      // Release the rest: evicted, nothing leaks.
      RefractionLutCache.release(k);
      RefractionLutCache.release(k);
      RefractionLutCache.release(k);
      expect(RefractionLutCache.isCached(k), isFalse);
      expect(glassMetrics.activeLuts, 0);
      expect(glassMetrics.lutEvictions, 1);
    });

    test('different geometry builds a different LUT', () {
      final RefractionLut a = RefractionLutCache.acquire(key);
      final RefractionLut b = RefractionLutCache.acquire(
        const GlassLutKey(thickness: 40, bezel: 26, ior: 1.5),
      );
      expect(identical(a, b), isFalse);
      expect(b.deltaMaxPx, greaterThan(a.deltaMaxPx));
      expect(glassMetrics.lutBuilds, 2);
      RefractionLutCache.release(key);
      RefractionLutCache.release(
        const GlassLutKey(thickness: 40, bezel: 26, ior: 1.5),
      );
    });

    test('bezel clamp makes capsule-sized elements share a LUT with pills', () {
      // A 999px bezel clamps to min(64,480)/2 = 32, equal to a 32px bezel.
      final RefractionLut clamped = RefractionLutCache.acquire(
        const GlassOptics(bezelWidth: 999).toLutKey(width: 64, height: 480),
      );
      final RefractionLut pill = RefractionLutCache.acquire(
        const GlassOptics(bezelWidth: 32).toLutKey(width: 64, height: 480),
      );
      expect(identical(clamped, pill), isTrue);
      expect(glassMetrics.lutBuilds, 1);
    });

    test('metrics summary stays parseable', () {
      RefractionLutCache.acquire(key);
      expect(glassMetrics.summary(), contains('lutBuilds=1'));
    });
  });
}
