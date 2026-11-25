"""ART-ANATOMY-001 in Blender: fit a body's anatomical collision profile from its production mesh.

Reads (never saves) a staged / production blend: for every mesh skinned to the armature, each
vertex's dominant bone weight (>= `DOMINANT_WEIGHT_MIN`; joint-transition vertices stay out) picks
its region; the region's rest vertices in the bone's local rest frame fit the volume
(`anatomical_bounds_core.fit_capsule` / `fit_slab`). Then the volumes are checked against the
evaluated (deformed, post-armature) mesh in the rest pose and in declared test poses: the share of
each region's vertices inside its volume and how far the rest stick out, so a volume that does not
follow its region when the bones move is visible in the report. Writes `<out>.anatomy.json`.
Bone-local frames are shared by Blender and Godot for WolfRig (G2 audit), so the profile needs no
conversion.
    blender -b --factory-startup --python anatomical_bounds.py -- <blend> <armature> <out.anatomy.json> <source body id>"""

import json
import math
import os
import sys

import bpy
from mathutils import Euler, Matrix

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import anatomical_bounds_core as core  # noqa: E402

## Declared coverage test poses (bone -> local XYZ Euler degrees): the G2 test pose and a raised,
## crossed two-hand reach with a turned chest - poses that move every fitted region.
TEST_POSES = {
    "rest": {},
    "g2_raise": {"UpperArm.R": (0, 0, 45), "Forearm.R": (70, 0, 0), "UpperArm.L": (0, 0, -45), "Forearm.L": (70, 0, 0)},
    "reach_turn": {"Chest": (0, 20, 0), "UpperArm.R": (60, 0, 20), "Forearm.R": (50, 0, 0), "UpperArm.L": (60, 0, -30),
                   "Forearm.L": (40, 0, 0), "Hand.R": (20, 0, 0), "Hand.L": (-20, 0, 0)},
}


def _rows(m):
    return [[m[r][c] for c in range(4)] for r in range(4)]


def _skinned(rig):
    return [o for o in bpy.data.objects if o.type == "MESH" and any(m.type == "ARMATURE" and m.object == rig for m in o.modifiers)]


def _partition(rig, meshes, minimum=core.DOMINANT_WEIGHT_MIN):
    """region bone -> [(mesh name, vertex index)] by dominant weight."""
    bones = {b.name for b in rig.data.bones}
    owned = {}
    for obj in meshes:
        names = {g.index: g.name for g in obj.vertex_groups}
        for v in obj.data.vertices:
            best, weight = None, 0.0
            for g in v.groups:
                name = names.get(g.group)
                if name in bones and g.weight > weight:
                    best, weight = name, g.weight
            if best is not None and weight >= minimum:
                owned.setdefault(best, []).append((obj.name, v.index))
    return owned


def _rest_points(rig, owned):
    """bone -> bone-local rest points of its dominant vertices."""
    inv_rig = rig.matrix_world.inverted()
    out = {}
    for bone_name, verts in owned.items():
        to_local = rig.data.bones[bone_name].matrix_local.inverted() @ inv_rig
        pts = []
        for mesh_name, index in verts:
            obj = bpy.data.objects[mesh_name]
            p = to_local @ (obj.matrix_world @ obj.data.vertices[index].co)
            pts.append((p.x, p.y, p.z))
        out[bone_name] = pts
    return out


def _evaluated(rig, owned):
    """bone -> world points of its dominant vertices in the current (evaluated, deformed) pose."""
    dg = bpy.context.evaluated_depsgraph_get()
    cache = {}
    out = {}
    for bone_name, verts in owned.items():
        pts = []
        for mesh_name, index in verts:
            if mesh_name not in cache:
                obj = bpy.data.objects[mesh_name]
                ev = obj.evaluated_get(dg)
                cache[mesh_name] = (obj.matrix_world.copy(), [v.co.copy() for v in ev.to_mesh().vertices])
                ev.to_mesh_clear()
            mw, cos = cache[mesh_name]
            p = mw @ cos[index]
            pts.append((p.x, p.y, p.z))
        out[bone_name] = pts
    return out


