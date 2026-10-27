"""Diagnostics for a captured study mesh. Evidence for a person, never a verdict.

Every function reads a ``MeshData`` and landmarks and returns plain data. No
function changes geometry. The layers stay separate on purpose: a mesh can
have smooth normals and a polygonal outline, or intended facets and a clean
outline.

    integrity      boundaries, non-manifold edges, degenerate faces, components, winding
    symmetry       mirrored-vertex distance and left/right section widths
    sections       width, depth, area and centre at landmark stations
    outlines       corners on the silhouette projected through fixed views
    creases        dihedral-angle edges grouped into clusters per region
    offsets        EXPERIMENTAL dents against a smoothed copy; ranking only

A finding names the region, kind, severity, coordinates, the evidence, and
the view that can verify it. ``diff`` separates existing defects from new
ones against a frozen control.
"""

from __future__ import annotations

import math

from . import anatomy, outline, regions
from .mesh_data import capture_mesh

_VIEW_FOR_REGION = {
    "head_face": "quarter", "head_crown": "side", "head_jaw": "quarter", "neck": "side",
    "chest": "front", "abdomen": "front", "back_upper": "rear", "back_lower": "rear",
    "shoulder": "quarter", "upper_arm": "front", "forearm": "front", "hand": "front",
    "pelvis": "front", "glute": "side", "thigh": "front", "calf": "side", "foot": "side",
}


def _finding(kind, region, severity, at, evidence, view=None, label=None, experimental=False):
    view = view or _VIEW_FOR_REGION.get(region, "front")
    return {
        "kind": kind,
        "region": region,
        "label": label or region,
        "severity": severity,
        "at": [round(c, 4) for c in at],
        "view": view,
        "evidence": evidence,
        "verify": "%s view, clay and grazing light" % view,
        "experimental": experimental,
    }


# --- integrity ---------------------------------------------------------------

def integrity(mesh, degenerate_area=1e-10):
    edges = mesh.edges()
    _normals, areas = mesh.face_normals()
    boundary = sum(1 for uses in edges.values() if len(uses) == 1)
    nonmanifold = sum(1 for uses in edges.values() if len(uses) > 2)
    flipped = sum(1 for uses in edges.values() if len(uses) == 2 and uses[0][1] == uses[1][1])
    degenerate = sum(1 for a in areas if a < degenerate_area)
    parent = list(range(len(mesh.faces)))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for uses in edges.values():
        first = root(uses[0][0])
        for face, _forward in uses[1:]:
            other = root(face)
            if other != first:
                parent[other] = first
    components = len({root(i) for i in range(len(mesh.faces))})
    return {
        "boundary_edges": boundary,
        "nonmanifold_edges": nonmanifold,
        "inconsistent_winding_edges": flipped,
        "degenerate_faces": degenerate,
        "components": components,
    }


def integrity_findings(report, expected_components):
    problems = {key: value for key, value in report.items() if key != "components" and value}
    if report["components"] != expected_components:
        problems["components"] = report["components"]
    if not problems:
        return []
    return [_finding("integrity", "mesh", "high", (0.0, 0.0, 0.0), problems, view="wire")]


# --- symmetry ----------------------------------------------------------------

def symmetry(mesh, cell=0.005):
    grid = {}
    for index, (x, y, z) in enumerate(mesh.vertices):
        grid.setdefault((int(math.floor(x / cell)), int(math.floor(y / cell)), int(math.floor(z / cell))), []).append(index)
    verts = mesh.vertices
    worst, worst_at, total = 0.0, None, 0.0
    for x, y, z in verts:
        mx = -x
        key = (int(math.floor(mx / cell)), int(math.floor(y / cell)), int(math.floor(z / cell)))
        best = math.inf
        for reach in (1, 2, 4):
            for dx in range(-reach, reach + 1):
                for dy in range(-reach, reach + 1):
                    for dz in range(-reach, reach + 1):
                        for k in grid.get((key[0] + dx, key[1] + dy, key[2] + dz), ()):
                            vx, vy, vz = verts[k]
                            d = (vx - mx) ** 2 + (vy - y) ** 2 + (vz - z) ** 2
                            if d < best:
                                best = d
            if best <= (reach * cell) ** 2:
                break
        best = math.sqrt(best)
        total += best
        if best > worst:
            worst, worst_at = best, (x, y, z)
    return {"mirror_max_dev_m": round(worst, 6), "mirror_mean_dev_m": round(total / max(1, len(verts)), 6),
            "mirror_worst_at": [round(c, 4) for c in worst_at] if worst_at else None}


