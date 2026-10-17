extends TestCase

## COLLIDE: the sampled sweep, on the envelope these cases name, and the contact rules
## (COMBAT Â§42, PLAN Phase 5).
##
## Implements: /spec/invariants.md#combat-002
## See also: /docs/concepts/combat.md

## Invisible overlap a resolved rigid contact may leave (m): millimetres,
## never a visible pass-through (RIGID-CONTACT-001).
const RIGID_SLOP := 0.003

var _rules: DuelRules
var _collision := CollisionSystem.new()


func _init() -> void:
	suite_name = "COLLIDE"
	## Hand-built revolute scenes: the mechanism under test, on the fixed pivot.
	_rules = DuelFixture.revolute_rules()


## A pair that will accept a new blade contact.
func _armed() -> SwordContactSet:
	return SwordContactSet.new()


## A pair already in contact, so only body hits can register.
func _engaged() -> SwordContactSet:
	var pair := SwordContactSet.new()
	pair.set_phase(SwordContactSet.Phase.CONTACTING)
	return pair


func _blade_to_point(pose: FighterPose, px: float, py: float) -> float:
	var weapon := _rules.combatant(0).weapon
	var hx := pose.x + pose.ux * weapon.blade_base_radius
	var hy := pose.y + pose.uy * weapon.blade_base_radius
	var tx := pose.x + pose.ux * weapon.tip_radius
	var ty := pose.y + pose.uy * weapon.tip_radius
	var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, px, py)
	return SimMath.length(px - SimMath.mix(hx, tx, t), py - SimMath.mix(hy, ty, t))


func _blade_gap(poses_at: Array[FighterPose]) -> float:
	var w := _rules.combatant(0).weapon
	var contact := SegmentContact.new()
	SimMath.closest_segments(
		poses_at[0].x + poses_at[0].ux * w.blade_base_radius, poses_at[0].y + poses_at[0].uy * w.blade_base_radius,
		poses_at[0].x + poses_at[0].ux * w.tip_radius, poses_at[0].y + poses_at[0].uy * w.tip_radius,
		poses_at[1].x + poses_at[1].ux * w.blade_base_radius, poses_at[1].y + poses_at[1].uy * w.blade_base_radius,
		poses_at[1].x + poses_at[1].ux * w.tip_radius, poses_at[1].y + poses_at[1].uy * w.tip_radius,
		contact
	)
	return contact.distance


## Preconditions of a body-only sweep from −80° to +80° at the origin past
## `target`: at the sweep's closest approach (θ = 0, the tip toward the
## target) the swords are still apart, so they meet nowhere on it; and the
## blade there passes through the target's torso, so the body is on the path.
## A future geometry change fails these, not the contact law under test.
func _assert_body_only_sweep(target: FighterPose) -> void:
	var closest := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, 0.0), target)
	var swords := _blade_gap(closest)
	assert_true(swords > 2.0 * _rules.combatant(0).weapon.blade_radius, "precondition: the swords never meet on the sweep (closest gap %.3f m)" % swords)
	var torso := _blade_to_point(closest[0], target.x, target.y)
	assert_true(torso < _rules.combatant(0).fighter.hurt_radius + _rules.combatant(0).weapon.blade_radius, "precondition: the sweep crosses the torso (%.3f m from its axis)" % torso)


func test_fast_blade_cannot_tunnel_through_a_body() -> void:
	var state := DuelFixture.state(_rules)
	state.fighter(0).weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	## The target faces away with its sword pointing back, beyond the
	## attacker's reach (its hilt end 8 cm past the attacker's tip), so only the body can be met.
	var target := ContactFixture.pose(1.05, 0.0, 0.0, 0.0)
	var start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(-80.0)), target)
	var finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(80.0)), target)
	var touch := _rules.combatant(0).fighter.push_radius + _rules.combatant(0).weapon.blade_radius
	assert_true(_blade_to_point(start[0], 1.05, 0.0) > touch, "precondition: clear of the body at tick start")
	assert_true(_blade_to_point(finish[0], 1.05, 0.0) > touch, "precondition: clear of the body at tick end")
	_assert_body_only_sweep(target)
	var report := ContactReport.new()
	## An engaged pair with held contacts off (holds = false): the swords are
	## not re-struck or held, so only body hits register. This test exercises
	## the body sweep; a held blade is CONTACT-INTEGRITY's.
	_collision.detect(state, start, finish, _rules, _engaged(), report, false)
	assert_false(report.blade, "precondition: no blade contact competes with the body")
	assert_true(report.body[0], "the sweep through the body is caught")
	assert_between(report.fraction, 0.3, 0.5, "contact begins before the blade reaches the center line")


func test_fast_blades_cannot_tunnel_through_each_other() -> void:
	var state := DuelFixture.state(_rules)
	var guard := ContactFixture.pose(2.0, 0.0, PI, deg_to_rad(-30.0))
	var start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(-20.0)), guard)
	var finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(60.0)), guard)
	var contact := SegmentContact.new()
	for poses_at: Array[FighterPose] in [start, finish]:
		var w := _rules.combatant(0).weapon
		SimMath.closest_segments(
			poses_at[0].x + poses_at[0].ux * w.blade_base_radius, poses_at[0].y + poses_at[0].uy * w.blade_base_radius,
			poses_at[0].x + poses_at[0].ux * w.tip_radius, poses_at[0].y + poses_at[0].uy * w.tip_radius,
			poses_at[1].x + poses_at[1].ux * w.blade_base_radius, poses_at[1].y + poses_at[1].uy * w.blade_base_radius,
			poses_at[1].x + poses_at[1].ux * w.tip_radius, poses_at[1].y + poses_at[1].uy * w.tip_radius,
			contact
		)
		assert_true(contact.distance > w.blade_radius * 2.0, "precondition: blades apart at both tick ends")
	var report := ContactReport.new()
	_collision.detect(state, start, finish, _rules, _armed(), report)
	assert_true(report.blade, "the crossing blades collide")
	assert_between(SimMath.length(report.blade_ax, report.blade_ay), _rules.combatant(0).weapon.blade_base_radius, _rules.combatant(0).weapon.tip_radius, "contact lies on the sweeping blade")


