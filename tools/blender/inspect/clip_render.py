"""Image-study render (GARMENT-VALIDATION-001): beauty (material) + flat garment-ID renders of a
built character blend at a chosen production clip frame (or rest), from named angles, at a
close-up target. The matched before/after view of the image-study loop, and the garment-ID mode
reads which garment surface makes a coverage opening (skin red, each garment a distinct flat
hue). Rigid head parts are bound to Head as the shipping assembly binds them.

    blender -b --factory-startup --python clip_render.py -- <blend> <prefix> <clip:frame|rest>
        <out_prefix> <tx,ty,tz> <scale> <views> [id]
`views`: comma list of front,three_quarter,side,rear,three_quarter_back. Trailing `id` switches
from material beauty to the flat garment-ID pass."""
import math
import os
import sys

import bpy
from mathutils import Vector

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.abspath(os.path.join(_HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(_ROOT, "tools", "blender", "inspect"))
sys.path.insert(0, os.path.join(_ROOT, "tools", "blender", "authoring"))
sys.path.insert(0, os.path.join(_ROOT, "tools", "character_modeling"))
import exposure_check  # noqa: E402
import pose_fixture  # noqa: E402
import skeleton_capture  # noqa: E402

a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=a[0])
prefix, clipspec, out = a[1], a[2], a[3]
target = Vector([float(x) for x in a[4].split(",")])
scale, views = float(a[5]), a[6].split(",")
idcolors = len(a) > 7 and a[7] == "id"
rig = bpy.data.objects[prefix + ".Armature"]
mine = []
for o in bpy.data.objects:
    if o.type != "MESH":
        continue
    part = o.name.split(".", 1)[1] if "." in o.name else ""
    o.hide_render = not o.name.startswith(prefix + ".") or part.startswith("DeadEye")
    if not o.hide_render:
        mine.append(o)
exposure_check._bind_head_parts(mine, rig)

sc = bpy.context.scene
if idcolors:
    ## Flat IDs: skin red, each garment its own hue, so an opening reads by its edge colours.
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "VERTEX"
    sc.display.shading.show_backface_culling = True
    palette = [(0.1, 0.5, 1.0), (1.0, 0.6, 0.0), (0.6, 1.0, 0.2), (0.8, 0.2, 1.0), (0.0, 0.8, 0.8),
               (1.0, 0.9, 0.2), (0.5, 0.5, 0.5), (0.3, 0.3, 0.9), (0.9, 0.4, 0.5)]
    n = 0
    for o in sorted(mine, key=lambda o: o.name):
        part = o.name.split(".", 1)[1]
        me = o.data
        attr = me.color_attributes.get("riposte_idc") or me.color_attributes.new("riposte_idc", "BYTE_COLOR", "POINT")
        if part in ("Body", "Head") or part.startswith(("Ear", "Eye", "Brow")):
            col = (1.0, 0.0, 0.0)
        else:
            col = palette[n % len(palette)]
            n += 1
        for d in attr.data:
            d.color = (*col, 1.0)
        me.color_attributes.active_color = attr
        me.attributes.active_color = attr
        print("IDCOLOR", part, tuple(round(c, 2) for c in col))
else:
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "MATERIAL"
    sc.display.shading.show_specular_highlight = False
sc.view_settings.view_transform = "Standard"
sc.render.resolution_x = sc.render.resolution_y = 900
sc.render.film_transparent = True

pose_fixture.reset(rig)
if clipspec != "rest":
    name, frame = clipspec.split(":")
    exposure_check._play(rig, bpy.data.actions[name], int(frame))
bpy.context.view_layer.update()

cd = bpy.data.cameras.new("c")
cd.type, cd.ortho_scale = "ORTHO", scale
cam = bpy.data.objects.new("c", cd)
sc.collection.objects.link(cam)
sc.camera = cam
angles = {"front": 0.0, "three_quarter": 35.0, "side": 90.0, "rear": 180.0, "three_quarter_back": 145.0}
for v in views:
    ang = math.radians(angles[v])
    cam.location = target + Vector((math.sin(ang), -math.cos(ang), 0.0)) * 6.0
    cam.rotation_euler = (math.radians(90.0), 0.0, ang)
    skeleton_capture.render_still(sc, "%s_%s.png" % (out, v), "clip_render", {"view": v, "clip": clipspec})
print("RIPOSTE_CLIP_RENDER", len(views))
