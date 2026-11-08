"""Garment definitions: the contract between a garment, the base it fits and the outfit it joins.

A garment definition (`riposte.garment`) is a first-class asset (CHARACTER-SOURCE-001):
it names the base it was fitted to (by id and topology fingerprint), the rig it was
skinned to (by contract digest), its category, the base fitting regions it occupies,
its semantic layer, how it deforms, the physique configurations it supports, the body
it hides, its clearance and material slots, and what it may be worn with.

Pure Python: no Blender. The Blender assembly (`tools/blender/character_assembly.py`)
and the audit (`tools/blender/inspect/garment_audit.py`) call these, so a definition is
judged the same way everywhere and the rules are unit-tested without Blender.
"""

import json

SCHEMA = "riposte.garment"
## fitted follows the body's edge flow; structured keeps its own silhouette with
## transitions at joints; loose hangs from where it attaches.
CATEGORIES = ("fitted", "structured", "loose")
## 0 is anatomy; 1 underlayer, 2 outer, 3 protection, 4 accessories.
LAYERS = (1, 2, 3, 4)
METHODS = ("skinned", "rigid")
## keys: the garment carries the base's physique keys (garment_physique.py) and
## bakes with the body; none: it covers only regions no physique parameter shapes.
PHYSIQUE = ("keys", "none")
MAX_INFLUENCES = 4
## Three asset types on one contract: clothing (layered, may hide body), hair (on the
## head, the intrinsic `hair` slot, must keep the face clear) and facial hair (an identity
## layer on the face's growth regions, the `hair` slot, its coverage declared like a
## garment's, the mouth preserved).
TYPES = ("garment", "hair", "facial_hair")
REQUIRED = (
    "id", "base_id", "base_topology_fingerprint", "skeleton_id", "rig_contract_sha256", "category",
    "regions", "source", "deformation", "supported_configurations", "materials",
)
REQUIRED_BY_TYPE = {"garment": ("layer", "coverage"), "hair": ("clearance", "design"),
                    "facial_hair": ("design", "coverage")}
## A region a fitting-region document places on another object than the body (the head's
## sub-regions on HeadV2) names it, and its parent region.
BODY_OBJECT = None
HAIR_SLOT = "hair"
HAIR_REGION = "head"
## A hairstyle is a designed arrangement of connected volumes: `design.regions` maps
## each design region (scalp, front_sweep, temples, ...) to the authored masses that
## build it (names or `fnmatch` patterns such as `Sweep.*`), and `design.primary` names
## the region the others grow from.
HAIR_SCALP = "scalp"
## Shipped hair is opaque sculpted geometry (ART-STYLE-001, mobile-first): no simulated
## strands, no alpha-layered cards, no runtime groom.
HAIR_METHODS = ("sculpted_mesh",)


## A hairstyle's geometry is a design variant of its builder (`wolf_hair.py`), named by the
## definition's `design.variant`. Definitions approved before the field (the v001 library
## versions) rebuild the variant they were approved with, by their built object, so a later
## default never changes them.
HAIR_V001_VARIANTS = {"HairRanger": "D", "HairTraining": "E"}


