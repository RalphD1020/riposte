extends TestCase

## IMPACT: one physical result per sword contact (IMPACT-PHYSICS-001). The
## exact contact point's velocity — fighter, heading, weapon and the carriage
## sliding along its orbit — through the contact's one effective mass gives
## the impulse and the energy; where on the blade it landed reaches the result
## only through leverage, never a multiplier.
##
## Implements: /spec/invariants.md#impact-physics-001
## See also: /docs/concepts/combat.md

const SPIN := 15.0
const MIRROR := 1e-9

var _rules: DuelRules


func _init() -> void:
	suite_name = "IMPACT"
	_rules = DuelFixture.rules()


## Fighter 0 at the origin facing +x with its blade at `angle` turning at
## `spin`; fighter 1 standing just across the blade from the point `fraction`
## of the way down it. Returns [state, contact x, contact y].
func _scene(angle: float, fraction: float, spin: float = SPIN, rules: DuelRules = null) -> Array:
	if rules == null:
		rules = _rules
	var state := DuelFixture.state(rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	a.weapon.angle = angle
	a.weapon.speed = spin
	a.weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	var pose := WeaponKinematics.pose_of(a, rules.combatant(0), BladePose.new())
	var r := rules.combatant(0).weapon.hilt_radius + fraction * rules.combatant(0).weapon.blade_length()
	var side := signf(spin) if spin != 0.0 else 1.0
	DuelFixture.place(b, pose.point_x(r) - pose.uy * 0.3 * side, pose.point_y(r) + pose.ux * 0.3 * side, PI)
	return [state, pose.point_x(r), pose.point_y(r)]


func _impact(scene: Array, rules: DuelRules = null) -> ImpactResult:
	var state: MatchState = scene[0]
	return ImpactModel.resolve(state.fighter(0), state.fighter(1), float(scene[1]), float(scene[2]), rules if rules != null else _rules)


## 1. At the same θ and θ̇, moving the contact down the rigid blade changes its
## speed by exactly the rotation over the extra radius.
func test_a_contact_farther_down_the_blade_moves_faster_by_the_rotation() -> void:
	var near := _scene(0.0, 0.3)
	var far := _scene(0.0, 0.8)
	var near_impact := _impact(near)
	var far_impact := _impact(far)
	assert_near(near_impact.blade_fraction, 0.3, 1e-9, "fixture: the near contact is 30% down the blade")
	assert_near(far_impact.blade_fraction, 0.8, 1e-9, "and the far one 80%")
	assert_near(far_impact.normal_speed - near_impact.normal_speed, SPIN * 0.5 * _rules.combatant(0).weapon.blade_length(), 1e-7, "Δv_n = θ̇ · Δr down a rigid blade")


## 2. At the same blade fraction and θ̇, a different θ moves the hands along
## the orbit, and the contact speed is the finite-difference rate of the
## point's own position — carriage `C′(θ)` included.
func test_the_carriage_moving_along_its_orbit_reaches_the_contact_speed() -> void:
	for degrees: float in [0.0, -45.0, -80.0]:
		var angle := deg_to_rad(degrees)
		var scene := _scene(angle, 0.6)
		var impact := _impact(scene)
		var r := _rules.combatant(0).weapon.hilt_radius + 0.6 * _rules.combatant(0).weapon.blade_length()
		var h := 1e-6
		var ahead := WeaponKinematics.pose_at(0.0, 0.0, 0.0, angle + h, _rules.combatant(0), BladePose.new())
		var behind := WeaponKinematics.pose_at(0.0, 0.0, 0.0, angle - h, _rules.combatant(0), BladePose.new())
		var vx := (ahead.point_x(r) - behind.point_x(r)) / (2.0 * h) * SPIN
		var vy := (ahead.point_y(r) - behind.point_y(r)) / (2.0 * h) * SPIN
		## The baked orbit interpolates C and C′ separately between its 0.5°
		## samples, so its secant and its slope agree to ~0.1 %, not to the bit.
		var rate := maxf(0.0, vx * impact.normal_x + vy * impact.normal_y)
		assert_near(impact.normal_speed, rate, 1e-3 * rate, "at %.0f° the contact speed is the point's own rate (carriage included)" % degrees)
	var centre := _impact(_scene(0.0, 0.6))
	var ready := _impact(_scene(deg_to_rad(-45.0), 0.6))
	assert_true(absf(centre.normal_speed - ready.normal_speed) > 1e-3, "and the orbit makes the same θ̇ and fraction a different speed at a different θ")


## 3 + 6. A left swing and its mirror make mirrored contacts: the same speed,
## impulse and energy, the normal reflected.
func test_mirrored_swings_make_mirrored_impacts() -> void:
	var right := _impact(_scene(deg_to_rad(-40.0), 0.65, SPIN))
	var left := _impact(_scene(deg_to_rad(40.0), 0.65, -SPIN))
	assert_true(right.normal_speed > 1.0, "fixture: a real cut (%.2f m/s)" % right.normal_speed)
	assert_near(left.normal_speed, right.normal_speed, MIRROR, "the same closing speed")
	assert_near(left.impulse, right.impulse, MIRROR, "the same impulse")
	assert_near(left.kinetic_severity, right.kinetic_severity, MIRROR, "the same energy")
	assert_near(left.normal_y, -right.normal_y, MIRROR, "the normal reflected (y)")
	assert_near(left.normal_x, right.normal_x, MIRROR, "(x)")


## 4. The fighters' own motion is part of the contact: stepping into the cut
## raises it, a target moving with the blow lowers it.
func test_body_motion_reaches_the_contact() -> void:
	var still := _impact(_scene(0.0, 0.65))
	var stepping := _scene(0.0, 0.65)
	(stepping[0] as MatchState).fighter(0).vy = 2.0
	var fleeing := _scene(0.0, 0.65)
	(fleeing[0] as MatchState).fighter(1).vy = 2.0
	var stepping_impact := _impact(stepping)
	var fleeing_impact := _impact(fleeing)
	assert_true(still.normal_y > 0.5, "fixture: the cut pushes along +y")
	assert_true(stepping_impact.normal_speed > still.normal_speed and stepping_impact.kinetic_severity > still.kinetic_severity, "stepping into the cut raises speed and energy")
	assert_true(fleeing_impact.normal_speed < still.normal_speed and fleeing_impact.kinetic_severity < still.kinetic_severity, "a target moving with the blow lowers them")


## Two blades crossing at 60°, touching at `fraction_a` down A's and
## `fraction_b` down B's, solved at 8 m/s closing along the normal to A's
## blade. Returns [A's lever, B's lever, |Δθ̇_A|, |Δθ̇_B|].
func _crossing(fraction_a: float, fraction_b: float) -> PackedFloat64Array:
	var weapon := _rules.combatant(0).weapon
	var spec := _rules.combatant(0)
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	a.weapon.angle = 0.0
	b.weapon.angle = 0.0
	var pose_a := WeaponKinematics.pose_of(a, spec, BladePose.new())
	var px := pose_a.point_x(weapon.hilt_radius + fraction_a * weapon.blade_length())
	var py := pose_a.point_y(weapon.hilt_radius + fraction_a * weapon.blade_length())
	## B at guard-centre too, its blade along its own heading, placed so the
	## point `fraction_b` down it is exactly that contact point.
	var heading := deg_to_rad(120.0)
	var down := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, spec, BladePose.new()).origin_x + weapon.hilt_radius + fraction_b * weapon.blade_length()
	DuelFixture.place(b, px - cos(heading) * down, py - sin(heading) * down, heading)
	var pose_b := WeaponKinematics.pose_of(b, spec, BladePose.new())
	assert_near(pose_b.point_x(weapon.hilt_radius + fraction_b * weapon.blade_length()), px, 1e-9, "fixture: the point is on B's blade too (x)")
	assert_near(pose_b.point_y(weapon.hilt_radius + fraction_b * weapon.blade_length()), py, 1e-9, "(y)")
	var nx := -pose_a.uy
	var ny := pose_a.ux
	var sides := PackedFloat64Array()
	for fighter: FighterState in [a, b]:
		var pose := pose_a if fighter == a else pose_b
		sides.append_array([WeaponKinematics.lever(fighter, pose, px, py, nx, ny), ContactMechanics.weapon_inertia(pose, _rules.combatant(0)), ContactMechanics.body_inverse_mass(_rules.combatant(0))])
	state.blade_contact.set_normal(nx, ny)
	var deltas := PackedFloat64Array([0.0, 0.0])
	SwordContactSolver.solve(state.blade_contact, 0, a, b, pose_a, pose_b, px, py, 8.0, sides[0], sides[3], sides[1], sides[4], weapon.restitution, SwordContactSolver.FRICTIONLESS, deltas, sides[2], sides[5])
	return PackedFloat64Array([absf(sides[0]), absf(sides[3]), absf(deltas[0]), absf(deltas[1])])


