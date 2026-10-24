"""Validate riposte.character_art JSON. The file is the only author of Wolf's
blocks, palette, display name, and body scale. This module checks the file.
It does not build a mesh and it does not apply the physics scale law.
"""

import json
import math
import os

SCHEMA = "riposte.character_art"
SCHEMA_VERSION = 1
SLOTS = ("skin", "hair", "fabric", "cloth", "fur", "leather", "metal", "side_accent")
WEARS = ("person", "hair", "clothes")
KINDS = ("prism", "box", "segment")
FACES = ("alive", "dead")

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
WOLF_PATH = os.path.join(ROOT, "game", "content", "characters", "wolf.character.json")


def load(path=WOLF_PATH):
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    problems = validate(data)
    if problems:
        raise ValueError("\n".join(problems))
    return data


def validate(data):
    problems = []
    if not isinstance(data, dict):
        return ["the art file is not an object"]
    if data.get("schema") != SCHEMA:
        problems.append("schema must be %s" % SCHEMA)
    if data.get("schema_version") != SCHEMA_VERSION:
        problems.append("schema_version must be %d" % SCHEMA_VERSION)
    scale = data.get("body_scale")
    if not isinstance(scale, (int, float)) or not math.isfinite(scale) or scale <= 0:
        problems.append("body_scale must be a positive finite number")
    name = data.get("display_name")
    if not isinstance(name, str) or not name.strip():
        problems.append("display_name is missing")
    for key in ("id", "fighter_id", "weapon_id", "handling_id"):
        if not isinstance(data.get(key), str) or not data[key]:
            problems.append("%s is missing" % key)
    frame = data.get("coordinate_frame")
    if frame != {"up": [0, 0, 1], "forward": [0, -1, 0], "left": [1, 0, 0], "units": "metres"}:
        problems.append("coordinate_frame is not the armature frame")
    _palette(data.get("palette"), "palette", problems)
    variants = data.get("variants")
    if not isinstance(variants, dict) or "ranger" not in variants or "training" not in variants:
        problems.append("variants must name ranger and training")
    else:
        for variant, body in variants.items():
            if not isinstance(body, dict):
                problems.append("variant %s is missing palette_overrides" % variant)
                continue
            overrides = body.get("palette_overrides", {})
            if not isinstance(overrides, dict):
                problems.append("variant %s is missing palette_overrides" % variant)
                continue
            _palette(overrides, "variant %s" % variant, problems)
            part_overrides = body.get("part_overrides", {})
            if not isinstance(part_overrides, dict):
                problems.append("variant %s part_overrides is not an object" % variant)
                continue
            for part_name, patch in part_overrides.items():
                if not isinstance(patch, dict):
                    problems.append("variant %s override %s is not an object" % (variant, part_name))
                elif "size" in patch and not _vec3(patch["size"]):
                    problems.append("variant %s override %s size is not a vector" % (variant, part_name))
    rig = data.get("rig")
    if not isinstance(rig, dict):
        problems.append("rig is missing")
        rig = {}
    parts = data.get("parts")
    if not isinstance(parts, list) or not parts:
        problems.append("parts must be a non-empty list")
        return problems
    names = []
    bones = set(rig.get("bones") or [])
    for part in parts:
        if not isinstance(part, dict):
            problems.append("a part is not an object")
            continue
        part_name = part.get("name")
        if not isinstance(part_name, str) or not part_name:
            problems.append("a part has no name")
            continue
        if part_name in names:
            problems.append("duplicate part %s" % part_name)
        names.append(part_name)
        if part.get("wear") not in WEARS:
            problems.append("%s has an unknown wear" % part_name)
        if part.get("kind") not in KINDS:
            problems.append("%s has an unknown kind" % part_name)
        if part.get("slot") not in SLOTS:
            problems.append("%s has an unknown slot" % part_name)
        if part.get("face", "alive") not in FACES:
            problems.append("%s has an unknown face" % part_name)
        bone = part.get("bone")
        if bones and bone not in bones:
            problems.append("%s binds to an unknown bone %s" % (part_name, bone))
        when = part.get("when", ["ranger", "training"])
        if not isinstance(when, list) or any(item not in ("ranger", "training") for item in when):
            problems.append("%s names an unknown variant" % part_name)
        _geometry(part, problems)
    accent = data.get("side_accent")
    if not isinstance(accent, dict):
        problems.append("side_accent is missing")
    else:
        color = accent.get("preview")
        if not _color(color):
            problems.append("side_accent.preview is not a 0-1 RGB triple")
        for piece in accent.get("pieces") or []:
            match = next((part for part in parts if isinstance(part, dict) and part.get("name") == piece), None)
            if match is None:
                problems.append("side_accent names a missing part %s" % piece)
            elif match.get("slot") != "side_accent":
                problems.append("%s is listed as a side accent but uses another slot" % piece)
    if rig:
        problems.extend(_chains(rig, [part for part in parts if isinstance(part, dict)]))
    if not problems:
        problems.extend(face_problems(data))
    alive = [part.get("name") for part in parts if isinstance(part, dict) and part.get("face", "alive") == "alive" and str(part.get("name", "")).startswith("Eye")]
    dead = [part.get("name") for part in parts if isinstance(part, dict) and part.get("face") == "dead"]
    if "Brow" not in names:
        problems.append("a Brow part is required")
    if "Eye.L" not in alive or "Eye.R" not in alive:
        problems.append("alive eyes Eye.L and Eye.R are required")
    if not any(str(item).startswith("DeadEye.L") for item in dead) or not any(str(item).startswith("DeadEye.R") for item in dead):
        problems.append("dead eyes need an X on each side")
    ## DeadEye rotation is around Blender Y (forward) so the X sits in the
    ## face plane (X right, Z up). Rotation around Z lays the bars in the
    ## ground plane and they read as eyebrow slashes.
    return problems


