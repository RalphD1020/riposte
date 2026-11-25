extends TestCase

## QUICK-90: the quick attack is a physically driven 90° command from wherever
## the blade is (COMBAT-001), its unopposed timing on the reference duelist is
## pinned as a regression baseline, and its follow-through is the blade's own
## torque-limited stop — never a snap to the commanded end.
##
## See also: /docs/concepts/combat.md

const STARTS := [-135.0, -90.0, -45.0, -20.0, -5.0, 0.0, 5.0, 20.0, 45.0, 90.0, 135.0]
## A free attack completes when it settles within this of its commanded end (θ never snapped).
const SETTLE_TOLERANCE_DEG := 5.0

var _rules: DuelRules


func _init() -> void:
	suite_name = "QUICK-90"
	_rules = DuelFixture.rules()


## A tap from `start` (degrees), stepped until the blade is back under control.
## Exactly at 0° the committed side is the right one, so the cut runs to +90°.
func _tap(start: float) -> Dictionary:
	var rig := WeaponRig.create(_rules)
	rig.fighter.weapon.reset(deg_to_rad(start))
	if is_zero_approx(start):
		rig.fighter.weapon.stable_side = -1.0
		rig.fighter.weapon.swing_dir = 1.0
	rig.step(true, true)
	var weapon := rig.fighter.weapon
	var dir := weapon.swing_dir
	var arc := absf(weapon.swing_end - weapon.swing_start)
	var near := -1
	var settled := -1
	var travel := 0.0
	var peak := 0.0
	var largest_step := 0.0
	var previous := weapon.speed
	for tick in 120:
		rig.step()
		travel = maxf(travel, (weapon.angle - weapon.swing_start) * dir)
		peak = maxf(peak, absf(weapon.speed))
		## Every tick the motor takes speed away from the cut is a brake tick.
		if absf(weapon.speed) < absf(previous) and weapon.speed * previous >= 0.0:
			largest_step = maxf(largest_step, absf(weapon.speed - previous))
		previous = weapon.speed
		if near < 0 and travel >= arc - deg_to_rad(SETTLE_TOLERANCE_DEG):
			near = tick + 1
		if settled < 0 and travel > 0.0 and absf(weapon.speed) <= SimMath.EPSILON:
			settled = tick + 1
		if weapon.phase == CombatPhase.Id.NEUTRAL and tick > 5:
			break
	return {"dir": dir, "arc": arc, "end": weapon.swing_end, "travel": travel, "near": near, "settled": settled,
		"peak": peak, "largest_brake_step": largest_step, "preparation": weapon.launch_preparation}


## The least weapon-coordinate inertia anywhere on the track (1° samples): the
## largest speed change a torque can make in one tick.
func _least_inertia() -> float:
	var spec := _rules.combatant(0)
	var least := INF
	for degrees in range(-135, 136):
		least = minf(least, WeaponKinematics.motor_inertia(spec, deg_to_rad(float(degrees))))
	return least


func test_a_quick_attack_commands_ninety_degrees_from_anywhere_and_gets_there() -> void:
	## ARRANGE: the reference duelist's sword, idle at every start angle.
	var weapon := _rules.combatant(0).weapon
	assert_near(rad_to_deg(weapon.min_arc), 90.0, 1e-9, "fixture: the quick arc is 90°")
	for start: float in STARTS:
		## ACT: a tap (press and release inside one tick).
		var tap := _tap(start)
		## ASSERT: a 90° command away from the committed side, inside the guard
		## limit, and the motor carries the blade there unopposed and settles it.
		assert_near(rad_to_deg(tap["arc"]), 90.0, 1e-6, "from %+.0f° the tap commands 90°" % start)
		assert_true(absf(tap["end"]) <= weapon.guard_limit + 1e-9, "from %+.0f° the commanded end stays inside the guard limit" % start)
		assert_between(rad_to_deg(tap["travel"]), 90.0 - SETTLE_TOLERANCE_DEG, 90.0 + SETTLE_TOLERANCE_DEG, "from %+.0f° the blade physically reaches its 90° (%.1f°)" % [start, rad_to_deg(tap["travel"])])
		assert_true(tap["settled"] > 0, "from %+.0f° the blade comes to rest there" % start)
	## PERTURB: the mirror. A tap from -θ and from +θ are the same cut mirrored.
	for start: float in [20.0, 45.0, 90.0, 135.0]:
		var right := _tap(-start)
		var left := _tap(start)
		assert_eq(right["near"], left["near"], "±%.0f° complete in the same tick" % start)
		assert_eq(right["settled"], left["settled"], "and settle in the same tick")
		assert_near(right["travel"], left["travel"], 1e-9, "and travel the same arc")
		assert_true(right["dir"] == -left["dir"], "in mirrored directions")


