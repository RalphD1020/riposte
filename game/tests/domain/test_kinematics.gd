extends TestCase

## KINEMATICS: the one home of sword geometry (WEAPON-PATH-001, PHYS-007).
## On the fixed pivot it reproduces the revolute sword exactly; on a moving
## origin its point velocity, lever (the weapon coordinate's Jacobian on a
## normal) and generalized inertia agree with finite differences and with the
## rigid sword's kinetic energy.
##
## Implements: /spec/invariants.md#weapon-path-001
## See also: /docs/concepts/combat.md

const DT := 1e-6
const FD_TOLERANCE := 1e-4


func _init() -> void:
	suite_name = "KINEMATICS"


## A smooth, mirrored test manifold: forward is even in θ, left is odd, so the
## path has the production path's symmetry without its tuning.
class CurvedPath:
	extends WeaponAttackPath

	func _init() -> void:
		_fixed = false

	func sample_into(angle: float, out: BladePose) -> void:
		out.carriage_forward = 0.12 + 0.08 * SimMath.cosine(angle)
		out.carriage_left = 0.15 * SimMath.sine(angle)
		out.d_carriage_forward = -0.08 * SimMath.sine(angle)
		out.d_carriage_left = 0.15 * SimMath.cosine(angle)


## The shipped loadout: the reference duelist with the bastard sword and their
## handling (LOADOUT-001).
func _shipped() -> CombatantPhysicsSpec:
	return LoadoutCatalog.compile(ContentIds.FIGHTER_DUELIST, ContentIds.WEAPON_BASTARD_SWORD)


## The shipped loadout carried on the test manifold, or on the fixed pivot.
func _spec(curved: bool) -> CombatantPhysicsSpec:
	var spec := _shipped()
	spec.handling.attack_path = CurvedPath.new() if curved else WeaponAttackPath.fixed_pivot()
	return spec


func _fighter(x: float, y: float, facing: float, angle: float) -> FighterState:
	var fighter := FighterState.new()
	DuelFixture.place(fighter, x, y, facing)
	fighter.weapon.angle = angle
	fighter.vx = 0.7
	fighter.vy = -0.4
	fighter.turn_rate = 1.3
	fighter.weapon.speed = -6.0
	return fighter


func test_the_fixed_pivot_reproduces_the_revolute_sword_exactly() -> void:
	var spec := _spec(false)
	var weapon := spec.weapon
	assert_true(spec.handling.attack_path.is_fixed(), "fixture: the fixed pivot")
	var pose := BladePose.new()
	for case: Array in [[0.0, 0.0, 0.3, -0.7], [1.2, -2.5, -2.0, 2.3], [-4.0, 3.0, PI, 0.0]]:
		var fighter := _fighter(case[0], case[1], case[2], case[3])
		WeaponKinematics.pose_of(fighter, spec, pose)
		var blade := DuelGeometry.blade_angle(fighter)
		assert_eq(pose.origin_x, fighter.x, "the origin is the centre (x)")
		assert_eq(pose.origin_y, fighter.y, "the origin is the centre (y)")
		assert_eq(pose.point_x(weapon.tip_radius), fighter.x + SimMath.cosine(blade) * weapon.tip_radius, "the tip is centre + û·L, to the bit")
		var px := pose.point_x(0.8)
		var py := pose.point_y(0.8)
		var omega := fighter.turn_rate + fighter.weapon.speed
		WeaponKinematics.velocity_into(fighter, pose, px, py)
		assert_eq(pose.vx, fighter.vx - omega * (py - fighter.y), "velocity is v + ω×r (x)")
		assert_eq(pose.vy, fighter.vy + omega * (px - fighter.x), "velocity is v + ω×r (y)")
		assert_eq(WeaponKinematics.lever(fighter, pose, px, py, 0.6, 0.8), (px - fighter.x) * 0.8 - (py - fighter.y) * 0.6, "the lever is r × n")
		assert_eq(WeaponKinematics.generalized_inertia(spec, pose), weapon.moment_of_inertia(), "the inertia is the moment of inertia")