## On the shipped attack manifold the origin rides a curve, so the sweep
## resamples it along the arc: a crossing that happens mid-tick, with both
## blades clear at the tick's ends, is still found, on the blade, between its
## hilt and its tip measured from the origin (WEAPON-PATH-001).
func test_the_curved_manifold_cannot_tunnel_mid_arc() -> void:
	var rules := DuelFixture.rules()
	var weapon := rules.combatant(0).weapon
	var spec := rules.combatant(0)
	assert_false(spec.handling.attack_path.is_fixed(), "fixture: the shipped sword rides its manifold")
	var state := DuelFixture.state(rules)
	var guard := ContactFixture.pose(2.4, 0.0, PI, deg_to_rad(-30.0), spec)
	var start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(-25.0), spec), guard)
	var finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(60.0), spec), guard)
	var contact := SegmentContact.new()
	for poses_at: Array[FighterPose] in [start, finish]:
		SimMath.closest_segments(
			poses_at[0].origin_x + poses_at[0].ux * weapon.blade_base_radius, poses_at[0].origin_y + poses_at[0].uy * weapon.blade_base_radius,
			poses_at[0].origin_x + poses_at[0].ux * weapon.tip_radius, poses_at[0].origin_y + poses_at[0].uy * weapon.tip_radius,
			poses_at[1].origin_x + poses_at[1].ux * weapon.blade_base_radius, poses_at[1].origin_y + poses_at[1].uy * weapon.blade_base_radius,
			poses_at[1].origin_x + poses_at[1].ux * weapon.tip_radius, poses_at[1].origin_y + poses_at[1].uy * weapon.tip_radius,
			contact
		)
		assert_true(contact.distance > weapon.blade_radius * 2.0, "precondition: blades apart at both tick ends")
	var report := ContactReport.new()
	_collision.detect(state, start, finish, rules, _armed(), report)
	assert_true(report.blade, "the crossing blades collide mid-arc")
	var reach := SimMath.length(report.blade_ax, report.blade_ay)
	assert_between(reach, weapon.blade_base_radius - 0.25, WeaponKinematics.forward_reach(spec), "on the sweeping blade (%.3f m from the centre)" % reach)


## SLASH-SHAPE-001: the 270° range is where the sword can turn, never a
## hitbox. Two targets at the same distance — inside the old radial threat
## disc (`strike_reach`) and inside this cut's arc — differ only in bearing:
## straight down the heading the swept blade reaches the torso; out at 70°,
## where the hilt track has drawn the hands in, the actual blade passes short
## of it. The first is a hit, the second a whiff, decided by the swept sword
## alone.
const SECTOR_TARGET_BEARING_DEG := 70.0
const SECTOR_SWEEP_DEG := 80.0


func test_a_target_inside_the_sector_but_outside_the_swept_blade_is_missed() -> void:
	var rules := DuelFixture.rules()
	var weapon := rules.combatant(0).weapon
	var spec := rules.combatant(0)
	var distance := WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1)) - 0.05
	var clear := rules.combatant(0).fighter.hurt_radius + weapon.blade_radius
	var reached := PackedByteArray([0, 0])
	var bearings := PackedFloat64Array([0.0, deg_to_rad(SECTOR_TARGET_BEARING_DEG)])
	for index in bearings.size():
		var bearing := bearings[index]
		var tx := distance * cos(bearing)
		var ty := distance * sin(bearing)
		## The swept blade's nearest approach to the target's centre, sampled
		## along the whole arc: geometry, before any collision code runs.
		var nearest := INF
		var pose := BladePose.new()
		for tenth in range(-roundi(SECTOR_SWEEP_DEG * 10.0), roundi(SECTOR_SWEEP_DEG * 10.0) + 1):
			WeaponKinematics.pose_at(0.0, 0.0, 0.0, deg_to_rad(tenth / 10.0), spec, pose)
			var hx := pose.point_x(weapon.blade_base_radius)
			var hy := pose.point_y(weapon.blade_base_radius)
			var px := pose.point_x(weapon.tip_radius)
			var py := pose.point_y(weapon.tip_radius)
			var t := SimMath.closest_param_on_segment(hx, hy, px, py, tx, ty)
			nearest = minf(nearest, SimMath.length(tx - SimMath.mix(hx, px, t), ty - SimMath.mix(hy, py, t)))
		reached[index] = 1 if nearest < clear else 0
		var state := DuelFixture.state(rules)
		state.fighter(0).weapon.phase = CombatPhase.Id.ACTIVE_THREAT
		## The target faces away along the bearing with its sword pointing
		## away too, so only its body can be met.
		var target := ContactFixture.pose(tx, ty, bearing, 0.0, spec)
		var start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(-SECTOR_SWEEP_DEG), spec), target)
		var finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(SECTOR_SWEEP_DEG), spec), target)
		var report := ContactReport.new()
		_collision.detect(state, start, finish, rules, _engaged(), report, false)
		assert_eq(report.body[0], reached[index] == 1, "at %.0f° the collision agrees with the swept blade (nearest %.3f m, touch %.3f m)" % [rad_to_deg(bearing), nearest, clear])
	assert_true(distance < WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1)), "fixture: both targets sit inside the radial threat disc")
	assert_eq(reached[0], 1, "fixture: down the heading the blade reaches the torso")
	assert_eq(reached[1], 0, "fixture: at %.0f°, inside the same arc, it passes short" % SECTOR_TARGET_BEARING_DEG)


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
	assert_eq(pair.phase, SwordContactSet.Phase.CONTACTING, "and the pair records it")
	_collision.detect(state, resting, resting, _rules, pair, report)
	assert_false(report.blade, "leaning on the same contact is not a second impact")
	var touch := _rules.combatant(0).weapon.blade_radius * 2.0
	var nudged := ContactFixture.poses(a, ContactFixture.pose(1.6, touch + _rules.combat.separation_epsilon * 0.5, PI, 0.0))
	_collision.detect(state, nudged, nudged, _rules, pair, report)
	assert_eq(pair.phase, SwordContactSet.Phase.SEPARATING, "drifting past touch starts separating")
	assert_false(report.blade, "but inside the hysteresis band it cannot re-strike")
	var apart := ContactFixture.poses(a, ContactFixture.pose(1.6, touch + _rules.combat.separation_epsilon * 2.0, PI, 0.0))
	_collision.detect(state, apart, apart, _rules, pair, report)
	assert_eq(pair.phase, SwordContactSet.Phase.SEPARATED, "clearing the band separates them")
	_collision.detect(state, resting, resting, _rules, pair, report)
	assert_true(report.blade, "so coming back together is a new clash")


