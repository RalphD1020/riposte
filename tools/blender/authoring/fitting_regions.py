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
    blender --background --factory-startup --python tools/blender/authoring/fitting_regions.py -- --foundation
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


## The head's sub-regions (the foundation's head object): windows in the head's
## construction chart (u = |x| / half-width, v = height fraction from its lowest point,
## d = depth fraction from its front), so a region is anatomy, not a vertex number; it is
## stored as the head's vertex indices, valid on every resolved head (one topology, morphed).
## (u range, v range, d range), each [low, high).
HEAD_SUBREGIONS = {
    "mouth": ((0.0, 0.20), (0.17, 0.245), (0.0, 0.30)),
    "upper_lip": ((0.0, 0.30), (0.245, 0.31), (0.0, 0.30)),
    "chin": ((0.0, 0.36), (-0.1, 0.17), (0.0, 0.40)),
    "jaw": ((0.36, 1.01), (-0.1, 0.30), (0.0, 0.62)),
    "cheek_low": ((0.30, 1.01), (0.30, 0.40), (0.0, 0.45)),
    "sideburn": ((0.80, 1.01), (0.40, 0.58), (0.30, 0.60)),
    "scalp": ((0.0, 1.01), (0.70, 1.1), (-0.1, 1.1)),
}


def head_subregions(head, attribute):
    """{sub-region: [head vertex index]} from the head's stored construction surface."""
    import numpy as np
    stored = head.data.attributes[attribute]
    co = np.array([tuple(a.vector) for a in stored.data])
    low, height = co[:, 2].min(), np.ptp(co[:, 2])
    half, front, depth = np.abs(co[:, 0]).max(), co[:, 1].min(), np.ptp(co[:, 1])
    u, v, d = np.abs(co[:, 0]) / half, (co[:, 2] - low) / height, (co[:, 1] - front) / depth
    out = {}
    for name, (us, vs, ds) in HEAD_SUBREGIONS.items():
        inside = (u >= us[0]) & (u < us[1]) & (v >= vs[0]) & (v < vs[1]) & (d >= ds[0]) & (d < ds[1])
        out[name] = [int(i) for i in np.nonzero(inside)[0]]
        if not out[name]:
            raise SystemExit("RIPOSTE_REGIONS: empty head sub-region %s" % name)
    return out


def region_of(index, weights):
    """The fitting region of one body vertex from its skin weights {bone: weight}."""
    shoulder = next((s for s in ("L", "R") if weights.get("Shoulder.%s" % s, 0.0) >= SHOULDER_SHARE), None)
    if shoulder:
        return "shoulder.%s" % shoulder
    dominant = max(weights, key=weights.get)
    region = next((r for r, spec in REGIONS.items() if dominant in spec[0]), None)
    if region is None and dominant.startswith("Shoulder."):
        region = "shoulder.%s" % dominant[-1]
    if region is None:
        raise SystemExit("RIPOSTE_REGIONS: vertex %d (dominant %s) has no region" % (index, dominant))
    return region


def document_of(base_id, fingerprint, members, notes, objects=None):
    empty = [r for r, v in members.items() if not v]
    if empty:
        raise SystemExit("RIPOSTE_REGIONS: empty regions %s" % empty)
    regions = {}
    for region, spec in REGIONS.items():
        regions[region] = {"bones": list(spec[1]), "physique": list(spec[2]), "neighbours": list(spec[3]),
                           "clips": list(spec[4]), "vertices": members[region]}
        if objects and region in objects:
            regions[region]["object"] = objects[region]
    return {"schema": "riposte.fitting_regions", "version": 1, "base": base_id, "topology_fingerprint": fingerprint,
            "clearance_m": CLEARANCE_M, "notes": notes, "regions": regions}


def write(document, path):
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(document, handle, indent=1, separators=(",", ": "))
        handle.write("\n")
    print("RIPOSTE_REGIONS", {r: len(v["vertices"]) for r, v in document["regions"].items()})


