extends TestCase

## COLLIDE: swept detection never tunnels and respects contact rules
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
	var hx := pose.x + pose.ux * weapon.hilt_radius
	var hy := pose.y + pose.uy * weapon.hilt_radius
	var tx := pose.x + pose.ux * weapon.tip_radius
	var ty := pose.y + pose.uy * weapon.tip_radius
	var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, px, py)
	return SimMath.length(px - SimMath.mix(hx, tx, t), py - SimMath.mix(hy, ty, t))


func _blade_gap(poses_at: Array[FighterPose]) -> float:
	var w := _rules.combatant(0).weapon
	var contact := SegmentContact.new()
	SimMath.closest_segments(
		poses_at[0].x + poses_at[0].ux * w.hilt_radius, poses_at[0].y + poses_at[0].uy * w.hilt_radius,
		poses_at[0].x + poses_at[0].ux * w.tip_radius, poses_at[0].y + poses_at[0].uy * w.tip_radius,
		poses_at[1].x + poses_at[1].ux * w.hilt_radius, poses_at[1].y + poses_at[1].uy * w.hilt_radius,
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
	assert_between(SimMath.length(report.blade_ax, report.blade_ay), _rules.combatant(0).weapon.hilt_radius, _rules.combatant(0).weapon.tip_radius, "contact lies on the sweeping blade")


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
			poses_at[0].origin_x + poses_at[0].ux * weapon.hilt_radius, poses_at[0].origin_y + poses_at[0].uy * weapon.hilt_radius,
			poses_at[0].origin_x + poses_at[0].ux * weapon.tip_radius, poses_at[0].origin_y + poses_at[0].uy * weapon.tip_radius,
			poses_at[1].origin_x + poses_at[1].ux * weapon.hilt_radius, poses_at[1].origin_y + poses_at[1].uy * weapon.hilt_radius,
			poses_at[1].origin_x + poses_at[1].ux * weapon.tip_radius, poses_at[1].origin_y + poses_at[1].uy * weapon.tip_radius,
			contact
		)
		assert_true(contact.distance > weapon.blade_radius * 2.0, "precondition: blades apart at both tick ends")
	var report := ContactReport.new()
	_collision.detect(state, start, finish, rules, _armed(), report)
	assert_true(report.blade, "the crossing blades collide mid-arc")
	var reach := SimMath.length(report.blade_ax, report.blade_ay)
	assert_between(reach, weapon.hilt_radius - 0.25, WeaponKinematics.forward_reach(spec), "on the sweeping blade (%.3f m from the centre)" % reach)


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
			var hx := pose.point_x(weapon.hilt_radius)
			var hy := pose.point_y(weapon.hilt_radius)
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
		a.point_x(w.hilt_radius), a.point_y(w.hilt_radius), a.point_x(w.tip_radius), a.point_y(w.tip_radius),
		b.point_x(w.hilt_radius), b.point_y(w.hilt_radius), b.point_x(w.tip_radius), b.point_y(w.tip_radius),
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


## HAND-CONTACT-001 scenes, on the product Long Guard (the hands sit at the
## grip markers, out in front of the torso): fighter 1 at the origin facing
## +x with its sword at θ = 0; fighter 0's blade comes in square across fighter
## 1's sword, tip first, `along` metres from its pommel, its tip `from` → `to`
## metres off that sword's axis over the sweep. Returns [start, finish].
func _square_cut(rules: DuelRules, along: float, from: float, to: float) -> Array:
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, rules.combatant(1), BladePose.new())
	var nx := -held.uy
	var ny := held.ux
	var direction := atan2(-ny, -nx)
	var tip := WeaponKinematics.pose_at(0.0, 0.0, direction, 0.0, rules.combatant(0), BladePose.new())
	var reach := rules.combatant(0).weapon.tip_radius
	var target := ContactFixture.pose(0.0, 0.0, 0.0, 0.0, rules.combatant(1))
	var ends: Array = []
	for lateral: float in [from, to]:
		var x := held.point_x(along) + nx * lateral - tip.point_x(reach)
		var y := held.point_y(along) + ny * lateral - tip.point_y(reach)
		ends.append(ContactFixture.poses(ContactFixture.pose(x, y, direction, 0.0, rules.combatant(0)), target))
	return ends