func test_separating_inside_one_sweep_re_arms_the_pair() -> void:
	## The hysteresis is a separation requirement, not a cooldown. Blades that
	## were in contact and have genuinely come apart may clash again â€” even
	## within the same tick, which is what lets a parry be followed by a
	## re-engagement instead of a free hit.
	var state := DuelFixture.state(_rules)
	var guard := ContactFixture.pose(2.0, 0.0, PI, deg_to_rad(-30.0))
	var start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(-20.0)), guard)
	var finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(60.0)), guard)
	var band := _rules.combatant(0).weapon.blade_radius * 2.0 + _rules.combat.separation_epsilon
	assert_true(_blade_gap(start) > band, "precondition: clear of the hysteresis band at sweep start")
	var pair := _engaged()
	var report := ContactReport.new()
	_collision.detect(state, start, finish, _rules, pair, report)
	assert_true(report.blade, "the crossing registers once the pair has separated")
	assert_eq(pair.phase, SwordContactSet.Phase.CONTACTING, "and the pair is engaged again")


## CONTACT-ROLES-001: the push footprint keeps bodies apart; only the hurt
## torso is struck. A blade passing inside the footprint but outside the
## torso is a miss, while the bodies themselves still push at the footprint.
func test_the_blade_strikes_the_hurt_torso_not_the_push_footprint() -> void:
	var fighter := _rules.combatant(0).fighter
	var blade := _rules.combatant(0).weapon.blade_radius
	assert_true(fighter.hurt_radius < fighter.push_radius, "fixture: the torso is smaller than the footprint (%.3f < %.3f)" % [fighter.hurt_radius, fighter.push_radius])
	var between := (fighter.hurt_radius + fighter.push_radius) * 0.5 + blade
	var inside := fighter.hurt_radius * 0.8
	for case: Array in [[between, false, "inside the footprint, outside the torso: a miss"], [inside, true, "inside the torso: a hit"]]:
		var offset: float = case[0]
		var state := DuelFixture.state(_rules)
		state.fighter(0).weapon.phase = CombatPhase.Id.ACTIVE_THREAT
		var poses := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, 0.0), ContactFixture.pose(1.0, offset, PI, deg_to_rad(-90.0)))
		assert_near(_blade_to_point(poses[0], 1.0, offset), offset, 1e-9, "fixture: the blade passes %.3f m from the torso axis" % offset)
		var report := ContactReport.new()
		_collision.detect(state, poses, poses, _rules, _armed(), report)
		assert_false(report.blade, "fixture: the defender's blade is out of the way")
		assert_eq(report.body[0], bool(case[1]), str(case[2]))
	var spacing := fighter.push_radius * 2.0 * 0.95
	var shoulder_to_shoulder := DuelFixture.state(_rules)
	var close := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(90.0)), ContactFixture.pose(spacing, 0.0, PI, deg_to_rad(-90.0)))
	var push := ContactReport.new()
	_collision.detect(shoulder_to_shoulder, close, close, _rules, _armed(), push)
	assert_true(push.body_push, "bodies still push at the footprint (%.3f m apart)" % spacing)


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
	## Blade near the body for the full sub-interval â†’ enters once, stays inside.
	var near_start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(-5.0)), target)
	var near_finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(5.0)), target)
	_collision.detect(sweeping, near_start, near_finish, _rules, _engaged(), report)
	assert_true(report.body[0], "first entry registers as a hit")
	report.clear()
	## The lifecycle is now past ENTERED â†’ CONSTRAINING after resolution.
	## Second detect with the blade still overlapping must NOT re-damage.
	sweeping.weapon_body_contacts[0].phase = WeaponBodyContact.Phase.CONSTRAINING
	_collision.detect(sweeping, near_start, near_finish, _rules, _engaged(), report)
	assert_false(report.body[0], "continuously overlapping blade does not re-hit")


