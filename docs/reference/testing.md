# Testing

> See also: [spec/invariants.md](../../spec/invariants.md) (COVERAGE-001, TEST-TRUTH-001)
> See also: [docs/architecture/monorepo.md](../architecture/monorepo.md)
> Source: `apps/web/vitest.config.ts`, `game/tests/`

## Gates

| Package         | Tool                           | Gate                                                                                         |
| --------------- | ------------------------------ | -------------------------------------------------------------------------------------------- |
| `@riposte/web`  | Vitest + `@vitest/coverage-v8` | 100% per file (statements, branches, functions, lines) + manifest check                      |
| `@riposte/game` | Godot headless harness         | Behavioral: every suite green, zero engine ERROR/WARNING, zero leaks (not measured coverage) |

`pnpm test` is `turbo run test test:coverage` (the gating Godot harness + website coverage). `pnpm test:balance` runs the CPU balance smoke — CPU-BALANCE, non-held-out seeds only — in its own process with its own progress guard. `pnpm test:balance:audit` prints the tuning corpus (40 seeds, `CpuLadder.AUDIT_SEEDS`), a line per duel, and asserts nothing; `pnpm test:balance:accept` runs the held-out ladder (CPU-ACCEPT), once after a tuning pass. Every CPU duel prints a progress line, so the no-output guard stays a hang detector, never a budget. `pnpm test:fast` skips coverage. `pnpm check` runs `--import`, lint, typecheck, format, docs, arch, integrity, security, and `test:tooling`; it MUST NOT re-run behavior suites. `pnpm verify` is check → test → test:balance → build.

A hang guard detects hangs; it is never a budget. Each tier's guard is a **progress** guard: the Godot process is killed only after 480 s with no output (`spawnGodotWatched`, which prints why), and `TestCase` prints a line as each case finishes, so adding suites or long cases can never make a progressing run look hung, and gameplay code is never optimised to fit the harness. The benchmark tier exists so a long, non-gating measurement stays out of the correctness run.

## Web coverage scope

`src/**/*.{ts,tsx}` except tests, `*.d.ts`, and `src/test/**`. Routes and layouts are covered too (`apps/web/src/app/AppRoutes.test.tsx`); do not exclude pages to dodge coverage. `test:coverage` then runs `apps/web/scripts/check-coverage-manifest.mjs`: a source file no test imports fails the gate. `apps/web/src/app/theme.test.ts` is the website contrast gate.

## Game harness

`game/tests/harness/headless_runner.gd` runs `SUITES` in order and prints one `RIPOSTE_RESULT` line. `RIPOSTE_TIER` selects the tier: `gate` (default) skips `BENCHMARK_SUITES`, `balance` runs only them; a named `RIPOSTE_SUITE` runs regardless of tier. A suite fails on any failed assertion, a zero-assertion case, or leaked orphan nodes; the runner fails on engine errors or ObjectDB leaks at exit (the root waits briefly so the audio thread releases stopped voices). Cases are `test_*` methods and may `await`.

