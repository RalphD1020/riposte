"""Which measurements are protected, how, and on what authority.

A blanket sub-millimetre tolerance on a voxel-remeshed surface is precise in
the report without being accurate about the mesh. So every protected
measurement declares its class, where the number is measured, its tolerance
and the reason for it, and a calibration status. Only the hard classes can
fail a candidate; the soft classes are review triggers.

Classes
    SOURCE_INVARIANT   authored or rig value; exact or a small source tolerance
    GEOMETRY_INVARIANT integrity (holes, non-manifold, islands); pass/fail
    SHAPE_INVARIANT    a measurement that defines the approved design
    ANATOMY_TARGET     a range plus visual review, not an exact value
    HEURISTIC          a scanner signal; a review flag until calibrated

Status
    calibrated   checked against known-good and known-bad captures
    provisional  a defensible starting value, not yet calibrated
    advisory     evidence only; never fails a candidate on its own

Measurement source matters for tolerance. The head skull and mask are direct
lofts at fine resolution (``head_mesh``), so a face landmark can hold a
sub-millimetre-to-millimetre tolerance. The torso is voxel-remeshed
(``VOXEL`` = 5.5 mm), so a body span cannot credibly claim better than roughly
one voxel.
"""

from __future__ import annotations

SOURCE_INVARIANT = "source_invariant"
GEOMETRY_INVARIANT = "geometry_invariant"
SHAPE_INVARIANT = "shape_invariant"
ANATOMY_TARGET = "anatomy_target"
HEURISTIC = "heuristic"

HARD_CLASSES = frozenset((SOURCE_INVARIANT, GEOMETRY_INVARIANT, SHAPE_INVARIANT))
SOFT_CLASSES = frozenset((ANATOMY_TARGET, HEURISTIC))

VOXEL_M = 0.0055  # study fuse resolution; a remeshed span is no finer than this


class Protected:
    def __init__(self, path, cls, owner, method, tolerance, rationale, status):
        self.path = path
        self.cls = cls
        self.owner = owner
        self.method = method
        self.tolerance = tolerance
        self.rationale = rationale
        self.status = status

    @property
    def hard(self):
        return self.cls in HARD_CLASSES


# Face landmarks are measured on the direct skull/mask loft, not the remesh, so
# they hold fine tolerances. Body spans are measured on the voxel-remeshed
# torso, so they are held to roughly one voxel. Each entry names its phase
# owner: the phase allowed to change it is the one that must re-justify it.
REGISTRY = (
    Protected("head_landmarks.mask_fit.face.nose_tip.y", SHAPE_INVARIANT, "P1",
              "forward-most face vertex on the centre column (skull loft)", 0.001,
              "The nose peak defines the profile; the skull loft resolves it finely.", "provisional"),
    Protected("head_landmarks.mask_fit.face.nose_tip.z", SHAPE_INVARIANT, "P1",
              "height of the forward-most centre vertex (skull loft)", 0.002,
              "Peak height may shift one ring; two rings would move the nose.", "provisional"),
    Protected("head_landmarks.mask_fit.ridge.continuous_rows", SHAPE_INVARIANT, "P1",
              "count of centre-column rows forming the ridge", 0,
              "The ridge is the one authored hard edge; its row count is exact.", "provisional"),
    Protected("head_landmarks.mask_fit.face.chin.behind_nose_line_m", SHAPE_INVARIANT, "P1",
              "chin front vs the nose-tip vertical line (skull loft)", 0.0015,
              "The chin sits on the nose line; the loft resolves it finely.", "provisional"),
    Protected("head_landmarks.chin_width_m", SHAPE_INVARIANT, "P1",
              "chin width across the lower face (skull loft)", 0.002,
              "A defined chin, not a soft one; fine loft resolution.", "provisional"),
    Protected("head_landmarks.skull_width_m", SHAPE_INVARIANT, "P1",
              "widest cranium half-width x2 (skull loft)", 0.002,
              "The accepted head width is the body unit; loft resolution.", "provisional"),
    Protected("head_landmarks.skull_height_m", SOURCE_INVARIANT, "P1",
              "chin-to-crown height (skull loft, authored height input)", 0.002,
              "Head height is an authored input, not a polish variable.", "provisional"),
    Protected("head_landmarks.integrity.mirror_max_dev_m", GEOMETRY_INVARIANT, "all",
              "worst mirrored-vertex distance on the skull", 0.0005,
              "The head is authored symmetric; the loft is exact to rounding.", "calibrated"),
    Protected("body.deltoid_span_m", SHAPE_INVARIANT, "P3",
              "widest shoulder extent on the remeshed torso", 0.006,
              "Shoulder span defines the figure; measured on the 5.5 mm remesh, so ~1 voxel.", "provisional"),
    Protected("body.head.height", SOURCE_INVARIANT, "P1",
              "skull bounding height on the assembled figure", 0.003,
              "Proportion anchor; remesh plus bounding read, so a few mm.", "provisional"),
)
BY_PATH = {entry.path: entry for entry in REGISTRY}

# Phases declare what they may change; every other hard invariant stays fixed.
PHASE_MAY_CHANGE = {
    "P1": (),  # the crown join changes no protected measurement
    "P2": (),  # the back changes no front/head invariant
    "P3": ("body.deltoid_span_m",),  # the torso phase owns the shoulder span
    "P4": (),  # limbs keep every anchor
}


def hard_tolerances(exclude=()):
    """{path: tolerance} for the hard invariants, minus any a phase may change."""
    return {e.path: e.tolerance for e in REGISTRY if e.hard and e.path not in exclude}


def classify_status():
    counts = {}
    for entry in REGISTRY:
        counts[entry.status] = counts.get(entry.status, 0) + 1
    return counts
