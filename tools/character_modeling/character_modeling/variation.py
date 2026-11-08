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
from .interpolation import linear_anchors, monotone
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
## Muscularity's regional response beyond the base's `mass` key (CHARACTER-PHYSIQUE-ART-001).
## The key adds chest, shoulders and arms but little back, glute, hamstring or thigh depth,
## so the strongman read top-heavy and barrel-chested in profile; above the reference
## these broad shifts (left side, metres at full muscularity, mirrored; the base's HERO shift
## form) add the upper back, traps, lats, deltoids, quadriceps, hamstrings, a broad glute
## and the calves in proportion to the positive `mass` parameter. Below it the key strips
## muscle toward frail; LEAN_FLOOR keeps a conditioned fighter's shoulders, back and legs in
## proportion to the negative parameter. Candidates until a reviewed board approves them.
MASS_RESPONSE = {
    "upper_back_depth": ((0.09, 0.14, 1.31), 0.12, (0.1, 1.0, 0.15), 0.016),
    "trapezius_mass": ((0.10, 0.07, 1.45), 0.07, (0.2, 0.5, 1.0), 0.014),
    "lat_flare": ((0.17, 0.06, 1.22), 0.09, (1.0, 0.3, 0.0), 0.010),
    "deltoid_mass": ((0.22, 0.0, 1.38), 0.07, (1.0, 0.0, 0.2), 0.010),
    "quad_front": ((0.12, -0.075, 0.64), 0.10, (0.0, -1.0, 0.0), 0.016),
    "vastus_lateral": ((0.175, -0.01, 0.60), 0.08, (1.0, 0.0, 0.0), 0.008),
    "hamstring_depth": ((0.115, 0.10, 0.66), 0.10, (0.0, 1.0, 0.0), 0.012),
    "glute_broad": ((0.09, 0.13, 0.83), 0.11, (0.1, 1.0, -0.2), 0.008),
    "calf_back": ((0.12, 0.10, 0.30), 0.07, (0.0, 1.0, 0.0), 0.006),
}
LEAN_FLOOR = {
    "deltoid_mass": ((0.22, 0.0, 1.38), 0.07, (1.0, 0.0, 0.2), 0.008),
    "upper_back_depth": ((0.09, 0.14, 1.31), 0.12, (0.1, 1.0, 0.15), 0.008),
    "quad_front": ((0.12, -0.075, 0.64), 0.10, (0.0, -1.0, 0.0), 0.008),
    "calf_back": ((0.12, 0.10, 0.30), 0.07, (0.0, 1.0, 0.0), 0.004),
}


## Mass changes limb girth, never length (CHARACTER-MORPHOLOGY-001): fleshy sites (thigh,
## calf, upper arm, forearm) change far more than bony ones (knee, ankle, elbow, wrist),
## which stay nearly fixed, as measured girths do (Nevill et al. 2004: limb muscle girths
## grow faster than geometric similarity, wrists, ankles and the head slower). The lean
## anchor's factor of each limb's cross-section about its own centre, by position: legs by
## h = z / stature from the sole to the gluteal fold (1.0 there: the glutes are the
## silhouette's), arms by share from the armpit to the fingertip. Measured on the
## protected sweep (2026-11-01) the lean thigh was 0.94 of the reference's; an ectomorph's
## is near 0.8. Between lean and reference the factor is linear in mass; at and above the
## reference it is 1 (the strongman's girths come from the muscularity keys).
GIRTH_LEAN = {
    "leg": ((0.0, 1.0), (0.04, 1.0), (0.07, 0.985), (0.10, 0.95), (0.14, 0.90), (0.20, 0.89), (0.25, 0.93),
            (0.285, 0.975), (0.31, 0.95), (0.34, 0.87), (0.40, 0.84), (0.44, 0.88), (0.47, 1.0)),
    "arm": ((0.0, 1.0), (0.06, 0.97), (0.12, 0.92), (0.22, 0.90), (0.34, 0.94), (0.42, 0.98), (0.48, 0.95),
            (0.55, 0.93), (0.66, 0.97), (0.74, 1.0), (1.0, 1.0)),
}