## Face clearance (ART-HEAD-002). The protected region is authored per
## character as fractions of its own head: `band` is the eye/brow band as a
## share of the head's height, `width` its half-width as a share of the head's
## radius, and `reach` how far in metres it extends in front of the nose. It
## spans from the head's centre forward, along the frame's forward axis (-Y).
## Hair and clothes may frame the face (temples, sides, the back) but no part
## of either may enter that region, in any variant.
FEATURES = ("Eye.L", "Eye.R", "Brow")
COVERING = ("hair", "clothes")


def face_region(data):
    clearance = data["face_clearance"]
    head = next(part for part in data["parts"] if part.get("name") == clearance["head"])
    center = head.get("center", [0.0, 0.0])
    radius = float(head["radius"])
    height = float(head["z1"]) - float(head["z0"])
    half = float(clearance["width"]) * radius
    nose = radius * float(head.get("depth_scale", 1.0))
    return (
        (center[0] - half, center[0] + half),
        (center[1] - nose - float(clearance["reach"]), center[1]),
        (float(head["z0"]) + float(clearance["band"][0]) * height, float(head["z0"]) + float(clearance["band"][1]) * height),
    )


def face_problems(data):
    clearance = data.get("face_clearance")
    if not isinstance(clearance, dict):
        return ["face_clearance is missing"]
    problems = []
    head = next((part for part in data["parts"] if part.get("name") == clearance.get("head")), None)
    if head is None or head.get("kind") != "prism":
        problems.append("face_clearance.head must name the prism head")
    band = clearance.get("band")
    if not (isinstance(band, list) and len(band) == 2 and all(isinstance(item, (int, float)) for item in band) and 0.0 <= band[0] < band[1] <= 1.0):
        problems.append("face_clearance.band must be two head-height fractions, low then high")
    width = clearance.get("width")
    if not isinstance(width, (int, float)) or not 0.0 < width <= 1.0:
        problems.append("face_clearance.width must be a head-radius fraction in (0, 1]")
    reach = clearance.get("reach")
    if not isinstance(reach, (int, float)) or not math.isfinite(reach) or reach <= 0.0:
        problems.append("face_clearance.reach must be a positive distance")
    if problems:
        return problems
    region = face_region(data)
    for name in FEATURES:
        feature = next((part for part in data["parts"] if part.get("name") == name), None)
        if feature is None or feature.get("kind") != "box" or not _inside(feature["at"], region):
            problems.append("face_clearance does not hold %s" % name)
    for variant in ("ranger", "training"):
        for part in data["parts"]:
            if part.get("wear") in COVERING and visible(part, variant) and _overlaps(_bounds(data, part, variant), region):
                problems.append("%s covers the face in %s" % (part["name"], variant))
    return problems


