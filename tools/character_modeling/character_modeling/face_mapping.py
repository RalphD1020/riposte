"""Facial mapping (FACE-MAPPING-001): semantic face landmarks and the face surface chart
facial components attach through.

The mask is a convex, front-facing surface, so its chart is the one Wolf's marks already
use: u is x as a fraction of the head's half-width (signed, left positive), v is the
height above the head's lowest point as a fraction of its height, and the surface is the
forward-most point at (u, v). A Blender adapter samples that surface on a grid
(`tools/blender/inspect/face_surface.py`); everything here is pure.

A component (eye, lid, brow, cheek mark, hairline) never stores a vertex index. It stores
an attachment: a landmark, the surface region it must stay in, offsets along the
surface's tangents and normal, and an orientation rule. Its frame is resolved against
whichever head it is fitted to, so a new head topology, head profile or physique keeps
it attached as long as the landmarks resolve.
"""

from __future__ import annotations

import math

SCHEMA = "riposte.face_surface"
KIND = "face_surface"

## Landmark groups (paired names get .L/.R; central ones sit on the centre line).
LANDMARK_GROUPS = {
    "eyes": ("eye_centre", "eye_inner", "eye_outer"),
    "brows": ("brow_inner", "brow_apex", "brow_outer"),
    "brow_ridge": ("ridge_apex",),
    "cheeks": ("cheekbone_apex",),
    "nose": ("nose_root", "nose_tip", "nose_lateral"),
    "chin": ("chin_apex",),
    "jaw": ("jaw_transition",),
    "head": ("forehead_centre", "temple"),
}
CENTRAL = ("nose_root", "nose_tip", "chin_apex", "forehead_centre")
PAIRED = tuple(n for names in LANDMARK_GROUPS.values() for n in names if n not in CENTRAL)
## Regions of the chart a component may occupy: (u_min, u_max, v_min, v_max) for the left
## side (mirrored for the right); central regions span the centre line.
REGIONS = {
    "eye_opening": (0.12, 0.62, 0.48, 0.60),
    "brow_surface": (0.08, 0.75, 0.56, 0.72),
    "cheek_surface": (0.35, 0.90, 0.30, 0.52),
    "nose_surface": (-0.25, 0.25, 0.25, 0.68),
    "forehead_surface": (-0.80, 0.80, 0.62, 0.95),
}
CENTRAL_REGIONS = ("nose_surface", "forehead_surface")
ORIENTATIONS = ("follow_surface", "head_aligned")
SYMMETRY_TOLERANCE_M = 0.001
NOSE_PROUD_M = 0.002
## A surface faces forward when its normal is within about 45 degrees of -y.
FORWARD_FACING = 0.7


def landmark_names():
    out = []
    for names in LANDMARK_GROUPS.values():
        for name in names:
            out.extend([name] if name in CENTRAL else ["%s.L" % name, "%s.R" % name])
    return out


