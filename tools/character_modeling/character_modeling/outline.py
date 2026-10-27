"""Silhouette outlines projected from the mesh, not read from a render.

A view is an orthographic camera: a screen-right axis, a screen-up axis, and
the direction it looks along. The mesh's triangles are rasterized into a
fixed grid, enclosed holes are filled, and the outer boundary is chained
into one closed loop. A render mask is only a cross-check on this: render
antialiasing, shadow and background segmentation invent corners that the
geometry does not have.
"""

from __future__ import annotations

import math
from collections import deque

_R = 1.0 / math.sqrt(2.0)
# name: (screen right, screen up, look direction), Blender study space.
VIEWS = {
    "front": ((1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0)),
    "side": ((0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (-1.0, 0.0, 0.0)),
    "quarter": ((_R, -_R, 0.0), (0.0, 0.0, 1.0), (_R, _R, 0.0)),
    "rear": ((-1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, -1.0, 0.0)),
}
DEFAULT_CELL = 0.0015


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


class Raster:
    def __init__(self, width, height, u0, v0, cell):
        self.width, self.height, self.u0, self.v0, self.cell = width, height, u0, v0, cell
        self.filled = bytearray(width * height)
        self.owner = [-1] * (width * height)
        self.depth = [math.inf] * (width * height)

    def mark(self, i, j, owner, depth):
        k = j * self.width + i
        self.filled[k] = 1
        if depth < self.depth[k]:
            self.depth[k] = depth
            self.owner[k] = owner

    def area(self):
        return sum(self.filled) * self.cell * self.cell


def project(mesh, view, cell=DEFAULT_CELL, vertex_mask=None):
    """Rasterize ``mesh`` (or only faces whose vertices pass ``vertex_mask``)."""
    right, up, look = VIEWS[view] if isinstance(view, str) else view
    uv = [(_dot(v, right), _dot(v, up)) for v in mesh.vertices]
    depth = [_dot(v, look) for v in mesh.vertices]
    us = [p[0] for p in uv]
    vs = [p[1] for p in uv]
    pad = 3 * cell
    u0, v0 = min(us) - pad, min(vs) - pad
    width = int(math.ceil((max(us) + pad - u0) / cell)) + 1
    height = int(math.ceil((max(vs) + pad - v0) / cell)) + 1
    raster = Raster(width, height, u0, v0, cell)
    inv = 1.0 / cell
    for _face, a, b, c in mesh.triangles():
        if vertex_mask is not None and not (vertex_mask[a] and vertex_mask[b] and vertex_mask[c]):
            continue
        (ua, va), (ub, vb), (uc, vc) = uv[a], uv[b], uv[c]
        # Depth decides which triangle owns a cell; the owner named is that
        # triangle's vertex nearest the cell on screen, so a silhouette point
        # maps to the surface it came from.
        near = min(depth[a], depth[b], depth[c])

        def owner(pu, pv):
            da = (ua - pu) ** 2 + (va - pv) ** 2
            db = (ub - pu) ** 2 + (vb - pv) ** 2
            dc = (uc - pu) ** 2 + (vc - pv) ** 2
            return a if da <= db and da <= dc else (b if db <= dc else c)

        i0 = int((min(ua, ub, uc) - u0) * inv)
        i1 = int((max(ua, ub, uc) - u0) * inv)
        j0 = int((min(va, vb, vc) - v0) * inv)
        j1 = int((max(va, vb, vc) - v0) * inv)
        covered = False
        for j in range(j0, j1 + 1):
            pv = v0 + (j + 0.5) * cell
            for i in range(i0, i1 + 1):
                pu = u0 + (i + 0.5) * cell
                w0 = (ub - pu) * (vc - pv) - (uc - pu) * (vb - pv)
                w1 = (uc - pu) * (va - pv) - (ua - pu) * (vc - pv)
                w2 = (ua - pu) * (vb - pv) - (ub - pu) * (va - pv)
                if (w0 >= 0 and w1 >= 0 and w2 >= 0) or (w0 <= 0 and w1 <= 0 and w2 <= 0):
                    raster.mark(i, j, owner(pu, pv), near)
                    covered = True
        if not covered and (i0 != i1 or j0 != j1):
            # A sliver spanning cells that misses every centre still marks its
            # centroid's cell. A triangle inside one cell that misses the centre
            # marks nothing: that keeps the area unbiased.
            cu, cv = (ua + ub + uc) / 3.0, (va + vb + vc) / 3.0
            raster.mark(int((cu - u0) * inv), int((cv - v0) * inv), owner(cu, cv), near)
    _fill_holes(raster)
    return raster


def _fill_holes(raster):
    w, h, filled = raster.width, raster.height, raster.filled
    outside = bytearray(w * h)
    queue = deque()
    for i in range(w):
        for j in (0, h - 1):
            k = j * w + i
            if not filled[k] and not outside[k]:
                outside[k] = 1
                queue.append(k)
    for j in range(h):
        for i in (0, w - 1):
            k = j * w + i
            if not filled[k] and not outside[k]:
                outside[k] = 1
                queue.append(k)
    while queue:
        k = queue.popleft()
        i, j = k % w, k // w
        for ni, nj in ((i + 1, j), (i - 1, j), (i, j + 1), (i, j - 1)):
            if 0 <= ni < w and 0 <= nj < h:
                nk = nj * w + ni
                if not filled[nk] and not outside[nk]:
                    outside[nk] = 1
                    queue.append(nk)
    for k in range(w * h):
        if not outside[k] and not filled[k]:
            filled[k] = 1


def outer_loop(raster):
    """The outer boundary as ordered points, counter-clockwise (filled on the left).

    Points are the midpoints of boundary cell edges, so the loop has no
    half-cell staircase. Each point carries the owning (front-most) vertex of
    the filled cell beside it.
    """
    w, h, filled, cell = raster.width, raster.height, raster.filled, raster.cell

    def inside(i, j):
        return 0 <= i < w and 0 <= j < h and filled[j * w + i]

    # Directed boundary edges between corner lattice points, filled cell on the left.
    out = {}
    for j in range(h):
        for i in range(w):
            if not filled[j * w + i]:
                continue
            k = j * w + i
            if not inside(i, j - 1):
                out.setdefault((i, j), []).append(((i + 1, j), k))
            if not inside(i + 1, j):
                out.setdefault((i + 1, j), []).append(((i + 1, j + 1), k))
            if not inside(i, j + 1):
                out.setdefault((i + 1, j + 1), []).append(((i, j + 1), k))
            if not inside(i - 1, j):
                out.setdefault((i, j + 1), []).append(((i, j), k))
    if not out:
        return []
    start = min(out, key=lambda p: (p[1], p[0]))
    loop = []
    current, previous_dir = start, (1, 0)
    used = set()
    for _ in range(4 * w * h):
        options = [e for e in out.get(current, ()) if (current, e[0]) not in used]
        if not options:
            break
        if len(options) > 1:
            # Saddle corner: diagonal cells count as one silhouette, so turn right first.
            def turn(edge):
                dx, dy = edge[0][0] - current[0], edge[0][1] - current[1]
                return previous_dir[0] * dy - previous_dir[1] * dx
            options.sort(key=turn)
        nxt, owner_cell = options[0]
        used.add((current, nxt))
        mid_u = raster.u0 + (current[0] + nxt[0]) * 0.5 * cell
        mid_v = raster.v0 + (current[1] + nxt[1]) * 0.5 * cell
        loop.append((mid_u, mid_v, raster.owner[owner_cell]))
        previous_dir = (nxt[0] - current[0], nxt[1] - current[1])
        current = nxt
        if current == start:
            break
    return loop


def resample(loop, step):
    """Even arc-length samples of a closed loop; keeps the nearest owner."""
    if len(loop) < 3:
        return list(loop)
    pts = loop + [loop[0]]
    lengths = [0.0]
    for a, b in zip(pts, pts[1:]):
        lengths.append(lengths[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    total = lengths[-1]
    count = max(8, int(total / step))
    out = []
    seg = 0
    for n in range(count):
        s = total * n / count
        while lengths[seg + 1] < s:
            seg += 1
        a, b = pts[seg], pts[seg + 1]
        span = lengths[seg + 1] - lengths[seg]
        t = 0.0 if span == 0.0 else (s - lengths[seg]) / span
        owner = a[2] if t < 0.5 else b[2]
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, owner))
    return out


def turning(samples, window):
    """Signed turn (radians) at each sample between chords ``window`` samples long.

    Positive is a left turn: convex on a counter-clockwise outer loop.
    """
    n = len(samples)
    out = []
    for i in range(n):
        a, p, b = samples[(i - window) % n], samples[i], samples[(i + window) % n]
        ax, ay = p[0] - a[0], p[1] - a[1]
        bx, by = b[0] - p[0], b[1] - p[1]
        out.append(math.atan2(ax * by - ay * bx, ax * bx + ay * by))
    return out


def corners(samples, window, threshold_rad):
    """Isolated corners: local maxima of |turn| at or above ``threshold_rad``.

    Each corner reports its index, signed turn, and whether it stands out from
    the surrounding curve (``isolation`` is the turn minus the median |turn| of
    the samples three windows either side).
    """
    turns = turning(samples, window)
    n = len(turns)
    found = []
    for i in range(n):
        t = abs(turns[i])
        if t < threshold_rad:
            continue
        span = range(i - window, i + window + 1)
        if any(abs(turns[k % n]) > t or (abs(turns[k % n]) == t and k % n < i) for k in span if k % n != i):
            continue
        around = sorted(abs(turns[k % n]) for k in range(i - 3 * window, i + 3 * window + 1)
                        if abs(k - i) > window)
        median = around[len(around) // 2] if around else 0.0
        found.append({"index": i, "turn_rad": turns[i], "convex": turns[i] > 0.0, "isolation_rad": t - median})
    return found


def sample_points(loop, count=64):
    """``count`` points at even arc fractions, starting at the topmost point.

    The reproduction check compares these between a control and a rebuild.
    """
    if not loop:
        return []
    top = max(range(len(loop)), key=lambda k: (loop[k][1], -loop[k][0]))
    rotated = loop[top:] + loop[:top]
    total = 0.0
    pts = rotated + [rotated[0]]
    lengths = [0.0]
    for a, b in zip(pts, pts[1:]):
        total += math.hypot(b[0] - a[0], b[1] - a[1])
        lengths.append(total)
    out, seg = [], 0
    for n in range(count):
        s = total * n / count
        while lengths[seg + 1] < s:
            seg += 1
        a, b = pts[seg], pts[seg + 1]
        span = lengths[seg + 1] - lengths[seg]
        t = 0.0 if span == 0.0 else (s - lengths[seg]) / span
        out.append((round(a[0] + (b[0] - a[0]) * t, 5), round(a[1] + (b[1] - a[1]) * t, 5)))
    return out
