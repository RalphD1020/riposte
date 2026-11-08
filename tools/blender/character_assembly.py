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


def identity_materials(manifest, repo):
    """The identity's intrinsic materials (skin from its shared swatch, hair): (skin, hair)."""
    swatches = identity_profile.load_swatches(manifest, repo)
    palette = manifest["identity"]["palette"]
    return tuple(material(slot, identity_profile.palette_srgb(manifest, slot, swatches), palette[slot]["roughness"])
                 for slot in (identity_profile.SKIN, "hair"))


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
    problems += identity_profile.problems(manifest, row["outfit"], definitions, identity_profile.load_swatches(manifest, repo))
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
    skin, hair = identity_materials(manifest, repo)
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


## The character on the approved v2 base (CHARACTER-PIPELINE-001, attachments): the
## identity's face marks and hairstyles fitted to the approved head through the shared
## builders (`face_features.place_marks`, `wolf_hair.head_frame_of` / `build_style`) in the
## authoring A-pose, measured, then returned to the rest through the Head bone's own
## skinning and bound rigid on Head. Hanging-hair weights are topology-dependent data and
## are rebuilt after topology finalization (CHARACTER-TOPOLOGY-001), not here.
## Hair closer than this behind the head or body surface counts as inside it.
HAIR_INSIDE_TOLERANCE_M = 0.002
## The face the hair must keep clear (FACE-IDENTITY-001), in the head's chart.
FACE_CLEAR_U = 0.70
FACE_CLEAR_V = (0.30, 0.80)


def _authoring():
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "authoring"))
    import male_base_v2
    import face_features
    import wolf_hair
    return male_base_v2, face_features, wolf_hair


def _tree_of(obj):
    from mathutils.bvhtree import BVHTree
    points = [obj.matrix_world @ v.co for v in obj.data.vertices]
    return BVHTree.FromPolygons(points, [list(p.vertices) for p in obj.data.polygons])


def _inside(obj, tree):
    count, deepest = 0, 0.0
    for v in obj.data.vertices:
        p = obj.matrix_world @ v.co
        location, normal, _i, _d = tree.find_nearest(p)
        if location is None:
            continue
        depth = -(p - location).dot(normal)
        if depth > HAIR_INSIDE_TOLERANCE_M:
            count += 1
            deepest = max(deepest, depth)
    return {"vertices": count, "deepest_mm": round(deepest * 1000, 1)}


def _face_intrusion(obj, chart, head_tree):
    """Hair vertices over the face (the chart's face window, in front of the head's centre)."""
    from mathutils import Vector
    low, height, half_width, centre_y = chart
    count = 0
    for v in obj.data.vertices:
        p = obj.matrix_world @ v.co
        u, z = abs(p.x) / half_width, (p.z - low) / height
        if u < FACE_CLEAR_U and FACE_CLEAR_V[0] < z < FACE_CLEAR_V[1] and p.y < centre_y:
            hit = head_tree.ray_cast(Vector((p.x, p.y - 0.5, p.z)), Vector((0.0, 1.0, 0.0)))[0]
            if hit is None or p.y <= hit.y + 0.001:
                count += 1
    return count


def _clearance(obj, head_tree):
    """A mark's vertices' signed distance off the head surface, mm: [min, max]."""
    distances = []
    for v in obj.data.vertices:
        p = obj.matrix_world @ v.co
        location, normal, _i, _d = head_tree.find_nearest(p)
        distances.append((p - location).dot(normal))
    return [round(min(distances) * 1000, 2), round(max(distances) * 1000, 2)]


## Samples per triangle edge of a layer's surface clearance (a barycentric grid).
SURFACE_SAMPLES = 4


def _surface_clearance(obj, head_tree):
    """A layer's closest approach to the head across its faces, not only its vertices (a
    face's chord can dip under a curved panel between them), mm."""
    worst = None
    points = [obj.matrix_world @ v.co for v in obj.data.vertices]
    for polygon in obj.data.polygons:
        ring = [points[i] for i in polygon.vertices]
        for k in range(1, len(ring) - 1):
            a, b, c = ring[0], ring[k], ring[k + 1]
            for i in range(SURFACE_SAMPLES + 1):
                for j in range(SURFACE_SAMPLES + 1 - i):
                    p = (a * i + b * j + c * (SURFACE_SAMPLES - i - j)) / SURFACE_SAMPLES
                    location, normal, _i, _d = head_tree.find_nearest(p)
                    distance = (p - location).dot(normal)
                    worst = distance if worst is None else min(worst, distance)
    return round(worst * 1000, 3)


