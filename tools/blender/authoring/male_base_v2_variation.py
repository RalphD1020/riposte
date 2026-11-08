"""Build resolved characters on the default foundation (CHARACTER-VARIATION-001,
CHARACTER-FOUNDATION-001) and measure the fit.

The Blender half of `character_modeling.variation`: the pure resolver decides every number
(physique parameters, head proportions and morphology, identity placement) and
`foundation.apply` adds the foundation's resolution switches; this applies them to the
foundation's base objects (`male_base.foundation.blend`: `BodyV2`, `HeadV2`, never edited) on
copies, then fits the face (the foundation's default marks, or a character's) with
`face_features.place_marks` and, for a character's outfit only, its hairstyle
(`wolf_hair.build_style`) to the resolved head and body. No vertex index of any default head
is used. The default-body sets (configurations, matrix, sweep) build no hair and read no
character; `--set wolf` builds Wolf's outfits on top; `--lock` / `--verify-lock` (sweep only)
write or check the foundation's lock.

- Body: the configuration keys of v1's `Body` (16 keys, 8 parameters), evaluated in the
  authoring A-pose and carried onto `BodyV2` by the nearest point of v1's posed surface
  (as `garment_physique` carries them onto a garment), then smoothed over `BodyV2` so v1's
  facets do not print into the sculpt; the neck follows the head's `neck_transition`.
- Head: `variation.head_displacement` on a copy of `HeadV2` and on its stored
  construction surface, then the allometric size about the Head joint.
- Stature: the whole character scales by `height / 1.80` about the floor, as the game's
  fighter does.

Review builds: the outputs are scratch blends (lineups) and a JSON report; no master, no
attire blend, no export is written.

    blender --background --factory-startup --python tools/blender/authoring/male_base_v2_variation.py -- \
        --set configurations|matrix|sweep|identity|hair|hair_sweep_ranger|hair_sweep_training|hair_identity|wolf --out <dir>
        [--hair-variants ranger=G,training=F] [--seat-neck] [--lock|--verify-lock]

`--seat-neck` builds the neck-seating candidate (`male_base_v2.seat_neck`) on every
resolved character.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.interpolate import poly_3d_calc

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools", "character_modeling"))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender", "inspect"))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender"))
import character_assembly  # noqa: E402
import ear_component  # noqa: E402
import face_surface  # noqa: E402
import male_base_v2 as v2  # noqa: E402
import face_features  # noqa: E402
import facial_hair  # noqa: E402
import wolf_hair  # noqa: E402
from character_modeling import appearance, chest_profile, face_mapping, foundation, garments, rig_regions, silhouette, variation  # noqa: E402

CONFIGURATION = os.path.join(v2.CHARACTERS, "male_base.v2.configuration.json")
## Wolf, the first character on the foundation (`--set wolf`); the default sets never read it.
## A review copy of his manifest (a candidate identity) replaces it through
## RIPOSTE_CHARACTER_REVIEW.
WOLF = os.environ.get("RIPOSTE_CHARACTER_REVIEW") or os.path.join(v2.CHARACTERS, "wolf", "wolf.assembly.json")
## Smoothing of the transferred key deltas over BodyV2 (v1's facets are ~40 mm wide).
DELTA_SMOOTH_ITERATIONS = 40
NECK_BAND = (-0.3, 0.0, 0.7, 1.0)
SPACING_M = 1.9
## Fit tolerances (metres): hair may rest on the scalp within this depth; a mark's base may
## sit this far off the surface (it is sunk by its own depth_m by design).
HAIR_INSIDE_TOLERANCE_M = 0.0015
## A head triangle whose normal points down more steeply than this is the underside.
UNDERSIDE_NORMAL_Z = 0.5


def _document():
    with open(CONFIGURATION, encoding="utf-8") as handle:
        return json.load(handle)


def _foundation():
    return v2.foundation_document()[1]


def _variants():
    """The variant-generation settings: a review copy (RIPOSTE_VARIANTS_REVIEW), else the
    library's current approved `male_base_variants`, else none (the foundation's defaults)."""
    from character_modeling import asset_library
    review = os.environ.get("RIPOSTE_VARIANTS_REVIEW")
    if review:
        with open(review, encoding="utf-8") as handle:
            return json.load(handle)
    if "male_base_variants" not in asset_library.index()["assets"]:
        return None
    return asset_library.payload("male_base_variants", "variants.json")


def _lock_reference(base, blender):
    """The lock the default bodies are checked against: the current variants version's
    (when it carries one), else the foundation's."""
    from character_modeling import asset_library
    if not os.environ.get("RIPOSTE_VARIANTS_REVIEW") and "male_base_variants" in asset_library.index()["assets"]:
        if "lock.json" in asset_library.asset("male_base_variants")["files"]:
            return asset_library.payload("male_base_variants", "lock.json")
    with open(foundation.path_of(base, "lock", blender), encoding="utf-8") as handle:
        return json.load(handle)


def _identity(character=None):
    """The identity a character is dressed in: its own manifest, else the foundation's
    default identity (a neutral palette and the default face)."""
    return character if character is not None else foundation.identity_manifest(_foundation())


def _wolf():
    with open(WOLF, encoding="utf-8") as handle:
        return json.load(handle)


