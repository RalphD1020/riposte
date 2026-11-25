"""ART-ANATOMY-001: the engine-neutral half of a body's anatomical collision profile
(`<body>.anatomy.json`): simplified volumes fitted to the production body mesh (dominant-weight
vertices per bone, in bone-local rest coordinates, which Blender and Godot share for WolfRig - the
G2 audit), the collision-pair table, the penetration bands and the provisional joint limits.
Fitted by `tools/blender/inspect/anatomical_bounds.py` in Blender; evaluated there and by
`game/tools/anatomical_clearance.gd` in Godot.

Presentation and art validation only: the profile never moves the sword, detaches a palm, stretches
a bone or touches combat physics. Pose fitting treats grip attachment and hard anatomical validity
as feasibility, never as a soft cost. No bpy here: the geometry, the pair policy and the bands are
self-checked by the game lint.

Volumes are swept spheres, so every pair reduces to one shortest distance between core primitives:
    capsule  - a segment (a, b) swept by `radius`                    (limbs, hands, neck, head)
    prism    - a convex polygon (x, z) extruded over [y0, y1] in its bone's frame (the torso sections:
               the outline fitted to the section's vertices, so an oval ribcage or a lat flare is
               followed and no box corner stands proud of the body)
    clearance = distance(core_A, core_B) - (radius_A + radius_B)   (< 0 overlaps; mm = -1000 x).
Segment-to-prism distance is convex along the segment, so a bounded ternary search on the segment
parameter is exact to tolerance. Prism-prism pairs do not occur (the trunk is one connected body)."""

import hashlib
import json
import math

SCHEMA = "riposte.art_anatomy_profile"
VERSION = 2
SUFFIX = ".anatomy.json"

## ---------------------------------------------------------------- ArtAnatomyProfile: chains and joints
## The functional chains of WolfRigNeutral as it exists (21 bones; no twist, finger or extra girdle
## bones): the profile describes how these cooperate, it never adds a bone.
CHAINS = {
    "spine": ("Hips", "Spine", "Chest"),
    "look": ("Chest", "Neck", "Head"),
    "arm_R": ("Chest", "Shoulder.R", "UpperArm.R", "Forearm.R", "Hand.R"),
    "arm_L": ("Chest", "Shoulder.L", "UpperArm.L", "Forearm.L", "Hand.L"),
    "leg_R": ("Hips", "UpperLeg.R", "LowerLeg.R", "Foot.R"),
    "leg_L": ("Hips", "UpperLeg.L", "LowerLeg.L", "Foot.L"),
}
## What each anatomical function is carried by on this rig (the rig inventory the guide asks for).
RIG_CAPABILITIES = {
    "clavicle": "Shoulder.R / Shoulder.L (elevation driven by ClavicleResponse; no independent protraction control yet)",
    "humerus_swing_twist": "UpperArm.X rotation",
    "elbow_hinge": "Forearm.X rotation about the calibrated hinge",
    "forearm_pronation": "Forearm.X roll about its own long axis (no twist helper bones; skin validated by the mesh gate)",
    "wrist": "Hand.X swing (flexion / deviation)",
    "fingers": "none: a fixed sword-holding hand; the palm is the weapon attachment",
    "chest_torso": "Spine / Chest yaw (body follow + the authored cut torso)",
}
## Functional coordination the pose authoring evaluates together (not a simulator).
COORDINATION = {
    "two_hand_grip": {"chains": ("arm_R", "arm_L", "spine"), "constraint": "both palms on one rigid sword at fixed stations"},
    "upper_body_reach": {"chains": ("spine", "arm_R", "arm_L"), "order": "chest, clavicle, humerus, elbow hinge, forearm roll, wrist"},
    "looking": {"chains": ("look",)},
    "locomotion": {"chains": ("spine", "leg_R", "leg_L"), "constraint": "the physics root owns displacement and facing"},
}
## Joint constraints in calibrated anatomical frames (degrees). PROVISIONAL engineering bounds -
## `preferred` is the comfortable envelope pose fitting favours, `hard` is invalid; to be recalibrated
## on the approved HEMA reference poses (longpoint, both high guards, low follow-through) once the
## person approves them. Never world, camera or sword-side axes.
JOINT_CONSTRAINTS = {
    "elbow": {"flexion": {"preferred": [15.0, 140.0], "hard": [-5.0, 150.0]},
              "bend_plane_error": {"preferred": 10.0, "hard": 25.0}},
    "forearm": {"roll": {"preferred": [-60.0, 60.0], "hard": [-90.0, 90.0]}},
    "wrist": {"flexion": {"preferred": [-50.0, 50.0], "hard": [-75.0, 80.0]},
              "deviation": {"preferred": [-20.0, 20.0], "hard": [-35.0, 35.0]},
              "residual_twist": {"preferred": 10.0, "hard": 30.0}},
    "shoulder": {"twist": {"preferred": [-60.0, 60.0], "hard": [-100.0, 100.0]}},
}
## Motion quality (provisional): measured over real sim time at the sword's actual angular velocity.
MOTION_QUALITY = {"elbow_speed_warning_mps": 5.0, "joint_angular_speed_warning_dps": 1500.0, "bend_plane_step_warning_deg": 20.0}
## The calibration poses for the elbow hinge: approved clips' frames with clearly bent elbows.
HINGE_MIN_BEND_DEG = 20.0
## Forearm directions closer than this (upper-arm frame) are the same calibration pose.
HINGE_DUPLICATE_DEG = 2.0
HINGE_SPREAD_WARNING_DEG = 10.0