def clearance_self_check(path=WOLF_PATH):
    """The validator must reject a face-crossing fringe and accept temple hair."""
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    if face_problems(data):
        raise ValueError("the shipped character fails its own face clearance")
    lo, hi = face_region(data)[2]
    fringe = {"name": "SelfCheckFringe", "wear": "hair", "kind": "box", "bone": "Head", "slot": "hair", "size": [0.12, 0.05, 0.08], "at": [0.0, -0.11, (lo + hi) * 0.5]}
    temple = {"name": "SelfCheckTemple", "wear": "hair", "kind": "box", "bone": "Head", "slot": "hair", "size": [0.04, 0.06, 0.1], "at": [0.13, -0.02, (lo + hi) * 0.5]}
    data["parts"].append(fringe)
    if "SelfCheckFringe covers the face in ranger" not in face_problems(data):
        raise ValueError("a fringe over the eyes was not rejected")
    ## In front of the nose, inside the reach: depth, not just height.
    ahead = {"name": "SelfCheckAhead", "wear": "hair", "kind": "box", "bone": "Head", "slot": "hair", "size": [0.04, 0.02, 0.04], "at": [0.0, -0.14, (lo + hi) * 0.5]}
    data["parts"][-1] = ahead
    if "SelfCheckAhead covers the face in ranger" not in face_problems(data):
        raise ValueError("hair in front of the nose was not rejected")
    data["parts"][-1] = temple
    if face_problems(data):
        raise ValueError("temple hair beside the face was rejected")


def _inside(point, region):
    return all(region[axis][0] <= float(point[axis]) <= region[axis][1] for axis in range(3))


def _overlaps(bounds, region):
    return all(bounds[axis][0] < region[axis][1] - 1e-9 and bounds[axis][1] > region[axis][0] + 1e-9 for axis in range(3))


def _bounds(data, part, variant):
    """Axis-aligned bounds in the armature frame, conservative for rotations."""
    kind = part["kind"]
    if kind == "box":
        size = part_value(data, part, variant, "size")
        at = part["at"]
        rx, ry, rz = part.get("rotation", [0.0, 0.0, 0.0])
        corners = []
        for sx in (-0.5, 0.5):
            for sy in (-0.5, 0.5):
                for sz in (-0.5, 0.5):
                    corner = _rotate((sx * size[0], sy * size[1], sz * size[2]), rx, ry, rz)
                    corners.append(tuple(corner[axis] + at[axis] for axis in range(3)))
        return tuple((min(c[axis] for c in corners), max(c[axis] for c in corners)) for axis in range(3))
    if kind == "prism":
        center = part.get("center", [0.0, 0.0])
        reach = float(part["radius"]) * max(1.0, float(part.get("top_scale", 1.0)))
        depth = reach * float(part.get("depth_scale", 1.0))
        return ((center[0] - reach, center[0] + reach), (center[1] - depth, center[1] + depth), (float(part["z0"]), float(part["z1"])))
    pad = max(float(part["width"]), float(part["depth"])) * 0.5
    return tuple((min(part["a"][axis], part["b"][axis]) - pad, max(part["a"][axis], part["b"][axis]) + pad) for axis in range(3))


def _rotate(vector, rx, ry, rz):
    ## Same order as riposte_blocks.box: X @ Y @ Z applied to the vector.
    x, y, z = vector
    x, y = x * math.cos(rz) - y * math.sin(rz), x * math.sin(rz) + y * math.cos(rz)
    x, z = x * math.cos(ry) + z * math.sin(ry), -x * math.sin(ry) + z * math.cos(ry)
    y, z = y * math.cos(rx) - z * math.sin(rx), y * math.sin(rx) + z * math.cos(rx)
    return (x, y, z)


def palette_for(data, variant):
    colors = dict(data["palette"])
    overrides = data["variants"][variant].get("palette_overrides") or {}
    colors.update(overrides)
    return colors


def visible(part, variant):
    return variant in part.get("when", ["ranger", "training"])


def part_value(data, part, variant, key):
    overrides = data["variants"][variant].get("part_overrides") or {}
    if part["name"] in overrides and key in overrides[part["name"]]:
        return overrides[part["name"]][key]
    return part[key]