| Area         | Suites (suite name)                                                                                                                                                                                                                                       | Proves                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Harness      | HARNESS                                                                                                                                                                                                                                                   | Assertion semantics, vacuity detection                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Domain       | MATH, CMD, RULES, SCALING, INVARIANT, SIDE, FUZZ, MOVE, FACE, ATTACK, BURST, COMMIT, MOTION-COMMIT, COLLIDE, CONTACT, CONTACT-INTEGRITY, CONTACT-INTEGRITY-SHIP (audit tier), FRICTION, DAMAGE, SEMANTICS, ROUND, REPLAY, SYM, IMPACT, GENERIC, CONDITION | Determinism, input language, physical baseline and scaling laws, per-tick totality, cardinal sides and the locked world orientation, generated-input properties (including a fully mirrored opening) and graceful handling, physics, directional commitment as stopping-time laws (never a tuned rate), physical parry and whiff-as-label, the sword-contact gradient and μ = 0 tangent law, rigid contact held over a live seeded corpus (every tick within the slop, no crossing, no saturation, zero fallbacks on the ship corpus) and under walking and motor pressure, burst footwork, damage, swing semantics as descriptions only, rounds, replay + tamper detection, point symmetry, heterogeneous combatants, damage-driven condition |
| Application  | INPUT, DRIVER, SETTINGS, TUTORIAL, SESSION, CPU, CPU-BALANCE, APP-SHELL                                                                                                                                                                                   | Input merge, clock/hitstop, persistence sanitizing + bus layout, coaching, sessions, CPU fairness + difficulty laws (CPU), balance smoke on non-held-out seeds (CPU-BALANCE) and difficulty order on held-out seeds (CPU-ACCEPT, its own tier — a failure is a balance shift, not a broken law), UI scale, safe area, glyph coverage, every `InputActions` name in the InputMap, side-by-side menus only on short landscape screens                                                                                                                                                                                                                                                                                                            |
| Presentation | PRES-THEME, PRES-KIT, PRES-SNAPSHOT, PRES-CAMERA, PRES-PRESENTER, PRES-CONTACT, PRES-READABILITY, PRES-HUD                                                                                                                                                | Contrast (independent formula), theme variations, kit resolution, projection, framing, feedback, drawn swords meeting at the authoritative contact (CONTACT-PRESENTATION-001), every combat cue on two senses with settings that never change the duel (COMBAT-READABILITY-001), HUD, touch                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| End to end   | APP-E2E, FULL-E2E                                                                                                                                                                                                                                         | APP-E2E: real `main.tscn` lifecycle — menu → quick play → results → rematch → pause → quit; training; settings persistence. FULL-E2E: gameplay through real input, ticks, and solver — terminal scenarios, a full CPU set, victory, rematch, no state leaks                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |

There are three tiers, and a claim names the tier that proves it:

- **Presenter integration** (PRES-PRESENTER, PRES-RIG): a real `MatchPresenter` fed snapshots and events a test builds. It proves the presentation contract — one death, one sword, the terminal policy, clocks, latches — but its inputs are constructed, so it is not gameplay proof.
- **App lifecycle** (APP-E2E): the shipped scene and screens, with an idle or touch-driven human against the CPU. It proves the app flow, not specific combat outcomes.
- **Full gameplay** (FULL-E2E): the shipped scene from Quick Play, the human driven only through real input (`AppDriver.hold_move` presses the move actions and dash modifier on the Input singleton; the attack key goes through `push_input`), one frame per tick, and the real clock, solver, presenter, results, and victory showcase. Terminal scenarios (slash kill, lethal thrust, nonlethal poke, walk-off, shove off the edge, mirror colorway, next-round cleanup, leaving the victory), the COMBAT exchange (a clash pressed, slid along and disengaged into a riposte, the scrape held and let go with the contact), the three combat journeys (PROBE-EVASION: a back-dash before the release makes a tap miss, against a standing control it meets; PARRY-RIPOSTE: a wound guard parries a tap and the released wind lands; BAIT: giving ground with the sword wound makes a full advancing cut whiff — their scripted attackers judge measure on what they saw 100 ms earlier, and each asserts the order of facts, never a tick count) and the POST-ROUND journeys (the winner walking on through the result, pushing the body, the next round arriving clean) stand a scripted opponent (`ScenarioController`) opposite the human through the test-only `RiposteApp.compose_session` seam on a pinned seed; their human scripts were found by searching the solver, and each case asserts the outcome it needs as a fixture before judging presentation, so a tuning change that moves a scenario fails loudly. The canonical case plays a whole set against the real CPU: intro once, clean rounds, the set resolved by the solver, the winner shown once from authority, results locked until the cinematic ends, the replay verified, then a Rematch that is a fresh, introduced set and a clean exit. Exact rigid-body tumbles and pixels are never asserted; they are device QA.

E2E suites drive frames through `MatchScreen.advance_frame` / `ResultsScreen.advance_frame` (the same path `_process` uses) with `_process` disabled, pin seeds, and use a scratch settings file. Shared fixtures live in `game/tests/harness/` (`DuelFixture.of_type` is the one event filter; `AppDriver` boots and drives the shipped scene).