def _gap(a, b):
    """The nearest distance between two objects' vertices and the other's surface, mm."""
    tree = _tree_of(b)
    return round(min(tree.find_nearest(a.matrix_world @ v.co)[3] for v in a.data.vertices) * 1000, 1)


def palette_materials(manifest, repo):
    """Every intrinsic identity material (skin from its shared swatch; hair and the eye's
    eye, iris, pupil and catchlight from the palette): {slot: material}."""
    swatches = identity_profile.load_swatches(manifest, repo)
    palette = manifest["identity"]["palette"]
    return {slot: material(slot, identity_profile.palette_srgb(manifest, slot, swatches), palette[slot]["roughness"])
            for slot in manifest["materials"]["intrinsic"]}


def dress_face(made, materials):
    """The face features' material slots by component (`eye_assembly.MATERIALS`; the dead X
    in hair, hidden from renders: it shows only for `dead`)."""
    from character_modeling import eye_assembly
    for obj, component, _side in made:
        obj.data.materials.clear()
        for slot in eye_assembly.MATERIALS.get(component, ("hair",)):
            obj.data.materials.append(materials[slot])
        slots = obj.data.attributes.get("riposte_material_slot")
        if slots is not None:
            indices = [0] * len(obj.data.polygons)
            slots.data.foreach_get("value", indices)
            obj.data.polygons.foreach_set("material_index", indices)
            obj.data.attributes.remove(slots)
        obj.hide_render = component == "dead"


def set_face(made, preset, gaze=None, blink=0.0, scale=1.0):
    """Every face feature's channel keys at preset `preset` (scaled), with a gaze and a blink."""
    from character_modeling import expressions
    for obj, _component, side in made:
        keys = obj.data.shape_keys
        if keys is None:
            continue
        weights = expressions.weights(preset, side, gaze=gaze, blink=blink)
        for block in keys.key_blocks[1:]:
            w = weights.get(block.name, 0.0)
            block.value = w if block.name.startswith(("gaze", "blink")) else w * scale


## Face states checked on the built meshes (FACE-EYE-001): every preset at these weights,
## alone and with each gaze extreme, and the blink.
FACE_CHECK_SCALES = (0.5, 1.0)
FACE_CHECK_GAZES = (None, (1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0))
## A ray this long from an iris vertex toward the head must meet the eye white under it;
## within this of the white's edge a vertex is at the edge (the layers sit at slightly
## different depths along slightly different normals, and the white's segments chord the
## drawn edge: up to 0.36 mm measured at full aggressive with a sideways gaze, 2026-11-01;
## one or two pixels at the close-up review scale).
FACE_RAY_M = 0.006
FACE_EDGE_TOLERANCE_M = 0.0004
## The white-over-iris ray starts this far in front of the iris vertex (the white lies a
## fraction of a millimetre behind the iris; a start behind the vertex meets it from behind).
FACE_FRONT_START_M = 0.00002


## A masked iris vertex is covered when the eye mask's nearest surface lies in front of it
## (on the side away from the head) within this distance: the mask stands a fraction of a
## millimetre over the iris. Geometric, not a ray along the head's nearest normal (at the
## panel's crease that normal tilts and a ray misses a mask that is there).
FACE_MASK_COVER_M = 0.0015


def _under(mask, p, inward):
    if mask is None:
        return False
    location, _normal, _i, distance = mask.find_nearest(p)
    return location is not None and distance <= FACE_MASK_COVER_M and (location - p).dot(inward) < 0.0


