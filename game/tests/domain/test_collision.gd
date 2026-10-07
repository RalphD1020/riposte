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


## A pair that will accept a new blade contact.
func _armed() -> ContactPairState:
	return ContactPairState.new()


## A pair already in contact, so only body hits can register.
func _engaged() -> ContactPairState:
	var pair := ContactPairState.new()
	pair.set_phase(ContactPairState.Phase.CONTACTING)
	return pair


func _blade_to_point(pose: FighterPose, px: float, py: float) -> float:
	var weapon := _rules.weapon
	var hx := pose.x + pose.ux * weapon.hilt_radius
	var hy := pose.y + pose.uy * weapon.hilt_radius
	var tx := pose.x + pose.ux * weapon.tip_radius
	var ty := pose.y + pose.uy * weapon.tip_radius
	var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, px, py)
	return SimMath.length(px - SimMath.mix(hx, tx, t), py - SimMath.mix(hy, ty, t))


func _blade_gap(poses_at: Array[FighterPose]) -> float:
	var w := _rules.weapon
	var contact := SegmentContact.new()
	SimMath.closest_segments(
		poses_at[0].x + poses_at[0].ux * w.hilt_radius, poses_at[0].y + poses_at[0].uy * w.hilt_radius,
		poses_at[0].x + poses_at[0].ux * w.tip_radius, poses_at[0].y + poses_at[0].uy * w.tip_radius,
		poses_at[1].x + poses_at[1].ux * w.hilt_radius, poses_at[1].y + poses_at[1].uy * w.hilt_radius,
		poses_at[1].x + poses_at[1].ux * w.tip_radius, poses_at[1].y + poses_at[1].uy * w.tip_radius,
		contact
	)
	return contact.distance


func test_fast_blade_cannot_tunnel_through_a_body() -> void:
	var state := DuelFixture.state(_rules)
	state.fighter(0).weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	## Point the target's weapon perpendicular (+90°) so it geometrically
	## avoids the attacker without using BIND to suppress detection.
	var target := ContactFixture.pose(1.0, 0.0, PI, deg_to_rad(90.0))
	var start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(-80.0)), target)
	var finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(80.0)), target)
	var touch := _rules.fighter.body_radius + _rules.weapon.blade_radius
	assert_true(_blade_to_point(start[0], 1.0, 0.0) > touch, "precondition: clear of the body at tick start")
	assert_true(_blade_to_point(finish[0], 1.0, 0.0) > touch, "precondition: clear of the body at tick end")
	var report := ContactReport.new()
	## Use a BOUND pair so blade-on-blade contacts are suppressed and only
	## body hits register. This test exercises the body sweep, not blade contact.
	var bound := ContactPairState.new()
	bound.set_phase(ContactPairState.Phase.BOUND)
	_collision.detect(state, start, finish, _rules, bound, report)
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
	_collision.detect(state, start, finish, _rules, _armed(), report)
	assert_true(report.blade, "the crossing blades collide")
	assert_between(SimMath.length(report.blade_ax, report.blade_ay), _rules.weapon.hilt_radius, _rules.weapon.tip_radius, "contact lies on the sweeping blade")


