"""Validate and compile riposte.character_art JSON.

One document describes a person. `compile` turns body dimensions into named
anchors and anchor references into metres. The fighter builder and the crowd
builder both emit that result; neither one invents a head, a limb, or a boot.

Schema 2 replaced schema 1's absolute segment endpoints (`a`, `b`) with
`from` / `to` anchors and added `body`. The two shipped files were migrated
with the compiler. There is no schema 1 reader.

`body_scale` is the physics scale. This module checks that it is a positive
number and does not multiply a mesh by it.
"""

import copy
import json
import math
import os

SCHEMA = "riposte.character_art"
SCHEMA_VERSION = 2
SLOTS = ("skin", "hair", "fabric", "cloth", "fur", "leather", "metal", "side_accent", "face")
WEARS = ("person", "hair", "clothes", "beard")
KINDS = ("prism", "box", "segment", "clump", "dome")
FACES = ("alive", "dead")

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
WOLF_PATH = os.path.join(ROOT, "game", "content", "characters", "wolf.character.json")


def linear_channel(value):
    """sRGB 0-1 to the linear base color the builder writes. One conversion."""
    value = float(value)
    if value <= 0.04045:
        return value / 12.92
    return ((value + 0.055) / 1.055) ** 2.4


def linear_color(color):
    return tuple(linear_channel(channel) for channel in color)


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
    role = data.get("role", "fighter")
    if role not in ("fighter", "spectator"):
        problems.append("role must be fighter or spectator")
    if role == "fighter":
        for key in ("id", "fighter_id", "weapon_id", "handling_id"):
            if not isinstance(data.get(key), str) or not data[key]:
                problems.append("%s is missing" % key)
    elif not isinstance(data.get("id"), str) or not data.get("id"):
        problems.append("id is missing")
    frame = data.get("coordinate_frame")
    fighter_frame = {"up": [0, 0, 1], "forward": [0, -1, 0], "left": [1, 0, 0], "units": "metres"}
    spectator_frame = {"up": [0, 0, 1], "forward": [0, 1, 0], "left": [1, 0, 0], "units": "metres"}
    if frame != (spectator_frame if role == "spectator" else fighter_frame):
        problems.append("coordinate_frame is not the armature frame")
    _palette(data.get("palette"), "palette", problems)
    variants = data.get("variants")
    expected = ("bald", "crop", "bun", "fringe") if data.get("role") == "spectator" else ("ranger", "training")
    if not isinstance(variants, dict) or any(name not in variants for name in expected):
        problems.append("variants must name %s" % ", ".join(expected))
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
    problems.extend(_body(data))
    problems.extend(_silhouette(data))
    if role == "spectator":
        problems.extend(_poses(data))
    rig = data.get("rig")
    if role != "spectator" and not isinstance(rig, dict):
        problems.append("rig is missing")
    if not isinstance(rig, dict):
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
        when = part.get("when", list(expected))
        if not isinstance(when, list) or any(item not in expected for item in when):
            problems.append("%s names an unknown variant" % part_name)
        _geometry(part, problems)
        for key in ("from", "to", "on"):
            if key in part and (not isinstance(part.get(key), str) or not part.get(key)):
                problems.append("%s %s is not an anchor name" % (part_name, key))
    accent = data.get("side_accent")
    if data.get("role") == "spectator":
        accent = None
    elif not isinstance(accent, dict):
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
    alive = [part.get("name") for part in parts if isinstance(part, dict) and part.get("face", "alive") == "alive" and str(part.get("name", "")).startswith("Eye")]
    dead = [part.get("name") for part in parts if isinstance(part, dict) and part.get("face") == "dead"]
    if "Brow" not in names:
        problems.append("a Brow part is required")
    if "Eye.L" not in alive or "Eye.R" not in alive:
        problems.append("alive eyes Eye.L and Eye.R are required")
    if data.get("role") != "spectator" and (not any(str(item).startswith("DeadEye.L") for item in dead) or not any(str(item).startswith("DeadEye.R") for item in dead)):
        problems.append("dead eyes need an X on each side")
    ## DeadEye rotation is around Blender Y (forward) so the X sits in the
    ## face plane (X right, Z up). Rotation around Z lays the bars in the
    ## ground plane and they read as eyebrow slashes.
    if problems:
        return problems
    pose_names = list(data["poses"]) if role == "spectator" else [None]
    for pose in pose_names:
        try:
            compiled = compile(data, pose)
        except (KeyError, TypeError, ValueError) as exc:
            problems.append("could not compile %s: %s" % (pose or "rest", exc))
            continue
        label = pose or "rest"
        for item in face_problems(compiled):
            problems.append("%s: %s" % (label, item))
        for item in hair_problems(compiled):
            problems.append("%s: %s" % (label, item))
        if role != "spectator":
            problems.extend(_chains(compiled))
    return problems


def compile(data, pose=None):
    """A copy whose parts are in metres. Anchors resolve, a clothing shell
    becomes a second segment, and `body_scale` is left untouched."""
    role = data.get("role", "fighter")
    if role == "spectator" and pose is None:
        pose = "seated"
    points = anchors(data, pose)
    compiled = copy.deepcopy(data)
    _apply_silhouette(compiled)
    parts = []
    for part in compiled["parts"]:
        shell = part.get("shell")
        placed = _place(part, points, compiled)
        placed.pop("shell", None)
        parts.append(placed)
        if not isinstance(shell, dict):
            continue
        extra = copy.deepcopy(placed)
        extra["name"] = part["name"] + ".Shell"
        extra["slot"] = shell["slot"]
        extra["wear"] = shell.get("wear", "clothes")
        pad = float(shell["pad"])
        extra["width"] = float(part["width"]) + pad
        extra["depth"] = float(part["depth"]) + pad
        if "width_to" in part:
            extra["width_to"] = float(part["width_to"]) + pad
        if "depth_to" in part:
            extra["depth_to"] = float(part["depth_to"]) + pad
        if "bevel" in shell:
            extra["bevel"] = shell["bevel"]
        parts.append(extra)
    names = [part["name"] for part in parts]
    if len(names) != len(set(names)):
        raise ValueError("compiled part names collide")
    compiled["parts"] = parts
    return compiled


