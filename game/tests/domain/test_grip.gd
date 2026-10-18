extends TestCase

## GRIP: steel is blade on blade and each guard root against the other blade
## from its protected side, never guard on guard (STEEL-TOPOLOGY-001,
## GUARD-PROTECTION-001). Hands, the handle and the grip side of the crossguard
## are not combat geometry (TORSO-CIRCLE-001, rules 55): a blade that crosses
## only them meets nothing. The torso circle is the only damage target, and the
## blade capsule is the authoritative blade (BLADE-COLLISION-PARITY-001).
##
## Scenes are on the product Long Guard: fighter 1 at the origin facing +x with
## its sword at θ = 0; fighter 0's blade comes in square across fighter 1's
## sword, tip first, at a point `along` metres from its pommel, from `from` to
## `to` metres off that sword's axis.
##
## See also: /docs/reference/testing.md
## See also: /docs/concepts/combat.md

var _rules: DuelRules
var _live := {}


func _init() -> void:
	suite_name = "GRIP"
	_rules = DuelFixture.rules()


# ── fixtures ─────────────────────────────────────────────────────────────────


## The world point `along` metres down fighter 1's Long Guard sword from its
## pommel and `across` it (+ toward perp(û)).
func _on_sword(rules: DuelRules, along: float, across: float) -> Vector2:
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, rules.combatant(1), BladePose.new())
	return Vector2(held.point_x(along) - held.uy * across, held.point_y(along) + held.ux * across)


## Fighter 0's pose with its blade square across fighter 1's sword, its tip at
## (`along`, `across`) in fighter 1's sword frame.
func _square_pose(rules: DuelRules, along: float, across: float) -> FighterPose:
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, rules.combatant(1), BladePose.new())
	var direction := atan2(-held.ux, held.uy)
	var tip := _on_sword(rules, along, across)
	var reach := WeaponKinematics.pose_at(0.0, 0.0, direction, 0.0, rules.combatant(0), BladePose.new())
	var spec := rules.combatant(0)
	return ContactFixture.pose(tip.x - reach.point_x(spec.weapon.tip_radius), tip.y - reach.point_y(spec.weapon.tip_radius), direction, 0.0, spec)


## [start, finish] of a square cut at `along`, its tip `from` → `to` off the
## axis (fighter 1 standing).
func _square_cut(rules: DuelRules, along: float, from: float, to: float) -> Array:
	var target := ContactFixture.pose(0.0, 0.0, 0.0, 0.0, rules.combatant(1))
	return [
		ContactFixture.poses(_square_pose(rules, along, from), target),
		ContactFixture.poses(_square_pose(rules, along, to), target),
	]


## A state standing at `poses`, fighter 0 closing at `speed` (m/s) along its cut.
func _state_at(rules: DuelRules, poses: Array[FighterPose], speed: float) -> MatchState:
	var state := DuelFixture.state(rules)
	for slot in 2:
		DuelFixture.place(state.fighter(slot), poses[slot].x, poses[slot].y, poses[slot].facing)
		state.fighter(slot).weapon.angle = 0.0
	state.fighter(0).vx = cos(poses[0].facing) * speed
	state.fighter(0).vy = sin(poses[0].facing) * speed
	return state


## Stand fighter 0 at sweep fraction `s` between `start` and `finish` (the cut
## translates only).
func _seek(state: MatchState, start: Array[FighterPose], finish: Array[FighterPose], s: float) -> void:
	state.fighter(0).x = lerpf(start[0].x, finish[0].x, s)
	state.fighter(0).y = lerpf(start[0].y, finish[0].y, s)


## Surface gap from fighter 0's blade segment to a disc at `point`.
## Negative means the blade has entered the disc.
func _segment_gap(rules: DuelRules, poses: Array[FighterPose], point: Vector2, disc: float) -> float:
	var pose := WeaponKinematics.pose_at(poses[0].x, poses[0].y, poses[0].facing, 0.0, rules.combatant(0), BladePose.new())
	var weapon := rules.combatant(0).weapon
	var hx := pose.point_x(weapon.blade_base_radius)
	var hy := pose.point_y(weapon.blade_base_radius)
	var tx := pose.point_x(weapon.tip_radius)
	var ty := pose.point_y(weapon.tip_radius)
	var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, point.x, point.y)
	return Vector2(point.x - lerpf(hx, tx, t), point.y - lerpf(hy, ty, t)).length() - disc - weapon.blade_radius


## Surface gap from fighter 0's blade to fighter 1's torso circle.
func _torso_gap(rules: DuelRules, poses: Array[FighterPose]) -> float:
	return _segment_gap(rules, poses, Vector2(poses[1].x, poses[1].y), rules.combatant(1).fighter.hurt_radius)


## The blades' surface gap with the fighters at `poses`.
func _gaps(rules: DuelRules, poses: Array[FighterPose]) -> float:
	var a := WeaponKinematics.pose_at(poses[0].x, poses[0].y, poses[0].facing, 0.0, rules.combatant(0), BladePose.new())
	var b := WeaponKinematics.pose_at(poses[1].x, poses[1].y, poses[1].facing, 0.0, rules.combatant(1), BladePose.new())
	var weapon := rules.combatant(0).weapon
	return SwordContactGeometry.new().measure(poses[0].x, poses[0].y, a.origin_x, a.origin_y, a.ux, a.uy, b.origin_x, b.origin_y, b.ux, b.uy, weapon, rules.combatant(1).weapon)


func _count(events: Array[DuelEvent], type: StringName) -> int:
	return DuelFixture.of_type(events, type).size()


# ── STEEL-TOPOLOGY-001 ───────────────────────────────────────────────────────


## Steel is three pairs — blade on blade, and each sword's blade on the
## other's guard root — of at most two points each; there is no guard-on-guard
## pair, and the held solver has a row for every point the set can hold. A tip
## resting on the quillon from the blade's side is steel; the same tip under
## the quillon, on the grip side, or lying level with the bar itself is not;
## the same tip on the blade is.
func test_steel_is_the_blades_and_each_guard_on_its_protected_side() -> void:
	## ARRANGE
	var weapon := _rules.combatant(1).weapon
	var blade_r := _rules.combatant(0).weapon.blade_radius
	var touching := weapon.crossguard_radius + blade_r - 0.001
	var inside := weapon.crossguard_half_span * 0.8
	assert_true(weapon.crossguard_half_span > 3.0 * (weapon.crossguard_radius + blade_r), "fixture: the crossguard reaches well out past the blade (%.3f m)" % weapon.crossguard_half_span)
	## ACT: a tip on the quillon from above, from below and level with it, and
	## on the blade.
	var above := _square_cut(_rules, weapon.crossguard_centre_radius + touching, inside, inside)
	var below := _square_cut(_rules, weapon.crossguard_centre_radius - touching, inside, inside)
	var level := _square_cut(_rules, weapon.crossguard_centre_radius, inside, inside)
	var on_blade := _square_cut(_rules, (weapon.blade_base_radius + weapon.tip_radius) * 0.5, 2.0 * blade_r - 0.001, 2.0 * blade_r - 0.001)
	## ASSERT
	assert_eq(SwordContactSet.PAIRS, 3, "three pairs: blade on blade, and each blade on the other guard — never guard on guard")
	assert_eq(SwordContactSet.CAPACITY, SwordContactSet.PAIRS * SwordContactSet.POINTS_PER_PAIR, "at most two points a pair")
	assert_eq(RigidContactSolver.BLADE_ROWS, SwordContactSet.CAPACITY, "and the held solver a row for each")
	assert_eq(_side(above[0]), 1, "fixture: from above the tip comes from the protected side")
	assert_true(_gaps(_rules, above[0]) < 0.0, "a tip resting on the quillon from the blade's side is steel (%.4f m)" % _gaps(_rules, above[0]))
	assert_eq(_side(below[0]), -1, "fixture: from below it comes from the grip side")
	assert_true(_gaps(_rules, below[0]) > 0.0, "the same tip under the quillon is not steel (%.4f m)" % _gaps(_rules, below[0]))
	assert_eq(_side(level[0]), 0, "fixture: level with the bar it is within the bar's own thickness")
	assert_true(_gaps(_rules, level[0]) > 0.0, "and there it is never protection (%.4f m)" % _gaps(_rules, level[0]))
	assert_true(_gaps(_rules, on_blade[0]) < 0.0, "the same tip on the blade is steel (%.4f m)" % _gaps(_rules, on_blade[0]))


## Which side of fighter 1's guard fighter 0's blade comes from at `poses`.
func _side(poses: Array[FighterPose]) -> int:
	var a := WeaponKinematics.pose_at(poses[0].x, poses[0].y, poses[0].facing, 0.0, _rules.combatant(0), BladePose.new())
	var b := WeaponKinematics.pose_at(poses[1].x, poses[1].y, poses[1].facing, 0.0, _rules.combatant(1), BladePose.new())
	var blade := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	SwordContactGeometry.place(a.origin_x, a.origin_y, a.ux, a.uy, _rules.combatant(0).weapon, blade)
	return SwordContactGeometry.guard_side(b.origin_x, b.origin_y, b.ux, b.uy, _rules.combatant(1).weapon, blade)