def calibrate_hinge(samples):
    """The elbow hinge in the upper arm's bone-local frame from bent reference poses: each sample is
    (upper-arm local direction of the forearm, i.e. f expressed in the upper arm frame); the hinge is
    the normalized local +Y x f (perpendicular to the humerus by construction), averaged over the
    samples with HINGE_MIN_BEND_DEG or more of bend. Returns (axis, spread_deg, used) or raises
    when no sample is bent enough - never a fallback vector."""
    axes = []
    poses = []
    for f in samples:
        bend = math.degrees(math.acos(_clamp(f[1] / max(_length(f), 1e-12), -1.0, 1.0)))
        if bend < HINGE_MIN_BEND_DEG:
            continue
        ## Frames of one held pose are one calibration example, not independent evidence.
        u = _mul(f, 1.0 / _length(f))
        if any(math.degrees(math.acos(_clamp(_dot(u, p), -1.0, 1.0))) < HINGE_DUPLICATE_DEG for p in poses):
            continue
        poses.append(u)
        n = (f[2], 0.0, -f[0])  # (0, 1, 0) x f
        ln = _length(n)
        axes.append(_mul(n, 1.0 / ln))
    if not axes:
        raise ValueError("no calibration pose bends the elbow by %.0f deg or more" % HINGE_MIN_BEND_DEG)
    mean = (sum(a[0] for a in axes), sum(a[1] for a in axes), sum(a[2] for a in axes))
    mean = _mul(mean, 1.0 / _length(mean))
    spread = max(math.degrees(math.acos(_clamp(_dot(a, mean), -1.0, 1.0))) for a in axes)
    return tuple(round(c, 6) for c in mean), round(spread, 2), len(axes)


def palm_normal(points, contact):
    """The palm's outward normal in the hand's bone-local frame: the least-spread direction
    perpendicular to the hand's long axis (+Y) of its vertices, signed toward the grip contact (the
    handle lies against the palm). Wrist flexion turns the fingers toward it, about +Y x n."""
    xs, zs = [p[0] for p in points], [p[2] for p in points]
    mx, mz = sum(xs) / len(xs), sum(zs) / len(zs)
    sxx = sum((x - mx) ** 2 for x in xs)
    szz = sum((z - mz) ** 2 for z in zs)
    sxz = sum((x - mx) * (z - mz) for x, z in zip(xs, zs))
    ## The smaller eigenvector of [[sxx, sxz], [sxz, szz]].
    angle = 0.5 * math.atan2(2.0 * sxz, sxx - szz) + math.pi / 2.0
    n = (math.cos(angle), 0.0, math.sin(angle))
    if n[0] * contact[0] + n[2] * contact[2] < 0.0:
        n = (-n[0], 0.0, -n[2])
    return tuple(round(c, 6) for c in n)