# --- sections ----------------------------------------------------------------

def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _unit(a):
    length = math.sqrt(_dot(a, a))
    return (a[0] / length, a[1] / length, a[2] / length)


def _point_in_polygon(u, v, poly):
    inside = False
    for (u0, v0), (u1, v1) in zip(poly, poly[1:] + poly[:1]):
        if (v0 > v) != (v1 > v) and u < u0 + (v - v0) * (u1 - u0) / (v1 - v0):
            inside = not inside
    return inside


def slice_section(mesh, origin, normal, axis_u, triangles=None):
    """The closed section loop around ``origin`` in the plane (origin, normal).

    Returns width (extent along ``axis_u``), depth (extent along the in-plane
    perpendicular), area, centre offset, or None when no loop encloses or
    approaches the origin.
    """
    normal = _unit(normal)
    axis_u = _unit(_sub(axis_u, tuple(c * _dot(axis_u, normal) for c in normal)))
    axis_v = _cross(normal, axis_u)
    verts = mesh.vertices
    side = {}

    def signed(i):
        value = side.get(i)
        if value is None:
            value = _dot(_sub(verts[i], origin), normal)
            side[i] = value
        return value

    point_of = {}
    links = {}
    for _face, a, b, c in (triangles if triangles is not None else mesh.triangles()):
        crossing = []
        for p, q in ((a, b), (b, c), (c, a)):
            sp, sq = signed(p), signed(q)
            if (sp < 0.0) != (sq < 0.0):
                key = (p, q) if p < q else (q, p)
                if key not in point_of:
                    t = sp / (sp - sq)
                    vp, vq = verts[p], verts[q]
                    world = (vp[0] + (vq[0] - vp[0]) * t, vp[1] + (vq[1] - vp[1]) * t, vp[2] + (vq[2] - vp[2]) * t)
                    rel = _sub(world, origin)
                    point_of[key] = (_dot(rel, axis_u), _dot(rel, axis_v))
                crossing.append(key)
        if len(crossing) == 2:
            links.setdefault(crossing[0], []).append(crossing[1])
            links.setdefault(crossing[1], []).append(crossing[0])
    loops, seen = [], set()
    for start in links:
        if start in seen:
            continue
        loop, previous, current = [], None, start
        while current not in seen:
            seen.add(current)
            loop.append(point_of[current])
            following = [k for k in links[current] if k != previous and k not in seen]
            if not following:
                break
            previous, current = current, following[0]
        if len(loop) >= 3:
            loops.append(loop)
    if not loops:
        return None
    chosen = [loop for loop in loops if _point_in_polygon(0.0, 0.0, loop)]
    if chosen:
        loop = min(chosen, key=lambda lp: abs(_area(lp)))
    else:
        loop = min(loops, key=lambda lp: min(u * u + v * v for u, v in lp))
    us = [p[0] for p in loop]
    vs = [p[1] for p in loop]
    area = abs(_area(loop))
    cu = sum(us) / len(us)
    cv = sum(vs) / len(vs)
    return {"width": max(us) - min(us), "depth": max(vs) - min(vs), "area": area,
            "center_u": cu, "center_v": cv, "enclosed": bool(chosen)}


def _area(loop):
    return 0.5 * sum(u0 * v1 - u1 * v0 for (u0, v0), (u1, v1) in zip(loop, loop[1:] + loop[:1]))