## The strongman anchor's distal fullness (girth study GIRTH_FULL): measured on the sweep
## (2026-11-01) the strongman's forearm and calf grew less over the reference (1.10, 1.11)
## than his thigh and upper arm (1.14, 1.16). The calf fills its upper-to-middle belly and
## the forearm its proximal belly below the elbow; the knee, ankle, elbow and wrist hold.
GIRTH_STRONG = {
    "leg": ((0.0, 1.0), (0.07, 1.0), (0.12, 1.02), (0.17, 1.06), (0.22, 1.06), (0.26, 1.03), (0.285, 1.0), (1.0, 1.0)),
    "arm": ((0.0, 1.0), (0.40, 1.0), (0.44, 1.02), (0.50, 1.07), (0.58, 1.05), (0.66, 1.02), (0.74, 1.0), (1.0, 1.0)),
}
GIRTH_FULL = "full"


def _polyline(points, t):
    if t <= points[0][0]:
        return points[0][1]
    if t >= points[-1][0]:
        return points[-1][1]
    return next(v0 + (v1 - v0) * (t - t0) / (t1 - t0) for (t0, v0), (t1, v1) in zip(points, points[1:]) if t <= t1)


def girth_factor(mass, limb, t, strong=False):
    """The cross-section factor of `limb` ("leg" or "arm") at position t for muscularity
    `mass`: GIRTH_LEAN at the lean anchor, 1 at the reference, linear between; above the
    reference 1, or with `strong` toward GIRTH_STRONG at the strongman. Held past the
    anchors (no extrapolation)."""
    return linear_anchors({-1.0: _polyline(GIRTH_LEAN[limb], t), 0.0: 1.0,
                           1.0: _polyline(GIRTH_STRONG[limb], t) if strong else 1.0}, mass)


