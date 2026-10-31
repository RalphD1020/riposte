"""Region checks for the production body at rest, measured against its landmarks.

Each check is local to the anatomy it names; none is a global height rule
(an arm raised overhead rightly rises above the mantle):

- flesh seams: the torso shares an edge with each shoulder and each leg,
  the deltoid cap shares an edge with the upper arm, and the chest and the
  pelvis are one surface. A count of components does not name which of
  those failed. The nude body has no intentional separate islands; garments
  are not part of this mesh;
- neck intrusion: at rest, no vertex riding the arm (upper arm or clavicle
  dominant) sits above the trapezius ridge between the neck root and the
  acromion;
- mantle: the torso reaches the acromion height across that span;
- deltoid: the arm's surface reaches the shoulder span at shoulder height;
- socket: each arm's first ring shares its boundary with the torso;
- girdle mapping: the socket boundary rides the clavicle as well as the arm,
  so the girdle can move with the arm rather than stay a static chest shell.

Posed checks (shoulder range, clips, combat pose, clavicle, IK) run in Godot
on the imported skin (PRES-PRODUCTION); these are the construction contract.
"""

from __future__ import annotations

from . import anatomy, diagnostics
from .mesh_data import MeshData
from .production import AROUND

RIDGE_TOLERANCE_M = 0.005
SPAN_TOLERANCE_M = 0.03
# The deltoid's outer face and the first upper-arm ring's outer face.
OUTER_STEP_M = 0.02
# Back reach between neighbouring sections, socket → deltoid cap → upper arm.
# The rejected cap stepped 3.9 / 7.3 cm at the back; the flowing cap steps
# about 2 cm. The front (6.0 / 3.0 / 5.1 cm) is not held here: flowing it
# folded the girdle in Godot, and it stays an open anterior finding.
DEPTH_STEP_M = 0.03
CAP_RINGS = 2
ARM_FAMILY = ("UpperArm.", "Shoulder.")
SPINE = ("Hips", "Spine", "Chest", "Neck", "Head")
FLESH_SEAMS = ("torso_shoulder", "shoulder_upper_arm", "torso_pelvis", "pelvis_leg")
# The nude body is one flesh surface. Clothing and rigid accessories are
# separate meshes and are not built here.
INTENTIONAL_SEPARATE = ()


def _undirected_edges(faces):
    edges = set()
    for face in faces:
        for index, start in enumerate(face):
            end = face[(index + 1) % len(face)]
            edges.add((start, end) if start < end else (end, start))
    return edges


def _in_span(index, span):
    return span[0] <= index < span[1]


def _crosses(edges, span, others):
    """True when some edge has one end in ``span`` and the other in ``others``."""
    def outside(index):
        return any(_in_span(index, other) for other in others)

    return any((_in_span(a, span) and outside(b)) or (_in_span(b, span) and outside(a)) for a, b in edges)


def _has_prefix(weights, prefix):
    return any(bone.startswith(prefix) for bone, _w in weights)


def _shoulder_meets_arm(edges, weights, arms):
    """The deltoid cap (a vertex that names a clavicle) shares an edge with
    the upper-arm shaft (upper arm, and no clavicle)."""
    def in_arm(index):
        return any(_in_span(index, span) for span in arms)

    for a, b in edges:
        if not (in_arm(a) and in_arm(b)):
            continue
        left, right = weights[a], weights[b]
        if ((_has_prefix(left, "Shoulder") and _has_prefix(right, "UpperArm") and not _has_prefix(right, "Shoulder"))
                or (_has_prefix(right, "Shoulder") and _has_prefix(left, "UpperArm") and not _has_prefix(left, "Shoulder"))):
            return True
    return False


