# Godot Conventions

> See also: [README.md](../../README.md), [docs/architecture/monorepo.md](../architecture/monorepo.md)
> See also: [docs/concepts/simulation.md](../concepts/simulation.md), [docs/concepts/presentation.md](../concepts/presentation.md)
> See also: [spec/invariants.md](../../spec/invariants.md) — WEB-001, WEB-003, WEB-004, PRES-KIT-001, SIM-MATH-001, ZERO-TOLERANCE-001
> Source: `game/project.godot`, `game/scripts/lint.mjs`

## Version and renderer

Godot **4.7.2-stable** (`GODOT_BIN` or `godot` on PATH). Compatibility (`gl_compatibility`) everywhere (WEB-001); single-threaded Web export with desktop and mobile VRAM compression (WEB-003).

## Project structure

```text
game/
├── project.godot            warnings=2 (errors), input map, 1280×720 canvas_items/expand
├── default_bus_layout.tres  audio buses: Music, SFX, Voice, Crowd → Master; Combat, UI → SFX (names: AudioBuses)
├── export_presets.cfg       committed Web preset (safe-area + theme-color head include)
├── src/
│   ├── domain/              deterministic simulation (no engine types)
│   ├── application/         sessions, controllers, CPU, clock, input, settings, app shell
│   ├── presentation/        theme, kits, snapshots, proxies, camera, VFX/audio, HUD, touch
│   └── main/                main.tscn + RiposteMain (scene entry)
├── content/                 content ids, rules, presentation kits, procedural audio
├── tests/                   harness + domain / application / presentation suites
├── tools/                   check_scripts.gd (typecheck)
└── scripts/                 Node: godot runner, lint, export/serve, templates, tool tests
```

## Layering (lint-enforced)

- `src/domain`, `content/rules`: no scene types, no engine vectors or singletons, `SimMath` not libm, `SeededRng` only, no print/signals/await, and no application or presentation class names (SIM-001, SIM-MATH-001, SIM-RNG-001).
- `src/presentation`: never names an application class or content identity; drives nothing (PRES-001).
- Layer bans are derived from each layer's `class_name`s, so new classes are covered automatically.
- Everywhere in `src`: no global randomness, no release `assert()`, no `OS.has_feature("mobile")`.
- `src` and `tests`: DuelEvent payloads are read and written through `DuelEventKeys`, never string literals.
- Rules marked `strings: true` see string literals; comments are always ignored.

## Centralized names

One home per vocabulary; never retype a literal:

| Vocabulary                                    | Home                                                                                      |
| --------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Event names / payload keys                    | `DuelEventTypes` / `DuelEventKeys`                                                        |
| Match reasons, outcome slots, contact classes | `MatchPhase` (`REASON_*`, `NO_WINNER`, `DRAW`, `is_combatant`); `ContactResolver.CLASS_*` |
| Input actions (match `project.godot [input]`) | `InputActions`                                                                            |
| Product events / property keys                | `ProductEvents` / `ProductEvents.PROP_*`                                                  |
| Audio buses                                   | `AudioBuses` (+ `default_bus_layout.tres`)                                                |
| Crowd reaction / kit cue names                | `CrowdDirector.CUE_*` → `PresentationKit.CUE_CROWD_*`                                     |
| Contact-kind labels                           | `StrikeResult.KIND_SLASH` / `KIND_POKE` / `KIND_THRUST` / `KIND_GRAZE`                    |
| Menu music path and loop trim                 | `RiposteApp.MENU_LOOP`, `LOOP_VOLUME_DB`, `LOOP_CUT_DB`                                   |
| Friend-match wire                             | `MatchNote.KIND_*`, `SLOT_NONE`, `ACCEPT_WINDOW`                                          |
| Settings file layout                          | `PlayerSettings.SECTION_*` / `KEY_*`                                                      |
| Replay serialization                          | `ReplayRecord.KEY_*`                                                                      |
| Styles, sizes, colors                         | `RiposteTheme` tokens and type variations                                                 |
| Copy                                          | `AppCopy` (menus), `HudCopy` (HUD)                                                        |
| Content identities                            | `ContentIds`                                                                              |
| Platform / display feature strings            | `Platform` (`is_web()`, `is_headless()`)                                                  |
| Browser safe-area JSON contract               | `SafeArea.WEB_PROPERTY` / `KEY_*` / `KEYS`                                                |

