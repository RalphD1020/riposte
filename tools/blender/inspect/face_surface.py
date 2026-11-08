"""Sample a head's mask as a FaceSurface (FACE-MAPPING-001) and report its semantic
landmarks and Wolf's face attachments resolved on it. Read-only.

    blender --background --factory-startup --python tools/blender/inspect/face_surface.py -- \
        --blend <file.blend> --object HeadV2 --out <report.json>

The chart is the one Wolf's marks use (u = x / half-width, v = height fraction above the
head's lowest point), in the v1 head frame unless --frame low,height,half_width is given;
each grid point is the forward-most hit of a ray from the front. Judgement is
`character_modeling.face_mapping`.
"""

import argparse
import json
import os
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "character_modeling"))
from character_modeling import face_mapping  # noqa: E402

V1_HEAD_FRAME = (1.522, 0.2765, 0.1084)
GRID = (61, 61)
U_SPAN = (-0.9, 0.9)
V_SPAN = (0.05, 0.92)
## Wolf's components as attachments: each mark on its landmark, lifted by its own proud
## distance (wolf.assembly.json identity.face.marks).
WOLF_ATTACHMENTS = {"Eye": ("eye_centre", "eye_opening"), "Brow": ("brow_apex", "brow_surface")}


def _arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--blend", required=True)
    parser.add_argument("--object", default="HeadV2")
    parser.add_argument("--out", required=True)
    parser.add_argument("--frame", default="")
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1:])


def sample(obj, frame):
    low, height, half_width = frame
    points = [obj.matrix_world @ v.co for v in obj.data.vertices]
    offset = obj.matrix_world.translation.x
    tree = BVHTree.FromPolygons(points, [list(p.vertices) for p in obj.data.polygons])
    us = [U_SPAN[0] + (U_SPAN[1] - U_SPAN[0]) * i / (GRID[0] - 1) for i in range(GRID[0])]
    vs = [V_SPAN[0] + (V_SPAN[1] - V_SPAN[0]) * j / (GRID[1] - 1) for j in range(GRID[1])]
    positions, normals, outside = [], [], 0
    rows = []
    for v in vs:
        row = []
        for u in us:
            hit, normal, _i, _d = tree.ray_cast(Vector((offset + u * half_width, -0.5, low + v * height)), Vector((0.0, 1.0, 0.0)))
            if hit is not None and normal.y > 0.0:
                normal = -normal
            row.append(None if hit is None else ((hit.x - offset, hit.y, hit.z), tuple(normal)))
        rows.append(row)
    filled = [j for j, row in enumerate(rows) if any(s is not None for s in row)]
    if not filled:
        raise SystemExit("RIPOSTE_FACE_SURFACE: no mask on any row")
    for j, row in enumerate(rows):
        ## Below a chin that rises above the chart's lowest rows, a row meets no surface: it
        ## is extended from the nearest row that does, as samples outside the silhouette are
        ## from their row; landmarks are never searched there.
        if not any(s is not None for s in row):
            near = min(filled, key=lambda k: abs(k - j))
            outside += len(row)
            rows[j] = [None if s is None else ((s[0][0], s[0][1], low + vs[j] * height), s[1]) for s in rows[near]]
    for v, row in zip(vs, rows):
        hits = [i for i, s in enumerate(row) if s is not None]
        ## Outside the silhouette (the jaw narrows below the chart's corners) the row is
        ## extended from its nearest hit; landmarks are never searched there.
        for i, s in enumerate(row):
            if s is None:
                outside += 1
                near = min(hits, key=lambda k: abs(k - i))
                (x, y, z), n = row[near]
                row[i] = ((us[i] * half_width, y, z), n)
        positions.append([s[0] for s in row])
        normals.append([s[1] for s in row])
    return {"schema": face_mapping.SCHEMA, "u": us, "v": vs, "positions": positions, "normals": normals,
            "frame": {"low": low, "height": height, "half_width": half_width}, "outside_samples": outside}


def main():
    args = _arguments()
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(args.blend))
    frame = tuple(float(c) for c in args.frame.split(",")) if args.frame else V1_HEAD_FRAME
    data = sample(bpy.data.objects[args.object], frame)
    surface = face_mapping.FaceSurface(data)
    with open(os.path.join(ROOT, "art-src", "blender", "characters", "wolf", "wolf.assembly.json"), encoding="utf-8") as handle:
        marks = json.load(handle)["identity"]["face"]["marks"]
    landmarks = face_mapping.derive_landmarks(surface, marks)
    attachments = {}
    for kind, (landmark, region) in WOLF_ATTACHMENTS.items():
        for side in ("L", "R"):
            attachments["%s.%s" % (kind, side)] = {"landmark": "%s.%s" % (landmark, side), "region": region,
                                                   "normal_offset_m": marks[kind].get("proud_m", 0.0)}
    problems, frames = face_mapping.attachment_problems(surface, landmarks, attachments)
    problems += face_mapping.landmark_problems(landmarks)
    report = {
        "object": args.object,
        "landmarks_m": {name: [round(c, 4) for c in surface.position(*uv)] for name, uv in sorted(landmarks.items())},
        "landmarks_uv": {name: [round(c, 4) for c in uv] for name, uv in sorted(landmarks.items())},
        "curvature_cheekbone_per_m": [round(c, 2) for c in surface.curvature(*landmarks["cheekbone_apex.L"])],
        "attachments": {name: {k: [round(c, 4) for c in f[k]] for k in ("origin", "normal", "uv")} for name, f in frames.items()},
        "problems": problems,
    }
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=1)
    print("RIPOSTE_FACE_SURFACE", json.dumps({"object": args.object, "problems": len(problems),
                                              "nose_tip": report["landmarks_m"]["nose_tip"],
                                              "nose_root": report["landmarks_m"]["nose_root"],
                                              "cheekbone_apex.L": report["landmarks_m"]["cheekbone_apex.L"]}))


if __name__ == "__main__":
    main()