def main():
    if "--foundation" in sys.argv:
        return foundation_regions()
    bpy.ops.wm.open_mainfile(filepath=BASE)
    body = bpy.data.objects["Body"]
    names = {g.index: g.name for g in body.vertex_groups}
    head_island = set(character_assembly._head_island(body))
    members = {region: [] for region in REGIONS}
    for vertex in body.data.vertices:
        weights = {names[g.group]: g.weight for g in vertex.groups if g.weight > 0.0}
        members["head" if vertex.index in head_island else region_of(vertex.index, weights)].append(vertex.index)
    write(document_of("character.male_base", character_assembly.topology_fingerprint(body), members,
                      "Fitting regions are modeling and validation areas on the base topology, not bones. Derived from the base's weights by tools/blender/authoring/fitting_regions.py; regenerate after any retopology."),
          OUT)


def foundation_regions():
    """The default foundation's fitting regions (`male_base.foundation.regions.json`): on
    its body (`BodyV2`, the topology every configuration shares) from the weights it deforms
    with (`male_base_v2_variation.smoothed_weights`, the foundation's passes); the head is
    the separate head object (`HeadV2`), every vertex of it. Keyed to the foundation record's
    body fingerprint, the one `foundation.garment_target` checks garments against."""
    import numpy as np
    sys.path.insert(0, HERE)
    sys.path.insert(0, os.path.join(ROOT, "tools", "character_modeling"))
    import male_base_v2 as v2
    import male_base_v2_variation as mv
    from character_modeling import foundation
    module, document = v2.foundation_document()
    blender = os.path.dirname(v2.CHARACTERS)
    with open(foundation.path_of(document, "record", blender), encoding="utf-8") as handle:
        record = json.load(handle)
    bpy.ops.wm.open_mainfile(filepath=foundation.path_of(document, "source", blender))
    v2.apose()
    body, head = bpy.data.objects[v2.SCULPT], bpy.data.objects[v2.STUDY]
    if v2.fingerprint(body)["sha256"] != record["objects"][v2.SCULPT]["sha256"]:
        raise SystemExit("RIPOSTE_REGIONS: the foundation source does not match its record")
    raw = v2._transfer_weights([tuple(c) for c in mv._coords(body)])
    edges = np.array([tuple(e.vertices) for e in body.data.edges])
    weights = mv.smoothed_weights(raw, edges, len(body.data.vertices), document["resolution"]["rig_weight_smooth_iterations"])
    names = sorted(weights)
    table = np.stack([weights[n] for n in names], axis=1)
    members = {region: [] for region in REGIONS}
    members["head"] = list(range(len(head.data.vertices)))
    for index, row in enumerate(table):
        members[region_of(index, {names[j]: float(row[j]) for j in np.nonzero(row > 0.0)[0]})].append(index)
    out = document_of(document["id"], record["objects"][v2.SCULPT]["sha256"], members,
                      "The foundation's fitting regions: modeling and validation areas on its body topology (BodyV2), not bones; the head region is the head object (HeadV2), and its sub-regions (parent head) are windows of the head's construction chart stored as HeadV2 vertex indices, valid on every resolved head. Derived by tools/blender/authoring/fitting_regions.py --foundation from the weights the foundation deforms with; regenerate after any retopology or a new foundation record.",
                      {"head": v2.STUDY})
    out["head_topology_fingerprint"] = record["objects"][v2.STUDY]["sha256"]
    for name, vertices in head_subregions(head, v2.F0_ATTRIBUTE).items():
        out["regions"][name] = {"parent": "head", "object": v2.STUDY, "bones": ["Head"], "physique": [],
                                "neighbours": ["head"], "clips": ["idle", "death"], "vertices": vertices}
    from character_modeling import asset_library
    asset_library.refuse_overwrite(foundation.path_of(document, "regions", blender))
    write(out, foundation.path_of(document, "regions", blender))


if __name__ == "__main__":
    main()
