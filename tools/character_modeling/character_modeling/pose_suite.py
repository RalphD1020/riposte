"""The preset pose suite (POSE-SUITE-001): versioned stress fixtures for the dressed character.

Each fixture is data, applied in Blender to every physique and character alike
(`tools/blender/authoring/pose_fixture.py`). Angles are world-space degrees from the rig's
rest (the relaxed A-pose, arms ARM_DROP_FROM_HORIZONTAL_DEG below horizontal), so 35 deg of
`elevate` brings an arm to horizontal:

  elevate   the arm raised out to the side, total, shoulder girdle included;
  clavicle  the share of `elevate` the clavicle (`Shoulder.*`) takes, as a fraction. A real
            arm raise moves the shoulder girdle too (scapulohumeral rhythm, about one part in
            three above horizontal); a raise of the upper arm alone is kept as a diagnostic
            of the worst case, never as the acceptance pose;
  forward   the arm swung forward (negative) or back about the shoulder;
  bend      elbow flexion of the forearm;
  twist     the torso turned about the vertical (`Spine`, then `Chest` half of it each);
  head      `yaw` (turned about the vertical, positive to the left) and `pitch` (positive
            looking down), the neck taking NECK_SHARE of each and the head the rest.

`samples` walks each fixture's `fractions` (0.25, 0.5, 1.0 by default): an arm raise can
look right at both ends and fail in between. A fixture changes only as an intentional,
documented change to this contract, never to let a model pass.
"""

from __future__ import annotations

from .pose import ARM_DROP_FROM_HORIZONTAL_DEG

VERSION = 2
RIG = "WolfRig"
SIDES = ("L", "R")
ARM_KEYS = ("elevate", "clavicle", "forward", "bend")
HEAD_KEYS = ("yaw", "pitch")
NECK_SHARE = 0.4
## Above this share the clavicle takes more than the shoulder girdle can.
MAX_CLAVICLE_SHARE = 0.4
DEFAULT_FRACTIONS = (0.25, 0.5, 1.0)
VIEWS = ("front", "side", "rear", "three_quarter")
HORIZONTAL = ARM_DROP_FROM_HORIZONTAL_DEG


def _arms(**arm):
    return {"L": dict(arm), "R": dict(arm)}


FIXTURES = (
    {"id": "arms_horizontal", "source": "the T-pose silhouette; the armhole's widest lateral opening",
     "stress": "armhole and underarm lateral stretch", "arms": _arms(elevate=HORIZONTAL, clavicle=0.1)},
    {"id": "arms_raise", "source": "a raise to the side, sword above the shoulder",
     "stress": "underarm fabric, vest armhole, shoulder cap", "arms": _arms(elevate=65.0, clavicle=0.3)},
    {"id": "arms_overhead", "source": "the overswing's high point",
     "stress": "full shoulder elevation, collar clearance", "arms": _arms(elevate=110.0, clavicle=0.33)},
    {"id": "one_arm_up", "source": "asymmetric sword-ready and recovery",
     "stress": "asymmetric chest and back loading",
     "arms": {"L": {"elevate": 110.0, "clavicle": 0.33}, "R": {"elevate": -10.0, "clavicle": 0.0}}},
    {"id": "arms_forward", "source": "both hands forward on the grip",
     "stress": "upper back stretch, chest compression, sleeve rotation", "arms": _arms(forward=-90.0, clavicle=0.0)},
    {"id": "guard", "source": "the forward guard with the elbows bent",
     "stress": "sleeve and bracer at the elbow", "arms": _arms(forward=-70.0, bend=70.0)},
    {"id": "twist_raise", "source": "a turned torso with the sword arm raised",
     "stress": "combined shoulder, chest and waist loading", "twist": 25.0,
     "arms": {"L": {"elevate": 65.0, "clavicle": 0.3}, "R": {"forward": -40.0}}},
    {"id": "head_turn", "source": "looking over the shoulder at an opponent circling",
     "stress": "neckwear and hair at the jaw and nape, mouth coverage", "head": {"yaw": 50.0}},
    {"id": "head_down", "source": "looking down at a fallen opponent or the blade",
     "stress": "neckwear top edge at the nose, chin into the collar", "head": {"pitch": 35.0}},
    {"id": "head_up", "source": "looking up from a knockdown",
     "stress": "neckwear and collar opening at the throat", "head": {"pitch": -30.0}},
    {"id": "turn_twist_raise", "source": "a turned head over a turned torso with the sword arm raised",
     "stress": "combined head, neck, shoulder and waist loading", "twist": 25.0, "head": {"yaw": -35.0, "pitch": 15.0},
     "arms": {"L": {"elevate": 65.0, "clavicle": 0.3}, "R": {"forward": -40.0}}},
    {"id": "arms_raise_no_clavicle", "source": "diagnostic: the upper arm raised with the shoulder girdle locked",
     "stress": "the worst case the skin weights alone must survive", "diagnostic": True,
     "arms": _arms(elevate=65.0, clavicle=0.0)},
)


def fixture(fid):
    for f in FIXTURES:
        if f["id"] == fid:
            return f
    raise KeyError(fid)


def scaled(f, t):
    """Fixture `f` at fraction `t` of its motion (every angle scaled; shares unchanged)."""
    arms = {s: {k: (v if k == "clavicle" else v * t) for k, v in a.items()} for s, a in f.get("arms", {}).items()}
    head = {k: v * t for k, v in f.get("head", {}).items()}
    return {"id": f["id"], "t": t, "arms": arms, "twist": f.get("twist", 0.0) * t, "head": head}


def samples(include_diagnostic=True):
    """Every (fixture id @ fraction) sample of the suite, in order."""
    out = []
    for f in FIXTURES:
        if f.get("diagnostic") and not include_diagnostic:
            continue
        for t in f.get("fractions", DEFAULT_FRACTIONS):
            out.append(scaled(f, t))
    return out


def problems():
    """Contract checks on the fixture data itself."""
    out, seen = [], set()
    for f in FIXTURES:
        fid = f.get("id")
        if not fid or fid in seen:
            out.append("fixture id %r missing or repeated" % fid)
        seen.add(fid)
        for key in ("source", "stress"):
            if not f.get(key):
                out.append("%s: names its %s" % (fid, key))
        for side, arm in f.get("arms", {}).items():
            if side not in SIDES:
                out.append("%s: unknown side %s" % (fid, side))
            stray = sorted(set(arm) - set(ARM_KEYS))
            if stray:
                out.append("%s: unknown arm keys %s" % (fid, stray))
            if not 0.0 <= arm.get("clavicle", 0.0) <= MAX_CLAVICLE_SHARE:
                out.append("%s: clavicle share outside [0, %s]" % (fid, MAX_CLAVICLE_SHARE))
        stray = sorted(set(f.get("head", {})) - set(HEAD_KEYS))
        if stray:
            out.append("%s: unknown head keys %s" % (fid, stray))
        if any(not 0.0 < t <= 1.0 for t in f.get("fractions", DEFAULT_FRACTIONS)):
            out.append("%s: fractions lie in (0, 1]" % fid)
    return out
