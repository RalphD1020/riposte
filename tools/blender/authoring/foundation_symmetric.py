"""Stage the symmetric default foundation (CHARACTER-SYMMETRY-001) as a review candidate.

From an approved foundation's own source (the approved `BodyV2` sculpt and `HeadV2`, never
edited in place), with Blender's native tools only:

- Body: `Symmetrize` on the sculpt (the character's +X half onto -X), welded on the midline.
- Head: `Symmetrize` on the approved head, whose shape is already bilateral and whose voxel
  triangulation is not; its construction points and face-control tags follow the mirror. A
  head whose shape deviates from its mirror beyond `HEAD_SHAPE_TOLERANCE_M` is refused.
- Bind rig (`male_base_v2.BIND_RIG`): a NEW rig object copied from the shared rig, its stored
  authoring A-pose made its rest (the sculpt's own space) and bone-`Symmetrize`d +X onto -X.
  The shipping rig is never modified; it stays in the source only as the v1 transfer source.
- Skin fields (`male_base_v2.BIND_FIELDS`): v1's weights and physique keys transferred once
  onto the symmetric sculpt, then made bilateral by Blender's vertex-group mirror (the -X
  side copies the +X side) and shape-key mirror (`blend_from_shape` from the mirrored key);
  midline vertices take the mean of a left/right pair.
- Clips: every action re-expressed on the bind rig's rest by matching each bone's orientation
  (armature space) to the shared rig's evaluated pose, keyed on every bone, so no clip depends
  on an implicit rest. Clips stay rotations; root and hip translation stay where they were keyed.

The candidate (blend, record, rig contract, foundation document, a Wolf manifest and garment
copies retargeted to the candidate topology and rig) is written to an iteration folder; nothing
under `art-src` is written. Its fitting regions come from `fitting_regions.py --foundation` run
on the candidate document.

    blender --background --factory-startup --python tools/blender/authoring/foundation_symmetric.py -- \
        --from <foundation document> --out <.reports/art/iterations/...> [--garment-revisions <folder>]
"""

import copy
import hashlib
import json
import os
import sys

import bmesh
import bpy
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools", "blender"))
sys.path.insert(0, os.path.join(ROOT, "tools", "character_modeling"))
import male_base_v2 as v2  # noqa: E402
import male_base_v2_variation as mv  # noqa: E402
from character_modeling import foundation, symmetry  # noqa: E402

## The sculpt's +X half is kept and mirrored onto -X (the rig's bones the same way).
MERGE_M = 0.0001
## Seam doubles closer than this are one vertex the halves never joined (the seam check's
## own weld distance); anything farther apart is real topology and is left alone.
WELD_M = 1e-5
SHIPPING_RIG = "Armature"
## The approved head's voxel triangulation is not mirrored, its shape is (mean 0.2 mm, worst
## 2.1 mm): beyond this the head carries a designed asymmetry the stage must not erase.
HEAD_SHAPE_TOLERANCE_M = 0.003


def _select_only(obj):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def symmetrize_body(body, direction="X"):
    mesh = bmesh.new()
    mesh.from_mesh(body.data)
    bmesh.ops.symmetrize(mesh, input=mesh.verts[:] + mesh.edges[:] + mesh.faces[:], direction=direction, dist=MERGE_M)
    ## Weld the seam (Merge by Distance on the midline): coincident doubles there are two
    ## halves never joined.
    seam = [v for v in mesh.verts if abs(v.co.x) <= MERGE_M]
    bmesh.ops.remove_doubles(mesh, verts=seam, dist=WELD_M)
    mesh.to_mesh(body.data)
    mesh.free()
    body.data.update()


def shape_asymmetry_m(obj):
    """The shape's own bilateral deviation, independent of its triangulation: the largest
    distance from a vertex's mirror image to the surface."""
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    verts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    tree = BVHTree.FromPolygons(verts, [list(p.vertices) for p in obj.data.polygons])
    return max(tree.find_nearest(Vector((-p.x, p.y, p.z)))[3] for p in verts)


