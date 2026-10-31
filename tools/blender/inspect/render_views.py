"""Orthographic Workbench views of a character master, for side-by-side review.

Fixed cameras (front, three-quarter, side, rear; optionally a head closeup) so
two renders of the same view compare like for like. Read-only: the blend is
never saved.

    blender --background --factory-startup --python tools/blender/inspect/render_views.py -- \
        --blend art-src/blender/characters/male_base.blend --out .reports/male_base/default \
        (or --blend game/assets/generated/characters/wolf_bare.glb [--dead] for an exported character)
        [--pose apose|rest] [--keys mass_plus:1,definition_plus:0.5] [--head] [--materials] \
        [--target 0,-0.61,0 --scale 1.4 --views top,side]

`--pose apose` applies the master's stored authoring pose (`riposte_authoring_pose`);
`rest` is WolfRig's rest. `--keys` sets physique shape keys by name.
"""

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Vector

AUTHORING_POSE = "riposte_authoring_pose"
VIEWS = {"front": 0.0, "three_quarter": 35.0, "side": 90.0, "rear": 180.0}
BODY_FRAME = (2.0, Vector((0.0, 0.0, 0.92)), (700, 900))
HEAD_FRAME = (0.55, Vector((0.0, 0.0, 1.60)), (700, 700))
SKIN_TONE = (0.75, 0.62, 0.52)
CAMERA_DISTANCE_M = 6.0
## `gameplay`: the shipped match camera (RiposteKits camera profile: pitch 48 degrees,
## nearest distance 14 m, fov 40), perspective, from the front, so a review in Blender
## sees what a player sees. Anatomy that disappears here earns little modeling effort.
GAMEPLAY_PITCH_DEG = 48.0
GAMEPLAY_DISTANCE_M = 14.0
GAMEPLAY_FOV_DEG = 40.0
GAMEPLAY_LOOK_AT = Vector((0.0, 0.0, 0.95))


def _arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--blend", required=True)
    parser.add_argument("--out", required=True, help="output prefix; _<view>.png is appended")
    parser.add_argument("--pose", choices=("apose", "rest"), default="rest")
    parser.add_argument("--keys", default="")
    parser.add_argument("--head", action="store_true")
    parser.add_argument("--target", default="", help="x,y,z the views look at (overrides the body/head frame)")
    parser.add_argument("--scale", type=float, default=0.0, help="orthographic scale in metres (with --target)")
    parser.add_argument("--views", default=",".join(VIEWS), help="comma list of %s, top, bottom, gameplay" % ", ".join(VIEWS))
    parser.add_argument("--configuration", default="", help="a named configuration of <blend>.configuration.json (sets its keys)")
    parser.add_argument("--wire", action="store_true", help="overlay the wireframe (topology review)")
    parser.add_argument("--materials", action="store_true", help="shade with each material's colour, not one skin tone")
    parser.add_argument("--hide", default="", help="comma list of collections or objects not to render")
    parser.add_argument("--clip", default="", help="pose the armature at an action (with --frame)")
    parser.add_argument("--frame", type=int, default=0)
    parser.add_argument("--dead", action="store_true", help="a .glb: show the dead-eye X instead of the eyes (FacePresentation's rule)")
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1:])


def _pose(scene, name):
    if name != "apose":
        return
    rig = next(o for o in scene.objects if o.type == "ARMATURE")
    rig.animation_data_clear()
    for bone, quaternion in json.loads(rig[AUTHORING_POSE]).items():
        pose_bone = rig.pose.bones[bone]
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.rotation_quaternion = quaternion
    bpy.context.view_layer.update()


def _keys(spec):
    body = bpy.data.objects.get("Body")
    if not spec or body is None or body.data.shape_keys is None:
        return
    for pair in spec.split(","):
        name, value = pair.split(":")
        body.data.shape_keys.key_blocks[name].value = float(value)