def _triangles_near(mesh, a, b, radius):
    """Triangles with a vertex within ``radius`` of segment a-b (a cheap pre-filter)."""
    ab = _sub(b, a)
    length2 = _dot(ab, ab)
    near = []
    for v in mesh.vertices:
        t = max(-0.1, min(1.1, _dot(_sub(v, a), ab) / length2))
        q = (a[0] + ab[0] * t, a[1] + ab[1] * t, a[2] + ab[2] * t)
        near.append(_dot(_sub(v, q), _sub(v, q)) <= radius * radius)
    return [tri for tri in mesh.triangles() if near[tri[1]] or near[tri[2]] or near[tri[3]]]


def _limb_series(mesh, a, b, fractions, radius):
    tris = _triangles_near(mesh, a, b, radius)
    direction = _unit(_sub(b, a))
    lateral = _cross(direction, (0.0, 1.0, 0.0))
    if _dot(lateral, lateral) < 1e-9:
        lateral = (1.0, 0.0, 0.0)
    out = []
    for f in fractions:
        point = tuple(a[k] + (b[k] - a[k]) * f for k in range(3))
        section = slice_section(mesh, point, direction, lateral, tris)
        if section is not None:
            section.update(s=round(f, 4), at=[round(c, 4) for c in point])
            out.append(section)
    return out


def _fractions(lo, hi, step):
    count = int(round((hi - lo) / step))
    return [lo + step * k for k in range(count + 1)]


def sections(mesh, landmarks):
    """Station series for the torso and each limb, left and right."""
    yc = landmarks["torso_center_y"]
    z0 = landmarks["crotch_z"] + 0.03
    z1 = min(landmarks["shoulder_z"] - 0.12, landmarks["chest_z"] + 0.06)
    buckets = {}
    for tri in mesh.triangles():
        zs = (mesh.vertices[tri[1]][2], mesh.vertices[tri[2]][2], mesh.vertices[tri[3]][2])
        for key in range(int(math.floor(min(zs) / 0.01)), int(math.floor(max(zs) / 0.01)) + 1):
            buckets.setdefault(key, []).append(tri)
    torso = []
    for z in _fractions(z0, z1, 0.01):
        section = slice_section(mesh, (0.0, yc, z), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0),
                                buckets.get(int(math.floor(z / 0.01)), []))
        if section is not None:
            section.update(s=round(z, 4), at=[0.0, round(yc, 4), round(z, 4)])
            torso.append(section)
    series = {"torso": torso}
    for side in ("L", "R"):
        j = landmarks["joints"][side]
        series["upper_arm." + side] = _limb_series(mesh, j["shoulder"], j["elbow"], _fractions(0.3, 0.95, 0.05), 0.12)
        series["forearm." + side] = _limb_series(mesh, j["elbow"], j["wrist"], _fractions(0.08, 0.92, 0.06), 0.10)
        series["thigh." + side] = _limb_series(mesh, j["hip"], j["knee"], _fractions(0.25, 0.95, 0.05), 0.14)
        series["calf." + side] = _limb_series(mesh, j["knee"], j["ankle"], _fractions(0.06, 0.94, 0.06), 0.11)
    return series


def zigzag(values, prominence):
    """Significant interior turning points: [(index, 'max' | 'min')]."""
    pivots = []
    if len(values) < 3:
        return pivots
    hi = lo = 0
    trend = 0
    for i, v in enumerate(values):
        if v > values[hi]:
            hi = i
        if v < values[lo]:
            lo = i
        if trend >= 0 and values[hi] - v >= prominence and (trend == 1 or hi > lo):
            pivots.append((hi, "max"))
            trend, lo = -1, i
        elif trend <= 0 and v - values[lo] >= prominence and (trend == -1 or lo > hi):
            pivots.append((lo, "min"))
            trend, hi = 1, i
    return [p for p in pivots if 0 < p[0] < len(values) - 1]