def anchors(data, pose=None):
    """Named points derived from `body` and, for a spectator, one baked pose.
    Left is +X, matching `coordinate_frame.left`. A part hangs off these names
    instead of repeating the metres."""
    if data.get("role") == "spectator":
        return _spectator_anchors(data, pose or "seated")
    return _fighter_anchors(data)


def _fighter_anchors(data):
    body = data["body"]
    rig = data["rig"]
    lead = data.get("lead_foot", "R")
    out = {
        "root": (0.0, 0.0, 0.0),
        "root.tail": (0.0, 0.0, float(body["root_tail"])),
        "hips": (0.0, 0.0, float(body["hips_z"])),
        "hips.top": (0.0, 0.0, float(body["hips_top"])),
        "spine": (0.0, 0.0, float(body["spine_z"])),
        "spine.top": (0.0, 0.0, float(body["spine_top"])),
        "chest": (0.0, 0.0, float(body["chest_z"])),
        "chest.top": (0.0, 0.0, float(body["chest_top"])),
        "neck": (0.0, 0.0, float(body["neck_z"])),
        "head.base": (0.0, 0.0, float(body["head_z"])),
        "head.bone": (0.0, 0.0, float(body["head_top"])),
    }
    for side, tag in ((1, "L"), (-1, "R")):
        shoulder, elbow, wrist, grip = _arm_points(data, side)
        suffix = "." + tag
        out["collar" + suffix] = (shoulder[0] * float(body["collar_share"]), 0.0, shoulder[2])
        out["shoulder" + suffix] = shoulder
        out["elbow" + suffix] = elbow
        out["wrist" + suffix] = wrist
        out["grip" + suffix] = grip
        out["bracer" + suffix] = _lerp(elbow, wrist, float(body["bracer_t"]))
        out["accent" + suffix] = _lerp(elbow, wrist, float(body["accent_bracer_t"]))
        foot_y = -float(rig["lead_foot_forward"]) if tag == lead else float(rig["rear_foot_back"])
        x = float(body["hip_x"]) * side
        out["hip" + suffix] = (x, foot_y * float(body["hip_y_share"]), float(body["hip_z"]))
        out["knee" + suffix] = (x, foot_y + float(body["knee_y_bias"]), float(body["knee_z"]))
        out["ankle" + suffix] = (x, foot_y, float(body["ankle_z"]))
        out["shin" + suffix] = (x, foot_y, float(body["shin_z"]))
        out["toe" + suffix] = (x, foot_y + float(body["toe_y_bias"]), float(body["toe_z"]))
        out["foot" + suffix] = (x, foot_y + float(body["boot_y_bias"]), float(body["boot_z"]))
    return out


def _spectator_anchors(data, pose_name):
    body = data["body"]
    pose = data["poses"][pose_name]
    out = {
        "head.base": (0.0, 0.0, float(body["head_z"])),
        "head.crown": (0.0, 0.0, float(body["head_z"]) + float(body["head_height"])),
    }
    for name in ("pelvis", "chest", "tunic", "hem", "panel", "collar", "belt", "neck"):
        point = body[name]
        out[name] = (float(point[0]), float(point[1]), float(point[2]))
    pairs = {
        "hip": (float(body["hip_x"]), float(body["hip_y"]), float(body["hip_z"])),
        "knee": (float(body["hip_x"]), float(body["knee_y"]), float(body["knee_z"])),
        "ankle": (float(body["hip_x"]), float(body["ankle_y"]), float(body["ankle_z"])),
        "foot": (float(body["hip_x"]), float(body["foot_y"]), float(body["foot_z"])),
        "cuff": (float(body["hip_x"]), float(body["cuff_y"]), float(body["cuff_z"])),
        "shoulder": (float(body["shoulder_x"]), float(body["shoulder_y"]), float(body["shoulder_z"])),
        "elbow": tuple(float(item) for item in pose["elbow"]),
        "wrist": tuple(float(item) for item in pose["wrist"]),
    }
    for name, point in pairs.items():
        out[name + ".L"] = point
        out[name + ".R"] = (-point[0], point[1], point[2])
    ox, oy, oz = (float(item) for item in pose["hand_offset"])
    fraction = float(body["bracer_t"])
    for tag, sign in (("L", 1.0), ("R", -1.0)):
        elbow = out["elbow." + tag]
        wrist = out["wrist." + tag]
        out["bracer." + tag] = _lerp(elbow, wrist, fraction)
        out["hand." + tag] = (wrist[0] + ox * sign, wrist[1] + oy, wrist[2] + oz)
    return out


def _apply_silhouette(data):
    """Copy one profile's masses onto the parts that name them.

    The helper that builds a prism or a limb does not know which character
    it is. Chest, waist, neck, hand, and boot sizes live here, once, and
    both skins of a character read the same mass.
    """
    silhouette = data.get("silhouette")
    if not isinstance(silhouette, dict):
        return
    masses = silhouette.get("masses")
    if not isinstance(masses, dict):
        raise ValueError("silhouette.masses is missing")
    for part in data["parts"]:
        key = part.get("mass")
        if not key:
            continue
        spec = masses.get(key)
        if not isinstance(spec, dict):
            raise ValueError("%s names an unknown silhouette mass %s" % (part.get("name"), key))
        for field, value in spec.items():
            part[field] = copy.deepcopy(value) if isinstance(value, list) else value


def _place(part, points, data):
    if part.get("radius_source") == "head":
        part["radius"] = float(data["body"]["head_radius"])
    if part.get("kind") == "segment":
        part["a"] = list(points[part["from"]])
        part["b"] = list(points[part["to"]])
        return part
    anchor = part.get("on")
    if not anchor:
        return part
    origin = points[anchor]
    kind = part["kind"]
    if kind == "box":
        offset = part.get("at", [0.0, 0.0, 0.0])
        part["at"] = _add(offset, origin)
    elif kind == "prism":
        part["z0"] = float(part["z0"]) + origin[2]
        part["z1"] = float(part["z1"]) + origin[2]
        center = part.get("center", [0.0, 0.0])
        part["center"] = [float(center[0]) + origin[0], float(center[1]) + origin[1]]
    elif kind == "dome":
        part["rings"] = [[float(ring[0]) + origin[2], *ring[1:]] for ring in part["rings"]]
        if "apex" in part:
            part["apex"] = _add(part["apex"], origin)
        center = part.get("center", [0.0, 0.0])
        part["center"] = [float(center[0]) + origin[0], float(center[1]) + origin[1]]
    elif kind == "clump":
        part["points"] = [_add(point, origin) for point in part["points"]]
        ## A variant's point override is the same anchor-local shape. Lift it
        ## with the part, or the training sweep builds at the origin.
        for variant in data.get("variants", {}).values():
            if not isinstance(variant, dict):
                continue
            patch = (variant.get("part_overrides") or {}).get(part.get("name"))
            if isinstance(patch, dict) and isinstance(patch.get("points"), list):
                patch["points"] = [_add(point, origin) for point in patch["points"]]
    return part


