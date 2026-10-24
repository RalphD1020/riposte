extends TestCase

## ENTANGLE: the grip/handle disentanglement contract (GRIP-DISENTANGLE, audit
## 2026-10-22). The lower sword - the handle-side of the crossguard, the hands,
## and the arms - is modelled as a grip axis: the dominant-hand grip point back
## along the handle to the owner's torso ring, bounded there and never into the
## torso. The rule is narrow: two fighters' grip axes must not become entangled
## by crossing each other. It is completely separate from blade hit
## classification - the blade and the blade-hit regions are excluded, a blade
## reaching a torso is still a hit, and nothing here is a blocking hitbox.
##
## This suite is Phase 1: the deterministic detection primitives, their geometry
## contract, and a reachability probe over real combat. No production solver or
## replay-golden change is made here; a resolution constraint is an approved
## gameplay change only if the probe shows a reachable entanglement.
##
## See also: /docs/concepts/combat.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "ENTANGLE"
	_rules = StandardDuelRules.create()


## Signed area of the triangle a-b-c: >0 left of a->b, <0 right.
static func _orient(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)


## Two finite segments properly cross when each straddles the other's line.
static func _segments_cross(p0: Vector2, p1: Vector2, q0: Vector2, q1: Vector2) -> bool:
	var d1 := _orient(q0, q1, p0)
	var d2 := _orient(q0, q1, p1)
	var d3 := _orient(p0, p1, q0)
	var d4 := _orient(p0, p1, q1)
	return (d1 > 0.0) != (d2 > 0.0) and (d3 > 0.0) != (d4 > 0.0)


## The grip axis of a fighter in world space: the dominant-hand grip point (the
## top of the pass-through handle, just below the steel crossguard) back to the
## owner's torso ring along the handle-to-body direction. It never enters the
## torso - the far endpoint sits on the ring (`hurt_radius`) - and it carries no
## blade geometry.
func _grip_axis(state: MatchState, slot: int) -> Array:
	var spec := _rules.combatant(slot)
	var fighter := state.fighter(slot)
	var pose := WeaponKinematics.pose_of(fighter, spec, BladePose.new())
	var front := Vector2(pose.point_x(spec.weapon.dominant_grip_radius), pose.point_y(spec.weapon.dominant_grip_radius))
	var center := Vector2(fighter.x, fighter.y)
	var pommel := Vector2(pose.origin_x, pose.origin_y)
	var toward := pommel - center
	var back := center
	if toward.length() > 1.0e-9:
		back = center + toward.normalized() * spec.fighter.hurt_radius
	return [front, back]


## Whether the two fighters' grip axes cross right now.
func _grips_crossed(state: MatchState) -> bool:
	var a := _grip_axis(state, 0)
	var b := _grip_axis(state, 1)
	return _segments_cross(a[0], a[1], b[0], b[1])


## The detection primitive separates a real crossing from a close parallel pass:
## proximity alone is never a crossing, and an infinite-line intersection beyond
## the finite segments is not one either.
func test_the_crossing_primitive_is_finite_and_not_a_distance_rule() -> void:
	## Two segments that properly cross.
	assert_true(_segments_cross(Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)), "an X crosses")
	## Close parallel segments: never a crossing, however near.
	assert_false(_segments_cross(Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 0.001), Vector2(1, 0.001)), "a close parallel pass does not cross")
	## Their infinite lines meet far away, but the finite segments do not.
	assert_false(_segments_cross(Vector2(0, 0), Vector2(1, 0.001), Vector2(0, 1), Vector2(1, 1.001)), "a near-parallel pair whose lines meet far off does not cross")
	## A T-junction that stops short does not cross; extended, it does.
	assert_false(_segments_cross(Vector2(-1, 0), Vector2(1, 0), Vector2(0, 0.01), Vector2(0, 1)), "a segment ending above the line does not cross")
	assert_true(_segments_cross(Vector2(-1, 0), Vector2(1, 0), Vector2(0, -0.01), Vector2(0, 1)), "the same segment reaching across does")


## A swept crossing is caught between tick endpoints: a grip that is clear one
## tick and clear the next may still have crossed in between, so detection must
## test the motion, not only the endpoints. Sampling the swept path finds it.
func test_a_swept_crossing_is_caught_between_ticks() -> void:
	## A fixed horizontal axis; a short vertical bar that starts below it, sweeps
	## up through it, and ends above it one tick later - clear at both endpoints.
	var fixed_0 := Vector2(-1, 0)
	var fixed_1 := Vector2(1, 0)
	var start_0 := Vector2(0, -1.0)
	var start_1 := Vector2(0, -0.5)
	var end_0 := Vector2(0, 0.5)
	var end_1 := Vector2(0, 1.0)
	assert_false(_segments_cross(start_0, start_1, fixed_0, fixed_1), "clear before")
	assert_false(_segments_cross(end_0, end_1, fixed_0, fixed_1), "clear after")
	var crossed := false
	for step in 9:
		var t := float(step) / 8.0
		var s0 := start_0.lerp(end_0, t)
		var s1 := start_1.lerp(end_1, t)
		crossed = crossed or _segments_cross(s0, s1, fixed_0, fixed_1)
	assert_true(crossed, "sampling the swept path catches the crossing the endpoints miss")