## THRUST-BOUNDARY precondition (today's rules; W-THRUST adds the axial branch
## as a versioned change): a tap inside the planned ±30° thrust sector is a 90°
## cut, and a hold records its press angle once and keeps it however far the
## blade winds, so an attack family classified from it cannot change mid-attack.
func test_the_press_angle_is_recorded_once_for_the_attack_family() -> void:
	## ARRANGE: a hold pressed at -20° (inside the planned sector).
	var rig := WeaponRig.create(_rules)
	rig.fighter.weapon.reset(deg_to_rad(-20.0))
	var weapon := _rules.combatant(0).weapon
	## ACT: press, then hold past the tap threshold while the blade winds out
	## through -30° and on toward the load.
	rig.press()
	var pressed_at := rig.fighter.weapon.hold_start_angle
	var crossed_boundary := false
	for _i in weapon.tap_threshold_ticks + 60:
		rig.step()
		crossed_boundary = crossed_boundary or absf(rig.fighter.weapon.angle) > deg_to_rad(30.0)
		## ASSERT: the press angle never moves while the action lasts.
		assert_near(rig.fighter.weapon.hold_start_angle, pressed_at, 1e-12, "the press angle stays the one recorded at the press")
	assert_near(rad_to_deg(pressed_at), -20.0, 1e-9, "it is the angle at the press")
	assert_eq(rig.fighter.weapon.phase, CombatPhase.Id.CHARGING, "a hold past the threshold charges")
	assert_true(crossed_boundary, "fixture: the blade wound out across the planned ±30° boundary")
	## PERTURB: taps from inside the sector are 90° cuts, never anything else.
	for start: float in [-20.0, -5.0, 0.0, 5.0, 20.0]:
		var tap := _tap(start)
		assert_near(rad_to_deg(tap["arc"]), 90.0, 1e-6, "a tap at %+.0f° is a 90° cut" % start)


func test_quick_timing_is_pinned_on_the_reference_duelist() -> void:
	## ARRANGE / ACT: prepared (Ready, far round) and under-prepared (near centre) taps.
	var weapon := _rules.combatant(0).weapon
	var ready := _tap(-45.0)
	var far := _tap(-135.0)
	var near := _tap(-20.0)
	var centre := _tap(0.0)
	## ASSERT: the baseline the 50/50 tuning starts from (60 Hz ticks, unopposed,
	## release to near-completion — within the settle tolerance of the
	## commanded 90° — not to a stop or back to Ready).
	assert_eq(ready["near"], 10, "a tap from Ready completes its 90° in 10 ticks (~0.17 s)")
	assert_eq(far["near"], 9, "and from the full load in 9")
	assert_eq(near["near"], 12, "from ±20° in 12")
	assert_eq(centre["near"], 15, "from the centre in 15 (~0.25 s)")
	assert_near(ready["peak"], weapon.achievable_swing_speed(0.0, 1.0), 1e-9, "a prepared tap reaches the tap target speed")
	assert_near(centre["peak"], weapon.achievable_swing_speed(0.0, 0.0), 1e-9, "a centre tap reaches the preparation floor's share of it")
	assert_near(centre["peak"] / ready["peak"], weapon.preparation_floor, 1e-9, "the floor is 0.55 of a prepared tap")
	## PERTURB: preparation is monotone in |θ| up to the guard, not a step.
	assert_true(centre["peak"] < near["peak"] and near["peak"] < ready["peak"], "less prepared, slower (%.2f < %.2f < %.2f rad/s)" % [centre["peak"], near["peak"], ready["peak"]])


