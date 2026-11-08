"""The foundation's ear (a foundation anatomical component, not an identity asset): one
designed outline and relief, built in each resolved head's own frame, so every character
inherits the same ear sized and placed by its head. Pure Python.

Ear-local coordinates, in ear heights (E = EAR_HEIGHT x the head's chart height): `a`
forward (toward the face), `b` up, `h` out of the head. The outline runs from the root of
the helix (front, top) over the top, down the back, round the lobule, through the
intertragic notch and up the tragus; s is the fraction from the concha centre to the
outline. Simplified anatomy, proportionate and strong (All Might's language, never a
small decorative ear, an elf's or a cartoon's): a continuous helix rim, thicker at the top
and absent at the lobule; a Y-shaped antihelix (its body and two crura); a shallow concha
bowl; a small tragus; a soft rounded lobule; the front sunk into the skull so the root has
no seam.
"""

from __future__ import annotations

import math

## Size and placement on the head's chart (v = height fraction from the chin): the top at
## about brow height, the bottom at about the nose base.
EAR_TOP_V = 0.66
EAR_BOTTOM_V = 0.35
EAR_HEIGHT = EAR_TOP_V - EAR_BOTTOM_V
## The long axis leans back (top behind bottom); the back of the ear stands out from the
## skull by FLARE_DEG; the front ROOT_SINK ear heights into the skull, following the skull's
## own curvature over ROOT_BLEND ear heights (`placement`, `follow_weight`).
TILT_DEG = 15.0
FLARE_DEG = 16.0
## With the three-physique head design (`variation.design_coordinate`, -1 lean .. +1
## strongman) the flare follows the build, every build flatter than FLARE_DEG: the ear sits
## against the side plane as supporting form, never silhouette noise, flattest on the lean
## head (narrowest, where a flared ear reads widest against it).
DESIGN_FLARE_DEG = (8.5, 9.0, 10.5)
## And its size (a scale on EAR_HEIGHT, the root anchored): the lean head's face narrows
## below the cheekbones and a full-size ear read too prominent from the front; reference and
## strongman keep the approved ear. The lean flare (8.5) keeps the smaller ear's free rim
## off the skull (at 7 degrees three rim vertices sank into it, at 8 one; at 0.88 the helix
## top touched it).
DESIGN_SCALE = (0.90, 1.0, 1.0)
ROOT_A = 0.10
ROOT_SINK = 0.05
ROOT_BLEND = 0.22
## The root's depth, as a fraction of the head's depth from its mid-depth (negative is
## forward): never far back on the skull.
ROOT_DEPTH_OFFSET = -0.03
## The outline, (a, b) in ear heights, from the helix root round to the tragus.
OUTLINE = (
    (0.12, 0.28), (0.06, 0.42), (-0.04, 0.50), (-0.16, 0.48), (-0.27, 0.40), (-0.35, 0.26),
    (-0.38, 0.10), (-0.36, -0.06), (-0.31, -0.20), (-0.24, -0.33), (-0.15, -0.45), (-0.05, -0.50),
    (0.04, -0.46), (0.09, -0.36), (0.12, -0.24), (0.17, -0.12), (0.18, 0.00), (0.15, 0.13),
)
CONCHA = (0.0, -0.04)
## Outline-parameter bands (t in 0..1 around OUTLINE): (lo, full, full_hi, hi).
HELIX = (-0.05, 0.02, 0.56, 0.66)
HELIX_TOP = (0.04, 0.12, 0.26, 0.36)
LOBULE = (0.56, 0.64, 0.74, 0.80)
ANTIHELIX = (0.12, 0.20, 0.46, 0.56)
INFERIOR_CRUS = (-0.04, 0.02, 0.12, 0.20)
TRAGUS_T = 0.88
## The attachment arc of the outline (wrapping past 1): from the lobule's front attachment
## through the tragus to the helix root, sunk ROOT_ARC_SINK ear heights into the skull at
## the outline; its ramps are where the free rim emerges from the skin, gradually.
ROOT_ARC = (0.64, 0.70, 1.02, 1.10)
ROOT_ARC_SINK = 0.06
## Relief, in ear heights.
BASE = 0.045
RIM = 0.060
RIM_TOP = 0.35
SCAPHA = -0.018
ANTIHELIX_LIFT = 0.034
CRUS_LIFT = 0.022
CONCHA_DEPTH = -0.036
TRAGUS_LIFT = 0.050
LOBULE_LIFT = 0.020
THICKNESS = 0.045
EDGE = 0.012


