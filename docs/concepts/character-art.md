# Character art

> See also: [spec/invariants.md](../../spec/invariants.md) — ART-HEAD-001, ART-HEAD-002, ART-LAYER-001, ART-CROWD-001, ART-CROWD-002, PRES-KIT-001
> See also: [docs/concepts/content.md](./content.md) — the character art file as content, [docs/concepts/presentation.md](./presentation.md) — kits and the match look, [docs/reference/assets.md](../reference/assets.md) — the asset build
> Source: `game/content/characters/*.character.json`, `tools/blender/character_art.py`, `tools/blender/bootstrap/build_wolf.py`

Riposte's people are built, not sculpted: a LEGO-like block body and a pentagonal head, with modeled voxel pieces worn on top. Every fighter is authored as one `riposte.character_art` JSON file, and a code-built Blender script turns that file into the source scene the asset build exports. The JSON is the only author of the blocks; nobody hand-edits the GLB.

## The head and the face (ART-HEAD-001)

The head is a five-sided prism. One vertex points along the art frame's forward axis (`coordinate_frame.forward`, −Y in Blender), and that vertex is the face's centreline: the implicit nose. The eyes and brow sit across it as small dark voxel blocks, and death swaps the eyes for an X while the brow stays.

Wolf's numbers belong to Wolf. His head runs from 1.50 m to 1.75 m with a 0.125 m radius; his eyes sit at 1.635 m and his brow at 1.668 m. Another character with a taller or shorter head authors its own placement against its own head. No character copies another's world coordinates, which is what produced the crowd's low "mustache" faces.

A modeled nose or mouth is optional. It is never the fix for eyes or a brow in the wrong place.

## Hair frames the face, it never covers it (ART-HEAD-002)

Hair is a crown cap plus locks: a thin cap on the head, temples and side locks beside the face, a nape and rear masses behind it, and at most a short lock above the brow. None of it hangs in front of the eyes.

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

Today the base is flat materials and vertex colors. The block helpers in `tools/blender/riposte_blocks.py` generate no UVs, so painted detail waits until one painted feature has gone through Blender, the GLB export, Godot import and a gameplay capture. Until then nothing is painted, and paint never stands in for a missing surface.

## The crowd (ART-CROWD-001, ART-CROWD-002)

Spectators are the same people with less detail: a block body, a pentagonal head on its neck at Wolf's height-to-radius ratio, a hair cap, and eyes and brow at the same head fractions as Wolf's, seated on the head's front faces. `tools/blender/bootstrap/build_crowd.py` builds them. Every layer it exports shares the figure's origin, because the game draws each layer's bare mesh in a `MultiMesh`; a layer with its own origin drew every head inside its tunic once, leaving the eyes and hair floating. Which audience a stage seats is a `CrowdProfile` on its stage profile: The Arena's is the Roman crowd, and The End has none.

## The build

| Step                     | Command / file                                                                                                  |
| ------------------------ | --------------------------------------------------------------------------------------------------------------- |
| Author                   | `game/content/characters/wolf.character.json`                                                                   |
| Validate (lint)          | `tools/blender/character_art.py`                                                                                |
| Regenerate the source    | `blender --background --factory-startup --python tools/blender/bootstrap/build_wolf.py -- [--variant training]` |
| Export and validate GLBs | `pnpm game:assets` (`tools/blender/export_assets.py`, `validate_assets.py`)                                     |
| Capture the face         | `godot --path game -s res://tools/capture_arena_look.gd -- --hair`                                              |
