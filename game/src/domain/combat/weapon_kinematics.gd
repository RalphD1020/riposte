class_name WeaponKinematics
extends RefCounted

## The one home of authoritative sword kinematics (WEAPON-PATH-001, PHYS-007).
## Every system that needs where a blade is, how fast a point on it moves, or
## how hard it is to turn asks here; nothing rebuilds `centre + û·r` itself.
##
## The current weapon is this sword and only this sword: one planar angle, a
## blade capsule, and a crossguard. A different shape would be a new model
## with its own state. This file is that sword, not a registry.
##
## The sword is rigid and has one coordinate, θ, its yaw from the combat heading
## φ (WEAPON-PATH-003). The attack track places its carriage (grip centre),
## `carriage = X + R(φ)·C(θ)`; the origin (pommel) sits a grip-centre radius `g`
## back down the blade, `P(θ) = C(θ) − g·û(θ)`, so `P′(θ) = C′(θ) − g·perp(û)`
## — the carriage's translation plus the ordinary rotation, nothing else. A
## point at world position `p` on the blade therefore moves at
##
## ```text
## v = v_fighter + (φ̇ + θ̇)·perp(p − X) + θ̇·(R(φ)·P′(θ) − perp(origin − X))
## ```
##
## The last term is the attack path's contribution, written as an additive
## correction to the revolute model: on the fixed pivot it is exactly zero, so
## the same code reproduces the circle to the bit. Its projection on a contact
## normal is the weapon coordinate's Jacobian (`lever`), which is how an
## impulse at a point becomes a change of θ̇.
##
## Every function takes the combatant's `CombatantPhysicsSpec`: the track is
## its handling's, the blade and mass its weapon's, the hands its body's. No
## function here knows which fighter it is posing (COMBATANT-GENERIC-001).
##
## Implements: /spec/invariants.md#weapon-path-001
## See also: /docs/concepts/combat.md


## Pose `fighter`'s sword into `out` (and return it).
static func pose_of(fighter: FighterState, spec: CombatantPhysicsSpec, out: BladePose) -> BladePose:
	return pose_at(fighter.x, fighter.y, fighter.facing, fighter.weapon.angle, spec, out)


## Pose a sword from explicit centre, combat heading, and weapon angle.
static func pose_at(x: float, y: float, facing: float, angle: float, spec: CombatantPhysicsSpec, out: BladePose) -> BladePose:
	var cf := SimMath.heading_cosine(facing)
	var sf := SimMath.heading_sine(facing)
	var ca := SimMath.cosine(angle)
	var sa := SimMath.sine(angle)
	## û = R(φ)·(cos θ, sin θ). The heading uses the half-turn pair and θ the
	## odd series, so a mirrored duel and a left/right reflection both stay
	## exact (WEAPON-ORBIT-004).
	out.ux = cf * ca - sf * sa
	out.uy = sf * ca + cf * sa
	var path := spec.handling.attack_path
	var g := spec.handling.carriage_radius
	if path.is_fixed():
		out.origin_x = x
		out.origin_y = y
		out.offset_x = 0.0
		out.offset_y = 0.0
		out.carriage_x = x + out.ux * g
		out.carriage_y = y + out.uy * g
		out.dorigin_x = 0.0
		out.dorigin_y = 0.0
		out.carriage_forward = 0.0
		out.carriage_left = 0.0
		out.d_carriage_forward = 0.0
		out.d_carriage_left = 0.0
		return out
	path.sample_into(angle, out)
	## Combat frame: P = C − g·û(θ), P′ = C′ − g·perp(û(θ)).
	var origin_forward := out.carriage_forward - g * ca
	var origin_left := out.carriage_left - g * sa
	var dorigin_forward := out.d_carriage_forward + g * sa
	var dorigin_left := out.d_carriage_left - g * ca
	out.carriage_x = x + out.carriage_forward * cf - out.carriage_left * sf
	out.carriage_y = y + out.carriage_forward * sf + out.carriage_left * cf
	out.offset_x = origin_forward * cf - origin_left * sf
	out.offset_y = origin_forward * sf + origin_left * cf
	out.origin_x = x + out.offset_x
	out.origin_y = y + out.offset_y
	out.dorigin_x = dorigin_forward * cf - dorigin_left * sf
	out.dorigin_y = dorigin_forward * sf + dorigin_left * cf
	return out


## Velocity of the world point (`px`, `py`) on `fighter`'s posed blade, written
## to `pose.vx` / `pose.vy`.
static func velocity_into(fighter: FighterState, pose: BladePose, px: float, py: float) -> void:
	var omega := fighter.turn_rate + fighter.weapon.speed
	path_velocity_into(fighter, pose)
	pose.vx = fighter.vx - omega * (py - fighter.y) + pose.vx
	pose.vy = fighter.vy + omega * (px - fighter.x) + pose.vy


