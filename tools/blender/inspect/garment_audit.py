"""Weight and fit audit of a skinned garment against the base (PRES-GARMENT-SKINNING's Blender side).

Reports, per garment object:
- each bone's share of the garment's vertices (dominant bone);
- influence counts, normalization errors, unweighted vertices (hard failures);
- influences from bones outside the garment's declared fitting regions
  (`male_base.regions.json`) — a finding to explain, not an automatic failure;
- weight discontinuities: neighbouring vertices whose bone weights differ by
  more than a threshold (a seam the skin will tear along);
- distance from the base body's surface by region against the category's
  clearance range (penetration below zero, floating above the range).

Read-only. Use on a garment in a blend that also holds (or links) the base `Body`:

    blender --background --factory-startup --python tools/blender/inspect/garment_audit.py -- \
        --blend art-src/blender/characters/wolf/wolf_attire.blend --garment RangerGambeson \
        --definition art-src/blender/garments/ranger_gambeson.garment.json [--json out.json]
"""

import argparse
import fnmatch
import json
import os
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "character_modeling"))

from character_modeling import garments, hair_design, surface_integration  # noqa: E402

sys.path.insert(0, os.path.join(ROOT, "tools", "blender"))
import character_assembly  # noqa: E402
REGIONS = os.path.join(ROOT, "art-src", "blender", "characters", "male_base.regions.json")
SURFACES = os.path.join(ROOT, "art-src", "blender", "characters", "male_base.surfaces.json")
CALIBRATION = os.path.join(ROOT, "art-src", "blender", "characters", "male_base.surface_calibration.json")
MAX_INFLUENCES = 4
NORMAL_TOLERANCE = 1e-4
DISCONTINUITY = 0.5
NEGLIGIBLE = 0.01
## Below this a vertex is inside the body; a garment's open boundary can sit
## exactly on the surface, where the nearest face's side is a rounding tie.
PENETRATION_M = 0.0005


## The deformation envelope's default sample: clips that load the shoulder,
## armpit, chest, waist, hip and knee, at a few frames each.
ENVELOPE_CLIPS = ("idle", "walk_forward", "dash_forward", "dash_left", "dash_right", "charge_support",
                  "swing_support", "overswing", "death", "ring_fall_a")
FRAMES_PER_CLIP = 4
CONFIGURATION = os.path.join(ROOT, "art-src", "blender", "characters", "male_base.configuration.json")
BASE_MASTER = os.path.join(ROOT, "art-src", "blender", "characters", "male_base.blend")


def _arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--blend", required=True)
    parser.add_argument("--garment", required=True)
    parser.add_argument("--definition", required=True)
    parser.add_argument("--json", default="")
    parser.add_argument("--configurations", default="", help="'all' (the definition's supported list) or a comma list")
    parser.add_argument("--clips", default="", help="'envelope' (the default set), 'all' (every production clip) or a comma list")
    parser.add_argument("--frame-step", type=int, default=0,
                        help="sample every Nth frame of each clip (the acceptance matrix uses 2); 0 = %d frames per clip" % FRAMES_PER_CLIP)
    parser.add_argument("--manifest", default="", help="the character manifest: enables the hair checks (face, scalp, crown)")
    parser.add_argument("--configuration", default=CONFIGURATION, help="the base's configuration file (its keys and named configurations)")
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1:])


