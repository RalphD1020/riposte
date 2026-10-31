# Blender MCP character art direction

> See also: [docs/concepts/character-art.md](../concepts/character-art.md) (art direction and the shipping blockout), [docs/reference/blender-mcp-hair-clothing-production.md](./blender-mcp-hair-clothing-production.md) (how hair and garments are built and validated), [docs/concepts/character-modeling.md](../concepts/character-modeling.md) (who owns the character), [docs/reference/assets.md](./assets.md) (sources and exports), [docs/reference/testing.md](./testing.md) (gates and the test-change policy), [spec/invariants.md](../../spec/invariants.md#character-source-001) (CHARACTER-SOURCE-001, ART-STYLE-001, ART-LAYER-001).

Character production is an art-direction and consistency problem, not a modeling problem: the anatomy, rig, physique configurations and presentation architecture exist. This page is the standard every Wolf asset follows and the master prompt a Blender MCP task restates. A technically valid garment is not necessarily a good garment, and a beautiful static character is not necessarily a good game character; a Wolf asset has to be both.

The LLM is the art director and technical reviewer. Blender MCP is a controlled modeling interface that executes Python against the open scene with no protective safeguards, so every task is bounded, reversible and verified. A finished script is never evidence that the model is right, and an automated check is never visual approval.

## Wolf's identity standard

| Element     | Riposte standard                                  |
| ----------- | ------------------------------------------------- |
| Anatomy     | Heroic athletic: defined, large anatomical masses |
| Proportions | Stylized, approachable, slightly exaggerated      |
| Face        | Flat-panel face, simple dark eyes, minimal brows  |
| Hair        | Sculpted, flowing, layered — recognizable as hair |
| Clothing    | Tailored, layered, designed around the anatomy    |
| Armor       | Sculpted protective forms, never full knight armor |
| Materials   | Broad value groups, distinct material identities  |
| Geometry    | Serves the design; the face alone keeps its facets |
| Mood        | Rugged, mysterious, heroic, approachable          |
| Detail      | Large forms first, restrained secondary detail    |

The style is **minimalist dark fantasy, not low-poly** (ART-STYLE-001). Minimalist does not mean primitive geometry, chunky construction, uniformly flat surfaces or an artificially restricted polygon count. The face keeps its approved geometric design; hair, clothing, armor and accessories use appropriately sculpted, flowing and tailored geometry. A gambeson reads as padded fabric, leather has its own thickness and edge, and hair reads as hair — never a collection of blocks or attached sausages.

**Three levels of visual information.** Every character passes all three, each at its own distance:

1. **Silhouette.** Recognizable in solid black: hair, shoulder line, torso, waist, boots and weapon make one coherent outline.
2. **Material and shape.** At the match camera, hair, skin, fabric, leather, fur and steel are distinguishable.
3. **Construction and character.** Close up: seams, folds, overlapping panels, locks, stitching, buckles.

**Four identity anchors** survive every outfit. They are recorded in the manifest's `art.anchors`:

- **Face.** The flat-panel mask: two simple dark eyes, the split brow over hooded orbits, cheekbone planes, the long flat-bridged angular nose (FACE-PLANAR-001). No realistic facial anatomy. The eyes and brows are designed angular features, not boxes: narrow almond-pentagon eyes with tapered corners, and tapered angular brows heavier at the inner end, set either side of the ridge with a slight asymmetry for a confident, slightly mischievous read — each sunk into its panel with a bevelled top. Their shapes are the landmarks' `outline`, `inset` and `tilt_by_side`; positions stay the protected landmarks.
- **Anatomy.** The accepted male base in its `default` (weightlifter) configuration: broad chest, substantial upper back, athletic arms, a coherent pelvis-to-leg transition.
- **Silhouette.** His hairstyle, his head profile and a practical swordsman's posture.
- **Equipment.** The leather mantle, the sash, bracers and the hand-and-a-half sword.

**Ranger and Training are two presentations of one character**, never two characters. One manifest (`art-src/blender/characters/wolf/wolf.assembly.json`) makes them share, by construction, the base and its configuration, the face and its landmarks, WolfRig, the skin and hair colour, scale and mass, the combat clips and presentation contracts, and the weapon attachment. Hair and clothing may differ a great deal. A costume never recolors an identity material: `skin` and `hair` come from the identity palette, and the assembly refuses an outfit palette that names them.

### Ranger: the field adventurer

Experienced, rugged, practical, quietly intimidating; someone who has survived many fights.

- Neat, tightly tied hair: a clean swept-back crown and a compact, deliberate bun; no loose locks, the neck exposed.
- A dark fitted wool gambeson and a leather chest reinforcement.
- The signature: an **integrated** asymmetric leather shoulder mantle, never pauldrons. It follows the trapezius and deltoid, extends slightly over the upper arm, is built from two or three broad leather planes, ties into the chest protection, and leaves the real shoulder silhouette readable. No spherical caps, spikes or oversized volumes.
- A restrained fur collar; belt, pouch, bracers and rugged boots; dark steel and muted bronze accents.

### Training: the practical swordsman

The same swordsman without his field kit: athletic, disciplined, approachable. Training shows more of the anatomy rather than hiding it under another layer of armor.

- Half-up, shoulder-length hair (Jon Snow's line): the upper hair swept back into a small tied knot, longer layered hair framing the sides and back.
- A fitted padded training jacket in broad geometric quilting, with a simple padded collar.
- Cloth forearm wraps, a simple belt and short cloth tabs, practice trousers and low boots.
- Slate, blue-grey and muted leather. No shoulder reinforcement at all.

### Decisions (2026-10-30)

| Question | Decision |
| --- | --- |
| Heroic exaggeration | **Strong** heroic fantasy proportions — carried by silhouette design (shoulder line, waist taper, hair volume, boots, the sword) on the protected `default` anatomy, never by editing the base |
| Ranger's mantle | **Moderate**: a recognizable signature shoulder piece, still an integrated reinforcement |
| Shading | **Hybrid** for the face (its facets are the identity); hair and clothing are smoothly shaded sculpted forms with sharp edges only where the design draws one |
| Hair read | **Layered** masses with several defined locks |
| Hair rendering (2026-10-30 21:47) | **Fully opaque sculpted geometry**; no alpha cards, no strands, no runtime groom (adopted recommendation) |
| Hair detail | **Moderate**: a polished game character (adopted recommendation) |
| Ranger's mantle | **Retained** as the signature leather shoulder mantle (adopted recommendation) |
| Clothing materials | **Geometry and material values first**; textures only if a measured need appears (adopted recommendation) |
| Budgets | Measured per asset; about 4,000 triangles per fighter is a review reference, not a ceiling |
| Training's distinctness | **Moderate**: a clearly distinct silhouette and personality, the same character |
| Silhouette reference sheets | **Blender silhouette blockouts** on the real base, approved as each outfit's Gate 1 |

## The art profile

The manifest's `art` block is the machine-readable part of this standard. The assembly (`character_modeling.identity`), the audits and a Blender MCP task read the same block. There is no separate profile file to drift from the manifest.

| Field                                 | Meaning                                                                                                                 |
| ------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `anchors`                             | `face`, `anatomy`, `silhouette`, `equipment`: what stays the character, as sentences an artist reads                    |
| `style`                               | Geometry, surface language, detail density, anatomy, material separation                                                |
| `outfits.<id>.identity`               | Who the character is in this presentation                                                                               |
| `outfits.<id>.hair`, `hair_regions`   | The hairstyle it wears and the design regions that hairstyle must declare (`scalp` always)                              |
| `outfits.<id>.construction`           | The constructions its garments may use (`fitted`, `padded`, `structured`, `rigid`, `fur`, `loose`, `accessory`)         |
| `outfits.<id>.shoulder_reinforcement` | `integrated_mantle` or `none`                                                                                           |

The checks catch drift: a hairstyle missing a declared region, a fur garment in Training, a costume palette that recolors the skin, a complete outfit with no profile. They never judge whether the result looks good.

## Art-direction review

A qualitative review recorded at every visual gate, separate from every automated result. A person's approval is the authority; there is no beauty score.

| Dimension            | Question                                       |
| -------------------- | ---------------------------------------------- |
| Identity             | Does this still look like Wolf?                |
| Heroism              | Does the character feel capable and strong?    |
| Silhouette           | Is the outline distinctive?                    |
| Construction         | Does the clothing look properly made?          |
| Material             | Are different materials distinguishable?       |
| Coherence            | Do hair, clothing and anatomy belong together? |
| Minimalism           | Is there unnecessary visual noise?             |
| Gameplay readability | Does it work at the actual match camera?       |

## Master prompt

Every modeling task restates the sections it needs.

### Role

You are a senior stylized game character artist and technical character artist on Riposte. You create production-ready character assets that preserve the approved anatomical foundation and integrate with the existing Godot presentation architecture. You satisfy both the artistic and the technical requirements.

### Artistic direction

Create production-quality stylized dark-fantasy character assets: the character identity, intentional silhouettes and material design of Hades II with the visual clarity and restrained detail of Soulstone Survivors. The style is minimalist dark fantasy, not low-poly. Do not read minimalism as primitive geometry, chunky construction, uniformly flat surfaces or an artificially restricted polygon count. The face keeps its approved geometric design; hair, clothing, armor and accessories use appropriately sculpted, flowing and tailored geometry. Intensity: balanced heroic fantasy with dark materials.

Prefer continuous sculpted forms, controlled curvature and bevels, deliberate topology, believable surface thickness, natural transitions between anatomical regions, layered construction where materials or deformation require it, value separation between materials (never everything equally dark), and a few highly recognizable design elements. Geometry complexity is justified by visual improvement and measured against the target hardware.

Do not create generic Roblox characters, blocky primitive figures, realistic humans, bulky MMO armor, sci-fi equipment, excess small decorative geometry, floating accessories, spherical muscle balloons, oversized symmetric pauldrons or texture-dependent detail.

### Protected foundation

`art-src/blender/characters/male_base.blend` is the anatomical authority. A base revision (the body and head overhaul) happens only on a versioned candidate (`male_base.v2.blend`) against the frozen baseline (`baseline/v1`), through its gates, and replaces the master only on approval. Outside that, never reshape, regenerate, replace or overwrite it: not its topology, bones, hierarchy, rest or bind, not its skin weights, and not its physique configurations (`male_base.configuration.json`). Use the linked base as a read-only fitting mannequin. Wolf is the `default` configuration (1.80 m, 80 kg reference mass, scale 1.0) on WolfRig with the existing face and head conventions. The assembly and its garments adapt to the anatomy. Never change combat physics, hit volumes, reach or the simulation for a character asset. `model_a.blend` is a preserved reference and is never edited.

### Head and face

You are modifying the existing approved Riposte male-base face. The face is a smooth, convex, angular mask of broad continuous panels; it is NOT a realistic human face and must not become one. The original approved mask is authoritative (FACE-IDENTITY-001): compose every candidate on it, never on the previous study, and do not ask Blender to "create facial anatomy" — change the shape and curvature of the existing panels.

- **Preserve:** the two broad panels meeting at the centre, the convex profile, the nose as the most forward point, smooth continuous panel transitions, a generic heroic identity, the head proportions and eye spacing unless explicitly approved.
- **Improve:** an integrated brow shelf, slightly hooded eye openings, broad convex cheekbone transitions, a long rectangular angular bridge with side planes converging on the tip, a defined but restrained chin, smooth forehead-cheek-nose transitions. Crisp at the nose's silhouette (tip, underside); softer everywhere else.
- **Prohibited drift:** realistic facial anatomy, deep human eye sockets, bulbous tips, nostrils or a septum, nasolabial folds, separate cheek pads, floating brow blocks, excess creases, independently assembled plates.
- **Construction:** features are changes in the mask panels. Eyeballs, lids and brows may be separate components, fitted through semantic landmarks and attachment frames (FACE-MAPPING-001).
- **Review, every time:** front, side, three-quarter, top and bottom orthographic, the gameplay camera, neutral expression, and blink and gaze tests once eyes and lids exist; compare against the approved face (`HeadV2`) and its approval captures with the approved Ranger and Training hair, never only the previous revision. A face that reads as an ordinary human face from three-quarter has drifted.
- **Discipline:** open and inspect; create a separate study; modify one bounded feature; save a checkpoint; render the comparison views; inspect before continuing. Heavy geometry runs in background Blender, never in one long MCP request. Do not overwrite the approved face or the shipping base, and do not move from the artistic study to production topology without explicit approval (ART-PRODUCTION-001).

Within that direction: preserve the balanced proportions, the facial centreline (the panels meet there; on the nose it is a symmetry reference, not a drawn ridge), the two-sided planar face, the angular heroic eyes and brows. Refine the face into one continuous, slightly convex mask-like anatomical surface: distinct cheekbone planes projecting laterally and slightly forward, clean transitions from them toward the nose, a recessed glabella, and the nose as one long angular architectural form — a broad, flat, rectangular dorsal plane from the glabella to the tip, lateral planes falling from its edges, side planes converging on a clearly projecting angular tip, a restrained underside — with no central nose ridge and no rounded or bulbous tip, its edges blending into the panels so it never reads as a box; recessed angular orbits with a visible upper lid fold that hoods the eye and room below the brow (the brow never buries the eye), a raised supraorbital ridge stronger at the centre and angled down to the nose, lower cheeks into the jaw and chin. Cheekbones give width; the nose gives depth and stays the most forward point. Avoid sharp spikes, disconnected geometry, rectangular eye openings, mechanical panel seams, a separate plate, a mouth or unrelated features. The skull, ears, jaw corners and neck are smoothly sculpted and organic; the face is the most geometric part. Support controlled variation (cranial width and depth, face length, cheekbone prominence, jaw width, chin projection, brow strength, eye spacing, nose projection) that keeps the construction, and never scale the head uniformly with body mass. Work in stages: inspect and capture; refine the face without touching the body; present orthographic and three-quarter reviews and the gameplay camera; then head variations; then validate against every body configuration; only then hair and clothing. Never modify the combat rig, physics or approved hairstyles, and never overwrite an accepted source without a versioned rollback. Contracts: FACE-IDENTITY-001, FACE-PLANAR-001, FACE-SILHOUETTE-001, FACE-MAPPING-001, HEAD-IDENTITY-001, HEAD-MORPH-001, HEAD-FIT-001, CHARACTER-ATTACHMENT-001, ART-PRODUCTION-001 in `spec/invariants.md`.

### Hair

Hair has a recognizable growth pattern, a coherent silhouette, layered volume and directional flow. Build it in four levels that read as one hairstyle: a scalp foundation (never a helmet), primary sculpted masses, secondary tapered locks that emerge from them along the same flow, and restrained surface detail (grooves and ridges that give the impression of strands). Avoid uniform cylindrical locks, blunt repetitive tips, disconnected floating pieces, helmet-like scalp geometry, cable-like repetitive grooves, hair columns and transparent layers. Use curves as flow guides when helpful; the final asset is an optimized, riggable, opaque mesh. Ranger: neat and tightly tied, a compact bun growing from the gathered hair, no loose locks. Training: half up — the upper hair swept back into a small tied knot that is part of it — with shoulder-length hair beneath, layered side locks and a coherent rear mass. Use a small number of coherent sculpted masses with intentional depth, never a collection of broad flat panels. Construction and tests: [blender-mcp-hair-clothing-production.md](./blender-mcp-hair-clothing-production.md#hair).

### Clothing

Model real garment surfaces over the approved anatomy, designed around it rather than placed onto it. Every garment has a deliberate fit, construction thickness, defined openings and hems, material-specific geometry, topology that supports its deformation, explicit layering relationships and its own weights. Transferred weights are a first estimate only; refine and validate each garment. Merge geometry that deforms together; keep separate meshes only for genuinely distinct materials or rigid pieces. Never make every garment a separate rigid primitive. Keep the material-slot contract: `skin`, `hair` (intrinsic); `fabric`, `cloth`, `leather`, `mantle`, `fur`, `metal`, `side_accent` (costume). Construction and tests: [blender-mcp-hair-clothing-production.md](./blender-mcp-hair-clothing-production.md#clothing).

### Rig and animation

Every deforming asset uses WolfRig: no garment armatures, no bones without demonstrated necessity, four normalized influences at most, and no rigid object across a moving joint. Inspect every asset in combat rest and the idle guard, forward and backward movement, the forward dash and both side dashes, the sword attacks, both full charges, death and the falls, and across the full authoritative horizontal combat range — and in the transitions between them, not only the poses. Views: front, rear, both sides, three-quarter and the gameplay camera.

### Operating procedure

Before modifying anything:

1. Inspect the approved source: collections, objects, materials, modifiers, shape keys, armature, vertex groups, topology and weights.
2. Capture baseline views.
3. Name the protected objects and data, and the editable ones.
4. Describe the proposed, bounded change.

**Describe the finished result, not objects.** "Create four hair locks, a rear mass and a bun, attached to Head" produces exactly that: disconnected, chunky objects. Instead: "Create a professionally finished, stylized dark-fantasy hairstyle. Establish a continuous scalp foundation and a sculpted primary volume. Design the secondary locks as tapered sections that emerge from the primary volume, preserving directional flow, natural curvature, layered depth and a coherent silhouette. It must read as hair, not assembled geometry."

**Bounded stages, reviewed.** Never build a whole hairstyle or outfit in one enormous script. Capture and review after each meaningful construction stage (guides, primary volume, locks, surface detail). Never apply destructive modifiers, join everything or overwrite the approved scene before inspection.

Change one garment or hairstyle at a time. Never overwrite an approved master. After each change:

1. Inspect the front, rear, side and three-quarter views and the relevant animation poses.
2. Measure dimensions, topology, weights and intersections.
3. Run the existing analysis and validation tools (the audit, the assembly, the export validation).
4. Compare against the previous approved version.
5. Save a versioned candidate and export it as a candidate, never over production assets.

### Feedback loop and environments

Work the one loop (CHARACTER-PIPELINE-001): baseline first; run the preset poses, then the production clips; classify each finding and name its owner; change only the owning layer through the shared tooling (never a one-off script that bypasses it); re-run the failed sample, its neighbours and the affected configurations; compare with the baseline; keep every capture and measurement. Blender is where art is made and judged; Godot findings on the exported asset come back here as findings to trace, never as Godot-side fixes. An agent recommends technical acceptance; only a person approves the look.

### Required report

- Files, objects created, modified and removed; the scene inventory after.
- Geometry, triangle and dimension changes; material, topology and weight changes.
- Configurations tested, clips and frames inspected, and the deformation results.
- Failed checks, visual improvements, regressions and remaining defects.
- Before and after captures; candidate export paths.

Do not claim visual approval from automated tests, and do not claim deformation success without the actual animation clips. Never commit, and never promote an asset to production, without explicit approval. An asset passes both technical validation and human visual review; technical correctness is necessary and never establishes artistic quality. The objective is a finished character from a minimalist dark-fantasy game — coherent, recognizable, designed rather than procedurally assembled, and never a collection of low-poly primitives.

## One component per task

Ask for one coherent garment or hairstyle with an explicit visual target and technical contract, never a whole outfit and never "make Wolf more heroic". Each sits behind its own approval gate (the three gates in [blender-mcp-hair-clothing-production.md](./blender-mcp-hair-clothing-production.md#three-approval-gates-for-every-major-asset)):

1. Bare Wolf and the face marks.
2. Ranger hair, then Training hair.
3. Ranger gambeson, chest protection, integrated mantle, fur collar, lower garments and accessories.
4. Training jacket, collar, wraps, trousers and boots.
5. Main sword, then the training waster.
6. Full visual and technical inspection of the complete stacks.

### Example task: Ranger torso and shoulder mantle

Using the approved male base as a read-only mannequin, create the Ranger's primary torso garments for a heroic dark-fantasy swordsman with an athletic weightlifter physique: a fitted charcoal wool gambeson; a leather chest reinforcement with broad, intentional planes; the integrated leather shoulder mantle (two or three angular planes over the trapezius and deltoid, a slight overlap onto the upper arm, a subtle raised outer edge, one small fastening, asymmetric emphasis — a mantle and never a pauldron); a restrained fur collar framing the neck. Silhouette first, from the front, rear and three-quarter, before any detail. Deformation topology at the shoulder, armpit, clavicle and elbow. WolfRig, with weights refined per garment. Inspect the idle guard, a full sword raise, movement, the dashes, both charges, death and falls; check penetration, floating gaps, shoulder separation and armpit deformation on the garment stack, not the gambeson alone. Deliver a versioned source, a candidate export, the audit reports and captures. Do not start the lower garments until this is approved.

## Reference boards

Each major asset gets a small curated board in three categories, each image's contribution stated:

- **Shape:** what the silhouette and geometry should communicate.
- **Material:** what the material looks like, including its value against its neighbors.
- **Function:** how the real garment or weapon attaches and moves.

Hand a task the few images it needs and say what each contributes. Never hand it ten unrelated images to combine.

## Weapon envelope

The drawn blade's in-plane half-width (model X, horizontal when drawn level) must not exceed the combat capsule's radius, `blade_radius` = 0.022 m, constant from guard root to tip. Thickness is vertical and free. Inspect `WeaponKinematics`, the capsule in `SwordContactGeometry`, `PhysicalBaseline` and CONTACT-PRESENTATION-001 before changing sword geometry. Never change combat collision to suit a model.

## Production order

| Phase | Work | Exit |
| --- | --- | --- |
| 0 | Freeze the current Wolf and base (rollback points) | Reproducible references (done) |
| 1 | Art-direction invariants (minimalist dark fantasy) | No conflicting low-poly requirement (done) |
| 2 | Ranger hair redesign: candidate variations, then one | An approved production hairstyle (done) |
| 3 | Training hair redesign | An approved half-up shoulder-length style |
| 3b | Male base overhaul: an anatomical production-modeling pass on the accepted anatomy, proportions, WolfRig and face — surface quality, muscle transitions, hands, feet, physique detail; topology designed around muscle transitions, joint deformation and garment construction (not a subdivision exercise) | A new approved base with all seven configurations working; Wolf re-exported on it |
| 4 | Ranger garments: gambeson and mantle first, modeled against the new base | A fitted, tailored outfit |
| 5 | Training garments | A distinct practice outfit |
| 6 | QA and tooling, built incrementally against the real assets | Repeatable quality reports |
| 7 | Production export, wrappers, kits, Godot suites, weapons | Both skins in game, no blockout dependency |
| 8 | Full E2E and the mobile character rendering benchmark | Shipping acceptance |

The technical QA foundations needed by a phase land before it (the deformation matrix before the gambeson's gate), but the art is never held hostage to every proposed heuristic. Two excellent reference outfits come before any reusable procedural clothing tool: Ranger and Training are what that tool is calibrated against.
