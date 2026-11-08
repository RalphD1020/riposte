# Character art

> See also: [spec/invariants.md](../../spec/invariants.md) — ART-STYLE-001, ART-HEAD-001, ART-HEAD-002, ART-LAYER-001, ART-CROWD-001, ART-CROWD-002, PRES-KIT-001
> See also: [docs/concepts/content.md](./content.md) — the character art file as content, [docs/concepts/presentation.md](./presentation.md) — kits and the match look, [docs/reference/assets.md](../reference/assets.md) — the asset build
> Source: `game/content/characters/*.character.json`, `tools/blender/character_art.py`, `tools/blender/character_build.py`, `tools/blender/bootstrap/build_wolf.py`, `tools/blender/bootstrap/build_crowd.py`

Riposte's people are minimalist dark fantasy on powerful heroic physiques (an Olympic weightlifter by default — strong and explosive, not stocky bulk), presented with Hades II's light, materials, and crowd. Soft joins do not mean a larger head. The face opening is a soft pentagon on one rounded skull. The JSON file (`riposte.character_art` schema 2) is the blockout: landmarks, masses, and the parts `character_build.py` can emit. `build_wolf.py` skins that blockout to `WolfRig` and keeps the combat clips. `build_crowd.py` bakes a pose and joins material slots for section `MultiMesh`es. Neither file is a second character builder, and neither grows a new primitive to imitate a finished skull, ribcage, garment, or boot. The production fighter is one authored surface on that same rig, through the same export, after a gameplay capture accepts it. Until that capture, the blockout is what ships. Nobody hand-edits a GLB, and nobody copies a sculpt back into radii and calls it the same mesh.

## Art direction (ART-STYLE-001)

Minimalist dark fantasy: stylized, sculpted, intentional character art with restrained detail and a strong identity — Hades II's character design, silhouettes and material language with Soulstone Survivors' readable silhouettes and material discipline, on powerful heroic physiques. It applies to fighters, the crowd, materials, lighting, and stages.

The references have one job each, and none of them sets head-to-body proportion by itself:

| Reference                   | Its job                                                                                                         | Not its job                                         |
| --------------------------- | --------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| All Might (My Hero Academia) | Primary physique and masculine anatomy: heroic silhouette, jaw, cheekbones, brow musculature, neck into trapezius | His measurements (2.20 m) or his caricature         |
| Dark-fantasy action RPGs    | World and material language: restrained colour, ruggedness, functional layering, weathered materials            | Realistic human anatomy                             |
| Fire Emblem (3D)            | Construction of a stylized anime head: simplified planes, readable features, clean three-quarter transitions     | Physique, slender proportions, a softer jaw         |

"Anime" means the facial design, not a slender figure: never a smaller body under a larger skull, larger eyes or a softer jaw. The head is a proportionate rounded cranium carrying a substantial masculine facial mask, designed around the locked eyes and brows, measured at the 1.80 m reference and verified across the sweep. Lean (ectomorphic, visibly athletic), reference (a balanced Olympic weightlifter) and strongman (heavier frame, thick forearms, calves and neck, definition kept) are one heroic language. Keep one body reference board and a separate head and face board, so a request about the face is never read as a request about the physique.

**Low-poly is not a requirement; minimalism is.** Treating low-poly construction as the art direction restricted the hair and clothing to assembled primitives — the hair read as chunky dreadlocks. Low-poly is now a characteristic of one part of the character, the face, not a rule for the whole.

| Area        | Standard                                                                                                                                           |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| Face        | The approved geometric design: a flat, panel-based mask, the long flat-bridged angular nose, hooded angular eyes and brows — iconic and minimalist |
| Body        | The accepted male base and its configurations                                                                                                      |
| Hair        | Sculpted, flowing, layered, recognizable as actual hair                                                                                            |
| Clothing    | Tailored, fitted to the anatomy, with intentional folds and material transitions                                                                   |
| Armor       | Sculpted protective forms, a restrained silhouette, never primitive blocks                                                                         |
| Weapons     | Recognizable historical silhouettes with stylized craftsmanship                                                                                    |
| Materials   | Strong material identity in restrained palettes, without heavy textures                                                                            |
| Geometry    | Topology appropriate to the art; smooth curves, bevels and subdivision where they serve it                                                         |
| Performance | Mobile-first budgets measured per asset; a triangle count is never a proxy for quality                                                             |
| Physics     | Completely independent of visual geometry                                                                                                          |