Balance tool (not a suite): `pnpm test:balance:audit` (or `godot --headless --path game --script res://tools/balance_report.gd`) prints CPU-vs-CPU matchups (wins, rounds, hits, parries, charge, round length) with the shipping rules over the fixed 40-seed tuning corpus, disjoint from the smoke and held-out corpora (`CpuLadder`); read-only. The pnpm command runs the ladder only; run the tool directly for the slow mirror-match tactics table. `tools/feel_report.gd` (40 CPU duels) also breaks first impacts down by region — blade/blade, blade on a crossguard or handle, hilt on hilt — against separation, θ, swinging swords, blade fraction, closing speed and the CPUs' own preferred distances, which is how a hilt-heavy histogram is told apart as CPU spacing (inside sword range) or geometry (at fencing distance). `tools/swing_speed_report.gd` prints peak forte, centre-of-percussion and tip speeds at tap, half and full charge against a human reference. `tools/perf_report.gd` plays Hard-vs-Hard Quick Play matches with the real presenter mounted and prints per-frame cost (mean / p50 / p99 / max) of the authoritative step (split by held blade contact), both CPUs, the presenter's push and render, and the whole frame; `-- --sim-only` drops the presenter to give the engine floor (see [performance](../architecture/PERFORMANCE.md#measured)).

Same-tick fixtures (a kill and a ring-out in one tick, ROUND and PRES-PRESENTER) assert their own preconditions — both events on one tick and the intended `lethal_fraction` / `support_lost_fraction` order — before the production reading, so a geometry change fails as "no longer kill-first", never as a mystery winner.

## Test design (TEST-TRUTH-001)

ARRANGE (assert the fixture) → PERTURB → ACT (production code) → ASSERT (independent expectation). Lint rejects tautologies, commented-out or skipped assertions, and `Engine.time_scale` changes. Do not add tests whose only job is to inflate coverage.

Oracles are written from the rules, never from the implementation. A test that re-derives its expectation by reimplementing the code under test will agree with that code's bugs. For physical behaviour prefer ordered comparisons (`quality_a > quality_b`) so the suite survives deliberate balance tuning; reserve exact assertions for known formulas, determinism, replay fixtures, and boundaries.

Scenarios reach their configurations through the simulation (SCENARIO-REACHABILITY-001). Placing two fighters body-to-body with a centred Long Guard between them skips the point contact that live play would have resolved first; a test built that way asks the solver to fix a state the game cannot reach. Place a penetrating start only when recovery from it is the subject, and say so in the test. Hand-placed fixtures are written in metres of a particular geometry: when the hilt track changes, move them by the measured reach change and re-check what each fixture asserts about itself, rather than loosening the assertions.

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

## When each test runs (TEST-TIER-001, TEST-OWNERSHIP-001)

Run the tiny truth tests while implementing; save the broad ones for checkpoints. `game/tests/suite_manifest.json` gives every suite a size and a measured budget, and every production script an owning area, so the cheap loop is chosen by the code that changed rather than by worry.

| Size        | What it holds                                                             | When                                  | Command                                                                              |
| ----------- | ------------------------------------------------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------ |
| **fast**    | local laws: math, frame movement, commitment, friction rows, contact rows | continuously, seconds                 | `pnpm test:changed` (what the working tree touched), `pnpm test:focused fast`        |
| **focused** | an affected subsystem: contact, weapon, movement, CPU, presentation, app  | after a coherent slice, a few minutes | `pnpm test:focused contact` (areas or suite names: `pnpm test:focused MOVE REPLAY`)  |
| **gate**    | every correctness suite, plus replay goldens, fuzz and the E2E journeys   | once per feature-complete batch       | `pnpm test`                                                                          |
| **audit**   | CPU smoke, tuning and held-out ladders; contact ship corpus; frame cost   | release checkpoints, by hand          | `pnpm test:balance`, `:audit`, `:accept`; `pnpm test:contact:ship`; `pnpm test:perf` |

The selective commands skip Godot's asset import; run `pnpm game:import` (or pass `--import`) once per session, and again after adding assets or a `class_name` script. A changed test file selects only its own suite, a docs change selects nothing (`pnpm docs:check`), and a production file with no owning area fails the selection until the manifest names one.

The loop:

1. **Implementing.** Parse or lint, then `pnpm test:changed`. Never the full gate, a corpus, a balance tier or every E2E.
2. **Feature complete.** `pnpm test:focused <area>`; fix local failures; leave unrelated suites alone.
3. **Batch complete.** One `pnpm test`. If it is red: classify every red, reproduce each at the lowest useful layer, fix them all, rerun only the red suites (`pnpm test:focused <SUITE>…`), then one final `pnpm test`. Never a full rerun per fix.
4. **Release checkpoint.** The audits, `pnpm check`, then one human acceptance.

A rules version still names every gameplay change, but it is not a ceremony: goldens are re-pinned once per batch, after the replay diff is explained mechanism by mechanism. The exception is a refactor that must be hash-identical, where the goldens are the acceptance test for each step.

Each law has one owner (TEST-OWNERSHIP-001). A journey proves that real input reaches the interaction and the player sees the result; it never re-proves the Coulomb bound, the commitment curve or the contact slop. When a broad test finds a bug, the permanent regression goes down to the owning suite first. The FULL-E2E combat journeys are kept to the canonical few — the full set, spacing beats a tap, the bait whiff, parry–riposte, clash–slide–disengage, the Long Guard poke and thrust, the slash terminal, ring-out, the fallen body, winner control into the next round.

Probes for one-off discovery live outside the project (`godot --headless --path game --script <absolute path>` runs them with every game class available), so they are never imported, parsed by `scripts:check`, or left behind.

## Gates a person runs

Two gates are deliberately not automated, because what they check is a human reading a screen rather than a value in a state: the combat-feel and readability gate ([combat-feel-gate.md](./combat-feel-gate.md)), which blocks the mechanics freeze, and the real-device pass ([device-qa.md](./device-qa.md)). Both list what the suite already proves, so the hand pass is spent on the part only a hand can reach.

## Tuning against the test set

Where a test grades an emergent outcome rather than an authored value, the seeds it grades on are part of the contract. CPU difficulty keeps two disjoint corpora — calibration seeds to read while tuning, acceptance seeds that grade and are never inspected — and the one claim too small to resolve at an affordable sample size is measured by a tool instead of gated. See [docs/concepts/cpu.md](../concepts/cpu.md#how-difficulty-is-tested-and-what-the-tests-can-prove). Raising a sample until a gate passes re-creates exactly the overfitting the split prevents.

## What tests cannot prove

Legibility at arm's length and the behaviour of an actual hand on glass. Everything mechanical about touch — heading-relative steering, simultaneous thumbs on independent indices, all four burst gestures with their negatives, OS cancellation — is driven through the shipped `main.tscn` in APP-E2E, because a simulated `InputEventScreenTouch` is a real one as far as the game is concerned. The rest is a written procedure: [device QA](./device-qa.md).

## Commands

```bash
pnpm test                                   # gating harness + web coverage
pnpm test:balance                           # CPU balance smoke (own process)
pnpm test:balance:audit                     # CPU tuning corpus report (40 seeds)
pnpm test:balance:accept                    # CPU held-out ladder (once after tuning)
pnpm test:contact:ship                      # contact ship + development corpora (audit)
pnpm test:perf                              # frame-cost report (never a gate)
pnpm test:changed                           # suites owning the working tree's changes (no import)
pnpm test:focused contact MOVE              # areas or suite names (no import)
pnpm game:import                            # Godot asset import: once per session / after new assets or class_name scripts
pnpm test:fast                              # without coverage
pnpm --filter @riposte/web test:coverage    # web only
RIPOSTE_SUITE=APP-E2E pnpm --filter @riposte/game test   # one game suite
```
