# Testing

> See also: [spec/invariants.md](../../spec/invariants.md) (COVERAGE-001, TEST-TRUTH-001)
> See also: [docs/architecture/monorepo.md](../architecture/monorepo.md)
> Source: `apps/web/vitest.config.ts`, `game/tests/`

## Gates

| Package         | Tool                           | Gate                                                                                         |
| --------------- | ------------------------------ | -------------------------------------------------------------------------------------------- |
| `@riposte/web`  | Vitest + `@vitest/coverage-v8` | 100% per file (statements, branches, functions, lines) + manifest check                      |
| `@riposte/game` | Godot headless harness         | Behavioral: every suite green, zero engine ERROR/WARNING, zero leaks (not measured coverage) |

`pnpm test` is `turbo run test test:coverage` (Godot harness + website coverage). `pnpm test:fast` skips coverage. `pnpm check` runs `--import`, lint, typecheck, format, docs, arch, integrity, security, and `test:tooling`; it MUST NOT re-run behavior suites. `pnpm verify` is check → test → build.

## Web coverage scope

`src/**/*.{ts,tsx}` except tests, `*.d.ts`, and `src/test/**`. Routes and layouts are covered too (`apps/web/src/app/AppRoutes.test.tsx`); do not exclude pages to dodge coverage. `test:coverage` then runs `apps/web/scripts/check-coverage-manifest.mjs`: a source file no test imports fails the gate. `apps/web/src/app/theme.test.ts` is the website contrast gate.

## Game harness

`game/tests/harness/headless_runner.gd` runs `SUITES` in order and prints one `RIPOSTE_RESULT` line. A suite fails on any failed assertion, a zero-assertion case, or leaked orphan nodes; the runner fails on engine errors or ObjectDB leaks at exit (the root waits briefly so the audio thread releases stopped voices). Cases are `test_*` methods and may `await`.

| Area         | Suites (suite name)                                                                        | Proves                                                                                                                                                                                                                                                   |
| ------------ | ------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Harness      | HARNESS                                                                                    | Assertion semantics, vacuity detection                                                                                                                                                                                                                   |
| Domain       | MATH, CMD, RULES, MOVE, FACE, ATTACK, COMMIT, COLLIDE, CONTACT, DAMAGE, ROUND, REPLAY, SYM | Determinism, input language, physics, damage, rounds, replay + tamper detection, point symmetry                                                                                                                                                          |
| Application  | INPUT, DRIVER, SETTINGS, TUTORIAL, SESSION, CPU, APP-SHELL                                 | Input merge, clock/hitstop, persistence sanitizing + bus layout, coaching, sessions, CPU fairness + difficulty order, UI scale, safe area, glyph coverage, every `InputActions` name in the InputMap, side-by-side menus only on short landscape screens |
| Presentation | PRES-THEME, PRES-KIT, PRES-SNAPSHOT, PRES-CAMERA, PRES-PRESENTER, PRES-HUD                 | Contrast (independent formula), theme variations, kit resolution, projection, framing, feedback, HUD, touch                                                                                                                                              |
| End to end   | APP-E2E                                                                                    | Real `main.tscn`: menu → quick play → results → rematch → pause → quit; training from How to Play; settings drill-down persistence                                                                                                                       |

APP-E2E drives frames through `MatchScreen.advance_frame` (the same path `_process` uses) with `_process` disabled, pins seeds, and uses a scratch settings file. Shared fixtures live in `game/tests/harness/` (`DuelFixture.of_type` is the one event filter).

Balance tool (not a suite): `godot --headless --path game --script res://tools/balance_report.gd` prints CPU-vs-CPU matchups (wins, rounds, hits, parries, charge, round length) with the shipping rules; read-only.

## Test design (TEST-TRUTH-001)

ARRANGE (assert the fixture) → PERTURB → ACT (production code) → ASSERT (independent expectation). Lint rejects tautologies, commented-out or skipped assertions, and `Engine.time_scale` changes. Do not add tests whose only job is to inflate coverage.

## Production scope

Code affecting authoritative state, simulation outcome, win/loss, deterministic hashes, matchmaking, ELO, or shipping product behavior MUST be in covered scope.

## Commands

```bash
pnpm test                                   # harness + web coverage
pnpm test:fast                              # without coverage
pnpm --filter @riposte/web test:coverage    # web only
RIPOSTE_SUITE=APP-E2E pnpm --filter @riposte/game test   # one game suite
```
