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


## The whole bounded prediction, written into `out` and returned, under one
## named `continuation` (`ThreatContinuation`; the unopposed close when none):
## PLANTED reads a swing in flight on its own line — whether its remaining
## sweep, about the heading as it reacquires, reaches the body
## (DEFLECTION-001); ROUTE predicts an intended path (CPU-008). With its
## `steel` set the target's sword is swept too, under its own known law for the phase
## it is in — a swing in flight keeps driving to its end, anything else is
## arrested by its brake or hold — with no knowledge of the target's future
## input; any of its steel (blade, crossguard bar and handle — every
## collidable feature stops a cut, GUARD-CONTACT-001) met by any of this sword's
## before the torso or a hand reads `ThreatEstimate.STEEL` (a tie goes to the
## steel, as in the duel). Blades
## already touching when the prediction starts are a bind, not an obstruction
## (`starts_bound`): only steel met again after they part is a new contact.
static func estimate(
	attacker: FighterState,
	attacker_spec: CombatantPhysicsSpec,
	target: FighterState,
	target_spec: CombatantPhysicsSpec,
	combat: CombatTuning,
	out: ThreatEstimate,
	continuation: ThreatContinuation = null
) -> ThreatEstimate:
	var assumed := continuation if continuation != null else ThreatContinuation.closing()
	var motion := assumed.motion
	var steel := assumed.steel
	var route_x := assumed.route_x
	var route_y := assumed.route_y
	out.within_horizon = false
	out.residual_gap = 0.0
	out.readiness_remaining = 0.0
	out.first_contact = ThreatEstimate.NONE
	out.steel_time = 0.0
	out.starts_bound = false
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
	## A strike not yet pressed cuts from the side the blade commits to by the
	## time it launches, which its own momentum may still change (COMBAT-005).
	var side_free := not (swinging or charging)
	var charge := weapon.swing_charge if swinging else (weapon.charge if charging else 0.0)
	var ceiling := definition.achievable_swing_speed(charge, weapon.launch_preparation) * speed if swinging else 0.0
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
	## The target's hands are damageable too (HAND-CONTACT-001): the earliest of
	## torso and either hand disc is the threat. They ride the target's predicted
	## translation from where its grips are now (its heading and sword frozen,
	## like the rest of the target).
	var wounds_hands := definition.wounds(SwordContactSet.Feature.BLADE)
	var grips := WeaponKinematics.pose_of(target, target_spec, BladePose.new())
	var off_x := grips.point_x(target_spec.weapon.offhand_grip_radius) - target.x
	var off_y := grips.point_y(target_spec.weapon.offhand_grip_radius) - target.y
	var dominant_x := grips.point_x(target_spec.weapon.dominant_grip_radius) - target.x
	var dominant_y := grips.point_y(target_spec.weapon.dominant_grip_radius) - target.y
	var hand_touch := target_spec.fighter.hand_radius + definition.blade_radius
	var apart := body.push_radius + target_spec.fighter.push_radius
	var tx := target.x
	var ty := target.y
	var gap := INF
	## The target's sword, swept only when asked (`steel`).
	var their := target_spec.weapon
	var their_theta := target.weapon.angle
	var their_omega := target.weapon.speed
	var their_swinging := CombatPhase.is_swinging(target.weapon.phase)
	var their_drive := 0.0
	var their_ceiling := 0.0
	var their_speed_scale := 1.0
	var their_pose: BladePose = null
	var segments: SegmentContact = null
	## Last tick's bodies and swords, to order a same-tick crossing.
	var previous := PackedFloat64Array()
	## With `steel`, the target's heading follows its known automatic law too —
	## it keeps tracking the attacker with its own bounded turn motor, carrying
	## its sword with it — while its body keeps its current velocity: its next
	## footwork input is not known.
	var their_phi := target.facing
	var their_phi_rate := target.turn_rate
	var their_body := target_spec.fighter
	var their_tracking := 0.0
	var their_rate_tracking := 0.0
	if steel:
		var their_condition := ConditionModel.compute(target.health, target_spec.fighter.max_health, combat, ConditionState.new())
		their_drive = target_spec.fighter.weapon_torque_scale * their_condition.force_scale
		their_ceiling = their.achievable_swing_speed(target.weapon.swing_charge, target.weapon.launch_preparation) * their_condition.speed_scale
		their_speed_scale = their_condition.speed_scale
		their_tracking = CommitmentModel.turn_torque_share(target, target_spec, their_condition, combat)
		their_rate_tracking = CommitmentModel.turn_rate_share(target, target_spec, their_condition, combat)
		their_pose = BladePose.new()
		segments = SegmentContact.new()
		WeaponKinematics.pose_at(x, y, phi, theta, attacker_spec, pose)
		WeaponKinematics.pose_at(tx, ty, target.facing, their_theta, target_spec, their_pose)
		out.starts_bound = _steel_clearance(pose, definition, their_pose, their, segments) <= 0.0
	var bound := out.starts_bound
	previous = PackedFloat64Array([x, y, phi, theta, tx, ty, their_phi, their_theta])
	for k in range(1, HORIZON_TICKS + 1):
		var t := float(k) * dt
		tx += target.vx * dt
		ty += target.vy * dt
		if steel:
			var their_error := SimMath.wrap_angle(SimMath.arctan2(y - ty, x - tx) - their_phi)
			var their_max_rate := their_body.turn_speed_max * their_rate_tracking
			their_phi_rate = SimMath.approach(their_phi_rate, clampf(their_body.track_gain * their_error, -their_max_rate, their_max_rate), their_body.turn_accel() * their_tracking * dt)
			their_phi = SimMath.wrap_angle(their_phi + their_phi_rate * dt)
		## Heading: bounded turn torque toward the target, as FacingSystem.
		var error := SimMath.wrap_angle(SimMath.arctan2(ty - y, tx - x) - phi)
		var max_rate := body.turn_speed_max * rate_tracking
		phi_rate = SimMath.approach(phi_rate, clampf(body.track_gain * error, -max_rate, max_rate), body.turn_accel() * tracking * dt)
		phi = SimMath.wrap_angle(phi + phi_rate * dt)
		## Footwork: close at the locomotion force, never into the body.
		var dx := tx - x
		var dy := ty - y
		var distance := SimMath.length(dx, dy)
		if motion != ThreatContinuation.PLANTED:
			var closing := body.max_speed * speed * asking if distance > apart else 0.0
			var ux := dx / distance if distance > SimMath.EPSILON else 0.0
			var uy := dy / distance if distance > SimMath.EPSILON else 0.0
			if motion == ThreatContinuation.ROUTE:
				ux = route_x
				uy = route_y
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
		## The coordinate's inertia at this pose is read only where a motor
		## changes θ̇: a blade at rest and not launched, or a swing past its
		## end, stays exactly where it is.
		if not launched and t >= ready:
			launched = true
			ceiling = definition.achievable_swing_speed(charge, definition.preparation(theta)) * speed
			swing_end = clampf(theta + dir * definition.arc(charge), -definition.guard_limit, definition.guard_limit)
		if launched:
			if (theta - swing_end) * dir < 0.0:
				inertia = WeaponKinematics.motor_inertia(attacker_spec, theta, pose)
				omega = SimMath.approach(omega, dir * ceiling, definition.swing_accel(charge, drive, inertia) * dt)
				theta = clampf(theta + omega * dt, -definition.guard_limit, definition.guard_limit)
		else:
			if omega != 0.0:
				inertia = WeaponKinematics.motor_inertia(attacker_spec, theta, pose)
				omega = SimMath.approach(omega, 0.0, _arrest_accel(weapon, omega, definition, drive, inertia) * dt)
				theta = clampf(theta + omega * dt, -definition.guard_limit, definition.guard_limit)
			if side_free and absf(theta) > definition.side_deadzone:
				dir = -1.0 if theta > 0.0 else 1.0
		WeaponKinematics.pose_at(x, y, phi, theta, attacker_spec, pose)
		var hx := pose.point_x(definition.hilt_radius)
		var hy := pose.point_y(definition.hilt_radius)
		var px := pose.point_x(definition.tip_radius)
		var py := pose.point_y(definition.tip_radius)
		var steel_now := INF
		var steel_crossed := false
		if steel:
			if their_swinging and (their_theta - target.weapon.swing_end) * target.weapon.swing_dir < 0.0:
				var their_inertia := WeaponKinematics.motor_inertia(target_spec, their_theta, their_pose)
				their_omega = SimMath.approach(their_omega, target.weapon.swing_dir * their_ceiling, their.swing_accel(target.weapon.swing_charge, their_drive, their_inertia) * dt)
			elif target.weapon.phase == CombatPhase.Id.CHARGING:
				## A held charge keeps winding back under its own motor, as
				## `WeaponSystem` drives it, while the button stays held.
				var their_inertia := WeaponKinematics.motor_inertia(target_spec, their_theta, their_pose)
				their_omega = SimMath.approach(their_omega, -target.weapon.swing_dir * their.windup_speed * their_speed_scale, their.windup_accel(their_drive, their_inertia) * dt)
			elif their_omega != 0.0:
				var their_inertia := WeaponKinematics.motor_inertia(target_spec, their_theta, their_pose)
				their_omega = SimMath.approach(their_omega, 0.0, _arrest_accel(target.weapon, their_omega, their, their_drive, their_inertia) * dt)
			their_theta = clampf(their_theta + their_omega * dt, -their.guard_limit, their.guard_limit)
			WeaponKinematics.pose_at(tx, ty, their_phi, their_theta, target_spec, their_pose)
			steel_now = _steel_clearance(pose, definition, their_pose, their, segments)
			if bound:
				## Still in the bind it started in, or just parted from it.
				bound = steel_now <= 0.0
			else:
				steel_crossed = steel_now <= 0.0
		var along := SimMath.closest_param_on_segment(hx, hy, px, py, tx, ty)
		gap = SimMath.length(tx - SimMath.mix(hx, px, along), ty - SimMath.mix(hy, py, along)) - touch
		var region := ThreatEstimate.BODY
		if wounds_hands:
			## Swept with its sword, the target's hands ride its grips as its
			## sword and heading actually move; otherwise at their frozen offsets.
			var hand_gap := (
				_hands_gap(hx, hy, px, py, their_pose, their) if steel
				else minf(
					_segment_gap(hx, hy, px, py, tx + off_x, ty + off_y),
					_segment_gap(hx, hy, px, py, tx + dominant_x, ty + dominant_y)
				)
			) - hand_touch
			if hand_gap < gap:
				gap = hand_gap
				region = ThreatEstimate.HAND
		var flesh_crossed := gap <= 0.0
		## Steel and flesh both reached inside this tick: order them by where
		## each first crossed, found by bisecting the tick on the interpolated
		## bodies and swords (a fixed count); a tie is the steel's.
		if steel_crossed and flesh_crossed:
			var now := PackedFloat64Array([x, y, phi, theta, tx, ty, their_phi, their_theta])
			var steel_at := _first_crossing(true, previous, now, attacker_spec, target_spec, touch, hand_touch, wounds_hands, pose, their_pose, segments)
			var flesh_at := _first_crossing(false, previous, now, attacker_spec, target_spec, touch, hand_touch, wounds_hands, pose, their_pose, segments)
			steel_crossed = steel_at <= flesh_at
			flesh_crossed = not steel_crossed
		if steel_crossed:
			out.first_contact = ThreatEstimate.STEEL
			out.steel_time = t
			break
		if flesh_crossed:
			out.within_horizon = true
			out.hit_time = t
			out.first_contact = region
			return out
		if steel:
			previous = PackedFloat64Array([x, y, phi, theta, tx, ty, their_phi, their_theta])
	var horizon := float(HORIZON_TICKS) * dt
	out.hit_time = horizon
	out.residual_gap = gap
	out.readiness_remaining = maxf(0.0, ready - horizon)
	return out



