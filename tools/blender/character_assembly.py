"""Character assembly: a base in a configuration + a character's identity and outfit (CHARACTER-SOURCE-001).

The base owns anatomy; the assembly owns what is present. It never changes
anatomy: it bakes a named configuration of the base's physique keys, splits the
base's head island out as `HeadSkin`, attaches the character's identity
objects (face marks; later hair and garments) rigidly or skinned on WolfRig,
and applies the character's intrinsic palette. Everything happens in memory on
a copy opened from the base; no source blend is ever saved.

A character manifest (`riposte.character_assembly`) pins the base's topology
fingerprint and WolfRig's contract digest; assembly refuses a mismatch, so a
character or garment built against an older base cannot silently export.
"""

import hashlib
import json
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "character_modeling"))

from character_modeling import garments  # noqa: E402
from character_modeling import identity as identity_profile  # noqa: E402

SCHEMA = "riposte.character_assembly"
BODY = "Body"
HEAD = "Head"
HEAD_SKIN = "HeadSkin"
## The head island: the skull joined into the base, riding Head alone.
HEAD_ISLAND_MIN_WEIGHT = 0.99


def topology_fingerprint(mesh_object):
    """sha256 over the vertex count and every face's vertex indices: the
    topology garments and regions are keyed to. Positions are not part of it
    (a shape pass does not change it); a retopology does."""
    digest = hashlib.sha256()
    digest.update(str(len(mesh_object.data.vertices)).encode())
    for polygon in mesh_object.data.polygons:
        digest.update(b"|")
        digest.update(",".join(str(i) for i in polygon.vertices).encode())
    return digest.hexdigest()


def head_topology_fingerprint(faces):
    """sha256 over the head's own face topology, its vertex indices renumbered in
    first-use order (HEAD-FIT-001): it sits beside the full fingerprint, so a body
    revision leaves it unchanged and a face revision changes it alone."""
    order = {}
    digest = hashlib.sha256()
    for face in faces:
        digest.update(b"|")
        digest.update(",".join(str(order.setdefault(i, len(order))) for i in face).encode())
    return digest.hexdigest()


def head_island_faces(body):
    """The head island's faces (every vertex rides Head alone, above the neck)."""
    head = body.vertex_groups[HEAD].index
    world = body.matrix_world
    island = {v.index for v in body.data.vertices
              if (world @ v.co).z > 1.5 and any(g.group == head and g.weight >= HEAD_ISLAND_MIN_WEIGHT for g in v.groups)}
    return [list(p.vertices) for p in body.data.polygons if all(i in island for i in p.vertices)]


def rig_contract_digest(path):
    """sha256 over the contract's bones (names, parents, heads, tails), canonical JSON."""
    with open(path, encoding="utf-8") as handle:
        contract = json.load(handle)
    canonical = json.dumps(contract["bones"], sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode()).hexdigest()


def linear(srgb):
    """sRGB [0, 1] to linear, the one conversion (as `character_art.linear_color`)."""
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb)


def bake_configuration(body, values, parameters):
    """Mix a configuration's physique keys into the rest mesh and remove the
    keys. Returns problems; an empty list means the body is baked."""
    ranges = {p["id"]: p["range"] for p in parameters}
    if body.data.shape_keys is None:
        return ["%s carries no physique keys" % body.name] if values else []
    blocks = body.data.shape_keys.key_blocks
    problems = []
    weights = {}
    for parameter, value in values.items():
        if parameter not in ranges:
            problems.append("unknown physique parameter %s" % parameter)
        elif not ranges[parameter][0] <= value <= ranges[parameter][1]:
            problems.append("%s = %s outside %s" % (parameter, value, ranges[parameter]))
        elif value != 0:
            key = "%s_%s" % (parameter, "plus" if value > 0 else "minus")
            if key not in blocks:
                problems.append("missing physique key %s" % key)
            else:
                weights[key] = abs(value)
    if problems:
        return problems
    basis = blocks[0].data
    mixed = [point.co.copy() for point in basis]
    for key, weight in weights.items():
        for index, point in enumerate(blocks[key].data):
            mixed[index] += (point.co - basis[index].co) * weight
    body.shape_key_clear()
    for vertex, point in zip(body.data.vertices, mixed):
        vertex.co = point
    return []


