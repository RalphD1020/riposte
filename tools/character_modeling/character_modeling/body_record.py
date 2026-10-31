"""A base body's record and the regression between two of them.

A record (`riposte.body_record`) is what a master is, measured: its topology, the
protected head island (positions and weights, vertex for vertex), WolfRig's rest as the
master carries it, its physique keys and vertex groups, and per named configuration its
landmark measurements — torso sections at fixed heights, limb girths by station along
each bone, bounds, surface area and volume. `tools/blender/inspect/base_record.py`
measures a blend into one; the baseline (v1) is frozen beside its copy.

`compare` is the regression report between a baseline and a candidate. What MUST NOT
change is a hard failure: the rig's rest (bones, parents, heads, tails, rolls), the head
island (same positions and weights vertex for vertex, in any vertex order), the physique
parameters' keys and the named configurations, the crown. What is meant to change (the
sculpt changes sections and girths) is reported as measured deltas, never judged here:
the person judges the look; numbers find where to look.

Pure Python: no Blender.
"""

from __future__ import annotations

import math

SCHEMA = "riposte.body_record"
VERSION = 1
## Equal within this (metres): rounding of a saved blend, not a change.
POSITION_TOLERANCE_M = 1e-5
WEIGHT_TOLERANCE = 1e-4
SPINE = ("Hips", "Spine", "Chest")
TORSO_HEIGHTS_M = (0.90, 0.95, 1.00, 1.05, 1.10, 1.15, 1.20, 1.25, 1.30, 1.35, 1.40, 1.45, 1.50)
TORSO_HALF_WIDTH_M = 0.30
STATION = 0.2


def torso_sections(points, edges, dominant, heights=TORSO_HEIGHTS_M):
    """Width, depth, front and back of the torso cut at each height: edges with an end
    riding a spine bone, crossing the height, within TORSO_HALF_WIDTH_M of the centre."""
    out = {}
    for z in heights:
        cut = []
        for a, b in edges:
            if dominant[a] not in SPINE and dominant[b] not in SPINE:
                continue
            pa, pb = points[a], points[b]
            if (pa[2] - z) * (pb[2] - z) > 0 or pa[2] == pb[2]:
                continue
            t = (z - pa[2]) / (pb[2] - pa[2])
            p = tuple(pa[i] + (pb[i] - pa[i]) * t for i in range(3))
            if abs(p[0]) < TORSO_HALF_WIDTH_M:
                cut.append(p)
        if cut:
            xs, ys = [p[0] for p in cut], [p[1] for p in cut]
            out["%.2f" % z] = {"width": round(max(xs) - min(xs), 4), "depth": round(max(ys) - min(ys), 4),
                               "front": round(min(ys), 4), "back": round(max(ys), 4)}
    return out


def limb_girths(points, dominant, bones, skipped=SPINE + ("Root", "SwordMount", "Neck", "Head")):
    """Mean and largest radius from each left-side bone's axis by station along it
    (0 at the head, 1 at the tail), over the vertices that bone dominates."""
    out = {}
    for name, (head, tail) in sorted(bones.items()):
        if name.endswith(".R") or name in skipped:
            continue
        axis = tuple(tail[i] - head[i] for i in range(3))
        length = math.sqrt(sum(c * c for c in axis))
        if length <= 0.0:
            continue
        unit = tuple(c / length for c in axis)
        stations = {}
        for index, p in enumerate(points):
            if dominant[index] != name:
                continue
            rel = tuple(p[i] - head[i] for i in range(3))
            along = sum(rel[i] * unit[i] for i in range(3)) / length
            radial = tuple(rel[i] - unit[i] * along * length for i in range(3))
            key = round(max(-STATION, min(1.0 + STATION, along)) / STATION) * STATION
            stations.setdefault("%.1f" % key, []).append(math.sqrt(sum(c * c for c in radial)))
        if stations:
            out[name] = {k: {"mean_r": round(sum(r) / len(r), 4), "max_r": round(max(r), 4), "n": len(r)}
                         for k, r in sorted(stations.items())}
    return out


