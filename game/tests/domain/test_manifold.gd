extends TestCase

## MANIFOLD: the sword contact manifold and its solver (CONTACT-MANIFOLD-001,
## BLADE-FRICTION-001). The foundation reproduces the shipped normal response
## exactly before anything new is switched on: one point, one iteration and no
## friction is the old one-shot impulse, bit for bit.
##
## Implements: /spec/invariants.md#combat-002
## Implements: /spec/invariants.md#combat-003
## See also: /docs/concepts/combat.md

## Normal from blade 1 toward blade 0 at 30° off the y axis; tangent = perp(n).
const NX := 0.5
const NY := -0.8660254037844386
const PX := 1.05
const PY := 0.02

var _rules: DuelRules
var _revolute: DuelRules


func _init() -> void:
	suite_name = "MANIFOLD"
	_rules = DuelFixture.rules()
	_revolute = DuelFixture.revolute_rules()


## A charged cut (fighter 0) meeting a guard (fighter 1) on the shipped
## manifold, with a crossing normal so both the normal and the tangent have a
## lever on each weapon.
func _crossing_scene() -> MatchState:
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 14.0, CombatPhase.Id.ACTIVE_THREAT, 0.6, _rules.combatant(0).weapon)
	ContactFixture.arm(state.fighter(1), 2.1, 0.25, PI, 0.4, -3.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.combatant(0).weapon)
	state.fighter(1).stability = 0.7
	return state


func _poses(state: MatchState) -> Array[BladePose]:
	var spec := _rules.combatant(0)
	var poses: Array[BladePose] = [
		WeaponKinematics.pose_of(state.fighter(0), spec, BladePose.new()),
		WeaponKinematics.pose_of(state.fighter(1), spec, BladePose.new()),
	]
	return poses


## Relative velocity of the blade points at (PX, PY), blade 0 minus blade 1,
## along (dx, dy) — computed here from the kinematics, not by the solver.
func _relative(state: MatchState, dx: float, dy: float) -> float:
	var poses := _poses(state)
	WeaponKinematics.velocity_into(state.fighter(0), poses[0], PX, PY)
	WeaponKinematics.velocity_into(state.fighter(1), poses[1], PX, PY)
	return (poses[0].vx - poses[1].vx) * dx + (poses[0].vy - poses[1].vy) * dy


func _solve(state: MatchState, friction: float, closing: float, deltas: PackedFloat64Array) -> float:
	var poses := _poses(state)
	var a := state.fighter(0)
	var b := state.fighter(1)
	var cross_a := WeaponKinematics.lever(a, poses[0], PX, PY, NX, NY)
	var cross_b := WeaponKinematics.lever(b, poses[1], PX, PY, NX, NY)
	var inertia_a := WeaponKinematics.generalized_inertia(_rules.combatant(0), poses[0]) * 1.4
	var inertia_b := WeaponKinematics.generalized_inertia(_rules.combatant(0), poses[1]) * 1.1
	state.blade_contact.set_normal(NX, NY)
	return SwordContactSolver.solve(
		state.blade_contact, 0, a, b, poses[0], poses[1], PX, PY, closing,
		cross_a, cross_b, inertia_a, inertia_b, _rules.combatant(0).weapon.restitution, friction, deltas
	)