def symmetrize_head(head):
    """Symmetrize the approved head (+X onto -X) and keep its per-vertex construction data
    true on the mirrored half: the construction point mirrored, a control tag renamed to its
    -x twin (`face_mask` names the -x twin `<name>.R`). A centre control (no twin) lies on the
    midline by definition, so its vertex is set onto X = 0 first and survives as a seam vertex."""
    names = sorted(v2._mask_module().control_points(None))
    number = {n: i + 1 for i, n in enumerate(names)}
    centre = {number[n] for n in names if not n.endswith(".R") and n + ".R" not in number}
    for v, control in zip(head.data.vertices, head.data.attributes[v2.CONTROL_ATTRIBUTE].data):
        if control.value in centre:
            v.co.x = 0.0
    head.data.update()
    symmetrize_body(head)
    construction = head.data.attributes[v2.F0_ATTRIBUTE]
    tag = head.data.attributes[v2.CONTROL_ATTRIBUTE]
    for v, point, control in zip(head.data.vertices, construction.data, tag.data):
        if v.co.x >= -symmetry.MIDLINE_EPS_M:
            continue
        if point.vector.x > 0.0:
            point.vector = (-point.vector.x, point.vector.y, point.vector.z)
        if control.value > 0:
            twin = names[control.value - 1] + ".R"
            control.value = number.get(twin, 0)
    head.data.update()


def _points(obj):
    return [tuple(obj.matrix_world @ v.co) for v in obj.data.vertices]


def symmetry_report(obj):
    problems, stats = symmetry.mirror_problems(_points(obj))
    seam, seam_stats = symmetry.centerline_seam_problems(_points(obj), [list(p.vertices) for p in obj.data.polygons])
    return problems + seam, dict(stats, seam=seam_stats)


def _midline_pairs(fields):
    names = [g.name for g in fields.vertex_groups]
    return [(fields.vertex_groups[n].index, fields.vertex_groups[symmetry.mirror_bone_name(n)].index)
            for n in names if n.endswith(".L")]


