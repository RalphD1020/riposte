"""Resolve a body (height, frame build, muscularity) into physical attributes.

The one implementation of the character physique model. Nothing in GDScript
re-derives these numbers: ``write_physique`` emits a resolved file the game's
catalog adapter reads, and a drift check fails when that file no longer
matches this resolver.

Model (geometric similarity, Wolf = 1.0). With ``h = height / 1.80``:

- Lengths along the skeleton scale with ``h`` (grip reach, lying length).
- Girths scale with ``h ** GIRTH_EXPONENT`` times a build factor. At the
  default exponent of 1 the body is isometric, so mass goes as ``h³``
  (``m = 80 · h³ · b_m``), muscle cross-section as ``h²`` and a joint torque
  (cross-section times lever) as ``h³`` — the same square-cube laws as
  ``FighterCatalog.prototype_at``. One exponent drives girth, mass, force
  and torque together so they cannot disagree.
- Frame build widens the skeleton: girth and mass scale with it; strength
  and turn torque do not (a wider skeleton is not a stronger one; it is a
  larger inertia, which the simulation already derives from mass and
  ``push_radius``).
- Muscularity scales muscle volume. Mass grows by the muscle share of the
  body; force-producing cross-section grows with muscularity; torso girth
  grows by the square root of its cross-section (bone and organs do not
  swell).

Mass is not strength: each output has its own law, and a heavier build does
not hit harder because it is heavier. Calibration constants are provisional
until the variant matrix measures generated bodies against them.

Every output is a resolved SI quantity or a dimensionless multiplier of
Wolf's reference; see ``UNITS``.
"""

from __future__ import annotations

import json
from pathlib import Path

from .baseline import reference, reference_geometry
from .parameters import BODY_BY_ID, BODY_INPUTS

SCHEMA = "riposte.physique"
VERSION = 1

# Girth exponent on relative height. 1 = isometric (geometric similarity).
GIRTH_EXPONENT = 1.0
# Skeletal muscle as a share of an athletic male's body mass (~0.42; Janssen
# et al. 2000, J Appl Physiol 89:81). Muscularity scales only that share.
MUSCLE_MASS_SHARE = 0.42
# Muscle as a share of the torso's cross-section at blade height. Provisional.
TORSO_MUSCLE_AREA_SHARE = 0.35
# How strongly frame breadth widens girth and the spacing footprint.
FRAME_GIRTH_EXPONENT = 1.0
FRAME_FOOTPRINT_EXPONENT = 1.0

# Applied: the adapter writes these onto FighterDefinition through the
# existing seam (authored mass and radii, ``resolve_actuators`` scales).
APPLIED = (
    "mass_kg", "strength_scale", "traction_scale", "turn_support_scale",
    "hurt_radius_m", "push_radius_m", "grip_radius_m", "hand_radius_m",
    "lying_half_length_m", "lying_radius_m",
)
# Proposed: reported for the balance review, never applied without an
# approved simulation contract (stamina capacity and recovery).
PROPOSED = ("stamina_capacity", "stamina_recovery")
# Readings: derived ratios for people. The simulation must not read them; it
# already derives acceleration and turning from the absolute quantities.
READINGS = ("mass_scale", "acceleration_scale", "turn_acceleration_scale")
OUTPUTS = APPLIED + PROPOSED + READINGS
UNITS = {
    "mass_kg": "kg", "hurt_radius_m": "m", "push_radius_m": "m", "grip_radius_m": "m",
    "hand_radius_m": "m", "lying_half_length_m": "m", "lying_radius_m": "m",
    "strength_scale": "x Wolf weapon drive", "traction_scale": "x Wolf locomotion force",
    "turn_support_scale": "x Wolf turn torque", "stamina_capacity": "x Wolf work capacity",
    "stamina_recovery": "x Wolf recovery rate", "mass_scale": "x Wolf mass",
    "acceleration_scale": "x Wolf linear acceleration", "turn_acceleration_scale": "x Wolf angular acceleration",
}
# The torso hurt-radius convention (TORSO-CIRCLE-001). ``hurt_radius`` is the
# circumscribed (enclosing) radius of the torso cross-section at blade height:
# the farthest section point from the torso axis. Wolf's 0.195 m is that
# radius of his 8-sided gambeson section with a flat half-width of 0.185 m and
# a half-depth of 0.154 m (the vertex at 22.5 degrees sits at ~0.1957 m). It is
# not the ellipse semiaxis (0.185 m) nor the bounding rectangle's corner
# (0.241 m). The approved 0.195 m stays the baseline; a measured mesh is
# compared with this convention and reported, never written back.
HURT_SECTION_SIDES = 8
HURT_SECTION_SPIN_RAD = 3.141592653589793 / 8.0


def enclosing_radius(points):
    """Circumscribed radius of a planar section about its axis (the convention)."""
    return max((x * x + y * y) ** 0.5 for x, y in points)