def audit(garment, body, definition, regions):
    names = {g.index: g.name for g in garment.vertex_groups}
    allowed = set()
    for region in definition["regions"]:
        allowed.update(regions["regions"][region]["bones"])
    report = {"garment": garment.name, "vertices": len(garment.data.vertices), "hard": [], "findings": []}
    dominant_share = {}
    weights = []
    unweighted = heavy = unnormalized = negligible = 0
    outside = {}
    for vertex in garment.data.vertices:
        w = {names[g.group]: g.weight for g in vertex.groups if g.weight > 0.0}
        weights.append(w)
        if not w:
            unweighted += 1
            continue
        if len(w) > MAX_INFLUENCES:
            heavy += 1
        if abs(sum(w.values()) - 1.0) > NORMAL_TOLERANCE:
            unnormalized += 1
        negligible += sum(1 for v in w.values() if v < NEGLIGIBLE)
        top = max(w, key=w.get)
        dominant_share[top] = dominant_share.get(top, 0) + 1
        for bone, value in w.items():
            if bone not in allowed and value >= NEGLIGIBLE:
                outside[bone] = outside.get(bone, 0) + 1
    for label, count in (("unweighted vertices", unweighted), ("vertices over four influences", heavy), ("unnormalized vertices", unnormalized)):
        if count:
            report["hard"].append("%d %s" % (count, label))
    if negligible:
        report["findings"].append("%d negligible influences (< %.2f) to strip" % (negligible, NEGLIGIBLE))
    for bone, count in sorted(outside.items()):
        report["findings"].append("%d vertices take %s, outside the declared regions %s" % (count, bone, definition["regions"]))
    report["bone_share"] = {b: round(c / max(1, len(garment.data.vertices)), 3) for b, c in sorted(dominant_share.items())}
    jumps = 0
    for edge in garment.data.edges:
        a, b = (weights[i] for i in edge.vertices)
        bones = set(a) | set(b)
        if bones and max(abs(a.get(k, 0.0) - b.get(k, 0.0)) for k in bones) > DISCONTINUITY:
            jumps += 1
    if jumps:
        report["findings"].append("%d edges jump more than %.1f in one bone's weight" % (jumps, DISCONTINUITY))
    world = body.matrix_world
    tree = BVHTree.FromPolygons([world @ v.co for v in body.data.vertices], [list(p.vertices) for p in body.data.polygons])
    low, high = garments.clearance_for(definition, regions, "default")
    inside = floating = 0
    worst_in = worst_out = 0.0
    for vertex in garment.data.vertices:
        p = garment.matrix_world @ vertex.co
        nearest, normal, _index, distance = tree.find_nearest(p)
        if nearest is None:
            continue
        signed = distance if (p - nearest).dot(normal) >= 0.0 else -distance
        if signed < -PENETRATION_M:
            inside += 1
            worst_in = min(worst_in, signed)
        elif signed > high:
            floating += 1
            worst_out = max(worst_out, signed)
    if inside:
        report["hard"].append("%d vertices inside the body (worst %.4f m)" % (inside, worst_in))
    if floating:
        report["findings"].append("%d vertices beyond the %s clearance %.3f m (worst %.4f m)" % (floating, definition["category"], high, worst_out))
    report["clearance_m"] = [low, high]
    return report


## Hair defaults (a hair definition's `clearance` may override them).
SCALP_ABOVE = 0.85
SCALP_REACH_M = 0.05
SCALP_COVERED_SHARE = 0.98
CROWN_MAX_M = 0.06
FACE_DEPTH_M = 0.05


def _head_island(body):
    head = body.vertex_groups["Head"].index
    world = body.matrix_world
    return [world @ v.co for v in body.data.vertices if v.co.z > 1.5 and any(g.group == head and g.weight >= 0.99 for g in v.groups)]