def physique_response(mass):
    """The regional shifts at a `mass` parameter: (centre, radius, direction, amount), each
    amount LEAN_FLOOR's at the lean anchor, none at the reference, MASS_RESPONSE's at the
    strongman, linear between (the keys' weights)."""
    out = {}
    for name in sorted(set(MASS_RESPONSE) | set(LEAN_FLOOR)):
        c, r, d, _a = MASS_RESPONSE.get(name) or LEAN_FLOOR[name]
        amount = linear_anchors({-1.0: LEAN_FLOOR.get(name, (0, 0, 0, 0.0))[3], 0.0: 0.0,
                                 1.0: MASS_RESPONSE.get(name, (0, 0, 0, 0.0))[3]}, mass)
        out[name] = (c, r, d, amount)
    return out


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
    ## Semantic lower-face stations: the mandibular corner (out and a little forward, below
    ## and ahead of the ear: a lean neck lies against the jaw's side behind it, so a corner
    ## pushed only outward, or down, crossed the lean 1.80-1.90 m necks) and the chin's
    ## corners (out and down, so the chin's lower edge is broad and flatter without growing
    ## longer at the centre).
    "jaw_angle": [{"kind": "push", "move": (0.0020, -0.0015, 0.0), "u": (0.80, 0.15), "v": (0.15, 0.06),
                   "d": (0.25, 0.38, 0.58, 0.72)}],
    "chin_corner": [{"kind": "push", "move": (0.0015, 0.0, -0.001), "u": (0.30, 0.12), "v": (0.04, 0.05),
                     "d": (-0.2, -0.1, 0.25, 0.40)}],
    ## The lower face's underside and contour (anime_jaw): the submental region behind the
    ## chin pad lifted toward the throat junction (the underside sagged ~10 mm from the chin
    ## back to the neck, a second soft mass), between and behind the face mask's lower
    ## boundary (lifting the boundary raised the mask off its lowest chart row); a broad smooth widening between the chin's
    ## corners (one compact chin edge, not two nodes); a restrained plane break where the
    ## cheek turns into the jaw.
    "submental_lift": [{"kind": "push", "move": (0.0, 0.0, 0.004), "u": (0.0, 0.30), "v": (-0.2, -0.1, 0.05, 0.13),
                        "d": (0.18, 0.35, 0.60, 0.78)}],
    ## The jaw's lower border rising from the chin toward the mandibular corner (it ran
    ## downhill, the rest of the chin-to-neck sag in profile), outside the neck's seam.
    "mandible_border": [{"kind": "push", "move": (0.0, 0.0, 0.004), "u": (0.68, 0.22), "v": (-0.2, -0.1, 0.06, 0.15),
                         "d": (0.18, 0.38, 0.60, 0.76)}],
    ## The ramus: behind the mandibular corner the jaw's lower side edge rises toward the ear
    ## lobe, so the jaw ends at an angle below the ear and the neck emerges behind it (it ran
    ## level under the whole ear, merging into the neck); the lower band only, short of the
    ## nape. Starting further back hid the turn behind the neck.
    "ramus_recess": [{"kind": "push", "move": (0.0, 0.0, 0.004), "u": (0.80, 0.25), "v": (-0.2, -0.1, 0.10, 0.22),
                      "d": (0.48, 0.60, 0.72, 0.84)}],
    ## The submental line: the underside rising from the chin's lowest point back to the
    ## cervicomental junction (measured on the round-4 head it fell 15 mm from the chin to
    ## a lowest point just ahead of the neck: a pouch, the face mask's own lower panels from
    ## the chin back to its boundary under the chin, 0.21 of the depth, and the skull behind).
    ## Rises with depth from behind the chin pad (0.10) to the junction, then fades; its
    ## height band ramps over more than pi/2 of the lift (0.14 of the head) so the surface
    ## never folds.
    "submental_profile": [{"kind": "push", "move": (0.0, 0.0, 0.004), "u": (0.0, 0.35), "v": (-0.2, -0.1, 0.04, 0.18),
                           "d": (0.10, 0.30, 0.40, 0.55)}],
    ## The jawline as one long, gently rising line from the chin's corner back toward the ear
    ## (the border lift and the turn behind the corner summed into a bend and a hump).
    "jaw_line": [{"kind": "push", "move": (0.0, 0.0, 0.004), "u": (0.72, 0.28), "v": (-0.2, -0.1, 0.10, 0.22),
                  "d": (0.18, 0.80, 0.86, 0.96)}],
    ## The profile corner where the chin's front turns under (two planar mask panels meeting):
    ## eased back and up, so the chin reads rounded in profile; its projection barely moves.
    "chin_round": [{"kind": "push", "move": (0.0, 0.0025, 0.0015), "u": (0.0, 0.40), "v": (0.04, 0.025),
                    "d": (0.10, 0.05)}],
    "chin_breadth": [{"kind": "push", "move": (0.001, 0.0, -0.0005), "u": (0.22, 0.20), "v": (0.05, 0.06),
                      "d": (-0.2, -0.1, 0.25, 0.40)}],
    "cheek_jaw_break": [{"kind": "push", "move": (-0.0008, 0.0, 0.0), "u": (0.64, 0.10), "v": (0.24, 0.04),
                         "d": (-0.2, -0.1, 0.40, 0.60)}],
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
## Foundation design studies of the head shape (candidates, never an identity): offsets of
## the head parameters every character carries on top of its identity, so one study is
## reviewed on every head. `anime_head` (2026-11-01): the head read as a soft mannequin.
## A heroic anime male head carries a tall, broad cranium over a shorter face, planar
## cheeks under defined cheekbones, and a jaw that tapers to a firm, projecting chin.
HEAD_STUDY = {
    "anime_head": {"cranial_height": 1.0, "cranial_width": 0.4, "face_length": -0.7, "jaw_width": -0.35,
                   "chin_projection": 1.0, "cheek_fullness": -0.8, "cheekbone_width": 0.5},
    ## `anime_planes` (on anime_head): the lower face more deliberately planar and adult:
    ## flatter cheeks under the cheekbone, a stronger jaw (less of a V), a firmer chin. Only
    ## fields whose windows lie below the eye panel, so the eyes, brows and cranium keep
    ## their place.
    "anime_planes": {"cheek_fullness": -0.4, "jaw_width": 0.3, "chin_projection": 0.3},
    ## `heroic_cranium` (2026-11-05, on anime_planes): the head read alien. Measured on the
    ## reference, the cranium was 0.80 of the head's height wide and widest at the temples,
    ## a bulb over a 0.71-as-wide jaw; the vertical split (1:1 about the eye) and the midface
    ## projection were sound. A proportionate rounded cranium on the heroic face (All Might's
    ## masculine structure, Fire Emblem's construction): the skull behind the facial mask
    ## narrowed, slightly lower and less deep at the back, the jaw body broader, cheek volume
    ## restored under the cheekbones (never skeletal), a stronger brow region (0.4 uncovered an
    ## iris at half blink on the 1.60 m strongman head). Relationships, not sharper planes;
    ## the eyes, brows and nose stay on their mask anchors.
    "heroic_cranium": {"cranial_width": -1.4, "cranial_depth": -0.4, "cranial_height": -0.3,
                       "jaw_width": 0.25, "cheek_fullness": 0.5, "brow_strength": 0.25},
    ## `heroic_jaw` (2026-11-05, on heroic_cranium; the cranium, profile and upper face are the
    ## protected baseline): the lower face read as the bottom of a continuous oval. A softly
    ## angular, broad-based pentagon instead: a clearer mandibular corner (2 mm out, 1.5 mm
    ## forward) and a broader, flatter chin edge (corners 1.5 mm out, 1 mm down), inside a
    ## 1-3 mm budget; the chin's height and projection at the centre, the cheeks and the
    ## forehead, nose and cranium are untouched.
    "heroic_jaw": {"jaw_angle": 1.0, "chin_corner": 1.0},
    ## `anime_jaw` (2026-11-06, on heroic_jaw; the checkpoint is heroic_jaw without it): the
    ## lower face still read as a rounded oval with a double chin. The underside sagged
    ## ~10 mm from the chin back to the neck (side silhouette): the submental region lifted
    ## (up to 10.4 mm, beyond the 1-3 mm contour budget because the measured sag is ~10 mm)
    ## toward a deliberate jaw-to-neck junction (the chin pad and the jaw's side edges stay);
    ## the chin's edge one broad compact form; the mandibular corner at the 3 mm budget (a
    ## lean neck lies against the jaw's side, so it cannot grow further here); a restrained
    ## cheek-to-jaw plane break. Cranium, forehead, temples, nose, ears
    ## and the face are untouched.
    "anime_jaw": {"submental_lift": 2.6, "mandible_border": 1.5, "jaw_angle": 0.2, "chin_breadth": 1.0, "cheek_jaw_break": 1.0},
    ## `jaw_angle_turn` (2026-11-06, on anime_jaw, the round-3 checkpoint): measured in
    ## profile, the jaw's lower side edge ran level 20-30 mm above the chin from a fifth of
    ## the head's depth to past the ear, so the jaw never turned at an angle and merged into
    ## the neck. Behind the corner the edge now rises toward the ear lobe (up to 10 mm; 14 mm
    ## exposed the 2.00 m lean neck across a jaw edge): a readable mandibular angle, the neck
    ## emerging behind it. Chin, jaw body, cheeks, cranium, nape and face untouched (1.5 mm
    ## less cheek also moved a fitted brow expression key 0.78 mm on one side, so the cheek
    ## stays).
    "jaw_angle_turn": {"ramus_recess": 2.5},
    ## `submental_fix` (2026-11-06, every build): the chin is the underside's lowest point,
    ## the line rises ~12 mm back to the neck junction (cervicomental angle), no pouch.
    "submental_fix": {"submental_profile": 3.0},
    ## `smooth_jaw` (2026-11-06, every build; replaces anime_jaw + jaw_angle_turn in the design
    ## anchors, which stay as they were for the checkpoints): anime_jaw's terms without its
    ## border lift, and one straight rising jawline into the back of the head instead of the
    ## border lift plus the turn; the chin's profile corner rounded.
    "smooth_jaw": {"submental_lift": 2.6, "jaw_angle": 0.2, "chin_breadth": 1.0, "cheek_jaw_break": 1.0,
                   "jaw_line": 3.5, "chin_round": 1.0},
    ## `contour_jaw` (2026-11-06, with the mask's `lower_contour`; replaces smooth_jaw in the
    ## design anchors): the mask now rounds and splits the chin's turn itself, so the field
    ## that faked it (chin_round, a push at the corner) is dropped: on the rounded chin it
    ## dented the turn into a step.
    "contour_jaw": {"submental_lift": 2.6, "jaw_angle": 0.2, "chin_breadth": 1.0, "cheek_jaw_break": 1.0,
                    "jaw_line": 3.5},
    ## Physique design anchors (`head_design`, three-physique system, 2026-11-06): the round-4
    ## face is the strongman anchor (All Might: broad jaw, cheekbone architecture, firm chin);
    ## these derive the others from it. `reference_face` (Goku/Vegeta: balanced, athletic,
    ## a clearly angular medium jaw, defined cheek planes, compact chin, less facial bulk);
    ## `lean_face` (Spike Spiegel: narrower and longer, lean planar cheeks, a narrow angular
    ## jaw, slim compact chin; athletic, never gaunt or hollow).
    "reference_face": {"jaw_width": -0.35, "cheek_fullness": -0.5, "cheekbone_depth": 0.3, "chin_breadth": -0.4},
    "lean_face": {"jaw_width": -0.6, "cheek_fullness": -0.8, "cheekbone_depth": 0.5, "face_length": 0.25,
                  "cranial_width": -0.3, "chin_breadth": -0.4},
    ## `chin_end` (2026-11-06, with lean_face / reference_face in the anchors): their chin
    ## narrowing (chin_breadth -0.4) read as a pointed (lean) or pinched (reference) chin
    ## once the jaw narrowed into it; the chin end is short and broad on every build, the
    ## jaw still narrower.
    "chin_end": {"chin_breadth": 0.4},
    ## `strongman_face`: the heavy physique profile adds cheek fullness (+0.45) on top of the
    ## anchor face; the strongman's extra size is jaw, neck and traps, never facial fat, so the
    ## cheeks return to the anchor face's.
    "strongman_face": {"cheek_fullness": -0.45},
}
## The physique design coordinate: frame and muscularity, each normalized on its range,
## averaged (lean -1, reference 0, strongman +1; a narrow strong or broad lean body sits
## between). Height never enters it: every height carries every build.
DESIGN_ANCHORS = ("lean", "reference", "strongman")


