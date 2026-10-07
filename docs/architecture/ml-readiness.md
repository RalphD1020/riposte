# ML-Readiness Schema

> See also: [docs/concepts/cpu.md](../concepts/cpu.md), [spec/invariants.md](../../spec/invariants.md) — CPU-001, SIM-002
> Source: `game/src/application/cpu/cpu_decision_trace.gd`, `game/src/domain/replay/replay_record.gd`

> Data contracts for future ML training. No training happens now; these schemas define what a pipeline would read.

## Authoritative replay

A `ReplayRecord` is the canonical truth of a duel. Everything else is derived from it plus the versioned rules:

| Field           | Type             | Description                                 |
| --------------- | ---------------- | ------------------------------------------- |
| `rules_id`      | StringName       | Content id of the rule set                  |
| `rules_version` | int              | Semantic version — mismatches reject replay |
| `seed_value`    | int              | Match seed (RNG, side assignment)           |
| `commands_0`    | PackedInt32Array | Packed PlayerCommands for slot 0            |
| `commands_1`    | PackedInt32Array | Packed PlayerCommands for slot 1            |
| `final_hash`    | String           | State hash at match end (determinism proof) |

Events are **derived**: re-simulating commands + versioned rules regenerates them exactly. Events are persisted for convenience/analytics but are not authoritative if they disagree with a re-simulation under the same rules version.

## ObservationVector

Only information available to the player/CPU at decision time. Corresponds to `CpuObservation` + own `FighterState`:

| Field                | Type  | Range       | Source                                |
| -------------------- | ----- | ----------- | ------------------------------------- |
| `own_x`, `own_y`     | float | arena       | FighterState (proprioception, no lag) |
| `own_vx`, `own_vy`   | float | m/s         | FighterState                          |
| `own_facing`         | float | radians     | FighterState                          |
| `own_health`         | float | [0, max]    | FighterState                          |
| `own_stamina`        | float | [0, max]    | FighterState                          |
| `own_weapon_phase`   | int   | CombatPhase | FighterState.weapon                   |
| `own_weapon_charge`  | float | [0, 1]      | FighterState.weapon                   |
| `own_commitment`     | float | [0, 1]      | FighterState.weapon                   |
| `own_stability`      | float | [floor, 1]  | FighterState                          |
| `opp_x`, `opp_y`     | float | arena       | CpuObservation (lagged)               |
| `opp_vx`, `opp_vy`   | float | m/s         | CpuObservation (lagged)               |
| `opp_phase`          | int   | CombatPhase | CpuObservation (lagged)               |
| `opp_charge`         | float | [0, 1]      | CpuObservation (lagged)               |
| `opp_commitment`     | float | [0, 1]      | CpuObservation (lagged)               |
| `opp_exposure`       | float | [0, 1]      | CpuObservation (lagged)               |
| `opp_point_threat`   | float | [0, 1]      | CpuObservation (lagged)               |
| `perceived_distance` | float | m           | Derived from sighting                 |
| `initiative`         | float | seconds     | TacticalAssessment                    |
| `measure_quality`    | float | [0, 1]      | TacticalAssessment                    |
| `stamina_depletion`  | float | [0, 1]      | TacticalAssessment                    |
| `tempo_opportunity`  | float | [0, 1]      | TacticalAssessment                    |
| `arena_pressure`     | float | [-1, 1]     | TacticalAssessment                    |

## ActionChoice

One of the exact human semantic actions. The action space is constant across all difficulties — difficulty is evaluation quality, not action availability:

| Category | Values                               |
| -------- | ------------------------------------ |
| Move     | HOLD, APPROACH, RETREAT, ORBIT, BAIT |
| Attack   | NONE, TAP, HOLD                      |
| Burst    | NONE, FORWARD, BACKWARD, LEFT, RIGHT |

A single decision emits one Move + one Attack + optionally one Burst. There is no composite "dash-attack" action — the CPU decides to dash and decides to attack independently, using the same timing rules as humans (CPU-001).

## OutcomeLabel

Local outcomes for reward/value estimation. Measured at the decision's temporal horizon (the next few ticks or the next decision):

| Field                 | Type  | Description                                  |
| --------------------- | ----- | -------------------------------------------- |
| `damage_dealt`        | float | Damage the decision led to dealing           |
| `damage_received`     | float | Damage taken in the window                   |
| `measure_improvement` | float | Δ measure_quality from this decision to next |
| `initiative_change`   | float | Δ initiative                                 |
| `stamina_change`      | float | Δ stamina (negative = spent)                 |
| `hit_landed`          | bool  | Own strike connected                         |
| `hit_received`        | bool  | Opponent strike connected                    |
| `round_result`        | int   | +1 won, -1 lost, 0 ongoing                   |

## CpuDecisionTrace

Structured sidecar emitted per CPU decision. Fixed typed fields, never dictionaries:

| Field                     | Type               | Description                                                       |
| ------------------------- | ------------------ | ----------------------------------------------------------------- |
| `tick`                    | int                | Decision tick                                                     |
| `observation_tick`        | int                | Tick of the observation used                                      |
| `move_scores`             | PackedFloat64Array | Utility scores [5]                                                |
| `chosen_move`             | Move enum          | Selected footwork                                                 |
| `chosen_attack`           | Attack enum        | Selected attack intent                                            |
| `measure_quality`         | float              | From TacticalAssessment                                           |
| `initiative`              | float              | From TacticalAssessment                                           |
| `stamina_depletion`       | float              | From TacticalAssessment                                           |
| `tempo_opportunity`       | float              | From TacticalAssessment                                           |
| `arena_pressure`          | float              | From TacticalAssessment                                           |
| `burst_started`           | bool               | Whether a burst gesture was launched                              |
| `burst_is_lateral`        | bool               | Lateral vs axial burst                                            |
| `edge_clearance`          | float              | Own distance from platform edge (platform_radius - center_dist)   |
| `outward_radial_speed`    | float              | Positive = moving toward edge                                     |
| `stopping_margin`         | float              | Worst outward radial speed at farthest predicted trajectory point |
| `voluntary_ring_out_risk` | float              | 1.0 if chosen move crosses platform, else 0.0                     |

Source: `game/src/application/cpu/cpu_decision_trace.gd`
