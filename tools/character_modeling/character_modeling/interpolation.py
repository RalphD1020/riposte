"""Interpolation between authored stations (CHARACTER-VARIATION-001).

Two schemes, each for its own kind of data:

- `linear_anchors`: the build axis's three anchors (lean -1, reference 0, strongman +1),
  linear between neighbours and held at the bounds: the same weights as the base's shape
  keys (a `_minus` or `_plus` key at |mass|), so every mapping that rides with the keys
  (silhouette, chest, girth, regional response) puts an in-between body exactly between its
  anchors in every system at once.
- `monotone`: a monotone cubic (Fritsch-Carlson) through any number of stations: exact at
  each station, continuous in slope, never leaving the range of its two neighbours (no
  overshoot), held past the ends. For authored data sampled at several stations (the head's
  physique profiles at the named configurations, a profile's landmarks along h).

Pure Python.
"""

from __future__ import annotations

ANCHORS = (-1.0, 0.0, 1.0)


def clamp(x, low=-1.0, high=1.0):
    return min(max(float(x), low), high)


def linear_anchors(values, mass):
    """`values` {-1: a, 0: b, 1: c} at `mass`, linear between neighbours, held at the bounds."""
    m = clamp(mass)
    lo, hi = (-1.0, 0.0) if m <= 0.0 else (0.0, 1.0)
    t = (m - lo) / (hi - lo)
    return (1.0 - t) * values[lo] + t * values[hi]


def monotone(points, x):
    """The monotone cubic through `points` [(x, v), ...] (increasing x) at x, held past the
    ends. Between two stations it never leaves their range."""
    xs, ys = [p[0] for p in points], [p[1] for p in points]
    if x <= xs[0]:
        return ys[0]
    if x >= xs[-1]:
        return ys[-1]
    n = len(xs)
    d = [(ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) for i in range(n - 1)]
    m = [d[0]] + [0.0 if d[i - 1] * d[i] <= 0.0 else (d[i - 1] + d[i]) / 2.0 for i in range(1, n - 1)] + [d[-1]]
    for i in range(n - 1):
        if d[i] == 0.0:
            m[i] = m[i + 1] = 0.0
            continue
        a, b = m[i] / d[i], m[i + 1] / d[i]
        s = a * a + b * b
        if s > 9.0:
            t = 3.0 / s ** 0.5
            m[i], m[i + 1] = t * a * d[i], t * b * d[i]
    i = max(k for k in range(n - 1) if xs[k] <= x)
    w = xs[i + 1] - xs[i]
    t = (x - xs[i]) / w
    h00, h10, h01, h11 = 2 * t ** 3 - 3 * t ** 2 + 1, t ** 3 - 2 * t ** 2 + t, -2 * t ** 3 + 3 * t ** 2, t ** 3 - t ** 2
    return h00 * ys[i] + h10 * w * m[i] + h01 * ys[i + 1] + h11 * w * m[i + 1]