## Tape-measure girths (what a tape reads: the convex-hull perimeter of a thin slab of the
## surface), measured in the authoring A-pose where the arms clear the torso. Torso slabs
## are horizontal and leave out the head island; limb slabs cross the posed bone. Targets
## per physique archetype (1.80 m, cm; docs/reference/character-anatomy.md) are directional.
TAPE_SLAB_M = 0.006
TAPE_TORSO_HALF_WIDTH_M = 0.24
TAPE_STATIONS = (
    ("neck", "torso", 1.545),
    ("chest", "torso", 1.27),
    ("waist", "torso", 1.05),
    ## Reach covers the heaviest configuration's arm (an extreme-heavy arm outgrew 0.10 m).
    ("upper_arm", "limb", ("UpperArm.L", 0.5, 0.13)),
    ("forearm", "limb", ("Forearm.L", 0.25, 0.08)),
    ("mid_thigh", "limb", ("UpperLeg.L", 0.45, 0.14)),
    ("calf", "limb", ("LowerLeg.L", 0.3, 0.10)),
)
BIDELTOID_BAND_M = (1.30, 1.48)
TAPE_TARGETS_CM = {
    "extreme_lean": {"neck": 38, "chest": 100, "waist": 76, "upper_arm": 34, "forearm": 29, "mid_thigh": 56, "calf": 38, "bideltoid": 49},
    "default": {"neck": 42, "chest": 112, "waist": 84, "upper_arm": 39, "forearm": 32, "mid_thigh": 62, "calf": 41, "bideltoid": 54},
    "extreme_heavy": {"neck": 47, "chest": 126, "waist": 90, "upper_arm": 48, "forearm": 36, "mid_thigh": 70, "calf": 46, "bideltoid": 60},
}


def hull_perimeter(points):
    """Convex-hull perimeter of 2D points (monotone chain)."""
    pts = sorted(set((round(p[0], 5), round(p[1], 5)) for p in points))
    if len(pts) < 3:
        return 0.0

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    hull = lower[:-1] + upper[:-1]
    return sum(math.dist(hull[i], hull[(i + 1) % len(hull)]) for i in range(len(hull)))


def tape_girths(points, bones, excluded=()):
    """Girths in cm at TAPE_STATIONS (plus the bideltoid breadth) of A-pose `points`;
    `bones` maps a bone to its posed (head, tail); `excluded` indices (the head island)
    never enter a torso slab."""
    skip = set(excluded)
    out = {}
    for name, kind, where in TAPE_STATIONS:
        if kind == "torso":
            slab = [(p[0], p[1]) for i, p in enumerate(points)
                    if i not in skip and abs(p[2] - where) < TAPE_SLAB_M and abs(p[0]) < TAPE_TORSO_HALF_WIDTH_M]
        else:
            bone, t, reach = where
            head, tail = bones[bone]
            axis = tuple(tail[i] - head[i] for i in range(3))
            length = math.sqrt(sum(c * c for c in axis))
            a = tuple(c / length for c in axis)
            centre = tuple(head[i] + axis[i] * t for i in range(3))
            u = _orthogonal(a)
            v = (a[1] * u[2] - a[2] * u[1], a[2] * u[0] - a[0] * u[2], a[0] * u[1] - a[1] * u[0])
            slab = []
            for p in points:
                d = tuple(p[i] - centre[i] for i in range(3))
                along = sum(d[i] * a[i] for i in range(3))
                radial = tuple(d[i] - a[i] * along for i in range(3))
                if abs(along) < TAPE_SLAB_M and math.sqrt(sum(c * c for c in radial)) < reach:
                    slab.append((sum(d[i] * u[i] for i in range(3)), sum(d[i] * v[i] for i in range(3))))
        out[name] = round(hull_perimeter(slab) * 100.0, 1)
    band = [p[0] for p in points if BIDELTOID_BAND_M[0] < p[2] < BIDELTOID_BAND_M[1]]
    out["bideltoid"] = round(2.0 * max(band) * 100.0, 1) if band else 0.0
    return out


def tape_ratios(girths, archetype="default"):
    target = TAPE_TARGETS_CM[archetype]
    return {k: round(girths[k] / target[k], 3) for k in target if girths.get(k)}


def _orthogonal(a):
    """A unit vector perpendicular to unit `a` (Blender's Vector.orthogonal convention)."""
    x, y, z = abs(a[0]), abs(a[1]), abs(a[2])
    if x < y and x < z:
        o = (0.0, a[2], -a[1])
    elif y < z:
        o = (-a[2], 0.0, a[0])
    else:
        o = (a[1], -a[0], 0.0)
    n = math.sqrt(sum(c * c for c in o))
    return tuple(c / n for c in o)


