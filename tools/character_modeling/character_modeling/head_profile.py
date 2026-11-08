"""Head identity and morphology (HEAD-IDENTITY-001, HEAD-MORPH-001).

A head is resolved from two independent dimensions:

- identity: the character's own design parameters (or an archetype preset), the same in
  every body configuration — who he is;
- morphology from the physique: one deterministic profile per named configuration of the
  base (`<base>.configuration.json` `head_profiles`), working through soft tissue and
  silhouette — how his head belongs to his body.

They compose by addition and clamp to each parameter's range. A physique profile MUST NOT
set an identity-only parameter (a heavier body never changes eye spacing, nose, brow
curvature or face length) and may move the skull only within `PHYSIQUE_LIMIT` (body mass
does not determine skull size). Nothing here scales a head uniformly. The geometry these
parameters drive is authored in Blender as head shape keys (head milestone M3); until a
parameter has its key it is a design value that the tooling validates and records.

Pure Python: no Blender.
"""

from __future__ import annotations

SCHEMA = "riposte.head_profile"
## id: (kind, reads). identity_only parameters belong to the character alone; shared ones
## may also be moved, within PHYSIQUE_LIMIT, by the physique.
PARAMETERS = {
    "cranial_width": ("shared", "skull breadth"),
    "cranial_depth": ("shared", "front-to-back skull volume"),
    "cranial_height": ("identity_only", "crown and forehead proportion"),
    "face_length": ("identity_only", "brow-to-chin proportion"),
    "cheekbone_width": ("shared", "lateral facial projection"),
    "cheekbone_depth": ("shared", "forward cheek projection"),
    "cheek_fullness": ("shared", "lower-cheek soft tissue"),
    "jaw_width": ("shared", "lower-face silhouette"),
    "jaw_angle": ("identity_only", "mandibular corner below and ahead of the ear"),
    "chin_corner": ("identity_only", "breadth and flatness of the chin's lower edge"),
    "chin_breadth": ("identity_only", "one broad chin edge between its corners"),
    "submental_lift": ("identity_only", "the underside behind the chin rising to the jaw-neck junction"),
    "mandible_border": ("identity_only", "the jaw's lower border rising toward the mandibular corner"),
    "ramus_recess": ("identity_only", "the jaw's edge rising behind the mandibular corner toward the ear"),
    "submental_profile": ("identity_only", "the underside rising from the chin to the cervicomental junction"),
    "jaw_line": ("identity_only", "the jawline rising straight from the chin toward the ear"),
    "chin_round": ("identity_only", "the chin's profile corner rounded"),
    "cheek_jaw_break": ("identity_only", "the plane break where the cheek turns into the jaw"),
    "chin_projection": ("shared", "forward chin volume"),
    "brow_strength": ("shared", "brow ridge projection over the orbit"),
    "brow_curvature": ("identity_only", "brow expression"),
    "eye_spacing": ("identity_only", "distance between the eyes"),
    "nose_projection": ("identity_only", "central facial projection"),
    "neck_transition": ("shared", "skull-to-neck continuity and neck thickness"),
}
RANGE = (-1.0, 1.0)
## The most a physique may move a shared parameter: the skull is restrained, soft tissue is not.
PHYSIQUE_LIMIT = {"cranial_width": 0.25, "cranial_depth": 0.25}
DEFAULT_PHYSIQUE_LIMIT = 1.0
## Curated identity presets (directions on the one head, not separate meshes). Each
## differs from the reference in proportion and in the face's placement (eye spacing,
## brow angle), so two characters on one body read as two people (same-face prevention).
ARCHETYPES = {
    "reference": {},
    "angular": {"cheekbone_width": -0.3, "cheekbone_depth": 0.6, "jaw_width": -0.5, "chin_projection": 0.2, "face_length": 0.2,
                "brow_curvature": 0.6, "nose_projection": 0.4},
    "broad": {"jaw_width": 0.6, "cheek_fullness": 0.5, "chin_projection": 0.4, "cranial_width": 0.3, "cheekbone_width": 0.3,
              "eye_spacing": 0.5, "face_length": -0.2},
    "elongated": {"face_length": 0.6, "cranial_height": 0.3, "jaw_width": -0.3, "cheek_fullness": -0.3,
                  "eye_spacing": -0.3, "brow_curvature": -0.3},
    "compact": {"face_length": -0.5, "cheek_fullness": 0.4, "jaw_width": 0.3, "cranial_height": -0.2,
                "brow_curvature": -0.5, "nose_projection": -0.4},
}


def _range_problems(label, values):
    out = []
    for key, value in sorted(values.items()):
        if key not in PARAMETERS:
            out.append("%s: unknown head parameter %s" % (label, key))
        elif not isinstance(value, (int, float)) or not RANGE[0] <= value <= RANGE[1]:
            out.append("%s: %s = %r outside %s" % (label, key, value, list(RANGE)))
    return out


def physique_problems(profiles, configurations):
    """The base's physique-derived head profiles: one per named configuration, shared
    parameters only, the skull within its limit."""
    out = []
    missing = sorted(set(configurations) - set(profiles))
    extra = sorted(set(profiles) - set(configurations))
    if missing:
        out.append("head profiles missing for configurations %s" % missing)
    if extra:
        out.append("head profiles for unknown configurations %s" % extra)
    for name, values in sorted(profiles.items()):
        label = "head profile %s" % name
        out += _range_problems(label, values)
        for key, value in sorted(values.items()):
            if PARAMETERS.get(key, ("",))[0] == "identity_only":
                out.append("%s: %s is identity, never physique (HEAD-IDENTITY-001)" % (label, key))
            elif key in PARAMETERS and abs(value) > PHYSIQUE_LIMIT.get(key, DEFAULT_PHYSIQUE_LIMIT):
                out.append("%s: %s = %s beyond the physique limit %s (HEAD-MORPH-001)" % (
                    label, key, value, PHYSIQUE_LIMIT.get(key, DEFAULT_PHYSIQUE_LIMIT)))
    return out


def identity_problems(identity):
    """A character's head identity: a known archetype and bounded parameters."""
    out = []
    archetype = identity.get("archetype", "reference")
    if archetype not in ARCHETYPES:
        out.append("head identity: unknown archetype %r (known: %s)" % (archetype, sorted(ARCHETYPES)))
    out += _range_problems("head identity", identity.get("parameters", {}))
    return out


def resolve(identity, physique):
    """The composed head parameters: archetype + the character's parameters + the
    configuration's physique profile, clamped to the range. Every parameter is present."""
    values = {key: 0.0 for key in PARAMETERS}
    for source in (ARCHETYPES.get(identity.get("archetype", "reference"), {}), identity.get("parameters", {}), physique):
        for key, value in source.items():
            if key in values:
                values[key] += value
    return {key: round(max(RANGE[0], min(RANGE[1], value)), 4) for key, value in values.items()}


def identity_of(resolved, physique):
    """What a resolved head says about the character once the physique is taken out: the
    test that changing configuration never changes identity."""
    return {key: round(value - physique.get(key, 0.0), 4) for key, value in resolved.items()
            if PARAMETERS[key][0] == "identity_only" or key not in physique}
