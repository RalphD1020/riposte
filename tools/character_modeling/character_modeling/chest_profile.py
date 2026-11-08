"""The anterior chest in side profile (CHARACTER-PHYSIQUE-ART-001): its own bounded system,
applied after the body's silhouette and touching nothing else.

A heroic thorax in profile is not a rounded mound: the chest is full immediately under the
clavicle, the pectoral is one broad mass from there down to a defined lower boundary that
turns back into the rib cage, and the deepest point is a plateau, never a single apex. The
profile is authored as landmarks (h = z / stature, front depth in centimetres at the
reference stature) per build anchor (the resolved muscularity `mass`: lean -1, reference 0,
strongman +1), evaluated with a monotone cubic (it never overshoots its landmarks, so no
new apex can appear between them). The correction is the authored profile minus the
protected baseline's measured front contour (`BASELINE`, the side-silhouette iteration of
2026-11-01), zero at the band's ends (the rib-cage return below, the neck above), and both
are interpolated linearly in mass and held at the anchors (no extrapolation). `metrics`
reads a front contour for the gates.

Pure Python: no Blender.
"""

from __future__ import annotations

from .interpolation import ANCHORS, linear_anchors, monotone

KIND = "chest_profile"
REFERENCE_STATURE_M = 1.80
## The band the chest system owns: the rib-cage return up to the neck.
BAND = (0.62, 0.84)
## The protected baseline's measured front silhouette (cm at 1.80 m) per anchor, h 0.62..0.84.
BASELINE_H = tuple(round(0.62 + 0.01 * i, 2) for i in range(23))
BASELINE = {
    -1.0: (11.8, 12.2, 12.8, 13.5, 14.2, 14.6, 15.4, 16.0, 16.6, 16.9, 17.1, 17.2, 17.3, 17.4, 17.4, 17.1, 16.4,
           15.4, 14.0, 12.0, 10.4, 9.1, 7.4),
    0.0: (13.2, 13.8, 14.7, 15.6, 16.6, 17.3, 18.2, 19.0, 19.7, 20.0, 20.2, 20.2, 20.2, 20.1, 19.9, 19.5, 18.6, 17.4,
          15.7, 13.4, 11.5, 9.9, 7.8),
    1.0: (15.5, 16.3, 17.4, 18.6, 19.8, 20.6, 21.7, 23.0, 23.9, 24.3, 24.5, 24.4, 24.2, 23.9, 23.6, 23.1, 21.9, 20.3,
          18.2, 15.4, 13.2, 11.3, 8.3),
}
## Landmarks (h, cm): the rib-cage return (0.62, held), the lower pectoral boundary (0.64 to
## 0.66, a tight turn), the mid pectoral (0.68 to 0.72), the upper pectoral maximum (0.74 to
## 0.78, the plateau), the clavicular transition (0.80 to 0.83) and the neck (0.84, held).
STUDIES = {
    "heroic_chest": {
        -1.0: ((0.62, 11.8), (0.64, 13.0), (0.66, 14.8), (0.68, 15.9), (0.70, 16.5), (0.72, 16.8), (0.74, 17.1),
               (0.76, 17.3), (0.78, 17.0), (0.80, 15.4), (0.81, 13.6), (0.82, 11.4), (0.83, 9.4), (0.84, 7.4)),
        0.0: ((0.62, 13.2), (0.64, 14.9), (0.66, 17.3), (0.68, 18.9), (0.70, 19.5), (0.72, 19.7), (0.74, 19.9),
              (0.76, 19.9), (0.78, 19.4), (0.80, 17.6), (0.81, 15.6), (0.82, 13.0), (0.83, 10.4), (0.84, 7.8)),
        1.0: ((0.62, 15.5), (0.64, 17.0), (0.66, 20.4), (0.68, 22.6), (0.70, 23.3), (0.72, 23.6), (0.74, 23.8),
              (0.76, 23.9), (0.78, 23.6), (0.80, 21.0), (0.81, 18.6), (0.82, 15.4), (0.83, 12.0), (0.84, 8.3)),
    },
    ## One chest for every build (2026-11-01): the lean anchor's square heroic contour
    ## (heroic_chest's lean landmarks, its plateau squared: 0.70-0.78 pulled 40% toward its
    ## deepest) is the master shape; each anchor is that shape scaled in depth from its own
    ## rib-cage return (lean 0.85: a smaller chest; reference 1.18; strongman 1.42: muscle
    ## volume, never a rounder or more projecting chest) with a linear correction meeting
    ## its baseline at the neck.
    "lean_master": {
        -1.0: ((0.62, 11.8), (0.64, 12.76), (0.66, 14.23), (0.68, 15.105), (0.70, 15.827), (0.72, 15.92), (0.74, 16.013),
               (0.76, 16.055), (0.78, 15.842), (0.80, 14.32), (0.81, 12.76), (0.82, 10.86), (0.83, 9.13), (0.84, 7.4)),
        0.0: ((0.62, 13.2), (0.64, 14.597), (0.66, 16.702), (0.68, 17.981), (0.70, 19.048), (0.72, 19.241), (0.74, 19.435),
              (0.76, 19.558), (0.78, 19.326), (0.80, 17.278), (0.81, 15.144), (0.82, 12.539), (0.83, 10.169), (0.84, 7.8)),
        1.0: ((0.62, 15.5), (0.64, 17.117), (0.66, 19.587), (0.68, 21.062), (0.70, 22.282), (0.72, 22.451), (0.74, 22.62),
              (0.76, 22.704), (0.78, 22.362), (0.80, 19.833), (0.81, 17.234), (0.82, 14.067), (0.83, 11.183), (0.84, 8.3)),
    },
    ## One chest shape, three sizes (2026-11-01, on lean_master): in profile the lean read
    ## flat and heroic and the reference and strongman as mounds, because their rise over
    ## the abdomen grew far faster than their bodies (lean 4.7 cm, reference 7.2, strongman
    ## 9.5). Lean is lean_master's lean exactly; reference and strongman are its rise above
    ## the rib-cage return times 1.2 and 1.4, the strongman's return recessed (0.58-0.62:
    ## his lower pectoral turns back into the rib cage instead of climbing from the
    ## abdomen), each with a linear correction meeting its baseline at the neck.
    "lean_master_v2": {
        -1.0: ((0.58, 11.3), (0.59, 11.4), (0.60, 11.5), (0.61, 11.6), (0.62, 11.8), (0.64, 12.76), (0.66, 14.23),
               (0.68, 15.105), (0.70, 15.827), (0.72, 15.92), (0.74, 16.013), (0.76, 16.055), (0.78, 15.842),
               (0.80, 14.32), (0.81, 12.76), (0.82, 10.86), (0.83, 9.13), (0.84, 7.4)),
        0.0: ((0.58, 12.3), (0.59, 12.4), (0.60, 12.6), (0.61, 12.9), (0.62, 13.2), (0.64, 14.341), (0.66, 16.094),
              (0.68, 17.133), (0.70, 17.989), (0.72, 18.089), (0.74, 18.19), (0.76, 18.23), (0.78, 17.963),
              (0.80, 16.126), (0.81, 14.248), (0.82, 11.963), (0.83, 9.881), (0.84, 7.8)),
        1.0: ((0.58, 13.8), (0.59, 14.0), (0.60, 14.15), (0.61, 14.35), (0.62, 14.6), (0.64, 15.931), (0.66, 17.977),
              (0.68, 19.189), (0.70, 20.187), (0.72, 20.304), (0.74, 20.422), (0.76, 20.468), (0.78, 20.157),
              (0.80, 18.013), (0.81, 15.823), (0.82, 13.157), (0.83, 10.728), (0.84, 8.3)),
    },
    ## The same shape with more fullness under the clavicle and a flatter plateau.
    "heroic_chest_full": {
        -1.0: ((0.62, 11.8), (0.64, 13.1), (0.66, 15.0), (0.68, 16.0), (0.70, 16.4), (0.72, 16.6), (0.74, 16.9),
               (0.76, 17.2), (0.78, 17.2), (0.80, 16.0), (0.81, 14.4), (0.82, 12.2), (0.83, 9.8), (0.84, 7.4)),
        0.0: ((0.62, 13.2), (0.64, 15.0), (0.66, 17.6), (0.68, 19.0), (0.70, 19.4), (0.72, 19.5), (0.74, 19.7),
              (0.76, 19.9), (0.78, 19.7), (0.80, 18.4), (0.81, 16.6), (0.82, 14.0), (0.83, 10.8), (0.84, 7.8)),
        1.0: ((0.62, 15.5), (0.64, 17.2), (0.66, 20.8), (0.68, 22.8), (0.70, 23.3), (0.72, 23.4), (0.74, 23.6),
              (0.76, 23.8), (0.78, 23.6), (0.80, 22.0), (0.81, 20.2), (0.82, 17.2), (0.83, 13.0), (0.84, 8.3)),
    },
}
## A study's band when it is not BAND: lean_master_v2 owns the lower chest from 0.58 (the
## strongman's lower pectoral starts there). Below 0.62 its baseline is BASELINE_LOW (the
## same protected measurement), so the studies on BAND keep their baseline exactly.
STUDY_BAND = {"lean_master_v2": (0.58, 0.84)}
BASELINE_LOW_H = (0.58, 0.59, 0.60, 0.61)
BASELINE_LOW = {-1.0: (11.3, 11.4, 11.5, 11.6), 0.0: (12.3, 12.4, 12.6, 12.9), 1.0: (13.8, 14.2, 14.6, 15.0)}
## Smoothing of the correction along h (a contour, never its sample corners).
SMOOTH_H = 0.006
## Metric readings: the plateau is where the front is within PLATEAU_CM of its deepest.
PLATEAU_CM = 0.4
UPPER_H = 0.80


