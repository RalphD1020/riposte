"""Load a character-model profile and resolve its sliders.

A profile is a versioned JSON file. It describes a body. It does not move
WolfRig, export a GLB, or decide that a silhouette has been accepted.
"""

from __future__ import annotations

import json
from pathlib import Path

from .anatomy import resolve_controls, validate_controls
from .parameters import (
    ACCEPTED_CHEEK_WIDTH_M,
    ACCEPTED_HEAD_SCALE,
    ACCEPTED_SIDE_BLEND,
    BY_ID,
    SLIDERS,
)
from .pose import (
    ARM_DROP_FROM_HORIZONTAL_DEG,
    POSE_ID,
    a_pose_joints,
)

SCHEMA = "riposte.character_model"
VERSION = 1
PROFILES = Path(__file__).resolve().parents[1] / "profiles"
STUDY_ORDER = ("study_wow_heroic.json", "study_compact_chibi.json", "study_compact_hybrid.json")


def load_profile(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    problems = validate(data)
    if problems:
        raise ValueError("%s: %s" % (path, "; ".join(problems)))
    return resolve(data)


def load_studies():
    return tuple(load_profile(PROFILES / name) for name in STUDY_ORDER)


def validate(data):
    problems = []
    if not isinstance(data, dict):
        return ["profile must be an object"]
    if data.get("schema") != SCHEMA:
        problems.append("schema must be %s" % SCHEMA)
    if data.get("version") != VERSION:
        problems.append("version must be %s" % VERSION)
    if data.get("status") not in ("study", "pending"):
        problems.append("status must be study or pending until a person accepts a silhouette")
    if data.get("pose") != POSE_ID:
        problems.append("pose must be %s" % POSE_ID)
    for key in ("id", "label", "title"):
        if not isinstance(data.get(key), str) or not data[key]:
            problems.append("%s is required" % key)
    sliders = data.get("sliders")
    if not isinstance(sliders, dict):
        return problems + ["sliders must be an object"]
    unknown = sorted(set(sliders) - set(BY_ID))
    if unknown:
        problems.append("unknown sliders: %s" % ", ".join(unknown))
    missing = sorted(set(BY_ID) - set(sliders))
    if missing:
        problems.append("missing sliders: %s" % ", ".join(missing))
    for slider_id, value in sliders.items():
        slider = BY_ID.get(slider_id)
        if slider is None or isinstance(value, bool) or not isinstance(value, (int, float)):
            continue
        if not slider.holds(float(value)):
            problems.append(
                "%s=%s is outside %s..%s" % (slider_id, value, slider.minimum, slider.maximum)
            )
    if "upper_arm" in sliders and "upper_arm_end" in sliders:
        if sliders["upper_arm_end"] > sliders["upper_arm"]:
            problems.append("upper arm grows toward the elbow")
    if "forearm" in sliders and "forearm_end" in sliders:
        if sliders["forearm_end"] > sliders["forearm"]:
            problems.append("forearm grows toward the wrist")
    if "thigh" in sliders and "thigh_end" in sliders:
        if sliders["thigh_end"] > sliders["thigh"]:
            problems.append("thigh grows toward the knee")
    if "calf_belly" in sliders and "calf_knee" in sliders and "calf_ankle" in sliders:
        if sliders["calf_belly"] < sliders["calf_knee"] or sliders["calf_belly"] < sliders["calf_ankle"]:
            problems.append("calf belly is not the fullest part of the lower leg")
    problems += validate_controls(data.get("controls"))
    return problems


def resolve(data):
    sliders = {key: float(data["sliders"][key]) for key in BY_ID}
    chest = sliders["chest_mass"]
    waist = chest * sliders["waist_taper"]
    head_width = sliders["head_width"]
    crown = sliders["crown_fullness"]
    side_blend = sliders["side_blend"]
    accepted_head = (
        abs(head_width - 1.0) < 1e-9
        and abs(crown - 1.0) < 1e-9
        and abs(side_blend - ACCEPTED_SIDE_BLEND) < 1e-9
    )
    head_kw = None
    if not accepted_head:
        head_kw = {
            "width_scale": ACCEPTED_HEAD_SCALE * head_width,
            "depth_scale": ACCEPTED_HEAD_SCALE,
            "side_blend": side_blend,
            "crown_x": crown,
        }
    return {
        "id": data["id"],
        "label": data["label"],
        "title": data["title"],
        "status": data["status"],
        "pose": data["pose"],
        "sliders": sliders,
        "controls": resolve_controls(data.get("controls")),
        "head_kw": head_kw,
        "cheek_width_m": ACCEPTED_CHEEK_WIDTH_M * head_width,
        "style": {
            "title": data["title"],
            "shoulders": sliders["shoulder_breadth"],
            "chest": chest,
            "depth": sliders["chest_depth"],
            "waist": waist,
            "pelvis": sliders["hip_breadth"],
            "neck": sliders["neck"],
            "arm": (sliders["upper_arm"], sliders["upper_arm_end"]),
            "fore": (sliders["forearm"], sliders["forearm_end"]),
            "thigh": (sliders["thigh"], sliders["thigh_end"]),
            "calf": (sliders["calf_knee"], sliders["calf_belly"], sliders["calf_ankle"]),
            "boot_w": sliders["boot_volume"],
            "shaft": sliders["boot_shaft"],
            "hand": sliders["hand_size"],
        },
    }


def self_check():
    studies = load_studies()
    male = load_profile(PROFILES / "male_base.json")
    if male["status"] != "pending":
        raise SystemExit("male base is a starting mannequin, not an accepted silhouette")
    if tuple(study["label"] for study in studies) != ("A", "B", "C"):
        raise SystemExit("studies must be A, B, C in that order")
    if any(study["status"] == "accepted" for study in studies):
        raise SystemExit("a study profile cannot mark itself accepted")
    defaults = {slider.id: slider.default for slider in SLIDERS}
    pending = {
        "schema": SCHEMA,
        "version": VERSION,
        "id": "check",
        "label": "M",
        "title": "check",
        "status": "pending",
        "pose": POSE_ID,
        "sliders": defaults,
    }
    if validate(pending):
        raise SystemExit("defaults are not a valid profile: %s" % validate(pending))
    first = resolve(pending)
    if resolve(pending) != first:
        raise SystemExit("resolve is not repeatable")
    rejected = dict(pending)
    rejected["status"] = "accepted"
    if not validate(rejected):
        raise SystemExit("accepted status must be refused until a person records it")
    over = dict(pending)
    over["sliders"] = dict(defaults)
    over["sliders"]["shoulder_breadth"] = 9.0
    if not validate(over):
        raise SystemExit("a slider past its maximum must be refused")
    unknown = dict(pending)
    unknown["sliders"] = dict(defaults)
    unknown["sliders"]["grip_z"] = 1.0
    if not validate(unknown):
        raise SystemExit("a control that is not a slider must be refused")
    if set(first["controls"].values()) != {1.0}:
        raise SystemExit("regional controls must default to the accepted shape (1.0)")
    for controls, why in (({"muscularity": 1.05}, "global muscularity must stay disabled"),
                          ({"lat_flare": 2.0}, "a regional control past its range must be refused"),
                          ({"bulk": 1.0}, "an unknown regional control must be refused")):
        if not validate(dict(pending, controls=controls)):
            raise SystemExit(why)
    landmarks = {
        "shoulder_x": 0.265, "shoulder_z": 1.37, "hip_x": 0.12, "hip_z": 0.89,
        "upper_arm": 0.358, "forearm": 0.30, "hand": 0.06,
        "thigh": 0.50, "shin": 0.31, "foot": 0.16,
    }
    left = a_pose_joints(landmarks, "L")
    right = a_pose_joints(landmarks, "R")
    if left["shoulder"][0] != -right["shoulder"][0] or left["hip"][0] != -right["hip"][0]:
        raise SystemExit("A-pose is not mirrored")
    if abs(left["elbow"][1]) > 1e-9 or abs(left["knee"][0] - left["hip"][0]) > 1e-9:
        raise SystemExit("A-pose arm leaves the coronal plane or the leg is not straight")
    drop = _drop_degrees(left["shoulder"], left["elbow"])
    if abs(drop - ARM_DROP_FROM_HORIZONTAL_DEG) > 1e-6:
        raise SystemExit("arm drop is %s, not %s" % (drop, ARM_DROP_FROM_HORIZONTAL_DEG))
    reach = _distance(left["shoulder"], left["elbow"])
    if abs(reach - landmarks["upper_arm"]) > 1e-9:
        raise SystemExit("A-pose changed the upper-arm length")
    heroic = studies[0]["style"]
    if abs(heroic["waist"] / heroic["chest"] - studies[0]["sliders"]["waist_taper"]) > 1e-9:
        raise SystemExit("waist does not follow the taper slider")
    if studies[0]["head_kw"] is not None or studies[2]["head_kw"] is not None:
        raise SystemExit("A and C must keep the accepted head")
    if studies[1]["head_kw"] is None:
        raise SystemExit("B is the study whose head is allowed to widen")
    print("RIPOSTE_MODEL_OK", len(studies), "studies", len(SLIDERS), "sliders")


def _drop_degrees(shoulder, elbow):
    import math
    horizontal = math.hypot(elbow[0] - shoulder[0], elbow[1] - shoulder[1])
    return math.degrees(math.atan2(-(elbow[2] - shoulder[2]), horizontal))


def _distance(a, b):
    return sum((a[index] - b[index]) ** 2 for index in range(3)) ** 0.5


if __name__ == "__main__":
    self_check()
