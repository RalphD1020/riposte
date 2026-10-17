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

"When" is as much a rule as "what", so the sequence is versioned: `DuelSimulation.TICK_ORDER_VERSION` (currently **16**) must be bumped deliberately whenever it changes. Version 15 is the stamina settle after contacts (rules 53). Version 16 inserts impact-authority recovery between contact lifecycle and that settle (rules 57). Rules 56 left the version at 15 because the dip stayed inside the contact step and authority did not recover until the round reset. Stamina does not read authority, and authority does not read stamina, so their relative order is not visible in either value; the version records that the recovery step exists. Symmetric by construction — per-fighter updates read only start-of-tick relationships, so slot order never biases outcomes, and fighter A is never advanced and then used as fighter B's input. The numbered list is the sequence pinned in `duel_simulation.gd`.

```text
 1. guard: a finished match accepts no further steps
 2. dispatch on match phase
 3. ROUND_ACTIVE: advance phase and round counters
 4. freeze condition for both fighters (from start-of-tick health and
    stamina, CONDITION-001, STAMINA-004)
 5. capture start poses for both fighters
 6. consume attack input edges for both fighters
 7. compute tracking multipliers from start-of-tick state
 8. facing then footwork for both fighters
 9. weapon motor and weapon phase for both fighters
10. arena boundary confinement only (body separation shares the TOI loop)
11. capture finish poses for both fighters
12. contacts (RIGID-CONTACT-001, COMBAT-007): persisted sword contacts,
    the chronological loop, then the position stage
13. contact lifecycle upkeep (blade manifold + weapon-body)
14. impact authority recovers toward 1, except a sword this tick's steel
    episode dipped (IMPACT-AUTHORITY-001)
15. settle stamina once from the motors' own work (measured in steps 8–9,
    before any contact) and a dash start (STAMINA-004)
16. round end evaluation
17. advance the tick counter
18. validate invariants; fail closed on violation
```

The contact step is itself a bounded loop rather than a single pass, because contacts inside one tick are ordered in time and the later ones depend on the earlier ones (COMBAT-007). All contact types share the same chronology:

```text
hold persisted contacts touching at the start (velocity stage); re-carry the tick
loop until max_contacts_per_tick new contacts (holds spend HOLDS_PER_TICK):
    find the earliest contact among blade↔blade, blade→body, body↔body,
        and persisted pairs driven past twice the slop
    if none: stop
    seek both fighters to that time of impact
    resolve the contact according to its interaction type:
        blade↔blade → bilateral rigid impulse (changes both weapons)
        blade/tip→body → one contact impulse (PHYS-008: body receives damage/push;
                          the blade reacts through its lever, J·c/M_θ — a centred
                          point has c ≈ 0 and drives through)
        body↔body → inverse-mass impulse (changes body velocities, never weapons)
        persisted pair → normal constraint (closing removed, no event)
    re-hold every held contact from the post-resolution velocities
        (a hold that arrested a driven cut ends it — phase only, nothing moves)
    carry the remainder of the tick forward from the post-resolution state
        (budget spent: in sweep substeps, each substep's overlap pushed out)
    the impact pose becomes the new start; the carried pose the new finish
push persisted overlap back to contact_slop (position stage)
```

A new steel episode dips each sword once from that contact's own solved change in angular velocity. A torso entry does not. Later holds of the same episode do not dip; on those ticks, and on every other living tick, the deficit fades at the guard return's natural frequency. The dip is inside the contact step. Recovery is the next step, and it does not run for a sword that dipped on that tick. Stamina settles after that (IMPACT-AUTHORITY-001).

A contact is reported on the substep it comes into touch, never on every substep it stays touching: a held contact is already a constraint, and re-reporting it only spends the budget. Bodies meet at most once a tick; overlap left later in the tick is separated where each remainder is carried. Before this rule, pressed bodies re-reported every substep, exhausted the budget, and the unswept rest of the tick let a blade pass straight through a held contact. The re-hold budget itself is a fixed bound (`HOLDS_PER_TICK`), never raised to make a counter read zero; a tick that spends it carries its remainder in the sweep's own substeps with the position stage after each (CONTACT-FALLBACK-001), so the pair keeps its last non-penetrating side, only the advance along the normal is cancelled, tangent slide, θ̇ and every other motion carry on, and the next tick starts with the full budget. On 70 adversarial storms it holds the worst held overlap at the slop (2.3 mm, against 3.45 cm unbounded). Representative play reaches it only as the bounded fast-slide class — one contact sliding fast along a turning blade, closing again after each re-hold — classified and counted against its measured baseline (CONTACT-REHOLD-FALLBACK-001).