def design_coordinate(body):
    """The build coordinate (-1..1) of body inputs: the mean of normalized frame and
    muscularity."""
    return round(0.5 * (normalized("frame_build", float(body["frame_build"])) + normalized("muscularity", float(body["muscularity"]))), 9)


def designed_study(design, body):
    """The head studies of `design` ({anchor: {study: value}}) at a body: each study's value
    piecewise linear between the lean, reference and strongman anchors (the keys' weights,
    held past the ends), so the three faces interpolate with no overshoot."""
    if not design:
        return {}
    b = design_coordinate(body)
    names = sorted({s for anchor in DESIGN_ANCHORS for s in design.get(anchor, {})})
    return {s: round(linear_anchors({-1.0: design.get("lean", {}).get(s, 0.0), 0.0: design.get("reference", {}).get(s, 0.0),
                                      1.0: design.get("strongman", {}).get(s, 0.0)}, b), 9) for s in names}


def studied_head(parameters, study=None):
    """The resolved head `parameters` with the head `study` ({name: value}) added."""
    out = dict(parameters)
    for key, value in (study or {}).items():
        if key not in HEAD_STUDY:
            raise ValueError("variation: unknown head study %s (known: %s)" % (key, ", ".join(sorted(HEAD_STUDY))))
        for name, amount in HEAD_STUDY[key].items():
            out[name] = out.get(name, 0.0) + amount * value
    return out