def _component_find(vertex_count, faces):
    parent = list(range(vertex_count))

    def find(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    for face in faces:
        for other in face[1:]:
            union(face[0], other)
    return find


def _same_component(mesh, left, right):
    find = _component_find(len(mesh["vertices"]), mesh["faces"])
    roots = [find(index) for index, weights in enumerate(mesh["weights"]) if left(weights)]
    if not roots:
        return False
    root = roots[0]
    return any(right(weights) and find(index) == root for index, weights in enumerate(mesh["weights"]))


def component_census(mesh):
    """``(vertex_count, face_count)`` per connected component, largest first.

    Zero boundary edges means each component is watertight. It does not mean
    the body is one surface. Five watertight tubes are five rows here.
    """
    faces = mesh["faces"]
    find = _component_find(len(mesh["vertices"]), faces)
    face_count = {}
    used = {}
    for face in faces:
        root = find(face[0])
        face_count[root] = face_count.get(root, 0) + 1
        used.setdefault(root, set()).update(face)
    return tuple(sorted(((len(used[root]), face_count[root]) for root in face_count), reverse=True))


def flesh_seams(mesh):
    """Named flesh connections on the nude body.

    A manifold of separate tubes passes an integrity check and still fails
    the seams that anatomy requires. ``intentional_separate`` is empty:
    nothing on this body is supposed to be its own island.
    """
    pieces = {name: (first, end) for name, first, end in mesh.get("pieces", ())}
    needed = ("Torso", "Arm.L", "Arm.R", "Leg.L", "Leg.R")
    components = diagnostics.integrity(MeshData(mesh["vertices"], mesh["faces"]))["components"]
    if not set(needed) <= set(pieces):
        return {name: False for name in FLESH_SEAMS} | {
            "intentional_separate": INTENTIONAL_SEPARATE, "components": components}
    edges = _undirected_edges(mesh["faces"])
    torso, arms, legs = pieces["Torso"], (pieces["Arm.L"], pieces["Arm.R"]), (pieces["Leg.L"], pieces["Leg.R"])
    return {
        "torso_shoulder": _crosses(edges, torso, arms),
        "shoulder_upper_arm": _shoulder_meets_arm(edges, mesh["weights"], arms),
        "torso_pelvis": _same_component(
            mesh, lambda weights: _dominant(weights) in ("Chest", "Spine", "Neck"),
            lambda weights: _dominant(weights) == "Hips"),
        "pelvis_leg": _crosses(edges, torso, legs),
        "intentional_separate": INTENTIONAL_SEPARATE,
        "components": components,
    }


def _dominant(weights):
    return max(weights, key=lambda bw: bw[1])[0] if weights else ""


def _ring_outer(vertices, start, count, sign):
    return max(sign * vertices[index][0] for index in range(start, start + count))


def outer_contour_finding(mesh, landmarks):
    """The deltoid cap and the proximal arm must share one outer face, the
    shoulder span. Absent on a mesh that has no deltoid ring (the rejected loft)."""
    if "deltoid_outer" not in mesh.get("regions", ()):
        return None
    span = landmarks.sizes["shoulders"]
    worst = 0.0
    for name, first, _end in mesh["pieces"]:
        if not name.startswith("Arm."):
            continue
        sign = 1.0 if name.endswith(".L") else -1.0
        cap = _ring_outer(mesh["vertices"], first + AROUND, AROUND, sign)
        shaft = _ring_outer(mesh["vertices"], first + 2 * AROUND, AROUND, sign)
        worst = max(worst, abs(cap - shaft))
        if sign * cap > span + 0.01:
            return "deltoid outer face %.3f m past the %.3f m span" % (sign * cap, span)
    if worst > OUTER_STEP_M:
        return "outer face steps %.3f m between the deltoid and the upper arm" % worst
    return None


# A ledge where the thigh meets the pelvis: the step from the opening to the
# first thigh ring larger than the next step down the thigh by more than this.
# The pre-flow body: 5.3 cm against 0.4 (left front), 10.8 against 1.0 (right back).
HIP_LEDGE_M = 0.02


def _hip_ledge(mesh, torso_around):
    """(worst excess, where): how much each leg's junction step exceeds the
    slope just below it, front and back."""
    vertices = mesh["vertices"]
    worst = (0.0, "")
    for name, first, _end in mesh["pieces"]:
        if not name.startswith("Leg."):
            continue
        sign = 1.0 if name.endswith(".L") else -1.0
        half = [v for v in vertices[:torso_around] if sign * v[0] >= -1e-9]
        rings = [vertices[first + r * AROUND:first + (r + 1) * AROUND] for r in range(2)]
        spans = [(min(v[1] for v in s), max(v[1] for v in s)) for s in [half] + rings]
        for side, pick in (("front", 0), ("back", 1)):
            junction = abs(spans[1][pick] - spans[0][pick])
            below = abs(spans[2][pick] - spans[1][pick])
            if junction - below > worst[0]:
                worst = (junction - below, "%s %s" % (name, side))
    return worst


def pelvis_findings(mesh, torso_around):
    """``{check: detail}`` for the hip join at rest; empty is a pass.

    - hip_outer: the pelvis opening and the first thigh ring share an outer face;
    - seat: the glutes reach behind the rear thigh tops, so the hip is not two
      columns under a box.
    """
    findings = {}
    if "pelvis_opening" not in mesh.get("regions", ()):
        return {"seat": "no pelvis opening: the legs are not welded to the pelvis"}
    vertices = mesh["vertices"]
    pelvis = vertices[:3 * torso_around]
    seat = max(v[1] for v in pelvis)
    opening = vertices[:torso_around]
    for name, first, _end in mesh["pieces"]:
        if not name.startswith("Leg."):
            continue
        sign = 1.0 if name.endswith(".L") else -1.0
        top = vertices[first:first + 2 * AROUND]
        thigh_outer = max(sign * v[0] for v in vertices[first:first + AROUND])
        pelvis_outer = max(sign * v[0] for v in opening)
        if abs(thigh_outer - pelvis_outer) > OUTER_STEP_M:
            findings["hip_outer"] = "%s outer face steps %.3f m at the hip" % (name, abs(thigh_outer - pelvis_outer))
        rear = max(v[1] for v in top)
        if rear > seat + RIDGE_TOLERANCE_M:
            findings["seat"] = "%s thigh sits %.3f m behind the glutes" % (name, rear - seat)
    ledge, where = _hip_ledge(mesh, torso_around)
    if ledge > HIP_LEDGE_M:
        findings["hip_ledge"] = "%s steps %.3f m more at the hip than just below it" % (where, ledge)
    return findings


def depth_contour_finding(mesh):
    """The posterior deltoid flows from the socket into the upper arm: no back
    step between neighbouring sections larger than ``DEPTH_STEP_M``. None when
    the mesh has no socket (the rejected loft)."""
    sockets = mesh.get("sockets")
    if not sockets or "deltoid" not in mesh.get("regions", ()):
        return None
    vertices = mesh["vertices"]
    worst = (0.0, "")
    for name, first, _end in mesh["pieces"]:
        if not name.startswith("Arm."):
            continue
        sections = [sockets[name[-1]]] + [range(first + ring * AROUND, first + (ring + 1) * AROUND)
                                          for ring in range(CAP_RINGS + 1)]
        spans = [(min(vertices[i][1] for i in s), max(vertices[i][1] for i in s)) for s in sections]
        for (_front_a, back_a), (_front_b, back_b) in zip(spans, spans[1:]):
            if abs(back_b - back_a) > worst[0]:
                worst = (abs(back_b - back_a), "%s back" % name)
    if worst[0] > DEPTH_STEP_M:
        return "deltoid %s steps %.3f m between sections" % (worst[1], worst[0])
    return None


def shoulder_findings(mesh, landmarks):
    """``{check: detail}`` for every shoulder contract the mesh breaks; empty is a pass."""
    findings = {}
    vertices, weights = mesh["vertices"], mesh["weights"]
    seams = flesh_seams(mesh)
    for name in FLESH_SEAMS:
        if not seams[name]:
            findings[name] = "the %s connection is missing" % name.replace("_", "-")
    if seams["intentional_separate"] == () and seams["components"] != 1 and not findings:
        findings["components"] = "%d components with no intentional island" % seams["components"]
    contour = outer_contour_finding(mesh, landmarks)
    if contour:
        findings["outer_contour"] = contour
    depth = depth_contour_finding(mesh)
    if depth:
        findings["depth_contour"] = depth
    intrusions = 0
    for v, w in zip(vertices, weights):
        if not _dominant(w).startswith(ARM_FAMILY):
            continue
        ridge = anatomy.trapezius_ridge_z(landmarks, v[0])
        if ridge is not None and v[2] > ridge + RIDGE_TOLERANCE_M:
            intrusions += 1
    if intrusions:
        findings["neck_intrusion"] = "%d arm vertices above the trapezius ridge" % intrusions
    neck_x, _top = landmarks.neck_root
    shoulder = landmarks.shoulders["L"]
    acromion = shoulder.acromion
    head_z = landmarks.mantle_top_z + 0.03
    mantle = [v[2] for v, w in zip(vertices, weights)
              if _dominant(w) in SPINE and neck_x <= abs(v[0]) <= acromion[0] and v[2] < head_z]
    if not mantle or max(mantle) < acromion[2] - RIDGE_TOLERANCE_M:
        findings["mantle"] = "torso tops out at %.3f m below the acromion %.3f m" % (
            max(mantle) if mantle else 0.0, acromion[2])
    band = (shoulder.axilla[2], acromion[2] + 0.02)
    arm_x = [abs(v[0]) for v, w in zip(vertices, weights)
             if _dominant(w).startswith(ARM_FAMILY) and band[0] <= v[2] <= band[1]]
    span = landmarks.sizes["shoulders"]
    if not arm_x or max(arm_x) < span - SPAN_TOLERANCE_M:
        findings["deltoid"] = "deltoid reaches %.3f m, short of the %.3f m span" % (max(arm_x) if arm_x else 0.0, span)
    sockets = mesh.get("sockets")
    if sockets is None:
        findings["socket"] = "no socket loops: the arms are not welded to the torso"
        return findings
    torso = next((first, end) for name, first, end in mesh["pieces"] if name == "Torso")
    for side, loop in sockets.items():
        if len(loop) != 12 or not all(torso[0] <= index < torso[1] for index in loop):
            findings["socket"] = "%s socket loop is not a 12-vertex torso boundary" % side
            continue
        static = [i for i in loop if not {"Shoulder." + side, "UpperArm." + side} <= {b for b, _w in weights[i]}]
        if static:
            findings["girdle_mapping"] = "%d %s socket vertices do not ride both the clavicle and the arm" % (
                len(static), side)
    return findings
