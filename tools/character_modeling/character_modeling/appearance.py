"""The appearance plan (CHARACTER-LAYERING-001): a character's layers composed once, into one
flat plan that the Blender build realizes and the export records.

"Decorator" here means declarative composition, never runtime wrappers: each layer is a
definition that adds to the character and declares what it covers; `resolve` validates them
against the foundation, orders them, and computes the visibility of everything beneath them
in one place. No layer mutates another's visibility on its own; the Blender build and Godot
read the same plan and never reinterpret it.

Layers, innermost first (a layer may hide only what lies beneath it):

    foundation              the resolved body and head (never trimmed: hidden regions are
                            removed from derived copies)
    identity.face           the face marks (the foundation's default, a character's refinement)
    identity.facial_hair    facial hair (`riposte.garment` type `facial_hair`)
    outfit.hair             the outfit's hairstyle (type `hair`)
    outfit.garment.<1..4>   the outfit's garments by layer (type `garment`)

Coverage is directional and explicit. `coverage.hides`: foundation regions (body regions,
head sub-regions) whose surface the layer covers; `coverage.preserves`: regions that must
stay visible whatever covers them (a beard preserves the mouth); `coverage.hides_components`:
components beneath the layer it hides whole (a closed helmet hides the hairstyle). A hide of
a preserved region, or of a component that is not beneath, fails closed with its reason.

Pure Python: no Blender.
"""

from __future__ import annotations

import hashlib
import json

from . import garments

SCHEMA = "riposte.appearance_plan"
VERSION = 1
FOUNDATION = "foundation"
FACE = "identity.face"
FACIAL_HAIR = "identity.facial_hair"
HAIR = "outfit.hair"
GARMENT = "outfit.garment"
ORDER = {FOUNDATION: 0, FACE: 10, FACIAL_HAIR: 20, HAIR: 30}
GARMENT_ORDER = 100
LAYER_OF_TYPE = {"facial_hair": FACIAL_HAIR, "hair": HAIR}


def _layer(definition):
    kind = definition.get("type", "garment")
    if kind == "garment":
        return "%s.%d" % (GARMENT, definition["layer"]), GARMENT_ORDER + 10 * definition["layer"]
    layer = LAYER_OF_TYPE[kind]
    return layer, ORDER[layer]


def resolve(character, outfit, definitions, regions, target):
    """The appearance plan of `character` (its manifest) in `outfit`, from the asset
    `definitions` ({id: definition}), the foundation's fitting `regions` and the garment
    `target` (`foundation.garment_target`). Raises ValueError with every problem."""
    if outfit not in character["outfits"]:
        raise ValueError("%s has no outfit %s" % (character.get("id", "?"), outfit))
    ids = list(character["foundation"].get("facial_hair", [])) + list(character["outfits"][outfit].get("garments", []))
    missing = [i for i in ids if i not in definitions]
    if missing:
        raise ValueError("no definitions for %s" % missing)
    chosen = [definitions[i] for i in ids]
    problems = garments.outfit_problems(chosen, target, regions)
    components = []
    for definition in chosen:
        layer, order = _layer(definition)
        components.append({"id": definition["id"], "type": definition.get("type", "garment"), "layer": layer,
                           "order": order, "source": dict(definition["source"]),
                           "deformation": dict(definition["deformation"]),
                           "coverage": dict(definition.get("coverage", {}))})
    components.sort(key=lambda c: (c["order"], c["id"]))
    order_of = {c["id"]: c["order"] for c in components}
    preserved = {r: c["id"] for c in components for r in c["coverage"].get("preserves", [])}
    hidden_regions, hidden_components, margins = {}, {}, {}
    for component in components:
        coverage = component["coverage"]
        for region in coverage.get("hides", []):
            if region in preserved:
                problems.append("%s hides %s, which %s preserves" % (component["id"], region, preserved[region]))
                continue
            target_object = regions["regions"][region].get("object") or "body"
            hidden_regions.setdefault(target_object, set()).add(region)
            margins[target_object] = min(margins.get(target_object, 99), coverage.get("margin_rings", 1))
        for other in coverage.get("hides_components", []):
            if other not in order_of:
                problems.append("%s hides %s, which is not in this appearance" % (component["id"], other))
            elif order_of[other] >= component["order"]:
                problems.append("%s hides %s, which is not beneath it" % (component["id"], other))
            else:
                hidden_components.setdefault(other, []).append(component["id"])
    if problems:
        raise ValueError("; ".join(problems))
    plan = {
        "schema": SCHEMA, "version": VERSION, "character": character["id"], "outfit": outfit,
        "foundation": target["base"]["id"], "foundation_fingerprint": target["base"]["topology_fingerprint"],
        "face": character["foundation"]["face"],
        "components": [c for c in components if c["id"] not in hidden_components],
        "visibility": {
            "hidden_regions": {k: sorted(v) for k, v in sorted(hidden_regions.items())},
            "margin_rings": dict(sorted(margins.items())),
            "preserved_regions": sorted(preserved),
            "hidden_components": {k: sorted(v) for k, v in sorted(hidden_components.items())},
        },
    }
    plan["fingerprint"] = fingerprint(plan)
    return plan


def fingerprint(plan):
    """The plan's digest (every field but the digest): what a build and an export record."""
    body = {k: v for k, v in plan.items() if k != "fingerprint"}
    return hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest()[:16]


def hidden_vertices(plan, regions, target_object="body"):
    """Vertex indices of `target_object` ("body", or a region document's object such as the
    head) the plan hides."""
    out = set()
    for region in plan["visibility"]["hidden_regions"].get(target_object, []):
        out.update(regions["regions"][region]["vertices"])
    return out