def _coords(obj):
    import numpy as np
    co = np.empty(len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get("co", co)
    return co.reshape(-1, 3)


def _evaluated(body):
    import numpy as np
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = body.evaluated_get(depsgraph).to_mesh()
    co = np.empty(len(mesh.vertices) * 3)
    mesh.vertices.foreach_get("co", co)
    body.evaluated_get(depsgraph).to_mesh_clear()
    return co.reshape(-1, 3) @ np.array(body.matrix_world.to_3x3()).T + np.array(tuple(body.matrix_world.translation))


def key_deltas():
    """{key name: (n, 3) delta on BodyV2}: v1's keys in the A-pose, carried and smoothed."""
    import numpy as np
    v2.apose()
    body, target = bpy.data.objects["Body"], bpy.data.objects[v2.SCULPT]
    blocks = body.data.shape_keys.key_blocks
    for block in blocks[1:]:
        block.value = 0.0
    basis = _evaluated(body)
    posed = {}
    for block in blocks[1:]:
        block.value = 1.0
        posed[block.name] = _evaluated(body) - basis
        block.value = 0.0
    faces = [list(p.vertices) for p in body.data.polygons]
    tree = BVHTree.FromPolygons([Vector(p) for p in basis], faces)
    points = _coords(target)
    count = len(points)
    index = np.zeros((count, 4), dtype=np.int64)
    weight = np.zeros((count, 4))
    for i, p in enumerate(points):
        location, _n, face, _d = tree.find_nearest(Vector(p))
        corners = faces[face]
        share = poly_3d_calc([Vector(basis[c]) for c in corners], location)
        index[i, :len(corners)] = corners
        weight[i, :len(corners)] = share
    edges = np.array([tuple(e.vertices) for e in target.data.edges])
    degree = np.bincount(edges.ravel(), minlength=count).astype(float)
    out = {}
    for name, delta in posed.items():
        d = (weight[:, :, None] * delta[index]).sum(axis=1)
        for _round in range(DELTA_SMOOTH_ITERATIONS):
            total = np.zeros_like(d)
            np.add.at(total, edges[:, 0], d[edges[:, 1]])
            np.add.at(total, edges[:, 1], d[edges[:, 0]])
            d = 0.5 * d + 0.5 * total / np.maximum(degree, 1.0)[:, None]
        out[name] = d
    return out


def _neck_scale(points, weights, scale):
    import numpy as np
    if scale == 1.0:
        return points
    _m, head, tail = v2.bone_frame("Neck")
    head, tail = np.array(tuple(head)), np.array(tuple(tail))
    a = (tail - head) / np.linalg.norm(tail - head)
    along = (points - head) @ a
    t = along / np.linalg.norm(tail - head)
    radial = points - (head + along[:, None] * a)
    w = np.minimum(weights.get("Neck", 0.0), 1.0) * v2._window(np, t, NECK_BAND)
    return points + (w * (scale - 1.0))[:, None] * radial


## Vertex groups that are the arm (outside the torso's silhouette).
ARM_GROUPS = ("Arm", "Hand", "Finger", "Thumb")
## The silhouette's torso half-width at the reference stature (metres): the A-pose arms lie
## outside it below the armpit.
SILHOUETTE_HALF_WIDTH_M = 0.19
SILHOUETTE_STEP_H = 0.005


def _arm_weight(weights, resolved, legacy=True):
    """Each vertex's arm weight: the arm regions' (`rig_regions.ARM`) summed, clamped. `legacy`
    (the protected builds' ARM_GROUPS substring match, which misses the forearm) unless the
    resolved character asks for the region fix (`region_fix`)."""
    import numpy as np
    total = None
    for name, w in weights.items():
        if (any(s in name for s in ARM_GROUPS) if legacy and not resolved.get("region_fix")
                else rig_regions.in_regions(name, rig_regions.ARM)):
            total = w.copy() if total is None else total + w
    return np.zeros(len(next(iter(weights.values())))) if total is None else np.minimum(total, 1.0)


def _silhouette(co, weights, resolved, key="silhouette_study"):
    """`co` with the resolved body's silhouette study `resolved[key]` applied (`silhouette`):
    at each height the correction moves the front (back) of the torso and legs, fully at the
    silhouette's front-most (back-most) surface and fading to nothing at the body's middle,
    the arms excluded; one smooth contour per side, never a local push."""
    import numpy as np
    study = resolved.get(key)
    if not study:
        return co
    problems = silhouette.anchor_problems(study)
    if problems:
        raise ValueError("; ".join(problems))
    ## The body is built at the reference stature; its height is the root's scale.
    stature = float(resolved["body"]["height_m"]) / float(resolved["stature_scale"])
    mass = resolved["parameters"]["mass"]
    scale = stature / silhouette.REFERENCE_STATURE_M / 100.0
    body = 1.0 - _arm_weight(weights, resolved)
    h = co[:, 2] / stature
    torso = (np.abs(co[:, 0] - np.median(co[:, 0])) < SILHOUETTE_HALF_WIDTH_M * stature / silhouette.REFERENCE_STATURE_M) & (body > 0.5)
    grid = np.arange(0.28, 0.92, SILHOUETTE_STEP_H)
    front = np.full(len(grid), np.nan)
    back = np.full(len(grid), np.nan)
    for i, g in enumerate(grid):
        band = co[torso & (np.abs(h - g) < 0.006), 1]
        if len(band):
            front[i], back[i] = band.min(), band.max()
    ok = ~np.isnan(front)
    front_at = np.interp(h, grid[ok], front[ok])
    back_at = np.interp(h, grid[ok], back[ok])
    middle = 0.5 * (front_at + back_at)
    out = co.copy()
    for side, edge, sign in (("front", front_at, -1.0), ("back", back_at, 1.0)):
        delta = np.array([silhouette.smoothed(study, mass, side, g) for g in grid]) * scale
        share = np.clip((co[:, 1] - middle) / np.where(np.abs(edge - middle) > 1e-6, edge - middle, 1e-6), 0.0, 1.0)
        out[:, 1] += sign * np.interp(h, grid, delta) * share ** 2 * body
    return out


## The chest system's lateral mask at the reference stature (metres from the body's centre):
## full across the pectorals, fading to nothing at the deltoids' front.
CHEST_MASK_X_M = (0.15, 0.21)
## `chest_fit`: the closed loop eases in over this much h inside the band's ends.
CHEST_FIT_EDGE_H = 0.03


def _chest(co, weights, resolved):
    """`co` with the resolved body's anterior chest profile (`chest_profile`): inside the
    chest band only, the front of the thorax moves toward the authored side profile, fully at
    the silhouette's front-most surface, fading to nothing at the body's middle and outside
    the lateral mask; the back, the arms and every other region are untouched."""
    import numpy as np
    study = resolved.get("chest_study")
    if not study:
        return co
    problems = chest_profile.problems(study)
    if problems:
        raise ValueError("; ".join(problems))
    stature = float(resolved["body"]["height_m"]) / float(resolved["stature_scale"])
    mass = resolved["parameters"]["mass"]
    scale = stature / chest_profile.REFERENCE_STATURE_M
    body = 1.0 - _arm_weight(weights, resolved)
    h = co[:, 2] / stature
    ax = np.abs(co[:, 0] - np.median(co[:, 0])) / scale
    lo, hi = CHEST_MASK_X_M
    lateral = np.clip((hi - ax) / (hi - lo), 0.0, 1.0)
    lateral = lateral * lateral * (3.0 - 2.0 * lateral)
    torso = (ax < SILHOUETTE_HALF_WIDTH_M) & (body > 0.5)
    lo_h, hi_h = chest_profile.band(study)
    grid = np.arange(lo_h - 0.01, hi_h + 0.011, SILHOUETTE_STEP_H)
    front = np.full(len(grid), np.nan)
    back = np.full(len(grid), np.nan)
    for i, g in enumerate(grid):
        band = co[torso & (np.abs(h - g) < 0.006), 1]
        if len(band):
            front[i], back[i] = band.min(), band.max()
    ok = ~np.isnan(front)
    front_at = np.interp(h, grid[ok], front[ok])
    middle = 0.5 * (front_at + np.interp(h, grid[ok], back[ok]))
    delta = np.array([chest_profile.smoothed(study, mass, g) for g in grid]) * scale / 100.0
    closure = min(max(float(mass) + 1.0, 0.0), 1.0) if resolved.get("chest_fit") else 0.0
    if closure:
        ## `chest_fit`: the authored profile's own kinks off (`chest_profile.smoothed_target`
        ## minus `target`: the landmarks' uneven slopes, the two-step lower pectoral), added
        ## to the open loop, so every body keeps its own depth (frame and development still
        ## shape it) and only the profile's shape is evened; faded out at the band's ends
        ## (the neck and the rib-cage return keep theirs); none at the lean, full from the
        ## reference up.
        kinks = np.array([chest_profile.smoothed_target(study, mass, g) - chest_profile.target(study, mass, g)
                          for g in grid]) * scale / 100.0
        fade = v2._window(np, grid, (lo_h, lo_h + CHEST_FIT_EDGE_H, hi_h - CHEST_FIT_EDGE_H, hi_h))
        delta = delta + closure * fade * kinks
    share = np.clip((co[:, 1] - middle) / np.where(np.abs(front_at - middle) > 1e-6, front_at - middle, 1e-6), 0.0, 1.0)
    inside = (h > lo_h) & (h < hi_h)
    out = co.copy()
    out[:, 1] -= np.where(inside, np.interp(h, grid, delta), 0.0) * share ** 2 * lateral * body
    return out


## The height (h) where the A-pose arm is measured leaving the torso, and the reach (metres
## at the reference stature) over which an arm's girth change fades in: none inside the
## torso's width, so the back and the chest never move with an arm.
ARMPIT_H = 0.72
ARM_TORSO_FADE_M = (0.17, 0.21)


def _girth(co, weights, resolved):
    """`co` with the limbs' mass-driven girth (`variation.girth_factor`): each leg's
    horizontal cross-section scaled about its own centre at that height, each arm's
    cross-section across its length scaled about its centre (by its skin weight); lengths,
    joint centres and the torso untouched. A no-op at the reference, and above it unless the
    girth study is GIRTH_FULL (the strongman's distal fullness)."""
    import numpy as np
    mass = resolved["parameters"]["mass"]
    strong = resolved.get("girth_study") == variation.GIRTH_FULL
    if not resolved.get("girth_study") or mass == 0.0 or (mass > 0.0 and not strong):
        return co
    stature = float(resolved["body"]["height_m"]) / float(resolved["stature_scale"])
    arm = _arm_weight(weights, resolved, legacy=False)
    out = co.copy()
    cx = np.median(co[:, 0])
    h = co[:, 2] / stature
    for sign in (1.0, -1.0):
        side = (co[:, 0] - cx) * sign > 0.0
        ## Legs: by height, about each slice's centre.
        leg = side & (h < 0.47) & (arm < 0.5)
        grid = np.arange(0.0, 0.475, 0.005)
        centre = np.full((len(grid), 2), np.nan)
        for i, g in enumerate(grid):
            s = leg & (np.abs(h - g) < 0.004)
            if s.any():
                centre[i] = co[s][:, :2].mean(axis=0)
        ok = ~np.isnan(centre[:, 0])
        if ok.any():
            c = np.stack([np.interp(h[leg], grid[ok], centre[ok, k]) for k in range(2)], axis=1)
            f = np.array([variation.girth_factor(mass, "leg", t, strong) for t in h[leg]])
            out[leg, :2] = c + (co[leg, :2] - c) * f[:, None]
        ## Arms: by share from the armpit (where the arm leaves the torso at chest height) to
        ## the fingertip, about each slice's centre; never inside the torso's width.
        limb = side & (arm > 0.0)
        if not limb.any():
            continue
        reach = np.abs(co[:, 0] - cx)
        tip = reach[limb].max()
        chest = np.sort(reach[side & (np.abs(h - ARMPIT_H) < 0.004)])
        gaps = np.diff(chest)
        armpit = float(chest[np.argmax(gaps)] + gaps.max() / 2.0) if len(gaps) and gaps.max() > 0.01 else SILHOUETTE_HALF_WIDTH_M
        share = (reach - armpit) / max(tip - armpit, 1e-6)
        lo, hi = ARM_TORSO_FADE_M
        arm = arm * np.clip((reach / (stature / silhouette.REFERENCE_STATURE_M) - lo) / (hi - lo), 0.0, 1.0)
        limb = limb & (arm > 0.0)
        grid = np.linspace(0.0, 1.0, 81)
        centre = np.full((len(grid), 2), np.nan)
        for i, g in enumerate(grid):
            s = limb & (np.abs(share - g) < 0.008)
            if s.any():
                centre[i] = co[s][:, 1:].mean(axis=0)
        ok = ~np.isnan(centre[:, 0])
        c = np.stack([np.interp(share[limb], grid[ok], centre[ok, k]) for k in range(2)], axis=1)
        f = np.array([variation.girth_factor(mass, "arm", t, strong) for t in np.clip(share[limb], 0.0, 1.0)])
        f = 1.0 + (f - 1.0) * arm[limb]
        out[limb, 1:] = c + (co[limb, 1:] - c) * f[:, None]
    return out


## Chest smoothing (`chest_smooth`): the strongman's and reference's chest front read lumpy
## in profile, ripples 3-5 cm across (a volume-preserving Taubin pass kept them: they are
## low frequencies on this mesh). Laplacian passes in depth take the ripples off the chest
## front's surface; the side contour is then restored to its own lightly smoothed shape
## (CHEST_SMOOTH_CONTOUR_H), so its depth, peak height and plateau stay while its waves go.
## Only the front of the chest band, with soft edges; the lean (mass -1) is untouched.
CHEST_SMOOTH_PASSES = 90
CHEST_SMOOTH_LAMBDA = 0.6
CHEST_SMOOTH_BAND = (0.60, 0.64, 0.81, 0.845)
CHEST_SMOOTH_CONTOUR_H = 0.012


def _smooth_chest(co, obj, weights, resolved):
    """`co` with the chest's front surface smoothed in depth (Laplacian passes over the
    mesh's own edges, moving y only, so the front view is untouched; then its side contour
    restored to its own lightly smoothed shape): weight 1 inside the band's core, the
    pectoral mask and the front of
    the body, falling softly to 0 at their edges and on the arms, so nothing outside moves.
    Strength rises from 0 at the lean to 1 at the reference and above."""
    import numpy as np
    strength = min(max(float(resolved["parameters"]["mass"]) + 1.0, 0.0), 1.0)
    if not resolved.get("chest_smooth") or strength == 0.0:
        return co
    stature = float(resolved["body"]["height_m"]) / float(resolved["stature_scale"])
    scale = stature / chest_profile.REFERENCE_STATURE_M
    h = co[:, 2] / stature
    ax = np.abs(co[:, 0] - np.median(co[:, 0])) / scale
    w = v2._window(np, h, CHEST_SMOOTH_BAND)
    lo, hi = CHEST_MASK_X_M
    lateral = np.clip((hi - ax) / (hi - lo), 0.0, 1.0)
    w = w * lateral * lateral * (3.0 - 2.0 * lateral)
    ## The front of the body: ahead of the torso's middle at that height (a soft ramp).
    torso = ax < SILHOUETTE_HALF_WIDTH_M
    grid = np.arange(CHEST_SMOOTH_BAND[0] - 0.01, CHEST_SMOOTH_BAND[3] + 0.011, SILHOUETTE_STEP_H)
    mid = np.full(len(grid), np.nan)
    for i, g in enumerate(grid):
        s = torso & (np.abs(h - g) < 0.006)
        if s.any():
            mid[i] = 0.5 * (co[s, 1].min() + co[s, 1].max())
    ok = ~np.isnan(mid)
    middle = np.interp(h, grid[ok], mid[ok])
    front = np.clip((middle - co[:, 1]) / (0.06 * scale), 0.0, 1.0)
    w = w * front * (1.0 - _arm_weight(weights, resolved, legacy=False)) * strength
    edges = np.empty(len(obj.data.edges) * 2, dtype=np.int64)
    obj.data.edges.foreach_get("vertices", edges)
    edges = edges.reshape(-1, 2)
    degree = np.bincount(edges.ravel(), minlength=len(co)).astype(float)
    degree[degree == 0] = 1.0

    def contour(points):
        f = np.full(len(grid), np.nan)
        for i, g in enumerate(grid):
            s = torso & (np.abs(h - g) < 0.006)
            if s.any():
                f[i] = points[s, 1].min()
        return f
    before = contour(co)
    out = co.copy()
    for _k in range(CHEST_SMOOTH_PASSES):
        total = np.zeros_like(out)
        np.add.at(total, edges[:, 0], out[edges[:, 1]])
        np.add.at(total, edges[:, 1], out[edges[:, 0]])
        ## Depth only: the side profile is smoothed, the front view (x, z) never moves.
        out[:, 1] = out[:, 1] + CHEST_SMOOTH_LAMBDA * w * (total[:, 1] / degree - out[:, 1])
    ## The contour back to the original's, lightly smoothed along h (its waves off, its
    ## depth and landmarks kept), fading to the original at the band's ends.
    after = contour(out)
    ok = ~np.isnan(before) & ~np.isnan(after)
    kernel = np.exp(-0.5 * (np.arange(-6, 7) * SILHOUETTE_STEP_H / CHEST_SMOOTH_CONTOUR_H) ** 2)
    smooth = np.convolve(np.pad(before[ok], 6, mode="edge"), kernel / kernel.sum(), mode="valid")
    blend = v2._window(np, grid[ok], CHEST_SMOOTH_BAND)
    target = before[ok] + blend * (smooth - before[ok])
    delta = np.interp(h, grid[ok], target - after[ok])
    edge = np.interp(h, grid[ok], after[ok])
    share = np.clip((out[:, 1] - middle) / np.where(np.abs(edge - middle) > 1e-6, edge - middle, 1e-6), 0.0, 1.0)
    out[:, 1] += delta * share ** 2 * (w > 0) * np.clip(w / max(strength, 1e-6), 0.0, 1.0) * strength
    return out


def _shifted(co, shifts):
    """`co` moved by broad mirrored shifts {name: (centre, radius, direction, amount)} (the
    base's HERO shift form)."""
    import numpy as np
    out = co.copy()
    p = co.copy()
    sign = np.where(p[:, 0] < 0.0, -1.0, 1.0)
    p[:, 0] = np.abs(p[:, 0])
    for centre, radius, direction, amount in shifts.values():
        if not amount:
            continue
        d = np.array(direction) / np.linalg.norm(direction)
        r = np.linalg.norm(p - np.array(centre), axis=1)
        move = (amount * np.exp(-0.5 * (r / radius) ** 2))[:, None] * d
        move[:, 0] *= sign
        out += move
    return out


def _identity_materials(identity=None):
    """The identity's skin (its shared swatch) and hair, as the assembly makes them."""
    return character_assembly.identity_materials(_identity(identity), ROOT)


def _material(name, colour):
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.diffuse_color = colour
    return material


def build_body(resolved, deltas, weights, name, identity=None):
    source = bpy.data.objects[v2.SCULPT]
    obj = source.copy()
    obj.data = source.data.copy()
    obj.name = obj.data.name = name
    co = _coords(source)
    for parameter, value in resolved["parameters"].items():
        if value:
            co = co + abs(value) * deltas["%s_%s" % (parameter, "plus" if value > 0 else "minus")]
    co = _neck_scale(co, weights, resolved["head"]["neck_radial_scale"])
    co = _shifted(co, variation.physique_response(resolved["parameters"]["mass"]))
    co = _silhouette(co, weights, resolved)
    co = _chest(co, weights, resolved)
    co = _smooth_chest(co, obj, weights, resolved)
    co = _girth(co, weights, resolved)
    co = _silhouette(co, weights, resolved, "glute_study")
    obj.data.vertices.foreach_set("co", co.ravel())
    obj.data.update()
    obj.data.materials.clear()
    obj.data.materials.append(_identity_materials(identity)[0])
    return obj


def build_head(resolved, name, identity=None):
    """A copy of HeadV2 morphed by the resolved head parameters (surface and construction
    surface alike), then sized about the Head joint (relative to the body's stature)."""
    import numpy as np
    source = bpy.data.objects[v2.STUDY]
    obj = source.copy()
    obj.data = source.data.copy()
    obj.name = obj.data.name = name
    ## The control vertices found on the unmorphed head (same topology): the morph moves
    ## the chart frame, a lookup on the morphed head would miss them.
    controls = v2._mask_module().control_points(resolved.get("mask_study"))
    obj[v2.CONTROL_INDICES] = json.dumps(v2.face_control_indices(source, list(controls), resolved.get("mask_study")))
    stored = obj.data.attributes[v2.F0_ATTRIBUTE]
    construction = np.array([tuple(a.vector) for a in stored.data])
    frame = {"low": construction[:, 2].min(), "height": np.ptp(construction[:, 2]),
             "half_width": np.abs(construction[:, 0]).max(), "front": construction[:, 1].min(), "back": construction[:, 1].max()}
    params = variation.studied_head(resolved["head"]["parameters"], resolved.get("head_study"))
    proportions = resolved["head"]["proportions"]
    _m, pivot, _t = v2.bone_frame("Head")
    pivot = np.array(tuple(pivot))
    size = np.array([proportions["relative_scale"] * proportions["width_scale"],
                     proportions["relative_scale"] * proportions["depth_scale"], proportions["relative_scale"]])

    def morph(points):
        moved = np.array([np.add(p, variation.head_displacement(tuple(p), frame, params)) for p in points])
        return pivot + (moved - pivot) * size

    surface = morph(_coords(obj))
    obj.data.vertices.foreach_set("co", surface.ravel())
    stored.data.foreach_set("vector", morph(construction).ravel())
    obj.data.update()
    obj.data.materials.clear()
    obj.data.materials.append(_identity_materials(identity)[0])
    chart = (frame["low"], frame["height"], frame["half_width"])
    chart = (pivot[2] + (chart[0] - pivot[2]) * size[2], chart[1] * size[2], chart[2] * size[0])
    return obj, chart


def fit_face(head, chart, resolved, collection, prefix, identity=None):
    """The identity's face features on a resolved head (the same builder and checks as the
    character candidate): {object: base offset}, plus the structural face checks."""
    tree = face_features.head_of(head)
    manifest = _identity(identity)
    mask = resolved.get("mask_study")
    marks = resolved.get("marks") or _foundation()["default_identity"]["face"]["marks"]
    if resolved.get("face_response"):
        marks = variation.responded_marks(marks, variation.face_response(resolved))
    made = face_features.place_marks(collection, tree, chart[0], chart[1], chart[2], marks,
                                     resolved["face"]["eye_spacing_u"], resolved["face"]["brow_tilt_deg"],
                                     mask_parameters=mask, ridge=face_features.ridge_lines(v2.face_controls, head, parameters=mask))
    character_assembly.dress_face(made, character_assembly.palette_materials(manifest, ROOT))
    for obj, _component, _side in made:
        obj.name = "%s.%s" % (prefix, obj.name)
    return character_assembly.face_checks(made, tree)


def fit_hair(head, body, which, collection, prefix):
    """The hairstyle `which` (a style, or (style, variant) from its definition) fitted to
    the resolved head."""
    style, variant = which if isinstance(which, tuple) else (which, None)
    ## The head map's components: this character's resolved ears and brows (HAIR-FIT).
    parts = [o for o in collection.objects if o.type == "MESH"]
    ears = [(o, ear_component.free_rim()) for o in parts if o.name.startswith("%s.Ear." % prefix)]
    brows = [o for o in parts if o.name.startswith("%s.Brow." % prefix)]
    frame = wolf_hair.head_frame_of(head, body, ears, brows)
    obj = wolf_hair.build_style(frame, style, variant)
    obj.name = "%s.%s" % (prefix, obj.name)
    collection.objects.link(obj)
    return obj


def _inside(obj, tree, tolerance):
    """Vertices of `obj` behind the surface in `tree` (nearest point, its normal):
    count and the deepest, metres."""
    count, deepest = 0, 0.0
    for v in obj.data.vertices:
        p = obj.matrix_world @ v.co
        location, normal, _i, _d = tree.find_nearest(p)
        if location is None:
            continue
        depth = -(p - location).dot(normal)
        if depth > tolerance:
            count += 1
            deepest = max(deepest, depth)
    return {"vertices": count, "deepest_mm": round(deepest * 1000, 1)}


def _tree(obj):
    points = [obj.matrix_world @ v.co for v in obj.data.vertices]
    return BVHTree.FromPolygons(points, [list(p.vertices) for p in obj.data.polygons])


def measure(head, body, hair, chart, marks):
    head_tree, body_tree = _tree(head), _tree(body)
    sample = face_surface.sample(head, chart)
    surface = face_mapping.FaceSurface(sample)
    landmarks = face_mapping.derive_landmarks(surface, marks)
    attachments = {}
    for kind, (landmark, region) in face_surface.WOLF_ATTACHMENTS.items():
        for side in ("L", "R"):
            attachments["%s.%s" % (kind, side)] = {"landmark": "%s.%s" % (landmark, side), "region": region,
                                                   "normal_offset_m": marks[kind].get("proud_m", 0.0)}
    problems, _frames = face_mapping.attachment_problems(surface, landmarks, attachments)
    problems += face_mapping.landmark_problems(landmarks)
    zs = [(head.matrix_world @ v.co).z for v in head.data.vertices]
    body_zs = [(body.matrix_world @ v.co).z for v in body.data.vertices]
    ## Head/body integration: where the body's surface crosses the head's, by the class of
    ## the head triangle crossed (`v2.head_face_classes`). The neck enters under the jaw,
    ## covers the jaw's lower edge row and enters the lower occiput at the nape: the seam.
    ## A crossing through the jaw's sides above that row or the face is the neck or the
    ## trapezius showing through: a defect, reported with how far the body stands outside.
    low = min(zs)
    kinds = v2.head_face_classes(head)
    classes = {kind: 0 for kind in v2.SEAM_CLASSES + v2.DEFECT_CLASSES}
    defect_z, outside = [], {}
    head_world = head.matrix_world
    for head_index, body_index in head_tree.overlap(body_tree):
        kind = kinds[head_index]
        classes[kind] += 1
        polygon = head.data.polygons[head_index]
        centre = head_world @ polygon.center
        normal = (head_world.to_3x3() @ polygon.normal).normalized()
        depth = max((body.matrix_world @ body.data.vertices[i].co - centre).dot(normal)
                    for i in body.data.polygons[body_index].vertices)
        outside[kind] = max(outside.get(kind, 0.0), depth)
        if kind in v2.DEFECT_CLASSES or (kind == "jaw_edge" and depth > v2.JAW_EDGE_COVER_M):
            defect_z.append(centre.z - low)
    poking = dict(classes, defect_pairs=len(defect_z),
                  defect_outside_mm=round(max([outside.get(k, 0.0) for k in v2.DEFECT_CLASSES]) * 1000, 1),
                  jaw_edge_outside_mm=round(outside.get("jaw_edge", 0.0) * 1000, 1),
                  defect_height_above_chin_mm=[round(min(defect_z) * 1000, 1), round(max(defect_z) * 1000, 1)] if defect_z else None)
    report = {"head_height_m": round(max(zs) - low, 4), "figure_height_m": round(max(zs) - min(body_zs), 4),
              "heads_tall": round((max(zs) - min(body_zs)) / (max(zs) - low), 2),
              "landmarks_uv": {k: [round(c, 4) for c in uv] for k, uv in sorted(landmarks.items())},
              "landmark_problems": problems, "neck_through_head_vertices": poking}
    if hair is not None:
        report["hair_inside_head"] = _inside(hair, head_tree, HAIR_INSIDE_TOLERANCE_M)
        report["hair_inside_body"] = _inside(hair, body_tree, HAIR_INSIDE_TOLERANCE_M)
    return report


## Rig fitting (`rig_fit`): a joint's Gaussian neighbourhood on the base sculpt (metres at
## the reference stature), weighted by the skin weights of the bone and its parent.
RIG_FIT_SIGMA_M = 0.035


def smoothed_weights(weights, edges, count, iterations):
    """The skin weights the body deforms with: v1's transferred weights (nearest point of
    v1's ~40 mm facets, so neighbouring dense-sculpt vertices can jump between unrelated
    weight sets and tear apart in a bend) averaged over the sculpt's edges `iterations`
    times, then at most MAX_INFLUENCES per vertex, below MIN_INFLUENCE pruned, normalized.
    Only the deformation reads them; every shape field keeps the transferred weights."""
    import numpy as np
    names = sorted(weights)
    table = np.stack([weights[n] for n in names], axis=1)
    degree = np.maximum(np.bincount(edges.ravel(), minlength=count).astype(float), 1.0)[:, None]
    for _ in range(iterations):
        total = np.zeros_like(table)
        np.add.at(total, edges[:, 0], table[edges[:, 1]])
        np.add.at(total, edges[:, 1], table[edges[:, 0]])
        table = 0.5 * table + 0.5 * total / degree
    keep = np.argsort(table, axis=1)[:, -v2.MAX_INFLUENCES:]
    mask = np.zeros(table.shape, dtype=bool)
    np.put_along_axis(mask, keep, True, axis=1)
    table = np.where(mask & (table >= v2.MIN_INFLUENCE), table, 0.0)
    table = table / np.maximum(table.sum(axis=1, keepdims=True), 1e-12)
    return {n: table[:, j] for j, n in enumerate(names)}


def fit_rig(body, weights, collection, name, smooth_iterations=0):
    """The character's own armature (CHARACTER-RIG-FIT): a copy of the shared rig whose
    joints follow the character's shaped mesh. Each bone end moves by the mean displacement,
    from the base sculpt to this body, of the vertices around it (a Gaussian of their rest
    distance, weighted by the skin weights of the bone and its parent), the way SMPL's joint
    regressor derives joints from the shaped surface: one resolved body drives mesh and
    joints alike. Its rest is the authoring A-pose the mesh is built in (the shared rig's
    pose applied), so the body's armature modifier is the identity at rest. The body gets
    the skin weights as vertex groups and an armature modifier on its armature."""
    import numpy as np
    shared = next(o for o in bpy.data.objects if o.type == "ARMATURE" and o.name == "Armature")
    rig = shared.copy()
    rig.data = shared.data.copy()
    rig.name = rig.data.name = "%s.Armature" % name
    collection.objects.link(rig)
    view = bpy.context.view_layer
    for obj in view.objects:
        obj.select_set(False)
    view.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    base = _coords(bpy.data.objects[v2.SCULPT])
    moved = _coords(body) - base
    to_rig = np.array(rig.matrix_world.inverted())
    world = np.array(rig.matrix_world)
    ends = {}
    for bone in rig.data.bones:
        parent = bone.parent.name if bone.parent else None
        skin = weights.get(bone.name, 0.0) + (weights.get(parent, 0.0) if parent else 0.0)
        for end, local in (("head", bone.head_local), ("tail", bone.tail_local)):
            p = (world @ np.array([*local, 1.0]))[:3]
            w = np.exp(-0.5 * (np.linalg.norm(base - p, axis=1) / RIG_FIT_SIGMA_M) ** 2) * (skin if np.ndim(skin) else 1.0)
            delta = (w[:, None] * moved).sum(axis=0) / w.sum() if w.sum() > 1e-9 else np.zeros(3)
            ends[(bone.name, end)] = (to_rig @ np.array([*(p + delta), 1.0]))[:3]
    bpy.ops.object.mode_set(mode="EDIT")
    for edit in rig.data.edit_bones:
        edit.head = tuple(ends[(edit.name, "head")])
        edit.tail = tuple(ends[(edit.name, "tail")])
    bpy.ops.object.mode_set(mode="OBJECT")
    if smooth_iterations:
        edges = np.array([tuple(e.vertices) for e in body.data.edges])
        weights = smoothed_weights(weights, edges, len(body.data.vertices), smooth_iterations)
    for group, w in weights.items():
        vg = body.vertex_groups.new(name=group)
        for i in np.nonzero(w > 1e-4)[0]:
            vg.add([int(i)], float(w[i]), "REPLACE")
    modifier = body.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    return rig


def mask_layer(obj, hidden, margin, coverers, reach_m):
    """Remove from `obj` (a character's own copy, never a source) the faces its covering
    layers hide (`garments.masked_faces`, `margin` rings inside the covered area), and count
    the open edges no covering layer's surface reaches (`character_assembly.exposed_holes`)."""
    if not hidden:
        return {"removed": 0, "exposed": 0}
    faces = [tuple(p.vertices) for p in obj.data.polygons]
    removed = garments.masked_faces(faces, hidden, margin)
    holes = garments.open_boundary_after_mask(faces, removed)
    midpoints = [obj.matrix_world @ ((obj.data.vertices[a].co + obj.data.vertices[b].co) * 0.5) for a, b in holes]
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in removed], context="FACES_ONLY")
    bm.to_mesh(obj.data)
    bm.free()
    return {"removed": len(removed), "exposed": character_assembly.exposed_holes(midpoints, coverers, reach_m)}


