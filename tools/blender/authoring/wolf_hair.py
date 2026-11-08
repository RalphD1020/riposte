"""Author Wolf's two hairstyles into `art-src/blender/characters/wolf/wolf_attire.blend`.

Hair is its own asset type (`art-src/blender/garments/wolf_hair_*.garment.json`,
`"type": "hair"`) built in the four levels of
docs/reference/blender-mcp-hair-clothing-production.md, as opaque sculpted geometry:

1. Scalp foundation: a grid of rays onto the base's skull from each style's hairline
   curve up to the crown, lifted off the skull — one clean hairline, never a helmet.
2. Primary masses from flow guides: tied hair is one continuous shell — guides run over
   the skull from the hairline to the style's gather point along great circles,
   alternating ridge and groove — and hanging hair (Training) is thick sheets of the
   same construction falling from under the tied section, their grooves stopping short
   of their ridges so the lower edge breaks into tapered points.
3. Secondary locks: a few lens-sectioned locks over the crown or the rear sheet,
   emerging from the volume, and the bun: a core wrapped by coiling locks.
4. Surface detail: the grooves sculpted into the shell and sheets are the strand
   direction; seeded variation in band width, volume and curvature keeps them from
   repeating like cables.

Each style has three review variants (`--ranger A|B|C`, `--training A|B|C`). Every
face is tagged with its clump (`riposte_mass` / `riposte_masses`, matched by the hair
definition's `design.regions` globs) and every clump's profile is recorded
(`riposte_locks`) so `character_modeling.hair_design` measures what was built.
Ranger is rigid on Head; Training's scalp, tied hair and bun are rigid on Head and its
hanging hair hands from Head to Neck by height. The base is linked read-only; nothing
here edits it. Refuses to rebuild an existing style without `--replace`.

    blender --background --factory-startup --python tools/blender/authoring/wolf_hair.py -- \
        [--replace] [--ranger A] [--training A]
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Quaternion, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
ATTIRE = os.path.join(ROOT, "art-src", "blender", "characters", "wolf", "wolf_attire.blend")
HEAD = "Head"
NECK = "Neck"

## The scalp foundation (see _cap).
CAP_LIFT_M = 0.004
CAP_THICKNESS_M = 0.008
CAP_AZIMUTH_STEPS = 24
CAP_ROWS = 7
CAP_TOP_ELEVATION = 88.0
## A clump's lens section (across, up): pointed edges, a raised ridge, a shallow keel.
LENS = ((-1.0, 0.0), (-0.55, 0.8), (0.0, 1.0), (0.55, 0.8), (1.0, 0.0), (0.0, -0.35))
KEEL = 0.35
## Sections along a guide.
RINGS = 7
HANGING_RINGS = 9
## Smooth sculpted shading; only the lens edges (the creases between clumps) stay sharp.
SHARP_DEGREES = 80.0
## Clumps whose tips show (hanging hair) taper to this share of their widest section.
TIP_WIDTH = 0.16
TIP_HEIGHT = 0.3
## Training's hanging hair hands from Head to Neck by height (head heights from the head
## island's lowest point) between HEAD_ONLY and NECK_FULL; no Chest share unless the
## clips prove it is needed. Influences below MIN_INFLUENCE snap to one bone.
HEAD_ONLY = 0.35
NECK_FULL = -0.35
MIN_INFLUENCE = 0.01
## Per-face clump index (face attribute), the names it indexes, and the clump profiles.
MASS_ATTRIBUTE = "riposte_mass"
MASS_NAMES = "riposte_masses"
LOCKS = "riposte_locks"
CAP_MASS = "Cap"
## Sector names by azimuth from the front: the definition's design regions glob these.
SECTORS = ((50.0, "Sweep"), (130.0, "Temple"), (181.0, "Nape"))

## Each style's hairline: elevation (degrees, seen from the head centre) by azimuth.
HAIRLINE_RANGER = ((0.0, 30.0), (45.0, 25.0), (90.0, 8.0), (135.0, -20.0), (180.0, -32.0))
HAIRLINE_TRAINING = ((0.0, 28.0), (45.0, 22.0), (90.0, 2.0), (135.0, -30.0), (180.0, -42.0))

## tied: the primary volume, one continuous shell from the hairline to `gather`
## (azimuth, elevation) along great circles. `bands` strand bands round the head, each a
## ridge guide with a groove guide between it and the next (`groove` m deep), so the
## strand direction is sculpted into one surface rather than made by separate tubes.
## `thickness` runs root -> mid -> end in metres above the scalp cap, `bulge` adds
## volume peaking at `peak` of the length, `swirl` bends a band sideways, `jitter` is
## the seeded variation. `crown` tapered locks layer over the top. `rear_floor` raises
## the roots behind the head (Training's lower hair hangs instead).
## bun: core radii (side, up, out) and the coiling wraps over it.
RANGER_VARIANTS = {
    "A": {"label": "tightly swept back, compact bun",
          "tied": {"gather": (180.0, 26.0), "bands": 18, "thickness": (0.002, 0.012, 0.006), "bulge": 0.004, "peak": 0.3,
                   "groove": 0.008, "swirl": 0.003, "jitter": 0.25, "crown": 2},
          "bun": {"radii": (0.034, 0.03, 0.028), "wraps": 3, "turn": 1.5}},
    "B": {"label": "fuller swept back, more sculpted flow",
          "tied": {"gather": (180.0, 28.0), "bands": 16, "thickness": (0.003, 0.016, 0.008), "bulge": 0.01, "peak": 0.3,
                   "groove": 0.011, "swirl": 0.008, "jitter": 0.3, "crown": 4},
          "bun": {"radii": (0.038, 0.033, 0.031), "wraps": 3, "turn": 1.6}},
    "C": {"label": "restrained, close-fitting, neat bun",
          "tied": {"gather": (180.0, 24.0), "bands": 22, "thickness": (0.002, 0.009, 0.005), "bulge": 0.002, "peak": 0.35,
                   "groove": 0.006, "swirl": 0.002, "jitter": 0.2, "crown": 0},
          "bun": {"radii": (0.03, 0.027, 0.025), "wraps": 3, "turn": 1.4}},
    ## Revision 5: B's approved silhouette and bun position with Training's finer surface
    ## (more, shallower bands; no crown locks) and a tighter, more disciplined bun.
    "D": {"label": "B refined: finer swept surface, tight warrior bun", "seat_cap": True,
          "tied": {"gather": (180.0, 28.0), "bands": 22, "thickness": (0.003, 0.013, 0.007), "bulge": 0.008, "peak": 0.3,
                   "groove": 0.007, "swirl": 0.006, "jitter": 0.25, "crown": 0},
          "bun": {"radii": (0.035, 0.031, 0.029), "wraps": 4, "turn": 1.8, "wrap_width": 0.95, "wrap_height": 0.22}},
}
## Revision 6 (candidate, shared groundwork): D unchanged plus primary flow masses over
## it: a crown mass, then two front sweeps parted a little off centre (the left over the
## right), each rooted just in front of the hairline so the hairline is hair, not the
## shell's edge, curving over the head and converging under the bun.
## A flow mass: `root` (azimuth, elevation offset from the hairline), `via` controls
## (azimuth, elevation), `end` (offset from the gather point), `width` / `height` root ->
## peak -> tip (m), `peak` (share of the length), `twist` (degrees of roll), `embed` (m
## sunk into the hair beneath).
RANGER_VARIANTS["F"] = dict(RANGER_VARIANTS["D"], label="D + flow masses: integrated hairline, crown and front sweeps into the bun",
                            ## The shell thinner under the masses: they carry the volume.
                            tied=dict(RANGER_VARIANTS["D"]["tied"], thickness=(0.002, 0.008, 0.005), bulge=0.004),
                            ## Roots flush with the scalp (height 0): a mass grows out of it.
                            flow=({"name": "Crown.Mass", "root": (4.0, 24.0), "via": ((6.0, 76.0), (172.0, 66.0)), "end": (0.0, 7.0),
                                   "width": (0.045, 0.075, 0.022), "height": (0.0, 0.008, 0.003), "peak": 0.4, "twist": 6.0, "embed": 0.002},
                                  {"name": "Sweep.Mass.R", "root": (-12.0, -3.0), "via": ((-22.0, 60.0), (-140.0, 62.0)), "end": (14.0, 3.0),
                                   "width": (0.06, 0.09, 0.02), "height": (0.0, 0.009, 0.003), "peak": 0.3, "twist": 9.0, "embed": 0.002},
                                  {"name": "Sweep.Mass.L", "root": (18.0, -3.0), "via": ((28.0, 58.0), (138.0, 60.0)), "end": (-14.0, 5.0),
                                   "width": (0.06, 0.092, 0.02), "height": (0.0, 0.0095, 0.003), "peak": 0.3, "twist": 9.0, "embed": 0.002}))
## Revision 7 (candidate, Ranger): F completed. Order matters (each mass lies on what is
## built before it): crown; temples sweeping back over the ears; the nape rising into the
## bun from below its hairline (no jagged edge); the front sweeps; secondary locks riding
## them with their tapered tips on the hair (`length` < 1); one short loose accent at the
## right temple (the only asymmetry beside the part); and a folded bun, a little fuller,
## lower and elongated, the gathered tips under it. Bun folds: (phase deg, reach deg,
## width and height as shares of the core's outward radius).
_RANGER_FLOW = RANGER_VARIANTS["F"]["flow"]
RANGER_VARIANTS["G"] = dict(
    RANGER_VARIANTS["F"], label="F completed: temples, nape, secondary locks, temple accent, folded bun",
    nape_clear=0.004, fit_head=True,
    tied=dict(RANGER_VARIANTS["F"]["tied"], gather=(180.0, 26.0), bands=14),
    bun={"radii": (0.036, 0.04, 0.03), "wraps": 0,
         "folds": ((45.0, 105.0, 1.2, 0.16), (135.0, 100.0, 1.1, 0.15))},
    flow=({"name": "Crown.Mass", "root": (4.0, 24.0), "via": ((6.0, 76.0), (172.0, 66.0)), "end": (0.0, 7.0),
           "width": (0.05, 0.085, 0.024), "height": (0.0, 0.006, 0.0025), "peak": 0.4, "twist": 6.0, "embed": 0.003},
          {"name": "Temple.Mass.R", "root": (-82.0, -3.0), "via": ((-104.0, 30.0), (-150.0, 30.0)), "end": (22.0, -4.0),
           "width": (0.04, 0.065, 0.02), "height": (0.0, 0.005, 0.0025), "peak": 0.35, "twist": 5.0, "embed": 0.003},
          {"name": "Temple.Mass.L", "root": (84.0, -3.0), "via": ((106.0, 32.0), (150.0, 31.0)), "end": (-22.0, -3.0),
           "width": (0.04, 0.065, 0.02), "height": (0.0, 0.005, 0.0025), "peak": 0.35, "twist": 5.0, "embed": 0.003},
          {"name": "Nape.Mass.1", "root": (150.0, -7.0), "via": ((160.0, 2.0),), "end": (-16.0, -9.0),
           "width": (0.014, 0.075, 0.026), "height": (0.0, 0.006, 0.003), "peak": 0.5, "twist": 5.0, "embed": 0.003},
          {"name": "Nape.Mass.2", "root": (-150.0, -7.0), "via": ((-160.0, 2.0),), "end": (16.0, -9.0),
           "width": (0.014, 0.075, 0.026), "height": (0.0, 0.006, 0.003), "peak": 0.5, "twist": 5.0, "embed": 0.003},
          {"name": "Nape.Mass.3", "root": (180.0, -8.0), "via": ((180.0, 2.0),), "end": (0.0, -12.0),
           "width": (0.014, 0.06, 0.022), "height": (0.0, 0.0065, 0.003), "peak": 0.5, "twist": 4.0, "embed": 0.003},
          {"name": "Sweep.Mass.R", "root": (-12.0, -3.0), "via": ((-22.0, 60.0), (-140.0, 62.0)), "end": (14.0, 3.0),
           "width": (0.07, 0.1, 0.022), "height": (0.0, 0.0065, 0.0025), "peak": 0.3, "twist": 8.0, "embed": 0.003},
          {"name": "Sweep.Mass.L", "root": (18.0, -3.0), "via": ((28.0, 58.0), (138.0, 60.0)), "end": (-14.0, 5.0),
           "width": (0.07, 0.102, 0.022), "height": (0.0, 0.007, 0.0025), "peak": 0.3, "twist": 8.0, "embed": 0.003},
          {"name": "Sweep.Lock.R", "root": (-30.0, -1.0), "via": ((-38.0, 56.0), (-128.0, 58.0)), "end": (16.0, 4.0), "length": 0.78,
           "width": (0.016, 0.03, 0.005), "height": (0.0, 0.0035, 0.0015), "peak": 0.35, "twist": 12.0, "embed": 0.0015},
          {"name": "Sweep.Lock.L", "root": (36.0, -1.0), "via": ((46.0, 52.0), (132.0, 56.0)), "end": (-16.0, 4.0), "length": 0.84,
           "width": (0.016, 0.028, 0.005), "height": (0.0, 0.0035, 0.0015), "peak": 0.35, "twist": 12.0, "embed": 0.0015},
          {"name": "Crown.Lock", "root": (-4.0, 30.0), "via": ((-6.0, 76.0), (174.0, 64.0)), "end": (0.0, 8.0), "length": 0.7,
           "width": (0.014, 0.026, 0.005), "height": (0.0, 0.0035, 0.0015), "peak": 0.4, "twist": 10.0, "embed": 0.0015},
          ## Ends on the temple above the ear's front (never on the ear, never past the face).
          {"name": "Temple.Accent.R", "root": (-56.0, -4.0), "via": ((-64.0, 6.0),), "to": (-72.0, 12.0),
           "width": (0.012, 0.016, 0.004), "height": (0.0, 0.004, 0.0015), "peak": 0.4, "twist": 14.0, "embed": 0.001}))
## hanging: thick sheets of the same ridge/groove construction, falling from below the
## tie. rear: `bands` ridges between |azimuth| `from`..180 at root elevation `el`, the
## middle longest (`length`: head heights below the head's lowest point, shortest..
## longest), `back` m behind the head at the end, `splay` outward; each groove stops
## short of its ridges, so the lower edge breaks into tapered points. sides: ridges at
## azimuths `az` beside the face down to `ends` (left, right) at `end_x` half-widths.
TRAINING_VARIANTS = {
    "A": {"label": "half up, layered shoulder-length",
          "tied": {"gather": (180.0, 48.0), "bands": 16, "thickness": (0.003, 0.014, 0.008), "bulge": 0.008, "peak": 0.35,
                   "groove": 0.009, "swirl": 0.006, "jitter": 0.25, "crown": 2, "rear_floor": 34.0},
          "bun": {"radii": (0.026, 0.023, 0.022), "wraps": 3, "turn": 1.4},
          "hanging": {"rear": {"bands": 6, "from": 122.0, "el": 40.0, "length": (-0.12, -0.24), "back": 0.05, "splay": 0.035,
                               "thickness": 0.016, "groove": 0.018, "swirl": 0.012, "locks": 2},
                      "sides": {"az": (78.0, 92.0, 106.0), "el": 18.0, "ends": (-0.04, 0.08), "end_x": 1.16,
                                "thickness": 0.012, "groove": 0.004}}},
    "B": {"label": "half up, fuller and wavier",
          "tied": {"gather": (180.0, 50.0), "bands": 16, "thickness": (0.004, 0.018, 0.009), "bulge": 0.012, "peak": 0.35,
                   "groove": 0.012, "swirl": 0.012, "jitter": 0.3, "crown": 4, "rear_floor": 34.0},
          "bun": {"radii": (0.029, 0.026, 0.025), "wraps": 3, "turn": 1.5},
          "hanging": {"rear": {"bands": 7, "from": 118.0, "el": 42.0, "length": (-0.1, -0.26), "back": 0.056, "splay": 0.055,
                               "thickness": 0.019, "groove": 0.022, "swirl": 0.022, "locks": 3},
                      "sides": {"az": (76.0, 90.0, 104.0), "el": 18.0, "ends": (-0.06, 0.02), "end_x": 1.18,
                                "thickness": 0.014, "groove": 0.005}}},
    "C": {"label": "half up, sleek and straighter",
          "tied": {"gather": (180.0, 46.0), "bands": 20, "thickness": (0.002, 0.01, 0.006), "bulge": 0.003, "peak": 0.35,
                   "groove": 0.006, "swirl": 0.003, "jitter": 0.18, "crown": 0, "rear_floor": 34.0},
          "bun": {"radii": (0.023, 0.02, 0.02), "wraps": 3, "turn": 1.3},
          "hanging": {"rear": {"bands": 6, "from": 126.0, "el": 38.0, "length": (-0.14, -0.22), "back": 0.046, "splay": 0.02,
                               "thickness": 0.014, "groove": 0.012, "swirl": 0.006, "locks": 1},
                      "sides": {"az": (80.0, 93.0, 106.0), "el": 18.0, "ends": (0.0, 0.08), "end_x": 1.14,
                                "thickness": 0.011, "groove": 0.003}}},
    ## Revision 4: the knot where Ranger's bun sits (the same gather point), finer bands,
    ## about half the thickness, thinner tips and slimmer locks: less blocky, less chunky.
    "D": {"label": "half up, knot at Ranger's bun position, finer and lighter",
          "tied": {"gather": (180.0, 28.0), "bands": 22, "thickness": (0.002, 0.009, 0.005), "bulge": 0.005, "peak": 0.35,
                   "groove": 0.006, "swirl": 0.005, "jitter": 0.22, "crown": 0, "rear_floor": 20.0},
          "bun": {"radii": (0.032, 0.028, 0.026), "wraps": 3, "turn": 1.5},
          ## No overlay locks (they read as tusks); the side hair falls behind the cheek,
          ## framing the jaw and neck rather than lying flat beside the face.
          ## One continuous hanging volume wrapping forward to behind the ears; its
          ## front-most bands are the side locks (`side_from`), so there is no separate flap.
          "hanging": {"rear": {"bands": 12, "from": 110.0, "el": 26.0, "length": (0.04, -0.22), "back": 0.05, "splay": 0.0,
                               "thickness": 0.009, "groove": 0.008, "swirl": 0.022, "locks": 0, "side_from": 130.0,
                               "layer": 0.006, "length_jitter": 0.45}}},
    ## Revision 5: D integrated with the anatomy. The tied hair starts at a parting that
    ## rises smoothly behind the ears and lies over the hanging roots; no stub bands under
    ## the knot. The hanging hair drapes: occipital contour, a bounded fall across the
    ## nape hollow, the neck, then carried out by the trapezius (see _draped).
    "E": {"label": "D integrated: parting over the hanging roots, hair draping the nape", "seat_cap": True,
          "resting_weights": True, "weight_ramp": (0.35, 0.25),
          "tied": {"gather": (180.0, 28.0), "bands": 22, "thickness": (0.002, 0.009, 0.005), "bulge": 0.005, "peak": 0.35,
                   "groove": 0.006, "swirl": 0.005, "jitter": 0.22, "crown": 0, "rear_open": 160.0,
                   "parting": {"from": 95.0, "to": 140.0, "el": 16.0, "lap": 0.002}},
          "bun": {"radii": (0.032, 0.028, 0.026), "wraps": 3, "turn": 1.5},
          "hanging": {"rear": {"bands": 12, "from": 110.0, "el": (12.0, 24.0), "length": (0.04, -0.22), "thickness": 0.008,
                               "groove": 0.007, "swirl": 0.024, "locks": 0, "side_from": 130.0, "layer": 0.005,
                               "length_jitter": 0.45,
                               "drape": {"root_gap": CAP_LIFT_M + 0.002, "gap": 0.015, "gap_by": 0.5, "fall": 0.45, "rows": 16,
                                         "edge_guides": 2, "groove_ease": 0.2}}}},
}
## Revision 6 (candidate, Training): E on Ranger G's root system: Ranger's hairline, the
## same crown, front sweeps, secondary locks and temple accent (one identity), the temple
## masses lower so they lie over the parting (no ledge), a smaller folded knot at the
## same place, and the loose hair as four draped masses behind the ears (no hooks by the
## jaw): the side masses shorter, the rear pair longest and layered over them, each with
## its own flow; ends staggered by mass, not saw-teeth.
_G = RANGER_VARIANTS["G"]
_SHARED = {m["name"]: m for m in _G["flow"]}
TRAINING_VARIANTS["F"] = dict(
    TRAINING_VARIANTS["E"], label="E on Ranger G's roots: shared hairline and front, no ledge, four loose masses",
    hairline=HAIRLINE_RANGER, nape_clear=0.004, fit_head=True,
    ## Loose hair Head -> Neck by height (approved 2026-11-07: cleaner than the body's
    ## resting weights through the head and neck poses), over this hairstyle's own length:
    ## head only above 0.25 head heights, all Neck by -0.10 (its tips end at -0.135), so no
    ## tip carries the head into the trapezius when the head snaps back.
    resting_weights=False, weight_ramp=(0.25, -0.10),
    tied=dict(TRAINING_VARIANTS["E"]["tied"], thickness=(0.002, 0.008, 0.005), bulge=0.004, gather=(180.0, 26.0), bands=14),
    bun={"radii": (0.03, 0.033, 0.026), "wraps": 0, "folds": ((45.0, 105.0, 1.2, 0.16), (135.0, 100.0, 1.1, 0.15))},
    flow=(_SHARED["Crown.Mass"],
          dict(_SHARED["Temple.Mass.R"], via=((-104.0, 22.0), (-150.0, 24.0))),
          dict(_SHARED["Temple.Mass.L"], via=((106.0, 22.0), (150.0, 24.0))),
          _SHARED["Sweep.Mass.R"], _SHARED["Sweep.Mass.L"], _SHARED["Sweep.Lock.R"], _SHARED["Sweep.Lock.L"],
          _SHARED["Crown.Lock"], _SHARED["Temple.Accent.R"],
          ## The gathered upper hair rising from below the parting into the knot: it lies
          ## over the line where the tied section meets the loose hair.
          {"name": "Nape.Tie.L", "root_at": (140.0, 10.0), "via": ((158.0, 18.0),), "end": (-16.0, -4.0),
           "width": (0.03, 0.06, 0.022), "height": (0.0, 0.006, 0.003), "peak": 0.45, "twist": 6.0, "embed": 0.003},
          {"name": "Nape.Tie.R", "root_at": (-140.0, 10.0), "via": ((-158.0, 18.0),), "end": (16.0, -4.0),
           "width": (0.03, 0.06, 0.022), "height": (0.0, 0.006, 0.003), "peak": 0.45, "twist": 6.0, "embed": 0.003},
          {"name": "Nape.Tie.C", "root_at": (180.0, 8.0), "via": ((180.0, 16.0),), "end": (0.0, -8.0),
           "width": (0.03, 0.055, 0.02), "height": (0.0, 0.0065, 0.003), "peak": 0.45, "twist": 4.0, "embed": 0.003},
          {"name": "Nape.Tie.L2", "root_at": (118.0, 12.0), "via": ((140.0, 20.0),), "end": (-24.0, -2.0),
           "width": (0.03, 0.055, 0.02), "height": (0.0, 0.006, 0.003), "peak": 0.45, "twist": 6.0, "embed": 0.003},
          {"name": "Nape.Tie.R2", "root_at": (-118.0, 12.0), "via": ((-140.0, 20.0),), "end": (24.0, -2.0),
           "width": (0.03, 0.055, 0.02), "height": (0.0, 0.006, 0.003), "peak": 0.45, "twist": 6.0, "embed": 0.003}),
    ## Each loose mass ends as one chevron (its middle band longest), behind the neck and
    ## never wider than the head: no curtain, no row of teeth, no blade along the shoulder,
    ## no hooks; the rear pair ends at the base of the neck, the sides by the jaw.
    hanging={"drape": dict(TRAINING_VARIANTS["E"]["hanging"]["rear"]["drape"], gap=0.024, rows=14),
             "masses": ({"name": "A", "az": (122.0, 152.0), "bands": 4, "el": 14.0, "length": (0.08, 0.05),
                         "thickness": 0.008, "groove": 0.001, "swirl": 0.016, "layer": 0.0, "edge_guides": 2},
                        {"name": "D", "az": (208.0, 238.0), "bands": 4, "el": 14.0, "length": (0.09, 0.06),
                         "thickness": 0.008, "groove": 0.001, "swirl": 0.014, "layer": 0.0, "edge_guides": 2},
                        {"name": "C", "az": (180.0, 212.0), "bands": 4, "el": 20.0, "length": (-0.05, -0.115),
                         "thickness": 0.009, "groove": 0.0012, "swirl": 0.018, "layer": 0.003, "edge_guides": 2},
                        {"name": "B", "az": (150.0, 182.0), "bands": 4, "el": 20.0, "length": (-0.06, -0.135),
                         "thickness": 0.009, "groove": 0.0012, "swirl": 0.02, "layer": 0.007, "edge_guides": 2})})
## The candidates put forward for approval (variations stay buildable for review).
DEFAULT_RANGER = "D"
DEFAULT_TRAINING = "E"


def _jitter(seed, k):
    """Deterministic variation in -1..1 (the same build always makes the same hair)."""
    v = math.sin(seed * 12.9898 + k * 78.233) * 43758.5453
    return (v - math.floor(v)) * 2.0 - 1.0


def _drape_frame(body):
    """The whole body at rest, for hair that follows the occiput, nape, neck and shoulders."""
    world = body.matrix_world
    points = [world @ v.co for v in body.data.vertices]
    return BVHTree.FromPolygons(points, [list(p.vertices) for p in body.data.polygons])


def _body_offset(tree, direction, z, gap):
    """The radius from the rig's vertical axis at which a surface `gap` off the body
    (along its normal) crosses height `z` in horizontal `direction`; None off the body."""
    hit, normal, _i, _d = tree.ray_cast(Vector((0.0, 0.0, z)) + direction * 0.4, -direction)
    if hit is None:
        return None
    if normal.dot(direction) < 0.0:
        normal = -normal
    return Vector((hit.x, hit.y, 0.0)).length + gap / max(0.35, Vector((normal.x, normal.y, 0.0)).length)


def _head_frame(body):
    head = body.vertex_groups[HEAD].index
    world = body.matrix_world
    members = sorted(v.index for v in body.data.vertices if v.co.z > 1.5 and any(g.group == head and g.weight >= 0.99 for g in v.groups))
    index = {i: n for n, i in enumerate(members)}
    points = [world @ body.data.vertices[i].co for i in members]
    polygons = [[index[i] for i in p.vertices] for p in body.data.polygons if all(i in index for i in p.vertices)]
    stored = body.data.attributes.get(CONSTRUCTION_ATTRIBUTE)
    extents = points if stored is None else [world @ Vector(stored.data[i].vector) for i in members]
    low = min(p.z for p in extents)
    height = max(p.z for p in extents) - low
    half_width = max(abs(p.x) for p in extents)
    front = min(p.y for p in extents)
    back = max(p.y for p in extents)
    centre = Vector((0.0, (front + back) * 0.5, low + 0.55 * height))
    return {"tree": BVHTree.FromPolygons(points, polygons), "low": low, "height": height,
            "half_width": half_width, "front": front, "back": back, "centre": centre}


## A head's construction surface (the skull before its face forms), stored by the base
## builder: the fitting frame is measured on it, so a longer nose never moves the hair.
CONSTRUCTION_ATTRIBUTE = "riposte_f0_co"


def head_frame_of(head, body, ears=(), brows=()):
    """The fitting frame of any head object (the approved `HeadV2`, a resolved head
    profile) with the body the hanging hair drapes over: extents from the head's
    construction surface when it carries one (equal to v1's head island on the approved
    head), rays against its real surface, so the approved designs fit whatever skull they
    meet. With the resolved `ears` and `brows`, the head map a style fitted to the head
    reads (`fit_head`): the ears' keep-out and the brow line."""
    world = head.matrix_world
    surface = [world @ v.co for v in head.data.vertices]
    stored = head.data.attributes.get(CONSTRUCTION_ATTRIBUTE)
    points = surface if stored is None else [world @ Vector(a.vector) for a in stored.data]
    low = min(p.z for p in points)
    height = max(p.z for p in points) - low
    front = min(p.y for p in points)
    back = max(p.y for p in points)
    frame = {"tree": BVHTree.FromPolygons(surface, [list(p.vertices) for p in head.data.polygons]), "low": low,
             "height": height, "half_width": max(abs(p.x - world.translation.x) for p in points), "front": front,
             "back": back, "centre": Vector((world.translation.x, (front + back) * 0.5, low + 0.55 * height)),
             "body": _skin_frame((head, body))}
    frame["map"] = _head_map(frame, ears, brows)
    return frame


