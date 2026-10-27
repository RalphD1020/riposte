"""Anatomy regions and the regional controls that may shape them.

A region is a name for part of one connected surface. It is never a
separate mesh. The study fuses its lofts with a remesh, which destroys loft
identity, so a vertex's region comes from where it sits relative to the
figure's landmarks, deterministically. Near a boundary the answer is
blended: the region it is in, a confidence, and the region across the
nearest boundary. A diagnostic that lands on a low-confidence vertex says
"deltoid / upper arm" rather than inventing precision.

A control is defined by the surface change it may make and what it must
leave alone. 1.0 is the accepted default shape of whichever aesthetic is
loaded. The ranges are experimental until calibrated against measured
deltas and sheets.
"""

from __future__ import annotations

import math

REGIONS = (
    "head_face", "head_crown", "head_jaw", "neck",
    "chest", "abdomen", "back_upper", "back_lower",
    "shoulder", "upper_arm", "forearm", "hand",
    "pelvis", "glute", "thigh", "calf", "foot",
)
PART_HEAD = "head"
PART_BODY = "body"
# Width over which a boundary blends between two regions (m).
BLEND_M = 0.03
ARM_REACH_M = 0.13
SHOULDER_ALONG_M = 0.10
NECK_ABOVE_SHOULDER_M = 0.05
UPPER_BACK_BELOW_CHEST_M = 0.04
LOWER_BACK_ABOVE_HIP_M = 0.04
ABDOMEN_BELOW_HIP_M = 0.02
JAW_ABOVE_CHIN_M = 0.10
# Outline concavities expected where these meet: armpit, crotch, jaw, neck.
JUNCTIONS = frozenset(frozenset(pair) for pair in (
    ("shoulder", "chest"), ("shoulder", "back_upper"), ("upper_arm", "chest"),
    ("upper_arm", "back_upper"), ("upper_arm", "back_lower"), ("upper_arm", "shoulder"),
    ("thigh", "pelvis"), ("thigh", "glute"), ("thigh", "abdomen"),
    ("neck", "head_face"), ("neck", "head_crown"), ("neck", "head_jaw"), ("head_jaw", "head_face"),
    ("neck", "chest"), ("neck", "back_upper"),
    ("neck", "shoulder"), ("calf", "foot"), ("forearm", "hand"),
))

REQUIRED_LANDMARKS = ("chin_z", "shoulder_z", "chest_z", "waist_z", "hip_z", "crotch_z", "torso_center_y", "joints")
JOINTS = ("shoulder", "elbow", "wrist", "palm", "hip", "knee", "ankle", "toe")


def validate_landmarks(landmarks):
    problems = ["landmark %s is missing" % key for key in REQUIRED_LANDMARKS if key not in landmarks]
    for side in ("L", "R"):
        joints = landmarks.get("joints", {}).get(side, {})
        problems += ["joint %s.%s is missing" % (name, side) for name in JOINTS if name not in joints]
    if not problems and not (landmarks["crotch_z"] < landmarks["hip_z"] < landmarks["waist_z"]
                             < landmarks["chest_z"] < landmarks["shoulder_z"] < landmarks["chin_z"]):
        problems.append("landmark heights are not crotch < hip < waist < chest < shoulder < chin")
    return problems


def _smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def _along_chain(p, chain):
    """Distance from ``p`` to a polyline and the arc length of the closest point."""
    best, best_s, travelled = math.inf, 0.0, 0.0
    for a, b in zip(chain, chain[1:]):
        ab = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        length2 = ab[0] ** 2 + ab[1] ** 2 + ab[2] ** 2
        length = math.sqrt(length2)
        ap = (p[0] - a[0], p[1] - a[1], p[2] - a[2])
        t = 0.0 if length2 == 0.0 else max(0.0, min(1.0, (ap[0] * ab[0] + ap[1] * ab[1] + ap[2] * ab[2]) / length2))
        q = (a[0] + ab[0] * t, a[1] + ab[1] * t, a[2] + ab[2] * t)
        d = math.dist(p, q)
        if d < best:
            best, best_s = d, travelled + t * length
        travelled += length
    return best, best_s


