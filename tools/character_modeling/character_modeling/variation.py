"""Resolve a character definition into the variation the base builder applies.

One definition, one path, for every character and every crowd member (CHARACTER-VARIATION-001):

    definition (body inputs, development, head identity)
      -> physique (``physique.resolve_physique``: mass and the physical outputs, unchanged)
      -> the base's physique parameters (the shape keys of ``<base>.configuration.json``)
      -> head proportions (allometric size) and head morphology (physique profile + identity)
      -> face-mark placement (identity only)

Body inputs (``parameters.BODY_INPUTS``) keep their meaning and bounds:

- ``height_m`` is stature: the whole figure scales by ``h = height / 1.80``, as the game's
  fighter scales. The head does not: it grows as ``h ** HEAD_STATURE_EXPONENT`` (adult head
  height varies about half as much as stature), so its scale relative to the body is
  ``h ** (HEAD_STATURE_EXPONENT - 1)``.
- ``frame_build`` is skeletal breadth: it drives ``upper_body`` (shoulder girdle and
  ribcage) and a share of ``waist`` (pelvis), and widens the skull slightly
  (``HEAD_FRAME_*_EXPONENT``). Never muscle.
- ``muscularity`` is muscle volume: it drives ``mass``. Never the skull: muscularity reaches
  the head only as soft tissue, through the base's physique head profiles (jaw, cheeks,
  neck), interpolated along ``mass``.

Mass is never an input: it is ``physique.resolve_physique`` of the body inputs, and nothing
here feeds it back into geometry. Development (regional emphasis and definition) is a
separate, optional input; the seven named configurations are exactly body inputs plus a
development preset (``configuration_definition``), so a configuration and a character
definition resolve the same way.

Head identity (``head_profile``: archetype + parameters) never changes with the physique,
and the physique never changes identity-only parameters (HEAD-IDENTITY-001). Identity
parameters that are placement rather than geometry (``eye_spacing``, ``brow_curvature``)
move the face marks; the rest shape the head through ``HEAD_FIELDS``.

Calibration constants are provisional until approved captures calibrate them. Pure Python.
"""

from __future__ import annotations

import math

from . import head_profile
from .baseline import REFERENCE_HEIGHT_M
from .parameters import BODY_BY_ID
from .physique import resolve_physique

SCHEMA = "riposte.variation"
PHYSIQUE_PARAMETERS = ("mass", "definition", "upper_body", "chest", "shoulders", "waist", "arms", "legs")
PARAMETER_RANGE = (-1.0, 1.0)
## Body input -> physique parameter: muscularity is mass; frame is skeletal breadth.
MUSCULARITY_PARAMETER = "mass"
FRAME_PARAMETERS = {"upper_body": 1.0, "waist": 0.4}
DEVELOPMENT = ("definition", "chest", "shoulders", "waist", "arms", "legs")
## Head allometry: head size ~ height ** 0.5 (adult head height ~21.5 cm at 1.60 m and
## ~24 cm at 2.00 m: ln(1.116) / ln(1.25) ~ 0.49). A broader skeleton is a larger skull:
## the whole head grows with frame ** HEAD_FRAME_SIZE_EXPONENT, its width a little more,
## its depth a little less (the 2026-10-31 review: an unchanged head on the strongman read
## too small). Muscle never sizes the skull. Provisional until calibrated on captures.
HEAD_STATURE_EXPONENT = 0.5
HEAD_FRAME_SIZE_EXPONENT = 0.25
HEAD_FRAME_WIDTH_EXPONENT = 0.2
HEAD_FRAME_DEPTH_EXPONENT = -0.1
## The head's scale relative to the body across the whole envelope stays within this band
## (the matrix reports any row outside it).
RELATIVE_HEAD_BOUNDS = (0.88, 1.12)
## Identity placement: chart units (head half-widths) of eye spacing and degrees of brow
## tilt per unit parameter.
EYE_SPACING_U = 0.07
BROW_CURVATURE_DEG = 10.0
## The neck follows neck_transition on the body too: radial scale of the neck per unit.
NECK_RADIAL_PER_UNIT = 0.08
## Reading only: body-mass index of the resolved body, reported for review, never a bound.
UNDERWEIGHT_BMI = 18.5