## The fitted regions: bone whose dominant-weight vertices define it, the shape, and for limbs the
## joint-transition share of the bone excluded at each end. Torso sections are convex prisms over a
## share of their bone's vertex height; the chest is three stacked sections.
REGIONS = (
    {"id": "pelvis", "bone": "Hips", "shape": "prism", "slice": (0.0, 1.0), "end": "bottom"},
    {"id": "abdomen", "bone": "Spine", "shape": "prism", "slice": (0.0, 1.0)},
    {"id": "chest_lower", "bone": "Chest", "shape": "prism", "slice": (0.0, 1.0 / 3.0)},
    {"id": "chest_mid", "bone": "Chest", "shape": "prism", "slice": (1.0 / 3.0, 2.0 / 3.0)},
    {"id": "chest_upper", "bone": "Chest", "shape": "prism", "slice": (2.0 / 3.0, 1.0), "end": "top"},
    {"id": "neck", "bone": "Neck", "shape": "capsule", "trim": (0.0, 0.0)},
    {"id": "head", "bone": "Head", "shape": "capsule", "trim": (0.0, 0.0)},
    {"id": "upper_arm_R", "bone": "UpperArm.R", "shape": "capsule", "trim": (0.12, 0.12)},
    {"id": "upper_arm_L", "bone": "UpperArm.L", "shape": "capsule", "trim": (0.12, 0.12)},
    {"id": "forearm_R", "bone": "Forearm.R", "shape": "capsule", "trim": (0.12, 0.08)},
    {"id": "forearm_L", "bone": "Forearm.L", "shape": "capsule", "trim": (0.12, 0.08)},
    {"id": "hand_R", "bone": "Hand.R", "shape": "capsule", "trim": (0.0, 0.0)},
    {"id": "hand_L", "bone": "Hand.L", "shape": "capsule", "trim": (0.0, 0.0)},
)
## Dominant-weight partition: a vertex belongs to the bone carrying its largest weight, and only if
## that weight is at least this (joint-transition vertices shared between bones stay out).
DOMINANT_WEIGHT_MIN = 0.6
## Robust exterior extents (percentiles of the region's vertices), so a stray vertex never inflates
## a volume; the radius is the cross-section percentile, measured along the segment.
EXTENT_PERCENTILES = (3.0, 97.0)
RADIUS_PERCENTILE = 85.0
RADIUS_STATIONS = 5
## A capsule's radius is the candidate (percentile of the section-centre distance) that best balances
## skin outside the volume against volume outside the skin; the station profile is diagnostic.
RADIUS_CANDIDATE_PERCENTILES = tuple(range(30, 96, 5))

## Penetration bands (mm of proxy overlap), project-specific initial QA tolerances - not published
## industry thresholds; calibrate against approved captures.
BANDS = ((3.0, "minor"), (8.0, "warning"), (15.0, "significant"))
HARD_BAND = "hard"
## Early warning: a checked pair closer than this (positive clearance) is reported as "near".
NEAR_MARGIN_M = 0.005

## The pair table. `a_range` / `b_range` restrict a capsule to a share of its segment (the upper
## arm's distal half against its own chest: the shoulder joint's anatomical contact is permitted).
## Adjacent joints, the torso sections among themselves and the two hands on the grip are excluded
## by omission and listed in EXCLUDED with the reason.
def _pairs():
    pairs = []
    torso = ("pelvis", "abdomen", "chest_lower", "chest_mid", "chest_upper")
    for side, other in (("R", "L"), ("L", "R")):
        for part in torso:
            pairs.append({"a": "forearm_" + side, "b": part})
            pairs.append({"a": "hand_" + side, "b": part})
        pairs.append({"a": "upper_arm_" + side, "b": "chest_lower", "a_range": (0.5, 1.0)})
        pairs.append({"a": "upper_arm_" + side, "b": "abdomen", "a_range": (0.5, 1.0)})
        pairs.append({"a": "forearm_" + side, "b": "upper_arm_" + other})
        pairs.append({"a": "hand_" + side, "b": "head"})
        pairs.append({"a": "hand_" + side, "b": "neck"})
        pairs.append({"a": "forearm_" + side, "b": "head"})
        pairs.append({"a": "upper_arm_" + side, "b": "head"})
        pairs.append({"a": "hand_" + side, "b": "upper_arm_" + other})
    pairs.append({"a": "forearm_R", "b": "forearm_L"})
    pairs.append({"a": "upper_arm_R", "b": "upper_arm_L"})
    pairs.append({"a": "forearm_R", "b": "hand_L", "warning_only": True})
    pairs.append({"a": "forearm_L", "b": "hand_R", "warning_only": True})
    return tuple(pairs)


PAIRS = _pairs()
EXCLUDED = (
    ("upper_arm_X", "forearm_X", "shared elbow joint"),
    ("forearm_X", "hand_X", "shared wrist joint"),
    ("hand_R", "hand_L", "both palms on the grip: expected contact, never a self-collision"),
    ("torso sections", "torso sections", "one connected trunk"),
    ("neck", "head / chest_upper", "connected"),
    ("upper_arm_X", "chest_upper / chest_mid", "shoulder joint and armpit: permitted anatomical contact (the distal half is checked against chest_lower / abdomen)"),
)

## Provisional joint limits (declared, not fitted): the SKELETON-CAPTURE-001 arm heuristics plus the
## wrist components the G3 audit decomposes. Severity hard blocks a pose; warning is reviewed.
JOINT_LIMITS = {
    "elbow_flexion_deg": {"min": 15.0, "max": 140.0, "severity": "warning"},
    "wrist_flexion_deg": {"max_abs": 70.0, "severity": "warning"},
    "wrist_deviation_deg": {"max_abs": 35.0, "severity": "warning"},
    "segment_length_tolerance": {"max_rel": 0.02, "severity": "hard"},
}


## ---------------------------------------------------------------- vectors

def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _mul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _length(a):
    return math.sqrt(_dot(a, a))


def _lerp(a, b, t):
    return _add(a, _mul(_sub(b, a), t))


