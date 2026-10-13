class_name InitiativeModel
extends RefCounted

## Time-to-threat diagnostic (COMBAT §46, PHYS-004): how soon this fighter's
## actual blade could reach the opponent's body from the current physical
## state. Used to classify parries and ripostes, by the CPU, and by the debug
## overlay and HUD. It never changes simulation state, and damage never reads
## it.
##
## A bounded estimate, not a second simulation (rules 43). For a fixed
## horizon of `HORIZON_TICKS` it advances the attacker with the same bounded
## laws the duel uses — the weapon motor's torque over the coordinate's one
## inertia (UNIFIED-MASS-001) toward its target speed, the heading's turn
## torque toward the target under the authority commitment leaves, footwork
## closing at the locomotion force — carries the target along its current
## velocity, and samples the **actual blade capsule** at each predicted tick
## against the target's hurt circle (SLASH-SHAPE-001). The first predicted
## overlap is the threat time. A swing in flight is followed to its end; a
## weapon not swinging is read as the strike it could start once it is back
## under control, and until then its resting blade is carried along by the
## footwork — a blade that walked in can poke, so it threatens. Past the
## horizon there is no time to give: the result (`ThreatEstimate`) says so,
## reads the horizon, and keeps what was still left — the blade's gap to the
## torso and the readiness still owed — for ranking, never as seconds.
##
## Deliberately approximate. The opponent's sword is not predicted: a sword in
## the way makes an attack defendable, not unreachable, and whether the guard
## holds is the contact solver's business when the contact actually happens.
## Fixed iterations, so the cost per call is bounded.
##
## Every quantity is the attacker's own (`attacker_spec`: weapon, drive,
## inertia, heading and footwork, each scaled by the attacker's own condition,
## CONDITION-001) or the target's own (`target_spec`: its hurt torso and push
## body). No reference reach, no reference fighter, and no injury branch: a
## wounded attacker's threat is slower only because its actuators are
## (COMBATANT-GENERIC-001).
##
## See also: /docs/concepts/combat.md

const UNREACHABLE := 9.0
## The prediction horizon (ticks): half a second.
const HORIZON_TICKS := 30


static func time_to_threat(fighter: FighterState, opponent: FighterState, rules: DuelRules) -> float:
	return threat_time(fighter, rules.spec_of(fighter), opponent, rules.spec_of(opponent), rules.combat)


## How soon `attacker` (driven by `attacker_spec`) could reach `target`'s body
## (`target_spec`'s hurt torso), in seconds: the predicted time inside the
## horizon, the horizon itself past it, `UNREACHABLE` for the dead.
static func threat_time(attacker: FighterState, attacker_spec: CombatantPhysicsSpec, target: FighterState, target_spec: CombatantPhysicsSpec, combat: CombatTuning) -> float:
	return estimate(attacker, attacker_spec, target, target_spec, combat, ThreatEstimate.new()).hit_time