## A state standing where `poses` are, fighter 0 driving its square cut in at
## `speed` (m/s) along the cut.
func _hand_state(rules: DuelRules, poses: Array[FighterPose], speed: float) -> MatchState:
	var state := DuelFixture.state(rules)
	for slot in 2:
		DuelFixture.place(state.fighter(slot), poses[slot].x, poses[slot].y, poses[slot].facing)
		state.fighter(slot).weapon.angle = 0.0
	state.fighter(0).vx = cos(poses[0].facing) * speed
	state.fighter(0).vy = sin(poses[0].facing) * speed
	return state


## Stand `state`'s fighters at `poses`, keeping everything else.
func _stand(state: MatchState, poses: Array[FighterPose]) -> void:
	for slot in 2:
		state.fighter(slot).x = poses[slot].x
		state.fighter(slot).y = poses[slot].y
		state.fighter(slot).facing = poses[slot].facing


## Interpolated poses at sweep fraction `s` (both cuts translate only).
func _between(start: Array[FighterPose], finish: Array[FighterPose], s: float, rules: DuelRules) -> Array[FighterPose]:
	return ContactFixture.poses(
		ContactFixture.pose(lerpf(start[0].x, finish[0].x, s), lerpf(start[0].y, finish[0].y, s), start[0].facing, 0.0, rules.combatant(0)),
		finish[1]
	)


func _count(events: Array[DuelEvent], type: StringName, region: String = "") -> int:
	var count := 0
	for event in events:
		if event.type == type and (region == "" or event.text(DuelEventKeys.REGION) == region):
			count += 1
	return count


## The blade clips an off hand and misses the handle: one HAND wound, no
## sword contact at all, no parry — a hand is hurt geometry, never steel.
func test_a_blade_clipping_a_hand_wounds_it_without_touching_steel() -> void:
	var rules := DuelFixture.rules()
	var weapon := rules.combatant(1).weapon
	var hand := rules.combatant(1).fighter.hand_radius
	var blade := rules.combatant(0).weapon.blade_radius
	var miss := (weapon.handle_radius + blade + hand + blade) * 0.5
	assert_true(miss > weapon.handle_radius + blade and miss < hand + blade, "fixture: the tip ends inside the hand, clear of the handle")
	var ends := _square_cut(rules, weapon.offhand_grip_radius, 0.25, miss)
	var start: Array[FighterPose] = ends[0]
	var finish: Array[FighterPose] = ends[1]
	var state := _hand_state(rules, finish, 3.0)
	var report := ContactReport.new()
	state.blade_contact.begin_search()
	_collision.detect(state, start, finish, rules, state.blade_contact, report)
	assert_true(report.hand[0], "the off hand is entered")
	assert_false(report.blade, "no steel is met")
	assert_false(report.body[1] or report.body[0], "nor a torso")
	assert_eq(state.blade_contact.point_count, 0, "and the swords hold no contact point")
	var events: Array[DuelEvent] = []
	var before := state.fighter(1).health
	## As the simulation does: wound at the hand's own instant, then resolve the
	## rest of the sweep — here nothing.
	_stand(state, _between(start, finish, report.hand_fraction[0], rules))
	ContactResolver.wound_hand(state, rules, 0, report.hand_grip[0], report.hand_fraction[0], 1, events)
	ContactResolver.resolve(state, report, rules, 1, report.fraction, events)
	assert_eq(_count(events, DuelEventTypes.BODY_HIT, DuelEventKeys.REGION_HAND), 1, "one HAND wound")
	assert_eq(_count(events, DuelEventTypes.PARRY), 0, "never a parry")
	assert_eq(_count(events, DuelEventTypes.BLADE_CONTACT), 0, "nor a blade contact")
	assert_true(state.fighter(1).health < before, "the hand is hurt")
	assert_true(state.fighter(0).weapon.hand_struck, "and this attack's hand episode is spent")


