"""Bounded shape controls for a future character creator.

A slider stores a domain value (a width in head-widths, a ratio, a
multiplier), not a raw vertex or a bone coordinate. The first panel is the
subset with ``ui`` set. The rest are valid controls the study can already
name; they stay off that panel until a preset needs them in the tool.
"""

from __future__ import annotations

ACCEPTED_CHEEK_WIDTH_M = 0.1125 * 1.17 * 2.0
ACCEPTED_HEAD_SCALE = 1.17
ACCEPTED_SIDE_BLEND = 0.66


class Slider:
    def __init__(self, id, group, label, meaning, unit, minimum, default, maximum, ui):
        self.id = id
        self.group = group
        self.label = label
        self.meaning = meaning
        self.unit = unit
        self.minimum = minimum
        self.default = default
        self.maximum = maximum
        self.ui = ui

    def holds(self, value):
        return self.minimum <= value <= self.maximum


def _slider(id, group, label, meaning, unit, minimum, default, maximum, ui):
    if not (minimum <= default <= maximum):
        raise ValueError("%s default is outside its range" % id)
    return Slider(id, group, label, meaning, unit, minimum, default, maximum, ui)


# Limb length, grip, and floor are not sliders. Mass may change. Stations may not.
SLIDERS = (
    _slider("shoulder_breadth", "torso", "Shoulder breadth",
            "Width of the shoulder silhouette, deltoid to deltoid, not the joint span.", "head_widths", 1.80, 3.00, 3.20, True),
    _slider("chest_mass", "torso", "Chest mass",
            "Upper-torso width, apart from how deep the chest is.", "head_widths", 1.50, 1.52, 2.10, True),
    _slider("chest_depth", "torso", "Chest depth",
            "Front-to-back size as a fraction of the front width at the same station.", "width_fraction", 0.50, 0.75, 0.75, True),
    _slider("waist_taper", "torso", "Waist taper",
            "Waist width divided by chest width. The torso narrows evenly to this.", "chest_fraction", 0.72, 0.88, 0.94, True),
    _slider("hip_breadth", "torso", "Hip breadth",
            "Pelvis width at the end of the torso taper. It does not flare past the waist.", "head_widths", 1.10, 1.34, 2.05, True),
    _slider("neck", "torso", "Neck",
            "Neck width. It stays narrower than the head.", "head_widths", 0.36, 0.56, 0.64, False),
    _slider("upper_arm", "limbs", "Upper-arm mass",
            "Upper-arm diameter at the shoulder.", "head_widths", 0.28, 0.66, 0.80, False),
    _slider("upper_arm_end", "limbs", "Upper-arm end",
            "Upper-arm diameter at the elbow.", "head_widths", 0.24, 0.50, 0.58, False),
    _slider("forearm", "limbs", "Forearm mass",
            "Forearm diameter below the elbow.", "head_widths", 0.26, 0.50, 0.62, False),
    _slider("forearm_end", "limbs", "Forearm end",
            "Forearm diameter at the wrist. The grip station does not move.", "head_widths", 0.22, 0.36, 0.56, False),
    _slider("thigh", "limbs", "Thigh mass",
            "Thigh diameter at the hip.", "head_widths", 0.40, 0.78, 0.86, True),
    _slider("thigh_end", "limbs", "Thigh end",
            "Thigh diameter at the knee.", "head_widths", 0.32, 0.56, 0.74, False),
    _slider("calf_knee", "limbs", "Knee",
            "Leg diameter through the knee.", "head_widths", 0.26, 0.54, 0.62, False),
    _slider("calf_belly", "limbs", "Calf mass",
            "Calf diameter at its fullest.", "head_widths", 0.34, 0.66, 0.80, False),
    _slider("calf_ankle", "limbs", "Ankle",
            "Leg diameter at the ankle. The ankle station does not move.", "head_widths", 0.24, 0.48, 0.58, False),
    _slider("hand_size", "extremities", "Hand size",
            "Hand thickness as a multiplier of the wrist. The grip does not move.", "wrist_fraction", 0.85, 1.08, 1.30, False),
    _slider("boot_volume", "extremities", "Boot volume",
            "Foot width. The sole stays on the floor.", "head_widths", 0.32, 0.50, 0.68, False),
    _slider("boot_shaft", "extremities", "Boot shaft",
            "How high the foot mass rises. It is not a bone length.", "metres", 0.10, 0.15, 0.22, False),
    _slider("head_width", "head", "Head width",
            "Cheek width as a multiple of the accepted head. 1 is that head.", "accepted_head", 0.90, 1.0, 1.15, True),
    _slider("crown_fullness", "head", "Crown fullness",
            "How wide the cranium is above the brow, relative to the accepted crown.", "accepted_crown", 0.94, 1.0, 1.12, True),
    _slider("side_blend", "head", "Cheek blend",
            "Where the flat cheek starts to round into the skull. Lower is softer.", "cheek_fraction", 0.45, 0.66, 0.72, False),
)

BY_ID = {slider.id: slider for slider in SLIDERS}
UI_IDS = tuple(slider.id for slider in SLIDERS if slider.ui)


def require_slider(id):
    slider = BY_ID.get(id)
    if slider is None:
        raise KeyError(id)
    return slider