## Two crossguards lying across each other, the blades well apart: guard on
## guard is never steel — no point, no gap — so two guards can never hook.
func test_two_crossguards_never_meet() -> void:
	## ARRANGE: fighter 1 in Long Guard at the origin; fighter 0's sword
	## pointing square across it, its bar laid over fighter 1's quillon.
	var weapon := _rules.combatant(1).weapon
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var bar_1 := Vector2(held.point_x(weapon.crossguard_centre_radius), held.point_y(weapon.crossguard_centre_radius))
	var square := WeaponKinematics.pose_at(0.0, 0.0, PI / 2.0, 0.0, _rules.combatant(0), BladePose.new())
	var bar_0 := Vector2(square.point_x(weapon.crossguard_centre_radius), square.point_y(weapon.crossguard_centre_radius))
	var wanted := bar_1 + Vector2(0.10, weapon.crossguard_half_span * 0.8)
	var poses := ContactFixture.poses(ContactFixture.pose(wanted.x - bar_0.x, wanted.y - bar_0.y, PI / 2.0, 0.0, _rules.combatant(0)), ContactFixture.pose(0.0, 0.0, 0.0, 0.0, _rules.combatant(1)))
	var a := WeaponKinematics.pose_at(poses[0].x, poses[0].y, poses[0].facing, 0.0, _rules.combatant(0), BladePose.new())
	var guard_0 := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var guard_1 := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	SwordContactGeometry.place_guard(a.origin_x, a.origin_y, a.ux, a.uy, weapon, guard_0)
	SwordContactGeometry.place_guard(held.origin_x, held.origin_y, held.ux, held.uy, weapon, guard_1)
	var bars := SegmentContact.new()
	SimMath.closest_segments(guard_0[0], guard_0[1], guard_0[2], guard_0[3], guard_1[0], guard_1[1], guard_1[2], guard_1[3], bars)
	assert_true(bars.distance < 2.0 * weapon.crossguard_radius, "fixture: the two crossbars lie across each other (%.4f m apart)" % bars.distance)
	## ACT
	var geometry := SwordContactGeometry.new()
	var b := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var gap := geometry.measure(poses[0].x, poses[0].y, a.origin_x, a.origin_y, a.ux, a.uy, b.origin_x, b.origin_y, b.ux, b.uy, weapon, weapon)
	## ASSERT
	assert_true(gap > 0.0 and _all_apart(geometry), "crossguard on crossguard is no steel (least steel gap %.4f m)" % gap)


## Handles and crossguards pass through each other. Two bars sharing a centre,
## blades parallel and a few centimetres apart, put each start cap in the
## other's guard corner from the protected side. That cap is hilt on hilt, so
## it is not steel. A tip on the quillon from the blade side still is. A
## handle laid through the other bar is not.
func test_hilts_pass_and_a_blade_still_meets_the_guard() -> void:
	## ARRANGE: same heading, bars overlapping, blades clear of each other.
	var weapon := _rules.combatant(1).weapon
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var bar_1 := Vector2(held.point_x(weapon.crossguard_centre_radius), held.point_y(weapon.crossguard_centre_radius))
	var beside := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(0), BladePose.new())
	var bar_0 := Vector2(beside.point_x(weapon.crossguard_centre_radius), beside.point_y(weapon.crossguard_centre_radius))
	var lateral := 0.06
	var poses := ContactFixture.poses(ContactFixture.pose(bar_1.x - bar_0.x, bar_1.y - bar_0.y + lateral, 0.0, 0.0, _rules.combatant(0)), ContactFixture.pose(0.0, 0.0, 0.0, 0.0, _rules.combatant(1)))
	var a := WeaponKinematics.pose_at(poses[0].x, poses[0].y, poses[0].facing, 0.0, _rules.combatant(0), BladePose.new())
	var b := WeaponKinematics.pose_at(poses[1].x, poses[1].y, poses[1].facing, 0.0, _rules.combatant(1), BladePose.new())
	var guard_0 := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var guard_1 := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	SwordContactGeometry.place_guard(a.origin_x, a.origin_y, a.ux, a.uy, weapon, guard_0)
	SwordContactGeometry.place_guard(b.origin_x, b.origin_y, b.ux, b.uy, weapon, guard_1)
	var bars := SegmentContact.new()
	SimMath.closest_segments(guard_0[0], guard_0[1], guard_0[2], guard_0[3], guard_1[0], guard_1[1], guard_1[2], guard_1[3], bars)
	assert_true(bars.distance < 2.0 * weapon.crossguard_radius, "fixture: the crossbars overlap (%.4f m)" % bars.distance)
	var blade_0 := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	SwordContactGeometry.place(a.origin_x, a.origin_y, a.ux, a.uy, weapon, blade_0)
	assert_eq(SwordContactGeometry.guard_side(b.origin_x, b.origin_y, b.ux, b.uy, weapon, blade_0), 1, "fixture: that blade comes from the protected side")
	## ACT
	var geometry := SwordContactGeometry.new()
	geometry.measure(poses[0].x, poses[0].y, a.origin_x, a.origin_y, a.ux, a.uy, b.origin_x, b.origin_y, b.ux, b.uy, weapon, weapon)
	## ASSERT
	assert_eq(_start_cap_guards(geometry), 0, "a start cap in the other hilt is not steel")
	var touching := weapon.crossguard_radius + weapon.blade_radius - 0.001
	var inside := weapon.crossguard_half_span * 0.8
	var on_guard: Array = _square_cut(_rules, weapon.crossguard_centre_radius + touching, inside, inside)[0]
	assert_true(_gaps(_rules, on_guard) < 0.0, "a tip on the quillon from the blade side is still steel")
	var handle := _handle_through_bar()
	assert_true(_gaps(_rules, handle) > 0.0, "a handle through the other bar is not steel (%.4f m)" % _gaps(_rules, handle))


## The mutual start-cap drop is the same whichever sword is named first.
## A tip on the blade-side quillon, a grip-side miss, and blade on blade stay
## steel or stay clear. `START_CAP` is not widened here.
func test_the_mutual_cap_is_symmetric_and_one_sided_blocks_stay() -> void:
	## ARRANGE + ACT: overlapped hilts at several headings and offsets.
	var weapon := _rules.combatant(1).weapon
	var overlapped := 0
	for heading: float in PackedFloat64Array([0.0, PI / 6.0, PI / 2.0, PI]):
		for lateral: float in PackedFloat64Array([0.0, 0.03, 0.06, 0.10]):
			var poses: Array = _hilt_poses(heading, lateral)
			if _bar_gap(poses) >= 2.0 * weapon.crossguard_radius:
				continue
			overlapped += 1
			var forward := _geometry(poses)
			var swapped := _geometry_swapped(poses)
			## ASSERT
			assert_eq(_start_cap_guards(forward), 0, "start caps are not steel (heading %.3f, offset %.2f)" % [heading, lateral])
			assert_eq(_start_cap_guards(swapped), 0, "either naming of the pair (heading %.3f, offset %.2f)" % [heading, lateral])
			assert_eq(_touching(forward), _touching(swapped), "the same number of contacts survive either order (heading %.3f, offset %.2f)" % [heading, lateral])
	assert_true(overlapped >= 4, "fixture: several overlapped hilt poses were measured (%d)" % overlapped)
	var reach := weapon.crossguard_radius + weapon.blade_radius - 0.001
	var inside := weapon.crossguard_half_span * 0.8
	var on_guard: Array = _square_cut(_rules, weapon.crossguard_centre_radius + reach, inside, inside)[0]
	var below: Array = _square_cut(_rules, weapon.crossguard_centre_radius - reach, inside, inside)[0]
	var on_blade: Array = _square_cut(_rules, (weapon.blade_base_radius + weapon.tip_radius) * 0.5, 2.0 * weapon.blade_radius - 0.001, 2.0 * weapon.blade_radius - 0.001)[0]
	var struck := _geometry(on_guard)
	var struck_swap := _geometry_swapped(on_guard)
	assert_true(_guard_touches(struck) > 0, "a tip on the blade-side quillon is steel")
	assert_true(_guard_touches(struck_swap) > 0, "and still steel when the swords are named the other way")
	assert_eq(_start_cap_guards(struck), 0, "that block is the tip, not the start cap")
	assert_eq(_start_cap_guards(struck_swap), 0, "and not the start cap the other way")
	assert_eq(_guard_touches(_geometry(below)), 0, "the grip side of the same bar is not steel")
	assert_true(_blade_touches(_geometry(on_blade)) > 0, "blade on blade stays steel")


func _hilt_poses(heading: float, lateral: float) -> Array:
	var weapon := _rules.combatant(1).weapon
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var bar_1 := Vector2(held.point_x(weapon.crossguard_centre_radius), held.point_y(weapon.crossguard_centre_radius))
	var other := WeaponKinematics.pose_at(0.0, 0.0, heading, 0.0, _rules.combatant(0), BladePose.new())
	var bar_0 := Vector2(other.point_x(weapon.crossguard_centre_radius), other.point_y(weapon.crossguard_centre_radius))
	return ContactFixture.poses(ContactFixture.pose(bar_1.x - bar_0.x, bar_1.y - bar_0.y + lateral, heading, 0.0, _rules.combatant(0)), ContactFixture.pose(0.0, 0.0, 0.0, 0.0, _rules.combatant(1)))