## μ = 0 is the frictionless solve, not a rounding of it: however many
## iterations the solver runs, a frictionless contact is the one-shot impulse
## bit for bit.
func test_a_frictionless_contact_is_the_one_shot_impulse_at_any_iteration_count() -> void:
	var state := _crossing_scene()
	var a := state.fighter(0)
	var b := state.fighter(1)
	var closing := -_relative(state, NX, NY)
	assert_true(closing > 0.0, "fixture: the blades close along the normal (%.3f m/s)" % closing)
	assert_true(SwordContactSolver.ITERATIONS > 1, "fixture: the solver iterates (%d)" % SwordContactSolver.ITERATIONS)
	## The shipped one-shot formula, written out independently.
	var poses := _poses(state)
	var cross_a := WeaponKinematics.lever(a, poses[0], PX, PY, NX, NY)
	var cross_b := WeaponKinematics.lever(b, poses[1], PX, PY, NX, NY)
	var inertia_a := WeaponKinematics.generalized_inertia(_rules.combatant(0), poses[0]) * 1.4
	var inertia_b := WeaponKinematics.generalized_inertia(_rules.combatant(0), poses[1]) * 1.1
	var denominator := cross_a * cross_a / inertia_a + cross_b * cross_b / inertia_b
	var impulse := (1.0 + _rules.combatant(0).weapon.restitution) * closing / denominator
	var speed_a := a.weapon.speed + impulse * cross_a / inertia_a
	var speed_b := b.weapon.speed + -impulse * cross_b / inertia_b
	var deltas := PackedFloat64Array([0.0, 0.0])
	var solved := _solve(state, SwordContactSolver.FRICTIONLESS, closing, deltas)
	assert_eq(solved, impulse, "the normal impulse is the one-shot impulse, bit for bit")
	assert_eq(a.weapon.speed, speed_a, "fighter 0's weapon speed matches exactly")
	assert_eq(b.weapon.speed, speed_b, "fighter 1's weapon speed matches exactly")
	assert_eq(deltas[0], impulse * cross_a / inertia_a, "the reported change is the applied change (0)")
	assert_eq(deltas[1], -impulse * cross_b / inertia_b, "the reported change is the applied change (1)")
	assert_eq(state.blade_contact.normal_impulse[0], impulse, "the manifold records the normal impulse")
	assert_near(_relative(state, NX, NY), _rules.combatant(0).weapon.restitution * closing, 1e-9, "the blades leave at e × the closing speed")


## The swords are held. Near the hands a contact's levers all but vanish, so a
## weapons-only response can remove the closing speed only by spinning both
## blades at ~closing ÷ lever; with the wielders' bodies in the effective mass
## the bodies carry it, the impulse is the closed form with their inverse masses
## added, and each body moves by J / m along the normal.
func test_the_wielders_carry_a_contact_at_the_hands() -> void:
	var lever := 0.05
	var closing := 6.6
	var inverse_mass := 1.0 / _rules.combatant(0).fighter.mass
	var ceiling := _rules.combatant(0).weapon.swing_speed_full * SimulationGuardrails.CAPACITY_SAFETY_FACTOR
	var collide := func(bodies: float) -> Array:
		var state := _crossing_scene()
		var poses := _poses(state)
		var a := state.fighter(0)
		var b := state.fighter(1)
		var inertia_a := WeaponKinematics.generalized_inertia(_rules.combatant(0), poses[0])
		var inertia_b := WeaponKinematics.generalized_inertia(_rules.combatant(0), poses[1])
		var start := [a.weapon.speed, b.weapon.speed, a.vx, a.vy, b.vx, b.vy]
		state.blade_contact.set_normal(NX, NY)
		var deltas := PackedFloat64Array([0.0, 0.0])
		var impulse := SwordContactSolver.solve(state.blade_contact, 0, a, b, poses[0], poses[1], PX, PY, closing, lever, lever, inertia_a, inertia_b, _rules.combatant(0).weapon.restitution, SwordContactSolver.FRICTIONLESS, deltas, bodies, bodies)
		var expected := (1.0 + _rules.combatant(0).weapon.restitution) * closing / (lever * lever / inertia_a + lever * lever / inertia_b + 2.0 * bodies)
		return [impulse, expected, deltas, a, b, start]
	var held: Array = collide.call(inverse_mass)
	var loose: Array = collide.call(0.0)
	assert_true(absf((loose[2] as PackedFloat64Array)[0]) > ceiling, "perturbation: weapons alone spin past twice the motor's actuated limit (%.1f rad/s)" % absf((loose[2] as PackedFloat64Array)[0]))
	assert_near(float(held[0]), float(held[1]), 1e-9, "the impulse is the closed form with the bodies' inverse masses")
	for slot in 2:
		assert_true(absf((held[2] as PackedFloat64Array)[slot]) < ceiling, "held, sword %d stays within twice the actuated limit (%.1f rad/s)" % [slot, absf((held[2] as PackedFloat64Array)[slot])])
	var held_a: FighterState = held[3]
	var held_b: FighterState = held[4]
	var before: Array = held[5]
	var j := float(held[0])
	assert_near(held_a.vx - float(before[2]), j * NX * inverse_mass, 1e-9, "fighter 0's body takes J / m along the normal (x)")
	assert_near(held_a.vy - float(before[3]), j * NY * inverse_mass, 1e-9, "(y)")
	assert_near(held_b.vx - float(before[4]), -j * NX * inverse_mass, 1e-9, "fighter 1's body the reaction (x)")
	assert_near(held_b.vy - float(before[5]), -j * NY * inverse_mass, 1e-9, "(y)")


