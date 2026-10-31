"""Offline deformation weights for one production body.

Creation landmarks say where the surface is. This module says how that
surface follows WolfRig. It is a small deterministic function: a vertex's
deformation region names a few candidate bones, spatial falloff mixes those
candidates with the spine, then weights are pruned and normalized. It is not
a generic influence solver, and it does not run in Godot. Godot deforms the
imported skin with linear blend skinning.

At most four influences, so the Compatibility renderer can import the mesh.
"""

from __future__ import annotations

import math

from .anatomy import CLAVICLE_RIDGE_SHARE, TRANSITION_FADE_M, region_affinity

INFLUENCE_LIMIT = 4
PRUNE_WEIGHT = 0.02
# Width over which a torso ring blends between two spine bones (m).
SPINE_BLEND_M = 0.05
# The neck column (neck half-widths from the midline) inside which the mantle
# may ride the neck bone; outside it the trapezius is chest mass.
NECK_COLUMN_OF_NECK = 1.1


def _smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def normalize_weights(weights):
    """Merge, prune below ``PRUNE_WEIGHT``, keep the ``INFLUENCE_LIMIT``
    strongest, and normalize to one. Deterministic: ties break by bone name."""
    merged = {}
    for bone, w in weights:
        merged[bone] = merged.get(bone, 0.0) + w
    kept = sorted(((bone, w) for bone, w in merged.items() if w >= PRUNE_WEIGHT), key=lambda bw: (-bw[1], bw[0]))
    kept = kept[:INFLUENCE_LIMIT]
    total = sum(w for _bone, w in kept)
    return tuple((bone, w / total) for bone, w in kept)


def _mix(parts):
    """``[(weights, share), ...]`` -> one normalized weight tuple."""
    return normalize_weights([(bone, w * share) for weights, share in parts for bone, w in weights])


def _spine_weights(points, z, neck_root_z):
    """Two-bone blend up the spine by height, ``SPINE_BLEND_M`` wide at each
    boundary. The chest gives way to the neck at the neck root (the mantle
    top), not at the neck bone's head, which sits inside the mantle."""
    order = ("Hips", "Spine", "Chest", "Neck", "Head")
    bounds = (points["Spine"][0][2], points["Chest"][0][2], max(points["Neck"][0][2], neck_root_z),
              points["Head"][0][2])
    for index, edge in enumerate(bounds):
        if z < edge + SPINE_BLEND_M * 0.5:
            t = _smooth((z - (edge - SPINE_BLEND_M * 0.5)) / SPINE_BLEND_M)
            lower, upper = order[index], order[index + 1]
            if t <= 0.0:
                return ((lower, 1.0),)
            return ((lower, 1.0 - t), (upper, t))
    return (("Head", 1.0),)


def torso_region(position, landmarks, socket_side, socket_centre, ring_tag):
    """The deformation region of one torso vertex.

    ``socket_side`` is "L"/"R" for a vertex on a socket boundary, else None;
    ``socket_centre`` is its side's socket centre; ``ring_tag`` the tag of the
    torso ring it sits on.
    """
    x, y, z = position
    shoulder = landmarks.shoulders["L"]
    if socket_side is not None:
        if z >= shoulder.socket_z[2] - 1e-9:
            return "acromial"
        return "axilla" if z <= shoulder.socket_z[0] + 1e-9 else "socket_side"
    if ring_tag == "pelvis_opening":
        return "pelvis_opening"
    if ring_tag in ("glute", "hip_upper"):
        return ring_tag
    neck_x = landmarks.neck_root[0]
    if z >= shoulder.acromion[2] - 0.005 and abs(x) > neck_x * 0.85 and z <= landmarks.mantle_top_z + 0.005:
        return "trapezius"
    if math.dist(position, socket_centre) < TRANSITION_FADE_M[1] and z < shoulder.acromion[2]:
        return "pectoral" if y < 0.0 else "latissimus"
    return "spine"


def assign_torso(vertices, weights, regions, points, landmarks, stations, torso_end, chain, sockets, around):
    """Write torso and crotch weights from deformation regions.

    Each vertex's region row (``anatomy.region_affinity``) is mixed with the
    spine blend by distance or height, then normalized and pruned. Limb
    vertices are weighted by the loft that builds them; this function does
    not touch those.
    """
    on_socket = {index: side for side, loop in sockets.items() for index in loop}
    centres = {}
    for side, loop in sockets.items():
        n = float(len(loop))
        centres[side] = (
            sum(vertices[i][0] for i in loop) / n,
            sum(vertices[i][1] for i in loop) / n,
            sum(vertices[i][2] for i in loop) / n,
        )
    neck_x = landmarks.neck_root[0]
    neck_inner = landmarks.sizes["neck"] * NECK_COLUMN_OF_NECK
    acromion_x = landmarks.shoulders["L"].acromion[0]
    for index in range(torso_end):
        position = vertices[index]
        x, _y, z = position
        side = "L" if x >= 0.0 else "R"
        ring = index // around
        tag = stations[ring][3] if ring < len(stations) else None
        if ring == 1:
            tag = "glute"
        elif ring == 2:
            tag = "hip_upper"
        region = torso_region(position, landmarks, on_socket.get(index), centres[side], tag)
        base = _spine_weights(points, z, landmarks.mantle_top_z)
        if region == "spine":
            assigned = normalize_weights(base)
        elif region == "trapezius":
            # The ridge is chest mass: the neck bone (whose head sits below the
            # mantle) keeps only the neck column, or a head turn drags the shoulders.
            chest = _smooth((abs(x) - neck_inner) / (neck_x - neck_inner))
            share = CLAVICLE_RIDGE_SHARE * _smooth((abs(x) - neck_x) / (acromion_x - neck_x))
            assigned = _mix([(base, (1.0 - chest) * (1.0 - share)), ((("Chest", 1.0),), chest * (1.0 - share)),
                             ((("Shoulder." + side, 1.0),), share)])
        elif region in ("pectoral", "latissimus"):
            d = math.dist(position, centres[side])
            near = 1.0 - _smooth((d - TRANSITION_FADE_M[0]) / (TRANSITION_FADE_M[1] - TRANSITION_FADE_M[0]))
            assigned = _mix([(region_affinity(region, side), near), (base, 1.0 - near)])
        elif region in ("pelvis_opening", "glute", "hip_upper"):
            left = _smooth((x / max(abs(stations[ring][1]), 1e-6) + 0.35) / 0.7)
            assigned = _mix([(region_affinity(region, "L"), left), (region_affinity(region, "R"), 1.0 - left)])
        else:
            assigned = normalize_weights(region_affinity(region, side))
        weights[index] = assigned
        regions[index] = region
    for index in chain:
        weights[index] = normalize_weights(region_affinity("crotch", "L"))
        regions[index] = "crotch"
