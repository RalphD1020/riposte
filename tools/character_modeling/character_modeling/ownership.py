"""Character ownership, revisions and change impact (CHARACTER-OWNERSHIP-001, CHARACTER-RELEASE-001).

One appearance composes three owners, each versioned on its own:

    foundation   shared topology, skeleton contract, anatomical generators, default anatomy and
                 the default identity: the library's `male_base_foundation` (asset_library)
    identity     who the character is: physique, head and face, facial hair, pigments
                 (skin, hair, eyes), art direction
    skin         how the character is dressed and styled: hairstyle geometry, attire, costume
                 colours, exposure (one outfit of the character manifest)

Changing the foundation affects every character built on it; changing an identity affects
every skin of that character; changing a skin affects that skin. Hair pigment is identity
(both hairstyles inherit it); hairstyle geometry is skin. Weapons belong to the equipment
system and are outside all three.

`classify` names the owner of a manifest field and `problems` refuses a manifest that puts a
field under the wrong owner: there is no generic override path, so a skin cannot reach into
the identity or the foundation. `snapshot` digests each owner's authored inputs; `impact`
compares two snapshots of a character family and lists every affected skin with the
validations it needs.

Two publication authorities, one per kind of thing (no second concept of "published"):
`asset_library` is the authority for reusable library assets (the foundation, a hairstyle, a
face, a skin tone) - it stores immutable byte copies other characters and the creator menus
reuse. The release record here (`<character>.releases.json`) is the authority for one
character's own identity and skin composition - it pins each revision by the content digest of
its authored inputs (and so, transitively, the worn garment/library-asset revisions) plus the
approval evidence, and never copies a library asset's bytes or re-runs its validations. A
character composition is not a reusable library asset, so it is not an `asset_library`
category; the two never version the same record. A published identity revision is an
ART_REFERENCE (an accepted appearance); the RUNTIME stage (the validated shipping asset) is a
separate, F8/F9/F10-gated promotion (`promote_runtime`), never a side effect of art approval.

Revision digests cover authored definitions only: a builder change with byte-identical output
is not an artistic revision. A build's `provenance` records definitions, builder and output
geometry together.

Pure Python: no Blender.

    python -m character_modeling.ownership status [--foundation <candidate document>]
    python -m character_modeling.ownership impact --manifest <candidate assembly>
    python -m character_modeling.ownership classify <field path>
    python -m character_modeling.ownership publish --character <id> --scope identity|skin [--skin <name>]
        --by <person> --date <YYYY-MM-DD> --evidence <iteration> [--validated ranger,training]
"""

from __future__ import annotations

import argparse
import copy
import glob
import hashlib
import json
import os
import sys
from pathlib import Path

from .physique import resolve_physique

ROOT = Path(__file__).resolve().parents[3]
BLENDER = ROOT / "art-src" / "blender"
CHARACTERS = BLENDER / "characters"
GARMENTS = BLENDER / "garments"

FOUNDATION, IDENTITY, SKIN = "foundation", "identity", "skin"
SCOPES = (FOUNDATION, IDENTITY, SKIN)
## Manifest fields outside the three owners: the weapon loadout, derived build policy (budget,
## validation list, exports: a new derived artifact, never a character revision), the file's
## own metadata, the v1 master the shipping blockout still reads, and staging keys a candidate
## copy may carry but a canonical manifest may not.
EQUIPMENT, DERIVED, META, LEGACY, STAGING = "equipment", "derived", "meta", "legacy", "staging"
## The foundation reference (which foundation version a character is pinned to) and its rig.
REF, RIG = "ref", "rig"
PHYSIQUE, HEAD, PIGMENT, DIRECTION = "physique", "head", "pigment", "direction"
IDENTITY_ASPECTS = (PHYSIQUE, HEAD, PIGMENT, DIRECTION)