func _bar_gap(poses: Array) -> float:
	var weapon := _rules.combatant(1).weapon
	var a := WeaponKinematics.pose_at(poses[0].x, poses[0].y, poses[0].facing, 0.0, _rules.combatant(0), BladePose.new())
	var b := WeaponKinematics.pose_at(poses[1].x, poses[1].y, poses[1].facing, 0.0, _rules.combatant(1), BladePose.new())
	var guard_0 := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var guard_1 := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	SwordContactGeometry.place_guard(a.origin_x, a.origin_y, a.ux, a.uy, weapon, guard_0)
	SwordContactGeometry.place_guard(b.origin_x, b.origin_y, b.ux, b.uy, weapon, guard_1)
	var bars := SegmentContact.new()
	SimMath.closest_segments(guard_0[0], guard_0[1], guard_0[2], guard_0[3], guard_1[0], guard_1[1], guard_1[2], guard_1[3], bars)
	return bars.distance


func _geometry(poses: Array) -> SwordContactGeometry:
	return _geometry_ordered(poses[0], poses[1], _rules.combatant(0), _rules.combatant(1))


func _geometry_swapped(poses: Array) -> SwordContactGeometry:
	return _geometry_ordered(poses[1], poses[0], _rules.combatant(1), _rules.combatant(0))


func _geometry_ordered(first: FighterPose, second: FighterPose, spec_a: CombatantPhysicsSpec, spec_b: CombatantPhysicsSpec) -> SwordContactGeometry:
	var a := WeaponKinematics.pose_at(first.x, first.y, first.facing, 0.0, spec_a, BladePose.new())
	var b := WeaponKinematics.pose_at(second.x, second.y, second.facing, 0.0, spec_b, BladePose.new())
	var geometry := SwordContactGeometry.new()
	geometry.measure(first.x, first.y, a.origin_x, a.origin_y, a.ux, a.uy, b.origin_x, b.origin_y, b.ux, b.uy, spec_a.weapon, spec_b.weapon)
	return geometry


static func _touching(geometry: SwordContactGeometry) -> int:
	var found := 0
	for point in geometry.count:
		if geometry.point_gap[point] <= 0.0:
			found += 1
	return found


static func _blade_touches(geometry: SwordContactGeometry) -> int:
	var found := 0
	for point in geometry.count:
		if geometry.point_gap[point] <= 0.0 and geometry.point_pair[point] == SwordContactSet.PAIR_BLADES:
			found += 1
	return found


static func _guard_touches(geometry: SwordContactGeometry) -> int:
	var found := 0
	for point in geometry.count:
		var pair := geometry.point_pair[point]
		if geometry.point_gap[point] <= 0.0 and (pair == SwordContactSet.PAIR_BLADE_ON_GUARD or pair == SwordContactSet.PAIR_GUARD_ON_BLADE):
			found += 1
	return found


## Guard-pair points whose blade point is the start cap and which overlap.
func _start_cap_guards(geometry: SwordContactGeometry) -> int:
	var found := 0
	for point in geometry.count:
		var pair := geometry.point_pair[point]
		if pair == SwordContactSet.PAIR_BLADES or geometry.point_gap[point] > 0.0:
			continue
		var x := geometry.point_bx[point]
		var y := geometry.point_by[point]
		var sx := geometry.blade_b[0]
		var sy := geometry.blade_b[1]
		if pair == SwordContactSet.PAIR_BLADE_ON_GUARD:
			x = geometry.point_ax[point]
			y = geometry.point_ay[point]
			sx = geometry.blade_a[0]
			sy = geometry.blade_a[1]
		if SimMath.length(x - sx, y - sy) <= SwordContactGeometry.START_CAP:
			found += 1
	return found


## Fighter 0's handle laid across fighter 1's bar, its blade pointing away
## from that bar so the start cap is not the thing in the guard.
func _handle_through_bar() -> Array[FighterPose]:
	var weapon := _rules.combatant(1).weapon
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var bar := Vector2(held.point_x(weapon.crossguard_centre_radius), held.point_y(weapon.crossguard_centre_radius))
	var facing := PI / 2.0
	var away := WeaponKinematics.pose_at(0.0, 0.0, facing, 0.0, _rules.combatant(0), BladePose.new())
	var along := weapon.dominant_grip_radius * 0.5
	var grip := Vector2(away.point_x(along), away.point_y(along))
	return ContactFixture.poses(ContactFixture.pose(bar.x - grip.x, bar.y - grip.y, facing, 0.0, _rules.combatant(0)), ContactFixture.pose(0.0, 0.0, 0.0, 0.0, _rules.combatant(1)))


static func _all_apart(geometry: SwordContactGeometry) -> bool:
	for point in geometry.count:
		if geometry.point_gap[point] <= 0.0:
			return false
	return true


## The guard root is a deliberate approximation, and its envelope is pinned:
## how far its steel reaches beyond the drawn sword (the crossbar and the
## blade, at their own thickness, as the authored model has them) — at most
## the bar's own half-depth, its rounded edge, which is what the root's rise is
## derived from — and nowhere on the grip side of the bar. (A first rules-52
## root rose half its half-span with edges at the blade's thickness and stood
## out 5.4 cm in the corner: steel the player cannot see.)
func test_the_guard_root_reaches_no_further_than_its_corner() -> void:
	## ARRANGE
	var weapon := _rules.combatant(1).weapon
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var guard := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	assert_true(SwordContactGeometry.place_guard(held.origin_x, held.origin_y, held.ux, held.uy, weapon, guard), "fixture: the product sword has a crossguard")
	var bar := SegmentContact.new()
	var blade := SegmentContact.new()
	var worst := 0.0
	var lowest := INF
	## ACT: along both slanted edges, how far the root's surface stands out
	## beyond the nearer of the drawn bar and the drawn blade.
	for edge: Array in [[2, 4], [4, 0]]:
		for k in 201:
			var t := float(k) / 200.0
			var px := lerpf(guard[edge[0]], guard[edge[1]], t)
			var py := lerpf(guard[edge[0] + 1], guard[edge[1] + 1], t)
			SimMath.closest_segments(px, py, px, py, guard[0], guard[1], guard[2], guard[3], bar)
			SimMath.closest_segments(px, py, px, py, held.point_x(weapon.blade_base_radius), held.point_y(weapon.blade_base_radius), held.point_x(weapon.tip_radius), held.point_y(weapon.tip_radius), blade)
			var beyond := minf(bar.distance - weapon.crossguard_radius, blade.distance - weapon.blade_radius) + weapon.crossguard_radius
			worst = maxf(worst, beyond)
			lowest = minf(lowest, (px - held.origin_x) * held.ux + (py - held.origin_y) * held.uy)
	## ASSERT
	assert_true(worst > 0.0, "fixture: the root does fill the corner (%.4f m)" % worst)
	assert_true(worst <= weapon.crossguard_radius + 1.0e-9, "the root's steel stands out at most the bar's half-depth beyond the drawn sword (%.4f m, half-depth %.4f m)" % [worst, weapon.crossguard_radius])
	assert_true(lowest >= weapon.crossguard_centre_radius - 1.0e-9, "and none of it lies on the grip side of the bar (lowest %.4f m, bar at %.4f m)" % [lowest, weapon.crossguard_centre_radius])


## Two wandering duels, every live tick read once for the suite: steel ticks,
## the most points or held rows ever, the farthest a point strays off either
## blade, soundness, and every event.
func _live_duels() -> Dictionary:
	if not _live.is_empty():
		return _live
	var held := 0
	var guarded := 0
	var crowded := 0
	var most := 0
	var outside := 0.0
	var sound := true
	var events: Array[DuelEvent] = []
	for seed_value: int in [3, 5, 9]:
		var runner := SimRunner.create(_rules, seed_value)
		var pilots: Array[Pilot] = [Pilot.wander(seed_value, 11), Pilot.wander(seed_value, 23)]
		for _tick in 1800:
			if runner.state.is_finished():
				break
			runner.push(pilots[0].command(runner.state, 0), pilots[1].command(runner.state, 1))
			var contact := runner.state.blade_contact
			if runner.state.phase != MatchPhase.Id.ROUND_ACTIVE:
				continue
			most = maxi(most, maxi(contact.point_count, contact.hold_count()))
			held += 1 if contact.point_count > 0 else 0
			guarded += 1 if _any_guard_point(contact) else 0
			crowded += 1 if _most_in_a_pair(contact) > SwordContactSet.POINTS_PER_PAIR else 0
			for point in contact.point_count:
				outside = maxf(outside, maxf(absf(contact.fraction_a[point] - SimMath.clamp01(contact.fraction_a[point])), absf(contact.fraction_b[point] - SimMath.clamp01(contact.fraction_b[point]))))
		sound = sound and runner.is_sound()
		events.append_array(runner.events)
	_live = {"held": held, "guarded": guarded, "crowded": crowded, "most": most, "outside": outside, "sound": sound, "events": events}
	return _live


