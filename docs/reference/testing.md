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

| Area         | Suites (suite name)                                                                                                                          | Proves                                                                                                                                                                                                                                                                                                          |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Harness      | HARNESS                                                                                                                                      | Assertion semantics, vacuity detection                                                                                                                                                                                                                                                                          |
| Domain       | MATH, CMD, RULES, SCALING, INVARIANT, SIDE, FUZZ, MOVE, FACE, ATTACK, BURST, COMMIT, COLLIDE, CONTACT, DAMAGE, SEMANTICS, ROUND, REPLAY, SYM | Determinism, input language, physical baseline and scaling laws, per-tick totality, cardinal sides and the locked world orientation, generated-input properties and graceful handling, physics, burst footwork, damage, swing semantics as descriptions only, rounds, replay + tamper detection, point symmetry |
| Application  | INPUT, DRIVER, SETTINGS, TUTORIAL, SESSION, CPU, APP-SHELL                                                                                   | Input merge, clock/hitstop, persistence sanitizing + bus layout, coaching, sessions, CPU fairness + difficulty order, UI scale, safe area, glyph coverage, every `InputActions` name in the InputMap, side-by-side menus only on short landscape screens                                                        |
| Presentation | PRES-THEME, PRES-KIT, PRES-SNAPSHOT, PRES-CAMERA, PRES-PRESENTER, PRES-HUD                                                                   | Contrast (independent formula), theme variations, kit resolution, projection, framing, feedback, HUD, touch                                                                                                                                                                                                     |
| End to end   | APP-E2E                                                                                                                                      | Real `main.tscn`: menu → quick play → results → rematch → pause → quit; training from How to Play; settings drill-down persistence                                                                                                                                                                              |

APP-E2E drives frames through `MatchScreen.advance_frame` (the same path `_process` uses) with `_process` disabled, pins seeds, and uses a scratch settings file. Shared fixtures live in `game/tests/harness/` (`DuelFixture.of_type` is the one event filter).

Balance tool (not a suite): `godot --headless --path game --script res://tools/balance_report.gd` prints CPU-vs-CPU matchups (wins, rounds, hits, parries, charge, round length) with the shipping rules; read-only.

## Test design (TEST-TRUTH-001)

ARRANGE (assert the fixture) → PERTURB → ACT (production code) → ASSERT (independent expectation). Lint rejects tautologies, commented-out or skipped assertions, and `Engine.time_scale` changes. Do not add tests whose only job is to inflate coverage.

Oracles are written from the rules, never from the implementation. A test that re-derives its expectation by reimplementing the code under test will agree with that code's bugs. For physical behaviour prefer ordered comparisons (`quality_a > quality_b`) so the suite survives deliberate balance tuning; reserve exact assertions for known formulas, determinism, replay fixtures, and boundaries.

## Readability proofs (PRES-PRESENTER)

Readability claims are testable, and the ones that matter are _negative_. The presenter suite proves that the ribbon carries the projected `swing_potential` unaltered rather than a presentation-local guess, that the sweet region is a distinct surface and not a tint, that turning the accessibility cues off or up changes the drawing while leaving the band width and the carried reading untouched, that wind-back tension tightens and then lets go, that burst dust stays on the floor and drifts away from the heading, and that a whiff is never punctuated like a hit. Each one is a thing that would be easy to break silently and impossible to notice from a passing screenshot.

Two more guard the accessibility floor and the one diagnostic: with shake, motion, the ribbon, and the sweet rib all switched off, a body hit is still marked in the world, still heard, still felt in the pacing, and `SWEET_REGION_MIN` is still where it was; and the debug vectors draw nothing until asked, then follow the simulated swing direction when the blade reverses while the tip _speed_ stays a magnitude. TUTORIAL covers the lessons themselves: the sweet-spot drill passes on `blade_fraction` alone and refuses a hit near the hilt, at the very tip, or by the opponent, the momentum drill refuses two hits that felt the same, and the scripted partner winds up exactly once per period without moving, paces in and out without ever swinging, and stands down outside an active round.