## The head map (HAIR-FIT): what a hairstyle fitted to the resolved head keeps clear of or
## follows, measured on that head's own components, never on Wolf's.
## An ear's free part stands more than EAR_COVER_M off the skull: hair may lie over the
## attachment nearer the head (it partly covers the upper ear) but never over the helix
## or the lower ear (the ear stays a facing cue). The keep-out is the free part's highest
## elevation per EAR_BIN_DEG of azimuth, widened EAR_SIDE_DEG each way, plus EAR_TOP_M.
EAR_COVER_M = 0.008
EAR_TOP_M = 0.004
EAR_BIN_DEG = 2.0
EAR_SIDE_DEG = 6.0
EAR_FALL_DEG = 8.0
## The front hairline follows the brow: by how much the resolved brow's highest elevation
## differs from Wolf's approved default (measured on male_base_foundation v002, Wolf's
## default body), its front lifts or drops, easing out by BROW_FADE_DEG of azimuth.
BROW_REF_EL = 16.51
BROW_FADE_DEG = (60.0, 95.0)


def _angles(frame, p):
    d = p - frame["centre"]
    return math.degrees(math.atan2(d.x, -d.y)), math.degrees(math.asin(max(-1.0, min(1.0, d.z / d.length))))


def _head_map(frame, ears, brows):
    """Ear keep-out bins {signed azimuth bin: lowest elevation hair may reach}, each ear's
    span and top, and the brow's highest elevation; empty without the components."""
    floor, spans = {}, {}
    for entry in ears:
        ## An ear, or (ear, its free-rim vertex indices): the helix is protected however
        ## near the skull it lies; only the attachment may be covered.
        ear, rim = entry if isinstance(entry, tuple) else (entry, ())
        rim = set(rim)
        world = ear.matrix_world
        free = []
        for v in ear.data.vertices:
            p = world @ v.co
            location, normal, _i, _d = frame["tree"].find_nearest(p)
            if v.index in rim or (p - location).dot(normal) > EAR_COVER_M:
                free.append(_angles(frame, p))
        if not free:
            continue
        radius = (frame["centre"] - frame["tree"].find_nearest(world @ ear.data.vertices[0].co)[0]).length
        top = math.degrees(EAR_TOP_M / radius)
        for az, el in free:
            k = round(az / EAR_BIN_DEG)
            floor[k] = max(floor.get(k, -90.0), el + top)
        side = ear.name.split(".")[-1]
        spans[side] = [round(min(a for a, _e in free), 1), round(max(a for a, _e in free), 1),
                       round(max(e for _a, e in free), 1), round(min(e for _a, e in free), 1)]
    ## A flat plateau EAR_SIDE_DEG each way, then a smooth fall over EAR_FALL_DEG: the
    ## scalp cap's coarse ring (one vertex every 15 degrees) arches over the ear instead
    ## of chording across it, and the hairline has no step.
    plateau = int(round(EAR_SIDE_DEG / EAR_BIN_DEG))
    fall = int(round(EAR_FALL_DEG / EAR_BIN_DEG))
    widened = {}
    for k, el in floor.items():
        for j in range(k - plateau - fall, k + plateau + fall + 1):
            x = max(0.0, min(1.0, (abs(j - k) - plateau) / float(fall)))
            widened[j] = max(widened.get(j, -90.0), el - (el + 40.0) * x * x * (3.0 - 2.0 * x))
    brow = max((_angles(frame, b.matrix_world @ v.co)[1] for b in brows for v in b.data.vertices), default=None)
    return {"ear_floor": widened, "ears": spans, "brow_el": None if brow is None else round(brow, 2)}