static func _any_guard_point(contact: SwordContactSet) -> bool:
	for point in contact.point_count:
		if contact.pair[point] != SwordContactSet.PAIR_BLADES:
			return true
	return false


static func _most_in_a_pair(contact: SwordContactSet) -> int:
	var counts := PackedInt32Array([0, 0, 0])
	for point in contact.point_count:
		counts[contact.pair[point]] += 1
	return maxi(counts[0], maxi(counts[1], counts[2]))


## Every manifold live play produces is at most two points a steel pair and
## never more than the set holds, each at a place along both blades (a guard
## point at the guard's own fraction, 0), and the solver never holds more.
func test_live_manifolds_are_two_points_a_pair_at_most() -> void:
	## ARRANGE + ACT: the live duels, every tick read.
	var live := _live_duels()
	## ASSERT
	assert_true(int(live["held"]) > 50, "fixture: the duels touch steel (%d ticks)" % int(live["held"]))
	assert_true(int(live["guarded"]) > 0, "fixture: and a guard root among it (%d ticks)" % int(live["guarded"]))
	assert_true(int(live["most"]) <= SwordContactSet.CAPACITY, "no manifold or hold record ever has more points than the set holds (%d)" % int(live["most"]))
	assert_eq(int(live["crowded"]), 0, "nor more than two in any one pair")
	assert_eq(float(live["outside"]), 0.0, "each at a place along both blades")
	assert_true(bool(live["sound"]), "every tick legal")


## PARRY-001 / CONTACT-OUTCOME-001 from the other side: a parry is only ever a
## reading of a solved steel contact. In the live duels every PARRY lands on a
## tick with a BLADE_CONTACT (blade on blade, or a blade on a guard root from
## its protected side) whose attacker is the parried fighter and whose
## solve arrested that fighter's cut, and the parrier is the other fighter —
## no parry without the steel that made it, and no grip ever makes one.
## Rules 56: seeds 3, 5 and 9 parry four times between them. The floor is the
## sample, not the law.
func test_every_parry_is_an_arrested_steel_contact() -> void:
	## ARRANGE + ACT: the live duels' events.
	var events: Array[DuelEvent] = _live_duels()["events"]
	var parries := 0
	var unexplained := PackedStringArray()
	for event in events:
		if event.type != DuelEventTypes.PARRY:
			continue
		parries += 1
		var explained := false
		for clash in events:
			if clash.type != DuelEventTypes.BLADE_CONTACT or clash.tick != event.tick or clash.actor != event.target:
				continue
			var arrested := DuelEventKeys.ARRESTED_0 if event.target == 0 else DuelEventKeys.ARRESTED_1
			explained = explained or (bool(clash.data[arrested]) and event.actor == 1 - event.target)
		if not explained:
			unexplained.append("tick %d" % event.tick)
	## ASSERT
	assert_true(parries >= 4, "fixture: the duels parry (%d)" % parries)
	assert_eq(unexplained.size(), 0, "every parry is an arrested steel contact (%s)" % ", ".join(unexplained))


# ── BLADE-COLLISION-PARITY-001 ───────────────────────────────────────────────


## The rigid capsule is the authoritative blade: its ends are the posed
## blade's own points (the guard root's apex and the point), and the contact
## points it finds are points of the posed blades at their fractions — read
## back by projection on the pose's own direction — on the curved attack
## track, every θ and φ.
func test_the_blade_capsule_is_the_authoritative_blade() -> void:
	## ARRANGE
	var spec := _rules.combatant(0)
	var weapon := spec.weapon
	assert_false(spec.handling.attack_path.is_fixed(), "fixture: the product sword rides a curved track")
	var segment := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var geometry := SwordContactGeometry.new()
	var pose_a := BladePose.new()
	var pose_b := BladePose.new()
	var ends := 0.0
	var points := 0.0
	var touched := 0
	for theta: float in [-weapon.guard_limit, -1.2, -0.45, 0.0, 0.3, 0.9, weapon.guard_limit]:
		for phi: float in [0.0, 0.7, -2.4]:
			## ACT: the capsule placed on the authoritative pose.
			WeaponKinematics.pose_at(0.3, -0.2, phi, theta, spec, pose_a)
			SwordContactGeometry.place(pose_a.origin_x, pose_a.origin_y, pose_a.ux, pose_a.uy, weapon, segment)
			ends = maxf(ends, maxf(
				SimMath.length(segment[0] - pose_a.point_x(weapon.guard_root_apex_radius()), segment[1] - pose_a.point_y(weapon.guard_root_apex_radius())),
				SimMath.length(segment[2] - pose_a.point_x(weapon.tip_radius), segment[3] - pose_a.point_y(weapon.tip_radius))
			))
			## A second sword crossing this one at mid-blade, touching.
			var r := (weapon.blade_base_radius + weapon.tip_radius) * 0.5
			var mid := Vector2(pose_a.point_x(r), pose_a.point_y(r))
			var across := phi + theta + PI / 2.0
			var lift := 2.0 * weapon.blade_radius - 0.001
			var rest := WeaponKinematics.pose_at(0.0, 0.0, across, 0.0, spec, BladePose.new())
			var bx := mid.x - pose_a.uy * lift - rest.point_x(r)
			var by := mid.y + pose_a.ux * lift - rest.point_y(r)
			WeaponKinematics.pose_at(bx, by, across, 0.0, spec, pose_b)
			if geometry.measure(0.3, -0.2, pose_a.origin_x, pose_a.origin_y, pose_a.ux, pose_a.uy, pose_b.origin_x, pose_b.origin_y, pose_b.ux, pose_b.uy, weapon, weapon) > 0.0:
				continue
			touched += 1
			var along_a := SimMath.mix(weapon.blade_base_radius, weapon.tip_radius, geometry.fraction_a)
			var along_b := SimMath.mix(weapon.blade_base_radius, weapon.tip_radius, geometry.fraction_b)
			points = maxf(points, maxf(
				SimMath.length(geometry.ax - pose_a.point_x(along_a), geometry.ay - pose_a.point_y(along_a)),
				SimMath.length(geometry.bx - pose_b.point_x(along_b), geometry.by - pose_b.point_y(along_b))
			))
	## ASSERT
	assert_true(touched >= 15, "fixture: the crossing touches at almost every pose (%d)" % touched)
	assert_eq(ends, 0.0, "the capsule's ends are the posed blade's own points")
	assert_true(points <= 1.0e-12, "the contact points are points of the posed blades at their fractions (%s m)" % String.num_scientific(points))


## The velocity a blade point is solved with is the motion the sweep carries
## it through: `WeaponKinematics.velocity_into` against a central difference
## of `pose_at`, at every 0.5° sample of the attack track and every midpoint
## between, at the blade's base, middle and tip, turning and walking. Measured
## worst at rules 51: 7.3e-6 relative, at the centreline; the bound is 1e-4.
## The root-pivot stick — rotation about the body with no track — misses the
## same motion by 0.21 or more, so the bound tells the two apart a thousandfold.
func test_a_blade_point_moves_as_the_sweep_moves_it() -> void:
	## ARRANGE
	var spec := _rules.combatant(0)
	var weapon := spec.weapon
	var path := spec.handling.attack_path
	assert_false(path.is_fixed(), "fixture: the product sword rides a curved track")
	var h := 1.0e-6
	var step := WeaponAttackPath.DEFAULT_STEP * 0.5
	var worst := 0.0
	var stick := INF
	var samples := 0
	var theta := -weapon.guard_limit + step
	while theta < weapon.guard_limit - step:
		for phi: float in [0.0, -2.4]:
			for along: float in [weapon.blade_base_radius, (weapon.blade_base_radius + weapon.tip_radius) * 0.5, weapon.tip_radius]:
				for motion: Vector4 in [Vector4(0.8, -0.5, 1.1, 6.0), Vector4(-1.2, 0.4, -0.6, -14.0)]:
					var fighter := FighterState.new()
					DuelFixture.place(fighter, 0.3, -0.2, phi)
					fighter.weapon.angle = theta
					fighter.vx = motion.x
					fighter.vy = motion.y
					fighter.turn_rate = motion.z
					fighter.weapon.speed = motion.w
					## ACT
					var pose := WeaponKinematics.pose_at(0.3, -0.2, phi, theta, spec, BladePose.new())
					var px := pose.point_x(along)
					var py := pose.point_y(along)
					WeaponKinematics.velocity_into(fighter, pose, px, py)
					var ahead := WeaponKinematics.pose_at(0.3 + motion.x * h, -0.2 + motion.y * h, phi + motion.z * h, theta + motion.w * h, spec, BladePose.new())
					var behind := WeaponKinematics.pose_at(0.3 - motion.x * h, -0.2 - motion.y * h, phi - motion.z * h, theta - motion.w * h, spec, BladePose.new())
					var swept := Vector2(ahead.point_x(along) - behind.point_x(along), ahead.point_y(along) - behind.point_y(along)) / (2.0 * h)
					var scale := maxf(swept.length(), 1.0)
					worst = maxf(worst, (Vector2(pose.vx, pose.vy) - swept).length() / scale)
					var omega := motion.z + motion.w
					var pivot := Vector2(motion.x - omega * (py - fighter.y), motion.y + omega * (px - fighter.x))
					stick = minf(stick, (pivot - swept).length() / scale)
					samples += 1
		theta += step
	## ASSERT
	assert_true(samples > 10000, "fixture: every sample and midpoint of the track (%d)" % samples)
	assert_true(worst <= 1.0e-4, "a blade point moves as the sweep moves it (%s relative)" % String.num_scientific(worst))
	assert_true(stick > 1000.0 * 1.0e-4, "and the root-pivot stick would not (%s relative at best)" % String.num_scientific(stick))