def shelves(values, absolute, median_factor):
    """Indices where the profile's curvature spikes: a step or a ledge."""
    if len(values) < 5:
        return []
    d2 = [values[i - 1] - 2.0 * values[i] + values[i + 1] for i in range(1, len(values) - 1)]
    mags = sorted(abs(x) for x in d2)
    median = mags[len(mags) // 2]
    limit = max(absolute, median_factor * median)
    out = []
    for k, x in enumerate(d2):
        if abs(x) <= limit:
            continue
        if k > 0 and abs(d2[k - 1]) > abs(x):
            continue
        if k + 1 < len(d2) and abs(d2[k + 1]) >= abs(x):
            continue
        out.append((k + 1, x))
    return out


def section_findings(series, landmarks=None):
    findings = []

    def torso_region(row, metric):
        if landmarks is None:
            return None
        x, yc, z = row["at"]
        y = yc - 0.01 if metric == "width" else yc + 0.01
        return anatomy.classify((x, y, z), landmarks)[0]

    def check(name, rows, metric, spec):
        values = [row[metric] for row in rows]
        pivots = zigzag(values, spec["prominence_m"])
        maxima = [p for p in pivots if p[1] == "max"]
        minima = [p for p in pivots if p[1] == "min"]
        fixed = spec["region"]

        def region_at(index):
            return (torso_region(rows[index], metric) if name == "torso" else None) or fixed
        # The intended bellies are the fullest maxima and the intended waists the
        # narrowest minima; every other significant turning point is reported.
        allowed = spec["max_interior_maxima"]
        for index, _kind in sorted(maxima, key=lambda p: -values[p[0]])[allowed:]:
            findings.append(_finding("section_extra_belly", region_at(index), "medium", rows[index]["at"],
                                     {"series": name, "metric": metric, "station": rows[index]["s"],
                                      "maxima": len(maxima), "expected": allowed}))
        allowed = spec["max_interior_minima"]
        for index, _kind in sorted(minima, key=lambda p: values[p[0]])[allowed:]:
            findings.append(_finding("section_dip", region_at(index), "medium", rows[index]["at"],
                                     {"series": name, "metric": metric, "station": rows[index]["s"],
                                      "minima": len(minima), "expected": allowed}))
        for index, curvature in shelves(values, regions.SHELF_ABS_M, regions.SHELF_MEDIAN_FACTOR):
            findings.append(_finding("section_shelf", region_at(index), "medium", rows[index]["at"],
                                     {"series": name, "metric": metric, "station": rows[index]["s"],
                                      "curvature_m": round(curvature, 5)}))

    specs = regions.SECTION_SERIES
    torso = series.get("torso", [])
    if torso:
        check("torso", torso, "width", specs["torso_width"])
        check("torso", torso, "depth", specs["torso_depth"])
    for name, rows in series.items():
        base = name.split(".")[0]
        if base in specs and rows:
            check(name, rows, "width", specs[base])
            check(name, rows, "depth", specs[base])
    for base in ("upper_arm", "forearm", "thigh", "calf"):
        left, right = series.get(base + ".L", []), series.get(base + ".R", [])
        for a, b in zip(left, right):
            gap = abs(a["width"] - b["width"])
            if gap > regions.MIRROR_TOLERANCE_M:
                findings.append(_finding("section_asymmetry", base, "high", a["at"],
                                         {"station": a["s"], "left_width": round(a["width"], 4),
                                          "right_width": round(b["width"], 4)}))
                break
    return findings


# --- outlines ----------------------------------------------------------------

def _exempt_vertices(mesh):
    exempt = set()
    for flag in regions.EXEMPT_FACE_FLAGS:
        for index in mesh.face_flags.get(flag, ()):
            exempt.update(mesh.faces[index])
    return exempt


def outlines(mesh, labels, views=tuple(outline.VIEWS), cell=outline.DEFAULT_CELL):
    """Per view: projected area, 64 reproduction samples, and corner findings."""
    exempt = _exempt_vertices(mesh)
    out, findings = {}, []
    for view in views:
        raster = outline.project(mesh, view, cell)
        loop = outline.outer_loop(raster)
        samples = outline.resample(loop, regions.OUTLINE_STEP_M)
        window = regions.OUTLINE_WINDOW
        corners = outline.corners(samples, window, math.radians(20.0))
        kept = 0
        for corner in corners:
            i = corner["index"]
            owner = samples[i][2]
            if owner < 0 or owner in exempt:
                continue
            region, confidence, neighbour = labels[owner]
            policy = regions.policy(region)
            limit = policy["outline_convex_deg"] if corner["convex"] else policy["outline_concave_deg"]
            turn = math.degrees(abs(corner["turn_rad"]))
            if turn < limit:
                continue
            if not corner["convex"]:
                left = labels[samples[(i - 2 * window) % len(samples)][2]][0]
                right = labels[samples[(i + 2 * window) % len(samples)][2]][0]
                pairs = {frozenset((region, left)), frozenset((region, right)), frozenset((left, right))}
                if neighbour is not None:
                    pairs.add(frozenset((region, neighbour)))
                if pairs & anatomy.JUNCTIONS:
                    continue
            severity = "high" if turn >= regions.HIGH_FACTOR * limit else "medium"
            kind = "outline_corner" if corner["convex"] else "outline_notch"
            findings.append(_finding(kind, region, severity, mesh.vertices[owner],
                                     {"turn_deg": round(turn, 1),
                                      "isolation_deg": round(math.degrees(corner["isolation_rad"]), 1),
                                      "confidence": confidence},
                                     view=view, label=anatomy.label(labels[owner])))
            kept += 1
        perimeter = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(loop, loop[1:] + loop[:1]))
        out[view] = {"area_m2": round(raster.area(), 6),
                     "perimeter_m": round(perimeter, 4), "samples": outline.sample_points(loop),
                     "corners_considered": len(corners), "corners_reported": kept}
    return out, findings


