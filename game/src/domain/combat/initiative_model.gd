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
## input; its blade — the only steel that stops a cut (STEEL-TOPOLOGY-001) —
## met by this sword's blade before the torso reads `ThreatEstimate.STEEL` (a
## tie goes to the steel, as in the duel). Steel is swept like the duel's:
## a tick that ends with the blades apart but closer than they travelled in
## it is sampled inside, so a fast point cannot skip the other blade. Blades
## already touching when the prediction starts are a bind, not an obstruction
## (`starts_bound`): only steel met again after they part is a new contact.
##
## The estimate never writes a fighter. Angle and speed are copied into
## locals (`theta`, `omega`, and the target's pair); the guard stop is
## `WeaponSystem.write_limited` into `coast_out` / `their_out`, the same
## arrival rule as the weapon step, and those buffers are discarded with
## the call.
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
	var condition := ConditionModel.compute(attacker.health, body.max_health, attacker.stamina, combat, ConditionState.new())
	var force := condition.force_scale
	var speed := condition.speed_scale
	## Damage term, then fatigue applied once (STAMINA-004). The return reads
	## the base. Swing, wind-up, brake and the zone read the scaled drive.
	var base_drive := body.weapon_torque_scale * condition.damage_force_scale
	var fatigue_scaled_drive := base_drive * condition.fatigue_scale
	var pose := BladePose.new()
	var inertia := WeaponKinematics.motor_inertia(attacker_spec, weapon.angle, pose)
	## Start-of-tick authority. The estimate does not invent a contact dip; each
	## predicted tick that continues recovers the same way the duel does
	## (IMPACT-AUTHORITY-001).
	var return_auth := attacker.impact_authority
	var their_return_auth := target.impact_authority
	var ready := _readiness(attacker, definition, fatigue_scaled_drive, base_drive, inertia, combat, return_auth)
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
	## The swords' steel as the duel measures it (blades and guards), when swept.
	var steel_geometry: SwordContactGeometry = SwordContactGeometry.new() if steel else null
	var apart := body.push_radius + target_spec.fighter.push_radius
	var tx := target.x
	var ty := target.y
	var gap := INF
	## The target's sword, swept only when asked (`steel`).
	var their := target_spec.weapon
	var their_theta := target.weapon.angle
	var their_omega := target.weapon.speed
	var their_swinging := CombatPhase.is_swinging(target.weapon.phase)
	var their_fatigue_scaled_drive := 0.0
	var their_base_drive := 0.0
	var their_ceiling := 0.0
	var their_speed_scale := 1.0
	var their_pose: BladePose = null
	## Last tick's bodies and swords, to order a same-tick crossing.
	var previous := PackedFloat64Array()
	## Last tick's steel clearance and steel extremes (each sword's blade base
	## and point and its crossguard's two ends), to sweep the steel between
	## ticks.
	var previous_steel := INF
	var previous_ends := PackedFloat64Array()
	previous_ends.resize(STEEL_EXTREMES * 4)
	var ends := PackedFloat64Array()
	ends.resize(STEEL_EXTREMES * 4)
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
		var their_condition := ConditionModel.compute(target.health, target_spec.fighter.max_health, target.stamina, combat, ConditionState.new())
		their_base_drive = target_spec.fighter.weapon_torque_scale * their_condition.damage_force_scale
		their_fatigue_scaled_drive = their_base_drive * their_condition.fatigue_scale
		their_ceiling = their.achievable_swing_speed(target.weapon.swing_charge, target.weapon.launch_preparation) * their_condition.speed_scale
		their_speed_scale = their_condition.speed_scale
		their_tracking = CommitmentModel.turn_torque_share(target, target_spec, their_condition, combat)
		their_rate_tracking = CommitmentModel.turn_rate_share(target, target_spec, their_condition, combat)
		their_pose = BladePose.new()
		WeaponKinematics.pose_at(x, y, phi, theta, attacker_spec, pose)
		WeaponKinematics.pose_at(tx, ty, target.facing, their_theta, target_spec, their_pose)
		previous_steel = _steel_clearance(pose, definition, their_pose, their, steel_geometry)
		out.starts_bound = previous_steel <= 0.0
		_blade_ends(pose, definition, their_pose, their, previous_ends)
	var bound := out.starts_bound
	previous = PackedFloat64Array([x, y, phi, theta, tx, ty, their_phi, their_theta])
	var coast_out := PackedFloat64Array([0.0, 0.0])
	var their_out := PackedFloat64Array([0.0, 0.0])
	var coast_side := weapon.stable_side
	var their_side := target.weapon.stable_side
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
		## Weapon. Until it is ready the blade is not frozen: it keeps moving
		## under the same coast the duel applies (the attack's brake while
		## overswinging or recovering above control speed, the guard return
		## once it is under control — GUARD-RETURN-001), so a guard knocked
		## spinning is predicted to spin away and then settle on its side.
		## Once ready it drives its strike toward the target speed. A swing
		## past its end stays where that tick left it.
		if not launched and t >= ready:
			launched = true
			ceiling = definition.achievable_swing_speed(charge, definition.preparation(theta)) * speed
			swing_end = clampf(theta + dir * definition.arc(charge), -definition.guard_limit, definition.guard_limit)
		if launched:
			if (theta - swing_end) * dir < 0.0:
				inertia = WeaponKinematics.motor_inertia(attacker_spec, theta, pose)
				omega = SimMath.approach(omega, dir * ceiling, definition.swing_accel(charge, fatigue_scaled_drive, inertia) * dt)
				WeaponSystem.write_limited(coast_out, theta, omega, definition.guard_limit, combat.guard_limit_zone, WeaponSystem.zone_spring(definition, fatigue_scaled_drive, inertia, combat), combat.guard_limit_damping, WeaponSystem.limit_accel_cap(definition, fatigue_scaled_drive, inertia))
				theta = coast_out[0]
				omega = coast_out[1]
		else:
			inertia = WeaponKinematics.motor_inertia(attacker_spec, theta, pose)
			omega = WeaponSystem.coast_speed(omega, theta, weapon.phase, coast_side, weapon.swing_charge, definition, fatigue_scaled_drive, base_drive, inertia, combat, return_auth, false)
			WeaponSystem.write_limited(coast_out, theta, omega, definition.guard_limit, combat.guard_limit_zone, WeaponSystem.zone_spring(definition, fatigue_scaled_drive, inertia, combat), combat.guard_limit_damping, WeaponSystem.limit_accel_cap(definition, fatigue_scaled_drive, inertia))
			theta = coast_out[0]
			omega = coast_out[1]
			if absf(theta) > definition.side_deadzone:
				coast_side = 1.0 if theta > 0.0 else -1.0
			if side_free and absf(theta) > definition.side_deadzone:
				dir = -1.0 if theta > 0.0 else 1.0
		WeaponKinematics.pose_at(x, y, phi, theta, attacker_spec, pose)
		var hx := pose.point_x(definition.blade_base_radius)
		var hy := pose.point_y(definition.blade_base_radius)
		var px := pose.point_x(definition.tip_radius)
		var py := pose.point_y(definition.tip_radius)
		var steel_now := INF
		var steel_crossed := false
		## Where in the tick a sampled steel crossing was found (> 1: none).
		var swept_at := 2.0
		if steel:
			if their_swinging and (their_theta - target.weapon.swing_end) * target.weapon.swing_dir < 0.0:
				var their_inertia := WeaponKinematics.motor_inertia(target_spec, their_theta, their_pose)
				their_omega = SimMath.approach(their_omega, target.weapon.swing_dir * their_ceiling, their.swing_accel(target.weapon.swing_charge, their_fatigue_scaled_drive, their_inertia) * dt)
			elif target.weapon.phase == CombatPhase.Id.CHARGING:
				## A held charge keeps winding back under its own motor, as
				## `WeaponSystem` drives it, while the button stays held.
				var their_inertia := WeaponKinematics.motor_inertia(target_spec, their_theta, their_pose)
				their_omega = SimMath.approach(their_omega, -target.weapon.swing_dir * their.windup_speed * their_speed_scale, their.windup_accel(their_fatigue_scaled_drive, their_inertia) * dt)
			else:
				var their_inertia := WeaponKinematics.motor_inertia(target_spec, their_theta, their_pose)
				their_omega = WeaponSystem.coast_speed(their_omega, their_theta, target.weapon.phase, their_side, target.weapon.swing_charge, their, their_fatigue_scaled_drive, their_base_drive, their_inertia, combat, their_return_auth, false)
			var their_inertia_now := WeaponKinematics.motor_inertia(target_spec, their_theta, their_pose)
			WeaponSystem.write_limited(their_out, their_theta, their_omega, their.guard_limit, combat.guard_limit_zone, WeaponSystem.zone_spring(their, their_fatigue_scaled_drive, their_inertia_now, combat), combat.guard_limit_damping, WeaponSystem.limit_accel_cap(their, their_fatigue_scaled_drive, their_inertia_now))
			their_theta = their_out[0]
			their_omega = their_out[1]
			if absf(their_theta) > their.side_deadzone:
				their_side = 1.0 if their_theta > 0.0 else -1.0
			WeaponKinematics.pose_at(tx, ty, their_phi, their_theta, target_spec, their_pose)
			steel_now = _steel_clearance(pose, definition, their_pose, their, steel_geometry)
			_blade_ends(pose, definition, their_pose, their, ends)
			if bound:
				## Still in the bind it started in, or just parted from it.
				bound = steel_now <= 0.0
			else:
				steel_crossed = steel_now <= 0.0
				## Open at both ends of the tick yet closer than the blades
				## travelled in it: a fast blade can cross the other inside the
				## tick, as the duel's substeps would find it, so sample it.
				if not steel_crossed and minf(previous_steel, steel_now) < _travel(previous_ends, ends):
					var now := PackedFloat64Array([x, y, phi, theta, tx, ty, their_phi, their_theta])
					swept_at = _steel_within(previous, now, attacker_spec, target_spec, pose, their_pose, steel_geometry)
					steel_crossed = swept_at <= 1.0
		var along := SimMath.closest_param_on_segment(hx, hy, px, py, tx, ty)
		gap = SimMath.length(tx - SimMath.mix(hx, px, along), ty - SimMath.mix(hy, py, along)) - touch
		var flesh_crossed := gap <= 0.0
		## Steel and flesh both reached inside this tick: order them by where
		## each first crossed, found by bisecting the tick on the interpolated
		## bodies and swords (a fixed count); a tie is the steel's.
		if steel_crossed and flesh_crossed:
			var now := PackedFloat64Array([x, y, phi, theta, tx, ty, their_phi, their_theta])
			var steel_at := swept_at if swept_at <= 1.0 else _first_crossing(true, previous, now, attacker_spec, target_spec, touch, pose, their_pose, steel_geometry)
			var flesh_at := _first_crossing(false, previous, now, attacker_spec, target_spec, touch, pose, their_pose, steel_geometry)
			steel_crossed = steel_at <= flesh_at
			flesh_crossed = not steel_crossed
		if steel_crossed:
			out.first_contact = ThreatEstimate.STEEL
			out.steel_time = t
			break
		if flesh_crossed:
			out.within_horizon = true
			out.hit_time = t
			out.first_contact = ThreatEstimate.BODY
			return out
		if steel:
			previous = PackedFloat64Array([x, y, phi, theta, tx, ty, their_phi, their_theta])
			previous_steel = steel_now
			for i in ends.size():
				previous_ends[i] = ends[i]
		return_auth = ImpactAuthority.recover(return_auth, combat.guard_return_natural_frequency, dt)
		their_return_auth = ImpactAuthority.recover(their_return_auth, combat.guard_return_natural_frequency, dt)
	var horizon := float(HORIZON_TICKS) * dt
	out.hit_time = horizon
	out.residual_gap = gap
	out.readiness_remaining = maxf(0.0, ready - horizon)
	return out



