"""Deformation audit of a skinned base body through the production clips (Blender side of
the body's deformation gate; read-only).

The same sampling as `garment_audit.envelope`: every named configuration (its keys) x every
production clip, every `--frame-step` frames plus the last, on the real `Armature` and its
clips. Per sample, against the configured body at rest:

- tearing: edges stretched beyond STRETCH_MAX of their rest length;
- collapse: triangles whose area falls below COLLAPSE_MIN of their rest area;
- flips: triangles whose normal turns against their own bone's rotation of the rest normal;
- pops (temporal): a vertex stepping between consecutive samples more than POP_RATIO times
  the largest step of any bone head (the skin may never move faster than the skeleton).

Each failure names its configuration, clip, frame, count, worst value and the dominant
bone at the worst element, so the owning region is diagnosed before anything is changed.

    blender --background --factory-startup --python tools/blender/inspect/deformation_audit.py -- \
        --blend <bound.blend> --configuration <configuration.json> [--configurations all] \
        [--clips all] [--frame-step 2] --json <report.json>
"""

import argparse
import json
import os
import sys

import bpy
import numpy as np

STRETCH_MAX = 2.5
COLLAPSE_MIN = 0.15
FLIP_DOT = -0.2
POP_RATIO = 1.5
POP_FLOOR_M = 0.002


def _arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--blend", required=True)
    parser.add_argument("--configuration", required=True)
    parser.add_argument("--configurations", default="all")
    parser.add_argument("--clips", default="all")
    parser.add_argument("--frame-step", type=int, default=2)
    parser.add_argument("--json", required=True)
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1:])


def _points(obj):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = obj.evaluated_get(depsgraph).to_mesh()
    co = np.empty(len(mesh.vertices) * 3)
    mesh.vertices.foreach_get("co", co)
    obj.evaluated_get(depsgraph).to_mesh_clear()
    m = np.array(obj.matrix_world)
    return co.reshape(-1, 3) @ m[:3, :3].T + m[:3, 3]


def _triangles(obj):
    obj.data.calc_loop_triangles()
    tris = np.empty(len(obj.data.loop_triangles) * 3, dtype=np.int64)
    obj.data.loop_triangles.foreach_get("vertices", tris)
    return tris.reshape(-1, 3)


def _cross(points, tris):
    a, b, c = points[tris[:, 0]], points[tris[:, 1]], points[tris[:, 2]]
    return np.cross(b - a, c - a)


def _dominant(obj, names):
    count = len(obj.data.vertices)
    best, owner = np.zeros(count), np.full(count, -1)
    for group in obj.vertex_groups:
        weights = np.zeros(count)
        for v in obj.data.vertices:
            for g in v.groups:
                if g.group == group.index:
                    weights[v.index] = g.weight
        take = weights > best
        best[take], owner[take] = weights[take], names.index(group.name)
    return owner


def _set_keys(obj, values, parameters):
    known = {p["id"] for p in parameters}
    for block in obj.data.shape_keys.key_blocks[1:]:
        block.value = 0.0
    for parameter, value in values.items():
        if parameter in known and value:
            obj.data.shape_keys.key_blocks["%s_%s" % (parameter, "plus" if value > 0 else "minus")].value = abs(value)


def _pose(rig, clip, frame):
    if rig.animation_data is None:
        rig.animation_data_create()
    if clip is None:
        rig.animation_data.action = None
        for bone in rig.pose.bones:
            bone.matrix_basis.identity()
    else:
        rig.animation_data.action = bpy.data.actions[clip]
    bpy.context.scene.frame_set(int(frame))


def _bone_heads(rig):
    return np.array([tuple(rig.matrix_world @ b.head) for b in rig.pose.bones])


def _bone_rotations(rig, names):
    out = []
    for name in names:
        pb = rig.pose.bones[name]
        m = rig.matrix_world @ pb.matrix @ rig.data.bones[name].matrix_local.inverted() @ rig.matrix_world.inverted()
        out.append(np.array(m.to_3x3().normalized()))
    return np.stack(out)


