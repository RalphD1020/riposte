"""The heroic paneled mask (FACE-IDENTITY-001): the whole face as its own topology — named
control vertices in the head's chart, panels between them, a designed boundary where the
face joins the skull.

Chart: u = x / the head's half-width, v = height fraction from the chin, both of the
resolved head's construction surface, so the mask follows whatever head it is built on
(physique proportions, identity, stature). A control vertex is (u, v, lift, follow):
`lift` is metres out of the construction surface along its normal; `follow` (0..1) says
how much a panel touching it bends with the skull (0: the panel is the flat plane of its
corners, 1: it lies on the skull plus its lift). Boundary vertices sit on the skull
(lift 0, follow 1): the face boundary is a design boundary, not the edge of an object.

The composition, one surface from hairline to chin, wrapping into the temples and the
sides: the forehead rising into one protruding brow ridge across both eyes that descends
at the centre into a broad rectangular nose bridge (four corners); the bridge projects to
the nose peak, the face's forward point, and folds under into a simple nose base; a shelf
panel under the brow; hooded-eye panels under the shelf, bounded by the bridge inside and
the cheekbone outside; the cheekbones are vertices where the eye, shelf, nose-side, cheek
and temple panels converge, raised out of the recessed eye; below them the lower mask is
the original panel mask's broad convex surface — cheeks, mouth, jaw and chin with minimal
definition and its simple centre-line convergence.

Mask architecture parameters (`head_profile`: brow_strength, nose_projection,
cheekbone_depth, cheekbone_width, chin_projection) move named vertices, so a
broader or leaner head keeps the same design. Pure Python.
"""

from __future__ import annotations

import math

## (u, v, lift m, follow) of the +x side; u == 0 vertices are on the centre line.
CONTROL = {
    ## The boundary, on the skull: hairline, temples, the side plane, the jaw, under the chin.
    "hairline": (0.0, 0.92, 0.0, 1.0),
    "hairline_side": (0.40, 0.905, 0.0, 1.0),
    "temple_top": (0.74, 0.82, 0.0, 1.0),
    "temple_back": (0.90, 0.66, 0.0, 1.0),
    "side": (0.88, 0.50, 0.0, 1.0),
    "jaw_back": (0.74, 0.32, 0.0, 1.0),
    "jaw_angle": (0.50, 0.10, 0.0, 1.0),
    "jaw_low": (0.30, 0.04, 0.0, 1.0),
    "chin_low": (0.0, 0.03, 0.0, 1.0),
    ## The perimeter ring: where the face's convex field turns into the head (the original
    ## mask's continuous turn), from the forehead down the temples (through brow_tail and
    ## cheek_side) to the jaw and chin. Planar on the ring; the band outside follows the skull.
    "ring_top": (0.0, 0.835, 0.002, 0.0),
    "ring_forehead": (0.44, 0.815, 0.002, 0.0),
    "ring_temple": (0.76, 0.74, 0.002, 0.0),
    "jaw_ring": (0.62, 0.25, 0.001, 0.0),
    "chin_ring": (0.40, 0.08, 0.001, 0.0),
    ## Forehead and the brow ridge (the ridge line descends into the bridge's top corner).
    "forehead": (0.0, 0.79, 0.004, 0.8),
    "forehead_side": (0.50, 0.77, 0.002, 1.0),
    "brow_inner": (0.17, 0.66, 0.013, 0.0),
    "brow_mid": (0.38, 0.672, 0.012, 0.0),
    "brow_outer": (0.64, 0.655, 0.008, 0.0),
    "brow_tail": (0.82, 0.62, 0.002, 1.0),
    ## The shelf under the brow (the underside of the overhang).
    "shelf_inner": (0.15, 0.615, 0.006, 0.0),
    "shelf_mid": (0.36, 0.622, 0.005, 0.0),
    "shelf_outer": (0.60, 0.61, 0.003, 0.0),
    ## The hooded-eye panel (recessed under the shelf; corners from the eye landmarks).
    "eye_inner": (0.15, 0.545, 0.001, 0.0),
    "eye_low": (0.34, 0.505, 0.0, 0.0),
    "eye_outer": (0.53, 0.545, -0.001, 0.0),
    ## The rectangular bridge: the root between the brows, the top and bottom corners, the
    ## peak at the bottom of its front (the face's forward point), the nose base under it.
    "bridge_root": (0.0, 0.64, 0.012, 0.0),
    "bridge_top": (0.10, 0.635, 0.012, 0.0),
    "bridge_bottom": (0.115, 0.425, 0.015, 0.0),
    "nose_peak": (0.0, 0.405, 0.018, 0.0),
    "nose_wing": (0.17, 0.37, 0.006, 0.0),
    "nose_base": (0.0, 0.345, 0.008, 0.0),
    "nose_side": (0.23, 0.43, 0.006, 0.0),
    ## The cheekbone junction: raised out of the recessed eye, the turn into the lower mask.
    "cheekbone": (0.62, 0.45, 0.010, 0.0),
    "cheek_side": (0.73, 0.43, 0.002, 0.0),
    ## The lower mask: broad planes through the original mask's surface, a few mm proud of
    ## it (the field projects), through the cheeks, mouth and chin to the ring.
    "cheek_low": (0.38, 0.28, 0.003, 0.0),
    "mouth": (0.0, 0.22, 0.003, 0.0),
    "chin": (0.0, 0.09, 0.005, 0.0),
}
## The boundary loop of the +x side, from the top of the centre line to the bottom.
BOUNDARY = ("hairline", "hairline_side", "temple_top", "temple_back", "side", "jaw_back",
            "jaw_angle", "jaw_low", "chin_low")
