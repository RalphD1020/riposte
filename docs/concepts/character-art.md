# Character art

> See also: [spec/invariants.md](../../spec/invariants.md) — ART-HEAD-001, ART-HEAD-002, ART-LAYER-001, ART-CROWD-001, ART-CROWD-002, PRES-KIT-001
> See also: [docs/concepts/content.md](./content.md) — the character art file as content, [docs/concepts/presentation.md](./presentation.md) — kits and the match look, [docs/reference/assets.md](../reference/assets.md) — the asset build
> Source: `game/content/characters/*.character.json`, `tools/blender/character_art.py`, `tools/blender/character_build.py`, `tools/blender/bootstrap/build_wolf.py`, `tools/blender/bootstrap/build_crowd.py`

Riposte's people are a heroic body in World of Warcraft proportion, with chibi softness in the forms and a Hades read in the light, the materials, and the crowd. Chibi is not a larger head. The face opening is a soft pentagon on one rounded skull. The JSON file (`riposte.character_art` schema 2) is the blockout: landmarks, masses, and the parts `character_build.py` can emit. `build_wolf.py` skins that blockout to `WolfRig` and keeps the combat clips. `build_crowd.py` bakes a pose and joins material slots for section `MultiMesh`es. Neither file is a second character builder, and neither grows a new primitive to imitate a finished skull, ribcage, garment, or boot. The production fighter is one authored surface on that same rig, through the same export, after a gameplay capture accepts it. Until that capture, the blockout is what ships. Nobody hand-edits a GLB, and nobody copies a sculpt back into radii and calls it the same mesh.

`body` holds the landmarks the rig is derived from. `silhouette.masses` holds the chest, waist, neck, hand, and boot envelopes. A part names a mass with `mass`, and `character_art.compile` copies that mass onto the part before it resolves anchors. The builder never branches on which character it is. A part names an anchor (`on`, or `from` / `to` for a segment) instead of repeating a world position in a second script. `body_scale` is the physics scale on the same file. The mesh builder does not multiply by it, and changing a body dimension does not change reach, mass, or hitboxes. Left is +X in both documents, matching `coordinate_frame.left`.

| Anchor                                        | Derived from                                       | Used by                                                    |
| --------------------------------------------- | -------------------------------------------------- | ---------------------------------------------------------- |
| `head.base`                                   | `body.head_z`                                      | Head, crown, hair, beard, eyes, brow                       |
| `head.bone`                                   | `body.head_top`                                    | Fighter head-bone tip. The scalp volume hangs on `head.base` |
| `shoulder.L` / `R`, `elbow`, `wrist`, `grip`  | Shoulder, the guard arm chain, or a spectator pose | Arms, sleeves, hands                                       |
| `bracer`, `accent`                            | A fraction along elbow to wrist                    | Bracers                                                    |
| `hip`, `knee`, `shin`, `ankle`, `foot`, `toe` | Hip width and the foot's fore/aft rest             | Legs, trousers, boots                                      |
| `hips`, `spine`, `chest`, `neck`              | The fighter torso stations                         | The combat skeleton                                        |

A spectator pose (`seated`, `cheer`) replaces elbow, wrist, and the hand offset. The legs stay. The boot hangs on `foot`, the cuff on `cuff`, and the hand on `hand`. A clothing `shell` on a segment is a second segment of the same span, emitted by the compiler. A segment may name `joint_overlap` in metres along its own axis so the mesh passes the anchor and meets the next piece. The anchor stays the bone end. Wolf and the crowd use that same helper and their own overlap. The grip end of a hand does not overlap. Combat clips stay in `build_wolf.py`. Wolf's gambeson, belt, collar, and chest plate are still metres in that one file; they follow a torso anchor once they name one.

## The head and the face (ART-HEAD-001)

The face is a five-sided volume. One vertex points along the art frame's forward axis (`coordinate_frame.forward`, −Y in Blender), and that vertex is the face's centreline: the implicit nose. The eyes and brow sit across it as small dark blocks, and death swaps the eyes for an X while the brow stays. The cranium continues over the crown and the rear as one rounded-faceted skull. The facets stay visible. It is not a smooth sphere, and it is not a flat lid with a cap perched on it. Hair overlaps that skull. A spectator's bald head is the same construction, shorter and with fewer rings.

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

## Two costumes, one Wolf

The ranger and the training variant share the body, the belt, the boots, the weapon, `FurCollar`, and the small side-accent pieces. Side color stays on those pieces. Main is the ranger mesh: wool `#202428`, lower cloth `#303438`, leather `#3B3935`, steel `#73777A`, and the scarf in the dark fur. Alternate is the training mesh: slate `#29343F`, blue-grey `#414E5A`, leather `#51483F`, and the same scarf in a pale fur `#A7A69E`. The pale fur is that scarf's material. It is not a second garment, and there is no node named cloak or mantle. Fight Setup chooses the mesh. Side does not recolor it. The JSON stores sRGB. `character_art.linear_color` is the only conversion into the linear material. Ranger hair is `#25282B`. Training hair is `#30343A`. Skin stays the sRGB of the face that was already shipping. Costume metal is the material `costume_metal`. The blade stays `steel`. A green contrast check is not a picture of the fight.

## The crowd (ART-CROWD-001, ART-CROWD-002)

Spectators are authored in `spectator.character.json` and compiled with the same emitter as Wolf. The body is still the simpler tunic, not Wolf's armor, and its dimensions live on that file's `body`, not as a scaled Wolf. A bald seat shows the shared soft-pentagon crown. The other seats wear a thick cap, and a bun or a fringe adds one lock. A separate draw wears a modeled beard on the jaw. Eyes and brow are the only face blocks. `build_crowd.py` bakes `seated` or `cheer` and joins each material into one mesh. The crowd still draws those layers as section MultiMeshes. Every layer it exports shares the figure's origin, because the game draws each layer's bare mesh in a `MultiMesh`; a layer with its own origin drew every head inside its tunic once, leaving the eyes and hair floating. Which audience a stage seats is a `CrowdProfile` on its stage profile: The Arena's is the Roman crowd, and The End has none. A missing scene fails the profile check. `CrowdMeshes` still names a box when a lookup misses, and the tests reject that name.

## Names

A name is a contract only when something outside the blockout reads it.

The rig contract is the bone list and the rest metres in `wolf.rig-contract.json`. Clips, the grip, and `PRES-RIG` use those. An authored surface binds to them and does not rename them.

The face contract is the node-name prefixes `Eye`, `Brow`, and `DeadEye`. `FacePresentation` shows and hides by those prefixes. `SideAccent` is the export's side marker. Those stay when the body stops being prisms.

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
