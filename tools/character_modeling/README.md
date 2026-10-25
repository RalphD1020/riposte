# Character modeling

Definitions for proportion studies and, later, an internal character creator. This folder does not build meshes and does not replace `tools/blender/bootstrap/build_wolf.py`.

A profile in `profiles/` names slider values. `character_modeling.resolve` checks those values and returns the widths a study or a future tool should build. `relaxed-a-pose` is the modeling pose. Wolf's combat rest pose stays on `game/content/characters/wolf.character.json`.

```text
python -c "import character_modeling; character_modeling.self_check()"
```

Run that from this directory. `pnpm lint` runs the same check.

The durable explanation is [docs/concepts/character-modeling.md](../../docs/concepts/character-modeling.md).