## COMBAT-007 through the real geometry and lifecycle (not just `observe()`):
## the only way one blade damages the same torso twice is a genuine separation
## past the hysteresis band and a real re-entry. This is the mechanism the
## seed-9 corpus witnesses many times over — slow blades at a clinch disengage
## by more than `separation_epsilon` past touch, then re-touch — so each is one
## honest hit per entry, never a scrape re-arming on numerical noise. The
## withdrawal precondition is asserted in metres so a future change to the gap
## math or the epsilon cannot quietly turn one episode into many.
func test_a_withdraw_past_hysteresis_then_reentry_is_a_second_body_hit() -> void:
	var touch := _rules.combatant(0).fighter.hurt_radius + _rules.combatant(0).weapon.blade_radius
	var eps := _rules.combat.separation_epsilon
	var state := DuelFixture.state(_rules)
	state.fighter(0).weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	var inside := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, 0.0), ContactFixture.pose(1.0, 0.0, PI, deg_to_rad(-90.0)))
	var clear_offset := touch + eps + 0.05
	var withdrawn := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, 0.0), ContactFixture.pose(1.0, clear_offset, PI, deg_to_rad(-90.0)))
	assert_true(_blade_to_point(inside[0], 1.0, 0.0) < touch, "fixture: the blade is inside the torso (%.3f m < %.3f m)" % [_blade_to_point(inside[0], 1.0, 0.0), touch])
	assert_true(_blade_to_point(withdrawn[0], 1.0, clear_offset) > touch + eps, "fixture: the withdrawn blade clears the torso past the hysteresis band (%.3f m > %.3f m)" % [_blade_to_point(withdrawn[0], 1.0, clear_offset), touch + eps])
	var report := ContactReport.new()
	_collision.detect(state, inside, inside, _rules, _engaged(), report)
	assert_true(report.body[0], "the first entry is a hit")
	## The resolver advances a nonlethal entry to CONSTRAINING; stepping the
	## blade back out past the band must rearm the lifecycle to OUTSIDE and
	## never damage on the way.
	state.weapon_body_contacts[0].advance_after_entry(false)
	var withdraw_hits := 0
	for _step in 4:
		if state.weapon_body_contacts[0].phase == WeaponBodyContact.Phase.OUTSIDE:
			break
		_collision.detect(state, withdrawn, withdrawn, _rules, _engaged(), report)
		if report.body[0]:
			withdraw_hits += 1
	assert_eq(withdraw_hits, 0, "withdrawing the blade is never a hit")
	assert_eq(state.weapon_body_contacts[0].phase, WeaponBodyContact.Phase.OUTSIDE, "a withdraw past the hysteresis band rearms the lifecycle")
	_collision.detect(state, inside, inside, _rules, _engaged(), report)
	assert_true(report.body[0], "a genuine re-entry is the second hit")


func test_substeps_scale_with_motion_and_cap() -> void:
	var still := ContactFixture.pose(0.0, 0.0, 0.0, 0.0)
	var idle := ContactFixture.poses(still, still)
	assert_eq(CollisionSystem.substep_count(idle, idle, _rules), 1, "no motion needs one substep")
	var turned := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, 1.0), still)
	assert_eq(CollisionSystem.substep_count(idle, turned, _rules), ceili(1.22 / 0.03), "one radian of tip travel")
	var spun := ContactFixture.poses(ContactFixture.pose(5.0, 5.0, 0.0, 3.0), ContactFixture.pose(-5.0, 0.0, 0.0, -3.0))
	assert_eq(CollisionSystem.substep_count(idle, spun, _rules), _rules.combat.max_substeps, "capped")


func test_blade_contact_outranks_body_contact_in_one_substep() -> void:
	var coarse := DuelFixture.revolute_rules()
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
	var reach := _rules.combatant(0).weapon.tip_radius + _rules.combatant(0).fighter.push_radius
	var target := ContactFixture.pose(reach, 0.0, PI, 0.0)
	var gap := 0.3
	var start := ContactFixture.poses(ContactFixture.pose(-gap, 0.0, 0.0, 0.0), target)
	var finish := ContactFixture.poses(ContactFixture.pose(gap, 0.0, 0.0, 0.0), target)
	var report := ContactReport.new()
	_collision.detect(state, start, finish, _rules, _engaged(), report)
	assert_true(report.body[0], "a neutral blade advancing tip-first produces a body contact")


func test_recovery_blade_can_produce_body_contact() -> void:
	## A blade in recovery still physically exists and can contact a body.
	## If the opponent advances onto the blade tip, the physics applies.
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	a.weapon.phase = CombatPhase.Id.RECOVERY
	a.weapon.angle = 0.0
	## The target faces away with its sword pointing back, beyond the
	## attacker's reach, so only the attacker's body contact is tested.
	var target := ContactFixture.pose(1.05, 0.0, 0.0, 0.0)
	var start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(-80.0)), target)
	var finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(80.0)), target)
	_assert_body_only_sweep(target)
	var report := ContactReport.new()
	_collision.detect(state, start, finish, _rules, _engaged(), report, false)
	assert_false(report.blade, "precondition: no blade contact competes with the body")
	assert_true(report.body[0], "a blade in recovery can produce a body contact")


