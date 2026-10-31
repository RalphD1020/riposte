# Character modeling

> See also: [character-art.md](./character-art.md) — the blockout that ships today, [docs/reference/assets.md](../reference/assets.md) — export and Godot import, [presentation.md](./presentation.md) — clip, combat pose, clavicle, then arm IK
> Source: `tools/character_modeling/`

One pipeline. Definition, physical resolution, construction and presentation stay apart. Construction itself splits into two mappings — anatomy says what the body is, deformation says how that body follows bones — and they share one WolfRig. They are not two skeletons.

| Concern             | What it owns                                                        | Home                                                                                                      |
| ------------------- | ------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Definition          | The saved, versioned inputs: body inputs, shape sliders, status     | `profiles/*.json` (`riposte.character_model` v2), `definition.py`, `parameters.py`                        |
| Physical resolution | Mass, actuator scales, hurt and push radii, grip and lying geometry | `physique.py` → `game/content/characters/*.physique.json` → `FighterCatalog.from_physique` (PHYSIQUE-001) |
| Construction        | Anatomy, landmarks, and fixed topology from the profile and the rig | `anatomy.py`, `production.py`, `tools/blender/bootstrap/build_wolf_production.py`                         |
| Deformation         | Candidate bones, normalized weights, the four-influence limit       | `skinning.py` offline. Godot `Skeleton3D` and `Skin` deform the import; there is no runtime mesher       |
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

**Two kinds of pose study, both required.** Artistic studies (A-pose and reference proportions, rest, guard and ready, heroic attack and defensive poses, strong asymmetry, weapon poses, every side and the gameplay camera) answer *does this character look right*: identity, head-to-body proportion, silhouette, weapon and hand readability. Technical studies (the preset-pose suite and the production clips with intermediate samples) answer *does it deform correctly*: shoulder and clavicle, elbows and wrists, torso and pelvis, hips, knees and ankles, grip, attachment intersections.

**The pose suite (POSE-SUITE-001).** Preset poses are versioned data in `character_modeling`, tied to the rig contract version, and applied in Blender: reference poses (the A-pose, the production rest), preset stress poses (guard, ready, and the existing shoulder release and diagnostic ranges and the hip range), and animation ranges (samples of the production clips, intermediate frames included). The same fixtures run on every physique and character; a fixture changes only as an intentional, documented change to the shared contract, never to let a model pass. Presets are regression fixtures; clips prove timing and transitions; neither replaces the other.

**The integration record (CHARACTER-INTEGRATION-001).** The export manifest written beside every GLB (`asset_id`, `source`, `source_sha256`, `configuration`, bones, animations, attachments, materials, triangles) is the handoff record. It also carries the rig contract's digest and rest signature, the definition and animation-kit versions, and the state of each gate (Blender art, Blender deformation, Godot integration) for that exact source hash; a result recorded against another hash does not count.

**The feedback loop.** An agent (or a person) works the same loop in either environment's findings: observe and baseline → run the presets (then the clips) → measure and capture → classify the finding and its owner (definition/resolver, anatomy, geometry/topology, skeleton mapping, weights, hair or face attachment, garment or equipment fit, material, export, animation contract, runtime IK or pose modifier) → propose the smallest bounded change in the owning layer → apply it through the shared builder → re-run the failed sample, its neighbours and the affected configurations → compare with the baseline → accept or reject → keep the evidence. Godot findings carry the export version, clip, frame, modifier and IK state, the bone or region, expected and observed values and a capture; an art or mapping finding is fixed in Blender and re-run in both environments; a runtime finding is reported to the animation kit, never hidden by distorting the character. An agent recommends technical acceptance; a person approves the look. Only what a change invalidates is re-run (a hairline does not rebuild the body; a rig contract change invalidates every mapping).

## The male base is no one character

`male_base.blend` is the default male body every male character is built from. Wolf is the first character on it, not its owner: a character is the base in a physique configuration plus its own face features (eyes, brows), attire, palette and identity. A character never forks the body, and a fix to the base reaches every character. The female base is a second master on the same schema, rig contract and gates. The skeleton keeps the name WolfRig: it is the canonical fighter skeleton, and its name is historical.

## Who owns the character (CHARACTER-SOURCE-001)