## The face features follow the resolved head (CHARACTER-MORPHOLOGY-001, `face_response`).
## The marks are fractions of the head's chart, so they already scale with it; what the
## chart does not carry: the features' depths and offsets are metres at the reference
## stature, and the root scales the whole character by stature, so without a response they
## grow with height while the head grows only with its allometric size (12 % too deep at
## 2.00 m). With it they follow the head's size (`relative_scale`). Eyes vary less than
## heads (an adult eye is nearly one size), so the eye's share of the head shrinks a little
## on a larger head: its size follows the head's size to EYE_SIZE_EXPONENT. Brow mass rises
## with muscularity (heavier soft tissue over the ridge), linear between the anchors like
## the keys. The reference resolves to exactly 1 everywhere, so its face is the locked one.
EYE_SIZE_EXPONENT = -0.35
BROW_THICKNESS = {-1.0: 0.94, 0.0: 1.0, 1.0: 1.12}
BROW_PROJECTION = {-1.0: 0.95, 0.0: 1.0, 1.0: 1.15}
## Mark fields that are metres of anatomy (scaled with the head).
FACE_METRE_FIELDS = ("depth_m", "proud_m", "settle_m")


def face_response(resolved):
    """{eye_scale, brow_thickness, brow_projection, depth_scale} for a resolved
    configuration (1 for each at the reference)."""
    proportions = resolved["head"]["proportions"]
    mass = resolved["parameters"]["mass"]
    return {"eye_scale": round(proportions["size_scale"] ** EYE_SIZE_EXPONENT, 9),
            "brow_thickness": round(linear_anchors(BROW_THICKNESS, mass), 9),
            "brow_projection": round(linear_anchors(BROW_PROJECTION, mass), 9),
            "depth_scale": round(proportions["relative_scale"], 9)}