def hair_checks(hair, body, definition, manifest):
    """Face clearance (no hair inside the character's head-relative face volume),
    scalp coverage (the crown's skull is covered by hair outward from the head's
    centre) and the crown bound (hair adds at most CROWN_MAX_M above the skull)."""
    clearance = definition.get("clearance", {})
    face = manifest["identity"]["face"]["clearance"]
    skull = _head_island(body)
    low = min(p.z for p in skull)
    height = max(p.z for p in skull) - low
    half_width = max(abs(p.x) for p in skull)
    front = min(p.y for p in skull)
    back = max(p.y for p in skull)
    centre = Vector((0.0, (front + back) * 0.5, low + 0.55 * height))
    points = [hair.matrix_world @ v.co for v in hair.data.vertices]
    z0, z1 = low + face["band"][0] * height, low + face["band"][1] * height
    in_face = [i for i, p in enumerate(points)
               if z0 <= p.z <= z1 and abs(p.x) <= face["width"] * half_width and front - face["reach_m"] <= p.y <= front + FACE_DEPTH_M]
    tree = BVHTree.FromPolygons(points, [list(p.vertices) for p in hair.data.polygons])
    above = clearance.get("scalp_above", SCALP_ABOVE)
    crown = [p for p in skull if (p.z - low) / height >= above]
    covered = 0
    for p in crown:
        direction = (p - centre).normalized()
        hit, _n, _i, distance = tree.ray_cast(p - direction * 0.002, direction, clearance.get("scalp_reach_m", SCALP_REACH_M))
        covered += hit is not None
    share = covered / max(1, len(crown))
    top = max(p.z for p in points) - (low + height)
    report = {"face_intrusions": len(in_face), "scalp_covered": round(share, 3), "crown_above_skull_m": round(top, 4)}
    hard = []
    if in_face:
        hard.append("%d hair vertices inside the face clearance" % len(in_face))
    if share < clearance.get("scalp_covered_share", SCALP_COVERED_SHARE):
        hard.append("scalp coverage %.2f below %.2f above %.2f of the head" % (share, clearance.get("scalp_covered_share", SCALP_COVERED_SHARE), above))
    if top > clearance.get("crown_max_m", CROWN_MAX_M):
        hard.append("hair rises %.3f m above the skull (bound %.3f)" % (top, clearance.get("crown_max_m", CROWN_MAX_M)))
    design, design_hard, findings = _design_checks(hair, definition, points)
    report["design"] = design
    return report, hard + design_hard, findings


## Status provisional: a mass further than this from every other mass reads as a
## separate, floating piece (calibrated on Wolf's two hairstyles and a detached lock).
ROOT_CONTACT_M = 0.002


def _design_checks(hair, definition, points):
    """The mesh's tagged masses against `design.regions` (every mass in exactly one
    declared region, every declared mass present), and each mass's contact gap to
    the rest of the hairstyle: a lock that touches nothing is floating."""
    names = list(hair.get("riposte_masses", []))
    attribute = hair.data.attributes.get("riposte_mass")
    if not names or attribute is None:
        return {"tagged": False}, ["%s is not tagged with its masses (rebuild it with its authoring script)" % hair.name], []
    owner = [d.value for d in attribute.data]
    design_regions = definition["design"]["regions"]
    declared = [m for masses in design_regions.values() for m in masses]
    hard = []
    unmapped = sorted(n for n in names if hair_design.region_of(n, design_regions) is None)
    ## A pattern may match nothing in one variant (no crown locks); a region may not.
    empty = sorted(region for region, patterns in design_regions.items()
                   if not any(fnmatch.fnmatchcase(n, p) for n in names for p in patterns))
    if unmapped:
        hard.append("masses %s belong to no design region" % unmapped)
    if empty:
        hard.append("design regions %s have no mass in the mesh" % empty)
    polygons = [list(p.vertices) for p in hair.data.polygons]
    gaps = {}
    for index, name in enumerate(names):
        mine = [f for f, o in zip(polygons, owner) if o == index]
        others = [f for f, o in zip(polygons, owner) if o != index]
        if not mine or not others:
            continue
        tree = BVHTree.FromPolygons(points, others)
        vertices = {v for f in mine for v in f}
        ## A vertex behind another surface (inside a mass, under the cap) means the mass
        ## passes through it: attached, whatever its vertices' distance to that surface.
        nearest = [tree.find_nearest(points[v]) for v in vertices]
        through = any(n[0] is not None and (points[v] - n[0]).dot(n[1]) < 0.0 for v, n in zip(vertices, nearest))
        gaps[name] = 0.0 if through else round(min(n[3] for n in nearest), 4)
    floating = sorted(n for n, g in gaps.items() if g > ROOT_CONTACT_M)
    findings = ["masses %s touch no other mass (contact gap > %.3f m)" % (floating, ROOT_CONTACT_M)] if floating else []
    overlaps = _mass_overlaps(names, owner, polygons, points)
    ## The scalp cap lies under the masses by contract (it is the coverage foundation).
    buried = sorted({pair.split(" in ")[0] for pair, o in overlaps.items()
                     if o["share"] > BURIED_SHARE and not pair.startswith("Cap ")})
    if buried:
        findings.append("masses %s are more than %d %% inside another mass: geometry that shapes nothing (advisory)" % (
            buried, round(BURIED_SHARE * 100)))
    report = {"tagged": True, "masses": len(names), "contact_gap_m": gaps, "overlaps": overlaps}
    if hair.get("riposte_locks"):
        metrics, heuristics = hair_design.heuristics(json.loads(hair["riposte_locks"]), design_regions)
        report["lock_metrics"] = metrics
        report["design_heuristics"] = heuristics
    return report, hard, findings


