# Example: authored presentation kit

> See also: [docs/concepts/presentation.md](../docs/concepts/presentation.md), [docs/reference/godot.md](../docs/reference/godot.md) — the rig and animation contract
> Source: `game/src/presentation/kit/presentation_kit.gd`, `game/content/presentation/riposte_kits.gd`

Replace the duelist's primitive capsule with a Blender model, its animations, and a custom swing sound. One new kit file; no code changes (PRES-KIT-001).

## 1. Wrap the model

Import `duelist.glb` and save a wrapper scene `res://assets/presentation/fighters/duelist/duelist.tscn` whose tree contains:

- a `MeshInstance3D` named `Body` (tinted with the combatant color: listed in `color_targets`),
- an `AnimationPlayer` with clips such as `idle`, `walk`, `charge`, `swing`, `hit`, `stagger`, `death`.

Model faces local +Z (Godot's model front, the glTF convention) at the origin with feet on the ground; `visual_transform` corrects anything else. `ArenaTransform` turns gameplay headings into world yaw.

## 2. Author the kit at the identity's path

`RiposteKits.AUTHORED_KIT_PATHS` maps `fighter.duelist` to `res://assets/presentation/fighters/duelist/duelist_kit.tres`:

```ini
[gd_resource type="Resource" script_class="PresentationKit" load_steps=3 format=3]

[ext_resource type="Script" path="res://src/presentation/kit/presentation_kit.gd" id="1_kit"]
[ext_resource type="PackedScene" path="res://assets/presentation/fighters/duelist/duelist.tscn" id="2_model"]

[resource]
script = ExtResource("1_kit")
id = &"fighter.duelist"
primitive = &"FIGHTER"
scene = ExtResource("2_model")
color_targets = PackedStringArray("Body")
animation_clips = {
&"IDLE": &"idle",
&"MOVE": &"walk",
&"CHARGE": &"charge",
&"SWING": &"swing",
&"HIT": &"hit",
&"STAGGER": &"stagger",
&"DEATH": &"death"
}
```

Sounds work the same way on the weapon kit (`weapon.bastard_sword`): set `audio_cues` entries such as `&"swing"` or `&"blade.strong"` to imported streams. Missing cues stay silent; missing clips fall back to procedural primitive motion.

## 3. Verify

```bash
pnpm check   # the kit loads and every script still compiles
pnpm test    # PRES-KIT proves authored kits win and identities stay complete
```

Authored kits load first and the factory kit fills any gap, so you can replace one identity at a time.
