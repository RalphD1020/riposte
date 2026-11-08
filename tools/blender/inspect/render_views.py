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
VIEWS = {"front": 0.0, "three_quarter": 35.0, "side": 90.0, "rear": 180.0, "three_quarter_other": -35.0, "side_other": -90.0}
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
## `gameplay_head`: the same camera rendered at this multiple and cropped to --target's
## neighbourhood (this many metres across), so the face at play distance can be read.
GAMEPLAY_HEAD_MULTIPLE = 6
GAMEPLAY_HEAD_SPAN_M = 0.6
## `low`: from below the face, looking up this many degrees, turned this far off the front.
LOW_PITCH_DEG = 30.0
LOW_YAW_DEG = 20.0
## `--flat`: a flat silhouette, this tone on white.
SILHOUETTE_TONE = (0.08, 0.08, 0.09)


def _arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--blend", required=True)
    parser.add_argument("--out", required=True, help="output prefix; _<view>.png is appended")
    parser.add_argument("--pose", choices=("apose", "rest"), default="rest")
    parser.add_argument("--keys", default="")
    parser.add_argument("--head", action="store_true")
    parser.add_argument("--target", default="", help="x,y,z the views look at (overrides the body/head frame)")
    parser.add_argument("--scale", type=float, default=0.0, help="orthographic scale in metres (with --target)")
    parser.add_argument("--views", default="front,three_quarter,side,rear", help="comma list of %s, top, bottom, low, gameplay, gameplay_head" % ", ".join(VIEWS))
    parser.add_argument("--configuration", default="", help="a named configuration of <blend>.configuration.json (sets its keys)")
    parser.add_argument("--wire", action="store_true", help="overlay the wireframe (topology review)")
    parser.add_argument("--materials", action="store_true", help="shade with each material's colour, not one skin tone")
    parser.add_argument("--hide", default="", help="comma list of collections or objects not to render")
    parser.add_argument("--clip", default="", help="pose the armature at an action (with --frame)")
    parser.add_argument("--frame", type=int, default=0)
    parser.add_argument("--dead", action="store_true", help="a .glb: show the dead-eye X instead of the eyes (FacePresentation's rule)")
    parser.add_argument("--flat", action="store_true", help="a flat silhouette (one tone on white, no light)")
    parser.add_argument("--face", default="", help="PRESET[,gaze_h,gaze_v[,blink]]: the face's channel keys at a shared preset")
    parser.add_argument("--beside", default="", help="baseline prefixes (comma list): also write <out>_<view>_beside.png (baselines left, candidate last)")
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