def _head_island(body):
    """Vertex indices of the connected component that rides Head alone."""
    head = body.vertex_groups[HEAD].index
    bm = bmesh.new()
    bm.from_mesh(body.data)
    deform = bm.verts.layers.deform.active
    seen = set()
    for start in bm.verts:
        if start.index in seen:
            continue
        component = []
        stack = [start]
        seen.add(start.index)
        while stack:
            v = stack.pop()
            component.append(v)
            for edge in v.link_edges:
                other = edge.other_vert(v)
                if other.index not in seen:
                    seen.add(other.index)
                    stack.append(other)
        if all(v[deform].get(head, 0.0) >= HEAD_ISLAND_MIN_WEIGHT for v in component):
            indices = [v.index for v in component]
            bm.free()
            return indices
    bm.free()
    return []


def split_head(body):
    """Separate the head island into its own object `HeadSkin`, rigid on Head."""
    island = set(_head_island(body))
    if not island:
        raise SystemExit("RIPOSTE_ASSEMBLY: no head island on %s" % body.name)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    for vertex in body.data.vertices:
        vertex.select = vertex.index in island
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    head = next(o for o in bpy.context.selected_objects if o is not body)
    head.name = HEAD_SKIN
    head.data.name = HEAD_SKIN
    for group in list(head.vertex_groups):
        if group.name != HEAD:
            head.vertex_groups.remove(group)
    return head


def bind_rigid(obj, rig, bone):
    """One bone, weight 1, the armature modifier: a rigid part on WolfRig."""
    obj.vertex_groups.clear()
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    obj.parent = rig


def append_collection(path, name):
    """Append a collection's objects from another blend into this scene."""
    with bpy.data.libraries.load(path, link=False) as (source, target):
        if name not in source.collections:
            raise SystemExit("RIPOSTE_ASSEMBLY: %s has no collection %s" % (path, name))
        target.collections = [name]
    collection = target.collections[0]
    objects = list(collection.all_objects)
    for obj in objects:
        bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.update()
    return objects


def material(name, srgb, roughness, metallic=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*linear(srgb), 1.0)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    mat.diffuse_color = (*linear(srgb), 1.0)
    return mat


def _library_path(manifest, blender_root, *parts):
    """A path in the garment library (`art-src/blender/garments/` unless the manifest names another)."""
    library = manifest.get("garment_library", "garments")
    root = library if os.path.isabs(library) else os.path.join(blender_root, library)
    return os.path.join(root, *parts)


def load_outfit(manifest, outfit, blender_root):
    """The outfit's garment definitions and the base's fitting regions, with every
    compatibility problem (garments.outfit_problems)."""
    regions_path = os.path.splitext(os.path.join(blender_root, manifest["base"]["source"]))[0] + ".regions.json"
    with open(regions_path, encoding="utf-8") as handle:
        regions = json.load(handle)
    definitions = [garments.load(_library_path(manifest, blender_root, "%s.garment.json" % gid))
                   for gid in manifest["outfits"][outfit].get("garments", [])]
    return definitions, regions, garments.outfit_problems(definitions, manifest, regions)


def mask_body(body, definitions, regions):
    """Remove, in this in-memory copy only, the base faces the outfit hides
    (garments.masked_faces). Returns (faces removed, open edges left for the
    garment to cover). Run before `split_head`: indices are the canonical topology."""
    hidden = garments.hidden_vertices(definitions, regions)
    if not hidden:
        return 0, []
    margin = min((d["coverage"].get("margin_rings", 1) for d in definitions if d.get("coverage", {}).get("hides")), default=1)
    faces = [tuple(p.vertices) for p in body.data.polygons]
    removed = garments.masked_faces(faces, hidden, margin)
    holes = garments.open_boundary_after_mask(faces, removed)
    edge_midpoints = [(body.matrix_world @ ((body.data.vertices[a].co + body.data.vertices[b].co) * 0.5)) for a, b in holes]
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.faces.ensure_lookup_table()
    doomed = set(removed)
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in doomed], context="FACES_ONLY")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(body.data)
    bm.free()
    return len(removed), edge_midpoints