## Only the attack path's share of a blade point's velocity,
## `θ̇·(R(φ)·P′(θ) − perp(origin − X))`, written to `pose.vx` / `pose.vy`.
## Exactly zero on the fixed pivot.
static func path_velocity_into(fighter: FighterState, pose: BladePose) -> void:
	var theta_dot := fighter.weapon.speed
	pose.vx = theta_dot * (pose.dorigin_x + pose.offset_y)
	pose.vy = theta_dot * (pose.dorigin_y - pose.offset_x)


## The weapon coordinate's Jacobian at (`px`, `py`) projected on the unit
## normal (`nx`, `ny`): how fast that point moves along the normal per unit
## θ̇ — the lever an impulse there acts through.
static func lever(fighter: FighterState, pose: BladePose, px: float, py: float, nx: float, ny: float) -> float:
	var cross := (px - fighter.x) * ny - (py - fighter.y) * nx
	return cross + ((pose.dorigin_x + pose.offset_y) * nx + (pose.dorigin_y - pose.offset_x) * ny)


## Resistance of the weapon coordinate to acceleration at this pose:
## `I_origin + m·(|P′|² + 2·d_c·P′·perp(û))`, d_c the centre of mass's distance
## down the blade from the origin. On the fixed pivot it is the moment of
## inertia exactly.
static func generalized_inertia(spec: CombatantPhysicsSpec, pose: BladePose) -> float:
	var weapon := spec.weapon
	var inertia := weapon.moment_of_inertia()
	if spec.handling.attack_path.is_fixed():
		return inertia
	var path_speed_sq := pose.dorigin_x * pose.dorigin_x + pose.dorigin_y * pose.dorigin_y
	var coupling := pose.dorigin_x * -pose.uy + pose.dorigin_y * pose.ux
	return inertia + weapon.mass * (path_speed_sq + 2.0 * weapon.center_of_mass_radius * coupling)


## Resistance of the weapon coordinate of a *held* sword: the sword's own
## generalized inertia plus the wielder's hands (and the share of the forearms
## they reflect, `hand_mass` each) riding rigidly at the weapon's grip
## stations, which the same formula treats as point masses at
## `offhand_grip_radius` and `dominant_grip_radius`
## (`m·(r² + |P′|² + 2·r·P′·perp(û))`). Passive inertia only — the wielder's
## strength is the bounded motor (RIGID-CONTACT-001).
static func held_inertia(spec: CombatantPhysicsSpec, pose: BladePose) -> float:
	var weapon := spec.weapon
	var hand_mass := spec.fighter.hand_mass
	var inertia := generalized_inertia(spec, pose)
	var path_speed_sq := pose.dorigin_x * pose.dorigin_x + pose.dorigin_y * pose.dorigin_y
	var coupling := pose.dorigin_x * -pose.uy + pose.dorigin_y * pose.ux
	var off := weapon.offhand_grip_radius
	var dominant := weapon.dominant_grip_radius
	return inertia + hand_mass * (off * off + dominant * dominant + 2.0 * path_speed_sq + 2.0 * (off + dominant) * coupling)


## The one inertia of the weapon coordinate at `angle` (UNIFIED-MASS-001): the
## held sword's generalized inertia there (`held_inertia`), which the motor
## divides its torque by exactly as every contact divides its impulse by it.
## A function of θ alone — the combat-frame pose is rotation invariant — so a
## caller may pass any pose to sample into (`out`), or none.
static func motor_inertia(spec: CombatantPhysicsSpec, angle: float, out: BladePose = null) -> float:
	var pose := out if out != null else BladePose.new()
	pose_at(0.0, 0.0, 0.0, angle, spec, pose)
	return held_inertia(spec, pose)


## The largest the weapon coordinate's inertia gets anywhere on the track — an
## upper bound for estimates that must not undercount how long a drive takes.
static func peak_motor_inertia(spec: CombatantPhysicsSpec) -> float:
	var pose := BladePose.new()
	var limit := spec.weapon.guard_limit
	var peak := 0.0
	for sample in floori(rad_to_deg(limit) / CLEARANCE_STEP_DEG) + 1:
		peak = maxf(peak, motor_inertia(spec, minf(deg_to_rad(float(sample) * CLEARANCE_STEP_DEG), limit), pose))
	return peak


## How far ahead of the body centre the tip reaches in Long Guard (θ = 0): the
## carriage there plus the blade beyond it. The track's longest forward reach,
## for threat and spacing estimates.
static func forward_reach(spec: CombatantPhysicsSpec) -> float:
	var pose := pose_at(0.0, 0.0, 0.0, 0.0, spec, BladePose.new())
	return pose.point_x(spec.weapon.tip_radius)


## Every |θ| the clearance sweep samples, in degrees (both sides mirror).
const CLEARANCE_STEP_DEG := 0.5


