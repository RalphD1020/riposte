# Character layering: mapping faces, facial hair, hair and attire

> See also: [character-asset-library.md](./character-asset-library.md) (approved assets, versions, categories, menus), [docs/concepts/character-modeling.md](../concepts/character-modeling.md) (the foundation and how a character layers on it), [blender-mcp-hair-clothing-production.md](./blender-mcp-hair-clothing-production.md) (hair and clothing production), [spec/invariants.md](../../spec/invariants.md#character-layering-001) (CHARACTER-LAYERING-001, CHARACTER-FOUNDATION-001)

A character is a foundation plus layers. This guide is how every layer is mapped onto the anatomy beneath it and how one declaration decides what each layer hides, so code and graphics agree by construction.

## The decorator is a plan, not a stack of wrappers

"Decorator" here means declarative composition: each layer is a definition that adds to the character and declares what it covers. `character_modeling.appearance.resolve` validates every chosen definition against the foundation, orders them and computes the visibility of everything beneath them, once, into a flat appearance plan (`riposte.appearance_plan`, with its own fingerprint). Nothing is a runtime wrapper; no layer changes another's visibility on its own.

| Responsibility | Owns | Home |
| --- | --- | --- |
| Definitions | what a character is and wears, and what each piece covers | the character manifest (`foundation` block, `identity`, `outfits`); `riposte.garment` definitions (`type` `facial_hair`, `hair`, `garment`) |
| Resolver | compatibility, order, coverage, the immutable plan | `appearance.resolve`, `garments.problems`, `foundation.garment_target` |
| Blender builders | fitting, generated geometry, derived (masked) meshes, validation | `male_base_v2_variation.py` (`apply_layers`, `mask_layer`), `face_features`, `facial_hair`, `wolf_hair` |
| Export manifest | the plan's fingerprint and the validated outputs | `export_assets.py` (from F10 on the foundation) |
| Godot | static selection of prebuilt meshes, blend-shape weights | `FighterSkinKit`, `FacePresentation`; never geometry, never a second coverage rule |

The parity rule: one declaration, one resolved plan, one validated visual result. Blender realizes the plan; Godot reads its result.

## The layers

Innermost first. A layer may hide only what lies beneath it.

| Layer | Contents | Ownership vs coverage |
| --- | --- | --- |
| `foundation` | the resolved body, skeleton, head (cranium, face surface, landmarks) | never trimmed; hidden regions are removed from the character's own derived copy |
| `identity.face` | the face marks: the foundation's default face, or a character's `face_refine` over it | eyes, brows, lash lines; the nose is the head surface |
| `identity.facial_hair` | beard, moustache, goatee, sideburns (`type: facial_hair`) | identity, worn in every outfit; covers face skin, preserves the mouth |
| `outfit.hair` | the outfit's hairstyle (`type: hair`) | a skin's choice; never shapes the skull |
| `outfit.garment.<1..4>` | underlayer, outer, protection, accessories (`type: garment`, `layer`) | covers body regions and the layers beneath |

Ownership and coverage are separate properties: a beard is identity but hides chin skin; a helmet is attire but can hide the hairstyle.

## Mapping each layer onto the anatomy beneath it

Two mappings, chosen by whether topology is shared:

- **Shared topology: bind to the mesh.** Every resolved head is the foundation's head topology (`HeadV2`, morphed per configuration), and every resolved body the foundation body's. A vertex list or a barycentric point on that topology is valid on every variation, the way production groom bindings carry facial-hair roots across heads by matching topology and UVs ([Accent groom bindings](https://dev.accent.studio/v1/groom-bindings/technical-dive)). Coverage regions use this: the foundation's regions file (`male_base.foundation.v002.regions.json` for the current version) stores body regions and the head's sub-regions as vertex indices, keyed to the record's fingerprints.
- **Authoring and placement: landmarks and charts.** Shapes are designed in anatomy, never in world coordinates: the face chart (u across the head's half-width, v up its height), the mask's anchors (`eye_recess`, `brow_ridge`), the measured ridge line, the hair's construction surface. A feature is placed by querying the resolved head's surface there, so it follows every head.

Never reuse vertex indices across a different fingerprint; a retopology regenerates the regions and every binding.

| Asset | Fitted to | Mapping |
| --- | --- | --- |
| Eyes, brows, lash lines | the resolved head's face | marks in the face chart on their mask anchors, columns walked on the surface (`face_features.place_marks`); `variation.face_response` follows head size and build |
| Nose | the head surface | the mask's nose controls (`face_mask`), part of the head |
| Scalp hair | the resolved cranium | the construction surface and hairline (`wolf_hair.head_frame_of`, `build_style`); primary masses cover the scalp and set the silhouette, secondary locks set the flow, tertiary detail the hairline ([large-to-small hair construction](https://hossimo.com/articles/tips-and-tricks-an-artist-friendly-approach-to-sculpt-groom-hair/)); roots on the scalp, never floating or buried ([Reallusion hair guide](https://wiki.reallusion.com/Content_Dev:CC_3.4_Hair_Mesh_Production)) |
| Facial hair | the resolved face | masses designed as chart outlines (lower edge, cheek line, thickness, drop, clumps), each point projected onto the head and stood off along its smoothed normal (`facial_hair.build`); coverage on the head's sub-regions |
| Garments | the resolved body | the foundation's fitting regions, surfaces and interfaces (`male_base.surfaces.json`), coverage by region |
| Rigid accessories | named anchors on a bone | an anchor, a fit envelope, explicit coverage |

Fit order for every height and build: resolve the body and skeleton → the head and face anatomy → the character's identity → eyes, brows, nose → hair and facial hair → garments → coverage across all layers → derived visible geometry → validation. A hairstyle, beard or garment fitted once to the reference is never assumed to fit another body without the same checks.

## Coverage: directional and explicit

Every layer that covers anything declares it in its definition's `coverage`:

| Field | Meaning |
| --- | --- |
| `hides` | foundation regions (body regions, head sub-regions) whose surface it covers |
| `preserves` | regions that must stay visible whatever covers them (facial hair always preserves `mouth`) |
| `hides_components` | components beneath it hidden whole (a closed helmet hides the hairstyle) |
| `margin_rings` | how many face rings inside a covered region stay (`garments.masked_faces`) |
| `requires`, `incompatible_with` | pairing rules (`garments.problems`) |

`appearance.resolve` computes the plan's visibility from the whole selection: hidden regions per target object, margins, preserved regions, hidden components. It fails closed when a layer hides a preserved region, hides a component that is not beneath it, names an unknown region, or hides a region it does not occupy. A helmet never hides "everything on the face" by implication; a beard never the mouth.

**Bake the hiding into derived meshes.** The canonical body and head are never trimmed. The build removes hidden faces from the character's own copy (`mask_layer`: `garments.masked_faces` with the margin, `garments.open_boundary_after_mask`), then counts mask edges no covering surface reaches (`character_assembly.exposed_holes`): a hole that would show. This is how layered-clothing tools work: each layer trimmed only by the layers above it, the body by the whole outfit, the trimmed result baked per combination actually worn, the cut kept a margin inside the covering edge so animation never opens a gap, poke-through fixed by hand where geometry pushes outside its cover, and non-stacking pieces (belts, gloves, boots) treated against all others rather than by order ([Athian layered clothing](https://athiangames.com/docs/dynamic-mesh-occluder/layered-clothing), [Crystal occlusion layers](https://arawn-software-publishing.gitbook.io/crystal-character-creator-professional/core-concepts/runtime-body-occlusion-culler/body-culling-equipment-occlusion-layers-and-mask-painter)). Riposte does it at build time, never at runtime, and measures coverage across the pose suite and clips, not only the rest pose.

## Facial hair

An identity layer, never part of the canonical head, never hiding a weak jaw.

- Growth regions: moustache (upper lip), chin and goatee, cheek and jaw, sideburns, neck; each style names its masses and the head sub-regions they cover.
- Modeled masses for the silhouette (broad low-poly clumps on the lower edge; the moustache distinct; a cheek line that follows the cheekbone, not a uniform outline); material or painted detail for stubble where modeling is not worth it.
- Deformation: rigid on `Head` while the face has no jaw; once the jaw exists (FACE-EXPRESSION-001), the beard follows the jaw's deformation (production practice binds a beard to a reduced copy of the face surface, so it moves with the skin rather than staying rigid ([attaching a beard to a face](https://www.3dfiggins.com/writeups/AttachBeard/))), and it is tested with jaw opening, mouth corners and cheek raise.
- Checks: points of a mass in the preserved mouth window, points that missed the head, mask holes no beard surface covers, the face checks unchanged.

## Hair

- Fitted after the head is resolved; the cranium never changes for a hairstyle.
- Separate the scalp cap / root region, the hairline (from forehead and temple landmarks), primary masses, secondary locks, correction geometry.
- Detect gaps, scalp penetration, collisions with brows and eyes, and (for long styles) merging with the neck and shoulders; Wolf's Ranger and Training are two configurations of the same hair system, never a copy edited by hand.
- Default studies are bald; a hairstyle appears only in a character's build.

## Gates

| Gate | Covers |
| --- | --- |
| A. Blender geometry and art | feature placement, head silhouette, hairline, beard and attachment fit, garment fit, coverage boundaries and exposed holes; front, side, rear, three-quarter, the match camera |
| B. Facial animation | expressions, eye behaviour, mask clearance, facial-hair deformation |
| C. Skeleton and animation | garment and hair deformation, coverage through combat poses and clips, export/import parity |

Automated checks catch missing mappings, incompatible layers, uncovered holes, invalid hidden regions and intersections; visual studies catch anatomy and silhouette. Neither replaces the other.

## What exists and what does not (verified 2026-11-02)

| In place | Not yet |
| --- | --- |
| `appearance.resolve`: the plan, ordering, `hides` / `preserves` / `hides_components`, margins, fingerprint | region-level masking of a lower garment by a higher one (the garment's own regions); the plan in the export manifest (F10) |
| `garments`: types `garment`, `hair`, `facial_hair`; `coverage.preserves`; `also_fitted`; head sub-regions (`parent`, `object`) | a calibrated cover reach per region |
| the foundation's regions (`male_base.foundation.v002.regions.json`): 19 body regions and 7 head sub-regions | ankle regions mirror-symmetric (v1's weights are not) |
| `facial_hair.build` and `mask_layer` in the `wolf` set | facial-hair deformation with a jaw; the pose-suite coverage check |
| `foundation.character_marks` with `face_refine` | archetype-driven feature resolution (the face-identity layer) |

The names `covers_body`, `covers_layers` and a separate visibility profile were planned vocabulary, never code: `coverage.hides`, `hides_components` and the plan's `visibility` are their implementation. There is one coverage system.

## What is source and what is evidence

| Committed | Iteration evidence only |
| --- | --- |
| definitions (`*.garment.json`, the character manifest), the foundation document, record, lock and regions | candidate meshes, renders, boards, per-run logs |
| the resolver, the builders, the coverage algorithms, the tests | review copies of a foundation or a character (`RIPOSTE_FOUNDATION_REVIEW`, `RIPOSTE_CHARACTER_REVIEW`) |
| approved fixtures the tests read | probe scripts, intermediate scenes |

Canonical geometry stays reproducible from committed source; an approval names the source revision, parameters, outputs and tests it was given.