## The grip axis never reaches into the torso: its far endpoint is on the hurt
## ring, so the projected line stops at the owner's hit box, as required.
func test_the_grip_axis_stops_at_the_torso_ring() -> void:
	var runner := SimRunner.create(_rules, 3)
	runner.skip_intro()
	for slot in 2:
		var axis := _grip_axis(runner.state, slot)
		var center := Vector2(runner.state.fighter(slot).x, runner.state.fighter(slot).y)
		var hurt := _rules.combatant(slot).fighter.hurt_radius
		assert_near((axis[1] as Vector2).distance_to(center), hurt, 1.0e-5, "slot %d: the axis ends on the torso ring" % slot)
		assert_true((axis[0] as Vector2).distance_to(center) > hurt, "slot %d: and its hand end is outside the torso" % slot)


## Detection is mirror symmetric: a crossing and its reflection are both found,
## so the rule carries no side bias.
func test_detection_is_mirror_symmetric() -> void:
	var a0 := Vector2(-1, -0.5)
	var a1 := Vector2(1, 0.5)
	var b0 := Vector2(-1, 0.5)
	var b1 := Vector2(1, -0.5)
	assert_eq(
		_segments_cross(a0, a1, b0, b1),
		_segments_cross(Vector2(a0.x, -a0.y), Vector2(a1.x, -a1.y), Vector2(b0.x, -b0.y), Vector2(b1.x, -b1.y)),
		"a crossing and its mirror are detected the same"
	)


## Reachability probe and the design lesson it teaches. A hard, close, mutual
## bind - both fighters pressing and winding into each other for two seconds -
## rests with the grip axes OVERLAPPING in the plan projection for most of the
## exchange, while every tick stays legal and combat continues. That is the
## audit's point made concrete: a static grip-axis crossing (or a minimum grip
## distance) is a legitimate close-combat state, not an entanglement, so a
## crossing/distance rule would wrongly constrain ordinary play. The real
## disentanglement rule must therefore be a swept thread-through (a hand
## actually passing through the opponent's axis), which is Phase 2 and gated on
## approval because it changes authoritative behaviour. This test pins the
## boundary: close overlaps happen in valid play and are never forced apart.
func test_a_static_grip_crossing_is_a_legitimate_close_combat_state() -> void:
	var guard := _rules.combatant(0).weapon.guard_angle
	var runner := SimRunner.create(_rules, 11)
	runner.skip_intro()
	var a := runner.state.fighter(0)
	var b := runner.state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, PI / 2.0)
	a.weapon.reset(guard)
	DuelFixture.place(b, 0.0, ContactFixture.crossed_guard_separation(_rules.combatant(0), -0.002, 1.0), -PI / 2.0)
	b.weapon.reset(-guard)
	var crossings := 0
	var closest_bodies := INF
	for t in 120:
		var cmd_a := PlayerCommand.create(runner.state.tick, 0.0, 1.0, t % 20 < 10, t % 20 == 9)
		var cmd_b := PlayerCommand.create(runner.state.tick, 0.0, 1.0, t % 20 < 10, t % 20 == 9)
		runner.push(cmd_a, cmd_b)
		closest_bodies = minf(closest_bodies, SimMath.length(runner.state.fighter(0).x - runner.state.fighter(1).x, runner.state.fighter(0).y - runner.state.fighter(1).y))
		if _grips_crossed(runner.state):
			crossings += 1
		assert_true(runner.is_sound(), "tick %d: a legal state" % t)
	assert_true(closest_bodies < _rules.combatant(0).fighter.push_radius + _rules.combatant(1).fighter.push_radius + 0.2, "fixture: the bodies were genuinely close (%.3f m)" % closest_bodies)
	## The grip axes overlap on most ticks of a legitimate bind - a crossing or
	## distance rule would over-constrain it, so proximity alone must never be
	## the trigger (the audit's central warning, encoded).
	assert_true(crossings > 20, "a legitimate hard bind rests with the grip axes overlapping (%d of 120 ticks), so a crossing/distance rule would wrongly fire" % crossings)
	## Then they come apart on ordinary retreat, with nothing held.
	for _t in 40:
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, -1.0), PlayerCommand.create(runner.state.tick, 0.0, -1.0))
	assert_false(_grips_crossed(runner.state), "and ordinary retreat parts the grips")
	assert_eq(runner.state.blade_contact.hold_count() + runner.state.blade_contact.point_count, 0, "with no stale blade hold")
	assert_true(runner.is_sound(), "every tick of the disengage is legal (%s)" % runner.violation_summary())