## A masked head edge must lie within this distance of a covering layer's surface.
COVER_REACH_M = 0.004


def apply_layers(layers, head, chart, collection, prefix, identity):
    """The appearance plan's identity layers beyond the face, in its order: facial hair fitted
    to the resolved head, then the plan's hidden head regions removed from this character's
    head (its own copy) and checked for exposed holes. Returns the report."""
    report = {"plan": layers["plan"]["fingerprint"]}
    made = []
    for definition in layers["facial_hair"]:
        obj, fit = facial_hair.build(head, chart, definition, _identity_materials(identity)[1], "%s.%s" % (prefix, definition["source"]["object"]))
        collection.objects.link(obj)
        made.append(obj)
        report[definition["id"]] = fit
    regions = layers["regions"]
    hidden = appearance.hidden_vertices(layers["plan"], regions, v2.STUDY)
    margin = layers["plan"]["visibility"]["margin_rings"].get(v2.STUDY, 1)
    report["head_mask"] = mask_layer(head, hidden, margin, made, COVER_REACH_M)
    return report


def build_character(resolved, deltas, weights, name, hair_style, x, seat=False, identity=None, layers=None):
    """One character: the resolved body and head, the rig fit, the face (the resolved
    marks) and the hairstyle if any, measured; `identity` dresses it (a character's
    manifest), else the foundation's default identity; `layers` (a character's appearance
    plan and its definitions) adds the plan's facial hair and head coverage last."""
    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    body = build_body(resolved, deltas, weights, "%s.Body" % name, identity)
    head, chart = build_head(resolved, "%s.Head" % name, identity)
    collection.objects.link(body)
    collection.objects.link(head)
    if resolved.get("rig_fit"):
        fit_rig(body, weights, collection, name, resolved.get("rig_weight_smooth_iterations") or 0)
    neck = v2.seat_neck(body, head) if seat or resolved.get("seat_neck") else None
    face = fit_face(head, chart, resolved, collection, name, identity)
    ears = (ear_component.build_ears(head, chart, collection, name, head.data.materials[0],
                                     resolved.get("ear_flare_deg", ear_component.ear.FLARE_DEG), resolved.get("ear_scale", 1.0))
            if resolved.get("ears") else [])
    hair = fit_hair(head, body, hair_style, collection, name) if hair_style else None
    if hair is not None:
        ## Dressed in the identity's hair material (the palette a review judges).
        hair.data.materials.clear()
        hair.data.materials.append(_identity_materials(identity)[1])
    marks = resolved.get("marks") or _foundation()["default_identity"]["face"]["marks"]
    if resolved.get("face_response"):
        marks = variation.responded_marks(marks, variation.face_response(resolved))
    report = measure(head, body, hair, chart, marks)
    report["face_marks"] = face
    report["neck_seat"] = neck
    if ears:
        report["ears"] = ear_component.ear_report(ears, head, hair)
    if layers:
        report["layers"] = apply_layers(layers, head, chart, collection, name, identity)
    ## The lock (CHARACTER-FOUNDATION-001): every built mesh's fingerprint, before the root
    ## places the character (the meshes' own coordinates).
    report["fingerprints"] = {obj.name: v2.fingerprint(obj)["sha256"] for obj in sorted(collection.objects, key=lambda o: o.name)
                              if obj.type == "MESH"}
    root = bpy.data.objects.new("%s.Root" % name, None)
    collection.objects.link(root)
    h = resolved["stature_scale"]
    root.matrix_world = Matrix.Translation((x, 0.0, 0.0)) @ Matrix.Scale(h, 4)
    for obj in collection.objects:
        if obj is not root:
            obj.parent = root
    report["figure_height_scaled_m"] = round(report["figure_height_m"] * h, 4)
    return report