def band(x, window):
    lo, full, full_hi, hi = window
    if x <= lo or x >= hi:
        return 0.0
    if x < full:
        return 0.5 - 0.5 * math.cos(math.pi * (x - lo) / (full - lo))
    if x > full_hi:
        return 0.5 + 0.5 * math.cos(math.pi * (x - full_hi) / (hi - full_hi))
    return 1.0


def bump(x, centre, radius):
    d = (x - centre) / radius
    return math.exp(-d * d)


def _catmull(points, t):
    n = len(points)
    f = t * n
    i = int(math.floor(f)) % n
    u = f - math.floor(f)
    p0, p1, p2, p3 = (points[(i + k) % n] for k in (-1, 0, 1, 2))
    return tuple(0.5 * (2 * p1[c] + (-p0[c] + p2[c]) * u + (2 * p0[c] - 5 * p1[c] + 4 * p2[c] - p3[c]) * u * u
                        + (-p0[c] + 3 * p1[c] - 3 * p2[c] + p3[c]) * u ** 3) for c in (0, 1))


def outline_at(t):
    """The smooth closed outline (a, b) at t in 0..1."""
    return _catmull(OUTLINE, t % 1.0)


def relief(s, t):
    """(front h, back h) in ear heights at radial fraction s and outline parameter t."""
    tc = t % 1.0
    helix = band(tc, HELIX) + band(tc - 1.0, HELIX)
    rim = RIM * (1.0 + RIM_TOP * band(tc, HELIX_TOP)) * bump(s, 0.92, 0.07) * helix
    scapha = SCAPHA * bump(s, 0.80, 0.05) * helix
    antihelix = ANTIHELIX_LIFT * bump(s, 0.66, 0.07) * band(tc, ANTIHELIX)
    crus = CRUS_LIFT * bump(s, 0.50, 0.07) * (band(tc, INFERIOR_CRUS) + band(tc - 1.0, INFERIOR_CRUS))
    lobe = band(tc, LOBULE) * _smooth(0.35, 0.70, s)
    concha = CONCHA_DEPTH * (1.0 - _smooth(0.22, 0.55, s)) * (1.0 - lobe)
    gap = min(abs(tc - TRAGUS_T), 1.0 - abs(tc - TRAGUS_T))
    tragus = TRAGUS_LIFT * bump(s, 0.72, 0.12) * bump(gap, 0.0, 0.05)
    lobule = LOBULE_LIFT * lobe * (1.0 - _smooth(0.88, 1.0, s))
    edge = EDGE * _smooth(0.94, 1.0, s)
    sink = ROOT_ARC_SINK * attachment(tc) * _smooth(0.80, 1.0, s)
    front = BASE + rim + scapha + antihelix + crus + concha + tragus + lobule - edge - sink
    back = front - THICKNESS * (1.0 - _smooth(0.90, 1.0, s))
    return front, min(back, front - 0.004)


def attachment(t):
    """How much of the outline at t is the ear's attachment to the skull (1 on the arc from
    the lobule's front through the tragus to the helix root, 0 on the free rim)."""
    tc = t % 1.0
    return max(band(tc, ROOT_ARC), band(tc + 1.0, ROOT_ARC))