## Head morph fields, per unit of a head parameter, in the head's chart: u = x / half-width
## (|u| on the mirrored side), v = height fraction from the chin, d = depth fraction from
## the face's front (0) to the back of the skull (1). Each field is a displacement in metres
## of the reference head (before the head's size scale). `scale` fields move a coordinate
## away from a pivot by a fraction of its distance; `push` fields move by a fixed amount
## inside a Gaussian window. Windows: (centre, radius) per chart axis, or a band
## (lo, full, full_hi, hi) with cosine ramps.
HEAD_FIELDS = {
    "cranial_width": [{"kind": "scale", "axis": "x", "pivot": "centre", "amount": 0.06,
                       "v": (0.30, 0.50, 1.1, 1.2), "d": (0.15, 0.40, 1.1, 1.2)}],
    "cranial_depth": [{"kind": "scale", "axis": "y", "pivot": "middle", "amount": 0.06,
                       "v": (0.25, 0.45, 1.1, 1.2), "d": (0.45, 0.60, 1.1, 1.2)}],
    "cranial_height": [{"kind": "scale", "axis": "z", "pivot": "eye", "amount": 0.10,
                        "v": (0.55, 0.62, 1.1, 1.2)}],
    "face_length": [{"kind": "scale", "axis": "z", "pivot": "eye", "amount": 0.11,
                     "v": (-0.2, -0.1, 0.48, 0.55), "d": (-0.2, -0.1, 0.55, 0.75)}],
    "jaw_width": [{"kind": "scale", "axis": "x", "pivot": "centre", "amount": 0.14,
                   "v": (-0.2, -0.1, 0.28, 0.48)}],
    "cheek_fullness": [{"kind": "push", "move": (0.005, -0.002, 0.0), "u": (0.72, 0.18), "v": (0.29, 0.10),
                        "d": (-0.2, -0.1, 0.55, 0.75)}],
    "cheekbone_width": [{"kind": "push", "move": (0.0045, 0.0, 0.0), "u": (0.58, 0.14), "v": (0.43, 0.07),
                         "d": (-0.2, -0.1, 0.45, 0.65)}],
    "cheekbone_depth": [{"kind": "push", "move": (0.0, -0.0045, 0.0), "u": (0.58, 0.14), "v": (0.43, 0.07),
                         "d": (-0.2, -0.1, 0.45, 0.65)}],
    "chin_projection": [{"kind": "push", "move": (0.0, -0.004, -0.001), "u": (0.0, 0.25), "v": (0.07, 0.08),
                         "d": (-0.2, -0.1, 0.40, 0.60)}],
    "brow_strength": [{"kind": "push", "move": (0.0, -0.0025, 0.0), "u": (0.0, 0.45), "v": (0.655, 0.035),
                       "d": (-0.2, -0.1, 0.25, 0.40)}],
    "nose_projection": [{"kind": "push", "move": (0.0, -0.007, 0.0), "u": (0.0, 0.07), "v": (0.40, 0.10),
                         "d": (-0.2, -0.1, 0.15, 0.30)}],
    "neck_transition": [{"kind": "scale", "axis": "x", "pivot": "centre", "amount": 0.10,
                         "v": (-0.2, -0.1, 0.05, 0.20), "d": (0.30, 0.55, 1.1, 1.2)},
                        {"kind": "scale", "axis": "y", "pivot": "middle", "amount": 0.08,
                         "v": (-0.2, -0.1, 0.05, 0.20), "d": (0.45, 0.60, 1.1, 1.2)}],
}
PLACEMENT_PARAMETERS = ("eye_spacing", "brow_curvature")
## The eye line of the reference face (chart v of the orbit centre), the scale pivot of
## cranial_height and face_length.
EYE_V = 0.54

## The boundary matrix (height, frame, muscularity) and representative intermediates.
BOUNDARY_MATRIX = (
    ("default", 1.80, 1.00, 1.00),
    ("short_lean", 1.60, 0.85, 0.80),
    ("short_powerful", 1.60, 1.15, 1.25),
    ("tall_lean", 2.00, 0.85, 0.80),
    ("tall_powerful", 2.00, 1.15, 1.25),
    ("short_max_muscle", 1.60, 1.00, 1.25),
    ("tall_min_muscle", 2.00, 1.00, 0.80),
    ("mid_low", 1.70, 0.925, 0.90),
    ("mid_high", 1.90, 1.075, 1.125),
    ("mixed_broad_lean", 1.75, 1.15, 0.85),
    ("mixed_narrow_strong", 1.85, 0.85, 1.20),
)