## Owner of every top-level key of a `riposte.character_assembly`: (scope, aspect), or a dict
## of the owners of its parts.
TOP = {
    "schema": (META, None), "version": (META, None), "id": (META, None), "notes": (META, None),
    "base": (LEGACY, None),
    "skin_swatches": (IDENTITY, PIGMENT),
    "skeleton": (FOUNDATION, RIG),
    ## The v1 physique block; kept equal to `foundation.body` (`problems`).
    "physique": (IDENTITY, PHYSIQUE),
    "foundation": {"id": (FOUNDATION, REF), "definition": (FOUNDATION, REF), "notes": (META, None),
                   "body": (IDENTITY, PHYSIQUE), "face": (IDENTITY, HEAD), "face_refine": (IDENTITY, HEAD),
                   "facial_hair": (IDENTITY, HEAD)},
    "identity": {"source": (IDENTITY, HEAD), "collections": (IDENTITY, HEAD), "palette": (IDENTITY, PIGMENT),
                 "face": (IDENTITY, HEAD), "head": (IDENTITY, HEAD)},
    "art": {"profile": (IDENTITY, DIRECTION), "notes": (META, None), "anchors": (IDENTITY, DIRECTION),
            "style": (IDENTITY, DIRECTION), "outfits": (SKIN, None)},
    "materials": (IDENTITY, PIGMENT),
    "outfits": (SKIN, None),
    "weapons": (EQUIPMENT, None),
    "budget": (DERIVED, None), "validation": (DERIVED, None), "exports": (DERIVED, None),
    "garment_library": (STAGING, None),
}
OUTFIT_KEYS = ("collections", "body_mask", "garments", "complete", "exposure", "palette")
## A hairstyle's colour is the identity's hair pigment: it may name that slot.
HAIR_PIGMENT = "hair"
MASS_TOLERANCE_KG = 0.05

## What each kind of change must re-validate on every affected skin.
VALIDATIONS = {
    FOUNDATION: ("topology", "skeleton", "deformation", "physique_variation", "silhouette", "coverage", "export"),
    RIG: ("skeleton", "deformation", "animation", "weapon_handling", "export"),
    PHYSIQUE: ("fit", "motion", "coverage", "physics"),
    HEAD: ("face_identity", "eyes", "hair_fit", "scarf_fit", "animation"),
    PIGMENT: ("materials", "palette", "gameplay_contrast"),
    DIRECTION: ("art_review",),
    SKIN: ("fit", "layer_order", "exposure", "high_contrast_coverage", "pose"),
}

RELEASE_SCHEMA = "riposte.character_releases"
RELEASE_VERSION = 1
PROVENANCE_SCHEMA = "riposte.character_build_provenance"
CLEAN, EDITED, UNRELEASED = "clean", "edited", "unreleased"
APPROVAL_KEYS = ("date", "by", "evidence")
## A release stage (CHARACTER-RELEASE-001). `publish` only ever produces an ART_REFERENCE: an
## accepted appearance and identity, NOT a shipping asset. RUNTIME is the validated runtime
## asset (production topology + deformation + Godot import + performance); reaching it is
## `promote_runtime`, gated on the F8/F9/F10 evidence, never a side effect of publishing an
## art revision. The record's `runtime` pointer stays null until then, so an art approval can
## never be mistaken for a shipping release.
ART_REFERENCE, RUNTIME = "art_reference", "runtime"
RUNTIME_EVIDENCE = ("f8_topology", "f9_regression", "f10_godot")


def digest(value):
    """A short content digest of a JSON value (key order never matters)."""
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()[:16]