def band(study):
    """The h band `study` owns."""
    return STUDY_BAND.get(study, BAND)


def _baseline_points(mass, low):
    points = list(zip(BASELINE_H, BASELINE[mass]))
    return list(zip(BASELINE_LOW_H, BASELINE_LOW[mass])) + points if low else points


def baseline(mass, h, study=None):
    """The protected baseline's front depth (cm) at h for muscularity `mass` (from
    BASELINE_LOW too when `study`'s band starts below BAND)."""
    low = band(study)[0] < BAND[0]
    return linear_anchors({a: monotone(_baseline_points(a, low), h) for a in ANCHORS}, mass)


def target(study, mass, h):
    """The authored front depth (cm) at h for muscularity `mass`."""
    anchors = STUDIES[study]
    return linear_anchors({a: monotone(anchors[a], h) for a in ANCHORS}, mass)


## The authored profile as the closed loop fits it (`chest_fit`): the monotone cubic is
## continuous in slope, not in curvature, and the landmarks' slopes rise unevenly (the lower
## pectoral climbs in two steps at 0.66-0.68), so the profile itself carries small kinks.
## A Gaussian along h this wide takes them off and leaves the plateau and the apex where
## they are; the lower turn and the clavicle's bend stay bends. Near the band's ends it
## departs from the profile (the neck end falls steeply), so the builder fades it out there.
## The builder adds only the difference (smoothed minus authored) to the open loop, so a
## body's own depth (its frame, its development) is never replaced by the profile's.
FIT_SMOOTH_H = 0.008


