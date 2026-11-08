"""The anime eye (FACE-EYE-001): a graphic eye built from flat layers, never a human eye.

Anime eyes are drawn, not modelled: an eye-white shape (the aperture), an iris with its
darker rim, a distinct pupil and one highlight, all clipped by the eye-white shape as a 2D
clipping mask would clip them, and a tapered lash-line graphic along the upper edge with a
pointed outer wing, plus a short accent under the outer corner. There are no eyelids, no
eyeball and no lid creases: expression is the drawing's own shape (the aperture's edges, the
lash line riding the upper edge, the iris's place and how much of it the aperture shows).
A blink brings the upper edge down onto the lower one, the white and iris squashed to the
closed line so they vanish with it, the lash line becoming the closed-eye line.

Everything here is in the eye's own design space, so it is pure and testable: x across the
eye (-0.5 the inner corner, +0.5 the outer, outward positive on both sides), y in eye
heights (the mark's `height` of the chart), depth in metres off the head's surface along
the eye's frame normal. The layers lie in a shallow stack on the recessed eye panel (white,
then iris, pupil and highlight, then the lines), each seated on the resolved head by the
Blender builder, so the drawing curves with the face and never stands off it.

Channels are relative shape keys (linear in their weights, as blend shapes are), one set
per side mesh: the brow's, the upper edge's, the lower edge's, the gaze and the blink.

Pure Python: no Blender.
"""

from __future__ import annotations

import math

KIND = "eye_assembly"
## Components and their node prefixes (FacePresentation finds them by prefix).
COMPONENTS = {"eye": "Eye", "iris": "EyeIris", "line": "EyeLine", "brow": "Brow", "mask": "EyeMask"}
## Material slots per component, in face-index order (the identity palette names them).
MATERIALS = {"eye": ("eye",), "iris": ("iris_rim", "iris", "pupil", "catchlight"), "line": ("lid_line",),
             "brow": ("hair",), "mask": ("skin",)}
## Occlusion (a profile's `occlusion`): "clip" (the default) clips the iris to the aperture
## in every key; "mask" keeps the iris and pupil perfect circles (they only move with the
## gaze) and hides what falls outside the aperture under the eye mask, a skin layer over the
## iris shaped by the same aperture channels. The mask's edges are the aperture's edges, so
## it blends linearly with them and the occlusion is exact in every blend (a clipped iris
## blended from clipped keys warps).
MASK = "mask"
## The white (a profile's `white`): "aperture" (the default) is drawn between the aperture's
## edges and keyed with them; "backing" (masked eyes) is fixed and the mask shapes it.
APERTURE = "aperture"
BACKING = "backing"
## The mask's outer bounds (eye heights): beyond any iris the gaze can carry.
MASK_TOP = 0.62
MASK_BOTTOM = -0.66

BROW_CHANNELS = ("brow_inner_down", "brow_inner_up", "brow_outer_up", "brow_outer_down", "brow_tension")
UPPER_CHANNELS = ("lid_upper_open", "lid_upper_close", "lid_upper_inner_down", "lid_upper_outer_up")
LOWER_CHANNELS = ("lid_lower_raise", "lid_lower_tension", "lid_lower_relax")
GAZE_CHANNELS = ("gaze_left", "gaze_right", "gaze_up", "gaze_down")
BLINK = "blink"
CHANNELS = BROW_CHANNELS + UPPER_CHANNELS + LOWER_CHANNELS + GAZE_CHANNELS + (BLINK,)
## The aperture's channels (they reshape the drawing; the iris is clipped by it).
APERTURE_CHANNELS = UPPER_CHANNELS + LOWER_CHANNELS + ("gaze_up", "gaze_down", BLINK)
## The shape keys each component carries.
COMPONENT_KEYS = {
    "brow": BROW_CHANNELS,
    "eye": APERTURE_CHANNELS,
    "line": APERTURE_CHANNELS,
    "iris": APERTURE_CHANNELS + ("gaze_left", "gaze_right"),
    "mask": APERTURE_CHANNELS,
}

## Aperture edge deltas at full weight, in eye heights, shaped across the eye by `_bump`
## (zero at the corners: the corners are the drawing's fixed points) and inner/outer weights.
UPPER_DELTA = {"lid_upper_open": 0.2, "lid_upper_close": -0.36, "lid_upper_inner_down": -0.3,
               "lid_upper_outer_up": 0.22, "gaze_up": 0.1, "gaze_down": -0.12}