def _definitions(which, document):
    """(name, definition, hairstyle) rows of a set. The default-body sets (configurations,
    matrix, sweep) are the foundation's bodies: no character's hair, no attire."""
    configurations = document["configurations"]
    order = ("extreme_lean", "lean", "lean_half", "default", "heavy_half", "heavy", "extreme_heavy")
    if which == "configurations":
        return [(n, variation.configuration_definition(configurations, n), None) for n in order]
    if which == "matrix":
        return [(n, {"body": {"height_m": h, "frame_build": f, "muscularity": m}}, None)
                for n, h, f, m in variation.BOUNDARY_MATRIX]
    if which == "sweep":
        return [(n, {"body": {"height_m": h, "frame_build": f, "muscularity": m}}, None) for n, h, f, m in variation.sweep()]
    if which == "identity":
        ## Same-face check: five head identities on the default body, then one identity on
        ## three physiques (the identity must hold, the proportions must follow).
        rows = [("id_%s" % a, {"body": dict(variation.configuration_definition(configurations, "default")["body"]),
                               "head": {"archetype": a}}, None) for a in ("reference", "angular", "broad", "elongated", "compact")]
        for n in ("extreme_lean", "default", "extreme_heavy"):
            rows.append(("angular_%s" % n, dict(variation.configuration_definition(configurations, n), head={"archetype": "angular"}), None))
        return rows
    ## A hairstyle mapped to every variant (HAIR-FIT): the foundation's whole sweep (the
    ## configurations its library validations are recorded per), and every head archetype.
    if which in ("hair_sweep_ranger", "hair_sweep_training"):
        style = which.rsplit("_", 1)[1]
        return [(n, {"body": {"height_m": h, "frame_build": f, "muscularity": m}}, style) for n, h, f, m in variation.sweep()]
    if which == "hair_identity":
        default = variation.configuration_definition(configurations, "default")["body"]
        return [("%s_%s" % (style, a), {"body": dict(default), "head": {"archetype": a}}, style)
                for a in ("reference", "angular", "broad", "elongated", "compact") for style in ("ranger", "training")]
    if which == "hair":
        rows = []
        for n in ("extreme_lean", "default", "extreme_heavy"):
            for style in ("ranger", "training"):
                rows.append(("%s_%s" % (style, n), variation.configuration_definition(configurations, n), style))
        for n, h, f, m in variation.BOUNDARY_MATRIX:
            if n in ("short_powerful", "tall_lean"):
                for style in ("ranger", "training"):
                    rows.append(("%s_%s" % (style, n), {"body": {"height_m": h, "frame_build": f, "muscularity": m}}, style))
        return rows
    raise SystemExit("unknown set %s" % which)