def _clamp(x, lo, hi):
    return lo if x < lo else hi if x > hi else x


## ---------------------------------------------------------------- distances

def segment_segment(p1, q1, p2, q2):
    """Shortest distance between segments p1-q1 and p2-q2 (Ericson, Real-Time Collision Detection 5.1.9)."""
    d1, d2, r = _sub(q1, p1), _sub(q2, p2), _sub(p1, p2)
    a, e, f = _dot(d1, d1), _dot(d2, d2), _dot(d2, r)
    eps = 1e-12
    if a <= eps and e <= eps:
        return _length(r)
    if a <= eps:
        s, t = 0.0, _clamp(f / e, 0.0, 1.0)
    else:
        c = _dot(d1, r)
        if e <= eps:
            s, t = _clamp(-c / a, 0.0, 1.0), 0.0
        else:
            b = _dot(d1, d2)
            denom = a * e - b * b
            s = _clamp((b * f - c * e) / denom, 0.0, 1.0) if denom > eps else 0.0
            t = (b * s + f) / e
            if t < 0.0:
                s, t = _clamp(-c / a, 0.0, 1.0), 0.0
            elif t > 1.0:
                s, t = _clamp((b - c) / a, 0.0, 1.0), 1.0
    return _length(_sub(_add(p1, _mul(d1, s)), _add(p2, _mul(d2, t))))


## Ternary-search iterations for segment-to-prism: (2/3)^60 of the segment, far below a micrometre.
PRISM_SEARCH_ITERATIONS = 60


def _point_segment_2d(px, pz, ax, az, bx, bz):
    dx, dz = bx - ax, bz - az
    ll = dx * dx + dz * dz
    t = _clamp(((px - ax) * dx + (pz - az) * dz) / ll, 0.0, 1.0) if ll > 1e-18 else 0.0
    return math.hypot(px - (ax + dx * t), pz - (az + dz * t))


def _inside_polygon(px, pz, polygon):
    """Inside a counter-clockwise convex polygon (x, z)."""
    n = len(polygon)
    for i in range(n):
        ax, az = polygon[i]
        bx, bz = polygon[(i + 1) % n]
        if (bx - ax) * (pz - az) - (bz - az) * (px - ax) < 0.0:
            return False
    return True


def _edge_distance(px, pz, polygon):
    n = len(polygon)
    return min(_point_segment_2d(px, pz, polygon[i][0], polygon[i][1], polygon[(i + 1) % n][0], polygon[(i + 1) % n][1]) for i in range(n))


def point_prism_local(p, polygon, y0, y1):
    """Distance from a bone-local point to the solid prism polygon (x, z) x [y0, y1]: the product of two
    convex sets, so the closest point is the 2D closest point with y clamped."""
    d2 = 0.0 if _inside_polygon(p[0], p[2], polygon) else _edge_distance(p[0], p[2], polygon)
    dy = y0 - p[1] if p[1] < y0 else p[1] - y1 if p[1] > y1 else 0.0
    return math.hypot(d2, dy)


def segment_prism(p, q, posed):
    """Shortest distance between a world segment and a posed prism (convex in the segment parameter)."""
    m = posed["to_local"]
    a, b = _apply(m, p), _apply(m, q)
    f = lambda t: point_prism_local(_lerp(a, b, t), posed["polygon"], posed["y0"], posed["y1"])
    lo, hi = 0.0, 1.0
    for _ in range(PRISM_SEARCH_ITERATIONS):
        m1, m2 = lo + (hi - lo) / 3.0, hi - (hi - lo) / 3.0
        if f(m1) <= f(m2):
            hi = m2
        else:
            lo = m1
    return min(f((lo + hi) / 2.0), f(0.0), f(1.0))


def _sub_segment(shape, share):
    a, b = shape["a"], shape["b"]
    return _lerp(a, b, share[0]), _lerp(a, b, share[1])


def clearance(shape_a, shape_b, a_range=(0.0, 1.0), b_range=(0.0, 1.0)):
    """Signed clearance (m) between two posed volumes (world-space shapes as `pose_volume` returns)."""
    if shape_a["shape"] == "prism" and shape_b["shape"] != "prism":
        return clearance(shape_b, shape_a, b_range, a_range)
    if shape_a["shape"] == "prism":
        raise ValueError("prism-prism pairs are excluded (one connected trunk)")
    radii = shape_a["radius"] + shape_b["radius"]
    p, q = _sub_segment(shape_a, a_range)
    if shape_b["shape"] == "capsule":
        r, s = _sub_segment(shape_b, b_range)
        return segment_segment(p, q, r, s) - radii
    return segment_prism(p, q, shape_b) - radii


