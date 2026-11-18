#!/usr/bin/env python3
"""Independent cross-check of the Liquid Glass Engine optics.

Re-implements the QuickLiquid math from scratch (pure Python/float64) and
compares against the Dart core's dumped profile (tool/profile.json):
  height z(s)    = T*sqrt(s*(2-s))
  slope sigma(s) = (T/B)*(1-s)/sqrt(s*(2-s))
  Snell: sinI = sigma/sqrt(1+sigma^2), cosI = 1/sqrt(1+sigma^2),
        sinT = eta*sinI, cosT = sqrt(1-sinT^2), eta = 1/n
        t_xy = (eta*cosI - cosT)*sinI
        t_z  = -eta + (eta*cosI - cosT)*cosI
        Delta(s) = z(s)*|t_xy/t_z|
Also verifies the emergent properties and the cache-sharing metrics.
"""
import json
import math
import sys

import os

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROFILE = os.path.join(
    _REPO_ROOT, "packages", "liquid_glass_core", "tool", "profile.json")


def displacement(s, T, B, n):
    if s <= 0 or s >= 1:
        return 0.0
    z = T * math.sqrt(s * (2 - s))
    sigma = (T / B) * (1 - s) / math.sqrt(s * (2 - s))
    cos_i = 1 / math.sqrt(1 + sigma * sigma)
    sin_i = sigma * cos_i
    eta = 1 / n
    sin_t = eta * sin_i
    cos_t = math.sqrt(1 - sin_t * sin_t)
    k = eta * cos_i - cos_t
    t_xy = k * sin_i
    t_z = -eta + k * cos_i
    return z * abs(t_xy / t_z)


def main():
    data = json.load(open(PROFILE))
    p = data["params"]
    T, B, n = p["thickness"], p["bezelWidth"], p["ior"]
    lut = data["lut"]["values"]
    size = len(lut)

    raw = [displacement(i / (size - 1), T, B, n) for i in range(size)]
    dmax = max(raw)
    worst = max(abs(raw[i] / dmax - lut[i]) for i in range(size))
    peak_s = raw.index(dmax) / (size - 1)

    checks = {
        "lut size == 512": size == 512,
        "Delta(0) == 0": abs(raw[0]) < 1e-15,
        "Delta(1) == 0": abs(raw[-1]) < 1e-15,
        "peak strictly inside (0,1)": 0.02 < peak_s < 0.98,
        "Delta_max matches Dart": abs(dmax - data["lut"]["deltaMaxPx"]) < 1e-9,
        "peakS matches Dart": abs(peak_s - data["lut"]["peakS"]) < 1e-9,
        "normalized max == 1": abs(max(lut) - 1.0) < 1e-6,
        "LUT entries match (float32)": worst < 1e-6,
    }

    # Rim ratio limit: Delta(s) -> 0 while |t_xy/t_z| -> sqrt(1-eta^2)/eta.
    eta = 1 / n
    rim = math.sqrt(1 - eta * eta) / eta
    s_deep = 1e-9
    z = T * math.sqrt(s_deep * (2 - s_deep))
    sigma = (T / B) * (1 - s_deep) / math.sqrt(s_deep * (2 - s_deep))
    cos_i = 1 / math.sqrt(1 + sigma * sigma)
    sin_i = sigma * cos_i
    sin_t = eta * sin_i
    cos_t = math.sqrt(1 - sin_t * sin_t)
    k = eta * cos_i - cos_t
    ratio = abs((k * sin_i) / (-eta + k * cos_i))
    checks["rim ratio converges (2e-4)"] = abs(ratio - rim) < 2e-4
    checks["Delta -> 0 at rim"] = z * ratio < 0.01

    print(f"params: T={T} B={B} n={n} M={p['refractionStrength']}")
    print(f"Delta_max = {dmax:.6f} px   peak s = {peak_s:.4f}   "
          f"rim ratio = {rim:.6f}")
    print(f"worst |python - dart| (normalized LUT) = {worst:.3e}")

    m = data["metrics"]
    checks["4 acquires -> 1 build + 3 hits"] = (
        m["lutBuilds"] == 1 and m["lutCacheHits"] == 3)
    checks["1 live LUT after 4 acquires"] = m["activeLuts"] == 1

    ok = True
    for name, passed in checks.items():
        print(f"  {'PASS' if passed else 'FAIL'}  {name}")
        ok = ok and passed

    print("CROSS-CHECK " + ("OK" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
