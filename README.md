# Riposte

Browser-first Godot game with a Next.js informational site.

## Authority

```text
spec/     normative contracts     WHAT MUST BE TRUE
code      executable implementation
docs/     durable explanation     HOW THE SYSTEM WORKS
.impl/    local working memory    WHAT WE INTEND TO BUILD
```

Conflict: **spec > code > docs > .impl**. Code that violates spec is defective. Docs that contradict code are stale. Committed markdown MUST NOT reference `.impl/`.

## Doc index

| Surface                  | Role                                         |
| ------------------------ | -------------------------------------------- |
| [README.md](./README.md) | Universal guidelines + commands (this file)  |
| [docs/](./docs/)         | Package/system docs                          |
| [spec/](./spec/)         | Implementation-independent contracts         |
| [examples/](./examples/) | Consumer proofs (reserved)                   |
| [AGENTS.md](./AGENTS.md) | Agent navigation                             |
| `.impl/` (local only)    | LLM implementation plans — **not committed** |

Start with [docs/architecture/monorepo.md](./docs/architecture/monorepo.md) and [spec/invariants.md](./spec/invariants.md).

## Priority order

Reliability → security → performance → user experience → cost.

## Stack

- TypeScript (strict), pnpm workspaces, Turborepo
- `@riposte/web` — Next.js App Router landing gateway
- `@riposte/game` — Godot **4.7.x** source / **4.7.2-stable** authoritative runtime (Compatibility)
- Vitest **100%** on `@riposte/web` `src`

**Build once:** one Godot source → one Web artifact family (`dist/game/web/`) → many hosts. The Next.js site acquires and admits the player to the standalone Godot export (`http://127.0.0.1:8060/` on localhost).

## Topology

```text
riposte/
├── apps/web/          @riposte/web
├── game/              @riposte/game   Godot 4.7
├── packages/          future shared packages
├── docs/ spec/ examples/ scripts/
└── dist/              generated (gitignored)
    └── game/web/      canonical Godot Web export (`pnpm game:export:web`)
```

## Commands

```bash
pnpm install
pnpm dev               # Turbo: Next.js :3000 + Godot Web serve :8060
pnpm dev:web           # Next.js only
pnpm build
pnpm game:export:web   # clean-room dist/game/web/ then --export-release Web
pnpm build:static      # Next.js static export (website hosts, not itch game)
pnpm lint              # ESLint + game source scanners (not Godot import)
pnpm typecheck         # tsc + GDScript load
pnpm test              # Vitest 100% + Godot harness
pnpm test:tooling      # Fail-fixture gate (not inside pnpm test)
pnpm check             # import + lint + typecheck + docs/arch + tooling; writes .reports/check
pnpm verify            # check then test then build
pnpm test:fast
pnpm format
pnpm format:check
pnpm docs:generate
pnpm docs:check
pnpm arch:check
pnpm integrity:check
pnpm security:check
# Godot 4.7.2-stable: GODOT_BIN or `godot` on PATH. --import is part of pnpm check.
pnpm kill              # recovery: free :3000 / :3001 / :8060
pnpm reinstall         # clean + frozen lockfile (lockfile kept)
pnpm dependencies:refresh
```

Root `dev` / `lint` / `typecheck` / `test` call Turbo. `check` / `build` / `verify` are sequential report runners. Additional packages join Turbo tasks by exposing those script names. Never add a no-op script to satisfy Turbo.

## Coverage

Measured `src` in packages that define `test:coverage` must stay at 100% statements, branches, functions, and lines. Do not maintain coverage through ignore/exclude/expect/disable or meaningless execution-only tests.

## Performance

Performance is architectural. The website server-renders, ships minimal JS, and uses the system font stack. The game must not run on the Next.js main thread. See [docs/architecture/PERFORMANCE.md](./docs/architecture/PERFORMANCE.md).

## Secrets

Never commit `.env`, `*.pem`, or `**/.godot/export_credentials.cfg`. `export_presets.cfg` is committed configuration.

Agents do not create git commits unless the human asks
physics combat dueling game