# ── TORSO-CIRCLE-001 ─────────────────────────────────────────────────────────


## A swept cut through a hand or the handle, clear of the blade and of the
## torso circle, is not a contact. No report, no row, no impulse, no parry,
## no wound, and health does not move.
func test_a_blade_through_a_hand_or_the_handle_meets_nothing() -> void:
	var weapon := _rules.combatant(1).weapon
	var blade := _rules.combatant(0).weapon.blade_radius
	var hand_r := _rules.combatant(1).fighter.hand_radius
	var hand := hand_r + blade
	var handle := weapon.handle_radius + blade
	var parts := {
		"off hand": [weapon.offhand_grip_radius, hand + 0.01, hand - 0.005],
		"dominant hand": [weapon.dominant_grip_radius, hand + 0.01, hand - 0.005],
		"handle": [(weapon.offhand_grip_radius + weapon.dominant_grip_radius) * 0.5, handle + 0.01, handle - 0.005],
		"pommel": [-0.005, handle + 0.01, handle - 0.008],
	}
	for part: String in parts:
		## ARRANGE: the cut closes at 3 m/s, from outside the part to inside it.
		var cut: Array = parts[part]
		var ends := _square_cut(_rules, float(cut[0]), float(cut[1]), float(cut[2]))
		var start: Array[FighterPose] = ends[0]
		var finish: Array[FighterPose] = ends[1]
		var state := _state_at(_rules, finish, 3.0)
		var centre := _on_sword(_rules, float(cut[0]), 0.0)
		var disc := hand_r if part != "handle" and part != "pommel" else weapon.handle_radius
		assert_true(_segment_gap(_rules, start, centre, disc) > 0.0, "%s fixture: the blade starts outside that disc" % part)
		assert_true(_segment_gap(_rules, finish, centre, disc) < 0.0, "%s fixture: and finishes inside it" % part)
		assert_true(_torso_gap(_rules, start) > 0.0 and _torso_gap(_rules, finish) > 0.0, "%s fixture: both ends stay outside the torso circle" % part)
		assert_true(_gaps(_rules, finish) > 0.0, "%s fixture: clear of the blade" % part)
		var before := state.fighter(1).health
		## ACT
		var report := ContactReport.new()
		var collision := CollisionSystem.new()
		state.blade_contact.begin_search()
		collision.detect(state, start, finish, _rules, state.blade_contact, report)
		var events: Array[DuelEvent] = []
		ContactResolver.resolve(state, report, _rules, 1, report.fraction, events)
		var held := RigidContactSolver.new().solve_velocity(state, _rules, true)
		## ASSERT
		assert_false(report.any(), "%s: the sweep meets nothing" % part)
		assert_false(report.body[0] or report.body[1] or report.blade, "%s: neither torso nor steel" % part)
		assert_eq(state.blade_contact.point_count, 0, "%s: no contact point" % part)
		assert_eq(_count(events, DuelEventTypes.BODY_HIT) + _count(events, DuelEventTypes.BLADE_CONTACT) + _count(events, DuelEventTypes.PARRY), 0, "%s: no wound, blade contact or parry" % part)
		assert_eq(held, 0.0, "%s: nothing to hold" % part)
		assert_eq(state.blade_contact.hold_count(), 0, "%s: and no hold is recorded" % part)
		assert_eq(state.fighter(1).health, before, "%s: health is unchanged" % part)


## A cut laid along the crossbar's own line is never protected
## (GUARD-PROTECTION-001: within the bar's thickness is no side). The same
## cut a few centimetres toward the pommel, through the dominant hand, is
## not a contact either (TORSO-CIRCLE-001).
func test_a_cut_along_the_crossbar_is_never_protected() -> void:
	## ARRANGE: across the quillon, from outside it to the far side of the bar.
	var weapon := _rules.combatant(1).weapon
	var blade := _rules.combatant(0).weapon.blade_radius
	var reach := weapon.crossguard_radius + blade
	var ends := _square_cut(_rules, weapon.crossguard_centre_radius, weapon.crossguard_half_span + reach + 0.01, weapon.crossguard_half_span * 0.4)
	var start: Array[FighterPose] = ends[0]
	var finish: Array[FighterPose] = ends[1]
	var state := _state_at(_rules, finish, 3.0)
	assert_true(_gaps(_rules, finish) > 0.0, "fixture: the cut never reaches the blade")
	var hand := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var dominant := Vector2(hand.point_x(weapon.dominant_grip_radius), hand.point_y(weapon.dominant_grip_radius))
	assert_true(_on_sword(_rules, weapon.crossguard_centre_radius, weapon.crossguard_half_span * 0.4).distance_to(dominant) > _rules.combatant(1).fighter.hand_radius + blade, "fixture: nor a hand")
	## ACT
	var report := ContactReport.new()
	var collision := CollisionSystem.new()
	state.blade_contact.begin_search()
	collision.detect(state, start, finish, _rules, state.blade_contact, report)
	var held := RigidContactSolver.new().solve_velocity(state, _rules, true)
	## PERTURB: the same cut, onto the dominant hand.
	var into_hand := _rules.combatant(1).fighter.hand_radius + blade - 0.005
	var hit := _square_cut(_rules, weapon.dominant_grip_radius, weapon.crossguard_half_span + reach + 0.01, into_hand)
	var control := ContactReport.new()
	var other := CollisionSystem.new()
	var control_state := _state_at(_rules, hit[1], 3.0)
	control_state.blade_contact.begin_search()
	other.detect(control_state, hit[0], hit[1], _rules, control_state.blade_contact, control)
	## ASSERT
	assert_false(report.any(), "across the crossguard the sweep meets nothing")
	assert_eq(state.blade_contact.point_count + state.blade_contact.hold_count(), 0, "and nothing is held")
	assert_eq(held, 0.0, "the held solve has no row")
	assert_false(control.any(), "the same cut through the hand is not a contact either")
	assert_eq(control_state.fighter(1).health, state.fighter(1).health, "and it does not wound")


## A blade resting across the opponent's handle is no sword contact and no
## constraint: drawing the handle out from under it moves neither fighter.
func test_a_blade_across_a_handle_drags_nothing() -> void:
	var weapon := _rules.combatant(1).weapon
	for draw: Vector2 in [Vector2(-0.025, 0.0), Vector2(0.0, -0.025)]:
		## ARRANGE: fighter 0's blade lying square across fighter 1's handle,
		## between the hands; fighter 1 drawing its sword out from under it.
		var resting := _square_pose(_rules, (weapon.offhand_grip_radius + weapon.dominant_grip_radius) * 0.5, -0.3)
		var target := ContactFixture.pose(0.0, 0.0, 0.0, 0.0, _rules.combatant(1))
		var start := ContactFixture.poses(resting, target)
		var finish := ContactFixture.poses(resting, ContactFixture.pose(draw.x, draw.y, 0.0, 0.0, _rules.combatant(1)))
		var state := _state_at(_rules, start, 0.0)
		state.fighter(1).vx = draw.x * float(SimulationTimebase.TICK_RATE)
		state.fighter(1).vy = draw.y * float(SimulationTimebase.TICK_RATE)
		assert_true(_gaps(_rules, start) > 0.0 and _gaps(_rules, finish) > 0.0, "fixture: clear of the blade throughout")
		var before_health := state.fighter(1).health
		var before := [state.fighter(0).x, state.fighter(0).y, state.fighter(0).vx, state.fighter(0).vy, state.fighter(0).weapon.speed, state.fighter(1).vx, state.fighter(1).vy, state.fighter(1).weapon.speed]
		## ACT
		var report := ContactReport.new()
		var collision := CollisionSystem.new()
		state.blade_contact.begin_search()
		collision.detect(state, start, finish, _rules, state.blade_contact, report)
		var solver := RigidContactSolver.new()
		var held := solver.solve_velocity(state, _rules, true)
		solver.project(state, _rules)
		var after := [state.fighter(0).x, state.fighter(0).y, state.fighter(0).vx, state.fighter(0).vy, state.fighter(0).weapon.speed, state.fighter(1).vx, state.fighter(1).vy, state.fighter(1).weapon.speed]
		## ASSERT
		assert_false(report.any(), "drawn %s: the sweep meets nothing" % str(draw))
		assert_false(report.body[0] or report.body[1], "drawn %s: not a torso hit" % str(draw))
		assert_eq(state.blade_contact.point_count + state.blade_contact.hold_count(), 0, "drawn %s: and nothing is held" % str(draw))
		assert_eq(held, 0.0, "drawn %s: the held solve has no row" % str(draw))
		assert_eq(after, before, "drawn %s: neither fighter is pulled, pushed or turned" % str(draw))
		assert_eq(state.fighter(1).health, before_health, "drawn %s: and nobody is wounded" % str(draw))


