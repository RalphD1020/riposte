"""Character Surface Integration: whether independently authored components form one
believable character.

A character is a coordinated system of anatomical and visual surfaces, not meshes that
happen to share a skeleton. Each component (a hairstyle today, garments next) declares
how it meets each anatomical region of a source surface (`surfaces.relationships` in its
definition), and the assembly is measured against those declarations:

- attach: firmly integrated with the region (hair roots and the bun on the scalp). The
  component's gap to the region is bounded; a disconnected root is a hard failure.
- clearance: outside the region with no penetration (the neck beside a tied style).
- drape: rests along the region's contour (hanging hair over the occiput, nape and
  trapezius): no penetration, a bounded separation, and it follows the contour where the
  region narrows instead of standing off it as a sheet or column.

Not every surface should touch: hair has volume and garments have thickness. What this
finds is accidental floating, intersections and disconnected silhouettes.

Regions are located by spatial query in a rig-relative frame (bands along named bones,
sectors of azimuth round the rig's vertical axis), never by vertex index, so the same
declaration serves every base on the rig contract, every physique and every component.
The base's topology fingerprint stays what it was: asset compatibility.

Severity: hard (face penetration, disconnected roots, severe intersections), warning
(calibrated: excessive separation, unnatural nape curvature) and advisory (layering and
transitions for a person to look at). No universal threshold is invented: a bound comes
from `calibration` measured on approved assets, with its provenance. An uncalibrated
metric is reported as a measurement and never flags, except a sign rule that holds at any
scale (hair moving away from a nape that narrows is a column whatever the character's size).

Not measured yet: silhouette continuity, and garment intersection and layer ordering (no
garment surfaces are assembled yet; a relationship's `source` already names a garment).

Pure Python: no Blender. The Blender side (tools/blender/inspect/garment_audit.py) takes
the measurements and calls this module to judge them.
"""

from __future__ import annotations

import math

RELATIONSHIPS = ("attach", "clearance", "drape")
SEVERITIES = ("hard", "warning", "advisory")
BASE_SOURCE = "base"
GARMENT_PREFIX = "garment:"
KIND = "surface_integration"
## The head/neck interfaces garments and hair fit through (HEAD-FIT-001).
INTERFACES = ("head_to_neck", "neck_to_shoulder")
## Penetration this shallow is mesh tolerance, not contact (the envelope's own tolerance).
PENETRATION_M = 0.0005


def azimuth(point, axis):
    """Degrees from the front (-y) round the vertical axis through `axis` (x, y), 0..180
    on either side: the sectors are symmetric."""
    x, y = point[0] - axis[0], point[1] - axis[1]
    return abs(math.degrees(math.atan2(x, -y)))


def band_height(landmarks, bone, share):
    """The height `share` of the way along `bone` (head 0 -> tail 1; outside 0..1 extends it)."""
    head, tail = landmarks[bone]
    return head[2] + share * (tail[2] - head[2])


def classify(point, landmarks, regions):
    """The first declared region whose bone band and azimuth sector contain `point`, else None."""
    axis = landmarks[regions["axis"]][0]
    a = azimuth(point, axis)
    for region in regions["regions"]:
        low, high = (band_height(landmarks, region["bone"], s) for s in region["span"])
        if min(low, high) <= point[2] <= max(low, high) and region["sector"][0] <= a <= region["sector"][1]:
            return region["name"]
    return None


def region_problems(regions, bones):
    """A surface-region declaration: named regions on bones of the rig, spans and sectors
    that are ordered pairs, an axis bone."""
    out = []
    if regions.get("axis") not in bones:
        out.append("surface regions: the axis %r is not a rig bone" % regions.get("axis"))
    names = [r.get("name") for r in regions.get("regions", [])]
    if not names or len(set(names)) != len(names):
        out.append("surface regions: regions are named, uniquely")
    for region in regions.get("regions", []):
        if region.get("bone") not in bones:
            out.append("surface region %s: bone %r is not a rig bone" % (region.get("name"), region.get("bone")))
        for key, lo, hi in (("span", -math.inf, math.inf), ("sector", 0.0, 180.0)):
            pair = region.get(key) or []
            if not (len(pair) == 2 and lo <= pair[0] < pair[1] <= hi):
                out.append("surface region %s: %s must be an ordered pair within [%s, %s]" % (region.get("name"), key, lo, hi))
    ## The head/neck fitting interfaces (HEAD-FIT-001) group declared regions.
    for interface in INTERFACES:
        members = regions.get("interfaces", {}).get(interface)
        if not members:
            out.append("surface regions: interface %s names its regions" % interface)
        else:
            unknown = sorted(set(members) - set(names))
            if unknown:
                out.append("surface regions: interface %s names unknown regions %s" % (interface, unknown))
    return out


def relationship_problems(component, regions):
    """A component's declared relationships: known regions and relationships, a known
    source, severities from SEVERITIES, and (for hair) design regions it really has."""
    out = []
    cid = component.get("id", "?")
    surfaces = component.get("surfaces")
    if not surfaces or not surfaces.get("relationships"):
        return ["%s: declares how it meets the body (surfaces.relationships)" % cid]
    known = {r["name"] for r in regions["regions"]}
    design = set(component.get("design", {}).get("regions", {}))
    for rel in surfaces["relationships"]:
        label = "%s: surface %s" % (cid, rel.get("region"))
        if rel.get("region") not in known:
            out.append("%s: unknown region (known: %s)" % (label, sorted(known)))
        if rel.get("relationship") not in RELATIONSHIPS:
            out.append("%s: relationship must be one of %s" % (label, RELATIONSHIPS))
        source = rel.get("source", BASE_SOURCE)
        if source != BASE_SOURCE and not source.startswith(GARMENT_PREFIX):
            out.append("%s: source is %r or %s<id>" % (label, BASE_SOURCE, GARMENT_PREFIX))
        if rel.get("severity", "warning") not in SEVERITIES:
            out.append("%s: severity must be one of %s" % (label, SEVERITIES))
        missing = sorted(set(rel.get("design_regions", [])) - design) if design else []
        if not rel.get("design_regions") or missing:
            out.append("%s: names the component's design regions it concerns (unknown: %s)" % (label, missing))
    return out


