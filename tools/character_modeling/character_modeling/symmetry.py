"""Bilateral-symmetry CHECKS for the default anatomical foundation (CHARACTER-SYMMETRY-001).

The default male (and future female) foundation — the unposed body, the head anatomy, and the
left/right placement of ears, eyes and brows — is bilaterally symmetric about the character's
X=0 midline in the canonical neutral modeling A-pose. Symmetry is a property of the UNPOSED
foundation only: posed fighters (the combat guard, attacks) and intentionally asymmetric
costumes (a one-sided belt, shoulder plate or hairstyle) are exempt, and this module is never
run against a combat/animation clip.

This module only CHECKS symmetry; it never MANUFACTURES it. Symmetry is produced by construction
with Blender's Mirror modifier (model one half, mirror, merge + clip the centerline) or by
Symmetrize on a staged copy of an approved mesh — never a custom bilateral-correspondence
engine. `mirror_problems` is the geometry gate; `weight_mirror_problems` is the rig-weight gate.

Pure Python: no Blender. A Blender caller extracts the A-pose vertices/weights and calls these.
"""

from __future__ import annotations

import math

## A vertex within this seam band of the midline is treated as a centerline (welded-seam)
## vertex: it maps to itself, never to a counterpart, and must sit on X=0 within TOLERANCE_M.
## The band is wider than the match tolerance (a merged seam is exactly 0; the nearest off-seam
## body vertices are several mm out), so a seam vertex left off the midline is caught.
MIDLINE_EPS_M = 0.002
## A counterpart must lie within this of the mirrored position to count as symmetric. 1 mm is
## well below any anatomically meaningful bilateral difference and above float/round noise.
TOLERANCE_M = 0.001


def _key(point, tolerance):
    step = tolerance
    return tuple(round(c / step) for c in point)


def mirror_problems(vertices, tolerance=TOLERANCE_M, midline_eps=MIDLINE_EPS_M, limit=20):
    """Why `vertices` ([(x,y,z)] in the A-pose, root-normalized to the X=0 midline) are not
    bilaterally symmetric: every vertex must have a counterpart near (-x, y, z) within
    `tolerance`. A welded seam vertex (x ≈ 0) is its own counterpart and matches trivially; a
    seam vertex that drifted off the midline, or a side vertex with no mirror, has none and is
    reported. Returns (problems, stats) with the counts and the worst matched asymmetry (m);
    empty problems means symmetric to tolerance. `midline_eps` only informs the centerline
    stat. `limit` caps the listed examples."""
    buckets = {}
    for p in vertices:
        buckets.setdefault(_key(p, tolerance), []).append(p)
    problems, worst, unmatched, centerline = [], 0.0, 0, 0
    for i, (x, y, z) in enumerate(vertices):
        if abs(x) <= midline_eps:
            centerline += 1
        mirror = (-x, y, z)
        kx, ky, kz = _key(mirror, tolerance)
        best = None
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for q in buckets.get((kx + dx, ky + dy, kz + dz), ()):
                        d = ((q[0] - mirror[0]) ** 2 + (q[1] - mirror[1]) ** 2 + (q[2] - mirror[2]) ** 2) ** 0.5
                        if best is None or d < best:
                            best = d
        if best is None or best > tolerance:
            unmatched += 1
            if len(problems) < limit:
                problems.append("vertex %d at (%.4f, %.4f, %.4f) has no mirror counterpart (nearest %s)"
                                % (i, x, y, z, ("%.4f m" % best) if best is not None else "none"))
        elif best > worst:
            worst = best
    stats = {"vertices": len(vertices), "centerline": centerline, "unmatched": unmatched,
             "worst_offset_m": round(worst, 6), "symmetric": not problems}
    return problems, stats


