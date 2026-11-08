"""The character foundation (`riposte.character_foundation`, CHARACTER-FOUNDATION-001).

A foundation is the default body every character of a base is built on: the base sculpt
and head (how the builder makes them from the master), the resolution studies every
configuration applies on top of `variation.resolve`, and the default identity (a neutral
palette and the default face). It owns no character: no hair, no attire. A character
names its foundation and layers identity, hair and attire on top; garments target the
foundation's id, topology fingerprint and fitting regions.

Pure Python: no Blender. The builders (`male_base_v2.py --foundation`,
`male_base_v2_variation.py`) read the same document through these functions.
"""

import json
import os

from . import chest_profile, ear, eye_assembly, face_mask, silhouette, variation
from .physique import resolve_physique

SCHEMA = "riposte.character_foundation"
VERSION = 1
REQUIRED = ("id", "status", "source", "record", "lock", "regions", "builder", "base", "resolution", "reference",
            "skeleton", "default_identity", "materials")
## The resolution keys every configuration built on the foundation carries (the builder's
## switches: head design, side-profile studies, girth, the rig fit and its weights).
RESOLUTION_KEYS = ("head_study", "silhouette_study", "chest_study", "glute_study", "girth_study", "region_fix",
                   "rig_fit", "chest_smooth", "chest_fit", "face_response", "rig_weight_smooth_iterations")
## Switches a later foundation revision introduced: absent means off, so an approved
## foundation that predates one keeps its document (and its lock) unchanged. `ears`: the
## foundation's ear component (`ear`), built on every resolved head. `head_design`: head
## studies anchored at the lean, reference and strongman builds ({anchor: {study: value}},
## `variation.designed_study`), added to `head_study` at each body's build coordinate.
## `seat_neck`: every resolved body's neck seated inside its head where it would come
## through the jaw's sides or the face (`male_base_v2.seat_neck`; nothing moves where
## nothing crosses).
OPTIONAL_RESOLUTION_KEYS = ("ears", "head_design", "seat_neck")
SWITCHES = ("ears", "seat_neck")
STATUSES = ("candidate", "approved")
## Variant generation (three approval scopes: the canonical foundation; how its derived
## height and build variants are generated; a character's identity). These switches change
## only derived variants, never the reference: the foundation document's value is the
## canonical default, and the current approved variant-generation version
## (`riposte.foundation_variants`, the library's `male_base_variants`) sets them, so turning
## one on is a new variants version, never a foundation revision.
VARIANT_SCHEMA = "riposte.foundation_variants"
VARIANT_KEYS = ("face_response",)
FACE_MARKS = ("Eye", "Brow", "DeadEye")
## The reference configuration resolves to this mass within this tolerance (kg).
MASS_TOLERANCE_KG = 0.05


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def path_of(document, key, blender_root):
    """An `art-src/blender`-relative path the foundation names, made absolute."""
    return os.path.join(blender_root, document[key])


