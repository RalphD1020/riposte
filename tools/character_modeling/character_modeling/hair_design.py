"""Hair design heuristics: measurements of a hairstyle's locks that ask for a look.

A lock is one authored clump: its centre line (`points`), its section `widths` and
`heights` along that line, and whether its tip shows (`free`: hanging hair) or
disappears into the hairstyle (tied hair ending in the bun). The authoring script
records them (`riposte_locks`); a hand sculpt can supply the same profile.

These are design heuristics, never technical failures and never an artistic verdict:
uniform widths, blunt visible tips and repetitive curvature are what made the earlier
hair read as chunky dreadlocks, so they are flagged for a person to look at. Whether
the hair looks natural, heroic or attractive stays a person's approval. Every
threshold is provisional until calibrated on approved and rejected hairstyles.

Pure Python: no Blender.
"""

from __future__ import annotations

import fnmatch
import math

KIND = "design_heuristic"
STATUS = "provisional"
## A region of at least MIN_LOCKS locks whose widest sections vary less than this
## (coefficient of variation) reads as uniform.
UNIFORM_WIDTH_CV = 0.08
MIN_LOCKS = 3
## A visible tip wider than this share of its lock's widest section reads as blunt.
BLUNT_TIP_SHARE = 0.45
## A region whose locks all turn less than this, or whose turning varies less than
## REPETITIVE_TURN_CV, reads as straight or repetitive.
STRAIGHT_TURN_DEG = 6.0
REPETITIVE_TURN_CV = 0.12


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _norm(a):
    return math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])


def _angle(a, b):
    na, nb = _norm(a), _norm(b)
    if na < 1e-12 or nb < 1e-12:
        return 0.0
    c = max(-1.0, min(1.0, (a[0] * b[0] + a[1] * b[1] + a[2] * b[2]) / (na * nb)))
    return math.degrees(math.acos(c))


def lock_metrics(lock):
    """Length, widest section, tip share of it, and total turning along the centre line."""
    points = lock["points"]
    widths = lock["widths"]
    steps = [_sub(b, a) for a, b in zip(points, points[1:])]
    length = sum(_norm(s) for s in steps)
    turn = sum(_angle(a, b) for a, b in zip(steps, steps[1:]))
    widest = max(widths)
    return {"length_m": round(length, 4), "widest_m": round(widest, 4),
            "tip_share": round(widths[-1] / widest, 3) if widest > 0 else 0.0, "turn_deg": round(turn, 2)}


def _cv(values):
    mean = sum(values) / len(values)
    if mean <= 0:
        return 0.0
    return math.sqrt(sum((v - mean) ** 2 for v in values) / len(values)) / mean


def region_of(name, regions):
    """The design region whose names or patterns match a lock's name, else None."""
    for region, patterns in regions.items():
        if any(fnmatch.fnmatchcase(name, p) for p in patterns):
            return region
    return None


def heuristics(locks, regions):
    """Per design region: uniform widths, blunt visible tips, and straight or repetitive
    curvature of hanging (free) locks. Returns (metrics by lock, findings)."""
    metrics = {lock["name"]: lock_metrics(lock) for lock in locks}
    grouped = {}
    for lock in locks:
        grouped.setdefault(region_of(lock["name"], regions), []).append(lock)
    findings = []
    for region, members in sorted(grouped.items(), key=lambda item: str(item[0])):
        values = [metrics[m["name"]] for m in members]
        if len(members) >= MIN_LOCKS:
            cv = _cv([v["widest_m"] for v in values])
            if cv < UNIFORM_WIDTH_CV:
                findings.append(_finding(region, "width_variation", round(cv, 3), "< %.2f" % UNIFORM_WIDTH_CV,
                                         "every lock in %s is about as wide as the next: the uniform dreadlock look" % region))
        ## Curvature is judged on hanging hair only: tied hair combed to one point is
        ## meant to flow alike.
        turns = [metrics[m["name"]]["turn_deg"] for m in members if m.get("free")]
        if len(turns) >= MIN_LOCKS:
            if max(turns) < STRAIGHT_TURN_DEG:
                findings.append(_finding(region, "curvature", round(max(turns), 2), "< %.1f deg" % STRAIGHT_TURN_DEG,
                                         "the locks in %s are straight: no flow" % region))
            elif _cv(turns) < REPETITIVE_TURN_CV:
                findings.append(_finding(region, "curvature_variation", round(_cv(turns), 3), "< %.2f" % REPETITIVE_TURN_CV,
                                         "the locks in %s all bend alike: repetitive, artificial" % region))
        blunt = sorted(m["name"] for m in members if m.get("free") and metrics[m["name"]]["tip_share"] > BLUNT_TIP_SHARE)
        if blunt:
            findings.append(_finding(region, "tip_taper", blunt, "> %.2f of the widest section" % BLUNT_TIP_SHARE,
                                     "visible tips in %s end blunt: %s" % (region, ", ".join(blunt))))
    return metrics, findings


def _finding(region, metric, value, threshold, message):
    return {"kind": KIND, "status": STATUS, "region": region, "metric": metric, "value": value,
            "threshold": threshold, "message": message}