## Panels of the +x side (mirrored): (region, (a, b, c)).
PANELS = (
    ("perimeter", ("hairline", "ring_top", "hairline_side")),
    ("perimeter", ("ring_top", "ring_forehead", "hairline_side")),
    ("perimeter", ("hairline_side", "ring_forehead", "temple_top")),
    ("perimeter", ("ring_forehead", "ring_temple", "temple_top")),
    ("perimeter", ("temple_top", "ring_temple", "temple_back")),
    ("perimeter", ("ring_temple", "brow_tail", "temple_back")),
    ("forehead", ("ring_top", "forehead", "ring_forehead")),
    ("forehead", ("forehead", "forehead_side", "ring_forehead")),
    ("forehead", ("forehead_side", "ring_temple", "ring_forehead")),
    ("brow", ("forehead", "bridge_root", "bridge_top")),
    ("brow", ("forehead", "bridge_top", "brow_inner")),
    ("brow", ("forehead", "brow_inner", "brow_mid")),
    ("brow", ("forehead", "brow_mid", "forehead_side")),
    ("brow", ("forehead_side", "brow_mid", "brow_outer")),
    ("brow", ("forehead_side", "brow_outer", "ring_temple")),
    ("temple", ("ring_temple", "brow_outer", "brow_tail")),
    ("shelf", ("bridge_top", "shelf_inner", "brow_inner")),
    ("shelf", ("brow_inner", "shelf_inner", "shelf_mid")),
    ("shelf", ("brow_inner", "shelf_mid", "brow_mid")),
    ("shelf", ("brow_mid", "shelf_mid", "shelf_outer")),
    ("shelf", ("brow_mid", "shelf_outer", "brow_outer")),
    ("shelf", ("brow_outer", "shelf_outer", "brow_tail")),
    ("shelf", ("shelf_outer", "cheekbone", "brow_tail")),
    ("eye", ("shelf_inner", "eye_inner", "eye_low")),
    ("eye", ("shelf_inner", "eye_low", "shelf_mid")),
    ("eye", ("shelf_mid", "eye_low", "eye_outer")),
    ("eye", ("shelf_mid", "eye_outer", "shelf_outer")),
    ("eye", ("shelf_outer", "eye_outer", "cheekbone")),
    ("eye", ("eye_inner", "nose_side", "eye_low")),
    ("eye", ("eye_low", "cheekbone", "eye_outer")),
    ("temple", ("brow_tail", "cheekbone", "cheek_side")),
    ("perimeter", ("brow_tail", "cheek_side", "side")),
    ("perimeter", ("brow_tail", "side", "temple_back")),
    ("bridge", ("bridge_root", "bridge_bottom", "bridge_top")),
    ("bridge", ("bridge_root", "nose_peak", "bridge_bottom")),
    ("bridge", ("bridge_top", "eye_inner", "shelf_inner")),
    ("bridge", ("bridge_top", "bridge_bottom", "eye_inner")),
    ("nose_side", ("eye_inner", "bridge_bottom", "nose_side")),
    ("nose_side", ("bridge_bottom", "nose_wing", "nose_side")),
    ("nose_side", ("eye_low", "nose_side", "cheekbone")),
    ("nose", ("nose_peak", "nose_wing", "bridge_bottom")),
    ("nose", ("nose_peak", "nose_base", "nose_wing")),
    ("cheek", ("nose_side", "nose_wing", "cheek_low")),
    ("cheek", ("nose_side", "cheek_low", "cheekbone")),
    ("cheek", ("cheekbone", "cheek_low", "jaw_ring")),
    ("cheek", ("cheekbone", "jaw_ring", "cheek_side")),
    ("lower_mask", ("nose_base", "mouth", "nose_wing")),
    ("lower_mask", ("nose_wing", "mouth", "cheek_low")),
    ("lower_mask", ("cheek_low", "mouth", "chin")),
    ("lower_mask", ("cheek_low", "chin", "chin_ring")),
    ("lower_mask", ("cheek_low", "chin_ring", "jaw_ring")),
    ("perimeter", ("cheek_side", "jaw_ring", "jaw_back")),
    ("perimeter", ("cheek_side", "jaw_back", "side")),
    ("perimeter", ("jaw_ring", "jaw_angle", "jaw_back")),
    ("perimeter", ("jaw_ring", "chin_ring", "jaw_angle")),
    ("perimeter", ("chin_ring", "jaw_low", "jaw_angle")),
    ("perimeter", ("chin", "jaw_low", "chin_ring")),
    ("perimeter", ("chin", "chin_low", "jaw_low")),
)
## The perimeter ring of the +x side, top to bottom: the field (inside) turns into the band.
RING = ("ring_top", "ring_forehead", "ring_temple", "brow_tail", "cheek_side", "jaw_ring", "chin_ring", "chin")
## The bridge's front: its four corners (a rectangle in the chart) around the root and the peak.
BRIDGE = ("bridge_top", "bridge_bottom")
## Refinement: each panel edge in this many segments, a convex swell inside each panel
## (metres per metre of the panel's size at its centre; nothing on its edges).
REFINE = 3
SWELL = 0.025
## Mask architecture: head parameter -> (vertices, lift per unit) or (vertices, (du, dv) per unit).
ARCHITECTURE = {
    "brow_strength": (("bridge_top", "brow_inner", "brow_mid", "brow_outer"), 0.004),
    "nose_projection": (("bridge_bottom", "nose_peak"), 0.005),
    "cheekbone_depth": (("cheekbone", "cheek_side"), 0.003),
    "chin_projection": (("chin",), 0.003),
}
## The jaw is the resolved head's own (the lower mask lies on its construction surface).
PLACEMENT = {
    "cheekbone_width": (("cheekbone",), (0.06, 0.0)),
}
## Foundation design studies (CHARACTER-FACE-ART-DIRECTION-001, HEAD-MORPHOLOGY-002):
## candidate revisions of the shared mask itself, never an identity parameter. 0 is the
## approved mask; a candidate names values in `parameters`. Each row moves its vertices by
## (du, dv) chart units and, when given, lifts them by dlift metres, per unit. Once one is
## approved its values are baked into CONTROL (with a new head approval and fingerprint)
## and its entry here is removed.
## `ridge_straight`: the crest's arch flattened onto the line from its inner to its outer
## vertex (1 = straight). `ridge_angle`: the outer ridge, shelf and tail lowered, the ridge
## descending outward. `edge_softness`: SOFTEN scaled by 1 + value (-0.5 halves the
## rounding: crisper planes, still soft).
## `anime_face` (2026-11-01): the paneled mask in anime proportion. The nose becomes a small
## pointed 3D wedge (the bridge narrowed to about half and lowered, its bottom corners
## drawn in so the tip stands forward of them, a narrow base and wings); the brow's
## projection lowered with the nose's; the hooded eye panel enlarged (lower eye line,
## raised shelf, wider corners, the cheekbone below) for large graphic eyes.
MASK_STUDY = {
    "ridge_straight": ((("brow_mid",), (0.0, -0.0142)), (("shelf_mid",), (0.0, -0.0090))),
    "ridge_angle": ((("brow_outer",), (0.0, -0.010)), (("shelf_outer",), (0.0, -0.007)), (("brow_tail",), (0.0, -0.006))),
    "anime_face": (
        (("bridge_root",), (0.0, 0.0, -0.004)),
        (("bridge_top",), (-0.045, 0.0, -0.004)),
        (("bridge_bottom",), (-0.07, 0.0, -0.007)),
        (("nose_peak",), (0.0, -0.005, -0.002)),
        (("nose_wing",), (-0.08, 0.015, -0.002)),
        (("nose_base",), (0.0, 0.0, -0.003)),
        (("nose_side",), (-0.07, 0.0, -0.002)),
        (("brow_inner", "brow_mid", "brow_outer"), (0.0, 0.0, -0.003)),
        (("shelf_inner",), (-0.04, 0.006, 0.0)),
        (("shelf_mid", "shelf_outer"), (0.0, 0.006, 0.0)),
        (("eye_inner",), (-0.04, -0.01, 0.0)),
        (("eye_low",), (0.0, -0.035, 0.0)),
        (("eye_outer",), (0.04, -0.015, 0.0)),
        (("cheekbone",), (0.02, -0.025, 0.0)),
    ),
    ## `anime_nose` (2026-11-01, on anime_face): the nose read as a thin slit, a long narrow
    ## ridge. A compact triangular wedge instead: the tip the most forward point, a little
    ## lower; the wings and the lower bridge wider than the bridge above (a base that tapers
    ## up), the lower bridge less raised (a short wedge, not a ridge from the brows); the base
    ## lifted so the underside is a small downward plane catching the shadow. The bridge's
    ## top and root (where the brow ridge starts) never move.
    "anime_nose": (
        (("nose_peak",), (0.0, -0.005, 0.004)),
        (("nose_wing",), (0.035, -0.005, 0.002)),
        (("nose_base",), (0.0, 0.0, 0.002)),
        (("bridge_bottom",), (0.012, 0.0, -0.002)),
        (("nose_side",), (0.01, 0.0, 0.0)),
    ),
    ## `face_integration` (2026-11-05, on anime_nose, for the heroic_cranium head): the face
    ## read as a mask of carved parts. Depth and follow only (no vertex moves in the chart,
    ## so the eye_recess and brow_ridge anchors, and the locked eyes and brows on them, keep
    ## their place), and nothing the brow lies on (the ridge, the shelf, the temple ring:
    ## easing the shelf bent the locked brow's ends 8 mm): the hooded-eye panel raised 1 mm
    ## toward the shelf so the orbit is a seat, not a rectangular cavity (2 mm uncovered an
    ## iris at half blink on the 1.60 m lean head, 4 mm on the 1.80 m); the forehead's ring
    ## follows the skull instead of folding at a planar edge; the lower cheek, the cheek side
    ## and the jaw ring fuller (cheek volume under the cheekbone, never hollow); a restrained
    ## mouth plane and a broad chin with forward projection; the nose a continuous wedge —
    ## the lower bridge raised into the tip and the tip projecting a little further (easing
    ## it back lost the profile), the wings and base wider and lifted so an underside plane
    ## carries the shadow, not a notch.
    "face_integration": (
        (("eye_inner", "eye_low", "eye_outer"), (0.0, 0.0, 0.001)),
        (("ring_forehead",), (0.0, 0.0, 0.0, 0.6)),
        (("cheek_low",), (0.0, 0.0, 0.003)),
        (("cheek_side", "jaw_ring", "chin_ring"), (0.0, 0.0, 0.002)),
        (("mouth",), (0.0, 0.0, 0.004)),
        (("chin",), (0.0, 0.0, 0.002)),
        (("bridge_bottom",), (0.0, 0.0, 0.006)),
        (("nose_peak",), (0.0, 0.0, 0.002)),
        (("nose_wing",), (0.01, 0.0, 0.003)),
        (("nose_base",), (0.0, 0.005, 0.003)),
    ),
}
EDGE_SOFTNESS = "edge_softness"
## Where an identity mark sits: a mark names an anchor, never a height. Each anchor is
## lines of control vertices (piecewise linear in the chart, held level past their ends);
## the anchor is their mean. `eye_recess`: midway between the shelf's lower edge and the
## eye panel's lower edge, inside the recessed hooded-eye panel. `brow_ridge`: the ridge's
## crest, the line where the brow plate turns into the shelf (softened, SOFT_EDGES), from
## where it meets the nose (the bridge's top corner) along the brow.
ANCHORS = {
    "eye_recess": (("shelf_inner", "shelf_mid", "shelf_outer"), ("eye_inner", "eye_low", "eye_outer")),
    "brow_ridge": (("bridge_top", "brow_inner", "brow_mid", "brow_outer"),),
}
## A ridge mark with `"inner": "ridge_start"` begins where its anchor begins (the brow at
## the bridge's top corner, where the ridge meets the nose); its outer end stays at
## x + width / 2. Its columns include every control vertex of the anchor between its ends,
## so its bottom edge bends exactly where the ridge does.
RIDGE_START = "ridge_start"