def hair_variant(hair):
    """The builder variant a hairstyle definition builds: its `design.variant`, else the
    variant its object was approved with before the field existed."""
    named = (hair.get("design") or {}).get("variant")
    if named:
        return named
    obj = hair["source"]["object"]
    if obj not in HAIR_V001_VARIANTS:
        raise ValueError("%s names no design.variant and %s has no approved variant" % (hair.get("id", "?"), obj))
    return HAIR_V001_VARIANTS[obj]


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def problems(garment, manifest, regions, worn_with=()):
    """Why `garment` may not be assembled onto the character `manifest`.

    `regions` is the base's fitting-region document; `worn_with` the other
    garment definitions in the same outfit. Empty means compatible.
    """
    kind = garment.get("type", "garment")
    if kind not in TYPES:
        return ["%s: type must be one of %s" % (garment.get("id", "?"), TYPES)]
    missing = [key for key in REQUIRED + REQUIRED_BY_TYPE[kind] if key not in garment]
    if missing:
        return ["%s %s lacks %s" % (kind, garment.get("id", "?"), ", ".join(missing))]
    gid = garment["id"]
    out = []
    if garment.get("schema") != SCHEMA:
        out.append("%s is not a %s" % (gid, SCHEMA))
    base = manifest["base"]
    ## A definition fitted to more than one base (a hairstyle the builder fits to each
    ## resolved head) lists the others in `also_fitted`; it must name this one.
    fitted = [(garment["base_id"], garment["base_topology_fingerprint"])]
    fitted += [(b.get("base_id"), b.get("base_topology_fingerprint")) for b in garment.get("also_fitted", [])]
    ids = [b for b, _f in fitted]
    if base["id"] not in ids:
        out.append("%s is fitted to %s, not %s" % (gid, ", ".join(ids), base["id"]))
    elif (base["id"], base["topology_fingerprint"]) not in fitted:
        out.append("%s was fitted to another base topology (%s..)" % (gid, dict(fitted)[base["id"]][:12]))
    if regions.get("topology_fingerprint") not in (None, base["topology_fingerprint"]):
        out.append("the fitting regions describe another base topology")
    skeleton = manifest["skeleton"]
    if garment["skeleton_id"] != skeleton["id"] or garment["rig_contract_sha256"] != skeleton["contract_sha256"]:
        out.append("%s was skinned to another rig contract" % gid)
    if garment["category"] not in CATEGORIES:
        out.append("%s: unknown category %s" % (gid, garment["category"]))
    if kind == "garment" and garment["layer"] not in LAYERS:
        out.append("%s: layer %s is not a garment layer" % (gid, garment["layer"]))
    if kind == "hair":
        out += _hair_problems(gid, garment)
    elif kind == "facial_hair":
        out += _facial_hair_problems(gid, garment, regions)
    else:
        out += _upper_boundary_problems(gid, garment)
    out += _clearance_problems(gid, garment, regions)
    unknown = [r for r in garment["regions"] if r not in regions["regions"]]
    if unknown:
        out.append("%s: unknown fitting regions %s" % (gid, unknown))
    if not garment["regions"]:
        out.append("%s occupies no fitting region" % gid)
    out += _deformation_problems(gid, garment["deformation"])
    if garment["deformation"].get("physique", "keys") == "none":
        shaped = sorted({p for r in garment["regions"] if r in regions["regions"] for p in regions["regions"][r].get("physique", [])})
        if shaped:
            out.append("%s does not follow physique but covers regions shaped by %s" % (gid, shaped))
    unsupported = [c for c in manifest["physique"]["supported_configurations"] if c not in garment["supported_configurations"]]
    if unsupported:
        out.append("%s does not support the character's configurations %s" % (gid, unsupported))
    coverage = garment.get("coverage", {})
    hidden = [r for r in coverage.get("hides", []) if not covers(garment, r, regions)]
    if hidden:
        out.append("%s hides regions it does not cover %s" % (gid, hidden))
    unknown = [r for r in coverage.get("hides", []) + coverage.get("preserves", []) if r not in regions["regions"]]
    if unknown:
        out.append("%s: coverage names unknown regions %s" % (gid, unknown))
    both = sorted(set(coverage.get("hides", [])) & set(coverage.get("preserves", [])))
    if both:
        out.append("%s both hides and preserves %s" % (gid, both))
    slots = set(manifest["materials"]["intrinsic"]) | set(manifest["materials"]["costume"])
    stray = [m for m in garment["materials"] if m not in slots]
    if stray:
        out.append("%s uses material slots outside the character's %s" % (gid, stray))
    out += _pairing_problems(garment, worn_with)
    return out


