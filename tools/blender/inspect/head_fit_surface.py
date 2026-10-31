"""Measure a head into its HeadFitSurface (`character_modeling.head_fit`) and judge its face.

Read-only. Every landmark is a surface query on the head (rays and scans in the head's
own frame), never a vertex index, so it works on any head topology: the v1 head island on
`Body`, the approved `HeadV2`, a resolved head profile. The face's design fractions (where the eyes and
brows sit) come from the character manifest's face marks.

    blender --background --factory-startup --python tools/blender/inspect/head_fit_surface.py -- \
        --blend art-src/blender/characters/male_base.v2.blend --object HeadV2 \
        --manifest art-src/blender/characters/wolf/wolf.assembly.json --out <head_fit.json> \
        [--reference <a reference head_fit.json>]
"""

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "character_modeling"))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender"))

from character_modeling import head_fit  # noqa: E402
import character_assembly  # noqa: E402
## The direction the approved hairstyles gather to (azimuth from the front, elevation from
## the head centre): the shared bun anchor on the occipital region.
BUN_DIRECTION = (180.0, 28.0)
SCAN_STEP_M = 0.0005
CHEEK_SPAN_M = 0.012
## A face-panel point faces forward at least this much (cosine with -Y).
PANEL_FACING = 0.6


def _arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--blend", required=True)
    parser.add_argument("--object", default="Body")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--reference", default="")
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1:])


def head_surface(obj):
    """(points, faces) of the head: a Body's head island, or every face of a head object."""
    world = obj.matrix_world
    points = [world @ v.co for v in obj.data.vertices]
    if obj.name != "Body":
        return points, [list(p.vertices) for p in obj.data.polygons]
    return points, character_assembly.head_island_faces(obj)


def head_fingerprint(faces):
    return character_assembly.head_topology_fingerprint(faces)


