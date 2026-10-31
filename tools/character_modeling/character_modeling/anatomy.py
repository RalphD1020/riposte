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
from dataclasses import dataclass
from types import MappingProxyType

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
    def __init__(self, id, regions, surface_change, protects, minimum=0.9, maximum=1.1):
        self.id = id
        self.regions = tuple(regions)
        self.surface_change = surface_change
        self.protects = tuple(protects)
        self.minimum = minimum
        self.default = 1.0
        self.maximum = maximum
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
    # Overall muscularity is not a regional control: it is the ``muscularity``
    # body input (``parameters.BODY_INPUTS``), one home for one concept.
)
CONTROL_BY_ID = {control.id: control for control in CONTROLS}


# --- Creation regions --------------------------------------------------------
#
# A creation region says what the body is made of. It is not a bone and it is
# not a weight. ``anchors`` are the joints the geometry is built around.
# ``deform_bones`` are the candidate bones that may influence it when it
# moves. A shoulder is anchored on the clavicle and deforms across the
# clavicle, the upper arm and the chest; those lists are deliberately not
# the same. Weights live in the deformation mapping below and in
# ``skinning.py``, not here.
#
# Protected landmarks are ``<Bone>.head`` / ``<Bone>.tail`` in the rig
# contract (``game/content/characters/wolf.rig-contract.json``).

# Ordinary combat motion. Overhead past the clips is a diagnostic, not a bar.
COMBAT_DEFORMATION = "combat clips, guards and joint flex"
SHOULDER_DEFORMATION = "combat elevation and rotation; sweeps past that envelope are diagnostic"


class RegionDefinition:
    def __init__(self, id, anchors, neighbors, protected_landmarks, deform_bones, max_influences,
                 construction, deformation):
        self.id = id
        self.anchors = tuple(anchors)
        self.neighbors = tuple(neighbors)
        self.protected_landmarks = tuple(protected_landmarks)
        self.deform_bones = tuple(deform_bones)
        self.max_influences = max_influences
        self.construction = construction
        self.deformation = deformation
        outside = [bone for bone in self.anchors if bone not in self.deform_bones]
        if outside:
            raise ValueError("%s anchors %s outside its deform candidates" % (id, outside))
        if not 1 <= max_influences <= 4:
            raise ValueError("%s allows %s influences; Compatibility allows 1..4" % (id, max_influences))

    @property
    def controls(self):
        return tuple(control.id for control in CONTROLS if self.id in control.regions)


def _both(name):
    return (name + ".L", name + ".R")


def _ends(bone, end):
    return tuple("%s.%s" % (side, end) for side in _both(bone))


_SH, _UA, _FA, _HA = _both("Shoulder"), _both("UpperArm"), _both("Forearm"), _both("Hand")
_UL, _LL, _FT = _both("UpperLeg"), _both("LowerLeg"), _both("Foot")


def _region(id, anchors, neighbors, protected, deform, influences, construction, deformation=COMBAT_DEFORMATION):
    return RegionDefinition(id, anchors, neighbors, protected, deform, influences, construction, deformation)