LOWER_DELTA = {"lid_lower_raise": 0.14, "lid_lower_tension": 0.06, "lid_lower_relax": -0.07,
               "gaze_up": 0.04, "gaze_down": -0.08, BLINK: 0.05}
LOWER_TENSION_STRAIGHTEN = 0.5
## A blink closes the upper edge onto the lower edge's rest line plus this gap.
BLINK_GAP = 0.01
## The closed eye's lash line is this share of its open thickness (a line, not a smear).
BLINK_LINE_SHARE = 0.55
## Gaze: the iris centre's travel at full weight (eye widths across, eye heights up/down);
## a profile's `iris.gaze` ({"x", "up", "down"}) sets its own (a large iris already fills
## the eye: it travels less, and stays inside the white at the extremes).
GAZE_X = 0.16
GAZE_UP = 0.14
GAZE_DOWN = 0.12
## Brow channel deltas at full weight (the brow is the swept ridge mark; see face_features).
BROW_DELTA = {
    "brow_inner_down": {"along_m": -0.0032, "inward_u": 0.018},
    "brow_inner_up": {"along_m": 0.0030},
    "brow_outer_up": {"along_m": 0.0036},
    "brow_outer_down": {"along_m": -0.0022},
    "brow_tension": {"top_m": -0.0012, "depth": 0.35},
}

## Columns across the aperture and rays round the iris (fixed topology for every key).
SAMPLES = 41
IRIS_RAYS = 28
## The clip keeps clipped points this far inside the aperture (a share of the ray), and
## LOWER_CLIP_INSET (eye heights) above the lower edge: a blend of two keys mixes the clipped
## iris and the white's edges linearly and they drift apart near the edges (measured on the
## built meshes, 2026-11-01). At the upper edge the lash line's overlap covers the drift.
## A large iris is clipped over more of its outline, so its drift is larger: a profile's
## `iris.clip_inset` / `iris.lower_clip_inset` keep it further inside.
CLIP_INSET = 0.006
LOWER_CLIP_INSET = 0.035
## Validation (structural; never an art verdict).
MIN_APERTURE = 0.08
BLINK_CLOSED = 0.05
PUPIL_VISIBLE = 0.5


def _clamp(value, low, high):
    return max(low, min(high, value))


def polyline_at(points, x):
    """A polyline [(x, y)] at x, held level past its ends."""
    if x <= points[0][0]:
        return points[0][1]
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return points[-1][1]


def _bump(x):
    return max(0.0, 1.0 - (2.0 * x) ** 2)


def _inner(x):
    return _clamp(0.5 - x, 0.0, 1.0)


def _outer(x):
    return _clamp(0.5 + x, 0.0, 1.0)


def _corner_line(profile, x):
    upper, lower = profile["upper"], profile["lower"]
    y0 = 0.5 * (upper[0][1] + lower[0][1])
    y1 = 0.5 * (upper[-1][1] + lower[-1][1])
    return y0 + (y1 - y0) * (x + 0.5)


def channel_delta(profile, edge, channel, x):
    """An aperture edge's change (eye heights) at x at full weight: edge "upper" or "lower"."""
    if edge == "upper":
        if channel == BLINK:
            ## Onto the lower edge as the blink leaves it (it rises a little too).
            closed = polyline_at(profile["lower"], x) + LOWER_DELTA[BLINK] * _bump(x) + BLINK_GAP
            return closed - polyline_at(profile["upper"], x)
        amount = UPPER_DELTA.get(channel, 0.0)
        shape = _inner(x) if channel == "lid_upper_inner_down" else _outer(x) if channel == "lid_upper_outer_up" else 1.0
        return amount * _bump(x) * shape
    delta = LOWER_DELTA.get(channel, 0.0) * _bump(x)
    if channel == "lid_lower_tension":
        delta += LOWER_TENSION_STRAIGHTEN * (_corner_line(profile, x) - polyline_at(profile["lower"], x)) * _bump(x)
    return delta


def edge(profile, which, x, weights=None):
    """The aperture's upper or lower edge at x under channel `weights` ({channel: w})."""
    rest = polyline_at(profile[which], x)
    return rest + sum(w * channel_delta(profile, which, c, x) for c, w in (weights or {}).items() if c in APERTURE_CHANNELS)