func test_frictionless_contact_applies_no_tangent_impulse() -> void:
	var state := _crossing_scene()
	var tx := -NY
	var ty := NX
	var sliding_before := _relative(state, tx, ty)
	assert_true(absf(sliding_before) > 0.5, "fixture: the blades slide across each other (%.3f m/s)" % sliding_before)
	var closing := -_relative(state, NX, NY)
	var deltas := PackedFloat64Array([0.0, 0.0])
	var normal := _solve(state, SwordContactSolver.FRICTIONLESS, closing, deltas)
	assert_true(normal > 0.0, "the normal stage still pushes the blades apart")
	assert_eq(state.blade_contact.tangent_impulse[0], 0.0, "μ = 0 ⇒ Jt = 0 exactly")


func test_high_friction_sticks_the_slide() -> void:
	var state := _crossing_scene()
	var tx := -NY
	var ty := NX
	var closing := -_relative(state, NX, NY)
	var deltas := PackedFloat64Array([0.0, 0.0])
	var normal := _solve(state, 50.0, closing, deltas)
	var tangent := state.blade_contact.tangent_impulse[0]
	assert_true(absf(tangent) < 50.0 * normal, "inside the cone (|%.4f| < μ·%.4f)" % [tangent, normal])
	assert_near(_relative(state, tx, ty), 0.0, 1e-9, "a contact inside the cone stops sliding")


## Coulomb: the bound is μ·Jn on the accumulated impulses. A fast slide
## saturates it and keeps sliding; pressing harder raises what friction can
## take. (Not "doubles": with the swords' rotation coupling the two directions,
## the normal impulse of an iterated solve is not linear in the closing speed
## alone.)
func test_friction_saturates_at_the_coulomb_bound_and_grows_with_pressure() -> void:
	var friction := 0.05
	var light := _crossing_scene()
	var closing := -_relative(light, NX, NY)
	var tx := -NY
	var ty := NX
	var sliding_before := _relative(light, tx, ty)
	var deltas := PackedFloat64Array([0.0, 0.0])
	var light_normal := _solve(light, friction, closing, deltas)
	var light_tangent := light.blade_contact.tangent_impulse[0]
	## Saturated: the tangent sits on the cone it was clamped to. The final
	## normal top-up may then add a little normal impulse — it only widens the
	## cone and is never followed by a tangent step — so the tangent is on the
	## bound within that top-up and never outside it.
	assert_true(absf(light_tangent) <= friction * light_normal + 1e-12, "the tangent stays inside the cone")
	assert_near(absf(light_tangent), friction * light_normal, 1e-6 * friction * light_normal, "a fast slide saturates the cone")
	assert_true(absf(sliding_before) > 0.5, "fixture: a fast slide (%.3f m/s)" % sliding_before)
	assert_true(absf(_relative(light, tx, ty)) > 1e-3, "a saturated contact keeps sliding")
	var heavy := _crossing_scene()
	var heavy_normal := _solve(heavy, friction, closing * 2.0, deltas)
	var heavy_tangent := heavy.blade_contact.tangent_impulse[0]
	assert_true(heavy_normal > light_normal, "a harder press takes more normal impulse (%.3f → %.3f N·s)" % [light_normal, heavy_normal])
	assert_true(absf(heavy_tangent) <= friction * heavy_normal + 1e-12, "the accumulated tangent stays inside its cone")
	assert_true(absf(heavy_tangent) > absf(light_tangent), "and friction takes more of the slide (%.4f → %.4f N·s)" % [absf(light_tangent), absf(heavy_tangent)])


## Fighter 1's blade descends across fighter 0's from above; moving fighter 1
## along x slides the crossing down fighter 0's blade.
func _crossing_poses(b_x: float) -> Array[FighterPose]:
	return ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, 0.0), ContactFixture.pose(b_x, 0.5, PI, 0.5))