## Surface gap (m) between the two shipped blades as rigid capsules, and the
## signed side of B's tip relative to A's blade line (which side it is on).
func _rigid_blades(state: MatchState, rules: DuelRules) -> Vector2:
	var w := rules.combatant(0).weapon
	var spec := rules.combatant(0)
	var a := WeaponKinematics.pose_of(state.fighter(0), spec, BladePose.new())
	var b := WeaponKinematics.pose_of(state.fighter(1), spec, BladePose.new())
	var contact := SegmentContact.new()
	SimMath.closest_segments(
		a.point_x(w.blade_base_radius), a.point_y(w.blade_base_radius), a.point_x(w.tip_radius), a.point_y(w.tip_radius),
		b.point_x(w.blade_base_radius), b.point_y(w.blade_base_radius), b.point_x(w.tip_radius), b.point_y(w.tip_radius),
		contact
	)
	var side := a.ux * (b.point_y(w.tip_radius) - a.origin_y) - a.uy * (b.point_x(w.tip_radius) - a.origin_x)
	return Vector2(contact.distance - 2.0 * w.blade_radius, signf(side))


## Two full slashes meeting head-on through the shared centre band, on the
## shipped orbit, through the real tick: each fighter loads on `side` (âˆ’1 its
## right, +1 its left) and cuts across. Returns [runner, contact event].
func _crossing_slashes(side: float) -> Array:
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 1)
	runner.skip_intro()
	var weapon := rules.combatant(0).weapon
	for slot in 2:
		ContactFixture.arm(runner.state.fighter(slot), 2.4 * slot, 0.0, PI * slot, side * deg_to_rad(70.0), -side * 14.0, CombatPhase.Id.ACTIVE_THREAT, 1.0, weapon)
	var start := _rigid_blades(runner.state, rules)
	assert_true(start.x > 0.0, "fixture: the blades start apart (%.3f m)" % start.x)
	var contact: DuelEvent = null
	for _tick in 30:
		runner.idle(1)
		contact = runner.first(DuelEventTypes.BLADE_CONTACT)
		if contact != null:
			break
	return [runner, contact, start.y]


## RIGID-CONTACT-001 at the time of impact: a right cut meeting a right cut
## through the centre band is found at first contact, the blades do not pass
## through each other in that tick, both swords are turned back by physics,
## and the left-side mirror of the whole exchange is the exact reflection.
func test_crossing_full_slashes_meet_at_first_contact_and_mirror() -> void:
	var rules := DuelFixture.rules()
	var right := _crossing_slashes(-1.0)
	var left := _crossing_slashes(1.0)
	for scenario: Array in [right, left]:
		var runner: SimRunner = scenario[0]
		var contact: DuelEvent = scenario[1]
		assert_true(contact != null, "fixture: the cuts meet")
		if contact == null:
			return
		var after := _rigid_blades(runner.state, rules)
		assert_true(after.x >= -RIGID_SLOP, "no penetration beyond slop after the resolved contact (%.4f m)" % after.x)
		assert_eq(after.y, float(scenario[2]), "and the blades are still on the sides they met from")
		for slot in 2:
			var fighter := runner.state.fighter(slot)
			assert_true(fighter.weapon.speed * fighter.weapon.swing_dir < 14.0, "slot %d's sword is turned back by the contact (%.2f rad/s)" % [slot, fighter.weapon.speed])
		var a := runner.state.fighter(0)
		var b := runner.state.fighter(1)
		assert_near(a.weapon.angle, b.weapon.angle, 1e-9, "a head-on clash is point-symmetric: equal Î¸ either side")
		assert_near(a.weapon.speed, b.weapon.speed, 1e-9, "and equal Î¸Ì‡")
	var r_contact: DuelEvent = right[1]
	var l_contact: DuelEvent = left[1]
	assert_eq(r_contact.tick, l_contact.tick, "the mirror meets on the same tick")
	assert_near(l_contact.number(DuelEventKeys.FRACTION_0), r_contact.number(DuelEventKeys.FRACTION_0), 1e-9, "at the same blade fraction")
	assert_near(l_contact.number(DuelEventKeys.IMPULSE), r_contact.number(DuelEventKeys.IMPULSE), 1e-9, "with the same impulse")
	assert_near(l_contact.number(DuelEventKeys.NORMAL_Y), -r_contact.number(DuelEventKeys.NORMAL_Y), 1e-9, "along the reflected normal")
	assert_near(l_contact.number(DuelEventKeys.Y), -r_contact.number(DuelEventKeys.Y), 1e-9, "at the reflected point")
	var r_runner: SimRunner = right[0]
	var l_runner: SimRunner = left[0]
	assert_near(l_runner.state.fighter(0).weapon.angle, -r_runner.state.fighter(0).weapon.angle, 1e-9, "ending at the reflected Î¸")
	assert_near(l_runner.state.fighter(0).weapon.speed, -r_runner.state.fighter(0).weapon.speed, 1e-9, "turning at the reflected Î¸Ì‡")