The position stage solves its rows together. A sword pinned between the opponent's blade and torso (typically at the opponent's guard end; since rules 35 the crossguard and handle collide too, the hands never) has two rows pushing it in opposite directions; corrected one after the other each undoes the other, and only the opponent's weapon rotation — the one motion that separates them — makes progress. Solved as one small complementarity problem (at most four rows — the blades, each sword on the other's torso, and the two bodies — fixed-order active-set enumeration) the correction goes straight to that rotation, bounded per pass so nothing teleports. The bodies are a row because a Long Guard blade that starts past the opponent's centre pushes that torso back toward its wielder: cleared on its own, the overlap would drive the bodies into each other. A separated body pair rests 1 nm outside touching, the same rule as held swords resting at the slop below their re-hold line: detection at exactly touching must never be decided by rounding.

### Totality

The simulation is a closed state-transition system, so every legal state/command pair has a defined successor and anything outside that set is a defect rather than a state to improvise from. `StateInvariants.check(state, rules)` runs at step 18 and returns the id of the first violated invariant in a fixed order: finiteness of every authoritative scalar, `|angle| ≤ guard_limit`, health within `[0, max_health]`, stability within `[floor, 1]`, charge and commitment within `[0, 1]`, earned wind-back within the span that buys full charge, non-negative counters, agreement between death and the `DEAD` weapon phase (one phase enum makes `DEAD and CHARGING` unrepresentable), and a contact pair that has not outlived its bind escape bound.

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

There are three levels of the promise, and only the first is made:

| Level | Promise                                                              | Status                                                                                                                                                     |
| ----- | -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A     | Same inputs, same build, same platform → bit-identical duel and hash | **Shipped.** REPLAY, FUZZ and the per-tick hash tests prove it every run.                                                                                  |
| B     | Bit-identical across operating systems, CPUs, and the Web export     | Not claimed. Decided with networking; needs a cross-platform gate before it can be.                                                                        |
| C     | Lockstep or rollback netcode over two peers' simulations             | Not claimed. A fixed tick does not imply it, and server-authoritative play may need neither B nor C — only the server's simulation has to be the true one. |

## Match flow

`MatchPhase`: `ROUND_INTRO → ROUND_ACTIVE → ROUND_RESULT → … → MATCH_ENDED`. A round ends on a kill, a trade, or timeout (more health wins). A trade is two deaths in the same tick, and it is decided by which blade arrived first: `FighterState.lethal_fraction` records the sub-tick instant of each death, the fighter who fell later takes the round as `REASON_TRADE_FIRST_CONTACT`, and only an exact tie is a draw (`REASON_DOUBLE_KILL`). Slot number, attacker role, and remaining health are deliberately not consulted — any of them would make the arena asymmetric. A ring-out is ordered the same way (COMBAT-014): every `RING_OUT` records `support_lost_fraction`, the sub-tick instant the centre crossed the edge, and `FighterState.terminal_kind()` / `terminal_time()` read a fighter's way out as whichever of the lethal blow and the lost footing came first. When both fighters left the round in one tick, the one who left later wins and the reason is the loser's way out (`REASON_RING_OUT`, or a kill reason); a fighter who crossed the edge and then landed a kill later in the tick was already out, and a dead fighter never wins by an opponent's later fall. `rounds_to_win` decides the match; a set is one match.

A decided round is not a cutscene. `POST_ROUND_FREE` and `ROUND_RESULT` run one shared step, and one gate, `DuelSimulation.accepts_gameplay_input`, keeps the round's winner — alive, on the platform — in full control until exactly the next `ROUND_INTRO` or the end of the match; the loser's commands are ignored. The killed fighter is a **body** (FALLEN-BODY-001): thrown along the killing impulse, lying once its collapse is over as a capsule through its centre of mass, sliding on ground friction rather than braking, pushed and turned about its centre of mass by the winner's push circle through the same kind of contact impulse as every other collision, and — pushed over the rim — a post-round corpse fall that changes nothing about the result. Nothing in the decided round can change who won.

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
