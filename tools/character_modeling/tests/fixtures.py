"""Synthetic meshes with known shapes and known defects."""

from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from character_modeling.mesh_data import MeshData  # noqa: E402


def revolve(profile, sides, name="revolve", radius_at=None):
    """Closed surface of revolution about Z. ``profile`` is [(z, r)], first and last r == 0 (poles).

    ``radius_at(z, angle, r)`` may perturb a ring radius per vertex.
    """
    verts, faces = [], []
    rings = []
    for z, r in profile:
        if r == 0.0:
            rings.append([len(verts)])
            verts.append((0.0, 0.0, z))
            continue
        ring = []
        for k in range(sides):
            angle = math.tau * k / sides
            rr = radius_at(z, angle, r) if radius_at else r
            ring.append(len(verts))
            verts.append((rr * math.sin(angle), -rr * math.cos(angle), z))
        rings.append(ring)
    for lower, upper in zip(rings, rings[1:]):
        if len(lower) == 1:
            for k in range(sides):
                faces.append((lower[0], upper[(k + 1) % sides], upper[k]))
        elif len(upper) == 1:
            for k in range(sides):
                faces.append((lower[k], lower[(k + 1) % sides], upper[0]))
        else:
            for k in range(sides):
                faces.append((lower[k], lower[(k + 1) % sides], upper[(k + 1) % sides], upper[k]))
    return MeshData(verts, faces, name=name)


def capsule_profile(radius, z0, z1, ring_step, cap_rings=10, radius_of_z=None):
    """Hemispherical caps sized to the body's own end radii, so only authored changes show."""
    r0 = radius_of_z(z0) if radius_of_z else radius
    r1 = radius_of_z(z1) if radius_of_z else radius
    profile = [(z0 - r0, 0.0)]
    for k in range(1, cap_rings):
        a = math.pi / 2.0 * (1.0 - k / cap_rings)
        profile.append((z0 - r0 * math.sin(a), r0 * math.cos(a)))
    count = int(round((z1 - z0) / ring_step))
    for k in range(count + 1):
        z = z0 + (z1 - z0) * k / count
        profile.append((z, radius_of_z(z) if radius_of_z else radius))
    for k in range(1, cap_rings):
        a = math.pi / 2.0 * k / cap_rings
        profile.append((z1 + r1 * math.sin(a), r1 * math.cos(a)))
    profile.append((z1 + r1, 0.0))
    return profile


def capsule(radius=0.1, z0=0.0, z1=0.6, ring_step=0.01, sides=48, radius_of_z=None):
    return revolve(capsule_profile(radius, z0, z1, ring_step, radius_of_z=radius_of_z), sides, "capsule")


def stepped_capsule(step_z=0.3, before=0.10, after=0.115, ring_step=0.01, sides=48):
    def radius(z):
        return before if z < step_z else after
    return capsule(radius=before, ring_step=ring_step, sides=sides, radius_of_z=radius)


def sphere(radius=0.1, rings=32, sides=64, radius_at=None):
    profile = [(-radius * math.cos(math.pi * k / rings), radius * math.sin(math.pi * k / rings)) for k in range(rings + 1)]
    profile[0] = (profile[0][0], 0.0)
    profile[-1] = (profile[-1][0], 0.0)
    return revolve(profile, sides, "sphere", radius_at=radius_at)


def box(size=0.2):
    h = size / 2.0
    verts = [(x, y, z) for z in (-h, h) for y in (-h, h) for x in (-h, h)]
    faces = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
    return MeshData(verts, faces, name="box")


def displaced(mesh, func):
    """Copy of ``mesh`` with every vertex moved along its radial direction by ``func(v)`` metres."""
    verts = []
    for v in mesh.vertices:
        length = math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2) or 1.0
        d = func(v)
        verts.append(tuple(c + c / length * d for c in v))
    return MeshData(verts, mesh.faces, mesh.face_flags, mesh.name)


def roof(angle_deg=34.0, half_width=0.08, height=0.16, columns=16, rows=16):
    """Two flat panels meeting at a vertical centre ridge at x = 0. An open sheet:
    creases read only shared edges, and a closing box would join the ridge's cluster.

    Returns the mesh and the face indices touching the centre column.
    """
    slope = math.tan(math.radians(angle_deg) / 2.0)
    verts, faces = [], []
    grid = []
    for r in range(rows + 1):
        z = height * r / rows
        row = []
        for c in range(-columns, columns + 1):
            x = half_width * c / columns
            row.append(len(verts))
            verts.append((x, -0.05 + abs(x) * slope, z))
        grid.append(row)
    ridge = []
    for r in range(rows):
        for c in range(2 * columns):
            index = len(faces)
            faces.append((grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c]))
            if c in (columns - 1, columns):
                ridge.append(index)
    return MeshData(verts, faces, name="roof"), ridge


def uniform_labels(mesh, region):
    return [(region, 1.0, None)] * len(mesh.vertices)


def landmarks():
    """A plausible figure frame for region classification."""
    def side(sign):
        return {
            "shoulder": (0.2 * sign, 0.0, 1.45), "elbow": (0.47 * sign, 0.0, 1.26),
            "wrist": (0.7 * sign, 0.0, 1.1), "palm": (0.75 * sign, 0.0, 1.07),
            "hip": (0.1 * sign, 0.0, 0.95), "knee": (0.1 * sign, 0.0, 0.5),
            "ankle": (0.1 * sign, 0.0, 0.09), "toe": (0.1 * sign, -0.16, 0.03),
        }
    return {"chin_z": 1.6, "shoulder_z": 1.45, "chest_z": 1.3, "waist_z": 1.1, "hip_z": 0.95,
            "crotch_z": 0.85, "torso_center_y": 0.0, "joints": {"L": side(1.0), "R": side(-1.0)}}
