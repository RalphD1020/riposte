# Blender art iteration protocol

> The short standing protocol for LLM-driven Blender art work. Read the detailed contracts for normative detail; do not restate them in prompts.
>
> See also: [blender-mcp-hair-clothing-production.md](./blender-mcp-hair-clothing-production.md) (hair/clothing production), [character-layering.md](./character-layering.md) (the appearance plan and coverage), [blender-mcp-character-art-direction.md](./blender-mcp-character-art-direction.md) (Wolf's identity standard), [spec/invariants.md](../../spec/invariants.md#garment-validation-001) (GARMENT-VALIDATION-001, ART-STYLE-001, BLENDER-SOURCE-OF-TRUTH-001).

## Operating principle

**Art direction establishes the shape. Procedural tools adapt it. Automated tests protect it.
Gameplay determines whether it succeeds.**

Mathematics detects what is objectively broken (penetration, holes, exposed skin, inverted
faces, broken seams). Images and a person decide whether something looks good. A geometry
statistic (curvature, polygon count, a relaxation-pass count) is never an aesthetic verdict.

Do not build a new general mechanism for every visual defect. If one authored garment shape
fixes a defect, improve that shape; only generalize when several independent garments show the
same structural failure.

## The approved model is the design authority

The current approved Wolf model is the primary design authority; Soulstone Survivors (readable
forms, economical detail) and Hades II (proportion, material hierarchy, restrained asymmetry)
are supplementary references only. Do not re-interpret the aesthetic from first principles each
task — that is how drift happens. Compare every change against the approved reference views.

Wolf's four permanent art rules (both skins carry all four; see the art-direction doc):

| Principle            | Ranger                                    | Training                                 |
| -------------------- | ----------------------------------------- | ---------------------------------------- |
| Strong silhouette    | Structured, militant, fitted upper armor  | Soft, athletic, relaxed garments         |
| Smooth major forms   | Clean leather planes over cloth           | Rounded fabric, broad folds              |
| Intentional layering | Bracers/boots compress the fabric beneath | Light vest/bindings over loose clothing  |
| Restrained detail    | Belt fastening, chest seam, shaped girdle | Tunic folds, simple closures, soft waist |

## The image-study loop (every visual edit)

1. **Observe** — inspect the candidate beside the approved baseline. Name one specific defect:
   its location, the pose/camera where it shows.
2. **Hypothesize** — silhouette geometry, weights, normals, fit, layering, or coverage? Use
   wireframe or surface-ID inspection only to distinguish causes.
3. **Change** — the smallest authoritative garment or fitting component. Preserve the protected
   character and unrelated assets.
4. **Compare** — render the same camera and pose, before/after, at final-equivalent smoothness
   and real combat distance. Confirm the intended improvement without a regression.
5. **Verify** — run the focused checks the change's scope warrants; keep or revert.

The LLM explains an image, it does not rate it. A useful observation gives a location, the
visual defect, the expected appearance, the likely cause, and a scope constraint — e.g. "the
left sleeve forms a sharp triangular transition into the chest on forward reach; rest-pose
silhouette is fine; defect localized to the shoulder seam; preserve the chest; investigate
sleeve-cap topology/weights before changing volume." Require that specificity before changing
geometry. "8/10" is not a development artifact.

### Session discipline for LLM-driven Blender MCP work

Every iteration is: inspect the exact staged source, its asset and rig identity, topology,
pose and the failing state → make one bounded edit in the owning component (a Blender object,
weight field or clip, or one existing Godot presentation rule) → run the targeted check and
confirm accepted states are unchanged → compare before/after (a Blender render for authored
geometry, a Godot render for imported and runtime behaviour) → save a new staged revision or
revert. One interactive Blender session owns a `.blend` while it is edited: no second agent on
the same file, no long background job against the live MCP session, and no script that keeps
mesh references across an edit (Blender invalidates them). Repeatable operations (building,
mirroring, export, validation) are deterministic `bpy` scripts; anatomical judgement and
local shape edits are interactive. Each approved asset has one canonical editable source; a
generator kept for deterministic variants never becomes a second maintained authority beside a
hand-edited `.blend`. A runtime pose fault is judged on Godot's poses, never on a Blender
frame of the clip. The iteration ends with the concise record below: what changed, what
improved, what regressed, candidate or approved, and the exact asset and rig identities.

## Three test levels — select by the change's risk, not by how many tests exist

| Level               | Trigger                                                     | Scope                                                                                                                                               |
| ------------------- | ----------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| A — quick iteration | every meaningful visual edit                                | a few matched renders (front, three-quarter, gameplay camera, the view showing the defect), the directly affected pose, the relevant geometry check |
| B — milestone smoke | a garment/fitting change is accepted                        | Ranger + Training, reference physique (lean/strongman where fit changed), selected high-risk poses, semantic coverage                               |
| C — full regression | before library promotion, shipping mesh, or F9/F10 approval | full physique sweep, production clips (high-risk clips every frame), coverage, relational checks, Godot import and gameplay                         |

Add the pose that matches the change: shoulder → raised-arm/forward-reach; trousers → hip-flex;
scarf → head pitch; bracer → elbow flex/forearm rotation; boot → knee flex/dash. Do not render
the whole character from every angle after changing one belt fastening. The full battery runs
at milestones, not after every small adjustment — the tests still exist for regression, they
are just not all run every iteration.

### Pose-by-region selection map

| Area changed       | Primary poses                           |
| ------------------ | --------------------------------------- |
| Sleeve / shoulder  | arms forward, horizontal, raised, guard |
| Bracer / cuff      | elbow flex, forearm rotation, guard     |
| Waist / girdle     | torso twist, forward lean, locomotion   |
| Trousers / crotch  | deep hip flex, lunge, running           |
| Boots              | knee flex, walking, dash                |
| Scarf              | head down/up, yaw, combined torso twist |
| Loose hair / scarf | head turn, tilt, combat movement        |

## Validate garment relationships, not the whole fighter each time

The unit of validation is the local relationship between a layer and the surface immediately
beneath it. Compose incrementally; prove each new layer before building the next. When a later
image fails, this tells you the earliest stage where the problem appeared, so you fix the
owning layer instead of rebuilding garments.

Assembly stages (Ranger; Training is the same with its extra tunic/vest): body → tunic → vest →
bracers/boots → belt/girdle → scarf/hair → complete fighter. Hair and neckwear may resolve as
separate branches and combine when their mutual relationship is validated.

At each new layer record only four things: **target** (the evaluated surface beneath),
**relationship** (over/beneath/compresses/continues-under), **required check**, **result**
(pass/fail with an affected-region image). Stop at the first failed stage. If every layer passes
but the assembled character exposes skin, investigate composition, skinning or coverage
trimming — do not rebuild garments.

Local relationships worth checking (region in parentheses): shirt over body (shoulder/armpit),
vest over shirt (chest/armhole), bracer over sleeve (forearm/wrist), belt over tunic (waist),
boot over trouser (calf/ankle), scarf over collar (neck), loose hair over scarf (nape). Layer
order is a local, region-dependent relationship — not a global `offset = previous + thickness`,
which inflates the character.

## The five heuristics

Separate hard failures (block promotion) from soft diagnostic signals (flag for review).

| #   | Heuristic               | Measures                                                   | When                           | Kind                                                                                                                   |
| --- | ----------------------- | ---------------------------------------------------------- | ------------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| 1   | Surface intersection    | unintended crossing/penetration between neighboring layers | after fitting, high-risk poses | hard where a surface is exposed or armor is pierced; soft for concealed minor overlap                                  |
| 2   | Coverage continuity     | forbidden visible skin, holes, missing underlayers         | final assembled character      | hard (`exposure_check.py`)                                                                                             |
| 3   | Boundary integrity      | open seams, broken collars/cuffs, wrong layer order        | garment openings/attachments   | hard; an intended hem/opening is not a defect                                                                          |
| 4   | Deformation stability   | large local stretch, collapse, flipped faces, frame jumps  | relevant pose/clip tests       | hard on collapse/inversion; soft on concealed stretch (region-/material-specific references, not one global threshold) |
| 5   | Silhouette & appearance | choppiness, bulk, readability, intended fabric shape       | every visual iteration         | soft — a person decides from matched images                                                                            |

Distance alone cannot tell inside from outside: a point deep inside a surface can still be
close to its polygons. Use surface orientation / ray intersection / containment to tell
separation from penetration, and report the location and extent of each violation, not just the
worst value. Keep the masked/unmasked twin for diagnosing a failure; it needn't be rendered for
every routine successful edit.

## Design / fit / motion are separate responsibilities

`garment_builder.py` adapts an approved garment shape to the resolved body and nearby clothing;
it does not invent the garment's artistic form by moving vertices away from the body until tests
pass.

| Concept                     | Owner                                                   | Example                                                                 |
| --------------------------- | ------------------------------------------------------- | ----------------------------------------------------------------------- |
| Design (what it looks like) | the authored garment shape / guide curves / fit profile | a baggy sleeve's shoulder, loose upper arm, elbow fullness, narrow cuff |
| Fit (how it adapts)         | resolved anatomy + local clearance against neighbors    | the sleeve follows Wolf's arm proportions over the physique             |
| Motion (how it deforms)     | WolfRig weights + limited correctives                   | the sleeve bends at the elbow                                           |

Baggy clothing gets its shape from where fabric is supported, constrained and allowed to hang —
gathered at cuffs, bracers, belts and boot openings — not from a global ease multiplier applied
equally to shoulders, chest, thighs and ankles. Avoid adding more universal parameters
(arbitrary relaxation-pass counts, ever-wider ray-sampling schemes, garment-specific fallbacks
hidden in shared code) unless a demonstrated multi-garment failure requires it.

## Standardized equipment architecture

One shared organization, two implementation paths. Attire is a layered visual assembly;
weapons are physical combat definitions with matching visual assets. They share identification,
asset references, versioning and loadout selection — not fitting, deformation or collision. Do
not build a universal equipment engine or force both into one inheritance hierarchy.

**Attire slots** (a slot taxonomy, not a render order; two items may share a slot, and the
front/back relationship is regional): `hair`, `inner_torso`, `outer_torso`, `shoulder`,
`forearm`, `waist`, `legs`, `footwear`, `neckwear`. Slots are optional; a character need not
fill every slot. Map these onto the existing `riposte.garment` fields and the outfit manifest —
do not introduce a parallel contract.

**Weapons** stay the existing `WeaponDefinition` + `WeaponHandlingProfile` (physical:
mass/geometry/inertia/contact) with a visual asset that conforms to the physical dimensions.
The active blade follows the deterministic combat simulation, never the hand bone. Costume
selection must never change weapon physics. Composition stays `FighterDefinition +
WeaponDefinition + WeaponHandlingProfile → CombatantPhysicsSpec`.

**Loadout** selects appearance + outfit + weapons by reference; it does not duplicate the
physique, skeleton, face or weapon physics.

**Naming.** Stable logical identifiers (`garment.ranger.leather_vest.v001`,
`neckwear.wolf.tactical_wrap.v001`, `weapon.bastard_sword.default.v001`). Iteration build IDs
(`s17`) stay in evidence records, never in permanent asset identity.

## High-contrast layer analysis is permanent

The surface-ID / high-contrast render is a kept, permanent safeguard — it has repeatedly exposed
shoulder, cuff and throat skin that beauty renders concealed. Diagnostic colors (forbidden skin,
current outer layer, underlying layer, permitted opening) are for debugging renders only;
coverage classification comes from surface IDs and the garment `coverage` contract, never color
matching. Combine two checks: the high-contrast surface-ID render (what is visibly exposed from
each camera) and local geometry intersection/clearance (whether adjacent surfaces cross). Neither
substitutes for the other — an interior overlap can be invisible and acceptable; a skin patch can
be visible despite acceptable distances.

The face has the same safeguard (FACE-LAYERS, `tools/blender/inspect/face_layers.py`): per
expression state and view, the eye rendered alone gives each luminous aperture, the full face
rendered over it in surface IDs (eye magenta, head cyan, brow yellow) names the frontmost owner
of every aperture pixel, and the signed clearance of every evaluated eye sample from the head
says which surface crossed. An island of head inside an aperture, or any head pixel there from
the front, fails; head along the aperture's edge at an angled view is the socket rim. Brows
also pass a contour gate (edge reversals that move the edge visibly, kinks, thickness turns,
degenerate edges, neutral mirror symmetry). States include intermediate weights and
combinations: relative shape keys add linearly, so a pose clean at 0 and 1 can sink through the
head between them. `--negative` pushes an eye behind the head and must fail; the pre-correction
brow is the positive control the contour gate must still reject.

## Every skeleton image carries its skeleton (SKELETON-CAPTURE-001)

Any character tooling image that shows a skeleton-bearing body — Blender inspect / authoring
renders, Godot capture tools, art-iteration probes and the boards composed from them — writes a
sidecar beside the PNG, `<image>.skeleton.json` (schema `riposte.skeleton_capture`): the camera
(projection and transform), every visible skeleton's bones for the exact frame shown (world
position and rotation, the image pixel each joint lands on, in front of the camera / inside the
frame), per skeleton the arm readings (elbow flexion, upper-arm elevation, forearm pitch, elbow
above shoulder and above wrist) and checks with a severity - `hard` (joint lengths preserved
against the rest) makes a pose invalid, `warning`s (elbow lift, an elbow more than 5 cm above its
wrist, upper-arm elevation, a locked or folded elbow) are provisional quality signals, and
silhouette / HEMA credibility / readability stay visual review; a level forearm is fine and the
grip's handedness is the palm attachment order on the handle, never wrist order, the primary skeleton (most
joints in frame) lifted to the top level, and whatever the tool knows about the state (`extra`:
pose, clip, view, grip readings). A board writes `<board>.skeleton.json` with its row / column
sections and each cell's skeletons mapped into board pixels, and can draw the arm joints over the
board (`_joints.png`). Reviews and scorers read pose from that data, never guessed from pixels.
A sword-contact capture (`game/tools/capture_contact_audit.gd`) adds `extra.contact_audit` — the
contact's readings from `ContactRenderAudit` (witness error, visible steel gap, station
correspondence with its near-parallel ambiguity flag, onset discontinuity, vertical separation; m and
gameplay-camera px) — and `extra.weapons` (each drawn sword's steel ends and contact station, the
solver point; world and pixels). Its 2–4 px goal is camera-space readability, never a physical
tolerance: the drawn swords are a declared approximation of the exact planar contact
(CONTACT-PRESENTATION-001).