def face_checks(made, head_tree):
    """Structural checks of the built anime eye (never an art verdict): in every checked
    state every iris vertex is covered: over the eye white (a ray from it toward the head
    meets the white) or under the lash line; no white in front of the iris outside the
    lash line and mask (`white_over_iris`: states where it shows through); the brows and
    lines off the head; the white's closest approach to the head across its faces
    (`white_clearance_mm`, at neutral: the head must not show through it); the neutral gap
    between brow and lash line. Keys are reset to neutral afterwards."""
    from mathutils.bvhtree import BVHTree
    from character_modeling import expressions
    depsgraph = bpy.context.evaluated_depsgraph_get()

    def evaluated(obj):
        mesh = obj.evaluated_get(depsgraph).data
        return [obj.matrix_world @ v.co for v in mesh.vertices], [list(p.vertices) for p in mesh.polygons]

    states = [("neutral", None, 1.0, 0.0), ("neutral", None, 1.0, 0.5)]
    states += [(n, g, k, 0.0) for n in expressions.KEYED for k in FACE_CHECK_SCALES for g in FACE_CHECK_GAZES]
    states += [("neutral", g, 1.0, 0.0) for g in FACE_CHECK_GAZES[1:]]
    report = {"states": len(states), "iris_off_white": 0, "examples": [], "white_over_iris": 0, "white_over_examples": []}
    for preset, gaze, scale, blink in states:
        set_face(made, preset, gaze, blink, scale)
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        for side in ("L", "R"):
            parts = {c: o for o, c, s in made if s == side}
            white = BVHTree.FromPolygons(*evaluated(parts["eye"]))
            line = BVHTree.FromPolygons(*evaluated(parts["line"]))
            mask = BVHTree.FromPolygons(*evaluated(parts["mask"])) if "mask" in parts else None
            for p in evaluated(parts["iris"])[0]:
                _location, normal, _i, _d = head_tree.find_nearest(p)
                inward = normal if normal.y > 0.0 else -normal
                ## The white in front of the iris (toward the viewer), not under the lash
                ## line or the mask: the white showing through it.
                if (white.ray_cast(p - inward * FACE_FRONT_START_M, -inward, FACE_RAY_M)[0] is not None
                        and line.ray_cast(p, -inward, FACE_RAY_M)[0] is None and not _under(mask, p, inward)):
                    report["white_over_iris"] += 1
                    if len(report["white_over_examples"]) < 6:
                        report["white_over_examples"].append("%s %s %s x%.1f blink %.1f" % (side, preset, gaze, scale, blink))
                    break
            for p in evaluated(parts["iris"])[0]:
                _location, normal, _i, _d = head_tree.find_nearest(p)
                inward = normal if normal.y > 0.0 else -normal
                ## Covered when the white is under it, or the lash line or the eye mask
                ## (a masked eye's occlusion) over it.
                if (white.ray_cast(p, inward, FACE_RAY_M)[0] is None and line.ray_cast(p, -inward, FACE_RAY_M)[0] is None
                        and not _under(mask, p, inward)
                        and white.find_nearest(p)[3] > FACE_EDGE_TOLERANCE_M):
                    report["iris_off_white"] += 1
                    if len(report["examples"]) < 6:
                        report["examples"].append("%s %s %s x%.1f blink %.1f" % (side, preset, gaze, scale, blink))
                    break
    set_face(made, "neutral")
    bpy.context.view_layer.update()
    report["clearance_mm"] = {o.name: _clearance(o, head_tree) for o, c, _s in made if c in ("brow", "line", "dead")}
    report["white_clearance_mm"] = {o.name: _surface_clearance(o, head_tree) for o, c, _s in made if c == "eye"}
    for side in ("L", "R"):
        parts = {c: o for o, c, s in made if s == side}
        report.setdefault("brow_line_gap_mm", {})[side] = _gap(parts["brow"], parts["line"])
    return report


def fit_identity(head, body, manifest, hair_styles, prefix):
    """The identity's face features and `hair_styles` ({skin: style}) fitted to `head` (with
    its stored construction surface) and `body`: the face in `<prefix>.Face` (the eye
    assemblies, brows on the ridge line, the dead X), every component carrying its shared
    channels as shape keys (FACE-EYE-001; presets are their weighted sums,
    FACE-EXPRESSION-001) and checked in every preset, blend, gaze and the blink; each skin's
    hair in `<prefix>.Hair.<skin>`. Returns (objects, report)."""
    male_base_v2, face_features, wolf_hair = _authoring()
    identity = manifest["identity"]
    repo = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    materials = palette_materials(manifest, repo)
    hair_material = materials["hair"]
    stored = head.data.attributes[male_base_v2.F0_ATTRIBUTE]
    construction = [head.matrix_world @ a.vector for a in stored.data]
    low = min(p.z for p in construction)
    height = max(p.z for p in construction) - low
    half_width = max(abs(p.x) for p in construction)
    centre_y = 0.5 * (min(p.y for p in construction) + max(p.y for p in construction))
    head_tree, body_tree = _tree_of(head), _tree_of(body)
    objects, report = [], {"chart": [round(low, 4), round(height, 4), round(half_width, 4)], "faces": {}, "hair": {}}
    controls = face_features.ridge_lines(male_base_v2.face_controls, head)
    crest = face_features.ridge_controls(male_base_v2.face_controls, head)
    face = bpy.data.collections.new("%s.Face" % prefix)
    bpy.context.scene.collection.children.link(face)
    made = face_features.place_marks(face, head_tree, low, height, half_width, identity["face"]["marks"], ridge=controls)
    dress_face(made, materials)
    report["faces"] = face_checks(made, head_tree)
    objects += [obj for obj, _c, _s in made]
    report["ridge_line_below_crest_mm"] = {n: round(min((p - q).length for _u, q in controls[1.0 if u >= 0 else -1.0]) * 1000, 1)
                                           for n, (u, p) in crest.items() if u >= 0}
    for skin, style in hair_styles.items():
        collection = bpy.data.collections.new("%s.Hair.%s" % (prefix, skin))
        bpy.context.scene.collection.children.link(collection)
        obj = wolf_hair.build_style(wolf_hair.head_frame_of(head, body), style)
        collection.objects.link(obj)
        obj.data.materials.clear()
        obj.data.materials.append(hair_material)
        report["hair"][skin] = {"object": obj.name, "variant": obj.get("riposte_variant"),
                                "triangles": sum(len(p.vertices) - 2 for p in obj.data.polygons),
                                "inside_head": _inside(obj, head_tree), "inside_body": _inside(obj, body_tree),
                                "over_face_vertices": _face_intrusion(obj, (low, height, half_width, centre_y), head_tree)}
        objects.append(obj)
    return objects, report


