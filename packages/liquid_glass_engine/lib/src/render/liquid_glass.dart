/// The [LiquidGlass] widget: exact-Snell refraction over live backdrop.
///
/// Rendering strategy (mirroring the QuickLiquid cost model):
///
/// * **Refraction mode** (default where supported): exactly one
///   `BackdropFilter` layer per element whose filter is
///   `ui.ImageFilter.shader` - the GPU evaluates the exact optics per pixel
///   (SDF -> s -> Snell -> inward sample). No per-pixel Dart work, no LUT
///   upload, no repaint of any map for slider changes: `refractionStrength`
///   and `chromaticAberration` are pure uniform (attribute-only) updates.
/// * **Soft mode** (fallback, mirroring the web engine's
///   `refractionMode: 'auto'`): blur + painted rim layers when the
///   shader-backdrop path is unavailable (e.g. Flutter web, or a renderer
///   without shader-filter support). A live construction probe - not
///   feature flags that lie - decides at runtime.
/// * The LUT (512-entry exact trace, `Delta_max` normalizer) is built once
///   per geometry and refcounted: N same-optics elements share one build.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_core/liquid_glass_core.dart';

import '../config.dart';
import 'program_loader.dart';
import 'soft_glass_surface.dart';

/// How the element resolves its rendering path.
enum LiquidGlassMode {
  /// Use exact-Snell refraction where supported, soft fallback otherwise.
  auto,

  /// Force the shader-backed refraction path (falls back to soft on
  /// renderers without shader-filter support).
  refraction,

  /// Force the blur + rim-light fallback, never touching the shader path.
  soft,
}

/// A liquid-glass element: exact refraction of whatever is painted beneath
/// it, with a specular rim and optional frost.
///
/// The widget must be given bounded dimensions - place it in a `SizedBox`,
/// a `Positioned`, or a parent with tight constraints - and something must
/// be painted *beneath* it in the same layer stack (a backdrop).
///
/// ```dart
/// Stack(children: [
///   const BackdropPage(),                        // any content
///   Align(
///     alignment: Alignment.bottomCenter,
///     child: SizedBox(
///       width: 480,
///       height: 64,
///       child: LiquidGlass(
///         config: const LiquidGlassConfig(
///           shape: LiquidGlassShape.capsule(),
///         ),
///         child: const ToolbarContent(),
///       ),
///     ),
///   ),
/// ])
/// ```
class LiquidGlass extends StatefulWidget {
  const LiquidGlass({
    super.key,
    this.config = const LiquidGlassConfig(),
    this.child,
    this.mode = LiquidGlassMode.auto,
  });

  /// Optics + presentation configuration.
  final LiquidGlassConfig config;

  /// Content painted on top of the glass surface (icon, label, controls).
  final Widget? child;

  /// Rendering path selection; see [LiquidGlassMode].
  final LiquidGlassMode mode;

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<LiquidGlassConfig>('config', config));
    properties.add(EnumProperty<LiquidGlassMode>('mode', mode));
  }
}

class _LiquidGlassState extends State<LiquidGlass> {
  ui.FragmentShader? _shader;
  bool _programFailed = false;
  bool _shaderFilterSupported = false;
  bool _shaderFilterProbed = false;

  GlassLutKey? _lutKey;
  RefractionLut? _lut;

  @override
  void initState() {
    super.initState();
    _loadProgram();
  }