class FaceSurface:
    """The sampled mask: `positions[j][i]` is the surface point at (u[i], v[j]) in metres
    (head space), `normals` the outward normals; `frame` is the head's low, height and
    half_width (the chart's scale)."""

    def __init__(self, data):
        if data.get("schema") != SCHEMA:
            raise ValueError("face surface: schema %r, expected %r" % (data.get("schema"), SCHEMA))
        self.u = list(data["u"])
        self.v = list(data["v"])
        self.positions = data["positions"]
        self.normals = data["normals"]
        self.frame = data["frame"]
        if len(self.positions) != len(self.v) or any(len(row) != len(self.u) for row in self.positions):
            raise ValueError("face surface: positions are not a %d x %d grid" % (len(self.v), len(self.u)))

    def _locate(self, axis, value):
        if value < axis[0] or value > axis[-1]:
            raise ValueError("face surface: %.3f is outside the sampled chart [%.3f, %.3f]" % (value, axis[0], axis[-1]))
        for i in range(len(axis) - 1):
            if value <= axis[i + 1]:
                return i, (value - axis[i]) / (axis[i + 1] - axis[i])
        return len(axis) - 2, 1.0

    def _bilinear(self, grid, u, v):
        i, s = self._locate(self.u, u)
        j, t = self._locate(self.v, v)
        a, b, c, d = grid[j][i], grid[j][i + 1], grid[j + 1][i], grid[j + 1][i + 1]
        return tuple((a[k] * (1 - s) + b[k] * s) * (1 - t) + (c[k] * (1 - s) + d[k] * s) * t for k in range(3))

    def position(self, u, v):
        return self._bilinear(self.positions, u, v)

    def normal(self, u, v):
        return _unit(self._bilinear(self.normals, u, v))

    def _step(self):
        return (self.u[1] - self.u[0]) * 0.5, (self.v[1] - self.v[0]) * 0.5

    def _derivative(self, u, v, axis):
        hu, hv = self._step()
        du, dv = (hu, 0.0) if axis == "u" else (0.0, hv)
        lo = (max(u - du, self.u[0]), max(v - dv, self.v[0]))
        hi = (min(u + du, self.u[-1]), min(v + dv, self.v[-1]))
        span = (hi[0] - lo[0]) if axis == "u" else (hi[1] - lo[1])
        return _scale(_sub(self.position(*hi), self.position(*lo)), 1.0 / span)

    def tangents(self, u, v):
        """(horizontal, vertical) unit tangents, orthogonal to the normal and each other;
        horizontal points toward +u (the left), vertical upward."""
        n = self.normal(u, v)
        tu = _unit(_reject(self._derivative(u, v, "u"), n))
        tv = _unit(_reject(_reject(self._derivative(u, v, "v"), n), tu))
        return tu, tv

    def curvature(self, u, v):
        """Normal curvature along u and v (1/m); positive is convex (bulging outward)."""
        hu, hv = self._step()
        n = self.normal(u, v)
        out = []
        for axis, h in (("u", hu), ("v", hv)):
            lo = (u - h, v) if axis == "u" else (u, v - h)
            hi = (u + h, v) if axis == "u" else (u, v + h)
            if not (self.u[0] <= lo[0] and hi[0] <= self.u[-1] and self.v[0] <= lo[1] and hi[1] <= self.v[-1]):
                out.append(0.0)
                continue
            p0, p1, p2 = self.position(*lo), self.position(u, v), self.position(*hi)
            second = _scale(_add(_sub(p0, p1), _sub(p2, p1)), 1.0 / (h * h))
            metric = _dot(*(2 * (self._derivative(u, v, axis),)))
            out.append(-_dot(second, n) / metric if metric > 0 else 0.0)
        return tuple(out)

    def chart(self, point):
        """(u, v) of a head-space point (the chart is a front projection)."""
        return point[0] / self.frame["half_width"], (point[2] - self.frame["low"]) / self.frame["height"]

    def project(self, point):
        """The surface point and (u, v) under a head-space point."""
        u, v = self.chart(point)
        return self.position(u, v), (u, v)

    def metres_per_unit(self, u, v):
        return math.sqrt(_dot(*(2 * (self._derivative(u, v, "u"),)))), math.sqrt(_dot(*(2 * (self._derivative(u, v, "v"),))))


def derive_landmarks(surface, identity, samples=41):
    """Landmarks in (u, v): the geometric ones measured on the surface, the identity ones
    (eyes, brows) from the character's mark fractions. `identity` holds the Eye and Brow
    marks (x, z, width as chart fractions)."""
    eye, brow = identity["Eye"], identity["Brow"]
    eye_v = eye["z"]

    def scan(u_range, v_range, score):
        u_range = (max(u_range[0], surface.u[0]), min(u_range[1], surface.u[-1]))
        v_range = (max(v_range[0], surface.v[0]), min(v_range[1], surface.v[-1]))
        best = None
        for a in range(samples):
            for b in range(samples):
                u = u_range[0] + (u_range[1] - u_range[0]) * a / (samples - 1)
                v = v_range[0] + (v_range[1] - v_range[0]) * b / (samples - 1)
                s = score(u, v)
                if best is None or s > best[0]:
                    best = (s, (u, v))
        return best[1]

    def forward(u, v):
        return -surface.position(u, v)[1]

    nose_tip = scan((0.0, 0.0), (0.25, eye_v), forward)
    nose_root = scan((0.0, 0.0), (eye_v - 0.05, eye_v + 0.12), lambda u, v: -forward(u, v))
    chin = scan((0.0, 0.0), (0.0, nose_tip[1] - 0.12), forward)
    ridge = scan((0.12, 0.6), (eye_v + 0.04, eye_v + 0.16), forward)
    ## The cheekbone apex: the strongest vertical convexity on the forward-facing panel
    ## (the head's sides curve too, but they face sideways).
    cheek = scan((0.4, 0.85), (nose_tip[1] - 0.05, eye_v - 0.06),
                 lambda u, v: surface.curvature(u, v)[1] if -surface.normal(u, v)[1] > FORWARD_FACING else -math.inf)
    ## The nose's lateral boundary: just above the tip, the outermost point still standing
    ## NOSE_PROUD_M proud of the panel (measured against the cheek at u 0.45).
    lateral_v = nose_tip[1] + 0.02
    lateral = (0.0, lateral_v)
    for a in range(samples):
        u = 0.35 * a / (samples - 1)
        if forward(u, lateral_v) > forward(0.45, lateral_v) + NOSE_PROUD_M:
            lateral = (u, lateral_v)
    paired = {
        "eye_centre": (eye["x"], eye_v),
        "eye_inner": (eye["x"] - eye["width"] / 2.0, eye_v),
        "eye_outer": (eye["x"] + eye["width"] / 2.0, eye_v),
        "brow_inner": (brow["x"] - brow["width"] / 2.0, brow["z"]),
        "brow_apex": (brow["x"], brow["z"]),
        "brow_outer": (brow["x"] + brow["width"] / 2.0, brow["z"]),
        "ridge_apex": ridge,
        "cheekbone_apex": cheek,
        "nose_lateral": lateral,
        "jaw_transition": (0.8, chin[1] + 0.05),
        "temple": (0.9, eye_v + 0.1),
    }
    out = {"nose_tip": nose_tip, "nose_root": nose_root, "chin_apex": chin, "forehead_centre": (0.0, min(0.9, eye_v + 0.25))}
    for name, (u, v) in paired.items():
        out["%s.L" % name] = (u, v)
        out["%s.R" % name] = (-u, v)
    return out


