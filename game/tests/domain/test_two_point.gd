extends TestCase

## TWO-POINT: every feature pair of two compound swords (BLADE / GUARD / HILT
## on each side) is its own manifold of at most two contact points
## (TWO-POINT-001, CONTACT-MANIFOLD-001): its candidates, duplicates merged,
## the two nearest distinct constraints kept. The sword pair keeps every pair's
## points, so a lock with more constraints than two keeps them all. Every point
## is a row from its first impact, solved like a held contact — never a
## midpoint impulse that becomes several constraints a tick later. The event is
## placed at the touching points' centroid; the solve uses the points
## themselves.
##
## See also: /docs/reference/testing.md
## See also: /docs/concepts/combat.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "TWO-POINT"
	_rules = DuelFixture.rules()


## Where a fighter stands so the point `along` metres down its blade from the
## origin sits at (`px`, `py`), blade pointing along `direction` (θ = 0).
func _stand_for(px: float, py: float, direction: float, along: float, spec: CombatantPhysicsSpec) -> Vector2:
	var pose := WeaponKinematics.pose_at(0.0, 0.0, direction, 0.0, spec, BladePose.new())
	return Vector2(px - pose.point_x(along), py - pose.point_y(along))


func _measure(state: MatchState, rules: DuelRules, geometry: SwordContactGeometry) -> float:
	var weapon := rules.combatant(0).weapon
	var spec := rules.combatant(0)
	var a := WeaponKinematics.pose_of(state.fighter(0), spec, BladePose.new())
	var b := WeaponKinematics.pose_of(state.fighter(1), spec, BladePose.new())
	return geometry.measure(state.fighter(0).x, state.fighter(0).y, a.origin_x, a.origin_y, a.ux, a.uy, b.origin_x, b.origin_y, b.ux, b.uy, weapon, weapon)