## Status advisory: a mass mostly inside another adds triangles and no silhouette.
BURIED_SHARE = 0.5


def _landmarks(body):
    """Rest joint positions (head, tail) by bone: the rig frame the surface regions live in."""
    rig = body.parent
    return {b.name: (tuple(rig.matrix_world @ b.head_local), tuple(rig.matrix_world @ b.tail_local)) for b in rig.data.bones}


def surface_region_of(body, surfaces):
    """Every body vertex's anatomical surface region at rest (spatial query; computed per run)."""
    landmarks = _landmarks(body)
    world = body.matrix_world
    return {v.index: surface_integration.classify(tuple(world @ v.co), landmarks, surfaces) for v in body.data.vertices}


def surface_checks(component, body, definition, surfaces, calibration):
    """Character Surface Integration at rest: each declared relationship measured on the
    component's parts in its design regions against the body surface they are nearest.
    Attach and clearance measure every vertex; drape measures the hanging locks' guides
    (their inner faces) and how each lock follows the body where it narrows."""
    landmarks = _landmarks(body)
    axis = landmarks[surfaces["axis"]][0]
    world = body.matrix_world
    body_points = [world @ v.co for v in body.data.vertices]
    tree = BVHTree.FromPolygons(body_points, [list(p.vertices) for p in body.data.polygons])
    names = list(component.get("riposte_masses", []))
    attribute = component.data.attributes.get("riposte_mass")
    owner = [d.value for d in attribute.data] if attribute is not None else []
    design = definition["design"]["regions"]
    locks = json.loads(component.get("riposte_locks", "[]"))
    points = [component.matrix_world @ v.co for v in component.data.vertices]

    def signed(p):
        nearest, normal, _face, distance = tree.find_nearest(p)
        if nearest is None:
            return None, None
        side = distance if (p - nearest).dot(normal) >= 0.0 else -distance
        return side, surface_integration.classify(tuple(nearest), landmarks, surfaces)

    def body_radius(p):
        d = Vector((p.x - axis[0], p.y - axis[1], 0.0))
        if d.length < 1e-6:
            return None
        d.normalize()
        origin = Vector((axis[0], axis[1], p.z))
        hit = tree.ray_cast(origin + d * 0.4, -d)[0]
        return None if hit is None else (Vector((hit.x, hit.y, 0.0)) - Vector((axis[0], axis[1], 0.0))).length

    report = {"relationships": []}
    hard, findings = [], []
    for rel in definition["surfaces"]["relationships"]:
        if rel.get("source", surface_integration.BASE_SOURCE) != surface_integration.BASE_SOURCE:
            report["relationships"].append({"region": rel["region"], "relationship": rel["relationship"],
                                            "unmeasured": "source %s is not in this assembly" % rel["source"]})
            continue
        wanted = set(rel["design_regions"])
        measured = {"distances": [], "locks": {}}
        if rel["relationship"] == "drape":
            mine = [l for l in locks if l.get("free") and hair_design.region_of(l["name"], design) in wanted]
            for lock in mine:
                pts = [Vector(p) for p in lock["points"]]
                for p in pts:
                    side, region = signed(p)
                    if region == rel["region"]:
                        measured["distances"].append(side)
                pairs = [(Vector((p.x - axis[0], p.y - axis[1], 0.0)).length, body_radius(p)) for p in pts]
                pairs = [pair for pair in pairs if pair[1] is not None]
                c = surface_integration.conformity(pairs)
                if c is None:
                    continue
                ## A lock is judged where the body narrows most beneath it.
                widest = max(range(len(pairs)), key=lambda i: pairs[i][1])
                narrowest = widest + min(range(len(pairs) - widest), key=lambda i: pairs[widest + i][1])
                _side, region = signed(pts[narrowest])
                if region == rel["region"]:
                    measured["locks"][lock["name"]] = pairs
        else:
            masses = {i for i, n in enumerate(names) if hair_design.region_of(n, design) in wanted}
            vertices = {v for p in component.data.polygons if owner and owner[p.index] in masses for v in p.vertices}
            for v in sorted(vertices):
                side, region = signed(points[v])
                if region == rel["region"]:
                    measured["distances"].append(side)
        result, found = surface_integration.evaluate(rel, measured, calibration)
        report["relationships"].append(result)
        for f in found:
            (hard if f["severity"] == "hard" else findings).append(
                "surface %s %s: %s%s" % (f["region"], f["metric"], f["message"], " (advisory)" if f["severity"] == "advisory" else ""))
        report.setdefault("findings", []).extend(found)
    return report, hard, findings