func test_blades_already_touching_must_separate_first() -> void:
	## COMBAT-002 and the lifecycle hysteresis together: one clash is one
	## contact, however many ticks the blades spend leaning on each other, and
	## they must genuinely come apart before the next one counts.
	var state := DuelFixture.state(_rules)
	var a := ContactFixture.pose(0.0, 0.0, 0.0, 0.0)
	var b := ContactFixture.pose(1.6, 0.03, PI, 0.0)
	var resting := ContactFixture.poses(a, b)
	var pair := _armed()
	var report := ContactReport.new()
	_collision.detect(state, resting, resting, _rules, pair, report)
	assert_true(report.blade, "the first touch is a contact")
	assert_eq(pair.phase, ContactPairState.Phase.CONTACTING, "and the pair records it")
	_collision.detect(state, resting, resting, _rules, pair, report)
	assert_false(report.blade, "leaning on the same contact is not a second impact")
	var touch := _rules.weapon.blade_radius * 2.0
	var nudged := ContactFixture.poses(a, ContactFixture.pose(1.6, touch + _rules.combat.separation_epsilon * 0.5, PI, 0.0))
	_collision.detect(state, nudged, nudged, _rules, pair, report)
	assert_eq(pair.phase, ContactPairState.Phase.SEPARATING, "drifting past touch starts separating")
	assert_false(report.blade, "but inside the hysteresis band it cannot re-strike")
	var apart := ContactFixture.poses(a, ContactFixture.pose(1.6, touch + _rules.combat.separation_epsilon * 2.0, PI, 0.0))
	_collision.detect(state, apart, apart, _rules, pair, report)
	assert_eq(pair.phase, ContactPairState.Phase.SEPARATED, "clearing the band separates them")
	_collision.detect(state, resting, resting, _rules, pair, report)
	assert_true(report.blade, "so coming back together is a new clash")


func test_separating_inside_one_sweep_re_arms_the_pair() -> void:
	## The hysteresis is a separation requirement, not a cooldown. Blades that
	## were in contact and have genuinely come apart may clash again — even
	## within the same tick, which is what lets a parry be followed by a
	## re-engagement instead of a free hit.
	var state := DuelFixture.state(_rules)
	var guard := ContactFixture.pose(2.0, 0.0, PI, deg_to_rad(-30.0))
	var start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(-20.0)), guard)
	var finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(60.0)), guard)
	var band := _rules.weapon.blade_radius * 2.0 + _rules.combat.separation_epsilon
	assert_true(_blade_gap(start) > band, "precondition: clear of the hysteresis band at sweep start")
	var pair := _engaged()
	var report := ContactReport.new()
	_collision.detect(state, start, finish, _rules, pair, report)
	assert_true(report.blade, "the crossing registers once the pair has separated")
	assert_eq(pair.phase, ContactPairState.Phase.CONTACTING, "and the pair is engaged again")


func test_a_bound_pair_registers_no_blade_contact() -> void:
	## COMBAT §45: a bind is one sustained event. Blades grinding together
	## inside it must not keep generating fresh impulses.
	var state := DuelFixture.state(_rules)
	var guard := ContactFixture.pose(2.0, 0.0, PI, deg_to_rad(-30.0))
	var start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(-20.0)), guard)
	var finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(60.0)), guard)
	var bound := ContactPairState.new()
	bound.set_phase(ContactPairState.Phase.BOUND)
	var report := ContactReport.new()
	_collision.detect(state, start, finish, _rules, bound, report)
	assert_false(report.blade, "no impulse while bound")
	assert_true(bound.is_bound(), "and the bind is not silently dropped")


func test_only_live_strikes_cut() -> void:
	var target := ContactFixture.pose(1.0, 0.0, PI, 0.0)
	var start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(-80.0)), target)
	var finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(80.0)), target)
	var report := ContactReport.new()
	## A dead blade is inert and cannot deal body damage.
	var dead := DuelFixture.state(_rules)
	DuelFixture.kill(dead.fighter(0))
	_collision.detect(dead, start, finish, _rules, _engaged(), report)
	assert_false(report.body[0], "a dead blade never deals body damage")
	## The weapon-body lifecycle prevents repeated damage while the blade
	## remains inside the body (COMBAT-007). Continuously overlapping frames
	## produce at most one hit (the ENTERED transition), not one per substep.
	var sweeping := DuelFixture.state(_rules)
	sweeping.fighter(0).weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	## Blade near the body for the full sub-interval → enters once, stays inside.
	var near_start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(-5.0)), target)
	var near_finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(5.0)), target)
	_collision.detect(sweeping, near_start, near_finish, _rules, _engaged(), report)
	assert_true(report.body[0], "first entry registers as a hit")
	report.clear()
	## The lifecycle is now ENTERED → INSIDE after tick upkeep. Second detect
	## with the blade still overlapping must NOT re-damage.
	sweeping.weapon_body_contacts[0].phase = WeaponBodyContact.Phase.INSIDE
	_collision.detect(sweeping, near_start, near_finish, _rules, _engaged(), report)
	assert_false(report.body[0], "continuously overlapping blade does not re-hit")


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
	_collision.detect(state, start, finish, coarse, _armed(), report)
	assert_true(report.blade, "blades meet")
	assert_false(report.body[0], "the blade in the way prevents the body hit")


