"""How a gripping hand meets its handle (PRES-GRIP-001): pure geometry, no Blender.

The handle is a prism along a point ``origin`` on its axis and a unit ``axis``, over
``half_length`` either side of the origin. Its section is a circle of ``radius``, or the real
oval grip: ``section = (a, b, a_axis)``, semi-axis ``a`` along the unit ``a_axis`` (perpendicular
to the axis) and ``b`` across it. For a surface point ``v`` its radial distance from the axis is
``rho = |(v - a) - ((v - a) . u) u|`` and its radial clearance ``d = rho - r(phi)``, ``r(phi)`` the
section's radius in that direction: negative inside the handle (penetration), about zero
touching, positive separated (a radial, not a normal, distance: exact for the circle, within a
fraction of a millimetre for a near-circular grip). Only points within the axial span count.

A hand is sampled as (patch, point) pairs, the patches being the three intended contacts of a
power grip — ``palm``, ``fingers``, ``thumb``. Per patch: the deepest penetration, the nearest
clearance, the samples in contact (within ``tolerance`` of the surface) and the circular mean of
their angles round the handle, measured from ``ref`` (a direction perpendicular to the axis).
A grip holds when no patch penetrates beyond ``penetration_limit`` and every patch has contact
(none floats). How the patches sit round the handle (fingers across from the palm, the thumb
from a third side) is described by ``diagnostics``, never a pass/fail: an anatomical thumb does
not meet one angle on every handle, and its opposing contact and silhouette are judged together.

The tolerances are project-specific visual tolerances for a stylized hand, not anatomical or
industry standards. Units are whatever the caller's points use (the inspector uses millimetres).
"""

from __future__ import annotations

import math

PATCHES = ("palm", "fingers", "thumb")
## Contact band: within this of the handle's surface, a sample touches it (candidate, 3 mm).
TOLERANCE = 3.0
## Allowed stylized overlap before a penetration is a problem (candidate, 1.5 mm).
PENETRATION_LIMIT = 1.5
## Opposition reading (descriptive, `diagnostics`): fingers across the handle from the palm, the
## thumb from a third side.
FINGERS_FROM_PALM_DEG = 90.0
THUMB_FROM_PALM_DEG = 45.0


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _scale(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def _norm(a):
    return math.sqrt(_dot(a, a))


def radial(point, origin, axis):
    """(axial position along ``axis`` from ``origin``, radial offset vector off the axis)."""
    rel = _sub(point, origin)
    t = _dot(rel, axis)
    return t, _sub(rel, _scale(axis, t))


def section_radius(off, radius, section=None):
    """The handle section's radius in the direction of the radial offset ``off``."""
    if section is None:
        return radius
    a, b, a_axis = section
    rho = _norm(off)
    if rho == 0.0:
        return min(a, b)
    c = _dot(off, a_axis) / rho
    s = math.sqrt(max(0.0, 1.0 - c * c))
    return a * b / math.sqrt((b * c) ** 2 + (a * s) ** 2)


def clearance(point, origin, axis, radius, section=None):
    """(axial position, radial clearance ``rho - r(phi)``) of one point."""
    t, off = radial(point, origin, axis)
    return t, _norm(off) - section_radius(off, radius, section)


def angle(point, origin, axis, ref):
    """Angle (degrees, -180..180) of ``point`` round the axis from ``ref`` (perpendicular to it)."""
    _t, off = radial(point, origin, axis)
    side = _cross(axis, ref)
    return math.degrees(math.atan2(_dot(off, side), _dot(off, ref)))


def _circular_mean(degrees):
    s = sum(math.sin(math.radians(a)) for a in degrees)
    c = sum(math.cos(math.radians(a)) for a in degrees)
    return math.degrees(math.atan2(s, c))


def separation(a, b):
    """Smallest angle between two directions round the axis (degrees, 0..180)."""
    return abs((a - b + 180.0) % 360.0 - 180.0)


def measure(samples, origin, axis, radius, half_length, ref, tolerance=TOLERANCE, section=None):
    """Per-patch contact report for ``samples`` = [(patch, point), ...] (see module doc)."""
    out = {}
    for patch in PATCHES:
        rows = []
        for name, point in samples:
            if name != patch:
                continue
            t, d = clearance(point, origin, axis, radius, section)
            if abs(t) <= half_length:
                rows.append((d, angle(point, origin, axis, ref)))
        touching = [a for d, a in rows if abs(d) <= tolerance or d < 0.0]
        out[patch] = {
            "samples": len(rows),
            "deepest": min((d for d, _a in rows), default=None),
            "nearest": min((abs(d) for d, _a in rows), default=None),
            "contact": len(touching),
            "angle": _circular_mean(touching) if touching else None,
        }
    return out


def problems(report, penetration_limit=PENETRATION_LIMIT):
    """What keeps a measured grip from holding (empty when it holds)."""
    found = []
    for patch in PATCHES:
        row = report[patch]
        if row["samples"] == 0:
            found.append("%s has no surface within the handle's span" % patch)
            continue
        if row["deepest"] < -penetration_limit:
            found.append("%s penetrates the handle by %.1f" % (patch, -row["deepest"]))
        if row["contact"] == 0:
            found.append("%s floats %.1f off the handle" % (patch, row["nearest"]))
    return found


def diagnostics(report):
    """How the patches sit round the handle: descriptive notes for the reviewer, never a
    failure (judge them with the opposing contact and the silhouette)."""
    notes = []
    palm, fingers, thumb = (report[p]["angle"] for p in PATCHES)
    if palm is not None and fingers is not None:
        sep = separation(palm, fingers)
        notes.append("fingers close %.0f deg round from the palm%s" % (sep, "" if sep >= FINGERS_FROM_PALM_DEG else " (beside it, not across)"))
    if palm is not None and thumb is not None:
        sep = separation(palm, thumb)
        notes.append("thumb closes %.0f deg round from the palm%s" % (sep, "" if sep >= THUMB_FROM_PALM_DEG else " (near the palm's side)"))
    return notes