def problems(document):
    """Why the foundation cannot be built or applied. Empty means consistent."""
    if document.get("schema") != SCHEMA:
        return ["not a %s" % SCHEMA]
    if document.get("version") != VERSION:
        return ["foundation version %s is not %d" % (document.get("version"), VERSION)]
    missing = [key for key in REQUIRED if key not in document]
    if missing:
        return ["foundation lacks %s" % ", ".join(missing)]
    out = []
    if document["status"] not in STATUSES:
        out.append("status must be one of %s" % (STATUSES,))
    unknown_mask = sorted(set(document["base"].get("mask_study", {})) - set(face_mask.MASK_STUDY)
                          - {face_mask.EDGE_SOFTNESS, face_mask.LOWER_CONTOUR})
    if unknown_mask:
        out.append("unknown mask studies %s" % unknown_mask)
    resolution = document["resolution"]
    unknown = sorted(set(resolution) - set(RESOLUTION_KEYS) - set(OPTIONAL_RESOLUTION_KEYS))
    out += ["%s is a switch (true or false)" % k for k in SWITCHES if k in resolution and not isinstance(resolution[k], bool)]
    design = resolution.get("head_design") or {}
    out += ["head_design anchor %s is not one of %s" % (a, variation.DESIGN_ANCHORS) for a in sorted(set(design) - set(variation.DESIGN_ANCHORS))]
    out += ["head_design %s names unknown head studies %s" % (a, sorted(set(s) - set(variation.HEAD_STUDY)))
            for a, s in sorted(design.items()) if set(s) - set(variation.HEAD_STUDY)]
    canonical_on = sorted(k for k in VARIANT_KEYS if resolution.get(k))
    if canonical_on:
        out.append("variant switches %s are set by variant generation, not on in the foundation" % canonical_on)
    if unknown:
        out.append("unknown resolution keys %s" % unknown)
    lacking = sorted(set(RESOLUTION_KEYS) - set(resolution))
    if lacking:
        out.append("resolution lacks %s" % lacking)
    head = sorted(set(resolution.get("head_study") or {}) - set(variation.HEAD_STUDY))
    if head:
        out.append("unknown head studies %s" % head)
    for key in ("silhouette_study", "glute_study"):
        if resolution.get(key) is not None and resolution[key] not in silhouette.ANCHORS:
            out.append("%s %s is not a silhouette study" % (key, resolution[key]))
    if resolution.get("chest_study") is not None and resolution["chest_study"] not in chest_profile.STUDIES:
        out.append("chest_study %s is not a chest study" % resolution["chest_study"])
    if resolution.get("girth_study") not in (None, variation.GIRTH_FULL):
        out.append("girth_study must be null or %s" % variation.GIRTH_FULL)
    iterations = resolution.get("rig_weight_smooth_iterations")
    if not isinstance(iterations, int) or iterations < 0:
        out.append("rig_weight_smooth_iterations is a count of passes")
    out += _identity_problems(document)
    reference = document["reference"]
    mass = resolve_physique({k: reference[k] for k in ("height_m", "frame_build", "muscularity")})["mass_kg"]
    if abs(mass - reference["mass_kg"]) > MASS_TOLERANCE_KG:
        out.append("the reference body resolves to %.2f kg, not %.2f" % (mass, reference["mass_kg"]))
    return out


def _identity_problems(document):
    identity = document["default_identity"]
    marks = identity.get("face", {}).get("marks", {})
    out = ["the default face lacks %s" % m for m in FACE_MARKS if m not in marks]
    if "Eye" in marks:
        out += ["default eye: %s" % p for p in eye_assembly.profile_problems(marks["Eye"])]
    missing = sorted(set(document["materials"]["intrinsic"]) - set(identity.get("palette", {})))
    if missing:
        out.append("the default palette lacks the intrinsic materials %s" % missing)
    skin = identity.get("palette", {}).get("skin", {})
    if "swatch" not in skin or "srgb" in skin:
        out.append("the default skin names a shared swatch, not a colour")
    return out


def apply(resolved, document, marks=None, variants=None):
    """`resolved` (from `variation.resolve`) with the foundation's base design, resolution
    studies and face (the default face unless `marks` names an identity's own), and the
    variant-generation settings of `variants` over the document's defaults: a copy."""
    out = dict(resolved)
    out["mask_study"] = dict(document["base"]["mask_study"])
    out["marks"] = marks if marks is not None else document["default_identity"]["face"]["marks"]
    for key in RESOLUTION_KEYS:
        out[key] = document["resolution"][key]
    for key in SWITCHES:
        out[key] = document["resolution"].get(key, False)
    design = document["resolution"].get("head_design")
    coordinate = variation.design_coordinate(resolved["body"]) if design else 0.0
    out["ear_flare_deg"] = ear.design_flare(coordinate) if design else ear.FLARE_DEG
    out["ear_scale"] = ear.design_scale(coordinate) if design else 1.0
    if design:
        study = dict(out["head_study"] or {})
        for name, value in variation.designed_study(design, resolved["body"]).items():
            study[name] = round(study.get(name, 0.0) + value, 9)
        out["head_study"] = {k: v for k, v in study.items() if v}
    if variants is not None:
        problems = variants_problems(variants, document)
        if problems:
            raise ValueError("; ".join(problems))
        out.update(variants["settings"])
    out["foundation"] = document["id"]
    return out


