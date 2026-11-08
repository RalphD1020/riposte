"""The lower face's contour quality (HEAD-CONTOUR-001). Pure Python.

A profile is a polyline in a view plane (metres): the midline from the mouth round the chin
and under it to the neck, or the mandibular border (the jawline a side view reads) from the
chin back to the jaw's corner. It is resampled at equal arc length, so the measures do not
depend on the mesh's tessellation, and read as the turning between consecutive steps:

- a kink is one step turning far more than the steps around it (a planar facet's corner, a
  stair step), never a designed curve, which turns over several steps;
- a reversal is the turning changing sign between steps that both turn more than the noise
  (a ripple: a dip then a bump);
- a profile's sharpest corner is its largest single-step turn.

Curvature is never required to be zero: the chin turns under and the jaw turns up into the
ramus by design. Acceptance bands come from measured heads (`HEAD_CONTOUR`).
"""

from __future__ import annotations

import math

STEP_M = 0.002
## Steps on each side a kink is compared with (their median turning).
WINDOW = 3
## Degrees: a kink turns this much more than its neighbours; a reversal's steps both turn
## more than NOISE_DEG.
KINK_DEG = 8.0
NOISE_DEG = 2.0


def resample(points, step=STEP_M):
    """`points` [(x, y)] at equal arc length `step` along the polyline (its ends kept)."""
    if len(points) < 2:
        return list(points)
    out = [tuple(points[0])]
    carry = 0.0
    for a, b in zip(points, points[1:]):
        length = math.dist(a, b)
        if length == 0.0:
            continue
        s = step - carry
        while s <= length:
            f = s / length
            out.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
            s += step
        carry = length - (s - step)
    if math.dist(out[-1], points[-1]) > 1e-9:
        out.append(tuple(points[-1]))
    return out


def turns(points):
    """The signed turning (degrees, counter-clockwise positive) at each interior point."""
    out = []
    for a, b, c in zip(points, points[1:], points[2:]):
        h1 = math.atan2(b[1] - a[1], b[0] - a[0])
        h2 = math.atan2(c[1] - b[1], c[0] - b[0])
        out.append(math.degrees((h2 - h1 + math.pi) % (2.0 * math.pi) - math.pi))
    return out


def _median(values):
    ordered = sorted(values)
    n = len(ordered)
    return 0.0 if n == 0 else ordered[n // 2] if n % 2 else 0.5 * (ordered[n // 2 - 1] + ordered[n // 2])


def analyse(points, step=STEP_M):
    """A profile's contour measures: its length, sharpest corner, kinks [(arc m, degrees)]
    and reversals [arc m]."""
    samples = resample(points, step)
    turning = turns(samples)
    kinks, reversals = [], []
    for i, t in enumerate(turning):
        around = [abs(turning[j]) for j in range(max(0, i - WINDOW), min(len(turning), i + WINDOW + 1)) if j != i]
        if abs(t) - _median(around) > KINK_DEG:
            kinks.append((round((i + 1) * step, 4), round(t, 2)))
    for i in range(1, len(turning)):
        a, b = turning[i - 1], turning[i]
        if abs(a) > NOISE_DEG and abs(b) > NOISE_DEG and a * b < 0.0:
            reversals.append(round((i + 1) * step, 4))
    length = sum(math.dist(a, b) for a, b in zip(samples, samples[1:]))
    return {"length_m": round(length, 4), "sharpest_deg": round(max((abs(t) for t in turning), default=0.0), 2),
            "kinks": kinks, "reversals": reversals}


## Acceptance (HEAD-CONTOUR-001), per profile: no kink, at most this many reversals, and the
## sharpest single-step turn within this many degrees (the chin's turn under, at STEP_M).
HEAD_CONTOUR = {"midline": {"reversals": 1, "sharpest_deg": 24.0},
                "border": {"reversals": 1, "sharpest_deg": 16.0}}


def problems(name, measures):
    """Why a profile fails HEAD_CONTOUR. Empty means it passes."""
    band = HEAD_CONTOUR[name]
    out = ["%s kink at %.0f mm (%.1f deg)" % (name, s * 1000.0, t) for s, t in measures["kinks"]]
    if len(measures["reversals"]) > band["reversals"]:
        out.append("%s reverses %d times (at most %d)" % (name, len(measures["reversals"]), band["reversals"]))
    if measures["sharpest_deg"] > band["sharpest_deg"]:
        out.append("%s turns %.1f deg in one step (at most %.1f)" % (name, measures["sharpest_deg"], band["sharpest_deg"]))
    return out
