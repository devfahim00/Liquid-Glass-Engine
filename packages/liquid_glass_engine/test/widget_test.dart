// One testWidgets per file: the whole verification chain (shader program
// load, renderer probe, widget tree over a live backdrop, cache metrics)
// runs inside a single test so every await is resolved by microtasks only.
import 'dart:ui' as ui;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_core/liquid_glass_core.dart';
import 'package:liquid_glass_engine/liquid_glass_engine.dart';

void main() {
  testWidgets('shader loads, probe resolves, widget paints', (
    WidgetTester tester,
  ) async {
    // 1. The Flutter tool compiled shaders/liquid_glass.frag at build time;
    //    loading the asset proves the GLSL is well-formed for this backend.
    await LiquidGlassEngine.warmUp();
    final ui.FragmentProgram program = await LiquidGlassProgram.load();
    final ui.FragmentShader shader = program.fragmentShader();
    expect(shader, isNotNull);

    // 2. Live probe: constructing a shader filter either works (Impeller)
    //    or throws here (software tester / web) - never silently lies.
    bool shaderFilterSupported = true;
    try {
      // ignore: unused_local_variable
      final ui.ImageFilter probe = ui.ImageFilter.shader(shader);
      shaderFilterSupported = true;
    } on Object {
      shaderFilterSupported = false;
    }
    debugPrint('probe: shader filter supported = $shaderFilterSupported');

    // 3. The widget over a rich backdrop, in whichever mode the renderer
    //    resolved to.
    glassMetrics.reset();
    RefractionLutCache.debugReset();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color(0xFF0f172a),
                      Color(0xFF7c3aed),
                      Color(0xFFf59e0b),
                    ],
                  ),
                ),
                child: const Center(child: Text('backdrop')),
              ),
              const Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: 320,
                  height: 96,
                  child: LiquidGlass(
                    child: Center(child: Text('glass')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('glass'), findsOneWidget);
    expect(find.text('backdrop'), findsOneWidget);
    // Exactly one backdrop-filtered surface for the element (the cost
    // model: one layer per element, never a dual frost layer).
    expect(find.byType(ClipRRect), findsOneWidget);
    // The refraction path builds exactly one shared LUT for the element; the
    // soft fallback needs none - metrics reflect the work actually done.
    if (shaderFilterSupported) {
      expect(glassMetrics.lutBuilds, 1);
      expect(glassMetrics.activeLuts, 1);
      expect(glassMetrics.summary(), contains('lutBuilds=1'));
    } else {
      expect(glassMetrics.lutBuilds, 0);
    }
    expect(LiquidGlassEngine.metrics, same(glassMetrics));
  });
}