# --- creases -----------------------------------------------------------------

def crease_clusters(mesh, labels):
    """Edges bent past their region's threshold, grouped by shared vertices."""
    normals, _areas = mesh.face_normals()
    verts = mesh.vertices
    exempt_faces = set()
    for flag in regions.EXEMPT_FACE_FLAGS:
        exempt_faces.update(mesh.face_flags.get(flag, ()))
    flagged = []
    hidden = mesh.hidden
    for (a, b), uses in mesh.edges().items():
        if len(uses) != 2 or a in hidden or b in hidden:
            continue
        fa, fb = uses[0][0], uses[1][0]
        if fa in exempt_faces or fb in exempt_faces:
            continue
        cosine = max(-1.0, min(1.0, _dot(normals[fa], normals[fb])))
        angle = math.degrees(math.acos(cosine))
        region = labels[a][0]
        if angle >= regions.policy(region)["dihedral_deg"]:
            flagged.append((a, b, angle))
    parent = {}

    def root(i):
        parent.setdefault(i, i)
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for a, b, _angle in flagged:
        ra, rb = root(a), root(b)
        if ra != rb:
            parent[rb] = ra
    groups = {}
    for edge in flagged:
        groups.setdefault(root(edge[0]), []).append(edge)
    clusters = []
    for edges in groups.values():
        length = peak = 0.0
        weighted = [0.0, 0.0, 0.0]
        tally = {}
        peak_at = None
        for a, b, angle in edges:
            pa, pb = verts[a], verts[b]
            seg = math.dist(pa, pb)
            length += seg
            mid = tuple((pa[k] + pb[k]) * 0.5 for k in range(3))
            for k in range(3):
                weighted[k] += mid[k] * seg
            tally[labels[a][0]] = tally.get(labels[a][0], 0.0) + seg
            if angle > peak:
                peak, peak_at = angle, (a, mid)
        region = max(tally, key=tally.get)
        clusters.append({
            "region": region,
            "label": anatomy.label(labels[peak_at[0]]),
            "edges": len(edges),
            "length_m": round(length, 4),
            "peak_deg": round(peak, 2),
            "mean_deg": round(sum(e[2] for e in edges) / len(edges), 2),
            "centroid": [round(c / length, 4) for c in weighted] if length else list(peak_at[1]),
            "peak_at": [round(c, 4) for c in peak_at[1]],
        })
    clusters.sort(key=lambda c: (-c["peak_deg"] * c["length_m"]))
    return clusters