def audit(body, rig, configuration, names, clips, frame_step):
    tris = _triangles(body)
    edges = np.array([tuple(e.vertices) for e in body.data.edges])
    owner = _dominant(body, [b.name for b in rig.pose.bones])
    bone_names = [b.name for b in rig.pose.bones]
    tri_owner = owner[tris[:, 0]]
    failures, worst = [], {}
    samples = 0
    for name in names:
        _set_keys(body, configuration["configurations"][name], configuration["parameters"])
        _pose(rig, None, 0)
        rest = _points(body)
        rest_edge = np.linalg.norm(rest[edges[:, 0]] - rest[edges[:, 1]], axis=1)
        rest_cross = _cross(rest, tris)
        rest_area = np.linalg.norm(rest_cross, axis=1)
        rest_normal = rest_cross / np.maximum(rest_area, 1e-12)[:, None]
        valid = rest_area > 1e-10
        for clip in clips:
            end = int(bpy.data.actions[clip].frame_range[1])
            start = int(bpy.data.actions[clip].frame_range[0])
            previous, previous_heads = None, None
            for frame in sorted(set(range(start, end + 1, frame_step)) | {end}):
                _pose(rig, clip, frame)
                p = _points(body)
                heads = _bone_heads(rig)
                samples += 1
                stretch = np.linalg.norm(p[edges[:, 0]] - p[edges[:, 1]], axis=1) / np.maximum(rest_edge, 1e-9)
                cross = _cross(p, tris)
                area = np.linalg.norm(cross, axis=1)
                ratio = np.where(valid, area / np.maximum(rest_area, 1e-12), 1.0)
                rotations = _bone_rotations(rig, bone_names)
                expected = np.einsum("tij,tj->ti", rotations[tri_owner], rest_normal)
                dots = np.where(valid, np.einsum("ti,ti->t", cross / np.maximum(area, 1e-12)[:, None], expected), 1.0)
                sample = {"stretch_max": float(stretch.max()), "collapse_min": float(ratio.min()), "flip_min": float(dots.min())}
                found = {"tearing": int((stretch > STRETCH_MAX).sum()), "collapse": int((ratio < COLLAPSE_MIN).sum()),
                         "flips": int((dots < FLIP_DOT).sum())}
                where = {"tearing": bone_names[owner[edges[int(stretch.argmax()), 0]]],
                         "collapse": bone_names[tri_owner[int(ratio.argmin())]],
                         "flips": bone_names[tri_owner[int(dots.argmin())]]}
                if previous is not None:
                    step = np.linalg.norm(p - previous, axis=1)
                    bone_step = float(np.linalg.norm(heads - previous_heads, axis=1).max())
                    limit = max(POP_FLOOR_M, POP_RATIO * bone_step)
                    found["pops"] = int((step > limit).sum())
                    sample["pop_ratio"] = float(step.max() / max(bone_step, 1e-6))
                    where["pops"] = bone_names[owner[int(step.argmax())]]
                previous, previous_heads = p, heads
                key = (name, clip)
                w = worst.setdefault("%s/%s" % key, {k: v for k, v in sample.items()})
                w["stretch_max"] = max(w["stretch_max"], sample["stretch_max"])
                w["collapse_min"] = min(w["collapse_min"], sample["collapse_min"])
                w["flip_min"] = min(w["flip_min"], sample["flip_min"])
                if "pop_ratio" in sample:
                    w["pop_ratio"] = max(w.get("pop_ratio", 0.0), sample["pop_ratio"])
                for kind, count in found.items():
                    if count:
                        failures.append({"configuration": name, "clip": clip, "frame": frame, "kind": kind,
                                         "count": count, "bone": where[kind],
                                         "value": round(sample.get({"tearing": "stretch_max", "collapse": "collapse_min",
                                                                    "flips": "flip_min", "pops": "pop_ratio"}[kind], 0.0), 3)})
    _pose(rig, None, 0)
    _set_keys(body, {}, configuration["parameters"])
    by = {}
    for f in failures:
        k = "%s|%s|%s" % (f["kind"], f["clip"], f["bone"])
        by.setdefault(k, {"samples": 0, "configurations": set(), "worst": f})
        by[k]["samples"] += 1
        by[k]["configurations"].add(f["configuration"])
    summary = {k: {"samples": v["samples"], "configurations": sorted(v["configurations"]), "worst": v["worst"]} for k, v in sorted(by.items())}
    return {"samples": samples, "failing_samples": len({(f["configuration"], f["clip"], f["frame"]) for f in failures}),
            "by_kind_clip_bone": summary, "worst_by_configuration_clip": {k: {m: round(x, 3) for m, x in v.items()} for k, v in worst.items()}}


def main():
    args = _arguments()
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(args.blend))
    with open(os.path.abspath(args.configuration), encoding="utf-8") as handle:
        configuration = json.load(handle)
    body = bpy.data.objects["Body"]
    rig = body.parent
    names = list(configuration["configurations"]) if args.configurations == "all" else args.configurations.split(",")
    clips = sorted(a.name for a in bpy.data.actions) if args.clips == "all" else args.clips.split(",")
    report = audit(body, rig, configuration, names, clips, args.frame_step)
    report.update({"blend": os.path.abspath(args.blend), "configurations": names, "clips": clips, "frame_step": args.frame_step,
                   "thresholds": {"stretch_max": STRETCH_MAX, "collapse_min": COLLAPSE_MIN, "flip_dot": FLIP_DOT, "pop_ratio": POP_RATIO}})
    os.makedirs(os.path.dirname(os.path.abspath(args.json)), exist_ok=True)
    with open(os.path.abspath(args.json), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(report, handle, indent=1)
    print("RIPOSTE_DEFORMATION_AUDIT", json.dumps({"samples": report["samples"], "failing_samples": report["failing_samples"],
                                                   "groups": len(report["by_kind_clip_bone"])}))


if __name__ == "__main__":
    main()