## The surface clearance (m; ≤ 0 touching) between the steel of the sword at
## `pose` and the sword at `their_pose` — blade on blade, and each guard root
## against the other blade from its protected side (STEEL-TOPOLOGY-001,
## GUARD-PROTECTION-001), measured as the duel measures it: a route is clear
## once it is past the other sword's steel. A prediction has no contact history,
## so every guard side is read fresh.
static func _steel_clearance(pose: BladePose, definition: WeaponDefinition, their_pose: BladePose, their: WeaponDefinition, steel_geometry: SwordContactGeometry) -> float:
	return steel_geometry.measure(pose.origin_x, pose.origin_y, pose.origin_x, pose.origin_y, pose.ux, pose.uy, their_pose.origin_x, their_pose.origin_y, their_pose.ux, their_pose.uy, definition, their)


## Bisection steps that order a same-tick steel and flesh crossing: a fixed
## count, never "until converged" (1/64 of a tick).
const CROSSING_REFINEMENT := 6
## Samples inside a tick whose blades came within that tick's travel of each
## other: a fixed count, enough that the fastest point moves about a blade's
## thickness between samples.
const STEEL_SWEEP_SAMPLES := 16


## Points per sword that bound how far its steel moves: the blade's base and
## point and the crossguard's two ends. A sword moves rigidly, so no point of
## its steel (the blade and the guard root, within their convex hull) moves
## farther than the farthest of these.
const STEEL_EXTREMES := 4


