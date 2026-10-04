# Combat

> See also: [spec/invariants.md](../../spec/invariants.md) — COMBAT-001, COMBAT-002, COMBAT-003
> See also: [docs/concepts/simulation.md](./simulation.md), [docs/concepts/controls.md](./controls.md)
> Source: `game/src/domain/combat/`, tuning values in `game/content/rules/standard_duel_rules.gd`

Two verbs (move, attack) and real steel. Every outcome comes from simulated bodies and blades; nothing is a canned animation. Numbers live in the rules content file; this doc names mechanisms, not values.

## Mechanisms → code

| Mechanism                                              | Code                                                                                 |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------ |
| Footwork, stability, separation                        | `game/src/domain/combat/movement_system.gd`                                          |
| Facing and tracking (degrades with commitment)         | `game/src/domain/combat/facing_system.gd`                                            |
| Arena boundary (hard, no ring-outs)                    | `game/src/domain/combat/arena_constraints.gd`                                        |
| Input language, motor, phases, recovery (COMBAT-001)   | `game/src/domain/combat/weapon_system.gd`                                            |
| Commitment `K`                                         | `game/src/domain/combat/commitment_model.gd`                                         |
| Swept collision (COMBAT-002)                           | `game/src/domain/combat/collision_system.gd`, `fighter_pose.gd`, `contact_report.gd` |
| Blade impulse, deflection, bind, parry (COMBAT-003)    | `game/src/domain/combat/contact_resolver.gd`                                         |
| Strike quality and damage curve (COMBAT-003)           | `game/src/domain/combat/damage_model.gd`, `strike_result.gd`                         |
| Initiative / time-to-threat                            | `game/src/domain/combat/initiative_model.gd`                                         |
| Shared geometry (distance, closing speed, blade angle) | `game/src/domain/combat/duel_geometry.gd`                                            |

## Attack language (COMBAT-001)

- **Tap**: release before the threshold → exactly 0% charge, 90° quick cut.
- **Hold**: charges and physically winds the blade back; **release** swings from the actual retracted angle with arc `90° + 90° × charge`.
- **Direction**: from which side of the facing the blade is on; the sword rests where it stopped, so the next cut starts there.
- **Phases** (`CombatPhase`): `NEUTRAL → CHARGING → LAUNCH → ACTIVE_EARLY/THREAT/LATE → OVERSWING → RECOVERY`, plus `BIND`, `STAGGER`, `DEAD`.
- **Cancel**: a canceled input drops a charge into a short recovery, never an attack.

## Contact (COMBAT-002, COMBAT-003)

- Substeps per tick are sized so no blade point travels farther than `substep_travel`; the earliest contact wins, so fast blades never tunnel.
- **Blade on blade**: 2D rigid impulse about each fighter's pivot. Faster, heavier, better-planted blades displace the other. A swing slowed below the deflect fraction is interrupted. Low closing speed binds; a bind resolves by planting and squareness.
- **Parry**: classified, not pressed: the defender ends up threatening first by the parry margin.
- **Body**: quality = closing speed × blade efficiency (where on the blade) × edge alignment × attacker stability × mass factor × target exposure, mapped through a nonlinear curve. Criticals require convergence (high quality and exposure), never chance. Double hits are symmetric.

## Debug

F3 (debug builds) shows distance, closing speed, orbit, each fighter's phase/charge/commitment/stability/time-to-threat, and the last contact (`game/src/presentation/hud/debug_overlay.gd`).
