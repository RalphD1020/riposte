extends TestCase

## QUICK-90: the quick attack is a physically driven 90° command from wherever
## the blade is (COMBAT-001), its unopposed timing on the reference duelist is
## pinned as a regression baseline, and its follow-through is the blade's own
## torque-limited stop — never a snap to the commanded end.
##
## See also: /docs/concepts/combat.md

const STARTS := [-135.0, -90.0, -45.0, -20.0, -5.0, 0.0, 5.0, 20.0, 45.0, 90.0, 135.0]

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
	var spec := _rules.combatant(0)
	var crossed := -1
	var end_speed := NAN
	var end_inertia := NAN
	var travel := 0.0
	var peak := 0.0
	var largest_step := 0.0
	var previous := weapon.speed
	for tick in 120:
		rig.step()
		travel = maxf(travel, (weapon.angle - weapon.swing_start) * dir)
		peak = maxf(peak, absf(weapon.speed))
		if weapon.phase == CombatPhase.Id.OVERSWING or (crossed >= 0 and weapon.phase == CombatPhase.Id.RECOVERY):
			largest_step = maxf(largest_step, absf(weapon.speed - previous))
		previous = weapon.speed
		if crossed < 0 and (weapon.angle - weapon.swing_end) * dir >= 0.0:
			crossed = tick + 1
			end_speed = absf(weapon.speed)
			end_inertia = WeaponKinematics.motor_inertia(spec, weapon.angle)
		if weapon.phase == CombatPhase.Id.NEUTRAL and tick > 5:
			break
	return {"dir": dir, "arc": absf(weapon.swing_end - weapon.swing_start), "end": weapon.swing_end, "travel": travel, "crossed": crossed,
		"peak": peak, "end_speed": end_speed, "end_inertia": end_inertia, "largest_brake_step": largest_step, "preparation": weapon.launch_preparation}


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
		## limit, and the motor carries the blade all the way there unopposed.
		assert_near(rad_to_deg(tap["arc"]), 90.0, 1e-6, "from %+.0f° the tap commands 90°" % start)
		assert_true(absf(tap["end"]) <= weapon.guard_limit + 1e-9, "from %+.0f° the commanded end stays inside the guard limit" % start)
		assert_true(tap["travel"] >= deg_to_rad(90.0), "from %+.0f° the blade physically reaches its 90° (%.1f°)" % [start, rad_to_deg(tap["travel"])])
		assert_true(tap["crossed"] > 0, "from %+.0f° the commanded end is crossed" % start)
	## PERTURB: the mirror. A tap from -θ and from +θ are the same cut mirrored.
	for start: float in [20.0, 45.0, 90.0, 135.0]:
		var right := _tap(-start)
		var left := _tap(start)
		assert_eq(right["crossed"], left["crossed"], "±%.0f° cross in the same tick" % start)
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
	## release to the commanded end — not to a stop or back to Ready).
	assert_eq(ready["crossed"], 10, "a tap from Ready crosses its 90° in 10 ticks (~0.17 s)")
	assert_eq(far["crossed"], 10, "and from the full load")
	assert_eq(near["crossed"], 13, "from ±20° in 13")
	assert_eq(centre["crossed"], 16, "from the centre in 16 (~0.27 s)")
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
		var tap_speed: float = tap["end_speed"]
		var tap_inertia: float = tap["end_inertia"]
		var predicted := tap_inertia * tap_speed * tap_speed / (2.0 * drive * weapon.brake_torque_tap)
		var overswing: float = tap["travel"] - tap["arc"]
		## ASSERT: the overswing is the stop a constant brake predicts from the
		## speed at the end (the inertia varies along the track, so within a band),
		## and no brake tick removes more speed than the brake can.
		assert_between(overswing, 0.6 * predicted, 1.4 * predicted, "from %+.0f° the overswing %.1f° is the predicted stop %.1f°" % [start, rad_to_deg(overswing), rad_to_deg(predicted)])
		var cap := drive * weapon.brake_torque_tap / _least_inertia() * SimulationTimebase.TICK_SECONDS
		assert_true(tap["largest_brake_step"] <= cap + 1e-9, "no snap: the largest braking step (%.2f rad/s) is within the brake's own limit (%.2f)" % [tap["largest_brake_step"], cap])
	## PERTURB: a full charge. Its 180° command overruns by the stop its 18 rad/s
	## and gentler full-charge brake predict (the ~242° the art plan measured).
	var rig := WeaponRig.create(_rules)
	rig.press()
	while rig.fighter.weapon.charge < 1.0 and rig.tick < 240:
		rig.step()
	rig.release()
	var w := rig.fighter.weapon
	var travel := 0.0
	var end_speed := NAN
	var end_inertia := NAN
	for _i in 120:
		rig.step()
		travel = maxf(travel, (w.angle - w.swing_start) * w.swing_dir)
		if is_nan(end_speed) and (w.angle - w.swing_end) * w.swing_dir >= 0.0:
			end_speed = absf(w.speed)
			end_inertia = WeaponKinematics.motor_inertia(_rules.combatant(0), w.angle)
		if w.phase == CombatPhase.Id.NEUTRAL:
			break
	var full_predicted := end_inertia * end_speed * end_speed / (2.0 * drive * weapon.brake_torque_full)
	assert_near(rad_to_deg(absf(w.swing_end - w.swing_start)), 180.0, 1e-6, "a full charge commands 180°")
	assert_near(end_speed, weapon.swing_speed_full, 1e-6, "and crosses its end at the full target speed")
	assert_between(travel - absf(w.swing_end - w.swing_start), 0.6 * full_predicted, 1.4 * full_predicted, "its overswing %.0f° is the physical stop %.0f°, not a runaway" % [rad_to_deg(travel - absf(w.swing_end - w.swing_start)), rad_to_deg(full_predicted)])
	assert_true(travel <= deg_to_rad(250.0), "the whole travel stays readable (%.0f°)" % rad_to_deg(travel))
