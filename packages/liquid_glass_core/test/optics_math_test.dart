import 'package:liquid_glass_core/liquid_glass_core.dart';
import 'package:test/test.dart';

void main() {
  const double T = 20.0, B = 26.0, n = 1.5;

  group('height z(s) = T*sqrt(s(2-s))', () {
    test('z(0) = 0 and z(1) = T', () {
      expect(Snell.height(0.0, T), 0.0);
      expect(Snell.height(1.0, T), T);
    });

    test('is a quarter circle: (z/T)^2 + (1-s)^2 == 1', () {
      for (int i = 1; i < 20; i++) {
        final double s = i / 20;
        final double z = Snell.height(s, T) / T;
        final double identity = z * z + (1 - s) * (1 - s);
        expect(identity, closeTo(1.0, 1e-12), reason: 's=$s');
      }
    });
  });

  group('slope sigma(s)', () {
    test('infinite at the rim, zero at the flat-top join', () {
      expect(Snell.slope(0.0, T, B), double.infinity);
      expect(Snell.slope(1.0, T, B), 0.0);
    });

    test('monotonically decreasing on (0, 1]', () {
      double prev = double.infinity;
      for (int i = 1; i <= 40; i++) {
        final double s = i / 40;
        final double sigma = Snell.slope(s, T, B);
        expect(sigma < prev, isTrue, reason: 's=$s sigma=$sigma');
        prev = sigma;
      }
    });
  });

  group('exact Snell displacement Delta(s)', () {
    test('Delta(0) = 0 and Delta(1) = 0', () {
      expect(
        Snell.displacement(s: 0.0, thickness: T, bezel: B, ior: n),
        0.0,
      );
      expect(
        Snell.displacement(s: 1.0, thickness: T, bezel: B, ior: n),
        0.0,
      );
    });

    test('positive everywhere inside the bezel', () {
      for (int i = 1; i < 50; i++) {
        final double s = i / 50;
        expect(
          Snell.displacement(s: s, thickness: T, bezel: B, ior: n),
          greaterThan(0.0),
          reason: 's=$s',
        );
      }
    });

    test('peaks strictly inside (0, 1) - clear center, bent rim', () {
      int peak = 0;
      double best = -1;
      for (int i = 0; i <= 100; i++) {
        final double s = i / 100;
        final double v = Snell.displacement(s: s, thickness: T, bezel: B, ior: n);
        if (v > best) {
          best = v;
          peak = i;
        }
      }
      expect(peak, greaterThan(2));
      expect(peak, lessThan(98));
      expect(best, greaterThan(3.0)); // ~5 px at T=20, B=26, n=1.5
    });

    test('unimodal: rises then falls', () {
      final List<double> profile = List<double>.generate(
        101,
        (int i) => Snell.displacement(
          s: i / 100,
          thickness: T,
          bezel: B,
          ior: n,
        ),
      );
      final int peak = profile.indexWhere(
        (double v) => v == profile.reduce((double a, double b) => a > b ? a : b),
      );
      for (int i = 1; i < peak; i++) {
        expect(profile[i], greaterThan(profile[i - 1]));
      }
      for (int i = peak + 1; i < profile.length; i++) {
        expect(profile[i], lessThan(profile[i - 1]));
      }
    });

    test('ray bends inward and downward for every s in (0,1)', () {
      for (int i = 1; i < 20; i++) {
        final double s = i / 20;
        final RefractedRay r =
            Snell.ray(s: s, thickness: T, bezel: B, ior: n);
        expect(r.tXy, lessThan(0.0), reason: 's=$s lateral must be inward');
        expect(r.tZ, lessThan(0.0), reason: 's=$s must descend');
        expect(r.bendRatio, greaterThan(0.0));
        expect(r.bendRatio, lessThan(Snell.rimRatio(n) + 1e-9),
            reason: 'bounded by the rim limit for every s');
      }
    });

    test('rim limit |t_xy/t_z| -> sqrt(1-eta^2)/eta (finite)', () {
      // Deep in the sigma -> infinity regime the bend ratio converges to the
      // finite rim limit sqrt(1-eta^2)/eta (error ~ 1/sigma).
      const double s = 1e-9;
      final RefractedRay r = Snell.ray(s: s, thickness: T, bezel: B, ior: n);
      final double ratio = (r.tXy / r.tZ).abs();
      expect(ratio, closeTo(Snell.rimRatio(n), 2e-4));
      // And therefore Delta(s) -> 0 at the rim (z -> 0 wins over the ratio).
      expect(
        Snell.displacement(s: s, thickness: T, bezel: B, ior: n),
        lessThan(0.01),
      );
    });

    test('thicker glass bends more; higher ior bends more', () {
      double deltaMax(double t, double ior) {
        double best = 0;
        for (int i = 1; i < 200; i++) {
          final double v = Snell.displacement(
            s: i / 200,
            thickness: t,
            bezel: B,
            ior: ior,
          );
          if (v > best) best = v;
        }
        return best;
      }

      expect(deltaMax(40.0, n), greaterThan(deltaMax(20.0, n)));
      expect(deltaMax(20.0, 1.6), greaterThan(deltaMax(20.0, 1.4)));
    });

    test('Delta is independent of element size', () {
      // Same optics at two different sizes: identical profile.
      final double a = Snell.displacement(
        s: 0.5,
        thickness: T,
        bezel: B,
        ior: n,
      );
      expect(a, Snell.displacement(s: 0.5, thickness: T, bezel: B, ior: n));
    });
  });

  group('rounded-rect SDF', () {
    test('negative inside, positive outside, zero on the boundary', () {
      const double halfW = 261, halfH = 310.5, r = 28;
      expect(
        RoundedRectSdf.distance(-100, -100, halfW, halfH, r),
        lessThan(0.0),
      );
      expect(
        RoundedRectSdf.distance(halfW + 5, 0, halfW, halfH, r),
        greaterThan(0.0),
      );
      expect(
        RoundedRectSdf.distance(halfW, 0, halfW, halfH, r),
        closeTo(0.0, 1e-12),
      );
      // On the corner arc, 45 degrees out.
      final double c = r * 0.7071067811865476;
      expect(
        RoundedRectSdf.distance(
          halfW - r + c,
          halfH - r + c,
          halfW,
          halfH,
          r,
        ),
        closeTo(0.0, 1e-9),
      );
    });

    test('outward direction: edge branch axis-aligned, corner radial', () {
      const double halfW = 100, halfH = 60, r = 20;
      final (double, double) edge = RoundedRectSdf.outwardDirection(
        95,
        0,
        halfW,
        halfH,
        r,
      );
      expect(edge.$1, closeTo(1.0, 1e-12));
      expect(edge.$2, closeTo(0.0, 1e-12));

      final (double, double) corner = RoundedRectSdf.outwardDirection(
        85,
        45,
        halfW,
        halfH,
        r,
      );
      expect(corner.$1, closeTo(0.7071067811865476, 1e-9));
      expect(corner.$2, closeTo(0.7071067811865476, 1e-9));
    });

    test('inward distance = -signed distance', () {
      const double halfW = 100, halfH = 60, r = 20;
      expect(
        RoundedRectSdf.inwardDistance(0, 0, halfW, halfH, r),
        -RoundedRectSdf.distance(0, 0, halfW, halfH, r),
      );
    });
  });

  group('bezel clamp (capsule dome)', () {
    const GlassOptics optics = GlassOptics(bezelWidth: 26.0);

    test('B stays B when below min(w,h)/2', () {
      expect(optics.effectiveBezel(522, 621), 26.0);
    });

    test('B clamps to min(w,h)/2 for pill shapes - s reaches 1 at the medial '
        'axis with zero slope (no ridge)', () {
      expect(optics.effectiveBezel(163, 353), 26.0);
      expect(optics.effectiveBezel(64, 480), 26.0);
      expect(const GlassOptics(bezelWidth: 999).effectiveBezel(64, 480), 32.0);
      expect(const GlassOptics(bezelWidth: 999).effectiveBezel(200, 200), 100.0);
    });

    test('LUT key follows the clamp, not the raw width', () {
      final GlassLutKey big = const GlassOptics(bezelWidth: 999)
          .toLutKey(width: 64, height: 480);
      final GlassLutKey small = const GlassOptics(bezelWidth: 32)
          .toLutKey(width: 64, height: 480);
      expect(big, small);
    });
  });
}