REGION_DEFINITIONS = (
    _region("head_face", ("Head",), ("head_crown", "head_jaw", "neck"), ("Head.head", "Head.tail"),
            ("Head",), 2, "head loft"),
    _region("head_crown", ("Head",), ("head_face", "head_jaw", "neck"), ("Head.head", "Head.tail"),
            ("Head",), 2, "head loft"),
    _region("head_jaw", ("Head",), ("head_face", "head_crown", "neck"), ("Head.head",),
            ("Head",), 2, "head loft"),
    _region("neck", ("Neck",), ("head_face", "head_crown", "head_jaw", "chest", "back_upper", "shoulder"),
            ("Neck.head", "Head.head"), ("Neck", "Chest", "Head"), 2, "neck rings"),
    _region("chest", ("Chest",), ("neck", "shoulder", "upper_arm", "abdomen", "back_upper"),
            ("Chest.head", "Neck.head"), ("Chest", "Neck", "Spine") + _SH + _UA, 4, "torso grid"),
    _region("abdomen", ("Spine",), ("chest", "pelvis", "back_lower", "thigh"), ("Spine.head",),
            ("Spine", "Chest", "Hips"), 2, "torso grid"),
    _region("back_upper", ("Chest",), ("neck", "shoulder", "upper_arm", "back_lower", "chest"),
            ("Chest.head", "Neck.head"), ("Chest", "Neck") + _SH + _UA, 4, "torso grid"),
    _region("back_lower", ("Spine",), ("back_upper", "glute", "abdomen", "upper_arm"),
            ("Spine.head", "Hips.tail"), ("Spine", "Hips"), 2, "torso grid"),
    _region("shoulder", _SH, ("neck", "chest", "back_upper", "upper_arm"), _ends("Shoulder", "tail"),
            _SH + _UA + ("Chest",), 4, "socket weld and deltoid cap", SHOULDER_DEFORMATION),
    _region("upper_arm", _UA, ("shoulder", "chest", "back_upper", "back_lower", "forearm"),
            _ends("UpperArm", "head") + _ends("UpperArm", "tail"), _UA + _SH + _FA, 2, "limb loft"),
    _region("forearm", _FA, ("upper_arm", "hand"), _ends("Forearm", "tail"), _FA + _UA + _HA, 2, "limb loft"),
    _region("hand", _HA, ("forearm",), _ends("Hand", "tail"), _HA + _FA, 2, "limb loft"),
    _region("pelvis", ("Hips",), ("abdomen", "glute", "thigh"), ("Hips.head",) + _ends("UpperLeg", "head"),
            ("Hips", "Spine") + _UL, 4, "torso grid and pelvis opening"),
    _region("glute", ("Hips",), ("pelvis", "back_lower", "thigh"), ("Hips.head",),
            ("Hips",) + _UL, 4, "torso grid"),
    _region("thigh", _UL, ("pelvis", "glute", "abdomen", "calf"),
            _ends("UpperLeg", "head") + _ends("UpperLeg", "tail"), _UL + ("Hips",) + _LL, 2, "limb loft"),
    _region("calf", _LL, ("thigh", "foot"), _ends("LowerLeg", "tail"), _LL + _UL + _FT, 2, "limb loft"),
    _region("foot", _FT, ("calf",), _ends("Foot", "head"), _FT + _LL, 2, "limb loft"),
)
REGION_BY_ID = {region.id: region for region in REGION_DEFINITIONS}


def validate_region_contract(rig_bones):
    """Problems with the creation-region contract against the rig's bone names."""
    bones = set(rig_bones)
    problems = []
    if tuple(region.id for region in REGION_DEFINITIONS) != REGIONS:
        problems.append("region definitions must cover REGIONS exactly, in order")
    for region in REGION_DEFINITIONS:
        problems += ["%s anchors unknown bone %s" % (region.id, bone) for bone in region.anchors if bone not in bones]
        problems += ["%s deforms with unknown bone %s" % (region.id, bone)
                     for bone in region.deform_bones if bone not in bones]
        if not 1 <= region.max_influences <= 4:
            problems.append("%s allows %s influences" % (region.id, region.max_influences))
        for landmark in region.protected_landmarks:
            bone, _, end = landmark.rpartition(".")
            if bone not in bones or end not in ("head", "tail"):
                problems.append("%s protects unknown landmark %s" % (region.id, landmark))
        for neighbor in region.neighbors:
            other = REGION_BY_ID.get(neighbor)
            if other is None:
                problems.append("%s names unknown neighbor %s" % (region.id, neighbor))
            elif region.id not in other.neighbors:
                problems.append("%s and %s must name each other as neighbors" % (region.id, neighbor))
    return problems


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