  Future<void> _loadProgram() async {
    try {
      final ui.FragmentProgram program = await LiquidGlassProgram.load();
      final ui.FragmentShader shader = program.fragmentShader();
      // Live probe: actually construct the shader filter once. This is the
      // analog of the web engine's live-DOM probe - `CSS.supports`-style
      // feature flags lie; a real construction does not. Unsupported
      // renderers (Flutter web, software rasterizers) throw here and the
      // element uses soft mode for its whole lifetime.
      try {
        // ignore: unused_local_variable
        final ui.ImageFilter probe = ui.ImageFilter.shader(shader);
        _shaderFilterSupported = true;
      } catch (error) {
        _shaderFilterSupported = false;
        debugPrint('liquid_glass_engine: shader backdrop unavailable on '
            'this renderer ($error); using the soft fallback.');
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _shader = shader;
        _shaderFilterProbed = true;
      });
    } catch (error) {
      debugPrint('liquid_glass_engine: shader program failed to load '
          '($error); using the soft fallback.');
      if (mounted) {
        setState(() {
          _programFailed = true;
          _shaderFilterProbed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    if (_lutKey != null) {
      RefractionLutCache.release(_lutKey!);
      _lutKey = null;
      _lut = null;
    }
    _shader?.dispose();
    super.dispose();
  }

  /// Keeps the refcounted LUT lease in sync with the current geometry.
  void _syncLut(Size size) {
    final GlassLutKey key = widget.config.optics.toLutKey(
      width: size.width,
      height: size.height,
    );
    if (_lutKey == key) {
      return;
    }
    if (_lutKey != null) {
      RefractionLutCache.release(_lutKey!);
    }
    _lutKey = key;
    _lut = RefractionLutCache.acquire(key);
  }

  bool _useRefraction() {
    switch (widget.mode) {
      case LiquidGlassMode.soft:
        return false;
      case LiquidGlassMode.refraction:
      case LiquidGlassMode.auto:
        return _shader != null &&
            _shaderFilterProbed &&
            _shaderFilterSupported &&
            !_programFailed;
    }
  }

  // Uniform indices (see shaders/liquid_glass.frag). Float slots 0..1 are
  // the engine-set vec2 (bound texture size) and are never written here.
  static const int _uDpr = 2;
  static const int _uRadius = 3;
  static const int _uThickness = 4;
  static const int _uBezel = 5;
  static const int _uIor = 6;
  static const int _uStrength = 7;
  static const int _uDeltaMax = 8;
  static const int _uCa = 9;
  static const int _uFrost = 10;
  static const int _uSaturation = 11;
  static const int _uLightX = 12;
  static const int _uLightY = 13;
  static const int _uRim = 14;
  static const int _uTintR = 15;
  static const int _uTintG = 16;
  static const int _uTintB = 17;
  static const int _uTintA = 18;

  void _applyUniforms(ui.FragmentShader s, Size size, double dpr) {
    final GlassOptics optics = widget.config.optics;
    final RefractionLut lut = _lut!;
    s.setFloat(_uDpr, dpr);
    s.setFloat(_uRadius, widget.config.shape.resolvedRadius(size));
    s.setFloat(_uThickness, optics.thickness);
    s.setFloat(_uBezel, optics.effectiveBezel(size.width, size.height));
    s.setFloat(_uIor, optics.ior);
    s.setFloat(_uStrength, optics.refractionStrength);
    s.setFloat(_uDeltaMax, lut.deltaMaxPx > 0 ? lut.deltaMaxPx : 1e-6);
    s.setFloat(_uCa, optics.chromaticAberration);
    s.setFloat(_uFrost, optics.frost);
    s.setFloat(_uSaturation, optics.saturation);
    final Offset light = widget.config.lightVector();
    s.setFloat(_uLightX, light.dx);
    s.setFloat(_uLightY, light.dy);
    s.setFloat(_uRim, widget.config.rim);
    s.setFloat(_uTintR, widget.config.tint.r / 255.0);
    s.setFloat(_uTintG, widget.config.tint.g / 255.0);
    s.setFloat(_uTintB, widget.config.tint.b / 255.0);
    s.setFloat(_uTintA, widget.config.tint.a / 255.0);
  }

  @override
  Widget build(BuildContext context) {
    if (!_useRefraction()) {
      // Soft fallback (also used for the first frames while the program
      // loads; warm up with LiquidGlassEngine.warmUp() to avoid it).
      return SoftGlassSurface(
        config: widget.config,
        child: widget.child,
      );
    }
    final ui.FragmentShader shader = _shader!;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        if (!size.isFinite || size.width <= 0 || size.height <= 0) {
          // Unbounded axes cannot be sized; shrink instead of throwing.
          return const SizedBox.shrink();
        }
        _syncLut(size);
        final double dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
        _applyUniforms(shader, size, dpr);
        final double radius = widget.config.shape.resolvedRadius(size);
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ui.ImageFilter.shader(
              shader,
              filterQuality: ui.FilterQuality.medium,
            ),
            child: SizedBox.fromSize(size: size, child: widget.child),
          ),
        );
      },
    );
  }
}
