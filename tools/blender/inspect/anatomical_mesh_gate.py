"""ART-ANATOMY-001 second layer in Blender: the deformed-mesh self-intersection gate.

Applies final skeleton poses (rest-relative per bone: quaternion x, y, z, w and translation in the
bone's rest frame - the form Godot's final pose maps to 1:1 on WolfRig, G2.h) to a staged blend's
armature, evaluates the skinned body AFTER the armature (and any later deform modifier), and
measures how deep arm skin sits inside the torso and inside the other arm: per checked part, the
dominant-weight vertices of the part, each tested for being inside the other region's deformed
(open) surface by majority ray parity, its depth the distance to that surface. The shoulder joint is not a defect
(only the distal half of the upper arm is tested against the torso) and the two palms on the grip
are expected contact (hand-hand is not tested). Penetration bands are the profile's
(anatomical_bounds_core.BANDS). Read-only: never saves.
    blender -b --factory-startup --python anatomical_mesh_gate.py -- <blend> <armature> <poses.json> <out.json>
poses.json: {"states": {name: {"pose": {bone: [qx, qy, qz, qw, dx, dy, dz]}}}} (the G2 / G3 audit output)."""

import json
import os
import sys

import bpy
from mathutils import Quaternion, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import anatomical_bounds_core as core  # noqa: E402

TORSO_BONES = ("Hips", "Spine", "Chest")
## Checked parts: (part id, bones, share of the bone length tested - distal only for the upper arm).
PARTS = (
    ("upper_arm_R", ("UpperArm.R",), 0.5), ("forearm_R", ("Forearm.R",), 0.0), ("hand_R", ("Hand.R",), 0.0),
    ("upper_arm_L", ("UpperArm.L",), 0.5), ("forearm_L", ("Forearm.L",), 0.0), ("hand_L", ("Hand.L",), 0.0),
)
## Part -> surfaces it must stay out of.
CHECKS = {
    "upper_arm_R": ("torso",), "forearm_R": ("torso", "arm_L"), "hand_R": ("torso",),
    "upper_arm_L": ("torso",), "forearm_L": ("torso", "arm_R"), "hand_L": ("torso",),
}
SURFACES = {"torso": TORSO_BONES, "arm_R": ("UpperArm.R", "Forearm.R"), "arm_L": ("UpperArm.L", "Forearm.L")}


def _dominant(obj, bones):
    names = {g.index: g.name for g in obj.vertex_groups}
    out = {}
    for v in obj.data.vertices:
        best, weight = None, 0.0
        for g in v.groups:
            name = names.get(g.group)
            if name in bones and g.weight > weight:
                best, weight = name, g.weight
        if best is not None:
            out[v.index] = (best, weight)
    return out


## Inside test against an OPEN region surface (the torso is open at the neck, shoulders and hips; an arm is a tube): ray
## parity in these 14 directions with a majority vote, so a ray leaving through an opening is outvoted. The nearest face's
## normal alone misreads any vertex whose nearest face is a back face.
RAY_DIRECTIONS = tuple(Vector(d).normalized() for d in (
    (1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1),
    (1, 1, 1), (1, 1, -1), (1, -1, 1), (1, -1, -1), (-1, 1, 1), (-1, 1, -1), (-1, -1, 1), (-1, -1, -1)))
RAY_EPSILON = 1e-5
RAY_MAX_HITS = 64


def _crossings(tree, origin, direction):
    count = 0
    start = origin
    for _ in range(RAY_MAX_HITS):
        hit = tree.ray_cast(start, direction)
        if hit[0] is None:
            break
        count += 1
        start = hit[0] + direction * RAY_EPSILON
    return count


def inside(tree, p):
    votes = sum(1 for d in RAY_DIRECTIONS if _crossings(tree, p, d) % 2 == 1)
    return votes * 2 > len(RAY_DIRECTIONS)