# --- Construction landmarks --------------------------------------------------
#
# ``derive_anatomy(resolved, rig)`` is pure. It reads a resolved profile (its
# style widths) and the rig contract (its joints) and returns the points the
# production builder constructs around. Landmarks are construction data only:
# they never enter simulation, rules, reach, mass, or hit detection. The rig
# contract stays the authority for every joint; a landmark that disagrees with
# it is a problem, not a correction. Real anthropometry is a sanity range,
# never acceptance; Model A (the accepted study) is the visual reference: a
# high heroic mantle and deltoids whose outer surface sets the shoulder span.
#
# The A-pose is a modeling and binding reference, not a second skeleton: the
# body is built on WolfRig's one rest pose, and every profile keeps that rest.

# Acromion: the top of the shoulder girdle, just lateral of and above the joint.
ACROMION_ABOVE_GH_M = 0.06
ACROMION_LATERAL_OF_GH_M = 0.01
# The trapezius ridge peaks this far above the acromion beside the neck
# (Model A's girdle top is 1.473 m against a 1.37 m joint).
MANTLE_RISE_M = 0.045
# The ridge meets the neck this many neck half-widths from the midline.
NECK_ROOT_OF_NECK = 1.8
# Axilla (armpit) below the joint; its front and back folds either side.
AXILLA_BELOW_GH_M = 0.09
AXILLA_FOLD_M = 0.08
# Deltoid cap: it sweeps around a centre this far below the joint, from the
# socket (facing out) to the upper arm (along the humerus). The outer face
# of that cap is the shoulder span (``deltoid_outer_extent``). Front-back
# depth is a multiple of the arm.
DELTOID_BELOW_GH_M = 0.025
DELTOID_DEPTH_OF_ARM = 1.15
# Where the cap hands its outer face to the shaft, as a fraction of the
# humerus. The shaft beyond this stays on the bone. The fraction is not a
# translation of the arm.
DELTOID_HANDOFF = 0.28
# Pelvis: crest above, groin below, glute mass behind the hip joint.
ILIAC_ABOVE_HIP_M = 0.13
GROIN_BELOW_HIP_M = 0.085
GLUTE_BEHIND_HIP_M = 0.06


@dataclass(frozen=True)
class ShoulderLandmarks:
    chest_anchor: tuple          # Chest head: the stable upper-torso reference
    neck_base: tuple             # Neck head
    clavicle_start: tuple        # sternal end (Shoulder head)
    clavicle_end: tuple          # acromial end (the acromion)
    gh_center: tuple             # glenohumeral joint (UpperArm head): the rig's, never moved
    acromion: tuple              # shoulder top; the socket's upper boundary
    deltoid_center: tuple        # the point the deltoid cap's rings sweep around
    deltoid_outer_extent: tuple  # the deltoid's outermost surface point (the shoulder span)
    deltoid_underside: tuple     # point on the humerus where the cap hands off to the shaft
    deltoid_radii: tuple         # (vertical, front-back) half extents of the cap rings
    trap_ridge: tuple            # (neck root, acromion): the trapezius ridge
    axilla: tuple                # armpit centre, the socket's lower boundary
    axilla_front: tuple          # pectoral fold
    axilla_back: tuple           # latissimus fold
    socket_z: tuple              # (axilla, mid, acromion) heights of the socket rows


@dataclass(frozen=True)
class PelvisLandmarks:
    hip: tuple                   # hip joint (UpperLeg head): the rig's, never moved
    iliac_z: float
    glute: tuple
    groin: tuple


@dataclass(frozen=True)
class AnatomyLandmarks:
    sizes: MappingProxyType      # half-widths in metres (read-only)
    shoulders: MappingProxyType  # side -> ShoulderLandmarks
    pelvis: MappingProxyType     # side -> PelvisLandmarks
    neck_root: tuple             # (half-width, z) where the trapezius ridge meets the neck
    mantle_top_z: float