func test_the_follow_through_is_the_blades_own_torque_limited_stop() -> void:
	## ARRANGE: taps and a full charge, their speed and inertia where they cross
	## the commanded end, and the brake each attack carries.
	var weapon := _rules.combatant(0).weapon
	var drive := _rules.combatant(0).fighter.weapon_torque_scale
	for start: float in [-45.0, -135.0, 0.0]:
		## ACT
		var tap := _tap(start)
		var settle: float = tap["travel"] - tap["arc"]
		## ASSERT: the attack's own brake, started from its stopping distance,
		## settles the blade at the commanded end (±5°, nothing clamps it), and no
		## brake tick removes more speed than the brake can.
		assert_between(rad_to_deg(settle), -SETTLE_TOLERANCE_DEG, SETTLE_TOLERANCE_DEG, "from %+.0f° the free stop settles %.1f° from the commanded end" % [start, rad_to_deg(settle)])
		var cap := drive * weapon.brake_torque_tap / _least_inertia() * SimulationTimebase.TICK_SECONDS
		assert_true(tap["largest_brake_step"] <= cap + 1e-9, "no snap: the largest braking step (%.2f rad/s) is within the brake's own limit (%.2f)" % [tap["largest_brake_step"], cap])
	## PERTURB: a full charge. Its 180° command reaches the full target speed and
	## its gentler full-charge brake still settles it at the end (it used to
	## overrun to ~242° when braking waited for the endpoint).
	var rig := WeaponRig.create(_rules)
	rig.press()
	while rig.fighter.weapon.charge < 1.0 and rig.tick < 240:
		rig.step()
	rig.release()
	var w := rig.fighter.weapon
	var travel := 0.0
	var peak := 0.0
	for _i in 120:
		rig.step()
		travel = maxf(travel, (w.angle - w.swing_start) * w.swing_dir)
		peak = maxf(peak, absf(w.speed))
		if w.phase == CombatPhase.Id.NEUTRAL:
			break
	var arc := absf(w.swing_end - w.swing_start)
	assert_near(rad_to_deg(arc), 180.0, 1e-6, "a full charge commands 180°")
	assert_near(peak, weapon.swing_speed_full, 1e-6, "and reaches the full target speed")
	assert_between(rad_to_deg(travel - arc), -SETTLE_TOLERANCE_DEG, SETTLE_TOLERANCE_DEG, "its stop %.1f° from the end is the brake's, not a runaway" % rad_to_deg(travel - arc))


## A cut wound to `charge` from `start` (degrees) and released, its rig returned
## still at the release tick.
func _released(start: float, charge: float) -> WeaponRig:
	var rig := WeaponRig.create(_rules)
	rig.fighter.weapon.reset(deg_to_rad(start))
	if is_zero_approx(start):
		rig.fighter.weapon.stable_side = -1.0
		rig.fighter.weapon.swing_dir = 1.0
	if charge <= 0.0:
		rig.step(true, true)
		return rig
	rig.press()
	while rig.fighter.weapon.charge < charge and rig.tick < 240:
		rig.step()
	rig.release()
	return rig


## The mirror's trigonometric floor on a weapon quantity (relative to max(1, |x|)):
## the inertia is evaluated at ±θ, so mirrored values agree to a few ulps, never
## bit for bit. Any brake decision that fell differently would be orders above it.
const MIRROR_TRIG_REL := 1.0e-12


func _mirrored(left: float, right: float) -> bool:
	return absf(left + right) <= MIRROR_TRIG_REL * maxf(1.0, maxf(absf(left), absf(right)))


