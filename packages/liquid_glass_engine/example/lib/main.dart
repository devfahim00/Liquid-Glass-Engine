/// Liquid Glass Engine - interactive demo.
///
/// A scrolling, colorful backdrop sits beneath three kinds of glass
/// elements (cards, a capsule toolbar, a circular button) plus a control
/// sheet that changes optics at runtime - proving that strength / CA /
/// frost / saturation / light-angle updates never rebuild the LUT (watch
/// the metrics overlay: `lutBuilds` only moves when the *geometry* changes).
library;

import 'dart:async';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:liquid_glass_engine/liquid_glass_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Compile the shader before the first frame so no element ever renders
  // its fallback flash.
  try {
    await LiquidGlassEngine.warmUp();
  } on Object catch (e) {
    debugPrint('warm-up skipped: $e');
  }
  runApp(const LiquidGlassDemoApp());
}

class LiquidGlassDemoApp extends StatelessWidget {
  const LiquidGlassDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Liquid Glass Engine',
      debugShowCheckedModeBanner: false,
      home: DemoHome(),
    );
  }
}

class DemoHome extends StatefulWidget {
  const DemoHome({super.key});

  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  double _thickness = 20;
  double _bezel = 26;
  double _ior = 1.5;
  double _strength = 22;
  double _ca = 0.0;
  double _frost = 0.0;
  double _saturation = 1.0;
  double _light = 135;
  double _rim = 1.0;
  bool _showControls = false;
  bool _showMetrics = true;
  late final Timer _metricsTimer;

  GlassOptics get _optics => GlassOptics(
        thickness: _thickness,
        bezelWidth: _bezel,
        ior: _ior,
        refractionStrength: _strength,
        chromaticAberration: _ca,
        frost: _frost,
        saturation: _saturation,
      );

  LiquidGlassConfig get _config => LiquidGlassConfig(
        optics: _optics,
        lightAngleDeg: _light,
        rim: _rim,
      );

  @override
  void initState() {
    super.initState();
    _metricsTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted && _showMetrics) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _metricsTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0b1020),
      body: Stack(
        children: <Widget>[
          // --- The backdrop: rich, scrollable content -------------------
          const _ScrollingBackdrop(),
          // --- Shared-optics demo cards (one LUT for all four) -----------
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: <Widget>[
                  for (int i = 0; i < 4; i++)
                    SizedBox(
                      width: 168,
                      height: 116,
                      child: LiquidGlass(
                        config: _config,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Card ${i + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'same optics\none shared LUT',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // --- Capsule toolbar -------------------------------------------
          Positioned(
            left: 24,
            right: 24,
            bottom: 24,
            child: Center(
              child: SizedBox(
                width: 420,
                height: 64,
                child: LiquidGlass(
                  config: LiquidGlassConfig(
                    shape: const LiquidGlassShape.capsule(),
                    optics: _optics,
                    lightAngleDeg: _light,
                    rim: _rim,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: <Widget>[
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.home_outlined,
                            color: Colors.white),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.search, color: Colors.white),
                      ),
                      // The circular accent: glass on glass.
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Colors.white24,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.favorite,
                            color: Colors.white),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _showControls = true),
                        icon:
                            const Icon(Icons.tune, color: Colors.white),
                      ),
                      IconButton(
                        onPressed: () =>
                            setState(() => _showMetrics = !_showMetrics),
                        icon: const Icon(Icons.analytics_outlined,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // --- Metrics overlay -------------------------------------------
          if (_showMetrics)
            Positioned(
              right: 16,
              top: 60,
              child: IgnorePointer(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    LiquidGlassEngine.metrics.summary(),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          // --- Control sheet (glass itself) -------------------------------
          if (_showControls)
            Positioned.fill(
              child: Center(
                child: SizedBox(
                  width: 380,
                  child: LiquidGlass(
                    config: LiquidGlassConfig(
                      shape: const LiquidGlassShape.rounded(28),
                      optics: _optics.copyWith(frost: 0.02),
                      lightAngleDeg: _light,
                      rim: _rim,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const Expanded(
                                child: Text(
                                  'Optics',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    setState(() => _showControls = false),
                                icon: const Icon(Icons.close, color: Colors.white),
                              ),
                            ],
                          ),
                          _slider('thickness (T)', _thickness, 4, 60,
                              (v) => setState(() => _thickness = v)),
                          _slider('bezelWidth (B)', _bezel, 4, 60,
                              (v) => setState(() => _bezel = v)),
                          _slider('ior (n)', _ior, 1.05, 2.4,
                              (v) => setState(() => _ior = v)),
                          _slider('refractionStrength (M)', _strength, 0, 60,
                              (v) => setState(() => _strength = v)),
                          _slider('chromaticAberration', _ca, 0, 1,
                              (v) => setState(() => _ca = v)),
                          _slider('frost', _frost, 0, 1,
                              (v) => setState(() => _frost = v)),
                          _slider('saturation', _saturation, 0.2, 2,
                              (v) => setState(() => _saturation = v)),
                          _slider('lightAngle', _light, 0, 360,
                              (v) => setState(() => _light = v)),
                          _slider('rim', _rim, 0, 2,
                              (v) => setState(() => _rim = v)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 170,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: const SliderThemeData(
              trackHeight: 2,
              overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// Colorful scrolling content for the glass to refract.
class _ScrollingBackdrop extends StatelessWidget {
  const _ScrollingBackdrop();

  static const List<(Color, Color, String)> _rows = <(Color, Color, String)>[
    (Color(0xFF6366f1), Color(0xFF8b5cf6), 'Indigo dawn'),
    (Color(0xFFec4899), Color(0xFFf43f5e), 'Rose quarter'),
    (Color(0xFFf59e0b), Color(0xFFef4444), 'Ember line'),
    (Color(0xFF06b6d4), Color(0xFF3b82f6), 'Cyan sweep'),
    (Color(0xFF10b981), Color(0xFF84cc16), 'Mint ridge'),
    (Color(0xFF8b5cf6), Color(0xFF2dd4bf), 'Violet tide'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 40),
      itemCount: 24,
      itemBuilder: (BuildContext context, int index) {
        final (Color a, Color b, String title) =
            _rows[index % _rows.length];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Container(
            height: 170,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[a, b],
              ),
              borderRadius: BorderRadius.circular(30),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              '$title ${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ),
        );
      },
    );
  }
}