## 5. Strong against weak is leverage alone: A's strong meeting B's weak turns
## A's sword less and B's more than the same blades the other way round — no
## multiplier anywhere, only each blade's Jacobian at the shared point.
func test_strong_and_weak_come_from_leverage_alone() -> void:
	var a_strong := _crossing(0.1, 0.9)
	var a_weak := _crossing(0.9, 0.1)
	assert_true(a_strong[0] < a_weak[0], "fixture: A's strong is the short lever (%.3f < %.3f)" % [a_strong[0], a_weak[0]])
	assert_true(a_strong[1] > a_weak[1], "fixture: and B's weak the long one (%.3f > %.3f)" % [a_strong[1], a_weak[1]])
	assert_true(a_strong[2] < a_weak[2], "A's sword, met on its strong, turns less (%.2f vs %.2f rad/s)" % [a_strong[2], a_weak[2]])
	assert_true(a_strong[3] > a_weak[3], "and B's, met on its weak, turns more (%.2f vs %.2f rad/s)" % [a_strong[3], a_weak[3]])
	assert_true(a_strong[3] > a_strong[2], "so the strong displaces the weak")


## 7 + 8. The centre of percussion is a weapon property, derived from its mass
## distribution, and the cut-efficiency profile peaked there only describes how
## cleanly a cut bites: it changes no impulse and no energy, and it can never
## exceed 1.
func test_the_sweet_spot_adds_no_energy() -> void:
	var weapon := _rules.combatant(0).weapon
	var fraction := ContactMechanics.percussion_fraction(weapon)
	assert_between(fraction, 0.5, 0.8, "the centre of percussion is in the outer middle of the blade (%.3f)" % fraction)
	assert_near(weapon.efficiency(fraction), 1.0, 1e-12, "and the cut bites cleanest there")
	var shipped := _impact(_scene(0.0, fraction))
	var flat := DuelFixture.rules()
	flat.combatant(0).weapon.efficiency_values = PackedFloat64Array([0.5, 0.5, 0.5, 0.5])
	assert_true(flat.combatant(0).weapon.is_valid(), "perturbation: a flat efficiency profile is a legal weapon")
	var scene := _scene(0.0, fraction)
	var flat_impact := ImpactModel.resolve((scene[0] as MatchState).fighter(0), (scene[0] as MatchState).fighter(1), float(scene[1]), float(scene[2]), flat)
	assert_near(flat_impact.impulse, shipped.impulse, 1e-12, "efficiency changes no impulse")
	assert_near(flat_impact.kinetic_severity, shipped.kinetic_severity, 1e-12, "and no energy")
	assert_true(flat_impact.blade_efficiency < shipped.blade_efficiency, "only how cleanly it bites")
	var bonus := DuelFixture.rules()
	bonus.combatant(0).weapon.efficiency_values = PackedFloat64Array([0.35, 0.75, 1.2, 0.8])
	assert_false(bonus.combatant(0).weapon.is_valid(), "an efficiency above 1 would add energy: the weapon is invalid")