| Responsibility | Owner |
| --- | --- |
| Anatomy, silhouette, topology, skin weights, art direction | The male base master in Blender, `art-src/blender/characters/male_base.blend` |
| The face, the approved proportions (reference) | Model A, `art-src/blender/characters/reference/model_a.blend` and its manifest — preserved, never overwritten |
| Joints, hierarchy, the one rest | WolfRig, `wolf.rig-contract.json` |
| Dimensions, body types, customization | The profile (`male_base.json`), `physique.py` |
| Animation, IK, grips, combat presentation | Godot |
| Art approval: deformation, attachments, pose and silhouette studies | Blender (MCP): the pose suite, the production clips, captures, a person |
| Integration acceptance of the exact export | `validate_candidate`, then Godot: PRES-PRODUCTION and PRES-MALE-BASE-* on every exported configuration with the real animation kit |

Model A is the approved study generator's output, extracted from the study scene and moved onto the origin, nothing else; its manifest pins the study's hash and lists how it differs from WolfRig (crown 1.785 m against the rig's 1.80 m, the A-pose against the rig's combat-stance rest, remesh topology with no weights). Model A is not production-ready and is not heroic: its torso is a box (the waist as wide as the chest), so the master takes its face and its joints, not its massing.

**The master.** `tools/blender/bootstrap/bootstrap_male_base.py` created it once, like every bootstrap under `tools/blender/bootstrap/`; from then on the blend is edited in Blender and the export reads it. The bootstrap is not a body generator. It started from WolfRig, its combat clips and the frozen v1 candidate's joint-looped topology and region weights (proven in Godot, carried over as candidates); it put Model A's head on the Head bone (planar decimation keeps the two panels, the ridge and the nose as planes; lifted 15 mm to WolfRig's 1.80 m crown; the neck's top ring runs up into the skull); and it made the heroic pass — mass redistributed around unchanged joints: the waist narrows (0.355 → 0.307 m wide, 0.265 → 0.215 m deep), the barrel chest loses depth (0.305 → 0.252 m) while the chest and shoulders keep their breadth, the pelvis keeps its depth so the thigh tops still meet it, and the limbs taper (upper arm, forearm, thigh, calf about 10-25 % slimmer, most at elbow, wrist, knee and ankle). Bone lengths, reach, hit volumes and the crown do not move. The A-pose (Model A's arms, legs plumb) is stored on the armature as `riposte_authoring_pose`, the inspection pose; the rest and the bind stay WolfRig's.

**The muscularity pass: an Olympic weightlifter by default.** The first pass went too slim (chest 0.41 × 0.252 m, waist 0.307 m — corseted). `tools/blender/authoring/male_base_muscularity_pass.py` edited the master once (the pass id is recorded on the armature; a second run refuses), with the region fields in `tools/blender/authoring/body_fields.py`. Topology, weights, joints, bone lengths and the rest are unchanged. Result: chest 0.453 m wide and 0.306 m deep (depth about 0.7 of width, a lifter's ribcage), waist 0.341 m (defined, not pinched), the obliques and lats filling under the mantle, the upper back deeper, the trapezius raised, the upper arm's belly about 6 % fuller; the pelvis untouched. The fields are anatomy, not uniform scaling: the torso scales width, front depth and back depth separately by height; the pectorals and the trapezius are their own masses; the trapezius fades out across the front of the chest (raising it there lifts the clavicle line the arm rises against); arm girth sits in the biceps and triceps bellies (the deltoid is the shoulder's); the clavicle's field fades past the shoulder joint (scaling there about the joint inflates an isolated sphere — it folded the girdle at the heaviest configuration).

**Configuration.** The physique is parameters on the one topology, not separate models: `art-src/blender/characters/male_base.configuration.json` names `mass` (lean muscular ← weightlifter → bodybuilder), `definition` (softer ↔ very defined — leanness is not mass), `upper_body`, `chest`, `shoulders`, `waist`, `arms` and `legs`, each in [-1, 1] with a `_minus` and a `_plus` shape key on the master; 0 is the authored default, the middle of the range. Named configurations (`default`, `lean`, `lean_half`, `heavy_half`, `heavy`, `extreme_lean`, `extreme_heavy` with every slider at its end) export as separate GLBs: the export mixes the keys into the rest mesh in memory and removes them, `validate_candidate` refuses a mesh that still carries keys, and the manifest records the configuration and its hash. Each exported configuration runs every PRES-PRODUCTION case (`PRES-MALE-BASE-*`). A profile's body weight will drive `mass` in Phase 6; physics already reads the profile, so the mapping is presentation only.

**Garments.** Clothing must stay valid inside the base's deformation envelope — every clip, transition and supported configuration — not merely fit the default at rest. Five conformities are validated separately: anatomical (shape and landmarks), topological (geometry where it deforms), skeletal (the right weights), dynamic (attached through real clips) and parametric (every supported configuration). A garment is a first-class asset with its own definition (`art-src/blender/garments/<id>.garment.json`): category (`fitted`, `structured`, `loose`), the base's fitting regions it occupies (`male_base.regions.json`, keyed to the base fingerprint — regions are modeling and validation areas, not bones), semantic layer (0 anatomy, 1 underlayer, 2 outer, 3 protection, 4 accessories) and what it is compatible with, deformation (`skinned` on WolfRig with at most four influences, or `rigid` on one bone), supported configurations, body coverage, per-region clearance, material slots, and the validation suites it must pass. A character manifest composes garments by id and refuses a garment whose base fingerprint, rig version, configuration or layer does not match. Weights start from the base by surface correspondence and are refined by hand; physique support starts from the base's key deltas and is corrected where the garment's construction differs; body and garments bake with the same configuration; covered body faces are removed only in the export copy. Blender MCP creates garments ([docs/reference/blender-mcp-hair-clothing-production.md](../reference/blender-mcp-hair-clothing-production.md)); the tooling — `garment_audit.py` and the reusable PRES-GARMENT-FIT, -SKINNING, -PHYSIQUE, -LAYERING and -IMPORT suites, parameterized by garment definition — decides whether one is valid. Tests measure anatomy and deformation through landmarks and regions, never fixed vertex indices or a one-dominant-bone assumption.

**Inspection.** `tools/blender/inspect/render_views.py` renders a master from fixed orthographic views (front, three-quarter, side, rear; `--head` for the face; `--pose apose|rest`; `--keys` for a configuration), so two passes compare like for like. `tools/blender/inspect/base_record.py` measures every configuration into one body record: torso sections and limb girths in the rest, and tape-measure girths in the A-pose against the archetype targets (`character_modeling.body_record`). In Godot, `game/tools/capture_production.gd --candidate=<glb>` captures every pose from every side. Neither replaces the gates; they are the evidence a person reads beside them.

**The rest, the bind, the import.** One rest: WolfRig's combat-stance rest is the Blender armature rest, the bind, and the rest Godot imports (PRES-PRODUCTION checks the import against the contract). The A-pose is applied as a pose for inspection and configuration, never applied as a rest.

**v1, frozen.** `production.py` and `build_wolf_production.py` still build `wolf_production.blend` → `wolf_production.glb`, and PRES-PRODUCTION still gates it, as a regression reference. It is not the character: it was built from Model A's numbers, not its surface, and drifted from Model A's silhouette and face while matching its measurements. No new anatomy is authored there.

**Corrections stay in their layer.** A topology defect is fixed in the master's topology, a weight defect in its weights, a bone-orientation defect in the rig, wrong proportions in the master's shape, an animation defect in the clip or presentation, an import defect in the export/import configuration. A weight fix never moves a joint or a dimension. A smoothing pass is not a fix: relaxing a junction band blindly (volume-preserving Laplacian on the hip band) threw spikes through the crotch and was rejected; the hip-front shelf it was meant for is a topology item for the junction work.

## Head identity and morphology

The head is a parameterized anatomical component, not one fixed object attached to every body (HEAD-IDENTITY-001, HEAD-MORPH-001). Two dimensions never conflate:

| Dimension | What it varies | Who sets it |
| --- | --- | --- |
| Morphology from the physique | Jaw and chin width, cheek fullness, cheekbone prominence, neck and jaw-to-neck transition; restrained skull width and depth | The named configuration resolves one deterministic head profile |
| Identity | Cranial width, depth and height, face length, cheekbone width and depth, jaw width, chin projection, brow strength and curvature, eye spacing, nose projection, neck transition | The character (bounded parameters, or an archetype preset: angular, broad, elongated, compact) |

A physique never sets an identity-only parameter, and nothing scales the head uniformly: a heavy fighter does not get an enormous head, a lean one not a tiny one. Body mass does not determine skull size; physique works through soft tissue and silhouette. What never changes: the eye line relative to the cranium, the nose centreline and peak, the forehead-to-face relationship, the panel construction, the eye and brow language. The test that matters: two characters with the same body, hair and clothing read as different people. `character_modeling.head_profile` holds the parameters, archetypes and the physique-to-head mapping and enforces the separation.

**The face construction** (FACE-PLANAR-001, FACE-SILHOUETTE-001, FACE-IDENTITY-001) is the approved mask, built by `tools/blender/authoring/male_base_v2.py`: f0 copies v1's head island and subdivides only the face's triangles (no shape change; stored as the construction surface), f1 shapes those vertices from named forms in the head's own frame (`FACE_FORMS`, `NOSE`) strengthened by `FACE_ADJUST` — a brow ridge over hooded eyes, the upper lid fold, cheekbones as the turn between panels, an angular nose tip projecting forward, the chin — and plane turns steeper than `edge_deg` shade as edges. The nose is the most forward point; the cheekbones are the widest forward-facing landmarks; the two panels and their silhouette are the original mask's.

**Fitting through landmarks** (HEAD-FIT-001). `character_modeling.head_fit` defines `HeadFitSurface`: semantic landmarks queried from the surface, never vertex indices, and the face checks measured on them (symmetry, the nose as the forward-most point, the cheekbones as the widest forward-facing landmarks, orbital depth, eyelid-to-brow separation, brow projection). Hair is projected onto the selected head and keeps its design; garments fit the head-to-neck and neck-to-shoulder interfaces. The head has its own topology fingerprint beside the body's.

## The approved base v2 (2026-10-31)

Approved by the person on 2026-10-31. `tools/blender/authoring/male_base_v2.py` builds it deterministically from the frozen v1 master and saves `male_base.v2.blend` (`Armature`, `Body` = v1 as the weight and key reference, `BodyV2`, `HeadV2`):

- **BodyV2.** v1's body in the A-pose without its head island, closed and voxel-remeshed (b0), the large anatomical forms (b1), then the heroic proportions as broad fields (w1, `HERO`: shoulder girdle, ribcage, arms, thighs, calves, neck, trapezius, upper back, lats, glutes). The b1 surface is stored on the object.
- **HeadV2.** The approved face above, on v1's skull.

`male_base.v2.record.json` holds each object's fingerprint; `--verify` rebuilds in memory and compares the rebuild, the record and the saved file. `--bind <blend>` maps the form into WolfRig: v1's weights carried over as the starting point (at most four influences, below 0.01 pruned, normalized), every vertex returned from the A-pose to the rig's rest by the inverse of its own blended skinning matrix, the 16 configuration keys carried and smoothed; posed back in the A-pose the bound body is the approved form again (the round trip is measured). The bound body is a working candidate for the deformation gates; the form is a design sculpt, and production topology (joint loops, ART-PRODUCTION-001) is the next geometry step. Model A (`art-src/blender/characters/reference/model_a.blend`) stays the preserved output of the earlier study generator.

## Variation: body inputs, configurations, head (CHARACTER-VARIATION-001)

`character_modeling.variation` resolves a definition (body inputs, development, head identity) into what the builder applies, on top of `physique.py` and `head_profile` (it never changes their outputs): muscularity drives `mass`; frame drives `upper_body` and a share of `waist`; the seven named configurations are exactly body inputs plus development (each round-trips). Height scales the whole figure; the head grows allometrically (`height ** 0.5`, a broader frame a larger skull, never muscle), so its scale relative to the body stays within `RELATIVE_HEAD_BOUNDS`. Physique reaches the head through the configuration's head profile (jaw, cheeks, neck), interpolated along `mass`; identity (archetype and parameters) never changes with the physique, and placement parameters (`eye_spacing`, `brow_curvature`) move the face marks. `HEAD_FIELDS` defines the head's deformation per parameter in the head's chart. `matrix_report` resolves the boundary matrix (every corner of height × frame × muscularity, the default, intermediates) and reports mass, BMI and head scale; the short-and-lean corner reads below the underweight BMI under the isometric mass law, a finding for the physics owner, not a clamp.

## Face mapping and the attachment framework (FACE-MAPPING-001, CHARACTER-ATTACHMENT-001)

Facial components are fitted to the mask through semantic landmarks, not placed on Wolf. The face's chart is the one Wolf's marks already use: u is x over the head's half-width, v the height fraction above its lowest point, and the surface is the mask's forward-most point there. `tools/blender/inspect/face_surface.py` samples any head object on that chart; `character_modeling.face_mapping` holds the rest, pure and tested:

- `FaceSurface`: position, normal, horizontal and vertical tangents, curvature and projection at (u, v).
- `derive_landmarks`: the geometric landmarks measured on the surface (nose tip and root, chin, brow ridge apex, the cheekbone apex as the strongest vertical convexity on the forward-facing panel, the nose's lateral boundary) and the identity ones from the character's mark fractions (eye centre, inner and outer corners; brow inner, apex and outer).
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