def rig_points(rig):
    """``{bone: (head, tail)}`` from a rig contract."""
    return {bone["name"]: (tuple(bone["head"]), tuple(bone["tail"])) for bone in rig["bones"]}


def body_sizes(style, cheek_width_m):
    """Half-widths in metres from a resolved profile's style (head-width multiples)."""
    w = cheek_width_m
    depth = style["depth"]
    chest = style["chest"] * w * 0.5
    return {
        "pelvis": style["pelvis"] * w * 0.5, "pelvis_d": style["pelvis"] * w * 0.5 * depth,
        "waist": style["waist"] * w * 0.5, "waist_d": style["waist"] * w * 0.5 * depth,
        "chest": chest, "chest_d": chest * depth,
        "neck": style["neck"] * w * 0.5, "neck_d": style["neck"] * w * 0.5 * 0.92,
        "head": w * 0.5, "head_d": w * 0.5 * 0.92,
        "shoulders": style["shoulders"] * w * 0.5,
        "arm": style["arm"][0] * w * 0.5, "arm_end": style["arm"][1] * w * 0.5,
        "fore": style["fore"][0] * w * 0.5, "fore_end": style["fore"][1] * w * 0.5,
        "hand": style["fore"][1] * w * 0.5 * style["hand"],
        "thigh": style["thigh"][0] * w * 0.5, "thigh_end": style["thigh"][1] * w * 0.5,
        "knee": style["calf"][0] * w * 0.5, "calf": style["calf"][1] * w * 0.5, "ankle": style["calf"][2] * w * 0.5,
        "foot": style["boot_w"] * w * 0.5, "foot_tall": style["boot_w"] * w * 0.5 * 0.62,
    }


def derive_anatomy(resolved, rig):
    """The construction landmarks for one resolved profile on one rig contract.

    Raises ``ValueError`` when the profile and rig cannot make a shoulder: the
    deltoid surface must sit outside the joint, and the mantle must clear the
    acromion below the head. A rig missing a bone raises ``KeyError``.
    """
    points = rig_points(rig)
    sizes = body_sizes(resolved["style"], resolved["cheek_width_m"])
    neck_z = points["Neck"][0][2]
    head_z = points["Head"][0][2]
    shoulders, pelvis = {}, {}
    for side, sign in (("L", 1.0), ("R", -1.0)):
        gh = points["UpperArm." + side][0]
        span = sizes["shoulders"]
        if span <= abs(gh[0]):
            raise ValueError("shoulder span %.3f m does not clear the %s joint at %.3f m" % (span, side, abs(gh[0])))
        acromion = (gh[0] + sign * ACROMION_LATERAL_OF_GH_M, gh[1], gh[2] + ACROMION_ABOVE_GH_M)
        neck_root = (sign * sizes["neck"] * NECK_ROOT_OF_NECK, gh[1] - 0.02, acromion[2] + MANTLE_RISE_M)
        centre = (gh[0], gh[1], gh[2] - DELTOID_BELOW_GH_M)
        radii = (acromion[2] - centre[2], max(sizes["arm"] * DELTOID_DEPTH_OF_ARM, sizes["chest_d"] * 0.62))
        axilla = (gh[0] - sign * 0.03, gh[1], gh[2] - AXILLA_BELOW_GH_M)
        tail = points["UpperArm." + side][1]
        underside = tuple(gh[i] + (tail[i] - gh[i]) * DELTOID_HANDOFF for i in range(3))
        shoulders[side] = ShoulderLandmarks(
            chest_anchor=points["Chest"][0], neck_base=points["Neck"][0],
            clavicle_start=points["Shoulder." + side][0], clavicle_end=acromion,
            gh_center=gh, acromion=acromion, deltoid_center=centre,
            deltoid_outer_extent=(sign * span, gh[1], centre[2]), deltoid_underside=underside,
            deltoid_radii=radii,
            trap_ridge=(neck_root, acromion), axilla=axilla,
            axilla_front=(axilla[0], axilla[1] - AXILLA_FOLD_M, axilla[2]),
            axilla_back=(axilla[0], axilla[1] + AXILLA_FOLD_M, axilla[2]),
            socket_z=(axilla[2], (axilla[2] + acromion[2]) * 0.5, acromion[2]),
        )
        hip = points["UpperLeg." + side][0]
        pelvis[side] = PelvisLandmarks(
            hip=hip, iliac_z=hip[2] + ILIAC_ABOVE_HIP_M,
            glute=(hip[0] * 0.85, hip[1] + GLUTE_BEHIND_HIP_M, hip[2] - 0.05),
            groin=(0.0, hip[1] - 0.04, hip[2] - GROIN_BELOW_HIP_M),
        )
    mantle_top = shoulders["L"].acromion[2] + MANTLE_RISE_M
    if not neck_z < mantle_top < head_z:
        raise ValueError("mantle top %.3f m must sit between the neck root %.3f and the head %.3f" % (
            mantle_top, neck_z, head_z))
    return AnatomyLandmarks(
        sizes=MappingProxyType(sizes), shoulders=MappingProxyType(shoulders), pelvis=MappingProxyType(pelvis),
        neck_root=(sizes["neck"] * NECK_ROOT_OF_NECK, mantle_top), mantle_top_z=mantle_top,
    )