def _to_rest_on(obj, rig, bone, skinning):
    """An object authored in the posed (A-pose) world, returned to the rest by the bone's
    skinning matrix and bound rigid on it."""
    from mathutils import Matrix
    unpose = Matrix([list(row) for row in skinning]).inverted()
    obj.data.transform(unpose @ obj.matrix_world, shape_keys=True)
    obj.matrix_world = Matrix.Identity(4)
    bind_rigid(obj, rig, bone)


def build_candidate(manifest_path, out):
    """The character on the approved v2 base for review: the base bound to WolfRig with
    its approved head, the identity fitted (both skins' hair), every attachment rigid on
    Head. Saved to `out` (an iteration folder); no source is written."""
    male_base_v2, _face_features, _wolf_hair = _authoring()
    with open(manifest_path, encoding="utf-8") as handle:
        manifest = json.load(handle)
    bpy.ops.wm.open_mainfile(filepath=male_base_v2.CANDIDATE)
    male_base_v2.apose()
    head, body = bpy.data.objects[male_base_v2.STUDY], bpy.data.objects[male_base_v2.SCULPT]
    prefix = manifest["id"].split(".")[-1].capitalize()
    blender_root = os.path.join(male_base_v2.ROOT, "art-src", "blender")
    styles = {}
    for skin, outfit in manifest["outfits"].items():
        for gid in outfit.get("garments", []):
            definition = garments.load(_library_path(manifest, blender_root, "%s.garment.json" % gid))
            if definition.get("type") == "hair":
                styles[skin] = next(k for k, v in _wolf_hair.STYLES.items() if v[0] == definition["source"]["object"])
    objects, report = fit_identity(head, body, manifest, styles, prefix)
    report["bind"] = male_base_v2.bind(male_base_v2.SCULPT, male_base_v2.STUDY)
    rig = male_base_v2._rig()
    male_base_v2.apose()
    skinning = male_base_v2._skinning([HEAD])[0]
    for obj in objects:
        _to_rest_on(obj, rig, HEAD, skinning)
    bound = bpy.data.objects[male_base_v2.BOUND]
    bound.data.materials.clear()
    bound.data.materials.append(identity_materials(manifest, male_base_v2.ROOT)[0])
    bpy.context.view_layer.update()
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out, copy=True)
    return report


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--candidate" not in args:
        raise SystemExit("pass --candidate <iteration folder>/<name>.blend [--manifest <character.assembly.json>]")
    repo = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    from character_modeling import iterations
    out = os.path.abspath(args[args.index("--candidate") + 1])
    problems = iterations.path_problems(out, repo)
    if problems:
        raise SystemExit("RIPOSTE_ITERATION: " + "; ".join(problems))
    manifest = args[args.index("--manifest") + 1] if "--manifest" in args else os.path.join(
        repo, "art-src", "blender", "characters", "wolf", "wolf.assembly.json")
    print("RIPOSTE_CHARACTER_CANDIDATE", json.dumps(dict(build_candidate(manifest, out), blend=out)))


if __name__ == "__main__":
    main()
