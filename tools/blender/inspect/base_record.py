"""Measure a base master into a body record (`character_modeling.body_record`).

Read-only: the blend is never saved. The record holds the topology (fingerprint,
triangles, quads, poles by dominant bone, non-manifold edges), the protected head island
vertex for vertex, WolfRig's rest as the master carries it, every physique key's deltas
(digest, largest, how many vertices move), the vertex groups, and per named
configuration (`<master>.configuration.json`) the landmark measurements: torso sections,
limb girths, bounds, surface area and volume.

    blender --background --factory-startup --python tools/blender/inspect/base_record.py -- \
        --blend art-src/blender/characters/male_base.blend --out <record.json> \
        [--compare <baseline record.json> --report <regression.json>]

With --compare it also writes the regression report against a baseline record and exits
non-zero on a hard problem (the rig rest, the head island, keys or configurations, the crown).
"""

import argparse
import hashlib
import json
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "character_modeling"))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender"))

from character_modeling import body_record  # noqa: E402
import character_assembly  # noqa: E402

HEAD = "Head"
HEAD_ISLAND_MIN_WEIGHT = character_assembly.HEAD_ISLAND_MIN_WEIGHT
HEAD_ISLAND_MIN_Z = 1.5


def _arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--blend", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--configuration", default="", help="the configuration file (default: beside the blend)")
    parser.add_argument("--compare", default="")
    parser.add_argument("--report", default="")
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1:])


