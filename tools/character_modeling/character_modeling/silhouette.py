"""The side silhouette of the body (CHARACTER-PHYSIQUE-ART-001): what a profile reads as is
the front-most and back-most surface of the torso and legs at each height, so the physique's
profile is authored there, as curves, never as local pushes of single muscles.

Heights are normalized, h = z / stature (A-pose), so one curve serves every supported height.
Depths are centimetres at the reference stature (REFERENCE_STATURE_M), scaled by stature.

A study (`ANCHORS`) is three authored anchors on the build axis (the resolved muscularity
`mass`: lean -1, reference 0, strongman +1), each the correction from the restored body's
measured silhouette to that anchor's heroic target, per side ("front", "back"), as (h, cm)
points; the ends are zero so a correction never steps. Between anchors the correction is
interpolated linearly in mass and held at the anchors past them (bounded weights, never an
overshoot). `metrics` reads a silhouette for the regression gates: where the chest is
deepest, whether it leads the back, how much the waist pinches, how abruptly the back drops
above the glutes, and the contour's sharpest bend. Readings, never an art verdict.

Pure Python: no Blender.
"""

from __future__ import annotations

from .interpolation import linear_anchors

KIND = "silhouette"
REFERENCE_STATURE_M = 1.80
SIDES = ("front", "back")
## The restored body's silhouette corrected to the heroic targets (2026-11-01). Front: a
## strong abdominal wall (no pinch), a defined lower pectoral edge, the chest deepest HIGH
## (an upper-chest plateau, not an apex at the nipple line), the clavicle shelf into the neck.
## Back: the hamstring tie-in rising into one broad gluteal mass with no shelf above it, a
## shallower lumbar curve, the upper back flatter and below the chest (the chest leads).
ANCHORS = {
    "heroic_profile": {
        -1.0: {
            "front": ((0.50, 0.0), (0.52, 0.0), (0.54, 0.3), (0.56, 0.5), (0.58, 0.6), (0.60, 0.6), (0.62, 0.6),
                      (0.64, 0.3), (0.66, 0.3), (0.68, 0.4), (0.70, -0.1), (0.72, -0.2), (0.74, 0.1), (0.76, 0.4),
                      (0.78, 0.8), (0.80, 0.8), (0.82, 0.2), (0.84, 0.0)),
            "back": ((0.36, 0.0), (0.38, 0.0), (0.40, 0.3), (0.42, 0.5), (0.44, 0.2), (0.46, -0.6), (0.48, -0.8),
                     (0.50, -0.2), (0.52, 0.7), (0.54, 1.1), (0.56, 1.2), (0.58, 1.2), (0.60, 1.0), (0.62, 0.9),
                     (0.64, 0.5), (0.66, 0.1), (0.68, -0.3), (0.70, -0.5), (0.72, -0.7), (0.74, -0.7), (0.76, -0.7),
                     (0.78, -0.3), (0.80, 0.0), (0.82, 0.0)),
        },
        0.0: {
            "front": ((0.50, 0.0), (0.52, 0.1), (0.54, 0.5), (0.56, 0.6), (0.58, 0.5), (0.60, 0.3), (0.62, 0.4),
                      (0.64, 0.1), (0.66, 0.3), (0.68, 0.5), (0.70, -0.4), (0.72, -0.4), (0.74, 0.2), (0.76, 0.6),
                      (0.78, 1.1), (0.80, 1.2), (0.82, 0.2), (0.84, 0.0)),
            "back": ((0.36, 0.0), (0.38, 0.0), (0.40, 0.4), (0.42, 0.6), (0.44, 0.2), (0.46, -0.3), (0.48, -0.5),
                     (0.50, 0.1), (0.52, 0.8), (0.54, 1.1), (0.56, 1.2), (0.58, 1.2), (0.60, 1.1), (0.62, 0.9),
                     (0.64, 0.6), (0.66, 0.1), (0.68, -0.2), (0.70, -0.7), (0.72, -0.8), (0.74, -0.8), (0.76, -0.7),
                     (0.78, -0.3), (0.80, 0.0), (0.82, 0.0)),
        },
        1.0: {
            "front": ((0.50, 0.0), (0.52, 0.1), (0.54, 0.6), (0.56, 0.8), (0.58, 0.9), (0.60, 1.0), (0.62, 1.1),
                      (0.64, 0.8), (0.66, 0.6), (0.68, 0.2), (0.70, -1.4), (0.72, -1.2), (0.74, 0.0), (0.76, 1.1),
                      (0.78, 2.0), (0.80, 1.6), (0.82, 0.25), (0.84, 0.0)),
            "back": ((0.36, 0.0), (0.38, 0.0), (0.40, 0.2), (0.42, 0.4), (0.44, 0.2), (0.46, -0.1), (0.48, -0.4),
                     (0.50, 0.4), (0.52, 1.6), (0.54, 1.8), (0.56, 2.0), (0.58, 1.8), (0.60, 1.4), (0.62, 1.0),
                     (0.64, 0.4), (0.66, -0.1), (0.68, -0.7), (0.70, -1.4), (0.72, -1.6), (0.74, -1.6), (0.76, -1.5),
                     (0.78, -1.2), (0.80, -1.0), (0.82, -0.45), (0.84, 0.0)),
        },
    },
}
## `lean_glute` (2026-11-01, applied after the lean's limb girth): with his upper hamstring
## slimmed, the lean's glute rose steeply out of it to a point (0.7-0.9 cm per step from
## h 0.42 to the peak at 0.47). One round, muscular arc instead at the same lean scale: the
## hamstring tie-in filled under the glute, the peak a little lower and broader, the
## upper glute flowing into the lower back. The reference and strongman are untouched.
_ZERO = ((0.30, 0.0), (0.62, 0.0))
ANCHORS["lean_glute"] = {
    -1.0: {"front": _ZERO,
           "back": ((0.36, 0.0), (0.38, 0.0), (0.39, 0.1), (0.40, 0.3), (0.41, 0.6), (0.42, 1.0), (0.43, 0.9), (0.44, 0.7),
                    (0.45, 0.3), (0.46, -0.3), (0.47, -0.55), (0.48, -0.55), (0.49, -0.4), (0.50, -0.2), (0.51, 0.0),
                    (0.52, 0.1), (0.53, 0.2), (0.54, 0.1), (0.56, 0.1), (0.58, 0.0))},
    0.0: {"front": _ZERO, "back": _ZERO},
    1.0: {"front": _ZERO, "back": _ZERO},
}
## The correction is smoothed along h with this Gaussian sigma (a contour, never the
## authored points' corners).
SMOOTH_H = 0.012
## Metric bands (h).
CHEST_BAND = (0.62, 0.82)
WAIST_BAND = (0.52, 0.62)
SHELF_BAND = (0.46, 0.58)
TORSO_BAND = (0.40, 0.80)


