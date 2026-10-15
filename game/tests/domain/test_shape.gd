extends TestCase

## SHAPE: the combat-shape acceptance gate for the attack track
## (WEAPON-PATH-003). θ is the sword's horizontal angle from the combat
## heading; the track only says where the carriage (the grip centre) rides. A
## right cut and a left cut are mirrored traversals of the same track,
## overlapping through the centre and Long Guard — so the left and right
## attacks must be mathematical reflections of one another, in pose, sweep and
## contact, with no hand or guard ever inside the torso.
##
## Implements: /spec/invariants.md#weapon-path-003
## See also: /docs/concepts/combat.md

## Visible air between a hand (or the guard) and the torso at the postures.
const VISIBLE_AIR := 0.02
const POSTURES_DEG: PackedFloat64Array = [0.0, 45.0, 80.0, 135.0]
const MIRROR := 1e-9

var _rules: DuelRules


func _init() -> void:
	suite_name = "SHAPE"
	_rules = DuelFixture.rules()


func _pose(angle: float) -> BladePose:
	return WeaponKinematics.pose_at(0.0, 0.0, 0.0, angle, _rules.combatant(0), BladePose.new())


## Every degree, both sides: forward is even, lateral is odd, and the blade's
## yaw is the reflection of its mirror — C(−θ) = mirror(C(θ)), yaw(−θ) = −yaw(θ).
func test_the_track_and_the_blade_mirror_at_every_degree() -> void:
	assert_false(_rules.combatant(0).handling.attack_path.is_fixed(), "fixture: the shipped sword rides its track")
	for degrees in range(0, 136):
		var angle := deg_to_rad(float(degrees))
		var left := _pose(angle)
		var right := _pose(-angle)
		assert_near(left.carriage_forward, right.carriage_forward, MIRROR, "carriage forward is even at ±%d°" % degrees)
		assert_near(left.carriage_left, -right.carriage_left, MIRROR, "carriage lateral is odd at ±%d°" % degrees)
		assert_near(left.ux, right.ux, MIRROR, "blade forward component mirrors at ±%d°" % degrees)
		assert_near(left.uy, -right.uy, MIRROR, "blade lateral component mirrors at ±%d°" % degrees)
		assert_near(SimMath.wrap_angle(SimMath.arctan2(left.uy, left.ux) - angle), 0.0, MIRROR, "yaw is exactly θ at %d°" % degrees)


## Shape-preserving: away from the centre the carriage only falls back and only
## draws out, so it never loops or backtracks, and the postures read in order.
func test_the_carriage_never_loops_and_the_postures_read_in_order() -> void:
	var previous := _pose(0.0)
	for degrees in range(1, 136):
		var pose := _pose(deg_to_rad(float(degrees)))
		assert_true(pose.carriage_forward <= previous.carriage_forward + MIRROR, "forward never rises away from the centre (%d°)" % degrees)
		assert_true(pose.carriage_left >= previous.carriage_left - MIRROR, "lateral never falls away from the centre (%d°)" % degrees)
		previous = pose
	var forward := PackedFloat64Array()
	var lateral := PackedFloat64Array()
	for degrees in POSTURES_DEG:
		var pose := _pose(deg_to_rad(degrees))
		forward.append(pose.carriage_forward)
		lateral.append(pose.carriage_left)
	assert_true(forward[0] > forward[1] and forward[1] > forward[2] and forward[2] > forward[3], "forward: Long Guard > Ready > Gather > Load (%s)" % forward)
	assert_true(lateral[0] < lateral[1] and lateral[1] < lateral[2] and lateral[2] < lateral[3], "lateral: Long Guard < Ready < Gather < Load (%s)" % lateral)
	assert_near(lateral[0], 0.0, MIRROR, "Long Guard is on the centreline")