def trapezius_ridge_z(landmarks, x):
    """Height of the trapezius ridge at lateral distance ``|x|`` (neck root to
    acromion, linear). Outside that span there is no ridge: ``None``."""
    neck_x, top = landmarks.neck_root
    acromion = landmarks.shoulders["L"].acromion
    ax = abs(x)
    if not neck_x <= ax <= acromion[0]:
        return None
    t = (ax - neck_x) / (acromion[0] - neck_x)
    return top + (acromion[2] - top) * t


# --- Deformation regions: anatomy -> deform bones ------------------------------
#
# Anatomical regions (above) say what the body is made of; deformation regions
# say which vertices move together when a joint moves. The builder tags every
# vertex with one deformation region as it constructs it (authoring metadata,
# never runtime), and the region's affinity row says which WolfRig deform
# bones it rides and how much. ``{side}`` is the vertex's side. The rows are
# relationships calibrated against posed captures, not anatomical truth:
#
# - the girdle around the socket rides the clavicle (``Shoulder.*``) as well
#   as the arm, so the shoulder rises with the arm instead of the arm swinging
#   out of a static chest shell; the socket's top row sits above the joint, so
#   it rides mostly the clavicle (a large arm share drags it over the ridge
#   when the arm reaches forward, measured under the real full load);
# - the trapezius rides the chest near the neck and the clavicle toward the
#   acromion (``CLAVICLE_RIDGE_SHARE``, graded along the ridge);
# - the armpit and the pectoral/latissimus folds stay mostly with the chest
#   and give a little to the arm, so they stretch rather than tear.
#
# An empty row (``spine``, ``trapezius``) takes the height blend between spine
# bones (the trapezius adds its graded clavicle share); the transition regions
# fade toward that blend with distance from the socket.