## v(p) for a material point p on the blade equals the finite-difference rate
## of that point as the fighter translates, the heading turns and θ moves.
func test_a_moving_origin_point_velocity_matches_finite_differences() -> void:
	var spec := _spec(true)
	var weapon := spec.weapon
	var fighter := _fighter(0.4, -1.1, 0.9, -1.2)
	var pose := WeaponKinematics.pose_of(fighter, spec, BladePose.new())
	assert_true(absf(pose.offset_x) + absf(pose.offset_y) > 0.05, "fixture: the origin is off the centre")
	var r := 0.9
	var px := pose.point_x(r)
	var py := pose.point_y(r)
	WeaponKinematics.velocity_into(fighter, pose, px, py)
	var later := WeaponKinematics.pose_at(fighter.x + fighter.vx * DT, fighter.y + fighter.vy * DT, fighter.facing + fighter.turn_rate * DT, fighter.weapon.angle + fighter.weapon.speed * DT, spec, BladePose.new())
	assert_near(pose.vx, (later.point_x(r) - px) / DT, FD_TOLERANCE, "x velocity matches the finite difference")
	assert_near(pose.vy, (later.point_y(r) - py) / DT, FD_TOLERANCE, "y velocity matches the finite difference")
	var revolute := fighter.vx - (fighter.turn_rate + fighter.weapon.speed) * (py - fighter.y)
	assert_true(absf(pose.vx - revolute) > 0.01, "perturbation: the path's own motion is part of it")


## The lever is ∂p/∂θ · n: how far the contact point moves along the normal per
## radian of weapon angle.
func test_the_lever_is_the_weapon_jacobian_on_the_normal() -> void:
	var spec := _spec(true)
	var fighter := _fighter(0.0, 0.0, 0.0, 0.6)
	var pose := WeaponKinematics.pose_of(fighter, spec, BladePose.new())
	var r := 0.7
	var nx := 0.28
	var ny := -0.96
	var lever := WeaponKinematics.lever(fighter, pose, pose.point_x(r), pose.point_y(r), nx, ny)
	var nudged := WeaponKinematics.pose_at(fighter.x, fighter.y, fighter.facing, fighter.weapon.angle + DT, spec, BladePose.new())
	var dpx := (nudged.point_x(r) - pose.point_x(r)) / DT
	var dpy := (nudged.point_y(r) - pose.point_y(r)) / DT
	assert_near(lever, dpx * nx + dpy * ny, FD_TOLERANCE, "lever = (∂p/∂θ)·n")


## M_θ = I_cm + m·|∂c/∂θ|²: the kinetic energy of the rigid sword per ½θ̇²,
## with c the centre of mass down the blade.
func test_generalized_inertia_is_the_rigid_swords_kinetic_energy() -> void:
	var spec := _spec(true)
	var weapon := spec.weapon
	var fighter := _fighter(0.0, 0.0, 0.3, -0.4)
	var pose := WeaponKinematics.pose_of(fighter, spec, BladePose.new())
	var d_c := weapon.center_of_mass_radius
	var nudged := WeaponKinematics.pose_at(fighter.x, fighter.y, fighter.facing, fighter.weapon.angle + DT, spec, BladePose.new())
	var dcx := (nudged.point_x(d_c) - pose.point_x(d_c)) / DT
	var dcy := (nudged.point_y(d_c) - pose.point_y(d_c)) / DT
	var about_center := weapon.moment_of_inertia() - weapon.mass * d_c * d_c
	var expected := about_center + weapon.mass * (dcx * dcx + dcy * dcy)
	assert_near(WeaponKinematics.generalized_inertia(spec, pose), expected, 1e-3, "M_θ is the rigid sword's kinetic-energy mass")
	assert_true(absf(expected - weapon.moment_of_inertia()) > 1e-3, "perturbation: a moving origin changes it")


## The shipped manifold is exactly mirrored: the left pose is the right pose
## reflected across the combat heading, with matching speeds — no side
## advantage hides in the geometry.
func test_the_shipped_manifold_is_mirrored() -> void:
	var spec := _shipped()
	assert_false(spec.handling.attack_path.is_fixed(), "fixture: the shipped sword rides its attack manifold")
	var right := BladePose.new()
	var left := BladePose.new()
	for degrees in range(0, 136, 5):
		var angle := deg_to_rad(float(degrees))
		spec.handling.attack_path.sample_into(-angle, right)
		spec.handling.attack_path.sample_into(angle, left)
		assert_near(left.carriage_forward, right.carriage_forward, 1e-12, "forward matches at ±%d°" % degrees)
		assert_near(left.carriage_left, -right.carriage_left, 1e-12, "lateral mirrors at ±%d°" % degrees)
		assert_near(left.d_carriage_forward, -right.d_carriage_forward, 1e-12, "forward speed mirrors at ±%d°" % degrees)
		assert_near(left.d_carriage_left, right.d_carriage_left, 1e-12, "lateral speed matches at ±%d°" % degrees)


