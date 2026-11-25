"""SKELETON-CAPTURE-001: the engine-neutral half of the skeleton sidecar every skeleton-bearing
character image carries (`<image>.skeleton.json`, written beside the PNG by
`tools/blender/inspect/skeleton_capture.py` in Blender and `game/tools/skeleton_capture.gd` in
Godot; boards carry `<board>.skeleton.json` with each cell's bones mapped into board pixels).

A sidecar records, for the exact frame the image shows: the camera (projection, transform), every
visible skeleton's bones (world position and rotation, the pixel each joint lands on, whether it is
in front of the camera and inside the frame) and derived arm readings, so a reviewer or a scorer
reads the pose from the image's own data instead of guessing it from pixels. No bpy here: the
schema and the derived readings are shared and self-checked by the game lint."""

import math

SCHEMA = "riposte.skeleton_capture"
VERSION = 1
SIDECAR_SUFFIX = ".skeleton.json"
BOARD_SUFFIX = ".skeleton.json"
## WolfRig's arm chain per side: shoulder joint (upper arm head), elbow, wrist.
ARM_BONES = {"R": ("UpperArm.R", "Forearm.R", "Hand.R"), "L": ("UpperArm.L", "Forearm.L", "Hand.L")}


def sidecar_path(image_path):
    """The sidecar beside an image: `<image without .png>.skeleton.json`."""
    stem = image_path[:-4] if image_path.lower().endswith(".png") else image_path
    return stem + SIDECAR_SUFFIX


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _length(a):
    return math.sqrt(_dot(a, a))


def _angle(a, b):
    la, lb = _length(a), _length(b)
    if la < 1e-9 or lb < 1e-9:
        return 0.0
    return math.degrees(math.acos(max(-1.0, min(1.0, _dot(a, b) / (la * lb)))))


def arm_readings(positions, up):
    """Per side present in `positions` (bone name -> world (x, y, z)), with `up` the world's unit
    up axis: elbow flexion (0 straight), upper-arm elevation from hanging (0) through horizontal
    (90), forearm pitch above horizontal, and the elbow's height above its shoulder and above its
    wrist (m). Frame-free apart from `up`, so Blender (Z up) and Godot (Y up) agree."""
    out = {}
    for side, (upper, fore, hand) in ARM_BONES.items():
        if upper not in positions or fore not in positions or hand not in positions:
            continue
        s, e, w = positions[upper], positions[fore], positions[hand]
        upper_vec, fore_vec = _sub(e, s), _sub(w, e)
        down = (-up[0], -up[1], -up[2])
        fore_len = _length(fore_vec)
        out[side] = {
            "elbow_flex_deg": round(180.0 - _angle(_sub(s, e), _sub(w, e)), 2),
            "upper_elevation_deg": round(_angle(upper_vec, down), 2),
            "forearm_pitch_deg": round(math.degrees(math.asin(max(-1.0, min(1.0, _dot(fore_vec, up) / fore_len)))) if fore_len > 1e-9 else 0.0, 2),
            "elbow_above_shoulder_m": round(_dot(_sub(e, s), up), 4),
            "elbow_above_wrist_m": round(_dot(_sub(e, w), up), 4),
        }
    return out


## Arm validation (refit supplement, 2026-11-22). Three severities: `hard` failures make a pose
## invalid (joint lengths changed - a stretched or compressed chain), `warning`s are provisional
## quality signals, never approvals or anatomical limits (elbow lift, level-forearm tolerance, upper-arm
## elevation, a straight or folded elbow); silhouette, HEMA credibility and readability stay visual
## review. Grip attachment, bend branch, penetration and IK correction need the weapon and the solver,
## so the probes add them. A level forearm in the long point or follow-through is fine: the elbow may
## sit a few centimetres above its wrist.
HEURISTICS = {
    "elbow_below_shoulder_m": -0.05,   # warning: elbow_above_shoulder_m must be <= this
    "elbow_above_wrist_max_m": 0.05,   # warning: elbow_above_wrist_m must be <= this (level forearm tolerated)
    "upper_elevation_max_deg": 90.0,   # warning
    "elbow_flex_min_deg": 15.0,        # warning
    "elbow_flex_max_deg": 140.0,       # warning
    "segment_length_tolerance": 0.02,  # hard: |posed / rest - 1| of upper arm and forearm
}


def _check(value, limit, ok, severity):
    return {"value": value, "limit": limit, "pass": bool(ok), "severity": severity}


