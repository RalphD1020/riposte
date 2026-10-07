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
game/src/presentation  snapshots → director → requests → proxies, HUD, touch       PRES-001, PRES-002
game/content           rules values + one PresentationKit per identity            PRES-KIT-001
apps/web               gateway site; serves the staged export at /play              WEB-004, WEB-005
```

- Presentation pipeline: `SnapshotProjector` → `CombatFeedbackDirector` → `FeedbackFrame` → presenters. The director is pure computation; downstream presenters consume typed value-like requests ([docs/architecture/presentation-feedback.md](./docs/architecture/presentation-feedback.md), PRES-002).
- Feedback constants (impulse ceilings, audio tiers, spark geometry) have one canonical home on `CombatFeedbackDirector`. Impact semantics (clash/slash/poke/thrust/graze/kill) live on `ImpactPresentationProfile`. VFX-specific sizes and lifetimes live on `VfxDirector`. Per-identity feel (hitstop bands, trails) lives in kits.

- Determinism: `SimMath` scalars, `SeededRng`, fixed ticks, SHA-256 state hash, verified replays (SIM-002, SIM-MATH-001, SIM-RNG-001). Scoped to one build — same build, rules, seed, and commands — not to every platform.
- Art, animation, and sound change in one place: the identity's kit ([examples/presentation-kit.md](./examples/presentation-kit.md)).
- Content is authored as a size and a mass; the physical equations produce the gameplay ([examples/catalog-authoring.md](./examples/catalog-authoring.md)).
- Arena: `DuelRules.platform_radius` is the sole authoritative physical dimension. The warning ring is a derived presentation concept at `platform_radius - edge_warning_inset`. There is no arena wall — body separation is pure inverse-mass overlap resolution, and crossing `platform_radius` is a ring-out (ARENA-001).
- Styles: `RiposteTheme` type variations (game) and `apps/web/src/app/globals.css` semantic classes (web) share one light palette; no inline styles except runtime safe-area margins. Copy lives in `AppCopy` / `HudCopy` (game) and `SiteCopy` (web).
- No magic strings or numbers: each vocabulary has one home (`DuelEventKeys`, `InputActions`, `ProductEvents`, `AudioBuses`, `ContentIds`, `Platform`, `SafeArea`, `CombatFeedbackDirector` constants, rules content, named tunables); lint rejects literal event payload keys ([docs/reference/godot.md](./docs/reference/godot.md#centralized-names)).
- Where a contract crosses a language boundary no compiler reads — the export shell's safe-area JavaScript, its loading CSS, the web manifest and favicon — a test holds the two halves together. A rename there does not error; it ships a notch over the HUD or an off-brand first paint.
- Accessibility is tested: contrast pairs, 48 px targets with one UI unit ≥ one CSS px, glyph coverage, mobile layouts (UX-001).

## Priority order

Reliability → security → performance → user experience → cost.

## Stack

- TypeScript (strict), pnpm workspaces, Turborepo
- `@riposte/web` — Next.js App Router landing gateway
- `@riposte/game` — Godot **4.7.x** source / **4.7.2-stable** authoritative runtime (Compatibility)
- Vitest **100%** on `@riposte/web` `src`

**Build once:** one Godot source → one Web artifact family (`dist/game/web/`) → many hosts. `pnpm game:stage:web` copies that artifact into `apps/web/public/game/`, so `/play` serves the game from our own origin; the same bytes are also the itch.io upload.

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
pnpm game:stage:web    # copy that export into apps/web/public/game/ for /play
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

Two gates only a person can run: [docs/reference/combat-feel-gate.md](./docs/reference/combat-feel-gate.md) (combat reads and feels right — mechanics freeze depends on it) and [docs/reference/device-qa.md](./docs/reference/device-qa.md) (real phones and tablets).

## Coverage

Measured `src` in packages that define `test:coverage` must stay at 100% statements, branches, functions, and lines per file. Do not maintain coverage through ignore/exclude/expect/disable or meaningless execution-only tests. `@riposte/web` `test:coverage` is measured Vitest. `@riposte/game` `test` / `test:headless` is the behavioral harness; game has no `test:coverage` until GDScript coverage is actually measured. Root `pnpm test` runs game `test` plus web `test:coverage`.

When 100% coverage exposes an uncovered branch: (1) test reachable behavior, (2) test the authoritative failure boundary, or (3) delete unreachable code. Do not rewrite conditionals solely to change instrumentation.

Every behavioral test asserts its fixture, its perturbation, the production code, and the contract (TEST-TRUTH-001). A test that passes against a stubbed or absent mechanism proves nothing; prefer one test that fails when the mechanism is removed over three that do not.

**Production scope**: If code affects authoritative state, simulation outcome, economy, progression, win/loss, matchmaking, ELO ratings, deterministic hashes, or shipping product behavior, it MUST be in covered scope and MUST NOT reside in a coverage-excluded directory.

## Performance

Performance is architectural. The website server-renders, ships minimal JS, and uses the system font stack. The game must not run on the Next.js main thread. A cue that is switched off costs nothing per frame. See [docs/architecture/PERFORMANCE.md](./docs/architecture/PERFORMANCE.md).

## itch.io vs this website

- itch.io hosts the same **Godot Web** export (`dist/game/web/`), as a secondary home rather than the front door.
- This Next.js app is the gateway **and** the host: `/play` serves the staged export from this origin. Unstaged deployments fall back to `NEXT_PUBLIC_PLAY_URL`, then the local `:8060` serve ([docs/concepts/web.md](./docs/concepts/web.md)).
- `build:static` is for static **website** hosts. It is not the itch game pipeline.

## Secrets

Never commit `.env`, `*.pem`, or `**/.godot/export_credentials.cfg`. `export_presets.cfg` is committed configuration.

Agents do not create git commits unless the human asks.