## Centerline gap along the true arc, sampled from the weapon angle. This is
## not `CollisionSystem`: a miss here is the sweep's miss.
func _arc_gap(angle_a: float, x_b: float, y_b: float, facing_b: float, angle_b: float, contact: SegmentContact) -> float:
	var weapon := _rules.combatant(0).weapon
	var spec := _rules.combatant(0)
	var a := BladePose.new()
	var b := BladePose.new()
	WeaponKinematics.pose_at(0.0, 0.0, 0.0, angle_a, spec, a)
	WeaponKinematics.pose_at(x_b, y_b, facing_b, angle_b, spec, b)
	SimMath.closest_segments(
		a.origin_x + a.ux * weapon.blade_base_radius, a.origin_y + a.uy * weapon.blade_base_radius,
		a.origin_x + a.ux * weapon.tip_radius, a.origin_y + a.uy * weapon.tip_radius,
		b.origin_x + b.ux * weapon.blade_base_radius, b.origin_y + b.uy * weapon.blade_base_radius,
		b.origin_x + b.ux * weapon.tip_radius, b.origin_y + b.uy * weapon.tip_radius,
		contact
	)
	return contact.distance


func _arc_min(start_angle: float, end_angle: float, x_b: float, y_b: float, facing_b: float, start_b: float, end_b: float, contact: SegmentContact) -> float:
	var samples := 240
	var min_gap := 1.0e9
	for i in samples + 1:
		var s := float(i) / float(samples)
		var gap := _arc_gap(start_angle + (end_angle - start_angle) * s, x_b, y_b, facing_b, start_b + (end_b - start_b) * s, contact)
		if gap < min_gap:
			min_gap = gap
	return min_gap


## A hilt that barely moves, a blade that turns through another blade, and the
## same scene shifted until the arc itself stays clear. The production sweep
## has to agree with that arc, including when both blades turn.
func test_a_rotational_crossing_and_its_near_miss_follow_the_arc() -> void:
	var weapon := _rules.combatant(0).weapon
	var band := weapon.blade_radius * 2.0
	var contact := SegmentContact.new()
	var start_a := deg_to_rad(-20.0)
	var end_a := deg_to_rad(60.0)
	var guard_angle := deg_to_rad(-30.0)
	var state := DuelFixture.state(_rules)
	var crossing := _arc_min(start_a, end_a, 2.0, 0.0, PI, guard_angle, guard_angle, contact)
	var start_gap := _arc_gap(start_a, 2.0, 0.0, PI, guard_angle, contact)
	var end_gap := _arc_gap(end_a, 2.0, 0.0, PI, guard_angle, contact)
	assert_true(crossing < band - 0.004, "fixture: the arc crosses (min %.4f m, band %.4f m)" % [crossing, band])
	assert_true(start_gap > band and end_gap > band, "fixture: both ends of that arc are clear")
	var report := ContactReport.new()
	_collision.detect(state, ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, start_a), ContactFixture.pose(2.0, 0.0, PI, guard_angle)), ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, end_a), ContactFixture.pose(2.0, 0.0, PI, guard_angle)), _rules, _armed(), report, false, false)
	assert_true(report.blade, "the sweep reports the crossing the arc found")
	assert_false(report.body[0] or report.body[1], "fixture: the body is not what the sweep found")
	var low := 0.0
	var high := 0.6
	for _i in 24:
		var mid := (low + high) * 0.5
		if _arc_min(start_a, end_a, 2.0, mid, PI, guard_angle, guard_angle, contact) < band + 0.01:
			low = mid
		else:
			high = mid
	var clear_y := high
	var clear_gap := _arc_min(start_a, end_a, 2.0, clear_y, PI, guard_angle, guard_angle, contact)
	assert_true(clear_gap > band + 0.01, "fixture: the shifted arc stays clear (min %.4f m)" % clear_gap)
	report = ContactReport.new()
	_collision.detect(state, ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, start_a), ContactFixture.pose(2.0, clear_y, PI, guard_angle)), ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, end_a), ContactFixture.pose(2.0, clear_y, PI, guard_angle)), _rules, _armed(), report, false, false)
	assert_false(report.blade, "a near miss the arc stays outside of is not a contact")
	var half := weapon.swing_speed_full * SimulationTimebase.TICK_SECONDS * 0.5
	low = 1.6
	high = 3.2
	for _i in 24:
		var mid := (low + high) * 0.5
		if _arc_min(-half, half, mid, 0.0, PI, half, -half, contact) < band - 0.004:
			low = mid
		else:
			high = mid
	var both_gap := _arc_min(-half, half, low - 0.01, 0.0, PI, half, -half, contact)
	var miss_gap := _arc_min(-half, half, high + 0.02, 0.0, PI, half, -half, contact)
	assert_true(both_gap < band - 0.004, "fixture: both blades' arcs cross (min %.4f m)" % both_gap)
	assert_true(miss_gap > band + 0.01, "fixture: and a step farther they do not (min %.4f m)" % miss_gap)
	report = ContactReport.new()
	_collision.detect(state, ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, -half), ContactFixture.pose(low - 0.01, 0.0, PI, half)), ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, half), ContactFixture.pose(low - 0.01, 0.0, PI, -half)), _rules, _armed(), report, false, false)
	assert_true(report.blade, "both blades turning through each other is a contact")
	report = ContactReport.new()
	_collision.detect(state, ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, -half), ContactFixture.pose(high + 0.02, 0.0, PI, half)), ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, half), ContactFixture.pose(high + 0.02, 0.0, PI, -half)), _rules, _armed(), report, false, false)
	assert_false(report.blade, "the same two turns, clear of each other, are not")