def variants_problems(variants, document):
    """Why a variant-generation document cannot be applied to `document`."""
    if variants.get("schema") != VARIANT_SCHEMA:
        return ["not a %s" % VARIANT_SCHEMA]
    out = []
    if variants.get("foundation") != document["id"]:
        out.append("variant generation for %s, not %s" % (variants.get("foundation"), document["id"]))
    settings = variants.get("settings", {})
    unknown = sorted(set(settings) - set(VARIANT_KEYS))
    if unknown:
        out.append("variant generation sets %s, which are not variant switches %s" % (unknown, VARIANT_KEYS))
    out += ["variant switch %s is true or false" % k for k, v in settings.items() if k in VARIANT_KEYS and not isinstance(v, bool)]
    return out


def identity_manifest(document):
    """The default identity in the shape the assembly's material helpers read
    (`character_assembly.identity_materials` / `palette_materials`)."""
    identity = document["default_identity"]
    return {"skin_swatches": identity["skin_swatches"],
            "identity": {"palette": identity["palette"], "face": identity["face"]},
            "materials": {"intrinsic": list(document["materials"]["intrinsic"]), "costume": []}}


def garment_target(document, record, character):
    """What a garment fitted on this foundation is checked against (`garments.problems`):
    the foundation's id and body topology fingerprint, the skeleton, and the character's
    supported configurations and material slots."""
    return {"base": {"id": document["id"], "topology_fingerprint": record["objects"]["BodyV2"]["sha256"]},
            "skeleton": dict(document["skeleton"]),
            "physique": {"supported_configurations": list(character["physique"]["supported_configurations"])},
            "materials": {"intrinsic": list(character["materials"]["intrinsic"]),
                          "costume": list(character["materials"]["costume"])}}


def character_problems(document, character):
    """Why a character manifest cannot be built on this foundation: its `foundation` block
    must name it and resolve its body to the reference or a supported body."""
    block = character.get("foundation")
    if block is None:
        return ["%s names no foundation" % character.get("id", "?")]
    out = []
    if block.get("id") != document["id"]:
        out.append("%s is built on %s, not %s" % (character.get("id", "?"), block.get("id"), document["id"]))
    if block.get("face") not in ("default", "identity"):
        out.append("foundation.face is default (the foundation's face) or identity (the character's own marks)")
    if character["skeleton"] != document["skeleton"]:
        out.append("%s uses another skeleton contract than its foundation" % character.get("id", "?"))
    try:
        resolve_physique(block["body"])
    except (KeyError, ValueError) as error:
        out.append("foundation.body does not resolve: %s" % error)
    return out


def character_marks(document, character):
    """The face a character wears on the foundation: the default face (with the character's
    `face_refine` laid over it: per mark, the keys it names replace the default's, so a
    character's identity is the default face plus its own measured changes), or its own
    marks."""
    block = character["foundation"]
    if block["face"] != "default":
        return character["identity"]["face"]["marks"]
    marks = document["default_identity"]["face"]["marks"]
    refine = block.get("face_refine") or {}
    if not refine:
        return marks
    out = {name: dict(mark) for name, mark in marks.items()}
    for name, keys in refine.items():
        if name not in out:
            raise KeyError("face_refine names a mark the default face does not have: %s" % name)
        for key, value in keys.items():
            if isinstance(value, dict) and isinstance(out[name].get(key), dict):
                out[name][key] = dict(out[name][key], **value)
            else:
                out[name][key] = value
    return out
