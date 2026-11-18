// Pure unit tests for the Flutter-side config resolution and the engine's
// cache metrics facade. Synchronous bodies only (no timer awaits).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_core/liquid_glass_core.dart';
import 'package:liquid_glass_engine/liquid_glass_engine.dart';

void main() {
  setUp(() {
    glassMetrics.reset();
    RefractionLutCache.debugReset();
  });

  test('config equality and light vector', () {
    const LiquidGlassConfig a = LiquidGlassConfig();
    const LiquidGlassConfig b = LiquidGlassConfig(
      optics: GlassOptics(thickness: 20, bezelWidth: 26, ior: 1.5),
    );
    expect(a, b); // same numbers, equal optics
    expect(a.hashCode, b.hashCode);
    expect(a.copyWith(rim: 2.0).rim, 2.0);
    expect(a != b.copyWith(lightAngleDeg: 90), isTrue);

    // 135 degrees = classic top-left light, in y-down screen coordinates.
    final Offset light = a.lightVector();
    expect(light.dx, closeTo(-0.7071067811865476, 1e-12));
    expect(light.dy, closeTo(-0.7071067811865476, 1e-12));
    expect(light.distance, closeTo(1.0, 1e-12));
  });

  test('shape resolution: capsules clamp, huge radii degrade gracefully', () {
    const LiquidGlassShape capsule = LiquidGlassShape.capsule();
    expect(capsule.resolvedRadius(const Size(480, 64)), 32.0);
    expect(capsule.resolvedRadius(const Size(64, 64)), 32.0); // circle

    const LiquidGlassShape rounded = LiquidGlassShape.rounded(999);
    // Radius clamps to min(w, h)/2 - a huge radius degrades into a capsule.
    expect(rounded.resolvedRadius(const Size(100, 40)), 20.0);
    expect(rounded.resolvedRadius(const Size(100, 200)), 50.0);

    const LiquidGlassShape normal = LiquidGlassShape.rounded(24);
    expect(normal.resolvedRadius(const Size(300, 150)), 24.0);
  });

  test('engine metrics counters increment through the shared cache', () {
    const GlassOptics optics = GlassOptics();
    final GlassLutKey key = optics.toLutKey(width: 300, height: 150);
    RefractionLutCache.acquire(key);
    RefractionLutCache.acquire(key);
    expect(glassMetrics.lutBuilds, 1);
    expect(glassMetrics.lutCacheHits, 1);
    expect(glassMetrics.activeLuts, 1);
    expect(LiquidGlassEngine.metrics, same(glassMetrics));
    RefractionLutCache.release(key);
    RefractionLutCache.release(key);
    expect(glassMetrics.activeLuts, 0);
    expect(glassMetrics.lutEvictions, 1);
  });
}