def wolf_rows(document):
    """Wolf on the foundation: one row per outfit that wears a hairstyle, his body from his
    `foundation` block, his face (`foundation.character_marks`) and his identity palette.
    (name, definition, hairstyle, marks, manifest)."""
    wolf = _wolf()
    problems = foundation.character_problems(document, wolf)
    if problems:
        raise SystemExit("RIPOSTE_WOLF: " + "; ".join(problems))
    marks = foundation.character_marks(document, wolf)
    styles = {entry[0]: style for style, entry in wolf_hair.STYLES.items()}
    blender = os.path.dirname(v2.CHARACTERS)
    with open(foundation.path_of(document, "record", blender), encoding="utf-8") as handle:
        record = json.load(handle)
    with open(foundation.path_of(document, "regions", blender), encoding="utf-8") as handle:
        regions = json.load(handle)
    target = foundation.garment_target(document, record, wolf)
    ids = set(wolf["foundation"].get("facial_hair", [])) | {g for e in wolf["outfits"].values() for g in e["garments"]}
    ## The manifest's garment library (a review copy may name candidate definitions).
    library = wolf.get("garment_library", "garments")
    library = library if os.path.isabs(library) else os.path.join(blender, library)
    definitions = {}
    for gid in sorted(ids):
        with open(os.path.join(library, "%s.garment.json" % gid), encoding="utf-8") as handle:
            definitions[gid] = json.load(handle)
    rows = []
    for outfit, entry in sorted(wolf["outfits"].items()):
        ## The style and the builder variant its definition pins (garments.hair_variant).
        hair = next(((styles[definitions[g]["source"]["object"]], garments.hair_variant(definitions[g]))
                     for g in entry["garments"] if definitions[g].get("type") == "hair"), None)
        if not hair:
            continue
        plan = appearance.resolve(wolf, outfit, definitions, regions, target)
        layers = {"plan": plan, "regions": regions,
                  "facial_hair": [definitions[c["id"]] for c in plan["components"] if c["type"] == "facial_hair"]}
        rows.append(("wolf_%s" % outfit, {"body": dict(wolf["foundation"]["body"])}, hair, marks, wolf, layers))
    return rows