DEFORM_REGIONS = {
    "spine": (),
    "trapezius": (),
    "acromial": (("Shoulder.{side}", 0.55), ("UpperArm.{side}", 0.15), ("Chest", 0.30)),
    "socket_side": (("Shoulder.{side}", 0.35), ("UpperArm.{side}", 0.45), ("Chest", 0.20)),
    "axilla": (("Chest", 0.55), ("UpperArm.{side}", 0.30), ("Shoulder.{side}", 0.15)),
    "pectoral": (("Chest", 0.75), ("Shoulder.{side}", 0.15), ("UpperArm.{side}", 0.10)),
    "latissimus": (("Chest", 0.75), ("Shoulder.{side}", 0.15), ("UpperArm.{side}", 0.10)),
    "deltoid": (("UpperArm.{side}", 0.70), ("Shoulder.{side}", 0.30)),
    "deltoid_outer": (("UpperArm.{side}", 0.88), ("Shoulder.{side}", 0.12)),
    "pelvis_opening": (("Hips", 0.45), ("UpperLeg.{side}", 0.55)),
    "glute": (("Hips", 0.65), ("UpperLeg.{side}", 0.35)),
    # The ring above the glute starts the thigh's share, so the clips' stance
    # (4° abduction, the lead thigh flexed 19°) spreads over five rings, not
    # three: concentrated, the weld band stretched 1.45× standing in guard.
    "hip_upper": (("Hips", 0.88), ("UpperLeg.{side}", 0.12)),
    "crotch": (("Hips", 0.50), ("UpperLeg.L", 0.25), ("UpperLeg.R", 0.25)),
}
# Which creation region bounds each deformation row. ``spine`` and
# ``trapezius`` are height blends across several creation regions, so they
# are not owned by one of them. A row may not name a bone its owner did not
# list as a candidate.
DEFORM_OWNED_BY = {
    "acromial": "shoulder", "socket_side": "shoulder", "axilla": "shoulder",
    "deltoid": "shoulder", "deltoid_outer": "shoulder",
    "pectoral": "chest", "latissimus": "back_upper",
    "pelvis_opening": "pelvis", "glute": "glute", "crotch": "pelvis", "hip_upper": "pelvis",
}
# Angular gradient around the joint for the deltoid cap rings: the upper-arm
# share on the ring's top (facing up, over the acromion) and on its underside
# (toward the axilla); the rest rides the clavicle. A cap ring's top sits above
# the joint, so a full arm share would swing it medially over the acromion on
# a raise and fold the shoulder top; the underside follows the arm.
DELTOID_GRADIENT = {"deltoid": (0.50, 0.85), "deltoid_outer": (0.72, 0.95)}
# Clavicle share at the acromion end of the trapezius ridge (zero at the neck).
CLAVICLE_RIDGE_SHARE = 0.6
# Transition regions fade to the spine blend between these distances from the
# socket centre (m). The fade ends short of the sternum and spine: the mantle
# rings there are close together, and a sliver of clavicle on them folds the
# upper chest when the girdle lifts (measured under the real full load).
TRANSITION_FADE_M = (0.08, 0.16)


def region_affinity(region, side, upness=None):
    """The deform-bone row for ``region`` on ``side`` ("L" / "R"). For a
    deltoid region, ``upness`` (-1 underside .. 1 top, the vertex's direction
    from its ring centre against world up) selects along ``DELTOID_GRADIENT``."""
    if region not in DEFORM_REGIONS:
        raise ValueError("unknown deformation region %s" % region)
    if region in DELTOID_GRADIENT and upness is not None:
        top, under = DELTOID_GRADIENT[region]
        t = max(0.0, min(1.0, upness * 0.5 + 0.5))
        arm = under + (top - under) * t
        return (("UpperArm." + side, arm), ("Shoulder." + side, 1.0 - arm))
    return tuple((bone.format(side=side), share) for bone, share in DEFORM_REGIONS[region])


def validate_deform_ownership():
    """Problems when a deformation row names a bone its creation region did not allow."""
    problems = []
    blends = {"spine", "trapezius"}
    if set(DEFORM_OWNED_BY) | blends != set(DEFORM_REGIONS):
        problems.append("every deformation region is owned or is a spine blend")
    for region, owner_id in DEFORM_OWNED_BY.items():
        owner = REGION_BY_ID.get(owner_id)
        if owner is None:
            problems.append("%s names unknown creation region %s" % (region, owner_id))
            continue
        allowed = set(owner.deform_bones)
        for side in ("L", "R"):
            for bone, _share in region_affinity(region, side):
                if bone not in allowed:
                    problems.append("%s bone %s is outside %s candidates" % (region, bone, owner_id))
    return problems