## A cut that meets the blade and would have gone on into the handle reports
## the steel and not a body hit. The handle behind the blade is not a wound.
func test_steel_met_before_the_handle_is_not_a_body_hit() -> void:
	var weapon := _rules.combatant(1).weapon
	var blade := _rules.combatant(0).weapon.blade_radius
	var below := 0.015
	var along := weapon.blade_base_radius - below
	var steel := sqrt(pow(weapon.blade_radius + blade, 2.0) - below * below)
	var handle := weapon.handle_radius + blade
	var target := ContactFixture.pose(0.0, 0.0, 0.0, 0.0, _rules.combatant(1))
	var from := steel + 0.003
	var to := handle - 0.004
	var start := ContactFixture.poses(_square_pose(_rules, along, from), target)
	var finish := ContactFixture.poses(_square_pose(_rules, along, to), target)
	var onward := ContactFixture.poses(_square_pose(_rules, along, to - 0.02), target)
	assert_true(_gaps(_rules, start) > 0.0, "fixture: clear of steel at the start")
	assert_true(_gaps(_rules, finish) < 0.0, "fixture: into the blade by the end")
	var state := _state_at(_rules, start, 3.0)
	var before := state.fighter(1).health
	var collision := CollisionSystem.new()
	state.blade_contact.begin_search()
	var first := ContactReport.new()
	collision.detect(state, start, finish, _rules, state.blade_contact, first)
	var rest := ContactReport.new()
	collision.detect(state, finish, onward, _rules, state.blade_contact, rest)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, first, _rules, 1, first.fraction, events)
	assert_true(first.blade, "the blade is the contact")
	assert_false(first.body[0] or first.body[1], "and it is not a torso hit")
	assert_false(rest.body[0] or rest.body[1], "continuing through the handle still is not")
	assert_eq(_count(events, DuelEventTypes.BODY_HIT), 0, "no body wound is emitted")
	assert_eq(state.fighter(1).health, before, "health is unchanged by the steel alone in this pose")


## The off hand sits outside the torso. A square cut crosses that disc while
## the torso gap and the steel gap stay positive, and wounds nothing. The same
## blade, kept square, then translates in through the circle: one torso entry,
## at the crossing rather than at the overlapped end, and a further sweep that
## stays inside does not wound again. Exit and a later re-entry are CONTACT's
## lifecycle witness (COMBAT-007).
func test_a_blade_that_crosses_the_hand_and_then_the_torso_wounds_once() -> void:
	var weapon := _rules.combatant(1).weapon
	var blade := _rules.combatant(0).weapon.blade_radius
	var hand_r := _rules.combatant(1).fighter.hand_radius
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var hand := Vector2(held.point_x(weapon.offhand_grip_radius), held.point_y(weapon.offhand_grip_radius))
	assert_true(hand.length() > _rules.combatant(1).fighter.hurt_radius + hand_r, "fixture: the off hand sits outside the torso circle (%.3f m)" % hand.length())
	var outside := _square_cut(_rules, weapon.offhand_grip_radius, hand_r + blade + 0.01, 0.0)
	var start: Array[FighterPose] = outside[0]
	var through: Array[FighterPose] = outside[1]
	assert_true(_segment_gap(_rules, start, hand, hand_r) > 0.0, "fixture: the cut starts outside the hand")
	assert_true(_segment_gap(_rules, through, hand, hand_r) < 0.0, "fixture: and crosses it")
	assert_true(_torso_gap(_rules, through) > 0.0, "fixture: the hand crossing is still outside the torso (%.3f m)" % _torso_gap(_rules, through))
	assert_true(_gaps(_rules, start) > 0.0 and _gaps(_rules, through) > 0.0, "fixture: and clear of steel")
	var miss := _state_at(_rules, through, 3.0)
	var miss_health := miss.fighter(1).health
	var miss_report := ContactReport.new()
	var collision := CollisionSystem.new()
	miss.blade_contact.begin_search()
	collision.detect(miss, start, through, _rules, miss.blade_contact, miss_report)
	var miss_events: Array[DuelEvent] = []
	ContactResolver.resolve(miss, miss_report, _rules, 1, miss_report.fraction, miss_events)
	assert_false(miss_report.any(), "crossing only the hand meets nothing")
	assert_eq(_count(miss_events, DuelEventTypes.BODY_HIT), 0, "and emits no body hit")
	assert_eq(miss.fighter(1).health, miss_health, "and no damage")
	var inward := hand.normalized()
	var shift := 0.0
	var entered := through
	while shift < 1.0 and _torso_gap(_rules, entered) > -0.12:
		shift += 0.02
		var moved := ContactFixture.pose(through[0].x - inward.x * shift, through[0].y - inward.y * shift, through[0].facing, 0.0, _rules.combatant(0))
		entered = ContactFixture.poses(moved, through[1])
	assert_true(_torso_gap(_rules, entered) < 0.0, "fixture: the same blade then enters the torso")
	assert_true(_gaps(_rules, entered) > 0.0, "fixture: still clear of steel at the entry")
	var state := _state_at(_rules, through, 0.0)
	state.fighter(0).vx = -inward.x * 4.0
	state.fighter(0).vy = -inward.y * 4.0
	var before := state.fighter(1).health
	state.blade_contact.begin_search()
	var report := ContactReport.new()
	collision.detect(state, through, entered, _rules, state.blade_contact, report)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, _rules, 1, report.fraction, events)
	var hits := events.filter(func(event: DuelEvent) -> bool: return event.type == DuelEventTypes.BODY_HIT)
	assert_true(report.body[0], "the torso entry is the contact")
	assert_false(report.blade, "steel is not in this sweep")
	assert_true(report.fraction < 0.9, "the hit is the entry, not the overlapped end (%.3f)" % report.fraction)
	assert_eq(hits.size(), 1, "one torso hit")
	if hits.size() == 1:
		assert_eq(hits[0].text(DuelEventKeys.REGION), DuelEventKeys.REGION_TORSO, "and it is the torso")
	assert_true(state.fighter(1).health < before, "health records that one entry")
	var deeper := ContactFixture.poses(ContactFixture.pose(entered[0].x - inward.x * 0.02, entered[0].y - inward.y * 0.02, entered[0].facing, 0.0, _rules.combatant(0)), entered[1])
	var again := ContactReport.new()
	var held_health := state.fighter(1).health
	collision.detect(state, entered, deeper, _rules, state.blade_contact, again)
	var more: Array[DuelEvent] = []
	ContactResolver.resolve(state, again, _rules, 2, again.fraction, more)
	assert_false(again.body[0], "staying inside does not enter again")
	assert_eq(_count(more, DuelEventTypes.BODY_HIT), 0, "and does not wound again")
	assert_eq(state.fighter(1).health, held_health, "health stays at the one entry")

# ── GUARD-PROTECTION-001 ─────────────────────────────────────────────────────


## A blade [x0, y0, x1, y1], 0.4 m long, whose centreline crosses fighter 1's
## Long Guard sword axis `along` metres from its pommel at `angle` to it,
## centred `across` off the axis (+ toward perp(û)).
func _crossing(along: float, angle: float, across: float = 0.0) -> PackedFloat64Array:
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var centre := _on_sword(_rules, along, across)
	var wx := held.ux * cos(angle) - held.uy * sin(angle)
	var wy := held.uy * cos(angle) + held.ux * sin(angle)
	return PackedFloat64Array([centre.x - wx * 0.2, centre.y - wy * 0.2, centre.x + wx * 0.2, centre.y + wy * 0.2])


## Which side of fighter 1's guard `blade` comes from.
func _side_of(blade: PackedFloat64Array) -> int:
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	return SwordContactGeometry.guard_side(held.origin_x, held.origin_y, held.ux, held.uy, _rules.combatant(1).weapon, blade)


## `blade` reflected through fighter 1's sword axis (its mirror on the other
## quillon).
func _reflected(blade: PackedFloat64Array) -> PackedFloat64Array:
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var out := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	for end in 2:
		var dx := blade[2 * end] - held.origin_x
		var dy := blade[2 * end + 1] - held.origin_y
		var along := dx * held.ux + dy * held.uy
		var across := dx * -held.uy + dy * held.ux
		out[2 * end] = held.origin_x + held.ux * along + held.uy * across
		out[2 * end + 1] = held.origin_y + held.uy * along - held.ux * across
	return out