def at(points, h):
    """A (h, value) polyline at h, zero past its ends."""
    if h <= points[0][0] or h >= points[-1][0]:
        return 0.0
    for (h0, v0), (h1, v1) in zip(points, points[1:]):
        if h <= h1:
            return v0 + (v1 - v0) * (h - h0) / (h1 - h0)
    return 0.0


def anchor_problems(study):
    """Why a study cannot be used: missing anchors or sides, unordered heights, ends that
    are not zero."""
    out = []
    anchors = ANCHORS.get(study)
    if anchors is None:
        return ["unknown silhouette study %s (known: %s)" % (study, ", ".join(sorted(ANCHORS)))]
    if sorted(anchors) != [-1.0, 0.0, 1.0]:
        out.append("%s: anchors must be lean -1, reference 0 and strongman +1" % study)
    for mass, sides in sorted(anchors.items()):
        for side in SIDES:
            points = sides.get(side)
            if not points:
                out.append("%s %+.0f: no %s correction" % (study, mass, side))
                continue
            if any(b[0] <= a[0] for a, b in zip(points, points[1:])):
                out.append("%s %+.0f %s: heights must increase" % (study, mass, side))
            if points[0][1] or points[-1][1]:
                out.append("%s %+.0f %s: the ends must be zero" % (study, mass, side))
    return out


def correction(study, mass, side, h):
    """The correction (cm at the reference stature) of `side` at height h for a body of
    muscularity `mass`: the anchors' corrections interpolated in mass, held past the ends."""
    anchors = ANCHORS[study]
    return linear_anchors({a: at(anchors[a][side], h) for a in anchors}, mass)


def smoothed(study, mass, side, h, step=0.002):
    """`correction` smoothed along h (SMOOTH_H)."""
    import math
    total = weight = 0.0
    k = int(3 * SMOOTH_H / step)
    for i in range(-k, k + 1):
        w = math.exp(-0.5 * (i * step / SMOOTH_H) ** 2)
        total += w * correction(study, mass, side, h + i * step)
        weight += w
    return total / weight


def _band(hs, values, band):
    return [(h, v) for h, v in zip(hs, values) if band[0] <= h <= band[1] and v == v]


def metrics(hs, front, back):
    """Readings of one silhouette (equal-step heights `hs`, depths in any one unit):
    `chest_apex_h` (where the front is deepest in the chest band), `chest_lead` (front's
    deepest minus the back's, chest band), `waist_ratio` (the shallowest total depth in the
    waist band over the deepest in the chest band), `glute_shelf` (the back's steepest drop
    per step in the shelf band) and `bend` (the largest second difference of either contour
    in the torso band, per step squared)."""
    chest_f = _band(hs, front, CHEST_BAND)
    chest_b = _band(hs, back, CHEST_BAND)
    apex_h, apex = max(chest_f, key=lambda p: p[1])
    total = [(h, f + b) for (h, f), (_h, b) in zip(zip(hs, front), zip(hs, back))]
    waist = min(v for h, v in _band(*zip(*total), WAIST_BAND))
    chest = max(v for h, v in _band(*zip(*total), CHEST_BAND))
    shelf = _band(hs, back, SHELF_BAND)
    drop = max(a[1] - b[1] for a, b in zip(shelf, shelf[1:]))

    def bend(values):
        v = [x for _h, x in _band(hs, values, TORSO_BAND)]
        return max(abs(v[i + 1] - 2 * v[i] + v[i - 1]) for i in range(1, len(v) - 1))
    return {"chest_apex_h": apex_h, "chest_lead": round(apex - max(v for _h, v in chest_b), 4),
            "waist_ratio": round(waist / chest, 4), "glute_shelf": round(drop, 4),
            "bend": round(max(bend(front), bend(back)), 4)}
