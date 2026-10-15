# Combat Speed Ledger

> See also: [combat.md](../concepts/combat.md), [testing.md](./testing.md), [invariants](../../spec/invariants.md#deflection-consequence-001)
> Source: `game/tests/harness/speed_ledger.gd`, `game/content/rules/weapon_catalog.gd`, `game/content/rules/fighter_catalog.gd`, `game/content/rules/standard_duel_rules.gd`

Every quantity that sets how fast a duel plays, in one place, so feel tuning compares numbers instead of impressions. The "Now" column is generated from the shipped rules: the constants are read from content and the timings are measured by driving the real weapon motor, idle, from the right guard. `RULES` (`test_the_speed_ledger_matches_the_rules`) fails when this page and the rules disagree. Regenerate it with:

```text
godot --headless --path game --script res://tools/speed_ledger.gd -- --write
```

The abb6a27 column is a frozen record of rules 20 — the build whose feel the review compares against — copied once from that commit's content. It is history, never recomputed.

<!-- prettier-ignore-start -->
<!-- speed-ledger:begin -->

| Quantity | Unit | Now (rules 52) | abb6a27 (rules 20) |
| --- | --- | --- | --- |
| Simulation rate | Hz | 60 | 60 |
| Tap swing speed cap | rad/s | 10.5 | 10.5 |
| Full swing speed cap | rad/s | 18.0 | 20.0 |
| Tap attack arc | ° | 90 | 90 |
| Full attack arc (ATTACK-ARC-001) | ° | 180 | 180 |
| Control domain | ° | 270 | 270 |
| Swing torque tap / full | N·m | 128.7 / 148.5 | 128.7 / 148.5 |
| Attack brake tap / full | N·m | 217.8 / 148.5 | 217.8 / 148.5 |
| Hold / reacquire torque | N·m | 39.6 | 39.6 |
| Wind-back speed @ torque | rad/s @ N·m | 1.8 @ 59.4 | 1.8 @ 59.4 |
| Control speed (attack gate) | rad/s | 1.2 | 1.2 |
| Recovery | ticks | floor 6, then the brake (RECOVERY-001) | 6 + authored up to 48 (commitment, overswing, displacement, facing, balance) |
| Bind | — | rigid contact, no winner | scripted; loser +10 recovery |
| Attack buffer | ticks | 4 | 4 |
| Healthy turn torque | N·m | 175.0 | 175.0 |
| Healthy turn-rate cap | rad/s | 9.0 | 9.0 |
| Full-commit turn share | — | torque 35 % / rate 50 % | tracking floor 12 % (penalties 0.72, overswing 0.1) |
| Move speed | m/s | 4.2 | 4.2 |
| Locomotion / brake / burst force | N | 1760 / 2400 / 5600 | 1760 / 2400 / 5600 |
| Burst speed (axial) | m/s | 8.4 | 8.4 |
| Hurt target radius | m | torso 0.195 | whole body 0.27 |
| Grip hurt region (hands, handle) | m | hands 2 × 0.035, handle 0.015; wound share 0.60 | — |
| Sword-vs-sword steel | — | blade only (STEEL-TOPOLOGY-001) | blade only |
| Exposure in damage | — | reading only (PHYS-004) | damage × 0.75–1.5 |
| Tap from the guard: release → overswing | ticks | 10 | — |
| Tap whiff: release → under control | ticks | 20 | — |
| Full charge: press → fully wound | ticks | 59 | — |
| Full charge: release → overswing | ticks | 12 | — |
| Full whiff: release → under control | ticks | 25 | — |

<!-- speed-ledger:end -->
<!-- prettier-ignore-end -->

## Reading it

- **The actuators did not change.** Swing, brake, hold and wind-back torques, control speed, the attack buffer, footwork forces and the turn motor are the same as in rules 20; only the full swing speed cap moved (20 → 18 rad/s). What rules 20 had and the current build does not is _authored consequence_: up to 48 ticks of recovery, a scripted bind loser and a damage multiplier for exposure. The current build replaces them with physics (DEFLECTION-CONSEQUENCE-001, PHYS-004), so the ledger is where a lever's size is judged before it is pulled.
- **The arc is not the domain.** 270° is where the sword can turn; one attack travels at most 180° plus its overswing (ATTACK-ARC-001).
- **Timings are idle, healthy and unopposed.** A contact, a wound or a moving body changes them through the same laws; the lost-line corpus (`game/tools/reacquisition_probe.gd`) and the feel probe (`game/tools/feel_probe.gd`) measure those.