## A hand reached first, then the handle behind it in the same sweep: the
## HAND wound first, then the rigid HILT contact — one episode, never a parry
## (the handle does not defend its wielder).
func test_a_hand_then_the_handle_wounds_once_then_meets_steel() -> void:
	var rules := DuelFixture.rules()
	var weapon := rules.combatant(1).weapon
	var hand := rules.combatant(1).fighter.hand_radius
	var blade := rules.combatant(0).weapon.blade_radius
	## Hand entry at 30 % of the sweep, handle at 34 %.
	var travel := (hand - weapon.handle_radius) / 0.04
	var from := hand + blade + 0.30 * travel
	var ends := _square_cut(rules, weapon.offhand_grip_radius, from, from - travel)
	var start: Array[FighterPose] = ends[0]
	var finish: Array[FighterPose] = ends[1]
	var state := DuelFixture.state(rules)
	var report := ContactReport.new()
	state.blade_contact.begin_search()
	_collision.detect(state, start, finish, rules, state.blade_contact, report)
	assert_true(report.hand[0] and report.blade, "fixture: the sweep reaches a hand and then steel")
	assert_near(report.hand_fraction[0], 0.30, 0.01, "the hand at 30 %")
	assert_true(report.hand_fraction[0] < report.fraction, "before the handle")
	assert_eq(state.blade_contact.feature_b[0], SwordContactSet.Feature.HILT, "and the steel is the handle")
	var struck := _hand_state(rules, _between(start, finish, report.hand_fraction[0], rules), 3.0)
	struck.blade_contact = state.blade_contact
	var events: Array[DuelEvent] = []
	ContactResolver.wound_hand(struck, rules, 0, report.hand_grip[0], report.hand_fraction[0], 1, events)
	_stand(struck, _between(start, finish, report.fraction, rules))
	ContactResolver.resolve(struck, report, rules, 1, report.fraction, events)
	assert_eq(_count(events, DuelEventTypes.BODY_HIT, DuelEventKeys.REGION_HAND), 1, "one HAND wound")
	assert_eq(_count(events, DuelEventTypes.BLADE_CONTACT), 1, "then the rigid contact on the handle")
	assert_eq(_count(events, DuelEventTypes.PARRY), 0, "never a parry off the handle")
	var again := ContactReport.new()
	struck.blade_contact.begin_search()
	_collision.detect(struck, start, finish, rules, SwordContactSet.new(), again)
	assert_false(again.hand[0], "the same attack never wounds a hand twice")


## The guard met first shields the hand behind it: GUARD owns the contact, no
## HAND — and without the crossbar the same cut reaches the hand.
func test_a_guard_met_first_shields_the_hand() -> void:
	var rules := DuelFixture.rules()
	var weapon := rules.combatant(1).weapon
	## Just inside the crossbar's reach, between the dominant hand and the forte.
	var along := weapon.guard_centre_radius - (weapon.guard_radius + rules.combatant(0).weapon.blade_radius) * 0.85
	var ends := _square_cut(rules, along, 0.30, 0.02)
	var state := DuelFixture.state(rules)
	var report := ContactReport.new()
	state.blade_contact.begin_search()
	_collision.detect(state, ends[0], ends[1], rules, state.blade_contact, report)
	assert_true(report.blade, "steel is met")
	assert_eq(state.blade_contact.feature_b[0], SwordContactSet.Feature.GUARD, "on the guard")
	assert_true(weapon.protects(SwordContactSet.Feature.GUARD), "which defends its wielder (a parry may follow)")
	assert_false(report.hand[0], "and the hand behind it is never reached")
	var guardless := DuelFixture.rules()
	guardless.combatant(0).weapon.guard_half_span = 0.0
	guardless.combatant(1).weapon.guard_half_span = 0.0
	var bare := _square_cut(guardless, along, 0.30, 0.02)
	var exposed := ContactReport.new()
	var open_state := DuelFixture.state(guardless)
	open_state.blade_contact.begin_search()
	_collision.detect(open_state, bare[0], bare[1], guardless, open_state.blade_contact, exposed)
	assert_true(exposed.hand[0], "without the crossbar the same cut reaches the hand")
