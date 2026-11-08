"""The face expressions every character shares (FACE-EXPRESSION-001).

An expression is a preset: authored weights of the shared eye-assembly channels
(`eye_assembly.CHANNELS`: brow, upper lid, lower lid), per side, so the asymmetry
is designed rather than mirrored, plus a default gaze. Presets are data, never
generated at runtime; Godot mirrors this table (a tooling test keeps them equal)
and adds gaze toward its target and blinks on events.

Neutral is the rest geometry: composed, lids about 80 % open, brows on the ridge.
`dead` swaps the eyes for the X (visibility) and keeps the neutral brows.
"""

from . import eye_assembly

VERSION = 4
NEUTRAL = "neutral"
DEAD = "dead"
## Order is the presentation's order.
PRESETS = {
    NEUTRAL: {"L": {}, "R": {}, "gaze": (0.0, 0.0)},
    ## Settled and sure: the brows sit level and low, the upper lids drop a touch, the
    ## lower lids firm; one outer brow lifts a little (the left), never a frown.
    "confident": {
        "L": {"brow_inner_down": 0.25, "brow_tension": 0.3, "brow_outer_up": 0.12, "lid_upper_close": 0.14,
              "lid_lower_tension": 0.3},
        "R": {"brow_inner_down": 0.3, "brow_tension": 0.35, "brow_outer_down": 0.15, "lid_upper_close": 0.18,
              "lid_lower_tension": 0.3},
        "gaze": (0.0, 0.0),
    },
    ## Focused and dangerous: the inner brows compress toward the bridge under tension, the
    ## upper lids lower decisively at the inner end, the lower lids tense; the left side
    ## leads. The aperture narrows without collapsing: the iris stays readable on the far
    ## eye of a three-quarter view (a squint at the corners reads as closed eyes there).
    "aggressive": {
        "L": {"brow_inner_down": 0.9, "brow_tension": 0.8, "brow_outer_up": 0.15, "lid_upper_close": 0.3,
              "lid_upper_inner_down": 0.4, "lid_lower_tension": 0.45, "lid_lower_raise": 0.18},
        "R": {"brow_inner_down": 0.72, "brow_tension": 0.65, "brow_outer_up": 0.3, "lid_upper_close": 0.24,
              "lid_upper_inner_down": 0.3, "lid_lower_tension": 0.35, "lid_lower_raise": 0.12},
        "gaze": (0.0, -0.1),
    },
    ## Attentive and watchful: the eyes open and the brows lift a little and evenly (the
    ## inner brow never rises: a raised inner brow reads as worry); the right side leads.
    "alert": {
        "L": {"brow_outer_up": 0.3, "brow_inner_down": 0.05, "lid_upper_open": 0.65, "lid_upper_outer_up": 0.2,
              "lid_lower_relax": 0.25},
        "R": {"brow_outer_up": 0.4, "brow_inner_down": 0.05, "lid_upper_open": 0.75, "lid_upper_outer_up": 0.28,
              "lid_lower_relax": 0.3},
        "gaze": (0.0, 0.05),
    },
    DEAD: {"L": {}, "R": {}, "gaze": (0.0, 0.0), "eyes": "x"},
}
EXPRESSIONS = tuple(PRESETS)
## The preset channels a blink fades out.
LID_CHANNELS = eye_assembly.UPPER_CHANNELS + eye_assembly.LOWER_CHANNELS
## Presets that move geometry (the rest are visibility or rest).
KEYED = tuple(name for name, preset in PRESETS.items() if preset["L"] or preset["R"])


def weights(name, side, gaze=None, blink=0.0):
    """The channel weights of preset `name` on `side`, with a gaze (horizontal: + the
    character's left; vertical: + up; default the preset's) and a blink weight. A blink
    closes from the rest aperture: the preset's lid channels and the vertical gaze (which
    moves the edges too) fade out as it rises, so the closed line is the same under every
    preset and gaze (the keys add linearly; a lid already lowered would otherwise close
    past the lower edge, a raised one stay open)."""
    if name not in PRESETS:
        raise KeyError("expressions: unknown %r (known: %s)" % (name, ", ".join(PRESETS)))
    preset = PRESETS[name]
    keep = 1.0 - min(max(blink, 0.0), 1.0)
    out = {c: (w * keep if c in LID_CHANNELS else w) for c, w in preset[side].items()}
    h, v = preset["gaze"] if gaze is None else gaze
    if h:
        out["gaze_left" if h > 0 else "gaze_right"] = abs(h)
    if v:
        out["gaze_up" if v > 0 else "gaze_down"] = abs(v) * keep
    if blink:
        out[eye_assembly.BLINK] = blink
    return out


def problems():
    """Presets naming a channel that is not shared, or a weight outside 0..1."""
    out = []
    for name, preset in PRESETS.items():
        for side in ("L", "R"):
            for channel, w in preset[side].items():
                if channel not in eye_assembly.CHANNELS:
                    out.append("%s.%s: unknown channel %s" % (name, side, channel))
                if not 0.0 <= w <= 1.0:
                    out.append("%s.%s: %s weight %.2f outside 0..1" % (name, side, channel, w))
    return out