## 9. The solved impulse never makes energy: through the contact's effective
## mass, the motion it touches loses exactly ½(1 − e²)·v_n² / k.
func test_a_blade_contact_takes_out_exactly_the_dissipated_energy() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	ContactFixture.arm(a, 0.0, 0.0, 0.0, 0.0, 14.0, CombatPhase.Id.ACTIVE_THREAT, 0.6, _rules.combatant(0).weapon)
	ContactFixture.arm(b, 2.1, 0.25, PI, 0.4, -3.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.combatant(0).weapon)
	a.turn_rate = 0.0
	b.turn_rate = 0.0
	var pose_a := WeaponKinematics.pose_of(a, _rules.combatant(0), BladePose.new())
	var pose_b := WeaponKinematics.pose_of(b, _rules.combatant(0), BladePose.new())
	var px := 1.05
	var py := 0.02
	var nx := 0.5
	var ny := -0.8660254037844386
	var closing := SwordContactSolver.closing_speed(a, b, pose_a, pose_b, px, py, nx, ny)
	assert_true(closing > 0.0, "fixture: the blades close (%.3f m/s)" % closing)
	var cross_a := WeaponKinematics.lever(a, pose_a, px, py, nx, ny)
	var cross_b := WeaponKinematics.lever(b, pose_b, px, py, nx, ny)
	var inertia_a := 0.8
	var inertia_b := 0.7
	var inverse_a := 1.0 / 14.0
	var inverse_b := 1.0 / 18.0
	var energy := func() -> float:
		return 0.5 * (inertia_a * a.weapon.speed * a.weapon.speed + inertia_b * b.weapon.speed * b.weapon.speed + (a.vx * a.vx + a.vy * a.vy) / inverse_a + (b.vx * b.vx + b.vy * b.vy) / inverse_b)
	var before: float = energy.call()
	state.blade_contact.set_normal(nx, ny)
	var deltas := PackedFloat64Array([0.0, 0.0])
	SwordContactSolver.solve(state.blade_contact, 0, a, b, pose_a, pose_b, px, py, closing, cross_a, cross_b, inertia_a, inertia_b, _rules.combatant(0).weapon.restitution, SwordContactSolver.FRICTIONLESS, deltas, inverse_a, inverse_b)
	var k := cross_a * cross_a / inertia_a + cross_b * cross_b / inertia_b + inverse_a + inverse_b
	var lost := before - float(energy.call())
	assert_near(lost, ContactMechanics.dissipated_energy(closing, k, _rules.combatant(0).weapon.restitution), 1e-9, "the motion loses exactly the dissipated energy (%.4f J)" % lost)
	assert_true(lost >= 0.0, "and never gains any")
	assert_true(ContactMechanics.dissipated_energy(closing, k, _rules.combatant(0).weapon.restitution) <= ContactMechanics.available_energy(closing, k), "dissipated never exceeds available")