def crease_findings(clusters):
    findings = []
    for cluster in clusters:
        threshold = regions.policy(cluster["region"])["dihedral_deg"]
        if cluster["peak_deg"] >= regions.HIGH_FACTOR * threshold or cluster["length_m"] >= regions.HIGH_LENGTH_M:
            severity = "high"
        elif cluster["length_m"] < regions.LOW_LENGTH_M:
            severity = "low"
        else:
            severity = "medium"
        findings.append(_finding("crease_cluster", cluster["region"], severity, cluster["centroid"],
                                 {k: cluster[k] for k in ("edges", "length_m", "peak_deg", "mean_deg", "peak_at")},
                                 label=cluster["label"]))
    return findings


# --- experimental offsets ----------------------------------------------------

def offset_dents(mesh, labels):
    """EXPERIMENTAL. Vertices sitting inside a smoothed copy, clustered.

    Smoothing is not an anatomical ground truth: it erases intended relief
    and the face ridge. These are ranking signals only. ``corroborate`` marks
    the ones another layer also sees.
    """
    neighbors = mesh.vertex_neighbors()
    exempt = _exempt_vertices(mesh)
    depth = offset_depths(mesh, neighbors)
    dented = {i for i, d in enumerate(depth)
              if d <= -regions.OFFSET_DENT_M and i not in exempt and i not in mesh.hidden}
    _normals, face_areas = mesh.face_normals()
    vertex_area = [0.0] * len(mesh.vertices)
    for index, face in enumerate(mesh.faces):
        share = face_areas[index] / len(face)
        for vi in face:
            vertex_area[vi] += share
    seen, clusters = set(), []
    for start in dented:
        if start in seen:
            continue
        stack, members = [start], []
        seen.add(start)
        while stack:
            i = stack.pop()
            members.append(i)
            for k in neighbors[i]:
                if k in dented and k not in seen:
                    seen.add(k)
                    stack.append(k)
        deepest = min(members, key=lambda i: depth[i])
        centroid = [sum(mesh.vertices[i][k] for i in members) / len(members) for k in range(3)]
        tally = {}
        for i in members:
            tally[labels[i][0]] = tally.get(labels[i][0], 0) + 1
        clusters.append({
            "region": max(tally, key=tally.get),
            "label": anatomy.label(labels[deepest]),
            "vertices": len(members),
            "area_m2": round(sum(vertex_area[i] for i in members), 7),
            "deepest_m": round(depth[deepest], 5),
            "deepest_at": [round(c, 4) for c in mesh.vertices[deepest]],
            "centroid": [round(c, 4) for c in centroid],
            "direction": "inward",
        })
    clusters.sort(key=lambda c: c["deepest_m"])
    return clusters


def offset_depths(mesh, neighbors=None):
    """Signed distance of each vertex from its Laplacian-smoothed position, along the vertex normal.

    Plain Laplacian smoothing, not a volume-preserving filter: the reference
    has to lose the dent. Its shrinkage pushes convex surfaces positive, so it
    never invents a dent there; natural concavities read negative, which is
    why a dent needs corroboration.
    """
    neighbors = neighbors or mesh.vertex_neighbors()
    pos = [list(v) for v in mesh.vertices]
    edges = mesh.edges()
    mean_edge = sum(math.dist(mesh.vertices[a], mesh.vertices[b]) for a, b in edges) / max(1, len(edges))
    # Diffusion reach grows with the square root of the iterations, so the
    # same feature radius needs more passes on a finer mesh.
    passes = int(round((regions.OFFSET_RADIUS_M / max(mean_edge, 1e-6)) ** 2))
    passes = max(regions.OFFSET_MIN_ITERATIONS, min(regions.OFFSET_MAX_ITERATIONS, passes))
    factor = regions.OFFSET_LAMBDA
    for _iteration in range(passes):
        moved = []
        for i, around in enumerate(neighbors):
            if not around:
                moved.append(pos[i])
                continue
            n = len(around)
            ax = sum(pos[k][0] for k in around) / n
            ay = sum(pos[k][1] for k in around) / n
            az = sum(pos[k][2] for k in around) / n
            p = pos[i]
            moved.append([p[0] + factor * (ax - p[0]), p[1] + factor * (ay - p[1]), p[2] + factor * (az - p[2])])
        pos = moved
    normals = mesh.vertex_normals()
    depth = [sum((v[k] - pos[i][k]) * normals[i][k] for k in range(3)) for i, v in enumerate(mesh.vertices)]
    # The shrinkage bias follows the broad curvature and varies slowly; a
    # smoothed copy of the depth field removes it and leaves local relief.
    base = list(depth)
    for _iteration in range(passes):
        base = [b + factor * (sum(base[k] for k in around) / len(around) - b) if around else b
                for b, around in zip(base, neighbors)]
    return [d - b for d, b in zip(depth, base)]


