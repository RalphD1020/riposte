"""Derive the male base's anatomical fitting regions (`male_base.regions.json`).

A fitting region is a modeling and validation area on the base's topology, not
a bone: a garment occupies regions, and its vertices may be weighted to any of
the bones a region lists. Regions are keyed to the base's topology fingerprint
(`character_assembly.topology_fingerprint`); a retopology invalidates them, and
the assembly refuses a stale file. Each region records its vertex indices, the
bones that move it, the physique parameters that reshape it, its neighbours,
the clips that stress it, and per-category clearance ranges (metres from the
body surface) for `fitted`, `structured` and `loose` garments.

Membership is derived from the base's own weights (dominant bone; the shoulder
region is every vertex the clavicle moves), so it follows the authored skin
rather than a box drawn around it.

    blender --background --factory-startup --python tools/blender/authoring/fitting_regions.py
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))

import bpy  # noqa: E402

import character_assembly  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BASE = os.path.join(ROOT, "art-src", "blender", "characters", "male_base.blend")
OUT = os.path.join(ROOT, "art-src", "blender", "characters", "male_base.regions.json")
## The clavicle carries the shoulder region wherever it holds this much weight.
SHOULDER_SHARE = 0.10
CLEARANCE_M = {"fitted": [0.003, 0.02], "structured": [0.008, 0.05], "loose": [0.015, 0.12]}

## region id: (dominant bone families, bones that may influence it, physique parameters, neighbours, stressing clips)
REGIONS = {
    ## The head is the head island (HeadSkin); the neck rings below it ride Neck and Head.
    "head": ((), ("Head",), (), ("neck",), ("idle", "death")),
    "neck": (("Neck", "Head"), ("Neck", "Head", "Chest"), ("mass", "shoulders"), ("head", "upper_torso", "shoulder.L", "shoulder.R"), ("idle", "charge_support", "death")),
    "upper_torso": (("Chest",), ("Chest", "Spine", "Shoulder.L", "Shoulder.R", "Neck"), ("mass", "chest", "upper_body", "definition"), ("neck", "shoulder.L", "shoulder.R", "waist"), ("charge_support", "swing_support", "overswing", "dash_forward")),
    "waist": (("Spine",), ("Spine", "Chest", "Hips"), ("mass", "waist", "definition"), ("upper_torso", "pelvis"), ("dash_forward", "walk_forward", "death")),
    "pelvis": (("Hips",), ("Hips", "Spine", "UpperLeg.L", "UpperLeg.R"), ("mass",), ("waist", "upper_leg.L", "upper_leg.R"), ("walk_forward", "dash_forward", "death")),
}
for side in ("L", "R"):
    REGIONS.update({
        "shoulder.%s" % side: ((), ("Shoulder.%s" % side, "Chest", "UpperArm.%s" % side), ("mass", "shoulders", "upper_body"), ("upper_torso", "neck", "upper_arm.%s" % side), ("charge_support", "swing_support", "overswing")),
        "upper_arm.%s" % side: (("UpperArm.%s" % side,), ("UpperArm.%s" % side, "Shoulder.%s" % side, "Forearm.%s" % side), ("mass", "arms", "upper_body"), ("shoulder.%s" % side, "forearm.%s" % side), ("charge_support", "swing_support", "overswing")),
        "forearm.%s" % side: (("Forearm.%s" % side,), ("Forearm.%s" % side, "UpperArm.%s" % side, "Hand.%s" % side), ("mass", "arms"), ("upper_arm.%s" % side, "hand.%s" % side), ("charge_support", "swing_support")),
        "hand.%s" % side: (("Hand.%s" % side,), ("Hand.%s" % side, "Forearm.%s" % side), (), ("forearm.%s" % side,), ("charge_support",)),
        "upper_leg.%s" % side: (("UpperLeg.%s" % side,), ("UpperLeg.%s" % side, "Hips", "LowerLeg.%s" % side), ("mass", "legs"), ("pelvis", "lower_leg.%s" % side), ("walk_forward", "dash_forward", "death")),
        "lower_leg.%s" % side: (("LowerLeg.%s" % side,), ("LowerLeg.%s" % side, "UpperLeg.%s" % side, "Foot.%s" % side), ("mass", "legs"), ("upper_leg.%s" % side, "foot.%s" % side), ("walk_forward", "dash_forward")),
        "foot.%s" % side: (("Foot.%s" % side,), ("Foot.%s" % side, "LowerLeg.%s" % side), (), ("lower_leg.%s" % side,), ("walk_forward",)),
    })


def main():
    bpy.ops.wm.open_mainfile(filepath=BASE)
    body = bpy.data.objects["Body"]
    names = {g.index: g.name for g in body.vertex_groups}
    head_island = set(character_assembly._head_island(body))
    members = {region: [] for region in REGIONS}
    for vertex in body.data.vertices:
        weights = {names[g.group]: g.weight for g in vertex.groups if g.weight > 0.0}
        if vertex.index in head_island:
            members["head"].append(vertex.index)
            continue
        shoulder = next((s for s in ("L", "R") if weights.get("Shoulder.%s" % s, 0.0) >= SHOULDER_SHARE), None)
        if shoulder:
            members["shoulder.%s" % shoulder].append(vertex.index)
            continue
        dominant = max(weights, key=weights.get)
        region = next((r for r, spec in REGIONS.items() if dominant in spec[0]), None)
        if region is None and dominant.startswith("Shoulder."):
            region = "shoulder.%s" % dominant[-1]
        if region is None:
            raise SystemExit("RIPOSTE_REGIONS: vertex %d (dominant %s) has no region" % (vertex.index, dominant))
        members[region].append(vertex.index)
    document = {
        "schema": "riposte.fitting_regions",
        "version": 1,
        "base": "character.male_base",
        "topology_fingerprint": character_assembly.topology_fingerprint(body),
        "clearance_m": CLEARANCE_M,
        "notes": "Fitting regions are modeling and validation areas on the base topology, not bones. Derived from the base's weights by tools/blender/authoring/fitting_regions.py; regenerate after any retopology.",
        "regions": {
            region: {
                "bones": list(spec[1]),
                "physique": list(spec[2]),
                "neighbours": list(spec[3]),
                "clips": list(spec[4]),
                "vertices": members[region],
            }
            for region, spec in REGIONS.items()
        },
    }
    empty = [r for r, v in members.items() if not v]
    if empty:
        raise SystemExit("RIPOSTE_REGIONS: empty regions %s" % empty)
    with open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(document, handle, indent=1, separators=(",", ": "))
        handle.write("\n")
    print("RIPOSTE_REGIONS", {r: len(v) for r, v in members.items()})


if __name__ == "__main__":
    main()