def _apply(rig, pose):
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        values = pose.get(pb.name)
        if values is None:
            pb.rotation_quaternion = Quaternion()
            pb.location = Vector()
            continue
        pb.rotation_quaternion = Quaternion((values[3], values[0], values[1], values[2]))
        pb.location = Vector(values[4:7])
    bpy.context.view_layer.update()


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    bpy.ops.wm.open_mainfile(filepath=args[0])
    rig = bpy.data.objects[args[1]]
    states = json.load(open(args[2]))["states"]
    out_path = args[3]
    if rig.animation_data:
        rig.animation_data_clear()
    body = next(o for o in bpy.data.objects if o.type == "MESH" and o.name.endswith("Body") and any(m.type == "ARMATURE" and m.object == rig for m in o.modifiers))
    bones = {b.name for b in rig.data.bones}
    dominant = _dominant(body, bones)
    lengths = {b.name: b.length for b in rig.data.bones}
    rest_local = {i: rig.data.bones[b].matrix_local.inverted() @ body.data.vertices[i].co for i, (b, _) in dominant.items()}
    part_verts = {}
    for part, part_bones, share in PARTS:
        part_verts[part] = [i for i, (b, w) in dominant.items() if b in part_bones and w >= core.DOMINANT_WEIGHT_MIN and rest_local[i].y >= share * lengths[b]]
    surface_faces = {}
    for name, surface_bones in SURFACES.items():
        surface_faces[name] = [f.index for f in body.data.polygons if all(dominant.get(v, ("", 0))[0] in surface_bones for v in f.vertices)]
    report = {"body": body.name, "part_vertices": {k: len(v) for k, v in part_verts.items()}, "surface_faces": {k: len(v) for k, v in surface_faces.items()}, "states": {}}
    parity = []
    for name, state in states.items():
        _apply(rig, state.get("pose", {}))
        ## Pose-transfer parity: each elbow in the Chest bone's local frame (shared by both engines) against the audit's.
        chest_inv = (rig.matrix_world @ rig.pose.bones["Chest"].matrix).inverted()
        for side in "RL":
            if side in state and "elbow_chest" in state[side]:
                here = chest_inv @ (rig.matrix_world @ rig.pose.bones["Forearm." + side].head)
                parity.append(((here - Vector(state[side]["elbow_chest"])).length * 1000.0, name, side))
        dg = bpy.context.evaluated_depsgraph_get()
        ev = body.evaluated_get(dg)
        mesh = ev.to_mesh()
        mw = body.matrix_world
        co = [mw @ v.co for v in mesh.vertices]
        trees = {}
        for surface, faces in surface_faces.items():
            polys = [list(mesh.polygons[f].vertices) for f in faces]
            trees[surface] = BVHTree.FromPolygons(co, polys, all_triangles=False)
        result = {}
        for part, checks in CHECKS.items():
            for surface in checks:
                depths = []
                for i in part_verts[part]:
                    p = co[i]
                    hit = trees[surface].find_nearest(p)
                    if hit[0] is None or not inside(trees[surface], p):
                        continue
                    depths.append((p - hit[0]).length)
                if depths:
                    depths.sort()
                    worst = depths[-1] * 1000.0
                    p95 = depths[int(0.95 * (len(depths) - 1))] * 1000.0
                    result[f"{part}~{surface}"] = {"inside_vertices": len(depths), "of": len(part_verts[part]), "max_mm": round(worst, 1),
                                                   "p95_mm": round(p95, 1), "band": core.band(-p95 / 1000.0)}
        ev.to_mesh_clear()
        report["states"][name] = result
    _apply(rig, {})
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1)
    summary = {}
    for name, result in report["states"].items():
        bad = {k: (v["p95_mm"], v["max_mm"], v["inside_vertices"]) for k, v in result.items() if v["band"] not in ("clear", "near", "minor")}
        if bad:
            summary[name] = bad
    worst_parity = max(parity) if parity else (0.0, "", "")
    report["pose_transfer_parity_mm"] = round(worst_parity[0], 2)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1)
    print("RIPOSTE_MESH_GATE " + json.dumps({"out": out_path, "parity_worst_elbow_mm": [round(worst_parity[0], 2), worst_parity[1], worst_parity[2]],
                                             "parts": report["part_vertices"], "faces": report["surface_faces"], "failing": summary}))


main()
