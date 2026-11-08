# Character modeling

> See also: [character-art.md](./character-art.md) — the blockout that ships today, [docs/reference/assets.md](../reference/assets.md) — export and Godot import, [presentation.md](./presentation.md) — clip, combat pose, clavicle, then arm IK
> Source: `tools/character_modeling/`

One pipeline. Definition, physical resolution, construction and presentation stay apart. Construction itself splits into two mappings — anatomy says what the body is, deformation says how that body follows bones — and they share one WolfRig. They are not two skeletons.

| Concern             | What it owns                                                        | Home                                                                                                      |
| ------------------- | ------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Definition          | The saved, versioned inputs: body inputs, shape sliders, status     | `profiles/*.json` (`riposte.character_model` v2), `definition.py`, `parameters.py`                        |
| Physical resolution | Mass, actuator scales, hurt and push radii, grip and lying geometry | `physique.py` → `game/content/characters/*.physique.json` → `FighterCatalog.from_physique` (PHYSIQUE-001) |
| Construction        | Anatomy, landmarks, and fixed topology from the profile and the rig | `anatomy.py`, `production.py`, `tools/blender/bootstrap/build_wolf_production.py`                         |
| Deformation         | Candidate bones, normalized weights, the four-influence limit       | `skinning.py` offline. Godot `Skeleton3D` and `Skin` deform the import; there is no runtime mesher        |
| Presentation        | The one deform skeleton, clips, clavicle, IK, materials             | `WolfRig` (`wolf.rig-contract.json`), the asset export, Godot                                             |

A creation region is not a bone. The shoulder is anchored on the clavicle and may be influenced by the clavicle, the upper arm and the chest. `RegionDefinition.anchors` and `RegionDefinition.deform_bones` are different lists. Weights are a small function of region affinity and distance (`skinning.py`): prune, normalize, at most four influences. They are not a generic solver and they are not nearest-bone labels.

The modeling pose (the A-pose) is how a body is judged. It is not a second skeleton. The game rig is `WolfRig` (bone names, hierarchy, rest transforms, grips, combat clips). The production mesh is built and bound on that one rest pose. Height and segment-length changes that would move joints are a separate, validated family; muscularity and frame do not move the glenohumeral joint. Moving that joint needs a measured proposal and a person's approval.

The blockout in `wolf.character.json` still ships. The production candidate (`wolf_production.glb`) is exported and tested beside it and replaces it only after a person accepts a gameplay capture. A future creator tool is a thin editor over the same definition and configuration; it is never a second geometry system. Art direction is ART-STYLE-001: minimalist dark fantasy (not low-poly; the face keeps its geometric design), a powerful heroic physique (an Olympic weightlifter by default), Hades II presentation.

## The production pipeline and its two approval environments (CHARACTER-PIPELINE-001)

Every character — Wolf, a future fighter, a crowd member, a body an LLM refines through Blender MCP — goes through one pipeline. Character-specific differences live in definitions, profiles and authored assets, never in another builder, resolver, rig or validator.

```text
definition (profile, configuration, identity, attachments)
  -> pure resolver (physique.py, variation.py, head_profile, anatomy)
  -> Blender geometry (the approved base, its variations)
  -> canonical WolfRig mapping (the bind: rest = WolfRig's rest; the A-pose is the modeling reference)
  -> skinning and attachments (weights <= 4 influences, normalized; hair, face, garments, equipment fitted to the resolved anatomy)
  -> Blender pose and silhouette studies (artistic)
  -> Blender preset-pose validation (technical, the pose suite)
  -> Blender production-clip validation (every clip, intermediate frames)
  -> human art approval -> versioned source + GLB export
  -> Godot animation-kit integration (the exact export on the real AnimationPlayer -> CombatPoseModifier3D -> TwoBoneIK3D)
  -> runtime acceptance -> approved version
```

**Two approval environments, never interchangeable.** Blender (through Blender MCP) is the art authority: modeling, anatomy, variation, rig mapping, weights, attachments, pose and silhouette studies, deformation through presets and clips, captures and the evidence a person approves. Godot is the integration authority: it loads the exact exported asset into the production animation kit and proves the import contract (hierarchy, names, rest transforms, skin binding), clip compatibility, the combat pose modifier, clavicle-before-IK, two-bone IK, hands on the grip, root, stature and floor contact, temporal continuity, gameplay-camera readability and runtime budgets. Godot never authors, repairs or replaces art; a Blender approval never implies the Godot gate, and a Godot pass never implies visual approval. Matching bone names is not compatibility: hierarchy, rest transforms and the bind convention are checked. Retargeting is never a repair for a broken mapping — the source or the export is fixed.

**Two kinds of pose study, both required.** Artistic studies (A-pose and reference proportions, rest, guard and ready, heroic attack and defensive poses, strong asymmetry, weapon poses, every side and the gameplay camera) answer _does this character look right_: identity, head-to-body proportion, silhouette, weapon and hand readability. Technical studies (the preset-pose suite and the production clips with intermediate samples) answer _does it deform correctly_: shoulder and clavicle, elbows and wrists, torso and pelvis, hips, knees and ankles, grip, attachment intersections.

**The pose suite (POSE-SUITE-001).** Preset poses are versioned data in `character_modeling`, tied to the rig contract version, and applied in Blender: reference poses (the A-pose, the production rest), preset stress poses (guard, ready, and the existing shoulder release and diagnostic ranges and the hip range), and animation ranges (samples of the production clips, intermediate frames included). The same fixtures run on every physique and character; a fixture changes only as an intentional, documented change to the shared contract, never to let a model pass. Presets are regression fixtures; clips prove timing and transitions; neither replaces the other.

**The integration record (CHARACTER-INTEGRATION-001).** The export manifest written beside every GLB (`asset_id`, `source`, `source_sha256`, `configuration`, bones, animations, attachments, materials, triangles) is the handoff record. It also carries the rig contract's digest and rest signature, the definition and animation-kit versions, and the state of each gate (Blender art, Blender deformation, Godot integration) for that exact source hash; a result recorded against another hash does not count.

**The feedback loop.** An agent (or a person) works the same loop in either environment's findings: observe and baseline → run the presets (then the clips) → measure and capture → classify the finding and its owner (definition/resolver, anatomy, geometry/topology, skeleton mapping, weights, hair or face attachment, garment or equipment fit, material, export, animation contract, runtime IK or pose modifier) → propose the smallest bounded change in the owning layer → apply it through the shared builder → re-run the failed sample, its neighbours and the affected configurations → compare with the baseline → accept or reject → keep the evidence. Godot findings carry the export version, clip, frame, modifier and IK state, the bone or region, expected and observed values and a capture; an art or mapping finding is fixed in Blender and re-run in both environments; a runtime finding is reported to the animation kit, never hidden by distorting the character. An agent recommends technical acceptance; a person approves the look. Only what a change invalidates is re-run (a hairline does not rebuild the body; a rig contract change invalidates every mapping).

## The male base is no one character

`male_base.blend` is the default male body every male character is built from. Wolf is the first character on it, not its owner: a character is the base in a physique configuration plus its own face features (eyes, brows), attire, palette and identity. A character never forks the body, and a fix to the base reaches every character. The female base is a second master on the same schema, rig contract and gates. The skeleton keeps the name WolfRig: it is the canonical fighter skeleton, and its name is historical.

## The default foundation and how a character layers on it (CHARACTER-FOUNDATION-001)

The default male foundation is the approved default body family and the default face, as one document, read and checked by `character_modeling.foundation`. Every male character starts from it; it belongs to none of them. The document is the current `male_base_foundation` library version's (`asset_library.current_foundation_document`), so a revision is a new document beside the old one and a new version, and every builder follows it:

| Version | Document (with its `.blend`, `.record.json`, `.lock.json`, `.regions.json`) | What it added |
| --- | --- | --- |
| v001 (2026-11-02, superseded, kept for rollback) | `male_base.foundation.json` | the default bodies, the default eyes and brows |
| v002 (2026-11-06, current) | `male_base.foundation.v002.json` | the three-physique head (`head_design` on the build coordinate), ears, the lower-face contour, the skull underside, the seated neck; the eye's fixed white (`white: backing`); the body unchanged |

In the table below, file names are v001's; each version's own document names its files.

| Part | What it holds | Built / checked by |
| --- | --- | --- |
| `base` | The v1 master plus the mask and body studies that build the base sculpt (`BodyV2`) and head (`HeadV2`) | `male_base_v2.py --foundation` → `male_base.foundation.blend` + `male_base.foundation.record.json`; `--verify-foundation` rebuilds and compares |
| `resolution` | The switches every configuration applies after `variation.resolve`: the anime head study, the side-profile studies (silhouette, chest, lean glute), the limb girth study, the region fix, the rig fit and its weight smoothing, the chest smoothing | `foundation.apply` (one call; the builder never reads a probe or a character for them) |
| `reference` | 1.80 m, 1.0 frame, 1.0 muscularity, 80 kg: the Olympic-weightlifter calibration point | `foundation.problems` refuses a reference that does not resolve to 80 kg |
| `default_identity` | A neutral palette (skin as a shared swatch) and the default face marks: the approved eyes and brows | the same face checks as any identity |
| lock | Every default body's resolved fingerprint and the fingerprint of each of its 16 meshes (body, head, eye white, iris, mask, lines, brows, dead-eye X), for the 15-character sweep (1.60–2.00 m × lean / reference / strongman) | `male_base_v2_variation.py --set sweep --lock` writes `male_base.foundation.lock.json`; `--verify-lock` rebuilds and compares |
| regions | The garment fitting regions on the foundation body's topology (the head region is the head object) | `fitting_regions.py -- --foundation` → `male_base.foundation.regions.json`, keyed to the record's body fingerprint |

The default sets (`--set sweep`, `matrix`, `configurations`) build bare default bodies with the default face: no hair, no attire, nothing read from a character's manifest. A study that needs a candidate foundation names a review copy through `RIPOSTE_FOUNDATION_REVIEW`; a review copy never writes the lock. A review copy that changes the base (a mask study) names its own `source` and `record` in an iteration folder, so `--foundation` builds the candidate base there and never touches the approved one.

**Optional switches and the ears.** A switch a later revision introduces (`foundation.OPTIONAL_RESOLUTION_KEYS`) is off when the document does not name it, so an approved foundation that predates it keeps its document and lock. `ears` is the first: the foundation's ear component (`character_modeling.ear` designs the outline and relief — helix rim, Y antihelix, shallow concha, tragus, rimless lobule; `ear_component.py` builds both sides on each resolved head, the top at brow height and the bottom at the nose base, the root just ahead of the head's mid-depth and sunk into the skull along its curvature, rigid on Head). Ears are anatomy and belong to the foundation; earrings, piercings and ear armour are identity or attire.

**Three-physique head design (`head_design`).** The default face is not one face scaled: head studies are anchored at the lean, reference and strongman builds (`foundation` resolution `head_design`, `{anchor: {study: value}}`) and placed on the build coordinate (`variation.design_coordinate`: normalized frame and muscularity averaged, -1 / 0 / +1), piecewise linear between the anchors with no overshoot, added to the shared `head_study`. Height never enters the coordinate, so every height carries every build; height keeps its allometry (`head_proportions`), and the approved per-configuration physique profiles (jaw, cheeks, neck transition along `mass`) still apply on top. The anchors are art direction, not identities: lean after Spike Spiegel (narrower, longer, lean planar cheeks, a narrow angular jaw), reference after Goku and Vegeta (balanced, athletic, a clearly angular medium jaw), strongman after All Might (broad jaw and cheekbone architecture, a thick neck into the traps, never facial fat). A character's own identity parameters still move on top of its build's default. Combat never reads the head: the physical outputs (`physique.resolve_physique`: mass, strength, traction, turn support, hurt / push / grip radii) derive from height, frame and muscularity alone and are written to the character's physique JSON for the simulation.

**The under-jaw.** The chin is the underside's lowest point; behind it the submental line rises to the cervicomental junction where the neck enters, and the jaw's side edge turns up behind the mandibular corner toward the ear (`submental_profile`, `ramus_recess`). The face mask's lower panels reach under the chin to about a fifth of the head's depth, so a lift there must start behind the chin pad; the face-surface sampler extends a chart row that meets no surface (below a raised chin) from the nearest row that does.

**The lower face's contour (HEAD-CONTOUR-001).** The face mask is planar panels refined three times per edge, so below the mouth its edges are about 11 mm long, and in profile the chin was two planes meeting at one vertex (a 30-40 degree corner in one 2 mm step), the jaw border a chain of panel corners, the mask's boundary under the jaw a corner against the skull. The mask study `lower_contour` (`face_mask.LOWER_CONTOUR`) treats that at its source in `build_face`: the chin's and the border's panel edges round as the bridge does (`LOWER_SOFT_EDGES`, the under-jaw boundary corners `chin_low` / `jaw_low` with them); the seam blend under the jaw is widened; then the mask's own faces below the mouth are split smoothly (new vertices on a curve through the existing ones, none of which moves, never across the seam, where the face's and the skull's normals disagree and a split ripples the jaw's lower edge) and shade smooth. Control vertices carry their identity (`riposte_control`, a per-vertex tag), because a rounded control moves off its chart position. Behind the mask the head's lower half is the construction head's own 2-4 cm triangles, and the visible jaw-to-neck line is where that underside crosses the neck (two meshes, an occlusion boundary, not one surface), so with the study the skull's own faces below mid-ear and in front of the nape, and the seam's zip along the jaw's lower edge, are split flat and Taubin-smoothed (`_underside`: facet corners go, volume stays, at most 1 mm inward, fading over 25 mm to nothing where the region meets the rest of the skull, never put back on the coarse construction surface; the face's own faces are not in it). Below the mouth the mask's panels carry no convex swell (the rounding and the split give the curvature; a swell per panel stacked bulges into a lumpy jaw). A curved split there was rejected: it follows the coarse vertex normals and bulges. A rim at the ear lobe was rejected: it creased against the coarse facets above, in view. The nape is excluded: smoothing it moved the hanging hair into the body. Measuring is `tools/blender/inspect/lower_contour.py` (the midline section and the mandibular border, the point on each coronal section where the shading normal turns halfway from out to down) analysed by `character_modeling.contour`: equal-arc-length resampling, so the measure ignores tessellation; a kink is one 2 mm step turning far more than its neighbours, a reversal a ripple, and curvature itself is never penalised. A designed turn spreads over steps; a facet corner does not.