## The side is where the blade's centreline crosses the sword axis, read as a
## signed distance from the bar: past the bar's thickness toward the point is
## protected, past it toward the pommel is the grip side, and within it — or
## within the numerical tolerance of its edge — is no side, never protection.
## Steep or shallow, from either direction, on either quillon (its mirror),
## the reading is the same; a blade too near parallel to cross stably reads
## its point nearest the bar, and one lying beside the bar is no side.
func test_the_side_is_where_the_blade_line_crosses_the_sword_axis() -> void:
	## ARRANGE
	var weapon := _rules.combatant(1).weapon
	var bar := weapon.crossguard_centre_radius
	var thick := weapon.crossguard_radius
	var tolerance := SwordContactGeometry.SIDE_TOLERANCE
	var crossings := {
		bar + 2.0 * thick: 1,
		bar + thick + 10.0 * tolerance: 1,
		bar + thick + 0.5 * tolerance: 0,
		bar + 0.5 * thick: 0,
		bar: 0,
		bar - thick - 0.5 * tolerance: 0,
		bar - thick - 10.0 * tolerance: -1,
		bar - 2.0 * thick: -1,
	}
	var wrong := PackedStringArray()
	## ACT + ASSERT: square, steep, shallow (just above the parallel limit),
	## each from both directions and mirrored.
	for angle: float in [PI / 2.0, PI / 3.0, PI / 6.0, 0.11]:
		for direction: float in [0.0, PI]:
			for along: float in crossings:
				var blade := _crossing(along, angle + direction)
				for reading: int in [_side_of(blade), _side_of(_reflected(blade))]:
					if reading != int(crossings[along]):
						wrong.append("%.4f m at %.2f rad: %d" % [along - bar, angle + direction, reading])
	assert_eq(wrong.size(), 0, "the side is the crossing's signed distance from the bar (%s)" % ", ".join(wrong))
	## Near parallel (sin 0.03 < PARALLEL_SINE): the centreline would cross far
	## down the grip, but the blade lies above the bar, below it, or beside it.
	var shallow := 0.03
	assert_true(absf(sin(shallow)) < SwordContactGeometry.PARALLEL_SINE, "fixture: too near parallel to cross stably")
	var lying_above := _crossing(bar + 0.30, shallow, 0.05)
	var lying_below := _crossing(bar - 0.30, shallow, 0.05)
	var lying_beside := _crossing(bar, shallow, 0.05)
	assert_eq(_side_of(lying_above), 1, "a blade lying along the sword above the bar comes from the protected side")
	assert_eq(_side_of(_reflected(lying_above)), 1, "and so does its mirror")
	assert_eq(_side_of(lying_below), -1, "below it, from the grip side")
	assert_eq(_side_of(lying_beside), 0, "and one lying beside the bar is no side")


## Fighter 1 standing in Long Guard at the origin after the intro; fighter 0's
## blade square across its sword, pointing away from the axis with its tip
## `across` off it and `along` from its pommel; both swords at rest.
func _drift(along: float, across: float) -> SimRunner:
	var runner := SimRunner.create(_rules, 5)
	runner.skip_intro()
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var direction := atan2(-held.ux, held.uy) + (PI if across < 0.0 else 0.0)
	var tip := _on_sword(_rules, along, across)
	var reach := WeaponKinematics.pose_at(0.0, 0.0, direction, 0.0, _rules.combatant(0), BladePose.new())
	var weapon := _rules.combatant(0).weapon
	ContactFixture.arm(runner.state.fighter(1), 0.0, 0.0, 0.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	ContactFixture.arm(runner.state.fighter(0), tip.x - reach.point_x(weapon.tip_radius), tip.y - reach.point_y(weapon.tip_radius), direction, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	## θ = 0 is inside the side deadzone, so arming leaves both fighters on the
	## intro's stable_side. A heading flipped by half a turn is that sword's
	## mirror only when the remembered side and the swing direction flip with
	## it; otherwise the guard return pulls both blades the same local way
	## and the two quillons stop being one contact reflected.
	if across < 0.0:
		for slot in 2:
			var planted := runner.state.fighter(slot).weapon
			planted.stable_side = -planted.stable_side
			planted.swing_dir = -planted.swing_dir
	return runner


## One tick of `runner` with fighter 0 driven at `speed` m/s along fighter 1's
## Long Guard sword (+ toward its point).
func _drive(runner: SimRunner, speed: float) -> void:
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	runner.state.fighter(0).vx = held.ux * speed
	runner.state.fighter(0).vy = held.uy * speed
	runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))


## Which side of fighter 1's guard fighter 0's blade is on in `state`.
func _side_in(state: MatchState) -> int:
	var a := WeaponKinematics.pose_of(state.fighter(0), _rules.combatant(0), BladePose.new())
	var b := WeaponKinematics.pose_of(state.fighter(1), _rules.combatant(1), BladePose.new())
	var blade := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	SwordContactGeometry.place(a.origin_x, a.origin_y, a.ux, a.uy, _rules.combatant(0).weapon, blade)
	return SwordContactGeometry.guard_side(b.origin_x, b.origin_y, b.ux, b.uy, _rules.combatant(1).weapon, blade)


## The gap from fighter 0's blade to fighter 1's guard root in `state`.
func _guard_gap(state: MatchState) -> float:
	var a := WeaponKinematics.pose_of(state.fighter(0), _rules.combatant(0), BladePose.new())
	var b := WeaponKinematics.pose_of(state.fighter(1), _rules.combatant(1), BladePose.new())
	var geometry := SwordContactGeometry.new()
	geometry.measure(state.fighter(0).x, state.fighter(0).y, a.origin_x, a.origin_y, a.ux, a.uy, b.origin_x, b.origin_y, b.ux, b.uy, _rules.combatant(0).weapon, _rules.combatant(1).weapon, state.blade_contact.guard_mode)
	return geometry.guard_gap[0]


## The solved contacts on fighter 1's guard in `events`, and the largest
## impulse among them.
static func _guard_contacts(events: Array[DuelEvent]) -> Vector2:
	var count := 0
	var impulse := 0.0
	for event in events:
		if event.type == DuelEventTypes.BLADE_CONTACT and int(event.data[DuelEventKeys.STEEL_PAIR]) == SwordContactSet.PAIR_BLADE_ON_GUARD:
			count += 1
			impulse = maxf(impulse, event.number(DuelEventKeys.IMPULSE))
	return Vector2(count, impulse)


## A blade driven onto the guard from its protected side is stopped by it: a
## solved contact on that guard's pair, with positive impulse, and the blade
## kept on the protected side, never through the guard. The same blade driven
## up from the grip side passes through: no contact on the guard, its pair
## latched PASSING from first touch — still passing once the blade's line is
## already above the bar, so never flipped to a block part-way — and freed
## once it is clear. Both quillons read alike.
func test_the_guard_blocks_its_protected_side_and_passes_the_grip_side() -> void:
	## ARRANGE: 8 m/s carries the blade 13 cm a tick, from 10 cm above the bar
	## down onto it, or from 6 cm below the bar up through it.
	var weapon := _rules.combatant(1).weapon
	var inside := weapon.crossguard_half_span * 0.8
	var speed := 8.0
	var readings: Array = []
	for across: float in [inside, -inside]:
		var above := _drift(weapon.crossguard_centre_radius + 0.10, across)
		var below := _drift(weapon.crossguard_centre_radius - 0.06, across)
		assert_true(_guard_gap(above.state) > 0.0 and _guard_gap(below.state) > 0.0, "fixture: both clear of the guard at the start")
		assert_eq(_side_in(above.state), 1, "fixture: from above the blade comes from the protected side")
		assert_eq(_side_in(below.state), -1, "fixture: from below, from the grip side")
		## ACT: one tick onto the guard; the grip-side blade driven on until its
		## pair is freed (at most four ticks).
		_drive(above, -speed)
		var modes := PackedInt32Array()
		var sides := PackedInt32Array()
		for _tick in 4:
			_drive(below, speed)
			modes.append(below.state.blade_contact.guard_mode[0])
			sides.append(_side_in(below.state))
			if modes[modes.size() - 1] == SwordContactGeometry.GUARD_FREE:
				break
		var blocked := _guard_contacts(above.events)
		var passed := _guard_contacts(below.events)
		var latched_above := false
		for k in modes.size():
			latched_above = latched_above or (modes[k] == SwordContactGeometry.GUARD_PASSING and sides[k] == 1)
		## ASSERT
		assert_true(blocked.x > 0.0 and blocked.y > 0.0, "from the protected side the guard is struck and solved (%d contacts, impulse %.4f)" % [int(blocked.x), blocked.y])
		assert_eq(_side_in(above.state), 1, "and the blade stays on the protected side")
		assert_true(_guard_gap(above.state) >= -ContactGauge.allowed(_rules), "never through the guard (%.4f m)" % _guard_gap(above.state))
		assert_eq(int(passed.x), 0, "from the grip side the blade passes the guard untouched")
		assert_false(modes.has(SwordContactGeometry.GUARD_PROTECTED), "never flipped to a block on the way through (%s)" % str(modes))
		assert_true(latched_above, "still passing once its line is above the bar (%s, sides %s)" % [str(modes), str(sides)])
		assert_eq(modes[modes.size() - 1], SwordContactGeometry.GUARD_FREE, "and freed once it is clear (%s)" % str(modes))
		assert_true(above.is_sound() and below.is_sound(), "every tick legal")
		readings.append([int(blocked.x), snappedf(blocked.y, 1.0e-9), snappedf(_guard_gap(above.state), 1.0e-9), int(passed.x), modes, sides])
	assert_eq(str(readings[0]), str(readings[1]), "and both quillons read alike")


