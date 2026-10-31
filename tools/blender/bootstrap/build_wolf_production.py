"""Build the v1 production body candidate: one connected skinned body on WolfRig.

Frozen as a regression reference (CHARACTER-SOURCE-001). The male base master is
`characters/male_base.blend`, edited in Blender; this builder authors
no new anatomy. This is a candidate, not the shipping blockout. It
does not touch wolf.blend or wolf.glb. The armature is the blockout's own
(`build_wolf.build_armature`, the same bones and rest metres as
`wolf.rig-contract.json`); the body is `character_modeling.production`, one
connected fixed-topology surface with selective weights (at most four
influences, normalized). The clips are Wolf's, authored by the same
`build_wolf.build_actions`, so the candidate runs through the real
presentation pipeline (AnimationPlayer, CombatPoseModifier3D, TwoBoneIK3D)
exactly as the shipping fighter does.

Run: blender --background --factory-startup --python tools/blender/bootstrap/build_wolf_production.py
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "character_modeling"))

import bpy  # noqa: E402

import build_wolf  # noqa: E402
import character_art  # noqa: E402
import riposte_blocks as rb  # noqa: E402
from character_modeling import production  # noqa: E402
from character_modeling.baseline import RIG_CONTRACT  # noqa: E402
from character_modeling.definition import PROFILES, load_profile  # noqa: E402

PROFILE = "male_base.json"
OUT = os.path.join(ROOT, "art-src", "blender", "fighters", "wolf_production.blend")
BODY = "Body"
SKIN = "skin"


def build_body(rig, mesh):
    data = bpy.data.meshes.new(BODY)
    data.from_pydata(mesh["vertices"], [], mesh["faces"])
    data.validate(clean_customdata=False)
    data.update()
    for polygon in data.polygons:
        polygon.use_smooth = True
    obj = bpy.data.objects.new(BODY, data)
    bpy.context.scene.collection.objects.link(obj)
    skin = build_wolf.ART["palette"][SKIN]
    data.materials.append(rb.material(SKIN, character_art.linear_color(skin["color"]), roughness=skin["roughness"]))
    for index, weights in enumerate(mesh["weights"]):
        for bone_name, weight in weights:
            group = obj.vertex_groups.get(bone_name) or obj.vertex_groups.new(name=bone_name)
            group.add([index], weight, "REPLACE")
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    obj.parent = rig
    return obj


def main():
    scene = rb.reset_scene()
    scene.render.fps = build_wolf.FPS
    rig = build_wolf.build_armature()
    rig_contract = json.loads(RIG_CONTRACT.read_text(encoding="utf-8"))
    mesh = production.build(load_profile(PROFILES / PROFILE), rig_contract)
    body = build_body(rig, mesh)
    build_wolf.build_actions(rig)
    build_wolf._rest(rig)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    print("RIPOSTE_PRODUCTION_TRIS", rb.triangle_count([body]))
    bpy.ops.wm.save_as_mainfile(filepath=OUT, compress=True)
    print("RIPOSTE_BUILT", OUT)


if __name__ == "__main__":
    main()