def classify(p, landmarks, part=PART_BODY, on_face=False):
    """(region, confidence 0.5..1, neighbouring region or None) for one point.

    On the head: the flagged face panels are the face; below ``jaw_top_z``
    (default a tenth of a metre above the chin) the rest is the jaw; above it,
    the crown.
    """
    if part == PART_HEAD:
        if on_face:
            return "head_face", 1.0, None
        jaw_top = landmarks.get("jaw_top_z", landmarks["chin_z"] + JAW_ABOVE_CHIN_M)
        if p[2] < jaw_top:
            return _finish("head_jaw", [(jaw_top - p[2], "head_crown")])
        return _finish("head_crown", [(p[2] - jaw_top, "head_jaw")])
    x, y, z = p
    j = landmarks["joints"]["L" if x >= 0.0 else "R"]
    margins = []

    shoulder, elbow, wrist, palm = j["shoulder"], j["elbow"], j["wrist"], j["palm"]
    reach, along = _along_chain(p, (shoulder, elbow, wrist, palm))
    upper_len = math.dist(shoulder, elbow)
    fore_len = math.dist(elbow, wrist)
    axis = tuple((elbow[k] - shoulder[k]) / upper_len for k in range(3))
    past = sum((p[k] - shoulder[k]) * axis[k] for k in range(3))
    if reach < ARM_REACH_M and past > 0.0:
        torso_side = "back_upper" if y > landmarks["torso_center_y"] else "chest"
        if along < SHOULDER_ALONG_M:
            region = "shoulder"
            margins += [(past, torso_side), (SHOULDER_ALONG_M - along, "upper_arm")]
        elif along < upper_len:
            region = "upper_arm"
            margins += [(along - SHOULDER_ALONG_M, "shoulder"), (upper_len - along, "forearm")]
        elif along < upper_len + fore_len:
            region = "forearm"
            margins += [(along - upper_len, "upper_arm"), (upper_len + fore_len - along, "hand")]
        else:
            region, margins = "hand", [(along - upper_len - fore_len, "forearm")]
        margins.append((ARM_REACH_M - reach, torso_side))
        return _finish(region, margins)

    knee_z, ankle_z = j["knee"][2], j["ankle"][2]
    crotch, hip = landmarks["crotch_z"], landmarks["hip_z"]
    if z < crotch:
        if z < ankle_z:
            return _finish("foot", [(ankle_z - z, "calf")])
        if z < knee_z:
            return _finish("calf", [(knee_z - z, "thigh"), (z - ankle_z, "foot")])
        rear = y > landmarks["torso_center_y"]
        return _finish("thigh", [(z - knee_z, "calf"), (crotch - z, "glute" if rear else "pelvis")])

    yc = landmarks["torso_center_y"]
    front = y <= yc
    if z > landmarks["shoulder_z"] + NECK_ABOVE_SHOULDER_M:
        return _finish("neck", [(z - landmarks["shoulder_z"] - NECK_ABOVE_SHOULDER_M, "chest" if front else "back_upper")])
    waist, chest = landmarks["waist_z"], landmarks["chest_z"]
    if front:
        bands = (("pelvis", -math.inf, hip - ABDOMEN_BELOW_HIP_M), ("abdomen", hip - ABDOMEN_BELOW_HIP_M, waist),
                 ("chest", waist, math.inf))
        across = {"pelvis": "glute", "abdomen": "back_lower", "chest": "back_upper"}
    else:
        bands = (("glute", -math.inf, hip + LOWER_BACK_ABOVE_HIP_M),
                 ("back_lower", hip + LOWER_BACK_ABOVE_HIP_M, chest - UPPER_BACK_BELOW_CHEST_M),
                 ("back_upper", chest - UPPER_BACK_BELOW_CHEST_M, math.inf))
        across = {"glute": "pelvis", "back_lower": "abdomen", "back_upper": "chest"}
    for index, (region, lo, hi) in enumerate(bands):
        if lo <= z < hi:
            if index > 0:
                margins.append((z - lo, bands[index - 1][0]))
            if index < len(bands) - 1:
                margins.append((hi - z, bands[index + 1][0]))
            margins.append((abs(y - yc), across[region]))
            if region in ("pelvis", "glute"):
                margins.append((z - crotch, "thigh"))
            return _finish(region, margins)
    raise AssertionError("height bands do not cover z=%s" % z)