def anchor_shares(name):
    """Each of the anchor's lines' share of it (their mean)."""
    lines = ANCHORS[name]
    return tuple(1.0 / len(lines) for _line in lines)


def mark_span(mark, parameters=None):
    """A mark's (inner u, outer u) on its side: `inner` RIDGE_START pins the inner end to the
    start of its anchor's first line."""
    centre, half = mark["x"], mark["width"] / 2.0
    if mark.get("inner") == RIDGE_START:
        ## `inner_offset` (chart u) holds the inner end outside the bridge's edge line.
        start = control_points(parameters)[ANCHORS[mark["anchor"]][0][0]][0] + mark.get("inner_offset", 0.0)
        return start, centre + half
    return centre - half, centre + half


def column_us(mark, parameters=None):
    """A ridge mark's column positions (u, inner to outer): COLUMNS evenly across its span
    and every control vertex of its anchor strictly inside it."""
    inner, outer = mark_span(mark, parameters)
    controls = control_points(parameters)
    even = [inner + (outer - inner) * i / (COLUMNS - 1) for i in range(COLUMNS)]
    bends = [controls[n][0] for line in ANCHORS[mark["anchor"]] for n in line if inner < controls[n][0] < outer]
    return sorted(set(round(u, 12) for u in even + bends))