def _palette(colors, label, problems):
    if not isinstance(colors, dict):
        problems.append("%s is missing" % label)
        return
    for slot, body in colors.items():
        if slot not in SLOTS:
            problems.append("%s names an unknown slot %s" % (label, slot))
            continue
        if not isinstance(body, dict) or not _color(body.get("color")):
            problems.append("%s.%s color is not a 0-1 RGB triple" % (label, slot))


def _color(value):
    return (
        isinstance(value, list)
        and len(value) == 3
        and all(isinstance(channel, (int, float)) and math.isfinite(channel) and 0.0 <= channel <= 1.0 for channel in value)
    )


def _geometry(part, problems):
    name = part.get("name", "?")
    kind = part.get("kind")
    if kind == "prism":
        for key in ("sides", "radius", "z0", "z1"):
            if not isinstance(part.get(key), (int, float)) or not math.isfinite(part[key]):
                problems.append("%s is missing %s" % (name, key))
        if part.get("z1", 0) <= part.get("z0", 0):
            problems.append("%s prism has no height" % name)
        if part.get("sides", 0) < 3:
            problems.append("%s prism needs at least 3 sides" % name)
    elif kind == "box":
        if not _vec3(part.get("size")) or not _vec3(part.get("at")):
            problems.append("%s box needs size and at" % name)
    elif kind == "segment":
        if not _vec3(part.get("a")) or not _vec3(part.get("b")):
            problems.append("%s segment needs endpoints a and b" % name)
        if not isinstance(part.get("width"), (int, float)) or not isinstance(part.get("depth"), (int, float)):
            problems.append("%s segment needs width and depth" % name)


def _vec3(value):
    return isinstance(value, list) and len(value) == 3 and all(isinstance(item, (int, float)) and math.isfinite(item) for item in value)


def _chains(rig, parts):
    problems = []
    expected = {
        "UpperArm.L": _arm(rig, 1)[0:2],
        "Forearm.L": _arm(rig, 1)[1:3],
        "Hand.L": _arm(rig, 1)[2:4],
        "UpperArm.R": _arm(rig, -1)[0:2],
        "Forearm.R": _arm(rig, -1)[1:3],
        "Hand.R": _arm(rig, -1)[2:4],
    }
    by_name = {part["name"]: part for part in parts}
    for name, (start, end) in expected.items():
        part = by_name.get(name)
        if part is None:
            problems.append("missing limb %s" % name)
            continue
        if _far(part.get("a"), start) or _far(part.get("b"), end):
            problems.append("%s endpoints do not match the rig chain" % name)
    return problems


def _far(got, expect):
    if not _vec3(got):
        return True
    return any(abs(float(got[index]) - expect[index]) > 1e-6 for index in range(3))


def _arm(rig, side):
    shoulder_x = rig["shoulder"][0] * side
    shoulder = (shoulder_x, rig["shoulder"][1], rig["shoulder"][2])
    grip = (0.0, -(rig["grip_dominant"] if side < 0 else rig["grip_offhand"]), rig["blade_height"])
    delta = tuple(grip[index] - shoulder[index] for index in range(3))
    length = math.sqrt(sum(value * value for value in delta))
    unit = tuple(value / length for value in delta)
    wrist = tuple(grip[index] - unit[index] * rig["hand_length"] for index in range(3))
    reach = math.sqrt(sum((wrist[index] - shoulder[index]) ** 2 for index in range(3)))
    mid = tuple((shoulder[index] + wrist[index]) * 0.5 for index in range(3))
    bend = math.sqrt(max(rig["arm_segment"] ** 2 - (reach * 0.5) ** 2, 0.0))
    outward = (float(side), -0.30, -0.12)
    outward = _unit(outward)
    axis = tuple((wrist[index] - shoulder[index]) / reach for index in range(3))
    dot = sum(outward[index] * axis[index] for index in range(3))
    pole = _unit(tuple(outward[index] - axis[index] * dot for index in range(3)))
    elbow = tuple(mid[index] + pole[index] * bend for index in range(3))
    return shoulder, elbow, wrist, grip


def _unit(value):
    length = math.sqrt(sum(item * item for item in value))
    return tuple(item / length for item in value)