def margin(profile, component, x, weights=None):
    """Compatibility name: "lid_upper" is the upper edge, anything else the lower."""
    return edge(profile, "upper" if component == "lid_upper" else "lower", x, weights)


def columns():
    return [-0.5 + i / (SAMPLES - 1) for i in range(SAMPLES)]


def inside(profile, weights, x, y, lower_inset=0.0):
    """Whether (x, y) lies inside the aperture (its lower edge raised by `lower_inset`)."""
    if not -0.5 <= x <= 0.5:
        return False
    return edge(profile, "lower", x, weights) + lower_inset < y < edge(profile, "upper", x, weights)


def iris_centre(profile, side, weights=None):
    """The iris centre (x, y) under the gaze weights. `gaze_left` is the character's left:
    outward on the left eye, inward on the right."""
    weights = weights or {}
    x, y = profile["iris"]["centre"]
    travel = profile["iris"].get("gaze", {})
    left = 1.0 if side == "L" else -1.0
    x += travel.get("x", GAZE_X) * left * (weights.get("gaze_left", 0.0) - weights.get("gaze_right", 0.0))
    y += travel.get("up", GAZE_UP) * weights.get("gaze_up", 0.0) - travel.get("down", GAZE_DOWN) * weights.get("gaze_down", 0.0)
    return x, y


def _clip(profile, weights, centre, point):
    """`point` clipped to the iris's region of the aperture along the ray from `centre`
    (inside: unchanged)."""
    lower = profile["iris"].get("lower_clip_inset", LOWER_CLIP_INSET)
    if inside(profile, weights, *point, lower_inset=lower):
        return point
    lo, hi = 0.0, 1.0
    for _k in range(30):
        mid = 0.5 * (lo + hi)
        q = (centre[0] + (point[0] - centre[0]) * mid, centre[1] + (point[1] - centre[1]) * mid)
        if inside(profile, weights, *q, lower_inset=lower):
            lo = mid
        else:
            hi = mid
    t = max(0.0, lo - profile["iris"].get("clip_inset", CLIP_INSET))
    return (centre[0] + (point[0] - centre[0]) * t, centre[1] + (point[1] - centre[1]) * t)


def _seated_centre(profile, weights, centre):
    """The clip centre: the iris centre held inside the aperture (a closing eye squashes the
    iris onto the closed line with it)."""
    x = _clamp(centre[0], -0.45, 0.45)
    lo = edge(profile, "lower", x, weights) + profile["iris"].get("lower_clip_inset", LOWER_CLIP_INSET)
    hi = edge(profile, "upper", x, weights)
    if hi <= lo:
        return x, 0.5 * (hi + edge(profile, "lower", x, weights))
    return x, _clamp(centre[1], lo + 1e-6, hi - 1e-6)


def iris_shape(profile, side, weights=None):
    """The iris layer under `weights`: rings of IRIS_RAYS points each (outer iris, the rim's
    inner edge, the pupil), the pupil's centre and the highlight's four points, every point
    clipped to the aperture; (x, y) pairs."""
    weights = weights or {}
    iris = profile["iris"]
    cx, cy = iris_centre(profile, side, weights)
    rx, ry = 0.5 * iris["width"], 0.5 * iris["height"]
    masked = profile.get("occlusion") == MASK
    clip_centre = (cx, cy) if masked else _seated_centre(profile, weights, (cx, cy))

    def ring(sx, sy, ox=0.0, oy=0.0, count=IRIS_RAYS, turn=0.0):
        out = []
        for k in range(count):
            a = turn + 2.0 * math.pi * k / count
            p = (cx + ox * rx + rx * sx * math.cos(a), cy + oy * ry + ry * sy * math.sin(a))
            out.append(p if masked else _clip(profile, weights, clip_centre, p))
        return out
    if masked:
        return {"iris": ring(1.0, 1.0), "rim": ring(iris["rim"], iris["rim"]),
                "pupil": ring(iris["pupil"], iris["pupil"] * iris.get("pupil_aspect", 1.0)), "pupil_centre": (cx, cy),
                "catchlight": ring(iris["catchlight"]["size"], iris["catchlight"]["size"] * iris["width"] / iris["height"] * 2.0,
                                   iris["catchlight"]["offset"][0], iris["catchlight"]["offset"][1], count=4, turn=math.pi / 4)}
    pupil = iris["pupil"]
    glint = iris["catchlight"]
    return {"iris": ring(1.0, 1.0), "rim": ring(iris["rim"], iris["rim"]),
            "pupil": ring(pupil, pupil * iris.get("pupil_aspect", 1.0)),
            "pupil_centre": _clip(profile, weights, clip_centre, (cx, cy)),
            "catchlight": ring(glint["size"], glint["size"] * iris["width"] / iris["height"] * 2.0,
                               glint["offset"][0], glint["offset"][1], count=4, turn=math.pi / 4)}