## Soft edges: the bridge and the brow ridge turn as rounded, semi-angular edges (as the
## nose tip does): each refined point on these panel edges moves SOFTEN of the way to the
## mean of its neighbours, the points around them half that, over SOFTEN_PASSES, and the
## faces there are shaded smooth (`soft_edges`, `soften`).
SOFT_EDGES = (("bridge_top", "brow_inner"), ("brow_inner", "brow_mid"), ("brow_mid", "brow_outer"),
              ("bridge_root", "bridge_top"), ("bridge_top", "bridge_bottom"), ("bridge_top", "shelf_inner"),
              ("bridge_top", "eye_inner"))
SOFTEN = 0.45
SOFTEN_PASSES = 2
## `lower_contour` (2026-11-06, candidate; HEAD-CONTOUR-001): the lower face's profile was
## planar panels meeting at single vertices — the chin a point where the chin plane meets
## the plane under it (a 30-40 degree corner in one 2 mm step), the jaw border a chain of
## panel corners (a dip behind the chin, then a step). These edges are rounded as the
## bridge is, over LOWER_SOFTEN_PASSES, scaled by the study's value: the chin's front, its
## turn under and its corner, and the border back to the jaw's corner. The cheek planes
## (cheek_low, jaw_ring) stay crisp; the boundary is held.
LOWER_CONTOUR = "lower_contour"
LOWER_SOFT_EDGES = (("mouth", "chin"), ("chin", "chin_low"), ("chin", "jaw_low"), ("chin", "chin_ring"),
                    ("chin_ring", "jaw_low"), ("chin_ring", "jaw_angle"))