def _ear_floor(frame, azimuth):
    """The lowest elevation hair may reach at `azimuth` (signed degrees) beside the ears."""
    bins = frame.get("map", {}).get("ear_floor") or {}
    if not bins:
        return -90.0
    x = azimuth / EAR_BIN_DEG
    k0 = math.floor(x)
    a, b = bins.get(k0, -90.0), bins.get(k0 + 1, -90.0)
    return a + (b - a) * (x - k0)


def _clear_ears(frame, d):
    """`d` raised along its meridian to clear the ears' keep-out."""
    az, el = math.degrees(math.atan2(d.x, -d.y)), math.degrees(math.asin(max(-1.0, min(1.0, d.z / d.length))))
    low = _ear_floor(frame, az)
    return _direction(az, low) if el < low else d


def _skin_frame(objects):
    """The character's skin as one surface (a separate head and body, as on the v2 base):
    hanging hair rests on whichever is outermost, never on a neck that ends inside the skull."""
    points, polygons = [], []
    for obj in objects:
        start = len(points)
        points += [obj.matrix_world @ v.co for v in obj.data.vertices]
        polygons += [[start + i for i in p.vertices] for p in obj.data.polygons]
    return BVHTree.FromPolygons(points, polygons)


STYLES = {"ranger": ("HairRanger", RANGER_VARIANTS, HAIRLINE_RANGER, DEFAULT_RANGER),
          "training": ("HairTraining", TRAINING_VARIANTS, HAIRLINE_TRAINING, DEFAULT_TRAINING)}


def build_style(frame, which, variant=None):
    """One approved hairstyle (its design unchanged) fitted to `frame`; unweighted (the
    weights belong to the production body). Returns the hair object, not linked."""
    name, variants, hairline, default = STYLES[which]
    variant = variant or default
    ## A variant may share another style's hairline (one root system for both skins).
    hairline = variants[variant].get("hairline", hairline)
    obj, _cap_faces, _rigid = _build(frame, name, variants[variant], hairline)
    obj["riposte_variant"] = "%s: %s" % (variant, variants[variant]["label"])
    if variants[variant].get("fit_head"):
        head_map = frame.get("map", {})
        obj["riposte_head_map"] = json.dumps({"ears": head_map.get("ears"), "brow_el": head_map.get("brow_el"),
                                              "behind_ears_deg": round(_behind_ears(frame), 1),
                                              "neck_clearance_mm": round(_neck_clearance(frame) * 1000, 1)})
    return obj


def _direction(azimuth, elevation):
    a, e = math.radians(azimuth), math.radians(elevation)
    return Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))


def _hit(frame, d):
    """The skull point and its outward normal seen from the head centre along `d`."""
    d = d.normalized()
    hit, normal, _i, _dist = frame["tree"].ray_cast(frame["centre"] + d * 0.5, -d)
    if hit is None:
        raise SystemExit("RIPOSTE_HAIR: no skull along %s" % (tuple(round(c, 3) for c in d),))
    if normal.dot(d) < 0.0:
        normal = -normal
    return hit, normal


def _surface(frame, azimuth, elevation, lift):
    hit, normal = _hit(frame, _direction(azimuth, elevation))
    return hit + normal * lift