def measure(obj, marks):
    points, faces = head_surface(obj)
    used = sorted({i for f in faces for i in f})
    tree = BVHTree.FromPolygons(points, faces)
    head = [points[i] for i in used]
    low, high = min(p.z for p in head), max(p.z for p in head)
    height = high - low
    half_width = max(abs(p.x) for p in head)
    front, back = min(p.y for p in head), max(p.y for p in head)
    centre = Vector((0.0, (front + back) * 0.5, low + 0.55 * height))

    def ray(origin, direction):
        hit = tree.ray_cast(Vector(origin), Vector(direction).normalized())[0]
        if hit is None:
            raise SystemExit("RIPOSTE_HEAD_FIT: no head surface from %s along %s" % (tuple(round(c, 3) for c in origin), tuple(direction)))
        return hit

    def front_at(x, z):
        return ray((x, front - 0.3, z), (0.0, 1.0, 0.0))

    def front_soft(x, z):
        return tree.ray_cast(Vector((x, front - 0.3, z)), Vector((0.0, 1.0, 0.0)))[0]

    def panel_at(x, z):
        """A point of the forward-facing face panel (not the head's rounded side)."""
        hit, normal, _i, _d = tree.ray_cast(Vector((x, front - 0.3, z)), Vector((0.0, 1.0, 0.0)))
        if hit is None:
            return None
        n = normal if normal.y < 0.0 else -normal
        return hit if n.y < -PANEL_FACING else None

    def forward_most(x, z0, z1):
        best = None
        z = z0
        while z <= z1:
            p = front_at(x, z)
            if best is None or p.y < best.y:
                best = p
            z += SCAN_STEP_M
        return best

    def side_at(sign, y, z):
        return ray((sign * (half_width + 0.3), y, z), (-sign, 0.0, 0.0))

    eye, brow = marks["Eye"], marks["Brow"]
    eye_z = low + eye["z"] * height
    landmarks = {}
    bulges = {}
    for side, sign in (("L", 1.0), ("R", -1.0)):
        landmarks["eye_centre.%s" % side] = front_at(sign * eye["x"] * half_width, eye_z)
        inner_x = (brow["x"] - brow["width"] * 0.5) * half_width
        outer_x = (brow["x"] + brow["width"] * 0.5) * half_width
        landmarks["brow_inner.%s" % side] = forward_most(sign * inner_x, eye_z + 0.006, eye_z + 0.05)
        landmarks["brow_outer.%s" % side] = forward_most(sign * outer_x, eye_z + 0.006, eye_z + 0.05)
        ## The cheekbone apex: where the cheek panel is most convex vertically — a point
        ## standing ahead of the surface CHEEK_SPAN_M above and below it. The approved
        ## panels are planar up and down (no apex); a cheekbone is a forward convexity.
        best, bulge = None, -1.0
        x0, x1 = 0.35 * half_width, 0.8 * half_width
        z = low + 0.3 * height
        while z <= low + 0.52 * height:
            x = x0
            while x <= x1:
                p, up, down = (panel_at(sign * x, z + dz) for dz in (0.0, CHEEK_SPAN_M, -CHEEK_SPAN_M))
                if p is not None and up is not None and down is not None:
                    lift = (up.y + down.y) * 0.5 - p.y
                    if lift > bulge:
                        best, bulge = p, lift
                x += 0.002
            z += 0.002
        landmarks["cheek_peak.%s" % side] = best
        bulges[side] = bulge
        landmarks["temple.%s" % side] = side_at(sign, front + 0.06, low + 0.62 * height)
        landmarks["ear_root.%s" % side] = side_at(sign, centre.y + 0.01, eye_z)
        landmarks["jaw_angle.%s" % side] = side_at(sign, centre.y - 0.02, low + 0.12 * height)
    landmarks["nose_tip"] = forward_most(0.0, low + 0.25 * height, low + 0.6 * height)
    landmarks["nose_bridge"] = front_at(0.0, landmarks["brow_inner.L"].z)
    landmarks["chin"] = forward_most(0.0, low + 0.005, low + 0.2 * height)
    landmarks["hairline_front"] = front_at(0.0, low + 0.85 * height)
    landmarks["crown"] = ray((0.0, centre.y, high + 0.3), (0.0, 0.0, -1.0))
    landmarks["occipital"] = ray((0.0, back + 0.3, centre.z), (0.0, -1.0, 0.0))
    landmarks["nape"] = ray((0.0, back + 0.3, low + 0.08 * height), (0.0, -1.0, 0.0))
    a, e = (math.radians(c) for c in BUN_DIRECTION)
    direction = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    landmarks["bun_anchor"] = ray(centre + direction * 0.5, -direction)
    rig = bpy.data.objects.get("Armature")
    neck = rig.matrix_world @ rig.data.bones["Neck"].head_local if rig else Vector((0.0, 0.0, low))
    landmarks["neck_base"] = neck
    face_front_y = min(p.y for p in head if abs(p.x) < 0.8 * half_width and p.z <= low + 0.9 * height)
    return {"frame": {"low": round(low, 4), "height": round(height, 4), "half_width": round(half_width, 4),
                      "front": round(front, 4), "back": round(back, 4)},
            "landmarks": {k: [round(c, 5) for c in v] for k, v in sorted(landmarks.items())},
            "face_front_y": round(face_front_y, 5), "cheekbone_bulge_m": round(min(bulges.values()), 5),
            "head_fingerprint": head_fingerprint(faces),
            "head_vertices": len(used), "head_triangles": sum(len(f) - 2 for f in faces)}


def main():
    args = _arguments()
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(args.blend))
    with open(os.path.abspath(args.manifest), encoding="utf-8") as handle:
        marks = json.load(handle)["identity"]["face"]["marks"]
    data = measure(bpy.data.objects[args.object], marks)
    problems = head_fit.landmark_problems(data["landmarks"])
    data["measures"], data["findings"] = head_fit.face_checks(data["landmarks"], data["face_front_y"], cheekbone_bulge_m=data["cheekbone_bulge_m"])
    data["landmark_problems"] = problems
    if args.reference:
        with open(os.path.abspath(args.reference), encoding="utf-8") as handle:
            reference = json.load(handle)
        data["identity_problems"] = head_fit.identity_problems(reference["landmarks"], data["landmarks"])
    data["schema"] = head_fit.SCHEMA
    data["source"] = {"blend": os.path.relpath(os.path.abspath(args.blend), ROOT).replace("\\", "/"), "object": args.object}
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(data, handle, indent=1)
        handle.write("\n")
    hard = [f for f in data["findings"] if f["severity"] == "hard"] + [{"message": p} for p in problems + data.get("identity_problems", [])]
    print("RIPOSTE_HEAD_FIT %s %s measures %s findings %s" % (args.object, data["head_fingerprint"][:12], data["measures"],
                                                             [(f["severity"], f["metric"]) for f in data["findings"]]))
    for f in hard:
        print("RIPOSTE_HEAD_FIT_PROBLEM", f["message"])
    sys.exit(1 if hard else 0)


if __name__ == "__main__":
    main()
