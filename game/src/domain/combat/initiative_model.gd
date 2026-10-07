class_name InitiativeModel
extends RefCounted

## Time-to-threat diagnostic (COMBAT §46): who can credibly threaten first
## from the current physical state. Used to classify parries and ripostes,
## by the CPU, and by the debug overlay. It never changes simulation state.
##
## T_threat = weapon readiness + body turn + blade sweep onto the line + closing.
##
## See also: /docs/concepts/combat.md

const UNREACHABLE := 9.0


static func time_to_threat(fighter: FighterState, opponent: FighterState, rules: DuelRules) -> float:
	var weapon := fighter.weapon
	var definition := rules.weapon
	var dt := SimulationTimebase.TICK_SECONDS
	var ready := 0.0
	match weapon.phase:
		CombatPhase.Id.DEAD:
			return UNREACHABLE
		CombatPhase.Id.NEUTRAL:
			ready = maxf(0.0, absf(weapon.speed) - definition.control_speed) / definition.hold_accel(rules.fighter.weapon_torque_scale)
		CombatPhase.Id.OVERSWING:
			ready = absf(weapon.speed) / definition.brake_accel(weapon.swing_charge, rules.fighter.weapon_torque_scale)
			ready += float(definition.recovery_base_ticks) * dt + definition.recovery_commit_ticks * weapon.commitment * dt
		CombatPhase.Id.RECOVERY:
			ready = float(weapon.recovery_left) * dt
		CombatPhase.Id.STAGGER:
			ready = float(fighter.stagger_left) * dt
		CombatPhase.Id.BIND:
			ready = float(weapon.bind_left) * dt
	var bearing := DuelGeometry.facing_error(fighter, opponent)
	var turn := maxf(0.0, absf(bearing) - definition.guard_limit) / rules.fighter.turn_speed_max
	var line := clampf(bearing, -definition.guard_limit, definition.guard_limit)
	var sweep := absf(line - weapon.angle)
	if CombatPhase.is_swinging(weapon.phase):
		var toward := (line - weapon.angle) * weapon.swing_dir >= 0.0
		var speed := maxf(absf(weapon.speed), definition.swing_speed_tap)
		if toward:
			sweep /= speed
		else:
			ready += absf(weapon.swing_end - weapon.angle) / speed + float(definition.recovery_base_ticks) * dt
			sweep /= definition.swing_speed_tap
	else:
		sweep /= definition.swing_speed_tap
	var reach := definition.tip_radius + rules.fighter.body_radius
	var close := maxf(0.0, DuelGeometry.distance(fighter, opponent) - reach) / rules.fighter.max_speed
	return minf(ready + turn + sweep + close, UNREACHABLE)


## Positive when `fighter` threatens first.
static func initiative(fighter: FighterState, opponent: FighterState, rules: DuelRules) -> float:
	return time_to_threat(opponent, fighter, rules) - time_to_threat(fighter, opponent, rules)