The authored body is sculpted silhouettes, heroic action-figure anatomy, restrained surface detail, and Hades II's painterly light. Neither reference is a claim that its models are this game's. Detail concentrates at identity features rather than spreading evenly, and it never means a figure assembled from blocks. Smooth means the chest, waist, pelvis, deltoid, and thigh change into each other on purpose. A planned facet, such as the cranium, can stay. An accidental ridge, gap, or primitive intersection cannot.

The blockout named through the rest of this page is the placeholder that still ships. The word is the mesh in `wolf.character.json`, not a block-built style. Earlier proportion notes stay as history. They do not set the look. A study may close overlapping volumes with a remesh. That remesh is not the art direction and not the mesh that gets skinned. The gameplay capture on `WolfRig` remains the gate. A green height or triangle check is not that picture.

`body` holds the landmarks the rig is derived from. `silhouette.masses` holds the chest, waist, neck, hand, and boot envelopes. A part names a mass with `mass`, and `character_art.compile` copies that mass onto the part before it resolves anchors. The builder never branches on which character it is. A part names an anchor (`on`, or `from` / `to` for a segment) instead of repeating a world position in a second script. `body_scale` is the physics scale on the same file. The mesh builder does not multiply by it, and changing a body dimension does not change reach, mass, or hitboxes. Left is +X in both documents, matching `coordinate_frame.left`.

| Anchor                                        | Derived from                                       | Used by                                                      |
| --------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------ |
| `head.base`                                   | `body.head_z`                                      | Head, crown, hair, beard, eyes, brow                         |
| `head.bone`                                   | `body.head_top`                                    | Fighter head-bone tip. The scalp volume hangs on `head.base` |
| `shoulder.L` / `R`, `elbow`, `wrist`, `grip`  | Shoulder, the guard arm chain, or a spectator pose | Arms, sleeves, hands                                         |
| `bracer`, `accent`                            | A fraction along elbow to wrist                    | Bracers                                                      |
| `hip`, `knee`, `shin`, `ankle`, `foot`, `toe` | Hip width and the foot's fore/aft rest             | Legs, trousers, boots                                        |
| `hips`, `spine`, `chest`, `neck`              | The fighter torso stations                         | The combat skeleton                                          |

A spectator pose (`seated`, `cheer`) replaces elbow, wrist, and the hand offset. The legs stay. The boot hangs on `foot`, the cuff on `cuff`, and the hand on `hand`. A clothing `shell` on a segment is a second segment of the same span, emitted by the compiler. A segment may name `joint_overlap` in metres along its own axis so the mesh passes the anchor and meets the next piece. The anchor stays the bone end. Wolf and the crowd use that same helper and their own overlap. The grip end of a hand does not overlap. Combat clips stay in `build_wolf.py`. Wolf's gambeson, belt, collar, and chest plate are still metres in that one file; they follow a torso anchor once they name one.

## The head and the face (ART-HEAD-001)

The face is a five-sided volume. One vertex points along the art frame's forward axis (`coordinate_frame.forward`, −Y in Blender), and that vertex is the face's centreline: the implicit nose. The eyes and brow sit across it as small dark marks, and death swaps the eyes for an X while the brow stays. The cranium continues over the crown and the rear as one rounded-faceted skull. The facets stay visible. It is not a smooth sphere, and it is not a flat lid with a cap perched on it. Hair overlaps that skull. A spectator's bald head is the same construction, shorter and with fewer rings.

Wolf's metres belong in `wolf.character.json`, not in this page. Head size follows the heroic body. There is no enlarged-head band and no head-count to hit. The rejected builds were the ~0.40 m mascot head and the later ~0.33 m study head; both sat on a Head bone that is 0.295 m (`head_z` 1.505 to `head_top` 1.80) and swung with that bone. A gameplay capture accepts the next skull. The eyes and the brow are placed on that skull. The crowd uses the same face construction inside its own head, not Wolf's world coordinates. Copying those once put the crowd's eyes at mouth height. The crowd keeps its own dimensions and a lower detail budget.