def _hairline(hairline, azimuth):
    a = min(180.0, abs(azimuth))
    for (a0, e0), (a1, e1) in zip(hairline, hairline[1:]):
        if a <= a1:
            return e0 + (e1 - e0) * (a - a0) / (a1 - a0)
    return hairline[-1][1]


def _cap(frame, bm, hairline):
    """Rows of rays onto the skull from the style's hairline to the crown: one outer
    surface, thick inside the hairline and tapering onto the skull in its first row."""
    rows = []
    for row in range(CAP_ROWS + 1):
        ring = []
        for step in range(CAP_AZIMUTH_STEPS):
            azimuth = 360.0 * step / CAP_AZIMUTH_STEPS - 180.0
            low = _hairline(hairline, azimuth)
            elevation = low + (CAP_TOP_ELEVATION - low) * row / CAP_ROWS
            lift = CAP_LIFT_M if row == 0 else CAP_LIFT_M + CAP_THICKNESS_M
            ring.append(bm.verts.new(_surface(frame, azimuth, elevation, lift)))
        rows.append(ring)
    top = bm.verts.new(_surface(frame, 0.0, 90.0, CAP_LIFT_M + CAP_THICKNESS_M))
    cap = []
    for r0, r1 in zip(rows, rows[1:]):
        for k in range(CAP_AZIMUTH_STEPS):
            cap.append(bm.faces.new([r0[k], r0[(k + 1) % CAP_AZIMUTH_STEPS], r1[(k + 1) % CAP_AZIMUTH_STEPS], r1[k]]))
    for k in range(CAP_AZIMUTH_STEPS):
        cap.append(bm.faces.new([rows[-1][k], rows[-1][(k + 1) % CAP_AZIMUTH_STEPS], top]))
    return cap


def _profile(t, values, peak=0.5):
    """Root -> mid -> end interpolation with a smooth peak at `peak` of the length."""
    root, mid, end = values
    if t <= peak:
        s = math.sin(t / peak * math.pi * 0.5)
        return root + (mid - root) * s
    s = math.cos((t - peak) / (1.0 - peak) * math.pi * 0.5)
    return end + (mid - end) * s


def _sweep(bm, centres, normals, widths, heights):
    """A closed clump along `centres`: lens sections facing `normals`, fans at both ends.
    Returns its faces."""
    rings = []
    count = len(centres)
    for i, c in enumerate(centres):
        tangent = (centres[min(i + 1, count - 1)] - centres[max(i - 1, 0)]).normalized()
        across = tangent.cross(normals[i]).normalized()
        up = across.cross(tangent).normalized()
        if up.dot(normals[i]) < 0.0:
            up = -up
        rings.append([bm.verts.new(c + across * (u * widths[i] * 0.5) + up * (v * heights[i])) for u, v in LENS])
    faces = []
    sides = len(LENS)
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(sides):
            faces.append(bm.faces.new([r0[k], r0[(k + 1) % sides], r1[(k + 1) % sides], r1[k]]))
    start_dir = (centres[0] - centres[1]).normalized()
    end_dir = (centres[-1] - centres[-2]).normalized()
    start = bm.verts.new(centres[0] + start_dir * widths[0] * 0.15)
    tip = bm.verts.new(centres[-1] + end_dir * widths[-1] * 0.5)
    for k in range(sides):
        faces.append(bm.faces.new([start, rings[0][(k + 1) % sides], rings[0][k]]))
        faces.append(bm.faces.new([tip, rings[-1][k], rings[-1][(k + 1) % sides]]))
    return faces


def _tied_clump(frame, spec, root_az, root_el, seed, scale=1.0, lift_add=0.0):
    """A clump from (root_az, root_el) to the gather point along a great circle."""
    d0 = _direction(root_az, root_el)
    d1 = _direction(*spec["gather"])
    angle = d0.angle(d1)
    axis = d0.cross(d1)
    if angle < 0.05 or axis.length < 1e-6:
        return None
    axis.normalize()
    j = spec["jitter"]
    wj = 1.0 + _jitter(seed, 1) * j
    bj = 1.0 + _jitter(seed, 2) * j
    sj = _jitter(seed, 3)
    hits, normals = [], []
    for i in range(RINGS):
        t = i / (RINGS - 1)
        hit, normal = _hit(frame, Quaternion(axis, angle * t) @ d0)
        hits.append(hit)
        normals.append(normal)
    centres, widths, heights = [], [], []
    for i in range(RINGS):
        t = i / (RINGS - 1)
        peak = spec.get("peak", 0.5)
        w = _profile(t, spec["width"], peak) * wj * scale
        h = _profile(t, spec["height"], peak) * scale
        lift = _profile(t, spec["lift"], peak) + spec["bulge"] * bj * math.sin(math.pi * min(1.0, t / (2.0 * peak))) * scale + lift_add
        lift = max(lift, KEEL * h + CAP_LIFT_M)
        centres.append(hits[i] + normals[i] * lift)
        widths.append(w)
        heights.append(h)
    ## Curvature: a sideways bend that vanishes at both ends, signed per clump.
    for i in range(1, RINGS - 1):
        t = i / (RINGS - 1)
        tangent = (centres[i + 1] - centres[i - 1]).normalized()
        side = tangent.cross(normals[i]).normalized()
        centres[i] = centres[i] + side * spec["swirl"] * sj * math.sin(math.pi * t)
    return centres, normals, widths, heights


def _hanging_clump(frame, root_az, root_el, end_z, end_x, back, splay, width, height, swirl, seed, tip=TIP_WIDTH):
    """A falling clump: seated on the skull below the tie, then down the nape or beside
    the face to `end_z` (head heights below the head's lowest point), tapering to a tip."""
    p0 = _surface(frame, root_az, root_el, KEEL * height + CAP_LIFT_M + 0.006)
    p1 = _surface(frame, root_az, root_el - 22.0, KEEL * height + CAP_LIFT_M + 0.008)
    radial = Vector((math.sin(math.radians(root_az)), -math.cos(math.radians(root_az)), 0.0))
    behind = -math.cos(math.radians(root_az)) > 0.3
    hw = frame["half_width"]
    controls = [p0, p1]
    for share, z in ((0.5, end_z * 0.35 + 0.12), (1.0, end_z)):
        if behind:
            x = p1.x + radial.x * splay * share
            y = frame["back"] + back * share + 0.01
        else:
            x = math.copysign(end_x * hw, root_az) * (0.94 + 0.06 * share)
            y = p1.y + 0.012 * share
        controls.append(Vector((x, y, frame["low"] + z * frame["height"])))
    centres = _catmull(controls, HANGING_RINGS)
    sj = _jitter(seed, 4)
    normals, widths, heights = [], [], []
    for i, c in enumerate(centres):
        t = i / (HANGING_RINGS - 1)
        out = Vector((c.x, c.y - frame["centre"].y, 0.0))
        normals.append(out.normalized() if out.length > 1e-6 else radial)
        taper = 1.0 - (1.0 - tip) * max(0.0, (t - 0.35) / 0.65) ** 1.3
        widths.append(width * (0.75 + 0.25 * math.sin(math.pi * min(1.0, t * 2.0))) * taper)
        heights.append(height * (1.0 - (1.0 - TIP_HEIGHT) * t))
    for i in range(2, HANGING_RINGS - 1):
        t = i / (HANGING_RINGS - 1)
        tangent = (centres[i + 1] - centres[i - 1]).normalized()
        side = tangent.cross(normals[i]).normalized()
        centres[i] = centres[i] + side * swirl * sj * math.sin(math.pi * t)
    return centres, normals, widths, heights


def _catmull(points, count):
    """`count` samples through `points` on a Catmull-Rom spline (ends repeated)."""
    pts = [points[0]] + list(points) + [points[-1]]
    segments = len(points) - 1
    out = []
    for n in range(count):
        u = n / (count - 1) * segments
        i = min(int(u), segments - 1)
        t = u - i
        p0, p1, p2, p3 = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
        out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
                          + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
    return out



SHELL_ROWS = 12
## The shell stops short of the gather point; the bun covers its convergence.
SHELL_END = 0.9
RISE_ROWS = 4.0
CAP_TOP_M = CAP_LIFT_M + CAP_THICKNESS_M
## The deepest groove stays this far above the cap: never coplanar with it (z-fighting).
GROOVE_FLOOR_M = 0.0015
HANGING_ROWS = 12
## A hanging sheet's thickness at its tips, as a share of its root thickness.
SHEET_TIP = 0.22
## ... and at its root, where it starts under the tied hair (never zero: no degenerate faces).
SHEET_ROOT = 0.15


## Tied hair lies down the occiput's under-curve (ART-SURFACE-001): where the scalp faces
## down, its volume gives way, none at UNDERCURVE_Z[0], all of it from UNDERCURVE_Z[1]
## (the scalp normal's z), so the back of a tied style hugs the nape on any skull,
## never a brim standing off it.
UNDERCURVE_Z = (-0.6, -0.1)


def _lie(normal):
    low, high = UNDERCURVE_Z
    x = max(0.0, min(1.0, (normal.z - low) / (high - low)))
    return x * x * (3.0 - 2.0 * x)


def _tied_guides(frame, spec, hairline):
    """Ridge and groove guides round the head, from the hairline towards the gather point."""
    bands = spec["bands"]
    peak = spec.get("peak", 0.5)
    d1 = _direction(*spec["gather"])
    spacing = 360.0 / bands
    azimuths = []
    for i in range(bands * 2):
        k = i // 2
        azimuth = -180.0 + spacing * (k + 0.5) + (spacing * 0.5 if i % 2 else 0.0)
        azimuths.append(azimuth + _jitter(k, 11) * spacing * 0.18)
    ## `rear_open`: no bands behind this azimuth (under the knot, where they would be
    ## stubs); the shell is open there and its two edge guides lie flush on the cap.
    kept = [i for i, a in enumerate(azimuths) if abs(a) <= spec.get("rear_open", 181.0)]
    edges = {kept[0], kept[-1]} if len(kept) < len(azimuths) else set()
    parting = spec.get("parting")
    guides = []
    for i in kept:
        ridge = i % 2 == 0
        k = i // 2
        azimuth = azimuths[i]
        elevation = _hairline(hairline, azimuth)
        base = CAP_LIFT_M + 0.001
        if spec.get("rear_floor") is not None and abs(azimuth) > 110.0:
            elevation = max(elevation, spec["rear_floor"])
        if parting is not None:
            ## Half up: behind the ears the tied hair starts at the parting, rising
            ## smoothly from the hairline; there it lies over the hanging hair's roots.
            u = max(0.0, min(1.0, (abs(azimuth) - parting["from"]) / (parting["to"] - parting["from"])))
            share = u * u * (3.0 - 2.0 * u)
            elevation += (max(elevation, parting["el"]) - elevation) * share
            base += (CAP_TOP_M + parting.get("lap", 0.0) - base) * share
        d0 = _direction(azimuth, elevation)
        angle = d0.angle(d1)
        axis = d0.cross(d1)
        axis = axis.normalized() if axis.length > 1e-6 else Vector((0.0, 0.0, 1.0))
        bj = 1.0 + _jitter(k, 12) * spec["jitter"]
        sj = _jitter(k, 13)
        points, normals = [], []
        for m in range(SHELL_ROWS):
            t = SHELL_END * m / (SHELL_ROWS - 1)
            hit, normal = _hit(frame, _clear_ears(frame, Quaternion(axis, angle * t) @ d0))
            thick = _profile(t, spec["thickness"], peak) + spec["bulge"] * bj * math.sin(math.pi * min(1.0, t / (2.0 * peak)))
            if not ridge:
                thick -= spec["groove"] * math.sin(math.pi * min(1.0, t / SHELL_END)) ** 0.5
            if i in edges:
                thick = 0.0
            thick *= _lie(normal)
            ## The first row meets the cap's hairline; the shell rises onto the cap over
            ## RISE_ROWS rows, so the hairline is a soft edge, never a brim.
            rise = math.sin(math.pi * 0.5 * min(1.0, m / RISE_ROWS))
            lift = base + (CAP_TOP_M + max(GROOVE_FLOOR_M, thick) - base) * rise
            points.append(hit + normal * max(lift, base))
            normals.append(normal)
        for m in range(1, SHELL_ROWS - 1):
            t = m / (SHELL_ROWS - 1)
            tangent = (points[m + 1] - points[m - 1]).normalized()
            side = tangent.cross(normals[m]).normalized()
            points[m] = points[m] + side * spec["swirl"] * sj * math.sin(math.pi * t)
        guides.append({"azimuth": azimuth, "ridge": ridge, "points": points, "normals": normals})
    return guides, not edges