def weight_mirror_problems(vertices, weights, mirror_bone, tolerance=TOLERANCE_M, midline_eps=MIDLINE_EPS_M, limit=20):
    """Why the rig weights are not bilaterally mirrored: for each off-centerline vertex and its
    geometric mirror counterpart, the influence set must match once bone names are mirrored by
    `mirror_bone` (e.g. `UpperArm.L` <-> `UpperArm.R`, a centre bone to itself). `weights` is a
    list parallel to `vertices` of {bone: weight}. Returns (problems, stats)."""
    index = {}
    for i, (x, y, z) in enumerate(vertices):
        if abs(x) > midline_eps:
            index.setdefault(_key((x, y, z), tolerance), []).append(i)
    problems, checked = [], 0
    for i, (x, y, z) in enumerate(vertices):
        if abs(x) <= midline_eps:
            continue
        mirror = (-x, y, z)
        kx, ky, kz = _key(mirror, tolerance)
        partner = None
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for j in index.get((kx + dx, ky + dy, kz + dz), ()):
                        q = vertices[j]
                        if ((q[0] - mirror[0]) ** 2 + (q[1] - mirror[1]) ** 2 + (q[2] - mirror[2]) ** 2) ** 0.5 <= tolerance:
                            partner = j
        if partner is None:
            continue
        checked += 1
        mine = {mirror_bone(b): round(w, 4) for b, w in weights[i].items()}
        theirs = {b: round(w, 4) for b, w in weights[partner].items()}
        if mine != theirs and len([p for p in problems if "weights" in p]) < limit:
            problems.append("vertex %d weights %s do not mirror vertex %d weights %s" % (i, mine, partner, theirs))
    return problems, {"checked_pairs": checked, "symmetric_weights": not problems}


def centerline_seam_problems(vertices, faces, midline_eps=MIDLINE_EPS_M, weld_m=1e-5, limit=20):
    """Why the midline seam is not welded — a TOPOLOGY check kept apart from `mirror_problems`
    (a seam vertex mirrors to itself whether or not the halves are joined): open boundary edges
    running along the midline (both ends within `midline_eps` of X=0), and coincident duplicate
    vertices on the midline (two halves mirrored but never merged). `faces` are vertex-index
    sequences. Returns (problems, stats)."""
    edge_faces = {}
    for face in faces:
        for a, b in zip(face, list(face[1:]) + [face[0]]):
            key = (a, b) if a < b else (b, a)
            edge_faces[key] = edge_faces.get(key, 0) + 1
    on_mid = {i for i, v in enumerate(vertices) if abs(v[0]) <= midline_eps}
    open_edges = [e for e, n in edge_faces.items() if n == 1 and e[0] in on_mid and e[1] in on_mid]
    seen, duplicates = {}, 0
    for i in sorted(on_mid):
        key = tuple(round(c / weld_m) for c in vertices[i])
        if key in seen:
            duplicates += 1
        else:
            seen[key] = i
    problems = ["midline edge %s is open (unwelded seam)" % (e,) for e in open_edges[:limit]]
    if duplicates:
        problems.append("%d coincident duplicate vertices on the midline (halves not merged)" % duplicates)
    return problems, {"open_seam_edges": len(open_edges), "duplicate_seam_vertices": duplicates,
                      "welded": not problems}


def bone_mirror_problems(bones, tolerance=TOLERANCE_M, limit=20):
    """Why a deform skeleton's REST structure is not bilaterally symmetric. `bones` is
    {name: {"head": (x,y,z), "tail": (x,y,z), "parent": name or None}} in the rest/bind pose.
    Every `.L` bone needs a `.R` counterpart (and vice versa) whose head and tail are the
    mirrored positions within `tolerance` and whose parent is the mirrored parent; a centre
    bone (no side suffix) lies on the midline. Positions, not matrices: a reflected basis has
    the opposite handedness, so orientation is constructed by Blender's bone Symmetrize and
    judged by evaluated deformation, never by negating a matrix column. Returns (problems,
    stats) with the worst mirrored joint offset (m)."""
    problems, worst, pairs = [], 0.0, 0

    def mirrored(p):
        return (-p[0], p[1], p[2])

    def dist(p, q):
        return sum((a - b) ** 2 for a, b in zip(p, q)) ** 0.5

    for name, bone in sorted(bones.items()):
        other = mirror_bone_name(name)
        if other == name:
            off = max(abs(bone["head"][0]), abs(bone["tail"][0]))
            if off > tolerance and len(problems) < limit:
                problems.append("centre bone %s is %.4f m off the midline" % (name, off))
            continue
        if not name.endswith(".L"):
            if other not in bones and len(problems) < limit:
                problems.append("%s has no counterpart %s" % (name, other))
            continue
        partner = bones.get(other)
        if partner is None:
            if len(problems) < limit:
                problems.append("%s has no counterpart %s" % (name, other))
            continue
        pairs += 1
        d = max(dist(mirrored(bone["head"]), partner["head"]), dist(mirrored(bone["tail"]), partner["tail"]))
        worst = max(worst, d)
        if d > tolerance and len(problems) < limit:
            problems.append("%s and %s joints differ by %.4f m under reflection" % (name, other, d))
        expected = mirror_bone_name(bone["parent"]) if bone.get("parent") else None
        if partner.get("parent") != expected and len(problems) < limit:
            problems.append("%s parent %s does not mirror %s parent %s" % (other, partner.get("parent"), name, bone.get("parent")))
    return problems, {"pairs": pairs, "worst_joint_offset_m": round(worst, 6), "symmetric": not problems}