## SWING-BRAKE: the predictive brake is mirror-exact. A cut and its mirror
## brake on exactly the same ticks, in the same phases, with negated angle,
## speed and motor torque to the trigonometric floor, so a near-threshold
## decision can never fall differently on the two sides.
func test_the_predictive_brake_is_mirror_exact_tick_by_tick() -> void:
	for case: Array in [[45.0, 0.0], [135.0, 0.0], [20.0, 0.0], [45.0, 0.5], [45.0, 1.0]]:
		## ARRANGE: the same cut from +θ and from -θ.
		var right := _released(-float(case[0]), float(case[1]))
		var left := _released(float(case[0]), float(case[1]))
		assert_eq(right.fighter.weapon.swing_dir, -left.fighter.weapon.swing_dir, "fixture: %s mirrored directions" % str(case))
		var braked := 0
		for _i in 60:
			## ACT
			right.step()
			left.step()
			var r := right.fighter.weapon
			var l := left.fighter.weapon
			var right_brakes := r.motor_torque * r.speed < 0.0
			if right_brakes and CombatPhase.is_swinging(r.phase):
				braked += 1
			## ASSERT: the decision exactly, the motion to the trig floor, every tick.
			assert_eq(r.phase, l.phase, "%s tick %d: phase mirrored" % [str(case), right.tick])
			assert_eq(right_brakes, l.motor_torque * l.speed < 0.0, "%s tick %d: the brake decision mirrored" % [str(case), right.tick])
			assert_true(_mirrored(r.angle, l.angle), "%s tick %d: angle mirrored (%s vs %s)" % [str(case), right.tick, str(r.angle), str(l.angle)])
			assert_true(_mirrored(r.speed, l.speed), "%s tick %d: speed mirrored (%s vs %s)" % [str(case), right.tick, str(r.speed), str(l.speed)])
			assert_true(_mirrored(r.motor_torque, l.motor_torque), "%s tick %d: motor torque mirrored (%s vs %s)" % [str(case), right.tick, str(r.motor_torque), str(l.motor_torque)])
		## PERTURB: the fixture actually exercised the brake inside the attack.
		assert_true(braked > 0, "fixture: %s braked while still swinging (%d ticks)" % [str(case), braked])


## SWING-BRAKE: motor braking is not a phase. While the brake runs the cut
## keeps its active phases from progress (eligibility never reads the torque
## sign), and the motor's brake is the attack's own finite authority.
func test_braking_inside_the_attack_keeps_the_active_phases() -> void:
	var weapon := _rules.combatant(0).weapon
	var drive := _rules.combatant(0).fighter.weapon_torque_scale
	for charge: float in [0.0, 0.5, 1.0]:
		## ARRANGE
		var rig := _released(-45.0, charge)
		var w := rig.fighter.weapon
		var active_brake_ticks := 0
		var requested := drive * SimMath.mix(weapon.brake_torque_tap, weapon.brake_torque_full, w.swing_charge)
		var reaccelerated := false
		var braking := false
		for _i in 60:
			## ACT
			var before := w.speed
			rig.step()
			## Holding the speed target against the coordinate's own speed-up ends on the ceiling: regulation, not the
			## terminal brake.
			var ceiling := weapon.achievable_swing_speed(w.swing_charge, w.launch_preparation)
			var brakes := w.motor_torque * before < 0.0 and not is_equal_approx(absf(w.speed), ceiling)
			if brakes and CombatPhase.is_swinging(w.phase):
				## ASSERT: the commitment tick may brake gently (a bounded torque); every later one is the full brake,
				## unless the brake reached zero this tick, and never more than the attack's brake can give.
				assert_true(absf(w.motor_torque) <= requested + 1e-6, "charge %.1f: an in-attack brake never exceeds the attack's brake torque" % charge)
				if active_brake_ticks > 0 and absf(w.speed) > SimMath.EPSILON:
					assert_near(absf(w.motor_torque), requested, 1e-6, "charge %.1f: once committed, the brake is the attack's full brake torque" % charge)
				active_brake_ticks += 1
			## Re-driving is the motor pushing the cut on again; the coordinate's own speed-up where its inertia falls is not.
			reaccelerated = reaccelerated or (braking and CombatPhase.is_swinging(w.phase) and w.motor_torque * w.speed > 0.0)
			braking = braking or (brakes and CombatPhase.is_swinging(w.phase))
			if w.phase == CombatPhase.Id.NEUTRAL and rig.tick > 5:
				break
		assert_true(active_brake_ticks > 0, "charge %.1f: the brake ran while the phase was still active (%d ticks)" % [charge, active_brake_ticks])
		assert_false(reaccelerated, "charge %.1f: and once it braked the cut never re-drove (no chatter)" % charge)