LOWER_SOFTEN_PASSES = 4
## Boundary corners under the jaw that round with it (every other boundary vertex is held):
## jaw_low, held, pointed down below the border on both sides of it (the chin's pinch).
LOWER_FREE_BOUNDARY = ("chin_low", "jaw_low")


def soft_edges(edges=SOFT_EDGES):
    """`edges` (SOFT_EDGES) on both sides."""
    return sorted({tuple(sorted(e)) for a, b in edges for e in ((a, b), (mirrored(a), mirrored(b)))})


def soft_keys(points, edges=SOFT_EDGES):
    """The refined points (keys of `refined()`) lying on a soft edge, its ends included."""
    edges = [set(e) for e in soft_edges(edges)]
    return {key for key in points if any({name for name, _k in key} <= e for e in edges)}


def soften(positions, triangles, keys, fixed=frozenset(), parameters=None, amount=None, passes=SOFTEN_PASSES):
    """`positions` ({key: (x, y, z)}) with the soft points `keys` rounded (`amount`, by
    default SOFTEN scaled by the `edge_softness` study, toward their neighbours' mean, their
    neighbours half that, `passes` times); `fixed` never move."""
    if amount is None:
        amount = SOFTEN * (1.0 + (parameters or {}).get(EDGE_SOFTNESS, 0.0))
    neighbours = {}
    for _region, tri in triangles:
        for a in tri:
            neighbours.setdefault(a, set()).update(b for b in tri if b != a)
    ring = {n for k in keys for n in neighbours[k]} - set(keys)
    weights = {k: amount * 0.5 for k in ring}
    weights.update({k: amount for k in keys})
    out = dict(positions)
    for _pass in range(passes):
        step = dict(out)
        for key, weight in weights.items():
            if key in fixed:
                continue
            around = neighbours[key]
            mean = [sum(out[n][i] for n in around) / len(around) for i in range(3)]
            step[key] = tuple(out[key][i] + (mean[i] - out[key][i]) * weight for i in range(3))
        out = step
    return out