def fixed_white(profile):
    """Whether the profile's white is a fixed backing (`"white": "backing"`, masked eyes only)."""
    return profile.get("white") == BACKING and profile.get("occlusion") == MASK


def white_strip(profile, weights=None):
    """The eye white: per column (x, lower edge, upper edge), the upper edge never below the
    lower (a closed eye is a closed line). A fixed white (`fixed_white`) is the same backing
    whatever the weights: the envelope every aperture channel opens it to, within the mask's
    bounds, so the mask alone shapes what shows. A white that moves with the aperture sweeps
    straight chords across the recessed panel between its keys: at half blink it stood up to
    1.25 mm off the panel, in front of the iris and the mask (measured 2026-11-06)."""
    out = []
    fixed = fixed_white(profile)
    for x in columns():
        if fixed:
            lo = polyline_at(profile["lower"], x) + sum(min(0.0, channel_delta(profile, "lower", c, x)) for c in APERTURE_CHANNELS)
            hi = polyline_at(profile["upper"], x) + sum(max(0.0, channel_delta(profile, "upper", c, x)) for c in APERTURE_CHANNELS)
            lo, hi = max(lo, MASK_BOTTOM), min(hi, MASK_TOP)
        else:
            lo, hi = edge(profile, "lower", x, weights), edge(profile, "upper", x, weights)
        out.append((x, lo, max(hi, lo)))
    return out


def component_keys(profile, component):
    """The shape keys a component of this profile carries: COMPONENT_KEYS, except a fixed
    white (`fixed_white`), which carries none."""
    if component == "eye" and fixed_white(profile):
        return ()
    return COMPONENT_KEYS[component]


def lash_line(profile, weights=None):
    """The upper lash line: per column (x, bottom, top) riding the upper edge (overlapping
    the white by the line's `overlap`), its thickness thinning to BLINK_LINE_SHARE as the eye
    closes, then the pointed outer wing tip and inner tip; and the lower accent per column
    (x, top, bottom) under the outer corner."""
    line = profile["line"]
    blink = (weights or {}).get(BLINK, 0.0)
    thin = 1.0 - (1.0 - BLINK_LINE_SHARE) * _clamp(blink, 0.0, 1.0)
    upper = []
    for x in columns():
        y = max(edge(profile, "upper", x, weights), edge(profile, "lower", x, weights))
        upper.append((x, y - line["overlap"], y + polyline_at(line["thickness"], x) * thin))
    end_y = upper[-1][1] + line["overlap"]
    start_y = upper[0][1] + line["overlap"]
    wing = (0.5 + line["wing"][0], end_y + line["wing"][1])
    tip = (-0.5 - line["inner"][0], start_y + line["inner"][1])
    accent = []
    x0 = line["lower"]["from"]
    for x in columns():
        if x < x0:
            continue
        y = edge(profile, "lower", x, weights)
        t = line["lower"]["thickness"] * math.sin(math.pi * (x - x0) / (0.5 - x0)) ** 0.7 if x < 0.5 else 0.0
        accent.append((x, y + line["overlap"] * 0.5, y + line["overlap"] * 0.5 - t * thin))
    return {"upper": upper, "wing": wing, "tip": tip, "accent": accent}


def brow_delta(channel, t):
    """A brow channel at full weight at column t (-0.5 inner .. 0.5 outer): (bottom metres,
    top metres along the surface, depth scale change, inward chart u)."""
    d = BROW_DELTA[channel]
    shape = _inner(t) if "inner" in channel else _outer(t) if "outer" in channel else _bump(t)
    along = d.get("along_m", 0.0) * shape
    return along, along + d.get("top_m", 0.0) * _inner(t), d.get("depth", 0.0) * _bump(t), d.get("inward_u", 0.0) * shape