def stats(distances):
    """Signed distances to a surface (negative: inside): count, min, median, p90, max."""
    if not distances:
        return {"count": 0}
    ordered = sorted(distances)

    def pick(q):
        return ordered[min(len(ordered) - 1, int(q * (len(ordered) - 1) + 0.5))]

    return {"count": len(ordered), "min_m": round(ordered[0], 4), "p50_m": round(pick(0.5), 4),
            "p90_m": round(pick(0.9), 4), "max_m": round(ordered[-1], 4)}


def conformity(pairs):
    """How far hair follows a region where it narrows. `pairs` are (hair radius, body
    radius) down one lock, top to bottom, both from the rig's axis. Between the body's
    widest point and its narrowest below it, `follow` is the share of the body's
    narrowing the hair also makes: 1 hugs the contour, 0 is a vertical panel, negative
    stands away from it (the column). `gap_at_narrowest_m` is the hair's separation there.
    None when the body does not narrow along the lock."""
    if len(pairs) < 2:
        return None
    widest = max(range(len(pairs)), key=lambda i: pairs[i][1])
    below = pairs[widest:]
    narrowest = widest + min(range(len(below)), key=lambda i: below[i][1])
    narrowing = pairs[widest][1] - pairs[narrowest][1]
    if narrowing <= 1e-4:
        return None
    follow = (pairs[widest][0] - pairs[narrowest][0]) / narrowing
    return {"follow": round(follow, 3), "gap_at_narrowest_m": round(pairs[narrowest][0] - pairs[narrowest][1], 4),
            "narrowing_m": round(narrowing, 4)}


def _calibrated(calibration, key):
    entry = (calibration or {}).get("metrics", {}).get(key)
    return None if entry is None else entry["value"] * entry.get("margin", 1.0)


def evaluate(relationship, measured, calibration=None):
    """Findings for one declared relationship from its measurements:
    `measured` = {"distances": [...signed metres...], "locks": {name: [(hair_r, body_r), ...]}}.
    Returns (report, findings)."""
    region, kind = relationship["region"], relationship["relationship"]
    severity = relationship.get("severity", "warning")
    report = {"region": region, "relationship": kind, "separation": stats(measured.get("distances", []))}
    findings = []
    sep = report["separation"]
    if sep["count"] == 0:
        ## Nothing near a region it must clear is the point (a bare neck); nothing on a
        ## region it attaches to or drapes over is a wrong declaration or a missing part.
        if kind != "clearance":
            findings.append(_finding(region, kind, "advisory", "coverage", 0, None,
                                     "no part of the declared design regions meets %s: is the declaration right?" % region))
        return report, findings
    if kind == "attach":
        bound = _calibrated(calibration, "attach.max_gap_m")
        report["max_gap_bound_m"] = bound
        if bound is not None and sep["max_m"] > bound:
            findings.append(_finding(region, kind, "hard", "root_gap", sep["max_m"], bound,
                                     "hair stands off %s by %.4f m: disconnected roots" % (region, sep["max_m"])))
        return report, findings
    if sep["min_m"] < -PENETRATION_M:
        findings.append(_finding(region, kind, severity, "penetration", sep["min_m"], -PENETRATION_M,
                                 "hair is inside %s at rest (%.4f m)" % (region, sep["min_m"])))
    if kind == "drape":
        bound = _calibrated(calibration, "drape.p90_separation_m")
        report["p90_bound_m"] = bound
        if bound is not None and sep["p90_m"] > bound:
            findings.append(_finding(region, kind, severity, "separation", sep["p90_m"], bound,
                                     "hair floats over %s (p90 %.4f m)" % (region, sep["p90_m"])))
        follows = {}
        for name, pairs in sorted(measured.get("locks", {}).items()):
            c = conformity(pairs)
            if c is not None:
                follows[name] = c
        report["conformity"] = follows
        columns = sorted(n for n, c in follows.items() if c["follow"] < 0.0)
        if columns:
            findings.append(_finding(region, kind, severity, "nape_conformity", columns, "follow >= 0",
                                     "locks %s stand away from %s where it narrows: a sheet or column" % (columns, region)))
        floor = _calibrated(calibration, "drape.min_follow")
        if floor is not None:
            low = sorted(n for n, c in follows.items() if 0.0 <= c["follow"] < floor)
            if low:
                findings.append(_finding(region, kind, severity, "nape_conformity", low, ">= %.2f" % floor,
                                         "locks %s barely follow %s" % (low, region)))
    return report, findings


def attribute(failures, region_of):
    """Deformation integration: envelope failures counted by the anatomical region of the
    body vertex each one was nearest (`region_of`: body vertex -> region, classified at rest)."""
    counts = {}
    for failure in failures:
        region = region_of.get(failure.get("nearest_body")) or "unclassified"
        counts[region] = counts.get(region, 0) + 1
    return dict(sorted(counts.items()))


def _finding(region, relationship, severity, metric, value, threshold, message):
    return {"kind": KIND, "severity": severity, "region": region, "relationship": relationship,
            "metric": metric, "value": value, "threshold": threshold, "message": message}
