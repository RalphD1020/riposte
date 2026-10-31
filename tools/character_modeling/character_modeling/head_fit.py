"""HeadFitSurface: the head's semantic landmarks and the face checks measured on them
(HEAD-FIT-001, FACE-PLANAR-001, FACE-SILHOUETTE-001).

Consumers — the hair builder, garment fitting, CharacterArtQA — query named landmarks of
the selected head instead of its vertex indices, so a new cheekbone vertex or another
head profile never breaks them. `tools/blender/inspect/head_fit_surface.py` measures a
head mesh into a landmark set (`riposte.head_fit`); this module validates it and judges
the face:

- hard: the nose is the forward-most point of the face, on the centre line; the
  cheekbones are the widest forward-facing facial landmarks (a revision that loses either
  is a regression of the identity);
- warning: accidental asymmetry of paired landmarks; the brow burying the eye (the brow
  ridge must stand above the eye with clearance);
- advisory (measured, calibrated later on the approved face): orbital depth, brow
  projection, nose projection, cheekbone prominence, head-to-body proportion.

Identity preservation compares a candidate's landmarks with a reference's: the eye line
relative to the cranium and the nose centre line are invariant (HEAD-MORPH-001).

Coordinates: metres, Z up, -Y forward, X to the character's left. Pure Python.
"""

from __future__ import annotations

import math

SCHEMA = "riposte.head_fit"
KIND = "head_fit"
PAIRED = ("temple", "ear_root", "brow_inner", "brow_outer", "eye_centre", "cheek_peak", "jaw_angle")
CENTRAL = ("crown", "hairline_front", "occipital", "nape", "bun_anchor", "nose_bridge", "nose_tip", "chin", "neck_base")
## Facial landmarks the cheekbones must be wider than (forward-facing ones; temples, ears
## and the jaw angle are the head's sides, not the face).
FACIAL = ("brow_inner", "brow_outer", "eye_centre", "nose_bridge", "nose_tip", "chin")
SYMMETRY_TOLERANCE_M = 0.001
CENTRE_TOLERANCE_M = 0.001
## The nose tip is sampled on the surface; a face vertex this close ahead of it is the tip.
PEAK_TOLERANCE_M = 0.0005
## Below this a cheek "apex" is a flat panel's sampling noise, not a cheekbone.
CHEEKBONE_MIN_BULGE_M = 0.001
## Equal within this (metres) between two revisions of the same identity.
IDENTITY_TOLERANCE_M = 0.0015


def names():
    out = list(CENTRAL)
    for base in PAIRED:
        out += ["%s.L" % base, "%s.R" % base]
    return out


def landmark_problems(landmarks):
    out = []
    missing = [n for n in names() if n not in landmarks]
    if missing:
        out.append("head fit: landmarks missing %s" % missing)
    for name, p in sorted(landmarks.items()):
        if len(p) != 3 or not all(isinstance(c, (int, float)) and math.isfinite(c) for c in p):
            out.append("head fit: landmark %s is not a finite point" % name)
    return out


def _finding(severity, metric, value, threshold, message):
    return {"kind": KIND, "severity": severity, "metric": metric, "value": value, "threshold": threshold, "message": message}