def _closed(faces):
    """Every edge of these faces is shared by exactly two of them."""
    uses = {}
    for face in faces:
        for a, b in zip(face, face[1:] + face[:1]):
            key = (min(a, b), max(a, b))
            uses[key] = uses.get(key, 0) + 1
    return all(count == 2 for count in uses.values())


def _mass_overlaps(names, owner, polygons, points):
    """For every ordered pair of authored masses (the open scalp cap is no container),
    the share of A's vertices inside closed mass B and the deepest of them. Roots
    overlapping is the design (locks grow out of each other); a mass mostly inside
    another is not."""
    faces_of = {i: [f for f, o in zip(polygons, owner) if o == i] for i in range(len(names))}
    overlaps = {}
    for b, name_b in enumerate(names):
        ## Only a closed mass has an inside (open shell bands and the cap do not).
        if not faces_of[b] or not _closed(faces_of[b]):
            continue
        tree = BVHTree.FromPolygons(points, faces_of[b])
        for a, name_a in enumerate(names):
            if a == b or not faces_of[a]:
                continue
            vertices = {v for f in faces_of[a] for v in f}
            depths = []
            for v in vertices:
                nearest, normal, _i, distance = tree.find_nearest(points[v])
                if nearest is not None and (points[v] - nearest).dot(normal) < 0.0:
                    depths.append(distance)
            if depths:
                overlaps["%s in %s" % (name_a, name_b)] = {"share": round(len(depths) / len(vertices), 3),
                                                           "max_depth_m": round(max(depths), 4)}
    return overlaps


def _key_values(values, parameters):
    """Shape-key weights for a configuration: each signed parameter drives its
    `_minus` or `_plus` key (the export's bake rule)."""
    known = {p["id"] for p in parameters}
    weights = {}
    for parameter, value in values.items():
        if parameter in known and value != 0:
            weights["%s_%s" % (parameter, "plus" if value > 0 else "minus")] = abs(value)
    return weights


def _set_keys(obj, weights):
    """Apply key weights; returns the keys the object lacks (a configuration it cannot follow)."""
    missing = []
    blocks = obj.data.shape_keys.key_blocks if obj.data.shape_keys else {}
    for block in (blocks.values() if blocks else []):
        if block.name != "Basis":
            block.value = 0.0
    for name, weight in weights.items():
        if name in blocks:
            blocks[name].value = weight
        else:
            missing.append(name)
    return missing


def _pose(rig, clip, frame):
    if rig.animation_data is None:
        rig.animation_data_create()
    if clip is None:
        rig.animation_data.action = None
        for bone in rig.pose.bones:
            bone.matrix_basis.identity()
    else:
        rig.animation_data.action = bpy.data.actions[clip]
    bpy.context.scene.frame_set(int(frame))


def _evaluated(obj, depsgraph):
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    points = [obj.matrix_world @ v.co for v in mesh.vertices]
    faces = [list(p.vertices) for p in mesh.polygons]
    evaluated.to_mesh_clear()
    return points, faces