def main():
    args = _arguments()
    ## Blender resolves a relative render path against the drive root, not the working directory.
    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    source = os.path.abspath(args.blend)
    if source.lower().endswith(".glb"):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=source)
    else:
        bpy.ops.wm.open_mainfile(filepath=source)
    hidden = {h for h in args.hide.split(",") if h}
    for collection in bpy.data.collections:
        if collection.name in hidden:
            for obj in collection.all_objects:
                obj.hide_render = True
    for obj in bpy.data.objects:
        if obj.name in hidden or (obj.name.startswith("DeadEye") and not args.dead) or (obj.name.startswith("Eye") and args.dead):
            obj.hide_render = True
    scene = bpy.context.scene
    _pose(scene, args.pose)
    if args.clip:
        rig = next(o for o in scene.objects if o.type == "ARMATURE" and o.library is None)
        if rig.animation_data is None:
            rig.animation_data_create()
        rig.animation_data.action = bpy.data.actions[args.clip]
        scene.frame_set(args.frame)
    if args.configuration:
        with open(os.path.splitext(source)[0] + ".configuration.json", encoding="utf-8") as handle:
            values = json.load(handle)["configurations"][args.configuration]
        args.keys = ",".join("%s_%s:%s" % (p, "plus" if v > 0 else "minus", abs(v)) for p, v in values.items() if v != 0)
    _keys(args.keys)
    scene.render.engine = "BLENDER_WORKBENCH"
    if args.wire:
        ## Workbench draws a viewport wireframe overlay only in the viewport; a copy with
        ## a Wireframe modifier (after its armature) draws the edges in a final render.
        scene.display.shading.color_type = "OBJECT"
        for obj in [o for o in bpy.data.objects if o.type == "MESH" and not o.hide_render]:
            obj.color = (*SKIN_TONE, 1.0)
            wire = obj.copy()
            wire.modifiers.new("ReviewWire", "WIREFRAME").thickness = 0.0022
            wire.color = (0.05, 0.05, 0.07, 1.0)
            scene.collection.objects.link(wire)
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL" if args.materials else "SINGLE"
    scene.display.shading.single_color = SKIN_TONE
    scale, target, (width, height) = HEAD_FRAME if args.head else BODY_FRAME
    if args.target:
        target = Vector(float(c) for c in args.target.split(","))
        scale = args.scale or scale
        width = height = 800
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    camera_data = bpy.data.cameras.new("ReviewCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = scale
    camera = bpy.data.objects.new("ReviewCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    for view in args.views.split(","):
        camera_data.type = "PERSP" if view == "gameplay" else "ORTHO"
        if view == "gameplay":
            scene.render.resolution_x, scene.render.resolution_y = 1280, 720
            pitch = math.radians(GAMEPLAY_PITCH_DEG)
            camera_data.angle = math.radians(GAMEPLAY_FOV_DEG)
            camera.location = GAMEPLAY_LOOK_AT + Vector((0.0, -math.cos(pitch), math.sin(pitch))) * GAMEPLAY_DISTANCE_M
            camera.rotation_euler = (math.radians(90.0) - pitch, 0.0, 0.0)
        elif view == "top":
            camera.location = target + Vector((0.0, 0.0, CAMERA_DISTANCE_M))
            camera.rotation_euler = (0.0, 0.0, 0.0)
        elif view == "bottom":
            camera.location = target + Vector((0.0, 0.0, -CAMERA_DISTANCE_M))
            camera.rotation_euler = (math.radians(180.0), 0.0, 0.0)
        else:
            angle = math.radians(VIEWS[view])
            camera.location = target + Vector((math.sin(angle), -math.cos(angle), 0.0)) * CAMERA_DISTANCE_M
            camera.rotation_euler = (math.radians(90.0), 0.0, angle)
        scene.render.filepath = "%s_%s.png" % (out, view)
        bpy.ops.render.render(write_still=True)
        print("RIPOSTE_VIEW", scene.render.filepath)


if __name__ == "__main__":
    main()