## Both swords' steel extremes — this sword's, then the other's — into `out`
## (`STEEL_EXTREMES` points each, as x, y).
static func _blade_ends(pose: BladePose, definition: WeaponDefinition, their_pose: BladePose, their: WeaponDefinition, out: PackedFloat64Array) -> void:
	_steel_extremes(pose, definition, out, 0)
	_steel_extremes(their_pose, their, out, STEEL_EXTREMES * 2)


static func _steel_extremes(pose: BladePose, definition: WeaponDefinition, out: PackedFloat64Array, at: int) -> void:
	var bar := definition.crossguard_centre_radius
	var half := definition.crossguard_half_span
	out[at] = pose.point_x(definition.blade_base_radius)
	out[at + 1] = pose.point_y(definition.blade_base_radius)
	out[at + 2] = pose.point_x(definition.tip_radius)
	out[at + 3] = pose.point_y(definition.tip_radius)
	out[at + 4] = pose.point_x(bar) - pose.uy * half
	out[at + 5] = pose.point_y(bar) + pose.ux * half
	out[at + 6] = pose.point_x(bar) + pose.uy * half
	out[at + 7] = pose.point_y(bar) - pose.ux * half


## How far the two swords' steel could have closed on each other over the
## tick: the farthest any extreme of each moved, summed.
static func _travel(before: PackedFloat64Array, now: PackedFloat64Array) -> float:
	var moved := PackedFloat64Array([0.0, 0.0])
	for point in STEEL_EXTREMES * 2:
		var sword := 0 if point < STEEL_EXTREMES else 1
		moved[sword] = maxf(moved[sword], SimMath.length(now[2 * point] - before[2 * point], now[2 * point + 1] - before[2 * point + 1]))
	return moved[0] + moved[1]


