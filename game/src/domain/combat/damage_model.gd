class_name DamageModel
extends RefCounted

## Relational strike quality (COMBAT §34–§39, §47, §51–§54). Damage is never
## a property of the attack: it comes from the blade-point velocity relative
## to the target along the contact normal, where on the blade it landed, how
## well the edge was aligned, the attacker's stability, and the target's
## exposure, mapped through a nonlinear curve. Criticals are convergence,
## never chance.
##
## Implements: /spec/invariants.md#combat-003
## See also: /docs/concepts/combat.md


static func evaluate(attacker: FighterState, target: FighterState, point_x: float, point_y: float, rules: DuelRules) -> StrikeResult:
	var weapon := rules.weapon
	var combat := rules.combat
	var strike := StrikeResult.new()
	strike.attacker = attacker.slot
	strike.target = target.slot
	strike.point_x = point_x
	strike.point_y = point_y
	var rx := point_x - attacker.x
	var ry := point_y - attacker.y
	var radius := SimMath.length(rx, ry)
	strike.blade_fraction = SimMath.clamp01((radius - weapon.hilt_radius) / weapon.blade_length())
	var omega := attacker.turn_rate + attacker.weapon.speed
	var relative_x := attacker.vx - omega * ry - target.vx
	var relative_y := attacker.vy + omega * rx - target.vy
	var blade_x := rx / radius if radius > SimMath.EPSILON else SimMath.cosine(DuelGeometry.blade_angle(attacker))
	var blade_y := ry / radius if radius > SimMath.EPSILON else SimMath.sine(DuelGeometry.blade_angle(attacker))
	var turning := signf(omega) if absf(omega) > SimMath.EPSILON else attacker.weapon.swing_dir
	var edge_x := -blade_y * turning
	var edge_y := blade_x * turning
	var to_center_x := target.x - point_x
	var to_center_y := target.y - point_y
	var center_distance := SimMath.length(to_center_x, to_center_y)
	if center_distance > SimMath.EPSILON:
		strike.normal_x = to_center_x / center_distance
		strike.normal_y = to_center_y / center_distance
	else:
		strike.normal_x = edge_x
		strike.normal_y = edge_y
	strike.closing_speed = maxf(0.0, relative_x * strike.normal_x + relative_y * strike.normal_y)
	var relative_speed := SimMath.length(relative_x, relative_y)
	if relative_speed > SimMath.EPSILON:
		strike.alignment = SimMath.clamp01((relative_x * edge_x + relative_y * edge_y) / relative_speed)
	strike.efficiency = weapon.efficiency(strike.blade_fraction)
	var edge := SimMath.mix(weapon.edge_floor, 1.0, strike.alignment)
	var mass_factor := weapon.mass / combat.reference_weapon_mass
	var speed_quality := minf(strike.closing_speed / weapon.reference_closing_speed, combat.max_physical_quality)
	strike.physical_quality = speed_quality * strike.efficiency * edge * attacker.stability * mass_factor
	strike.exposure = exposure(target, attacker, rules)
	strike.quality = strike.physical_quality * strike.exposure
	strike.damage = combat.damage_for(strike.quality)
	strike.critical = (
		strike.physical_quality >= combat.critical_quality
		and strike.blade_fraction >= combat.critical_blade_min
		and strike.blade_fraction <= combat.critical_blade_max
		and strike.alignment >= combat.critical_alignment
		and strike.exposure >= combat.critical_exposure
	)
	return strike


## Vulnerability is relational state, not a flat "attacking = +X% damage"
## (COMBAT §47): commitment, balance debt, being out-angled, and the phase
## the target is caught in.
static func exposure(target: FighterState, attacker: FighterState, rules: DuelRules) -> float:
	var combat := rules.combat
	var value := combat.exposure_base
	value += combat.exposure_commit * target.weapon.commitment
	value += combat.exposure_balance * (1.0 - target.stability)
	value += combat.exposure_flank * absf(DuelGeometry.facing_error(target, attacker)) / PI
	match target.weapon.phase:
		CombatPhase.Id.CHARGING:
			value += combat.exposure_charging
		CombatPhase.Id.OVERSWING:
			value += combat.exposure_overswing
		CombatPhase.Id.RECOVERY:
			value += combat.exposure_recovery
		CombatPhase.Id.STAGGER:
			value += combat.exposure_stagger
	return clampf(value, combat.exposure_min, combat.exposure_max)
