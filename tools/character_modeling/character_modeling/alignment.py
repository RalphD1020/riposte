"""CHARACTER-ALIGNMENT-001: the Blender -> Godot anatomical-alignment contract.

Five things must agree against the same anatomical landmarks and one rest pose: the anatomical
reference, the deform skeleton, the skin binding, the Blender-authored animation, and the Godot
import. A part that is correct in isolation still deforms wrongly when they disagree.

This module is the pure decision layer the Blender inspection and the Godot parity scripts call
to LABEL a finding, so a discrepancy is fixed at its owning layer instead of compensated for at
a later one. It computes nothing about geometry itself; it classifies boundary-check outcomes
and the skin/landmark contracts. No Blender, no engine types.
"""

from __future__ import annotations

from . import retopology_reference
from .skinning import INFLUENCE_LIMIT

## The frame every component shares; the exporter, not a wrapper transform, converts to Godot.
FRAME = retopology_reference.FRAME
REFERENCE_STATURE_M = 1.80
## Body skinning never rides these; they move the weapon and the whole figure, not flesh.
NON_DEFORMING_BONES = ("Root", "SwordMount")
NORMALIZED_TOLERANCE = 1e-5

## The five contracts that must agree (CHARACTER-ALIGNMENT-001).
CONTRACTS = ("anatomical_reference", "deform_skeleton", "skin_binding", "blender_animation", "godot_import")

## Owning layers, in dependency order: an error is owned by the FIRST failing one, and fixing a
## later layer to hide an earlier fault is the mistake this ordering prevents.
LAYER_SOURCE = "source_geometry"
LAYER_TRANSFORM = "object_transform"
LAYER_REST = "bone_rest_or_roll"
LAYER_JOINT = "joint_placement"
LAYER_WEIGHTS = "skin_weights"
LAYER_ANIMATION = "animation"
LAYER_RUNTIME = "runtime_modifier"
BOUNDARY_ORDER = (LAYER_SOURCE, LAYER_TRANSFORM, LAYER_REST, LAYER_JOINT, LAYER_WEIGHTS, LAYER_ANIMATION, LAYER_RUNTIME)

## The diagnostic rule by symptom: the layers to check, in order, BEFORE touching the art.
SYMPTOM_OFFSET_IN_GODOT = "offset_in_godot"
SYMPTOM_WRONG_WHEN_POSED = "correct_at_rest_wrong_when_posed"
SYMPTOM_BLENDER_OK_GODOT_WRONG = "right_in_blender_wrong_in_godot"
FIX_ORDER = {
    SYMPTOM_OFFSET_IN_GODOT: (LAYER_TRANSFORM, LAYER_REST, LAYER_SOURCE),
    SYMPTOM_WRONG_WHEN_POSED: (LAYER_ANIMATION, LAYER_WEIGHTS, LAYER_JOINT, LAYER_REST),
    SYMPTOM_BLENDER_OK_GODOT_WRONG: (LAYER_RUNTIME, LAYER_SOURCE),
}


def classify(checks):
    """The owning layer of a discrepancy: the first `BOUNDARY_ORDER` layer whose check is false.

    `checks` maps layer names to pass/fail; a layer absent from `checks` is treated as passing
    (not yet measured is not a failure). Returns None when every measured layer passes."""
    unknown = sorted(set(checks) - set(BOUNDARY_ORDER))
    if unknown:
        raise ValueError("not alignment layers: %s" % ", ".join(unknown))
    for layer in BOUNDARY_ORDER:
        if layer in checks and not checks[layer]:
            return layer
    return None


def fix_order(symptom):
    """The ordered layers to inspect for a symptom before changing the art (fail closed)."""
    if symptom not in FIX_ORDER:
        raise ValueError("unknown alignment symptom: %s" % symptom)
    return FIX_ORDER[symptom]


def skin_problems(influences, non_deforming=NON_DEFORMING_BONES, limit=INFLUENCE_LIMIT):
    """Why a body vertex's skin influences break the Godot-import contract (empty when they do
    not): over the four-influence limit, not normalized to one, or carrying a non-deforming
    bone. `influences` is an iterable of (bone_name, weight)."""
    out = []
    rows = list(influences)
    if len(rows) > limit:
        out.append("%d influences exceed the %d-influence limit" % (len(rows), limit))
    riding = sorted(bone for bone, _w in rows if bone in non_deforming)
    if riding:
        out.append("non-deforming bone(s) weighted into the body: %s" % ", ".join(riding))
    total = sum(w for _bone, w in rows)
    if rows and abs(total - 1.0) > NORMALIZED_TOLERANCE:
        out.append("influences sum to %.6f, not normalized to 1" % total)
    return out


def landmark_parity_problems(blender, godot, tolerance_m):
    """Landmarks that differ between Blender and the converted Godot pose beyond `tolerance_m`.

    Both map a landmark name to an (x, y, z) already in one frame (the caller applies the
    documented conversion). A landmark present on one side only is itself a parity failure."""
    out = []
    for name in sorted(set(blender) | set(godot)):
        if name not in blender or name not in godot:
            out.append("%s present on only one side" % name)
            continue
        d = sum((a - b) ** 2 for a, b in zip(blender[name], godot[name])) ** 0.5
        if d > tolerance_m:
            out.append("%s differs by %.4f m (> %.4f)" % (name, d, tolerance_m))
    return out