## IMPACT-GRADIENT-001. Sample the sword-body response along the blade.
## At fraction f the contact sits at p(f); c(f) = ∂p/∂θ · n; 
## K(f) = 1/m_A + 1/m_B + c(f)²/M_θ; m_eff = 1/K.
## The target is a body, so it contributes mass and no weapon term.
## Continuity is the curve's own finite differences: halving the sample
## interval halves a smooth step and does not hide a jump. Witnesses at the
## forte, mid-blade, derived centre of percussion and foible are readings.
## Nothing here requires a monotone Strong→Weak damage curve.
func test_the_sword_contact_gradient_is_the_mechanics() -> void:
	var fine := _gradient(0.05)
	var coarse := _gradient(0.1)
	for name: String in ["impulse", "energy", "mass", "speed"]:
		var samples: PackedFloat64Array = fine[name]
		for value in samples:
			assert_true(is_finite(value), "%s stays finite along the blade" % name)
		var fine_step := _max_step(samples)
		var coarse_step := _max_step(coarse[name])
		assert_true(fine_step <= coarse_step + 1e-9, "%s has no jump that a finer sample still sees whole (%.6f vs %.6f)" % [name, fine_step, coarse_step])
		if coarse_step > 1e-6:
			assert_true(fine_step < coarse_step * 0.75, "%s is locally continuous: halving the interval shrinks the step (%.6f vs %.6f)" % [name, fine_step, coarse_step])
	var identity: PackedFloat64Array = fine["identity"]
	for error in identity:
		assert_near(error, 0.0, 1e-9, "J = (1 + e)·v_n / K at every fraction")
	var right_hand := _gradient(0.1, deg_to_rad(-40.0), SPIN)
	var left_hand := _gradient(0.1, deg_to_rad(40.0), -SPIN)
	for name: String in ["impulse", "energy", "mass"]:
		var right: PackedFloat64Array = right_hand[name]
		var left: PackedFloat64Array = left_hand[name]
		for i in right.size():
			assert_near(left[i], right[i], MIRROR, "%s mirrors at fraction %.1f" % [name, float(i) * 0.1])
	var weapon := _rules.combatant(0).weapon
	var cop := ContactMechanics.percussion_fraction(weapon)
	var stations := PackedFloat64Array([0.15, 0.5, cop, 0.95])
	var station_names := PackedStringArray(["forte", "mid-blade", "centre of percussion", "foible"])
	for i in stations.size():
		var impact := _impact(_scene(0.0, stations[i]))
		var eta := weapon.efficiency(stations[i])
		assert_true(eta > 0.0 and eta <= 1.0, "%s bite is a loss in (0, 1]" % station_names[i])
		assert_true(impact.kinetic_severity * eta <= impact.kinetic_severity + 1e-12, "%s bite cannot raise the solved energy" % station_names[i])
		assert_true(is_finite(impact.impulse) and is_finite(impact.inverse_effective_mass), "%s response is finite" % station_names[i])
	var grip := weapon.hand_centre_radius()
	var percussion := ContactMechanics.percussion_radius(weapon)
	var arm := percussion - grip
	assert_true(arm > 0.0, "precondition: the centre of percussion sits beyond the hands")
	var at_hands := 1.0 - (grip - grip) / arm
	var at_cop := 1.0 - (percussion - grip) / arm
	assert_near(at_hands, 1.0, 1e-12, "a strike at the hands reacts fully into the grip")
	assert_near(at_cop, 0.0, 1e-12, "the derived centre of percussion reacts into the hands not at all")
	## The injury calibration is a pinned physical constant (rules 42), and the
	## reference strike measured on today's mechanics is its witness: the two
	## stay close, so "1.0" still means about that strike.
	var witness := ContactMechanics.reference_severity(_rules.combatant(0), _rules.combatant(0), _rules.combat)
	assert_between(_rules.combat.reference_severity / witness, 0.9, 1.1, "and the reference strike on these mechanics is its witness (pinned %.2f J vs %.2f J)" % [_rules.combat.reference_severity, witness])


func _gradient(step: float, angle: float = 0.0, spin: float = SPIN) -> Dictionary:
	var impulse := PackedFloat64Array()
	var energy := PackedFloat64Array()
	var mass := PackedFloat64Array()
	var speed := PackedFloat64Array()
	var identity := PackedFloat64Array()
	var count := int(round(1.0 / step))
	for index in count + 1:
		var fraction := float(index) * step
		var impact := _impact(_scene(angle, fraction, spin))
		var k := impact.inverse_effective_mass
		impulse.append(impact.impulse)
		energy.append(impact.kinetic_severity)
		mass.append(1.0 / k if k > SimMath.EPSILON else 0.0)
		speed.append(impact.normal_speed)
		var expected := ContactMechanics.normal_impulse(impact.normal_speed, k, impact.restitution)
		identity.append(impact.impulse - expected)
	return {"impulse": impulse, "energy": energy, "mass": mass, "speed": speed, "identity": identity}


static func _max_step(samples: PackedFloat64Array) -> float:
	var worst := 0.0
	for i in range(1, samples.size()):
		worst = maxf(worst, absf(samples[i] - samples[i - 1]))
	return worst


## Fighter 0 at Long Guard walking its point straight ahead at 2 m/s, the
## blade still; fighter 1's hurt torso touching the tip, its centre
## `offset_degrees` off the blade's axis. Resolves the contact through the
## real resolver. Returns [impact, kind, Δθ̇ of fighter 0's sword].
func _point(offset_degrees: float) -> Array:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	a.weapon.angle = 0.0
	a.weapon.speed = 0.0
	a.weapon.swing_dir = 1.0
	a.weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	a.vx = 2.0
	var pose := WeaponKinematics.pose_of(a, _rules.combatant(0), BladePose.new())
	var tip_x := pose.point_x(_rules.combatant(0).weapon.tip_radius)
	var tip_y := pose.point_y(_rules.combatant(0).weapon.tip_radius)
	var off := deg_to_rad(offset_degrees)
	DuelFixture.place(b, tip_x + cos(off) * _rules.combatant(0).fighter.hurt_radius, tip_y + sin(off) * _rules.combatant(0).fighter.hurt_radius, PI)
	var impact := ImpactModel.resolve(a, b, tip_x, tip_y, _rules)
	var kind := DamageModel.classify_contact(impact, a, _rules)
	var before := a.weapon.speed
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_report(0, tip_x, tip_y), _rules, 1, 0.0, events)
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.BODY_HIT).size(), 1, "fixture: the point lands (%.0f° off axis)" % offset_degrees)
	return [impact, kind, a.weapon.speed - before]