## A mirrored pair's rest ORIENTATIONS match within this angle (deg). Joint positions can mirror
## perfectly while local axes do not, and inconsistent roll twists the arm when an otherwise
## valid animation curve is evaluated — the upper-arm-twist risk. This is the geometric check
## `bone_mirror_problems` (positions only) does not make.
ORIENTATION_TOLERANCE_DEG = 1.0


def _angle_deg(a, b):
    na = sum(c * c for c in a) ** 0.5
    nb = sum(c * c for c in b) ** 0.5
    if na < 1e-12 or nb < 1e-12:
        return 180.0
    dot = max(-1.0, min(1.0, sum(x * y for x, y in zip(a, b)) / (na * nb)))
    return math.degrees(math.acos(dot))


def bone_rest_orientation_problems(bones, tolerance_deg=ORIENTATION_TOLERANCE_DEG, limit=20):
    """Why a deform skeleton's REST ORIENTATIONS are not bilaterally symmetric. Each bone may
    carry a `roll_axis`: its local roll reference (the bone's local Z) as a unit vector in
    skeleton space. A `.L`/`.R` pair is roll-symmetric when the left bone's roll axis reflected
    across X=0 — (-x, y, z) — equals the right bone's roll axis within `tolerance_deg`; a centre
    bone's roll axis must be mirror-invariant (reflection leaves it unchanged, i.e. its
    x-component is ~0). This is the geometric comparison the upper-arm-twist risk needs — never a
    raw left/right quaternion equality, which a reflected (opposite-handed) frame fails even when
    correct. Bones with no `roll_axis` are skipped, so positions-only callers are unaffected.
    `bones` is {name: {..., "roll_axis": (x,y,z)}}. Returns (problems, stats) with the worst
    angular deviation (deg)."""
    problems, worst, pairs = [], 0.0, 0
    for name, bone in sorted(bones.items()):
        axis = bone.get("roll_axis")
        if axis is None:
            continue
        other = mirror_bone_name(name)
        if other == name:
            dev = _angle_deg(axis, (-axis[0], axis[1], axis[2]))
            worst = max(worst, dev)
            if dev > tolerance_deg and len(problems) < limit:
                problems.append("centre bone %s roll axis is not mirror-invariant (%.2f deg off the X=0 plane)" % (name, dev))
            continue
        if not name.endswith(".L"):
            continue
        partner = bones.get(other)
        if partner is None or partner.get("roll_axis") is None:
            continue
        pairs += 1
        dev = _angle_deg((-axis[0], axis[1], axis[2]), partner["roll_axis"])
        worst = max(worst, dev)
        if dev > tolerance_deg and len(problems) < limit:
            problems.append("%s and %s rest roll axes differ by %.2f deg under reflection" % (name, other, dev))
    return problems, {"pairs": pairs, "worst_orientation_deg": round(worst, 4), "symmetric": not problems}


def mirror_bone_name(name):
    """`Foo.L` <-> `Foo.R`; a centre bone maps to itself. The project's left/right convention."""
    if name.endswith(".L"):
        return name[:-2] + ".R"
    if name.endswith(".R"):
        return name[:-2] + ".L"
    return name