## The least surface-to-surface gap (m) over the whole track between the
## fighter's hurt torso and what the track carries: each hand (`hand_radius`
## round its grip point) and the whole rigid sword, pommel to tip, as a capsule
## of `blade_radius`. Negative means a hand or part of the sword sits inside
## the torso somewhere — a pose nobody could hold (WEAPON-PATH-003). The fixed
## pivot has no carriage and reports +INF.
static func least_surface_gap(spec: CombatantPhysicsSpec) -> float:
	return minf(minf(_least_over_track(spec, 0), _least_over_track(spec, 1)), _least_over_track(spec, 2))


## The least surface gap at one |θ| (radians): hands, sword and crossguard.
static func surface_gap_at(spec: CombatantPhysicsSpec, angle: float) -> float:
	return minf(minf(hand_gap_at(spec, angle), sword_gap_at(spec, angle)), crossguard_gap_at(spec, angle))


## The crossguard bar's surface gap to the wielder's own torso at one |θ|
## (radians); +INF for a sword without a guard or on the fixed pivot.
static func crossguard_gap_at(spec: CombatantPhysicsSpec, angle: float) -> float:
	var weapon := spec.weapon
	if spec.handling.attack_path.is_fixed() or weapon.crossguard_half_span <= 0.0:
		return INF
	var pose := pose_at(0.0, 0.0, 0.0, angle, spec, BladePose.new())
	var cx := pose.point_x(weapon.crossguard_centre_radius)
	var cy := pose.point_y(weapon.crossguard_centre_radius)
	var x0 := cx + pose.uy * weapon.crossguard_half_span
	var y0 := cy - pose.ux * weapon.crossguard_half_span
	var x1 := cx - pose.uy * weapon.crossguard_half_span
	var y1 := cy + pose.ux * weapon.crossguard_half_span
	var t := SimMath.closest_param_on_segment(x0, y0, x1, y1, 0.0, 0.0)
	return SimMath.length(SimMath.mix(x0, x1, t), SimMath.mix(y0, y1, t)) - spec.fighter.hurt_radius - weapon.crossguard_radius


## The hands' surface gap at one |θ| (radians).
static func hand_gap_at(spec: CombatantPhysicsSpec, angle: float) -> float:
	var weapon := spec.weapon
	if spec.handling.attack_path.is_fixed():
		return INF
	var pose := pose_at(0.0, 0.0, 0.0, angle, spec, BladePose.new())
	var least := INF
	for r in PackedFloat64Array([weapon.offhand_grip_radius, weapon.dominant_grip_radius]):
		least = minf(least, SimMath.length(pose.point_x(r), pose.point_y(r)) - spec.fighter.hurt_radius - spec.fighter.hand_radius)
	return least


## The rigid sword's surface gap at one |θ| (radians): the nearest point of the
## pommel-to-tip segment to the torso's centre, less both radii.
static func sword_gap_at(spec: CombatantPhysicsSpec, angle: float) -> float:
	var weapon := spec.weapon
	if spec.handling.attack_path.is_fixed():
		return INF
	var pose := pose_at(0.0, 0.0, 0.0, angle, spec, BladePose.new())
	## The origin is the segment's start and û its unit direction, so the
	## nearest point sits at the clamped projection of the centre on it.
	var along := clampf(-(pose.origin_x * pose.ux + pose.origin_y * pose.uy), 0.0, weapon.tip_radius)
	return SimMath.length(pose.point_x(along), pose.point_y(along)) - spec.fighter.hurt_radius - weapon.blade_radius


## `part` 0 = hands, 1 = sword, 2 = crossguard.
static func _least_over_track(spec: CombatantPhysicsSpec, part: int) -> float:
	if spec.handling.attack_path.is_fixed():
		return INF
	var limit := spec.weapon.guard_limit
	var least := INF
	for sample in floori(rad_to_deg(limit) / CLEARANCE_STEP_DEG) + 1:
		var at := minf(deg_to_rad(float(sample) * CLEARANCE_STEP_DEG), limit)
		match part:
			0:
				least = minf(least, hand_gap_at(spec, at))
			1:
				least = minf(least, sword_gap_at(spec, at))
			_:
				least = minf(least, crossguard_gap_at(spec, at))
	return least


## Centre-to-centre distance at which `attacker`'s Longpoint tip touches
## `target`'s hurt torso — the threat range, never the push footprint. The
## attacker's reach against the target's body: a long sword threatens a small
## target from further away, and nobody's reach is assumed.
static func strike_reach(attacker: CombatantPhysicsSpec, target: CombatantPhysicsSpec) -> float:
	return forward_reach(attacker) + target.fighter.hurt_radius


## Distance (m) from the origin along the blade to the point (`px`, `py`)'s
## projection, for blade fractions.
static func radius_of(pose: BladePose, px: float, py: float) -> float:
	return SimMath.length(px - pose.origin_x, py - pose.origin_y)