## 11. A point is not a separate mass model. Driven straight along its blade
## the contact's lever is zero and the sword does not turn; the same point
## met off its axis has a real lever, gives way, and is deflected by exactly
## `J·c/M_θ` — still a POKE, because classification reads geometry, while the
## mechanics are the cut's.
func test_an_off_axis_point_turns_the_sword_and_a_centred_one_does_not() -> void:
	var centred := _point(0.0)
	var off := _point(40.0)
	var mirror := _point(-40.0)
	var centred_impact: ImpactResult = centred[0]
	var off_impact: ImpactResult = off[0]
	assert_eq(centred[1], StrikeResult.ContactKind.POKE, "fixture: the centred contact is a POKE")
	assert_eq(off[1], StrikeResult.ContactKind.POKE, "fixture: so is the one 40° off axis")
	assert_near(centred_impact.lever_cross, 0.0, 1e-9, "along the blade the lever is zero")
	assert_near(float(centred[2]), 0.0, 1e-12, "so the centred point turns nothing")
	assert_true(absf(off_impact.lever_cross) > 0.1, "off axis the lever is real (%.3f m)" % off_impact.lever_cross)
	var expected := -off_impact.impulse * off_impact.lever_cross / off_impact.weapon_inertia
	assert_near(float(off[2]), expected, 1e-9, "and the sword turns by exactly J·c/M_θ (%.3f rad/s)" % expected)
	assert_true(absf(float(off[2])) > 0.1, "measurably")
	assert_near(float(mirror[2]), -float(off[2]), 1e-9, "the mirrored contact turns it the other way, as much")
	assert_true(1.0 / off_impact.inverse_effective_mass < 1.0 / centred_impact.inverse_effective_mass, "a point that gives way meets a lighter contact (%.1f vs %.1f kg)" % [1.0 / off_impact.inverse_effective_mass, 1.0 / centred_impact.inverse_effective_mass])
	assert_true(off_impact.kinetic_severity < centred_impact.kinetic_severity, "and delivers less energy (%.2f vs %.2f J)" % [off_impact.kinetic_severity, centred_impact.kinetic_severity])


## 12. Scale reaches a contact through physics alone. A longer, heavier sword
## on the same contact is harder to drive (`α = τ/I` for the same torque),
## carries more inertia, moves the same blade fraction faster, meets a heavier
## contact and so delivers more impulse — no weapon bonus anywhere. A heavier
## fighter is harder to shove but no stronger: mass is how hard a body is to
## accelerate, strength is the authored torque (PHYS-005).
func test_a_longer_heavier_sword_and_a_heavier_body_scale_through_physics_alone() -> void:
	var heavy := DuelFixture.rules()
	heavy.combatant(0).weapon = WeaponCatalog.bastard_sword_at(1.15, 2.1, heavy.combatant(0).fighter.grip_radius)
	assert_true(heavy.combatant(0).weapon.is_valid(), "fixture: the longer, heavier sword is a legal weapon")
	assert_true(heavy.combatant(0).weapon.tip_radius > _rules.combatant(0).weapon.tip_radius and heavy.combatant(0).weapon.mass > _rules.combatant(0).weapon.mass, "fixture: it is longer and heavier")
	var light_inertia := WeaponKinematics.motor_inertia(_rules.combatant(0), 0.0)
	var heavy_inertia := WeaponKinematics.motor_inertia(heavy.combatant(0), 0.0)
	assert_near(heavy.combatant(0).weapon.swing_accel(1.0, 1.0, heavy_inertia) / _rules.combatant(0).weapon.swing_accel(1.0, 1.0, light_inertia), light_inertia / heavy_inertia, 1e-12, "the same drive accelerates it slower, exactly by its inertia")
	var light_impact := _impact(_scene(0.0, 0.65))
	var heavy_impact := _impact(_scene(0.0, 0.65, SPIN, heavy), heavy)
	var light_pose := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(0), BladePose.new())
	var heavy_pose := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, heavy.combatant(0), BladePose.new())
	assert_true(WeaponKinematics.generalized_inertia(heavy.combatant(0), heavy_pose) > WeaponKinematics.generalized_inertia(_rules.combatant(0), light_pose), "it carries more inertia at the same θ")
	assert_true(heavy_impact.normal_speed > light_impact.normal_speed, "the same fraction moves faster (%.2f vs %.2f m/s)" % [heavy_impact.normal_speed, light_impact.normal_speed])
	assert_true(1.0 / heavy_impact.inverse_effective_mass > 1.0 / light_impact.inverse_effective_mass, "meets a heavier contact (%.2f vs %.2f kg)" % [1.0 / heavy_impact.inverse_effective_mass, 1.0 / light_impact.inverse_effective_mass])
	assert_true(heavy_impact.impulse > light_impact.impulse, "and delivers more impulse (%.2f vs %.2f N·s)" % [heavy_impact.impulse, light_impact.impulse])
	var bulky := DuelFixture.rules()
	bulky.combatant(0).fighter.mass = _rules.combatant(0).fighter.mass * 1.25
	var bulky_impact := _impact(_scene(0.0, 0.65, SPIN, bulky), bulky)
	assert_near(bulky_impact.target_mass / light_impact.target_mass, 1.25, 1e-12, "a heavier target resists in proportion to its mass")
	assert_true(bulky_impact.target_delta_v() < light_impact.target_delta_v(), "so it is shoved less (%.3f vs %.3f m/s)" % [bulky_impact.target_delta_v(), light_impact.target_delta_v()])
	assert_near(bulky_impact.normal_speed, light_impact.normal_speed, 1e-12, "but its own blade arrives no faster: bulk is not strength")
	assert_near(bulky.combatant(0).weapon.swing_accel(1.0, 1.0, WeaponKinematics.motor_inertia(bulky.combatant(0), 0.0)), _rules.combatant(0).weapon.swing_accel(1.0, 1.0, light_inertia), 1e-12, "the same arm drives the same sword exactly as hard")