## Property and fuzz proofs (FUZZ)

Scripted suites prove the cases someone thought of. FUZZ generates input a person might plausibly produce — jittery taps, held keys, rolled thumbs, attacks landing on top of footwork — and asserts laws that must hold for every stream: no burst without a deliberate gesture behind it, no burst from key repeat or a held direction, bursts never overlapping, the duel staying finite and separated inside the arena, neither lateral direction cheaper than the other, and bit-identical reproduction.

Its generator is weighted toward real gestures on purpose. Uniform random axes essentially never produce a double tap, so a fuzzer made of noise would exercise only the paths nobody worries about.

The graceful-handling matrix lives there too, and it is two claims, not one. **Input and external problems are absorbed** — clamped, ignored, or cancelled into a short recovery — because they arrive from outside the simulation and are not its fault. **Impossible authoritative state is not**: it means the simulation itself is wrong, so it fails closed as a no-contest rather than being quietly repaired.

## Production scope

Code affecting authoritative state, simulation outcome, win/loss, deterministic hashes, matchmaking, ELO, or shipping product behavior MUST be in covered scope.

## The test pyramid, and what each layer may claim

Each layer is only honest about its own row. A green suite below never licenses a claim from a row above it.

| Layer                | Proves                                                                        | May **not** claim                     |
| -------------------- | ----------------------------------------------------------------------------- | ------------------------------------- |
| Unit / property      | Math laws, totality, state invariants, symmetry, scaling                      | Game feel                             |
| Simulation scenarios | Tap, bind, parry, trade, contact lifecycles, CPU commands, a full match       | Browser or mobile integration         |
| Godot app E2E        | The real `main.tscn`: menus, match lifecycle, rematch, pause, touch mechanics | Browser rendering and input behaviour |
| Browser / device     | The Web export: boot, real input, canvas, safe area, sustained performance    | Balance, or legibility across humans  |

The bottom row is the one the automated gates cannot reach, and it is split by what is mechanical versus perceptual:

- **Mechanical** — hosting, boot, `/play` resolution, navigation, reload, focus loss. Automatable, and the intended home for a future Playwright gate. Not automated for MVP-0; run by hand from [device-qa.md](./device-qa.md).
- **Perceptual** — whether a parry reads clearly, whether a wind-back is legible at arm's length. Deliberately **never** automated. A test asserting "this reads clearly" would be asserting its own fixture.

## Gates a person runs

Two gates are deliberately not automated, because what they check is a human reading a screen rather than a value in a state: the combat-feel and readability gate ([combat-feel-gate.md](./combat-feel-gate.md)), which blocks the mechanics freeze, and the real-device pass ([device-qa.md](./device-qa.md)). Both list what the suite already proves, so the hand pass is spent on the part only a hand can reach.

## Tuning against the test set

Where a test grades an emergent outcome rather than an authored value, the seeds it grades on are part of the contract. CPU difficulty keeps two disjoint corpora — calibration seeds to read while tuning, acceptance seeds that grade and are never inspected — and the one claim too small to resolve at an affordable sample size is measured by a tool instead of gated. See [docs/concepts/cpu.md](../concepts/cpu.md#how-difficulty-is-tested-and-what-the-tests-can-prove). Raising a sample until a gate passes re-creates exactly the overfitting the split prevents.

## What tests cannot prove

Legibility at arm's length and the behaviour of an actual hand on glass. Everything mechanical about touch — duel-relative steering, simultaneous thumbs on independent indices, all four burst gestures with their negatives, OS cancellation — is driven through the shipped `main.tscn` in APP-E2E, because a simulated `InputEventScreenTouch` is a real one as far as the game is concerned. The rest is a written procedure: [device QA](./device-qa.md).

## Commands

```bash
pnpm test                                   # harness + web coverage
pnpm test:fast                              # without coverage
pnpm --filter @riposte/web test:coverage    # web only
RIPOSTE_SUITE=APP-E2E pnpm --filter @riposte/game test   # one game suite
```
