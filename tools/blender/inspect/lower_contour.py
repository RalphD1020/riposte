"""The lower face's profiles on a built head (HEAD-CONTOUR-001, `character_modeling.contour`):
the midline (a sagittal section from the mouth round the chin and under it toward the neck)
and the mandibular border (on each coronal section behind the chin, the point where the
surface turns from facing out to facing down: the jawline a side view reads), in the side
view's plane (depth, height), from the head's own mesh, never a render.

    blender --background built.blend --python lower_contour.py -- --rows a,b --out contour.json
"""

import json
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "character_modeling"))
from character_modeling import contour  # noqa: E402

## Of the head's height above its lowest point: the mouth's level, where the midline starts.
MOUTH_V = 0.22
## Behind the head's front (metres): where the midline ends (past the cervicomental
## junction) and the border's sections run (chin to the jaw's corner).
MIDLINE_DEPTH_M = 0.105
BORDER_DEPTHS_M = (0.040, 0.112)
BORDER_STEP_M = 0.002
## The border: the surface's normal halfway between out and down.
BORDER_ANGLE_DEG = 45.0


def _local(obj):
    offset = obj.matrix_world.translation
    return [obj.matrix_world @ v.co - offset for v in obj.data.vertices]


def section(obj, points, axis, value, normals=None):
    """The mesh cut by the plane `axis` = value: [(segment (p, q), (normal at p, at q))],
    the normals the shading's (vertex normals interpolated along the cut edges)."""
    out = []
    for poly in obj.data.polygons:
        ids = list(poly.vertices)
        hits = []
        for a, b in zip(ids, ids[1:] + ids[:1]):
            pa, pb = points[a], points[b]
            da, db = pa[axis] - value, pb[axis] - value
            if (da < 0.0) != (db < 0.0):
                f = da / (da - db)
                n = None if normals is None else normals[a].lerp(normals[b], f).normalized()
                hits.append((pa + (pb - pa) * f, n))
        if len(hits) == 2:
            out.append(((hits[0][0], hits[1][0]), (hits[0][1], hits[1][1])))
    return out


def _chain(segments):
    """The segments joined end to end into polylines (longest first)."""
    key = lambda p: (round(p.x, 7), round(p.y, 7), round(p.z, 7))
    ends = {}
    for i, (seg, _n) in enumerate(segments):
        for p in seg:
            ends.setdefault(key(p), []).append(i)
    used, lines = set(), []
    for start in range(len(segments)):
        if start in used:
            continue
        used.add(start)
        line = list(segments[start][0])
        for forward in (True, False):
            while True:
                tip = line[-1] if forward else line[0]
                nxt = [i for i in ends.get(key(tip), []) if i not in used]
                if not nxt:
                    break
                used.add(nxt[0])
                a, b = segments[nxt[0]][0]
                other = b if key(a) == key(tip) else a
                if forward:
                    line.append(other)
                else:
                    line.insert(0, other)
        lines.append(line)
    return sorted(lines, key=len, reverse=True)


def midline(obj, points):
    low = min(p.z for p in points)
    height = max(p.z for p in points) - low
    front = min(p.y for p in points)
    cx = 0.5 * (min(p.x for p in points) + max(p.x for p in points))
    line = _chain(section(obj, points, 0, cx))[0]
    keep = [p for p in line if p.z < low + MOUTH_V * height and p.y < front + MIDLINE_DEPTH_M]
    ## The front run first: from the mouth down round the chin, then back under it.
    keep.sort(key=lambda p: line.index(p))
    if keep and keep[0].z < keep[-1].z:
        keep.reverse()
    return [(p.y - front, p.z - low) for p in keep]


def border(obj, points):
    """(depth, height) and (depth, half width) of the mandibular border, chin to corner."""
    low = min(p.z for p in points)
    height = max(p.z for p in points) - low
    front = min(p.y for p in points)
    cx = 0.5 * (min(p.x for p in points) + max(p.x for p in points))
    rot = obj.matrix_world.to_3x3()
    normals = [(rot @ v.normal).normalized() for v in obj.data.vertices]
    side, plan = [], []
    target = math.radians(BORDER_ANGLE_DEG)
    y = BORDER_DEPTHS_M[0]
    while y <= BORDER_DEPTHS_M[1] + 1e-9:
        ## Along the section's +x lower run, where the shading normal crosses halfway
        ## between out and down: the border is the crossing nearest the bottom.
        crossings = []
        for (p, q), (np_, nq) in section(obj, points, 1, front + y, normals):
            if min(p.x, q.x) - cx <= 0.004 or max(p.z, q.z) > low + MOUTH_V * height:
                continue
            ap = math.atan2(-np_.z, np_.x)
            aq = math.atan2(-nq.z, nq.x)
            if np_.x > 0.0 and nq.x > 0.0 and (ap - target) * (aq - target) <= 0.0 and ap != aq:
                f = (target - ap) / (aq - ap)
                crossings.append(p.lerp(q, f))
        if crossings:
            point = min(crossings, key=lambda c: c.z)
            side.append((y, point.z - low))
            plan.append((y, point.x - cx))
        y += BORDER_STEP_M
    return side, plan


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    rows = args[args.index("--rows") + 1].split(",")
    out_path = args[args.index("--out") + 1]
    report = {}
    for row in rows:
        obj = bpy.data.objects[row + ".Head"]
        points = _local(obj)
        mid = midline(obj, points)
        side, plan = border(obj, points)
        measures = {"midline": contour.analyse(mid), "border": contour.analyse(side), "border_plan": contour.analyse(plan)}
        report[row] = {"measures": measures, "problems": contour.problems("midline", measures["midline"]) + contour.problems("border", measures["border"]),
                       "midline": [[round(a, 5), round(b, 5)] for a, b in mid], "border": [[round(a, 5), round(b, 5)] for a, b in side],
                       "border_plan": [[round(a, 5), round(b, 5)] for a, b in plan]}
        print("RIPOSTE_CONTOUR %s %s" % (row, json.dumps({k: {"sharpest": v["sharpest_deg"], "kinks": v["kinks"], "reversals": len(v["reversals"])} for k, v in measures.items()})))
    with open(out_path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(report, handle, indent=1)


if __name__ == "__main__":
    main()