def bind_fields(sculpt):
    """The bilateral skin fields: a copy of the symmetric sculpt carrying v1's weights as
    vertex groups and its physique keys as shape keys, mirrored -X from +X."""
    fields = sculpt.copy()
    fields.data = sculpt.data.copy()
    fields.name = fields.data.name = v2.BIND_FIELDS
    bpy.context.scene.collection.objects.link(fields)
    deltas = mv.key_deltas()
    weights = v2._transfer_weights([tuple(c) for c in mv._coords(sculpt)])
    for name, w in sorted(weights.items()):
        group = fields.vertex_groups.new(name=name)
        for i, x in enumerate(w):
            if x > 0.0:
                group.add([i], float(x), "REPLACE")
    for name in sorted(weights):
        mirror = symmetry.mirror_bone_name(name)
        if mirror not in fields.vertex_groups:
            fields.vertex_groups.new(name=mirror)
    fields.shape_key_add(name="Basis", from_mix=False)
    basis = mv._coords(fields)
    for name, delta in sorted(deltas.items()):
        key = fields.shape_key_add(name=name, from_mix=False)
        key.data.foreach_set("co", (basis + delta).ravel())
    _select_only(fields)
    side = [v.index for v in fields.data.vertices if v.co.x < -symmetry.MIDLINE_EPS_M]
    mid = [v.index for v in fields.data.vertices if abs(v.co.x) <= symmetry.MIDLINE_EPS_M]

    def select(indices):
        bpy.ops.object.mode_set(mode="OBJECT")
        for v in fields.data.vertices:
            v.select = False
        for i in indices:
            fields.data.vertices[i].select = True
        bpy.ops.object.mode_set(mode="EDIT")

    ## Weights: the selected -X side copies the +X side, names flipped (Blender's vertex-group mirror).
    select(side)
    bpy.ops.object.vertex_group_mirror(mirror_weights=True, flip_group_names=True, all_groups=True, use_topology=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    for i in mid:
        groups = {g.group: g.weight for g in fields.data.vertices[i].groups}
        for left, right in _midline_pairs(fields):
            mean = 0.5 * (groups.get(left, 0.0) + groups.get(right, 0.0))
            for index in (left, right):
                if mean > 0.0:
                    fields.vertex_groups[index].add([i], mean, "REPLACE")
                elif index in groups:
                    fields.vertex_groups[index].remove([i])
    ## Keys: each key's -X side takes its own mirrored copy; the midline takes half of it.
    blocks = fields.data.shape_keys.key_blocks
    for name in sorted(deltas):
        fields.active_shape_key_index = blocks.find(name)
        bpy.ops.object.shape_key_add(from_mix=False)
        mirrored = fields.active_shape_key
        mirrored.data.foreach_set("co", _key_co(blocks[name]).ravel())
        bpy.ops.object.shape_key_mirror(use_topology=False)
        fields.active_shape_key_index = blocks.find(name)
        for indices, blend in ((side, 1.0), (mid, 0.5)):
            select(indices)
            bpy.ops.mesh.blend_from_shape(shape=mirrored.name, blend=blend, add=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        fields.active_shape_key_index = blocks.find(mirrored.name)
        bpy.ops.object.shape_key_remove()
    fields.active_shape_key_index = 0
    fields.hide_render = fields.hide_viewport = True
    return fields


def _key_co(block):
    import numpy as np
    flat = np.empty(len(block.data) * 3)
    block.data.foreach_get("co", flat)
    return flat.reshape(-1, 3)


def bind_rig(shared):
    """The neutral bilateral bind rig: a new rig whose rest is the shared rig's authoring
    A-pose, bone-symmetrized +X onto -X."""
    rig = shared.copy()
    rig.data = shared.data.copy()
    rig.name = rig.data.name = v2.BIND_RIG
    rig.animation_data_clear()
    if v2.AUTHORING_POSE in rig:
        del rig[v2.AUTHORING_POSE]
    bpy.context.scene.collection.objects.link(rig)
    _select_only(rig)
    bpy.ops.object.mode_set(mode="POSE")
    for name, quaternion in json.loads(shared[v2.AUTHORING_POSE]).items():
        pb = rig.pose.bones[name]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = quaternion
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="EDIT")
    for edit in rig.data.edit_bones:
        edit.select = edit.select_head = edit.select_tail = edit.name.endswith(".L")
    bpy.ops.armature.symmetrize(direction="POSITIVE_X")
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.matrix_basis = Matrix.Identity(4)
    return rig


def _fcurves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                bag = strip.channelbag(slot)
                if bag:
                    yield from bag.fcurves


LEG_CHAINS = tuple(("UpperLeg.%s" % s, "LowerLeg.%s" % s, "Foot.%s" % s) for s in ("L", "R"))
## The pelvis bone the legs hang from (a translated channel in every clip that moves the body).
LEG_ROOT = "Hips"
## A pelvis drop eases in and out over this many frames (a step in one frame reads as a pop).
PELVIS_EASE_FRAMES = 6


def _leg_ik(hip, ankle, pole, upper, lower):
    """Knee of a two-bone leg from `hip` reaching `ankle` (clamped inside its reach), bent
    toward `pole`: the plane hip-ankle-pole, the law of cosines."""
    axis = ankle - hip
    d = min(max(axis.length, abs(upper - lower) + 1e-6), (upper + lower) * (1.0 - 1e-6))
    axis.normalize()
    along = (upper * upper - lower * lower + d * d) / (2.0 * d)
    bend = pole - hip
    bend = (bend - axis * bend.dot(axis)).normalized()
    return hip + axis * along + bend * max(upper * upper - along * along, 0.0) ** 0.5


def _pelvis_drop(hips, ankles, reach):
    """How far the pelvis must come down for every leg to reach its planted ankle: the old
    rest's longer right hip offset leaves a straight standing leg a few centimetres short on
    the bilateral skeleton, and the clip's foot would float. 0 where every ankle is in reach;
    a leg whose target is out of reach in plan alone is left to the solve's clamp."""
    drop = 0.0
    for hip, ankle in zip(hips, ankles):
        offset = ankle - hip
        flat = offset.x * offset.x + offset.y * offset.y
        if offset.length <= reach or flat >= reach * reach or offset.z >= 0.0:
            continue
        drop = max(drop, -(reach * reach - flat) ** 0.5 - offset.z)
    return drop


def _eased(drops, frames):
    """A per-frame pelvis drop eased in and out over `frames` either side of where it is
    needed — never less than the drop a frame needs, never a step in one frame."""
    import math
    out = {}
    for f in drops:
        out[f] = max(drops[g] * 0.5 * (1.0 + math.cos(math.pi * abs(g - f) / (frames + 1)))
                     for g in drops if abs(g - f) <= frames)
    return out


def _aim(rotation, direction):
    """`rotation` turned the least way that puts its bone axis (local Y) along `direction`."""
    from mathutils import Vector
    current = rotation @ Vector((0.0, 1.0, 0.0))
    return current.rotation_difference(direction.normalized()) @ rotation


def retarget_clips(shared, rig):
    """Every action re-expressed on `rig`'s rest: each bone's armature-space orientation
    matches the shared rig's evaluated pose; translation only where the clip keyed it. The
    legs keep the clip's ground contacts: each is solved (two-bone IK on the bind rig's own
    bone lengths) so its ankle lands where the clip put it, its knee toward the clip's knee,
    its foot in the clip's orientation — the old rest's staggered stance becomes motion on a
    bilateral skeleton, never a rest offset. Where the old rest's right hip offset left a
    straight standing leg short of its planted ankle (`death_stab`, `death`), the clip's
    pelvis comes down by exactly the shortfall in those frames (`_pelvis_drop`): the foot
    stays planted instead of floating. No bone is stretched."""
    scene = bpy.context.scene
    order = [b.name for b in rig.data.bones]
    rest_new = {b.name: b.matrix_local.copy() for b in rig.data.bones}
    parent = {b.name: (b.parent.name if b.parent else None) for b in rig.data.bones}
    report = {}
    shared.animation_data_create()
    for action in list(bpy.data.actions):
        paths = [f.data_path for f in _fcurves(action)]
        euler = {p.split('"')[1] for p in paths if p.endswith(".rotation_euler")}
        moved = {p.split('"')[1] for p in paths if p.endswith(".location")}
        for pb in shared.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
            pb.rotation_mode = "XYZ" if pb.name in euler else "QUATERNION"
        shared.animation_data.action = action
        if action.slots:
            shared.animation_data.action_slot = action.slots[0]
        baked = bpy.data.actions.new("%s.bind" % action.name)
        ## A clip is library data no object holds between plays; kept as the source keeps it.
        baked.use_fake_user = True
        rig.animation_data_create()
        rig.animation_data.action = baked
        start, end = (int(round(x)) for x in action.frame_range)
        frames = range(start, end + 1)
        targets = {}
        for frame in frames:
            scene.frame_set(frame)
            targets[frame] = {n: shared.pose.bones[n].matrix.copy() for n in order}
        reach = min(rig.data.bones[c[0]].length + rig.data.bones[c[1]].length for c in LEG_CHAINS) * (1.0 - 1e-4)
        drops = {f: 0.0 for f in frames}
        if LEG_ROOT in moved:
            for f in frames:
                hips = [(targets[f][LEG_ROOT] @ (rest_new[LEG_ROOT].inverted() @ rest_new[c[0]])).translation for c in LEG_CHAINS]
                drops[f] = _pelvis_drop(hips, [targets[f][c[2]].translation for c in LEG_CHAINS], reach)
            drops = _eased(drops, PELVIS_EASE_FRAMES)
        previous = {}
        for frame in frames:
            target = targets[frame]
            posed = {}
            for name in order:
                p = parent[name]
                rest_rel = rest_new[name] if p is None else rest_new[p].inverted() @ rest_new[name]
                frame_of_parent = Matrix.Identity(4) if p is None else posed[p]
                aimed = target[name]
                if name == LEG_ROOT and drops[frame] > 0.0:
                    aimed = Matrix.Translation((0.0, 0.0, -drops[frame])) @ aimed
                chain = next((c for c in LEG_CHAINS if name in c), None)
                if chain and name != chain[2]:
                    upper, lower = rig.data.bones[chain[0]].length, rig.data.bones[chain[1]].length
                    hip = (posed[parent[chain[0]]] @ (rest_new[parent[chain[0]]].inverted() @ rest_new[chain[0]])).translation
                    ankle = target[chain[2]].translation
                    knee = _leg_ik(hip, ankle, target[chain[1]].translation, upper, lower)
                    head = (frame_of_parent @ rest_rel).translation
                    tip = knee if name == chain[0] else ankle
                    aimed = Matrix.LocRotScale(head, _aim(target[name].to_quaternion(), tip - head), None)
                basis = (frame_of_parent @ rest_rel).inverted() @ aimed
                location, rotation, _scale = basis.decompose()
                if name not in moved:
                    location = location * 0.0
                ## One hemisphere for every clip (w >= 0 at its first key), continuous after:
                ## the same pose keyed q in one clip and -q in the next would blend through rest.
                if name in previous:
                    if previous[name].dot(rotation) < 0.0:
                        rotation.negate()
                elif rotation.w < 0.0:
                    rotation.negate()
                previous[name] = rotation
                pb = rig.pose.bones[name]
                pb.rotation_quaternion = rotation
                pb.location = location
                pb.keyframe_insert("rotation_quaternion", frame=frame)
                if name in moved:
                    pb.keyframe_insert("location", frame=frame)
                posed[name] = frame_of_parent @ rest_rel @ Matrix.LocRotScale(location, rotation, None)
        report[action.name] = {"frames": end - start + 1, "euler_bones": len(euler), "translated": sorted(moved),
                               "pelvis_drop_mm": round(1000 * max(drops.values()), 1)}
    shared.animation_data.action = None
    rig.animation_data.action = None
    for action in [a for a in bpy.data.actions if not a.name.endswith(".bind")]:
        name = action.name
        bpy.data.actions.remove(action)
        bpy.data.actions["%s.bind" % name].name = name
    for pb in shared.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    return report


def rig_contract(rig, template):
    """The bind rig's contract in the shipping contract's format (bone ends, parents)."""
    extra = {b["name"]: {k: v for k, v in b.items() if k not in ("name", "parent", "head", "tail")} for b in template["bones"]}
    bones = []
    for b in rig.data.bones:
        row = {"name": b.name, "parent": b.parent.name if b.parent else None,
               "head": [round(float(c), 6) for c in rig.matrix_world @ b.head_local],
               "tail": [round(float(c), 6) for c in rig.matrix_world @ b.tail_local]}
        row.update(extra.get(b.name, {}))
        bones.append(row)
    out = dict(template)
    out["bones"] = bones
    out["rest"] = "neutral bilateral A-pose (CHARACTER-SYMMETRY-001); clips are rotations on this rest"
    return out


def _digest(contract):
    return hashlib.sha256(json.dumps(contract["bones"], sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def _write(path, document):
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(document, indent=1) + "\n")


def stage_character(manifest_path, document, record, out, revisions=None):
    """A Wolf manifest and garment copies on the candidate: the same definitions, retargeted
    to its body topology and rig contract (a migration, CHARACTER-RELEASE-001). A definition in
    `revisions` (a folder of `<id>.garment.json`) is a candidate revision and replaces the
    library's for this candidate only; the approved definitions are never edited."""
    with open(manifest_path, encoding="utf-8") as handle:
        wolf = json.load(handle)
    blender = os.path.dirname(v2.CHARACTERS)
    library = wolf.get("garment_library", "garments")
    library = library if os.path.isabs(library) else os.path.join(blender, library)
    staged = os.path.join(out, "garments")
    os.makedirs(staged, exist_ok=True)
    body = record["objects"][v2.SCULPT]["sha256"]
    skeleton = document["skeleton"]
    ids = set(wolf["foundation"].get("facial_hair", [])) | {g for e in wolf["outfits"].values() for g in e["garments"]}
    for gid in sorted(ids):
        revised = os.path.join(revisions, "%s.garment.json" % gid) if revisions else None
        source = revised if revised and os.path.exists(revised) else os.path.join(library, "%s.garment.json" % gid)
        with open(source, encoding="utf-8") as handle:
            garment = json.load(handle)
        garment["base_topology_fingerprint"] = body
        for other in garment.get("also_fitted", []):
            if other.get("base_id") == document["id"]:
                other["base_topology_fingerprint"] = body
        garment["skeleton_id"] = skeleton["id"]
        garment["rig_contract_sha256"] = skeleton["contract_sha256"]
        source = garment.get("source", {})
        if source.get("blend") and not os.path.isabs(source["blend"]):
            source["blend"] = os.path.join(blender, source["blend"])
        _write(os.path.join(staged, "%s.garment.json" % gid), garment)
    wolf = copy.deepcopy(wolf)
    wolf["skeleton"] = dict(skeleton)
    wolf["garment_library"] = staged
    path = os.path.join(out, "wolf.assembly.candidate.json")
    _write(path, wolf)
    return path


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    out = os.path.abspath(args[args.index("--out") + 1])
    if os.path.commonpath([out, os.path.join(ROOT, "art-src")]) == os.path.join(ROOT, "art-src"):
        raise SystemExit("RIPOSTE_SYMMETRIC: a candidate is staged in an iteration folder, never under art-src")
    source_doc = os.path.abspath(args[args.index("--from") + 1])
    document = foundation.load(source_doc)
    blender = os.path.dirname(v2.CHARACTERS)
    bpy.ops.wm.open_mainfile(filepath=foundation.path_of(document, "source", blender))
    shared = bpy.data.objects[SHIPPING_RIG]
    head = bpy.data.objects[v2.STUDY]
    head_shape = shape_asymmetry_m(head)
    if head_shape > HEAD_SHAPE_TOLERANCE_M:
        raise SystemExit("RIPOSTE_SYMMETRIC: the approved head's shape deviates %.1f mm from its mirror: "
                         "a design asymmetry, not triangulation" % (1000 * head_shape))
    symmetrize_head(head)
    head_problems, head_stats = symmetry_report(head)
    if head_problems:
        raise SystemExit("RIPOSTE_SYMMETRIC: the symmetrized head is not bilateral: %s" % head_problems[:3])
    head_stats["shape_asymmetry_before_mm"] = round(1000 * head_shape, 3)
    missing = [n for n in v2._mask_module().control_points(None)
               if n not in {sorted(v2._mask_module().control_points(None))[a.value - 1]
                            for a in head.data.attributes[v2.CONTROL_ATTRIBUTE].data if a.value > 0}]
    if missing:
        raise SystemExit("RIPOSTE_SYMMETRIC: the symmetrized head lost face controls %s" % missing)
    sculpt = bpy.data.objects[v2.SCULPT]
    symmetrize_body(sculpt, args[args.index("--body-side") + 1] if "--body-side" in args else "X")
    body_problems, body_stats = symmetry_report(sculpt)
    if body_problems:
        raise SystemExit("RIPOSTE_SYMMETRIC: the symmetrized body is not bilateral: %s" % body_problems[:3])
    v2.apose()
    fields = bind_fields(sculpt)
    points = _points(fields)
    weights = [{fields.vertex_groups[g.group].name: g.weight for g in v.groups if g.weight > 0.0} for v in fields.data.vertices]
    weight_problems, weight_stats = symmetry.weight_mirror_problems(points, weights, symmetry.mirror_bone_name, tolerance=1e-5)
    if weight_problems:
        raise SystemExit("RIPOSTE_SYMMETRIC: the skin fields are not bilateral: %s" % weight_problems[:3])
    rig = bind_rig(shared)
    rest = {b.name: {"head": tuple(rig.matrix_world @ b.head_local), "tail": tuple(rig.matrix_world @ b.tail_local),
                     "parent": b.parent.name if b.parent else None,
                     "roll_axis": tuple((rig.matrix_world.to_3x3() @ b.matrix_local.to_3x3()).col[2].normalized())}
            for b in rig.data.bones}
    bone_problems, bone_stats = symmetry.bone_mirror_problems(rest)
    if bone_problems:
        raise SystemExit("RIPOSTE_SYMMETRIC: the bind rig is not bilateral: %s" % bone_problems[:3])
    ## Rest ORIENTATION, not just joint positions (CHARACTER-SYMMETRY-001): mirrored bones can
    ## share positions yet carry inconsistent roll that twists the arm. Verification only.
    orient_problems, orient_stats = symmetry.bone_rest_orientation_problems(rest)
    if orient_problems:
        raise SystemExit("RIPOSTE_SYMMETRIC: the bind rig's rest orientations are not bilateral: %s" % orient_problems[:3])
    v2.apose()
    clips = retarget_clips(shared, rig)
    v2.apose()
    if len([a for a in bpy.data.actions if a.use_fake_user]) != len(clips):
        raise SystemExit("RIPOSTE_SYMMETRIC: a retargeted clip would not be saved")
    os.makedirs(out, exist_ok=True)
    blend = os.path.join(out, "male_base.foundation.v003-candidate.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend, copy=True)
    record = {"schema": "riposte.character_foundation_record", "version": 1, "foundation": document["id"],
              "approved": None, "builder": "tools/blender/authoring/foundation_symmetric.py",
              "objects": {v2.SCULPT: v2.fingerprint(sculpt), v2.STUDY: v2.fingerprint(head)}}
    with open(os.path.join(ROOT, document["skeleton"]["contract"]), encoding="utf-8") as handle:
        template = json.load(handle)
    contract = rig_contract(rig, template)
    contract_path = os.path.join(out, "wolf.rig-contract.v003-candidate.json")
    _write(contract_path, contract)
    candidate = copy.deepcopy(document)
    candidate["status"] = "candidate"
    candidate["source"] = blend
    candidate["record"] = os.path.join(out, "male_base.foundation.v003-candidate.record.json")
    candidate["regions"] = os.path.join(out, "male_base.foundation.v003-candidate.regions.json")
    candidate["builder"] = "tools/blender/authoring/foundation_symmetric.py"
    candidate["resolution"]["symmetric"] = True
    candidate["skeleton"] = {"id": document["skeleton"]["id"], "contract": contract_path, "contract_sha256": _digest(contract)}
    candidate["notes"] = (document.get("notes", "") + " | SYMMETRIC CANDIDATE: Symmetrized BodyV2, the neutral bilateral "
                          "bind rig (rest = authoring A-pose), mirrored skin fields, clips re-expressed on the new rest. "
                          "Review copy only; no re-lock without approval.")
    _write(candidate["record"], record)
    document_path = os.path.join(out, "male_base.foundation.v003-candidate.json")
    _write(document_path, candidate)
    manifest = stage_character(mv.CANONICAL_WOLF if "--manifest" not in args else os.path.abspath(args[args.index("--manifest") + 1]),
                               candidate, record, out,
                               os.path.abspath(args[args.index("--garment-revisions") + 1]) if "--garment-revisions" in args else None)
    report = {"head": head_stats, "body": body_stats, "weights": weight_stats, "rig": bone_stats, "clips": clips,
              "document": document_path, "manifest": manifest, "contract_sha256": candidate["skeleton"]["contract_sha256"]}
    _write(os.path.join(out, "stage_report.json"), report)
    print("RIPOSTE_SYMMETRIC", json.dumps({k: v for k, v in report.items() if k != "clips"}))


if __name__ == "__main__":
    main()
