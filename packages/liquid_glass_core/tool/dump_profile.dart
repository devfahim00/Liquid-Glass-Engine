/// Writes a JSON profile (LUT values, timings, band ratios) so an
/// independent implementation can cross-check the optics.
///
/// Run from the package root:
/// ```sh
/// dart run tool/dump_profile.dart
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:liquid_glass_core/liquid_glass_core.dart';

void main() {
  glassMetrics.reset();

  const GlassOptics optics = GlassOptics(); // T=20, B=26, n=1.5, M=22
  final GlassLutKey key = optics.toLutKey(width: 522, height: 621);

  // Sharing demo: four acquires of one geometry = one build, three cache
  // hits, one live entry. Snapshot the counters before anything else runs.
  final RefractionLut lut = RefractionLutCache.acquire(key);
  for (int i = 0; i < 3; i++) {
    RefractionLutCache.acquire(key);
  }
  final int sharingBuilds = glassMetrics.lutBuilds;
  final int sharingHits = glassMetrics.lutCacheHits;
  final int sharingActive = glassMetrics.activeLuts;

  // Steady-state build cost (metrics reset so the sharing snapshot above is
  // unaffected).
  glassMetrics.reset();
  const int builds = 2000;
  final Stopwatch buildWatch = Stopwatch()..start();
  for (int i = 0; i < builds; i++) {
    RefractionLut.build(key);
  }
  buildWatch.stop();
  final int lutBuildUsAvg = buildWatch.elapsedMicroseconds ~/ builds;
  glassMetrics.reset();

  final Map<String, Object> profile = <String, Object>{
    'params': <String, Object>{
      'thickness': optics.thickness,
      'bezelWidth': optics.bezelWidth,
      'ior': optics.ior,
      'refractionStrength': optics.refractionStrength,
      'lutSize': RefractionLut.size,
    },
    'lut': {
      'deltaMaxPx': lut.deltaMaxPx,
      'peakS': lut.peakS,
      'values': lut.values.toList(),
    },
    'lutBuildUsAvg': lutBuildUsAvg,
    'rasters': <String, Object>{},
    'metrics': {
      'lutBuilds': sharingBuilds,
      'lutCacheHits': sharingHits,
      'activeLuts': sharingActive,
    },
  };

  final Map<String, Object> rasters =
      profile['rasters'] as Map<String, Object>;
  for (final (String label, double w, double h, double r)
      in const <(String, double, double, double)>[
    ('panel_522x621_r28', 522, 621, 28),
    ('card_353x163_r26', 353, 163, 26),
    ('toolbar_480x64_capsule', 480, 64, 32),
    ('panel_522x621_r28_narrowB10', 522, 621, 28),
  ]) {
    final bool narrow = label.contains('narrowB10');
    final GlassOptics o = narrow ? const GlassOptics(bezelWidth: 10) : optics;
    final RefractionLut l = narrow
        ? RefractionLut.build(o.toLutKey(width: w, height: h))
        : lut;
    glassMetrics.reset();
    final DisplacementMap map = DisplacementMapRaster.build(
      width: w,
      height: h,
      radius: r,
      optics: o,
      lut: l,
    );
    rasters[label] = {
      'widthPx': map.widthPx,
      'heightPx': map.heightPx,
      'fullPixels': map.fullPixels,
      'bandPixels': map.bandPixels,
      'bandRatio': map.fullPixels / map.bandPixels,
      'rasterTimeUs': glassMetrics.rasterTimeUs,
      'suggestedScale': map.suggestedScale,
    };
    glassMetrics.reset();
  }

  File('tool/profile.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(profile),
  );

  stdout.writeln('Delta_max = ${lut.deltaMaxPx.toStringAsFixed(4)} px');
  stdout.writeln('peak s    = ${lut.peakS.toStringAsFixed(4)}');
  stdout.writeln('LUT build = $lutBuildUsAvg us avg over $builds builds '
      '(512 Snell evals each)');
  for (final MapEntry<String, Object> e in rasters.entries) {
    final Map<String, Object> v = e.value as Map<String, Object>;
    stdout.writeln(
      '${e.key}: ${v['bandPixels']} band px of ${v['fullPixels']} '
      '(x${(v['bandRatio'] as num).toStringAsFixed(1)} fewer) in '
      '${v['rasterTimeUs']} us',
    );
  }
  stdout.writeln('wrote tool/profile.json');
}
