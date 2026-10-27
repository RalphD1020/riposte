# Character anatomy: heroic forms and the back

> See also: [character-modeling.md](../concepts/character-modeling.md) — the study pipeline and diagnostics, [character-art.md](../concepts/character-art.md) — the shipping blockout
> Source: the P-phase polish of the proportion study (`tools/character_modeling`)

The target is a sculpted, readable action figure, not an anatomy study and not a bodybuilder. Muscle reads through the connected silhouette and broad planes, not as a pile of separate forms. The only hard edge on the figure is the face's central ridge; the face panels may read as angular in profile. Everything else is a smooth, natural transition.

This guide is the artistic target the polish phases work toward and the scanner reports evidence against. It is not a set of numbers; the numbers live in the profile and the calibrated thresholds.

## Build order

Build the overall volume first, then suggest anatomy with shallow planes and the light. Do not model a muscle as a separate lump, and do not use smoothing to repair a bad profile — correct the generating curve, then let shading support it. A faceted surface can still have a clean silhouette; a smooth-shaded surface can still have a bad one. Fix the shape, not the normals.

## Face and head

- The centre ridge rises from the forehead, peaks at the nose tip, and falls to the chin. It is the one intended hard edge.
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
