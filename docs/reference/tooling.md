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
pnpm game:stage:web    # Copy that export into apps/web/public/game/ for /play
pnpm game:assets       # Blender sources → validated GLBs + manifests (BLENDER_BIN or `blender`; see assets.md)
pnpm build:static      # Next.js static export (website hosts, not itch game)
pnpm lint              # ESLint + game source scanners (not Godot import)
pnpm typecheck         # tsc + GDScript load
pnpm test              # Vitest 100% + manifest check + Godot harness + GDScript manifest
pnpm test:tooling      # Fail-fixture gate (not inside pnpm test)
pnpm check             # import + lint + typecheck + format + docs/arch + tooling
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

## Docs check

`pnpm docs:check` (`scripts/docs-check.mjs`) keeps the doc graph honest in both directions:

- committed markdown never references the local implementation-plan folder, and every `docs/` page has a `See also:` / `Source:` header;
- every `docs/…md` path and `spec/invariants.md#anchor` cited from code resolves;
- every relative markdown link and every backticked repository path in committed markdown exists, except the short `BUILD_OUTPUTS` allowlist of gitignored artifacts docs legitimately name.

## Staging `/play`

`pnpm game:stage:web` copies `dist/game/web/` into `apps/web/public/game/` and fails closed on a missing or incomplete export (see [web](../concepts/web.md)). It is deliberately **not** a Turbo dependency of the web `build`: that would make Godot a hard prerequisite of building the site, so `scripts/build.mjs` reports whether an artifact is staged instead, and `next.config.ts` adds the `/play` rewrite only when one is. `scripts/check-architecture.mjs` asserts the fail-closed behaviour on every run.

## Report runners

`check`, `build`, and `verify` are synchronous Node runners that share `scripts/reports.mjs` (`runEchoed` spawns with echoed output; `writeReport` writes `latest.json` + `latest.md`). The expected Godot version lives once in `scripts/godot-bin.mjs` (`EXPECTED_GODOT_VERSION`).

## Reports

Reports are written to `.reports/`:

- `.reports/check/latest.json` and `.reports/check/latest.md`
- `.reports/build/latest.json` and `.reports/build/latest.md`
- `.reports/verify/latest.json` and `.reports/verify/latest.md`

## Coverage

### TypeScript (`@riposte/web`)

Vitest with V8 coverage: 100% statements/branches/functions/lines per file. `apps/web/scripts/check-coverage-manifest.mjs` enforces a floor on in-scope file count and catches scope escape (files outside `src/` that would be invisible to the coverage run).

### GDScript (`@riposte/game`)

**Line-level measurement:** not yet available. GDScript has no mature CI-friendly coverage collector equivalent to V8/istanbul. The Godot debugger protocol could theoretically provide instruction-level data, but no tooling packages this for headless CI use as of Godot 4.7.2.

**Current gate:** behavioral tests (38 suites, 3400+ assertions) exercise all authoritative code paths. `game/scripts/check-coverage-manifest.mjs` enforces:

- **Scope floor**: minimum counts for domain and application production files, preventing silent scope shrinkage.
- **Class reference check**: warns when an in-scope `class_name` is not directly referenced by test sources. Indirect coverage (e.g., `ImpactResult` through `ImpactModel` tests, UI classes through E2E) is informational, not a hard failure.
- **Scope classification**: domain + application are in-scope; presentation is exempt per COVERAGE-001 (UX/UI).

When Godot ships a debugger-based coverage reporter or a community tool matures, replace the manifest with instrumented line/branch/function measurement.