def _hair_problems(gid, hair):
    out = []
    if HAIR_REGION not in hair["regions"]:
        out.append("%s: hair sits on the %s region" % (gid, HAIR_REGION))
    if hair["materials"] != [HAIR_SLOT]:
        out.append("%s: hair wears only the intrinsic %s slot (has %s)" % (gid, HAIR_SLOT, hair["materials"]))
    if not hair["clearance"].get("face"):
        out.append("%s: hair must keep the face clear (clearance.face)" % gid)
    design = hair["design"]
    regions = design.get("regions") or {}
    if not design.get("style"):
        out.append("%s: a hairstyle names its style (design.style)" % gid)
    if design.get("method") not in HAIR_METHODS:
        out.append("%s: design.method must be one of %s (opaque sculpted hair; no strands or cards)" % (gid, HAIR_METHODS))
    if not design.get("variant") and hair["source"]["object"] not in HAIR_V001_VARIANTS:
        out.append("%s: a hairstyle names the builder variant it builds (design.variant)" % gid)
    if HAIR_SCALP not in regions:
        out.append("%s: a hairstyle is built on a %s region" % (gid, HAIR_SCALP))
    if design.get("primary") not in regions:
        out.append("%s: design.primary must be one of its regions" % gid)
    masses = [m for region in regions.values() for m in region]
    if any(not region for region in regions.values()):
        out.append("%s: every design region names its masses" % gid)
    repeated = sorted({m for m in masses if masses.count(m) > 1})
    if repeated:
        out.append("%s: masses %s belong to more than one design region" % (gid, repeated))
    ## Character Surface Integration: the region names are checked against the base's
    ## surface regions by surface_integration.relationship_problems (the audit and tests).
    if not (hair.get("surfaces") or {}).get("relationships"):
        out.append("%s: a hairstyle declares how it meets the body (surfaces.relationships)" % gid)
    return out


def covers(garment, region, regions):
    """Whether `garment` occupies `region`: it names it, or the region's parent."""
    entry = regions["regions"].get(region, {})
    return region in garment["regions"] or entry.get("parent") in garment["regions"]


## Facial hair (CHARACTER-GROOMING-001): modeled masses fitted to the face's growth regions
## (`design.growth`: head sub-regions, each with its thickness), the intrinsic `hair` slot,
## rigid on Head (no jaw yet) or skinned; it may never hide the mouth.
FACIAL_HAIR_PRESERVED = ("mouth",)


def _facial_hair_problems(gid, hair, regions):
    out = []
    if hair["materials"] != [HAIR_SLOT]:
        out.append("%s: facial hair wears only the intrinsic %s slot (has %s)" % (gid, HAIR_SLOT, hair["materials"]))
    if HAIR_REGION not in hair["regions"]:
        out.append("%s: facial hair sits on the %s region" % (gid, HAIR_REGION))
    growth = hair["design"].get("growth") or {}
    if not growth:
        out.append("%s: facial hair names its growth regions (design.growth)" % gid)
    stray = sorted(r for r in growth if regions["regions"].get(r, {}).get("parent") != HAIR_REGION)
    if stray:
        out.append("%s: growth regions %s are not head sub-regions" % (gid, stray))
    missing = sorted(set(FACIAL_HAIR_PRESERVED) - set(hair["coverage"].get("preserves", [])))
    if missing:
        out.append("%s: facial hair preserves %s" % (gid, missing))
    return out


## A garment reaching the neck declares how it meets the head and neck (HEAD-FIT-001):
## its upper boundary and whether it may touch the body there.
NECK_REGIONS = ("neck",)
CONTACT = ("allowed", "clearance")


def _upper_boundary_problems(gid, garment):
    boundary = garment.get("upper_boundary")
    if boundary is None:
        if any(r in NECK_REGIONS for r in garment.get("regions", [])):
            return ["%s reaches the neck: it declares its upper boundary (upper_boundary: collar height and opening, hood clearance, contact)" % gid]
        return []
    out = []
    for key in ("collar_height_m", "collar_opening_m"):
        if not isinstance(boundary.get(key), (int, float)) or boundary[key] < 0:
            out.append("%s: upper_boundary.%s is a length in metres" % (gid, key))
    if "hood_clearance_m" in boundary and (not isinstance(boundary["hood_clearance_m"], (int, float)) or boundary["hood_clearance_m"] < 0):
        out.append("%s: upper_boundary.hood_clearance_m is a length in metres" % gid)
    if boundary.get("contact") not in CONTACT:
        out.append("%s: upper_boundary.contact must be one of %s (skin-tight may touch; padded and rigid keep clearance)" % (gid, CONTACT))
    return out


