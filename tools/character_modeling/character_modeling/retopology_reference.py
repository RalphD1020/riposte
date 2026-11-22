"""RETOPOLOGY-REFERENCE-001: the one body a production retopology is fitted to.

The production body is fitted to the evaluated, processed, symmetric default body (the
foundation's `id_reference` built by the symmetric pipeline at rest), never to the raw `BodyV2`
sculpt that body is built from. The two look alike (same topology family, same height), yet the
raw sculpt predates the approved chest, glute, girth and side-profile corrections (up to 24 mm,
3 cm deeper). Two valid-looking files hold different stages of the same anatomy; this module
pins the right stage and rejects the rest before any fitting begins.

A pin records what the reference is (role, canonical geometry digest of the evaluated rest mesh
in world metres, symmetry), where it came from (foundation document and builder digests, the
resolved configuration), what it is fitted against (the rig's rest digest and contract, the clip
contract) and in which frame. `problems(pin, observation)` compares a builder's observation of
its inputs with the pin; a builder fits nothing while it is non-empty. Every region of one build
receives the same observed reference, so no region can fit a different body revision.

Pure Python: no Blender. The Blender side (`tools/blender/authoring/production_body.py`)
observes the scene and calls this.
"""

from __future__ import annotations

from . import geometry, symmetry

SCHEMA = "riposte.retopology_reference"
VERSION = 1
ROLE = "processed_default_symmetric"
## Historical inputs that must never be fitted to: the raw sculpt and its Symmetrize copy.
RAW_SCULPT_OBJECTS = ("BodyV2", "BodyV2_sym")
## The frame every observation is taken in.
FRAME = {"space": "world", "units": "m", "up": "+Z", "forward": "-Y", "pose": "rest"}
## Rest-pose joint positions are equal within this (metres): saved-blend rounding.
REST_DECIMALS = 5
## A clip "moves the rig" when some bone leaves its rest by more than this at its middle frame.
CLIP_MOTION_M = 1e-4
SYMMETRY_TOLERANCE_M = 0.001


def rest_digest(bones):
    """The rig's rest identity: each bone's name, parent, head and tail, rounded."""
    rows = sorted([name, parent or "", [round(c, REST_DECIMALS) for c in head], [round(c, REST_DECIMALS) for c in tail]]
                  for name, parent, head, tail in bones)
    return geometry.digest(rows)


def observe(vertices, faces, source_object, bones, clip_motion, frame=None):
    """What a builder sees: the target mesh (world vertices, face index lists) and its object
    name, the rig's rest bones [(name, parent, head, tail)], and per clip the largest bone
    displacement (m) at its middle frame, evaluated through the rig."""
    _problems, stats = symmetry.mirror_problems(vertices, tolerance=SYMMETRY_TOLERANCE_M, midline_eps=2 * SYMMETRY_TOLERANCE_M)
    return {"source_object": source_object,
            "geometry": {"vertices": len(vertices), "faces": len(faces),
                         "sha256": geometry.mesh_digest(vertices, [(list(f), ()) for f in faces]),
                         "symmetric": bool(stats["symmetric"])},
            "rig_rest_sha256": rest_digest(bones),
            "clips": {name: round(motion, 6) for name, motion in clip_motion.items()},
            "frame": dict(frame or FRAME)}


def pin(observation, provenance, clip_contract):
    """A pin from an observation of the approved reference, its provenance (foundation id and
    document digest, builder digest, resolved configuration, rig contract) and the clip
    contract (the fighter's named clips)."""
    return {"schema": SCHEMA, "version": VERSION, "role": ROLE,
            "source_object": observation["source_object"],
            "geometry": observation["geometry"], "rig_rest_sha256": observation["rig_rest_sha256"],
            "clip_contract": sorted(clip_contract), "frame": observation["frame"],
            "provenance": provenance}


def problems(reference, observation):
    """Why `observation` is not the pinned reference (empty when it is)."""
    out = []
    if reference.get("schema") != SCHEMA or reference.get("role") != ROLE:
        out.append("the pin is not a %s %s pin" % (SCHEMA, ROLE))
    source = observation["source_object"]
    if source in RAW_SCULPT_OBJECTS:
        out.append("%s is the raw sculpt (a historical input): fit the processed default body, never the sculpt" % source)
    want, got = reference["geometry"], observation["geometry"]
    if got["sha256"] != want["sha256"]:
        out.append("target %s is not the pinned processed default (geometry %s..., pinned %s...; %d vs %d vertices)"
                   % (source, got["sha256"][:12], want["sha256"][:12], got["vertices"], want["vertices"]))
    if not got["symmetric"]:
        out.append("target %s is not bilaterally symmetric" % source)
    if observation["rig_rest_sha256"] != reference["rig_rest_sha256"]:
        out.append("the rig's rest is not the pinned WolfRigNeutral rest")
    if observation["frame"] != reference["frame"]:
        out.append("observed in frame %s, pinned %s" % (observation["frame"], reference["frame"]))
    clips = observation["clips"]
    missing = [c for c in reference["clip_contract"] if c not in clips]
    if missing:
        out.append("clips missing from the scene: %s" % ", ".join(missing))
    still = sorted(c for c in reference["clip_contract"] if c in clips and clips[c] <= CLIP_MOTION_M)
    if still:
        out.append("clips present but not moving the rig when evaluated: %s" % ", ".join(still))
    return out
