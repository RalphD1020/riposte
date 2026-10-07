class_name StaminaModel
extends RefCounted

## Pure static stamina arithmetic (STAMINA-001). Every function reads tuning
## and returns a plain float: no allocation, no side effects, no state.
##
## The stamina ceiling is derived from health so injury is a cause and reduced
## ceiling is a consequence — the ceiling is never stored in FighterState.
## Exertion drains stamina during motor effort; recovery restores it at rest;
## damage shock is an instantaneous hit on contact.
##
## See also: /docs/concepts/combat.md


## Current maximum stamina. The ceiling tracks health: at full health the
## ceiling equals `base_stamina`; at zero health it is reduced by
## `stamina_health_share` of `base_stamina`.
static func max_for_health(health: float, max_health: float, base_stamina: float, tuning: CombatTuning) -> float:
	if max_health <= 0.0:
		return 0.0
	var health_fraction := health / max_health
	return base_stamina * (1.0 - tuning.stamina_health_share * (1.0 - health_fraction))


## Instantaneous stamina cost of being hit. Proportional to damage dealt.
static func damage_shock(damage_dealt: float, tuning: CombatTuning) -> float:
	return damage_dealt * tuning.stamina_shock_rate


## Stamina drained by motor effort over `dt` seconds. Effort is a normalized
## combined signal from all motor channels (0 = idle, >1 = heavy exertion).
static func exertion(effort: float, dt: float, tuning: CombatTuning) -> float:
	return effort * tuning.stamina_exertion_rate * dt


## Stamina recovered over `dt` seconds when effort is below the recovery
## threshold. Returns zero when exerting or already at the ceiling.
static func recovery(effort: float, stamina: float, stamina_max: float, dt: float, tuning: CombatTuning) -> float:
	if effort > tuning.stamina_recovery_effort_ceiling:
		return 0.0
	var headroom := stamina_max - stamina
	if headroom <= 0.0:
		return 0.0
	return minf(tuning.stamina_recovery_rate * dt, headroom)


## Normalized effort for one motor channel. Positive and braking work are
## scaled by reference work and type-specific weights; utilization (isometric
## force at near-zero velocity) contributes directly through its own weight.
static func channel_effort(positive_work: float, braking_work: float, utilization: float, reference_work: float, tuning: CombatTuning) -> float:
	if reference_work <= SimMath.EPSILON:
		return 0.0
	return (positive_work * tuning.stamina_drive_weight + braking_work * tuning.stamina_brake_weight) / reference_work + utilization * tuning.stamina_hold_weight


## Combined normalized effort across all three motor channels from one tick's
## accumulated scratch data. This is the single effort signal that feeds
## `exertion()` and `recovery()`.
static func total_effort(scratch: FighterTickScratch, tuning: CombatTuning) -> float:
	var move := channel_effort(
		scratch.movement_positive_work, scratch.movement_braking_work,
		scratch.movement_utilization, tuning.stamina_move_reference_work, tuning
	)
	var turn := channel_effort(
		scratch.turn_positive_work, scratch.turn_braking_work,
		scratch.turn_utilization, tuning.stamina_turn_reference_work, tuning
	)
	var weapon := channel_effort(
		scratch.weapon_positive_work, scratch.weapon_braking_work,
		scratch.weapon_utilization, tuning.stamina_weapon_reference_work, tuning
	)
	return move + turn + weapon
