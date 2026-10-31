# Character anatomy: heroic forms and the back

> See also: [character-modeling.md](../concepts/character-modeling.md) — the study pipeline and diagnostics, [character-art.md](../concepts/character-art.md) — the shipping blockout
> Source: the P-phase polish of the proportion study (`tools/character_modeling`)

The target is a sculpted, readable action figure, not an anatomy study and not a bodybuilder. Muscle reads through the connected silhouette and broad planes, not as a pile of separate forms. The only hard edges on the figure are the face's designed plane changes — the nose's flat dorsal plane and the planes that meet it, the brow shelf, the cheekbone planes (FACE-PLANAR-001). Everything else is a smooth, natural transition (ANATOMY-FORM-001).

This guide is the artistic target the polish phases work toward and the scanner reports evidence against. It is not a set of numbers; the numbers live in the profile and the calibrated thresholds.

## Build order

Build the overall volume first, then suggest anatomy with shallow planes and the light. Do not model a muscle as a separate lump, and do not use smoothing to repair a bad profile — correct the generating curve, then let shading support it. A faceted surface can still have a clean silhouette; a smooth-shaded surface can still have a bad one. Fix the shape, not the normals.

## How the body is built

Three levels, each approved before the next (the hierarchy every anatomy-sculpting course teaches, and Blender Studio's stylized character workflow: design sculpt approved, then retopology, then configurations, then clothing):

| Level | What is modeled | Priority |
| --- | --- | --- |
| Primary | Silhouette, ribcage, pelvis, shoulder girdle, limb volumes, joints, neck, hands, feet | Highest |
| Secondary | Major muscle groups and the transitions between them | High |
| Tertiary | Separations, tendons, joint landmarks | Restrained |

Each limb is first a continuous tapered volume with round cross-sections, shaped from its front and side silhouettes; a muscle group is a broad change in that volume along the limb, overlapping its neighbours. The approved base (`tools/blender/authoring/male_base_v2.py`) follows this: large anatomical forms on a continuous surface, then the heroic proportions as broad fields along each segment and across the girdle and pelvis — never independent blobs.

Lumps come from five causes, each checked on review:

1. Independent muscle blobs instead of continuous groups.
2. Surface displacement larger than the form needs.
3. Abrupt transitions (deltoid into arm and chest, lats into the torso, the quadriceps as one mass).
4. Secondary detail added before the primary proportions are right.
5. Inconsistent smoothing: global smoothing erases structure, local sculpting leaves bumps.

## Physique archetypes

Body mass, muscular development and definition are separate dimensions (PHYSIQUE-AXES-001). The three anchors, with girth targets for a 1.80 m figure — directional guides from athletic anthropometry, stylized for the heroic proportions and calibrated on approved captures, never acceptance thresholds on their own:

| Girth (cm) | Lean sprinter (`extreme_lean`) | Olympic weightlifter (`default`) | Bodybuilder–strongman (`extreme_heavy`) |
| --- | --- | --- | --- |
| Neck | 38 | 42 | 47 |
| Chest | 100 | 112 | 126 |
| Waist | 76 | 84 | 90 |
| Upper arm (relaxed) | 34 | 39 | 48 |
| Forearm | 29 | 32 | 36 |
| Mid-thigh | 56 | 62 | 70 |
| Calf | 38 | 41 | 46 |
| Bideltoid width | 49 | 54 | 60 |

What separates them is not only size:

- **Sprinter.** Lean waist, narrower frame; muscle concentrated at the hips and knees (glutes, quadriceps, hamstrings, calves); shoulders and arms defined rather than heavy; clear definition. Athletic, never frail.
- **Weightlifter (Wolf).** A thick torso with real depth, heavy trapezius and upper back, strong glutes and thighs, a defined waist that is never corseted; muscular without bodybuilding separation. Weightlifters run comparatively compact, with a long trunk for their limbs.
- **Bodybuilder–strongman.** The widest shoulder-to-hip ratio, the most arm and thigh volume, full trapezius and neck; the strongman share keeps the waist and back thick, the bodybuilder share keeps the definition. Imposing, never obese or lumpy.

Definition per configuration (`male_base.configuration.json`): moderate at the default, rising toward both ends (the sprinter moderate-high, the maximum high); the abdominals stay suggested by volume at the default.

## Face and head

The face is anatomically informed stylization, not anatomy: only the features the mask needs, expressed as changes in its panels (FACE-IDENTITY-001). Head variation is three independent systems — head archetype, head proportions, facial feature layout — and two kinds of change that are never confused: identity (how a character looks: jaw profile, brow shape, eye spacing) and physique (how the anatomy looks). Physique adjusts the jaw, cheekbone width, lower-face proportions, the neck transition and at most the temples; it keeps eye spacing and the mask's design, and never scales the skull with body mass:

| Build | Head changes | Preserved |
| --- | --- | --- |
| Lean sprinter | Slightly narrower jaw, leaner cheeks | Brow, eye spacing, the mask |
| Weightlifter (default) | Balanced jaw and cheekbones | The reference face |
| Strongman | Wider jaw, fuller lower face, stronger neck transition | Eye placement, the face's identity |

Every head profile exposes the same semantic landmarks (FACE-MAPPING-001), so features, hair and clothing fit any profile without new code.

- The face is a flat, panel-based mask (FACE-PLANAR-001). The two panels meet on the centre line; the centre line is a symmetry reference, not a ridge to draw.
- The nose is one long angular form: a broad, flat, rectangular dorsal plane from the glabella to the tip (the front plane of the planes-of-the-head model), lateral planes falling from its edges, side planes converging on a projecting angular tip, and a short underside plane back to the face. No central nose ridge, no rounded tip. The dorsal plane's edges blend into the panels so it never reads as a box.
- The brow is a shelf over hooded eyes: a raised supraorbital ridge with a crisp lower edge, an upper lid fold beneath it with clearance, and the cheekbone planes turning the face from front to side.
- The two face panels meet at that ridge and blend into the cheeks and the crown with no sunken border and no proud shelf.
- The forehead flows into a round crown with a continuous, tangent join — no ridge where the face meets the head, no hollow above the brow.
- The jaw and chin are defined, the chin sitting on the line down from the nose tip. The jaw underside is a legitimately sharper surface than the crown.

## Torso and chest

- A full upper ribcage flows into the trapezius and deltoids.
- The pectoral transition is a shallow, broad plane, not two detached bulges.
- The lower chest tapers continuously into the abdomen — no horizontal shelf, no inward dip under the armpit followed by an outward flare.
- A clear V-taper from the shoulders to the waist, with the waist and pelvis widths preserved.

## Back and neck

The back is the region that most often fails. It must not read as a flat plate with two scapula-shaped depressions.

- **Neck and trapezius** — one continuous slope from the base of the skull into the shoulder girdle. No raised neck peg, no deep valley beside the spine.
- **Scapulae** — broad, shallow raised planes that sit within the back's overall volume and catch the light as the back turns. Never sunken holes, never detached-looking plates.
- **Rear deltoids** — fill the back of each shoulder and blend into the upper arms.
- **Lats** — carry the upper-body breadth down toward the waist, making the rear V-taper.
- **Spine** — a natural, restrained curve in profile (a shallow S), never a deep carved channel that splits the back into two columns.

A useful test: render the back under a large, soft light from above and to one side, then move the light. The broad forms should stay readable as the highlight moves. If the anatomy only appears under one exact light direction, the underlying shape is wrong.

## Arms

- The deltoid flows over the shoulder joint into the upper arm, with no nub or hard ledge at the junction.
- The upper arm has a muscular taper — a biceps belly in front, a triceps behind — not a constant cylinder.
- The elbow narrows, then the forearm swells in its upper third and tapers to the wrist.
- Forearms balance the shoulders without oversized wrists. The arm reads muscular in silhouette alone, before any shading.

## Legs and pelvis

- Thighs emerge from the pelvis, not from the bottom of a torso tube; the groin, glutes, and upper thighs stay continuously connected, with no tunic-like hem.
- The upper thigh has enough volume to meet the hip naturally; the outer quad swells.
- The knee is a controlled change in form, not a hard polygonal corner.
- The calf belly sits behind and high, tapering into the ankle with no abrupt change in circumference.

## What not to do

- Do not globally inflate every dimension by a fixed percentage.
- Do not increase polygon count to hide a bad cross-section.
- Do not smooth repeatedly until the body goes soft and loses its forms.
- Do not add separate muscle objects to the shipping mesh.
- Do not use a single smoothness score as the acceptance criterion.
- Do not move the accepted face, head proportions, rig, combat anchors, or physics during a body pass.