## LONG-GUARD-GEOMETRY-001: Long Guard is a rounded top, not a point. The centre is
## the track's farthest-forward hilt with a flat tangent; everything inside the
## corridor's leave edge stays within a few centimetres of it and ahead of
## everything outside; and the hilt never travels fast relative to θ, so a cut
## reads as the blade rotating through the hands, not the hands lunging.
const CORRIDOR_LEAVE_DEG := 18.0
## Most the hilt may drop inside the corridor (m).
const TOP_DROP := 0.04
## Steepest the hands may travel anywhere (m per radian of θ). The blade's own
## rotation moves its centre of percussion ~0.7 m per radian about the hands,
## so a hilt drawing back at up to a quarter metre per radian (the v40 track's
## Ready → Gather compression, ~0.23) still reads as the blade turning through
## the hands; a lunging hilt is roughly twice that.
const MAX_TRACK_SLOPE := 0.25


func test_long_guard_is_a_rounded_top_and_the_hilt_never_lunges() -> void:
	var centre := _pose(0.0)
	assert_near(centre.d_carriage_forward, 0.0, MIRROR, "the forward tangent is flat at the centre")
	var lowest_inside := INF
	var highest_outside := -INF
	var steepest := 0.0
	for tenth in range(-1350, 1351):
		var degrees := tenth / 10.0
		var pose := _pose(deg_to_rad(degrees))
		steepest = maxf(steepest, Vector2(pose.d_carriage_forward, pose.d_carriage_left).length())
		if absf(degrees) <= CORRIDOR_LEAVE_DEG:
			lowest_inside = minf(lowest_inside, pose.carriage_forward)
		else:
			highest_outside = maxf(highest_outside, pose.carriage_forward)
	assert_true(centre.carriage_forward >= lowest_inside, "the centre is the farthest-forward hilt")
	assert_true(centre.carriage_forward - lowest_inside <= TOP_DROP, "inside the corridor the hilt stays within %.0f cm of it (drops %.3f m)" % [TOP_DROP * 100.0, centre.carriage_forward - lowest_inside])
	assert_true(lowest_inside >= highest_outside, "and ahead of every hilt outside the corridor (%.3f ≥ %.3f)" % [lowest_inside, highest_outside])
	assert_true(steepest <= MAX_TRACK_SLOPE, "the hilt never travels more than %.2f m per radian of θ (steepest %.3f)" % [MAX_TRACK_SLOPE, steepest])
	## LONG-GUARD-GEOMETRY-001: Long Guard is also the longest point — no
	## angled blade anywhere on the track reaches farther forward than the tip
	## straight down the heading.
	var weapon := _rules.combatant(0).weapon
	var longest := centre.point_x(weapon.tip_radius)
	var farther := 0
	for tenth in range(-1350, 1351):
		if tenth != 0 and _pose(deg_to_rad(tenth / 10.0)).point_x(weapon.tip_radius) > longest + MIRROR:
			farther += 1
	assert_eq(farther, 0, "no θ puts the tip farther forward than Long Guard (%.3f m)" % longest)
	## Perturb: the v30 Long Guard depth with a deeper centre bolted on and the
	## Ready knot left behind makes the hilt lunge through the corridor.
	var lunging := DuelFixture.rules()
	var knots := PackedFloat64Array([0.0, deg_to_rad(15.0), deg_to_rad(45.0), deg_to_rad(80.0), deg_to_rad(135.0)])
	lunging.combatant(0).handling.attack_path = WeaponAttackPath.from_carriage_knots(knots, PackedFloat64Array([0.63, 0.61, 0.37, 0.33, 0.30]), PackedFloat64Array([0.0, 0.045, 0.14, 0.19, 0.20]))
	var worst := 0.0
	for degrees in range(-135, 136):
		var pose := WeaponKinematics.pose_at(0.0, 0.0, 0.0, deg_to_rad(float(degrees)), lunging.combatant(0), BladePose.new())
		worst = maxf(worst, Vector2(pose.d_carriage_forward, pose.d_carriage_left).length())
	assert_true(worst > MAX_TRACK_SLOPE, "control: a deep centre with the Ready knot left behind lunges (%.3f m/rad)" % worst)