## The steel gap between the swords at `poses`, with each guard pair latched
## as `modes`.
func _steel_gap(poses: Array[FighterPose], modes: PackedInt32Array) -> float:
	var a := WeaponKinematics.pose_at(poses[0].x, poses[0].y, poses[0].facing, 0.0, _rules.combatant(0), BladePose.new())
	var b := WeaponKinematics.pose_at(poses[1].x, poses[1].y, poses[1].facing, 0.0, _rules.combatant(1), BladePose.new())
	return SwordContactGeometry.new().measure(poses[0].x, poses[0].y, a.origin_x, a.origin_y, a.ux, a.uy, b.origin_x, b.origin_y, b.ux, b.uy, _rules.combatant(0).weapon, _rules.combatant(1).weapon, modes)


## A protected guard holds a blade while it is on the protected side or within
## the bar's own band — so the line never jitters — and lets it go once it is
## clearly on the grip side, having slipped off the quillon; a passing guard is
## never steel. (The ship corpus once held a blade that had slid round a
## quillon's end against the bar's underside, a degenerate pin.)
func test_a_protected_guard_lets_go_of_a_blade_that_slips_to_the_grip_side() -> void:
	## ARRANGE: one tip on the quillon from above, level with the bar, below it.
	var weapon := _rules.combatant(1).weapon
	var touching := weapon.crossguard_radius + _rules.combatant(0).weapon.blade_radius - 0.001
	var inside := weapon.crossguard_half_span * 0.8
	var above: Array[FighterPose] = _square_cut(_rules, weapon.crossguard_centre_radius + touching, inside, inside)[0]
	var level: Array[FighterPose] = _square_cut(_rules, weapon.crossguard_centre_radius, inside, inside)[0]
	var below: Array[FighterPose] = _square_cut(_rules, weapon.crossguard_centre_radius - touching, inside, inside)[0]
	assert_eq([_side(above), _side(level), _side(below)], [1, 0, -1], "fixture: above, within the band, and on the grip side")
	var protected := PackedInt32Array([SwordContactGeometry.GUARD_PROTECTED, SwordContactGeometry.GUARD_FREE])
	var passing := PackedInt32Array([SwordContactGeometry.GUARD_PASSING, SwordContactGeometry.GUARD_FREE])
	## ACT + ASSERT
	assert_true(_steel_gap(above, protected) < 0.0, "latched protected, a blade above the bar is held")
	assert_true(_steel_gap(level, protected) < 0.0, "and still held within the bar's band — no jitter at the line")
	assert_true(_steel_gap(below, protected) > 0.0, "clearly on the grip side it is let go")
	for poses: Array[FighterPose] in [above, level, below]:
		assert_true(_steel_gap(poses, passing) > 0.0, "a passing guard is never steel")


## Pairs of points in `contact` that stand for one place (within the
## separation two distinct constraints need, pushing the same way).
static func _duplicates(contact: SwordContactSet) -> int:
	var found := 0
	for i in contact.point_count:
		for j in range(i + 1, contact.point_count):
			var apart := SimMath.length(contact.point_x[i] - contact.point_x[j], contact.point_y[i] - contact.point_y[j])
			var same := contact.point_nx[i] * contact.point_nx[j] + contact.point_ny[i] * contact.point_ny[j] >= SwordContactGeometry.SAME_NORMAL_COSINE
			found += 1 if same and apart < SwordContactGeometry.MIN_POINT_SEPARATION else 0
	return found


## Fighter 0's pose with its blade's point at (`along`, `across`) in fighter
## 1's Long Guard sword frame, the blade running from there back along
## (`dir_along`, `dir_across`) in that frame (+ across toward perp(û)).
func _point_at(along: float, across: float, dir_along: float, dir_across: float) -> FighterPose:
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var tip := _on_sword(_rules, along, across)
	var away := Vector2(held.ux * dir_along - held.uy * dir_across, held.uy * dir_along + held.ux * dir_across).normalized()
	var facing := atan2(-away.y, -away.x)
	var reach := WeaponKinematics.pose_at(0.0, 0.0, facing, 0.0, _rules.combatant(0), BladePose.new())
	var spec := _rules.combatant(0)
	return ContactFixture.pose(tip.x - reach.point_x(spec.weapon.tip_radius), tip.y - reach.point_y(spec.weapon.tip_radius), facing, 0.0, spec)


## The seam of blade and guard root: an attacking point resting in the notch
## between the defender's blade and its guard root's slanted edge, touching
## both from the protected side — two pieces of steel at once, pushing
## different ways. The manifold keeps them as two distinct constraints, never
## two points for one place; pressed into the notch for several real ticks the
## point is held there with no duplicate point, no degenerate pin, overlap
## within the slop, and every tick legal.
func test_the_seam_of_blade_and_guard_root_holds_without_a_pin() -> void:
	## ARRANGE: the point's centre at the blade's reach off the axis and the
	## slanted edge's reach above it (each less 0.5 mm), the blade lying out
	## at slope 0.2 — away from both surfaces.
	var weapon := _rules.combatant(1).weapon
	var r := _rules.combatant(0).weapon.blade_radius
	var bar := weapon.crossguard_centre_radius
	var apex := weapon.guard_root_apex_radius()
	var h := weapon.crossguard_half_span
	var slant := SimMath.length(h, apex - bar)
	var off_blade := weapon.blade_radius + r - 0.0005
	var along := apex + ((weapon.crossguard_radius + r - 0.0005) * slant - off_blade * (apex - bar)) / h
	var poses := ContactFixture.poses(_point_at(along, off_blade, 0.2, 1.0), ContactFixture.pose(0.0, 0.0, 0.0, 0.0, _rules.combatant(1)))
	var a := WeaponKinematics.pose_at(poses[0].x, poses[0].y, poses[0].facing, 0.0, _rules.combatant(0), BladePose.new())
	var b := WeaponKinematics.pose_at(poses[1].x, poses[1].y, poses[1].facing, 0.0, _rules.combatant(1), BladePose.new())
	var geometry := SwordContactGeometry.new()
	geometry.measure(poses[0].x, poses[0].y, a.origin_x, a.origin_y, a.ux, a.uy, b.origin_x, b.origin_y, b.ux, b.uy, _rules.combatant(0).weapon, weapon)
	var pairs := PackedInt32Array()
	for p in geometry.count:
		pairs.append(geometry.point_pair[p])
	assert_eq(_side(poses), 1, "fixture: from the protected side, so the root is steel")
	assert_true(pairs.has(SwordContactSet.PAIR_BLADES) and pairs.has(SwordContactSet.PAIR_BLADE_ON_GUARD), "fixture: touching the blade and the root at once (%s)" % str(pairs))
	## ACT: pressed into the notch for four real ticks.
	var runner := SimRunner.create(_rules, 5)
	runner.skip_intro()
	ContactFixture.arm(runner.state.fighter(1), poses[1].x, poses[1].y, poses[1].facing, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	ContactFixture.arm(runner.state.fighter(0), poses[0].x, poses[0].y, poses[0].facing, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var duplicates := 0
	var held := 0
	var deepest := 0.0
	for _tick in 4:
		_drive(runner, -1.0)
		duplicates += _duplicates(runner.state.blade_contact)
		held = maxi(held, runner.state.blade_contact.point_count)
		deepest = maxf(deepest, -ContactGauge.blades(_rules, runner.state).x)
	## ASSERT
	assert_eq(_duplicates_in(geometry), 0, "the seam's two constraints are distinct, never one place twice")
	assert_true(held >= 1, "fixture: pressed, the point is held (%d points at most)" % held)
	assert_eq(duplicates, 0, "never two points for one place while it is held")
	assert_eq(runner.simulation.diagnostics.position_guard_hits, 0, "no degenerate pin")
	assert_true(deepest <= ContactGauge.allowed(_rules), "held within the slop (deepest %.4f m)" % deepest)
	assert_true(runner.is_sound(), "every tick legal (%s)" % runner.violation_summary())


static func _duplicates_in(geometry: SwordContactGeometry) -> int:
	var found := 0
	for i in geometry.count:
		for j in range(i + 1, geometry.count):
			var apart := SimMath.length((geometry.point_ax[i] + geometry.point_bx[i] - geometry.point_ax[j] - geometry.point_bx[j]) * 0.5, (geometry.point_ay[i] + geometry.point_by[i] - geometry.point_ay[j] - geometry.point_by[j]) * 0.5)
			var same := geometry.point_nx[i] * geometry.point_nx[j] + geometry.point_ny[i] * geometry.point_ny[j] >= SwordContactGeometry.SAME_NORMAL_COSINE
			found += 1 if same and apart < SwordContactGeometry.MIN_POINT_SEPARATION else 0
	return found