def offset_findings(clusters, min_area_m2=regions.OFFSET_MIN_AREA_M2):
    """Dents covering at least ``min_area_m2``: an area, so mesh resolution does not decide."""
    return [
        _finding("offset_dent", c["region"], "low", c["deepest_at"],
                 {k: c[k] for k in ("vertices", "area_m2", "deepest_m", "centroid", "direction")},
                 label=c["label"], experimental=True)
        for c in clusters if c["area_m2"] >= min_area_m2
    ]


def corroborate(findings, radius=regions.CORROBORATION_RADIUS_M):
    """An experimental finding becomes medium only when another layer agrees nearby."""
    solid = [f for f in findings if not f["experimental"] and f["kind"] != "integrity"]
    for f in findings:
        if not f["experimental"]:
            continue
        near = [g["kind"] for g in solid if math.dist(g["at"], f["at"]) <= radius]
        f["evidence"]["corroborated_by"] = sorted(set(near))
        if near:
            f["severity"] = "medium"
    return findings


# --- scan, diff, reproduce ---------------------------------------------------

_SEVERITY_RANK = {"high": 0, "medium": 1, "low": 2}


def scan(capture, include_offsets=True, include_outlines=True, cell=outline.DEFAULT_CELL):
    mesh = capture_mesh(capture)
    landmarks = capture["landmarks"]
    problems = anatomy.validate_landmarks(landmarks)
    if problems:
        raise ValueError("; ".join(problems))
    part_of_vertex = []
    for part in capture["parts"]:
        part_of_vertex += [part.get("role", anatomy.PART_BODY)] * len(part["vertices"])
    labels = anatomy.classify_mesh(mesh, landmarks, part_of_vertex)
    report = {
        "figure": capture.get("figure"),
        "meta": capture.get("meta", {}),
        "stats": mesh.stats(),
        "mesh_hash": mesh.mesh_hash(),
        "integrity": integrity(mesh),
        "symmetry": symmetry(mesh),
    }
    findings = integrity_findings(report["integrity"], len(capture["parts"]))
    if report["symmetry"]["mirror_max_dev_m"] > regions.MIRROR_TOLERANCE_M:
        findings.append(_finding("asymmetry", "mesh", "high", report["symmetry"]["mirror_worst_at"],
                                 dict(report["symmetry"]), view="front"))
    series = sections(mesh, landmarks)
    report["sections"] = series
    findings += section_findings(series, landmarks)
    clusters = crease_clusters(mesh, labels)
    report["crease_clusters"] = clusters[:200]
    findings += crease_findings(clusters)
    if include_outlines:
        report["outlines"], outline_found = outlines(mesh, labels, cell=cell)
        findings += outline_found
    if include_offsets:
        dents = offset_dents(mesh, labels)
        report["offset_dents"] = dents[:200]
        findings += offset_findings(dents)
    corroborate(findings)
    for f in findings:
        f["status"] = regions.status(f["kind"])
    findings.sort(key=lambda f: (_SEVERITY_RANK[f["severity"]], f["experimental"], f["region"], f["kind"]))
    report["findings"] = findings
    report["summary"] = summarize(findings)
    return report