def normalized(input_id, value):
    """A body input on its range as -1..0..1 (piecewise linear about Wolf's default)."""
    entry = BODY_BY_ID[input_id]
    if value >= entry.default:
        return (value - entry.default) / (entry.maximum - entry.default)
    return (value - entry.default) / (entry.default - entry.minimum)


def denormalized(input_id, n):
    entry = BODY_BY_ID[input_id]
    return entry.default + n * ((entry.maximum - entry.default) if n >= 0.0 else (entry.default - entry.minimum))


def physique_parameters(body, development=None):
    """The base's physique parameters for body inputs plus development. Raises on a value
    outside the parameter range (never clamped: the definition is wrong, not the range)."""
    development = dict(development or {})
    unknown = sorted(set(development) - set(DEVELOPMENT))
    if unknown:
        raise ValueError("unknown development parameters %s (known: %s)" % (unknown, list(DEVELOPMENT)))
    values = {key: 0.0 for key in PHYSIQUE_PARAMETERS}
    values[MUSCULARITY_PARAMETER] = normalized("muscularity", float(body["muscularity"]))
    frame = normalized("frame_build", float(body["frame_build"]))
    for key, share in FRAME_PARAMETERS.items():
        values[key] += share * frame
    for key, value in development.items():
        values[key] += float(value)
    out = {key: round(value, 9) for key, value in values.items()}
    bad = {k: v for k, v in out.items() if not PARAMETER_RANGE[0] - 1e-9 <= v <= PARAMETER_RANGE[1] + 1e-9}
    if bad:
        raise ValueError("physique parameters outside %s: %s" % (list(PARAMETER_RANGE), bad))
    return out


def configuration_definition(configurations, name, height_m=REFERENCE_HEIGHT_M):
    """A named configuration as body inputs plus development (the inverse of
    ``physique_parameters``): muscularity from mass, frame from upper_body, the rest
    development."""
    values = {key: 0.0 for key in PHYSIQUE_PARAMETERS}
    values.update(configurations[name])
    frame = values["upper_body"] / FRAME_PARAMETERS["upper_body"]
    body = {"height_m": height_m, "frame_build": round(denormalized("frame_build", frame), 9),
            "muscularity": round(denormalized("muscularity", values[MUSCULARITY_PARAMETER]), 9)}
    development = {key: round(values[key] - FRAME_PARAMETERS.get(key, 0.0) * frame, 9) for key in DEVELOPMENT}
    return {"body": body, "development": {k: v for k, v in development.items() if v}}


def head_physique_profile(profiles, configurations, mass):
    """The base's physique head profile at a mass parameter: the named profiles placed at
    their configurations' mass, linearly interpolated (exact at each configuration)."""
    stations = {}
    for name, values in configurations.items():
        stations.setdefault(round(float(values.get("mass", 0.0)), 9), name)
    ordered = sorted(stations.items())
    if mass <= ordered[0][0]:
        return dict(profiles[ordered[0][1]])
    if mass >= ordered[-1][0]:
        return dict(profiles[ordered[-1][1]])
    for (m0, a), (m1, b) in zip(ordered, ordered[1:]):
        if m0 <= mass <= m1:
            t = (mass - m0) / (m1 - m0)
            keys = set(profiles[a]) | set(profiles[b])
            return {k: round(profiles[a].get(k, 0.0) * (1 - t) + profiles[b].get(k, 0.0) * t, 9) for k in sorted(keys)}
    raise AssertionError("unreachable: mass %s within %s" % (mass, ordered))


def head_proportions(body):
    """Allometric head size: absolute and relative to the body's stature scale."""
    h = float(body["height_m"]) / REFERENCE_HEIGHT_M
    frame = float(body["frame_build"])
    size = h ** HEAD_STATURE_EXPONENT * frame ** HEAD_FRAME_SIZE_EXPONENT
    return {"stature_scale": round(h, 9), "size_scale": round(size, 9), "relative_scale": round(size / h, 9),
            "width_scale": round(frame ** HEAD_FRAME_WIDTH_EXPONENT, 9),
            "depth_scale": round(frame ** HEAD_FRAME_DEPTH_EXPONENT, 9)}