## Surface to surface, never centre to circle: each hand's surface and the
## whole rigid sword, pommel to tip, clear the hurt torso over the whole track,
## and the hands keep visible air at the postures (the sword's visible air is
## judged against the real clothes in PRES-RIG). Pulling the carriage in until
## anything is inside the torso makes the rules invalid — the duel is
## unavailable, not quietly re-tracked.
func test_no_hand_or_any_part_of_the_sword_ever_enters_the_torso() -> void:
	var least := WeaponKinematics.least_surface_gap(_rules.combatant(0))
	assert_true(least >= 0.0, "no hand or sword surface inside the torso anywhere (least %.4f m)" % least)
	for degrees in POSTURES_DEG:
		var gap := WeaponKinematics.hand_gap_at(_rules.combatant(0), deg_to_rad(degrees))
		assert_true(gap >= VISIBLE_AIR, "the hands keep visible air at the %d° posture (%.4f m)" % [int(degrees), gap])
		assert_true(WeaponKinematics.sword_gap_at(_rules.combatant(0), deg_to_rad(degrees)) >= 0.0, "and the sword clears the torso there")
		assert_true(WeaponKinematics.crossguard_gap_at(_rules.combatant(0), deg_to_rad(degrees)) >= 0.0, "and so does the crossguard")
	var tight := DuelFixture.rules()
	tight.combatant(0).fighter.hurt_radius += least + 0.01
	## A hurt torso may never exceed the push body (CONTACT-ROLES-001), so the
	## body grows with it: only the hands' clearance is broken.
	tight.combatant(0).fighter.push_radius = maxf(tight.combatant(0).fighter.push_radius, tight.combatant(0).fighter.hurt_radius)
	assert_true(tight.combatant(0).fighter.is_valid(), "perturbation: the torso grew past the hands but is still a legal body")
	assert_true(WeaponKinematics.least_surface_gap(tight.combatant(0)) < 0.0, "now part of the held sword is inside it")
	assert_true(tight.problem().contains("inside the hurt torso"), "the rules say why (%s)" % tight.problem())
	assert_true(DuelSimulation.create(tight) == null, "and fail closed: no duel")
	assert_eq(_rules.problem(), "", "the shipped rules have no problem")


## The v24 orbit cleared the hands but carried the pommel 0.19 m behind them —
## into the belly at Long Guard. Checking the hands alone passed it; checking
## the rigid sword rejects it, so an orbit nobody could hold never ships.
func test_an_orbit_that_puts_the_pommel_in_the_belly_is_rejected() -> void:
	var knots := PackedFloat64Array([0.0, deg_to_rad(45.0), deg_to_rad(80.0), deg_to_rad(135.0)])
	var v24 := DuelFixture.rules()
	v24.combatant(0).handling.attack_path = WeaponAttackPath.from_carriage_knots(knots, PackedFloat64Array([0.29, 0.255, 0.19, 0.12]), PackedFloat64Array([0.0, 0.14, 0.21, 0.25]))
	## Held high, up by the guard, so the hands clear while the pommel trails:
	## only the whole-sword check can catch it.
	v24.combatant(0).weapon.offhand_grip_radius = 0.15
	v24.combatant(0).weapon.dominant_grip_radius = 0.225
	assert_true(v24.combatant(0).handling.attack_path != null and v24.combatant(0).weapon.is_valid(), "fixture: the v24 knots are a well-formed orbit")
	assert_true(WeaponKinematics.hand_gap_at(v24.combatant(0), 0.0) >= 0.0, "fixture: its hands clear the torso at Long Guard (%.4f m)" % WeaponKinematics.hand_gap_at(v24.combatant(0), 0.0))
	assert_true(WeaponKinematics.sword_gap_at(v24.combatant(0), 0.0) < 0.0, "but its pommel is inside it (%.4f m)" % WeaponKinematics.sword_gap_at(v24.combatant(0), 0.0))
	assert_true(v24.problem().contains("inside the hurt torso"), "so the rules say why (%s)" % v24.problem())
	assert_true(DuelSimulation.create(v24) == null, "and fail closed")
	assert_true(WeaponKinematics.sword_gap_at(_rules.combatant(0), 0.0) >= 0.0, "the shipped orbit carries the pommel clear (%.4f m)" % WeaponKinematics.sword_gap_at(_rules.combatant(0), 0.0))