def heuristics(arms, lengths=None):
    """Per arm the checks over `arm_readings` (and, with `lengths` = {side: {upper, fore, upper_rest,
    fore_rest}} in metres, the hard joint-length check), each {value, limit, pass, severity}, plus the
    arm's `verdict` ("pass" / "warning" / "fail") and `pass` (no hard failure)."""
    out = {}
    tol = HEURISTICS["segment_length_tolerance"]
    for side, r in arms.items():
        checks = {
            "elbow_below_shoulder": _check(r["elbow_above_shoulder_m"], HEURISTICS["elbow_below_shoulder_m"], r["elbow_above_shoulder_m"] <= HEURISTICS["elbow_below_shoulder_m"], "warning"),
            "elbow_not_above_wrist": _check(r["elbow_above_wrist_m"], HEURISTICS["elbow_above_wrist_max_m"], r["elbow_above_wrist_m"] <= HEURISTICS["elbow_above_wrist_max_m"], "warning"),
            "upper_arm_not_above_horizontal": _check(r["upper_elevation_deg"], HEURISTICS["upper_elevation_max_deg"], r["upper_elevation_deg"] <= HEURISTICS["upper_elevation_max_deg"], "warning"),
            "elbow_bent_not_folded": _check(r["elbow_flex_deg"], [HEURISTICS["elbow_flex_min_deg"], HEURISTICS["elbow_flex_max_deg"]],
                                            HEURISTICS["elbow_flex_min_deg"] <= r["elbow_flex_deg"] <= HEURISTICS["elbow_flex_max_deg"], "warning"),
        }
        seg = (lengths or {}).get(side)
        if seg and seg.get("upper_rest") and seg.get("fore_rest"):
            worst = max(abs(seg["upper"] / seg["upper_rest"] - 1.0), abs(seg["fore"] / seg["fore_rest"] - 1.0))
            checks["joint_lengths_preserved"] = _check(round(worst, 5), tol, worst <= tol, "hard")
        hard = any(not c["pass"] for c in checks.values() if c["severity"] == "hard")
        warn = any(not c["pass"] for c in checks.values() if c["severity"] == "warning")
        out[side] = dict(checks, verdict="fail" if hard else ("warning" if warn else "pass"), **{"pass": not hard})
    return out


def board_cell(sidecar, origin, scale):
    """A sidecar's skeletons mapped into a board cell: every pixel scaled by `scale` and offset by
    the cell's `origin` (x, y) in board pixels; world data unchanged."""
    cell = {"image": sidecar.get("image", {}), "camera": sidecar.get("camera", {}), "arms": sidecar.get("arms", {}),
            "heuristics": sidecar.get("heuristics", {}), "extra": sidecar.get("extra", {}), "skeletons": []}
    for skeleton in sidecar.get("skeletons", []):
        bones = []
        for bone in skeleton.get("bones", []):
            mapped = dict(bone)
            if bone.get("pixel") is not None:
                mapped["pixel"] = [round(origin[0] + bone["pixel"][0] * scale, 2), round(origin[1] + bone["pixel"][1] * scale, 2)]
            bones.append(mapped)
        cell["skeletons"].append({**skeleton, "bones": bones})
    return cell


def self_check():
    """A right arm hanging straight, then bent 90 degrees forward at the elbow, in a Z-up and a
    Y-up world: the readings must agree and match the construction."""
    for up, lift in (((0.0, 0.0, 1.0), lambda x, y, z: (x, y, z)), ((0.0, 1.0, 0.0), lambda x, y, z: (x, z, -y))):
        hanging = {"UpperArm.R": lift(-0.2, 0.0, 1.4), "Forearm.R": lift(-0.2, 0.0, 1.1), "Hand.R": lift(-0.2, 0.0, 0.85)}
        reading = arm_readings(hanging, up)["R"]
        assert abs(reading["elbow_flex_deg"]) < 1e-6 and abs(reading["upper_elevation_deg"]) < 1e-6, reading
        assert abs(reading["elbow_above_shoulder_m"] + 0.3) < 1e-9 and abs(reading["elbow_above_wrist_m"] - 0.25) < 1e-9, reading
        bent = {"UpperArm.R": lift(-0.2, 0.0, 1.4), "Forearm.R": lift(-0.2, 0.0, 1.1), "Hand.R": lift(-0.2, -0.25, 1.1)}
        reading = arm_readings(bent, up)["R"]
        assert abs(reading["elbow_flex_deg"] - 90.0) < 1e-6 and abs(reading["forearm_pitch_deg"]) < 1e-6, reading
    raised = heuristics({"R": {"elbow_above_shoulder_m": 0.06, "elbow_above_wrist_m": 0.2, "upper_elevation_deg": 106.0, "elbow_flex_deg": 105.0}})["R"]
    assert raised["pass"] and raised["verdict"] == "warning" and not raised["elbow_below_shoulder"]["pass"] and raised["elbow_bent_not_folded"]["pass"], raised
    level = heuristics({"L": {"elbow_above_shoulder_m": -0.2, "elbow_above_wrist_m": 0.03, "upper_elevation_deg": 55.0, "elbow_flex_deg": 45.0}})["L"]
    assert level["verdict"] == "pass", level
    stretched = heuristics({"R": {"elbow_above_shoulder_m": -0.2, "elbow_above_wrist_m": -0.1, "upper_elevation_deg": 40.0, "elbow_flex_deg": 60.0}},
                           {"R": {"upper": 0.30, "fore": 0.25, "upper_rest": 0.28, "fore_rest": 0.25}})["R"]
    assert stretched["verdict"] == "fail" and not stretched["pass"] and stretched["joint_lengths_preserved"]["severity"] == "hard", stretched
    cell = board_cell({"skeletons": [{"bones": [{"name": "Hand.R", "pixel": [100.0, 50.0]}, {"name": "Head", "pixel": None}]}]}, (300, 20), 0.5)
    assert cell["skeletons"][0]["bones"][0]["pixel"] == [350.0, 45.0] and cell["skeletons"][0]["bones"][1]["pixel"] is None, cell
    assert sidecar_path("a/b_front.png") == "a/b_front.skeleton.json"
    return True


if __name__ == "__main__":
    self_check()
    print("skeleton_capture_core self-check passed")
