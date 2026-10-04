extends TestCase

## COLLIDE: swept detection never tunnels and respects contact rules
## (COMBAT §42, PLAN Phase 5).
##
## Implements: /spec/invariants.md#combat-002
## See also: /docs/concepts/combat.md

var _rules: DuelRules
var _collision := CollisionSystem.new()


func _init() -> void:
	suite_name = "COLLIDE"
	_rules = DuelFixture.rules()


func _blade_to_point(pose: FighterPose, px: float, py: float) -> float:
	var weapon := _rules.weapon
	var hx := pose.x + pose.ux * weapon.hilt_radius
	var hy := pose.y + pose.uy * weapon.hilt_radius
	var tx := pose.x + pose.ux * weapon.tip_radius
	var ty := pose.y + pose.uy * weapon.tip_radius
	var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, px, py)
	return SimMath.length(px - SimMath.mix(hx, tx, t), py - SimMath.mix(hy, ty, t))


func test_fast_blade_cannot_tunnel_through_a_body() -> void:
	var state := DuelFixture.state(_rules)
	state.fighter(0).weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	var target := ContactFixture.pose(1.0, 0.0, PI, 0.0)
	var start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(-80.0)), target)
	var finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(80.0)), target)
	var touch := _rules.fighter.body_radius + _rules.weapon.blade_radius
	assert_true(_blade_to_point(start[0], 1.0, 0.0) > touch, "precondition: clear of the body at tick start")
	assert_true(_blade_to_point(finish[0], 1.0, 0.0) > touch, "precondition: clear of the body at tick end")
	var report := ContactReport.new()
	_collision.detect(state, start, finish, _rules, false, report)
	assert_true(report.body[0], "the sweep through the body is caught")
	assert_between(report.fraction, 0.3, 0.5, "contact begins before the blade reaches the center line")


func test_fast_blades_cannot_tunnel_through_each_other() -> void:
	var state := DuelFixture.state(_rules)
	var guard := ContactFixture.pose(2.0, 0.0, PI, deg_to_rad(-30.0))
	var start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(-20.0)), guard)
	var finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(60.0)), guard)
	var contact := SegmentContact.new()
	for poses_at: Array[FighterPose] in [start, finish]:
		var w := _rules.weapon
		SimMath.closest_segments(
			poses_at[0].x + poses_at[0].ux * w.hilt_radius, poses_at[0].y + poses_at[0].uy * w.hilt_radius,
			poses_at[0].x + poses_at[0].ux * w.tip_radius, poses_at[0].y + poses_at[0].uy * w.tip_radius,
			poses_at[1].x + poses_at[1].ux * w.hilt_radius, poses_at[1].y + poses_at[1].uy * w.hilt_radius,
			poses_at[1].x + poses_at[1].ux * w.tip_radius, poses_at[1].y + poses_at[1].uy * w.tip_radius,
			contact
		)
		assert_true(contact.distance > w.blade_radius * 2.0, "precondition: blades apart at both tick ends")
	var report := ContactReport.new()
	_collision.detect(state, start, finish, _rules, true, report)
	assert_true(report.blade, "the crossing blades collide")
	assert_between(SimMath.length(report.blade_ax, report.blade_ay), _rules.weapon.hilt_radius, _rules.weapon.tip_radius, "contact lies on the sweeping blade")


func test_blades_already_touching_must_separate_first() -> void:
	var state := DuelFixture.state(_rules)
	var a := ContactFixture.pose(0.0, 0.0, 0.0, 0.0)
	var b := ContactFixture.pose(1.6, 0.03, PI, 0.0)
	var report := ContactReport.new()
	_collision.detect(state, ContactFixture.poses(a, b), ContactFixture.poses(a, b), _rules, true, report)
	assert_false(report.blade, "resting contact is not a new impact")


func test_cooldown_disables_blade_impacts() -> void:
	var state := DuelFixture.state(_rules)
	var guard := ContactFixture.pose(2.0, 0.0, PI, deg_to_rad(-30.0))
	var start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(-20.0)), guard)
	var finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(60.0)), guard)
	var report := ContactReport.new()
	_collision.detect(state, start, finish, _rules, false, report)
	assert_false(report.any(), "no blade impact while cooling down and nobody striking")


func test_only_live_strikes_cut() -> void:
	var target := ContactFixture.pose(1.0, 0.0, PI, 0.0)
	var start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(-80.0)), target)
	var finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(80.0)), target)
	var report := ContactReport.new()
	var resting := DuelFixture.state(_rules)
	_collision.detect(resting, start, finish, _rules, false, report)
	assert_false(report.body[0], "a neutral blade never deals body damage")
	var landed := DuelFixture.state(_rules)
	landed.fighter(0).weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	landed.fighter(0).weapon.swing_hit = true
	_collision.detect(landed, start, finish, _rules, false, report)
	assert_false(report.body[0], "one swing cannot hit twice")


func test_substeps_scale_with_motion_and_cap() -> void:
	var still := ContactFixture.pose(0.0, 0.0, 0.0, 0.0)
	var idle := ContactFixture.poses(still, still)
	assert_eq(CollisionSystem.substep_count(idle, idle, _rules), 1, "no motion needs one substep")
	var turned := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, 1.0), still)
	assert_eq(CollisionSystem.substep_count(idle, turned, _rules), ceili(1.22 / 0.03), "one radian of tip travel")
	var spun := ContactFixture.poses(ContactFixture.pose(5.0, 5.0, 0.0, 3.0), ContactFixture.pose(-5.0, 0.0, 0.0, -3.0))
	assert_eq(CollisionSystem.substep_count(idle, spun, _rules), _rules.combat.max_substeps, "capped")


func test_blade_contact_outranks_body_contact_in_one_substep() -> void:
	var coarse := DuelFixture.rules()
	coarse.combat.max_substeps = 1
	var state := DuelFixture.state(coarse)
	state.fighter(0).weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	var defender := ContactFixture.pose(1.0, 0.0, PI, 0.0)
	var start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(-90.0)), defender)
	var finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, 0.0), defender)
	var report := ContactReport.new()
	_collision.detect(state, start, finish, coarse, true, report)
	assert_true(report.blade, "blades meet")
	assert_false(report.body[0], "the blade in the way prevents the body hit")
