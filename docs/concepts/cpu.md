# CPU

> See also: [spec/invariants.md](../../spec/invariants.md) — CPU-001, SIM-RNG-001
> See also: [docs/concepts/combat.md](./combat.md)
> Source: `game/src/application/cpu/`

The CPU is a utility-scoring controller that emits the same `PlayerCommand` a human would (CPU-001).

## Perception

- Own body and weapon: read now (proprioception).
- Opponent: a reaction-delay memory (`CpuObservation`), extrapolated by observed velocity in proportion to anticipation skill. Never hidden state, never future commands.

## Decisions

At its decision cadence the CPU scores:

- **Footwork**: approach to the range its weapon wants, retreat from threats, re-take measure when smothered, orbit against committed rotation, bait just outside reach.
- **Attacks**: taps for probes, punishes, and interceptions from good range; charged swings from outside measure.
- **Standoff pressure** builds over time until someone commits.

## Difficulty

`CpuProfile.for_difficulty` returns data only: reaction delay, cadence, anticipation, discipline, charge habits. Easy, Medium, and Hard play the same rules. Tests prove the ordering (Hard beats Medium, Medium beats Easy over fixed seeds) and that perception is delayed.

Where to tune: profile weights (`cpu_profile.gd`) decide how much each consideration matters per difficulty; the named constants at the top of `cpu_controller.gd` are the heuristic's shape (thresholds, ramps, tolerances, steering) shared by every difficulty. `CpuObservation` carries only what decisions read, so the per-tick perception cost stays two `time_to_threat` calls. Measure changes with `game/tools/balance_report.gd`.

| Concept             | Code                                          |
| ------------------- | --------------------------------------------- |
| Controller          | `game/src/application/cpu/cpu_controller.gd`  |
| Profiles            | `game/src/application/cpu/cpu_profile.gd`     |
| Delayed observation | `game/src/application/cpu/cpu_observation.gd` |
| Behavior proofs     | `game/tests/application/test_cpu.gd`          |