## C0 and C1 everywhere, including through Longpoint and every knot: a kink in
## P(θ) would make point velocity — and force — jump under smooth input.
func test_the_shipped_manifold_is_smooth() -> void:
	var path := _shipped().handling.attack_path
	var pose := BladePose.new()
	var previous := BladePose.new()
	var step := deg_to_rad(0.25)
	path.sample_into(deg_to_rad(-135.0), previous)
	var angle := deg_to_rad(-135.0) + step
	var worst_position := 0.0
	var worst_slope := 0.0
	while angle <= deg_to_rad(135.0):
		path.sample_into(angle, pose)
		var moved := SimMath.length(pose.carriage_forward - previous.carriage_forward, pose.carriage_left - previous.carriage_left)
		var predicted := SimMath.length(previous.d_carriage_forward, previous.d_carriage_left) * step
		worst_position = maxf(worst_position, absf(moved - predicted))
		worst_slope = maxf(worst_slope, SimMath.length(pose.d_carriage_forward - previous.d_carriage_forward, pose.d_carriage_left - previous.d_carriage_left))
		previous.carriage_forward = pose.carriage_forward
		previous.carriage_left = pose.carriage_left
		previous.d_carriage_forward = pose.d_carriage_forward
		previous.d_carriage_left = pose.d_carriage_left
		angle += step
	assert_true(worst_position < 1e-3, "position follows its own derivative (C0/C1: worst %.5f m per step)" % worst_position)
	assert_true(worst_slope < 0.02, "the derivative never jumps (worst %.4f m/rad per step)" % worst_slope)


## The postures the manifold is authored from: Longpoint is the hands' most
## forward carriage, the loads draw them toward the striking side and nearer
## the body — but inside the shoulder line, so the outside of the swing
## narrows rather than spreading the hands sideways (SLASH-SHAPE-001) — and
## past the load the hands hold while the blade winds on.
func test_the_shipped_manifold_carries_the_postures() -> void:
	var path := _shipped().handling.attack_path
	var longpoint := path.carriage_forward(0.0)
	for degrees in range(5, 136, 5):
		assert_true(path.carriage_forward(deg_to_rad(float(degrees))) < longpoint, "Longpoint is the most forward carriage (vs %d°)" % degrees)
	assert_near(path.carriage_left(0.0), 0.0, 1e-12, "Longpoint is on the centreline")
	## Wolf's shoulder joints sit ~0.18 m either side of the centreline.
	assert_true(path.carriage_left(deg_to_rad(-135.0)) < -0.1, "the right load draws the hands toward the right")
	assert_true(path.carriage_left(deg_to_rad(135.0)) > 0.1, "and the left load toward the left")
	for degrees in range(0, 136, 5):
		assert_true(absf(path.carriage_left(deg_to_rad(float(degrees)))) < 0.18, "but never out to the shoulder line (%d°)" % degrees)
	assert_true(path.carriage_forward(deg_to_rad(135.0)) > PhysicalBaseline.TORSO_HURT_RADIUS_M, "a load keeps the hands in front of the torso, never folded onto the shoulder")
	var held := path.carriage_left(deg_to_rad(150.0)) - path.carriage_left(deg_to_rad(135.0))
	assert_near(held, 0.0, 1e-12, "past the last posture the hands hold while the blade turns")