## The first of `STEEL_SWEEP_SAMPLES` evenly spaced instants inside the tick
## from `before` to `now` at which the blades touch, as a fraction of the tick;
## 2.0 when none does. Leaves the poses where the tick ended.
static func _steel_within(
	before: PackedFloat64Array,
	now: PackedFloat64Array,
	attacker_spec: CombatantPhysicsSpec,
	target_spec: CombatantPhysicsSpec,
	pose: BladePose,
	their_pose: BladePose,
	steel_geometry: SwordContactGeometry
) -> float:
	var found := 2.0
	for i in range(1, STEEL_SWEEP_SAMPLES):
		var fraction := float(i) / float(STEEL_SWEEP_SAMPLES)
		_pose_between(before, now, fraction, attacker_spec, target_spec, pose, their_pose)
		if _steel_clearance(pose, attacker_spec.weapon, their_pose, target_spec.weapon, steel_geometry) <= 0.0:
			found = fraction
			break
	WeaponKinematics.pose_at(now[0], now[1], now[2], now[3], attacker_spec, pose)
	WeaponKinematics.pose_at(now[4], now[5], now[6], now[7], target_spec, their_pose)
	return found


## Both swords posed at `fraction` of the tick from `before` to `now` (each
## [x, y, φ, θ, target x, target y, target φ, target θ]), on the interpolated
## bodies and swords.
static func _pose_between(before: PackedFloat64Array, now: PackedFloat64Array, fraction: float, attacker_spec: CombatantPhysicsSpec, target_spec: CombatantPhysicsSpec, pose: BladePose, their_pose: BladePose) -> void:
	var phi := before[2] + SimMath.wrap_angle(now[2] - before[2]) * fraction
	var their_phi := before[6] + SimMath.wrap_angle(now[6] - before[6]) * fraction
	WeaponKinematics.pose_at(SimMath.mix(before[0], now[0], fraction), SimMath.mix(before[1], now[1], fraction), phi, SimMath.mix(before[3], now[3], fraction), attacker_spec, pose)
	WeaponKinematics.pose_at(SimMath.mix(before[4], now[4], fraction), SimMath.mix(before[5], now[5], fraction), their_phi, SimMath.mix(before[7], now[7], fraction), target_spec, their_pose)


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
	pose: BladePose,
	their_pose: BladePose,
	steel_geometry: SwordContactGeometry
) -> float:
	var open := 0.0
	var closed := 1.0
	for _i in CROSSING_REFINEMENT:
		var middle := (open + closed) * 0.5
		_pose_between(before, now, middle, attacker_spec, target_spec, pose, their_pose)
		var tx := SimMath.mix(before[4], now[4], middle)
		var ty := SimMath.mix(before[5], now[5], middle)
		var gap := 0.0
		if steel:
			gap = _steel_clearance(pose, attacker_spec.weapon, their_pose, target_spec.weapon, steel_geometry)
		else:
			var definition := attacker_spec.weapon
			var hx := pose.point_x(definition.blade_base_radius)
			var hy := pose.point_y(definition.blade_base_radius)
			var px := pose.point_x(definition.tip_radius)
			var py := pose.point_y(definition.tip_radius)
			gap = _segment_gap(hx, hy, px, py, tx, ty) - touch
		if gap <= 0.0:
			closed = middle
		else:
			open = middle
	## Leave the poses where the tick ended.
	WeaponKinematics.pose_at(now[0], now[1], now[2], now[3], attacker_spec, pose)
	WeaponKinematics.pose_at(now[4], now[5], now[6], now[7], target_spec, their_pose)
	return closed