## The surface clearance (m; ≤ 0 touching) between any collidable feature of
## the sword at `pose` (blade, crossguard bar, handle — GUARD-CONTACT-001) and
## any of the sword at `their_pose`: any steel stops a cut's path, protective
## or not, so a route is only clear past all of it.
static func _steel_clearance(pose: BladePose, definition: WeaponDefinition, their_pose: BladePose, their: WeaponDefinition, segments: SegmentContact) -> float:
	var mine := _features(pose, definition)
	var theirs := _features(their_pose, their)
	var least := INF
	for i in range(0, mine.size(), FEATURE_STRIDE):
		for j in range(0, theirs.size(), FEATURE_STRIDE):
			SimMath.closest_segments(mine[i], mine[i + 1], mine[i + 2], mine[i + 3], theirs[j], theirs[j + 1], theirs[j + 2], theirs[j + 3], segments)
			least = minf(least, segments.distance - mine[i + 4] - theirs[j + 4])
	return least


## Bisection steps that order a same-tick steel and flesh crossing: a fixed
## count, never "until converged" (1/64 of a tick).
const CROSSING_REFINEMENT := 6


## The fraction of the tick from `before` to `now` (each [x, y, φ, θ, target
## x, target y, target φ, target θ]) at which the steel clearance (`steel`) or
## the flesh gap first closed, by bisection on the interpolated bodies and
## swords. The tick's end when it closed only there.
static func _first_crossing(
	steel: bool,
	before: PackedFloat64Array,
	now: PackedFloat64Array,
	attacker_spec: CombatantPhysicsSpec,
	target_spec: CombatantPhysicsSpec,
	touch: float,
	hand_touch: float,
	wounds_hands: bool,
	pose: BladePose,
	their_pose: BladePose,
	segments: SegmentContact
) -> float:
	var open := 0.0
	var closed := 1.0
	for _i in CROSSING_REFINEMENT:
		var middle := (open + closed) * 0.5
		var x := SimMath.mix(before[0], now[0], middle)
		var y := SimMath.mix(before[1], now[1], middle)
		var phi := before[2] + SimMath.wrap_angle(now[2] - before[2]) * middle
		var theta := SimMath.mix(before[3], now[3], middle)
		var tx := SimMath.mix(before[4], now[4], middle)
		var ty := SimMath.mix(before[5], now[5], middle)
		var their_phi := before[6] + SimMath.wrap_angle(now[6] - before[6]) * middle
		var their_theta := SimMath.mix(before[7], now[7], middle)
		WeaponKinematics.pose_at(x, y, phi, theta, attacker_spec, pose)
		WeaponKinematics.pose_at(tx, ty, their_phi, their_theta, target_spec, their_pose)
		var gap := 0.0
		if steel:
			gap = _steel_clearance(pose, attacker_spec.weapon, their_pose, target_spec.weapon, segments)
		else:
			var definition := attacker_spec.weapon
			var hx := pose.point_x(definition.hilt_radius)
			var hy := pose.point_y(definition.hilt_radius)
			var px := pose.point_x(definition.tip_radius)
			var py := pose.point_y(definition.tip_radius)
			gap = _segment_gap(hx, hy, px, py, tx, ty) - touch
			if wounds_hands:
				gap = minf(gap, _hands_gap(hx, hy, px, py, their_pose, target_spec.weapon) - hand_touch)
		if gap <= 0.0:
			closed = middle
		else:
			open = middle
	## Leave the poses where the tick ended.
	WeaponKinematics.pose_at(now[0], now[1], now[2], now[3], attacker_spec, pose)
	WeaponKinematics.pose_at(now[4], now[5], now[6], now[7], target_spec, their_pose)
	return closed


