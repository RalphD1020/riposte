# Authored assets — Blender and ElevenLabs

> See also: [docs/concepts/presentation.md](../concepts/presentation.md) — kits, skins, intro, feedback
> See also: [docs/reference/godot.md](./godot.md) — rig contract, `SwordRig3D`, IK
> See also: [spec/invariants.md](../../spec/invariants.md) — PRES-KIT-001, CONTENT-002, UX-001
> Source: `art-src/blender/`, `tools/blender/`, `tools/audio/`, `game/assets/`

Art and sound arrive through one path each, and nothing in either path can reach the simulation.

## Models (Blender)

```text
tools/blender/bootstrap/*.py   code-built first versions of each source (one-time)
        ↓
art-src/blender/**/*.blend     the sources — refine by hand or through Blender MCP
        ↓  pnpm game:assets   (tools/blender/export_assets.py, headless)
validate → export GLB → manifest
        ↓
game/assets/generated/**/*.glb  committed, so CI and the Web export never need Blender
        ↓
game/assets/presentation/**     thin wrapper .tscn + kit .tres (the only edit surface)
```

- `pnpm game:assets` resolves Blender from `BLENDER_BIN`, then `blender` on PATH. `--bootstrap` regenerates the sources from the bootstrap scripts first and **overwrites hand edits**; use it only to start over.
- Each export is validated before anything is written (`tools/blender/validate_assets.py`). A fighter needs the rig's bones, all six material slots (`fabric`, `leather`, `metal`, `hair`, `skin`, `side_accent`), every clip, rigid single-bone binding on every piece, at least one `SideAccent*` piece, a `Head`, feet on the floor, a height of 1.70–1.85 m, ≤ 2000 triangles, and `fabric` at ≥ 3:1 against the arena floor. A weapon needs `GripOffhand` (0.15 m), `GripDominant` (0.225 m), `TrailStart` (0.25 m), `TrailEnd` and `Tip` (1.22 m) down −Y and ≤ 400 triangles. The arena's `PlatformTop` must be exactly `platform_radius` with its top at 0.
- Those numbers restate the physical baseline. If one fails, the art drifted; the rules do not move to meet it.
- Axes: Blender is Z-up and fighters face −Y, which the glTF exporter turns into Godot +Z — the direction the proxy's `WeaponOrigin` points the blade at weapon angle 0.
- Wolf is built in layers (core torso, gambeson shell, belt, collar, bracers, boots, block hair), every piece its own solid bound rigidly to one bone. Clips animate only what expresses physical state — feet, hips, spine, chest, head. Arms are always two-hand IK to the simulation-posed sword while it is held; once a dropped sword leaves the hands the IK eases off and the arms keep their rest carriage.
- Clip hip offsets are written in armature space — X lateral, −Y forward, +Z up — and the bootstrap converts each into the bone's own rest frame before keying. Written raw, the vertical `Hips` bone (Y-up, Z-forward locally) swaps "sink" with "step back": that is how a death once lifted the body 0.35 m instead of dropping it 0.68 m. Rotations are already bone-local (+X pitches forward). Terminal clips (`death`, `death_stab`, `run_through`) are verified by render (`game/tools/capture_deaths.gd`), not only by the validator.
- The rig carries one unweighted bone for cinematics, `SwordMount`: head at the pommel, pointing down the blade, keyed as quaternions (the exporter reads only the rotation channels of a bone's own mode). Gameplay clips never key it; the victory clips (`victory_combo`, `victory_idle`) do, and the validator requires that. They start and end in the duel's resting guard (blade level, 45° right). Verified by render: `game/tools/capture_victory.gd` → `.reports/victory_<beat>.png`. The Godot side guards hip semantics too: PRES-KIT reads the exported `Hips` tracks and asserts each clip moves the hips the way its name says.
- A future ragdoll is **authored in Godot, not Blender**: Blender skeleton → imported `Skeleton3D` → Godot physical-skeleton authoring ("Create Physical Skeleton" on the `Skeleton3D`, which generates a `PhysicalBoneSimulator3D` with `PhysicalBone3D` children, then pruned to the bones that matter with hinge/cone joints tuned) → a ragdoll wrapper scene the death backend instances. Blender only supplies the bones and their proportions.
- The authored arena brings the platform, cliff, relief, and perimeter. The warning ring and home marks stay code-drawn from the rules (`ArenaScaffold`), so they cannot drift from the boundary and spawns they mark.

## Sound (ElevenLabs)

```text
ElevenLabs flow (sfx / tts nodes, several takes per family)
        ↓  node tools/audio/takes-from-status.mjs  (saved run status → fetch list)
        ↓  node tools/audio/fetch-takes.mjs        (signed URLs expire in 2 h — fetch right away)
game/assets/presentation/audio/<family>/*.mp3      committed takes
        ↓  godot --headless --path game -s res://tools/author_audio_kits.gd
kit .tres audio_cues (Array of takes), audio_layers, announcer, UI theme
```

- A family is a folder; each file is a take. `author_audio_kits.gd` writes them into the kits in file order, which is the order variant keys index into, so adding a take means dropping the file in and rerunning it.
- Takes are picked deterministically from the event (`CombatFeedbackDirector.variant_key`), so a replay sounds identical.
- Layers name cues that sound together from one event — a strong clash is transient + metal tail + low impact — rather than one pre-mixed file.
- Held cues (charge tension, bind grind, arena ambience) are imported with `loop=true` in their `.mp3.import`.
- Record dry. Web builds do not depend on runtime bus effects, so any room tone is in the take.
- Every announcer line has a caption; the intro reads with sound off (UX-001).