## The whole bounded prediction, written into `out` and returned.
static func estimate(attacker: FighterState, attacker_spec: CombatantPhysicsSpec, target: FighterState, target_spec: CombatantPhysicsSpec, combat: CombatTuning, out: ThreatEstimate) -> ThreatEstimate:
	out.within_horizon = false
	out.residual_gap = 0.0
	out.readiness_remaining = 0.0
	var weapon := attacker.weapon
	if weapon.phase == CombatPhase.Id.DEAD:
		out.hit_time = UNREACHABLE
		return out
	var definition := attacker_spec.weapon
	var body := attacker_spec.fighter
	var dt := SimulationTimebase.TICK_SECONDS
	var condition := ConditionModel.compute(attacker.health, body.max_health, combat, ConditionState.new())
	var force := condition.force_scale
	var speed := condition.speed_scale
	var drive := body.weapon_torque_scale * force
	var pose := BladePose.new()
	var inertia := WeaponKinematics.motor_inertia(attacker_spec, weapon.angle, pose)
	var ready := _readiness(attacker, definition, drive, inertia, combat.recovery_min_ticks)
	## The predicted strike: the swing in flight, or the one this weapon could
	## launch — a held charge released now, otherwise a tap once ready.
	var swinging := CombatPhase.is_swinging(weapon.phase)
	var charging := weapon.phase == CombatPhase.Id.CHARGING
	var dir := weapon.swing_dir if swinging or charging else WeaponSystem.swing_direction(weapon)
	var charge := weapon.swing_charge if swinging else (weapon.charge if charging else 0.0)
	var ceiling := definition.achievable_swing_speed(charge, weapon.launch_readiness) * speed if swinging else 0.0
	var swing_end := weapon.swing_end
	## A swing in flight (or a held charge, released now) is launched already;
	## any other weapon launches its strike from wherever its motor has
	## brought it once it is ready.
	var launched := swinging
	var theta := weapon.angle
	var omega := weapon.speed
	var x := attacker.x
	var y := attacker.y
	var vx := attacker.vx
	var vy := attacker.vy
	var phi := attacker.facing
	var phi_rate := attacker.turn_rate
	## Final heading shares: commitment and the wound, already folded together
	## with their floors (RESPONSIVE-COMMITMENT-001).
	var tracking := CommitmentModel.turn_torque_share(attacker, attacker_spec, condition, combat)
	var rate_tracking := CommitmentModel.turn_rate_share(attacker, attacker_spec, condition, combat)
	## Footwork under the same laws as `MovementSystem`: what the body asks for
	## (stagger and death constrain intent) and the authority commitment leaves
	## to change its motion (PHYS-003). Frozen at their current values for the
	## horizon — an estimate, not a second simulation.
	var asking := CommitmentModel.translation_multiplier(attacker, body)
	var authority := CommitmentModel.move_authority(attacker, body)
	var touch := target_spec.fighter.hurt_radius + definition.blade_radius
	var apart := body.push_radius + target_spec.fighter.push_radius
	var tx := target.x
	var ty := target.y
	var gap := INF
	for k in range(1, HORIZON_TICKS + 1):
		var t := float(k) * dt
		tx += target.vx * dt
		ty += target.vy * dt
		## Heading: bounded turn torque toward the target, as FacingSystem.
		var error := SimMath.wrap_angle(SimMath.arctan2(ty - y, tx - x) - phi)
		var max_rate := body.turn_speed_max * rate_tracking
		phi_rate = SimMath.approach(phi_rate, clampf(body.track_gain * error, -max_rate, max_rate), body.turn_accel() * tracking * dt)
		phi = SimMath.wrap_angle(phi + phi_rate * dt)
		## Footwork: close at the locomotion force, never into the body.
		var dx := tx - x
		var dy := ty - y
		var distance := SimMath.length(dx, dy)
		var closing := body.max_speed * speed * asking if distance > apart else 0.0
		var ux := dx / distance if distance > SimMath.EPSILON else 0.0
		var uy := dy / distance if distance > SimMath.EPSILON else 0.0
		var step := body.move_accel() * force * authority * dt
		var wx := ux * closing - vx
		var wy := uy * closing - vy
		var want := SimMath.length(wx, wy)
		if want > step:
			wx *= step / want
			wy *= step / want
		vx += wx
		vy += wy
		x += vx * dt
		y += vy * dt
		## Weapon. Until it is ready the blade is not frozen: it keeps moving and
		## is arrested by the same motor the duel applies (the attack's brake
		## while overswinging or recovering above control speed, the hold
		## otherwise), so a guard knocked spinning is predicted to spin away.
		## Once ready it drives its strike toward the target speed.
		inertia = WeaponKinematics.motor_inertia(attacker_spec, theta, pose)
		if not launched and t >= ready:
			launched = true
			ceiling = definition.achievable_swing_speed(charge, definition.readiness(theta)) * speed
			swing_end = clampf(theta + dir * definition.arc(charge), -definition.guard_limit, definition.guard_limit)
		if launched:
			if (theta - swing_end) * dir < 0.0:
				omega = SimMath.approach(omega, dir * ceiling, definition.swing_accel(charge, drive, inertia) * dt)
				theta = clampf(theta + omega * dt, -definition.guard_limit, definition.guard_limit)
		else:
			omega = SimMath.approach(omega, 0.0, _arrest_accel(weapon, omega, definition, drive, inertia) * dt)
			theta = clampf(theta + omega * dt, -definition.guard_limit, definition.guard_limit)
		WeaponKinematics.pose_at(x, y, phi, theta, attacker_spec, pose)
		var hx := pose.point_x(definition.hilt_radius)
		var hy := pose.point_y(definition.hilt_radius)
		var px := pose.point_x(definition.tip_radius)
		var py := pose.point_y(definition.tip_radius)
		var along := SimMath.closest_param_on_segment(hx, hy, px, py, tx, ty)
		gap = SimMath.length(tx - SimMath.mix(hx, px, along), ty - SimMath.mix(hy, py, along)) - touch
		if gap <= 0.0:
			out.within_horizon = true
			out.hit_time = t
			return out
	var horizon := float(HORIZON_TICKS) * dt
	out.hit_time = horizon
	out.residual_gap = gap
	out.readiness_remaining = maxf(0.0, ready - horizon)
	return out


## Seconds until the weapon is back under control and may strike — the same
## gate recovery itself ends on (RECOVERY-001): an overswing brakes to rest
## and then sits out the universal floor; a recovery waits for the rest of its
## floor or for its brake to bring the blade under `control_speed`, whichever
## is later; a stagger runs out.
static func _readiness(attacker: FighterState, definition: WeaponDefinition, drive: float, inertia: float, min_ticks: int) -> float:
	var weapon := attacker.weapon
	var dt := SimulationTimebase.TICK_SECONDS
	var brake := definition.brake_accel(weapon.swing_charge, drive, inertia)
	match weapon.phase:
		CombatPhase.Id.NEUTRAL:
			return maxf(0.0, absf(weapon.speed) - definition.control_speed) / definition.hold_accel(drive, inertia)
		CombatPhase.Id.OVERSWING:
			return absf(weapon.speed) / brake + float(min_ticks) * dt
		CombatPhase.Id.RECOVERY:
			return maxf(float(weapon.recovery_left) * dt, maxf(0.0, absf(weapon.speed) - definition.control_speed) / brake)
		CombatPhase.Id.STAGGER:
			return float(attacker.stagger_left) * dt
	return 0.0


## The deceleration the duel's motor applies to a blade that is not striking:
## the attack's brake while it overswings or recovers above control speed
## (RECOVERY-001), the hold otherwise.
static func _arrest_accel(weapon: WeaponState, omega: float, definition: WeaponDefinition, drive: float, inertia: float) -> float:
	var braking := weapon.phase == CombatPhase.Id.OVERSWING or (weapon.phase == CombatPhase.Id.RECOVERY and absf(omega) > definition.control_speed)
	return definition.brake_accel(weapon.swing_charge, drive, inertia) if braking else definition.hold_accel(drive, inertia)


## Positive when `fighter` threatens first.
static func initiative(fighter: FighterState, opponent: FighterState, rules: DuelRules) -> float:
	return time_to_threat(opponent, fighter, rules) - time_to_threat(fighter, opponent, rules)
