"""What each region preserves, what it flags, and at what thresholds.

There is no universal maximum angle. Each region has its own, and every
threshold names the control capture it was calibrated against. A finding is
evidence for a person to inspect in the view named, not a verdict.

Face exceptions are narrow: only faces flagged ``face_ridge`` (the centre
edge) and ``face_v`` (the curve where the upper and lower panels meet) are
exempt from the generic crease and outline-corner rules. The rest of the face
— its borders, the forehead-to-crown join, the cheeks — is scanned like
any other surface, so a crown hollow or a proud cheek border still reports.
"""

from __future__ import annotations

from .mesh_data import FLAG_FACE_RIDGE, FLAG_FACE_V

EXEMPT_FACE_FLAGS = (FLAG_FACE_RIDGE, FLAG_FACE_V)

# Every scanner threshold is one of: calibrated (checked against known-good and
# known-bad captures), provisional (a defensible starting value), or advisory
# (evidence only, never fails a candidate alone). F4 moves these as it
# calibrates; see docs/concepts/character-modeling.md.
STATUS_CALIBRATED = "calibrated"
STATUS_PROVISIONAL = "provisional"
STATUS_ADVISORY = "advisory"
THRESHOLD_STATUS = {
    "integrity": STATUS_CALIBRATED,          # holes/non-manifold/islands are unambiguous
    "symmetry": STATUS_CALIBRATED,           # mirrored-vertex distance, authored-symmetric mesh
    "outline_corner": STATUS_PROVISIONAL,
    "outline_notch": STATUS_PROVISIONAL,
    "crease_cluster": STATUS_PROVISIONAL,
    "section_shelf": STATUS_PROVISIONAL,
    "section_dip": STATUS_PROVISIONAL,
    "section_extra_belly": STATUS_PROVISIONAL,
    "section_asymmetry": STATUS_CALIBRATED,
    "offset_dent": STATUS_ADVISORY,          # smoothed-copy probe; corroboration required
}


def status(kind):
    return THRESHOLD_STATUS.get(kind, STATUS_PROVISIONAL)


def _policy(preserve, flag, dihedral_deg, convex_deg=40.0, concave_deg=40.0):
    return {
        "preserve": preserve,
        "flag": flag,
        "dihedral_deg": dihedral_deg,
        "outline_convex_deg": convex_deg,
        "outline_concave_deg": concave_deg,
    }


POLICIES = {
    "head_face": _policy("Centre ridge and the intended face planes", "Horizontal cheek crease, proud border, sunk border", 14.0),
    "head_crown": _policy("A round crown continuous with the face top", "Crown ridge, forehead-to-crown hollow", 10.0),
    "head_jaw": _policy("A defined jaw and chin on the nose line", "Proud jaw corner, faceted jaw underside", 14.0),
    "neck": _policy("One slope from the skull base into the trapezius", "Neck peg, bulge behind the skull", 12.0),
    "chest": _policy("Broad ribcage and smooth V-taper", "Chest shelf, ring banding, local inward dip", 10.0),
    "abdomen": _policy("A continuous taper to the pelvis", "Belly shelf, waist pinch", 10.0),
    "back_upper": _policy("Full scapular region and natural spine", "Sunken scapulae, abrupt ridge, detached deltoids", 10.0),
    "back_lower": _policy("Lats carrying breadth to the waist", "Banding, lumbar trench", 10.0),
    "shoulder": _policy("Deltoid flowing over the joint into the arm", "Shoulder-arm nub, hard ledge", 12.0),
    "upper_arm": _policy("Muscular taper", "Isolated protrusions, sudden width changes", 12.0),
    "forearm": _policy("Upper-forearm belly tapering to the wrist", "Notch at the elbow, sudden width changes", 12.0),
    "hand": _policy("Blockout hand mass", "Flat end cap", 25.0, convex_deg=60.0),
    "pelvis": _policy("Continuous waist-to-hip-to-thigh flow", "Hip steps, tunic-like ledges", 10.0),
    "glute": _policy("Continuous seat into the hamstring", "Seat shelf", 10.0),
    "thigh": _policy("Quad and hamstring volume meeting the hip", "Inner-thigh pinching, hip ledge", 12.0),
    "calf": _policy("Rear-biased calf belly into the ankle", "Abrupt circumference change", 12.0),
    "foot": _policy("Blockout foot mass", "Detached-looking ankle", 25.0, convex_deg=60.0),
}

# Severity: a cluster whose peak reaches HIGH_FACTOR x the region threshold,
# or whose length passes HIGH_LENGTH_M, is high.
HIGH_FACTOR = 2.0
HIGH_LENGTH_M = 0.08
LOW_LENGTH_M = 0.012

# Cross-section series. ``max_interior_maxima`` / ``max_interior_minima`` are
# the bellies and waists the intended profile has; anything more is a bump
# or a dip. ``prominence_m`` ignores sampling noise.
SECTION_SERIES = {
    "torso_width": {"region": "chest", "max_interior_maxima": 1, "max_interior_minima": 1, "prominence_m": 0.002},
    "torso_depth": {"region": "back_upper", "max_interior_maxima": 2, "max_interior_minima": 1, "prominence_m": 0.002},
    "upper_arm": {"region": "upper_arm", "max_interior_maxima": 1, "max_interior_minima": 0, "prominence_m": 0.0015},
    "forearm": {"region": "forearm", "max_interior_maxima": 1, "max_interior_minima": 0, "prominence_m": 0.0015},
    "thigh": {"region": "thigh", "max_interior_maxima": 1, "max_interior_minima": 0, "prominence_m": 0.0015},
    "calf": {"region": "calf", "max_interior_maxima": 1, "max_interior_minima": 0, "prominence_m": 0.0015},
}
# A shelf: a curvature spike in a section profile, in metres per station
# squared, and against the series' own median curvature.
SHELF_ABS_M = 0.0025
SHELF_MEDIAN_FACTOR = 5.0

# Outline corner detection.
OUTLINE_STEP_M = 0.004
OUTLINE_WINDOW = 3
# Symmetry: worst mirrored-vertex distance before it is a finding.
MIRROR_TOLERANCE_M = 0.002
# Experimental offset probe (Laplacian reference, local relief).
# The smoothing reaches about OFFSET_RADIUS_M whatever the mesh resolution.
OFFSET_RADIUS_M = 0.025
OFFSET_MIN_ITERATIONS = 8
OFFSET_MAX_ITERATIONS = 120
OFFSET_LAMBDA = 0.5
OFFSET_DENT_M = 0.0015
OFFSET_MIN_AREA_M2 = 0.00005
CORROBORATION_RADIUS_M = 0.03
# Findings within this distance of a control finding of the same kind and
# region are the existing defect, not a new one.
MATCH_RADIUS_M = 0.025


def policy(region):
    return POLICIES[region]
