/// Soft fallback surface: backdrop blur + painted rim lighting.
///
/// Mirrors the web engine's fallback for engines that cannot resolve the
/// refraction path: blur + lighting layers, one `BackdropFilter` per
/// element, no dual "edge frost" layer.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:liquid_glass_core/liquid_glass_core.dart';

import '../config.dart';

/// Blur + rim-light surface used when the shader path is unavailable.
class SoftGlassSurface extends StatelessWidget {
  const SoftGlassSurface({
    super.key,
    required this.config,
    this.child,
  });

  final LiquidGlassConfig config;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        if (!size.isFinite || size.width <= 0 || size.height <= 0) {
          return const SizedBox.shrink();
        }
        final GlassOptics optics = config.optics;
        // Slight blur always reads as "glass"; frost pushes it up.
        final double sigma = 0.8 + 17.0 * optics.frost.clamp(0.0, 1.0);
        final double radius = config.shape.resolvedRadius(size);
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: sigma,
              sigmaY: sigma,
              tileMode: ui.TileMode.clamp,
            ),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SoftChromePainter(config: config),
                  ),
                ),
                if (child != null)
                  Positioned.fill(child: child!),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Paints the fallback rim lighting: a bezel-band sweep gradient oriented on
/// the light angle plus an inner specular line - the painted approximation
/// of the shader's analytic Blinn-Phong rim.
class _SoftChromePainter extends CustomPainter {
  const _SoftChromePainter({required this.config});

  final LiquidGlassConfig config;

  @override
  void paint(Canvas canvas, Size size) {
    final GlassOptics optics = config.optics;
    final double radius = config.shape.resolvedRadius(size);
    final double bezel =
        optics.effectiveBezel(size.width, size.height).clamp(0.0, radius);
    if (bezel <= 0 || config.rim <= 0) {
      return;
    }

    final Rect rect = Offset.zero & size;
    final RRect outer =
        RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final RRect inner = RRect.fromRectAndRadius(
      rect.deflate(bezel.clamp(0.0, math.min(size.width, size.height) / 2)),
      Radius.circular((radius - bezel).clamp(0.0, double.infinity)),
    );

    // Bezel band: outer shape minus the deflated shape.
    final Path band = Path.combine(
      PathOperation.difference,
      Path()..addRRect(outer),
      Path()..addRRect(inner),
    );

    final Offset light = config.lightVector();
    final double angle =
        math.atan2(-light.dy, -light.dx); // sweep starts opposite the light

    final double rimA = 0.55 * config.rim;
    final List<Color> colors = <Color>[
      const Color(0x00FFFFFF),
      const Color(0x30FFFFFF),
      Color.fromARGB((rimA.clamp(0.0, 1.0) * 255).round(), 255, 255, 255),
      const Color(0x30FFFFFF),
      const Color(0x00FFFFFF),
      const Color(0x00FFFFFF),
      const Color(0x24FFFFFF),
      const Color(0x00FFFFFF),
    ];
    final SweepGradient gradient = SweepGradient(
      startAngle: angle,
      endAngle: angle + 2 * math.pi,
      colors: colors,
      stops: const <double>[0.0, 0.12, 0.25, 0.38, 0.5, 0.62, 0.75, 1.0],
      transform: const GradientRotation(0),
    );

    canvas.saveLayer(rect, Paint());
    canvas.drawPath(
      band,
      Paint()
        ..shader = gradient.createShader(rect)
        ..blendMode = BlendMode.srcOver,
    );

    // Inner specular line where the bezel meets the flat top.
    final Path innerPath = Path()..addRRect(inner);
    canvas.drawPath(
      innerPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Color.fromARGB(((0.28 * config.rim).clamp(0.0, 1.0) * 255).round(), 255, 255, 255),
    );
    canvas.drawPath(
      Path()..addRRect(outer.deflate(0.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = const Color(0x14FFFFFF),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SoftChromePainter oldDelegate) =>
      oldDelegate.config != config;
}
