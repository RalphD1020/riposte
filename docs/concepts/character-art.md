# Character art

> See also: [spec/invariants.md](../../spec/invariants.md) — ART-HEAD-001, ART-HEAD-002, ART-LAYER-001, ART-CROWD-001, ART-CROWD-002, PRES-KIT-001
> See also: [docs/concepts/content.md](./content.md) — the character art file as content, [docs/concepts/presentation.md](./presentation.md) — kits and the match look, [docs/reference/assets.md](../reference/assets.md) — the asset build
> Source: `game/content/characters/*.character.json`, `tools/blender/character_art.py`, `tools/blender/bootstrap/build_wolf.py`

Riposte's people are built, not sculpted: a block body, a pentagonal face, and a faceted crown, with modeled pieces worn on top. Every fighter is authored as one `riposte.character_art` JSON file, and a code-built Blender script turns that file into the source scene the asset build exports. The JSON is the only author of the blocks; nobody hand-edits the GLB.

## The head and the face (ART-HEAD-001)

The face is a five-sided prism. One vertex points along the art frame's forward axis (`coordinate_frame.forward`, −Y in Blender), and that vertex is the face's centreline: the implicit nose. The eyes and brow sit across it as small dark blocks, and death swaps the eyes for an X while the brow stays. The crown continues that same polygon in a few shrinking rings to a small apex. The facets stay visible. It is not a smooth sphere and not a flat lid.

Wolf's numbers belong to Wolf. His face runs from 1.50 m to 1.75 m with a 0.125 m radius; his eyes sit at 1.635 m and his brow at 1.668 m. The jaw ring stays at that radius and the top of the face is `top_scale` 0.82, so the jaw is the wider ring. A separate crown continues that ring upward and a little toward the nape. The nose vertex is still the forward point, and the eye and brow boxes stay where they are. The crowd uses the same face and a shorter crown inside its own 0.25 m head, not Wolf's world coordinates. Copying those once put the crowd's eyes at mouth height.

A modeled nose or mouth is optional. It is never the fix for eyes or a brow in the wrong place.

## Hair frames the face, it never covers it (ART-HEAD-002)

Hair follows the crown: a cap of tapered clumps and, on the ranger, a sweep to the nape with uneven side locks. Training is a shorter crop and a smaller forelock, not the ranger shape reduced. A thick beard sits below the eye band as a mustache, two cheeks, and a jaw that tapers at the chin. None of it hangs in front of the eyes.

Each character authors where its face is, in terms of its own head:

```json
"face_clearance": {
  "head": "HeadSkin",
  "band": [0.46, 0.75],
  "width": 0.65,
  "reach": 0.04
}
```

`band` is the eye/brow band as fractions of the head's height, `width` its half-width as a fraction of the head's radius, and `reach` how far in metres the region extends in front of the nose. The region runs from the head's centre forward. `character_art.py` rejects the file if the region does not hold the eyes and brow, or if any `hair` or `clothes` part of any variant enters it. `pnpm lint` runs that check and a self-check proving a fringe over the eyes is rejected while temple hair passes.

The check catches a hairstyle that covers the face. It cannot tell you the face looks good, so a hairstyle change still needs a front, three-quarter and gameplay-camera capture (`capture_arena_look.gd -- --hair`).

## Painted base, modeled outer layer (ART-LAYER-001)

Two layers share one coordinate frame:

- **Base** — the block body and the head. Detail too thin to model belongs painted here: a hairline under the modeled cap, light scruff, cloth weave, stitching.
- **Modeled** — anything whose depth or silhouette reads at the match camera: hair volume and locks, collars, hems, cuffs, belts, bracers, armour.

Today the base is flat materials and vertex colors. The block helpers in `tools/blender/riposte_blocks.py` generate no UVs, so painted detail waits until one painted feature has gone through Blender, the GLB export, Godot import and a gameplay capture. Until then nothing is painted, and paint never stands in for a missing surface. Mail is a few broad bands, not a field of rings.

## Two costumes, one Wolf

The ranger and the training variant share the body, the belt, the boots, the weapon, and the small side-accent pieces. Side color stays on those pieces. Main is the ranger mesh: wool `#202428`, lower cloth `#303438`, leather `#3B3935`, steel `#73777A`, and one fur collar. Alternate is the training mesh: slate `#29343F`, blue-grey `#414E5A`, leather `#51483F`, and a pale trim `#A7A69E`. Neither wears a cloak or a mantle. Fight Setup chooses the mesh. Side does not recolor it. The JSON stores sRGB. `character_art.linear_color` is the only conversion into the linear material. Ranger hair is `#25282B`. Training hair is `#30343A`. Skin stays the sRGB of the face that was already shipping. Costume metal is the material `costume_metal`. The blade stays `steel`. A green contrast check is not a picture of the fight.

## The crowd (ART-CROWD-001, ART-CROWD-002)

Spectators are the same people with less detail: a block body, a pentagonal face and a short faceted crown near 0.125 m across and 0.25 m tall, on a simpler body than Wolf's, a hair dome rather than a slab, and eyes and brow at the same head fractions as Wolf's, seated on the head's front faces. `tools/blender/bootstrap/build_crowd.py` builds them. Every layer it exports shares the figure's origin, because the game draws each layer's bare mesh in a `MultiMesh`; a layer with its own origin drew every head inside its tunic once, leaving the eyes and hair floating. Which audience a stage seats is a `CrowdProfile` on its stage profile: The Arena's is the Roman crowd, and The End has none.

## The build

| Step                     | Command / file                                                                                                  |
| ------------------------ | --------------------------------------------------------------------------------------------------------------- |
| Author                   | `game/content/characters/wolf.character.json`                                                                   |
| Validate (lint)          | `tools/blender/character_art.py`                                                                                |
| Regenerate the source    | `blender --background --factory-startup --python tools/blender/bootstrap/build_wolf.py -- [--variant training]` |
| Export and validate GLBs | `pnpm game:assets` (`tools/blender/export_assets.py`, `validate_assets.py`)                                     |
| Capture the face         | `godot --path game -s res://tools/capture_arena_look.gd -- --hair`                                              |
