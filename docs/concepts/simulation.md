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

`DuelSimulation.step(state, command_0, command_1)` advances one 60 Hz tick (`SimulationTimebase.TICK_RATE`) and returns that tick's `DuelEvent`s.

### Canonical tick order

"When" is as much a rule as "what", so the sequence is versioned: `DuelSimulation.TICK_ORDER_VERSION` (currently **6**) must be bumped deliberately whenever it changes. Symmetric by construction — per-fighter updates read only start-of-tick relationships, so slot order never biases outcomes, and fighter A is never advanced and then used as fighter B's input.

```text
 1. guard: a finished match accepts no further steps
 2. dispatch on match phase
 3. ROUND_ACTIVE: advance phase and round counters
 4. freeze capability for both fighters (from start-of-tick stamina)
 5. capture start poses for both fighters
 6. consume attack input edges for both fighters
 7. compute tracking multipliers from start-of-tick state
 8. facing then footwork for both fighters (writes turn/movement exertion)
 9. weapon motor and weapon phase for both fighters (writes weapon exertion)
10. arena boundary confinement only (no body separation — that shares the TOI loop)
11. capture finish poses for both fighters
12. bind upkeep
13. unified chronological contact loop: detect earliest TOI among blade↔blade,
    blade→body, tip→body, body↔body, arena boundary; seek to impact; resolve
    according to interaction type (PHYS-008); carry remainder
14. stamina step: drain from scratch work, recovery if below threshold,
    apply contact shock, clamp
15. contact pair lifecycle upkeep (blade + weapon-body)
16. round end evaluation
17. advance the tick counter
18. validate invariants; fail closed on violation
```

Step 12 is itself a bounded loop rather than a single pass, because contacts inside one tick are ordered in time and the later ones depend on the earlier ones (COMBAT-007). All contact types share the same chronology:

```text
loop at most max_contacts_per_tick times:
    find the earliest contact among blade↔blade, blade→body, body↔body
    if none: stop
    seek both fighters to that time of impact
    resolve the contact according to its interaction type:
        blade↔blade → bilateral rigid impulse (changes both weapons)
        blade/tip→body → conditional coupling (PHYS-008: body receives damage/push;
                          non-stabbing contacts deflect the blade via reduced-mass
                          angular impulse; stabbing-angle contacts penetrate freely)
        body↔body → inverse-mass impulse (changes body velocities, never weapons)
    carry the remainder of the tick forward from the post-resolution state
    the impact pose becomes the new start; the carried pose the new finish
```

### Totality

The simulation is a closed state-transition system, so every legal state/command pair has a defined successor and anything outside that set is a defect rather than a state to improvise from. `StateInvariants.check(state, rules)` runs at step 16 and returns the id of the first violated invariant in a fixed order: finiteness of every authoritative scalar, `|angle| ≤ guard_limit`, health within `[0, max_health]`, stability within `[floor, 1]`, charge and commitment within `[0, 1]`, earned wind-back within the span that buys full charge, non-negative counters, agreement between death and the `DEAD` weapon phase (one phase enum makes `DEAD and CHARGING` unrepresentable), and a contact pair that has not outlived its bind escape bound.

Handling splits by source:

| Problem                                                                         | Response                                                                                                           |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| External or input (focus loss, touch cancel, duplicate edge, out-of-range axis) | Recover: `ATTACK_CANCELED`, clamp in `sanitized()`, ignore stale edges                                             |
| Non-finite or structurally impossible authoritative state                       | Fail closed: emit `SIMULATION_FAULT` with the invariant id, then end the match with `MatchPhase.REASON_NO_CONTEST` |

Failing closed deliberately does not repair the offending value: silently resetting the sword to a canonical guard would hide the defect and desynchronize replays. `SimRunner` validates every tick it produces, so behavioral suites prove totality for the ticks they drive.

| Concept                                                                                  | Code                                                                   |
| ---------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Rules (fighter, weapon, tuning, arena, format; `version` pins replays)                   | `game/src/domain/rules/duel_rules.gd`, values in `game/content/rules/` |
| State (fighters, weapons, phase, scores)                                                 | `game/src/domain/state/`                                               |
| Commands (CMD-001)                                                                       | `game/src/domain/commands/player_command.gd`                           |
| Events: `DuelEventTypes` names, `DuelEventKeys` payload keys (lint rejects literal keys) | `game/src/domain/events/`                                              |
| Setup, round reset, orchestration                                                        | `game/src/domain/match/`                                               |
| Per-tick totality check                                                                  | `game/src/domain/state/state_invariants.gd`                            |
| Math (SIM-MATH-001)                                                                      | `game/src/domain/math/sim_math.gd`                                     |
| RNG (SIM-RNG-001)                                                                        | `game/src/domain/rng/seeded_rng.gd`                                    |
| Hash + replay (SIM-002)                                                                  | `game/src/domain/replay/`                                              |

## Determinism

- Scalar IEEE-754 doubles only; `SimMath` replaces engine trig/pow/lerp (libm and FMA differ across platforms). No `Vector2/3` in the domain.
- Fixed tick, never render delta. Movement in commands is quantized to milli-units.
- `StateHasher` → SHA-256 over every authoritative field's exact bits. Tests prove per-tick hash equality across runs, point symmetry, and replay verification with tamper detection.
- Rules change ⇒ bump `DuelRules.version`; `ReplayVerifier` rejects mismatched rules.

The claim is scoped to **one build**: same build, same rules, same seed, same commands, same duel — bit for bit, hash included. Not "the same on every platform". `SimMath` exists to remove the engine's own drift (libm and FMA differ, and `lerp` is not the same function everywhere), and it does, but the double-precision result of a transcendental is still the platform's C library. Claiming cross-platform identity would be claiming something no gate here can check, and a determinism guarantee nobody verifies is worse than a narrower one that is true. Server-authoritative play, when it arrives, is what makes the stronger claim both necessary and testable.

## Match flow

`MatchPhase`: `ROUND_INTRO → ROUND_ACTIVE → ROUND_RESULT → … → MATCH_ENDED`. A round ends on a kill, a trade, or timeout (more health wins). A trade is two deaths in the same tick, and it is decided by which blade arrived first: `FighterState.lethal_fraction` records the sub-tick instant of each death, the fighter who fell later takes the round as `REASON_TRADE_FIRST_CONTACT`, and only an exact tie is a draw (`REASON_DOUBLE_KILL`). Slot number, attacker role, and remaining health are deliberately not consulted — any of them would make the arena asymmetric. `rounds_to_win` decides the match. During `ROUND_RESULT` bodies settle and nothing new can happen.

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

## Replay architecture

`ReplayRecord` is the canonical truth of a duel. Everything needed to reproduce one is commands + rules identity + seed:

| Field           | Role                                        |
| --------------- | ------------------------------------------- |
| `rules_id`      | Identifies which rule set                   |
| `rules_version` | Semantic version — mismatches reject replay |
| `seed_value`    | Match seed (RNG, side assignment)           |
| `commands_0/1`  | Packed `PlayerCommand` streams              |
| `final_hash`    | State hash at match end                     |

Events are **derived**: re-simulating commands + versioned rules regenerates them identically, which `ReplayVerifier` proves. Events are persisted for convenience/analytics but if stored events disagree with a re-simulation under the same rules version, commands win.

CPU decision traces (`CpuDecisionTrace`) are diagnostic sidecars, never part of the authoritative record. See [docs/architecture/ml-readiness.md](../architecture/ml-readiness.md).
