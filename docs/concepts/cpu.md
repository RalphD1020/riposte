# CPU

> See also: [spec/invariants.md](../../spec/invariants.md) — CPU-001, SIM-RNG-001
> See also: [docs/concepts/combat.md](./combat.md)
> Source: `game/src/application/cpu/`

The CPU is a utility-scoring controller that emits the same `PlayerCommand` a human would (CPU-001).

## Perception

- Own body and weapon: read now (proprioception).
- Opponent: a reaction-delay memory (`CpuObservation`), extrapolated by observed velocity in proportion to anticipation skill. Never hidden state, never future commands.
- Opponent **vulnerability**: their exposure, which is a reading of their body — weapon displaced, swing committed, balance lost, angle poor — and exactly the reading the player's own snapshot carries. It arrives delayed like everything else here. The CPU never receives a strike quality, because before contact nobody knows what a hit would do (COMBAT-009).

`opp_opening` is the part of that exposure which is actually an opening: the raw fraction never reaches zero, because a composed duelist is still a target, so a decision scored against it would leave the CPU permanently a little tempted by a perfect guard.

## Decisions

At its decision cadence the CPU scores:

- **Footwork**: approach to the range its weapon wants, retreat from threats, retreat from point threats (opponent's tip aimed with forward motion), re-take measure when smothered, orbit against committed rotation or point alignment, bait just outside reach.
- **Attacks**: taps for probes, punishes, and interceptions from good range; held swings from outside measure (charge arises from hold duration and opportunity, not from a separate CHARGE intent).
- **Point-threat awareness**: the CPU reads the opponent's sword-tip alignment and closing velocity as a `point_threat` reading in [0, 1]. Higher readings increase retreat and orbit urgency, scaled by the profile's `point_threat_weight`. Easy ignores point threats; Hard respects them strongly.
- **Condition awareness**: the CPU observes the opponent's coarse health band (`HEALTHY`, `HURT`, `WOUNDED`, `CRITICAL`) for tactical context.
- **Tactical assessment** (`TacticalAssessment`): compact derived state computed fresh each decision from observation + own fighter state. One pure evaluator across all difficulties (CPU-004). Signals include:
  - **Measure quality**: how close to preferred range (0–1)
  - **Initiative**: time differential (seconds, positive = own fighter threatens first)
  - **Tempo opportunity**: opponent in recovery/overswing and own fighter can arrive in time (0–1)
  - **Indes opportunity**: opponent committed and own tap can intercept (0–1)
  - **Line advantage**: own blade alignment toward opponent (0–1)
  - **Arena pressure**: opponent closer to edge relative to own edge distance (−1 to +1)
  - **Withdrawal urge**: urgency to retreat after own committed attack (0–1)
  - **Burst scores**: utility evaluation for all 4 burst directions (forward, backward, clockwise, counterclockwise)
- **Corner pressure**: harder profiles press more aggressively when the opponent is near the arena edge (`corner_pressure_weight`).
- **Tempo exploitation**: profiles with higher `tempo_awareness` punish recovery/overswing windows with approach and tap utility.
- **Withdrawal discipline**: after own committed attack, profiles with higher `withdrawal_discipline` retreat or orbit.
- **Standoff pressure** builds over time until someone commits.
- **Dashes**, by _typing the gesture_: full deflection, a genuine return to rest, full deflection again, on its own command stream. `DirectionalTapRecognizer` reads it exactly as it reads a thumb. There is no private dash call, which is what guarantees the CPU cannot reach a movement state a player cannot — and the test proves it behaviourally, by replaying the recorded commands with no CPU present and getting every dash back. **All four burst directions** are available: forward dash, back dash, left step, right step. Axial bursts (approach/retreat) and lateral bursts (orbit side-step) go through the same gesture path; `lateral_dash_weight` controls how often the CPU commits to a side-step.
- **How far to wind back**: a draw from the profile's band, leaned toward the top of it by how open the target looks. Deliberately a lean rather than a formula — replacing the draw outright made the CPU more readable, not better, and the ladder measured it.

The CPU never releases on a clock. It holds until the wind-back it wanted has physically been travelled (`weapon.charge >= _charge_target`), so its charge obeys the same displacement law a player's does. The one tick-based quantity left is a fail-safe for a blade that cannot travel at all — pinned, or already at the guard limit — and it is deliberately far longer than any real charge.

## Difficulty

`CpuProfile.for_difficulty` returns data only: reaction delay, cadence, anticipation, discipline, charge habits. Easy, Medium, and Hard play the same rules.

## How difficulty is tested, and what the tests can prove

Two seed corpora, because tuning a profile against the seeds that then grade it is training against the test set. `CALIBRATION_SEEDS` are for reading while tuning and nothing asserts on them; `ACCEPTANCE_SEEDS` grade the ladder and must not be inspected while tuning. They were fixed by a rule (the calibration block offset by 100), not chosen by searching for a block that passed.

Two kinds of claim, kept apart because they fail for different reasons:

| Kind            | Claim                                                                                                                                                                                                                                 | Where                                               |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| **Correctness** | Hard reacts sooner; Easy overcharges; Easy never dashes and Hard does; the CPU only observes state; it emits legal `PlayerCommand`s and reaches a burst through the player's own recognizer; no pre-contact strike quality reaches it | `test_cpu.gd`, structural — independent of who wins |
| **Balance**     | Medium and Hard each beat Easy decisively on held-out seeds                                                                                                                                                                           | `test_cpu.gd`, gated                                |
| **Effect size** | How much Hard actually beats Medium by                                                                                                                                                                                                | `game/tools/balance_report.gd`, measured not gated  |

Hard-over-Medium is deliberately **not** a gate. Measured over 200 duels on seeds outside both corpora: Medium and Hard each take Easy on about 88% of duels, but Hard takes Medium on only about 54.5% (match margin +18, round margin +42, health margin +1807). Sixteen duels cannot distinguish 54.5% from a coin — the acceptance block runs −2 for Hard — and lower-variance estimators do not rescue it, because within a single seed the match, round, and health margins move together rather than independently. A gate on that sign would fail for no code reason.

So the suite gates the part of the ladder that is unambiguous, and the effect size lives in the diagnostic tool. **That Hard's edge over Medium is this slim is a balance finding, not a resolved question**: the mechanisms are proven present, but they do not yet add up to an opponent a player would call clearly harder. Strengthening Hard is a design decision, and it belongs to a person — raise the sample until a gate passes and you have only re-derived the overfitting the split exists to prevent.

A stronger profile must be stronger at the thing the physics actually rewards, and three dials once quietly worked against Hard:

- **Decision cadence is not reaction speed.** Hard _perceives_ faster; it must not fidget faster. Re-picking footwork every few ticks is indecision, and indecision costs twice in a momentum game — the body never builds a coherent stride, and a fighter who keeps changing their own motion strikes with degraded structural coupling (PHYS-002).
- **`release_slack` is a lead allowance, not sloppiness.** A swing takes time to travel, so a fighter must release while the opponent is still _arriving_. Waiting until they are already inside reach is structurally late. A generous lead is only affordable if you know where they really are, so this rises with range accuracy rather than falling with it.
- **Caution counted once.** Strikes are already gated on range quality, so demanding a higher `attack_threshold` _and_ a timid charge ceiling on top produced a fighter who out-positioned opponents it never got around to hitting — measurably converting worse against Easy than Medium did.
- **A dash is a punctuation, not a gait.** `burst_weight` is a legitimate difficulty axis because it costs a profile nothing it is not entitled to: the gesture is available to everyone and Easy simply never types one. But a dash overrides steering intent and spends commitment, so dashing out of most decisive steps reads as twitchy _and_ loses more structure than the distance is worth. Hard sits near 0.18, not near 0.5; the ladder measured the difference.

A caution for anyone adding a new reading: the profile weights are calibrated against the _scale_ of the signals they multiply. Swapping a tuned binary term for a continuous reading of the same thing is a balance change even when it is strictly more information, and it flipped the Hard-over-Medium ordering every way it was tried. Give a new reading somewhere it adds information rather than somewhere it replaces a calibrated one, or recalibrate deliberately and measure.

Where to tune: profile weights (`cpu_profile.gd`) decide how much each consideration matters per difficulty; the named constants at the top of `cpu_controller.gd` are the heuristic's shape (thresholds, ramps, tolerances, steering) shared by every difficulty. `CpuObservation` carries only what decisions read, so the per-tick perception cost stays two `time_to_threat` calls. Measure changes with `game/tools/balance_report.gd`.

| Concept             | Code                                                |
| ------------------- | --------------------------------------------------- |
| Controller          | `game/src/application/cpu/cpu_controller.gd`        |
| Profiles            | `game/src/application/cpu/cpu_profile.gd`           |
| Delayed observation | `game/src/application/cpu/cpu_observation.gd`       |
| Tactical assessment | `game/src/application/cpu/tactical_assessment.gd`   |
| Decision trace      | `game/src/application/cpu/cpu_decision_trace.gd`    |
| Edge safety         | `game/src/application/cpu/edge_safety_evaluator.gd` |
| Edge safety result  | `game/src/application/cpu/edge_safety_result.gd`    |
| Behavior proofs     | `game/tests/application/test_cpu.gd`                |
| Edge safety proofs  | `game/tests/application/test_edge_safety.gd`        |

## Edge safety (CPU-006)

The CPU avoids voluntary self-ring-outs through a two-layer system:

- **Layer A (Safety)**: `EdgeSafetyEvaluator` is a pure stateless predictor using real motor laws (`locomotion_force/mass`, `burst_force/mass`, capability scaling from stamina/health). It forward-integrates position/velocity over a dynamic prediction horizon (`WALK_HORIZON_TICKS = 10` for walking, `burst_ticks + BRAKE_MARGIN_TICKS` for dashes). Returns `EdgeSafetyResult` with `crosses_platform`, `min_clearance`, `stopping_margin`, `recoverable`. The safety filter is **identical across all difficulties**.
- **Layer B (Tactical)**: `TacticalAssessment` edge features (`edge_clearance`, `outward_radial_speed`, `stopping_margin`, `opponent_edge_clearance`, `edge_position_advantage`) feed into CPU approach utility through `CpuProfile.edge_exploit_weight` (Easy=0.0, Medium=0.2, Hard=0.6). Difficulty changes only this tactical layer.

Walk safety only activates when the fighter is within `body_radius` of the platform edge — further out, the edge steering in `_steer()` handles avoidance. Burst safety is the hard filter: any burst whose predicted trajectory crosses the platform is suppressed. If no safe candidate exists, the CPU chooses maximum `min_clearance` (survival), never an invisible wall or idle clamp.

The CPU remains fully vulnerable to forced ring-outs from combat physics. The safety layer prevents voluntary walks and dashes off the cliff; it cannot prevent a knockback impulse or body separation from pushing the fighter past `platform_radius`.

## Decision traces

`CpuDecisionTrace` is a structured sidecar emitted per CPU decision. It carries fixed typed fields — utility scores, chosen move/attack, tactical assessment scalars, burst state — never dictionaries. Traces are diagnostic telemetry, never authoritative: they are not hashed, not replayed, and not fed back into the simulation.

Traces accumulate in `CpuController.traces` during a round and are cleared on round boundaries. The schema is documented in [docs/architecture/ml-readiness.md](../architecture/ml-readiness.md).