**Neck seating (`seat_neck`).** With the foundation switch on, every resolved body's neck is seated inside its head where it would come through the jaw's sides or the face (`male_base_v2.seat_neck`: a local narrowing toward the neck's own axis, eased over the mesh; nothing moves where nothing crosses). The tall lean body's neck stands wider than its head's lower sides (the head grows more slowly than the body), so at 2.00 m lean it crossed the jaw's side; the head is never moved to make room.

**Ears on a designed head.** With `head_design` the ear's flare and size follow the build (`ear.DESIGN_FLARE_DEG`, `ear.DESIGN_SCALE`: the lean ear smaller, its root anchored on the skull, its flare kept high enough that the smaller rim never touches the skull), every build flatter than the undesigned 16 degrees; reference and strongman keep the approved ear's size. Without a design the ear keeps its flare and size, so earlier candidates rebuild exactly.

**Measuring a head.** The head is judged by relationships, never by adding planes: cranium width to height, the widest band's height, jaw to cheek width, the split above and below the eye line, and the profile's forward points (forehead, brow, nose, upper lip, chin), across the height and build sweep. The locked eyes and brows are checked by their own shape (position and rotation removed) against the approved head: a head change may move them on the surface, never bend them.

**Layering a character.** A character is the foundation plus four kinds of layer, kept apart:

1. **Physical configuration** — the character's `foundation.body` (height, frame, muscularity, development), resolved by `variation` and `physique` into the body and head the foundation builds. Wolf's is the reference itself (1.80 m, 80 kg).
2. **Identity** — the face (`foundation.face`: `default`, the foundation's marks, or `identity`, the character's own `identity.face.marks`), the head identity (`identity.head`: archetype and parameters, `head_profile`), and the palette. Fitted to the resolved head, never the base head.
3. **Hair** — a `riposte.garment` of `type: "hair"` per outfit, built on the resolved head's construction surface (`wolf_hair.build_style`), declaring its design regions and its surface relationships (attach, clearance, drape).
4. **Attire** — `riposte.garment` definitions of `type: "garment"`: category (`fitted`, `structured`, `loose`), layer (1 underlayer … 4 accessories), the foundation fitting regions it occupies, deformation (`skinned` ≤ 4 influences or `rigid` on one bone), physique support, coverage (`coverage.hides`: regions whose body faces the export copy may remove, with `margin_rings`), clearance, upper boundary at the neck, materials from the character's costume slots, `requires` / `incompatible_with`. A garment for the foundation names `base_id: character.male_base.foundation` and the record's body fingerprint; `garments.problems(garment, foundation.garment_target(document, record, character), regions)` decides compatibility and refuses one fitted to another base.

Nothing a layer adds changes the foundation's meshes: Wolf built on the foundation (`--set wolf`, one row per outfit) has a body and face fingerprint-identical to the default reference. Wolf's `wolf.assembly.json` keeps its v1 `base` block for the shipping blockout export until Wolf exports from the foundation; his `foundation` block is what the authoring tools build from.

**Deformation weights.** The foundation body's skin weights come from v1 by the nearest point of v1's posed surface. v1's facets are about 40 mm wide and the sculpt's edges about 3 mm, so neighbouring vertices could take unrelated weight sets and tear in a bend (the worst 0.1 % of edges stretched 6–13× in guard, attack and overhead poses). The rig fit deforms with those weights averaged over the sculpt's edges 250 times, pruned to four influences and normalized (guard 1.65×, attack 1.79×, lunge 1.88×, overhead reach 2.11× at the 99.9th percentile); shape fields keep the transferred weights, so no shape changes. The remaining concentrations, the shoulder and chest under a high arm and a few collapsing edges in the groin fold at deep hip flexion, are topology and corrective-shape work (CHARACTER-TOPOLOGY-001), not more smoothing (500 passes bled the arm into the chest).

## Who owns the character (CHARACTER-SOURCE-001)

| Responsibility                                                      | Owner                                                                                                                              |
| ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Anatomy, silhouette, topology, skin weights, art direction          | The male base master in Blender, `art-src/blender/characters/male_base.blend`                                                      |
| The face, the approved proportions (reference)                      | Model A, `art-src/blender/characters/reference/model_a.blend` and its manifest — preserved, never overwritten                      |
| Joints, hierarchy, the one rest                                     | WolfRig, `wolf.rig-contract.json`                                                                                                  |
| Dimensions, body types, customization                               | The profile (`male_base.json`), `physique.py`                                                                                      |
| Animation, IK, grips, combat presentation                           | Godot                                                                                                                              |
| Art approval: deformation, attachments, pose and silhouette studies | Blender (MCP): the pose suite, the production clips, captures, a person                                                            |
| Integration acceptance of the exact export                          | `validate_candidate`, then Godot: PRES-PRODUCTION and PRES-MALE-BASE-* on every exported configuration with the real animation kit |

Model A is the approved study generator's output, extracted from the study scene and moved onto the origin, nothing else; its manifest pins the study's hash and lists how it differs from WolfRig (crown 1.785 m against the rig's 1.80 m, the A-pose against the rig's combat-stance rest, remesh topology with no weights). Model A is not production-ready and is not heroic: its torso is a box (the waist as wide as the chest), so the master takes its face and its joints, not its massing.

**The master.** `tools/blender/bootstrap/bootstrap_male_base.py` created it once, like every bootstrap under `tools/blender/bootstrap/`; from then on the blend is edited in Blender and the export reads it. The bootstrap is not a body generator. It started from WolfRig, its combat clips and the frozen v1 candidate's joint-looped topology and region weights (proven in Godot, carried over as candidates); it put Model A's head on the Head bone (planar decimation keeps the two panels, the ridge and the nose as planes; lifted 15 mm to WolfRig's 1.80 m crown; the neck's top ring runs up into the skull); and it made the heroic pass — mass redistributed around unchanged joints: the waist narrows (0.355 → 0.307 m wide, 0.265 → 0.215 m deep), the barrel chest loses depth (0.305 → 0.252 m) while the chest and shoulders keep their breadth, the pelvis keeps its depth so the thigh tops still meet it, and the limbs taper (upper arm, forearm, thigh, calf about 10-25 % slimmer, most at elbow, wrist, knee and ankle). Bone lengths, reach, hit volumes and the crown do not move. The A-pose (Model A's arms, legs plumb) is stored on the armature as `riposte_authoring_pose`, the inspection pose; the rest and the bind stay WolfRig's.

**The muscularity pass: an Olympic weightlifter by default.** The first pass went too slim (chest 0.41 × 0.252 m, waist 0.307 m — corseted). `tools/blender/authoring/male_base_muscularity_pass.py` edited the master once (the pass id is recorded on the armature; a second run refuses), with the region fields in `tools/blender/authoring/body_fields.py`. Topology, weights, joints, bone lengths and the rest are unchanged. Result: chest 0.453 m wide and 0.306 m deep (depth about 0.7 of width, a lifter's ribcage), waist 0.341 m (defined, not pinched), the obliques and lats filling under the mantle, the upper back deeper, the trapezius raised, the upper arm's belly about 6 % fuller; the pelvis untouched. The fields are anatomy, not uniform scaling: the torso scales width, front depth and back depth separately by height; the pectorals and the trapezius are their own masses; the trapezius fades out across the front of the chest (raising it there lifts the clavicle line the arm rises against); arm girth sits in the biceps and triceps bellies (the deltoid is the shoulder's); the clavicle's field fades past the shoulder joint (scaling there about the joint inflates an isolated sphere — it folded the girdle at the heaviest configuration).

**Configuration.** The physique is parameters on the one topology, not separate models: `art-src/blender/characters/male_base.configuration.json` names `mass` (lean muscular ← weightlifter → bodybuilder), `definition` (softer ↔ very defined — leanness is not mass), `upper_body`, `chest`, `shoulders`, `waist`, `arms` and `legs`, each in [-1, 1] with a `_minus` and a `_plus` shape key on the master; 0 is the authored default, the middle of the range. Named configurations (`default`, `lean`, `lean_half`, `heavy_half`, `heavy`, `extreme_lean`, `extreme_heavy` with every slider at its end) export as separate GLBs: the export mixes the keys into the rest mesh in memory and removes them, `validate_candidate` refuses a mesh that still carries keys, and the manifest records the configuration and its hash. Each exported configuration runs every PRES-PRODUCTION case (`PRES-MALE-BASE-*`). A profile's body weight will drive `mass` in Phase 6; physics already reads the profile, so the mapping is presentation only.

**Garments.** Clothing must stay valid inside the base's deformation envelope — every clip, transition and supported configuration — not merely fit the default at rest. Five conformities are validated separately: anatomical (shape and landmarks), topological (geometry where it deforms), skeletal (the right weights), dynamic (attached through real clips) and parametric (every supported configuration). A garment is a first-class asset with its own definition (`art-src/blender/garments/<id>.garment.json`): category (`fitted`, `structured`, `loose`), the base's fitting regions it occupies (`male_base.regions.json`, keyed to the base fingerprint — regions are modeling and validation areas, not bones), semantic layer (0 anatomy, 1 underlayer, 2 outer, 3 protection, 4 accessories) and what it is compatible with, deformation (`skinned` on WolfRig with at most four influences, or `rigid` on one bone), supported configurations, body coverage, per-region clearance, material slots, and the validation suites it must pass. A character manifest composes garments by id and refuses a garment whose base fingerprint, rig version, configuration or layer does not match. Weights start from the base by surface correspondence and are refined by hand; physique support starts from the base's key deltas and is corrected where the garment's construction differs; body and garments bake with the same configuration; covered body faces are removed only in the export copy. Blender MCP creates garments ([docs/reference/blender-mcp-hair-clothing-production.md](../reference/blender-mcp-hair-clothing-production.md)); the tooling — `garment_audit.py` and the reusable PRES-GARMENT-FIT, -SKINNING, -PHYSIQUE, -LAYERING and -IMPORT suites, parameterized by garment definition — decides whether one is valid. Tests measure anatomy and deformation through landmarks and regions, never fixed vertex indices or a one-dominant-bone assumption.

**Inspection.** `tools/blender/inspect/render_views.py` renders a master from fixed orthographic views (front, three-quarter, side, rear, top, bottom, `low` from below the face; `gameplay` is the match camera and `gameplay_head` the same camera cropped to `--target`; `--head` for the face; `--pose apose|rest`; `--keys` for a configuration; `--flat` a flat silhouette; `--beside <baseline prefix>` writes each view beside the baseline's), so two passes compare like for like. `tools/blender/inspect/base_record.py` measures every configuration into one body record: torso sections and limb girths in the rest, and tape-measure girths in the A-pose against the archetype targets (`character_modeling.body_record`). In Godot, `game/tools/capture_production.gd --candidate=<glb>` captures every pose from every side. Neither replaces the gates; they are the evidence a person reads beside them.

**The rest, the bind, the import.** One rest: WolfRig's combat-stance rest is the Blender armature rest, the bind, and the rest Godot imports (PRES-PRODUCTION checks the import against the contract). The A-pose is applied as a pose for inspection and configuration, never applied as a rest.

**v1, frozen.** `production.py` and `build_wolf_production.py` still build `wolf_production.blend` → `wolf_production.glb`, and PRES-PRODUCTION still gates it, as a regression reference. It is not the character: it was built from Model A's numbers, not its surface, and drifted from Model A's silhouette and face while matching its measurements. No new anatomy is authored there.

**Corrections stay in their layer.** A topology defect is fixed in the master's topology, a weight defect in its weights, a bone-orientation defect in the rig, wrong proportions in the master's shape, an animation defect in the clip or presentation, an import defect in the export/import configuration. A weight fix never moves a joint or a dimension. A smoothing pass is not a fix: relaxing a junction band blindly (volume-preserving Laplacian on the hip band) threw spikes through the crotch and was rejected; the hip-front shelf it was meant for is a topology item for the junction work.

## Head identity and morphology

The head is a parameterized anatomical component, not one fixed object attached to every body (HEAD-IDENTITY-001, HEAD-MORPH-001). Two dimensions never conflate:

| Dimension                    | What it varies                                                                                                                                                                  | Who sets it                                                                                    |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Morphology from the physique | Jaw and chin width, cheek fullness, cheekbone prominence, neck and jaw-to-neck transition; restrained skull width and depth                                                     | The named configuration resolves one deterministic head profile                                |
| Identity                     | Cranial width, depth and height, face length, cheekbone width and depth, jaw width, chin projection, brow strength and curvature, eye spacing, nose projection, neck transition | The character (bounded parameters, or an archetype preset: angular, broad, elongated, compact) |

A physique never sets an identity-only parameter, and nothing scales the head uniformly: a heavy fighter does not get an enormous head, a lean one not a tiny one. Body mass does not determine skull size; physique works through soft tissue and silhouette. What never changes: the eye line relative to the cranium, the nose centreline and peak, the forehead-to-face relationship, the panel construction, the eye and brow language. The test that matters: two characters with the same body, hair and clothing read as different people. `character_modeling.head_profile` holds the parameters, archetypes and the physique-to-head mapping and enforces the separation.

**The face** (FACE-PLANAR-001, FACE-SILHOUETTE-001, FACE-IDENTITY-001; approved 2026-10-31) is the heroic paneled mask as the whole face, built as its own topology by `male_base_v2.py` (f2, `build_face`) on the construction surface — v1's head island with only its face triangles subdivided (f0, no shape change), so the head keeps v1's shape — from `character_modeling.face_mask`: named control vertices in the head's chart (u, v, lift, follow), a designed boundary (frontal hairline, temples, side planes, jaw, under the chin) and the panels between them. Each control vertex is a mesh vertex placed on the construction surface plus its lift; each panel is refined into a few triangles that lie on the plane of its corners (`follow` 0: the brow, shelf, eyes, bridge, nose, cheekbones, mouth and chin are planar geometry) or bend with the skull (`follow` 1: the outer ring), with a small convex swell. Below the cheekbones the face is the lower mask: broad planar panels through the original panel mask's surface, a few millimetres proud of it (the field projects), and the cheekbone, raised out of the recessed eye, is the turn between the detailed upper face and that simpler mask. What makes the original read as a mask is one continuous turn around the face (measured 13–19° at u ≈ 0.4–0.55 on every row), so `face_mask.RING` designs it: a chain of vertices from the forehead down the temples, outside the brow and cheekbones, to the jaw and chin. Inside it the field is planar; outside it a perimeter band follows the skull to the boundary, where it eases in. The skull's front sheet inside the boundary is removed and the face is zipped to what remains; the seam is refined onto the construction surface (no chord cuts inside the skull's curvature) and relaxed across a narrow band, so the face eases into the temples and the jaw with no perimeter. Panels swell slightly (`face_mask.SWELL`), their turns shade as edges only above `FACE_EDGE_DEG` (softened, never razor-sharp), and the skull and seam triangles near the boundary are re-triangulated for even angles (`BEAUTIFY_M`, edge rotation only). The result is one closed surface, and the build is deterministic (same fingerprint on every run). The construction surface stays on the head (`riposte_f0_co`): hair and attachments frame on it, never on the face.

**Identity marks sit on the face's own features** (FACE-IDENTITY-001). A character's marks (`identity.face.marks`) give their spacing across the face (`x`, a fraction of the half-width) and name an anchor on the mask, never a height: `face_mask.ANCHORS` defines `eye_recess` (midway between the shelf's lower edge and the eye panel's lower edge, inside the recessed hooded-eye panel) and `brow_ridge` (the ridge's crest, from the bridge's top corner along the brow). `face_mask.resolve_marks` reads the height and the tilt off those lines at the mark (its own `tilt_deg` / `tilt_by_side` are offsets from the anchor's chord, so a deliberate asymmetry survives). Attachment and visible shape are separate. A brow (a mark with a `profile`) is attached by its bottom contour: at each of `face_mask.COLUMNS` columns across its width the bottom sits on the ridge line (plus its own `lift`; never an expression), settled `settle_m` down the surface from it (arc length along the head, `face_features._settle`, never a world height; Wolf's 2 mm seats the edge where the ridge's shadow begins, so no light band shows between brow and ridge), and its top contour is the profile's thickness above it, turned by the side's tilt (the approved asymmetry lives there) — Wolf's is a natural brow: a full head at the bridge, rising to an arch about three-fifths out, a tapered tail. The ridge line is measured on the head (`face_features.ridge_lines`): from each point of the crest the surface is walked to where its smooth-shaded normal turns from facing up to facing down (`HORIZON_Z`), the ridge's most forward point in profile — the line the eye reads as the ridge on a softened ridge, about 2 mm below the crest at the inner brow and 7 mm at the outer on Wolf; at the bridge's edge, where the surface never turns, it is the crest. The crest is on the head's own vertices: the ridge's control vertices are lifted off the construction surface when the face is built (about 2 mm above the chart line), so `male_base_v2.face_controls` finds them as the head's vertices and `face_features.place_marks` starts every column on the crest, walks the surface up from the ridge line by the column's thickness, and stands the volume `proud_m` off the surface and `depth_m` into it with a bevelled top; the lower face runs straight forward from the crest, so from the front the brow's bottom is the ridge line. A brow with `"inner": "ridge_start"` (Wolf's) begins where the ridge meets the nose, at the bridge's top corner, and its columns include every bend of the ridge (`face_mask.column_us`), so its inner bottom edge follows the ridge down to the nose on any head. **Soft edges**: the bridge's sides and top and the brow ridge are rounded and shaded smooth (`face_mask.SOFT_EDGES`, `SOFTEN`, `soften`), still noticeable and semi-angular, as the nose tip is; the face's boundary never moves. An eye's outline is seated in its flat recess. The landmarks the audits measure (`face_mapping.derive_landmarks`, `head_fit_surface`) resolve the same anchors. A brow stays off the bridge and above the eye.

**The anime eye** (FACE-EYE-001) is a drawing built from flat layers by the shared face-feature builder (`tools/blender/authoring/face_features.py`) from the pure design in `character_modeling.eye_assembly`: per side the eye white (`Eye`, the aperture), the iris with its darker rim, pupil and one highlight (`EyeIris`), clipped to the aperture like a 2D clipping mask, and the lines (`EyeLine`: the bold upper lash line with a pointed outer wing and inner tip, and a short accent under the outer corner). There are no eyelids or eyeballs: expression moves the drawing's edges and the iris, and a blink closes the upper edge onto the lower with the white and iris squashed to the closed line. An identity's `Eye` mark is its eye profile: the `upper` and `lower` edges (x -0.5 inner corner to 0.5 outer, y in eye heights), the `iris` (centre, width, height, rim, pupil, pupil_aspect, catchlight), the `line` (thickness along the eye, overlap, wing, inner tip, lower accent) and the layer `depth`s. Every point is seated on the resolved head under it. A masked eye (`occlusion: mask`) may set `white: backing`: the white no longer moves with the aperture but is one fixed sheet over everything the aperture can open to, and the skin mask over it shapes what shows. Shape keys blend linearly, so a moving white crosses the recessed eye panel in straight chords between its keys; mid-blink it stood up to 1.25 mm off the panel, in front of the iris and the mask. The fixed white has no keys and more rows (`BACKING_ROWS`) so its faces follow the panel; it sits deeper than the iris's own mid-gaze dip. A face's material slots are stored as a face attribute and applied once the slots exist (`character_assembly.dress_face`).

**Expressions** (FACE-EXPRESSION-001) are presets of shared channels (brow, upper lid, lower lid, gaze, blink), each a relative shape key on its component. `expressions.PRESETS` gives neutral, aggressive, alert and dead per-side weights and a default gaze; `expressions.weights(name, side, gaze, blink)` is what the builder checks, the review renders set (`render_views --face PRESET[,gaze_h,gaze_v[,blink]]`) and `FacePresentation` mirrors. `character_assembly.face_checks` re-checks every preset at 0.5 and 1, every gaze extreme and the blink on the built meshes. Dead is the X in place of the eye assembly.

**The head-neck fit** is measured on every configuration (`male_base_v2_variation`, `neck_through_head_vertices`) by `male_base_v2.head_face_classes`: the seam is the underside, the nape and the jaw's lower edge row (faces touching the underside); everything else crossed is a defect, and so is covering the edge row by more than `JAW_EDGE_COVER_M` (5 mm, just above the most the approved configurations need). On the approved head every crossing the default and lean configurations make (3 to 17, 36–45 mm above the chin, just in front of the jaw angle) is the neck covering the jaw's edge row by 2.9–4.5 mm: that cover is what keeps the junction clean, since the row is coarse and showing it reads as a jagged edge; heavy configurations make none. `male_base_v2.seat_neck` (`--seat-neck`) remains a diagnostic: pulling the neck inside the edge row exposes it.

**Skin is a shared swatch.** An identity's skin names one of the shared skin swatches (`skin_swatches` in the file the character manifest's `skin_swatches` names, the same ten the crowd draws from; `character_modeling.identity.palette_srgb`), never its own colour; the assembly, the character candidate and the variation tooling all take the identity's materials from `character_assembly.identity_materials`.

**The character candidate** (`tools/blender/character_assembly.py -- --candidate <iteration folder>/<name>.blend`). A character on the approved base for review: the identity's face marks and each outfit's hairstyle (resolved from its hair definition's object) fitted to `HeadV2` through the shared builders (`face_features.place_marks`, `wolf_hair.head_frame_of` / `build_style`) in the authoring A-pose and measured (hair inside the head or body, hair over the face), the base bound to WolfRig (`bind`), and every attachment returned to the rest by the Head bone's own skinning and bound rigid on Head. Hanging-hair weights are topology-dependent and are rebuilt after topology finalization. Outputs go to one iteration folder (ART-ITERATION-001); no source is written.

**Fitting through landmarks** (HEAD-FIT-001). `character_modeling.head_fit` defines `HeadFitSurface`: semantic landmarks queried from the surface, never vertex indices, and the face checks measured on them (symmetry, the nose as the forward-most point, the cheekbones as the widest forward-facing landmarks, orbital depth, eyelid-to-brow separation, brow projection). Hair is projected onto the selected head and keeps its design; garments fit the head-to-neck and neck-to-shoulder interfaces. The head has its own topology fingerprint beside the body's.

## The approved base v2 (2026-10-31)

Approved by the person on 2026-10-31. `tools/blender/authoring/male_base_v2.py` builds it deterministically from the frozen v1 master and saves `male_base.v2.blend` (`Armature`, `Body` = v1 as the weight and key reference, `BodyV2`, `HeadV2`):

- **BodyV2.** v1's body in the A-pose without its head island, closed and voxel-remeshed (b0), the large anatomical forms (b1), then the heroic proportions as broad fields (w1, `HERO`: shoulder girdle, ribcage, arms, thighs, calves, neck, trapezius, upper back, lats, glutes). The b1 surface is stored on the object.
- **HeadV2.** The approved head: the face above, built on v1's head shape (its construction surface); the construction head itself is not kept.

`male_base.v2.record.json` holds each object's fingerprint; `--verify` rebuilds in memory and compares the rebuild, the record and the saved file. `--bind <blend>` maps the form into WolfRig: v1's weights carried over as the starting point (at most four influences, below 0.01 pruned, normalized), every vertex returned from the A-pose to the rig's rest by the inverse of its own blended skinning matrix, the 16 configuration keys carried and smoothed; posed back in the A-pose the bound body is the approved form again (the round trip is measured). The bound body is a working candidate for the deformation gates; the form is a design sculpt, and production topology (joint loops, ART-PRODUCTION-001) is the next geometry step. Model A (`art-src/blender/characters/reference/model_a.blend`) stays the preserved output of the earlier study generator.

## Variation: body inputs, configurations, head (CHARACTER-VARIATION-001)

`character_modeling.variation` resolves a definition (body inputs, development, head identity) into what the builder applies, on top of `physique.py` and `head_profile` (it never changes their outputs): muscularity drives `mass`; frame drives `upper_body` and a share of `waist`; the seven named configurations are exactly body inputs plus development (each round-trips). Height scales the whole figure; the head grows allometrically (`height ** 0.5`, a broader frame a larger skull, never muscle), so its scale relative to the body stays within `RELATIVE_HEAD_BOUNDS`. Physique reaches the head through the configuration's head profile (jaw, cheeks, neck), interpolated along `mass`; identity (archetype and parameters) never changes with the physique, and placement parameters (`eye_spacing`, `brow_curvature`) move the face marks. `HEAD_FIELDS` defines the head's deformation per parameter in the head's chart. `matrix_report` resolves the boundary matrix (every corner of height × frame × muscularity, the default, intermediates) and reports mass, BMI and head scale; the short-and-lean corner reads below the underweight BMI under the isometric mass law, a finding for the physics owner, not a clamp.

## Anatomy before identity (CHARACTER-MORPHOLOGY-001, CHARACTER-PHYSIQUE-ART-001)

The head is resolved from the same body inputs as the body, then every identity feature is fitted to that resolved head. Height sizes the head (`h ** 0.5`: measured adult head circumference grows about `h ** 0.3`, so the heroic head is deliberately a little more responsive) and never reshapes it; frame is skeletal breadth; muscularity reaches the head as soft tissue and neck through the base's physique head profiles. Mass is a resolved check, never a morphology input. The resolved head is re-measured (landmarks, ridge line, surfaces) before the eye assembly, brows and hair are fitted.

The envelope is covered by three sets of `male_base_v2_variation.py`: `matrix` (all eight corners of height × frame × muscularity plus intermediates), `sweep` (every height 1.60–2.00 m with the lean, reference and strongman archetypes) and `configurations` (the seven named ones); each result records `variation.fingerprint` of its resolved configuration. Boards (`--render --frame head|body --only <prefix>`) compare same height across builds and same build across heights with fixed cameras; every body is judged front, side, rear and three-quarter, as a black silhouette and in clay, then at the gameplay camera, against the physique rubric (heroic silhouette, anatomical volume, proportional coherence, style fidelity, gameplay readability).

## Face mapping and the attachment framework (FACE-MAPPING-001, CHARACTER-ATTACHMENT-001)

Facial components are fitted to the mask through semantic landmarks, not placed on Wolf. The face's chart is the one Wolf's marks already use: u is x over the head's half-width, v the height fraction above its lowest point, and the surface is the mask's forward-most point there. `tools/blender/inspect/face_surface.py` samples any head object on that chart; `character_modeling.face_mapping` holds the rest, pure and tested:

- `FaceSurface`: position, normal, horizontal and vertical tangents, curvature and projection at (u, v).
- `derive_landmarks`: the geometric landmarks measured on the surface (nose tip and root, chin, brow ridge apex, the cheekbone apex as the strongest vertical convexity on the forward-facing panel, the nose's lateral boundary) and the identity ones from the character's marks, each resolved on its mask anchor (eye centre, inner and outer corners; brow inner, apex and outer).
- `resolve` / `attachment_problems`: a component's attachment (landmark, region, tangent and normal offsets, orientation) resolved to a frame on this head; outside its region, buried in the mask, or an unmirrored pair is hard.

Because a frame is resolved per head, the same attachment follows a re-topologized head, a head profile or a physique: the tests resample one mask at two resolutions and get the same frame within 0.5 mm. Measured on the approved head and on every resolved head profile, every landmark resolves and Wolf's eyes and brows attach with no findings. Next on this framework: the mask owns the eye openings, and eyeballs, lids and tapered brow meshes become fitted components with blink and gaze tests. Hair (HEAD-FIT-001) and garments (`male_base.surfaces.json` interfaces) use the same philosophy — named surfaces and interfaces, the fingerprint only as a compatibility check.

## Generated, approved, production-ready (ART-PRODUCTION-001)

Everything authored here with LLM help or by script is generated/exploratory until a person approves its look; approval preserves it (versioned, hashed, with its approval and profiles recorded) as the artistic source. Production-ready is a separate state reached by a separate pipeline on a copy: geometry audit that knows the intended construction, retopology or controlled cleanup that keeps the articulation loops, deformation and attachment validation, UVs and consolidated materials, detail transfer only where justified (never the silhouette or the convex facial planes), measured optimization, reproducible export. The approved v2 form (`BodyV2`, `HeadV2`) is artistically approved but not production-ready: a dense voxel sculpt and a triangulated face, a design reference until production topology replaces it.

## Overhauling the base: baseline, candidate, record

A base revision never edits the master in place. The v1 master and everything built on it are frozen in `art-src/blender/characters/baseline/v1/` (`character_modeling.baseline_freeze`: byte copies, read-only, every file's sha256 in `baseline.json`; the tests re-hash them, so a baseline that changes fails). The candidate is `male_base.v2.blend`. `tools/blender/inspect/base_record.py` measures a master into a body record (`character_modeling.body_record`: topology, the head island, the rig rest, every key's deltas, the vertex groups, and per configuration torso sections, limb girths, bounds, area and volume); with `--compare` it writes the regression report and fails on a moved joint, a changed crown, or a lost key or configuration. What the sculpt is meant to change is reported as measured deltas for a person to judge.

The approved form (`tools/blender/authoring/male_base_v2.py`) is authored in the master's stored A-pose, where the body is symmetric and can be mirrored; the production mesh still binds at WolfRig's combat rest, recovered exactly by inverting each vertex's blended skinning matrix, so the rest and bind never change. Forms are named masses placed in the rig's frame.

**Blender MCP operating rule.** An MCP call is short and bounded: open, inspect, run one stage on a few thousand vertices, save. Per-vertex passes over a dense sculpt, audits, renders and exports run in a background Blender process (vectorized), so the live session never hangs; a long pure-Python loop inside one MCP request crashed the session once. Every stage saves the candidate, so a crash loses at most one stage.

## Head measurements

The shipping head stays until a gameplay capture accepts a replacement. Model A keeps that head unchanged. A study does not write `wolf.character.json` or the rig.

The head is two surfaces. The cranium is the volume: temples, crown, occiput, and the fit on the neck. The face is a shallow shell on the front of that volume: two flat cheek planes and the center edge where they meet. Flattening the shell must not shrink the skull. Rear depth is its own control.

Record these from the mesh, in metres, Z up and −Y forward:

- Height, width, and depth, and depth divided by width. A thin side profile is a low depth-to-width number. The study range for a fuller skull is about 0.24–0.27 m of depth on the current cheek width. That range is a test, not a shipped measurement.
- Temple width and crown width. A crown much narrower than the cheeks, with no rear skull, reads as a cap.
- Occipital depth: how far the back of the skull sits behind the neck.
- Cheek-plane angle, plane-fit error on the flat region only, and how far the center edge sits forward. The edge stays. An almost-flat shell is a smaller angle, not a deleted edge.
- Left/right asymmetry, connected components, boundary edges, and non-manifold edges.

The body profile from the last pass is the control: underarm half-width rises from the waist into the chest, shoulder span stays, and the head bone stays at 1.505 with its tail at 1.80. A head variant does not reopen those. A render is not an acceptance.

## Pose

The modeling pose is `relaxed-a-pose`.

- Up is +Z. Forward is −Y. Left is +X. The mirror plane is YZ. The floor is z = 0. The same frame as the Blender study.
- Feet flat and parallel. Knees straight. Legs apart by the rig's hip width, so the inner leg can be seen.
- Torso upright. Head faces forward, with no tilt.
- Arms drop 35° from horizontal, in the coronal plane. Elbows are straight. Both sides match.
- No weapon and no clothing in the proportion views.

35° is the middle of the usual 30–45° drop from a T-pose. A T-pose stays available as a rigging reference. It is not the pose used to compare silhouettes. The production rest pose stays the combat stance the clips were authored on.

Segment lengths used to place the preview come from Wolf's stations. The preview does not write them back.

## Shape

A profile is JSON (`riposte.character_model`, version 2). It holds three body inputs and the shape sliders. A version-1 profile (sliders only) migrates deterministically to Wolf's body inputs; any other version fails with a clear error (`definition.migrate`).

| Body input    | Unit   | Range     | Wolf | Moves only                                                                               |
| ------------- | ------ | --------- | ---- | ---------------------------------------------------------------------------------------- |
| `height_m`    | metres | 1.60–2.00 | 1.80 | mass, actuator scales, hurt and push radii, grip, hand, lying geometry, stamina capacity |
| `frame_build` | × Wolf | 0.85–1.15 | 1.0  | mass, hurt and push radii, lying girth (never strength or turn torque)                   |
| `muscularity` | × Wolf | 0.80–1.25 | 1.0  | mass, actuator scales, hurt radius, lying girth, stamina capacity (never the footprint)  |

`parameters.BODY_INPUTS` declares each input's `affects` list; the resolver tests hold every other output fixed. Body inputs do not drive the shape sliders: no hidden coupling until authored examples prove a mapping. Muscularity is a body input, not a regional control.

Each slider has a minimum, a default, and a maximum. The stored value is the thing it means — a width in head-widths, a ratio, a multiplier — not a vertex and not a bone coordinate. The same profile resolves to the same numbers every time.

Widths are multiples of the accepted cheek width, 0.263 m (`radius` 0.1125 × 1.17, both sides). Head width 1 is that head. Depth of the accepted head stays put unless a slider that owns depth says otherwise. `head_width` does not change depth.

| Slider                                            | Group | First panel | Range                                     | Default |
| ------------------------------------------------- | ----- | ----------- | ----------------------------------------- | ------- |
| Shoulder breadth                                  | Torso | yes         | 1.80–3.20 head widths, deltoid to deltoid | 3.00    |
| Chest mass                                        | Torso | yes         | 1.50–2.10                                 | 1.52    |
| Chest depth                                       | Torso | yes         | 0.50–0.75 of the front width              | 0.75    |
| Waist taper                                       | Torso | yes         | 0.72–0.94 of chest width                  | 0.88    |
| Hip breadth                                       | Torso | yes         | 1.10–2.05                                 | 1.34    |
| Thigh mass                                        | Limbs | yes         | 0.40–0.86                                 | 0.78    |
| Head width                                        | Head  | yes         | 0.90–1.15 × accepted                      | 1       |
| Crown fullness                                    | Head  | yes         | 0.94–1.12 × accepted crown                | 1       |
| Neck, arm, forearm, calf, hand, boot, cheek blend | —     | no          | bounded in `parameters.py`                | —       |

The first panel is those eight. The others are already named and checked, and stay off the panel until a preset needs them. Limb length, grip position, and floor height are not sliders. A thicker forearm does not slide the grip. A larger boot does not drop the sole through the floor.

`status` is `study` or `pending`. A file cannot mark itself `accepted`. That word waits for a person.

Current profiles:

| File                               | What it is                                                                                                                                                               |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `profiles/male_base.json`          | The male base: Model A at Wolf's body inputs. Pending a person's acceptance.                                                                                             |
| `profiles/male_base.manifest.json` | Its build manifest (`riposte.build_manifest`): profile hash, study lineage, generator and Blender versions, physical baseline, measurements, validation (`manifest.py`). |
| `profiles/study_wow_heroic.json`   | Model A as a study profile; the same body.                                                                                                                               |

## Baseline

The defaults are a height-normalized reading of one front-view human male, scaled so the figure is 1.80 m tall. WolfRig joints stay where they are. The shoulder slider is the outer deltoid span. It is wider than the 0.53 m shoulder-joint span, because the joint sits inside the muscle.

The reading, and where it is soft:

| Reading                          | Value used              | How it was taken                                                                |
| -------------------------------- | ----------------------- | ------------------------------------------------------------------------------- |
| Deltoid to deltoid               | 3.00 head widths        | Last full span before the arms leave the torso                                  |
| Chest                            | 1.52                    | Central span at the armpit                                                      |
| Waist / chest                    | 0.88                    | Even taper. The measured pinch was 0.78 and read as a sunk waist                |
| Pelvis                           | 1.34                    | The bottom of that taper, 0.88 of the chest                                     |
| Thigh, knee, calf, ankle         | 0.78, 0.56, 0.66, 0.48  | Each leg's span, legs nearly vertical                                           |
| Upper arm, elbow, forearm, wrist | 0.66, 0.50, 0.50, 0.36  | Horizontal span times the sine of the arm angle, about 44° below horizontal     |
| Chest depth                      | 0.75 of the front width | The side uses the same fraction at every station, so it follows the front taper |
| Neck                             | 0.56                    | Design choice. Hair and the beard cover the neck in the source                  |
| Hand and foot                    | 1.08 and 0.50           | Design choice. The source hand is open, and the ground shadow covers the feet   |

The accepted head is 0.263 m wide. In the source, the head is about 0.22 m at the same 1.80 m height, so this fighter's head stays larger relative to the body than the reference head. Shoulder breadth follows the body height.

Model A is that baseline, scaled to Wolf: 1.80 m and 80 kg, the 1.0 reference (`baseline.py` restates `PhysicalBaseline` and a test reads the GDScript back).

No female profile yet. The female base gets its own authored shoulder, chest, waist, hip, thigh, and head values on the same contracts, resolver, export and validation; it is not a uniform scale or a muscularity setting of the male.

There is no single `bulk` control. A control that only grows every radius at once is rejected as an unknown slider.

## The pipeline every caller uses

```text
load_profile(path)            -> resolved profile (style widths, head overrides, body inputs)
physique.resolve_physique(body) -> mass, actuator scales, radii, grip and lying geometry
physique.write_all()            -> game/content/characters/*.physique.json (committed)
production.build(resolved, rig) -> v1 (frozen): vertices, faces, region weights on WolfRig's rest pose
build_wolf_production.py        -> art-src/blender/fighters/wolf_production.blend (v1, frozen)
male_base.blend         -> the master, edited in Blender (bootstrapped once)
pnpm game:assets                -> wolf_production.glb, male_base.glb + manifests (validator kind `candidate`)
```

A Blender study, a creator panel, an exporter and the crowd builder all call these; none invents a shoulder width, a mass or a radius. Shape keys stay available for a sculpted chest or jaw on the production topology. Hair, armour and garments are separate meshes with a part id, attachment points, a supported body range and a clearance rule (outfits never redefine anatomy or physics).

## What this module will not do

- It will not move `WolfRig` to the A-pose or rename a bone.
- It will not replace the shipping blockout before a gameplay capture accepts the production body.
- It will not write a combat value into the simulation: the game reads the committed physique through `FighterCatalog.from_physique`.
- It will not let a measured mesh overwrite combat mass or radii; mesh measurements are diagnostics.
- It will not grow a second builder per use (Wolf, female base, crowd): profiles and quality budgets differ, the builder does not.

`python -c "import character_modeling; character_modeling.self_check()"` from `tools/character_modeling` checks the profiles and schema, the ranges, the migration, the mirror, the 35° arm, Wolf's baseline against `PhysicalBaseline`, the region-to-rig contract, the build manifest and physique drift. `pnpm lint` runs it; `pnpm test:character-modeling` runs the unit suites.

## Two mesh products

The study mesh and the production mesh are different things with different jobs.

- The **study mesh** explores shape. It is the fused lofts, an automatic remesh, smoothing, and subdivision. A clean, connected, symmetric A-pose study mesh is not evidence that the mesh is ready to deform. Remesh topology does not follow how a body bends.
- The **production mesh** deforms and exports. `production.py` builds one connected fixed-topology surface on WolfRig's rest pose: the same vertex count and faces for every profile, edge loops at the joints, a shoulder socket welded to a deltoid cap, and a pelvis opening welded to the legs. At the shoulder the cap's outer face and the first arm ring meet on the shoulder span; the shaft beyond stays on the humerus and the joint does not move. Behind, the posterior deltoid flows from the socket into the upper arm: each cap ring's back is its share of the way between them, so the arm does not jut out of the back and fall away (judged from the rear and rear three-quarter views, not only the front). At the hip the lowest pelvis rings reach behind the glute landmark, so the seat covers the rear thigh tops; the opening and the thigh share an outer face. The stance puts each thigh fore or aft of the centred opening, so the first two thigh rings take their share of depth from the opening's half to the thigh below: no ledge in front of the trailing thigh and no shelf under the glute behind the lead one (`pelvis_findings` reports a junction step larger than the slope just below it). The crease at the front of the lead hip is the stance's hip fold, not a seam. The rejected ring-loft (five closed tubes) stays as a negative fixture. Flesh is connected where flesh is continuous. `skinning.py` weights that surface from deformation regions. It reproduces the accepted proportions through the resolved profile; it never silently reinterprets them, and it never moves a rig joint to hide a bad socket.

The handoff is the production gate (see [assets.md](../reference/assets.md)). `PRES-PRODUCTION` imports the candidate GLB, checks it is WolfRig bone for bone, and skins it the way the GPU does at frames of Wolf's own clips, including the clavicle response before arm IK (PRES-CLAVICLE-001). The hip case bends each thigh through the combat range Wolf's clips reach (at most 30° from rest, the forward dash; 45° flexion is gated for margin) and rejects a pelvis weighted to the hips alone. Death reaches 70° and stays a capture review. A green Python suite does not prove that import. A green import does not prove the shoulder reads correctly. A person accepts the gameplay-camera captures. The nude body is not accepted yet.

## Diagnostics are evidence, not a verdict

The scanner (`tools/character_modeling`, pure Python, no Blender) reads a captured study mesh and reports geometric evidence. It never changes geometry and never decides the art. Its layers stay separate on purpose: a mesh can have smooth normals and a polygonal outline, or intended facets and a clean outline.

- **Integrity** — holes, non-manifold edges, degenerate faces, components, winding.
- **Symmetry** — mirrored-vertex distance, authored-symmetric only.
- **Cross-sections** — width, depth, area, and centre at landmark stations, against each region's expected profile (never a blanket "monotonic everywhere" rule).
- **Outline corners** — on the silhouette projected from the mesh through fixed views; rendered masks are only a cross-check, because render antialiasing and shadows invent corners.
- **Crease clusters** — dihedral edges past a region threshold, grouped, with resolution persistence.
- **Offset probe** — EXPERIMENTAL dents against a smoothed copy; a ranking signal that needs corroboration, never a lone failure.

Regions (`anatomy.py`) are a confidence-weighted explanation, not ground truth. A remesh destroys loft identity, so a vertex's region is derived from landmarks; a boundary vertex reports both sides ("deltoid / upper arm") rather than false precision. Regions never generate geometry or override the loft and profile definitions.

## Regional controls, honestly

Controls (`anatomy.py` `CONTROLS`) are defined by the surface change each may make and the constraints it protects. 1.0 is the accepted default of whichever aesthetic is loaded, so every control at 1.0 reproduces the control exactly. Ranges near 0.9–1.1 are experimental until calibrated. Global `muscularity` exists but stays disabled until the default aesthetic is picked, so global scaling cannot hide which regional control produced a result.

A control is only a true control once it has a measurable, isolated effect on the actual profile. Until a phase gives it that effect, a control that merely scales a broad muscle overlay is marked `provisional`, and its value is read as a rough knob, not a contract. Do not keep adding environment switches as the permanent interface: switches isolate short-lived experiments, and once a shape is accepted its parameters are consolidated into a named, versioned profile.

## Protected measurements and the acceptance gate

A blanket sub-millimetre tolerance on a remeshed surface is precise in the report without being accurate about the mesh. Every protected measurement (`measurements.py`) declares a class, where it is measured, its tolerance, the reason, and a status:

- **Source invariant** — authored or rig value; exact, or a small source tolerance.
- **Geometry invariant** — integrity; pass or fail.
- **Shape invariant** — a measurement that defines the approved design; tolerance matches the measurement's resolution (a face landmark on the fine skull loft can hold a millimetre; a shoulder span on the 5.5 mm remesh cannot claim better than roughly one remesh cell).
- **Anatomy target** — a range plus visual review, not an exact value.
- **Heuristic** — a scanner signal; a review flag until calibrated.

Only the hard classes (source, geometry, shape) can fail a candidate. Each phase declares which hard invariant it is allowed to change; every other stays fixed.

Acceptance is a four-part gate, not a single score:

1. **Integrity** — the required mesh checks pass.
2. **Regression** — no unexplained new high-severity hard finding against the frozen control; protected measurements within their justified tolerances.
3. **Visual review** — the changed region reads right in the fixed views, the gameplay camera, and more than one lighting angle.
4. **Scope** — unchanged regions and the control reproduce as expected.

A phase meant to remove an existing defect must also improve that defect: the back phase cannot pass merely by adding no new findings; the back must acquire the intended relief and taper. A better score can still look worse — the scanner finds and verifies, the human accepts.

Thresholds (`regions.py`) are each labelled `calibrated` (checked against known-good and known-bad captures), `provisional` (a defensible starting value), or `advisory` (evidence only). The control is a regression baseline, not an oracle: its existing findings are not a to-do list, and thresholds are never tuned just to make it green.

## Three scan loops

- **Fast iteration** — generator measurements, selected views, cheap section and outline checks, offset probe skipped. Catches obvious regressions while tuning.
- **Phase gate** — full A/B/C builds, the complete scan, the control diff, and the fixed-view sheet. Decides whether a change is ready to accept.
- **Release gate** — full scan at final resolution, reproduction check, rig and animation checks, GLB import, and game tests. Proves the accepted result is safe to integrate.

A partial scan is never quietly treated as a full pass.