def _add(point, origin):
    return [float(point[index]) + float(origin[index]) for index in range(3)]


def _lerp(start, end, fraction):
    return tuple((1.0 - fraction) * start[index] + fraction * end[index] for index in range(3))


def _body(data):
    body = data.get("body")
    if not isinstance(body, dict):
        return ["body is missing"]
    problems = []
    if data.get("role") == "spectator":
        scalars = (
            "head_z", "head_height", "head_radius", "shoulder_x", "shoulder_y", "shoulder_z",
            "hip_x", "hip_y", "hip_z", "knee_y", "knee_z", "ankle_y", "ankle_z",
            "foot_y", "foot_z", "cuff_y", "cuff_z", "bracer_t",
        )
        points = ("pelvis", "chest", "tunic", "hem", "panel", "collar", "belt", "neck")
    else:
        scalars = (
            "head_z", "head_top", "head_radius", "neck_z", "chest_z", "chest_top",
            "spine_z", "spine_top", "hips_z", "hips_top", "root_tail", "collar_share",
            "hip_x", "hip_z", "knee_z", "knee_y_bias", "hip_y_share", "ankle_z",
            "shin_z", "toe_z", "toe_y_bias", "bracer_t", "accent_bracer_t",
            "boot_y_bias", "boot_z",
        )
        points = ()
        if not _vec3(body.get("shoulder")):
            problems.append("body.shoulder is not a vector")
    for key in scalars:
        value = body.get(key)
        if not isinstance(value, (int, float)) or not math.isfinite(value):
            problems.append("body.%s must be a finite number" % key)
    for key in points:
        if not _vec3(body.get(key)):
            problems.append("body.%s is not a vector" % key)
    for key in ("bracer_t", "accent_bracer_t"):
        value = body.get(key)
        if isinstance(value, (int, float)) and not 0.0 < float(value) < 1.0:
            problems.append("body.%s must be between the two anchors" % key)
    radius = body.get("head_radius")
    if isinstance(radius, (int, float)) and not float(radius) > 0.0:
        problems.append("body.head_radius must be positive")
    return problems


def _poses(data):
    poses = data.get("poses")
    if not isinstance(poses, dict) or any(name not in poses for name in ("seated", "cheer")):
        return ["poses must name seated and cheer"]
    problems = []
    for name, pose in poses.items():
        if not isinstance(pose, dict):
            problems.append("pose %s is not an object" % name)
            continue
        for key in ("elbow", "wrist", "hand_offset"):
            if not _vec3(pose.get(key)):
                problems.append("pose %s %s is not a vector" % (name, key))
    return problems


## Face clearance (ART-HEAD-002). The protected region is authored per
## character as fractions of its own head: `band` is the eye/brow band as a
## share of the head's height, `width` its half-width as a share of the head's
## radius, and `reach` how far in metres it extends in front of the nose. It
## spans from the head's centre forward, along the frame's forward axis (-Y).
## Hair and clothes may frame the face (temples, sides, the back) but no part
## of either may enter that region, in any variant.
FEATURES = ("Eye.L", "Eye.R", "Brow")
COVERING = ("hair", "clothes", "beard")