def _pose(rig, pose):
    for pb in rig.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = Euler((0.0, 0.0, 0.0))
        pb.location = (0.0, 0.0, 0.0)
    for name, deg in pose.items():
        if name in rig.pose.bones:
            rig.pose.bones[name].rotation_euler = Euler(tuple(math.radians(d) for d in deg))
    bpy.context.view_layer.update()
    return {pb.name: _rows(rig.matrix_world @ pb.matrix) for pb in rig.pose.bones}


## The authored grip contacts' origins in each hand's frame (the palm side the handle lies against).
CONTACTS = {"R": (0.0185, 0.06, 0.0261), "L": (-0.0185, 0.06, 0.0261)}


def _calibrate_elbows(clips_blend, spec, rest_hash):
    """Elbow hinges from approved bent clip frames ("action:frame,..."): per side the forearm direction
    in the upper arm's posed frame, calibrated by anatomical_bounds_core.calibrate_hinge. The clip rig
    must share the body's rest (same hash), so its bone-local frames are the profile's."""
    bpy.ops.wm.open_mainfile(filepath=clips_blend)
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    clip_hash = core.content_hash({b.name: [[round(x, 5) for x in row] for row in b.matrix_local] for b in rig.data.bones})
    if clip_hash != rest_hash:
        raise SystemExit("RIPOSTE_ANATOMY ERROR calibration rig rest %s differs from the body's %s" % (clip_hash, rest_hash))
    samples = {"R": [], "L": []}
    used = []
    for item in spec.split(","):
        action, frame = item.split(":")
        rig.animation_data_create()
        rig.animation_data.action = bpy.data.actions[action]
        bpy.context.scene.frame_set(int(frame))
        for side in "RL":
            upper = rig.pose.bones["UpperArm." + side]
            f = upper.matrix.to_3x3().inverted() @ (rig.pose.bones["Hand." + side].head - rig.pose.bones["Forearm." + side].head)
            samples[side].append((f.x, f.y, f.z))
        used.append(item)
    out = {}
    for side in "RL":
        axis, spread, count = core.calibrate_hinge(samples[side])
        per_sample = []
        for item, f in zip(used, samples[side]):
            try:
                per_sample.append([item, list(core.calibrate_hinge([f])[0])])
            except ValueError:
                per_sample.append([item, None])
        out["elbow_" + side] = {"bone": "Forearm." + side, "parent": "UpperArm." + side, "frame": "upper arm (bone-local)",
                                "longitudinal": [0.0, 1.0, 0.0], "hinge_axis": list(axis), "calibration_spread_deg": spread,
                                "calibration_samples": count, "calibration_poses": used, "per_sample_axes": per_sample,
                                "spread_warning": spread > core.HINGE_SPREAD_WARNING_DEG}
    return out


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    bpy.ops.wm.open_mainfile(filepath=args[0])
    rig = bpy.data.objects[args[1]]
    out_path, body_id = args[2], args[3]
    if rig.animation_data:
        rig.animation_data_clear()
    rig.data.pose_position = "POSE"
    meshes = _skinned(rig)
    owned = _partition(rig, meshes)
    ## A bone that is only ever a blend zone (no vertex at the dominant threshold, e.g. a short neck)
    ## falls back to its dominant vertices at any weight; the partition used is recorded per region.
    loose = _partition(rig, meshes, 0.0)
    partition = {}
    for region in core.REGIONS:
        bone = region["bone"]
        partition[bone] = "dominant_%.1f" % core.DOMINANT_WEIGHT_MIN if owned.get(bone) else "dominant_any"
        if not owned.get(bone) and loose.get(bone):
            owned[bone] = loose[bone]
    rest = _rest_points(rig, owned)
    volumes = []
    for region in core.REGIONS:
        bone = region["bone"]
        pts = rest.get(bone, [])
        if not pts:
            raise SystemExit("RIPOSTE_ANATOMY ERROR region %s: no dominant vertices on %s" % (region["id"], bone))
        if region["shape"] == "capsule":
            shape = core.fit_capsule(pts, rig.data.bones[bone].length, region["trim"])
        else:
            shape = core.fit_prism(pts, region["slice"])
        shape.update({"region_id": region["id"], "attached_bone": bone, "local_frame": "bone_rest", "vertex_count": len(pts),
                      "partition": partition[bone]})
        volumes.append(shape)
    report = {"meshes": [o.name for o in meshes], "regions": {}, "test_poses": {}}
    for pose_name, pose in TEST_POSES.items():
        matrices = _pose(rig, pose)
        world = _evaluated(rig, owned)
        cov = {}
        for v in volumes:
            posed = core.pose_volume(v, matrices[v["attached_bone"]])
            ## A volume answers only for the vertices it was fitted to (its band of the bone's region).
            lo, hi = v["fit_band"]
            mine = [p for p, q in zip(world[v["attached_bone"]], rest[v["attached_bone"]]) if lo <= q[1] <= hi]
            cov[v["region_id"]] = core.coverage(posed, mine)
        profile = {"volumes": volumes, "collision_pairs": [dict(p) for p in core.PAIRS]}
        pairs = core.evaluate(profile, matrices)
        report["test_poses"][pose_name] = {"coverage": cov, "worst_pairs": sorted(pairs, key=lambda r: r["clearance_m"])[:6]}
    _pose(rig, {})
    mesh_hash = core.content_hash({o.name: [[round(c, 4) for c in v.co] for v in o.data.vertices] for o in meshes})
    rest_hash = core.content_hash({b.name: [[round(x, 5) for x in row] for row in b.matrix_local] for b in rig.data.bones})
    ## Wrist frames from the body: each palm's normal in its hand's rest frame, signed toward the grip contact.
    joints = {}
    for side, contact in (("R", CONTACTS["R"]), ("L", CONTACTS["L"])):
        n = core.palm_normal(rest["Hand." + side], contact)
        flex_axis = (n[2], 0.0, -n[0])  # (0, 1, 0) x n
        joints["wrist_" + side] = {"bone": "Hand." + side, "parent": "Forearm." + side, "frame": "hand rest (anatomical neutral = rest)",
                                   "longitudinal": [0.0, 1.0, 0.0], "palm_normal": list(n), "flexion_axis": list(flex_axis), "deviation_axis": list(n)}
        joints["shoulder_" + side] = {"bone": "UpperArm." + side, "parent": "Shoulder." + side, "frame": "upper arm rest relative to shoulder rest",
                                      "longitudinal": [0.0, 1.0, 0.0], "decomposition": "swing-twist about +Y"}
    if len(args) > 5:
        joints.update(_calibrate_elbows(args[4], args[5], rest_hash))
    doc = core.profile_document(body_id, mesh_hash, rest_hash, volumes, report, joints)
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=1)
    summary = {}
    for v in volumes:
        rest_cov = report["test_poses"]["rest"]["coverage"][v["region_id"]]
        reach_cov = report["test_poses"]["reach_turn"]["coverage"][v["region_id"]]
        summary[v["region_id"]] = {"r_mm": round(v["radius"] * 1000.0, 1), "n": rest_cov["count"],
                                   "rest_skin_out": rest_cov["skin_out_p95_mm"], "rest_vol_out": rest_cov["volume_out_p95_mm"],
                                   "reach_skin_out": reach_cov["skin_out_p95_mm"], "reach_vol_out": reach_cov["volume_out_p95_mm"]}
    print("RIPOSTE_ANATOMY " + json.dumps({"out": out_path, "mesh_hash": mesh_hash, "rest_hash": rest_hash, "regions": summary}))


main()