def _face(spec):
    """Every face component's channel keys (FACE-EYE-001) at a shared preset, per side (the
    `.L` / `.R` in its name), with an optional gaze and blink."""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "character_modeling"))
    from character_modeling import eye_assembly, expressions
    parts = spec.split(",")
    gaze = (float(parts[1]), float(parts[2])) if len(parts) >= 3 else None
    blink = float(parts[3]) if len(parts) >= 4 else 0.0
    prefixes = tuple(eye_assembly.COMPONENTS.values())
    for obj in bpy.data.objects:
        keys = obj.data.shape_keys if obj.type == "MESH" else None
        mark = obj.name.split(".")
        side = next((s for s in ("L", "R") if s in mark), None)
        if keys is None or side is None or not any(m.startswith(prefixes) for m in mark):
            continue
        weights = expressions.weights(parts[0], side, gaze=gaze, blink=blink)
        for block in keys.key_blocks[1:]:
            block.value = weights.get(block.name, 0.0)
    bpy.context.view_layer.update()


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
                if obj is not None:
                    obj.hide_render = True
    characters = {c.name for c in bpy.data.collections}
    for obj in bpy.data.objects:
        ## A lineup's parts are named "<character>.<part>" (the character is a collection):
        ## hiding a character hides every part, and the dead-eye X / the eyes are recognized
        ## after the prefix.
        prefix, _dot, rest = obj.name.partition(".")
        part = rest if rest and prefix in characters else obj.name
        if obj.name in hidden or (rest and prefix in hidden) or (part.startswith("DeadEye") and not args.dead) or (part.startswith("Eye") and args.dead):
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
    if args.face:
        _face(args.face)
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
    scene.display.shading.light = "FLAT" if args.flat else "STUDIO"
    ## Workbench's studio specular lands on one near-black pupil and washes it grey, a
    ## defect of the review light, not of the eye: reviews judge form and colour without it.
    scene.display.shading.show_specular_highlight = False
    scene.display.shading.color_type = "MATERIAL" if args.materials else "SINGLE"
    scene.display.shading.single_color = SILHOUETTE_TONE if args.flat else SKIN_TONE
    if args.materials:
        ## Authored colours (the skin swatches, the palette) displayed as authored, not
        ## tone-mapped by the default view transform.
        scene.view_settings.view_transform = "Standard"
    if args.flat:
        scene.world = scene.world or bpy.data.worlds.new("ReviewWorld")
        scene.world.color = (1.0, 1.0, 1.0)
        scene.view_settings.view_transform = "Standard"
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
        camera_data.type = "PERSP" if view.startswith("gameplay") else "ORTHO"
        scene.render.use_border = scene.render.use_crop_to_border = False
        if view.startswith("gameplay"):
            multiple = GAMEPLAY_HEAD_MULTIPLE if view == "gameplay_head" else 1
            scene.render.resolution_x, scene.render.resolution_y = 1280 * multiple, 720 * multiple
            pitch = math.radians(GAMEPLAY_PITCH_DEG)
            camera_data.angle = math.radians(GAMEPLAY_FOV_DEG)
            camera.location = GAMEPLAY_LOOK_AT + Vector((0.0, -math.cos(pitch), math.sin(pitch))) * GAMEPLAY_DISTANCE_M
            camera.rotation_euler = (math.radians(90.0) - pitch, 0.0, 0.0)
            if multiple > 1:
                from bpy_extras.object_utils import world_to_camera_view
                bpy.context.view_layer.update()
                half = GAMEPLAY_HEAD_SPAN_M / 2.0
                corners = [world_to_camera_view(scene, camera, target + Vector((dx, 0.0, dz)))
                           for dx in (-half, half) for dz in (-half, half)]
                scene.render.border_min_x = min(c.x for c in corners)
                scene.render.border_max_x = max(c.x for c in corners)
                scene.render.border_min_y = min(c.y for c in corners)
                scene.render.border_max_y = max(c.y for c in corners)
                scene.render.use_border = scene.render.use_crop_to_border = True
        elif view == "low":
            pitch, yaw = math.radians(LOW_PITCH_DEG), math.radians(LOW_YAW_DEG)
            camera.location = target + Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch),
                                               -math.sin(pitch))) * CAMERA_DISTANCE_M
            camera.rotation_euler = (math.radians(90.0) + pitch, 0.0, yaw)
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
        if args.beside:
            baselines = [os.path.abspath(p) + "_%s.png" % view for p in args.beside.split(",")]
            print("RIPOSTE_VIEW", _beside(baselines, scene.render.filepath))


def _beside(baselines, candidate):
    """<candidate>_beside.png: the baselines left to right, the candidate last."""
    import numpy as np
    images = [bpy.data.images.load(path) for path in baselines + [candidate]]
    width, height = images[0].size
    if any(tuple(image.size) != (width, height) for image in images):
        raise SystemExit("RIPOSTE_VIEW: %s differ in size" % ", ".join(baselines + [candidate]))
    pixels = [np.array(image.pixels[:]).reshape(height, width, 4) for image in images]
    board = bpy.data.images.new("Beside", width * len(images), height, alpha=True)
    board.pixels = np.concatenate(pixels, axis=1).ravel()
    board.filepath_raw = candidate[:-4] + "_beside.png"
    board.file_format = "PNG"
    board.save()
    return board.filepath_raw


if __name__ == "__main__":
    main()
