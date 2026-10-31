"""Physique correspondence: transfer the base's configuration keys onto a garment (CHARACTER-SOURCE-001).

Every physique key on the base (`mass_plus`, `chest_minus`, ...) gets a key of the
same name on the garment: each garment vertex takes the key's displacement at its
nearest point on the base's rest surface (barycentric over that face), so a body
configuration and its clothes bake with the same values and keep their clearance.
This is the starting point, not the answer: structured pieces (a leather mantle)
do not deform like skin, so their keys are then corrected by hand in the attire
blend, and every configuration is measured on the baked body and garment together
(`tools/blender/inspect/garment_audit.py --configurations`).

Edits the attire blend that holds the garment (never the base master, which is
refused). Refuses a garment that already has physique keys unless `--replace`.

    blender --background --factory-startup --python tools/blender/authoring/garment_physique.py -- \
        --blend art-src/blender/characters/wolf/wolf_attire.blend --garment RangerGambeson [--replace]
"""

import argparse
import os
import sys

import bpy
from mathutils.bvhtree import BVHTree
from mathutils.interpolate import poly_3d_calc

PROTECTED = ("male_base.blend",)
BASE = "Body"


def _arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--blend", required=True)
    parser.add_argument("--garment", required=True)
    parser.add_argument("--base-object", default=BASE)
    parser.add_argument("--replace", action="store_true")
    parser.add_argument("--no-save", action="store_true", help="transfer in memory only (tests and probes)")
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1:])


def transfer(body, garment, replace=False):
    """Give `garment` a key per physique key of `body`. Returns the key names."""
    if body.data.shape_keys is None:
        raise SystemExit("RIPOSTE_PHYSIQUE: %s carries no physique keys" % body.name)
    if garment.data.shape_keys is not None:
        if not replace:
            raise SystemExit("RIPOSTE_PHYSIQUE: %s already has keys; pass --replace" % garment.name)
        garment.shape_key_clear()
    blocks = body.data.shape_keys.key_blocks
    basis = [body.matrix_world @ p.co for p in blocks[0].data]
    faces = [list(p.vertices) for p in body.data.polygons]
    tree = BVHTree.FromPolygons(basis, faces)
    to_local = garment.matrix_world.inverted()
    samples = []
    for vertex in garment.data.vertices:
        p = garment.matrix_world @ vertex.co
        _nearest, _normal, index, _distance = tree.find_nearest(p)
        face = faces[index]
        weights = poly_3d_calc([basis[i] for i in face], p)
        samples.append((face, weights))
    garment.shape_key_add(name="Basis", from_mix=False)
    names = []
    for block in blocks[1:]:
        key = garment.shape_key_add(name=block.name, from_mix=False)
        delta = [body.matrix_world.to_3x3() @ (block.data[i].co - blocks[0].data[i].co) for i in range(len(basis))]
        for point, vertex, (face, weights) in zip(key.data, garment.data.vertices, samples):
            moved = sum((delta[i] * w for i, w in zip(face, weights)), delta[face[0]] * 0.0)
            point.co = vertex.co + to_local.to_3x3() @ moved
        key.value = 0.0
        names.append(block.name)
    return names


def main():
    args = _arguments()
    path = os.path.abspath(args.blend)
    if os.path.basename(path) in PROTECTED:
        raise SystemExit("RIPOSTE_PHYSIQUE: %s is the protected base master" % path)
    bpy.ops.wm.open_mainfile(filepath=path)
    names = transfer(bpy.data.objects[args.base_object], bpy.data.objects[args.garment], args.replace)
    print("RIPOSTE_PHYSIQUE_KEYS", args.garment, len(names))
    if not args.no_save:
        bpy.ops.wm.save_mainfile()


if __name__ == "__main__":
    main()
