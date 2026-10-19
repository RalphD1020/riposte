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
- Wolf's blocks, palette, display name, and `body_scale` are authored in `game/content/characters/wolf.character.json` (`riposte.character_art` v1). `tools/blender/bootstrap/build_wolf.py` builds from that file. `tools/blender/character_art.py` validates it, including the arm-chain endpoints and a required `Brow`. Ranger and Training are appearance variants. Dead eyes are parts with `"face": "dead"`. Their rotation is around Blender Y so the X sits in the face plane at the eyes.
- Wolf is built in layers (core torso, gambeson shell, belt, collar, bracers, boots, block hair), every piece its own solid bound rigidly to one bone. Clips animate only what expresses physical state — feet, hips, spine, chest, head. Arms are always two-hand IK to the simulation-posed sword while it is held; once a dropped sword leaves the hands the IK eases off and the arms keep their rest carriage.
- Clip hip offsets are written in armature space — X lateral, −Y forward, +Z up — and the bootstrap converts each into the bone's own rest frame before keying. Written raw, the vertical `Hips` bone (Y-up, Z-forward locally) swaps "sink" with "step back": that is how a death once lifted the body 0.35 m instead of dropping it 0.68 m. Rotations are already bone-local (+X pitches forward). Terminal clips (`death`, `death_stab`, `run_through`) are verified by render (`game/tools/capture_deaths.gd`), not only by the validator.
- The rig carries one unweighted bone for cinematics, `SwordMount`: head at the pommel, pointing down the blade, keyed as quaternions (the exporter reads only the rotation channels of a bone's own mode). Gameplay clips never key it; the victory clips (`victory_combo`, `victory_idle`) do, and the validator requires that. They start and end in the duel's resting guard (blade level, 45° right). Verified by render: `game/tools/capture_victory.gd` → `.reports/victory_<beat>.png`. The Godot side guards hip semantics too: PRES-KIT reads the exported `Hips` tracks and asserts each clip moves the hips the way its name says.
- A future ragdoll is **authored in Godot, not Blender**: Blender skeleton → imported `Skeleton3D` → Godot physical-skeleton authoring ("Create Physical Skeleton" on the `Skeleton3D`, which generates a `PhysicalBoneSimulator3D` with `PhysicalBone3D` children, then pruned to the bones that matter with hinge/cone joints tuned) → a ragdoll wrapper scene the death backend instances. Blender only supplies the bones and their proportions.
- The authored arena brings the combat disc: `PlatformTop` at `platform_radius`, the cliff, and the current ornamental perimeter. The warning ring and home marks stay code-drawn from the rules (`ArenaScaffold`), so they cannot drift from the boundary and spawns they mark. The replacement bowl is the elevated arcade and basin in [presentation](../concepts/presentation.md#hud-and-world). It is presentation mesh outside the disc. It does not move `PlatformTop` and it does not add a collider.

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
- Held cues (charge tension, bind grind, arena ambience, the menu theme, the arena theme, and the crowd bed) are imported with `loop=true` in their `.mp3.import`.
- `RiposteApp` plays one music loop: the arena kit's `PresentationKit.CUE_MUSIC` from match start through Results and the victory showcase, `MENU_LOOP` on a menu screen. A handoff mutes and stops the current voice, then starts the next stream on the following frame, because an MP3 `play()` stacks a voice. A missing arena stream stops the loop rather than keeping the menu theme. Same stream already playing does not restart. Crowd reactions are `CUE_CROWD_CHEER`, `CUE_CROWD_STRONG`, `CUE_CROWD_SETPOINT`, `CUE_CROWD_VICTORY`, and the looping `CUE_CROWD_BED` on that kit. `CrowdDirector` picks at most one of those shots per tick and latches a finish to the scoreline; `MatchPresenter` maps the short `CrowdDirector.CUE_*` name (`game/src/presentation/match/match_presenter.gd`) and rides the bed trim. The bed player is a child of that presenter and stops with it. `CUE_CROWD_GASP` is the committed-miss shot. `CUE_MATCH_HORN` is the arena's end-of-match horn (`sfx/arena/match_horn`), not a fighter cue. The take is one blast slowed so it lasts `AudioDirector.HORN_SECONDS` (6 s). It is not restarted. The deciding round's banner says `MATCH WON` or `MATCH LOST` from the human's side (`HudCopy`). Wolf's howl is `character_call`, played in the intro and the victory cinematic; the spoken name is `crowd_chant` and replaces the generic set-win cheer when the kit has one. `author_audio_kits.gd` writes `AudioKitPlan` (`game/tools/audio_kit_plan.gd`) onto the existing kits and leaves the intro, the mark, and the announcer captions in place. A file on disk is not a listening approval. The 500 KB integrity cap in `scripts/check-integrity.mjs` applies to every tracked file; it is not a Steam audio specification. The shipped menu and arena loops are 80 kb/s MP3 so they fit that cap. Godot can import Ogg Vorbis. That encode was not adopted here. The direwolf mark is drawn on the victory card.
- Record dry. Web builds do not depend on runtime bus effects, so any room tone is in the take.
- Every announcer line has a caption; the intro reads with sound off (UX-001).