def polygon_section(half_width, half_depth, sides=HURT_SECTION_SIDES, spin=HURT_SECTION_SPIN_RAD):
    """Vertices of a spun regular polygon stretched to a flat half-width and a half-depth."""
    import math
    angles = [spin + 2.0 * math.pi * k / sides for k in range(sides)]
    radius = half_width / max(abs(math.cos(a)) for a in angles)
    depth = half_depth / max(abs(radius * math.sin(a)) for a in angles)
    return [(radius * math.cos(a), radius * depth * math.sin(a)) for a in angles]


def validate_body(body):
    if not isinstance(body, dict) or set(body) != set(BODY_BY_ID):
        return ["body must name exactly %s" % ", ".join(sorted(BODY_BY_ID))]
    problems = []
    for key, value in body.items():
        entry = BODY_BY_ID[key]
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not entry.holds(float(value)):
            problems.append("body.%s=%r is outside %s..%s" % (key, value, entry.minimum, entry.maximum))
    return problems


def resolve_physique(body):
    """Physical attributes for one body. Raises ValueError on a bad body or on
    a geometry that breaks ``0 < hurt_radius <= push_radius`` (no clamp)."""
    problems = validate_body(body)
    if problems:
        raise ValueError("; ".join(problems))
    ref = dict(reference(), **reference_geometry())
    h = float(body["height_m"]) / ref["height_m"]
    frame = float(body["frame_build"])
    muscle = float(body["muscularity"])
    girth = h ** GIRTH_EXPONENT
    section = girth * girth
    muscle_mass = (1.0 - MUSCLE_MASS_SHARE) + MUSCLE_MASS_SHARE * muscle
    torso_muscle = ((1.0 - TORSO_MUSCLE_AREA_SHARE) + TORSO_MUSCLE_AREA_SHARE * muscle) ** 0.5
    frame_girth = frame ** FRAME_GIRTH_EXPONENT
    mass_scale = h * section * frame * muscle_mass
    force = section * muscle
    torque = force * h
    hurt = ref["hurt_radius_m"] * girth * frame_girth * torso_muscle
    push = ref["push_radius_m"] * girth * frame ** FRAME_FOOTPRINT_EXPONENT
    if not (0.0 < hurt <= push):
        raise ValueError("hurt_radius %.4f m must be positive and within push_radius %.4f m" % (hurt, push))
    inertia_scale = mass_scale * (push / ref["push_radius_m"]) ** 2
    out = {
        "mass_kg": ref["mass_kg"] * mass_scale,
        "strength_scale": torque,
        "traction_scale": force,
        "turn_support_scale": torque,
        "hurt_radius_m": hurt,
        "push_radius_m": push,
        "grip_radius_m": ref["grip_radius_m"] * h,
        "hand_radius_m": ref["hand_radius_m"] * girth,
        "lying_half_length_m": ref["lying_half_length_m"] * h,
        "lying_radius_m": ref["lying_radius_m"] * girth * frame_girth * torso_muscle,
        "stamina_capacity": h * section * muscle,
        "stamina_recovery": 1.0,
        "mass_scale": mass_scale,
        "acceleration_scale": force / mass_scale,
        "turn_acceleration_scale": torque / inertia_scale,
    }
    return out


def physique_document(character_id, body):
    """The resolved file the game reads: inputs, applied values, proposals."""
    resolved = resolve_physique(body)
    return {
        "schema": SCHEMA,
        "version": VERSION,
        "id": character_id,
        "body": {entry.id: float(body[entry.id]) for entry in BODY_INPUTS},
        "applied": {key: round(resolved[key], 9) for key in APPLIED},
        "proposed": {key: round(resolved[key], 9) for key in PROPOSED},
        "readings": {key: round(resolved[key], 9) for key in READINGS},
    }


def render(document):
    return json.dumps(document, indent=2) + "\n"


def write_physique(path, character_id, body):
    Path(path).write_bytes(render(physique_document(character_id, body)).encode("utf-8"))


def drift(path, character_id, body):
    """Problems when the committed file at ``path`` no longer matches the resolver."""
    path = Path(path)
    if not path.is_file():
        return ["%s is missing; run the physique writer" % path.name]
    expected = render(physique_document(character_id, body))
    if path.read_text(encoding="utf-8").replace("\r\n", "\n") != expected:
        return ["%s is stale; regenerate it from the profile" % path.name]
    return []


# Each resolved physique the game reads, and the profile whose body it comes
# from. ``python -m character_modeling.physique`` regenerates them all.
PHYSIQUES = (
    ("character.wolf", "wolf.physique.json", "male_base.json"),
)


def _body_of(profile_name):
    from .definition import PROFILES, load_profile
    return load_profile(PROFILES / profile_name)["body"]


def physique_drift():
    from .baseline import PHYSIQUE_DIR
    problems = []
    for character_id, file_name, profile_name in PHYSIQUES:
        problems += drift(PHYSIQUE_DIR / file_name, character_id, _body_of(profile_name))
    return problems


def write_all():
    from .baseline import PHYSIQUE_DIR
    for character_id, file_name, profile_name in PHYSIQUES:
        write_physique(PHYSIQUE_DIR / file_name, character_id, _body_of(profile_name))
        print("wrote", file_name)


if __name__ == "__main__":
    write_all()