def face_checks(landmarks, face_front_y, calibration=None, cheekbone_bulge_m=None):
    """Findings for one head. `face_front_y` is the most forward y of the face region
    (measured on the surface), so the nose can be checked against every face point;
    `cheekbone_bulge_m` is how far the cheekbone apex stands above its panel's chord (a
    flat panel has none: then the face has no cheekbone to judge, an advisory)."""
    findings = []
    measures = {}
    tip = landmarks["nose_tip"]
    if abs(tip[0]) > CENTRE_TOLERANCE_M:
        findings.append(_finding("hard", "nose_centre", round(tip[0], 4), CENTRE_TOLERANCE_M, "the nose tip is off the centre line"))
    if tip[1] > face_front_y + PEAK_TOLERANCE_M:
        findings.append(_finding("hard", "nose_peak", round(tip[1] - face_front_y, 4), PEAK_TOLERANCE_M,
                                 "the face projects %.4f m ahead of the nose: the nose is no longer the forward-most point" % (tip[1] - face_front_y)))
    cheek = abs(landmarks["cheek_peak.L"][0])
    widest = max(abs(landmarks[n][0]) for n in names() if n.split(".")[0] in FACIAL)
    measures["cheekbone_half_width_m"] = round(cheek, 4)
    if cheekbone_bulge_m is not None:
        measures["cheekbone_bulge_m"] = round(cheekbone_bulge_m, 4)
    if cheekbone_bulge_m is not None and cheekbone_bulge_m < CHEEKBONE_MIN_BULGE_M:
        findings.append(_finding("advisory", "cheekbone_apex", round(cheekbone_bulge_m, 4), CHEEKBONE_MIN_BULGE_M,
                                 "no cheekbone apex: the cheek panel is flat"))
    elif cheek < widest - 1e-4:
        findings.append(_finding("hard", "cheekbone_width", round(cheek, 4), round(widest, 4),
                                 "a facial landmark is wider than the cheekbones: they no longer give the face its width"))
    for base in PAIRED:
        left, right = landmarks["%s.L" % base], landmarks["%s.R" % base]
        error = max(abs(left[0] + right[0]), abs(left[1] - right[1]), abs(left[2] - right[2]))
        if error > SYMMETRY_TOLERANCE_M:
            findings.append(_finding("warning", "symmetry", round(error, 4), SYMMETRY_TOLERANCE_M, "%s.L and %s.R are not mirror images" % (base, base)))
    eye, brow, cheek_p = landmarks["eye_centre.L"], landmarks["brow_inner.L"], landmarks["cheek_peak.L"]
    measures["brow_projection_m"] = round(eye[1] - brow[1], 4)
    measures["orbital_depth_m"] = round(eye[1] - min(brow[1], cheek_p[1]), 4)
    measures["nose_projection_m"] = round(cheek_p[1] - tip[1], 4)
    measures["cheekbone_depth_m"] = round(eye[1] - cheek_p[1], 4)
    measures["brow_eye_separation_m"] = round(brow[2] - eye[2], 4)
    floor = (calibration or {}).get("brow_eye_separation_m")
    if measures["brow_eye_separation_m"] <= 0.0 or (floor is not None and measures["brow_eye_separation_m"] < floor):
        findings.append(_finding("warning", "eyelid_separation", measures["brow_eye_separation_m"], floor or 0.0,
                                 "the brow sits on or below the eye: it buries the eye"))
    for metric in ("brow_projection_m", "orbital_depth_m", "nose_projection_m", "cheekbone_depth_m"):
        reference = (calibration or {}).get(metric)
        if reference is not None and measures[metric] < reference * 0.5:
            findings.append(_finding("advisory", metric, measures[metric], reference * 0.5,
                                     "%s is less than half the approved reference" % metric))
    return measures, findings


def identity_problems(reference, candidate):
    """What must not move between two revisions of one identity: the eye line (height and
    spacing), the nose centre line, the crown."""
    out = []
    for name in ("eye_centre.L", "eye_centre.R"):
        for axis, label in ((0, "spacing"), (2, "height")):
            if abs(reference[name][axis] - candidate[name][axis]) > IDENTITY_TOLERANCE_M:
                out.append("%s %s moved %.4f m" % (name, label, candidate[name][axis] - reference[name][axis]))
    for name in ("nose_tip", "nose_bridge"):
        if abs(candidate[name][0]) > CENTRE_TOLERANCE_M:
            out.append("%s left the centre line" % name)
    if abs(reference["crown"][2] - candidate["crown"][2]) > IDENTITY_TOLERANCE_M:
        out.append("crown moved %.4f m" % (candidate["crown"][2] - reference["crown"][2]))
    return out


def head_to_body(head_height_m, body_height_m):
    """Head-to-body proportion (advisory until calibrated): the share of standing height."""
    return round(head_height_m / body_height_m, 4) if body_height_m > 0 else 0.0