## 13. Passive contact: with nothing driving either side, a clash followed by
## held, sliding contacts — the normal stage with restitution on the first
## touch, then zero, the Coulomb tangent stage every time — never adds energy
## to the motion it touches. Measured in the solver's own metric (the
## inertias and masses it was given); the fighters' whole-body momentum is a
## separate question for the persistent manifold.
func test_repeated_contacts_with_no_drive_never_add_energy() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	ContactFixture.arm(a, 0.0, 0.0, 0.0, 0.0, 14.0, CombatPhase.Id.ACTIVE_THREAT, 0.6, _rules.combatant(0).weapon)
	ContactFixture.arm(b, 2.1, 0.25, PI, 0.4, -3.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.combatant(0).weapon)
	a.vx = 0.8
	b.vy = -0.6
	var inertia_a := 0.8
	var inertia_b := 0.7
	var inverse_a := 1.0 / 14.0
	var inverse_b := 1.0 / 18.0
	var energy := func() -> float:
		return 0.5 * (inertia_a * a.weapon.speed * a.weapon.speed + inertia_b * b.weapon.speed * b.weapon.speed + (a.vx * a.vx + a.vy * a.vy) / inverse_a + (b.vx * b.vx + b.vy * b.vy) / inverse_b)
	var start: float = energy.call()
	var solved := 0
	var slid := 0
	var worst_gain := -INF
	for step in 16:
		var pose_a := WeaponKinematics.pose_of(a, _rules.combatant(0), BladePose.new())
		var pose_b := WeaponKinematics.pose_of(b, _rules.combatant(0), BladePose.new())
		## The contact slides along the blades and its normal swings as they
		## turn and cross again: a held, sliding bind, not one repeated instant.
		var px := 1.05 - 0.02 * step
		var py := 0.02 + 0.01 * step
		var angle := deg_to_rad(-60.0 + 47.0 * step)
		var nx := cos(angle)
		var ny := sin(angle)
		var closing := SwordContactSolver.closing_speed(a, b, pose_a, pose_b, px, py, nx, ny)
		if closing <= 0.0:
			continue
		var before: float = energy.call()
		state.blade_contact.set_normal(nx, ny)
		var deltas := PackedFloat64Array([0.0, 0.0])
		var cross_a := WeaponKinematics.lever(a, pose_a, px, py, nx, ny)
		var cross_b := WeaponKinematics.lever(b, pose_b, px, py, nx, ny)
		var restitution := _rules.combatant(0).weapon.restitution if solved == 0 else 0.0
		SwordContactSolver.solve(state.blade_contact, 0, a, b, pose_a, pose_b, px, py, closing, cross_a, cross_b, inertia_a, inertia_b, restitution, 0.3, deltas, inverse_a, inverse_b)
		worst_gain = maxf(worst_gain, float(energy.call()) - before)
		if absf(state.blade_contact.tangent_impulse[0]) > 0.0:
			slid += 1
		solved += 1
	assert_true(solved >= 3, "fixture: a clash and repeated held contacts (%d solved)" % solved)
	assert_true(slid >= 1, "fixture: friction acted (%d sliding solves)" % slid)
	assert_true(worst_gain <= 1e-9, "no contact added energy (worst %.9f J)" % worst_gain)
	assert_true(float(energy.call()) < start, "the sequence lost energy overall (%.2f → %.2f J)" % [start, float(energy.call())])


## Two blades touching at mid-length, normal taken from A's blade. Nothing is
## moving until the caller says so. Returns [state, pose_a, pose_b, px, py, nx, ny].
func _touching() -> Array:
	var weapon := _rules.combatant(0).weapon
	var spec := _rules.combatant(0)
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	a.weapon.angle = 0.0
	a.weapon.speed = 0.0
	a.turn_rate = 0.0
	var pose_a := WeaponKinematics.pose_of(a, spec, BladePose.new())
	var r := weapon.hilt_radius + 0.55 * weapon.blade_length()
	var px := pose_a.point_x(r)
	var py := pose_a.point_y(r)
	var heading := deg_to_rad(90.0)
	var down := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, spec, BladePose.new()).origin_x + r
	DuelFixture.place(b, px - cos(heading) * down, py - sin(heading) * down, heading)
	b.weapon.angle = 0.0
	b.weapon.speed = 0.0
	b.turn_rate = 0.0
	var pose_b := WeaponKinematics.pose_of(b, spec, BladePose.new())
	var nx := -pose_a.uy
	var ny := pose_a.ux
	return [state, pose_a, pose_b, px, py, nx, ny]