func test_neutral_blade_detects_forward_stab() -> void:
	## COMBAT-010, PHYS-007: a stationary sword on an advancing fighter is a
	## valid point-strike source. The weapon need not be in a swing phase.
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	a.weapon.angle = 0.0
	a.weapon.phase = CombatPhase.Id.NEUTRAL
	a.vx = 6.0
	var reach := _rules.weapon.tip_radius + _rules.fighter.body_radius
	var target := ContactFixture.pose(reach, 0.0, PI, 0.0)
	var gap := 0.3
	var start := ContactFixture.poses(ContactFixture.pose(-gap, 0.0, 0.0, 0.0), target)
	var finish := ContactFixture.poses(ContactFixture.pose(gap, 0.0, 0.0, 0.0), target)
	var report := ContactReport.new()
	_collision.detect(state, start, finish, _rules, _engaged(), report)
	assert_true(report.body[0], "a neutral blade advancing tip-first produces a body contact")


func test_bound_blade_body_contact_detected_but_consequence_suppressed() -> void:
	## A blade in a bind is physically present and may geometrically overlap a
	## body. Detection stays truthful; ContactResolver suppresses the damage
	## consequence while the bind holds (COMBAT-007).
	var state := DuelFixture.state(_rules)
	state.fighter(0).weapon.phase = CombatPhase.Id.BIND
	var target := ContactFixture.pose(1.0, 0.0, PI, deg_to_rad(90.0))
	var start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(-80.0)), target)
	var finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(80.0)), target)
	var report := ContactReport.new()
	## Use a BOUND pair so blade-on-blade re-contact is suppressed; this test
	## exercises body detection through a bound blade, not blade collision.
	var bound := ContactPairState.new()
	bound.set_phase(ContactPairState.Phase.BOUND)
	_collision.detect(state, start, finish, _rules, bound, report)
	assert_true(report.body[0], "a bound blade's body overlap is detected geometrically")
	## Verify the consequence layer suppresses the hit.
	var events: Array[DuelEvent] = []
	var initial_health := state.fighter(1).health
	ContactResolver.resolve(state, report, _rules, 1, 0.0, events)
	assert_eq(state.fighter(1).health, initial_health, "bound blade contact deals no damage (consequence suppressed)")


func test_recovery_blade_can_produce_body_contact() -> void:
	## A blade in recovery still physically exists and can contact a body.
	## If the opponent advances onto the blade tip, the physics applies.
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	a.weapon.phase = CombatPhase.Id.RECOVERY
	a.weapon.angle = 0.0
	## Point the target's weapon perpendicular so only the attacker's body
	## contact is tested. A BOUND pair suppresses blade-on-blade re-contact so
	## the body detection code is reached.
	var target := ContactFixture.pose(1.0, 0.0, PI, deg_to_rad(90.0))
	var start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(-80.0)), target)
	var finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(80.0)), target)
	var report := ContactReport.new()
	var bound := ContactPairState.new()
	bound.set_phase(ContactPairState.Phase.BOUND)
	_collision.detect(state, start, finish, _rules, bound, report)
	assert_true(report.body[0], "a blade in recovery can produce a body contact")