## DEFLECTION-001 boundary: a free cut that the motor alone brakes to a stop
## short of or at its end met nothing — it is one whiff, never a deflection or
## a parry. Redirection by the wielder's own torque is not contact.
## SWING-BRAKE latch boundaries (2026-11-24): across fatigue and injury, quick / half / full cuts from both Ready sides and
## therefore different inertia along the brake, once the attack's full brake torque engages the motor never drives the
## cut forward again (no chatter back into driving), and every free cut settles within the tolerance of its commanded
## end. A latch that confused ceiling regulation with the terminal brake would stop cuts short; one that let prediction
## noise re-drive would show positive torque after the brake.
func test_the_terminal_brake_holds_across_condition_and_inertia() -> void:
	var weapon := _rules.combatant(0).weapon
	var max_health := _rules.combatant(0).fighter.max_health
	var regulated := 0
	for condition: Array in [["fresh", 1.0, 1.0], ["tired", 0.3, 1.0], ["wounded", 1.0, 0.5], ["tired and wounded", 0.3, 0.5]]:
		for hold: int in [1, 30, 90]:
			for side: float in [-1.0, 1.0]:
				## ARRANGE: the real duel, the condition pinned every tick.
				var runner := SimRunner.create(_rules, 7)
				runner.skip_intro()
				var fighter := runner.state.fighter(0)
				fighter.weapon.reset(side * weapon.guard_angle)
				fighter.weapon.stable_side = side
				fighter.weapon.swing_dir = -side
				var w := fighter.weapon
				var released := false
				var braked := false
				var redriven := false
				var end := NAN
				var reach := -INF
				var peak := 0.0
				for i in 220:
					fighter.stamina = float(condition[1])
					fighter.health = float(condition[2]) * max_health
					## ACT
					var before := runner.events.size()
					runner.push(PlayerCommand.create(runner.state.tick, 0.0, 0.0, i == 0, i == hold), PlayerCommand.idle(runner.state.tick))
					for e: DuelEvent in runner.events.slice(before):
						if e.type == DuelEventTypes.ATTACK_RELEASED and e.actor == 0:
							released = true
							end = w.swing_end * w.swing_dir
					if not released:
						continue
					reach = maxf(reach, w.angle * w.swing_dir)
					if CombatPhase.is_swinging(w.phase):
						var forward := w.speed * w.swing_dir
						if braked and w.motor_torque * w.swing_dir > 1e-9:
							redriven = true
						## Free flight: ceiling regulation holds the peak speed; only the commitment and the terminal brake
						## take the cut below it with braking torque.
						if w.motor_torque * w.swing_dir < 0.0 and forward < peak - 1e-9:
							braked = true
						elif w.motor_torque * w.swing_dir < 0.0:
							regulated += 1
						peak = maxf(peak, forward)
					if w.phase == CombatPhase.Id.NEUTRAL and absf(w.speed) < 1e-6:
						break
				## ASSERT
				var label := "%s, hold %d, from %+.0f°" % [condition[0], hold, rad_to_deg(side * weapon.guard_angle)]
				assert_true(released and braked, "fixture: %s releases and brakes" % label)
				assert_false(redriven, "%s: once braking, the motor never drives the cut on again" % label)
				assert_true(absf(rad_to_deg(reach - end)) <= SETTLE_TOLERANCE_DEG, "%s: settles within %.0f° of its end (%+.2f°)" % [label, SETTLE_TOLERANCE_DEG, rad_to_deg(reach - end)])
	assert_true(regulated > 0, "fixture: the matrix holds ceilings with negative torque before braking, the boundary the latch must not confuse (%d ticks)" % regulated)


func test_a_motor_braked_stop_is_a_whiff_not_a_deflection() -> void:
	for start: float in [-135.0, -45.0, 0.0]:
		## ARRANGE / ACT
		var rig := _released(start, 0.0)
		rig.settle()
		## ASSERT
		assert_eq(rig.events_of(DuelEventTypes.ATTACK_WHIFFED).size(), 1, "from %+.0f° the braked free cut is one whiff" % start)
		assert_eq(rig.events_of(DuelEventTypes.DEFLECTION).size(), 0, "and never a deflection")
		assert_eq(rig.events_of(DuelEventTypes.PARRY).size(), 0, "or a parry")
		assert_eq(rig.fighter.weapon.phase, CombatPhase.Id.NEUTRAL, "and the attack is over, not active forever")