/// Loads and caches the engine's fragment program.
///
/// The shader is declared in the package's `flutter: shaders:` section, so
/// the Flutter tool compiles it per backend and bundles it with any app
/// that depends on `liquid_glass_engine` - consumers never list it
/// themselves.
library;

import 'dart:ui' as ui;

/// Process-wide singleton for the compiled fragment program.
class LiquidGlassProgram {
  const LiquidGlassProgram._();

  /// Asset key as bundled for package-owned shaders.
  static const String assetPath =
      'packages/liquid_glass_engine/shaders/liquid_glass.frag';

  /// Unprefixed fallback (covers custom bundling setups).
  static const String fallbackPath = 'shaders/liquid_glass.frag';

  static Future<ui.FragmentProgram>? _future;

  /// Loads (once) and returns the compiled program.
  static Future<ui.FragmentProgram> load() {
    return _future ??= _load();
  }

  static Future<ui.FragmentProgram> _load() async {
    try {
      return await ui.FragmentProgram.fromAsset(assetPath);
    } on Object {
      // Asset missing under the prefixed path (custom bundling setups).
      return ui.FragmentProgram.fromAsset(fallbackPath);
    }
  }
}
