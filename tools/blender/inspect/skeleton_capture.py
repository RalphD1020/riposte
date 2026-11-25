"""SKELETON-CAPTURE-001 in Blender: render a still and write its skeleton sidecar beside it.

Every inspect / authoring script that renders a skeleton-bearing character calls `render_still`
instead of `bpy.ops.render.render(write_still=True)`, so each PNG carries `<png>.skeleton.json`:
the camera, every rendered armature's evaluated pose bones (world head / tail, world rotation, the
pixel each head lands on, in front / in frame), the shared arm readings and provisional heuristics
per skeleton (`skeleton_capture_core`), and the primary skeleton's (most joints in frame) at the
top level. A scene with no rendered armature writes no sidecar."""

import json
import os
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import skeleton_capture_core as core  # noqa: E402

UP = (0.0, 0.0, 1.0)


def render_still(scene, path, tool, extra=None):
    """Render `scene` to `path` (absolute) and write its sidecar; returns the sidecar path or ""."""
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return write(scene, path, tool, extra)


def _frame(scene):
    """Rendered pixel size and the normalized camera-view window the image covers (border crop)."""
    percent = scene.render.resolution_percentage / 100.0
    width, height = scene.render.resolution_x * percent, scene.render.resolution_y * percent
    if scene.render.use_border and scene.render.use_crop_to_border:
        r = scene.render
        return (width * (r.border_max_x - r.border_min_x), height * (r.border_max_y - r.border_min_y),
                (r.border_min_x, r.border_min_y, r.border_max_x, r.border_max_y))
    return width, height, (0.0, 0.0, 1.0, 1.0)


def _pixel(scene, camera, point, window, size):
    view = world_to_camera_view(scene, camera, point)
    x0, y0, x1, y1 = window
    u = (view.x - x0) / (x1 - x0) * size[0]
    v = (1.0 - (view.y - y0) / (y1 - y0)) * size[1]
    return [round(u, 2), round(v, 2)], view.z > 0.0, 0.0 <= u <= size[0] and 0.0 <= v <= size[1]


def _distance(a, b):
    return sum((a[i] - b[i]) ** 2 for i in range(3)) ** 0.5


def _segment_lengths(posed, rest):
    """Per side the posed and rest upper-arm / forearm lengths (joint to joint) for the hard check."""
    out = {}
    for side, (upper, fore, hand) in core.ARM_BONES.items():
        if all(n in posed and n in rest for n in (upper, fore, hand)):
            out[side] = {"upper": _distance(posed[upper], posed[fore]), "fore": _distance(posed[fore], posed[hand]),
                         "upper_rest": _distance(rest[upper], rest[fore]), "fore_rest": _distance(rest[fore], rest[hand])}
    return out


def write(scene, path, tool, extra=None):
    camera = scene.camera
    rigs = [o for o in scene.objects if o.type == "ARMATURE" and not o.hide_render and o.visible_get()]
    if camera is None or not rigs:
        return ""
    bpy.context.view_layer.update()
    width, height, window = _frame(scene)
    size = (width, height)
    skeletons = []
    for rig in rigs:
        bones = []
        positions = {}
        for bone in rig.pose.bones:
            head = rig.matrix_world @ bone.head
            tail = rig.matrix_world @ bone.tail
            rotation = (rig.matrix_world @ bone.matrix).to_quaternion()
            pixel, in_front, in_frame = _pixel(scene, camera, head, window, size)
            bones.append({
                "name": bone.name, "parent": bone.parent.name if bone.parent else None,
                "position": [round(c, 5) for c in head], "tail": [round(c, 5) for c in tail],
                "rotation_xyzw": [round(rotation.x, 6), round(rotation.y, 6), round(rotation.z, 6), round(rotation.w, 6)],
                "pixel": pixel if in_front else None, "in_front": in_front, "in_frame": in_frame and in_front,
            })
            positions[bone.name] = tuple(head)
        arms = core.arm_readings(positions, UP)
        rest = {b.name: tuple(rig.matrix_world @ b.head_local) for b in rig.data.bones}
        skeletons.append({"name": rig.name, "arms": arms, "heuristics": core.heuristics(arms, _segment_lengths(positions, rest)), "bones": bones})
    ## The image's subject: the skeleton with the most joints inside the frame.
    primary = max(range(len(skeletons)), key=lambda i: sum(1 for b in skeletons[i]["bones"] if b["in_frame"]))
    data = camera.data
    sidecar = {
        "schema": core.SCHEMA, "version": core.VERSION, "engine": "blender", "tool": tool, "up": list(UP), "units": "m",
        "image": {"file": os.path.basename(path), "width": round(width), "height": round(height)},
        "frame": scene.frame_current,
        "camera": {
            "projection": "orthographic" if data.type == "ORTHO" else "perspective",
            "ortho_scale": data.ortho_scale if data.type == "ORTHO" else None,
            "fov_deg": round(data.angle * 57.29577951308232, 4) if data.type != "ORTHO" else None,
            "position": [round(c, 5) for c in camera.matrix_world.translation],
            "rotation_xyzw": [round(c, 6) for c in (lambda q: (q.x, q.y, q.z, q.w))(camera.matrix_world.to_quaternion())],
        },
        "skeletons": skeletons,
        "primary": primary,
        "arms": skeletons[primary]["arms"],
        "heuristics": skeletons[primary]["heuristics"],
        "extra": extra or {},
    }
    out = core.sidecar_path(path)
    with open(out, "w", encoding="utf-8") as handle:
        json.dump(sidecar, handle, indent=1)
    return out