def summarize(findings):
    summary = {"high": 0, "medium": 0, "low": 0, "by_region": {}}
    for f in findings:
        summary[f["severity"]] += 1
        region = summary["by_region"].setdefault(f["region"], {"high": 0, "medium": 0, "low": 0})
        region[f["severity"]] += 1
    return summary


def diff(control_findings, candidate_findings, radius=regions.MATCH_RADIUS_M):
    """Mark each candidate finding new or existing; list control findings now resolved."""
    used = set()
    out = {"new": [], "existing": [], "resolved": []}
    for f in candidate_findings:
        match = None
        for k, g in enumerate(control_findings):
            if k in used or g["kind"] != f["kind"] or g["region"] != f["region"]:
                continue
            if g.get("view") != f.get("view") and f["kind"].startswith("outline"):
                continue
            if math.dist(g["at"], f["at"]) <= radius:
                match = k
                break
        if match is None:
            out["new"].append(dict(f, regression="new"))
        else:
            used.add(match)
            out["existing"].append(dict(f, regression="existing"))
    out["resolved"] = [dict(g, regression="resolved") for k, g in enumerate(control_findings) if k not in used]
    return out


def persistence(findings_a, findings_b, radius=regions.MATCH_RADIUS_M):
    """Which findings at one study resolution are also found at the other."""
    stable = []
    for f in findings_a:
        stable.append(any(g["kind"] == f["kind"] and g["region"] == f["region"]
                          and math.dist(g["at"], f["at"]) <= radius for g in findings_b))
    return stable


def _leaves(data, prefix=""):
    if isinstance(data, dict):
        for key, value in data.items():
            yield from _leaves(value, "%s.%s" % (prefix, key) if prefix else str(key))
    elif isinstance(data, (list, tuple)):
        for index, value in enumerate(data):
            yield from _leaves(value, "%s[%d]" % (prefix, index))
    else:
        yield prefix, data


def compare_measurements(control, candidate, tolerances, default_tolerance=None):
    """Violations where a protected numeric leaf moved past its tolerance.

    ``tolerances`` maps a leaf-path prefix to an absolute tolerance; the
    longest matching prefix wins. Leaves with no matching prefix are only
    compared when ``default_tolerance`` is given.
    """
    want = dict(_leaves(control))
    got = dict(_leaves(candidate))
    violations = []
    for path, value in want.items():
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            continue
        matches = [p for p in tolerances if path.startswith(p)]
        tol = tolerances[max(matches, key=len)] if matches else default_tolerance
        if tol is None:
            continue
        other = got.get(path)
        if other is None or isinstance(other, bool) or not isinstance(other, (int, float)):
            violations.append({"path": path, "control": value, "candidate": other, "tolerance": tol})
        elif abs(other - value) > tol:
            violations.append({"path": path, "control": value, "candidate": other, "tolerance": tol})
    return violations


def reproduce(control, candidate, cell=outline.DEFAULT_CELL, measurement_tolerance=1e-4):
    """Does a rebuild reproduce a frozen control? Exact where the build is deterministic."""
    problems = []
    if control["stats"] != candidate["stats"]:
        problems.append({"check": "topology", "control": control["stats"], "candidate": candidate["stats"]})
    if control["mesh_hash"] != candidate["mesh_hash"]:
        problems.append({"check": "mesh_hash", "control": control["mesh_hash"], "candidate": candidate["mesh_hash"]})
    for view, data in control.get("outlines", {}).items():
        other = candidate.get("outlines", {}).get(view)
        if other is None:
            problems.append({"check": "outline", "view": view, "missing": True})
            continue
        worst = max((math.dist(a, b) for a, b in zip(data["samples"], other["samples"])), default=0.0)
        if worst > 1.5 * cell or len(data["samples"]) != len(other["samples"]):
            problems.append({"check": "outline", "view": view, "worst_m": round(worst, 5)})
    moved = compare_measurements(control.get("measurements", {}), candidate.get("measurements", {}), {},
                                 default_tolerance=measurement_tolerance)
    if moved:
        problems.append({"check": "measurements", "moved": moved[:20], "count": len(moved)})
    return problems