One format, two writers, one shared definition: `tools/blender/skeleton_capture_core.py` (schema,
arm readings, heuristics, board mapping; self-checked by the game lint),
`tools/blender/inspect/skeleton_capture.py` (`render_still` replaces
`bpy.ops.render.render(write_still=True)`) and `game/tools/skeleton_capture.gd` (`SkeletonCapture.save`
replaces `get_image().save_png`). Godot rolls a skeleton back to its pre-modifier pose after each
update, so the drawn pose is only readable in `skeleton_updated`: a capture tool calls
`SkeletonCapture.watch(self)` before its first shot, and a sidecar written without it says
`pose_source: animation` instead of `final`. The heuristic limits are review targets, not
approvals; change them in both writers together.

## The body bounds its skeleton (ART-ANATOMY-001)

A two-bone IK solution that holds both palms on the sword is not yet a credible pose: the arm can pass through the
ribs, bend its elbow like a ball joint, or leave the wrist to absorb a turn the forearm should make. One
`ArtAnatomyProfile` per production body states what the body allows; poses are fitted against it and judged by it.

- **Fit** — `tools/blender/inspect/anatomical_bounds.py` (Blender, read-only on the blend) fits the volumes from the
  body's dominant-weight vertices (≥ 0.6; a blend-zone bone such as the neck falls back to any weight and says so):
  limb, hand, neck and head capsules (radius balancing skin outside against volume outside, both reported), torso
  sections as convex prisms whose outline follows the section's own vertices (a box or round section stands proud of a
  heroic ribcage exactly where two-handed elbows live). It records each volume's fit quality, the rig's chains and
  capabilities (WolfRig has clavicles as `Shoulder.*`, no twist or finger bones: forearm pronation is the forearm's own
  roll), coordination profiles, the joint frames and the provisional joint ranges. The elbow hinge is calibrated from
  approved bent clip frames whose rest matches the body's (the rest arm is straight, so a straight pose never
  calibrates a hinge); the calibration's spread is reported and frames that disagree (falls, flailing arms) are left
  out and named. Wrist axes come from each palm's normal, signed toward its grip contact.
