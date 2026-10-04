# Tooling

> See also: [README.md](../../README.md)
> See also: [docs/architecture/monorepo.md](../architecture/monorepo.md)
> Source: `package.json`, `scripts/`

## Commands

```bash
pnpm install           # Install dependencies
pnpm dev               # Turbo: Next.js :3000 + Godot Web serve :8060
pnpm dev:web           # Next.js only
pnpm build             # Production build
pnpm game:export:web   # Clean-room dist/game/web/ then --export-release Web
pnpm build:static      # Next.js static export (website hosts, not itch game)
pnpm lint              # ESLint + game source scanners (not Godot import)
pnpm typecheck         # tsc + GDScript load
pnpm test              # Vitest 100% + Godot harness
pnpm test:tooling      # Fail-fixture gate (not inside pnpm test)
pnpm check             # import + lint + typecheck + docs/arch + tooling
pnpm verify            # check then test then build
pnpm test:fast
pnpm format
pnpm format:check
pnpm docs:generate
pnpm docs:check
pnpm arch:check
pnpm integrity:check
pnpm security:check
pnpm kill              # Recovery: free :3000 / :3001 / :8060
pnpm reinstall         # Clean + frozen lockfile (lockfile kept)
pnpm dependencies:refresh
```

## Godot

Required: Godot **4.7.2-stable** on PATH or `GODOT_BIN` environment variable.

```bash
# Godot-specific commands
pnpm --filter @riposte/game godot:version
pnpm --filter @riposte/game godot:import
pnpm --filter @riposte/game godot:test
```

## Reports

Reports are written to `.reports/`:

- `.reports/check/latest.json` and `.reports/check/latest.md`
- `.reports/build/latest.json` and `.reports/build/latest.md`
- `.reports/verify/latest.json` and `.reports/verify/latest.md`