## Columns across a ridge mark's width (outward, -0.5..0.5): each its own surface frame.
COLUMNS = 13
SIDES = ("L", "R")


def mirrored(name):
    """The -x twin of a +x control name (centre-line names are their own twin)."""
    if name.endswith(".R"):
        return name[:-2]
    return name if CONTROL[name][0] == 0.0 else name + ".R"


def control_points(parameters=None):
    """Both sides' control vertices, {name or name.R: (u_signed, v, lift, follow)}, with the
    head's mask architecture applied. Centre-line vertices are shared."""
    parameters = parameters or {}
    points = {name: list(value) for name, value in CONTROL.items()}
    for key, (names, lift) in ARCHITECTURE.items():
        for name in names:
            points[name][2] += lift * parameters.get(key, 0.0)
    moves = [(key, names, delta) for key, (names, delta) in PLACEMENT.items()]
    moves += [(key, names, delta) for key, rows in MASK_STUDY.items() for names, delta in rows]
    for key, names, delta in moves:
        amount = parameters.get(key, 0.0)
        for name in names:
            points[name][0] += delta[0] * amount
            points[name][1] += delta[1] * amount
            if len(delta) > 2:
                points[name][2] += delta[2] * amount
            if len(delta) > 3:
                points[name][3] = min(1.0, max(0.0, points[name][3] + delta[3] * amount))
    out = {}
    for name, (u, v, lift, follow) in points.items():
        out[name] = (u, v, lift, follow)
        if CONTROL[name][0] > 0.0:
            out[name + ".R"] = (-u, v, lift, follow)
    return out


def anchor_v(name, u, parameters=None):
    """The anchor's height (chart v) at |u|."""
    controls = control_points(parameters)
    return sum(share * line_at([controls[n][:2] for n in line], u)
               for line, share in zip(ANCHORS[name], anchor_shares(name)))


def line_at(points, u):
    """A control line [(u, value)] at |u|: piecewise linear, held level past its ends
    (`value` a chart height or a point)."""
    u = abs(u)
    if u <= points[0][0]:
        return points[0][1]
    for (u0, v0), (u1, v1) in zip(points, points[1:]):
        if u <= u1:
            return v0 + (v1 - v0) * ((u - u0) / (u1 - u0))
    return points[-1][1]


def _interpolate(samples, t):
    t = max(samples[0][0], min(samples[-1][0], t))
    for (t0, a), (t1, b) in zip(samples, samples[1:]):
        if t0 <= t <= t1:
            return a + (b - a) * (t - t0) / (t1 - t0)
    return samples[-1][1]