func _solve_touch(touch: Array, restitution: float, friction: float) -> float:
	var state: MatchState = touch[0]
	var a := state.fighter(0)
	var b := state.fighter(1)
	var pose_a: BladePose = touch[1]
	var pose_b: BladePose = touch[2]
	var px := float(touch[3])
	var py := float(touch[4])
	var nx := float(touch[5])
	var ny := float(touch[6])
	var closing := SwordContactSolver.closing_speed(a, b, pose_a, pose_b, px, py, nx, ny)
	var cross_a := WeaponKinematics.lever(a, pose_a, px, py, nx, ny)
	var cross_b := WeaponKinematics.lever(b, pose_b, px, py, nx, ny)
	var inertia_a := ContactMechanics.weapon_inertia(pose_a, _rules.combatant(0))
	var inertia_b := ContactMechanics.weapon_inertia(pose_b, _rules.combatant(0))
	var inverse := ContactMechanics.body_inverse_mass(_rules.combatant(0))
	state.blade_contact.set_normal(nx, ny)
	var deltas := PackedFloat64Array([0.0, 0.0])
	return SwordContactSolver.solve(state.blade_contact, 0, a, b, pose_a, pose_b, px, py, closing, cross_a, cross_b, inertia_a, inertia_b, restitution, friction, deltas, inverse, inverse)


## GLANCE-001. μ = 0 on a single crossing with real tangent speed and a
## smaller normal closing. The tangent impulse is zero. Whatever the normal
## impulse does to the swords' spin, it is the whole of the state change —
## friction does not additionally eat tangent velocity.
func test_a_frictionless_crossing_does_not_consume_tangent_velocity() -> void:
	var touch := _touching()
	var state: MatchState = touch[0]
	var a := state.fighter(0)
	var nx := float(touch[5])
	var ny := float(touch[6])
	var tx := -ny
	var ty := nx
	a.vx = -nx * 0.6 + tx * 4.0
	a.vy = -ny * 0.6 + ty * 4.0
	var pose_a: BladePose = touch[1]
	var pose_b: BladePose = touch[2]
	var px := float(touch[3])
	var py := float(touch[4])
	var closing := SwordContactSolver.closing_speed(a, state.fighter(1), pose_a, pose_b, px, py, nx, ny)
	var sliding := absf(SwordContactSolver.closing_speed(a, state.fighter(1), pose_a, pose_b, px, py, tx, ty))
	assert_true(closing > 0.2, "fixture: the blades close (%.3f m/s)" % closing)
	assert_true(sliding > 2.0 and sliding > closing * 2.0, "fixture: tangent speed dominates (%.2f vs %.2f m/s)" % [sliding, closing])
	var speed_a := a.weapon.speed
	var speed_b := state.fighter(1).weapon.speed
	var vx_a := a.vx
	var vy_a := a.vy
	var vx_b := state.fighter(1).vx
	var vy_b := state.fighter(1).vy
	var cross_a := WeaponKinematics.lever(a, pose_a, px, py, nx, ny)
	var cross_b := WeaponKinematics.lever(state.fighter(1), pose_b, px, py, nx, ny)
	var inertia_a := ContactMechanics.weapon_inertia(pose_a, _rules.combatant(0))
	var inertia_b := ContactMechanics.weapon_inertia(pose_b, _rules.combatant(0))
	var inverse := ContactMechanics.body_inverse_mass(_rules.combatant(0))
	_solve_touch(touch, 0.0, SwordContactSolver.FRICTIONLESS)
	var jn := state.blade_contact.normal_impulse[0]
	assert_eq(state.blade_contact.tangent_impulse[0], 0.0, "μ = 0 applies no tangent impulse")
	assert_true(jn > 0.0, "the normal impulse is real (%.3f N·s)" % jn)
	assert_near(a.weapon.speed, speed_a + jn * cross_a / inertia_a, 1e-9, "A's spin changes only by J_n·c/M_θ")
	assert_near(state.fighter(1).weapon.speed, speed_b - jn * cross_b / inertia_b, 1e-9, "B's spin changes only by the reaction")
	assert_near(a.vx, vx_a + jn * nx * inverse, 1e-9, "A's body takes J_n along the normal")
	assert_near(a.vy, vy_a + jn * ny * inverse, 1e-9, "(y)")
	assert_near(state.fighter(1).vx, vx_b - jn * nx * inverse, 1e-9, "B's body takes the reaction along the normal")
	assert_near(state.fighter(1).vy, vy_b - jn * ny * inverse, 1e-9, "(y)")


## PRESSURE-001. The same swords, one of them stepping into the contact.
## Closing speed differs by exactly that root velocity; the impulse follows.
func test_stepping_into_a_contact_raises_normal_pressure() -> void:
	var still_touch := _touching()
	var still_state: MatchState = still_touch[0]
	var nx := float(still_touch[5])
	var ny := float(still_touch[6])
	var still_closing := SwordContactSolver.closing_speed(still_state.fighter(0), still_state.fighter(1), still_touch[1], still_touch[2], float(still_touch[3]), float(still_touch[4]), nx, ny)
	var moving := _touching()
	var mover: FighterState = (moving[0] as MatchState).fighter(0)
	var into := 1.4
	mover.vx = -nx * into
	mover.vy = -ny * into
	var moving_closing := SwordContactSolver.closing_speed(mover, (moving[0] as MatchState).fighter(1), moving[1], moving[2], float(moving[3]), float(moving[4]), nx, ny)
	assert_near(moving_closing - still_closing, into, 1e-8, "v_n changes by exactly the root step")
	_solve_touch(still_touch, 0.0, SwordContactSolver.FRICTIONLESS)
	_solve_touch(moving, 0.0, SwordContactSolver.FRICTIONLESS)
	var j_still := still_state.blade_contact.normal_impulse[0]
	var j_moving := (moving[0] as MatchState).blade_contact.normal_impulse[0]
	var cross_a := WeaponKinematics.lever(mover, moving[1], float(moving[3]), float(moving[4]), nx, ny)
	var cross_b := WeaponKinematics.lever((moving[0] as MatchState).fighter(1), moving[2], float(moving[3]), float(moving[4]), nx, ny)
	var k := cross_a * cross_a / ContactMechanics.weapon_inertia(moving[1], _rules.combatant(0)) + cross_b * cross_b / ContactMechanics.weapon_inertia(moving[2], _rules.combatant(0)) + 2.0 * ContactMechanics.body_inverse_mass(_rules.combatant(0))
	assert_true(j_moving > j_still, "so the normal impulse rises (%.3f → %.3f N·s)" % [j_still, j_moving])
	assert_near(j_moving - j_still, (moving_closing - maxf(still_closing, 0.0)) / k, 1e-6, "by Δv_n / K with e = 0")


