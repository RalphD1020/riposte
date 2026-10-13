class_name ConditionModel
extends RefCounted

## Damage-driven physical capability (CONDITION-001, rules 45). One damage
## fraction feeds three linear ranges, each with its own authored floor:
##
## ```text
## h              = clamp(health / max_health, 0, 1)
## force_scale    = F + (1 − F)·h      F = condition_force_floor     (0.70)
## speed_scale    = S + (1 − S)·h      S = condition_speed_floor     (0.85)
## tracking_scale = T + (1 − T)·h      T = condition_tracking_floor  (0.80)
## ```
##
## Strictly linear in damage, exactly 1 at full health (the span is the
## floor's complement, so the healthy identity holds by construction), and
## approaching each floor only at zero health. At half health: 0.85 / 0.925 /
## 0.90. Damage is the only input — stamina is not (STAMINA-002) — and the
## same law applies to every fighter, from their own healthy actuators.
##
## Implements: /spec/invariants.md#condition-001
## See also: /docs/concepts/combat.md


## Write `out` for a fighter at `health` of `max_health` under `combat`'s
## floors, and return it.
static func compute(health: float, max_health: float, combat: CombatTuning, out: ConditionState) -> ConditionState:
	var h := SimMath.clamp01(health / max_health) if max_health > 0.0 else 0.0
	out.health_fraction = h
	out.damage_fraction = 1.0 - h
	out.force_scale = _linear(combat.condition_force_floor, h)
	out.speed_scale = _linear(combat.condition_speed_floor, h)
	out.tracking_scale = _linear(combat.condition_tracking_floor, h)
	return out


## `fighter`'s condition under `rules`, freshly computed — for readers outside
## the tick (threat estimates, the CPU, the snapshot). Inside the tick systems
## read the frozen state in their scratch instead.
static func of(fighter: FighterState, rules: DuelRules) -> ConditionState:
	return compute(fighter.health, rules.spec_of(fighter).fighter.max_health, rules.combat, ConditionState.new())


static func _linear(floor_value: float, h: float) -> float:
	return floor_value + (1.0 - floor_value) * h