def _grid_faces(bm, rows_a, rows_b):
    """Quads between two guides' vertex columns (same row count)."""
    return [bm.faces.new([rows_a[m], rows_a[m + 1], rows_b[m + 1], rows_b[m]]) for m in range(len(rows_a) - 1)]


def _band_width(guides, index, row, cyclic=True):
    count = len(guides)
    around = (index - 1, (index + 1) % count) if cyclic else (index - 1, index + 1)
    neighbours = [guides[j]["points"][row] for j in around if 0 <= j < count]
    return sum((guides[index]["points"][row] - n).length for n in neighbours) / max(1, len(neighbours)) * 2.0


def _tied_shell(frame, bm, spec, hairline):
    """The primary volume: one continuous surface (closed round the head, or open under
    the knot); faces belong to the ridge they flank."""
    guides, cyclic = _tied_guides(frame, spec, hairline)
    columns = [[bm.verts.new(p) for p in g["points"]] for g in guides]
    parts = []
    count = len(guides)
    for i in range(count):
        if not guides[i]["ridge"]:
            continue
        faces = []
        if i > 0 or cyclic:
            faces += _grid_faces(bm, columns[i - 1], columns[i])
        if i < count - 1 or cyclic:
            faces += _grid_faces(bm, columns[i], columns[(i + 1) % count])
        g = guides[i]
        widths = [_band_width(guides, i, m, cyclic) for m in range(SHELL_ROWS)]
        parts.append((g["azimuth"], faces, {"points": g["points"], "widths": widths,
                                            "heights": [spec["groove"]] * SHELL_ROWS, "free": False}))
    return parts


def _falling(frame, root_az, root_el, end_z, end_x, back, splay, rows):
    """A falling guide: on the skull below the tie, then down the nape (behind) or beside
    the face to `end_z` head heights below the head's lowest point."""
    p0 = _surface(frame, root_az, root_el, CAP_TOP_M)
    p1 = _surface(frame, root_az, root_el - 22.0, CAP_TOP_M + 0.004)
    radial = Vector((math.sin(math.radians(root_az)), -math.cos(math.radians(root_az)), 0.0))
    behind = -math.cos(math.radians(root_az)) > 0.3
    controls = [p0, p1]
    for share, z in ((0.5, end_z * 0.35 + 0.12), (1.0, end_z)):
        if behind:
            x = p1.x + radial.x * splay * share
            y = frame["back"] + back * share + 0.01
        else:
            ## Beside the face the hair wraps the head's contour at its own azimuth, so a
            ## sheet of several guides curves round towards the neck instead of a flat panel.
            reach = end_x * frame["half_width"] * (0.94 + 0.06 * share)
            x = radial.x * reach
            y = frame["centre"].y + radial.y * reach * 0.9 + 0.012 * share
        controls.append(Vector((x, y, frame["low"] + z * frame["height"])))
    points = _catmull(controls, rows)
    normals = []
    for c in points:
        out = Vector((c.x, c.y - frame["centre"].y, 0.0))
        normals.append(out.normalized() if out.length > 1e-6 else radial)
    return points, normals


def _draped(frame, drape, root_az, root_el, end_z, rows):
    """A falling guide that drapes: from its root on the skull it follows the occipital
    contour, then falls no faster than `fall` (metres inward per metre down) across the
    nape hollow, follows the neck where the neck is nearer, and is carried outward by
    the trapezius. Its gap off the body grows from `root_gap` (over the scalp cap) to
    `gap` by the nape; the guide is the sheet's inner face."""
    p0 = _surface(frame, root_az, root_el, drape["root_gap"])
    direction = Vector((p0.x, p0.y, 0.0)).normalized()
    z_end = frame["low"] + end_z * frame["height"]
    radius = Vector((p0.x, p0.y, 0.0)).length
    points, normals = [p0], [direction]
    z_prev = p0.z
    for m in range(1, rows):
        t = m / (rows - 1)
        z = p0.z + (z_end - p0.z) * t
        gap = drape["root_gap"] + (drape["gap"] - drape["root_gap"]) * min(1.0, t / drape.get("gap_by", 0.5))
        target = _body_offset(drape["tree"], direction, z, gap)
        fallen = radius - drape["fall"] * (z_prev - z)
        radius = fallen if target is None else max(target, fallen)
        points.append(Vector((direction.x * radius, direction.y * radius, z)))
        normals.append(direction)
        z_prev = z
    return points, normals


def _sheet(bm, guides, thickness, groove, edge_guides=0, groove_ease=0.0):
    """A thick hanging sheet from ordered guides (ridges at even indices): an outer
    surface with the grooves inset, an inner surface offset towards the body, and walls
    round the edge. The grooves end short of their ridges, so the tips come to points."""
    outer, inner = [], []
    rows = len(guides[0]["points"])
    last = len(guides) - 1
    for j, g in enumerate(guides):
        column_out, column_in = [], []
        ## A sheet thins towards its two lateral edges: no full-thickness wall shows.
        edge = min(1.0, (min(j, last - j) + 1) / (edge_guides + 1.0)) if edge_guides else 1.0
        for m, (p, n) in enumerate(zip(g["points"], g["normals"])):
            t = m / (rows - 1)
            ## Grooves ease in below the root, so the root edge is one line, not teeth.
            ease = min(1.0, t / groove_ease) if groove_ease else 1.0
            inset = 0.0 if g["ridge"] else groove * math.sin(math.pi * min(1.0, t * 1.2)) ** 0.5 * ease
            depth = thickness * edge * (1.0 - (1.0 - SHEET_TIP) * t) * max(SHEET_ROOT, min(1.0, m / 2.0))
            ## The guide is the sheet's inner face and the thickness stands outward from
            ## it, so a guide that clears the body keeps the whole sheet clear.
            column_out.append(bm.verts.new(p + n * max(depth * SHEET_ROOT, depth - inset)))
            column_in.append(bm.verts.new(p))
        outer.append(column_out)
        inner.append(column_in)
    faces_by_ridge = {}
    for j in range(len(guides) - 1):
        ridge = j if guides[j]["ridge"] else j + 1
        faces = _grid_faces(bm, outer[j], outer[j + 1]) + _grid_faces(bm, inner[j + 1], inner[j])
        faces.append(bm.faces.new([outer[j][-1], outer[j + 1][-1], inner[j + 1][-1], inner[j][-1]]))
        faces.append(bm.faces.new([outer[j + 1][0], outer[j][0], inner[j][0], inner[j + 1][0]]))
        faces_by_ridge.setdefault(ridge, []).extend(faces)
    for j, side in ((0, -1), (len(guides) - 1, 1)):
        walls = _grid_faces(bm, inner[j], outer[j]) if side < 0 else _grid_faces(bm, outer[j], inner[j])
        faces_by_ridge.setdefault(j if guides[j]["ridge"] else j - side, []).extend(walls)
    return faces_by_ridge


def _hanging_sheet(frame, bm, azimuths, root_el, ends, end_x, back, splay, thickness, groove, swirl, seed, layer=0.0, drape=None,
                   smooth_ends=False):
    """Ridges at `azimuths` (ordered), grooves between them ending short of both. With
    `drape`, the guides follow the body (see _draped) instead of falling to a plane. With
    `smooth_ends` a groove ends midway between its ridges: the sheet's lower edge is one
    line (a mass ending in a chevron), never a row of teeth."""
    rows = HANGING_ROWS if drape is None else drape.get("rows", HANGING_ROWS)
    span = max(abs(180.0 - a) for a in azimuths) or 1.0

    def elevation(azimuth):
        ## (side, centre): roots rise towards the middle of the rear, under the knot.
        if not isinstance(root_el, (tuple, list)):
            return root_el
        s = max(0.0, 1.0 - abs(180.0 - azimuth) / span)
        return root_el[0] + (root_el[1] - root_el[0]) * s * s * (3.0 - 2.0 * s)

    def guide(azimuth, end):
        if drape is not None:
            return _draped(frame, drape, azimuth, elevation(azimuth), end, rows)
        return _falling(frame, azimuth, elevation(azimuth), end, end_x, back, splay * math.copysign(1.0, azimuth), rows)

    guides = []
    for k, azimuth in enumerate(azimuths):
        if k > 0:
            short = (ends[k - 1] + ends[k]) * 0.5 if smooth_ends else max(ends[k - 1], ends[k]) * 0.82 + 0.0
            points, normals = guide((azimuths[k - 1] + azimuth) * 0.5, short)
            guides.append({"ridge": False, "points": points, "normals": normals})
        points, normals = guide(azimuth, ends[k])
        sj = _jitter(seed + k, 15)
        ## Layering only ever lifts a ridge outward: the guide stays the inner bound.
        proud = layer * (1.0 if k % 2 == 0 else 0.0) * (0.7 + 0.3 * abs(_jitter(seed + k, 17)))
        for m in range(1, rows):
            t = m / (rows - 1)
            points[m] = points[m] + normals[m] * proud * math.sin(math.pi * 0.5 * min(1.0, t * 2.0))
        for m in range(2, rows - 1):
            t = m / (rows - 1)
            tangent = (points[m + 1] - points[m - 1]).normalized()
            side = tangent.cross(normals[m]).normalized()
            points[m] = points[m] + side * swirl * sj * math.sin(math.pi * t)
        guides.append({"ridge": True, "points": points, "normals": normals})
    faces_by_ridge = _sheet(bm, guides, thickness, groove, 0 if drape is None else drape.get("edge_guides", 0),
                            0.0 if drape is None else drape.get("groove_ease", 0.0))
    parts = []
    for j, g in enumerate(guides):
        if not g["ridge"]:
            continue
        widths = []
        for m in range(rows):
            t = m / (rows - 1)
            neighbours = [guides[i]["points"][m] for i in (j - 1, j + 1) if 0 <= i < len(guides)]
            spread = sum((g["points"][m] - n).length for n in neighbours) / max(1, len(neighbours)) * 2.0
            ## The groove beside a ridge ends at 82 % of the shorter ridge: below that the band is the ridge alone.
            widths.append(spread * (1.0 if t < 0.82 else max(SHEET_TIP, 1.0 - (t - 0.82) / 0.18)))
        parts.append((faces_by_ridge.get(j, []), {"points": g["points"], "widths": widths,
                                                  "heights": [thickness] * rows, "free": True}))
    return parts