def resolve_mark(mark, aspect, parameters=None):
    """A mark resolved onto the mask (FACE-MAPPING-001), in its neutral placement. A mark
    with an `anchor` gets `z`, the anchor's height at its centre, and its tilt (`tilt_deg`,
    and `tilt_by_side`) becomes the anchor's chord across the mark's width (`chord_deg`)
    plus the mark's own tilt.

    A ridge mark (a brow: it has a `profile`) is attached by its bottom contour: `columns`,
    per side, (t, u, v_bottom, v_top, v_anchor) at `column_us` outward across its span
    (`mark_span`; the resolved `x` and `width` are the span's), the bottom on the anchor's
    line at each u (offset only by the mark's own `lift`), the top contour designed
    independently as the profile's thickness (a fraction of `height`) above it, turned by the
    mark's own tilt and its side's (the approved asymmetry lives in the top contour). Every
    column is fitted to the surface on its own frame by the builder, so the brow follows the
    ridge's curvature and direction. Expressions are the eye assembly's channels
    (FACE-EXPRESSION-001), never a re-resolved mark. `aspect`: the chart's height over its
    half-width (a tilt is an angle on the head, not in the chart). A mark without an anchor
    is returned unchanged."""
    if "anchor" not in mark:
        return dict(mark)
    start, end = mark_span(mark, parameters)
    centre, half = 0.5 * (start + end), 0.5 * (end - start)
    width = end - start
    inner = anchor_v(mark["anchor"], centre - half, parameters)
    outer = anchor_v(mark["anchor"], centre + half, parameters)
    chord = math.degrees(math.atan2((outer - inner) * aspect, 2.0 * half))
    out = dict(mark, z=anchor_v(mark["anchor"], centre, parameters), tilt_deg=chord + mark.get("tilt_deg", 0.0), chord_deg=chord)
    if "tilt_by_side" in mark:
        out["tilt_by_side"] = {side: chord + tilt for side, tilt in mark["tilt_by_side"].items()}
    if "profile" in mark:
        out.update(x=centre, width=width)
        columns = {}
        for side in SIDES:
            own = math.tan(math.radians(mark.get("tilt_deg", 0.0) + mark.get("tilt_by_side", {}).get(side, 0.0)))
            rows = []
            for u in column_us(mark, parameters):
                t = (u - centre) / width
                anchor = anchor_v(mark["anchor"], u, parameters)
                bottom = anchor + mark.get("lift", 0.0)
                thick = _interpolate(mark["profile"], t) * mark["height"]
                rows.append((t, u, bottom, bottom + thick + own * t * width / aspect, anchor))
            columns[side] = rows
        out["columns"] = columns
    return out


def resolve_marks(marks, aspect, parameters=None):
    return {kind: resolve_mark(mark, aspect, parameters) for kind, mark in marks.items()}


def panels():
    """Both sides' panels, (region, (a, b, c)), each wound counter-clockwise in (u, v)."""
    out = list(PANELS) + [(region, tuple(mirrored(c) for c in corners)) for region, corners in PANELS]
    controls = control_points()
    wound = []
    for region, (a, b, c) in out:
        (ua, va), (ub, vb), (uc, vc) = (controls[n][:2] for n in (a, b, c))
        area = (ub - ua) * (vc - va) - (uc - ua) * (vb - va)
        wound.append((region, (a, b, c) if area > 0.0 else (a, c, b)))
    return wound


def edges():
    """Every panel edge once (the panel boundaries: where the face may turn)."""
    seen = set()
    for _region, (a, b, c) in panels():
        for p, q in ((a, b), (b, c), (c, a)):
            seen.add(tuple(sorted((p, q))))
    return sorted(seen)


def boundary_loop():
    """The closed boundary, both sides: down the +x side, back up the -x side."""
    return list(BOUNDARY) + [mirrored(n) for n in reversed(BOUNDARY[1:-1])]


def refined(n=REFINE):
    """The panels refined into n x n triangles each: (points, triangles). A point is keyed
    canonically by its weights on the control vertices — ((name, k), ...) with k/n the
    weight — so a point on a shared panel edge is one point for both panels. `points`
    maps key -> (weights {name: w}, swell: 27 * w1 * w2 * w3 of its panel, 0 on edges,
    region). Triangles keep the panel's winding."""
    points, triangles = {}, []
    for region, corners in panels():
        grid = {}
        for i in range(n + 1):
            for j in range(n + 1 - i):
                k = n - i - j
                ks = (i, j, k)
                key = tuple(sorted((corners[m], ks[m]) for m in range(3) if ks[m]))
                weights = {corners[m]: ks[m] / n for m in range(3) if ks[m]}
                points.setdefault(key, (weights, 27.0 * (i / n) * (j / n) * (k / n), region))
                grid[(i, j)] = key
        for i in range(n):
            for j in range(n - i):
                triangles.append((region, (grid[(i + 1, j)], grid[(i, j + 1)], grid[(i, j)])))
                if i + j < n - 1:
                    triangles.append((region, (grid[(i + 1, j)], grid[(i + 1, j + 1)], grid[(i, j + 1)])))
    return points, triangles
