extends TestCase

## GUARD: the crossguard and the handle are collidable sword features
## (GUARD-CONTACT-001). Each sword is a blade, a crossbar and a handle capsule,
## each measured from the sword model, by one geometry (`SwordContactGeometry`)
## and solved by the same contact physics — rigid, frictional (`guard_friction`),
## never a cutting edge and never a separate guard physics. Hands are not
## collision.
##
## See also: /docs/reference/testing.md
## See also: /docs/concepts/combat.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "GUARD"
	_rules = DuelFixture.rules()


func _guardless() -> DuelRules:
	var rules := DuelFixture.rules()
	rules.combatant(0).weapon.guard_half_span = 0.0
	return rules


## Where a fighter must stand so the point `along` metres down its blade from
## the origin sits at (`px`, `py`) with the blade pointing along `direction`
## (θ = 0, heading = direction).
func _stand_for(px: float, py: float, direction: float, along: float, spec: CombatantPhysicsSpec) -> Vector2:
	var pose := WeaponKinematics.pose_at(0.0, 0.0, direction, 0.0, spec, BladePose.new())
	return Vector2(px - pose.point_x(along), py - pose.point_y(along))


## Fighter 1 in Long Guard at the origin facing `facing`; its guard centre.
func _guard_centre(spec: CombatantPhysicsSpec, facing: float = 0.0) -> Vector2:
	var pose := WeaponKinematics.pose_at(0.0, 0.0, facing, 0.0, spec, BladePose.new())
	return Vector2(pose.point_x(spec.weapon.guard_centre_radius), pose.point_y(spec.weapon.guard_centre_radius))


func _measure(state: MatchState, rules: DuelRules, geometry: SwordContactGeometry) -> float:
	var weapon := rules.combatant(0).weapon
	var spec := rules.combatant(0)
	var a := WeaponKinematics.pose_of(state.fighter(0), spec, BladePose.new())
	var b := WeaponKinematics.pose_of(state.fighter(1), spec, BladePose.new())
	return geometry.measure(state.fighter(0).x, state.fighter(0).y, a.origin_x, a.origin_y, a.ux, a.uy, b.origin_x, b.origin_y, b.ux, b.uy, weapon, weapon)