def responded_marks(marks, response):
    """`marks` with the face response applied (a copy): the eye's width and height by
    `eye_scale` (its centre and spacing stay), the brow's thickness by `brow_thickness`,
    its depth and projection by `brow_projection`, every metre field by `depth_scale`."""
    import copy
    out = copy.deepcopy(marks)
    for name, mark in out.items():
        for key in FACE_METRE_FIELDS:
            if key in mark:
                mark[key] = mark[key] * response["depth_scale"]
        if name == "Eye":
            ## The eye's layer depths are its stacking order (fractions of a millimetre that
            ## keep white, iris, pupil, mask and line apart), not anatomy: they never scale.
            mark["width"] *= response["eye_scale"]
            mark["height"] *= response["eye_scale"]
        if name == "Brow":
            mark["height"] *= response["brow_thickness"]
            for key in ("depth_m", "proud_m"):
                mark[key] *= response["brow_projection"]
    return out


PLACEMENT_PARAMETERS = ("eye_spacing", "brow_curvature")
## The eye line of the reference face (chart v of the orbit centre), the scale pivot of
## cranial_height and face_length.
EYE_V = 0.54

## The boundary matrix (height, frame, muscularity): all eight corners, and representative
## intermediates.
BOUNDARY_MATRIX = (
    ("default", 1.80, 1.00, 1.00),
    ("short_lean", 1.60, 0.85, 0.80),
    ("short_powerful", 1.60, 1.15, 1.25),
    ("tall_lean", 2.00, 0.85, 0.80),
    ("tall_powerful", 2.00, 1.15, 1.25),
    ("short_narrow_strong", 1.60, 0.85, 1.25),
    ("short_broad_lean", 1.60, 1.15, 0.80),
    ("tall_narrow_strong", 2.00, 0.85, 1.25),
    ("tall_broad_lean", 2.00, 1.15, 0.80),
    ("short_max_muscle", 1.60, 1.00, 1.25),
    ("tall_min_muscle", 2.00, 1.00, 0.80),
    ("mid_low", 1.70, 0.925, 0.90),
    ("mid_high", 1.90, 1.075, 1.125),
    ("mixed_broad_lean", 1.75, 1.15, 0.85),
    ("mixed_narrow_strong", 1.85, 0.85, 1.20),
)


## The height sweep: every height anchor with the three physique archetypes (the athletic
## lean end, the Olympic-weightlifter reference, the strongman end), so every height
## reaches the whole build range.
SWEEP_HEIGHTS_M = (1.60, 1.70, 1.80, 1.90, 2.00)
ARCHETYPES = (("lean", 0.85, 0.80), ("reference", 1.00, 1.00), ("strongman", 1.15, 1.25))


def sweep():
    """(name, height, frame, muscularity) for every sweep height and archetype."""
    return tuple(("%s_%03d" % (name, round(h * 100)), h, f, m) for h in SWEEP_HEIGHTS_M for name, f, m in ARCHETYPES)


def fingerprint(resolved):
    """The resolved configuration's fingerprint: what every mapping result built from it
    records, so a change of physical inputs invalidates it."""
    import hashlib
    import json
    keys = ("body", "parameters", "head", "face")
    return hashlib.sha256(json.dumps({k: resolved[k] for k in keys}, sort_keys=True).encode()).hexdigest()[:16]


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
    their configurations' mass, each head parameter a monotone cubic through those stations
    (exact at each configuration, continuous in slope, no overshoot between two stations),
    held past the ends. A parameter a station leaves out is 0 there."""
    stations = {}
    for name, values in configurations.items():
        stations.setdefault(round(float(values.get("mass", 0.0)), 9), name)
    ordered = sorted(stations.items())
    if mass <= ordered[0][0]:
        return dict(profiles[ordered[0][1]])
    if mass >= ordered[-1][0]:
        return dict(profiles[ordered[-1][1]])
    ## The parameters the two bracketing stations name (the profile's keys stay what they
    ## were under linear interpolation, so a resolved configuration's fingerprint does too).
    a, b = next((a, b) for (m0, a), (m1, b) in zip(ordered, ordered[1:]) if m0 <= mass <= m1)
    keys = sorted(set(profiles[a]) | set(profiles[b]))
    return {k: round(monotone([(m, profiles[name].get(k, 0.0)) for m, name in ordered], mass), 9) for k in keys}


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
