class_name CapabilityModel
extends RefCounted

## Pure static capability arithmetic. Capability is a [floor, 1] scalar that
## scales how hard a fighter's motors push — forces and torques, never speed
## caps (PHYS-003). It degrades additively under injury and fatigue so that
## even combined penalties cannot strand a fighter below the authored floor.
##
## Four separate functions return plain floats (no allocation): one per motor
## channel so Phase 3 can wire each independently, even though the base
## formula is shared.
##
## Injury penalty: gentle nonlinear from `injury_load = 1 - health/max_health`.
## Fatigue penalty: steepening quadratic from `fatigue_load = 1 - stamina/stamina_max`.
## Combined: `clamp(1 - P_injury - P_fatigue, floor, 1)` — additive, not multiplicative.
##
## See also: /docs/concepts/combat.md


## Weapon swing / brake torque capability.
static func resolve_weapon(health: float, max_health: float, stamina: float, stamina_max: float, tuning: CombatTuning) -> float:
	return _resolve(health, max_health, stamina, stamina_max, tuning)


## Locomotion force capability.
static func resolve_movement(health: float, max_health: float, stamina: float, stamina_max: float, tuning: CombatTuning) -> float:
	return _resolve(health, max_health, stamina, stamina_max, tuning)


## Body turn torque capability.
static func resolve_turn(health: float, max_health: float, stamina: float, stamina_max: float, tuning: CombatTuning) -> float:
	return _resolve(health, max_health, stamina, stamina_max, tuning)


## Burst footwork force capability.
static func resolve_burst(health: float, max_health: float, stamina: float, stamina_max: float, tuning: CombatTuning) -> float:
	return _resolve(health, max_health, stamina, stamina_max, tuning)


## Injury penalty: a gentle nonlinear curve (`load^1.25`). At full health
## the penalty is zero; at zero health it reaches `capability_injury_max`.
static func injury_penalty(health: float, max_health: float, tuning: CombatTuning) -> float:
	if max_health <= 0.0:
		return tuning.capability_injury_max
	var injury_load := 1.0 - health / max_health
	return tuning.capability_injury_max * SimMath.pow_1_25(injury_load)


## Fatigue penalty: a steepening quadratic (`load²`). At full stamina
## the penalty is zero; at zero stamina it reaches `capability_fatigue_max`.
static func fatigue_penalty(stamina: float, stamina_max: float, tuning: CombatTuning) -> float:
	if stamina_max <= 0.0:
		return tuning.capability_fatigue_max
	var fatigue_load := 1.0 - stamina / stamina_max
	return tuning.capability_fatigue_max * fatigue_load * fatigue_load


static func _resolve(health: float, max_health: float, stamina: float, stamina_max: float, tuning: CombatTuning) -> float:
	var pi := injury_penalty(health, max_health, tuning)
	var pf := fatigue_penalty(stamina, stamina_max, tuning)
	return clampf(1.0 - pi - pf, tuning.capability_floor, 1.0)