def exposed_holes(edge_midpoints, garment_objects, reach_m):
    """Mask edges no garment surface covers within `reach_m`: a hole that would show."""
    from mathutils.bvhtree import BVHTree

    if not edge_midpoints:
        return 0
    points, polygons = [], []
    for obj in garment_objects:
        offset = len(points)
        points += [obj.matrix_world @ v.co for v in obj.data.vertices]
        polygons += [[offset + i for i in p.vertices] for p in obj.data.polygons]
    if not polygons:
        return len(edge_midpoints)
    tree = BVHTree.FromPolygons(points, polygons)
    exposed = 0
    for p in edge_midpoints:
        nearest, _normal, _index, distance = tree.find_nearest(p)
        if nearest is None or distance > reach_m:
            exposed += 1
    return exposed


def attach_garment(definition, manifest, blender_root, rig, values, parameters, palette_materials):
    """Append a garment from its source blend, bind it on WolfRig (skinned or
    rigid), bake its physique keys with the body's configuration and give it the
    outfit's costume materials. Returns problems."""
    source = definition["source"]
    blend = source["blend"] if os.path.isabs(source["blend"]) else os.path.join(blender_root, source["blend"])
    with bpy.data.libraries.load(blend, link=False) as (available, target):
        if source["object"] not in available.objects:
            return ["%s: %s has no object %s" % (definition["id"], blend, source["object"])]
        target.objects = [source["object"]]
    garment = target.objects[0]
    bpy.context.scene.collection.objects.link(garment)
    world = garment.matrix_world.copy()
    garment.parent = None
    garment.matrix_world = world
    problems = []
    deformation = definition["deformation"]
    if deformation["method"] == "rigid":
        bind_rigid(garment, rig, deformation["bone"])
    else:
        bones = {b.name for b in rig.data.bones}
        stray = sorted(g.name for g in garment.vertex_groups if g.name not in bones)
        if stray:
            problems.append("%s: vertex groups name no WolfRig bone %s" % (definition["id"], stray))
        for modifier in [m for m in garment.modifiers if m.type == "ARMATURE"]:
            garment.modifiers.remove(modifier)
        modifier = garment.modifiers.new("Armature", "ARMATURE")
        modifier.object = rig
        garment.parent = rig
    worn = sorted({slot.name.split(".")[0] for slot in garment.data.materials if slot})
    undeclared = [name for name in worn if name not in definition["materials"]]
    if undeclared:
        problems.append("%s wears material slots its definition does not declare %s" % (definition["id"], undeclared))
    follows = deformation.get("physique", "keys") == "keys"
    if garment.data.shape_keys is not None or (follows and any(v for v in values.values())):
        problems += ["%s: %s" % (definition["id"], p) for p in bake_configuration(garment, values, parameters)]
    for index, slot in enumerate(garment.data.materials):
        name = slot.name.split(".")[0] if slot else ""
        if name in palette_materials:
            garment.data.materials[index] = palette_materials[name]
    garment["riposte_garment"] = definition["id"]
    return problems