## Fighter 0's blade crossing fighter 1's left quillon `inward` metres in from
## its tip, five centimetres from its own point, at 60° to the bar, so neither
## fighter 0's guard nor the rest of its blade is near fighter 1's sword.
func _across_the_quillon(rules: DuelRules, inward: float = 0.02) -> MatchState:
	var weapon := rules.combatant(0).weapon
	var spec := rules.combatant(0)
	var state := DuelFixture.state(rules)
	ContactFixture.arm(state.fighter(1), 0.0, 0.0, 0.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var guard := _guard_centre(spec)
	var direction := deg_to_rad(-60.0)
	## Placed by the shipped crossbar, so the guardless control is the same scene.
	var at := _stand_for(guard.x, guard.y + _rules.combatant(0).weapon.guard_half_span - inward, direction, weapon.tip_radius - 0.05, spec)
	ContactFixture.arm(state.fighter(0), at.x, at.y, direction, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	return state


func test_the_nearest_feature_pair_is_the_contact() -> void:
	var weapon := _rules.combatant(0).weapon
	var spec := _rules.combatant(0)
	assert_true(weapon.guard_half_span > weapon.blade_radius * 2.0, "fixture: the crossbar reaches well past the blade (%.3f m)" % weapon.guard_half_span)
	var geometry := SwordContactGeometry.new()
	var across := _across_the_quillon(_rules)
	var gap := _measure(across, _rules, geometry)
	assert_true(gap < 0.0, "a blade across the quillon touches it (%.4f m)" % gap)
	assert_eq([geometry.feature_a, geometry.feature_b], [SwordContactSet.Feature.BLADE, SwordContactSet.Feature.GUARD], "on fighter 1's guard")
	assert_eq(geometry.fraction_b, 0.0, "a guard contact reads fraction 0")
	assert_true(geometry.fraction_a > 0.9, "near fighter 0's point (%.3f)" % geometry.fraction_a)
	## Perturb: the same blade with no crossguard on the sword touches nothing.
	var bare := SwordContactGeometry.new()
	assert_true(_measure(_across_the_quillon(_guardless()), _guardless(), bare) > 0.0, "without a guard the same blade is clear")
	## Two blades crossing at mid-length are blade on blade.
	var crossing := DuelFixture.state(_rules)
	ContactFixture.arm(crossing.fighter(1), 0.0, 0.0, 0.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var mid := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, spec, BladePose.new())
	var r := (weapon.hilt_radius + weapon.tip_radius) * 0.5
	var stand := _stand_for(mid.point_x(r), mid.point_y(r), -PI / 2.0, r, spec)
	ContactFixture.arm(crossing.fighter(0), stand.x, stand.y, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	_measure(crossing, _rules, geometry)
	assert_eq([geometry.feature_a, geometry.feature_b], [SwordContactSet.Feature.BLADE, SwordContactSet.Feature.BLADE], "crossing blades are blade on blade")


func test_a_degenerate_guard_normal_is_along_the_blade() -> void:
	var out := PackedFloat64Array([0.0, 0.0])
	SwordContactGeometry.degenerate_normal(SwordContactSet.Feature.GUARD, 1.0, 0.0, 0.3, 0.0, out)
	assert_eq(out, PackedFloat64Array([1.0, 0.0]), "a guard runs across the blade, so its normal is the blade direction")
	SwordContactGeometry.degenerate_normal(SwordContactSet.Feature.BLADE, 1.0, 0.0, 0.0, -0.3, out)
	assert_eq(out, PackedFloat64Array([0.0, -1.0]), "a blade's is its perpendicular, turned toward the other wielder")
	SwordContactGeometry.degenerate_normal(SwordContactSet.Feature.HILT, 1.0, 0.0, 0.0, 0.3, out)
	assert_eq(out, PackedFloat64Array([0.0, 1.0]), "the hilt runs along the blade, so it shares the blade's")


func test_guard_friction_is_a_material_not_a_rule() -> void:
	var combat := _rules.combat
	assert_true(combat.guard_friction > combat.blade_friction, "fixture: a crossbar grips harder than a blade")
	assert_eq(ContactMechanics.friction(SwordContactSet.Feature.BLADE, SwordContactSet.Feature.GUARD, combat), combat.guard_friction, "blade on guard is the guard's material")
	assert_eq(ContactMechanics.friction(SwordContactSet.Feature.GUARD, SwordContactSet.Feature.BLADE, combat), combat.guard_friction, "whichever side the guard is on")
	assert_eq(ContactMechanics.friction(SwordContactSet.Feature.BLADE, SwordContactSet.Feature.BLADE, combat), combat.blade_friction, "blade on blade is steel on steel")
	assert_eq(ContactMechanics.friction(SwordContactSet.Feature.HILT, SwordContactSet.Feature.BLADE, combat), combat.guard_friction, "the gripped hilt is hilt furniture too")


## A held contact can slide off the blade onto the crossguard. The contact
## never separates, so it is not a new impact; its identity is now another
## feature pair, so it is not the same persisted point either.
func test_a_contact_migrates_from_the_blade_onto_the_guard() -> void:
	var weapon := _rules.combatant(0).weapon
	var spec := _rules.combatant(0)
	var state := DuelFixture.state(_rules)
	var collision := CollisionSystem.new()
	var report := ContactReport.new()
	var manifold := state.blade_contact
	var home := ContactFixture.pose(0.0, 0.0, 0.0, 0.0, spec)
	var guard := _guard_centre(spec)
	var blade_start := guard.x + (weapon.hilt_radius - weapon.guard_centre_radius)
	## A diagonal blade across the forte, then the same blade drawn back past
	## the blade's start onto the crossbar.
	var diagonal := deg_to_rad(135.0)
	var reach := (weapon.hilt_radius + weapon.tip_radius) * 0.5
	var on_blade := _stand_for(blade_start + 0.06, 0.0, diagonal, reach, spec)
	var on_guard := _stand_for(blade_start - 0.04, 0.0, diagonal, reach, spec)
	var first := ContactFixture.poses(ContactFixture.pose(on_blade.x, on_blade.y, diagonal, 0.0, spec), home)
	manifold.begin_search()
	collision.detect(state, first, first, _rules, manifold, report)
	assert_true(report.blade, "fixture: the blades meet")
	assert_eq([manifold.feature_a[0], manifold.feature_b[0]], [SwordContactSet.Feature.BLADE, SwordContactSet.Feature.BLADE], "first on the blade")
	var slid := ContactFixture.poses(ContactFixture.pose(on_guard.x, on_guard.y, diagonal, 0.0, spec), home)
	manifold.begin_search()
	collision.detect(state, first, slid, _rules, manifold, report)
	assert_false(report.blade, "sliding onto the guard is not a new impact")
	assert_eq(manifold.phase, SwordContactSet.Phase.CONTACTING, "the contact never let go")
	var on_crossbar := -1
	for point in manifold.point_count:
		if manifold.feature_a[point] == SwordContactSet.Feature.BLADE and manifold.feature_b[point] == SwordContactSet.Feature.GUARD:
			on_crossbar = point
	assert_true(on_crossbar >= 0, "and it now rests on the guard (%d points)" % manifold.point_count)
	assert_false(manifold.is_persisted(on_crossbar), "a different feature pair is a different point")


## A crossbar is never a cutting edge: lying through a torso it is no body
## contact at all.
func test_a_guard_never_strikes_a_body() -> void:
	var weapon := _rules.combatant(0).weapon
	var spec := _rules.combatant(0)
	var runner := SimRunner.create(_rules, 1)
	runner.skip_intro()
	var state := runner.state
	ContactFixture.arm(state.fighter(1), 0.0, 0.0, 0.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var guard := _guard_centre(spec)
	var torso := Vector2(guard.x, guard.y + weapon.guard_half_span + 0.1)
	## Fighter 0 faces away with its own sword straight out ahead, far from
	## fighter 1's body and sword.
	ContactFixture.arm(state.fighter(0), torso.x, torso.y, PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var quillon := Vector2(guard.x, guard.y + weapon.guard_half_span)
	assert_true(quillon.distance_to(torso) < _rules.combatant(0).fighter.hurt_radius, "fixture: the quillon lies inside fighter 0's torso")
	var pose := WeaponKinematics.pose_of(state.fighter(1), spec, BladePose.new())
	var hx := pose.point_x(weapon.hilt_radius)
	var hy := pose.point_y(weapon.hilt_radius)
	var t := SimMath.closest_param_on_segment(hx, hy, pose.point_x(weapon.tip_radius), pose.point_y(weapon.tip_radius), torso.x, torso.y)
	var near := Vector2(SimMath.mix(hx, pose.point_x(weapon.tip_radius), t), SimMath.mix(hy, pose.point_y(weapon.tip_radius), t))
	assert_true(near.distance_to(torso) - _rules.combatant(0).fighter.hurt_radius - weapon.blade_radius > 0.0, "fixture: while its blade is clear of the torso")
	runner.idle(1)
	assert_eq(runner.count(DuelEventTypes.BODY_HIT), 0, "a guard inside a torso deals no hit")
	assert_eq(state.weapon_body_contacts[1].phase, WeaponBodyContact.Phase.OUTSIDE, "and starts no body contact")


## One real tick: fighter 0's blade, nearly flat alongside fighter 1's (tilted
## 10° so its point leads and its own guard trails well clear), sweeps sideways
## at `speed` across fighter 1's quillon and on into fighter 1's torso. `side`
## mirrors the scene (x → −x). Returns the runner.
func _sweep(rules: DuelRules, side: float, speed: float = 16.0) -> SimRunner:
	var weapon := rules.combatant(0).weapon
	var spec := rules.combatant(0)
	var runner := SimRunner.create(rules, 1)
	runner.skip_intro()
	var state := runner.state
	var facing := 0.0 if side > 0.0 else PI
	ContactFixture.arm(state.fighter(1), 0.0, 0.0, facing, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var guard := _guard_centre(spec, facing)
	var direction := facing + PI + side * deg_to_rad(10.0)
	var at := _stand_for(guard.x, guard.y + 0.22, direction, (weapon.hilt_radius + weapon.tip_radius) * 0.5, spec)
	ContactFixture.arm(state.fighter(0), at.x, at.y, direction, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	for fighter in state.fighters:
		fighter.weapon.swing_dir = side
		fighter.weapon.stable_side = side
	state.fighter(0).vy = -speed
	runner.idle(1)
	return runner


## Defence is chronological and the guard is part of it: a blade that meets
## the crossbar first is stopped there, so the torso behind it is not reached.
func test_a_guard_catch_stops_a_blade_before_the_body() -> void:
	var open := _sweep(_guardless(), 1.0)
	var open_hit := open.first(DuelEventTypes.BODY_HIT)
	var open_clash := open.first(DuelEventTypes.BLADE_CONTACT)
	assert_true(open_hit != null, "control: without a crossguard the sweep lays the blade on the torso")
	assert_true(open_clash == null or open.events.find(open_clash) > open.events.find(open_hit), "control: and the torso is the first thing it meets")
	var caught := _sweep(_rules, 1.0)
	var clash := caught.first(DuelEventTypes.BLADE_CONTACT)
	assert_true(clash != null, "the blade meets the crossguard")
	if clash == null:
		return
	assert_eq(int(clash.data[DuelEventKeys.FEATURE_1]), SwordContactSet.Feature.GUARD, "on fighter 1's guard, not its blade")
	assert_eq(caught.count(DuelEventTypes.BODY_HIT), 0, "and the torso behind it is not reached")
	var manifold := caught.state.blade_contact
	assert_ne(manifold.phase, SwordContactSet.Phase.SEPARATED, "the blade rests on the guard")


func test_a_guard_catch_mirrors_exactly() -> void:
	var right := _sweep(_rules, 1.0)
	var left := _sweep(_rules, -1.0)
	var r_clash := right.first(DuelEventTypes.BLADE_CONTACT)
	var l_clash := left.first(DuelEventTypes.BLADE_CONTACT)
	assert_true(r_clash != null and l_clash != null, "fixture: both sweeps meet the guard")
	if r_clash == null or l_clash == null:
		return
	assert_near(l_clash.number(DuelEventKeys.IMPULSE), r_clash.number(DuelEventKeys.IMPULSE), 1e-9, "the mirrored catch takes the same impulse")
	assert_near(l_clash.number(DuelEventKeys.FRACTION_0), r_clash.number(DuelEventKeys.FRACTION_0), 1e-9, "at the same place on the blade")
	for slot in 2:
		var r := right.state.fighter(slot)
		var l := left.state.fighter(slot)
		assert_near(l.x, -r.x, 1e-9, "slot %d: reflected position along the blade line" % slot)
		assert_near(l.y, r.y, 1e-9, "slot %d: the same lateral position" % slot)
		assert_near(l.vy, r.vy, 1e-9, "slot %d: the same lateral velocity" % slot)
		assert_near(l.weapon.angle, -r.weapon.angle, 1e-9, "slot %d: reflected θ" % slot)
		assert_near(l.weapon.speed, -r.weapon.speed, 1e-9, "slot %d: reflected θ̇" % slot)