## Dense samples of the true poses. Not `CollisionSystem`. `out` is
## gap, attacker fraction (0 base → 1 tip), defender fraction, sample index.
func _arc_closest(start_angle: float, end_angle: float, x_b: float, y_b: float, facing_b: float, start_b: float, end_b: float, contact: SegmentContact, out: PackedFloat64Array, samples: int = 240) -> void:
	out[0] = 1.0e9
	out[1] = 0.0
	out[2] = 0.0
	out[3] = -1.0
	for i in samples + 1:
		var s := float(i) / float(samples)
		var gap := _arc_gap(start_angle + (end_angle - start_angle) * s, x_b, y_b, facing_b, start_b + (end_b - start_b) * s, contact)
		if gap < out[0]:
			out[0] = gap
			out[1] = contact.s
			out[2] = contact.t
			out[3] = float(i)


## The defender stands on +X, blade pointing back at the attacker, so the
## named place on that blade sits `gap` metres past the attacker's tip at
## angle 0. The sweep runs from `-half` to `+half` and therefore passes that
## point in the middle, not at an end.
func _defender_x(gap: float, along: float) -> float:
	var weapon := _rules.combatant(0).weapon
	return weapon.tip_radius + gap + along


func _assert_graze(name: String, half: float, along: float, tip_b: bool, start_b: float = 0.0, end_b: float = 0.0, broadside: bool = false) -> void:
	var weapon := _rules.combatant(0).weapon
	var band := weapon.blade_radius * 2.0
	var contact := SegmentContact.new()
	var found := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var hit_gap := band - 0.006
	## Broadside: the defender's blade stands across the attacker's tip, so the
	## middle of that blade — not its point — is what the tip passes.
	var x_b := weapon.tip_radius + hit_gap if broadside else _defender_x(hit_gap, along)
	var y_b := -along if broadside else 0.0
	var facing_b := PI * 0.5 if broadside else PI
	_arc_closest(-half, half, x_b, y_b, facing_b, start_b, end_b, contact, found)
	assert_true(found[0] < band - 0.004 and found[0] > band - 0.012, "%s fixture: the arc bottoms out a few millimetres inside the band (%.4f m, band %.4f m)" % [name, found[0], band])
	var finer := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	_arc_closest(-half, half, x_b, y_b, facing_b, start_b, end_b, contact, finer, 960)
	assert_true(absf(finer[0] - found[0]) < 0.001, "%s fixture: four times the samples move the minimum by less than a millimetre (%.4f m, %.4f m)" % [name, found[0], finer[0]])
	assert_true(finer[0] < band - 0.004 and finer[0] > band - 0.012, "%s fixture: the finer oracle keeps the graze inside the band (%.4f m)" % [name, finer[0]])
	assert_true(found[3] > 48.0 and found[3] < 192.0, "%s fixture: that minimum is in the middle of the sweep, not an end (sample %.0f)" % [name, found[3]])
	var start_gap := _arc_gap(-half, x_b, y_b, facing_b, start_b, contact)
	var end_gap := _arc_gap(half, x_b, y_b, facing_b, end_b, contact)
	assert_true(start_gap > band + 0.01 and end_gap > band + 0.01, "%s fixture: both ends are clear (%.4f m, %.4f m)" % [name, start_gap, end_gap])
	assert_true(found[1] > 0.75, "%s fixture: the attacker meets near its tip (fraction %.2f)" % [name, found[1]])
	if tip_b:
		assert_true(found[2] > 0.75, "%s fixture: the defender meets near its tip (fraction %.2f)" % [name, found[2]])
	else:
		assert_true(found[2] > 0.25 and found[2] < 0.75, "%s fixture: the defender meets along its middle (fraction %.2f)" % [name, found[2]])
	var state := DuelFixture.state(_rules)
	var report := ContactReport.new()
	var start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, -half), ContactFixture.pose(x_b, y_b, facing_b, start_b))
	var finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, half), ContactFixture.pose(x_b, y_b, facing_b, end_b))
	var wanted := CollisionSystem.substeps_wanted(start, finish, _rules)
	_collision.diagnostics.reset()
	_collision.detect(state, start, finish, _rules, _armed(), report, false, false)
	assert_eq(_collision.diagnostics.ccd_cap_hits, 0, "%s fixture: this pass is inside the cap (%d wanted)" % [name, wanted])
	assert_true(report.blade, "%s: the sweep reports the graze the arc found (%d substeps)" % [name, wanted])
	assert_false(report.body[0] or report.body[1], "%s: the body is not the contact" % name)
	var miss_gap := band + 0.012
	var miss_x := weapon.tip_radius + miss_gap if broadside else _defender_x(miss_gap, along)
	var miss_y := -along if broadside else 0.0
	_arc_closest(-half, half, miss_x, miss_y, facing_b, start_b, end_b, contact, found)
	assert_true(found[0] > band + 0.01, "%s fixture: one centimetre further and the arc stays clear (%.4f m)" % [name, found[0]])
	_arc_closest(-half, half, miss_x, miss_y, facing_b, start_b, end_b, contact, finer, 960)
	assert_true(finer[0] > band + 0.01, "%s fixture: the finer oracle keeps the twin clear (%.4f m)" % [name, finer[0]])
	report = ContactReport.new()
	_collision.detect(state, ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, -half), ContactFixture.pose(miss_x, miss_y, facing_b, start_b)), ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, half), ContactFixture.pose(miss_x, miss_y, facing_b, end_b)), _rules, _armed(), report, false, false)
	assert_false(report.blade, "%s: the clear twin is not a contact" % name)


## Rotation whose tip travel asks for `steps` substeps when it is the only motion.
func _angle_for_substeps(steps: float) -> float:
	var travel := steps * _rules.combat.substep_travel
	return travel / _rules.combatant(0).weapon.tip_radius