def band(clearance_m):
    """The penetration band for a signed clearance: clear / near / minor / warning / significant / hard."""
    if clearance_m >= NEAR_MARGIN_M:
        return "clear"
    if clearance_m >= 0.0:
        return "near"
    mm = -clearance_m * 1000.0
    for limit, name in BANDS:
        if mm <= limit:
            return name
    return HARD_BAND


## ---------------------------------------------------------------- posing

def _apply(m, p):
    """A 4x4 row-major affine (list of rows) applied to a point."""
    return tuple(m[r][0] * p[0] + m[r][1] * p[1] + m[r][2] * p[2] + m[r][3] for r in range(3))


def _apply_dir(m, d):
    return tuple(m[r][0] * d[0] + m[r][1] * d[1] + m[r][2] * d[2] for r in range(3))


def rigid_inverse(m):
    """The inverse of a rigid 4x4 (rotation + translation; WolfRig poses carry no scale)."""
    rt = [[m[c][r] for c in range(3)] for r in range(3)]
    t = [-(rt[r][0] * m[0][3] + rt[r][1] * m[1][3] + rt[r][2] * m[2][3]) for r in range(3)]
    return [rt[0] + [t[0]], rt[1] + [t[1]], rt[2] + [t[2]], [0.0, 0.0, 0.0, 1.0]]


def pose_volume(volume, bone_matrix):
    """A profile volume (bone-local) carried into the bone's current world (or armature) frame. A
    prism stays in its bone's frame: queries carry the other shape into it (`to_local`)."""
    out = {"id": volume["region_id"], "shape": volume["shape"], "radius": volume["radius"]}
    if volume["shape"] == "capsule":
        out["a"], out["b"] = _apply(bone_matrix, volume["a"]), _apply(bone_matrix, volume["b"])
    else:
        out["to_local"] = rigid_inverse(bone_matrix)
        out["polygon"] = [tuple(v) for v in volume["polygon"]]
        out["y0"], out["y1"] = volume["y0"], volume["y1"]
    return out


def evaluate(profile, bone_matrices):
    """Every enabled pair's signed clearance and band for one pose (bone name -> 4x4 world matrix)."""
    posed = {v["region_id"]: pose_volume(v, bone_matrices[v["attached_bone"]]) for v in profile["volumes"] if v["attached_bone"] in bone_matrices}
    results = []
    for pair in profile["collision_pairs"]:
        if not pair.get("enabled", True) or pair["a"] not in posed or pair["b"] not in posed:
            continue
        c = clearance(posed[pair["a"]], posed[pair["b"]], tuple(pair.get("a_range", (0.0, 1.0))), tuple(pair.get("b_range", (0.0, 1.0))))
        b = band(c)
        if pair.get("warning_only") and b in ("significant", HARD_BAND):
            b = "warning"
        results.append({"a": pair["a"], "b": pair["b"], "clearance_m": round(c, 4), "penetration_mm": round(max(0.0, -c) * 1000.0, 1), "band": b})
    return results


## ---------------------------------------------------------------- fitting