- **Evaluate** — `tools/blender/anatomical_bounds_core.py` (geometry, pair table, bands, self-checked by the lint) and
  its Godot port `game/tools/anatomical_clearance.gd` (pair clearances; per-arm readings in the calibrated frames:
  shoulder swing / twist, elbow flexion and bend-plane error, forearm roll, wrist flexion / deviation / residual twist,
  each PASS / WARNING / FAIL). Rest-pose clearances match between the engines.
- **Fit poses** — offline only: for each key, candidate chest yaws (where the runtime has a consumer: the cut torso)
  and the elbow around its reach circle, each candidate built as a hinge elbow with forearm roll; hard joint limits and
  proxy overlaps past the hard band are infeasible, everything else is cost; one smooth path per key family is chosen
  over joint (torso, right, left) states with elbow travel and an elbow-speed cap. The output is ordinary key data.
  A key with no feasible candidate is reported as infeasible handling, never relaxed.
- **Second layer** — `tools/blender/inspect/anatomical_mesh_gate.py` applies the final Godot poses 1:1 to the staged rig
  (elbow parity reported), evaluates the deformed body after the armature, and measures arm skin inside the torso and
  inside the other arm by majority ray parity (the regions are open surfaces). The shoulder joint and the two palms on
  the grip are not defects.

