"""Wolf, the 1.0 reference every character build is measured against.

The authoritative values live in GDScript, ``PhysicalBaseline``
(``game/src/domain/rules/physical_baseline.gd``). Python cannot import them,
so they are restated here once and ``game_baseline`` reads the GDScript file
back: a test holds the two halves together, because a rename or a retune on
the far side would not otherwise error (README, cross-language contracts).

These are resolved SI quantities, not normalized authoring values.
"""

from __future__ import annotations

import re
from pathlib import Path

REFERENCE_HEIGHT_M = 1.80
REFERENCE_MASS_KG = 80.0
REFERENCE_PUSH_RADIUS_M = 0.27
REFERENCE_HURT_RADIUS_M = 0.195

# Wolf's body geometry beyond the baseline four: the grip reach
# (PhysicalBaseline.GRIP_RADIUS_M = sword length - blade), the hand proxy, and
# the lying body (FighterCatalog.LYING_*).
REFERENCE_GRIP_RADIUS_M = 0.25
REFERENCE_HAND_RADIUS_M = 0.035
REFERENCE_LYING_HALF_LENGTH_M = 0.85
REFERENCE_LYING_RADIUS_M = 0.18

REPO = Path(__file__).resolve().parents[3]
PHYSICAL_BASELINE_GD = REPO / "game" / "src" / "domain" / "rules" / "physical_baseline.gd"
FIGHTER_CATALOG_GD = REPO / "game" / "content" / "rules" / "fighter_catalog.gd"
RIG_CONTRACT = REPO / "game" / "content" / "characters" / "wolf.rig-contract.json"
PHYSIQUE_DIR = REPO / "game" / "content" / "characters"

# Python name -> GDScript constant in PhysicalBaseline.
GDSCRIPT_NAMES = {
    "height_m": "FIGHTER_HEIGHT_M",
    "mass_kg": "FIGHTER_MASS_KG",
    "push_radius_m": "FIGHTER_RADIUS_M",
    "hurt_radius_m": "TORSO_HURT_RADIUS_M",
}


def reference():
    """Wolf's physical reference as resolved SI values."""
    return {
        "height_m": REFERENCE_HEIGHT_M,
        "mass_kg": REFERENCE_MASS_KG,
        "push_radius_m": REFERENCE_PUSH_RADIUS_M,
        "hurt_radius_m": REFERENCE_HURT_RADIUS_M,
    }


def reference_geometry():
    return {
        "grip_radius_m": REFERENCE_GRIP_RADIUS_M,
        "hand_radius_m": REFERENCE_HAND_RADIUS_M,
        "lying_half_length_m": REFERENCE_LYING_HALF_LENGTH_M,
        "lying_radius_m": REFERENCE_LYING_RADIUS_M,
    }


def _constant(text, name, path):
    match = re.search(r"^const %s := ([0-9.]+)\s*$" % name, text, re.MULTILINE)
    if match is None:
        raise ValueError("%s is missing from %s" % (name, path))
    return float(match.group(1))


def game_baseline(path=PHYSICAL_BASELINE_GD):
    """The same four values parsed from ``PhysicalBaseline`` in GDScript."""
    text = Path(path).read_text(encoding="utf-8")
    return {key: _constant(text, constant, path) for key, constant in GDSCRIPT_NAMES.items()}


def game_geometry(baseline_path=PHYSICAL_BASELINE_GD, catalog_path=FIGHTER_CATALOG_GD):
    """Wolf's grip, hand and lying geometry parsed from the GDScript sources."""
    base = Path(baseline_path).read_text(encoding="utf-8")
    catalog = Path(catalog_path).read_text(encoding="utf-8")
    return {
        "grip_radius_m": round(_constant(base, "SWORD_LENGTH_M", baseline_path)
                               - _constant(base, "SWORD_BLADE_M", baseline_path), 12),
        "hand_radius_m": _constant(base, "HAND_PROXY_RADIUS_M", baseline_path),
        "lying_half_length_m": _constant(catalog, "LYING_HALF_LENGTH_M", catalog_path),
        "lying_radius_m": _constant(catalog, "LYING_RADIUS_M", catalog_path),
    }