def _round(values, places=6):
    return [round(v, places) for v in values]


def head_island(positions, weights):
    """The protected island as an order-free list of (position, weights) rows."""
    rows = [(_round(p), {b: round(w, 5) for b, w in sorted(ws.items())}) for p, ws in zip(positions, weights)]
    return sorted(rows, key=lambda row: row[0])


def _island_problems(a, b):
    if len(a) != len(b):
        return ["head island has %d vertices, the baseline %d" % (len(b), len(a))]
    moved = reweighted = 0
    worst = 0.0
    for (pa, wa), (pb, wb) in zip(a, b):
        d = math.sqrt(sum((pa[i] - pb[i]) ** 2 for i in range(3)))
        worst = max(worst, d)
        moved += d > POSITION_TOLERANCE_M
        bones = set(wa) | set(wb)
        reweighted += any(abs(wa.get(k, 0.0) - wb.get(k, 0.0)) > WEIGHT_TOLERANCE for k in bones)
    out = []
    if moved:
        out.append("head island: %d vertices moved (worst %.6f m)" % (moved, worst))
    if reweighted:
        out.append("head island: %d vertices reweighted" % reweighted)
    return out


def _bone_problems(a, b):
    out = []
    for name in sorted(set(a) | set(b)):
        if name not in a or name not in b:
            out.append("bone %s %s" % (name, "added" if name in b else "missing"))
            continue
        ra, rb = a[name], b[name]
        if ra.get("parent") != rb.get("parent"):
            out.append("bone %s parent %s -> %s" % (name, ra.get("parent"), rb.get("parent")))
        for key in ("head", "tail"):
            if max(abs(x - y) for x, y in zip(ra[key], rb[key])) > POSITION_TOLERANCE_M:
                out.append("bone %s %s moved" % (name, key))
        if max((abs(x - y) for x, y in zip(ra.get("axes", []), rb.get("axes", []))), default=0.0) > 1e-4:
            out.append("bone %s orientation changed" % name)
    return out


def _deltas(a, b):
    """Per measure present in both: candidate minus baseline (metres)."""
    out = {}
    for key in sorted(set(a) & set(b)):
        va, vb = a[key], b[key]
        if isinstance(va, dict):
            sub = _deltas(va, vb)
            if sub:
                out[key] = sub
        elif isinstance(va, (int, float)) and not isinstance(va, bool) and key not in ("n",):
            out[key] = round(vb - va, 4)
    return out


def compare(baseline, candidate):
    """The regression report: (hard problems, report). Hard: the rig rest, the head
    island, the physique keys and configurations, the crown. Reported: topology change,
    per-configuration landmark deltas."""
    hard = []
    hard += _bone_problems(baseline["bones"], candidate["bones"])
    hard += _island_problems(baseline["head_island"], candidate["head_island"])
    missing_keys = sorted(set(baseline["keys"]) - set(candidate["keys"]))
    if missing_keys:
        hard.append("physique keys missing: %s" % missing_keys)
    missing_configs = sorted(set(baseline["configurations"]) - set(candidate["configurations"]))
    if missing_configs:
        hard.append("configurations missing: %s" % missing_configs)
    crown_a = baseline["configurations"]["default"]["bounds"]["max"][2]
    crown_b = candidate["configurations"].get("default", {}).get("bounds", {}).get("max", [0, 0, crown_a])[2]
    if abs(crown_a - crown_b) > POSITION_TOLERANCE_M * 10:
        hard.append("crown %.4f m, the baseline %.4f m" % (crown_b, crown_a))
    topo_a, topo_b = baseline["topology"], candidate["topology"]
    report = {
        "topology": {"changed": topo_a["fingerprint"] != topo_b["fingerprint"],
                     "triangles": [topo_a["triangles"], topo_b["triangles"]],
                     "vertices": [topo_a["vertices"], topo_b["vertices"]]},
        "configurations": {name: _deltas(baseline["configurations"][name], candidate["configurations"][name])
                           for name in sorted(set(baseline["configurations"]) & set(candidate["configurations"]))},
    }
    return hard, report