def profile_problems(profile):
    """Why an eye profile cannot be built: missing blocks, edges that do not span the eye
    corner to corner, a line without thickness."""
    out = ["eye profile lacks %s" % k for k in ("upper", "lower", "iris", "line", "depth") if k not in profile]
    if out:
        return out
    for name in ("upper", "lower"):
        line = profile[name]
        if abs(line[0][0] + 0.5) > 1e-9 or abs(line[-1][0] - 0.5) > 1e-9:
            out.append("the %s edge must run from x -0.5 to 0.5" % name)
        if any(b[0] <= a[0] for a, b in zip(line, line[1:])):
            out.append("the %s edge's x must increase" % name)
    if any(t <= 0.0 for _x, t in profile["line"]["thickness"]):
        out.append("the lash line needs a positive thickness")
    d = profile["depth"]
    order = [d[k] for k in ("white_m", "iris_m", "pupil_m", "catchlight_m", "line_m")]
    if order != sorted(order) or len(set(order)) != len(order):
        out.append("layer depths must rise white < iris < pupil < catchlight < line")
    occlusion = profile.get("occlusion", "clip")
    if occlusion not in ("clip", MASK):
        out.append("occlusion must be clip or mask, not %s" % occlusion)
    elif occlusion == MASK and not d["catchlight_m"] < d.get("mask_m", -1.0) < d["line_m"]:
        out.append("a masked eye needs depth mask_m between catchlight_m and line_m")
    white = profile.get("white", APERTURE)
    if white not in (APERTURE, BACKING):
        out.append("white must be aperture or backing, not %s" % white)
    elif white == BACKING and occlusion != MASK:
        out.append("a backing white needs occlusion mask (the mask shapes it)")
    return out


def _area(points):
    return 0.5 * abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(points, points[1:] + points[:1])))


## Samples per axis of the masked pupil's visible share.
VISIBLE_SAMPLES = 24


def pupil_visible(profile, side, weights=None):
    """The share of the pupil's full (unclipped) area the aperture shows."""
    iris = profile["iris"]
    rx = 0.5 * iris["width"] * iris["pupil"]
    ry = 0.5 * iris["height"] * iris["pupil"] * iris.get("pupil_aspect", 1.0)
    full = math.pi * rx * ry
    if not full:
        return 0.0
    if profile.get("occlusion") == MASK:
        cx, cy = iris_centre(profile, side, weights)
        seen = total = 0
        for i in range(VISIBLE_SAMPLES):
            for j in range(VISIBLE_SAMPLES):
                u, v = -1.0 + (2 * i + 1) / VISIBLE_SAMPLES, -1.0 + (2 * j + 1) / VISIBLE_SAMPLES
                if u * u + v * v > 1.0:
                    continue
                total += 1
                seen += inside(profile, weights or {}, cx + u * rx, cy + v * ry)
        return seen / total
    return _area(iris_shape(profile, side, weights)["pupil"]) / full


def mask_strip(profile, weights=None):
    """The eye mask (occlusion "mask"): per column (x, upper edge, MASK_TOP) above the
    aperture and (x, lower edge, MASK_BOTTOM) below it, the edges exactly the aperture's
    (the upper never below the lower: a closed eye is covered whole)."""
    upper, lower = [], []
    for x in columns():
        lo, hi = edge(profile, "lower", x, weights), edge(profile, "upper", x, weights)
        upper.append((x, max(hi, lo), MASK_TOP))
        lower.append((x, lo, MASK_BOTTOM))
    return {"upper": upper, "lower": lower}


def state_problems(profile, weights, side, label=""):
    """Structural problems of one channel state on one side: the aperture's opening (and a
    closing blink), the pupil readable, the iris centre inside the drawing."""
    out = []
    blink = weights.get(BLINK, 0.0)
    for x in columns():
        gap = edge(profile, "upper", x, weights) - edge(profile, "lower", x, weights)
        if blink >= 1.0 - 1e-9:
            if abs(gap) > BLINK_CLOSED:
                out.append("%s%s: a full blink leaves %.3f between the edges at x %.2f" % (label, side, gap, x))
        elif abs(x) < 0.45 and gap < MIN_APERTURE * (1.0 - blink):
            out.append("%s%s: the aperture is %.3f tall at x %.2f (min %.3f)" % (label, side, gap, x, MIN_APERTURE))
    if blink < 0.5:
        seen = pupil_visible(profile, side, weights)
        if seen < PUPIL_VISIBLE:
            out.append("%s%s: only %.0f%% of the pupil shows" % (label, side, seen * 100))
    return out