def percentile(values, q):
    if not values:
        return 0.0
    s = sorted(values)
    k = (len(s) - 1) * q / 100.0
    lo = int(math.floor(k))
    hi = min(lo + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def fit_capsule(points, length, trim):
    """A capsule along the bone's local +Y from its region's bone-local points (the joint-transition
    share `trim` of the bone excluded at each end): the radius profile (RADIUS_PERCENTILE of the
    distance from the section centre) at RADIUS_STATIONS stations (diagnostic), the capsule radius
    balancing skin-out against volume-out (p95 each, RADIUS_CANDIDATE_PERCENTILES), the segment
    spanning the kept band (the caps reach into the excluded joint zones).
    `fit_band` is the bone-local y band coverage is measured on."""
    lo_t, hi_t = trim[0] * length, (1.0 - trim[1]) * length
    kept = [p for p in points if lo_t <= p[1] <= hi_t] or list(points)
    ## The section centre: the bone axis may sit off the flesh centre (a forearm's bones run near its back).
    cx = (percentile([p[0] for p in kept], EXTENT_PERCENTILES[0]) + percentile([p[0] for p in kept], EXTENT_PERCENTILES[1])) / 2.0
    cz = (percentile([p[2] for p in kept], EXTENT_PERCENTILES[0]) + percentile([p[2] for p in kept], EXTENT_PERCENTILES[1])) / 2.0
    radial = lambda p: math.hypot(p[0] - cx, p[2] - cz)
    ys = [p[1] for p in kept]
    y0, y1 = percentile(ys, EXTENT_PERCENTILES[0]), percentile(ys, EXTENT_PERCENTILES[1])
    profile = []
    for i in range(RADIUS_STATIONS):
        a = y0 + (y1 - y0) * i / RADIUS_STATIONS
        b = y0 + (y1 - y0) * (i + 1) / RADIUS_STATIONS
        ring = [radial(p) for p in kept if a <= p[1] <= b]
        profile.append(round(percentile(ring, RADIUS_PERCENTILE), 4) if ring else 0.0)
    a, b = (cx, y0, cz), (cx, y1, cz)
    band_pts = [p for p in kept if y0 <= p[1] <= y1]
    best = None
    for q in RADIUS_CANDIDATE_PERCENTILES:
        r = max(percentile([radial(p) for p in band_pts], q), 1e-3)
        cov = coverage({"shape": "capsule", "a": a, "b": b, "radius": r}, band_pts)
        score = fit_score(cov)
        if best is None or score < best[0]:
            best = (score, r)
    return {"shape": "capsule", "a": tuple(round(c, 4) for c in a), "b": tuple(round(c, 4) for c in b),
            "radius": round(best[1], 4), "radius_profile": profile, "fit_band": (round(y0, 4), round(y1, 4))}


## Angular sectors of a torso section's outline and the outline percentile of each.
PRISM_SECTORS = 16
OUTLINE_PERCENTILE = 97.0
_IDENTITY = [[1.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0], [0.0, 0.0, 1.0, 0.0], [0.0, 0.0, 0.0, 1.0]]


def fit_prism(points, share):
    """A torso section as a convex prism in the bone's local frame: its horizontal outline (x, z) is
    the convex hull of the section's OUTLINE_PERCENTILE radius from the section centre in each of
    PRISM_SECTORS angular sectors (an empty sector takes its neighbours' mean), extruded over the
    section's height band (`share` of the bone's own vertex height - the flesh runs past the bone's
    tail). The outline follows an oval or a heroic lat flare alike; no box corner stands proud of the
    body. Sections abut exactly (flat ends), so the trunk has neither notches nor bulges."""
    all_y = [p[1] for p in points]
    lo, hi = percentile(all_y, EXTENT_PERCENTILES[0]), percentile(all_y, EXTENT_PERCENTILES[1])
    lo_t, hi_t = lo + share[0] * (hi - lo), lo + share[1] * (hi - lo)
    kept = [p for p in points if lo_t <= p[1] <= hi_t] or list(points)
    xs, zs = [p[0] for p in kept], [p[2] for p in kept]
    cx = (percentile(xs, EXTENT_PERCENTILES[0]) + percentile(xs, EXTENT_PERCENTILES[1])) / 2.0
    cz = (percentile(zs, EXTENT_PERCENTILES[0]) + percentile(zs, EXTENT_PERCENTILES[1])) / 2.0
    sectors = [[] for _ in range(PRISM_SECTORS)]
    for p in kept:
        angle = math.atan2(p[2] - cz, p[0] - cx) % (2.0 * math.pi)
        sectors[min(int(angle / (2.0 * math.pi) * PRISM_SECTORS), PRISM_SECTORS - 1)].append(math.hypot(p[0] - cx, p[2] - cz))
    radii = [percentile(s, OUTLINE_PERCENTILE) if s else None for s in sectors]
    for i, r in enumerate(radii):
        if r is None:
            known = [x for x in (radii[(i - 1) % PRISM_SECTORS], radii[(i + 1) % PRISM_SECTORS]) if x is not None]
            radii[i] = sum(known) / len(known) if known else 0.0
    outline = []
    for i, r in enumerate(radii):
        angle = (i + 0.5) * 2.0 * math.pi / PRISM_SECTORS
        outline.append((round(cx + r * math.cos(angle), 4), round(cz + r * math.sin(angle), 4)))
    polygon = _convex_hull(outline)
    return {"shape": "prism", "polygon": polygon, "y0": round(lo_t, 4), "y1": round(hi_t, 4), "radius": 0.0,
            "fit_band": (round(lo_t, 4), round(hi_t, 4)),
            "extent": {"width": round(max(x for x, _ in polygon) - min(x for x, _ in polygon), 4),
                       "depth": round(max(z for _, z in polygon) - min(z for _, z in polygon), 4), "height": round(hi_t - lo_t, 4)}}


def signed_distance(volume_world, p):
    """A point's signed distance to a posed volume (negative inside, by the depth inside)."""
    if volume_world["shape"] == "capsule":
        return segment_segment(p, p, volume_world["a"], volume_world["b"]) - volume_world["radius"]
    q = _apply(volume_world["to_local"], p)
    polygon, y0, y1 = volume_world["polygon"], volume_world["y0"], volume_world["y1"]
    outside = point_prism_local(q, polygon, y0, y1)
    if outside > 0.0:
        return outside - volume_world["radius"]
    return -min(_edge_distance(q[0], q[2], polygon), q[1] - y0, y1 - q[1]) - volume_world["radius"]


def _convex_hull(points):
    """Counter-clockwise convex hull (x, z) (Andrew's monotone chain)."""
    pts = sorted(set(points))
    if len(pts) <= 2:
        return pts
    cross = lambda o, a, b: (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0.0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0.0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def coverage(volume_world, points):
    """How well a posed volume matches its region's (deformed) skin vertices. The vertices are the
    surface, so a good fit straddles them: `skin_out_p95_mm` is how far skin sticks out of the volume
    (under-coverage), `volume_out_p95_mm` how far the volume reaches past the skin (over-coverage)."""
    d = [signed_distance(volume_world, p) for p in points]
    if not d:
        return {"skin_out_p95_mm": 0.0, "volume_out_p95_mm": 0.0, "skin_out_p99_mm": 0.0, "volume_out_p99_mm": 0.0, "count": 0}
    return {"skin_out_p95_mm": round(max(0.0, percentile(d, 95.0)) * 1000.0, 1),
            "volume_out_p95_mm": round(max(0.0, -percentile(d, 5.0)) * 1000.0, 1),
            "skin_out_p99_mm": round(max(0.0, percentile(d, 99.0)) * 1000.0, 1),
            "volume_out_p99_mm": round(max(0.0, -percentile(d, 1.0)) * 1000.0, 1), "count": len(d)}


## Fit score: the tails, so a box corner standing proud of an oval section (few vertices there) is seen.
def fit_score(cov):
    return cov["skin_out_p99_mm"] + cov["volume_out_p99_mm"]


def content_hash(payload):
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()[:16]


def profile_document(source_body_id, mesh_hash, rest_hash, volumes, report, joints=None):
    return {"schema": SCHEMA, "version": VERSION, "validation_version": VERSION, "source_body_id": source_body_id,
            "source_mesh_hash": mesh_hash, "skeleton_rest_hash": rest_hash, "dominant_weight_min": DOMINANT_WEIGHT_MIN,
            "chains": {k: list(v) for k, v in CHAINS.items()}, "rig_capabilities": RIG_CAPABILITIES,
            "coordination_profiles": {k: {kk: list(vv) if isinstance(vv, tuple) else vv for kk, vv in v.items()} for k, v in COORDINATION.items()},
            "joints": joints or {}, "joint_constraints": JOINT_CONSTRAINTS, "motion_quality": MOTION_QUALITY,
            "grip_reach_envelope": {"validated_pose_domain": "pending (G3.c / G4 / G5)", "supported_handling_profiles": []},
            "volumes": volumes, "legacy_arm_heuristics": JOINT_LIMITS,
            "collision_pairs": [dict(p, enabled=True, allowed_clearance_m=0.0) for p in PAIRS],
            "excluded_pairs": [list(e) for e in EXCLUDED], "bands_mm": [list(b) for b in BANDS], "near_margin_m": NEAR_MARGIN_M,
            "fit_report": report}


## ---------------------------------------------------------------- self-check

def self_check():
    close = lambda x, y: abs(x - y) < 1e-6
    ## Parallel, crossing and end-to-end segments.
    assert close(segment_segment((0, 0, 0), (1, 0, 0), (0, 1, 0), (1, 1, 0)), 1.0)
    assert close(segment_segment((0, 0, 0), (1, 0, 0), (0.5, -1, 0.3), (0.5, 1, 0.3)), 0.3)
    assert close(segment_segment((0, 0, 0), (1, 0, 0), (2, 0, 0), (3, 0, 0)), 1.0)
    ## A segment through, beside, above and diagonal to a 2 m cube prism (polygon x, z; height y).
    cube = {"to_local": [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]], "polygon": [(-1, -1), (1, -1), (1, 1), (-1, 1)], "y0": -1.0, "y1": 1.0}
    near = lambda x, y: abs(x - y) < 1e-5
    assert near(segment_prism((0.2, -3, 0.2), (0.2, 3, 0.2), cube), 0.0)
    assert near(segment_prism((3, -3, 0), (3, 3, 0), cube), 2.0)
    assert near(segment_prism((-3, 1.4, 0.5), (3, 1.4, 0.5), cube), 0.4)
    assert near(segment_prism((2, -5, 2), (2, 5, 2), cube), math.sqrt(2.0))
    ## The guide's worked example: axes 0.09 m apart, radii summing to 0.12 m -> -0.03 m (30 mm).
    a = {"shape": "capsule", "a": (0, 0, 0), "b": (1, 0, 0), "radius": 0.06}
    b = {"shape": "capsule", "a": (0, 0.09, 0), "b": (1, 0.09, 0), "radius": 0.06}
    assert close(clearance(a, b), -0.03) and band(clearance(a, b)) == HARD_BAND
    assert band(0.01) == "clear" and band(0.002) == "near" and band(-0.002) == "minor" and band(-0.005) == "warning" and band(-0.012) == "significant"
    square = {"region_id": "t", "shape": "prism", "polygon": [(-0.1, -0.1), (0.1, -0.1), (0.1, 0.1), (-0.1, 0.1)], "y0": -0.1, "y1": 0.1, "radius": 0.0}
    trunk = pose_volume(square, _IDENTITY)
    assert near(clearance(a, trunk), -0.06) and near(clearance(trunk, a), -0.06)
    beside = {"shape": "capsule", "a": (0.3, -1, 0), "b": (0.3, 1, 0), "radius": 0.05}
    above = {"shape": "capsule", "a": (0.3, 0.4, 0.3), "b": (0.3, 0.4, 0.3), "radius": 0.0}
    assert near(clearance(beside, trunk), 0.15) and near(clearance(above, trunk), math.sqrt(0.2 ** 2 + 0.3 ** 2 + 0.2 ** 2))
    ## Carried by a turned bone (90 deg about y, then 1 m along x) and queried back through its inverse.
    turned = [[0.0, 0.0, 1.0, 1.0], [0.0, 1.0, 0.0, 0.0], [-1.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 1.0]]
    probe = {"shape": "capsule", "a": (1.0, -1, 0.3), "b": (1.0, 1, 0.3), "radius": 0.0}
    assert near(clearance(probe, pose_volume(square, turned)), 0.2)
    ## Fitting: a cylinder of radius 0.04 about +Y from 0 to 0.3 fits a ~0.04 capsule inside its extent.
    pts = [(0.04 * math.cos(k), y / 100.0, 0.04 * math.sin(k)) for y in range(0, 31) for k in [i * math.pi / 8 for i in range(16)]]
    cap = fit_capsule(pts, 0.3, (0.0, 0.0))
    assert abs(cap["radius"] - 0.04) < 0.002 and cap["a"][1] >= 0.0 and cap["b"][1] <= 0.3
    assert all(signed_distance(dict(cap, a=cap["a"], b=cap["b"]), p) < 0.003 for p in pts if cap["fit_band"][0] <= p[1] <= cap["fit_band"][1])
    ## An elliptical shell (0.2 x 0.15 m semi-axes): the prism outline hugs it to the 16-gon's chord error
    ## (r (1 - cos(pi / 16)) ~ 4 mm) - no corner stands proud.
    shell = [(0.2 * math.cos(k * math.pi / 32), y / 20.0, 0.15 * math.sin(k * math.pi / 32)) for k in range(64) for y in range(0, 5)]
    fitted = pose_volume(dict(fit_prism(shell, (0.0, 1.0)), region_id="e"), _IDENTITY)
    cov = coverage(fitted, shell)
    assert cov["skin_out_p99_mm"] < 6.0 and cov["volume_out_p99_mm"] < 6.0, cov
    assert all(point_prism_local((0.2 * math.cos(k) * 1.05, 0.1, 0.15 * math.sin(k) * 1.05), fitted["polygon"], 0.0, 0.2) > 0.0 for k in (0.6, 0.8, 2.3, 4.0))
    ## Hinge calibration: forearms bent about local +Z by 30 / 60 / 90 deg give the hinge +Z (+Y x f); a straight sample is ignored.
    bent = [(-math.sin(math.radians(b)), math.cos(math.radians(b)), 0.0) for b in (30.0, 60.0, 90.0)]
    axis, spread, used = calibrate_hinge(bent + [(0.0, 1.0, 0.0), bent[0]])
    assert used == 3 and spread < 1e-6 and near(axis[2], 1.0), (axis, spread, used)
    try:
        calibrate_hinge([(0.0, 1.0, 0.001)])
        raise AssertionError("a straight arm must not calibrate a hinge")
    except ValueError:
        pass
    flat = [(x / 100.0, y / 100.0, z / 1000.0) for x in range(-4, 5) for y in range(0, 10) for z in range(-1, 2)]
    assert near(abs(palm_normal(flat, (0.0, 0.0, 0.02))[2]), 1.0) and palm_normal(flat, (0.0, 0.0, 0.02))[2] > 0.0
    ## Pair table: every pair names fitted regions, no pair repeats, no excluded adjacency is checked.
    ids = {r["id"] for r in REGIONS}
    seen = set()
    for p in PAIRS:
        assert p["a"] in ids and p["b"] in ids, p
        key = frozenset((p["a"], p["b"]))
        assert key not in seen, p
        seen.add(key)
        assert key != frozenset(("hand_R", "hand_L"))
        for s in "RL":
            assert key != frozenset(("upper_arm_" + s, "forearm_" + s)) and key != frozenset(("forearm_" + s, "hand_" + s))
    for must in (("forearm_R", "chest_lower"), ("forearm_L", "chest_upper"), ("forearm_R", "forearm_L"), ("forearm_R", "upper_arm_L"), ("hand_R", "head")):
        assert frozenset(must) in seen, must
    return True