## The least distance from the blade segment to either of the target's grip
## markers, at the target's sword pose (its hands ride its grips).
static func _hands_gap(hx: float, hy: float, px: float, py: float, their_pose: BladePose, their: WeaponDefinition) -> float:
	return minf(
		_segment_gap(hx, hy, px, py, their_pose.point_x(their.offhand_grip_radius), their_pose.point_y(their.offhand_grip_radius)),
		_segment_gap(hx, hy, px, py, their_pose.point_x(their.dominant_grip_radius), their_pose.point_y(their.dominant_grip_radius))
	)


## Each collidable feature of a posed sword as [x0, y0, x1, y1, radius]: the
## blade, then the crossguard bar and the handle where the weapon has them.
const FEATURE_STRIDE := 5


static func _features(pose: BladePose, weapon: WeaponDefinition) -> PackedFloat64Array:
	var out := PackedFloat64Array([
		pose.point_x(weapon.hilt_radius), pose.point_y(weapon.hilt_radius),
		pose.point_x(weapon.tip_radius), pose.point_y(weapon.tip_radius),
		weapon.blade_radius,
	])
	if weapon.guard_half_span > 0.0:
		var gx := pose.point_x(weapon.guard_centre_radius)
		var gy := pose.point_y(weapon.guard_centre_radius)
		var sx := pose.uy * weapon.guard_half_span
		var sy := -pose.ux * weapon.guard_half_span
		out.append_array([gx + sx, gy + sy, gx - sx, gy - sy, weapon.guard_radius])
	if weapon.handle_radius > 0.0:
		out.append_array([
			pose.point_x(0.0), pose.point_y(0.0),
			pose.point_x(weapon.guard_centre_radius), pose.point_y(weapon.guard_centre_radius),
			weapon.handle_radius,
		])
	return out


## Distance from the segment (`ax`, `ay`)–(`bx`, `by`) to the point (`x`, `y`).
static func _segment_gap(ax: float, ay: float, bx: float, by: float, x: float, y: float) -> float:
	var t := SimMath.closest_param_on_segment(ax, ay, bx, by, x, y)
	return SimMath.length(x - SimMath.mix(ax, bx, t), y - SimMath.mix(ay, by, t))

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