def _bun(frame, bm, spec, gather):
    """A core at the gather point wrapped by coiling clumps: tied hair, not a ball."""
    hit, n = _hit(frame, _direction(*gather))
    rs, ru, ro = spec["radii"]
    ## Seated on the gathered hair, clear of the skull: its inner pole rests on the cap.
    centre = hit + n * (ro + CAP_LIFT_M + 0.002)
    up = Vector((0.0, 0.0, 1.0))
    up = (up - n * up.dot(n)).normalized()
    side = n.cross(up).normalized()
    parts = []
    core = []
    rows, cols = 5, 10
    grid = []
    for r in range(1, rows):
        th = math.pi * r / rows
        ring = []
        for c in range(cols):
            ph = 2.0 * math.pi * c / cols
            ring.append(bm.verts.new(centre + n * (math.cos(th) * ro)
                                     + (side * math.cos(ph) * rs + up * math.sin(ph) * ru) * math.sin(th)))
        grid.append(ring)
    outer = bm.verts.new(centre + n * ro)
    inner = bm.verts.new(centre - n * ro)
    for r0, r1 in zip(grid, grid[1:]):
        for c in range(cols):
            core.append(bm.faces.new([r0[c], r1[c], r1[(c + 1) % cols], r0[(c + 1) % cols]]))
    for c in range(cols):
        core.append(bm.faces.new([outer, grid[0][c], grid[0][(c + 1) % cols]]))
        core.append(bm.faces.new([inner, grid[-1][(c + 1) % cols], grid[-1][c]]))
    parts.append(("Bun.Core", core, None))
    ## Folds: gathered hair folded over the core's outer pole, each in the plane of the
    ## outward normal and an axis `phase` degrees round it, crossing the others: a knot of
    ## folded hair, never a ring round a ball.
    def on_core(direction, lift):
        ## The core's surface along `direction` from its centre, raised `lift`.
        d = direction.normalized()
        s = 1.0 / math.sqrt((d.dot(side) / rs) ** 2 + (d.dot(up) / ru) ** 2 + (d.dot(n) / ro) ** 2)
        return centre + d * (s + lift)

    for k, (phase, reach, width, height) in enumerate(spec.get("folds", ())):
        a = math.radians(phase)
        axis = side * math.cos(a) + up * math.sin(a)
        steps = 9
        lift = 0.0015 * (k + 1)
        centres, widths, heights, rings = [], [], [], []
        for i in range(steps):
            t = i / (steps - 1)
            th = math.radians(reach) * (2.0 * t - 1.0)
            centres.append(on_core(n * math.cos(th) + axis * math.sin(th), lift))
            widths.append(ro * width * (0.55 + 0.45 * math.sin(math.pi * t)))
            heights.append(ro * height * (0.6 + 0.4 * math.sin(math.pi * t)))
        ## Every section point wraps the core (a flat section stood its edges off it).
        for i, c in enumerate(centres):
            tangent = (centres[min(i + 1, steps - 1)] - centres[max(i - 1, 0)]).normalized()
            radial = (c - centre).normalized()
            across = tangent.cross(radial).normalized()
            rings.append([bm.verts.new(on_core(c + across * (u * widths[i] * 0.5) - centre, lift + v * heights[i]))
                          for u, v in FLOW_SECTION])
        faces = []
        sides_n = len(FLOW_SECTION)
        for r0, r1 in zip(rings, rings[1:]):
            for j in range(sides_n):
                faces.append(bm.faces.new([r0[j], r0[(j + 1) % sides_n], r1[(j + 1) % sides_n], r1[j]]))
        for ring, sign in ((rings[0], -1.0), (rings[-1], 1.0)):
            end = bm.verts.new(centres[0 if sign < 0 else -1])
            for j in range(sides_n):
                pair = (ring[(j + 1) % sides_n], ring[j]) if sign < 0 else (ring[j], ring[(j + 1) % sides_n])
                faces.append(bm.faces.new([end, *pair]))
        parts.append(("Bun.Fold.%d" % k, faces, {"points": centres, "widths": widths, "heights": heights, "free": False}))
    for band in range(spec["wraps"]):
        phase = 2.0 * math.pi * band / spec["wraps"]
        steps = 9
        centres, normals, widths, heights = [], [], [], []
        for i in range(steps):
            t = i / (steps - 1)
            s = phase + spec["turn"] * math.pi * t
            radial = side * math.cos(s) * rs + up * math.sin(s) * ru
            depth = (0.35 - 0.7 * t) * ro * (1.0 if band % 2 == 0 else -0.6)
            centres.append(centre + radial * 0.98 + n * depth)
            normals.append((radial.normalized() + n * 0.25).normalized())
            widths.append(ro * spec.get("wrap_width", 1.05) * math.sin(math.pi * (0.15 + 0.7 * t)))
            heights.append(ro * spec.get("wrap_height", 0.3))
        parts.append(("Bun.Wrap.%d" % band, _sweep(bm, centres, normals, widths, heights),
                      {"points": centres, "widths": widths, "heights": heights, "free": False}))
    return parts


## A flow mass's section (across -1..1, up from its keel 0 to its crest 1): broad, softly
## convex, thin at the edges and seated a little into what it lies on; never a tube.
FLOW_SECTION = ((-1.0, 0.06), (-0.62, 0.72), (0.0, 1.0), (0.62, 0.72), (1.0, 0.06), (0.45, -0.14), (-0.45, -0.14))
FLOW_RINGS = 9
## A mass's tip: the last ring's centre carried on by this share of its width, to a point.
FLOW_TIP = 0.6


def _flow_guide(frame, mass, hairline, gather, adaptive=False):
    """A flow mass's guide over the scalp: directions from the head centre through its
    root (azimuth, elevation offset from the hairline: negative starts in front of it; or
    `root_at`, absolute), its `via` controls (azimuth, elevation) and its end (an offset
    from the gather point, or `to`, absolute), on great-circle arcs (`_arc_path`), each
    sample seated on the skull."""
    if "root_at" in mass:
        ## An absolute root (azimuth, elevation): hair gathered from a parting, not the hairline.
        controls = [_direction(*mass["root_at"])]
    else:
        root_az, root_dz = mass["root"]
        controls = [_direction(root_az, _hairline(hairline, root_az) + root_dz)]
    controls += [_direction(az, el) for az, el in mass["via"]]
    if "to" in mass:
        controls.append(_direction(*mass["to"]))
    else:
        controls.append(_direction(gather[0] + mass["end"][0], gather[1] + mass["end"][1]))
    path = _arc_path(controls, None if adaptive else FLOW_RINGS, mass.get("length", 1.0))
    return [_hit(frame, _clear_ears(frame, d)) for d in path]


## Dense samples per radian of a guide's great-circle arcs, and the smoothing passes that
## round its corners at the controls (a spline overshoots between unevenly spaced controls).
ARC_DENSITY = 60.0
ARC_SMOOTH = 40


## Evaluated resolution, independent of the authored controls: a ring every FLOW_RING_RAD
## of arc (about 17 mm on Wolf's skull), denser where the path turns (each radian of
## turning counts as FLOW_CURVE_W radians of length), FLOW_RINGS_MIN..FLOW_RINGS_MAX rings.
FLOW_RING_RAD = 0.17
FLOW_CURVE_W = 0.6
FLOW_RINGS_MIN, FLOW_RINGS_MAX = 6, 22


def _arc_path(controls, count=None, length=1.0):
    """Directions along great-circle arcs through `controls`, smoothed at the controls
    (the ends fixed): `count` of them evenly spaced by angle, or (None) as many as the
    path's length and turning need, spaced closer where it turns. With `length` < 1 the
    path stops at that share of the way (a lock whose tip lies on the hair)."""
    dense = [controls[0]]
    for a, b in zip(controls, controls[1:]):
        steps = max(2, int(a.angle(b) * ARC_DENSITY))
        dense += [a.slerp(b, k / steps) for k in range(1, steps + 1)]
    for _p in range(ARC_SMOOTH):
        dense = [dense[0]] + [(dense[i - 1] + dense[i] * 2.0 + dense[i + 1]).normalized() for i in range(1, len(dense) - 1)] + [dense[-1]]
    lengths, weights = [0.0], [0.0]
    for i, (a, b) in enumerate(zip(dense, dense[1:])):
        turn = 0.0
        if 0 < i:
            before, after = dense[i] - dense[i - 1], b - a
            if before.length > 1e-9 and after.length > 1e-9:
                turn = before.angle(after)
        lengths.append(lengths[-1] + a.angle(b))
        weights.append(weights[-1] + a.angle(b) + (0.0 if count else FLOW_CURVE_W * turn))
    end = lengths[-1] * length
    j = next((i for i in range(len(lengths) - 1) if lengths[i + 1] >= end), len(lengths) - 2)
    span = lengths[j + 1] - lengths[j]
    w_end = weights[j] + (weights[j + 1] - weights[j]) * (0.0 if span <= 0.0 else (end - lengths[j]) / span)
    if count is None:
        count = max(FLOW_RINGS_MIN, min(FLOW_RINGS_MAX, int(math.ceil(end / FLOW_RING_RAD)) + 1))
    out, j = [], 0
    for n in range(count):
        s = w_end * n / (count - 1)
        while j < len(dense) - 2 and weights[j + 1] < s:
            j += 1
        span = weights[j + 1] - weights[j]
        out.append(dense[j].slerp(dense[j + 1], 0.0 if span <= 0.0 else min(1.0, (s - weights[j]) / span)))
    return out


def _outer_height(tree, skull, normal):
    """The outermost hair surface's height over `skull` along its normal (cap, shell,
    earlier masses); just off the scalp where nothing is built (a root below the hairline
    lies on the skin, never floating at the cap's height)."""
    under = CAP_LIFT_M
    start = skull + normal * 0.0005
    while tree is not None:
        hit = tree.ray_cast(start, normal, 0.08)[0]
        if hit is None:
            break
        under = (hit - skull).length
        start = hit + normal * 0.0002
    return under


## A mass glides over what lies beneath it: its seat heights are the envelope of the
## surface under it (each raised to its neighbours' highest, then blurred FLOW_SMOOTH
## times, never below the surface), so it never traces every ridge, groove and earlier
## mass edge beneath it as steps.
FLOW_SMOOTH = 3


def _envelope(values, passes=FLOW_SMOOTH):
    count = len(values)
    out = [max(values[max(0, i - 1):i + 2]) for i in range(count)]
    for _p in range(passes):
        out = [(out[max(0, i - 1)] + out[i] * 2.0 + out[min(count - 1, i + 1)]) * 0.25 for i in range(count)]
    return [max(a, b) for a, b in zip(out, values)]


## Smooth masses (HAIR-FIT styles): seats blurred FLOW_SMOOTH_ALONG times along the mass
## and FLOW_SMOOTH_ACROSS across it (a lock glides over the grooves beneath, its rims never
## zigzag); a hairline root eases from the scalp over the first FLOW_ROOT_EASE of the mass
## (the hair grows out of the skin, no brim); the tip runs on FLOW_TIP_SMOOTH of its last
## width and sinks into what it lies on (a tapered end, never a spike).
FLOW_SMOOTH_ALONG = 6
FLOW_SMOOTH_ACROSS = 2
FLOW_ROOT_EASE = 0.14
FLOW_TIP_SMOOTH = 0.35