def _penetration(garment_points, body_points, body_faces):
    """(count inside, worst signed distance, its garment vertex, nearest body vertex)."""
    tree = BVHTree.FromPolygons(body_points, body_faces)
    inside, worst, worst_vertex, worst_body = 0, 0.0, -1, -1
    for index, p in enumerate(garment_points):
        nearest, normal, face, distance = tree.find_nearest(p)
        if nearest is None:
            continue
        signed = distance if (p - nearest).dot(normal) >= 0.0 else -distance
        if signed < -PENETRATION_M:
            inside += 1
            if signed < worst:
                worst, worst_vertex = signed, index
                worst_body = min(body_faces[face], key=lambda i: (body_points[i] - p).length)
    return inside, worst, worst_vertex, worst_body


def envelope(garment, body, definition, regions, configurations, clips, frame_step=0, surface_region=None,
             configuration_path=CONFIGURATION):
    """Penetration of the garment through the body across configurations x poses,
    each measured on the posed, configured meshes together. Every failing sample
    names its worst vertex, the fitting region under it, and the likely owning
    layer (rest at default: fit/topology; a configuration only: the garment's
    physique shape; a pose only: its weights)."""
    with open(configuration_path, encoding="utf-8") as handle:
        configuration = json.load(handle)
    region_of = {}
    ## Fitting regions are vertex sets on one topology: on another body they name nothing
    ## (the rig-relative surface regions still attribute every failure).
    regions_current = regions.get("topology_fingerprint") == character_assembly.topology_fingerprint(body)
    for name, region in (regions["regions"].items() if regions_current else ()):
        for v in region["vertices"]:
            region_of[v] = name
    rig = body.parent
    samples = [(None, 0)]
    for clip in clips:
        end = int(bpy.data.actions[clip].frame_range[1])
        if frame_step > 0:
            samples += [(clip, f) for f in sorted(set(range(0, end + 1, frame_step)) | {end})]
        else:
            samples += [(clip, round(end * k / (FRAMES_PER_CLIP - 1))) for k in range(FRAMES_PER_CLIP)]
    failures, missing_keys = [], {}
    for name in configurations:
        weights = _key_values(configuration["configurations"][name], configuration["parameters"])
        _set_keys(body, weights)
        lacking = _set_keys(garment, weights)
        ## A definition that declares it follows no physique is not asked for keys.
        if lacking and definition["deformation"].get("physique", "keys") == "keys":
            missing_keys[name] = lacking
        for clip, frame in samples:
            _pose(rig, clip, frame)
            depsgraph = bpy.context.evaluated_depsgraph_get()
            body_points, body_faces = _evaluated(body, depsgraph)
            garment_points, _faces = _evaluated(garment, depsgraph)
            inside, worst, vertex, nearest_body = _penetration(garment_points, body_points, body_faces)
            if inside:
                at_rest = clip is None
                owner = ("fit or topology" if name == "default" else "garment physique shape") if at_rest else "weights or topology at a joint"
                failures.append({"configuration": name, "clip": clip or "rest", "frame": frame, "inside": inside,
                                 "worst_m": round(worst, 4), "vertex": vertex, "region": region_of.get(nearest_body, "?"),
                                 "surface_region": (surface_region or {}).get(nearest_body), "nearest_body": nearest_body,
                                 "likely_owner": owner})
    _set_keys(body, {})
    _set_keys(garment, {})
    _pose(rig, None, 0)
    failures.sort(key=lambda f: f["worst_m"])
    by_clip, by_region = {}, {}
    for f in failures:
        by_clip[f["clip"]] = by_clip.get(f["clip"], 0) + 1
        by_region.setdefault(f["region"], f)
    return {"configurations": list(configurations), "clips": list(clips), "samples": len(samples) * len(configurations),
            "failing_samples": len(failures), "failing_by_clip": by_clip, "worst_by_region": by_region,
            "failing_by_surface_region": surface_integration.attribute(failures, surface_region or {}),
            "worst": failures[:10], "missing_keys": missing_keys, "fitting_regions_current": regions_current}