## Malformed knots never make a track: every shape law the track relies on is
## checked at content load and named.
func test_malformed_tracks_fail_closed_with_a_reason() -> void:
	var knots := PackedFloat64Array([0.0, 1.0, 2.0])
	var good_forward := PackedFloat64Array([0.3, 0.25, 0.2])
	var good_lateral := PackedFloat64Array([0.0, 0.1, 0.2])
	assert_eq(WeaponAttackPath.knot_problem(knots, good_forward, good_lateral), "", "fixture: a well-formed track")
	assert_true(WeaponAttackPath.from_carriage_knots(knots, good_forward, good_lateral) != null, "fixture: which builds")
	var cases := {
		"forward rises": [knots, PackedFloat64Array([0.3, 0.32, 0.2]), good_lateral],
		"lateral falls": [knots, good_forward, PackedFloat64Array([0.0, 0.2, 0.1])],
		"off the centreline": [knots, good_forward, PackedFloat64Array([0.01, 0.1, 0.2])],
		"not ascending": [PackedFloat64Array([0.0, 2.0, 1.0]), good_forward, good_lateral],
		"not the centre": [PackedFloat64Array([0.1, 1.0, 2.0]), good_forward, good_lateral],
		"counts differ": [knots, PackedFloat64Array([0.3, 0.25]), good_lateral],
		"fewer than two": [PackedFloat64Array([0.0]), PackedFloat64Array([0.3]), PackedFloat64Array([0.0])],
	}
	for label: String in cases:
		var table: Array = cases[label]
		var reason := WeaponAttackPath.knot_problem(table[0], table[1], table[2])
		assert_true(reason != "", "%s is named (%s)" % [label, reason])
		assert_true(WeaponAttackPath.from_carriage_knots(table[0], table[1], table[2]) == null, "%s builds no track" % label)


## Drive a full charge from the guard on `side` (−1 right, +1 left) through the
## real input language, recording θ every tick from the press until settled.
func _full_charge(side: float) -> WeaponRig:
	var rig := WeaponRig.create(_rules)
	rig.fighter.weapon.angle = side * _rules.combatant(0).weapon.guard_angle
	WeaponSystem.update_stable_side(rig.fighter.weapon, _rules.combatant(0).weapon)
	rig.press()
	rig.hold(600)
	rig.release()
	rig.settle()
	return rig


## The two full-charge attacks are reflections of each other tick for tick:
## right-origin −135° → +45°, left-origin +135° → −45°. Their commanded sweeps
## overlap across [−45°, +45°] and together cover the whole 270°.
func test_full_charges_from_either_side_are_exact_mirrors() -> void:
	var right := _full_charge(-1.0)
	var left := _full_charge(1.0)
	var right_release := right.events_of(DuelEventTypes.ATTACK_RELEASED)
	var left_release := left.events_of(DuelEventTypes.ATTACK_RELEASED)
	assert_eq(right_release.size(), 1, "fixture: one right-origin swing")
	assert_eq(left_release.size(), 1, "fixture: one left-origin swing")
	assert_eq(right.angles.size(), left.angles.size(), "both took the same number of ticks")
	for tick in right.angles.size():
		assert_near(left.angles[tick], -right.angles[tick], MIRROR, "θ_L(t) = −θ_R(t) at tick %d" % tick)
	var limit := rad_to_deg(_rules.combatant(0).weapon.guard_limit)
	var right_from := -limit
	var right_to := rad_to_deg(right.fighter.weapon.swing_end)
	var left_from := limit
	var left_to := rad_to_deg(left.fighter.weapon.swing_end)
	assert_near(right_to, 45.0, 1e-9, "a full right-origin charge commands −135° → +45°")
	assert_near(left_to, -45.0, 1e-9, "a full left-origin charge commands +135° → −45°")
	assert_near(maxf(right_from, left_to), -45.0, 1e-9, "the commanded sweeps overlap from −45°")
	assert_near(minf(right_to, left_from), 45.0, 1e-9, "to +45°")
	assert_near(minf(right_from, left_to), -limit, 1e-9, "and together cover from −135°")
	assert_near(maxf(right_to, left_from), limit, 1e-9, "to +135°")