- **Judge motion, not keys** — approve a whole trajectory: no bend-branch flip, no oscillating torso between keys, and
  articulation rates evaluated along trajectories recorded from the 60 Hz simulation (`φ̇ = φ′(θ)·θ̇`,
  `φ̈ = φ″(θ)·θ̇² + φ′(θ)·θ̈`). Add keys only where an approved continuous path cannot be represented by interpolation.
- **Trust in proportion to accuracy** — a proxy overlap within the proxies' measured fit error is a lead for the mesh gate,
  not a defect; calibrate joints on independent poses (repeated frames of one held pose are one example).
- **Tools fail closed** — fitting / merge / audit scripts are import-safe, validate inputs before searching, write
  atomically, never overwrite a reference candidate, leave a manifest (input and output hashes), and a failed step stops the
  chain; an audit never measures a scene it could not load.

Bands (proxy overlap, provisional project QA tolerances, not industry thresholds): ≤ 3 mm minor, ≤ 8 mm warning,
≤ 15 mm significant, beyond hard. Joint ranges are provisional until recalibrated on approved reference postures
(longpoint, both high guards, low follow-through). Fit and calibration evidence stay in the iteration folder.

## LOD: profile before building a pipeline

Do not build custom LOD meshes, an optimizer and parity tests before profiling. Run one
integration experiment: import the final-equivalent character into Godot (two fighters, real
animation, arena, shadows, spectators) and measure frame time, skinned geometry and draw calls,
automatic LOD on vs off including high-risk frames. If it performs well, keep the geometry; if a
component is wasteful (the ~16k eyes/ears/brows is the first candidate to inspect — verify its
composition before declaring it waste), simplify that component. Provisional budget references
only (calibrate on target hardware): LOD0 30-50k, LOD1 15-30k, LOD2 6-12k tris per full fighter.