def resolve(definition, configuration_document):
    """Everything the builder needs for one definition:
    {"body", "physique", "parameters", "stature_scale", "head": {...}, "face": {...}}."""
    body = definition["body"]
    physique = resolve_physique(body)
    parameters = physique_parameters(body, definition.get("development"))
    identity = definition.get("head", {})
    problems = head_profile.identity_problems(identity)
    if problems:
        raise ValueError("; ".join(problems))
    profile = head_physique_profile(configuration_document["head_profiles"], configuration_document["configurations"],
                                    parameters["mass"])
    head = head_profile.resolve(identity, profile)
    return {
        "schema": SCHEMA,
        "body": {k: float(v) for k, v in body.items()},
        "physique": physique,
        "parameters": parameters,
        "stature_scale": round(float(body["height_m"]) / REFERENCE_HEIGHT_M, 9),
        "head": {"proportions": head_proportions(body), "physique_profile": profile, "parameters": head,
                 "neck_radial_scale": round(1.0 + NECK_RADIAL_PER_UNIT * head["neck_transition"], 9)},
        "face": {"eye_spacing_u": round(EYE_SPACING_U * head["eye_spacing"], 9),
                 "brow_tilt_deg": round(BROW_CURVATURE_DEG * head["brow_curvature"], 9)},
    }


def _band(x, band):
    lo, full, full_hi, hi = band
    if x <= lo or x >= hi:
        return 0.0
    if x < full:
        return 0.5 - 0.5 * math.cos(math.pi * (x - lo) / (full - lo))
    if x > full_hi:
        return 0.5 + 0.5 * math.cos(math.pi * (x - full_hi) / (hi - full_hi))
    return 1.0


def _gauss(x, window):
    centre, radius = window
    return math.exp(-0.5 * ((x - centre) / radius) ** 2)


def _window(field, chart):
    w = 1.0
    for axis in ("u", "v", "d"):
        if axis in field:
            spec = field[axis]
            w *= _band(chart[axis], spec) if len(spec) == 4 else _gauss(chart[axis], spec)
    return w


def chart(point, frame):
    """Chart coordinates of a head point: u (|x| / half-width), v (height fraction), d
    (depth fraction from the front)."""
    x, y, z = point
    return {"u": abs(x) / frame["half_width"], "v": (z - frame["low"]) / frame["height"],
            "d": (y - frame["front"]) / (frame["back"] - frame["front"])}


def head_displacement(point, frame, parameters):
    """The head morph at one point of the reference head (metres, before the size scale):
    the sum of HEAD_FIELDS weighted by the resolved head parameters. Mirrored in x."""
    c = chart(point, frame)
    x, y, z = point
    side = 1.0 if x >= 0.0 else -1.0
    pivots = {"centre": 0.0, "middle": 0.5 * (frame["front"] + frame["back"]),
              "eye": frame["low"] + EYE_V * frame["height"]}
    dx = dy = dz = 0.0
    for name, fields in HEAD_FIELDS.items():
        amount = parameters.get(name, 0.0)
        if not amount:
            continue
        for field in fields:
            w = _window(field, c) * amount
            if not w:
                continue
            if field["kind"] == "scale":
                coordinate = {"x": x, "y": y, "z": z}[field["axis"]]
                move = (coordinate - pivots[field["pivot"]]) * field["amount"] * w
                if field["axis"] == "x":
                    dx += move
                elif field["axis"] == "y":
                    dy += move
                else:
                    dz += move
            else:
                mx, my, mz = field["move"]
                dx += side * mx * w
                dy += my * w
                dz += mz * w
    return dx, dy, dz


def matrix_report():
    """The boundary matrix resolved: physical outputs, mass and the head's proportions."""
    rows = []
    for name, height, frame, muscle in BOUNDARY_MATRIX:
        body = {"height_m": height, "frame_build": frame, "muscularity": muscle}
        physique = resolve_physique(body)
        rows.append({"name": name, "body": body, "mass_kg": round(physique["mass_kg"], 2),
                     "bmi": round(physique["mass_kg"] / height ** 2, 2),
                     "parameters": physique_parameters(body), "head": head_proportions(body),
                     "hurt_radius_m": round(physique["hurt_radius_m"], 4), "push_radius_m": round(physique["push_radius_m"], 4)})
    masses = [r["mass_kg"] for r in rows]
    lo, hi = RELATIVE_HEAD_BOUNDS
    return {"rows": rows, "mass_range_kg": (min(masses), max(masses)),
            "below_underweight_bmi": [r["name"] for r in rows if r["bmi"] < UNDERWEIGHT_BMI],
            "head_outside_bounds": [r["name"] for r in rows if not lo <= r["head"]["relative_scale"] <= hi]}