## The same cut against the same stationary opponent, mirrored across the
## attacker's combat heading: first contact on the same tick, at the mirrored
## point and fraction, with the mirrored normal and the same impulse, leaving
## the mirrored θ and θ̇. Nothing in the track favours a side.
func _cut_into_stationary_opponent(side: float) -> SimRunner:
	var runner := SimRunner.create(_rules, 3)
	runner.skip_intro()
	var a := runner.state.fighter(0)
	var b := runner.state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 1.25, 0.0, PI)
	a.duel_forward_x = 1.0
	a.duel_forward_y = 0.0
	b.duel_forward_x = -1.0
	b.duel_forward_y = 0.0
	a.weapon.angle = side * _rules.combatant(0).weapon.guard_angle
	WeaponSystem.update_stable_side(a.weapon, _rules.combatant(0).weapon)
	b.weapon.angle = side * deg_to_rad(100.0)
	WeaponSystem.update_stable_side(b.weapon, _rules.combatant(0).weapon)
	runner.push(PlayerCommand.create(runner.state.tick, 0.0, 0.0, true, false), PlayerCommand.idle(runner.state.tick))
	for _i in 120:
		if a.weapon.charge >= 1.0:
			break
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, 0.0, false, false), PlayerCommand.idle(runner.state.tick))
	runner.push(PlayerCommand.create(runner.state.tick, 0.0, 0.0, false, true), PlayerCommand.idle(runner.state.tick))
	for _i in 60:
		if runner.first(DuelEventTypes.BODY_HIT) != null or runner.first(DuelEventTypes.BLADE_CONTACT) != null:
			break
		runner.idle(1)
	return runner


func test_mirrored_cuts_make_mirrored_contacts() -> void:
	var right := _cut_into_stationary_opponent(-1.0)
	var left := _cut_into_stationary_opponent(1.0)
	var right_hit := right.first(DuelEventTypes.BODY_HIT)
	var left_hit := left.first(DuelEventTypes.BODY_HIT)
	assert_true(right_hit != null and left_hit != null, "fixture: both full charges reach the body (right %s, left %s)" % [right_hit != null, left_hit != null])
	assert_true(right.is_sound() and left.is_sound(), "fixture: legal states")
	if right_hit == null or left_hit == null:
		return
	assert_true(right.first(DuelEventTypes.ATTACK_RELEASED).number(DuelEventKeys.CHARGE) >= 1.0, "fixture: a full charge, released")
	assert_eq(left_hit.tick, right_hit.tick, "first contact on the same tick")
	assert_near(left_hit.number(DuelEventKeys.X), right_hit.number(DuelEventKeys.X), MIRROR, "at the mirrored point (x)")
	assert_near(left_hit.number(DuelEventKeys.Y), -right_hit.number(DuelEventKeys.Y), MIRROR, "at the mirrored point (y)")
	assert_near(left_hit.number(DuelEventKeys.BLADE_FRACTION), right_hit.number(DuelEventKeys.BLADE_FRACTION), MIRROR, "the same blade fraction")
	assert_near(left_hit.number(DuelEventKeys.NORMAL_X), right_hit.number(DuelEventKeys.NORMAL_X), MIRROR, "the mirrored normal (x)")
	assert_near(left_hit.number(DuelEventKeys.NORMAL_Y), -right_hit.number(DuelEventKeys.NORMAL_Y), MIRROR, "the mirrored normal (y)")
	assert_near(left_hit.number(DuelEventKeys.PUSH), right_hit.number(DuelEventKeys.PUSH), MIRROR, "the same impulse")
	assert_near(left_hit.number(DuelEventKeys.DAMAGE), right_hit.number(DuelEventKeys.DAMAGE), MIRROR, "the same damage")
	var a_right := right.state.fighter(0).weapon
	var a_left := left.state.fighter(0).weapon
	assert_near(a_left.angle, -a_right.angle, MIRROR, "leaving the mirrored θ")
	assert_near(a_left.speed, -a_right.speed, MIRROR, "and the mirrored θ̇")