def _prepare(garment, body, definition):
    """In memory only (the audit never saves): make a linked base posable and bind
    the asset to the rig the way its definition says, so poses deform it."""
    rig = body.parent
    if not bpy.data.actions:
        ## An attire blend links the base's objects, not its clips: borrow them.
        with bpy.data.libraries.load(BASE_MASTER, link=False) as (source, target):
            target.actions = list(source.actions)
    for obj in (rig, body):
        if obj.library is not None:
            obj.make_local()
    if body.data.library is not None:
        body.data.make_local()
    if body.data.shape_keys is not None and body.data.shape_keys.library is not None:
        body.data.shape_keys.make_local()
    deformation = definition["deformation"]
    if deformation["method"] == "rigid":
        garment.vertex_groups.clear()
        group = garment.vertex_groups.new(name=deformation["bone"])
        group.add(list(range(len(garment.data.vertices))), 1.0, "REPLACE")
    if not any(m.type == "ARMATURE" and m.object == rig for m in garment.modifiers):
        modifier = garment.modifiers.new("Armature", "ARMATURE")
        modifier.object = rig


def main():
    args = _arguments()
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(args.blend))
    with open(os.path.abspath(args.definition), encoding="utf-8") as handle:
        definition = json.load(handle)
    with open(REGIONS, encoding="utf-8") as handle:
        regions = json.load(handle)
    _prepare(bpy.data.objects[args.garment], bpy.data.objects["Body"], definition)
    report = audit(bpy.data.objects[args.garment], bpy.data.objects["Body"], definition, regions)
    if args.manifest and definition.get("type") == "hair":
        with open(os.path.abspath(args.manifest), encoding="utf-8") as handle:
            manifest = json.load(handle)
        report["hair"], hard, findings = hair_checks(bpy.data.objects[args.garment], bpy.data.objects["Body"], definition, manifest)
        report["hard"] += hard
        report["findings"] += findings
    surface_region = None
    if definition.get("surfaces"):
        with open(SURFACES, encoding="utf-8") as handle:
            surfaces = json.load(handle)
        calibration = None
        if os.path.exists(CALIBRATION):
            with open(CALIBRATION, encoding="utf-8") as handle:
                calibration = json.load(handle)
        problems = surface_integration.region_problems(surfaces, {b.name for b in bpy.data.objects["Body"].parent.data.bones})
        problems += surface_integration.relationship_problems(definition, surfaces)
        report["hard"] += problems
        if not problems:
            report["surface_integration"], hard, findings = surface_checks(
                bpy.data.objects[args.garment], bpy.data.objects["Body"], definition, surfaces, calibration)
            report["hard"] += hard
            report["findings"] += findings
            surface_region = surface_region_of(bpy.data.objects["Body"], surfaces)
    if args.configurations or args.clips:
        configurations = definition.get("supported_configurations", ["default"]) if args.configurations in ("", "all") else args.configurations.split(",")
        if args.clips == "all":
            clips = sorted(a.name for a in bpy.data.actions)
        else:
            clips = list(ENVELOPE_CLIPS) if args.clips in ("", "envelope") else [c for c in args.clips.split(",") if c]
        report["envelope"] = envelope(bpy.data.objects[args.garment], bpy.data.objects["Body"], definition, regions,
                                      configurations, clips, args.frame_step, surface_region, os.path.abspath(args.configuration))
        if report["envelope"]["failing_samples"]:
            report["hard"].append("%d of %d envelope samples penetrate the body" % (report["envelope"]["failing_samples"], report["envelope"]["samples"]))
        for name, keys in report["envelope"]["missing_keys"].items():
            report["findings"].append("configuration %s: the garment lacks keys %s (run garment_physique.py)" % (name, keys))
    print("RIPOSTE_GARMENT_AUDIT", json.dumps(report))
    if args.json:
        with open(os.path.abspath(args.json), "w", encoding="utf-8", newline="\n") as handle:
            json.dump(report, handle, indent=2)
    sys.exit(1 if report["hard"] else 0)


if __name__ == "__main__":
    main()
