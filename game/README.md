# @riposte/game

> See also: [../README.md](../README.md)
> See also: [../docs/reference/godot.md](../docs/reference/godot.md)
> See also: [../spec/invariants.md](../spec/invariants.md)

Godot 4.7.x game source. Authoritative runtime: **4.7.2-stable**.

## Structure

```text
game/
├── project.godot          # Project configuration
├── export_presets.cfg     # Export configuration (committed when exists)
├── src/                   # Production source
│   └── main/              # Application entry
├── tests/                 # Test suites
│   └── harness/           # Test harness
├── content/               # Game content
├── tools/                 # Editor tools
└── scripts/               # Build scripts (Node.js)
```

## Scripts

```bash
pnpm dev                  # Serve dist/game/web/ on :8060
pnpm lint                 # Static source policy
pnpm typecheck            # GDScript load check
pnpm test                 # Headless behavioral harness
pnpm test:headless        # Same as test
pnpm check                # version → import → lint → scripts → tooling
pnpm godot:version        # Print Godot version
pnpm godot:import         # Run Godot import
pnpm godot:test           # Run test harness
pnpm export:web           # Export to dist/game/web/
pnpm export:templates     # Install export templates
```

## Coverage

- `test` / `test:headless` — headless behavioral harness (suites expected to pass). This is **not** measured GDScript line coverage. Do not add `test:coverage` until a collector measures it.

## Conventions

- Renderer: Compatibility (gl_compatibility)
- Warnings: Zero tolerance — no `@warning_ignore`
- Language: Typed GDScript only (no C# for Web export)