def _flow_mass(frame, bm, mass, hairline, gather, seed, smooth=False):
    """A primary hair mass on its guide, lying on the hair already built: every point of
    its section is seated on the outermost surface beneath it (sunk `embed`, so it grows
    out of the volume and its thin edges melt into it, wrapping the head instead of
    standing off it as a flat section would), then raised by the section's own height;
    width and height ease root -> `peak` -> tip and the section rolls by up to `twist`
    degrees. `smooth`: adaptive resolution, blurred seats, a root from the scalp and a
    sunk tip (see FLOW_SMOOTH_ALONG). Returns (faces, profile)."""
    guide = _flow_guide(frame, mass, hairline, gather, smooth)
    built = [f for f in bm.faces]
    verts = list({v for f in built for v in f.verts})
    index = {v: i for i, v in enumerate(verts)}
    tree = BVHTree.FromPolygons([v.co.copy() for v in verts], [[index[v] for v in f.verts] for f in built]) if built else None
    peak = mass.get("peak", 0.35)
    embed = mass.get("embed", 0.002)
    roll = mass.get("twist", 0.0) * (1.0 if _jitter(seed, 21) >= 0.0 else -1.0)
    along = FLOW_SMOOTH_ALONG if smooth else FLOW_SMOOTH
    count = len(guide)

    def rooted(i, seat):
        if not smooth or "root_at" in mass:
            return seat
        x = min(1.0, (i / (count - 1)) / FLOW_ROOT_EASE)
        return CAP_LIFT_M + (seat - CAP_LIFT_M) * x * x * (3.0 - 2.0 * x)

    seats = _envelope([_outer_height(tree, skull, normal) for skull, normal in guide], along)
    centres, ups, widths, heights = [], [], [], []
    for i, (skull, normal) in enumerate(guide):
        t = i / (count - 1)
        centres.append(skull + normal * max(CAP_LIFT_M, rooted(i, seats[i]) - embed))
        ups.append(normal)
        widths.append(_profile(t, mass["width"], peak) * (1.0 if smooth else 1.0 + _jitter(seed, 22 + i) * 0.03))
        heights.append(_profile(t, mass["height"], peak))
    ## The section's points over the surface beneath, as a grid (ring x section point),
    ## enveloped along the mass and across it.
    grid = []
    for i, c in enumerate(centres):
        t = i / (count - 1)
        tangent = (centres[min(i + 1, count - 1)] - centres[max(i - 1, 0)]).normalized()
        across = tangent.cross(ups[i]).normalized()
        across = Quaternion(tangent, math.radians(roll * math.sin(math.pi * t))) @ across
        grid.append([_hit(frame, _clear_ears(frame, c + across * (u * widths[i] * 0.5) - frame["centre"])) for u, _v in FLOW_SECTION])
    sides = len(FLOW_SECTION)
    under = [[_outer_height(tree, s, n) for s, n in row] for row in grid]
    for k in range(sides):
        column = _envelope([under[i][k] for i in range(count)], along)
        for i in range(count):
            under[i][k] = column[i]
    under = [_envelope(row, FLOW_SMOOTH_ACROSS if smooth else 1) for row in under]
    rings = []
    for i in range(count):
        ring = []
        for k, (u, v) in enumerate(FLOW_SECTION):
            skull, normal = grid[i][k]
            ring.append(bm.verts.new(skull + normal * (max(CAP_LIFT_M, rooted(i, under[i][k]) - embed) + v * heights[i])))
        rings.append(ring)
    faces = []
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(sides):
            faces.append(bm.faces.new([r0[k], r0[(k + 1) % sides], r1[(k + 1) % sides], r1[k]]))
    start = bm.verts.new(centres[0] - (centres[1] - centres[0]).normalized() * widths[0] * 0.1)
    run = (centres[-1] - centres[-2]).normalized() * widths[-1]
    if smooth:
        tip = bm.verts.new(centres[-1] + run * FLOW_TIP_SMOOTH - ups[-1] * (embed + heights[-1] * 0.2))
    else:
        tip = bm.verts.new(centres[-1] + run * FLOW_TIP + ups[-1] * heights[-1] * 0.3)
    for k in range(sides):
        faces.append(bm.faces.new([start, rings[0][(k + 1) % sides], rings[0][k]]))
        faces.append(bm.faces.new([tip, rings[-1][k], rings[-1][(k + 1) % sides]]))
    return faces, {"points": centres, "widths": widths, "heights": heights, "free": False}


def _sector(azimuth):
    a = abs(azimuth)
    for limit, name in SECTORS:
        if a < limit:
            return name
    return SECTORS[-1][1]


## The scalp cap stays at least this far beneath the hair above it.
CAP_UNDER_M = 0.0015


def _tuck(frame, beneath, over):
    """The cap and shell disappear under the masses laid over them: every vertex of
    `beneath` that would show through a face of `over` (outward from the skull) is lowered
    under it, so no shell band edge or cap row pokes between masses or shows at a root."""
    verts = list({v for f in over for v in f.verts})
    index = {v: i for i, v in enumerate(verts)}
    tree = BVHTree.FromPolygons([v.co.copy() for v in verts], [[index[v] for v in f.verts] for f in over])
    mine = set(verts)
    for v in {v for f in beneath for v in f.verts} - mine:
        direction = (v.co - frame["centre"]).normalized()
        skull, _normal = _hit(frame, direction)
        hit = tree.ray_cast(skull + direction * 0.0005, direction, 0.06)[0]
        if hit is None:
            continue
        reach = (hit - skull).length
        if (v.co - skull).length > reach - CAP_UNDER_M:
            v.co = skull + direction * max(CAP_LIFT_M * 0.5, reach - CAP_UNDER_M)


def _seat_cap(frame, bm, cap):
    """The cap disappears beneath the hairstyle: every cap vertex that would show through
    the first hair surface outward from the skull is lowered beneath it."""
    cap_set = set(cap)
    others = [f for f in bm.faces if f not in cap_set]
    verts = list({v for f in others for v in f.verts})
    index = {v: i for i, v in enumerate(verts)}
    tree = BVHTree.FromPolygons([v.co.copy() for v in verts], [[index[v] for v in f.verts] for f in others])
    for v in {v for f in cap for v in f.verts}:
        direction = (v.co - frame["centre"]).normalized()
        skull, _normal = _hit(frame, direction)
        hit = tree.ray_cast(skull + direction * 0.0005, direction, 0.05)[0]
        if hit is None:
            continue
        reach = (hit - skull).length
        if (v.co - skull).length > reach - CAP_UNDER_M:
            v.co = skull + direction * max(CAP_LIFT_M * 0.5, reach - CAP_UNDER_M)


## Behind the ears the hairline reaches the nape on any skull: from NAPE_FROM to
## NAPE_FULL degrees of azimuth (smoothstep) it is lowered from the style's line to where
## the scalp turns under (the normal's z reaches UNDERCURVE_Z[0]), searched in
## NAPE_STEP_DEG steps no lower than NAPE_LOWEST_DEG.
NAPE_FROM, NAPE_FULL = 100.0, 150.0
NAPE_STEP_DEG = 2.0
NAPE_LOWEST_DEG = -70.0
HAIRLINE_SAMPLE_DEG = 10.0
HAIRLINE_FIT_SAMPLE_DEG = 2.0


def _nape(frame, azimuth, elevation, clear=None):
    """How far down the nape the hair reaches: to the skull's undercurve, and with `clear`
    (metres) no closer than that to the body (a heavy trapezius rises into the nape)."""
    while elevation > NAPE_LOWEST_DEG:
        hit, normal = _hit(frame, _direction(azimuth, elevation))
        if normal.z <= UNDERCURVE_Z[0]:
            return elevation
        if clear is not None:
            p = hit + normal * CAP_LIFT_M
            loc, body_normal, _face, _distance = frame["body"].find_nearest(p)
            if loc is not None and (p - loc).dot(body_normal) < clear:
                return elevation + NAPE_STEP_DEG
        elevation -= NAPE_STEP_DEG
    return NAPE_LOWEST_DEG


def _fit_hairline(frame, hairline, clear=None):
    """The style's hairline fitted to the head: behind the ears it reaches the nape (with
    `clear`, never nearer the body than that)."""
    fitted = []
    ## A head-map fit samples finely enough to follow an ear's narrow peak.
    sample = HAIRLINE_FIT_SAMPLE_DEG if frame.get("map", {}).get("ear_floor") else HAIRLINE_SAMPLE_DEG
    steps = int(180.0 / sample)
    for k in range(steps + 1):
        azimuth = k * sample
        elevation = _hairline(hairline, azimuth)
        x = max(0.0, min(1.0, (azimuth - NAPE_FROM) / (NAPE_FULL - NAPE_FROM)))
        if x > 0.0:
            share = x * x * (3.0 - 2.0 * x)
            elevation += (min(elevation, _nape(frame, azimuth, elevation, clear)) - elevation) * share
        elevation += _brow_shift(frame, azimuth)
        elevation = max(elevation, _ear_floor(frame, azimuth), _ear_floor(frame, -azimuth))
        fitted.append((azimuth, elevation))
    return tuple(fitted)


def _brow_shift(frame, azimuth):
    """How far the front hairline follows the resolved brow (degrees), fading to the sides."""
    brow = frame.get("map", {}).get("brow_el")
    if brow is None or BROW_REF_EL is None:
        return 0.0
    a0, a1 = BROW_FADE_DEG
    x = max(0.0, min(1.0, (abs(azimuth) - a0) / (a1 - a0)))
    return (brow - BROW_REF_EL) * (1.0 - x * x * (3.0 - 2.0 * x))


## Loose hair on a thicker neck rests further out, never longer or wider: how far the
## resolved body's back stands behind the head's back NECK_PROBE_SHARE head heights below
## the chin, beyond Wolf's (NECK_REF_M, measured on male_base_foundation v002, Wolf's
## default body), adds NECK_CLEAR_SHARE of itself to the drape gap; a slimmer neck never
## takes the volume away.
NECK_PROBE_SHARE = -0.15
NECK_REF_M = -0.0062
NECK_CLEAR_SHARE = 0.5


def _neck_clearance(frame):
    z = frame["low"] + NECK_PROBE_SHARE * frame["height"]
    origin = Vector((frame["centre"].x, frame["back"] + 0.4, z))
    hit = frame["body"].ray_cast(origin, Vector((0.0, -1.0, 0.0)), 0.8)[0]
    if hit is None:
        return 0.0
    return max(0.0, (hit.y - frame["back"]) - NECK_REF_M) * NECK_CLEAR_SHARE


def _behind_ears(frame):
    """The azimuth (unsigned) behind both ears' free parts, with the keep-out's margin."""
    spans = frame.get("map", {}).get("ears") or {}
    return max((max(abs(s[0]), abs(s[1])) for s in spans.values()), default=0.0) + EAR_SIDE_DEG


