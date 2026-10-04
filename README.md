# Riposte

Physics-driven 1v1 sword duel for the browser (Godot) with a Next.js gateway site. Two verbs, real steel.

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
| [examples/](./examples/) | Consumer proofs (authored presentation kit)  |
| [AGENTS.md](./AGENTS.md) | Agent navigation                             |
| `.impl/` (local only)    | LLM implementation plans — **not committed** |

Start with [docs/architecture/monorepo.md](./docs/architecture/monorepo.md), [spec/invariants.md](./spec/invariants.md), and the game concept index [docs/concepts/game.md](./docs/concepts/game.md).

## Architecture in one screen

```text
game/src/domain        deterministic 60 Hz duel; PlayerCommand in, events out      SIM-001, CMD-001
game/src/application   sessions, controllers, CPU, clock, app shell (composes all) CPU-001, HITSTOP-001
game/src/presentation  snapshots → presenter → proxies, feedback, HUD, touch       PRES-001
game/content           rules values + one PresentationKit per identity            PRES-KIT-001
apps/web               static gateway; every Play goes through /play admission    WEB-005, WEB-006
```

- Determinism: `SimMath` scalars, `SeededRng`, fixed ticks, SHA-256 state hash, verified replays (SIM-002, SIM-MATH-001, SIM-RNG-001).
- Art, animation, and sound change in one place: the identity's kit ([examples/presentation-kit.md](./examples/presentation-kit.md)).
- Styles: `RiposteTheme` type variations (game) and `apps/web/src/app/globals.css` semantic classes (web) share one light palette; no inline styles except runtime safe-area margins. Copy lives in `AppCopy` / `HudCopy` (game) and `SiteCopy` (web).
- No magic strings or numbers: each vocabulary has one home (`DuelEventKeys`, `InputActions`, `ProductEvents`, `AudioBuses`, `ContentIds`, rules content, named tunables); lint rejects literal event payload keys ([docs/reference/godot.md](./docs/reference/godot.md#centralized-names)).
- Accessibility is tested: contrast pairs, 48 px targets with one UI unit ≥ one CSS px, glyph coverage, mobile layouts (UX-001).

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
pnpm test              # Vitest 100% + manifest check + Godot harness
pnpm test:tooling      # Fail-fixture gate (not inside pnpm test)
pnpm check             # import + lint + typecheck + format + docs/arch + tooling; writes .reports/check
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

Measured `src` in packages that define `test:coverage` must stay at 100% statements, branches, functions, and lines per file. Do not maintain coverage through ignore/exclude/expect/disable or meaningless execution-only tests. `@riposte/web` `test:coverage` is measured Vitest. `@riposte/game` `test` / `test:headless` is the behavioral harness; game has no `test:coverage` until GDScript coverage is actually measured. Root `pnpm test` runs game `test` plus web `test:coverage`.

When 100% coverage exposes an uncovered branch: (1) test reachable behavior, (2) test the authoritative failure boundary, or (3) delete unreachable code. Do not rewrite conditionals solely to change instrumentation.

**Production scope**: If code affects authoritative state, simulation outcome, economy, progression, win/loss, matchmaking, ELO ratings, deterministic hashes, or shipping product behavior, it MUST be in covered scope and MUST NOT reside in a coverage-excluded directory.

## Performance

Performance is architectural. The website server-renders, ships minimal JS, and uses the system font stack. The game must not run on the Next.js main thread. See [docs/architecture/PERFORMANCE.md](./docs/architecture/PERFORMANCE.md).

## itch.io vs this website

- itch.io hosts the **Godot Web** export (`dist/game/web/`).
- This Next.js app is the informational/community site. Play on localhost opens `http://127.0.0.1:8060/`; elsewhere it opens `NEXT_PUBLIC_PLAY_URL` once published ([docs/concepts/web.md](./docs/concepts/web.md)).
- `build:static` is for static **website** hosts. It is not the itch game pipeline.

## Secrets

Never commit `.env`, `*.pem`, or `**/.godot/export_credentials.cfg`. `export_presets.cfg` is committed configuration.

Agents do not create git commits unless the human asks.