Geometry priority and the masked budget (CHARACTER-GEOMETRY-PRIORITY-001): spend detail by a fixed
order — garments and hair, then head, then eyes/iris, then brows, then ears; the body is present
only where it is exposed. Ears are secondary detail and must not outrank the face/eyes/hair/garments
(the gameplay-stylized ear is the canonical default). The authoritative budget figure is the
masked/exported assembly, never the unmasked review build: the layering engine removes hidden
geometry from the body under garments AND garment-under-garment overlaps, conservatively across the
animation range, keeping anything uncertain. Production topology is deformation-aware retopology that
preserves the approved appearance (never a redesign, never blanket decimation or voxel-remesh as
final); after it, weight transfer + local correction + four-influence prune + the pose suite +
masking + a smoothed preview are mandatory before approval, and smooth shading is finishing only.

## Evidence: one concise record per accepted candidate

Problem (one sentence) · Change (what, and what was preserved) · Visual result (before/after at
gameplay + the failing pose) · Technical result (the focused checks that ran) · Decision (keep or
revert, brief reason). Produce extra wireframes, surface-IDs or geometry charts only to diagnose
an actual defect. Disposable probes live in the gitignored local scratch area and are archived
when done; promote only repeatedly-useful diagnostics into `tools/blender/inspect/` (or
`pose_fixture.py` / `exposure_check.py`). The scratch area is not a second production pipeline.

## Bounded, recorded exceptions (do not reopen without new contrary evidence)

- **`ring_fall` underarm visibility exception.** At the actual gameplay camera (48° pitch, 14 m,
  40° FOV, 1280×720) the full-overhead underarm in the ring-out fall is not observable: on-screen
  exposed skin peaks at ~0.07% of the frame and is dominated by the permitted hands and upper
  face; the armpit self-occludes with the arms up and is submerged below the shoulder line after
  water entry (`ring_out_water.gd`). Bounded to `ring_fall_a/b/c`, the underarm region, airborne
  frames, at match-camera distance. No pose corrective; not a general ignore rule.
- **Strongman crotch concealed overlap.** The Training strongman seat/crotch center-front vertex
  sits ~57 mm interior (shared `Seat` piece; the body is identical across builds; `_resolve`
  cannot reach a behind-surface vertex by design). The masked strongman gate shows 0 exposure at
  rest and through deep-flex clips, so it is concealed interior overlap. Accept; do not reshape
  the shared seat (would risk the reference/lean fit). Not a general internal-penetration ignore.