def _build(frame, name, style, hairline):
    ## Only a style fitted to the head map reads it (the approved v001 designs never do).
    if not style.get("fit_head"):
        frame = dict(frame, map={})
    hairline = _fit_hairline(frame, hairline, style.get("nape_clear"))
    bm = bmesh.new()
    cap = _cap(frame, bm, hairline)
    owners = [CAP_MASS] * len(cap)
    names = [CAP_MASS]
    locks = []
    rigid = {CAP_MASS: True}

    def add(mass, faces, profile, is_rigid):
        names.append(mass)
        owners.extend([mass] * len(faces))
        rigid[mass] = is_rigid
        if profile is not None:
            locks.append({"name": mass, "points": [[round(c, 5) for c in p] for p in profile["points"]],
                          "widths": [round(w, 5) for w in profile["widths"]],
                          "heights": [round(h, 5) for h in profile["heights"]], "free": profile["free"]})

    tied = style["tied"]
    counters = {}
    for azimuth, faces, profile in _tied_shell(frame, bm, tied, hairline):
        sector = _sector(azimuth)
        counters[sector] = counters.get(sector, 0) + 1
        add("%s.%02d" % (sector, counters[sector]), faces, profile, True)
    ## Secondary locks layered over the crown, emerging from the volume along its flow.
    lock = {"gather": tied["gather"], "lift": (CAP_TOP_M + 0.0, CAP_TOP_M + 0.014, CAP_TOP_M + 0.008), "bulge": tied["bulge"],
            "peak": tied.get("peak", 0.5), "width": (0.012, 0.07, 0.02), "height": (0.003, 0.011, 0.005),
            "swirl": tied["swirl"] * 2.0, "jitter": tied["jitter"]}
    for i in range(tied["crown"]):
        azimuth = -40.0 + 80.0 * (i + 0.5) / tied["crown"] + _jitter(i, 6) * 6.0
        clump = _tied_clump(frame, lock, azimuth, _hairline(hairline, azimuth) + 6.0 + _jitter(i, 7) * 3.0, 100 + i)
        if clump is None:
            continue
        centres, normals, widths, heights = clump
        add("Crown.%02d" % (i + 1), _sweep(bm, centres, normals, widths, heights),
            {"points": centres, "widths": widths, "heights": heights, "free": False}, True)
    ## Primary flow masses (in order: each seats on the hair built before it), then the bun
    ## over their converging tips.
    beneath = [f for f in bm.faces]
    over = []
    for n, mass in enumerate(style.get("flow", ())):
        faces, profile = _flow_mass(frame, bm, mass, hairline, tied["gather"], 600 + n, style.get("fit_head", False))
        add(mass["name"], faces, profile, True)
        over += faces
    for mass, faces, profile in _bun(frame, bm, style["bun"], tied["gather"]):
        add(mass, faces, profile, True)
        over += faces
    if style.get("fit_head") and over:
        _tuck(frame, beneath, over)
    hanging = style.get("hanging")
    ## Loose hair as several masses: each a draped sheet over its own azimuths (`az`, on
    ## the 0..360 round with the rear at 180), its bands longest in its middle (`length`:
    ## shortest, longest), its own root height, flow and layer, so the loose hair parts
    ## into masses with their own directions and ends, never one curtain.
    for n, spec in enumerate((hanging or {}).get("masses", ())):
        a0, a1 = spec["az"]
        ## Loose hair starts behind the resolved ears (the keep-out's back edge, each side).
        behind = _behind_ears(frame)
        a0, a1 = (max(a0, behind), a1) if a1 <= 180.0 else (a0, min(a1, 360.0 - behind))
        azimuths = [a0 + (a1 - a0) * k / (spec["bands"] - 1) for k in range(spec["bands"])]
        shortest, longest = spec["length"]
        ends = [shortest + (longest - shortest) * (1.0 - abs(2.0 * k / (spec["bands"] - 1) - 1.0)) ** 0.7
                * (1.0 + _jitter(k + 10 * n, 8) * spec.get("length_jitter", 0.0)) for k in range(spec["bands"])]
        drape = dict(hanging["drape"], tree=frame["body"])
        if frame.get("map"):
            drape["gap"] = drape["gap"] + _neck_clearance(frame)
        if "edge_guides" in spec:
            drape["edge_guides"] = spec["edge_guides"]
        for k, (faces, profile) in enumerate(_hanging_sheet(frame, bm, azimuths, spec["el"], ends, 1.06, 0.0, 0.0,
                                                             spec["thickness"], spec["groove"], spec["swirl"], 700 + 20 * n,
                                                             spec.get("layer", 0.0), drape, smooth_ends=True)):
            add("Fall.%s.%02d" % (spec["name"], k + 1), faces, profile, False)
    if hanging and "rear" in hanging:
        rear = hanging["rear"]
        bands = rear["bands"]
        azimuths = [rear["from"] + (360.0 - 2.0 * rear["from"]) * k / (bands - 1) for k in range(bands)]
        azimuths = [a if a <= 180.0 else a - 360.0 for a in azimuths]
        shortest, longest = rear["length"]
        ends = []
        for k in range(bands):
            middle = 1.0 - abs(2.0 * k / (bands - 1) - 1.0)
            spread = rear.get("length_jitter", 0.15)
            ends.append(shortest + (longest - shortest) * middle * (1.0 - spread + spread * (1.0 + _jitter(k, 8)) * 0.5))
        ordered = [a if a > 0 else a + 360.0 for a in azimuths]
        sides_n = {"L": 0, "R": 0}
        drape = None if rear.get("drape") is None else dict(rear["drape"], tree=frame["body"])
        for n, (faces, profile) in enumerate(_hanging_sheet(frame, bm, ordered, rear["el"], ends, rear.get("end_x", 1.06), rear.get("back", 0.0),
                                                             rear.get("splay", 0.0), rear["thickness"], rear["groove"], rear["swirl"], 200,
                                                             rear.get("layer", 0.0), drape)):
            side = "L" if ordered[n] < rear.get("side_from", 0.0) else "R" if ordered[n] > 360.0 - rear.get("side_from", 0.0) else None
            if side:
                sides_n[side] += 1
                add("Lock.%s.%d" % (side, sides_n[side]), faces, profile, False)
            else:
                add("Fall.%02d" % (n + 1), faces, profile, False)
        for k in range(rear.get("locks", 0)):
            t = (k + 0.5) / rear["locks"]
            azimuth = 180.0 - (180.0 - rear["from"]) * 0.8 * (2.0 * t - 1.0)
            azimuth = azimuth if azimuth <= 180.0 else azimuth - 360.0
            end_z = rear["length"][1] * (0.7 + 0.3 * (1.0 + _jitter(k, 16)) * 0.5)
            clump = _hanging_clump(frame, azimuth, rear["el"] - 6.0, end_z, 0.0, rear["back"] + 0.008,
                                   rear["splay"] * math.copysign(1.0, azimuth), rear.get("lock_width", 0.075),
                                   rear.get("lock_height", 0.01), rear["swirl"] * 1.5, 500 + k, 0.3)
            centres, normals, widths, heights = clump
            add("Fall.Lock.%d" % (k + 1), _sweep(bm, centres, normals, widths, heights),
                {"points": centres, "widths": widths, "heights": heights, "free": True}, False)
        sides = hanging.get("sides")
        for side, sign, end in () if sides is None else (("L", 1.0, sides["ends"][0]), ("R", -1.0, sides["ends"][1])):
            azimuths = [sign * a for a in sides["az"]]
            if sign < 0:
                azimuths = list(reversed(azimuths))
            ends = [end + 0.04 * k for k in range(len(azimuths))]
            for n, (faces, profile) in enumerate(_hanging_sheet(frame, bm, azimuths, sides["el"], ends, sides["end_x"], 0.0, 0.0,
                                                                 sides["thickness"], sides["groove"], 0.004, 300 if sign > 0 else 400)):
                add("Lock.%s.%d" % (side, n + 1), faces, profile, False)
    if style.get("seat_cap"):
        _seat_cap(frame, bm, cap)
    cap_set = set(cap)
    bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces if f not in cap_set])
    ## The cap is open: face it away from the head centre explicitly (Godot culls back faces).
    for face in cap:
        face.normal_update()
        if face.normal.dot(face.calc_center_median() - frame["centre"]) < 0.0:
            face.normal_flip()
    bm.verts.index_update()
    vertex_owner = {}
    for face, owner in zip(bm.faces, owners):
        for v in face.verts:
            vertex_owner.setdefault(v.index, owner)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    mesh.set_sharp_from_angle(angle=math.radians(SHARP_DEGREES))
    attribute = mesh.attributes.new(MASS_ATTRIBUTE, "INT", "FACE")
    attribute.data.foreach_set("value", [names.index(o) for o in owners])
    obj = bpy.data.objects.new(name, mesh)
    obj[MASS_NAMES] = names
    obj[LOCKS] = json.dumps(locks)
    material = bpy.data.materials.get("hair") or bpy.data.materials.new("hair")
    ## Preview colour only (the assembly assigns Wolf's intrinsic hair material).
    material.diffuse_color = (0.021, 0.024, 0.027, 1.0)
    mesh.materials.append(material)
    obj["riposte_slot"] = "hair"
    return obj, len(cap), {v: rigid[o] for v, o in vertex_owner.items()}


NECK_WEIGHTS = {NECK: 1.0}
SMOOTH_ROUNDS = 3
## Bones hair that rests on the body may follow (the body's own weights, nearest point):
## beside the jaw that is Head, over the nape mostly Head, on the trapezius Neck and Chest.
RESTING_BONES = (HEAD, NECK, "Chest")


def _resting_weights(body, tree, point):
    """The body's weights where hair rests: the nearest body face's vertices, by inverse
    distance, kept to RESTING_BONES and normalized (hair never follows an arm)."""
    nearest, _normal, face, _distance = tree.find_nearest(point)
    names = {g.index: g.name for g in body.vertex_groups}
    total = {}
    world = body.matrix_world
    for i in body.data.polygons[face].vertices:
        share = 1.0 / max(1e-4, (world @ body.data.vertices[i].co - nearest).length)
        for g in body.data.vertices[i].groups:
            if names[g.group] in RESTING_BONES:
                total[names[g.group]] = total.get(names[g.group], 0.0) + share * g.weight
    norm = sum(total.values())
    return {NECK: 1.0} if norm <= 0.0 else {b: w / norm for b, w in total.items()}


def _weight_hanging(obj, frame, rigid_vertex, body=None, ramp=(HEAD_ONLY, NECK_FULL)):
    """Scalp, tied hair and bun rigid on Head; hanging hair Head -> Neck by height, or,
    with `body`, Head -> the weights of the body surface it rests on (so hair lying on
    the trapezius moves with the trapezius). `ramp`: head heights where Head's share
    starts to fall and where it reaches zero."""
    head_only, off_head = ramp
    computed, free = [], set()
    for v in obj.data.vertices:
        z = (v.co.z - frame["low"]) / frame["height"]
        if rigid_vertex.get(v.index, True) or z >= head_only:
            computed.append({HEAD: 1.0})
            continue
        free.add(v.index)
        below = NECK_WEIGHTS if body is None else _resting_weights(body, frame["body"], obj.matrix_world @ v.co)
        t = min(1.0, (head_only - z) / (head_only - off_head))
        weights = {b: w * t for b, w in below.items()}
        weights[HEAD] = weights.get(HEAD, 0.0) + 1.0 - t
        computed.append(weights)
    if body is not None:
        ## Neighbouring hair resting on different surfaces must not jump in weight.
        neighbours = {i: [] for i in free}
        for edge in obj.data.edges:
            a, b = edge.vertices
            if a in free:
                neighbours[a].append(b)
            if b in free:
                neighbours[b].append(a)
        for _round in range(SMOOTH_ROUNDS):
            smoothed = {}
            for i in free:
                mixed = {k: 0.5 * w for k, w in computed[i].items()}
                for j in neighbours[i]:
                    for k, w in computed[j].items():
                        mixed[k] = mixed.get(k, 0.0) + 0.5 * w / len(neighbours[i])
                smoothed[i] = mixed
            for i, w in smoothed.items():
                computed[i] = w
    groups = {}
    for v, weights in zip(obj.data.vertices, computed):
        weights = {b: w for b, w in weights.items() if w >= MIN_INFLUENCE}
        norm = sum(weights.values())
        for bone, w in weights.items():
            if bone not in groups:
                groups[bone] = obj.vertex_groups.new(name=bone)
            groups[bone].add([v.index], w / norm, "REPLACE")


def _argument(flag, default):
    extra = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return extra[extra.index(flag) + 1] if flag in extra else default


def main():
    replace = "--replace" in sys.argv
    ranger = _argument("--ranger", DEFAULT_RANGER)
    training = _argument("--training", DEFAULT_TRAINING)
    bpy.ops.wm.open_mainfile(filepath=ATTIRE)
    frame = _head_frame(bpy.data.objects["Body"])
    frame["body"] = _drape_frame(bpy.data.objects["Body"])
    styles = (("Hair_Ranger", "HairRanger", RANGER_VARIANTS[ranger], HAIRLINE_RANGER, ranger),
              ("Hair_Training", "HairTraining", TRAINING_VARIANTS[training], HAIRLINE_TRAINING, training))
    for collection_name, name, style, hairline, variant in styles:
        if collection_name in bpy.data.collections:
            if not replace:
                raise SystemExit("RIPOSTE_HAIR_EXISTS: %s has %s; pass --replace" % (ATTIRE, collection_name))
            old = bpy.data.collections[collection_name]
            for obj in list(old.objects):
                bpy.data.objects.remove(obj, do_unlink=True)
            bpy.data.collections.remove(old)
        collection = bpy.data.collections.new(collection_name)
        bpy.context.scene.collection.children.link(collection)
        obj, cap_faces, rigid_vertex = _build(frame, name, style, hairline)
        obj["riposte_variant"] = "%s: %s" % (variant, style["label"])
        collection.objects.link(obj)
        if style.get("hanging"):
            _weight_hanging(obj, frame, rigid_vertex, bpy.data.objects["Body"] if style.get("resting_weights") else None,
                            style.get("weight_ramp", (HEAD_ONLY, NECK_FULL)))
        print("RIPOSTE_HAIR %s variant %s cap faces %d clumps %d vertices %d triangles %d" % (
            name, variant, cap_faces, len(obj[MASS_NAMES]) - 1, len(obj.data.vertices),
            sum(len(p.vertices) - 2 for p in obj.data.polygons)))
    bpy.ops.wm.save_as_mainfile(filepath=ATTIRE, relative_remap=True)


if __name__ == "__main__":
    main()