def _sha256(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def _weights(body):
    names = {g.index: g.name for g in body.vertex_groups}
    return [{names[g.group]: g.weight for g in v.groups if g.weight > 0.0} for v in body.data.vertices]


def _topology(body, dominant):
    mesh = body.data
    valence = [0] * len(mesh.vertices)
    for edge in mesh.edges:
        for i in edge.vertices:
            valence[i] += 1
    faces_per_edge = {}
    for polygon in mesh.polygons:
        for key in polygon.edge_keys:
            faces_per_edge[key] = faces_per_edge.get(key, 0) + 1
    boundary = {i for key, n in faces_per_edge.items() if n == 1 for i in key}
    poles = {}
    ## A pole: an interior vertex where three, or five or more, edges meet.
    for i, n in enumerate(valence):
        if i in boundary or n == 4:
            continue
        poles.setdefault(dominant[i], {"3": 0, "5+": 0})["3" if n == 3 else "5+"] += 1
    sides = [len(p.vertices) for p in mesh.polygons]
    return {"vertices": len(mesh.vertices), "faces": len(mesh.polygons), "triangles": sum(s - 2 for s in sides),
            "fingerprint": character_assembly.topology_fingerprint(body),
            "head_fingerprint": character_assembly.head_topology_fingerprint(character_assembly.head_island_faces(body)),
            "tris": sides.count(3), "quads": sides.count(4), "ngons": sum(1 for s in sides if s > 4),
            "non_manifold_edges": sum(1 for n in faces_per_edge.values() if n > 2),
            "boundary_edges": sum(1 for n in faces_per_edge.values() if n == 1),
            "poles_by_bone": dict(sorted(poles.items()))}


def _mixed(body, weights):
    blocks = body.data.shape_keys.key_blocks if body.data.shape_keys else None
    if blocks is None:
        return [body.matrix_world @ v.co for v in body.data.vertices]
    basis = blocks[0].data
    mixed = [p.co.copy() for p in basis]
    for name, value in weights.items():
        for index, point in enumerate(blocks[name].data):
            mixed[index] += (point.co - basis[index].co) * value
    return [body.matrix_world @ p for p in mixed]


AUTHORING_POSE = "riposte_authoring_pose"


def _apose(body, rig, key_weights):
    """The configured body and its bones in the stored authoring A-pose (tape girths), or
    None when the master stores no A-pose. The rig is returned to its rest."""
    if AUTHORING_POSE not in rig.keys():
        return None
    blocks = body.data.shape_keys.key_blocks if body.data.shape_keys else []
    for block in list(blocks)[1:]:
        block.value = key_weights.get(block.name, 0.0)
    for bone, quaternion in json.loads(rig[AUTHORING_POSE]).items():
        rig.pose.bones[bone].rotation_mode = "QUATERNION"
        rig.pose.bones[bone].rotation_quaternion = quaternion
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = body.evaluated_get(depsgraph).to_mesh()
    points = [tuple(body.matrix_world @ v.co) for v in mesh.vertices]
    body.evaluated_get(depsgraph).to_mesh_clear()
    bones = {b.name: (tuple(rig.matrix_world @ b.head), tuple(rig.matrix_world @ b.tail)) for b in rig.pose.bones}
    for block in list(blocks)[1:]:
        block.value = 0.0
    for pose_bone in rig.pose.bones:
        pose_bone.matrix_basis.identity()
    bpy.context.view_layer.update()
    return points, bones


def _key_weights(values):
    return {"%s_%s" % (p, "plus" if v > 0 else "minus"): abs(v) for p, v in values.items() if v != 0}


def _area_volume(points, polygons):
    area = volume = 0.0
    for polygon in polygons:
        a = points[polygon[0]]
        for i in range(1, len(polygon) - 1):
            b, c = points[polygon[i]], points[polygon[i + 1]]
            area += (b - a).cross(c - a).length * 0.5
            volume += a.dot(b.cross(c)) / 6.0
    return round(area, 4), round(abs(volume), 5)


def record(blend, configuration_path):
    bpy.ops.wm.open_mainfile(filepath=blend)
    body = bpy.data.objects["Body"]
    rig = body.parent
    weights = _weights(body)
    dominant = [max(w, key=w.get) if w else "" for w in weights]
    world = rig.matrix_world
    bones = {}
    for bone in rig.data.bones:
        axes = (world.to_3x3() @ bone.matrix_local.to_3x3())
        bones[bone.name] = {"parent": bone.parent.name if bone.parent else None,
                            "head": [round(c, 6) for c in world @ bone.head_local],
                            "tail": [round(c, 6) for c in world @ bone.tail_local],
                            "axes": [round(axes[r][c], 6) for r in range(3) for c in range(3)]}
    rest = [body.matrix_world @ v.co for v in body.data.vertices]
    island = [i for i, v in enumerate(body.data.vertices)
              if rest[i].z > HEAD_ISLAND_MIN_Z and weights[i].get(HEAD, 0.0) >= HEAD_ISLAND_MIN_WEIGHT]
    keys = {}
    if body.data.shape_keys:
        blocks = body.data.shape_keys.key_blocks
        basis = blocks[0].data
        for block in blocks[1:]:
            deltas = [(block.data[i].co - basis[i].co) for i in range(len(basis))]
            digest = hashlib.sha256(",".join("%.6f" % c for d in deltas for c in d).encode()).hexdigest()
            lengths = [d.length for d in deltas]
            keys[block.name] = {"sha256": digest, "max_m": round(max(lengths), 5),
                                "moved": sum(1 for x in lengths if x > 1e-5)}
    groups = {}
    for g in body.vertex_groups:
        members = [w[g.name] for w in weights if g.name in w]
        groups[g.name] = {"vertices": len(members), "weight_sum": round(sum(members), 4)}
    with open(configuration_path, encoding="utf-8") as handle:
        configuration = json.load(handle)
    edges = [tuple(e.vertices) for e in body.data.edges]
    polygons = [list(p.vertices) for p in body.data.polygons]
    bone_axes = {n: (tuple(b["head"]), tuple(b["tail"])) for n, b in bones.items()}
    configurations = {}
    for name, values in configuration["configurations"].items():
        points = _mixed(body, _key_weights(values))
        tuples = [tuple(p) for p in points]
        area, volume = _area_volume(points, polygons)
        configurations[name] = {
            "values": values,
            "bounds": {"min": [round(min(p[i] for p in tuples), 4) for i in range(3)],
                       "max": [round(max(p[i] for p in tuples), 4) for i in range(3)]},
            "surface_area_m2": area, "volume_m3": volume,
            "torso": body_record.torso_sections(tuples, edges, dominant),
            "limbs": body_record.limb_girths(tuples, dominant, bone_axes),
        }
        posed = _apose(body, rig, _key_weights(values))
        if posed is not None:
            configurations[name]["tape_girths_cm"] = body_record.tape_girths(posed[0], posed[1], island)
    return {"schema": body_record.SCHEMA, "version": body_record.VERSION,
            "source": {"blend": os.path.relpath(blend, ROOT).replace("\\", "/"), "sha256": _sha256(blend),
                       "configuration": os.path.relpath(configuration_path, ROOT).replace("\\", "/"),
                       "configuration_sha256": _sha256(configuration_path), "blender": bpy.app.version_string},
            "topology": _topology(body, dominant),
            "head_island": body_record.head_island([tuple(rest[i]) for i in island], [weights[i] for i in island]),
            "bones": bones, "keys": keys, "groups": groups, "configurations": configurations}


def main():
    args = _arguments()
    blend = os.path.abspath(args.blend)
    configuration = os.path.abspath(args.configuration) if args.configuration else os.path.splitext(blend)[0] + ".configuration.json"
    data = record(blend, configuration)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(data, handle, indent=1)
        handle.write("\n")
    topo = data["topology"]
    print("RIPOSTE_BODY_RECORD %s vertices %d triangles %d fingerprint %s head island %d keys %d" % (
        data["source"]["blend"], topo["vertices"], topo["triangles"], topo["fingerprint"][:12], len(data["head_island"]), len(data["keys"])))
    if args.compare:
        with open(args.compare, encoding="utf-8") as handle:
            baseline = json.load(handle)
        hard, report = body_record.compare(baseline, data)
        if args.report:
            with open(args.report, "w", encoding="utf-8", newline="\n") as handle:
                json.dump({"hard": hard, **report}, handle, indent=1)
                handle.write("\n")
        for problem in hard:
            print("RIPOSTE_BODY_REGRESSION", problem)
        sys.exit(1 if hard else 0)


if __name__ == "__main__":
    main()
