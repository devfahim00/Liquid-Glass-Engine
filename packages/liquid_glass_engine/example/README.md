# Liquid Glass Engine - example app

A runnable demo: a scrolling gradient backdrop beneath four same-optics
glass cards (one shared LUT), a capsule toolbar, a glass control sheet with
live sliders, and a metrics overlay reading
`LiquidGlassEngine.metrics.summary()` - the analog of the web engine's
`__QUICK_LIQUID__.metrics()` panel.

```sh
flutter pub get
flutter run
```

While dragging the sliders, watch the metrics overlay: `lutBuilds` only
moves when the *geometry* (`thickness`, `bezelWidth`, `ior`) changes -
strength, chromatic aberration, frost, saturation, light angle and rim are
attribute-only updates.