## Distance from the segment (`ax`, `ay`)–(`bx`, `by`) to the point (`x`, `y`).
static func _segment_gap(ax: float, ay: float, bx: float, by: float, x: float, y: float) -> float:
	var t := SimMath.closest_param_on_segment(ax, ay, bx, by, x, y)
	return SimMath.length(x - SimMath.mix(ax, bx, t), y - SimMath.mix(ay, by, t))

## Seconds until the weapon is back under control and may strike — the same
## gate recovery itself ends on (RECOVERY-001): an overswing brakes to rest
## and then sits out the universal floor; a recovery waits for the rest of its
## floor or for its brake to bring the blade under `control_speed`, whichever
## is later; a stagger runs out.
static func _readiness(attacker: FighterState, definition: WeaponDefinition, fatigue_scaled_drive: float, base_drive: float, inertia: float, combat: CombatTuning, return_scale: float) -> float:
	var weapon := attacker.weapon
	var dt := SimulationTimebase.TICK_SECONDS
	var brake := definition.brake_accel(weapon.swing_charge, fatigue_scaled_drive, inertia)
	match weapon.phase:
		CombatPhase.Id.NEUTRAL:
			return _seconds_until_controlled(weapon, definition, fatigue_scaled_drive, base_drive, inertia, combat, return_scale)
		CombatPhase.Id.OVERSWING:
			return absf(weapon.speed) / brake + float(combat.recovery_min_ticks) * dt
		CombatPhase.Id.RECOVERY:
			return maxf(float(weapon.recovery_left) * dt, maxf(0.0, absf(weapon.speed) - definition.control_speed) / brake)
		CombatPhase.Id.STAGGER:
			return float(attacker.stagger_left) * dt
	return 0.0


## How long the guard return takes to bring a neutral blade back under
## `control_speed`, stepping the same coast the duel uses.
static func _seconds_until_controlled(weapon: WeaponState, definition: WeaponDefinition, fatigue_scaled_drive: float, base_drive: float, inertia: float, combat: CombatTuning, return_scale: float) -> float:
	if absf(weapon.speed) <= definition.control_speed:
		return 0.0
	var dt := SimulationTimebase.TICK_SECONDS
	var angle := weapon.angle
	var omega := weapon.speed
	var side := weapon.stable_side
	var out := PackedFloat64Array([0.0, 0.0])
	for i in HORIZON_TICKS:
		omega = WeaponSystem.coast_speed(omega, angle, weapon.phase, side, weapon.swing_charge, definition, fatigue_scaled_drive, base_drive, inertia, combat, return_scale, false)
		WeaponSystem.write_limited(out, angle, omega, definition.guard_limit, combat.guard_limit_zone, WeaponSystem.zone_spring(definition, fatigue_scaled_drive, inertia, combat), combat.guard_limit_damping, WeaponSystem.limit_accel_cap(definition, fatigue_scaled_drive, inertia))
		angle = out[0]
		omega = out[1]
		if absf(angle) > definition.side_deadzone:
			side = 1.0 if angle > 0.0 else -1.0
		if absf(omega) <= definition.control_speed:
			return float(i + 1) * dt
		return_scale = ImpactAuthority.recover(return_scale, combat.guard_return_natural_frequency, dt)
	return float(HORIZON_TICKS) * dt


## Positive when `fighter` threatens first.
static func initiative(fighter: FighterState, opponent: FighterState, rules: DuelRules) -> float:
	return time_to_threat(opponent, fighter, rules) - time_to_threat(fighter, opponent, rules)