func test_the_manifold_records_where_the_blades_touch() -> void:
	var state := DuelFixture.state(_revolute)
	var weapon := _revolute.combatant(0).weapon
	var collision := CollisionSystem.new()
	var manifold := state.blade_contact
	var report := ContactReport.new()
	var near := _crossing_poses(1.6)
	manifold.begin_search()
	collision.detect(state, near, near, _revolute, manifold, report)
	assert_true(report.blade, "fixture: the crossing blades touch")
	assert_eq(manifold.point_count, 1, "crossing blades touch at one point")
	assert_eq(manifold.feature_a[0], SwordContactSet.Feature.BLADE, "on fighter 0's blade")
	assert_eq(manifold.feature_b[0], SwordContactSet.Feature.BLADE, "and fighter 1's")
	assert_false(manifold.is_persisted(0), "a first touch is not persisted")
	var fraction := manifold.fraction_a[0]
	var expected := (manifold.point_x[0] - weapon.hilt_radius) / (weapon.tip_radius - weapon.hilt_radius)
	assert_near(fraction, expected, 1e-6, "the fraction runs guard (0) → point (1) along the blade")
	assert_between(manifold.fraction_b[0], 0.0, 1.0, "and is a fraction on the other blade too")
	## Slide the crossing toward fighter 0's point; the contact stays the same one.
	var slid := _crossing_poses(1.8)
	manifold.begin_search()
	collision.detect(state, slid, slid, _revolute, manifold, report)
	assert_false(report.blade, "leaning on the same contact is not a second impact")
	assert_eq(manifold.point_count, 1, "still one point")
	assert_true(manifold.fraction_a[0] > fraction + 0.1, "the contact slid toward the point (%.3f → %.3f)" % [fraction, manifold.fraction_a[0]])
	assert_true(manifold.is_persisted(0), "and a slide alone never makes a new contact")
	## Pull fighter 1 clear: the manifold empties with no timer.
	var apart := _crossing_poses(3.4)
	manifold.begin_search()
	collision.detect(state, apart, apart, _revolute, manifold, report)
	assert_eq(manifold.point_count, 0, "separated geometry leaves no points")
	assert_false(manifold.is_touching(), "and the manifold says so")


func test_a_capped_sweep_is_counted_not_extended() -> void:
	var state := DuelFixture.state(_revolute)
	var collision := CollisionSystem.new()
	var report := ContactReport.new()
	var still := ContactFixture.pose(0.0, 0.0, 0.0, 0.0)
	var idle := ContactFixture.poses(still, still)
	collision.detect(state, idle, idle, _revolute, state.blade_contact, report)
	assert_eq(collision.diagnostics.ccd_cap_hits, 0, "fixture: an ordinary sweep fits its budget")
	var spun := ContactFixture.poses(ContactFixture.pose(5.0, 5.0, 0.0, 3.0), ContactFixture.pose(-5.0, 0.0, 0.0, -3.0))
	assert_true(CollisionSystem.substeps_wanted(idle, spun, _revolute) > _revolute.combat.max_substeps, "fixture: this motion wants more than the cap")
	collision.detect(state, idle, spun, _revolute, state.blade_contact, report)
	assert_eq(collision.diagnostics.ccd_cap_hits, 1, "the overflow is counted")
	assert_eq(CollisionSystem.substep_count(idle, spun, _revolute), _revolute.combat.max_substeps, "and the work stays at the cap")


func test_a_saturated_contact_loop_is_counted() -> void:
	var rules := DuelFixture.revolute_rules()
	rules.combat.max_contacts_per_tick = 1
	var simulation := DuelSimulation.create(rules)
	assert_true(simulation != null, "fixture: one contact per tick is still a valid rule set")
	var state := simulation.new_match(1)
	state.set_phase(MatchPhase.Id.ROUND_ACTIVE)
	DuelFixture.place(state.fighter(0), 0.0, 0.0, 0.0)
	DuelFixture.place(state.fighter(1), 1.6, 0.03, PI)
	state.fighter(0).weapon.angle = 0.0
	state.fighter(1).weapon.angle = 0.0
	assert_eq(simulation.diagnostics.contact_cap_hits, 0, "fixture: nothing has saturated yet")
	var events := simulation.step(state, PlayerCommand.new(), PlayerCommand.new())
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.CONTACT_SATURATED).size(), 1, "the one allowed contact saturates the loop")
	assert_eq(simulation.diagnostics.contact_cap_hits, 1, "and the saturation is counted")
	assert_true(simulation.diagnostics.max_manifold_points >= 1, "the touching blades were recorded")