Eyes and the brow are the only modeled marks on the face. A nostril, a lip, or a mouth is paint. Wolf's stubble mask is off while the hair is being rebuilt, so the face is the skin color alone. When stubble comes back it is paint on `HeadSkin` alone, a small opaque mask multiplied by the skin color. A full beard is a later jaw attachment, chosen apart from the scalp hairstyle, and is not in this fighter.

## Hair frames the face, it never covers it (ART-HEAD-002)

A fighter hairstyle starts with `ScalpDome`, the rounded crown on the five-sided face. The same helper can wear skin on a bald head. On Wolf it wears the hair color. Both skins share that dome and the body. Ranger's hair is a swept crown, temples, and a bun that continues the crown (`HairBun`). Training's hair is a front sweep and broad masses that reach the shoulders (`HairRear`, `HairLock`). They are different geometry. The collar is one mesh; training's pale fur is that collar's material. Hair stays out of the eye band. The check requires the dome to cover the skull, to continue over the crown, to close on a face rather than a point, and for each lock to meet the dome. A picture is still required. A bald crowd seat wears the same kind of crown at crowd size. Whether a frame reads as hair is decided at the match camera.

Each character authors where its face is, in terms of its own head:

```json
"face_clearance": {
  "head": "HeadSkin",
  "band": [0.4, 0.74],
  "width": 0.65,
  "reach": 0.04
}
```

`band` is the eye/brow band as fractions of the head's height, `width` its half-width as a fraction of the head's radius, and `reach` how far in metres the region extends in front of the nose. The region runs from the head's centre forward. `character_art.py` rejects the file if the region does not hold the eyes and brow, or if any `hair` or `clothes` part of any variant enters it. `pnpm lint` runs that check and a self-check proving a fringe over the eyes is rejected while temple hair passes.

The check catches a hairstyle that covers the face. It cannot tell you the face looks good, so a hairstyle change still needs a front, side, rear, three-quarter, and gameplay-camera capture (`capture_arena_look.gd -- --hair`).

## Painted base, modeled outer layer (ART-LAYER-001)

Two layers share one coordinate frame:

- **Base** — the block body and the head. Detail too thin to model belongs painted here: a hairline under the modeled cap, light scruff, cloth weave, stitching.
- **Modeled** — anything whose depth or silhouette reads at the match camera: hair volume and locks, the scarf, hems, cuffs, belts, bracers, armour. An outer piece encloses the body under it.

A garment, the material on it, and the draw batch are three different facts. `wear` and `slot` only name the material. The crowd joiner welds a slot into one mesh so a `MultiMesh` can draw it. That weld is not a layer order, and a shared radius is not coverage. Coverage is the outer surface enclosing the body under it at rest and in the poses that piece is worn through.

Tight cloth and stubble are paint. Outerwear is a volume that stands off the body: the gambeson, a leather chest that follows the torso, sleeves, bracers, the belt, and `FurCollar`. `FurCollar` is the scarf. There is no second cloak beside it. The torso showing through that scarf is a coverage failure of the one piece, not a missing material. A closed scarf encloses the torso. Two prisms on the same centre, with the outer one thinner along any axis, do not count. A thin metal stripe is not a layer. `HeadSkin` is the only mesh allowed to carry UVs, and only when it wears the stubble mask. It wears none right now. Nothing else is required to carry them. Paint never stands in for a missing surface. Mail is a few broad bands, not a field of rings.

## The mask is the face (FACE-IDENTITY-001)

The face is a designed mask whose surfaces happen to communicate heroic anatomy, not a miniature human anatomy project. The original approved panel mask is the master: every candidate is composed on it (never on the previous study) and judged against it. The two broad panels meet at the centre, the profile is convex, the nose is its highest forward point, and the silhouette stays simple. The features are changes in the panels' curvature:

| Feature    | Construction                                                                 | Avoid                                  |
| ---------- | ---------------------------------------------------------------------------- | -------------------------------------- |
| Brow ridge | A raised section of the upper panel, a shelf over the eye opening            | Separate human brow bones              |
| Eyes       | Recessed openings beneath the shelf, slightly hooded by the upper panel      | Deep human eye sockets                 |
| Cheekbones | Broad convex changes in the panel                                            | Bulging cheek pads                     |
| Nose       | The panels converging into a long flat rectangular bridge and an angular tip | A rounded human nose, nostrils, septum |
| Chin       | A controlled convex lower panel                                              | Creases and wrinkles                   |
| Forehead   | One broad continuous surface converging into the bridge                      | Forehead anatomy                       |