def assemble(manifest_path, asset_id, blender_root):
    """Build the asset `asset_id` of a character manifest into the current
    session. Returns (export row, problems)."""
    with open(manifest_path, encoding="utf-8") as handle:
        manifest = json.load(handle)
    if manifest.get("schema") != SCHEMA:
        return None, ["%s is not a %s" % (manifest_path, SCHEMA)]
    row = next((e for e in manifest["exports"] if e["id"] == asset_id), None)
    if row is None:
        return None, ["%s exports no %s" % (manifest_path, asset_id)]
    base = manifest["base"]
    repo = os.path.abspath(os.path.join(blender_root, "..", ".."))
    bpy.ops.wm.open_mainfile(filepath=os.path.join(blender_root, base["source"]))
    body = bpy.data.objects[BODY]
    rig = body.parent
    problems = []
    fingerprint = topology_fingerprint(body)
    if fingerprint != base["topology_fingerprint"]:
        problems.append("base topology %s.. is not the manifest's %s.." % (fingerprint[:12], base["topology_fingerprint"][:12]))
    skeleton = manifest["skeleton"]
    digest = rig_contract_digest(os.path.join(repo, skeleton["contract"]))
    if digest != skeleton["contract_sha256"]:
        problems.append("rig contract %s.. is not the manifest's %s.." % (digest[:12], skeleton["contract_sha256"][:12]))
    configuration_path = os.path.splitext(os.path.join(blender_root, base["source"]))[0] + ".configuration.json"
    with open(configuration_path, encoding="utf-8") as handle:
        configuration = json.load(handle)
    name = row["configuration"]
    if name not in manifest["physique"]["supported_configurations"]:
        problems.append("configuration %s is not supported by %s" % (name, manifest["id"]))
    definitions, regions, outfit_problems = load_outfit(manifest, row["outfit"], blender_root)
    problems += outfit_problems
    problems += identity_profile.problems(manifest, row["outfit"], definitions)
    unsupported = [d["id"] for d in definitions if name not in d["supported_configurations"]]
    if unsupported:
        problems.append("garments %s do not support configuration %s" % (unsupported, name))
    values = configuration["configurations"][name]
    problems += bake_configuration(body, values, configuration["parameters"])
    if problems:
        return row, problems
    removed, hole_midpoints = mask_body(body, definitions, regions)
    bpy.context.scene["riposte_masked_faces"] = removed
    bpy.context.scene["riposte_mask_open_edges"] = len(hole_midpoints)
    head = split_head(body)
    identity = manifest["identity"]
    palette = identity["palette"]
    skin = material("skin", palette["skin"]["srgb"], palette["skin"]["roughness"])
    hair = material("hair", palette["hair"]["srgb"], palette["hair"]["roughness"])
    for obj in (body, head):
        obj.data.materials.clear()
        obj.data.materials.append(skin)
    attire = os.path.join(blender_root, identity["source"])
    for collection in identity["collections"] + manifest["outfits"][row["outfit"]]["collections"]:
        for obj in append_collection(attire, collection):
            if obj.type != "MESH":
                continue
            slot = obj.get("riposte_slot", "hair")
            obj.data.materials.clear()
            obj.data.materials.append(hair if slot == "hair" else skin)
            bind_rigid(obj, rig, obj.get("riposte_bone", HEAD))
    outfit = manifest["outfits"][row["outfit"]]
    costume = {slot: material(slot, spec["srgb"], spec.get("roughness", 0.8), spec.get("metallic", 0.0))
               for slot, spec in outfit.get("palette", {}).items()}
    ## Intrinsic materials are the identity's (a hair asset wears Wolf's hair), costume the
    ## outfit's; a costume never recolors identity (identity_profile.problems refuses it first).
    worn_materials = {**costume, "skin": skin, "hair": hair}
    for definition in definitions:
        problems += attach_garment(definition, manifest, blender_root, rig, values, configuration["parameters"], worn_materials)
    if problems:
        return row, problems
    worn = [o for o in bpy.context.scene.objects if o.get("riposte_garment")]
    reach = max((garments.clearance_for(d, regions, "default")[1] for d in definitions if d.get("coverage", {}).get("hides")), default=0.0)
    exposed = exposed_holes(hole_midpoints, worn, reach)
    if exposed:
        return row, ["%d of %d mask edges are not covered by a garment within %.3f m" % (exposed, len(hole_midpoints), reach)]
    bpy.context.scene["riposte_outfit"] = row["outfit"]
    ## A work-in-progress outfit (hair only, a garment under review) exports for
    ## review without the side-accent pieces; a complete outfit must carry them.
    bpy.context.scene["riposte_outfit_complete"] = bool(outfit.get("complete", row["outfit"] != "bare"))
    bpy.context.scene["riposte_character"] = manifest["id"]
    bpy.context.scene["riposte_review_triangles"] = manifest["budget"]["review_triangles"]
    bpy.context.scene["riposte_max_triangles"] = manifest["budget"]["max_triangles"]
    return row, []