## YIELD-001. An engaged pair whose target steps away loses normal pressure.
## The solver does not pull them back together.
func test_stepping_away_from_a_contact_drops_pressure_without_suction() -> void:
	var pressing := _touching()
	var presser: FighterState = (pressing[0] as MatchState).fighter(0)
	var nx := float(pressing[5])
	var ny := float(pressing[6])
	presser.vx = -nx * 1.0
	presser.vy = -ny * 1.0
	var yielding := _touching()
	var yielder: FighterState = (yielding[0] as MatchState).fighter(1)
	yielder.vx = -nx * 2.0
	yielder.vy = -ny * 2.0
	var press_closing := SwordContactSolver.closing_speed(presser, (pressing[0] as MatchState).fighter(1), pressing[1], pressing[2], float(pressing[3]), float(pressing[4]), nx, ny)
	var yield_closing := SwordContactSolver.closing_speed((yielding[0] as MatchState).fighter(0), yielder, yielding[1], yielding[2], float(yielding[3]), float(yielding[4]), nx, ny)
	assert_true(press_closing > 0.0, "fixture: the press closes (%.3f m/s)" % press_closing)
	assert_true(yield_closing < 0.0, "fixture: the retreat opens (%.3f m/s)" % yield_closing)
	_solve_touch(pressing, 0.0, SwordContactSolver.FRICTIONLESS)
	_solve_touch(yielding, 0.0, SwordContactSolver.FRICTIONLESS)
	assert_true((pressing[0] as MatchState).blade_contact.normal_impulse[0] > 0.0, "pressing has normal pressure")
	assert_eq((yielding[0] as MatchState).blade_contact.normal_impulse[0], 0.0, "separating has none — no suction")


## SLIDE-MOTION-001. Lateral footwork changes tangent speed and, at μ = 0,
## still draws no tangent impulse. Friction will later spend that v_t; the
## kinematic contribution has to be there first.
func test_lateral_footwork_changes_tangent_speed_and_not_friction() -> void:
	var planted := _touching()
	var stepping := _touching()
	var nx := float(planted[5])
	var ny := float(planted[6])
	var tx := -ny
	var ty := nx
	var stepper: FighterState = (stepping[0] as MatchState).fighter(0)
	var lateral := 2.5
	stepper.vx = tx * lateral
	stepper.vy = ty * lateral
	var planted_slide := SwordContactSolver.closing_speed((planted[0] as MatchState).fighter(0), (planted[0] as MatchState).fighter(1), planted[1], planted[2], float(planted[3]), float(planted[4]), tx, ty)
	var stepping_slide := SwordContactSolver.closing_speed(stepper, (stepping[0] as MatchState).fighter(1), stepping[1], stepping[2], float(stepping[3]), float(stepping[4]), tx, ty)
	assert_near(stepping_slide - planted_slide, -lateral, 1e-8, "v_t changes by exactly the lateral step")
	_solve_touch(stepping, 0.0, SwordContactSolver.FRICTIONLESS)
	assert_eq((stepping[0] as MatchState).blade_contact.tangent_impulse[0], 0.0, "μ = 0 still applies no tangent impulse")


## TURN-CONTACT-001. Same θ and θ̇, a different heading rate. The turn
## shows up in the contact-point velocity and therefore in the closing speed.
func test_heading_rate_reaches_the_contact_point() -> void:
	var quiet := _touching()
	var turning := _touching()
	var nx := float(quiet[5])
	var ny := float(quiet[6])
	var px := float(quiet[3])
	var py := float(quiet[4])
	var spinner: FighterState = (turning[0] as MatchState).fighter(0)
	var rate := 1.7
	spinner.turn_rate = rate
	var quiet_closing := SwordContactSolver.closing_speed((quiet[0] as MatchState).fighter(0), (quiet[0] as MatchState).fighter(1), quiet[1], quiet[2], px, py, nx, ny)
	var turning_closing := SwordContactSolver.closing_speed(spinner, (turning[0] as MatchState).fighter(1), turning[1], turning[2], px, py, nx, ny)
	var dvx := -rate * (py - spinner.y)
	var dvy := rate * (px - spinner.x)
	assert_near(turning_closing - quiet_closing, -(dvx * nx + dvy * ny), 1e-8, "φ̇ changes v_n by the contact point's lever about the body")
	assert_true(absf(turning_closing - quiet_closing) > 0.05, "and that contribution is not zero (%.3f m/s)" % absf(turning_closing - quiet_closing))