## A shallow tip pass under the budget, the same pass near the cap, a
## tip-to-tip pass, and both blades turning. Each has a clear twin. The oracle
## is the sampled arc, and the margins are millimetres, not a tangent float.
func test_shallow_tip_grazes_follow_the_arc_inside_the_substep_budget() -> void:
	var weapon := _rules.combatant(0).weapon
	var modest := _angle_for_substeps(18.0) * 0.5
	var modest_wanted := CollisionSystem.substeps_wanted(ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, -modest), ContactFixture.pose(0.0, 0.0, PI, 0.0)), ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, modest), ContactFixture.pose(0.0, 0.0, PI, 0.0)), _rules)
	assert_true(modest_wanted > 1 and modest_wanted < int(float(_rules.combat.max_substeps) * 0.5), "fixture: the modest pass is inside the budget, not at the cap (%d)" % modest_wanted)
	var mid := (weapon.blade_base_radius + weapon.tip_radius) * 0.5
	_assert_graze("tip to middle", modest, mid, false, 0.0, 0.0, true)
	_assert_graze("tip to tip", modest, weapon.tip_radius, true)
	var near_cap := _angle_for_substeps(float(_rules.combat.max_substeps) - 1.5) * 0.5
	var cap_wanted := CollisionSystem.substeps_wanted(ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, -near_cap), ContactFixture.pose(0.0, 0.0, PI, 0.0)), ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, near_cap), ContactFixture.pose(0.0, 0.0, PI, 0.0)), _rules)
	assert_true(cap_wanted >= _rules.combat.max_substeps - 2 and cap_wanted <= _rules.combat.max_substeps, "fixture: the fast pass asks for the top of the budget (%d)" % cap_wanted)
	_assert_graze("tip to middle at the cap", near_cap, mid, false, 0.0, 0.0, true)
	var each := _angle_for_substeps((float(_rules.combat.max_substeps) - 1.5) * 0.5) * 0.5
	_assert_graze("both blades", each, weapon.tip_radius, true, each, -each)


## The supported detection claim is motion whose travel stays inside the cap.
## A full swing is the actuated ceiling (18 rad/s). The corruption bound is
## faster than that and is not this claim: one tick of it wants more samples
## than `max_substeps`. The grazes above already cover a pass faster than a
## full swing and a pass at the top of the cap.
func test_a_full_swing_fits_the_cap_and_the_corruption_bound_does_not() -> void:
	var live := DuelFixture.rules()
	var weapon := live.combatant(0).weapon
	var travel := weapon.tip_radius * weapon.swing_speed_full * SimulationTimebase.TICK_SECONDS
	var wanted := ceili(travel / live.combat.substep_travel)
	assert_eq(weapon.swing_speed_full, 18.0, "fixture: the actuated ceiling is the authored full swing")
	assert_true(wanted > 1 and wanted < 18, "a full swing tick stays inside the cap, under the modest graze (%d substeps, %.3f m)" % [wanted, travel])
	var bound := SimulationGuardrails.physical_weapon_speed_bound(live.combatant(0), live.combatant(1))
	var bound_travel := weapon.tip_radius * bound * SimulationTimebase.TICK_SECONDS
	var bound_wanted := ceili(bound_travel / live.combat.substep_travel)
	assert_true(bound > weapon.swing_speed_full, "fixture: a contact can outrun the motor (%.1f rad/s)" % bound)
	assert_true(bound_wanted > live.combat.max_substeps, "the corruption bound is outside the cap (%d substeps); a graze there is not claimed" % bound_wanted)


## Past the cap the sweep does not grow. A deep cross is still reported. The
## overflow is counted. A thin graze is not claimed once the step is coarser
## than the budget these witnesses used.
func test_an_over_cap_sweep_counts_the_overflow_and_keeps_a_deep_cross() -> void:
	var weapon := _rules.combatant(0).weapon
	var band := weapon.blade_radius * 2.0
	var spun := _angle_for_substeps(float(_rules.combat.max_substeps) + 12.0)
	var contact := SegmentContact.new()
	var crossing := _arc_min(-spun * 0.5, spun * 0.5, 2.0, 0.0, PI, deg_to_rad(-30.0), deg_to_rad(-30.0), contact)
	assert_true(crossing < band - 0.02, "fixture: the arc still crosses deeply (min %.4f m)" % crossing)
	var start := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, -spun * 0.5), ContactFixture.pose(2.0, 0.0, PI, deg_to_rad(-30.0)))
	var finish := ContactFixture.poses(ContactFixture.pose(0.0, 0.0, 0.0, spun * 0.5), ContactFixture.pose(2.0, 0.0, PI, deg_to_rad(-30.0)))
	var wanted := CollisionSystem.substeps_wanted(start, finish, _rules)
	assert_true(wanted > _rules.combat.max_substeps, "fixture: the motion wants more than the cap (%d)" % wanted)
	var state := DuelFixture.state(_rules)
	var report := ContactReport.new()
	_collision.diagnostics.reset()
	_collision.detect(state, start, finish, _rules, _armed(), report, false, false)
	assert_eq(_collision.diagnostics.ccd_cap_hits, 1, "the overflow is counted")
	assert_eq(CollisionSystem.substep_count(start, finish, _rules), _rules.combat.max_substeps, "and the sweep stays at the cap")
	assert_true(report.blade, "a deep cross is still a contact when the cap binds")

