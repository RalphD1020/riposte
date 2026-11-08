# Blender MCP hair and clothing production

> See also: [docs/reference/blender-mcp-character-art-direction.md](./blender-mcp-character-art-direction.md) (Wolf's identity standard and the master prompt every task inherits), [docs/concepts/character-modeling.md](../concepts/character-modeling.md) (the garment system), [docs/reference/testing.md](./testing.md) (gates and the test-change policy), [spec/invariants.md](../../spec/invariants.md#character-source-001).

Hair and clothing are two related production disciplines on the approved anatomical foundation. The male base is not redesigned and no other procedural character builder is created. The goal is professionally finished minimalist dark-fantasy characters (ART-STYLE-001, not low-poly) whose hair and clothing look like intentional extensions of their anatomy: hair sculpted and flowing, clothing tailored, only the face keeping its geometric language.

Low polygon counts, flat shading and assembled geometric pieces are not the goal. Deliberate silhouettes, coherent surface transitions, sculpted forms, material hierarchy and deformation-aware construction are. Geometry is measured against a per-asset performance budget, never used as a proxy for quality.

Blender MCP creates the asset; it is an execution interface, not an art director. The character tooling — asset definitions, `garment_audit.py`, the PRES-GARMENT-* suites — decides whether the asset is valid, and a person approves the look. MCP never invents its own standard.

## Principles

1. **Silhouette before detail.** Hair and clothing communicate identity from a distance.
2. **Anatomy before garments.** Clothing follows the body underneath; it never replaces that shape with primitive volumes.
3. **Designed masses instead of individual polygons.** Hair is intentional locks and overlapping masses; clothing is fitted panels and purposeful folds.
4. **Topology follows deformation.** Geometry supports the real skeleton and clips.
5. **Material separation creates readability.** Wool, leather, fur, steel and skin are distinguishable without texture detail.
6. **One coherent sculpture.** No disconnected cubes, floating accessories or arbitrary protrusions.

| Principle | For Riposte |
| --- | --- |
| Shape language | Large recognizable masses; smooth where the form flows, angular where the design draws an edge |
| Anatomical continuity | Hair and clothing follow the head, shoulders, chest and limbs |
| Controlled exaggeration | Exaggerate the important shapes without losing the anatomy |
| Functional topology | Edge flow supports the actual deformation |
| Material economy | Few materials, strong value separation, restrained surface detail |

Every geometric feature contributes to silhouette, material identity, construction or deformation, or it is removed.

**One attachment framework (CHARACTER-ATTACHMENT-001).** Hair, facial components and garments fit against named anatomical surfaces and interfaces, never fixed world positions or one body's vertex numbers. Hair knows the scalp, hairline, temples, ears, occipital region, nape and the neck and shoulder clearance (`HeadFitSurface`, HEAD-FIT-001); the bun attaches to the named head anchor; hanging hair follows the head and neck surfaces with clearance through deformation. Garments use the neck interface, shoulder landmarks, deltoid, chest and back surfaces, waist, pelvis and the upper-arm and thigh interfaces (`male_base.surfaces.json`); the mantle fits over the gambeson, not the bare body. The stack is anatomy, then the framework, then head attachments, then body attachments. Facial components use the face chart (FACE-MAPPING-001). The topology fingerprint stays the compatibility check; landmarks are the fitting interface.

## Three approval gates for every major asset

1. **Gate 1, silhouette blockout.** The overall shape, proportions and identity only — no seams, decorative geometry or final topology. Front, side, rear, three-quarter and gameplay-camera captures. A person approves before any refinement.
2. **Gate 2, surface construction.** The real mesh: transitions, thickness, topology and material separation. Wireframe and shaded inspection.
3. **Gate 3, deformation and integration.** Bound to WolfRig, every supported configuration, the real clips (critical intermediate frames, not only endpoints), a candidate export, and the import reviewed in Godot.

This prevents detailed geometry being spent on a silhouette nobody wants.

## Protected foundation

The approved default foundation ([CHARACTER-FOUNDATION-001](../../spec/invariants.md#character-foundation-001); the current library version's document, `art-src/blender/characters/male_base.foundation.v002.json`, its source `.blend`, record, lock and fitting regions `.regions.json`; v001's `male_base.foundation.*` kept for rollback) is read-only, used as the fitting mannequin: hair and attire fit the body and head the foundation resolves for the character's configuration (`male_base_v2_variation.py --set wolf` builds Wolf's), never a copy edited by hand. Never modify:

- its topology, proportions, skeleton hierarchy, rest or bind;
- its resolution switches, physique configurations, skin weights, fitting regions or landmarks;
- the default face (the foundation's eyes and brows);
- any simulation contract.

A garment for the foundation names `base_id: character.male_base.foundation` and the foundation record's body fingerprint (`objects.BodyV2.sha256`), occupies the foundation's fitting regions, and is checked with `garments.problems` against `foundation.garment_target`. The v1 master (`male_base.blend`, `male_base.regions.json`) is the shipping blockout's base only, until Wolf exports from the foundation.

All deforming assets use WolfRig and its bind convention. No other skeleton, no extra hair bones until WolfRig is shown unable to give the required movement. No duplicate anatomical foundation, no second character pipeline, and never a combat, skeleton-contract or runtime-code change inside an art task.

## Before modeling

1. Inspect the base, its landmarks, the relevant bones and weights, and the coverage regions.
2. Inventory the scene, name the protected collections and the target objects, record the existing version and capture baseline views.
3. Establish the silhouette and capture the blockout (Gate 1).

Make bounded, reversible changes; save new versions at milestones; never overwrite an approved source.

## Hair

**Opaque sculpted hair, never strands or cards.** Mobile-first: opaque sculpted meshes, a limited number of larger locks, small geometric surface detail; no simulated strands, no alpha-layered cards as the default (overdraw), no runtime groom. Blender's hair curves and Geometry Nodes hair tools may serve as authoring guides; the exported asset is mesh.

**Why the earlier hair read as chunky dreadlocks.** A handful of independent, similarly shaped masses: uniform widths, abrupt transitions, too much separation, nothing distinguishing scalp, volume and strands, blunt similar tips, little variation in curvature, a hairstyle assembled from objects rather than grown from a head. More subdivision on those objects does not fix it; the construction changes.

**The production hair model: four levels that read as one hairstyle.**

| Level | Purpose | Construction |
| --- | --- | --- |
| 1. Scalp foundation | Hairline, coverage, the skin-to-hair transition | A fitted covering on the actual head with a clean hairline — never a separate helmet |
| 2. Primary masses | The silhouette: swept crown, side and rear volume, the bun | Continuous sculpted forms following the flow, never detached cylinders |
| 3. Secondary locks | Direction, layering, overlap, variation | A limited number of tapered sections that emerge from the primary masses along the same flow |
| 4. Surface detail | The impression of strands | Grooves and ridges between overlapping clumps and narrow locks following the flow; never repetitive cable-like grooves |

**Pipeline.**

1. **Fit the scalp** to Wolf's actual head: hairline, coverage, root directions.
2. **Draw flow guides** — the major flow of the hair (a guide is authoring data, never the exported hair).
3. **Build primary volumes** along the guides, with variable cross-sections, curvature and controlled asymmetry.
4. **Add secondary locks**, each emerging from a volume and contributing to the silhouette.
5. **Refine the surface**: directional grooves, sculpted ridges, restrained variation.
6. **Optimize**: clean topology, hidden surfaces removed, deformation loops where hanging hair bends.
7. **Rig and export**: the scalp, the bun and the tied hair rigid on Head; hanging hair weighted across Head, Neck and, only where needed, Chest; through the existing pipeline.

`tools/blender/authoring/wolf_hair.py` implements this from flow guides. Tied hair is **one continuous shell**: guides run along great circles from the hairline to the gather point, alternating ridge and groove, and the surface between them carries the strand direction — the grooves are sculpted into one form, never made by separate tubes colliding. It meets the cap at the hairline and rises over four rows, so the hairline is a soft edge, not a brim. Hanging hair is **thick sheets** of the same ridge/groove construction falling from under the tied section (the guide is the sheet's inner face, the thickness stands outward, so a guide that clears the body keeps the sheet clear); each groove stops short of its ridges, so the lower edge breaks into tapered points. A few lens-sectioned locks layer over the crown or the rear sheet, emerging from the volume; the bun is a core wrapped by coiling locks. Each style has review variations (`--ranger A|B|C|D`, `--training A|B|C|D|E`).

The integrated construction (Ranger D, Training E) adds what surface integration asks for. **Drape**: a hanging guide follows the measured body — the occipital contour, then a bounded fall across the nape hollow (it may move inward only so fast per metre down, so it bridges the hollow instead of clinging to it), the neck where the neck is nearer, and outward where the trapezius widens — at a gap that grows from just above the scalp cap to the nape. **Parting**: for half-up hair the tied section starts behind the ears at a parting that rises smoothly from the hairline, lying over the hanging hair's roots; no tied bands are built under the knot, where they were stubs that read as a jagged fold. **Seated cap**: every scalp-cap vertex that would show through the first hair surface above it is lowered beneath it, so the scalp disappears beneath the hairstyle (a cap level with a groove z-fought into a scalloped patch). Grooves stay above the cap, ease in below a sheet's root (no teeth along it), and a sheet thins towards its lateral edges (no full-thickness wall shows). The script records every band's and lock's profile (`riposte_locks`) so the design heuristics measure what was built. It is the reproducible authoring path for review candidates; a hand sculpt in Blender (MCP or an artist) is equally valid and goes through the same definition, tags and audits.

**Flow masses on the head map (Ranger G, Training F; HAIR-FIT-001).** The v002 construction keeps the shell as an underlayer and builds the hairstyle from a few broad flow masses (crown, temples, front sweeps, nape) with three secondary locks and one short temple accent, each on a great-circle guide evaluated at a resolution set by its length and turning (`FLOW_RING_RAD`, `FLOW_CURVE_W`), not by its authored controls. A mass is seated on the hair beneath it through blurred seat heights (its rims never zigzag over grooves), grows from the scalp at a hairline root and ends in a tip that sinks into what it lies on; the cap and shell are then tucked under every mass and the bun. The bun is a core with folds wrapped over its own ellipsoid. A style with `fit_head` reads the head map `head_frame_of` measures on the resolved head: the ears' keep-out (the helix and any part standing `EAR_COVER_M` off the skull, as a plateau per azimuth), the brow line (the front hairline follows it) and, for loose hair, how far the neck stands behind the head (`NECK_REF_M`: the drape gap grows, the hair never lengthens). Training's loose masses start behind the ears and end in one chevron each (`smooth_ends`), weighted Head -> Neck by height. The builder's v001 variants never read the map and rebuild byte-identically.

**Mapping a hairstyle to every variant.** `male_base_v2_variation.py --set hair_sweep_ranger|hair_sweep_training` builds a hairstyle on the foundation's whole sweep and `--set hair_identity` on every head archetype (`--hair-variants ranger=G,training=F` names candidate builder variants); `ear_report` adds the helix vertices inside the hair and the visible ear's hidden share from beside, level and at the match camera's pitch. The person approves the per-configuration review sheets, and each approved configuration becomes a library validation of the hairstyle's version, so the character creator offers it as validated there. Combat readability is measured on the production clips with the export's own weighting (hair inside the posed body per clip) and at the match camera (the share of a blade swept round the fighter that the hair hides and the bald fighter would not), for both skins.

What each earlier construction taught: independent similar masses read as dreadlocks; many intersecting tubes read as a ribbed beanie or crumpled paper; thin hanging clumps read as icicles. Continuity and broad, shallow grooves are what made it read as hair.

**Hair heuristics and who decides.** Measured where measurable, never invented as an artistic verdict.

| Heuristic | Prevents | Kind |
| --- | --- | --- |
| Root attachment | Floating hair | Technical (audit: contact) |
| Root coverage | Exposed scalp gaps | Technical (audit: scalp coverage) |
| Flow continuity | Disconnected-looking locks | Technical (audit: contact, design regions) |
| Width variation | The uniform dreadlock look | Design heuristic (`hair_design`) |
| Tip taper | Blunt cylindrical ends | Design heuristic (`hair_design`) |
| Curvature variation | Repetitive artificial shapes | Design heuristic (`hair_design`) |
| Layer hierarchy | Hair reading as separate blocks | Design heuristic and review |
| Silhouette variation | Helmet-like hair | Review (captures) |
| Surface direction | Hair that reads as clay | Review |
| Overlap control | Excessive bulk | Advisory (audit: buried masses) |

**Three classes of finding, never mixed.** A technical failure blocks (a root off the scalp, hair in the neck during a death clip, a garment through the elbow). A design heuristic warns and asks for a look (uniform widths everywhere, blunt tips). An art-direction finding is a person's (the hair reads as dreadlocks; Ranger and Training silhouettes look alike). A passing intersection test never proves a good hairstyle.

**Design regions, not object lists.** Mass names (`SweptFront`, `Lock.L`) are implementation; they do not tell an artist what the hairstyle should look like. A hair definition's `design` block describes it as a designed arrangement of connected volumes: `style`, `primary` (the region the rest grows from), `regions` mapping each design region (`scalp` always, then `front_sweep`, `temples`, `rear_tie`, `side_locks`, `rear_mass`, optional `accents`) to the masses that build it, and an `intent` sentence. The authoring script tags every face with its mass (`riposte_mass` face attribute, names in `riposte_masses`), so the audit can trace each lock to its region. The character's art profile names the regions each outfit's hairstyle must have.

**Root-to-tip continuity.** Every secondary lock attaches clearly to a primary mass: no disconnected pieces, floating ends or abrupt changes of volume. Separate masses are fine — what matters is that they read as connected in the final design.

**Deformation.**

| Component | Deformation |
| --- | --- |
| Scalp, front sweep, temples, crown, bun | Head |
| Hanging hair beside the head | Head |
| Hanging hair resting on the body | From Head into the weights of the body surface beneath it (Head at the jaw, mostly Head at the nape, Neck and Chest on the trapezius), smoothed along the hair |

Rigid on Head is the default; skin only what the animation actually requires, with the existing WolfRig. Never spread hair across the skeleton because bones exist. Hair that rests on the body moves with the surface it rests on: weighted to Neck by height alone, hair beside the jaw was entered by the head in a death fall, and weighted partly to Head, tips on the upper back swung into it as the head fell back. The weights come from the base body, never from a garment.

**Shared rules.** Preserve the exact face and eye placement; respect `face_clearance`; one `hair` material slot; consistent visual thickness; the same character scale; validated against every supported clip; no transparent cards or strand shaders. Hairstyles differ in silhouette, flow and mass distribution, not merely length.

**Wolf.**

- **Ranger, neat and tightly tied (disciplined, prepared for combat):** an experienced swordsman who keeps his hair secured. Tight scalp coverage with a clean hairline; one clean swept-back crown mass; tight sides and a gathered nape drawn into a compact, deliberate bun that grows from the gathered hair. A compact, narrow, controlled silhouette with the neck exposed. No loose locks, stray spikes, accent tips or messy silhouette; no helmet-like cap, no bun that reads as an attached ball. Rigid on Head.
- **Training, half up and shoulder length (relaxed; Jon Snow's line):** the upper hair swept back and gathered into a small, clearly tied knot that is part of it, not an accessory on the skull; shoulder-length hair flowing beneath — one coherent rear mass, tapered ends of different lengths, layered side locks framing the face. Broader, layered and fuller around the neck than Ranger: a different silhouette, not Ranger with longer locks. The knot sits exactly where Ranger's bun does. The hanging hair drapes the occiput and the nape hollow and ends at the base of the neck; it narrows into the nape instead of hanging as a panel. The scalp cap and the tied hair are rigid on Head like the skull under them; the hanging hair takes the weights of the body surface it rests on.

**Baseline, not final.** Ranger and Training are the comparison baselines, not approved final designs. A candidate is welcome to improve them; what it may not do is regress their identity, hairline, bun position, coverage, fit or silhouette. A candidate that is not a clear improvement in identical before/after captures is discarded and the baseline kept. Each style is approved on its own (head anatomy, face integration, Ranger and Training are four separate art approvals), so a better hairstyle can never hide a poor head.

**A designed hairstyle, not a clump generator.** Procedural construction serves repeatability and fitting: scalp-local attachment, region masks, guide placement, deterministic generation of the final mesh. The hero silhouette is directed: guides are shaped and the silhouette edited on purpose, and no seed or random spread decides it. Three visual levels read as one style: primary masses establish the silhouette, secondary locks emerge from them (never glued onto a helmet), and a few deliberate accents finish tips and separations. A lock follows a curved guide with tangent continuity and a variable elliptical, softly flattened section that is convex on top, rounds into its sides, changes width and thickness gradually, blends its root into the mass and tapers its end (not necessarily to a sharp triangle). Never rectangular extrusions, constant-width pipes, flat plates, many deep grooves, uniform clumps, or strand count standing in for design. Before adding geometry, separate the cause: if the silhouette and clay are smooth but the light shows patches, the fault is normals or material, and polygons do not fix it. Blender's clump and Geometry Nodes hair tools may build guides; they do not replace authored shapes, and experimental hair dynamics stay out of the production path.

| Procedural failure | Prevention |
| --- | --- |
| Hair cap | Hairline and skull coverage validated from every angle |
| Floating roots | Scalp-local attachment coordinates, reprojected after any head change |
| Bald gaps | Root distribution and coverage checked in posed states |
| Spaghetti locks | The primary / secondary / accent hierarchy enforced |
| Blocky clumps | Cross-sections, curvature and normals measured |
| Identical clumps | Controlled deterministic variation by region |
| Spikes | Tip curvature and silhouette review |
| Intersections | Scalp, face, ears, neck and clothing checked |
| Unstable results | Fixed seeds and stable guide identities |
| Cost | Mesh budgets, LODs and performance measurements |

Ranger: keep the hairline and bun position; make the gathered hair visibly converge on the bun in broad overlapping locks from the temples and crown; give the bun a layered, irregular silhouette, not a sphere; improve the rear and three-quarter transitions. Training: keep the bun and the shoulder-length arrangement; split the loose rear hair into a few broad organic masses of controlled curvature and varied lengths; connect the half-up transition; no rigid curtain and no disconnected hanging clumps. Facial hair is revisited after the head shape is stable, because the jaw is its attachment surface.

**Surface integration (ART-SURFACE-001).** The geometry of a hairstyle can be finished while its integration with the body is not; [docs/concepts/character-art.md](../concepts/character-art.md#character-surface-integration-art-surface-001) defines attach, clearance and drape, the anatomical regions and the severities. Blender techniques and their place:

| Technique | Use |
| --- | --- |
| Sculpting and proportional editing | Shape the nape, hairline and transitions |
| Shrinkwrap (offset, vertex group) | Fit selected roots or regions to the scalp — never the whole hairstyle |
| Solidify | Controlled thickness of a shell that is already a good form; it does not rescue a flat one |
| Armature deformation | The runtime solution: follow the head and neck |
| Surface Deform | Optional offline deformation transfer, never a runtime dependency |
| Weighted vertex groups | How each hair region follows the skeleton |

Blender MCP shapes and inspects; the scripts make it reproducible. Never change a procedural parameter blind: every change is reviewed in captures before the next.

**Blender MCP task: hair surface integration.** Objective: make each hairstyle feel attached to the character's anatomy without redesigning an approved one (an approved silhouette, bun position and identity are preserved). Avoid flat hanging sheets, thick rectangular locks, floating masses, perfectly repetitive bands, helmet-like hair, abrupt scalp-to-hair transitions and excessive ornament. Favour continuous sculpted masses, natural directional flow, subtle variation in volume and curvature, clean transitions at the hairline and nape, intentional overlapping layers, and silhouettes that read at the gameplay camera.

1. Load the base and the character's assembly.
2. Inspect the head, scalp, ears, neck and shoulders from the front, side, rear and three-quarter.
3. Inspect the existing hair before modifying anything.
4. Identify the actual contact and clearance regions (`male_base.surfaces.json`).
5. Shape the rear profile to the occipital contour, the nape and the shoulder transition.
6. Check an approved style's integration without redesigning it.
7. Keep intentional volume and separation; no blanket shrinkwrap.
8. Keep hair deformation independent of clothing.
9. Keep the semantic tags and the assembly contract.
10. Validate every configuration and every clip; record each defect with its owning layer; never fix an animation defect by distorting correct hair.

Deliverables: the updated Blender source and authoring definitions, reproducible GLBs, the CharacterArtQA findings, front/side/rear/three-quarter captures, the two styles side by side, and an explicit list of remaining defects and unverified assumptions. Nothing replaces an approved production asset before its review gates pass.

**Fitting through the head, not to one head (HEAD-FIT-001).** The head is becoming variable (identity parameters and physique-derived profiles), so a hairstyle reads `HeadFitSurface` — semantic landmarks queried from the selected head (crown, hairline front, temples, ear roots, occipital, nape, bun anchor, face boundary) — instead of a pinned topology: the scalp foundation is projected onto that head, the hairline follows its forehead and temple landmarks (wider cheekbones do not move it), the bun stays on the occipital anchor (never a percentage of head width), and clearance is checked against the head, face, ears and neck, across every head profile and clip. Design intent is preserved and the fit adapts; Ranger D and Training E are fixtures of that refit, never redesigned for a bad fit.

**Garments meet the head and neck through interfaces.** Head-to-neck: skull base, jaw clearance, nape, neck attachment, collar opening. Neck-to-shoulder: trapezius, sternocleidomastoid, shoulder slope, clavicle, upper back. A garment declares its upper boundary (collar height, collar opening width, hood clearance, mantle attachment, shoulder coverage) and whether it may contact the body (skin-tight, padded and rigid armour differ). A collar in the jaw or hair in the face is a hard failure; a mantle crossing the neck in a clip is found by the envelope. Garments fit the actual anatomy of the selected body and head, never Wolf's default head.

**Order of work.** Do not perfect hair against anatomy about to be replaced: correct only obvious integration defects on the current base, establish the final neck, shoulder, trapezius and upper-back surfaces in the base overhaul, then refit both hairstyles and rerun the full matrix, then fit the gambeson and mantle to the new base, then validate hair + body + gambeson + mantle together across every configuration and clip.

**The scalp cap** is a grid of rays onto the skull from each style's hairline (an elevation curve by azimuth) up to the crown, so the hairline is one clean designed edge. Cutting the cap from the skull's own faces left a staircase that read as spikes at the nape. A mass grows from inside the cap behind the hairline, so its root face never shows on the forehead.

## Clothing

Clothing establishes identity and preserves the anatomical silhouette and movement underneath. A gambeson is a fitted garment with chest and back surfaces, side transitions, armholes, collar, hem and sleeves, not a box. A mantle is designed armor following the shoulder, not two boxes on the clavicles.

**Construction types.** Each has its own expectations for thickness, clearance and deformation, so no single clearance applies to everything:

| Construction | Examples | Expected behavior |
| --- | --- | --- |
| `fitted` | Gambeson, trousers, sleeves | Close anatomical correspondence, clean joint topology |
| `padded` | Training jacket, padded collar | Consistent thickness and controlled volume |
| `structured` | Leather mantle, chest protection, bracers, boots | A stable, deliberate outer silhouette; some sections rigid |
| `rigid` | Buckle, knee plate | One bone, or controlled rigid deformation |
| `fur` | Ranger's collar | A few large directional clumps, may overlap what it frames |
| `loose` | Skirt panels, hanging cloth | Controlled clearance and authored movement; never runtime cloth |
| `accessory` | Pouch, small fittings | Hard pieces attached to a bone or a garment |

A definition's `category` is one of these, and the contract accepts the ones whose clearance profile exists in `male_base.regions.json` (`fitted`, `structured`, `loose` today). `padded`, `rigid`, `fur` and `accessory` enter that list with their profile, calibrated on the first asset of the construction (the padded profile with the gambeson or the Training jacket); no profile is invented before an approved asset can calibrate it. An outfit's art profile lists the constructions its garments may use.

**Workflow: anatomical garment correspondence.** A garment understands the regions it covers, how it follows them and what happens when they move. Ranger's gambeson is a chest, an abdomen, an upper back, shoulder transitions, arm openings, waist compression and hem boundaries, modeled as one coherent garment:

1. **Fit the base surface.** The default Wolf anatomy is the mannequin; set the boundaries and the intended ease (Gate 1).
2. **Construct the garment.** The real surface, with deliberate thickness, openings, hems and material boundaries (Gate 2).
3. **Design the topology** around the moving regions (below).
4. **Define deformation.** Transfer weights from the base as an estimate, then refine the garment's own. Proximity transfer picks the wrong region where surfaces are close (armpit, groin): inspect and correct it.
5. **Establish layering:** which assets overlap, which stay outside another, which body faces are hidden.
6. **Test the real animation** through every relevant production clip.
7. **Test physique** — body and garment together across every supported configuration (Gate 3).

The garment is fitted to the body, not a copy of it: a gambeson has padding, a mantle structural thickness, a skirt its own volume.

**Garments have their own topology profile.** A garment does not inherit the anatomy's topology; geometry goes where it changes the silhouette or the deformation.

| Region | Topology intent |
| --- | --- |
| Chest | Broad surfaces, no unnecessary density |
| Shoulder | Enough loops for arm elevation |
| Armpit | Controlled compression and stretch |
| Elbow | Directional deformation loops |
| Waist | A smooth transition round the torso |
| Hip | Loops that accommodate leg separation |
| Hem | A stable, deliberate edge silhouette |
| Rigid leather | Stable panels with minimal bending |

**Thickness.** Not one large uniform Solidify. Consistent inward or outward thickness, clean openings, intentional hems, defined edges, the right padding volume and correct normals — padded fabric reads as padding, leather as an edge with thickness. Shrinkwrap, Surface Deform and Data Transfer never substitute for modeling the garment and validating its deformation.

**Topology.** Loops at the elbow; flow round the armpit and shoulder; flow through the crotch and hip; the knee shaped for flexion; transitions across the clavicle and deltoid. Geometry where deformation or silhouette needs it, never uniformly. Preserve the skinning relationships of the rigged base.

**Folds communicate forces.**

| Situation | Result |
| --- | --- |
| Fabric stretched across the chest | Broad, relatively smooth surface |
| Compressed under the arm | Small controlled folds |
| A sleeve bending at the elbow | Directional compression folds |
| A belt compressing the waist | Folds radiating from the belt |
| A skirt hanging from the waist | Vertical gravity folds |
| Shoulder movement | Tension changes across the mantle |

Three levels: **primary** folds (large changes of surface direction, part of the silhouette), **secondary** folds (smaller changes showing the material) and **tertiary** detail (seams, stitching, straps, small accents). Riposte garments use mostly the first two: a wool gambeson reads through broad padded planes, a leather mantle through angular surfaces and reinforced edges — never procedural noise or random wrinkles.

**Wolf.**

| Ranger, the field swordsman | Treatment |
| --- | --- |
| Gambeson | Fitted dark wool, broad padded planes |
| Chest protection | Contoured leather panels following the chest |
| Shoulder mantle | Integrated asymmetric leather reinforcement: two or three large surfaces, a defined outer edge, a little asymmetric detail; reinforces the broad shoulders without oversizing them |
| Collar | Restrained fur, framing rather than hiding the neck |
| Belt | Broad leather with a designed buckle |
| Pouch | One prominent functional pouch |
| Bracers | Sculpted leather with reinforced edge planes |
| Trousers | Fitted, controlled knee folds |
| Boots | Strong toe, cuff, layered sole |

| Training, Wolf without field equipment | Treatment |
| --- | --- |
| Jacket | Fitted padded training jacket, broad padded planes, no leather armor |
| Shoulders | The exposed anatomical shoulder silhouette |
| Collar | Simple padded collar |
| Arms | Fitted sleeves and cloth wraps |
| Waist | Simple belt, short cloth tabs |
| Trousers | Practice trousers with directional folds |
| Boots | Simpler low boots |

Ranger wears protective equipment; Training wears clothing made for unrestricted movement. Both are the same person.

## Skinning and physique

- WolfRig only. Transfer weights as a start — nearest-face interpolation for fitted garments, normal projection only where it maps better, always a maximum distance — then inspect region by region (a sleeve never picks up the pelvis) and refine the shoulder, armpit, elbow, wrist, waist, hip and knee. Normalize, strip negligible influences, at most four, none unweighted.
- Support only the declared configurations. Transfer the base's key deltas as a start, correct where the construction differs (structured leather does not deform like skin), and inspect the combined body and garment for every one. Data Transfer, Surface Deform and Solidify never replace inspection.
- Hair follows head shape and clearance; it is not assumed to need clothing's physique corrections. A hair or garment covering only regions no physique parameter shapes declares `"physique": "none"`.
- Never modify the base to accommodate a garment.

## Animation inspection

Real production clips: idle guard, forward and backward movement, the forward and both side dashes, a sword raise, the full charged attacks, death, falls, the full authoritative horizontal combat range. Inspect critical intermediate frames, not just clip endpoints.

## Validation

Record: triangles, vertices, mesh islands, material slots, bone influences, weight normalization, surface clearance, body and garment intersections, hair and face clearance, physique compatibility, deformation results. Tolerances are per asset — a fitted gambeson, a fur collar and a structured mantle have different intended clearances, a loose rear lock may move centimetres while an eye may not be entered by a millimetre — and intentional overlaps are declared, never tolerated silently.

| Hair test | Expected |
| --- | --- |
| Scalp coverage | No exposed scalp where the style covers the head |
| Face clearance | No intrusion into the eyes or brows |
| Head deformation | Hair follows Head |
| Neck clearance | No penetration during head turns |
| Shoulder clearance | Training's hair does not enter the shoulders |
| Crown bounds | Correct overall height |
| Design regions | Every tagged mass in exactly one declared region; every declared mass present |
| Root-to-tip continuity | No mass that touches no other mass |
| Silhouette | No unintended change against the approved captures |
| Material integrity | The `hair` slot only |
| Import integrity | Correct skeleton and mesh bindings |

| Clothing test | Expected |
| --- | --- |
| Anatomical fit | The intended clearance |
| Skinning | Valid normalized weights |
| Joint deformation | No unacceptable folds or separation |
| Layering | No unintended garment intersections |
| Body masking | No exposed hidden geometry |
| Physique | Valid on every supported configuration |
| Animation | No critical penetration or floating |
| Import | WolfRig and the right materials |

**Test the garment stack, not the garment.** The gambeson alone, then gambeson + chest protection, then + mantle, then the complete Ranger and the complete Training: the complete stack is what ships. Intentional overlaps are declared so the validator does not fight the design (the fur collar over the gambeson, the mantle over the chest protection).

**Calibrate every heuristic** against known-good and deliberately defective versions of the same asset: the defect is detected, it is localized to the right region, unrelated regions are not flagged, and the finding disappears when the good version returns. A threshold carries its status (calibrated, provisional or advisory) and the fixtures it was set from; no universal threshold is invented. The hair contact check, for example, catches a lock moved clear of every other mass and names only that lock, but it passes a lock pushed back that still overlaps its neighbour, so its next version tests the lock's root against the scalp or primary mass.

**Five kinds of evidence, never merged.** A clean deformation report does not establish that a hairstyle is aesthetically right.

| Validation | What it proves | Who decides |
| --- | --- | --- |
| Structural | Masses attached and mapped, geometry valid, no mass buried in another | The audit |
| Deformation | The asset follows the rig through the matrix without unacceptable intersections | The audit |
| Silhouette | The asset matches the approved design | A person (captures; image differences only flag change) |
| Identity | Wolf's face and anatomy remain recognizable | A person, with the identity checks guarding drift |
| Presentation | Features read at the gameplay camera | A person, from Godot captures |

**Two sampling tiers.** The iteration envelope (`--clips envelope`: 10 clips × 4 frames × every configuration, 287 samples) for each change; the acceptance matrix (`--clips all --frame-step 2`: every production clip at every second frame × every configuration, about 4,150 samples) before a gate. The matrix reports failures by clip and the worst sample per region. The envelope alone is not acceptance: on Wolf's hair it was clean while the matrix found the ring falls and a death clip.

**Five validation groups.**

| Group | Protects | State |
| --- | --- | --- |
| Identity | Face, anatomy, head, the art profile across outfits | Built: `identity.py`, the base fingerprint, the rig digest, the face marks |
| Hair | Scalp, clearance, design regions, continuity, silhouette, deformation | Built except the silhouette comparison |
| Clothing | Fit, thickness, topology, layering, masking, physique | Fit, weights, masking and physique built; stack, thickness and per-region deformation planned |
| Art direction | Silhouette, material hierarchy, detail economy | Captures and the review table; measurements planned |
| Runtime | Imported asset, rig, clips, grips, presentation | The Godot suites, after the first garment GLB |

Godot is the final runtime authority: the validated GLB is checked there for skeleton binding, meshes and materials, clips and `RESET`, four influences, the wrapper and `SwordRig3D` attachment, costume selection, no missing resources, and Compatibility rendering. Blender's analysis is an early warning and a diagnosis, never a substitute.

Approved hairstyles and garments keep fixed-camera captures (`render_views.py` at the gate's views and worst-case poses) as visual regression references; an image difference catches a regression, it never proves the new design looks good. Human visual approval is mandatory; an asset is not production-ready because it exports.

## Runtime

Blender is the authoring authority, GLB the runtime format, Godot imports and presents. All deforming meshes use WolfRig; rigid accessories attach to bones; configurations are baked before export; no runtime character reconstruction, no runtime cloth, no gameplay physics from hair or clothing meshes. Two meshes referencing the same skeleton do not prove correct bind matrices: validate the imported skin bindings. Keep the four-influence limit and Compatibility testing; no LODs or complex materials until a measured bottleneck asks for them.

## Decisions (2026-10-30)

- **Hair geometry:** sculpted mesh masses, no strand cards.
- **Clothing shading:** controlled smooth shading with sharp designed edges (crisp designed planes, smooth transitions inside them). Hair uses the same rule.
- **Reuse:** Wolf-specific assets first, written as reusable definitions; no promise that a garment fits every base.
- **Hair movement:** rigid on Head by default; no extra hair bones until WolfRig is proven insufficient.
- **Clothing before tooling:** two excellent reference outfits (Ranger, Training) come before any reusable procedural clothing generator; they are what it is calibrated against.

## Delivery and change report

Each task delivers the versioned Blender source, the asset definition, a candidate GLB (never over production), the geometry, weight and physique reports, the gate captures, and known defects naming every failed test and the likely owning layer. Report changed and new objects, modified geometry, weights, materials and modifiers, triangle counts, captures and validation results. Promotion needs the tooling and the Godot suites green and then a person's approval.

## The tooling

- **Definitions** — `art-src/blender/garments/<id>.garment.json` (`riposte.garment`, `"type": "garment"` or `"hair"`). The rules live in one pure module, `tools/character_modeling/character_modeling/garments.py` (unit-tested in `tests/test_garments.py`): base id and topology fingerprint, rig contract digest, category, regions, layer, deformation (including `physique`), supported configurations, `coverage.hides` only within the asset's own regions, material slots within the character's, per-asset clearance overrides and declared overlaps, `requires` / `incompatible_with`, duplicates; hair additionally covers the head, wears only `hair` and declares its face clearance. `character_assembly.load_outfit` refuses an outfit that fails any of them.
- **Physique correspondence** — `tools/blender/authoring/garment_physique.py` gives an asset a key per base physique key (same names), each vertex taking the key's displacement at its nearest point on the base's rest surface. A start, not the answer.
- **Audit** — `tools/blender/inspect/garment_audit.py`: weights and static fit against the asset's own clearance; with `--configurations all --clips envelope` the body and the asset posed together through every supported configuration and the envelope clips, every penetrating sample named with its worst vertex, the region under it and the likely owning layer (rest at default: fit or topology; a configuration only: the asset's physique shape; a pose only: weights or topology at a joint). For hair, with `--manifest`, it checks the face-clearance volume, scalp coverage, the crown bound, the tagged masses against `design.regions`, each mass's contact with the rest of the hairstyle (a mass passing through another surface counts as attached), and for every pair of masses the share of one inside the other (advisory: a mass mostly buried in another shapes nothing; the scalp cap lies under the masses by contract). In memory only, it makes a linked base posable, borrows the base's clips when the attire blend has none, and binds the asset as its definition says.
- **Design heuristics** — `tools/character_modeling/character_modeling/hair_design.py` (tests in `tests/test_hair_design.py`) measures the recorded profiles per design region: width variation, blunt visible tips, straight or repetitive curvature of hanging locks (tied hair combed to one point is meant to flow alike). Provisional design warnings, reported by the audit as `design_heuristics`, never failures. The buried-mass check considers only closed masses as containers (open shell bands and the cap have no inside); on the shell construction it still over-reports and awaits calibration.
- **Budget** — the character manifest's `budget`: above `review_triangles` (4,000) the export prints `RIPOSTE_BUDGET_REVIEW` for a person to look at where the geometry went; above `max_triangles` (8,000, provisional until the character rendering benchmark) it fails. A triangle count is a performance measurement, never an art-direction ceiling.
- **Identity** — `tools/character_modeling/character_modeling/identity.py` (tests in `tests/test_identity.py`) checks the manifest's `art` profile: the four anchors, every complete outfit profiled, the intrinsic palette, no costume palette naming an intrinsic material, and, for the outfit being assembled, that it wears its profiled hairstyle with exactly the profiled design regions and only garments of its declared constructions. `character_assembly.assemble` refuses an outfit that fails it, and assigns intrinsic materials after the costume's so a costume can never recolor identity.
- **Assembly** — `character_assembly.assemble` attaches each outfit asset from its source blend (skinned on WolfRig, or rigid on one bone), bakes its keys with the body's configuration when it follows physique, applies the outfit's costume palette, refuses material slots the definition does not declare, removes the covered body faces in the export copy only (a margin ring kept under every garment edge) and refuses the export if a mask edge is not covered.

A weight-audit finding asks for an explanation; it is not an automatic failure (30 % upper-arm influence mid-chest needs a reason). Hard limits — four influences, normalized, none unweighted, no body penetration — fail.