## Long Guard is a θ band, not a mode, and it has no secret side: seated at +8°
## or −8° the poses mirror, a walk-in is a POKE and a committed forward burst a
## THRUST from either seat, and an attack from the seat is the ordinary,
## mirrored cut.
func test_long_guard_is_symmetric_from_either_seat() -> void:
	for side: float in [1.0, -1.0]:
		var seat := side * deg_to_rad(8.0)
		var mirror := _pose(-seat)
		var pose := _pose(seat)
		assert_near(pose.carriage_forward, mirror.carriage_forward, MIRROR, "the seat at %+.0f° mirrors its partner (forward)" % rad_to_deg(seat))
		assert_near(pose.point_x(_rules.combatant(0).weapon.tip_radius), mirror.point_x(_rules.combatant(0).weapon.tip_radius), MIRROR, "the point threatens equally far forward")
		for burst: bool in [false, true]:
			var state := DuelFixture.state(_rules)
			var a := state.fighter(0)
			var b := state.fighter(1)
			DuelFixture.place(a, 0.0, 0.0, 0.0)
			a.weapon.phase = CombatPhase.Id.NEUTRAL
			a.weapon.angle = seat
			a.weapon.speed = 0.0
			a.vx = 6.0
			var tip := WeaponKinematics.pose_of(a, _rules.combatant(0), BladePose.new())
			var tip_x := tip.point_x(_rules.combatant(0).weapon.tip_radius)
			var tip_y := tip.point_y(_rules.combatant(0).weapon.tip_radius)
			DuelFixture.place(b, tip_x + tip.ux * _rules.combatant(0).fighter.hurt_radius, tip_y + tip.uy * _rules.combatant(0).fighter.hurt_radius, PI)
			if burst:
				a.gesture.mode = MovementGestureState.Mode.BURST
				a.gesture.burst_kind = MovementGestureState.BurstKind.FORWARD_DASH
				a.gesture.burst_ticks_remaining = 5
				a.gesture.burst_dir_x = 1.0
				a.gesture.burst_dir_y = 0.0
			var kind := DamageModel.classify_contact(ImpactModel.resolve(a, b, tip_x, tip_y, _rules), a, _rules)
			var expected := StrikeResult.ContactKind.THRUST if burst else StrikeResult.ContactKind.POKE
			assert_eq(kind, expected, "%s from the %+.0f° seat is a %s" % ["a burst" if burst else "a walk-in", rad_to_deg(seat), "THRUST" if burst else "POKE"])
	var ends := PackedFloat64Array()
	for side: float in [1.0, -1.0]:
		var rig := WeaponRig.create(_rules)
		rig.fighter.weapon.angle = side * deg_to_rad(8.0)
		WeaponSystem.update_stable_side(rig.fighter.weapon, _rules.combatant(0).weapon)
		rig.step(true, true)
		assert_eq(rig.events_of(DuelEventTypes.ATTACK_RELEASED).size(), 1, "an attack from the %+.0f° seat is an ordinary cut" % (side * 8.0))
		ends.append(rig.fighter.weapon.swing_end)
	assert_near(ends[0], -ends[1], MIRROR, "and the two seats' cuts are mirror images (%.1f° vs %.1f°)" % [rad_to_deg(ends[0]), rad_to_deg(ends[1])])