Edges are not all equally sharp: the nose's silhouette (tip, underside) is the sharpest; transitions within the broader face are soft. Three layers stay separate — the mask (identity), the sculpted features on it, and fitted components (eyes, lids, brows; FACE-MAPPING-001). Every revision is compared with the approved face (`HeadV2`) and its approval captures with the approved Ranger and Training hair; review covers front, side, three-quarter, top, bottom and the gameplay camera. If the face reads as an ordinary human face from three-quarter, it has drifted, however good the features look.

## A shared visual grammar, individual heads (CHARACTER-CONSISTENCY-001)

Every character shares the Riposte signature — the panel face, its cheekbones, the flat-bridged angular nose, angular eyes and expressive brows — and none shares Wolf's proportions by default. The head separates identity (who the character is) from morphology (how his head belongs to his body), so the roster avoids same-head syndrome without random heads (HEAD-IDENTITY-001, HEAD-MORPH-001). The face is one continuous surface with authored plane changes: brow ridge, recessed orbits under a lid fold, cheekbones that give the face its width, a long angular nose — a broad flat rectangular bridge plane carried to a projecting angular tip, with no central nose ridge — that gives it its depth and stays its forward-most point, lower cheeks into the jaw (FACE-PLANAR-001, FACE-SILHOUETTE-001). It stays the most geometric part of the character; the cranium, temples, jaw corners, ears and neck are organic — that contrast is part of the identity. Three consistencies are reviewed at the gameplay camera, in grayscale and in motion: one world, one coherent individual, distinguishable characters.

## Character surface integration (ART-SURFACE-001)

A character is a coordinated system of anatomical and visual surfaces, not meshes that happen to share a skeleton. A hairstyle can be finished as geometry while its integration with the body is not: hair is part of the character's anatomical and costume silhouette, not an accessory parked on the head. The goal is not to make every surface touch — hair has volume, garments have thickness, and some separation is deliberate — but to remove accidental floating, intersections, abrupt transitions and disconnected silhouettes.

| Component      | Authority                                                          |
| -------------- | ------------------------------------------------------------------ |
| Base body      | Anatomy and physique                                               |
| Face           | Stylized facial identity                                           |
| Hair           | Scalp attachment, hairstyle silhouette and independent deformation |
| Clothing       | Garment construction, thickness and body-relative fit              |
| Assembly       | Layer ordering, compatibility and final integration                |
| CharacterArtQA | Cross-component validation                                         |

Every hair definition declares, region by region, how it meets the body (`surfaces.relationships` in `art-src/blender/garments/*.garment.json`):

| Relationship | Expected result                                                                                              |
| ------------ | ------------------------------------------------------------------------------------------------------------ |
| `attach`     | Roots and bun integrated with the scalp; the scalp cap disappears beneath the hairstyle.                     |
| `clearance`  | Outside the region, with no penetration.                                                                     |
| `drape`      | Rests along the region's contour with its own volume, and follows it where it narrows (occiput, nape, neck). |

Hanging hair follows the occipital contour, narrows into the nape, follows the neck and is carried outward where the body widens. It is never pushed back off the body to avoid penetration — that is the floating column. Where a joint compresses (the nape crease when the head tilts), the hair keeps a little more clearance there, not everywhere. An animation that sweeps an arm through the head's volume is an animation defect recorded against the animation, never fixed by distorting correct hair.

Hair deforms on its own terms: the scalp, tied hair and bun are rigid on the head; hanging hair blends from the head into the weights of the body surface it rests on (the jaw is head, the nape skin mostly head, the trapezius neck and chest), smoothed along the hair so neighbouring locks never jump. It never depends on a garment's geometry or weights; a gambeson or mantle is an additional surface the assembled character is validated against, which keeps outfits modular. No runtime cloth, hair simulation or collision is needed — authored meshes, skeletal deformation, static spatial analysis and the animation envelope.

