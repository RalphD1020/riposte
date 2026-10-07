# AI Agent Instructions — Riposte

> Humans own software. AI proposes; CI enforces.

## Where truth lives

| Need                     | Read                                      |
| ------------------------ | ----------------------------------------- |
| Universal guidelines     | [README.md](./README.md)                  |
| Durable explanation      | [docs/](./docs/)                          |
| Normative contracts      | [spec/](./spec/)                          |
| Consumer proofs          | [examples/](./examples/)                  |
| Local plans (gitignored) | `.impl/` (never link from committed docs) |

```text
spec > code > docs > .impl
```

If code violates spec, the implementation is defective unless the spec has been superseded.

## Laws

0. Inspect `docs/` and `spec/` before implementing.
1. `.impl/` is temporary working memory. Promote durable facts to `docs/`, `spec/`, or `examples/`.
2. Committed markdown must not reference `.impl/`.
3. COVERAGE-001: 100% line/function/branch/statement coverage per file on all non-UX/UI production sources (TypeScript: `perFile: true`). GDScript coverage: behavioral gate green until measured by a real collector. Do not weaken thresholds or use ignore/exclude/expect/disable. TEST-TRUTH-001: every behavioral test asserts its fixture (ARRANGE), perturbation (PERTURB), production code (ACT), contract (ASSERT). Do not use `assert()` for release behavior. ZERO-TOLERANCE-001: zero `@warning_ignore`; Godot default warnings are errors.
4. Use root commands (`pnpm check`, `pnpm test`, `pnpm lint`, `pnpm typecheck`) for validation.
5. Package task names are the monorepo abstraction. Do not hardcode root scripts to `@riposte/web` or `@riposte/game`.
6. `apps/web` and `game` are siblings. Next.js must not own the Godot runtime. Do not put `.gd`, `.tscn`, `.tres`, or `project.godot` under `apps/web`.
7. Never add a no-op package script merely to satisfy Turbo (MONO-002).
8. GIT-001. Agents MUST NOT create commits unless the user explicitly instructs it in the current request.

## Riposte game work

