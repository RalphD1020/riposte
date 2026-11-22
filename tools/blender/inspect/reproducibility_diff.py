"""Fresh-process reproducibility diagnostic (CHARACTER-BUILD-001): are two independent builds
of the same character geometrically equivalent?

This is the milestone smoke test for generator determinism in the actual Blender environment.
Build the same `--set wolf` (or any set) twice in separate Blender processes, then compare the
two output `.blend`s here. Each mesh is compared as a CANONICAL, order-independent set of
oriented face records (face = its vertices' rounded local coordinates rotated to the smallest,
winding preserved, plus material index); index renumbering and face-array order do not change
it, while a moved vertex, flipped winding or changed material do. A harmless rim face reorder
reports `canonical_equal: true` with `raw_face_order_equal: false` — expected and acceptable.

This diagnostic never mutates a mesh and is not part of a build; it only reports.

blender --background --python tools/blender/inspect/reproducibility_diff.py -- <a.blend> <b.blend>
"""
import hashlib
import json
import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
Q = 5  # coordinate rounding (0.01 mm) — matches male_base_v2.FINGERPRINT_DECIMALS


def canonical_faces(obj):
    co = [tuple(round(c, Q) for c in v.co) for v in obj.data.vertices]
    out = []
    for p in obj.data.polygons:
        ring = [co[i] for i in p.vertices]
        k = ring.index(min(ring))
        out.append((tuple(ring[k:] + ring[:k]), p.material_index))
    out.sort()
    return out


def meshes(path):
    """{object name: (vertex count, canonical face digest, face count, raw face-order tuple)};
    objects are freed before returning so a second file loads under its own names."""
    with bpy.data.libraries.load(path, link=False) as (src, dst):
        dst.objects = list(src.objects)
    out = {}
    for obj in dst.objects:
        if obj and obj.type == "MESH":
            faces = canonical_faces(obj)
            out[obj.name] = (len(obj.data.vertices), hashlib.sha256(json.dumps(faces).encode()).hexdigest()[:16],
                             len(faces), tuple(tuple(p.vertices) for p in obj.data.polygons))
    for obj in list(dst.objects):
        if obj:
            bpy.data.objects.remove(obj, do_unlink=True)
    return out


a, b = meshes(args[0]), meshes(args[1])
report = {}
for name in sorted(set(a) & set(b)):
    (va, ha, nfa, raw_a), (vb, hb, nfb, raw_b) = a[name], b[name]
    report[name] = {"verts": [va, vb], "faces": [nfa, nfb], "canonical_equal": ha == hb,
                    "raw_face_order_equal": raw_a == raw_b}
print("RIPOSTE_REPRO", json.dumps(report))
print("RIPOSTE_SUMMARY", json.dumps({"all_canonical_equal": all(v["canonical_equal"] for v in report.values()),
                                     "all_raw_order_equal": all(v["raw_face_order_equal"] for v in report.values()),
                                     "meshes": len(report), "only_in_a": sorted(set(a) - set(b)),
                                     "only_in_b": sorted(set(b) - set(a))}))