**Regions are anatomical, not vertex lists.** `art-src/blender/characters/male_base.surfaces.json` names the scalp, occiput, temple, jaw, nape, side of the neck, throat, trapezius, collar and upper back as bands along WolfRig's bones and sectors of azimuth round its vertical axis. A point is classified by spatial query, so the same declaration serves every physique, a future female base on the same rig, and every hairstyle and garment; the topology fingerprint stays what it was, asset compatibility.

**Findings come in three severities.** Hard: face penetration, disconnected roots, severe intersections. Warning: calibrated excessive separation, unnatural nape curvature. Advisory: layering and transitions for a person to look at — including a declaration that measures nothing (hair declared to drape a region it never reaches). Nothing invents a universal threshold. `male_base.surface_calibration.json` holds each bound with the approved asset it was measured on; a metric without one is reported as a measurement and never flags. One rule holds at any scale and needs no calibration: a lock that moves away from the body where the body narrows is a column. Nape conformity is measured as `follow`, the share of the body's narrowing a lock also makes (1 hugs the contour, 0 is a vertical panel, negative a column), with the gap it leaves in the hollow.

The audit (`tools/blender/inspect/garment_audit.py`) measures the declarations at rest and attributes every animation-envelope failure to the anatomical region it touched; the pure judgement is `character_modeling.surface_integration`. Not measured yet: silhouette continuity, and garment intersection and layer ordering (no garment surfaces are assembled yet; a relationship's `source` already names a garment).

## Two costumes, one Wolf

**Wolf 1.0 on the male base (production; the blockout below still ships until it is approved).** Wolf is the male base in its `default` configuration (1.80 m, 80 kg, scale 1.0, WolfRig) plus his identity and his equipment, all authored in Blender. His identity standard, the art profile in his manifest and the master prompt are in [docs/reference/blender-mcp-character-art-direction.md](../reference/blender-mcp-character-art-direction.md); hair and garment construction in [docs/reference/blender-mcp-hair-clothing-production.md](../reference/blender-mcp-hair-clothing-production.md). Ranger and Training are two presentations of one character, not two characters: one manifest gives them the same base, configuration, face, WolfRig, skin and hair colour, scale, mass, clips and weapon attachment, and the assembly refuses a costume palette that recolors `skin` or `hair`. Heroism comes from silhouette and costume design, never from inflated anatomy: three masses — a heroic upper body the base already supplies, a designed shoulder-and-torso silhouette, and a grounded lower body (belt, a few hanging panels, tapered trousers, substantial boots) — read at the match camera before any material does. The face keeps its vocabulary: two dark eyes and two brows lying on the flat panels on either side of the raised ridge, the pointed nose, the dead-eye X — designed angular features (almond-pentagon eyes, tapered brows heavier at the inner end, tapered X bars), never boxes; expression comes from brow angle, eye spacing and head orientation, and both skins share one head-relative landmark set. Ranger (the adventurer): neat, tightly tied hair with a compact bun and no loose locks, a fitted charcoal gambeson, a leather chest reinforcement, the signature leather shoulder mantle (two or three angular planes over the trapezius and deltoid, a slight overlap onto the upper arm, a raised outer edge, one fastening, asymmetric emphasis — a mantle, never a pauldron), a restrained fur collar, belt, pouch, panels, bracers, boots. Training (the duelist): half-up shoulder-length hair (the upper hair swept back into a small tied knot, layered side locks and a rear mass beneath) on the same scalp foundation, a padded training jacket in broad quilting planes, a soft padded collar, cloth wraps, a simple belt and short tabs, practice trousers, lighter boots — no mantle, no fur — showing more of the anatomy. Materials separate in value: charcoal wool darkest, leather warmer and lighter, the mantle its own leather value, fur with lighter planes, steel and bronze brighter than any cloth, skin distinct from clothing. `skin` and `hair` belong to Wolf; the rest belong to the costume, and only costume slots take mirror-match alternates.

The blockout ranger and training variant share the body, the belt, the boots, the weapon, `FurCollar`, and the small side-accent pieces. Side color stays on those pieces. Main is the ranger mesh: wool `#202428`, lower cloth `#303438`, leather `#3B3935`, steel `#73777A`, and the scarf in the dark fur. Alternate is the training mesh: slate `#29343F`, blue-grey `#414E5A`, leather `#51483F`, and the same scarf in a pale fur `#A7A69E`. The pale fur is that scarf's material. It is not a second garment, and there is no node named cloak or mantle. Fight Setup chooses the mesh. Side does not recolor it. The JSON stores sRGB. `character_art.linear_color` is the only conversion into the linear material. Ranger hair is `#25282B`. Training hair is `#30343A`. Skin stays the sRGB of the face that was already shipping. Costume metal is the material `costume_metal`. The blade stays `steel`. A green contrast check is not a picture of the fight.

## The crowd (ART-CROWD-001, ART-CROWD-002)

Spectators are authored in `spectator.character.json` and compiled with the same emitter as Wolf. The body is still the simpler tunic, not Wolf's armor, and its dimensions live on that file's `body`, not as a scaled Wolf. A bald seat shows the shared soft-pentagon crown. The other seats wear a thick cap, and a bun or a fringe adds one lock. A separate draw wears a modeled beard on the jaw. Eyes and brow are the only modeled face marks. `build_crowd.py` bakes `seated` or `cheer` and joins each material into one mesh. The crowd still draws those layers as section MultiMeshes. Every layer it exports shares the figure's origin, because the game draws each layer's bare mesh in a `MultiMesh`; a layer with its own origin drew every head inside its tunic once, leaving the eyes and hair floating. Which audience a stage seats is a `CrowdProfile` on its stage profile: The Arena's is the Roman crowd, and The End has none. A missing scene fails the profile check. `CrowdMeshes` still names a box when a lookup misses, and the tests reject that name.

## Names

A name is a contract only when something outside the blockout reads it.

The rig contract is the bone list and the rest metres in `wolf.rig-contract.json`. Clips, the grip, and `PRES-RIG` use those. An authored surface binds to them and does not rename them.

The face contract is the node-name prefixes `Eye`, `Brow`, and `DeadEye`, and on `Eye` and `Brow` one blend shape per shared moving expression (FACE-EXPRESSION-001). `FacePresentation` shows an expression by those prefixes and shape names. `SideAccent` is the export's side marker. Those stay when the body stops being prisms.

`HeadSkin`, `ScalpDome`, `TorsoCore`, `GambesonShell`, `FurCollar`, `ChestLayer`, and `ShoulderMass` are blockout part names. The shipping tests look them up because that is the mesh that ships today. They are not the authored surface's anatomy. When a capture replaces a part, the test keeps the fact it was protecting — the scarf still covers the chest, the face still has no stubble mask, the fighter still has no second cloak — and drops the prism's name.

## How a look is accepted

The blockout ships until a person accepts a gameplay-camera capture of an authored fighter on `WolfRig`. `build_wolf.py` rebuilds the blockout blend from the JSON, headless, and `pnpm game:assets` exports the GLB. Godot reimports that file. `capture_arena_look.gd` is the review: front, side, three-quarter, and the gameplay camera, both skins, same framing each time. A live Blender session can inspect a disposable study. It is not a second builder, and `build_wolf.py` must not be aimed at that session: it resets the scene. A study that wins is kept as its own file and integrated on purpose. A height check, a triangle check, or a closed mesh is not that picture.

## The build

| Step                     | Command / file                                                                                                  |
| ------------------------ | --------------------------------------------------------------------------------------------------------------- |
| Author                   | `game/content/characters/*.character.json`                                                                      |
| Validate (lint)          | `tools/blender/character_art.py`                                                                                |
| Regenerate the source    | `blender --background --factory-startup --python tools/blender/bootstrap/build_wolf.py -- [--variant training]` |
| Export and validate GLBs | `pnpm game:assets` (`tools/blender/export_assets.py`, `validate_assets.py`)                                     |
| Capture the face         | `godot --path game -s res://tools/capture_arena_look.gd -- --hair`                                              |

That table is the blockout. An accepted authored fighter is a separate blend on `WolfRig`, exported by the same check, and it does not replace this table until a gameplay capture says so.

Proportion studies and a future creator read [character-modeling.md](./character-modeling.md). Those profiles do not move this rig, and they do not replace the blockout.