- Read `.impl/INDEX.md` when available. Concept index: [docs/concepts/game.md](./docs/concepts/game.md).
- Normative game contracts live in `spec/`. Durable explanations live in `docs/`. Never introduce committed references to `.impl/`.
- Use Compatibility for Web (WEB-001). Follow [docs/reference/godot.md](./docs/reference/godot.md). Authoritative runtime: Godot **4.7.2-stable**.
- Simulation (SIM-001): only `DuelSimulation.step` advances state, one `PlayerCommand` per fighter per 60 Hz tick (CMD-001). Domain uses `SimMath` scalars (SIM-MATH-001) and `SeededRng` (SIM-RNG-001); no engine types, singletons, signals, or upward dependencies (lint). Rules values live in `game/content/rules/`; changing one bumps `DuelRules.version` (SIM-002).
- Combat (COMBAT-001–003): tap = 0% charge 90° cut; arc `90° + 90° × charge`; swept collision; parry/riposte are classified outcomes; damage is relational strike quality; criticals are convergence. Docs name mechanisms; numbers live only in content.
- Contact (COMBAT-004–008): chronological contact loop over post-contact state with `ContactPairState` lifecycles; blade before body on a tie; trades decided by `lethal_fraction`, never slot/role/health; `StateInvariants` runs every tick and a non-finite authoritative state is `SIMULATION_FAULT` / `REASON_NO_CONTEST`; `TICK_ORDER_VERSION` pins the sequence.
- Physics (PHYS-001–006): `a = F/m`, `α = τ/I`, `I = k·m·L²`. Forces in newtons and torques in newton-metres, never accelerations. Mass never multiplies damage; size never touches reaction, timing, or input latency. Geometry linear, mass cubic, force squared, torque cubic — and never double-count scale (CONTENT-002; [examples/catalog-authoring.md](./examples/catalog-authoring.md)).
- Swing semantics (COMBAT-009): named readings — swing potential, swing progress, contact quality, exposure fraction, grade — are **descriptions, never decisions**. Nothing in the simulation reads one back, and presentation must do without a value rather than recompute a combat formula. Potential is not prediction; convergence exists only at contact.
- CPU (CPU-001): same commands and rules as a human; delayed perception of the opponent; difficulty is profile data. Profile weights are calibrated against the scale of the signals they multiply — swapping a tuned binary term for a continuous reading of the same thing is a balance change even when it is strictly more information.
- Presentation (PRES-001): reads `MatchState` only through `SnapshotProjector`; emits requests/intents; never names an application class or content identity. Art/animation/sound change only in the identity's `PresentationKit` (PRES-KIT-001; [examples/presentation-kit.md](./examples/presentation-kit.md)). Hitstop is wall-clock only (HITSTOP-001).
- App shell: `RiposteApp` composes; `ScreenRouter` holds one screen; every match/rematch is a fresh `MatchSession`. Menu controls come from `UiKit`; strings from `AppCopy` / `HudCopy`; styles from `RiposteTheme` type variations (`add_theme_*_override` only for runtime safe-area margins via `RiposteTheme.apply_insets`).
- Names have one home ([docs/reference/godot.md](./docs/reference/godot.md#centralized-names)): payload keys `DuelEventKeys` (lint-enforced), input `InputActions`, telemetry `ProductEvents.PROP_*`, buses `AudioBuses`, settings `PlayerSettings.KEY_*`, platform/display features `Platform`, the browser safe-area JSON contract `SafeArea.KEY_*`. Tunables are named constants (gameplay numbers only in `game/content/rules/`). A formula has one home too: `StructuralCoupling.effective_mass` is written once and takes the coupling, because the caller that resolves a hit also reports it.
- Contracts that cross a boundary no compiler reads are gated by tests instead: the export shell's safe-area JavaScript and loading CSS (`APP-SHELL`, `PRES-THEME`) and the web manifest and favicon colors (`theme.test.ts`). A rename on the far side does not error — it ships a notch over the HUD or an off-brand first paint.
- UX-001: contrast pairs tested; ≥ 48 px targets with one UI unit ≥ one CSS px (`UiScale`); never color alone; only glyphs the shipped font renders (draw icons in `HudIcons`); menus fit a 360 px-tall landscape phone.
- Web (WEB-004–006): every Play links to `/play`; `resolvePlaySurface` decides, hostname-free — the export staged on this origin, else itch, else the local serve, else "not published". `pnpm game:stage:web` copies `dist/game/web/` into `apps/web/public/game/` and fails closed. `/game/:path*` gets a path-scoped CSP (`'wasm-unsafe-eval'`, `worker-src blob:`); never widen the site-wide policy. Only `runtimeConfig.ts` reads `NEXT_PUBLIC_*`; destinations are validated; stubs say "Coming soon". Styles only in `globals.css`; copy only in `site.ts`.
- Device QA ([docs/reference/device-qa.md](./docs/reference/device-qa.md)): touch mechanics are proven in APP-E2E with real touch events. Legibility at arm's length and the behaviour of an actual hand are the human's pass, not an agent's claim.
- Performance: a switched-off cue costs nothing per frame — check `get_surface_count()` before clearing, and never rebuild a mesh into the state it is already in. The HUD writes a `Label` or bar only when its value changes. [docs/architecture/PERFORMANCE.md](./docs/architecture/PERFORMANCE.md).

## Coverage

Measured `src` in packages that define `test:coverage` must stay at 100% statements, branches, functions, and lines per file. Do not maintain coverage through ignore/exclude/expect/disable or meaningless execution-only tests.

When 100% coverage exposes an uncovered branch: (1) test reachable behavior, (2) test the authoritative failure boundary, or (3) delete unreachable code. Do not rewrite conditionals solely to change instrumentation.

Matchmaking, ELO systems, and all production logic affecting outcomes MUST be in covered scope.

## Commands

```bash
pnpm check
pnpm test
pnpm verify
pnpm docs:check
pnpm arch:check
```

`lint` is static policy. `typecheck` is parse/load. `test` is behavior. `check` is the non-artifact static/load/tooling gate (Godot `--import` first; includes `test:tooling`; does not re-run behavior suites). `build` is artifacts only. `verify` is check then test then build. Command contract: [docs/reference/tooling.md](./docs/reference/tooling.md).

<!-- BEGIN:turborepo-agent-rules -->

# This is NOT the Turborepo you know

Turborepo configuration, task behavior, and CLI commands can vary between installed versions and may differ from your training data. Resolve the `turbo` package from this file's directory or relevant workspace; in monorepos, it may not be visible from the repository root. For example, run `node -p "require.resolve('turbo/package.json')"` from a workspace that depends on `turbo`.

Read `docs/README.md` inside that installed package first, then read the relevant pages from its `docs/` directory before changing Turborepo configuration or commands. Heed deprecation notices. These bundled docs match the installed package version and are available without network access.

This block is written and re-added by `turbo` before repository-scoped commands when an AI agent is detected. In the Turborepo source repository, its template is defined in `crates/turborepo-cli/src/cli/agent_guidance.rs`. Removing the managed block while updates are enabled means a later qualifying invocation will add it again. Set `"agentGuidance": false` in the root `turbo.json` or `turbo.jsonc` to opt out; this does not remove an existing block. Keep the block committed with your work to avoid an uncommitted change on the next agent invocation.
<!-- END:turborepo-agent-rules -->
