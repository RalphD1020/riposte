# Godot Conventions

> See also: [README.md](../../README.md), [docs/architecture/monorepo.md](../architecture/monorepo.md)
> See also: [docs/concepts/simulation.md](../concepts/simulation.md), [docs/concepts/presentation.md](../concepts/presentation.md)
> Source: `game/project.godot`, `game/scripts/lint.mjs`

## Version and renderer

Godot **4.7.2-stable** (`GODOT_BIN` or `godot` on PATH). Compatibility (`gl_compatibility`) everywhere (WEB-001); single-threaded Web export with desktop and mobile VRAM compression (WEB-003).

## Project structure

```text
game/
├── project.godot            warnings=2 (errors), input map, 1280×720 canvas_items/expand
├── default_bus_layout.tres  audio buses Master → Music, SFX (names: AudioBuses)
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

| Vocabulary                                    | Home                                             |
| --------------------------------------------- | ------------------------------------------------ |
| Event names / payload keys                    | `DuelEventTypes` / `DuelEventKeys`               |
| Match reasons, contact classes                | `MatchPhase.REASON_*`, `ContactResolver.CLASS_*` |
| Input actions (match `project.godot [input]`) | `InputActions`                                   |
| Product events / property keys                | `ProductEvents` / `ProductEvents.PROP_*`         |
| Audio buses                                   | `AudioBuses` (+ `default_bus_layout.tres`)       |
| Settings file layout                          | `PlayerSettings.SECTION_*` / `KEY_*`             |
| Replay serialization                          | `ReplayRecord.KEY_*`                             |
| Styles, sizes, colors                         | `RiposteTheme` tokens and type variations        |
| Copy                                          | `AppCopy` (menus), `HudCopy` (HUD)               |
| Content identities                            | `ContentIds`                                     |

## GDScript

- Typed everywhere (`untyped_declaration` is an error). Zero `@warning_ignore` (ZERO-TOLERANCE-001).
- Shadowing is an error: locals and loop variables must not reuse member, method, or global names (`trail`/`trail()`, `pips`/`pips()`, `OK`).
- No `uid=` in hand-written `.tscn` headers.
- Accessibility (4.7): `accessibility_name`, `accessibility_description`, and `accessibility_live = AccessibilityServer.LIVE_POLITE`.
- Static caches (`HudIcons`, `PlaceholderAudio`, `RiposteTheme.display_font`) build once on first use.
- UI styling: pick a `RiposteTheme` type variation; `add_theme_*_override` is only for runtime values (safe-area margins via `RiposteTheme.apply_insets`).
- Tunables are named constants at the top of the file that owns them (gameplay values in `game/content/rules/`; per-identity feel in kits; generic feel in the presenter / directors).
- Nodes in the tree `queue_free`; swap screens with `remove_child` + `queue_free` so `_exit_tree` teardown runs first. Never free a button inside its own signal (defer the page swap).

## Harness

`godot --headless --fixed-fps 60 --path game res://tests/harness/run_headless.tscn` (`pnpm --filter @riposte/game test`). `RIPOSTE_SUITE=<name>` runs one suite. See [docs/reference/testing.md](./testing.md).

## Export

`pnpm game:export:web` writes `dist/game/web/` clean-room (fail closed on missing artifacts or safe-area include); `pnpm --filter @riposte/game dev` serves it on `127.0.0.1:8060`. Export excludes `tests/*` and `tools/*`.
