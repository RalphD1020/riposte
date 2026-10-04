# @riposte/game

> See also: [../README.md](../README.md), [../docs/reference/godot.md](../docs/reference/godot.md), [../spec/invariants.md](../spec/invariants.md)
> See also: [../docs/concepts/game.md](../docs/concepts/game.md) — concept index (simulation, combat, CPU, presentation, UX, controls)

Godot 4.7.x game source. Authoritative runtime: **4.7.2-stable**. Entry: `src/main/main.tscn`.

## Structure

```text
game/
├── project.godot          warnings as errors, input map, display stretch
├── export_presets.cfg     committed Web preset
├── src/
│   ├── domain/            deterministic duel: math, rules, commands, state, events, combat, match, replay
│   ├── application/       match sessions, controllers, CPU, clock, input, settings, tutorial, telemetry, app shell
│   ├── presentation/      theme, kits, snapshots, proxies, camera, VFX, audio, haptics, HUD, touch
│   └── main/              main.tscn + RiposteMain
├── content/               content ids, rules values, presentation kits, procedural audio
├── tests/                 harness/ domain/ application/ presentation/
├── tools/                 check_scripts.gd
└── scripts/               godot runner, lint, export/serve, templates, tool tests
```

## Scripts

```bash
pnpm dev                  # Serve dist/game/web/ on 127.0.0.1:8060
pnpm lint                 # Static source policy (layering, purity, warnings, test truth)
pnpm typecheck            # Load every GDScript (warnings are errors)
pnpm test                 # Headless behavioral harness (RIPOSTE_SUITE=<name> for one)
pnpm test:headless        # Same as test
pnpm check                # version → import → lint → scripts → tooling
pnpm export:web           # Export to dist/game/web/
pnpm export:templates     # Install export templates
```

## Change art, animation, or sound

Edit or add a `PresentationKit` for the identity; never presenters or gameplay. Walkthrough: [../examples/presentation-kit.md](../examples/presentation-kit.md).

## Change balance

Edit `content/rules/standard_duel_rules.gd` and bump `DuelRules.version` (replays pin rules by id + version).

## Coverage

`test` is the behavioral harness (every suite green, zero engine errors, zero leaks). It is **not** measured GDScript coverage; do not add `test:coverage` until a collector measures it.

## Conventions

- Compatibility renderer; typed GDScript only (no C#: Web export).
- Zero `@warning_ignore`; Godot default warnings are errors.
