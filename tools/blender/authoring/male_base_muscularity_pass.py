"""Muscularity and torso volume pass on the male base master (CHARACTER-SOURCE-001).

Edits `art-src/blender/characters/male_base.blend` in place, once (the
pass id is recorded on the armature and a second run refuses). Topology,
vertex groups, weights, joints, bone lengths and the rest do not change.

1. The default moves to an Olympic weightlifter: the ribcage regains depth
   (front and back), the pectorals and the upper back become masses, the
   mantle (clavicle, trapezius, deltoid) fills so the shoulder flows into
   chest and back instead of a cap on a narrow torso, the upper arms gain
   girth, and the waist loses its corset. The pelvis is untouched.
2. The configuration keys: shape keys on the same topology for each
   parameter in `male_base.configuration.json` (mass, definition,
   upper-body emphasis, chest, shoulders, waist, arms, legs; each side of a
   signed parameter its own key). The default is the middle of the range.
   The keys stay in the master; the export bakes a configuration's mix.

Run: blender --background --factory-startup --python tools/blender/authoring/male_base_muscularity_pass.py
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402

import body_fields  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
MASTER = os.path.join(ROOT, "art-src", "blender", "characters", "male_base.blend")
PASSES = "riposte_authoring_passes"
PASS_ID = "muscularity_torso_volume"

## The default, relative to the bootstrap (chest 0.41 m wide and 0.252 m
## deep, waist 0.307 m). Chest depth about +22 % (about 0.7 of its width, a
## lifter's ribcage), upper back +19 %; the
## pelvis (z <= 0.92) unchanged. The core is a lifter's: waist breadth +12 %,
## the obliques and lats +16 % and the upper chest +8 % into the mantle, so the
## torso fills the girdle instead of hanging under shoulder caps, and the
## waist is defined, not pinched (+3-5 % alone left the corset).
WEIGHTLIFTER = {
    "torso": (
        (0.80, 1.00, 1.00, 1.00),
        (0.92, 1.00, 1.00, 1.00),
        (1.00, 1.08, 1.05, 1.05),
        (1.06, 1.12, 1.10, 1.10),
        (1.14, 1.16, 1.14, 1.14),
        (1.22, 1.16, 1.22, 1.18),
        (1.30, 1.12, 1.24, 1.20),
        (1.38, 1.08, 1.18, 1.18),
        (1.46, 1.05, 1.09, 1.11),
        (1.54, 1.00, 1.00, 1.00),
    ),
    "pec": (0.014, 1.27, 0.06, 0.085, 0.06),
    "traps": (0.016, 0.11, 0.05, 1.45, 0.04),
    "limbs": {
        "Shoulder": ((0.0, 1.08), (1.0, 1.10)),
        "UpperArm": ((0.0, 1.09), (0.3, 1.07), (0.7, 1.06), (1.0, 1.03)),
        "Forearm": ((0.0, 1.04), (1.0, 1.00)),
        "Neck": ((0.0, 1.05), (1.0, 1.03)),
        "UpperLeg": ((0.0, 1.00), (0.3, 1.05), (1.0, 1.02)),
        "LowerLeg": ((0.0, 1.02), (0.3, 1.05), (1.0, 1.00)),
    },
}


def _torso(waist, chest, front, back, waist_depth=None):
    """Stations from a waist width, chest width and chest depth factor; the pelvis stays."""
    waist_depth = waist if waist_depth is None else waist_depth
    return (
        (0.80, 1.0, 1.0, 1.0),
        (0.92, 1.0, 1.0, 1.0),
        (1.06, waist, waist_depth, waist_depth),
        (1.18, (waist + chest) / 2, (waist_depth + front) / 2, (waist_depth + back) / 2),
        (1.30, chest, front, back),
        (1.46, 1.0 + (chest - 1.0) / 2, 1.0 + (front - 1.0) / 2, 1.0 + (back - 1.0) / 2),
        (1.56, 1.0, 1.0, 1.0),
    )


def _arms(upper, fore):
    """Girth in the biceps and triceps bellies; the deltoid at the top of the
    arm belongs to the shoulder keys (full girth from the socket stacks into
    the mantle and folds the arm's top when it rises)."""
    return {
        "UpperArm": ((0.0, 1.0 + (upper - 1.0) * 0.3), (0.35, upper), (0.7, upper), (1.0, 1.0 + (upper - 1.0) * 0.5)),
        "Forearm": ((0.0, fore), (1.0, 1.0 + (fore - 1.0) * 0.4)),
    }


def _legs(thigh, calf):
    return {
        "UpperLeg": ((0.0, 1.0), (0.3, thigh), (1.0, 1.0 + (thigh - 1.0) * 0.5)),
        "LowerLeg": ((0.0, 1.0 + (calf - 1.0) * 0.4), (0.3, calf), (1.0, 1.0 + (calf - 1.0) * 0.3)),
    }


## Each key is a field on the new default, at full weight.
KEYS = {
    ## Bodybuilder: chest depth, shoulder mass, arm circumference, back
    ## thickness and volume; still a waist.
    "mass_plus": {
        "torso": _torso(1.07, 1.10, 1.20, 1.20, 1.08),
        "pec": (0.018, 1.27, 0.06, 0.085, 0.06),
        "traps": (0.024, 0.11, 0.05, 1.45, 0.04),
        "limbs": {"Shoulder": ((0.0, 1.16), (1.0, 1.20)), "Neck": ((0.0, 1.16), (1.0, 1.12)),
                  **_arms(1.25, 1.16), **_legs(1.18, 1.12)},
    },
    ## Lean muscular: narrower waist, less girth everywhere, still athletic.
    "mass_minus": {
        "torso": _torso(0.90, 0.93, 0.86, 0.87, 0.90),
        "pec": (-0.008, 1.27, 0.06, 0.085, 0.06),
        "traps": (-0.010, 0.11, 0.05, 1.45, 0.04),
        "limbs": {"Shoulder": ((0.0, 0.90), (1.0, 0.90)), "Neck": ((0.0, 0.92), (1.0, 0.93)),
                  **_arms(0.85, 0.88), **_legs(0.87, 0.90)},
    },
    ## Definition: more defined sharpens the taper and the pectoral plane;
    ## softer fills the abdomen and blurs the taper. Mass is not definition.
    "definition_plus": {"torso": _torso(0.97, 1.0, 1.0, 1.0, 0.96), "pec": (0.004, 1.27, 0.06, 0.085, 0.06)},
    "definition_minus": {"torso": _torso(1.06, 1.01, 1.03, 1.02, 1.08), "pec": (-0.004, 1.27, 0.06, 0.085, 0.06)},
    ## Upper-body emphasis: girdle, chest and back against the waist.
    "upper_body_plus": {
        "torso": _torso(0.98, 1.04, 1.05, 1.06),
        "traps": (0.008, 0.11, 0.05, 1.45, 0.04),
        "limbs": {"Shoulder": ((0.0, 1.07), (1.0, 1.08)), **_arms(1.05, 1.02)},
    },
    "upper_body_minus": {
        "torso": _torso(1.01, 0.97, 0.96, 0.95),
        "traps": (-0.006, 0.11, 0.05, 1.45, 0.04),
        "limbs": {"Shoulder": ((0.0, 0.95), (1.0, 0.95)), **_arms(0.96, 0.98)},
    },
    "chest_plus": {"torso": _torso(1.0, 1.04, 1.10, 1.06), "pec": (0.008, 1.27, 0.06, 0.085, 0.06)},
    "chest_minus": {"torso": _torso(1.0, 0.97, 0.92, 0.95), "pec": (-0.005, 1.27, 0.06, 0.085, 0.06)},
    "shoulders_plus": {"traps": (0.012, 0.11, 0.05, 1.45, 0.04),
                       "limbs": {"Shoulder": ((0.0, 1.10), (1.0, 1.12)), "UpperArm": ((0.0, 1.06), (0.3, 1.0), (1.0, 1.0))}},
    "shoulders_minus": {"traps": (-0.008, 0.11, 0.05, 1.45, 0.04),
                        "limbs": {"Shoulder": ((0.0, 0.93), (1.0, 0.92)), "UpperArm": ((0.0, 0.96), (0.3, 1.0), (1.0, 1.0))}},
    "waist_plus": {"torso": _torso(1.08, 1.0, 1.0, 1.0, 1.08)},
    "waist_minus": {"torso": _torso(0.93, 1.0, 1.0, 1.0, 0.93)},
    "arms_plus": {"limbs": _arms(1.12, 1.10)},
    "arms_minus": {"limbs": _arms(0.90, 0.92)},
    "legs_plus": {"limbs": _legs(1.10, 1.08)},
    "legs_minus": {"limbs": _legs(0.92, 0.93)},
}


def main():
    bpy.ops.wm.open_mainfile(filepath=MASTER)
    body = bpy.data.objects["Body"]
    rig = body.parent
    done = json.loads(rig.get(PASSES, "[]"))
    if PASS_ID in done:
        raise SystemExit("RIPOSTE_PASS_ALREADY_APPLIED %s" % PASS_ID)
    if body.data.shape_keys is not None:
        raise SystemExit("RIPOSTE_PASS_REFUSED: the master already carries shape keys")
    rest = [v.co.copy() for v in body.data.vertices]
    default = body_fields.displaced(body, rig, WEIGHTLIFTER, rest)
    for vertex, p in zip(body.data.vertices, default):
        vertex.co = p
    body.shape_key_add(name="Basis", from_mix=False)
    for name, spec in KEYS.items():
        key = body.shape_key_add(name=name, from_mix=False)
        for point, p in zip(key.data, body_fields.displaced(body, rig, spec, default)):
            point.co = p
        key.value = 0.0
    rig[PASSES] = json.dumps(done + [PASS_ID])
    bpy.ops.wm.save_as_mainfile(filepath=MASTER, compress=True)
    print("RIPOSTE_PASS_APPLIED", PASS_ID, "keys", len(KEYS))


if __name__ == "__main__":
    main()