def _clearance_problems(gid, garment, regions):
    """Per-asset clearance overrides (metres, by region or `default`) and declared
    intentional overlaps, each with a reason — never a silent tolerance."""
    out = []
    for region, band in garment.get("clearance_m", {}).items():
        if region != "default" and region not in regions["regions"]:
            out.append("%s: clearance for an unknown region %s" % (gid, region))
        elif not (len(band) == 2 and 0.0 <= band[0] < band[1]):
            out.append("%s: clearance %s must be [low, high] with 0 <= low < high" % (gid, region))
    for overlap in garment.get("overlaps", []):
        if not overlap.get("with") or not overlap.get("reason") or not overlap.get("max_m", 0) > 0:
            out.append("%s: an overlap names what it overlaps, a positive max_m and a reason" % gid)
    return out


def clearance_for(garment, regions, region):
    """The [low, high] clearance an asset must keep over `region`: its own override, else the category's."""
    own = garment.get("clearance_m", {})
    return own.get(region) or own.get("default") or regions["clearance_m"][garment["category"]]


def _deformation_problems(gid, deformation):
    out = []
    method = deformation.get("method")
    if method not in METHODS:
        out.append("%s: deformation must be one of %s" % (gid, METHODS))
    if method == "skinned" and deformation.get("max_influences", MAX_INFLUENCES) > MAX_INFLUENCES:
        out.append("%s: more than %d influences" % (gid, MAX_INFLUENCES))
    if method == "rigid" and not deformation.get("bone"):
        out.append("%s: a rigid garment names its one bone" % gid)
    if deformation.get("physique", "keys") not in PHYSIQUE:
        out.append("%s: physique must be one of %s" % (gid, PHYSIQUE))
    return out


def _pairing_problems(garment, worn_with):
    gid = garment["id"]
    others = {o["id"]: o for o in worn_with if o["id"] != gid}
    out = []
    for oid, other in others.items():
        if oid in garment.get("incompatible_with", ()) or gid in other.get("incompatible_with", ()):
            out.append("%s cannot be worn with %s" % (gid, oid))
    for required in garment.get("requires", ()):
        if required not in others:
            out.append("%s requires %s" % (gid, required))
    return out


def outfit_problems(garments, manifest, regions):
    """Every garment's problems against the others, plus duplicate ids."""
    ids = [g.get("id") for g in garments]
    out = ["outfit lists %s twice" % i for i in sorted({i for i in ids if ids.count(i) > 1})]
    for garment in garments:
        out += problems(garment, manifest, regions, garments)
    return out


def hidden_vertices(garments, regions, target=BODY_OBJECT):
    """Vertex indices of `target` (the body when None, else a region document's `object`,
    such as the head) the outfit hides: the union of every garment's `hides` regions on it."""
    hidden = set()
    for garment in garments:
        for region in garment.get("coverage", {}).get("hides", ()):
            entry = regions["regions"][region]
            if entry.get("object") == target:
                hidden.update(entry["vertices"])
    return hidden


def masked_faces(faces, hidden, margin_rings=1):
    """Faces of the base to remove in the export copy.

    A face goes only when every vertex is hidden and it lies at least
    `margin_rings` faces inside the hidden area, so the body under a garment's
    edge stays — a mask removes what can never be seen, it never replaces the
    garment's clearance. `faces` is the base's face list (vertex index tuples).
    """
    candidates = [i for i, face in enumerate(faces) if all(v in hidden for v in face)]
    kept = set(range(len(faces))) - set(candidates)
    border = {v for i in kept for v in faces[i]}
    removable = set(candidates)
    for _ in range(margin_rings):
        ring = {i for i in removable if any(v in border for v in faces[i])}
        removable -= ring
        border |= {v for i in ring for v in faces[i]}
    return sorted(removable)


def open_boundary_after_mask(faces, removed):
    """Edges of the remaining base that lose their second face to the mask:
    the hole a garment must cover. Returned as sorted vertex pairs."""
    removed = set(removed)
    count = {}
    owner = {}
    for i, face in enumerate(faces):
        for a, b in zip(face, face[1:] + face[:1]):
            edge = (min(a, b), max(a, b))
            count[edge] = count.get(edge, 0) + 1
            owner.setdefault(edge, []).append(i)
    holes = []
    for edge, users in owner.items():
        if count[edge] == 2 and sum(1 for i in users if i in removed) == 1:
            holes.append(edge)
    return sorted(holes)