def file_sha256(path):
    """Content hash with line endings normalized, so a checkout's CRLF does not move it."""
    return hashlib.sha256(Path(path).read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def classify(path):
    """(scope, detail) of a manifest field path such as `foundation.body.muscularity`,
    `identity.palette.hair`, `outfits.ranger.palette.leather` or `art.outfits.training.hair`:
    the identity aspect, the skin (outfit) name, the foundation `ref`/`rig`, or None. Raises
    ValueError for a field no owner declares."""
    parts = path.split(".")
    owner = TOP.get(parts[0])
    if isinstance(owner, dict):
        if len(parts) < 2 or parts[1] not in owner:
            raise ValueError("%s: %s owns its parts %s, not %s" % (path, parts[0], sorted(owner), parts[1:2]))
        owner, rest = owner[parts[1]], parts[2:]
    else:
        rest = parts[1:]
    if owner is None:
        raise ValueError("%s: no owner declares %s" % (path, parts[0]))
    scope, detail = owner
    if scope == SKIN:
        if not rest:
            raise ValueError("%s: a skin field names its outfit" % path)
        return SKIN, rest[0]
    return scope, detail


def _owned(character):
    """(scope, detail, path, value) of every owned field, at the granularity of `TOP`."""
    for key, value in character.items():
        owner = TOP.get(key)
        if isinstance(owner, dict):
            for part, sub in value.items():
                if part in owner:
                    yield owner[part] + ("%s.%s" % (key, part), sub)
        elif owner is not None:
            yield owner + (key, value)


def problems(character, definitions=None, canonical=True):
    """Why `character` (a `riposte.character_assembly`) breaks the ownership contract: a field
    no owner declares, a skin colouring an identity material or a slot that is not a costume
    slot, facial hair worn as an outfit layer, a garment colouring identity materials, two
    hairstyles in one skin, a staging key in a canonical manifest, or a v1 physique block
    that disagrees with the identity's body. `definitions` ({id: garment definition}) adds
    the checks of the worn assets. Empty means the ownership holds."""
    definitions = definitions or {}
    cid = character.get("id", "?")
    out = []
    for key, value in sorted(character.items()):
        owner = TOP.get(key)
        if owner is None:
            out.append("%s: %s is not a field any owner declares" % (cid, key))
        elif isinstance(owner, dict):
            out += ["%s: %s.%s is not a field %s declares" % (cid, key, part, key) for part in sorted(set(value) - set(owner))]
        elif canonical and owner[0] == STAGING:
            out.append("%s: %s is a candidate's staging key, never a canonical manifest's" % (cid, key))
    materials = character.get("materials", {})
    intrinsic, costume = set(materials.get("intrinsic", [])), set(materials.get("costume", []))
    for name, entry in sorted(character.get("outfits", {}).items()):
        out += ["%s: outfit %s.%s is not a skin field" % (cid, name, k) for k in sorted(set(entry) - set(OUTFIT_KEYS))]
        for slot in sorted(entry.get("palette", {})):
            if slot in intrinsic:
                out.append("%s: skin %s colours the identity material %s" % (cid, name, slot))
            elif slot not in costume:
                out.append("%s: skin %s colours %s, which is not one of the character's costume slots" % (cid, name, slot))
        worn = [definitions[g] for g in entry.get("garments", []) if g in definitions]
        hair = [d["id"] for d in worn if d.get("type") == "hair"]
        if len(hair) > 1:
            out.append("%s: skin %s wears two hairstyles %s" % (cid, name, hair))
        for definition in worn:
            kind = definition.get("type", "garment")
            if kind == "facial_hair":
                out.append("%s: skin %s wears facial hair %s, which is identity (foundation.facial_hair)" % (cid, name, definition["id"]))
                continue
            allowed = costume | ({HAIR_PIGMENT} if kind == "hair" else set())
            foreign = sorted(set(definition.get("materials", [])) - allowed)
            if foreign:
                out.append("%s: %s in skin %s colours %s, outside its slots %s" % (cid, definition["id"], name, foreign, sorted(allowed)))
    for gid in character.get("foundation", {}).get("facial_hair", []):
        if gid in definitions and definitions[gid].get("type") != "facial_hair":
            out.append("%s: foundation.facial_hair names %s, which is not facial hair" % (cid, gid))
    out += _physique_problems(character)
    return out


def _physique_problems(character):
    body = character.get("foundation", {}).get("body")
    legacy = character.get("physique")
    if not body or not legacy:
        return []
    out = []
    cid = character.get("id", "?")
    if "height_m" in legacy and abs(float(legacy["height_m"]) - float(body["height_m"])) > 1e-9:
        out.append("%s: physique.height_m %s is not the identity body's %s" % (cid, legacy["height_m"], body["height_m"]))
    if "mass_kg" in legacy:
        mass = resolve_physique(body)["mass_kg"]
        if abs(mass - float(legacy["mass_kg"])) > MASS_TOLERANCE_KG:
            out.append("%s: physique.mass_kg %s is not the identity body's %.2f" % (cid, legacy["mass_kg"], mass))
    return out


def foundation_inputs(document_path):
    """What a character builds on, by content: the foundation document's id and digest and
    its record's (the body topology every garment is fitted to)."""
    document_path = Path(document_path)
    document = json.loads(document_path.read_text(encoding="utf-8"))
    record = BLENDER / document["record"]
    return {"id": document["id"], "definition": _relative(document_path), "sha256": file_sha256(document_path)[:16],
            "record_sha256": file_sha256(record)[:16] if record.exists() else None}


def _relative(path):
    path = Path(path).resolve()
    for base in (BLENDER, ROOT):
        try:
            return path.relative_to(base.resolve()).as_posix()
        except ValueError:
            continue
    return path.name


def snapshot(character, definitions, foundation, swatches=None):
    """Each owner's authored inputs of `character`, digested: {character, foundation (its
    `foundation_inputs`), rig (the skeleton contract digest), identity {aspect: digest},
    skins {outfit: digest}}. The skin digest covers the outfit, its art profile and the full
    definitions it wears; the identity's covers its fields, its facial hair definitions and,
    with the shared `swatches`, the skin colour its swatch names."""
    aspects = {aspect: {} for aspect in IDENTITY_ASPECTS}
    for scope, detail, path, value in _owned(character):
        if scope == IDENTITY:
            aspects[detail][path] = value
    for gid in character.get("foundation", {}).get("facial_hair", []):
        aspects[HEAD]["definition:%s" % gid] = definitions.get(gid)
    skin = character.get("identity", {}).get("palette", {}).get("skin", {})
    if swatches is not None and skin.get("swatch") in swatches:
        aspects[PIGMENT]["swatch:%s" % skin["swatch"]] = swatches[skin["swatch"]]
    profiles = character.get("art", {}).get("outfits", {})
    skins = {name: digest({"outfit": entry, "art": profiles.get(name),
                           "definitions": {g: definitions.get(g) for g in entry.get("garments", [])}})
             for name, entry in character.get("outfits", {}).items()}
    return {"character": character["id"], "foundation": dict(foundation),
            "rig": character.get("skeleton", {}).get("contract_sha256"),
            "identity": {aspect: digest(fields) for aspect, fields in aspects.items()}, "skins": skins}


def identity_digest(snap):
    return digest(snap["identity"])


def _foundation_key(inputs):
    return (inputs.get("id"), inputs.get("sha256"), inputs.get("record_sha256"))


def impact(before, after):
    """What moving a character family from `before` to `after` ({character id: snapshot})
    invalidates: {affected: [{character, skin, causes, validations}], unaffected: ["id/skin"],
    added, removed}. A foundation or rig change reaches every skin of every character on it, an
    identity aspect every skin of that character, a skin change that skin alone."""
    out = {"affected": [], "unaffected": [], "added": sorted(set(after) - set(before)),
           "removed": sorted(set(before) - set(after))}
    for cid in sorted(set(before) & set(after)):
        old, new = before[cid], after[cid]
        shared = []
        if _foundation_key(old["foundation"]) != _foundation_key(new["foundation"]):
            shared.append(FOUNDATION)
        if old["rig"] != new["rig"]:
            shared.append(RIG)
        shared += [a for a in IDENTITY_ASPECTS if old["identity"].get(a) != new["identity"].get(a)]
        for name in sorted(set(old["skins"]) | set(new["skins"])):
            causes = shared + ([SKIN] if old["skins"].get(name) != new["skins"].get(name) else [])
            if not causes:
                out["unaffected"].append("%s/%s" % (cid, name))
                continue
            validations = sorted({v for cause in causes for v in VALIDATIONS[cause]})
            out["affected"].append({"character": cid, "skin": name, "causes": causes, "validations": validations})
    return out


def scope_of(report):
    """The broadest owner an impact report touches (foundation > identity > skin), or None."""
    causes = {c for row in report["affected"] for c in row["causes"]}
    if causes & {FOUNDATION, RIG}:
        return FOUNDATION
    if causes & set(IDENTITY_ASPECTS):
        return IDENTITY
    return SKIN if causes else None


def migration_problems(report, validations):
    """Why a release (a foundation revision above all) cannot be published: every affected
    skin of `report` must have a passing validation in `validations` ({"character/skin":
    {"passed": bool, "evidence": str}}). One failure blocks the whole release: a shared
    revision is never partially promoted."""
    out = []
    for row in report["affected"]:
        key = "%s/%s" % (row["character"], row["skin"])
        result = validations.get(key)
        if result is None:
            out.append("%s was not validated (%s)" % (key, ", ".join(row["validations"])))
        elif not result.get("passed"):
            out.append("%s failed validation: %s" % (key, result.get("evidence", "no evidence")))
        elif not result.get("evidence"):
            out.append("%s passed without evidence" % key)
    return out


## Releases: the identity and skin revisions of one character, published like library assets.

def new_releases(snap, approval):
    """The first release record of a character: its identity and every skin at v001, all
    approved together (one coherent release). Stage ART_REFERENCE, no runtime asset yet."""
    record = {"schema": RELEASE_SCHEMA, "version": RELEASE_VERSION, "character": snap["character"],
              "identity": {"current": None, "versions": {}}, "skins": {}, "runtime": None}
    return publish(record, snap, IDENTITY, approval, validated=sorted(snap["skins"]))


def _current(entry):
    return entry["versions"][entry["current"]] if entry and entry.get("current") else None


def _next(entry):
    return "v%03d" % (len(entry["versions"]) + 1)


def status(snap, releases):
    """{identity, skins {name: state}, foundation, edited_aspects}: each owner's state against
    its current published revision (clean, edited, unreleased), and whether the character's
    foundation moved since its identity was published (a migration pending)."""
    identity = _current(releases.get("identity"))
    if identity is None:
        state, aspects, base = UNRELEASED, list(IDENTITY_ASPECTS), UNRELEASED
    else:
        aspects = [a for a in IDENTITY_ASPECTS if identity["aspects"].get(a) != snap["identity"][a]]
        state = EDITED if identity["digest"] != identity_digest(snap) else CLEAN
        base = CLEAN if _foundation_key(identity["foundation"]) == _foundation_key(snap["foundation"]) else EDITED
    skins = {}
    for name, value in sorted(snap["skins"].items()):
        current = _current(releases.get("skins", {}).get(name))
        skins[name] = UNRELEASED if current is None else (CLEAN if current["digest"] == value else EDITED)
    return {"identity": state, "skins": skins, "foundation": base, "edited_aspects": aspects}


def release_problems(snap, releases):
    """Why a canonical character does not match its published revisions: every owner must be
    clean (an edit becomes canonical by publication, never in place) and every published
    revision must name versions that exist."""
    cid = snap["character"]
    if releases.get("schema") != RELEASE_SCHEMA or releases.get("character") != cid:
        return ["%s: not its %s" % (cid, RELEASE_SCHEMA)]
    out = []
    identity = releases["identity"]
    for version, entry in sorted(identity["versions"].items()):
        for name, skin_version in sorted(entry["skins"].items()):
            if skin_version not in releases["skins"].get(name, {}).get("versions", {}):
                out.append("%s: identity %s names skin %s %s, which was never published" % (cid, version, name, skin_version))
    for name, entry in sorted(releases["skins"].items()):
        for version, row in sorted(entry["versions"].items()):
            if row["identity"] not in identity["versions"]:
                out.append("%s: skin %s %s names identity %s, which was never published" % (cid, name, version, row["identity"]))
    state = status(snap, releases)
    if state["identity"] != CLEAN:
        out.append("%s: identity is %s (%s) since %s; stage a candidate and publish a revision" % (
            cid, state["identity"], ", ".join(state["edited_aspects"]), identity.get("current")))
    if state["foundation"] == EDITED:
        out.append("%s: built on another foundation than identity %s was approved on; publish the migration" % (cid, identity["current"]))
    out += ["%s: skin %s is %s; stage a candidate and publish a revision" % (cid, n, s)
            for n, s in sorted(state["skins"].items()) if s != CLEAN]
    out += ["%s: skin %s was published but the character no longer has it" % (cid, n)
            for n in sorted(set(releases["skins"]) - set(snap["skins"]))]
    return out


def _approval_problems(approval):
    return ["the approval names its %s" % k for k in APPROVAL_KEYS if not (approval or {}).get(k)]


def publish(releases, snap, scope, approval, skin=None, validated=()):
    """`releases` with a new revision of `scope` published from `snap`: a copy; nothing
    published is ever changed. A skin revision is approved on the current identity, which
    must itself be clean. An identity revision (an identity edit, or a migration to another
    foundation) is one coherent release with every skin: each must be in `validated`, and an
    edited or unreleased skin is published with it. Raises ValueError with every problem."""
    out = copy.deepcopy(releases)
    problems_ = _approval_problems(approval)
    state = status(snap, out)
    if scope == SKIN:
        if skin not in snap["skins"]:
            problems_.append("%s has no skin %s" % (snap["character"], skin))
        elif state["skins"][skin] == CLEAN:
            problems_.append("skin %s is unchanged since %s" % (skin, out["skins"][skin]["current"]))
        if state["identity"] != CLEAN or state["foundation"] != CLEAN:
            problems_.append("the identity is not its published revision: publish the identity (with every skin) instead")
        if problems_:
            raise ValueError("; ".join(problems_))
        _publish_skin(out, snap, skin, out["identity"]["current"], approval)
        return out
    if scope != IDENTITY:
        raise ValueError("a character publishes identity or skin revisions; a foundation is a library asset")
    if state["identity"] == CLEAN and state["foundation"] == CLEAN and all(s == CLEAN for s in state["skins"].values()):
        problems_.append("identity is unchanged since %s" % out["identity"]["current"])
    missing = sorted(set(snap["skins"]) - set(validated))
    if missing:
        problems_.append("an identity revision is validated on every skin; missing %s" % missing)
    if problems_:
        raise ValueError("; ".join(problems_))
    version = _next(out["identity"])
    skins = {}
    for name in sorted(snap["skins"]):
        skins[name] = (out["skins"][name]["current"] if state["skins"][name] == CLEAN
                       else _publish_skin(out, snap, name, version, approval))
    out["identity"]["versions"][version] = {"digest": identity_digest(snap), "aspects": dict(snap["identity"]),
                                            "foundation": dict(snap["foundation"]), "rig": snap["rig"],
                                            "skins": skins, "approval": dict(approval), "stage": ART_REFERENCE}
    out["identity"]["current"] = version
    return out


def promote_runtime(releases, version, evidence):
    """Promote a published identity `version` to the RUNTIME stage: a copy with the record's
    `runtime` pointer set to it. Gated on the F8/F9/F10 evidence (`RUNTIME_EVIDENCE`, each a
    non-empty reference to the validated run); an art reference can never become the shipping
    asset without it. Raises ValueError with every problem."""
    out = copy.deepcopy(releases)
    problems_ = []
    if version not in out["identity"]["versions"]:
        problems_.append("identity %s was never published" % version)
    missing = [k for k in RUNTIME_EVIDENCE if not (evidence or {}).get(k)]
    if missing:
        problems_.append("a runtime promotion names its %s evidence" % ", ".join(missing))
    if problems_:
        raise ValueError("; ".join(problems_))
    out["identity"]["versions"][version]["stage"] = RUNTIME
    out["identity"]["versions"][version]["runtime_evidence"] = dict(evidence)
    out["runtime"] = version
    return out


def runtime_version(releases):
    """The character's validated shipping identity version, or None when only art references
    exist (F8/F9/F10 still pending)."""
    return (releases or {}).get("runtime")


def _publish_skin(out, snap, name, identity_version, approval):
    entry = out["skins"].setdefault(name, {"current": None, "versions": {}})
    version = _next(entry)
    entry["versions"][version] = {"digest": snap["skins"][name], "identity": identity_version, "approval": dict(approval)}
    entry["current"] = version
    return version


def builder_sha256(root=ROOT):
    """One digest of the builder sources (the character tooling and the Blender scripts)."""
    root = Path(root)
    files = sorted(set(glob.glob(str(root / "tools" / "character_modeling" / "character_modeling" / "*.py")))
                   | set(glob.glob(str(root / "tools" / "blender" / "*.py")))
                   | set(glob.glob(str(root / "tools" / "blender" / "authoring" / "*.py"))))
    return digest([[Path(f).relative_to(root).as_posix(), file_sha256(f)] for f in files])


def provenance(snap, releases, skin, builder, canonical_geometry):
    """The build record of one skin (CHARACTER-BUILD-001): every input by revision and digest
    (foundation, rig, identity, skin, builder) and the output geometry as the order-independent
    `canonical_geometry` ({mesh: sha256} from `male_base_v2.canonical_geometry`, winding and
    materials included, face-array order not). `resolved_input_hash` is the same for a rebuild
    of the same revisions and builder; `geometry_hash` is the same for geometrically equivalent
    builds and differs only on a meaningful geometry change, so a harmless rim face reorder
    does not move it. Raw byte-level `fingerprints` are a separate concern (the foundation lock
    / `.blend` diffing), never the production identity."""
    state = status(snap, releases) if releases else None
    identity_rev = releases["identity"]["current"] if releases and state["identity"] == CLEAN else None
    skin_rev = (releases["skins"][skin]["current"] if releases and state["skins"].get(skin) == CLEAN else None)
    inputs = {"foundation": dict(snap["foundation"]), "rig": snap["rig"],
              "identity": {"revision": identity_rev, "digest": identity_digest(snap)},
              "skin": {"name": skin, "revision": skin_rev, "digest": snap["skins"][skin]},
              "builder_sha256": builder}
    return {"schema": PROVENANCE_SCHEMA, "character": snap["character"], "skin": skin, "inputs": inputs,
            "resolved_input_hash": digest(inputs), "geometry_hash": digest(canonical_geometry)}


## Files: the canonical characters, their definitions and release records.

def canonical_manifests():
    """Every canonical character manifest (`characters/<name>/<name>.assembly.json`)."""
    return sorted(Path(p) for p in glob.glob(str(CHARACTERS / "*" / "*.assembly.json")))


def releases_path(manifest_path):
    path = Path(manifest_path)
    return path.with_name(path.name.replace(".assembly.json", ".releases.json"))


def definitions_of(character, library=None):
    """{id: definition} of every asset the character wears (its outfits and facial hair), from
    `library` (the canonical garments, or a candidate's `garment_library`)."""
    folder = Path(library or character.get("garment_library") or GARMENTS)
    folder = folder if folder.is_absolute() else BLENDER / folder
    ids = set(character.get("foundation", {}).get("facial_hair", []))
    ids |= {g for entry in character.get("outfits", {}).values() for g in entry.get("garments", [])}
    return {gid: json.loads((folder / ("%s.garment.json" % gid)).read_text(encoding="utf-8")) for gid in sorted(ids)}


def swatches_of(character):
    """The shared skin swatches the character's identity names, or None."""
    from . import identity as identity_profile
    return identity_profile.load_swatches(character, ROOT) if character.get("skin_swatches") else None


def load(manifest_path, foundation_path=None):
    """(character, definitions, snapshot) of a manifest, built on its pinned foundation
    document unless `foundation_path` stages another."""
    character = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
    definitions = definitions_of(character)
    pinned = BLENDER / character["foundation"]["definition"]
    snap = snapshot(character, definitions, foundation_inputs(foundation_path or pinned), swatches_of(character))
    return character, definitions, snap


def _canon(path):
    return os.path.normcase(os.path.realpath(path))


def known_foundation_documents():
    """The canonical paths of every foundation document the library knows (every version of
    the `male_base_foundation` asset, current and superseded). A character pinned to one of
    these is validly configured; the current one is active, an older one is awaiting
    migration."""
    from . import asset_library as lib
    out = set()
    entry = lib.index()["assets"].get(lib.FOUNDATION_ASSET)
    if not entry:
        return out
    for version in entry["versions"]:
        data = lib.asset(lib.FOUNDATION_ASSET, version)
        for name, record in data["files"].items():
            if name.endswith(".json") and lib.payload(lib.FOUNDATION_ASSET, name, version).get("schema") == lib.FOUNDATION_SCHEMA:
                try:
                    out.add(_canon(record["from"] if os.path.isabs(record["from"]) else ROOT / record["from"]))
                except (OSError, ValueError):
                    pass
    return out


def pin_problems(character, active_document, known=None):
    """Why a character's foundation pin is INVALID — a hard failure. A pin to the active
    foundation is clean; a pin to another KNOWN foundation version (a superseded one in
    `known`, default `known_foundation_documents()`) is a valid historical pin awaiting
    migration, NOT an error (`migration_pending` reports it); only a pin to a document the
    library does not know is a problem."""
    pinned = _canon(BLENDER / character["foundation"]["definition"])
    if pinned == _canon(active_document):
        return []
    if pinned in (known if known is not None else known_foundation_documents()):
        return []
    return ["%s is pinned to %s, which is not a known foundation version" % (
        character["id"], character["foundation"]["definition"])]


def migration_pending(character, active_document):
    """True when the character is validly pinned to a known but superseded foundation (a
    migration to the active foundation is pending, not a misconfiguration)."""
    return _canon(BLENDER / character["foundation"]["definition"]) != _canon(active_document) and not pin_problems(character, active_document)


def family(foundation_path=None, foundation_id=None):
    """{character id: snapshot} of every canonical character; with `foundation_path`, the
    characters built on `foundation_id` (the staged document's id) are staged on it."""
    out = {}
    for path in canonical_manifests():
        character = json.loads(path.read_text(encoding="utf-8"))
        staged = foundation_path if foundation_path and character["foundation"]["id"] == foundation_id else None
        out[character["id"]] = load(path, staged)[2]
    return out


def check_canonical():
    """Every canonical character's HARD ownership, foundation-pin and release problems (what
    the lint gate fails on). A valid historical pin awaiting migration is NOT a problem; see
    `pending_migrations`."""
    from . import asset_library
    active = asset_library.current_foundation_document()
    known = known_foundation_documents()
    out = []
    for path in canonical_manifests():
        character, definitions, snap = load(path)
        out += problems(character, definitions)
        out += pin_problems(character, active, known)
        record = releases_path(path)
        if not record.exists():
            out.append("%s has no release record %s" % (character["id"], record.name))
            continue
        out += release_problems(snap, json.loads(record.read_text(encoding="utf-8")))
    return out


def pending_migrations():
    """Characters validly pinned to a superseded foundation, awaiting migration (informational,
    never a lint failure): {character id: pinned foundation definition}."""
    from . import asset_library
    active = asset_library.current_foundation_document()
    out = {}
    for path in canonical_manifests():
        character = json.loads(path.read_text(encoding="utf-8"))
        if migration_pending(character, active):
            out[character["id"]] = character["foundation"]["definition"]
    return out


def _write(path, data):
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(data, indent=1, sort_keys=True) + "\n")


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("status", "impact", "classify", "publish"))
    parser.add_argument("field", nargs="?")
    parser.add_argument("--foundation")
    parser.add_argument("--manifest")
    parser.add_argument("--character")
    parser.add_argument("--scope", choices=(IDENTITY, SKIN))
    parser.add_argument("--skin")
    parser.add_argument("--by")
    parser.add_argument("--date")
    parser.add_argument("--evidence")
    parser.add_argument("--validated", default="")
    args = parser.parse_args(argv)
    if args.action == "classify":
        print(json.dumps(dict(zip(("scope", "detail"), classify(args.field)))))
        return 0
    if args.action == "impact":
        candidate, definitions, staged = load(args.manifest, args.foundation)
        canonical = next(p for p in canonical_manifests() if json.loads(p.read_text(encoding="utf-8"))["id"] == candidate["id"])
        report = impact({candidate["id"]: load(canonical)[2]}, {candidate["id"]: staged})
        report["scope"] = scope_of(report)
        report["problems"] = problems(candidate, definitions, canonical=False)
        print(json.dumps(report, indent=1))
        return 1 if report["problems"] else 0
    if args.action == "publish":
        path = next(p for p in canonical_manifests() if json.loads(p.read_text(encoding="utf-8"))["id"] == args.character)
        character, definitions, snap = load(path)
        found = problems(character, definitions)
        if found:
            raise SystemExit("RIPOSTE_OWNERSHIP: " + "; ".join(found))
        record = releases_path(path)
        approval = {"date": args.date, "by": args.by, "evidence": args.evidence}
        validated = [v for v in args.validated.split(",") if v]
        if record.exists():
            releases = publish(json.loads(record.read_text(encoding="utf-8")), snap, args.scope, approval, args.skin, validated)
        else:
            releases = new_releases(snap, approval)
        _write(record, releases)
        print("RIPOSTE_RELEASE_PUBLISHED", record.name, releases["identity"]["current"],
              json.dumps({n: e["current"] for n, e in releases["skins"].items()}))
        return 0
    report = {"problems": check_canonical(), "pending_migrations": pending_migrations()}
    if args.foundation:
        staged_id = json.loads(Path(args.foundation).read_text(encoding="utf-8"))["id"]
        report["impact"] = impact(family(), family(args.foundation, staged_id))
        report["impact"]["scope"] = scope_of(report["impact"])
    print(json.dumps(report, indent=1))
    return 1 if report["problems"] else 0


if __name__ == "__main__":
    sys.exit(main())