def smoothed_target(study, mass, h, sigma=FIT_SMOOTH_H, step=0.002):
    """The authored front depth (cm) at h, smoothed along h by a Gaussian of `sigma`
    (the profile held past the band's ends)."""
    import math
    lo, hi = band(study)
    total = weight = 0.0
    k = int(3 * sigma / step)
    for i in range(-k, k + 1):
        w = math.exp(-0.5 * (i * step / sigma) ** 2)
        total += w * target(study, mass, min(max(h + i * step, lo), hi))
        weight += w
    return total / weight


def correction(study, mass, h):
    """Target minus baseline (cm at the reference stature); zero outside the study's band."""
    lo, hi = band(study)
    if not lo < h < hi:
        return 0.0
    return target(study, mass, h) - baseline(mass, h, study)


def smoothed(study, mass, h, step=0.002):
    import math
    total = weight = 0.0
    k = int(3 * SMOOTH_H / step)
    for i in range(-k, k + 1):
        w = math.exp(-0.5 * (i * step / SMOOTH_H) ** 2)
        total += w * correction(study, mass, h + i * step)
        weight += w
    return total / weight


def problems(study):
    """Why a study cannot be used: unknown, anchors not lean/reference/strongman, landmarks
    unordered, or not meeting the baseline at the band's ends (the system would step)."""
    if study not in STUDIES:
        return ["unknown chest study %s (known: %s)" % (study, ", ".join(sorted(STUDIES)))]
    out = []
    anchors = STUDIES[study]
    if sorted(anchors) != [-1.0, 0.0, 1.0]:
        return ["%s: anchors must be lean -1, reference 0 and strongman +1" % study]
    for mass, points in sorted(anchors.items()):
        if any(b[0] <= a[0] for a, b in zip(points, points[1:])):
            out.append("%s %+.0f: landmark heights must increase" % (study, mass))
        if (points[0][0], points[-1][0]) != band(study):
            out.append("%s %+.0f: landmarks must span the band %s" % (study, mass, band(study)))
        for h, v in (points[0], points[-1]):
            if abs(v - baseline(mass, h, study)) > 1e-9:
                out.append("%s %+.0f: the landmark at h %.2f must equal the baseline" % (study, mass, h))
    return out


def metrics(hs, front):
    """Readings of a front contour (cm or any one unit) inside BAND: `apex_h` (deepest),
    `plateau` (the h span within PLATEAU_CM of the deepest: a mound is short, a heroic chest
    long), `upper_fullness` (depth at UPPER_H over the deepest), `convexity` (the largest
    negative second difference: the roundest bend) and `lower_turn` (the steepest rise per
    step below the apex: a defined lower boundary is steep)."""
    rows = [(h, v) for h, v in zip(hs, front) if BAND[0] <= h <= BAND[1] and v == v]
    apex_h, apex = max(rows, key=lambda r: r[1])
    span = [h for h, v in rows if v >= apex - PLATEAU_CM]
    upper = min(rows, key=lambda r: abs(r[0] - UPPER_H))[1]
    v = [r[1] for r in rows]
    convexity = max(-(v[i + 1] - 2 * v[i] + v[i - 1]) for i in range(1, len(v) - 1))
    below = [r for r in rows if r[0] <= apex_h]
    turn = max((b[1] - a[1]) for a, b in zip(below, below[1:])) if len(below) > 1 else 0.0
    return {"apex_h": apex_h, "plateau": round(max(span) - min(span), 3), "upper_fullness": round(upper / apex, 4),
            "convexity": round(convexity, 4), "lower_turn": round(turn, 4)}