def face_region(data):
    clearance = data["face_clearance"]
    head = next(part for part in data["parts"] if part.get("name") == clearance["head"])
    center = head.get("center", [0.0, 0.0])
    radius = float(head["radius"])
    height = float(head["z1"]) - float(head["z0"])
    half = float(clearance["width"]) * radius
    nose = radius * float(head.get("depth_scale", 1.0))
    reach = float(clearance["reach"])
    forward = float(data.get("coordinate_frame", {}).get("forward", [0, -1, 0])[1])
    if forward >= 0.0:
        depth = (center[1], center[1] + nose + reach)
    else:
        depth = (center[1] - nose - reach, center[1])
    return (
        (center[0] - half, center[0] + half),
        depth,
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
    for variant in _variant_names(data):
        for part in data["parts"]:
            if part.get("wear") in COVERING and visible(part, variant, data) and _covers(data, part, variant, region):
                problems.append("%s covers the face in %s" % (part["name"], variant))
    return problems


def rig_contract(data):
    """Bone ends the combat clips already key. An authored mesh binds to these.
    It does not move them."""
    points = anchors(data)
    rig = data["rig"]

    def xyz(name):
        return [round(float(value), 6) for value in points[name]]

    rows = [
        ("Root", "root", "root.tail", None),
        ("Hips", "hips", "hips.top", "Root"),
        ("Spine", "spine", "spine.top", "Hips"),
        ("Chest", "chest", "chest.top", "Spine"),
        ("Neck", "neck", "head.base", "Chest"),
        ("Head", "head.base", "head.bone", "Neck"),
    ]
    bones = []
    for name, head, tail, parent in rows:
        bones.append({"name": name, "parent": parent, "head": xyz(head), "tail": xyz(tail)})
    blade = float(rig["blade_height"])
    bones.insert(1, {
        "name": "SwordMount",
        "parent": "Root",
        "head": [0.0, 0.0, blade],
        "tail": [0.0, -0.3, blade],
        "rotation_mode": "QUATERNION",
    })
    for tag in ("L", "R"):
        bones.extend((
            {"name": "Shoulder." + tag, "parent": "Chest", "head": xyz("collar." + tag), "tail": xyz("shoulder." + tag)},
            {"name": "UpperArm." + tag, "parent": "Shoulder." + tag, "head": xyz("shoulder." + tag), "tail": xyz("elbow." + tag)},
            {"name": "Forearm." + tag, "parent": "UpperArm." + tag, "head": xyz("elbow." + tag), "tail": xyz("wrist." + tag)},
            {"name": "Hand." + tag, "parent": "Forearm." + tag, "head": xyz("wrist." + tag), "tail": xyz("grip." + tag)},
            {"name": "UpperLeg." + tag, "parent": "Hips", "head": xyz("hip." + tag), "tail": xyz("knee." + tag)},
            {"name": "LowerLeg." + tag, "parent": "UpperLeg." + tag, "head": xyz("knee." + tag), "tail": xyz("ankle." + tag)},
            {"name": "Foot." + tag, "parent": "LowerLeg." + tag, "head": xyz("ankle." + tag), "tail": xyz("toe." + tag)},
        ))
    return {
        "id": data["id"],
        "facing": "blender -Y becomes Godot +Z",
        "body_scale_does_not_scale_mesh": True,
        "bones": bones,
    }


def clearance_self_check(path=WOLF_PATH):
    """The validator must reject a face-crossing fringe and accept temple hair."""
    with open(path, "r", encoding="utf-8") as handle:
        raw = json.load(handle)
    ## Geometry checks run on compiled metres. The file stores anchors.
    data = compile(raw)
    if face_problems(data):
        raise ValueError("the shipped character fails its own face clearance")
    lo, hi = face_region(data)[2]
    fringe = {"name": "SelfCheckFringe", "wear": "hair", "kind": "box", "bone": "Head", "slot": "hair", "size": [0.12, 0.05, 0.08], "at": [0.0, -0.11, (lo + hi) * 0.5]}
    beside = face_region(data)[0][1] + 0.04
    temple = {"name": "SelfCheckTemple", "wear": "hair", "kind": "box", "bone": "Head", "slot": "hair", "size": [0.04, 0.06, 0.1], "at": [beside, -0.02, (lo + hi) * 0.5]}
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
    wool = linear_color([32.0 / 255.0, 36.0 / 255.0, 40.0 / 255.0])
    if abs(wool[0] - 0.01444) > 1.0e-4 or abs(wool[2] - 0.02122) > 1.0e-4:
        raise ValueError("sRGB #202428 did not linearize through the one helper")
    shipped_hair = hair_problems(data)
    if shipped_hair:
        raise ValueError("the shipped character fails its hair\n" + "\n".join(shipped_hair))
    floating = json.loads(json.dumps(data))
    lid = next(part for part in floating["parts"] if part.get("name") == "HeadSkin")
    cap = next(part for part in floating["parts"] if part.get("name") == "ScalpDome")
    cap["rings"] = [[float(lid["z1"]) + 0.05, *ring[1:]] for ring in cap["rings"]]
    if not any("floats" in item or "gap" in item for item in hair_problems(floating)):
        raise ValueError("a dome sitting above the skull was not rejected")
    thin = json.loads(json.dumps(data))
    next(part for part in thin["parts"] if part.get("name") == "ScalpDome")["radius"] = 0.02
    if not any("scalp" in item or "narrower" in item for item in hair_problems(thin)):
        raise ValueError("a dome narrower than the skull was not rejected")
    spectator = os.path.join(os.path.dirname(path), "spectator.character.json")
    with open(spectator, "r", encoding="utf-8") as handle:
        crowd = json.load(handle)
    buried = compile(crowd)
    cap = next(part for part in buried["parts"] if part.get("name") == "HairCap")
    cap["rings"] = [[ring[0], 0.2, ring[2] if len(ring) > 2 else 0.0, ring[3] if len(ring) > 3 else 0.0] for ring in cap["rings"]]
    if not any("inside the skull" in item for item in hair_problems(buried)):
        raise ValueError("a cap buried in the skull was not rejected")
    crowd_problems = validate(crowd)
    if crowd_problems:
        raise ValueError("spectator\n" + "\n".join(crowd_problems))
    _compiled_self_check(raw, crowd)
    _joint_self_check(raw, crowd)
    crowd_source = os.path.join(os.path.dirname(__file__), "bootstrap", "build_crowd.py")
    with open(crowd_source, "r", encoding="utf-8") as handle:
        source = handle.read()
    for banned in ("def _limb", "def _segment", "def _head", "def _face", "def _cap", "def _bun"):
        if banned in source:
            raise ValueError("crowd builder still constructs %s" % banned)
    contract_path = os.path.join(os.path.dirname(path), "wolf.rig-contract.json")
    with open(contract_path, "r", encoding="utf-8") as handle:
        stored = json.load(handle)
    if stored.get("bones") != rig_contract(raw)["bones"]:
        raise ValueError("the rig contract drifted from the landmarks")


def _joint_self_check(wolf, crowd):
    """Wolf and the crowd share the overlap helper and keep their own numbers.
    The hand stops at the grip."""
    def part(data, name):
        return next(item for item in data["parts"] if item.get("name") == name)

    hand = part(wolf, "Hand.L")
    if float((hand.get("joint_overlap") or {}).get("to", 0.0)) != 0.0:
        raise ValueError("the grip end of the hand overlaps")
    arm = part(wolf, "UpperArm.L")
    crowd_arm = part(crowd, "UpperArm.L")
    if float(crowd_arm["width"]) != 0.06:
        raise ValueError("the crowd arm took Wolf's width")
    if arm.get("joint_overlap") == crowd_arm.get("joint_overlap"):
        raise ValueError("the crowd copied Wolf's joint overlap")
    wolf_overlap = arm.get("joint_overlap") or {}
    if float(wolf_overlap.get("from", 0.0)) <= 0.0 or float(wolf_overlap.get("to", 0.0)) <= 0.0:
        raise ValueError("Wolf's upper arm does not overlap its joints")
    crowd_overlap = crowd_arm.get("joint_overlap") or {}
    if float(crowd_overlap.get("from", 0.0)) <= 0.0 or float(crowd_overlap.get("to", 0.0)) <= 0.0:
        raise ValueError("the crowd arm does not overlap its joints")


def _compiled_self_check(wolf, crowd):
    """The compiled metres are the old authored metres, and an anchor move
    carries the parts that hang on it. Physics scale does not."""
    rest = compile(wolf)
    points = anchors(wolf)
    upper = next(part for part in rest["parts"] if part["name"] == "UpperArm.L")
    if _far(upper["a"], list(points["shoulder.L"])) or _far(upper["b"], list(points["elbow.L"])):
        raise ValueError("the compiled left arm left the guard")
    bracer = next(part for part in rest["parts"] if part["name"] == "Bracer.L")
    if _far(bracer["a"], list(points["bracer.L"])):
        raise ValueError("the compiled bracer left the forearm")
    boot = next(part for part in rest["parts"] if part["name"] == "Boot.L")
    if _far(boot["at"], list(points["foot.L"])):
        raise ValueError("the compiled boot left the foot")
    cuff = next(part for part in rest["parts"] if part["name"] == "BootCuff.L")
    if _far(cuff["at"], list(points["shin.L"])):
        raise ValueError("the compiled cuff left the shin")
    head = next(part for part in rest["parts"] if part["name"] == "HeadSkin")
    if float(head["z0"]) > float(wolf["body"]["head_z"]) + 1e-9 or abs(float(head["radius"]) - float(wolf["body"]["head_radius"])) > 1e-9:
        raise ValueError("the compiled head left its radius or its base")
    scaled = copy.deepcopy(wolf)
    scaled["body_scale"] = 2.0
    scaled_head = next(part for part in compile(scaled)["parts"] if part["name"] == "HeadSkin")
    if abs(float(scaled_head["z0"]) - float(head["z0"])) > 1e-12:
        raise ValueError("body_scale moved the mesh")
    taller = copy.deepcopy(wolf)
    taller["body"]["shoulder"] = [0.2, 0.0, 1.42]
    moved = compile(taller)
    moved_arm = next(part for part in moved["parts"] if part["name"] == "UpperArm.L")
    moved_hip = next(part for part in moved["parts"] if part["name"] == "UpperLeg.L")
    still_hip = next(part for part in rest["parts"] if part["name"] == "UpperLeg.L")
    if abs(moved_arm["a"][2] - 1.42) > 1e-9 or _far(moved_hip["a"], still_hip["a"]):
        raise ValueError("a shoulder change did not stay on the arm")
    for name in ("BeardVolume", "BeardCheekVolume.L", "BeardCheekVolume.R"):
        if not any(part["name"] == name and part.get("wear") == "beard" for part in crowd["parts"]):
            raise ValueError("the spectator beard is missing %s" % name)
    seated = compile(crowd, "seated")
    cheered = compile(crowd, "cheer")
    seated_elbow = next(part for part in seated["parts"] if part["name"] == "Forearm.L")
    cheer_elbow = next(part for part in cheered["parts"] if part["name"] == "Forearm.L")
    if not _far(seated_elbow["a"], cheer_elbow["a"]):
        raise ValueError("seated and cheer built the same arm")
    seated_hip = next(part for part in seated["parts"] if part["name"] == "Thigh.L")
    cheer_hip = next(part for part in cheered["parts"] if part["name"] == "Thigh.L")
    if _far(seated_hip["a"], cheer_hip["a"]) or _far(seated_hip["b"], cheer_hip["b"]):
        raise ValueError("a cheer moved the seated legs")
    if not any(part["name"].endswith(".Shell") and part["slot"] == "fabric" for part in seated["parts"]):
        raise ValueError("the seated limbs have no cloth shell")
    raised = copy.deepcopy(crowd)
    raised["body"]["head_z"] = float(crowd["body"]["head_z"]) + 0.02
    raised_body = compile(raised, "seated")
    eye = next(part for part in seated["parts"] if part["name"] == "Eye.L")
    raised_eye = next(part for part in raised_body["parts"] if part["name"] == "Eye.L")
    belt = next(part for part in seated["parts"] if part["name"] == "Belt")
    raised_belt = next(part for part in raised_body["parts"] if part["name"] == "Belt")
    cap = next(part for part in seated["parts"] if part["name"] == "HairCap")
    raised_cap = next(part for part in raised_body["parts"] if part["name"] == "HairCap")
    if abs(raised_eye["at"][2] - eye["at"][2] - 0.02) > 1e-9:
        raise ValueError("raising the head left the eyes behind")
    if abs(raised_cap["rings"][0][0] - cap["rings"][0][0] - 0.02) > 1e-9:
        raise ValueError("raising the head left the hair behind")
    if _far(raised_belt["at"], belt["at"]):
        raise ValueError("raising the head moved the belt")


## Marks that read as a mouth or nostrils. A future full beard is a jaw
## attachment with its own name, not these blocks.
FACE_BLOCKS = ("BeardMustache", "BeardJaw", "BeardCheek.L", "BeardCheek.R", "Mouth", "Nostril", "Lip")


## One dome. Ranger wears a bun. Training wears shoulder-length locks.
SCALP_DOME = "ScalpDome"
STYLE_LOCKS = {
    "ranger": ("HairCrown", "HairBun", "HairTemple.L", "HairTemple.R"),
    "training": ("HairFront", "HairLock.L", "HairLock.R", "HairRear"),
}
RETIRED_LOCKS = (
    "HairSweep", "HairNape", "HairFringe",
    "HairCropFront", "HairCropTemple.L", "HairCropTemple.R", "HairCropNape",
)
REJECTED_HAIR = ("HairCap", "HairCropCap", "HairFlow", "HairForelock", "HairSide", "HairSide.L", "HairSide.R", "HeadCrown")


def hair_problems(data):
    """A fighter's hair covers the flat pentagon. A spectator crown still
    rejects a dome buried in the skull. A short wide clump is a plank.
    """
    problems = []
    for name in FACE_BLOCKS:
        if any(part.get("name") == name for part in data.get("parts", [])):
            problems.append("%s is a face block; stubble is paint and a full beard is a later jaw attachment" % name)
    for part in data.get("parts", []):
        if not isinstance(part, dict) or part.get("kind") != "clump":
            continue
        points = part.get("points") or []
        widths = part.get("width") or []
        if len(points) >= 2 and widths:
            length = 0.0
            for start, end in zip(points, points[1:]):
                length += math.sqrt(sum((float(end[axis]) - float(start[axis])) ** 2 for axis in range(3)))
            wide = max(float(item) for item in widths)
            if wide >= 0.14 and length < wide * 1.2:
                problems.append("%s clump is a plank" % part.get("name"))
    if data.get("role") == "spectator":
        problems.extend(_spectator_shell(data))
        return problems
    problems.extend(_fighter_hair(data))
    return problems


def _fighter_hair(data):
    problems = []
    for name in REJECTED_HAIR:
        if any(part.get("name") == name for part in data.get("parts", [])):
            problems.append("%s does not belong on the flat skull" % name)
    for part in data.get("parts", []):
        if isinstance(part, dict) and part.get("wear") == "hair" and part.get("kind") == "dome" and part.get("name") != SCALP_DOME:
            problems.append("%s is not the shared scalp dome" % part.get("name"))
    head = next((part for part in data.get("parts", []) if part.get("name") == "HeadSkin"), None)
    if head is None or head.get("kind") != "prism":
        return problems + ["HeadSkin is missing"]
    problems.extend(_skull_problems(head, float(data["body"]["head_radius"])))
    dome = next((part for part in data.get("parts", []) if part.get("name") == SCALP_DOME), None)
    if dome is None:
        return problems + ["ScalpDome is missing"]
    problems.extend(_dome_problems(dome, head))
    dome_bounds = _bounds(data, dome, "ranger") if dome.get("kind") == "dome" and dome.get("rings") else None
    for variant in ("ranger", "training"):
        if not visible(dome, variant, data):
            problems.append("%s does not wear the scalp dome" % variant)
    for name in RETIRED_LOCKS:
        if any(part.get("name") == name for part in data["parts"]):
            problems.append("%s is the retired shared sweep" % name)
    for variant, locks in STYLE_LOCKS.items():
        other = "training" if variant == "ranger" else "ranger"
        for lock_name in locks:
            lock = next((part for part in data["parts"] if part.get("name") == lock_name), None)
            if lock is None or lock.get("wear") != "hair" or not visible(lock, variant, data):
                problems.append("%s is missing %s" % (variant, lock_name))
                continue
            if visible(lock, other, data):
                problems.append("%s is on both skins" % lock_name)
            elif dome_bounds is not None and not _overlaps(_bounds(data, lock, variant), dome_bounds):
                problems.append("%s does not meet the scalp dome" % lock_name)
    bun = next((part for part in data["parts"] if part.get("name") == "HairBun"), None)
    rear = next((part for part in data["parts"] if part.get("name") == "HairRear"), None)
    if bun is not None and rear is not None:
        if _clump_length(rear) <= _clump_length(bun) + 0.08:
            problems.append("training hair is not longer than the bun")
    return problems


def _skull_problems(head, radius):
    problems = []
    if int(head.get("sides", 0)) != 5:
        problems.append("the skull is not a pentagon")
    if abs(float(head.get("radius", 0.0)) - float(radius)) > 1e-6:
        problems.append("the skull left its radius")
    if float(head.get("depth_scale", 1.0)) < 0.9:
        problems.append("the skull is too shallow to read as a volume")
    if float(head["z1"]) - float(head["z0"]) < 0.12:
        problems.append("the skull has no face")
    bevel = float(head.get("bevel", 0.0))
    if bevel < 0.0 or bevel > 0.02:
        problems.append("the skull bevel is not restrained")
    if abs(float(head.get("spin", 0.0)) + math.pi / 2.0) > 1e-6:
        problems.append("the skull vertex is not pointing forward")
    return problems


def _dome_problems(dome, head):
    problems = []
    if dome.get("kind") != "dome" or dome.get("closure") != "face" or int(dome.get("sides", 0)) < 8:
        return ["ScalpDome is not a closed rounded crown"]
    if "apex" in dome:
        problems.append("ScalpDome closes on a point")
    rings = dome.get("rings") or []
    if len(rings) < 4:
        problems.append("ScalpDome needs a run of rings, not a lid")
        return problems
    scales = [float(ring[1]) for ring in rings]
    if scales[-1] >= scales[0] or max(scales) == scales[-1]:
        problems.append("ScalpDome does not close over the crown")
    z0 = float(rings[0][0])
    z1 = float(rings[-1][0])
    lid = float(head["z1"])
    if z0 > lid - 0.001:
        problems.append("ScalpDome floats above the skull")
    if z1 <= lid + 0.01:
        problems.append("ScalpDome does not continue over the crown")
    if float(dome["radius"]) * max(scales) < float(head["radius"]) * float(head.get("top_scale", 1.0)) * 0.98:
        problems.append("ScalpDome is narrower than the skull")
    for point in _scalp_samples(head):
        if not _dome_contains(dome, *point):
            problems.append("ScalpDome leaves the scalp uncovered")
            break
    return problems


def _dome_contains(part, x, y, z, slack=1.0e-4):
    rings = part["rings"]
    if z < float(rings[0][0]) - slack or z > float(rings[-1][0]) + slack:
        return False
    scale = float(rings[-1][1])
    for lower, upper in zip(rings, rings[1:]):
        z_low, z_high = float(lower[0]), float(upper[0])
        if z_low - slack <= z <= z_high + slack and z_high > z_low:
            span = (min(max(z, z_low), z_high) - z_low) / (z_high - z_low)
            scale = float(lower[1]) + (float(upper[1]) - float(lower[1])) * span
            break
    return _pentagon_contains(part, x, y, float(part["radius"]) * scale, slack)


def _pentagon_contains(part, x, y, radius, slack):
    depth = float(part.get("depth_scale", 1.0)) or 1.0
    center = part.get("center", [0.0, 0.0])
    lx = float(x) - float(center[0])
    ly = (float(y) - float(center[1])) / depth
    dist = math.hypot(lx, ly)
    if dist <= slack:
        return True
    sides = int(part["sides"])
    sector = math.tau / sides
    rel = (math.atan2(ly, lx) - float(part.get("spin", 0.0))) % sector
    half = math.pi / sides
    denom = math.cos(rel - half)
    if denom <= 1.0e-6:
        return False
    return dist <= radius * math.cos(half) / denom + slack


def _clump_length(part):
    return _clump_length_points(part.get("points") or [])


def _clump_length_points(points):
    length = 0.0
    for start, end in zip(points, points[1:]):
        length += math.sqrt(sum((float(end[axis]) - float(start[axis])) ** 2 for axis in range(3)))
    return length


def _scalp_samples(head):
    """Points on the flat top face. The dome has to contain them, so the
    pentagon cannot show from above."""
    radius = float(head["radius"]) * float(head.get("top_scale", 1.0))
    depth = float(head.get("depth_scale", 1.0))
    spin = float(head.get("spin", 0.0))
    center = head.get("center", [0.0, 0.0])
    z_top = float(head["z1"])
    points = [(float(center[0]), float(center[1]), z_top)]
    sides = int(head["sides"])
    for index in range(sides):
        angle = spin + math.tau * index / sides
        for scale in (0.55, 0.98):
            points.append((
                float(center[0]) + math.cos(angle) * radius * scale,
                float(center[1]) + math.sin(angle) * radius * depth * scale,
                z_top,
            ))
    return points


def _prism_contains(part, x, y, z, slack=1.0e-4):
    z0 = float(part["z0"])
    z1 = float(part["z1"])
    if z < z0 - slack or z > z1 + slack:
        return False
    span = z1 - z0
    t = 0.0 if span <= 0.0 else (min(max(z, z0), z1) - z0) / span
    radius = float(part["radius"]) * (1.0 + (float(part.get("top_scale", 1.0)) - 1.0) * t)
    depth = float(part.get("depth_scale", 1.0)) or 1.0
    center = part.get("center", [0.0, 0.0])
    lx = float(x) - float(center[0])
    ly = (float(y) - float(center[1])) / depth
    dist = math.hypot(lx, ly)
    if dist <= slack:
        return True
    sides = int(part["sides"])
    sector = math.tau / sides
    rel = (math.atan2(ly, lx) - float(part.get("spin", 0.0))) % sector
    half = math.pi / sides
    denom = math.cos(rel - half)
    if denom <= 1.0e-6:
        return False
    return dist <= radius * math.cos(half) / denom + slack


def _spectator_shell(data):
    """The crowd still wears a dome on its crown. The shell may not sit
    inside that skull. It is not asked to hug the cone: that rule was pulling
    fighter hair down onto a point the fighter no longer has."""
    problems = []
    skin = _crown_samples(data)
    if not skin:
        return problems
    for part in data.get("parts", []):
        if not isinstance(part, dict) or part.get("kind") != "dome" or part.get("wear") != "hair":
            continue
        thickness = float(part.get("thickness") or 0.0)
        if thickness <= 0.0:
            problems.append("%s hair cap has no thickness" % part.get("name"))
            continue
        radius = float(part["radius"])
        for ring in part["rings"]:
            outer = radius * float(ring[1])
            skull = _radius_at(skin, float(ring[0]))
            if outer < skull - 0.001:
                problems.append("%s is inside the skull at z %.3f" % (part.get("name"), float(ring[0])))
    return problems


def _crown_samples(data):
    head = next((part for part in data.get("parts", []) if part.get("name") == "HeadSkin"), None)
    crown = next((part for part in data.get("parts", []) if part.get("name") == "HeadCrown"), None)
    if head is None or crown is None:
        return []
    samples = [(float(head["z1"]), float(head["radius"]) * float(head.get("top_scale", 1.0)))]
    for ring in crown.get("rings", []):
        samples.append((float(ring[0]), float(crown["radius"]) * float(ring[1])))
    apex = crown.get("apex")
    if apex is not None:
        samples.append((float(apex[2]), 0.0))
    samples.sort()
    return samples


def _radius_at(samples, z):
    if z <= samples[0][0]:
        return samples[0][1]
    if z >= samples[-1][0]:
        return samples[-1][1]
    for (z0, r0), (z1, r1) in zip(samples, samples[1:]):
        if z0 <= z <= z1 and z1 > z0:
            return r0 + (r1 - r0) * ((z - z0) / (z1 - z0))
    return samples[-1][1]


def _inside(point, region):
    return all(region[axis][0] <= float(point[axis]) <= region[axis][1] for axis in range(3))


def _covers(data, part, variant, region):
    if part.get("kind") == "dome":
        for ring in part["rings"]:
            if _overlaps(_dome_ring_bounds(part, ring), region):
                return True
        if "apex" not in part:
            return False
        apex = part["apex"]
        return _overlaps(((apex[0], apex[0]), (apex[1], apex[1]), (apex[2], apex[2])), region)
    if part.get("kind") != "clump":
        return _overlaps(_bounds(data, part, variant), region)
    points = part_value(data, part, variant, "points")
    widths = part_value(data, part, variant, "width")
    depths = part_value(data, part, variant, "depth")
    for point, width, depth in zip(points, widths, depths):
        pad = 0.5 * max(float(width), float(depth))
        station = (
            (float(point[0]) - pad, float(point[0]) + pad),
            (float(point[1]) - pad, float(point[1]) + pad),
            (float(point[2]) - pad, float(point[2]) + pad),
        )
        if _overlaps(station, region):
            return True
    return False


def _dome_ring_bounds(part, ring):
    scale = float(ring[1])
    reach = float(part["radius"]) * scale
    depth = reach * float(part.get("depth_scale", 1.0))
    ox = float(ring[2]) if len(ring) > 2 else 0.0
    oy = float(ring[3]) if len(ring) > 3 else 0.0
    center = part.get("center", [0.0, 0.0])
    z = float(ring[0])
    return ((center[0] + ox - reach, center[0] + ox + reach), (center[1] + oy - depth, center[1] + oy + depth), (z, z))


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
    if kind == "clump":
        points = part_value(data, part, variant, "points")
        widths = part_value(data, part, variant, "width")
        depths = part_value(data, part, variant, "depth")
        xs, ys, zs = [], [], []
        for point, width, depth in zip(points, widths, depths):
            pad = 0.5 * max(float(width), float(depth))
            xs.extend((float(point[0]) - pad, float(point[0]) + pad))
            ys.extend((float(point[1]) - pad, float(point[1]) + pad))
            zs.extend((float(point[2]) - pad, float(point[2]) + pad))
        return ((min(xs), max(xs)), (min(ys), max(ys)), (min(zs), max(zs)))
    if kind == "dome":
        boxes = [_dome_ring_bounds(part, ring) for ring in part["rings"]]
        if "apex" in part:
            apex = part["apex"]
            boxes.append(((apex[0], apex[0]), (apex[1], apex[1]), (apex[2], apex[2])))
        return tuple((min(box[axis][0] for box in boxes), max(box[axis][1] for box in boxes)) for axis in range(3))
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


def _variant_names(data):
    if data.get("role") == "spectator":
        return ("bald", "crop", "bun", "fringe")
    return ("ranger", "training")


def visible(part, variant, data=None):
    default = list(_variant_names(data)) if data is not None else ["ranger", "training"]
    return variant in part.get("when", default)


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
        for key in ("sides", "z0", "z1"):
            if not isinstance(part.get(key), (int, float)) or not math.isfinite(part[key]):
                problems.append("%s is missing %s" % (name, key))
        _radius_source(part, problems)
        if part.get("z1", 0) <= part.get("z0", 0):
            problems.append("%s prism has no height" % name)
        if part.get("sides", 0) < 3:
            problems.append("%s prism needs at least 3 sides" % name)
    elif kind == "box":
        if part.get("mass"):
            pass
        elif not _vec3(part.get("size")):
            problems.append("%s box needs a size" % name)
        elif part.get("on"):
            if "at" in part and not _vec3(part.get("at")):
                problems.append("%s offset is not a vector" % name)
        elif not _vec3(part.get("at")):
            problems.append("%s box needs an at vector or an anchor" % name)
    elif kind == "segment":
        if not isinstance(part.get("from"), str) or not isinstance(part.get("to"), str):
            problems.append("%s segment needs from and to anchors" % name)
        if "a" in part or "b" in part:
            problems.append("%s segment stores endpoints; the anchors are the source" % name)
        if part.get("mass"):
            pass
        elif not isinstance(part.get("width"), (int, float)) or not isinstance(part.get("depth"), (int, float)):
            problems.append("%s segment needs width and depth" % name)
        elif float(part.get("width") or 0) <= 0.0 or float(part.get("depth") or 0) <= 0.0:
            problems.append("%s segment sizes must be positive" % name)
        for end in ("width_to", "depth_to"):
            if end in part and (not isinstance(part.get(end), (int, float)) or float(part[end]) <= 0.0):
                problems.append("%s %s must be a positive length" % (name, end))
        overlap = part.get("joint_overlap")
        if overlap is not None:
            if not isinstance(overlap, dict) or any(key not in ("from", "to") for key in overlap):
                problems.append("%s joint_overlap names from and to only" % name)
            else:
                for end in ("from", "to"):
                    value = overlap.get(end, 0.0)
                    if not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0.0:
                        problems.append("%s joint_overlap.%s must be a non-negative length" % (name, end))
                if str(part.get("to", "")).startswith("grip") and float(overlap.get("to", 0.0)) != 0.0:
                    problems.append("%s does not extend past the grip" % name)
        shell = part.get("shell")
        if shell is not None:
            if not isinstance(shell, dict) or shell.get("slot") not in SLOTS:
                problems.append("%s shell needs a material slot" % name)
            elif not isinstance(shell.get("pad"), (int, float)) or float(shell["pad"]) <= 0.0:
                problems.append("%s shell pad must be a positive thickness" % name)
            elif shell.get("wear", "clothes") not in WEARS:
                problems.append("%s shell has an unknown wear" % name)
    elif kind == "clump":
        points = part.get("points")
        widths = part.get("width")
        depths = part.get("depth")
        if not isinstance(points, list) or len(points) < 2 or not all(_vec3(point) for point in points):
            problems.append("%s clump needs at least two points" % name)
        elif not isinstance(widths, list) or not isinstance(depths, list) or len(widths) != len(points) or len(depths) != len(points):
            problems.append("%s clump width and depth must match its points" % name)
        elif any(not isinstance(item, (int, float)) or item <= 0.0 for item in list(widths) + list(depths)):
            problems.append("%s clump sizes must be positive" % name)
    elif kind == "dome":
        rings = part.get("rings")
        if not isinstance(part.get("sides"), (int, float)) or part.get("sides", 0) < 3:
            problems.append("%s dome needs at least 3 sides" % name)
        _radius_source(part, problems)
        if not isinstance(rings, list) or len(rings) < 2:
            problems.append("%s dome needs at least two rings" % name)
        elif any(
            not isinstance(ring, list) or len(ring) < 2 or not all(isinstance(item, (int, float)) and math.isfinite(item) for item in ring)
            for ring in rings
        ):
            problems.append("%s dome rings are z, scale, and an optional offset" % name)
        elif any(float(ring[1]) <= 0.0 for ring in rings):
            problems.append("%s dome scales must be positive" % name)
        closure = part.get("closure", "apex")
        if closure == "face":
            if "apex" in part:
                problems.append("%s closes on a face and has no apex" % name)
            if float(part.get("thickness") or 0.0) != 0.0:
                problems.append("%s face cap is a solid, not a shell" % name)
        elif closure != "apex":
            problems.append("%s has an unknown dome closure" % name)
        elif not _vec3(part.get("apex")):
            problems.append("%s dome needs an apex" % name)


def _silhouette(data):
    silhouette = data.get("silhouette")
    if silhouette is None:
        return []
    problems = []
    masses = silhouette.get("masses") if isinstance(silhouette, dict) else None
    if not isinstance(masses, dict) or not masses:
        return ["silhouette.masses is missing"]
    for name, spec in masses.items():
        if not isinstance(spec, dict) or not spec:
            problems.append("silhouette mass %s is empty" % name)
    for part in data.get("parts") or []:
        if not isinstance(part, dict):
            continue
        key = part.get("mass")
        if key and key not in masses:
            problems.append("%s names an unknown silhouette mass %s" % (part.get("name"), key))
    return problems


def _radius_source(part, problems):
    name = part.get("name", "?")
    if part.get("mass"):
        return
    if part.get("radius_source") == "head":
        if "radius" in part:
            problems.append("%s names both a radius and the head radius" % name)
        return
    if part.get("radius_source") not in (None,):
        problems.append("%s has an unknown radius source" % name)
    elif not isinstance(part.get("radius"), (int, float)) or float(part.get("radius") or 0) <= 0.0:
        problems.append("%s needs a radius" % name)


def _vec3(value):
    return isinstance(value, list) and len(value) == 3 and all(isinstance(item, (int, float)) and math.isfinite(item) for item in value)


def _chains(data):
    problems = []
    expected = {}
    for side, tag in ((1, "L"), (-1, "R")):
        shoulder, elbow, wrist, grip = _arm_points(data, side)
        expected["UpperArm." + tag] = (shoulder, elbow)
        expected["Forearm." + tag] = (elbow, wrist)
        expected["Hand." + tag] = (wrist, grip)
    by_name = {part["name"]: part for part in data["parts"]}
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


def _arm_points(data, side):
    rig = data["rig"]
    shoulder_at = data["body"]["shoulder"]
    shoulder_x = shoulder_at[0] * side
    shoulder = (shoulder_x, shoulder_at[1], shoulder_at[2])
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
