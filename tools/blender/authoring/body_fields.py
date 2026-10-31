"""Region fields for authoring passes on a skinned master (CHARACTER-SOURCE-001).

A field reshapes a body in its rest around joints that do not move: each
vertex moves by the weighted blend of its bones' targets, so a vertex shared
at a joint takes a blend of smooth fields, never a step.

- The torso (Hips/Spine/Chest) scales about the centre line by height: width,
  front depth and back depth separately, so the ribcage, the pectorals and the
  upper back are separate masses.
- Limbs, the clavicle (Shoulder) and the neck scale radially about their bone
  axis by the station along the bone.
- Two masses no section can draw: the pectorals push the front of the chest
  forward, the trapezius raises the slope from the neck to the shoulder.

A spec is plain data: `torso` (z, width, front, back) stations, `limbs`
{family: ((t, scale), ...)}, optional `pec` (metres, z, z-spread, |x|,
x-spread) and `traps` (metres, |x|, x-spread, z, z-spread).
"""

import math

from mathutils import Vector

TORSO_FAMILIES = ("Hips", "Spine", "Chest")
## The trapezius rides every bone of the girdle and neck it spans.
TRAP_FAMILIES = TORSO_FAMILIES + ("Neck", "Shoulder")


def piecewise(stations, at):
    if at <= stations[0][0]:
        return stations[0][1:]
    for (a, *va), (b, *vb) in zip(stations, stations[1:]):
        if at <= b:
            k = (at - a) / (b - a)
            return tuple(x + (y - x) * k for x, y in zip(va, vb))
    return stations[-1][1:]


def _bump(value, centre, spread):
    return math.exp(-((value - centre) / spread) ** 2)


def family(bone_name):
    return bone_name.split(".")[0]


def _torso(spec, p):
    stations = spec.get("torso")
    if not stations:
        return p.copy()
    sx, front, back = piecewise(stations, p.z)
    q = Vector((p.x * sx, p.y * (front if p.y < 0.0 else back), p.z))
    pec = spec.get("pec")
    if pec and p.y < 0.0:
        metres, z, z_spread, x, x_spread = pec
        q.y -= metres * _bump(p.z, z, z_spread) * _bump(abs(p.x), x, x_spread)
    return q


## Past the clavicle's tail is the arm: scaling there about the shoulder joint
## inflates a sphere (an isolated cap), so the clavicle's field fades out over
## this share of its length beyond the joint.
CLAVICLE_PAST_JOINT_FADE = 0.3


def _limb(stations, p, head, tail, fade_past_tail=None):
    axis = tail - head
    length = axis.length
    direction = axis / length
    along = (p - head).dot(direction) / length
    t = max(0.0, min(1.0, along))
    foot = head + direction * (t * length)
    (scale,) = piecewise(stations, t)
    if fade_past_tail and along > 1.0:
        scale = 1.0 + (scale - 1.0) * max(0.0, 1.0 - (along - 1.0) / fade_past_tail)
    return foot + (p - foot) * scale


## The trapezius is the top and back of the girdle: full behind the shoulder
## line, gone across the front of the chest, so a raised trapezius never lifts
## the clavicle line the arm rises against (Blender -Y is forward).
TRAP_FRONT_FADE_Y = (-0.08, 0.02)


def _traps(spec, p):
    traps = spec.get("traps")
    if not traps:
        return 0.0
    metres, x, x_spread, z, z_spread = traps
    front, back = TRAP_FRONT_FADE_Y
    behind = max(0.0, min(1.0, (p.y - front) / (back - front)))
    return metres * behind * _bump(abs(p.x), x, x_spread) * _bump(p.z, z, z_spread)


def target(spec, p, bone_name, bones):
    kind = family(bone_name)
    if kind in TORSO_FAMILIES:
        q = _torso(spec, p)
    elif kind in spec.get("limbs", {}):
        head, tail = bones[bone_name]
        fade = CLAVICLE_PAST_JOINT_FADE if kind == "Shoulder" else None
        q = _limb(spec["limbs"][kind], p, head, tail, fade)
    else:
        q = p.copy()
    if kind in TRAP_FAMILIES:
        q.z += _traps(spec, p)
    return q


def displaced(body, rig, spec, coords):
    """New rest coordinates: `coords` moved by the spec's field."""
    names = {g.index: g.name for g in body.vertex_groups}
    bones = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in rig.data.bones}
    out = []
    for vertex, p in zip(body.data.vertices, coords):
        moved = Vector()
        for group in vertex.groups:
            name = names[group.group]
            moved += (target(spec, p, name, bones) - p) * group.weight
        out.append(p + moved)
    return out