## Fighter 1 in Long Guard at the origin facing +x; fighter 0's blade lying
## anti-parallel along it, `lateral` metres to its left (centre to centre), each
## point `short` metres (surface to surface) short of the other's crossbar.
## `mirror` reflects the scene across the x axis.
func _lying_along(rules: DuelRules, lateral: float, mirror: bool = false, short: float = 0.03) -> MatchState:
	var weapon := rules.combatant(0).weapon
	var spec := rules.combatant(0)
	var flip := -1.0 if mirror else 1.0
	var state := DuelFixture.state(rules)
	ContactFixture.arm(state.fighter(1), 0.0, 0.0, 0.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var pose := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, spec, BladePose.new())
	var guard_x := pose.point_x(weapon.guard_centre_radius)
	var tip_x := guard_x + weapon.guard_radius + weapon.blade_radius + short
	var at := _stand_for(tip_x, lateral * flip, PI, weapon.tip_radius, spec)
	ContactFixture.arm(state.fighter(0), at.x, at.y, PI, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	return state


## Record the geometry's touching points on the manifold, as the sweep does at
## a time of impact, and open the contact.
func _record_touching(state: MatchState, geometry: SwordContactGeometry) -> int:
	var manifold := state.blade_contact
	manifold.begin_substep()
	var index := 0
	for point in geometry.count:
		if geometry.point_gap[point] > 0.0:
			continue
		manifold.record_point(index, geometry.point_feature_a[point] as SwordContactSet.Feature, geometry.point_feature_b[point] as SwordContactSet.Feature, (geometry.point_ax[point] + geometry.point_bx[point]) * 0.5, (geometry.point_ay[point] + geometry.point_by[point]) * 0.5, geometry.point_fraction_a[point], geometry.point_fraction_b[point], geometry.point_nx[point], geometry.point_ny[point], geometry.point_local_a[point], geometry.point_local_b[point])
		index += 1
	manifold.observe(geometry.gap, 0.0, _rules.combat.separation_epsilon)
	return index


func test_crossing_blades_touch_at_one_point() -> void:
	var weapon := _rules.combatant(0).weapon
	var spec := _rules.combatant(0)
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(1), 0.0, 0.0, 0.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var pose := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, spec, BladePose.new())
	var r := (weapon.hilt_radius + weapon.tip_radius) * 0.5
	var at := _stand_for(pose.point_x(r), pose.point_y(r) + 2.0 * weapon.blade_radius - 0.001, deg_to_rad(-120.0), r, spec)
	ContactFixture.arm(state.fighter(0), at.x, at.y, deg_to_rad(-120.0), 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var geometry := SwordContactGeometry.new()
	assert_true(_measure(state, _rules, geometry) < 0.0, "fixture: the blades cross and touch")
	var where := PackedFloat64Array([0.0, 0.0])
	assert_eq(geometry.centroid(0.0, where), 1, "crossing blades touch at one point")
	assert_eq([geometry.feature_a, geometry.feature_b], [SwordContactSet.Feature.BLADE, SwordContactSet.Feature.BLADE], "blade on blade")


func test_blades_lying_along_each_other_touch_at_both_ends_of_the_overlap() -> void:
	var weapon := _rules.combatant(0).weapon
	var geometry := SwordContactGeometry.new()
	var state := _lying_along(_rules, 2.0 * weapon.blade_radius - 0.0005)
	assert_true(_measure(state, _rules, geometry) < 0.0, "fixture: the blades lie along each other, touching")
	var where := PackedFloat64Array([0.0, 0.0])
	assert_eq(geometry.centroid(0.0, where), 2, "a line contact is two points")
	for point in 2:
		assert_eq([geometry.point_feature_a[point], geometry.point_feature_b[point]], [SwordContactSet.Feature.BLADE, SwordContactSet.Feature.BLADE], "point %d is blade on blade" % point)
		assert_near(geometry.point_ny[point], 1.0, 1e-9, "point %d pushes straight apart" % point)
	var spread := absf(geometry.point_ax[1] - geometry.point_ax[0])
	assert_true(spread > 0.5, "at the two ends of the overlap, not one midpoint (%.3f m apart)" % spread)
	assert_true(geometry.point_fraction_a[0] < geometry.point_fraction_a[1], "in canonical order along fighter 0's blade")
	## Perturb: turned 30° the same blades cross instead — one point.
	ContactFixture.arm(state.fighter(0), state.fighter(0).x, state.fighter(0).y, PI - deg_to_rad(30.0), 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	_measure(state, _rules, geometry)
	assert_true(geometry.centroid(0.0, where) <= 1, "turned across, the line contact is gone")


## Near-parallel features have no single closest point, and the segment test
## may return any point of the overlap. Over an overlap the gap varies
## linearly, so that point is implied by the two ends: a line contact is always
## held at both ends, never at an interior point and one end (which would leave
## the other end free to turn in).
func test_a_near_parallel_line_contact_is_held_at_both_ends() -> void:
	var weapon := _rules.combatant(0).weapon
	var geometry := SwordContactGeometry.new()
	for tilt: float in [0.0, 1.0e-7, 1.0e-5, 1.0e-3]:
		var state := _lying_along(_rules, 2.0 * weapon.blade_radius - 0.0005)
		var fighter := state.fighter(0)
		ContactFixture.arm(fighter, fighter.x, fighter.y, PI + tilt, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
		assert_true(_measure(state, _rules, geometry) < 0.0, "tilt %s: fixture: the blades touch along each other" % tilt)
		var touching := _touching(geometry)
		assert_eq(touching.size(), 2, "tilt %s: a line contact is two points" % tilt)
		if touching.size() != 2:
			continue
		var spread := absf(geometry.point_ax[touching[1]] - geometry.point_ax[touching[0]])
		assert_true(spread > 0.5, "tilt %s: at the two ends of the overlap (%.3f m apart)" % [tilt, spread])
		assert_eq(geometry.dropped_within(0.0), 0, "tilt %s: and nothing real is left out" % tilt)


## A blade caught in the corner between the crossbar and the handle touches
## both, pushed two ways: two constraints, though they meet at one place.
func test_a_blade_in_the_corner_of_guard_and_handle_is_two_constraints() -> void:
	var weapon := _rules.combatant(0).weapon
	var spec := _rules.combatant(0)
	var state := DuelFixture.state(_rules)
	ContactFixture.arm(state.fighter(1), 0.0, 0.0, 0.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var pose := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, spec, BladePose.new())
	var corner_x := pose.point_x(weapon.guard_centre_radius) - weapon.guard_radius - weapon.blade_radius + 0.0003
	var corner_y := weapon.handle_radius + weapon.blade_radius - 0.0003
	var direction := -PI / 4.0
	var at := _stand_for(corner_x, corner_y, direction, weapon.tip_radius, spec)
	ContactFixture.arm(state.fighter(0), at.x, at.y, direction, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var geometry := SwordContactGeometry.new()
	assert_true(_measure(state, _rules, geometry) < 0.0, "fixture: the point sits in the corner")
	var where := PackedFloat64Array([0.0, 0.0])
	assert_eq(geometry.centroid(0.0, where), 2, "two touching points")
	var touching := _touching(geometry)
	var pairs := []
	for point in touching:
		pairs.append([geometry.point_feature_a[point], geometry.point_feature_b[point]])
	assert_true(pairs.has([SwordContactSet.Feature.BLADE, SwordContactSet.Feature.GUARD]), "one on the crossbar (%s)" % [pairs])
	assert_true(pairs.has([SwordContactSet.Feature.BLADE, SwordContactSet.Feature.HILT]), "one on the handle (%s)" % [pairs])
	var dot := geometry.point_nx[touching[0]] * geometry.point_nx[touching[1]] + geometry.point_ny[touching[0]] * geometry.point_ny[touching[1]]
	assert_true(absf(dot) < 0.2, "pushed two different ways (cos %.3f)" % dot)


## The geometry's touching points (gap ≤ 0), in its canonical order.
static func _touching(geometry: SwordContactGeometry) -> PackedInt32Array:
	var out := PackedInt32Array()
	for point in geometry.count:
		if geometry.point_gap[point] <= 0.0:
			out.append(point)
	return out


## The same scene reflected gives the reflected manifold: same gaps, same
## canonical order, reflected points and normals.
func test_the_manifold_mirrors_exactly() -> void:
	var lateral := 2.0 * _rules.combatant(0).weapon.blade_radius - 0.0005
	var straight := SwordContactGeometry.new()
	var reflected := SwordContactGeometry.new()
	_measure(_lying_along(_rules, lateral), _rules, straight)
	_measure(_lying_along(_rules, lateral, true), _rules, reflected)
	assert_eq(reflected.count, straight.count, "the same number of points")
	for point in straight.count:
		assert_near(reflected.point_gap[point], straight.point_gap[point], 1e-12, "point %d: the same gap" % point)
		assert_eq(reflected.point_feature_a[point], straight.point_feature_a[point], "point %d: the same feature on a" % point)
		assert_near(reflected.point_ax[point], straight.point_ax[point], 1e-9, "point %d: the same x" % point)
		assert_near(reflected.point_ay[point], -straight.point_ay[point], 1e-9, "point %d: the reflected y" % point)
		assert_near(reflected.point_ny[point], -straight.point_ny[point], 1e-9, "point %d: the reflected normal" % point)


## Record the touching points like `_record_touching`, last to first: the same
## physical contact stored in the other order.
func _record_touching_reversed(state: MatchState, geometry: SwordContactGeometry) -> int:
	var manifold := state.blade_contact
	manifold.begin_substep()
	var touching := _touching(geometry)
	touching.reverse()
	var index := 0
	for point: int in touching:
		manifold.record_point(index, geometry.point_feature_a[point] as SwordContactSet.Feature, geometry.point_feature_b[point] as SwordContactSet.Feature, (geometry.point_ax[point] + geometry.point_bx[point]) * 0.5, (geometry.point_ay[point] + geometry.point_by[point]) * 0.5, geometry.point_fraction_a[point], geometry.point_fraction_b[point], geometry.point_nx[point], geometry.point_ny[point], geometry.point_local_a[point], geometry.point_local_b[point])
		index += 1
	manifold.observe(geometry.gap, 0.0, _rules.combat.separation_epsilon)
	return index


## TWOPOINT-ORDER-001 (FRICTION-ORDER-001): storage order decides nothing
## physical. The same sliding line contact, its two points stored in either
## order, gives the same bodies, the same swords and the same total impulse —
## each point's own impulses simply swap places. Friction is engaged (the
## blades slide along the line), so the friction pass is what is proved.
func test_a_line_contacts_point_order_changes_nothing_physical() -> void:
	var weapon := _rules.combatant(0).weapon
	var states: Array[MatchState] = []
	for reversed: bool in [false, true]:
		## ARRANGE: a line contact driven into the line and along it.
		var state := _lying_along(_rules, 2.0 * weapon.blade_radius - 0.0005)
		state.fighter(0).vy = -2.5
		state.fighter(0).vx = 1.5
		var geometry := SwordContactGeometry.new()
		_measure(state, _rules, geometry)
		var recorded := _record_touching_reversed(state, geometry) if reversed else _record_touching(state, geometry)
		assert_eq(recorded, 2, "fixture: a two-point line contact")
		## ACT
		var report := ContactReport.new()
		report.blade = true
		var events: Array[DuelEvent] = []
		ContactResolver.resolve(state, report, _rules, 1, 0.0, events)
		states.append(state)
	## ASSERT
	var forward := states[0].blade_contact
	var backward := states[1].blade_contact
	assert_true(absf(forward.tangent_impulse[0]) + absf(forward.tangent_impulse[1]) > 0.0, "precondition: friction acted")
	for slot in 2:
		var x := states[0].fighter(slot)
		var y := states[1].fighter(slot)
		assert_near(y.vx, x.vx, 1.0e-12, "slot %d: the same body velocity x" % slot)
		assert_near(y.vy, x.vy, 1.0e-12, "slot %d: and y" % slot)
		assert_near(y.weapon.speed, x.weapon.speed, 1.0e-12, "slot %d: the same sword speed" % slot)
	for point in 2:
		assert_near(backward.normal_impulse[1 - point], forward.normal_impulse[point], 1.0e-12, "point %d's normal impulse follows the point, not the slot" % point)
		assert_near(backward.tangent_impulse[1 - point], forward.tangent_impulse[point], 1.0e-12, "and its friction too")


## A line contact's first impact is solved on both points at once: both carry
## impulse, neither is left closing, and the event says so.
func test_a_line_contact_is_two_rows_from_its_first_impact() -> void:
	var weapon := _rules.combatant(0).weapon
	var spec := _rules.combatant(0)
	var state := _lying_along(_rules, 2.0 * weapon.blade_radius - 0.0005)
	state.fighter(0).vy = -2.5
	var geometry := SwordContactGeometry.new()
	_measure(state, _rules, geometry)
	assert_eq(_record_touching(state, geometry), 2, "fixture: the sweep would record two points")
	var events: Array[DuelEvent] = []
	var report := ContactReport.new()
	report.blade = true
	ContactResolver.resolve(state, report, _rules, 1, 0.0, events)
	var contacts := DuelFixture.of_type(events, DuelEventTypes.BLADE_CONTACT)
	assert_eq(contacts.size(), 1, "one blade contact")
	if contacts.is_empty():
		return
	assert_eq(int(contacts[0].number(DuelEventKeys.POINT_COUNT)), 2, "solved on two points")
	var manifold := state.blade_contact
	for point in 2:
		assert_true(manifold.normal_impulse[point] > 0.0, "point %d carries impulse (%.4f N·s)" % [point, manifold.normal_impulse[point]])
	var pose_a := WeaponKinematics.pose_of(state.fighter(0), spec, BladePose.new())
	var pose_b := WeaponKinematics.pose_of(state.fighter(1), spec, BladePose.new())
	for point in 2:
		var closing := SwordContactSolver.closing_speed(state.fighter(0), state.fighter(1), pose_a, pose_b, manifold.point_x[point], manifold.point_y[point], manifold.point_nx[point], manifold.point_ny[point])
		assert_true(closing <= 1.0e-6, "point %d is no longer closing (%.6f m/s)" % [point, closing])
	var middle := (manifold.point_x[0] + manifold.point_x[1]) * 0.5
	assert_near(contacts[0].number(DuelEventKeys.X), middle, 1e-9, "the event sits at the line's middle")


## Two swords lying along each other, each point resting on the other's
## crossbar: the blades touch along a line (two points) and each point is
## stopped by a guard (one point per guard, pushed along the blades) — four
## independent constraints across three feature pairs, more than any one
## manifold of two could hold (TWO-POINT-001). Every one is kept and every one
## is solved from the first impact and in the hold; none is left closing.
func test_a_sword_lock_keeps_every_independent_constraint() -> void:
	var weapon := _rules.combatant(0).weapon
	var spec := _rules.combatant(0)
	var state := _lying_along(_rules, 2.0 * weapon.blade_radius - 0.0005, false, -0.0005)
	var geometry := SwordContactGeometry.new()
	assert_true(_measure(state, _rules, geometry) < 0.0, "fixture: the swords touch")
	var touching := _touching(geometry)
	var pairs := {}
	for point in touching:
		pairs[SwordContactSet.pair_of(geometry.point_feature_a[point], geometry.point_feature_b[point])] = true
	assert_true(touching.size() > SwordContactSet.POINTS_PER_PAIR, "fixture: more constraints than one feature pair could hold (%d)" % touching.size())
	assert_true(pairs.size() >= 3, "fixture: the line and both guards (%d feature pairs)" % pairs.size())
	assert_eq(geometry.dropped_within(0.0), 0, "no feature pair leaves a constraint out")
	var held := _lying_along(_rules, 2.0 * weapon.blade_radius - 0.0005, false, -0.0005)
	## Perturb: drive fighter 0 into everything at once — along the blades
	## into both guards, across them into the line.
	for scene: MatchState in [state, held]:
		scene.fighter(0).vx = -1.2
		scene.fighter(0).vy = -0.6
		scene.fighter(0).weapon.speed = 0.4
		_measure(scene, _rules, geometry)
		assert_eq(_record_touching(scene, geometry), touching.size(), "fixture: the sweep records every touching point")
	var events: Array[DuelEvent] = []
	var report := ContactReport.new()
	report.blade = true
	ContactResolver.resolve(state, report, _rules, 1, 0.0, events)
	var contacts := DuelFixture.of_type(events, DuelEventTypes.BLADE_CONTACT)
	assert_eq(contacts.size(), 1, "one blade contact")
	if contacts.is_empty():
		return
	assert_eq(int(contacts[0].number(DuelEventKeys.POINT_COUNT)), touching.size(), "solved on every point")
	RigidContactSolver.new().solve_velocity(held, _rules)
	for scene: MatchState in [state, held]:
		var label := "impact" if scene == state else "hold"
		var pose_a := WeaponKinematics.pose_of(scene.fighter(0), spec, BladePose.new())
		var pose_b := WeaponKinematics.pose_of(scene.fighter(1), spec, BladePose.new())
		var contact := scene.blade_contact
		var guards := 0.0
		for point in contact.point_count:
			var closing := SwordContactSolver.closing_speed(scene.fighter(0), scene.fighter(1), pose_a, pose_b, contact.point_x[point], contact.point_y[point], contact.point_nx[point], contact.point_ny[point])
			assert_true(closing <= 1.0e-6, "%s: point %d is no longer closing (%.6f m/s)" % [label, point, closing])
			if contact.feature_a[point] == SwordContactSet.Feature.GUARD or contact.feature_b[point] == SwordContactSet.Feature.GUARD:
				guards += contact.normal_impulse[point]
		assert_true(guards > 0.0, "%s: the guards take part of the push (%.4f N·s)" % [label, guards])


## Impact and hold are one mechanics: a slow (inelastic) two-point first
## impact and the held solver, from the same velocities, leave the same
## velocities. Frictionless, both are exactly one block solve.
func test_a_slow_two_point_impact_is_solved_exactly_like_a_hold() -> void:
	var rules := DuelFixture.rules()
	rules.combat.blade_friction = 0.0
	rules.combat.guard_friction = 0.0
	var weapon := rules.combatant(0).weapon
	var impact := _lying_along(rules, 2.0 * weapon.blade_radius - 0.0005)
	var held := _lying_along(rules, 2.0 * weapon.blade_radius - 0.0005)
	for state: MatchState in [impact, held]:
		state.fighter(0).vy = -0.4
		state.fighter(0).weapon.speed = 0.3
		var geometry := SwordContactGeometry.new()
		_measure(state, rules, geometry)
		_record_touching(state, geometry)
	assert_true(0.4 < weapon.restitution_threshold_speed, "fixture: closing below the restitution threshold, so the impact is inelastic")
	var events: Array[DuelEvent] = []
	var report := ContactReport.new()
	report.blade = true
	ContactResolver.resolve(impact, report, rules, 1, 0.0, events)
	RigidContactSolver.new().solve_velocity(held, rules)
	for slot in 2:
		assert_near(impact.fighter(slot).vx, held.fighter(slot).vx, 1e-9, "slot %d: the same vx" % slot)
		assert_near(impact.fighter(slot).vy, held.fighter(slot).vy, 1e-9, "slot %d: the same vy" % slot)
		assert_near(impact.fighter(slot).weapon.speed, held.fighter(slot).weapon.speed, 1e-9, "slot %d: the same θ̇" % slot)


## CONTACT-IDENTITY-001, the law itself: a point is the same contact as the
## old point on the same features it moved least from, one to one, whatever
## slot either occupies; a different feature pair or a jump past
## `MATCH_DISTANCE` is a new contact.
func test_contact_identity_follows_the_point_not_the_slot() -> void:
	var blade := SwordContactSet.Feature.BLADE
	var guard := SwordContactSet.Feature.GUARD
	var old_a := PackedInt32Array([blade, blade])
	var old_b := PackedInt32Array([blade, blade])
	var old_la := PackedFloat64Array([0.20, 0.70])
	var old_lb := PackedFloat64Array([0.80, 0.30])
	var out := PackedInt32Array([0, 0])
	## ARRANGE: two old points of one line contact, far apart on both blades.
	assert_true(absf(old_la[0] - old_la[1]) + absf(old_lb[0] - old_lb[1]) > SwordContactSet.MATCH_DISTANCE, "fixture: the old points are distinguishable")
	## One survivor, now in slot 0, near old point 1.
	SwordContactSet.assign(1, PackedInt32Array([blade, 0]), PackedInt32Array([blade, 0]), PackedFloat64Array([0.69, 0.0]), PackedFloat64Array([0.31, 0.0]), 2, old_a, old_b, old_la, old_lb, out)
	assert_eq(out[0], 1, "the survivor in slot 0 is old point 1, not whatever was in slot 0")
	## Both points, in swapped slots.
	SwordContactSet.assign(2, PackedInt32Array([blade, blade]), PackedInt32Array([blade, blade]), PackedFloat64Array([0.71, 0.21]), PackedFloat64Array([0.29, 0.79]), 2, old_a, old_b, old_la, old_lb, out)
	assert_eq([out[0], out[1]], [1, 0], "swapped slots keep their own contacts")
	## PERTURB: another feature pair, or a jump, is a new contact.
	SwordContactSet.assign(1, PackedInt32Array([guard, 0]), PackedInt32Array([blade, 0]), PackedFloat64Array([0.69, 0.0]), PackedFloat64Array([0.31, 0.0]), 2, old_a, old_b, old_la, old_lb, out)
	assert_eq(out[0], SwordContactSet.UNMATCHED, "a crossbar touch is never the blade touch it replaced")
	SwordContactSet.assign(1, PackedInt32Array([blade, 0]), PackedInt32Array([blade, 0]), PackedFloat64Array([0.45, 0.0]), PackedFloat64Array([0.55, 0.0]), 2, old_a, old_b, old_la, old_lb, out)
	assert_eq(out[0], SwordContactSet.UNMATCHED, "a point that jumped past the match distance is new")
	## A mirror reverses a crossbar's coordinate; the assignment is unchanged.
	var guard_a := PackedInt32Array([guard, guard])
	SwordContactSet.assign(2, guard_a, old_b, PackedFloat64Array([0.72, 0.18]), old_lb, 2, guard_a, old_b, old_la, old_lb, out)
	var straight := [out[0], out[1]]
	SwordContactSet.assign(2, guard_a, old_b, PackedFloat64Array([0.28, 0.82]), old_lb, 2, guard_a, old_b, PackedFloat64Array([0.80, 0.30]), old_lb, out)
	assert_eq([out[0], out[1]], straight, "the mirrored crossbar matches the same way")


## A line contact slides apart: the blades lie along each other (two points),
## then one blade turns about its point so the inner end of the overlap lifts.
## The surviving end — the point that was slot 1 — moves to slot 0 and must
## keep its own history: its contact id, its age, and the warm-start impulse it
## was held with, never slot 0's.
func test_a_surviving_endpoint_keeps_its_own_history() -> void:
	var rules := DuelFixture.rules()
	var weapon := rules.combatant(0).weapon
	var spec := rules.combatant(0)
	var state := _lying_along(rules, 2.0 * weapon.blade_radius - 0.0005)
	var manifold := state.blade_contact
	var geometry := SwordContactGeometry.new()
	var solver := RigidContactSolver.new()
	var tip := WeaponKinematics.pose_of(state.fighter(0), spec, BladePose.new())
	var tip_x := tip.point_x(weapon.tip_radius)
	var tip_y := tip.point_y(weapon.tip_radius)
	## ARRANGE: two touching points, held and pressed unevenly.
	manifold.begin_search()
	_measure(state, rules, geometry)
	assert_eq(_record_touching(state, geometry), 2, "fixture: a line contact, two points")
	state.fighter(0).vy = -0.4
	state.fighter(0).weapon.speed = 0.3
	solver.solve_velocity(state, rules, true)
	assert_eq(manifold.hold_count(), 2, "fixture: both points are held")
	var tip_end := 1 if manifold.local_a[1] > manifold.local_a[0] else 0
	assert_eq(tip_end, 1, "fixture: the end at fighter 0's point is slot 1 (farther from its origin)")
	var held_normal := manifold.hold_normal[tip_end]
	assert_true(absf(manifold.hold_normal[0] - manifold.hold_normal[1]) > 1.0e-4, "fixture: the two ends were held with different impulses (%.4f vs %.4f)" % [manifold.hold_normal[0], manifold.hold_normal[1]])
	var tip_id := manifold.contact_id[tip_end]
	var other_id := manifold.contact_id[1 - tip_end]
	assert_true(tip_id != other_id, "fixture: the two ends are two contacts")
	## PERTURB: turn fighter 0's blade about its point, a step at a time; the
	## inner end lifts while the point stays on the other blade.
	var survived := false
	for step in range(1, 9):
		var turn := deg_to_rad(0.5 * step)
		var at := _stand_for(tip_x, tip_y, PI + turn, weapon.tip_radius, spec)
		ContactFixture.arm(state.fighter(0), at.x, at.y, PI + turn, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
		state.fighter(1).vx = 0.0
		state.fighter(1).vy = 0.0
		state.fighter(0).vy = -0.4
		manifold.begin_search()
		_measure(state, rules, geometry)
		var touching := _record_touching(state, geometry)
		## ACT: the held solver's next tick.
		solver.solve_velocity(state, rules, true)
		if touching == 1:
			survived = true
			## ASSERT: slot 0 is now the point's own contact.
			assert_eq(manifold.contact_id[0], tip_id, "step %d: the survivor keeps its own contact id" % step)
			assert_true(manifold.age[0] >= step, "step %d: and its age (%d)" % [step, manifold.age[0]])
			assert_near(solver.warm_normal[0], maxf(held_normal, 0.0), 1e-12, "step %d: and starts from its own held impulse, not slot 0's" % step)
			break
		held_normal = manifold.hold_normal[1]
	assert_true(survived, "fixture: the inner end lifted while the point stayed touching")


## RIGID-CONTACT-001 final normal guarantee on a frictional first impact: a
## line contact that strikes while sliding fast along the other blade saturates
## its Coulomb cone. After the whole solve every row meets its restitution
## target, every tangent stays inside its cone, and the energy taken out is the
## drop in the solve's kinetic energy — never negative.
func test_a_sliding_two_point_impact_keeps_every_normal_and_its_cone() -> void:
	var rules := DuelFixture.rules()
	var weapon := rules.combatant(0).weapon
	var spec := rules.combatant(0)
	var state := _lying_along(rules, 2.0 * weapon.blade_radius - 0.0005)
	var a := state.fighter(0)
	var b := state.fighter(1)
	a.vy = -2.5
	a.vx = 3.0
	a.weapon.speed = 0.6
	var geometry := SwordContactGeometry.new()
	_measure(state, rules, geometry)
	assert_eq(_record_touching(state, geometry), 2, "fixture: two touching points")
	var manifold := state.blade_contact
	var pose_a := WeaponKinematics.pose_of(a, spec, BladePose.new())
	var pose_b := WeaponKinematics.pose_of(b, spec, BladePose.new())
	var targets := PackedFloat64Array([0.0, 0.0])
	for point in 2:
		var closing := SwordContactSolver.closing_speed(a, b, pose_a, pose_b, manifold.point_x[point], manifold.point_y[point], manifold.point_nx[point], manifold.point_ny[point])
		assert_true(closing > 0.0, "fixture: point %d closes (%.3f m/s)" % [point, closing])
		targets[point] = weapon.restitution_at(closing) * closing
	var held := PackedFloat64Array([0.0, 0.0])
	ContactMechanics.held_sword(a, pose_a, manifold.point_x[0], manifold.point_y[0], rules.combatant(0), held)
	var inertia_a := held[0]
	var inverse_a := held[1]
	ContactMechanics.held_sword(b, pose_b, manifold.point_x[0], manifold.point_y[0], rules.combatant(0), held)
	var inertia_b := held[0]
	var inverse_b := held[1]
	var before := SwordContactSolver.kinetic_energy(a, b, inertia_a, inertia_b, inverse_a, inverse_b)
	var events: Array[DuelEvent] = []
	var report := ContactReport.new()
	report.blade = true
	## ACT
	ContactResolver.resolve(state, report, rules, 1, 0.0, events)
	var contacts := DuelFixture.of_type(events, DuelEventTypes.BLADE_CONTACT)
	assert_eq(contacts.size(), 1, "one blade contact")
	if contacts.is_empty():
		return
	pose_a = WeaponKinematics.pose_of(a, spec, BladePose.new())
	pose_b = WeaponKinematics.pose_of(b, spec, BladePose.new())
	var saturated := false
	for point in 2:
		var mu := ContactMechanics.friction(manifold.feature_a[point], manifold.feature_b[point], rules.combat)
		var separation := -SwordContactSolver.closing_speed(a, b, pose_a, pose_b, manifold.point_x[point], manifold.point_y[point], manifold.point_nx[point], manifold.point_ny[point])
		assert_true(separation >= targets[point] - 1.0e-9, "point %d meets its restitution target (%.6f ≥ %.6f m/s)" % [point, separation, targets[point]])
		assert_true(absf(manifold.tangent_impulse[point]) <= mu * manifold.normal_impulse[point] + 1.0e-12, "point %d stays inside its cone (|%.5f| ≤ %.5f)" % [point, manifold.tangent_impulse[point], mu * manifold.normal_impulse[point]])
		saturated = saturated or absf(absf(manifold.tangent_impulse[point]) - mu * manifold.normal_impulse[point]) <= 1.0e-9
	assert_true(saturated, "fixture: the fast slide saturates a cone")
	var after := SwordContactSolver.kinetic_energy(a, b, inertia_a, inertia_b, inverse_a, inverse_b)
	var energy := contacts[0].number(DuelEventKeys.ENERGY)
	assert_true(energy > 0.0, "the impact takes energy out (%.4f J)" % energy)
	assert_near(energy, before - after, 1e-9, "exactly the drop in the solve's kinetic energy")


## The energy of a frictionless single contact is the closed form: one law, and
## its known exact value.
func test_a_frictionless_crossing_takes_out_the_closed_form_energy() -> void:
	var rules := DuelFixture.rules()
	rules.combat.blade_friction = 0.0
	var weapon := rules.combatant(0).weapon
	var spec := rules.combatant(0)
	var state := DuelFixture.state(rules)
	ContactFixture.arm(state.fighter(1), 0.0, 0.0, 0.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var pose := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, spec, BladePose.new())
	var r := (weapon.hilt_radius + weapon.tip_radius) * 0.5
	var at := _stand_for(pose.point_x(r), pose.point_y(r) + 2.0 * weapon.blade_radius - 0.001, deg_to_rad(-120.0), r, spec)
	ContactFixture.arm(state.fighter(0), at.x, at.y, deg_to_rad(-120.0), 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	state.fighter(0).vy = -3.0
	var geometry := SwordContactGeometry.new()
	_measure(state, rules, geometry)
	assert_eq(_record_touching(state, geometry), 1, "fixture: one crossing point")
	var a := state.fighter(0)
	var b := state.fighter(1)
	var manifold := state.blade_contact
	var pose_a := WeaponKinematics.pose_of(a, spec, BladePose.new())
	var pose_b := WeaponKinematics.pose_of(b, spec, BladePose.new())
	var px := manifold.point_x[0]
	var py := manifold.point_y[0]
	var closing := SwordContactSolver.closing_speed(a, b, pose_a, pose_b, px, py, manifold.point_nx[0], manifold.point_ny[0])
	var held := PackedFloat64Array([0.0, 0.0])
	ContactMechanics.held_sword(a, pose_a, px, py, rules.combatant(0), held)
	var k := held[1] + pow(WeaponKinematics.lever(a, pose_a, px, py, manifold.point_nx[0], manifold.point_ny[0]), 2.0) / held[0]
	ContactMechanics.held_sword(b, pose_b, px, py, rules.combatant(0), held)
	k += held[1] + pow(WeaponKinematics.lever(b, pose_b, px, py, manifold.point_nx[0], manifold.point_ny[0]), 2.0) / held[0]
	var events: Array[DuelEvent] = []
	var report := ContactReport.new()
	report.blade = true
	ContactResolver.resolve(state, report, rules, 1, 0.0, events)
	var contacts := DuelFixture.of_type(events, DuelEventTypes.BLADE_CONTACT)
	assert_eq(contacts.size(), 1, "one blade contact")
	if contacts.is_empty():
		return
	assert_near(contacts[0].number(DuelEventKeys.ENERGY), ContactMechanics.dissipated_energy(closing, k, weapon.restitution_at(closing)), 1e-9, "½(1 − e²)·v_n²/K")


## `measure` against a brute-force reference over seeded random poses: exact in
## the contact neighbourhood (true gap ≤ `EXACT_WITHIN`), and outside it never
## reports anything a caller could treat as touching. The broadphase may skip
## a pair only when it is certainly beyond `EXACT_WITHIN`.
func test_the_broadphase_is_exact_near_contact_and_conservative_beyond() -> void:
	var weapon := _rules.combatant(0).weapon
	var geometry := SwordContactGeometry.new()
	var rng := SeededRng.create(4242, 7)
	var near := 0
	var far := 0
	var wrong := PackedStringArray()
	for _sample in 3000:
		var ta := rng.next_range(-PI, PI)
		var tb := rng.next_range(-PI, PI)
		var ux := cos(ta)
		var uy := sin(ta)
		var vx := cos(tb)
		var vy := sin(tb)
		## Sword b's origin anywhere a blade's length around a point on sword a.
		var along := rng.next_range(0.0, weapon.tip_radius)
		var bx := ux * along + rng.next_range(-1.2, 1.2)
		var by := uy * along + rng.next_range(-1.2, 1.2)
		var truth := _brute_gap(0.0, 0.0, ux, uy, bx, by, vx, vy, weapon)
		var measured := geometry.measure(-ux, -uy, 0.0, 0.0, ux, uy, bx, by, vx, vy, weapon, weapon)
		if truth <= SwordContactGeometry.EXACT_WITHIN:
			near += 1
			if absf(measured - truth) > 1.0e-12 or geometry.count < 1:
				wrong.append("near: truth %.6f measured %.6f points %d" % [truth, measured, geometry.count])
		else:
			far += 1
			if measured < SwordContactGeometry.EXACT_WITHIN - 1.0e-12:
				wrong.append("far: truth %.6f measured %.6f" % [truth, measured])
	assert_true(near > 200 and far > 200, "fixture: both neighbourhoods sampled (%d near, %d far)" % [near, far])
	assert_eq(wrong.size(), 0, "the broadphase never changes an answer a caller reads:\n%s" % "\n".join(wrong.slice(0, 5)))


## Independent reference: every present feature pair, measured exactly.
func _brute_gap(pax: float, pay: float, ux: float, uy: float, pbx: float, pby: float, vx: float, vy: float, weapon: WeaponDefinition) -> float:
	var contact := SegmentContact.new()
	var la := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var lb := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var best := INF
	for fa in 3:
		for fb in 3:
			if not SwordContactGeometry.has_feature(fa, weapon) or not SwordContactGeometry.has_feature(fb, weapon):
				continue
			SwordContactGeometry.local_segment(fa, weapon, la)
			SwordContactGeometry.local_segment(fb, weapon, lb)
			SimMath.closest_segments(
				pax + ux * la[0] - uy * la[1], pay + uy * la[0] + ux * la[1], pax + ux * la[2] - uy * la[3], pay + uy * la[2] + ux * la[3],
				pbx + vx * lb[0] - vy * lb[1], pby + vy * lb[0] + vx * lb[1], pbx + vx * lb[2] - vy * lb[3], pby + vy * lb[2] + vx * lb[3],
				contact
			)
			best = minf(best, contact.distance - _feature_radius(fa, weapon) - _feature_radius(fb, weapon))
	return best


static func _feature_radius(feature: int, weapon: WeaponDefinition) -> float:
	match feature:
		SwordContactSet.Feature.GUARD:
			return weapon.guard_radius
		SwordContactSet.Feature.HILT:
			return weapon.handle_radius
	return weapon.blade_radius


## HAND-CONTACT-001: steel keeps its real size. The handle collides as the
## sword's own grip — never as the fists around it, which are hurt geometry
## (two discs at the grip markers), not part of the sword.
func test_the_hilt_is_the_handle_not_the_hands() -> void:
	var weapon := _rules.combatant(0).weapon
	var hand := _rules.combatant(0).fighter.hand_radius
	assert_eq(weapon.handle_radius, PhysicalBaseline.GRIP_HALF_WIDTH_M, "the hilt is the measured grip")
	assert_true(weapon.handle_radius < hand, "thinner than the fists around it")
	assert_true(SwordContactGeometry.has_feature(SwordContactSet.Feature.HILT, weapon), "and collidable")
	assert_false(weapon.protects(SwordContactSet.Feature.HILT), "but not steel that defends its wielder")
	assert_true(weapon.protects(SwordContactSet.Feature.GUARD) and weapon.protects(SwordContactSet.Feature.BLADE), "as the guard and the blade are")


## RIGID-CONTACT-001 passivity at a stop: a two-point line contact pressed
## while fighter 0's sword turns onto its guard stop. The stop is one row of
## the same LCP as both contact points — one model of the sword — so the
## solve only ever takes energy out and never sets the sword past its stop,
## turning either way. (A second, per-row lock on the stop once gave the
## sword two models in exactly this hold and added energy.)
func test_a_two_point_hold_on_a_stop_is_passive() -> void:
	for turning: float in [0.3, -0.3]:
		## ARRANGE: a held line contact, fighter 0's stop a milliradian away.
		var rules := DuelFixture.rules()
		var weapon := rules.combatant(0).weapon
		var state := _lying_along(rules, 2.0 * weapon.blade_radius - 0.0005)
		weapon.guard_limit = absf(state.fighter(0).weapon.angle) + 0.001
		state.blade_contact.begin_search()
		var geometry := SwordContactGeometry.new()
		_measure(state, rules, geometry)
		assert_eq(_record_touching(state, geometry), 2, "fixture: a line contact, two points")
		## PERTURB: pressed into the line, the sword driven at its stop.
		state.fighter(0).vy = -0.4
		state.fighter(0).weapon.speed = turning
		## ACT
		var audit := AuditedRigidSolver.new()
		audit.solve_velocity(state, rules, true)
		## ASSERT
		assert_eq(state.blade_contact.hold_count(), 2, "fixture (%+.1f rad/s): both points are held" % turning)
		assert_true(audit.stop_solves > 0, "fixture (%+.1f rad/s): the stop row is in the solve" % turning)
		assert_true(audit.worst_energy_gain <= 1.0e-9, "turning %+.1f rad/s the hold adds no energy (%s J)" % [turning, str(audit.worst_energy_gain)])
		assert_true(audit.worst_stop_overrun <= 1.0e-4, "and never turns past its stop (%s rad/s)" % str(audit.worst_stop_overrun))
