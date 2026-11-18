/// Debug widget that renders the CPU-built 8-bit displacement map.
///
/// Visualizes the band-limited, mirrored, Bayer-dithered encoder output of
/// `DisplacementMapRaster` (R = dx, G = dy) - handy to inspect what the
/// original SVG-filter engine would have consumed.
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:liquid_glass_core/liquid_glass_core.dart';

import '../config.dart';

/// Paints [DisplacementMapRaster.build] output as an image.
class LiquidGlassMapPreview extends StatefulWidget {
  const LiquidGlassMapPreview({
    super.key,
    this.width = 353,
    this.height = 163,
    this.radius = 26,
    this.config = const LiquidGlassConfig(),
  });

  /// Previewed element size, logical px.
  final double width;
  final double height;

  /// Previewed corner radius, logical px.
  final double radius;

  /// Optics used to build the map.
  final LiquidGlassConfig config;

  @override
  State<LiquidGlassMapPreview> createState() => _LiquidGlassMapPreviewState();
}

class _LiquidGlassMapPreviewState extends State<LiquidGlassMapPreview> {
  ui.Image? _image;
  DisplacementMap? _map;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(LiquidGlassMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height ||
        oldWidget.radius != widget.radius) {
      _rebuild();
    }
  }

  void _rebuild() {
    final GlassOptics optics = widget.config.optics;
    final RefractionLut lut = RefractionLutCache.acquire(
      optics.toLutKey(width: widget.width, height: widget.height),
    );
    final DisplacementMap map = DisplacementMapRaster.build(
      width: widget.width,
      height: widget.height,
      radius: widget.radius,
      optics: optics,
      lut: lut,
    );
    ui.decodeImageFromPixels(
      map.bytes,
      map.widthPx,
      map.heightPx,
      ui.PixelFormat.rgba8888,
      (ui.Image image) {
        if (mounted) {
          setState(() {
            _image?.dispose();
            _image = image;
            _map = map;
          });
        } else {
          image.dispose();
        }
      },
    );
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DisplacementMap? map = _map;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (_image != null)
          RawImage(
            image: _image,
            width: widget.width,
            height: widget.height,
            fit: BoxFit.fill,
          ),
        if (map != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'displacement map: ${map.bandPixels} band px of '
              '${map.fullPixels} (${(map.fullPixels / map.bandPixels).toStringAsFixed(1)}x fewer), '
              'scale S = ${map.suggestedScale.toStringAsFixed(0)} px',
              style: const TextStyle(
                color: Color(0xB3FFFFFF),
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}