def landmark_problems(landmarks):
    """Missing landmarks, and paired landmarks that are not mirror images in the chart."""
    problems = []
    for name in landmark_names():
        if name not in landmarks:
            problems.append({"severity": "hard", "landmark": name, "message": "missing"})
    for name in PAIRED:
        left, right = landmarks.get("%s.L" % name), landmarks.get("%s.R" % name)
        if left and right and (abs(left[0] + right[0]) > 1e-6 or abs(left[1] - right[1]) > 1e-6):
            problems.append({"severity": "hard", "landmark": name, "message": "left and right are not mirrored"})
    for name in CENTRAL:
        if name in landmarks and abs(landmarks[name][0]) > 1e-6:
            problems.append({"severity": "hard", "landmark": name, "message": "off the centre line"})
    return problems


def _region_contains(region, u, v):
    u0, u1, v0, v1 = REGIONS[region]
    if region in CENTRAL_REGIONS:
        return u0 <= u <= u1 and v0 <= v <= v1
    return u0 <= abs(u) <= u1 and v0 <= v <= v1


def resolve(surface, landmarks, attachment):
    """The component's frame on this surface: origin, horizontal and vertical tangents,
    normal, and its (u, v). `attachment`: landmark, region, tangent_offset_m (along the
    horizontal and vertical tangents, mirrored with the side), normal_offset_m,
    orientation."""
    name = attachment["landmark"]
    if name not in landmarks:
        raise KeyError("face mapping: landmark %r is not on this face" % name)
    u, v = landmarks[name]
    side = -1.0 if name.endswith(".R") else 1.0
    du_m, dv_m = attachment.get("tangent_offset_m", (0.0, 0.0))
    mu, mv = surface.metres_per_unit(u, v)
    u, v = u + side * du_m / mu, v + dv_m / mv
    point = surface.position(u, v)
    normal = surface.normal(u, v)
    if attachment.get("orientation", "follow_surface") == "follow_surface":
        tu, tv = surface.tangents(u, v)
    else:
        tu, tv, normal = (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, -1.0, 0.0)
    origin = _add(point, _scale(normal, attachment.get("normal_offset_m", 0.0)))
    return {"origin": origin, "horizontal": tu, "vertical": tv, "normal": normal, "uv": (u, v)}


def attachment_problems(surface, landmarks, attachments):
    """Hard: an unknown landmark or orientation, a component outside its region, a
    component buried in the mask (negative normal offset), a pair that does not mirror."""
    problems = []
    frames = {}
    for component, attachment in attachments.items():
        if attachment.get("orientation", "follow_surface") not in ORIENTATIONS:
            problems.append({"severity": "hard", "component": component, "message": "unknown orientation %r" % attachment.get("orientation")})
            continue
        if attachment["landmark"] not in landmarks:
            problems.append({"severity": "hard", "component": component, "message": "landmark %r missing" % attachment["landmark"]})
            continue
        frame = resolve(surface, landmarks, attachment)
        frames[component] = frame
        if attachment.get("region") and not _region_contains(attachment["region"], *frame["uv"]):
            problems.append({"severity": "hard", "component": component, "message": "outside %s at uv %.3f, %.3f" % ((attachment["region"],) + frame["uv"])})
        if attachment.get("normal_offset_m", 0.0) < 0.0:
            problems.append({"severity": "hard", "component": component, "message": "buried %.4f m in the mask" % attachment["normal_offset_m"]})
    for component, frame in frames.items():
        if component.endswith(".L") and component[:-2] + ".R" in frames:
            a, b = frame["origin"], frames[component[:-2] + ".R"]["origin"]
            error = math.sqrt((a[0] + b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)
            if error > SYMMETRY_TOLERANCE_M:
                problems.append({"severity": "hard", "component": component[:-2], "message": "pair off mirror by %.4f m" % error})
    return problems, frames


def _add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def _sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def _scale(a, s):
    return tuple(x * s for x in a)


def _dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def _unit(a):
    length = math.sqrt(_dot(a, a))
    return _scale(a, 1.0 / length) if length > 0 else a


def _reject(a, n):
    return _sub(a, _scale(n, _dot(a, n)))