def _smooth(lo, hi, x):
    if x <= lo:
        return 0.0
    if x >= hi:
        return 1.0
    y = (x - lo) / (hi - lo)
    return y * y * (3.0 - 2.0 * y)


def _anchored(values, coordinate):
    lean, reference, strong = values
    c = max(-1.0, min(1.0, coordinate))
    return reference + (reference - lean) * c if c < 0.0 else reference + (strong - reference) * c


def design_flare(coordinate):
    """The flare (degrees) at a build coordinate: DESIGN_FLARE_DEG piecewise linear between
    the lean, reference and strongman anchors, held at the ends."""
    return _anchored(DESIGN_FLARE_DEG, coordinate)


def design_scale(coordinate):
    """The ear's size (a scale on EAR_HEIGHT) at a build coordinate (DESIGN_SCALE)."""
    return _anchored(DESIGN_SCALE, coordinate)


def placement(a, flare_deg=FLARE_DEG):
    """Out-of-skull offset (ear heights) at forward coordinate a: the back flares out, the
    front sinks into the skull."""
    flare = math.tan(math.radians(flare_deg)) * max(0.0, ROOT_A - a)
    sink = ROOT_SINK * _smooth(ROOT_A - 0.16, ROOT_A + 0.02, a)
    return flare - sink


def follow_weight(a):
    """How much the ear at forward coordinate a follows the skull's surface (1 at the root
    and ahead of it, 0 on the free ear), so the root edge never stands off a curving skull."""
    return _smooth(ROOT_A - ROOT_BLEND, ROOT_A, a)


RINGS = 18
AROUND = 56


def outline_indices(rings=RINGS, around=AROUND):
    """Indices of grid()'s outline ring (shared by both sheets)."""
    return range(1 + (rings - 1) * around, 1 + rings * around)


def root_blend(rings=RINGS, around=AROUND):
    """Per grid() point, how much it may shade as the skin it meets: the attachment arc's
    outer rings only (never the concha, which also lies near the skull)."""
    weights = []
    for sheet in (0, 1):
        weights.append(0.0)
        for r in range(1, rings + 1):
            if r == rings and sheet == 1:
                continue
            s = r / rings
            weights += [attachment(k / around) * _smooth(0.80, 1.0, s) for k in range(around)]
    return weights


def grid(rings=RINGS, around=AROUND, flare_deg=FLARE_DEG):
    """The ear's closed surface in ear-local units: (points [(a, b, h)], quads [(i, j, k, l)]).
    Front and back sheets share the outline ring; the concha centre is one point per sheet."""
    points, quads, tris = [], [], []
    centre = CONCHA

    def point(s, t, sheet):
        oa, ob = outline_at(t)
        a = centre[0] + s * (oa - centre[0])
        b = centre[1] + s * (ob - centre[1])
        front, back = relief(s, t)
        return (a, b, (front if sheet == 0 else back) + placement(a, flare_deg))

    index = {}
    for sheet in (0, 1):
        index[(sheet, "c")] = len(points)
        points.append(point(0.0, 0.0, sheet))
        for r in range(1, rings + 1):
            s = r / rings
            for k in range(around):
                if r == rings and sheet == 1:
                    index[(1, r, k)] = index[(0, r, k)]
                    continue
                index[(sheet, r, k)] = len(points)
                points.append(point(s, k / around, sheet))
    for sheet in (0, 1):
        for k in range(around):
            k2 = (k + 1) % around
            tri = (index[(sheet, "c")], index[(sheet, 1, k)], index[(sheet, 1, k2)])
            tris.append(tri if sheet == 0 else tri[::-1])
        for r in range(1, rings):
            for k in range(around):
                k2 = (k + 1) % around
                quad = (index[(sheet, r, k)], index[(sheet, r + 1, k)], index[(sheet, r + 1, k2)], index[(sheet, r, k2)])
                quads.append(quad if sheet == 0 else quad[::-1])
    return points, quads, tris