Two of these cross a boundary no compiler checks, so both are gated by tests instead:

- `SafeArea`'s global name and inset keys must match hand-written JavaScript in `export_presets.cfg`'s head include. A rename there does not error — it silently reports a zero inset and puts the HUD under a phone notch. `APP-SHELL` asserts the preset publishes exactly `SafeArea.KEYS` and the global `SafeArea` evaluates.
- The export shell's loading CSS paints the first thing a player on `/play` ever sees, before any of this code exists. It is the one surface the theme cannot reach at runtime, so `PRES-THEME` asserts those colors are `RiposteTheme.STEEL_900` and `TEXT_ON_DARK` and that the pair still passes contrast.

`Platform` is deliberately thin. Touch layout is `DisplayServer.is_touchscreen_available()`, not a platform guess, and `OS.has_feature("mobile")` is false in a browser and lint-rejected; if a web-mobile branch ever becomes necessary, `web_android` / `web_ios` belong in `Platform` beside the rest.

## GDScript

- Typed everywhere (`untyped_declaration` is an error). Zero `@warning_ignore` (ZERO-TOLERANCE-001).
- Shadowing is an error: locals and loop variables must not reuse member, method, or global names (`trail`/`trail()`, `pips`/`pips()`, `OK`).
- No `uid=` in hand-written `.tscn` headers.
- Accessibility (4.7): `accessibility_name`, `accessibility_description`, and `accessibility_live = AccessibilityServer.LIVE_POLITE`.
- Static caches (`HudIcons`, `PlaceholderAudio`, `RiposteTheme.display_font`) build once on first use.
- UI styling: pick a `RiposteTheme` type variation; `add_theme_*_override` is only for runtime values (safe-area margins via `RiposteTheme.apply_insets`).
- Tunables are named constants at the top of the file that owns them (gameplay values in `game/content/rules/`; per-identity feel in kits; generic feel in the presenter / directors).
- Nodes in the tree `queue_free`; swap screens with `remove_child` + `queue_free` so `_exit_tree` teardown runs first. Never free a button inside its own signal (defer the page swap).

## Animation and rigs

Authored art arrives as a `PresentationKit.scene` and nothing else moves (PRES-KIT-001). The proxy either builds its primitive or instantiates the kit scene, so the boundary is a handful of names rather than a code path:

| The kit provides                    | The proxy does                                                                    |
| ----------------------------------- | --------------------------------------------------------------------------------- |
| `scene`                             | Instantiates it under `VisualRoot`; the primitive body is not built               |
| `visual_transform`                  | Applied to `VisualRoot` — the one place to correct an exporter's scale or up-axis |
| `color_targets`                     | Finds each named `MeshInstance3D` and gives it the combatant color, once at build |
| `animation_clips` (semantic → clip) | Plays the mapped clip on a descendant named `AnimationPlayer`                     |

Node contract: the root carries the ground pose and yaw, `VisualRoot` carries the kit transform and procedural motion, and `WeaponOrigin` hangs under `VisualRoot` at the kit's `blade_height`: the authoritative planar sword, at the domain pommel on the stretched orbit and yawed by the gameplay weapon angle (`WeaponKinematics` at the interpolated angle). `Shadow` and `ChargeRing` stay on the ground outside `VisualRoot` so a death tilt does not tip them. An authored character scene supplies the **body**; the blade stays the proxy's — drawn from the `SwordCarriage` node, which shares `WeaponOrigin`'s carriage and yaw and adds only the lift from `CombatPresentationField` (PRES-CARRIAGE-001, WEAPON-ORBIT-005) — because `blade_points()` (displayed) and `authoritative_blade_points()` (`WeaponOrigin`'s) are what trails, sparks, and the debug vectors read, and a second blade owned by the model would be a blade the game cannot see.

Rules for anything authored later:

- **An `AnimationPlayer` stores clips; an `AnimationTree` controls blending.** Both belong _inside_ the authored scene, not in `src/presentation`. The kit keeps naming clips by semantic (the PRES-KIT-001 list in `PresentationKit.ANIM_SEMANTICS`; `FighterAnimationSelector` picks one per frame from phase, burst kind, and carried velocity in the body's own frame); if a rig wants a locomotion `BlendSpace2D`, a body `StateMachine`, and one-shots for bursts, that graph is the scene's business and the semantic names are still the whole interface.
- **`animation_clips` keys MUST be a subset of the declared semantics.** A clip nobody asks for never plays; a semantic with no clip falls back to procedural motion rather than freezing.
- **Animation never decides anything.** A clip may not gate a hit, extend a window, or change a timing — the proxy is posed from the snapshot every frame and `_animate` only picks what to look like (PRES-001).
- **Set materials once at build, never per frame.** Combatant color goes through `color_targets`; a rig must not bake a side's color into its own materials, and per-frame material work on a shared resource would leak between fighters.
- **Index the face once.** `Eye*` and `DeadEye*` are collected by `FacePresentation.bind` when the proxy is built. A pose writes visibility only when `terminal_cause` changes (`game/src/presentation/entities/face_presentation.gd`).
- **No physics nodes.** The simulation owns position, facing, and contact; a `CharacterBody3D` or an `Area3D` in a kit scene is a second opinion about the fight.
- **Hands follow the displayed sword through `SwordRig3D`.** A fighter wrapper's root carries the script; the proxy calls `bind_sword(SwordCarriage, weapon_model)` and `apply_stance(FighterStanceProfile)` once, then `pose_sword(angle, phase, band, hand_lateral)` and `pose_elbows(poles)` every frame. The `SwordCarriage` node is the authoritative carriage and yaw, lifted by `CombatPresentationField` / `CutPresentationCurve` (PRES-CARRIAGE-001); `WeaponOrigin` stays as the undrawn authoritative sword. `look_toward(τ − φ)` lets the head glance toward the target bearing by at most `CombatPoseModifier3D.LOOK_LIMIT` (12°); otherwise the head faces the combat heading φ, so a committed heading that lags reads as lagging (PRES-HEADING-001). `apply_stance` turns the rig by the pelvis's blade and gives `CombatPoseModifier3D` the shoulders' blade, the head counter, and the per-side load-coil caps (PRES-STANCE-001); the chain then adds chest → spine → hips following the sword in decreasing, phase-capped shares. A two-setting `TwoBoneIK3D` (root `UpperArm.*`, middle `Forearm.*`, end `Hand.*`, end bone extended along its own `+Y`) puts the palms on the weapon's `GripDominant` / `GripOffhand` markers under the carriage, bending toward `ElbowGuideField` poles derived from each hand in the torso frame (PRES-ARMS-001) — off the shoulder→hand line, away from the body. A rig nobody guides (the showcase actor) keeps fallback poles on a `BoneAttachment3D` of the chest, lateral and slightly forward; a backward-biased pole clamps the sword to the torso and is wrong. Gameplay clips play on Godot's normal process step (modifiers run after them) with presentation time as `speed_scale`. Bone names are the rig contract: `Root, Hips, Spine, Chest, Neck, Head, Shoulder/UpperArm/Forearm/Hand.{L,R}, UpperLeg/LowerLeg/Foot.{L,R}`.
- **Modifier output exists only during the skeleton update.** Godot applies `SkeletonModifier3D` results for the update and reverts them after, so a test reads the modified pose inside `Skeleton3D.skeleton_updated` (with `modifier_callback_mode_process = MANUAL` and `advance()`), never after it.
- **Imported loops are set where they belong.** Looping clips are flagged from `PresentationKit.LOOPING_SEMANTICS` when the proxy builds; looping audio is `loop=true` in the take's `.mp3.import`.

## Harness

`godot --headless --fixed-fps 60 --path game res://tests/harness/run_headless.tscn` (`pnpm --filter @riposte/game test`). `RIPOSTE_SUITE=<name>` runs one suite. See [docs/reference/testing.md](./testing.md).

## Export

`pnpm game:export:web` writes `dist/game/web/` clean-room (fail closed on missing artifacts or safe-area include); `pnpm --filter @riposte/game dev` serves it on `127.0.0.1:8060`. Export excludes `tests/*` and `tools/*`. `pnpm game:stage:web` then **copies** that directory into `apps/web/public/game/` so the site can serve it at `/play` (WEB-004); `dist/game/web/` stays the canonical itch upload.