def _finish(region, margins):
    margin, neighbour = min(margins, key=lambda item: item[0]) if margins else (math.inf, None)
    confidence = 0.5 + 0.5 * _smooth(margin / BLEND_M)
    return region, round(confidence, 4), (neighbour if confidence < 1.0 else None)


def classify_mesh(mesh, landmarks, part_of_vertex):
    """Per-vertex (region, confidence, neighbour). ``part_of_vertex`` names each vertex's part."""
    face_vertices = set()
    for index in mesh.face_flags.get("face_panel", ()):
        face_vertices.update(mesh.faces[index])
    return [classify(v, landmarks, part_of_vertex[i], i in face_vertices) for i, v in enumerate(mesh.vertices)]


def label(entry):
    region, confidence, neighbour = entry
    return region if neighbour is None or confidence >= 0.8 else "%s / %s" % (region, neighbour)


# --- Regional controls -------------------------------------------------------

class Control:
    def __init__(self, id, regions, surface_change, protects, minimum=0.9, maximum=1.1, enabled=True):
        self.id = id
        self.regions = tuple(regions)
        self.surface_change = surface_change
        self.protects = tuple(protects)
        self.minimum = minimum
        self.default = 1.0
        self.maximum = maximum
        self.enabled = enabled
        unknown = [r for r in self.regions if r not in REGIONS]
        if unknown:
            raise ValueError("%s names unknown regions %s" % (id, unknown))


CONTROLS = (
    Control("chest_fullness", ("chest",), "Modest pectoral volume and heroic upper-torso breadth.",
            ("shoulder span", "neck fit", "face", "waist anchor")),
    Control("back_fullness", ("back_upper", "back_lower"), "Thoracic depth and a fuller upper back.",
            ("front silhouette", "arm root")),
    Control("scapular_relief", ("back_upper",), "Shallow, broad relief either side of the spine.",
            ("no deep groove", "no detached plates")),
    Control("lat_flare", ("back_lower", "back_upper"), "A clear rear V-taper from the armpit to the waist.",
            ("waist width", "underarm continuity")),
    Control("deltoid_fullness", ("shoulder",), "Rounds the shoulder into the upper arm.",
            ("shoulder joint position", "no shoulder-arm nub or ledge")),
    Control("arm_fullness", ("upper_arm",), "A controlled upper-arm belly.", ("elbow anchor", "wrist anchor")),
    Control("forearm_fullness", ("forearm",), "Volume in the upper forearm, tapering to the wrist.",
            ("grip", "hand anchor")),
    Control("leg_fullness", ("thigh",), "Quad and upper-thigh shape.", ("pelvis-to-thigh continuity", "knee anchor")),
    Control("calf_shape", ("calf",), "A rear-biased calf belly.", ("ankle anchor", "foot fit")),
    Control("neck_trap_slope", ("neck", "back_upper", "shoulder"), "Neck, trapezius and shoulder as one slope.",
            ("head clearance", "shoulder span")),
    # Disabled until the default aesthetic is picked: global scaling would hide
    # which regional control produced the result.
    Control("muscularity", REGIONS[2:], "Overall muscle fullness through the regional controls.",
            ("height", "skeleton", "face", "joint anchors"), enabled=False),
)
CONTROL_BY_ID = {control.id: control for control in CONTROLS}


def validate_controls(values):
    if values is None:
        return []
    if not isinstance(values, dict):
        return ["controls must be an object"]
    problems = ["unknown control %s" % key for key in sorted(set(values) - set(CONTROL_BY_ID))]
    for key, value in values.items():
        control = CONTROL_BY_ID.get(key)
        if control is None:
            continue
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            problems.append("%s must be a number" % key)
        elif not control.enabled and value != control.default:
            problems.append("%s is disabled until the default aesthetic is picked" % key)
        elif not (control.minimum <= value <= control.maximum):
            problems.append("%s=%s is outside %s..%s" % (key, value, control.minimum, control.maximum))
    return problems


def resolve_controls(values=None):
    problems = validate_controls(values)
    if problems:
        raise ValueError("; ".join(problems))
    resolved = {control.id: control.default for control in CONTROLS}
    resolved.update({key: float(value) for key, value in (values or {}).items()})
    return resolved
