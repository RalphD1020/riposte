# Simulation

> See also: [spec/invariants.md](../../spec/invariants.md) — SIM-001, SIM-002, SIM-MATH-001, SIM-RNG-001, CMD-001, HITSTOP-001
> See also: [docs/concepts/combat.md](./combat.md), [docs/concepts/cpu.md](./cpu.md)
> Source: `game/src/domain/`, `game/src/application/match/`, `game/src/application/clock/`

One deterministic 2D duel drives everything: Quick Play, Training, tests, replays, and (later) a server. Modes differ only in rules content and controllers.

## Layers

```text
domain       game/src/domain        pure, deterministic, no engine types (SIM-001)
content      game/content           authored rules + presentation kits (data)
application  game/src/application   sessions, controllers, CPU, clock, app shell
presentation game/src/presentation  reads snapshots, renders, plays feedback (PRES-001)
```

Dependency direction: application → presentation → domain; content is data any layer may read (rules content stays pure). Lint enforces it from `class_name`s.

## Tick

`DuelSimulation.step(state, command_0, command_1)` advances one 60 Hz tick (`SimulationTimebase.TICK_RATE`) and returns that tick's `DuelEvent`s. Order (symmetric: per-fighter updates read start-of-tick relationships, so slot order never biases outcomes):

```text
input edges → tracking + facing → footwork → weapon motor → arena → bind upkeep
→ swept collision → contact resolution → round flow
```

| Concept                                                                                  | Code                                                                                         |
| ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Rules (fighter, weapon, tuning, arena, format; `version` pins replays)                   | `game/src/domain/rules/duel_rules.gd`, values in `game/content/rules/standard_duel_rules.gd` |
| State (fighters, weapons, phase, scores)                                                 | `game/src/domain/state/`                                                                     |
| Commands (CMD-001)                                                                       | `game/src/domain/commands/player_command.gd`                                                 |
| Events: `DuelEventTypes` names, `DuelEventKeys` payload keys (lint rejects literal keys) | `game/src/domain/events/`                                                                    |
| Setup, round reset, orchestration                                                        | `game/src/domain/match/`                                                                     |
| Math (SIM-MATH-001)                                                                      | `game/src/domain/math/sim_math.gd`                                                           |
| RNG (SIM-RNG-001)                                                                        | `game/src/domain/rng/seeded_rng.gd`                                                          |
| Hash + replay (SIM-002)                                                                  | `game/src/domain/replay/`                                                                    |

## Determinism

- Scalar IEEE-754 doubles only; `SimMath` replaces engine trig/pow/lerp (libm and FMA differ across platforms). No `Vector2/3` in the domain.
- Fixed tick, never render delta. Movement in commands is quantized to milli-units.
- `StateHasher` → SHA-256 over every authoritative field's exact bits. Tests prove per-tick hash equality across runs, point symmetry, and replay verification with tamper detection.
- Rules change ⇒ bump `DuelRules.version`; `ReplayVerifier` rejects mismatched rules.

## Match flow

`MatchPhase`: `ROUND_INTRO → ROUND_ACTIVE → ROUND_RESULT → … → MATCH_ENDED`. A round ends on a kill, double kill (draw), or timeout (more health wins). `rounds_to_win` decides the match. During `ROUND_RESULT` bodies settle and nothing new can happen.

## Sessions and controllers

| Concept                                                                          | Code                                                             |
| -------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `MatchConfig` (mode, rules, seed, controllers, difficulty; `rematch()` re-seeds) | `game/src/application/match/match_config.gd`                     |
| `MatchComposer` (config → controllers → session)                                 | `game/src/application/match/match_composer.gd`                   |
| `MatchSession` (sim + state + controllers + replay record + event log)           | `game/src/application/match/match_session.gd`                    |
| Controllers: human, CPU, training dummy, replay                                  | `game/src/application/controllers/`, `game/src/application/cpu/` |
| Results stats                                                                    | `game/src/application/match/match_summary.gd`                    |

Every match and rematch composes a fresh `MatchSession`; nothing is reset in place.

## Clock

`FixedTickDriver` turns wall-clock frames into ticks: `consume(delta)` returns how many ticks to run (≤ `MAX_CATCH_UP_TICKS`), `alpha()` interpolates display, `hold()` is hitstop, `clear_backlog()` runs on resume (HITSTOP-001). `MatchScreen.advance_frame` is the only production caller.