## WEAPON-PATH-002: the pose is single-valued in θ. The same weapon angle gives
## the same hilt and the same yaw however it was reached — charging, releasing,
## rebounding, recovering — so collision geometry (and therefore reversals and
## binds) is coherent. Presentation may differ; physics may not.
func test_the_pose_is_single_valued_in_theta() -> void:
	var spec := _shipped()
	var base_pose := BladePose.new()
	var other := BladePose.new()
	for degrees in range(-135, 136, 9):
		var angle := deg_to_rad(float(degrees))
		var charging := _fighter(0.4, -1.1, 0.9, angle)
		charging.weapon.phase = CombatPhase.Id.CHARGING
		charging.weapon.speed = -8.0
		charging.weapon.charge = 0.7
		charging.weapon.swing_dir = 1.0
		WeaponKinematics.pose_of(charging, spec, base_pose)
		for history: Array in [
			[CombatPhase.Id.ACTIVE_THREAT, 12.0, 1.0],
			[CombatPhase.Id.RECOVERY, -2.0, -1.0],
			[CombatPhase.Id.NEUTRAL, 0.0, 1.0],
		]:
			var fighter := _fighter(0.4, -1.1, 0.9, angle)
			fighter.weapon.phase = history[0]
			fighter.weapon.speed = history[1]
			fighter.weapon.swing_dir = history[2]
			WeaponKinematics.pose_of(fighter, spec, other)
			assert_eq(other.origin_x, base_pose.origin_x, "same θ, same hilt x at %d° (%s)" % [degrees, history[0]])
			assert_eq(other.origin_y, base_pose.origin_y, "same θ, same hilt y at %d°" % degrees)
			assert_eq(other.ux, base_pose.ux, "same θ, same yaw at %d°" % degrees)
			assert_eq(other.uy, base_pose.uy, "same θ, same yaw at %d°" % degrees)


## WEAPON-PATH-002: the manifold preserves θ's ordering and bounds. Increasing
## θ moves the yaw monotonically counter-clockwise across the whole range; the
## origin never leaves the fighter's front; yaw stays φ + θ.
func test_the_manifold_preserves_the_angle_ordering_and_bounds() -> void:
	var spec := _shipped()
	var pose := BladePose.new()
	var previous_yaw := -INF
	for degrees in range(-135, 136, 3):
		var angle := deg_to_rad(float(degrees))
		var fighter := _fighter(0.0, 0.0, 0.0, angle)
		WeaponKinematics.pose_of(fighter, spec, pose)
		var yaw := SimMath.arctan2(pose.uy, pose.ux)
		assert_true(yaw > previous_yaw, "yaw increases with θ at %d° (%.4f > %.4f)" % [degrees, yaw, previous_yaw])
		assert_near(SimMath.wrap_angle(yaw - angle), 0.0, 1e-9, "yaw is φ + θ at %d°" % degrees)
		## The hands (the carriage) stay in front of the body; the pommel may
		## sit a grip-length behind them at a deep load, which is correct.
		assert_true(spec.handling.attack_path.carriage_forward(angle) > 0.0, "the hands stay in front at %d° (forward %.3f)" % [degrees, spec.handling.attack_path.carriage_forward(angle)])
		previous_yaw = yaw


## The sweep budgets the carriage's own travel along a curved track, so a track
## that carries the hands sideways cannot tunnel between substeps.
func test_the_sweep_budgets_the_carriages_travel() -> void:
	var rules := DuelFixture.revolute_rules()
	var fixed := rules.combatant(0)
	var curved := _spec(true)
	var curved_rules := DuelFixture.revolute_rules()
	curved_rules.combatants = [curved, curved]
	## One tick's worth of swing (0.3 rad), well under the substep cap.
	var a := _fighter(0.0, 0.0, 0.0, -0.15)
	var b := _fighter(3.0, 0.0, PI, 0.0)
	var start: Array[FighterPose] = [FighterPose.capture(a, fixed), FighterPose.capture(b, fixed)]
	a.weapon.angle = 0.15
	var finish: Array[FighterPose] = [FighterPose.capture(a, fixed), FighterPose.capture(b, fixed)]
	var revolute := CollisionSystem.substep_count(start, finish, rules)
	assert_true(revolute < rules.combat.max_substeps, "fixture: the revolute sweep is under the cap (%d)" % revolute)
	a.weapon.angle = -0.15
	var start_curved: Array[FighterPose] = [FighterPose.capture(a, curved), FighterPose.capture(b, curved)]
	a.weapon.angle = 0.15
	var finish_curved: Array[FighterPose] = [FighterPose.capture(a, curved), FighterPose.capture(b, curved)]
	assert_true(CollisionSystem.substep_count(start_curved, finish_curved, curved_rules) > revolute, "a carriage that travels needs more substeps (%d)" % revolute)
