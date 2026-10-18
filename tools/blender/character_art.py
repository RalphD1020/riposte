"""Validate riposte.character_art JSON. The file is the only author of Wolf's
blocks, palette, display name, and body scale. This module checks the file.
It does not build a mesh and it does not apply the physics scale law.
"""

import json
import math
import os

SCHEMA = "riposte.character_art"
SCHEMA_VERSION = 1
SLOTS = ("skin", "hair", "fabric", "leather", "metal", "side_accent")
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
    alive = [part.get("name") for part in parts if isinstance(part, dict) and part.get("face", "alive") == "alive" and str(part.get("name", "")).startswith("Eye")]
    dead = [part.get("name") for part in parts if isinstance(part, dict) and part.get("face") == "dead"]
    if "Eye.L" not in alive or "Eye.R" not in alive:
        problems.append("alive eyes Eye.L and Eye.R are required")
    if not any(str(item).startswith("DeadEye.L") for item in dead) or not any(str(item).startswith("DeadEye.R") for item in dead):
        problems.append("dead eyes need an X on each side")
    return problems


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
