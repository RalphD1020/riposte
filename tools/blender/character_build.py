"""Emit one compiled blockout part. Fighters and the crowd both call this.

`character_art.compile` has already resolved anchors to metres. This module
does not know whether the mesh will be rigged for a fight or joined into a
crowd layer, and it does not multiply by `body_scale`. The parts are the
blockout. A finished skull, chest, garment, or boot is an authored surface
on the same rig, not a new kind added here.
"""

import bpy

import character_art
import riposte_blocks as rb


def materials_for(data, variant):
    colors = character_art.palette_for(data, variant)
    made = {}
    for slot, body in colors.items():
        color = character_art.linear_color(body["color"])
        name = "costume_metal" if slot == "metal" else slot
        extra = {}
        if slot == "metal" or "metallic" in body:
            extra = {"metallic": body.get("metallic", 0.0)}
        made[slot] = rb.material(name, color, roughness=body.get("roughness", 0.8), **extra)
    accent = data.get("side_accent")
    if isinstance(accent, dict):
        made["side_accent"] = rb.material(
            "side_accent", character_art.linear_color(accent["preview"]), roughness=accent.get("roughness", 0.7),
        )
    return made


def emit_part(data, part, materials, variant):
    """One prism, box, dome, or clump. Segments stay with the fighter builder:
    they bind a limb to the rig."""
    mat = materials[part["slot"]]
    if part.get("paint") == "stubble":
        skin = character_art.palette_for(data, variant)["skin"]
        color = character_art.linear_color(skin["color"])
        mat = rb.material_with_mask("skin_head", color, rb.stubble_mask(color), roughness=skin.get("roughness", 0.75))
    kind = part["kind"]
    if kind == "prism":
        return rb.prism(
            part["name"], int(part["sides"]), part["radius"], part["z0"], part["z1"], mat,
            depth_scale=part.get("depth_scale", 1.0), top_scale=part.get("top_scale", 1.0),
            spin=part.get("spin", 0.0), bevel=part.get("bevel", 0.0),
            face_uv=part.get("paint") == "stubble",
        )
    if kind == "box":
        return rb.box(
            part["name"], tuple(character_art.part_value(data, part, variant, "size")), tuple(part["at"]), mat,
            bevel=part.get("bevel", 0.0), rotation=tuple(part.get("rotation", (0.0, 0.0, 0.0))),
        )
    if kind == "dome":
        apex = None if part.get("closure") == "face" else tuple(part["apex"])
        return rb.dome(
            part["name"], int(part["sides"]), part["radius"], part["rings"], apex, mat,
            depth_scale=part.get("depth_scale", 1.0), spin=part.get("spin", 0.0), bevel=part.get("bevel", 0.0),
            thickness=part.get("thickness", 0.0),
        )
    if kind == "clump":
        return rb.clump(
            part["name"],
            character_art.part_value(data, part, variant, "points"),
            character_art.part_value(data, part, variant, "width"),
            character_art.part_value(data, part, variant, "depth"),
            mat, bevel=part.get("bevel", 0.0), profile=part.get("profile", "gem"),
        )
    if kind == "segment":
        overlap = part.get("joint_overlap") or {}
        overlap_from = float(overlap.get("from", 0.0))
        overlap_to = float(overlap.get("to", 0.0))
        if "width_to" in part or "depth_to" in part:
            return rb.tapered_segment(
                part["name"], tuple(part["a"]), tuple(part["b"]),
                part["width"], part["depth"],
                part.get("width_to", part["width"]), part.get("depth_to", part["depth"]),
                mat, bevel=part.get("bevel", 0.0),
                overlap_from=overlap_from, overlap_to=overlap_to,
                rings=int(part.get("rings", 2)),
            )
        return rb.span(
            part["name"], tuple(part["a"]), tuple(part["b"]), part["width"], part["depth"], mat,
            bevel=part.get("bevel", 0.006),
            overlap_from=overlap_from, overlap_to=overlap_to,
        )
    return None


def bake(obj):
    """Write the object transform into the vertices and clear it. A fighter
    does this before skinning so the bone, not the object origin, carries the
    limb. The crowd join bakes parented spans the same way."""
    bpy.context.view_layer.update()
    obj.data.transform(obj.matrix_world)
    obj.matrix_world.identity()


def emit_visible(data, materials, variant, wears=None):
    made = []
    for part in data["parts"]:
        if wears is not None and part.get("wear") not in wears:
            continue
        if not character_art.visible(part, variant, data):
            continue
        obj = emit_part(data, part, materials, variant)
        if obj is not None:
            made.append(obj)
    return made