def lock_problems(lock, reports):
    """Why built characters differ from the foundation's lock: by character and mesh."""
    out = []
    for name, locked in sorted(lock["characters"].items()):
        built = reports.get(name)
        if built is None:
            out.append("%s was not built" % name)
            continue
        if built["resolved_fingerprint"] != locked["resolved_fingerprint"]:
            out.append("%s: resolved configuration %s != locked %s" % (name, built["resolved_fingerprint"], locked["resolved_fingerprint"]))
        for mesh, sha in sorted(locked["fingerprints"].items()):
            if built["fingerprints"].get(mesh) != sha:
                out.append("%s: %s changed" % (name, mesh))
        extra = sorted(set(built["fingerprints"]) - set(locked["fingerprints"]))
        if extra:
            out.append("%s: meshes outside the lock %s" % (name, extra))
    return out


BOARD_VIEWS = {"front": 0.0, "three_quarter": 35.0, "side": 90.0, "rear": 180.0}
## (spacing m, look-at z, height m, pixels per metre): whole figures or heads and necks.
BOARD_FRAMES = {"body": (SPACING_M, 1.0, 2.35, 260), "head": (0.78, 1.66, 0.56, 700)}


def render_board(blend, out, views, frame="body", gameplay=(), only=""):
    """Render a lineup blend as boards: every character turned on its own root to the view
    (so side and rear read in one row), labelled; `gameplay` names characters rendered
    alone through the shipped match camera (render_views' constants). Head boards lift
    every character so the heads share one line whatever the stature; `only` keeps the
    characters whose name starts with it."""
    import render_views
    bpy.ops.wm.open_mainfile(filepath=blend)
    scene = bpy.context.scene
    roots = sorted((o for o in bpy.data.objects if o.name.endswith(".Root")), key=lambda o: o.matrix_world.translation.x)
    for root in [r for r in roots if not r.name.startswith(only)]:
        for child in root.children_recursive:
            child.hide_render = True
    roots = [r for r in roots if r.name.startswith(only)]
    spacing, look_z, height_m, ppm = BOARD_FRAMES[frame]
    for i, root in enumerate(roots):
        root.location.x = i * spacing
        if frame == "head":
            head = bpy.data.objects["%s.Head" % root.name[:-5]]
            bpy.context.view_layer.update()
            zs = [(head.matrix_world @ v.co).z for v in head.data.vertices]
            root.location.z += look_z + 0.03 - 0.5 * (min(zs) + max(zs))
        label = bpy.data.curves.new("%s.Label" % root.name[:-5], "FONT")
        label.body = root.name[:-5]
        label.size = 0.06 if frame == "head" else 0.11
        label.align_x = "CENTER"
        text = bpy.data.objects.new(label.name, label)
        text.location = (i * spacing, -0.6, look_z - height_m * 0.46)
        text.rotation_euler = (math.radians(90.0), 0.0, 0.0)
        text.color = (0.1, 0.1, 0.1, 1.0)
        text.data.materials.append(_material("label", (0.1, 0.1, 0.12, 1.0)))
        scene.collection.objects.link(text)
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    width_m = spacing * len(roots)
    camera_data = bpy.data.cameras.new("BoardCamera")
    camera = bpy.data.objects.new("BoardCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    written = []
    for view in views:
        for root in roots:
            root.rotation_euler = (0.0, 0.0, math.radians(BOARD_VIEWS[view]))
        camera_data.type = "ORTHO"
        camera_data.ortho_scale = max(width_m, height_m)
        scene.render.resolution_x = int(width_m * ppm)
        scene.render.resolution_y = int(height_m * ppm)
        camera.location = ((len(roots) - 1) * spacing * 0.5, -render_views.CAMERA_DISTANCE_M, look_z)
        camera.rotation_euler = (math.radians(90.0), 0.0, 0.0)
        scene.render.filepath = "%s_%s.png" % (out, view)
        bpy.ops.render.render(write_still=True)
        written.append(scene.render.filepath)
    for root in roots:
        root.rotation_euler = (0.0, 0.0, 0.0)
    for name in gameplay:
        root = bpy.data.objects["%s.Root" % name]
        keep = root.location.x
        for other in roots:
            other.hide_render = True
            for child in other.children_recursive:
                child.hide_render = child.name.split(".", 1)[-1].startswith("DeadEye") or other is not root
        root.location.x = 0.0
        pitch = math.radians(render_views.GAMEPLAY_PITCH_DEG)
        camera_data.type = "PERSP"
        camera_data.angle = math.radians(render_views.GAMEPLAY_FOV_DEG)
        camera.location = render_views.GAMEPLAY_LOOK_AT + Vector((0.0, -math.cos(pitch), math.sin(pitch))) * render_views.GAMEPLAY_DISTANCE_M
        camera.rotation_euler = (math.radians(90.0) - pitch, 0.0, 0.0)
        scene.render.resolution_x, scene.render.resolution_y = 1280, 720
        scene.render.filepath = "%s_gameplay_%s.png" % (out, name)
        bpy.ops.render.render(write_still=True)
        written.append(scene.render.filepath)
        root.location.x = keep
    return written


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    if "--render" in args:
        sys.path.insert(0, os.path.join(ROOT, "tools", "blender", "inspect"))
        frame = args[args.index("--frame") + 1] if "--frame" in args else "body"
        views = args[args.index("--views") + 1].split(",") if "--views" in args else list(BOARD_VIEWS)
        gameplay = args[args.index("--gameplay") + 1].split(",") if "--gameplay" in args else ()
        only = args[args.index("--only") + 1] if "--only" in args else ""
        print("RIPOSTE_BOARD", json.dumps(render_board(os.path.abspath(args[args.index("--render") + 1]),
                                                       os.path.abspath(args[args.index("--out") + 1]), views, frame, gameplay, only)))
        return
    which = args[args.index("--set") + 1]
    out_dir = os.path.abspath(args[args.index("--out") + 1])
    document = _document()
    base = _foundation()
    blender = os.path.dirname(v2.CHARACTERS)
    ## `--lock` writes the candidate lock beside the build (`<out>/lock.json`): it becomes a
    ## lock only by promotion (a variants or foundation version), never in place.
    lock_path = os.path.join(out_dir, "lock.json")
    if ("--lock" in args or "--verify-lock" in args) and which != "sweep":
        raise SystemExit("RIPOSTE_LOCK: the foundation's lock is the sweep (the default bodies)")
    variants = _variants()
    ## The foundation's base source, or a review build of it (RIPOSTE_BASE_REVIEW).
    bpy.ops.wm.open_mainfile(filepath=v2.REVIEW_BASE or foundation.path_of(base, "source", blender))
    v2.apose()
    deltas = key_deltas()
    weights = v2._transfer_weights([tuple(c) for c in _coords(bpy.data.objects[v2.SCULPT])])
    if which == "wolf":
        rows = wolf_rows(base)
    else:
        rows = [(n, d, h, None, None, None) for n, d, h in _definitions(which, document)]
        ## `--hair-variants ranger=G,training=F`: the hair set fits named builder variants
        ## (candidates) instead of the approved defaults.
        if "--hair-variants" in args:
            pins = dict(p.split("=") for p in args[args.index("--hair-variants") + 1].split(","))
            rows = [(n, d, (h, pins[h]) if h in pins else h, a, b, c) for n, d, h, a, b, c in rows]
    reports = {}
    for i, (name, definition, hair_style, marks, character, layers) in enumerate(rows):
        resolved = foundation.apply(variation.resolve(definition, document), base, marks, variants)
        report = build_character(resolved, deltas, weights, name, hair_style, i * SPACING_M, "--seat-neck" in args,
                                 character, layers)
        if layers:
            report["appearance_plan"] = layers["plan"]
        report["x_m"] = i * SPACING_M
        report["body_inputs"] = resolved["body"]
        report["mass_kg"] = round(resolved["physique"]["mass_kg"], 2)
        report["parameters"] = {k: round(v, 3) for k, v in resolved["parameters"].items() if v}
        report["head_parameters"] = {k: v for k, v in resolved["head"]["parameters"].items() if v}
        report["head_proportions"] = resolved["head"]["proportions"]
        report["resolved_fingerprint"] = variation.fingerprint(resolved)
        reports[name] = report
        print("RIPOSTE_VARIANT", name, json.dumps({k: report[k] for k in ("mass_kg", "heads_tall", "neck_through_head_vertices")}
                                                  | {k: report.get(k) for k in ("hair_inside_head", "hair_inside_body")}
                                                  | {"landmark_problems": len(report["landmark_problems"])}))
    for name in ("Body", v2.SCULPT, v2.STUDY):
        bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, "%s.blend" % which), copy=True)
    with open(os.path.join(out_dir, "%s.json" % which), "w", encoding="utf-8") as handle:
        json.dump(reports, handle, indent=1)
    print("RIPOSTE_VARIATION_SET", which, len(reports))
    if "--lock" in args:
        lock = {"schema": "riposte.character_foundation_lock", "version": 1, "foundation": base["id"],
                "approved": base.get("approved"), "set": which,
                "variants": (variants or {}).get("settings", {}),
                "notes": "Every default body's resolved configuration and mesh fingerprints (body, head, face features) "
                         "under these variant settings: a candidate lock, published by promoting it with its foundation "
                         "or variants version; --verify-lock rebuilds and compares with the current one.",
                "characters": {n: {"resolved_fingerprint": r["resolved_fingerprint"], "fingerprints": r["fingerprints"]}
                               for n, r in sorted(reports.items())}}
        with open(lock_path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(json.dumps(lock, indent=1) + "\n")
        print("RIPOSTE_LOCK_WRITTEN", lock_path, len(reports))
    if "--verify-lock" in args:
        problems = lock_problems(_lock_reference(base, blender), reports)
        print("RIPOSTE_LOCK_VERIFY", json.dumps({"ok": not problems, "problems": problems}))
        if problems:
            raise SystemExit(1)


if __name__ == "__main__":
    main()
