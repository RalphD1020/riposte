extends TestCase

## ATTACK: the one-button weapon language (COMBAT §12–§19, §22, §64).
##
## Implements: /spec/invariants.md#combat-001
## See also: /docs/concepts/combat.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "ATTACK"
	_rules = DuelFixture.rules()


func _rig() -> WeaponRig:
	return WeaponRig.create(_rules)


## The most wind-back one tick of the motor can earn, and so the ceiling on
## any single tick's credit.
func _one_tick_of_windback() -> float:
	return _rules.combatant(0).weapon.windup_speed * SimulationTimebase.TICK_SECONDS


func test_tap_launches_exactly_zero_charge() -> void:
	var rig := _rig()
	rig.attack(4)
	var released := rig.events_of(DuelEventTypes.ATTACK_RELEASED)
	assert_eq(released.size(), 1, "one swing launched")
	assert_true(released[0].number(DuelEventKeys.CHARGE) == 0.0, "tap charge is exactly 0, not a tiny hold")
	assert_near(rad_to_deg(released[0].number(DuelEventKeys.ARC)), 90.0, 1e-9, "tap arc is 90°")
	assert_eq(rig.events_of(DuelEventTypes.CHARGE_STARTED).size(), 0, "a tap never enters CHARGING")


func test_same_tick_press_and_release_is_a_tap() -> void:
	var rig := _rig()
	rig.step(true, true)
	var released := rig.events_of(DuelEventTypes.ATTACK_RELEASED)
	assert_eq(released.size(), 1, "sub-tick tap still attacks")
	assert_true(released[0].number(DuelEventKeys.CHARGE) == 0.0, "sub-tick tap is 0% charge")


func test_holding_past_threshold_charges_from_zero() -> void:
	var rig := _rig()
	rig.press()
	rig.hold(_rules.combatant(0).weapon.tap_threshold_ticks)
	assert_eq(rig.fighter.weapon.phase, CombatPhase.Id.CHARGING, "threshold crossed into CHARGING")
	## Crossing the threshold does not award charge; the blade has only had
	## one tick of travel, and that is all it is credited with.
	assert_between(rig.fighter.weapon.earned_windback, 0.0, _one_tick_of_windback(), "charge starts from the blade's first tick of travel, not from a stored timer")
	rig.hold(240)
	rig.release()
	var released := rig.events_of(DuelEventTypes.ATTACK_RELEASED)
	assert_near(rad_to_deg(released[0].number(DuelEventKeys.ARC)), 180.0, 1e-9, "a hold to the guard limit earns the full 180° arc")


func test_charge_is_earned_wind_back_not_elapsed_time() -> void:
	## The defining property: charge measures how far the blade travelled, so
	## arc is exactly 90° plus the wind-back that was earned.
	var rig := _rig()
	rig.press()
	rig.hold(_rules.combatant(0).weapon.tap_threshold_ticks + 20)
	var weapon := rig.fighter.weapon
	assert_true(weapon.earned_windback > 0.0, "precondition: the blade actually travelled")
	assert_near(weapon.charge, weapon.earned_windback / _rules.combatant(0).weapon.windback_span(), 1e-12, "charge is wind-back as a fraction of the span")
	var travelled := absf(weapon.angle) - _rules.combatant(0).weapon.guard_angle
	assert_near(weapon.earned_windback, travelled, 1e-9, "every degree past the guard was credited")
	rig.release()
	var arc := rig.events_of(DuelEventTypes.ATTACK_RELEASED)[0].number(DuelEventKeys.ARC)
	assert_near(arc, _rules.combatant(0).weapon.min_arc + weapon.swing_charge * _rules.combatant(0).weapon.windback_span(), 1e-9, "arc is 90° plus the earned wind-back")


func test_charge_caps_at_full_and_spans_half_a_turn() -> void:
	var rig := _rig()
	rig.press()
	rig.hold(600)
	assert_true(rig.fighter.weapon.charge == 1.0, "charge stops at 100% once the blade runs out of travel")
	assert_near(rig.fighter.weapon.earned_windback, _rules.combatant(0).weapon.windback_span(), 1e-9, "and wind-back saturates with it")
	rig.hold(120)
	assert_true(rig.fighter.weapon.charge == 1.0, "holding a saturated blade longer buys nothing")
	rig.release()
	assert_near(rad_to_deg(rig.events_of(DuelEventTypes.ATTACK_RELEASED)[0].number(DuelEventKeys.ARC)), 180.0, 1e-9, "full charge arc 180°")


func test_charging_retracts_the_blade_behind_the_guard() -> void:
	var rig := _rig()
	var guard := rig.fighter.weapon.angle
	assert_near(rad_to_deg(guard), -45.0, 1e-9, "precondition: right-side guard")
	rig.press()
	rig.hold(240)
	assert_near(rad_to_deg(rig.fighter.weapon.angle), -135.0, 1e-9, "a full hold winds back 90° to the guard limit")
	assert_eq(rig.fighter.weapon.speed, 0.0, "and the limit stops it rather than grinding against it")


func test_restoring_an_under_prepared_blade_earns_nothing() -> void:
	## Winding in from inside the guard is restoration, not preparation.
	var rig := _rig()
	rig.fighter.weapon.angle = deg_to_rad(-20.0)
	WeaponSystem.update_stable_side(rig.fighter.weapon, _rules.combatant(0).weapon)
	rig.press()
	rig.hold(_rules.combatant(0).weapon.tap_threshold_ticks)
	var ticks := 0
	while rig.fighter.weapon.angle > -_rules.combatant(0).weapon.guard_angle:
		assert_eq(rig.fighter.weapon.charge, 0.0, "nothing is earned while the blade is still inside the guard")
		rig.hold(1)
		ticks += 1
	assert_true(ticks > 1, "precondition: the blade really travelled the 25° back to baseline")
	## The tick that lands on baseline may overshoot it slightly, so the blade
	## is credited with that overshoot and nothing more: the 25° was free.
	assert_between(rig.fighter.weapon.earned_windback, 0.0, _one_tick_of_windback(), "arriving at the canonical guard is worth no charge")


func test_a_collision_displacement_is_not_free_charge() -> void:
	## A bind flings the blade out to 100°; pressing and releasing there must
	## not cash in displacement the player never generated.
	var rig := _rig()
	rig.fighter.weapon.angle = deg_to_rad(100.0)
	WeaponSystem.update_stable_side(rig.fighter.weapon, _rules.combatant(0).weapon)
	rig.step(true, true)
	assert_eq(rig.fighter.weapon.swing_charge, 0.0, "releasing from inherited displacement is a 0% tap")
	var far := _rig()
	far.fighter.weapon.angle = deg_to_rad(135.0)
	WeaponSystem.update_stable_side(far.fighter.weapon, _rules.combatant(0).weapon)
	far.press()
	far.hold(300)
	assert_eq(far.fighter.weapon.charge, 0.0, "a blade already at the limit can hold forever and earn nothing")


## Charge-while-busy. Holding the button while the weapon cannot start an
## attack is where a duration-based charge would be most obviously wrong: the
## player would walk out of a long recovery with a free full swing they never
## earned.
func test_a_press_while_the_weapon_is_busy_cannot_charge() -> void:
	var rig := _rig()
	var busy := _rules.combatant(0).weapon.tap_threshold_ticks * 4 + _rules.combatant(0).weapon.buffer_ticks
	WeaponSystem.enter_recovery(rig.fighter.weapon, busy + 10)
	rig.press()
	## The press is not swallowed: it waits, like any press made while the
	## weapon is busy. It just never becomes a charge while the weapon is busy.
	assert_true(rig.fighter.buffered_press_tick >= 0, "the press is buffered rather than discarded")
	rig.hold(busy)
	assert_eq(rig.fighter.weapon.phase, CombatPhase.Id.RECOVERY, "precondition: still busy")
	assert_eq(rig.fighter.weapon.charge, 0.0, "a busy weapon earns nothing however long it is held")
	assert_eq(rig.fighter.weapon.earned_windback, 0.0, "because it has not wound back")
	assert_eq(rig.events_of(DuelEventTypes.CHARGE_STARTED).size(), 0, "and it never entered a charge at all")
	## Busy longer than the input buffer expires the press, so walking out of
	## a long recovery does not fire a swing the player has mentally moved on from.
	assert_eq(rig.fighter.buffered_press_tick, -1, "and busy longer than the buffer expires it")


func test_wind_back_is_credited_from_where_the_hold_began() -> void:
	## Beyond baseline the hold has to beat its own start, so the 100° blade
	## earns only what it adds — not the 55° it was handed.
	var rig := _rig()
	rig.fighter.weapon.angle = deg_to_rad(100.0)
	WeaponSystem.update_stable_side(rig.fighter.weapon, _rules.combatant(0).weapon)
	rig.press()
	rig.hold(_rules.combatant(0).weapon.tap_threshold_ticks + 400)
	var weapon := rig.fighter.weapon
	assert_near(rad_to_deg(weapon.angle), 135.0, 1e-9, "precondition: wound out to the limit")
	assert_near(rad_to_deg(weapon.earned_windback), 35.0, 1e-9, "only the 35° it travelled counts")
	assert_near(weapon.charge, 35.0 / 90.0, 1e-9, "so charge is 35 of the 90° span")


func test_earned_wind_back_is_not_refunded_by_drifting_back() -> void:
	var rig := _rig()
	rig.press()
	rig.hold(_rules.combatant(0).weapon.tap_threshold_ticks + 20)
	var earned := rig.fighter.weapon.earned_windback
	assert_true(earned > 0.0, "precondition: some wind-back earned")
	rig.fighter.weapon.angle = -_rules.combatant(0).weapon.guard_angle
	rig.hold(1)
	assert_eq(rig.fighter.weapon.earned_windback, earned, "being shoved back to baseline does not refund the hold")


func test_charge_cannot_outrun_the_motor() -> void:
	## One violent impulse must not convert itself into instant full charge.
	var rig := _rig()
	rig.press()
	rig.hold(_rules.combatant(0).weapon.tap_threshold_ticks + 4)
	var before := rig.fighter.weapon.earned_windback
	rig.fighter.weapon.angle = -_rules.combatant(0).weapon.guard_limit
	var one_tick := _one_tick_of_windback()
	rig.hold(1)
	assert_near(rig.fighter.weapon.earned_windback, before + one_tick, 1e-12, "a 90° shove credits exactly one tick of wind-back")
	rig.hold(1)
	assert_near(rig.fighter.weapon.earned_windback, before + one_tick * 2.0, 1e-12, "and keeps crediting a tick at a time while held")


func test_swing_walks_every_phase_in_order() -> void:
	var rig := _rig()
	rig.attack(3)
	var released_at := rig.phases.size() - 1
	rig.settle()
	var expected: Array[CombatPhase.Id] = [
		CombatPhase.Id.LAUNCH,
		CombatPhase.Id.ACTIVE_EARLY,
		CombatPhase.Id.ACTIVE_THREAT,
		CombatPhase.Id.ACTIVE_LATE,
		CombatPhase.Id.OVERSWING,
		CombatPhase.Id.RECOVERY,
		CombatPhase.Id.NEUTRAL,
	]
	assert_eq(rig.phase_sequence(released_at), expected, "launch → active → overswing → recovery → neutral")


func test_tap_sweeps_ninety_degrees_then_overswings() -> void:
	var rig := _rig()
	var start := rig.fighter.weapon.angle
	rig.attack(3)
	assert_true(rig.step_until_phase(CombatPhase.Id.OVERSWING), "reached overswing")
	var one_tick := rad_to_deg(_rules.combatant(0).weapon.swing_speed_tap / float(SimulationTimebase.TICK_RATE))
	assert_between(rad_to_deg(rig.fighter.weapon.angle - start), 90.0, 90.0 + one_tick, "active arc covers 90° (at most one tick of motion past the end)")
	rig.settle()
	assert_true(rig.fighter.weapon.angle > rig.fighter.weapon.swing_end, "momentum carries the blade past the arc end")


func test_sides_alternate_from_actual_geometry() -> void:
	var rig := _rig()
	rig.attack(3)
	rig.settle()
	assert_true(rig.fighter.weapon.angle > 0.0, "right-side tap ends on the left")
	rig.attack(3)
	var starts := rig.events_of(DuelEventTypes.ATTACK_STARTED)
	assert_eq(starts.size(), 2, "two attacks started")
	assert_eq(starts[0].number(DuelEventKeys.DIRECTION), 1.0, "first swing right → left")
	assert_eq(starts[1].number(DuelEventKeys.DIRECTION), -1.0, "second swing left → right")
	rig.settle()
	assert_true(rig.fighter.weapon.angle < 0.0, "left-side tap ends on the right")


func test_tap_sweeps_ninety_degrees_from_wherever_the_blade_is() -> void:
	## Law: a tap is "rotate 90° in the valid direction from the actual
	## position", never "move to the opposite canonical guard".
	var cases := PackedFloat64Array([45.0, 20.0, 100.0, 135.0, -45.0, -20.0])
	var expected := PackedFloat64Array([-45.0, -70.0, 10.0, 45.0, 45.0, 70.0])
	for i in cases.size():
		var rig := _rig()
		rig.fighter.weapon.angle = deg_to_rad(cases[i])
		WeaponSystem.update_stable_side(rig.fighter.weapon, _rules.combatant(0).weapon)
		rig.step(true, true)
		assert_near(
			rad_to_deg(rig.fighter.weapon.swing_end),
			expected[i],
			1e-9,
			"a tap from %.0f° commands %.0f°" % [cases[i], expected[i]]
		)


func test_committed_side_ignores_the_centre_deadzone() -> void:
	var deadzone := _rules.combatant(0).weapon.side_deadzone
	var rig := _rig()
	assert_eq(rig.fighter.weapon.stable_side, -1.0, "precondition: blade committed to the right")
	rig.fighter.weapon.angle = deadzone * 0.5
	WeaponSystem.update_stable_side(rig.fighter.weapon, _rules.combatant(0).weapon)
	assert_eq(rig.fighter.weapon.stable_side, -1.0, "drifting a hair past centre does not re-commit the side")
	assert_eq(WeaponSystem.swing_direction(rig.fighter.weapon), 1.0, "so the valid attack direction is unchanged")
	rig.fighter.weapon.angle = deadzone * 2.0
	WeaponSystem.update_stable_side(rig.fighter.weapon, _rules.combatant(0).weapon)
	assert_eq(rig.fighter.weapon.stable_side, 1.0, "clearing the deadzone commits to the new side")
	assert_eq(WeaponSystem.swing_direction(rig.fighter.weapon), -1.0, "and reverses the valid attack direction")


func test_side_does_not_chatter_across_centre() -> void:
	var rig := _rig()
	var deadzone := _rules.combatant(0).weapon.side_deadzone
	var sides := PackedFloat64Array()
	for i in 12:
		## Noise straddling exact zero, the case the old `angle <= 0`
		## tie-break would have flipped on every sample.
		rig.fighter.weapon.angle = (deadzone * 0.4) * (1.0 if i % 2 == 0 else -1.0)
		WeaponSystem.update_stable_side(rig.fighter.weapon, _rules.combatant(0).weapon)
		sides.append(rig.fighter.weapon.stable_side)
	for side in sides:
		assert_eq(side, -1.0, "numerical noise at centre never re-commits the side")


func test_preparation_is_continuous_and_saturates_at_baseline() -> void:
	var weapon := _rules.combatant(0).weapon
	assert_eq(weapon.preparation(0.0), 0.0, "a blade at dead centre has no preparation")
	assert_near(weapon.preparation(deg_to_rad(22.5)), 0.5, 1e-12, "halfway to baseline is half preparation")
	assert_eq(weapon.preparation(weapon.guard_angle), 1.0, "the canonical guard is fully prepared")
	assert_eq(weapon.preparation(weapon.guard_limit), 1.0, "wound back past baseline stays fully prepared, not more")
	assert_eq(weapon.preparation(-weapon.guard_angle), 1.0, "preparation is side-agnostic")


func test_under_prepared_tap_reaches_a_lower_top_speed() -> void:
	var prepared := _rig()
	prepared.step(true, true)
	var under := _rig()
	under.fighter.weapon.angle = deg_to_rad(-10.0)
	WeaponSystem.update_stable_side(under.fighter.weapon, _rules.combatant(0).weapon)
	under.step(true, true)
	assert_near(prepared.fighter.weapon.launch_preparation, 1.0, 1e-12, "the canonical guard launches fully prepared")
	assert_near(under.fighter.weapon.launch_preparation, 10.0 / 45.0, 1e-12, "a 10° blade launches at 10/45 preparation")
	prepared.step_until_phase(CombatPhase.Id.OVERSWING)
	under.step_until_phase(CombatPhase.Id.OVERSWING)
	var prepared_peak := _peak_speed(prepared)
	var under_peak := _peak_speed(under)
	assert_true(under_peak < prepared_peak, "under-loaded cuts cannot reach the prepared top speed (%f vs %f)" % [under_peak, prepared_peak])
	assert_true(under_peak > 0.0, "but they still swing")


func test_launch_preparation_is_fixed_at_release() -> void:
	## Crossing centre mid-swing must not retroactively upgrade an
	## under-prepared cut into a prepared one.
	var rig := _rig()
	rig.fighter.weapon.angle = deg_to_rad(-10.0)
	WeaponSystem.update_stable_side(rig.fighter.weapon, _rules.combatant(0).weapon)
	rig.step(true, true)
	var at_launch := rig.fighter.weapon.launch_preparation
	rig.step_until_phase(CombatPhase.Id.OVERSWING)
	assert_true(absf(rig.fighter.weapon.angle) > _rules.combatant(0).weapon.guard_angle, "precondition: the blade swept well past baseline")
	assert_eq(rig.fighter.weapon.launch_preparation, at_launch, "preparation stays the value captured at release")


func test_guard_region_classifies_without_snapping() -> void:
	var guard := _rules.combatant(0).weapon.guard_angle
	assert_eq(GuardRegion.of(0.0, guard), GuardRegion.Id.UNDER_PREPARED, "centre is under-prepared")
	assert_eq(GuardRegion.of(guard, guard), GuardRegion.Id.BASELINE, "the canonical guard is baseline")
	assert_eq(GuardRegion.of(-guard, guard), GuardRegion.Id.BASELINE, "either canonical guard is baseline")
	assert_eq(GuardRegion.of(_rules.combatant(0).weapon.guard_limit, guard), GuardRegion.Id.OUTWARD, "the guard limit is outward")
	var nearly := guard - GuardRegion.BASELINE_EPSILON * 0.5
	assert_eq(GuardRegion.of(nearly, guard), GuardRegion.Id.BASELINE, "a hair inside baseline still labels as baseline")
	var rig := _rig()
	rig.fighter.weapon.angle = nearly
	assert_eq(rig.fighter.weapon.angle, nearly, "labelling never rewrites the authoritative angle")
	assert_eq(GuardRegion.label(GuardRegion.Id.OUTWARD), "OUTWARD", "regions have stable debug labels")


func _peak_speed(rig: WeaponRig) -> float:
	var peak := 0.0
	for i in range(1, rig.angles.size()):
		peak = maxf(peak, absf(rig.angles[i] - rig.angles[i - 1]))
	return peak


## GUARD-RETURN-001. A finished swing does not stay where it stopped: once
## the blade is idle, the return carries it to the guard of the side it
## finished on.
func test_an_idle_blade_returns_after_the_swing() -> void:
	var rig := _rig()
	rig.attack(3)
	rig.settle()
	var stopped := rig.fighter.weapon.angle
	assert_true(absf(stopped) > 0.2, "precondition: the swing left the centre")
	rig.hold(180)
	var guard := rig.fighter.weapon.stable_side * _rules.combatant(0).weapon.guard_angle
	assert_near(rig.fighter.weapon.angle, guard, 0.02, "an idle blade returns to the guard it finished on")
	assert_near(rig.fighter.weapon.speed, 0.0, 0.05, "and rests there")


func test_heavy_overswings_and_recovers_longer_than_tap() -> void:
	var tap := _rig()
	tap.attack(3)
	tap.step_until_phase(CombatPhase.Id.RECOVERY)
	var tap_overswing := (tap.fighter.weapon.angle - tap.fighter.weapon.swing_end) * tap.fighter.weapon.swing_dir
	var tap_recovery := tap.fighter.weapon.recovery_ticks
	var heavy := _rig()
	heavy.attack(80)
	heavy.step_until_phase(CombatPhase.Id.RECOVERY)
	var heavy_overswing := (heavy.fighter.weapon.angle - heavy.fighter.weapon.swing_end) * heavy.fighter.weapon.swing_dir
	assert_true(heavy_overswing > tap_overswing, "heavy carries further past its arc")
	## RECOVERY-001: the recovery phase itself is the same universal floor for
	## both free whiffs (each overswing braked to rest first); the heavy one is
	## longer only because its weak brake takes longer to stop it.
	assert_eq(heavy.fighter.weapon.recovery_ticks, tap_recovery, "the recovery floor is universal")
	assert_eq(tap_recovery, _rules.combat.recovery_min_ticks, "and is the authored floor")


func test_press_just_before_recovery_ends_is_buffered() -> void:
	var rig := _rig()
	rig.attack(3)
	assert_true(rig.step_until_phase(CombatPhase.Id.RECOVERY), "reached recovery")
	while rig.fighter.weapon.recovery_left > 2:
		rig.step()
	var pressed_at := rig.tick
	rig.press()
	assert_eq(rig.events_of(DuelEventTypes.ATTACK_STARTED).size(), 1, "press during recovery does not start yet")
	rig.hold(_rules.combatant(0).weapon.buffer_ticks)
	var starts := rig.events_of(DuelEventTypes.ATTACK_STARTED)
	assert_eq(starts.size(), 2, "buffered press started once control returned")
	assert_true(starts[1].tick - pressed_at <= _rules.combatant(0).weapon.buffer_ticks, "within the buffer window")


func test_stale_press_expires() -> void:
	var rig := _rig()
	rig.attack(3)
	rig.step(true, true)
	rig.settle()
	rig.hold(10)
	assert_eq(rig.events_of(DuelEventTypes.ATTACK_RELEASED).size(), 1, "a press far outside the buffer is dropped")


func test_cancel_drops_charge_without_attacking() -> void:
	var rig := _rig()
	rig.press()
	rig.hold(20)
	assert_eq(rig.fighter.weapon.phase, CombatPhase.Id.CHARGING, "precondition: charging")
	rig.step(false, false, true)
	assert_eq(rig.events_of(DuelEventTypes.ATTACK_CANCELED).size(), 1, "cancel reported")
	assert_eq(rig.fighter.weapon.phase, CombatPhase.Id.RECOVERY, "safe recovery, not a swing")
	rig.release()
	rig.settle()
	assert_eq(rig.events_of(DuelEventTypes.ATTACK_RELEASED).size(), 0, "no accidental attack")


func test_duplicate_press_is_ignored() -> void:
	var rig := _rig()
	rig.press()
	rig.press()
	rig.release()
	assert_eq(rig.events_of(DuelEventTypes.ATTACK_STARTED).size(), 1, "second device press merged")
	assert_eq(rig.events_of(DuelEventTypes.ATTACK_RELEASED).size(), 1, "one tap")


func test_guard_limit_is_never_exceeded() -> void:
	var rig := _rig()
	for _i in 4:
		rig.attack(90)
		rig.settle()
	var worst := 0.0
	for angle in rig.angles:
		worst = maxf(worst, absf(angle))
	assert_true(worst <= _rules.combatant(0).weapon.guard_limit + 1e-12, "blade stays inside the 270° coverage")
	assert_eq(rig.events_of(DuelEventTypes.ATTACK_RELEASED).size(), 4, "every heavy launched")


func test_stagger_interrupts_a_charge() -> void:
	var rig := _rig()
	rig.press()
	rig.hold(20)
	WeaponSystem.stagger(rig.fighter, 10)
	assert_eq(rig.fighter.weapon.phase, CombatPhase.Id.STAGGER, "staggered")
	rig.release()
	assert_eq(rig.events_of(DuelEventTypes.ATTACK_RELEASED).size(), 0, "release after stagger does not attack")
	rig.hold(10)
	assert_eq(rig.fighter.weapon.phase, CombatPhase.Id.NEUTRAL, "control returns after the stagger")


func test_dead_weapon_ignores_input() -> void:
	var rig := _rig()
	DuelFixture.kill(rig.fighter)
	rig.step(true, true)
	assert_eq(rig.events.size(), 0, "no events from a dead fighter")
	assert_eq(rig.fighter.weapon.phase, CombatPhase.Id.DEAD, "stays dead")


# ── RECOVERY-001: physical recovery (rules 44) ───────────────────────────────


## Ticks from release to NEUTRAL for an attack held `hold_ticks`.
func _release_to_neutral(hold_ticks: int) -> int:
	var rig := _rig()
	rig.attack(hold_ticks)
	var released := rig.tick
	rig.settle()
	return rig.tick - released


## A recovery entered with the blade still moving fast: the floor passes, and
## the phase still waits until the attack's own brake has the blade back under
## control — never ending above `control_speed`, never before the floor.
func test_recovery_is_a_floor_plus_the_blade_back_under_control() -> void:
	## ARRANGE: an arrested cut rebounding at 24 rad/s into recovery — fast
	## enough that its brake needs longer than the floor to arrest it.
	var rig := _rig()
	var definition := _rules.combatant(0).weapon
	var w := rig.fighter.weapon
	var start_angle := w.angle
	w.swing_charge = 1.0
	w.speed = 24.0
	w.commitment = 0.8
	WeaponSystem.enter_recovery(w, _rules.combat.recovery_min_ticks)
	var inertia := WeaponKinematics.motor_inertia(_rules.combatant(0), w.angle)
	var brake := definition.brake_accel(1.0, _rules.combatant(0).fighter.weapon_torque_scale, inertia)
	## ACT: one tick, then to the end of recovery.
	rig.step()
	var first_drop := 24.0 - w.speed
	var ticks := 1
	while w.phase == CombatPhase.Id.RECOVERY and ticks < 240:
		rig.step()
		ticks += 1
	## ASSERT
	assert_near(first_drop, brake * SimulationTimebase.TICK_SECONDS, 1e-9, "the blade is arrested by the attack's brake torque, not the hold")
	assert_true(brake > definition.hold_accel(_rules.combatant(0).fighter.weapon_torque_scale, inertia), "fixture: the brake is the stronger of the two")
	assert_eq(w.phase, CombatPhase.Id.NEUTRAL, "recovery ends")
	assert_true(ticks > _rules.combat.recovery_min_ticks, "later than the floor, because the blade was still fast (%d ticks)" % ticks)
	assert_true(absf(w.speed) <= definition.control_speed, "and only once it is under control (%.3f rad/s)" % w.speed)
	## PERTURB: the mirrored rebound — the mirror of (θ, θ̇) is (−θ, −θ̇) —
	## takes exactly as long.
	var mirrored := _rig()
	mirrored.fighter.weapon.angle = -start_angle
	mirrored.fighter.weapon.swing_charge = 1.0
	mirrored.fighter.weapon.speed = -24.0
	mirrored.fighter.weapon.commitment = 0.8
	WeaponSystem.enter_recovery(mirrored.fighter.weapon, _rules.combat.recovery_min_ticks)
	var mirrored_ticks := 0
	while mirrored.fighter.weapon.phase == CombatPhase.Id.RECOVERY and mirrored_ticks < 240:
		mirrored.step()
		mirrored_ticks += 1
	assert_eq(mirrored_ticks, ticks, "a mirrored recovery is exactly as long")


## A blade already under control still sits out the universal floor.
func test_the_floor_always_holds() -> void:
	## ARRANGE
	var rig := _rig()
	var w := rig.fighter.weapon
	w.speed = 0.0
	WeaponSystem.enter_recovery(w, _rules.combat.recovery_min_ticks)
	## ACT
	var ticks := 0
	while w.phase == CombatPhase.Id.RECOVERY and ticks < 60:
		rig.step()
		ticks += 1
	## ASSERT
	assert_eq(ticks, _rules.combat.recovery_min_ticks, "exactly the floor, no more and no less")


## Nothing but the blade's own motion and the floor decides recovery:
## overswing, facing error, displacement and balance cost their time through
## the brake, the turn and movement authority — never again here.
func test_no_recovery_term_reads_facing_displacement_or_balance() -> void:
	## ARRANGE: the same whiff, once square and composed, once turned away and
	## off balance.
	var square := _rig()
	var turned := _rig()
	DuelFixture.place(turned.opponent, 0.0, 10.0, -PI / 2.0)
	turned.fighter.stability = _rules.combatant(0).fighter.stability_floor
	## ACT
	for rig: WeaponRig in [square, turned]:
		rig.attack(40)
		rig.step_until_phase(CombatPhase.Id.RECOVERY)
	var square_left := square.settle()
	var turned_left := turned.settle()
	## ASSERT
	assert_eq(turned_left, square_left, "the turned, unbalanced fighter recovers in exactly the same time")
	## And the authored duration terms no longer exist.
	var names := PackedStringArray()
	for property in _rules.combatant(0).weapon.get_property_list():
		names.append(str(property["name"]))
	for removed: String in ["recovery_base_ticks", "recovery_commit_ticks", "recovery_overswing_ticks_per_rad", "recovery_displacement_ticks_per_speed", "recovery_facing_ticks_per_rad", "recovery_balance_ticks", "recovery_max_ticks"]:
		assert_false(names.has(removed), "no weapon authors %s" % removed)


## A tap — little momentum, a strong brake — is back under control sooner
## than a full whiff overswinging on its weak brake, with no authored
## difference between them.
func test_a_tap_recovers_sooner_than_a_full_whiff() -> void:
	## ARRANGE + ACT
	var tap := _release_to_neutral(3)
	var full := _release_to_neutral(80)
	## ASSERT
	assert_true(tap < full, "the tap is whole again sooner (%d vs %d ticks)" % [tap, full])


## Commitment flows into recovery without a step and decays with the blade.
func test_commitment_is_continuous_into_recovery() -> void:
	## ARRANGE
	var rig := _rig()
	rig.attack(60)
	## ACT: the last overswing tick and the first recovery tick.
	var before := 0.0
	while rig.fighter.weapon.phase != CombatPhase.Id.RECOVERY and rig.tick < 400:
		before = rig.fighter.weapon.commitment
		rig.step()
	var entered := rig.fighter.weapon.commitment
	rig.settle()
	## ASSERT
	assert_true(before > 0.5, "fixture: the cut was committed (%.3f)" % before)
	assert_near(entered, before, 1e-12, "recovery starts from exactly the commitment overswing held")
	assert_eq(rig.fighter.weapon.commitment, 0.0, "and none is left once the gate passes")


# ── WHIFF-001: a whiff is a label, never a mechanic ──────────────────────────


## A landed hit is a hit, not a miss: the attack met the opponent, so its end
## emits no ATTACK_WHIFFED. A tap at an idle defender standing in measure,
## its guard seated at the far guard limit outside the sweep. (The cut that
## carries on through a hit into its overswing is CONTACT's mechanism test.)
func test_a_landed_tap_is_never_a_whiff() -> void:
	## ARRANGE
	var runner := SimRunner.create(_rules, 2)
	runner.skip_intro()
	var attacker := runner.state.fighter(0)
	var defender := runner.state.fighter(1)
	defender.weapon.angle = -_rules.combatant(1).weapon.guard_limit
	var reach := WeaponKinematics.strike_reach(_rules.combatant(0), _rules.combatant(1))
	var guard := 0
	while DuelGeometry.distance(attacker, defender) > reach and guard < 300:
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, 1.0), PlayerCommand.idle(runner.state.tick))
		guard += 1
	## ACT: tap, then idle until the attack is over.
	runner.push(PlayerCommand.create(runner.state.tick, 0.0, 1.0, true, true), PlayerCommand.idle(runner.state.tick))
	for _i in 120:
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
		if attacker.weapon.phase == CombatPhase.Id.NEUTRAL:
			break
	## ASSERT: the scene is what it claims to be...
	var hit := runner.first(DuelEventTypes.BODY_HIT)
	assert_true(hit != null and hit.actor == 0, "precondition: the tap landed on the defender")
	assert_eq(runner.count(DuelEventTypes.BLADE_CONTACT), 0, "precondition: no sword was involved")
	assert_eq(attacker.weapon.phase, CombatPhase.Id.NEUTRAL, "precondition: the attack has ended")
	## ...and its end is not a whiff.
	assert_true(attacker.weapon.attack_contacted, "the attack is marked as having met the opponent")
	assert_eq(runner.count(DuelEventTypes.ATTACK_WHIFFED), 0, "a landed hit never emits ATTACK_WHIFFED")
	assert_true(runner.is_sound(), "every tick legal (%s)" % runner.violation_summary())

## Two placements are the same measure to this (m).
const MEASURE_TOLERANCE := 1.0e-3


## LINE-CHANGE-001 (ATTACK-SIDE-001), from a searched state:
## which side of the sweep a defender occupies decides what a committed cut
## meets — line, not measure. Shipping rules, inside strike reach: the
## attacker stands at the origin facing the defender 1.5 m away; a planted tap
## from rest (θ −45° → +45°, swing_dir +1, 90°). The defender, reading it,
## starts walking 4 ticks before the press and holds 8 ticks of pure lateral
## walk. CONTROL (no step) and both line changes meet the torso: the hands
## the origin-side step carries into the sweep are not a target
## (TORSO-CIRCLE-001). Both steps end at the same distance, inside reach.
## Whether the line then wins the exchange is LINE-CHANGE-CAPITALIZATION-001,
## open.
func test_the_side_of_the_sweep_decides_what_a_cut_meets() -> void:
	var rules := StandardDuelRules.create()
	var reach := WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1))
	## ARRANGE (control): no line change.
	var control := _lined_tap(rules, "none", false)
	assert_eq(control.result, DuelEventKeys.REGION_TORSO, "control: without a line change the tap's first contact is the torso")
	assert_true(control.distance < reach, "fixture: the defender stands inside strike reach (%.3f < %.3f m)" % [control.distance, reach])
	## PERTURB + ACT: the same tap, the defender behind the blade, then into it.
	var behind := _lined_tap(rules, "origin", false)
	var into := _lined_tap(rules, "end", false)
	## ASSERT: measure is equal, so the line decided.
	## Equal to a millimetre: the attacker's heading tracks the two sides a
	## little differently, so the radial drift of a pure lateral walk differs
	## in the fifth decimal — far below anything that decides a contact.
	assert_near(behind.distance, into.distance, MEASURE_TOLERANCE, "both steps end at the same distance (%.4f m)" % behind.distance)
	assert_true(behind.distance < reach, "still inside strike reach after the step — measure did not decide it")
	assert_true(absf(behind.bearing_change) > 0.02, "the step changed the line (bearing %.3f rad)" % behind.bearing_change)
	assert_eq(behind.result, DuelEventKeys.REGION_TORSO, "behind the blade, the tap still meets the torso: the hands are not a target (%s)" % behind.result)
	assert_eq(into.result, DuelEventKeys.REGION_TORSO, "into the blade, the same walk is struck on the torso")
	## MIRROR: the whole scene reflected.
	var mirrored := _lined_tap(rules, "origin", true)
	assert_eq(mirrored.result, behind.result, "the mirrored scene meets the same thing")
	assert_near(mirrored.distance, behind.distance, MEASURE_TOLERANCE, "at the same distance")
	assert_near(mirrored.bearing_change, -behind.bearing_change, 1.0e-6, "with the bearing changed the other way")


## FIRST-CONTACT-001 (THREAT-001): the steel-aware estimate tells a cut that
## will meet flesh from one that will meet steel, from the state at the press
## alone — the defender's sword under its own known law, no future input. On
## the line-change scenes it predicts what the real tap then meets — flesh
## (the torso or the grip) or steel — and the same in the mirror. Which flesh
## is met first is a finer reading the estimate takes at tick resolution.
func test_the_threat_estimate_sees_the_steel_in_the_way() -> void:
	var rules := StandardDuelRules.create()
	for side: String in ["none", "origin", "end"]:
		## ARRANGE + ACT
		var scene := _lined_tap(rules, side, false)
		var steel_met := scene.result == "steel"
		var steel_seen := scene.predicted == ThreatEstimate.STEEL
		## ASSERT
		assert_true(scene.result != "", "fixture (%s): the tap met something" % side)
		assert_eq(steel_seen, steel_met, "%s: predicted %d, the tap met %s" % [side, scene.predicted, scene.result])
		assert_true(steel_met or scene.predicted == ThreatEstimate.BODY, "%s: flesh is the torso" % side)
	## PERTURB: the mirrored scene.
	var straight := _lined_tap(rules, "origin", false)
	var mirrored := _lined_tap(rules, "origin", true)
	assert_eq(mirrored.predicted, straight.predicted, "mirrored: the same is seen")


## One planted tap at the defender 1.5 m ahead, the defender walking toward
## the cut's `side` ("origin", "end" or "none") from 4 ticks before the press
## for 8 ticks; `mirror` reflects the scene (both rests at +45°).
func _lined_tap(rules: DuelRules, side: String, mirror: bool) -> LinedTap:
	var runner := SimRunner.create(rules, 5)
	runner.skip_intro()
	var attacker := runner.state.fighter(0)
	var defender := runner.state.fighter(1)
	var reflect := -1.0 if mirror else 1.0
	DuelFixture.place(attacker, 0.0, 0.0, 0.0)
	DuelFixture.place(defender, 1.5, 0.0, PI)
	attacker.weapon.reset(-reflect * rules.combatant(0).weapon.guard_angle)
	defender.weapon.reset(-reflect * rules.combatant(1).weapon.guard_angle)
	var start_bearing := DuelGeometry.bearing(attacker, defender)
	var press := runner.state.tick + 4
	var step_from := press - 4
	var direction := Vector2.ZERO
	var out := LinedTap.new()
	for _t in 60:
		var tick := runner.state.tick
		if tick == step_from and side != "none":
			direction = CutGeometry.origin_side(attacker) if side == "origin" else CutGeometry.end_side(attacker)
		var walk := PlayerCommand.idle(tick)
		if tick >= step_from and tick < step_from + 8 and side != "none":
			var intent := CutGeometry.step_intent(defender, attacker, direction)
			walk = PlayerCommand.create(tick, intent.x, intent.y)
		if tick == press:
			var spec := rules.spec_of(attacker)
			## The tap is planted, so the prediction carries no new footwork.
			out.predicted = InitiativeModel.estimate(attacker, spec, defender, rules.spec_of(defender), rules.combat, ThreatEstimate.new(), ThreatContinuation.planted(true)).first_contact
		var seen := runner.events.size()
		runner.push(PlayerCommand.create(tick, 0.0, 0.0, tick == press, tick == press), walk)
		if tick == step_from + 7:
			out.distance = DuelGeometry.distance(attacker, defender)
			out.bearing_change = SimMath.wrap_angle(DuelGeometry.bearing(attacker, defender) - start_bearing)
		for e in range(seen, runner.events.size()):
			var event: DuelEvent = runner.events[e]
			if event.type == DuelEventTypes.BODY_HIT and event.actor == 0:
				out.body_struck = true
				if out.result == "":
					out.result = event.text(DuelEventKeys.REGION)
			elif event.type == DuelEventTypes.BLADE_CONTACT and out.result == "":
				out.result = "steel"
		if out.result != "" and attacker.weapon.phase == CombatPhase.Id.RECOVERY:
			break
	if side == "none":
		out.distance = DuelGeometry.distance(attacker, defender)
	return out


## What one `_lined_tap` did: the cut's first contact (the region struck —
## `torso`, `steel`, or ""), whether it ever struck the opponent, and where
## the step left the defender.
class LinedTap:
	var result := ""
	## What the steel-aware threat estimate, read at the press, said the tap
	## would meet first (`ThreatEstimate.NONE` / `BODY` / `STEEL`).
	var predicted := ThreatEstimate.NONE
	var body_struck := false
	var distance := 0.0
	var bearing_change := 0.0


## Nothing in the simulation reads a whiff (WHIFF-001): the same free miss,
## once labelled and once with its label suppressed, moves every body, sword
## and phase identically on every tick. The only difference is the event.
func test_a_whiff_label_changes_no_physics() -> void:
	## ARRANGE: a tap at an idle defender far out of measure — a clean miss.
	var labelled := SimRunner.create(_rules, 2)
	var silenced := SimRunner.create(_rules, 2)
	for runner: SimRunner in [labelled, silenced]:
		runner.skip_intro()
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, 0.0, true, true), PlayerCommand.idle(runner.state.tick))
	## PERTURB: suppress the label on one of them.
	silenced.state.fighter(0).weapon.attack_contacted = true
	## ACT
	var diverged := ""
	for tick in 120:
		for runner: SimRunner in [labelled, silenced]:
			runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
		for slot in 2:
			var a := labelled.state.fighter(slot)
			var b := silenced.state.fighter(slot)
			var same := (
				a.x == b.x and a.y == b.y and a.vx == b.vx and a.vy == b.vy
				and a.facing == b.facing and a.turn_rate == b.turn_rate
				and a.weapon.angle == b.weapon.angle and a.weapon.speed == b.weapon.speed
				and a.weapon.phase == b.weapon.phase and a.weapon.commitment == b.weapon.commitment
				and a.weapon.recovery_left == b.weapon.recovery_left and a.health == b.health
			)
			if not same and diverged == "":
				diverged = "tick %d slot %d" % [tick, slot]
	## ASSERT
	assert_eq(labelled.count(DuelEventTypes.ATTACK_WHIFFED), 1, "control: the free miss is labelled once")
	assert_eq(silenced.count(DuelEventTypes.ATTACK_WHIFFED), 0, "perturbed: the label is suppressed")
	assert_eq(diverged, "", "and no physical quantity differs on any tick")


func _idle_blade(angle: float, speed: float, side: float) -> FighterState:
	var fighter := FighterState.new()
	fighter.slot = 0
	fighter.health = _rules.combatant(0).fighter.max_health
	fighter.weapon.reset(angle)
	fighter.weapon.speed = speed
	fighter.weapon.stable_side = side
	fighter.weapon.swing_dir = -side
	return fighter


func _step_blade(fighter: FighterState, tick: int, return_scale: float = 1.0, diagnostics: ContactDiagnostics = null, condition: ConditionState = null) -> void:
	var events: Array[DuelEvent] = []
	WeaponSystem.step(fighter, _rules, tick, events, condition, null, return_scale, diagnostics)


## GUARD-RETURN-001. An idle blade on the right settles on the right guard
## and does not travel through it.
func test_an_idle_blade_settles_on_its_committed_guard() -> void:
	var fighter := _idle_blade(0.0, 0.0, -1.0)
	var target := -_rules.combatant(0).weapon.guard_angle
	var furthest := 0.0
	for tick in 240:
		_step_blade(fighter, tick)
		furthest = minf(furthest, fighter.weapon.angle)
	assert_near(fighter.weapon.angle, target, 0.02, "it arrives on the committed guard")
	assert_near(fighter.weapon.speed, 0.0, 0.05, "and is at rest there")
	assert_true(furthest >= target - 0.05, "without passing through the guard (%s)" % str(furthest))


## The tick an attack is held, the return does not fight it.
func test_an_attack_takes_the_blade_over_on_its_tick() -> void:
	var idle := _idle_blade(0.0, 0.0, -1.0)
	var held := _idle_blade(0.0, 0.0, -1.0)
	held.attack_held = true
	held.press_tick = 0
	_step_blade(idle, 0)
	_step_blade(held, 0)
	assert_true(idle.weapon.angle < -0.001, "fixture: an idle tick leaves centre toward the guard")
	assert_near(held.weapon.angle, 0.0, 1e-9, "the held attack keeps the blade where it was")
	assert_eq(held.weapon.phase, CombatPhase.Id.NEUTRAL, "the tap threshold has not promoted it yet")


## Inside the deadzone the previous side stands, so the return keeps its target.
func test_the_return_keeps_its_side_inside_the_deadzone() -> void:
	var definition := _rules.combatant(0).weapon
	var fighter := _idle_blade(definition.side_deadzone * 0.5, 0.0, -1.0)
	var before := fighter.weapon.angle
	_step_blade(fighter, 0)
	assert_eq(fighter.weapon.stable_side, -1.0, "the deadzone does not flip the side")
	assert_true(fighter.weapon.angle < before, "so the return still carries it toward the right guard")


## A commanded swing that leaves the centre, and a blade planted at the angle
## that swing reached, remember the same side. `ContactFixture.arm` is a
## constructed pose for a domain test; this is the check that the side it
## commits is the side the command path has already committed at that angle.
func test_a_commanded_crossing_commits_the_side_a_planted_blade_commits() -> void:
	var definition := _rules.combatant(0).weapon
	var rig := _rig()
	var opening := rig.fighter.weapon.stable_side
	rig.attack(4)
	var crossed := false
	for _i in 240:
		rig.step()
		var angle := rig.fighter.weapon.angle
		if absf(angle) > definition.side_deadzone and (1.0 if angle > 0.0 else -1.0) != opening:
			crossed = true
			break
	assert_true(crossed, "fixture: the tap crosses onto the other side of the deadzone")
	var live := rig.fighter.weapon
	var live_side := 1.0 if live.angle > 0.0 else -1.0
	assert_eq(live.stable_side, live_side, "after the tick, the command path remembers the side it reached")
	assert_eq(live.commitment, CommitmentModel.commitment(live, definition), "and its commitment is the production reading of that weapon")
	var planted := FighterState.new()
	planted.slot = 0
	planted.health = rig.fighter.health
	planted.weapon.reset(0.0)
	planted.weapon.stable_side = opening
	ContactFixture.arm(planted, 0.0, 0.0, rig.fighter.facing, live.angle, live.speed, live.phase, live.swing_charge, definition)
	assert_eq(planted.weapon.angle, live.angle, "the planted angle is the commanded angle")
	assert_eq(planted.weapon.speed, live.speed, "and its angular velocity")
	assert_eq(planted.weapon.stable_side, live.stable_side, "and the side the command path committed")
	## At rest the sign of speed does not name a side, and `arm` derives
	## `swing_dir` from that sign. The return reads `stable_side`. Both
	## resting poses therefore share the committed side and the same `swing_dir`
	## before the next motor tick, so a mismatch would be the return itself.
	var from_command := _idle_blade(live.angle, 0.0, live.stable_side)
	var from_plant := _idle_blade(0.0, 0.0, opening)
	ContactFixture.arm(from_plant, 0.0, 0.0, 0.0, live.angle, 0.0, CombatPhase.Id.NEUTRAL, 0.0, definition)
	assert_eq(from_plant.weapon.stable_side, from_command.weapon.stable_side, "a resting plant of that angle commits it too")
	assert_eq(from_plant.weapon.commitment, 0.0, "neutral commitment is zero")
	from_plant.weapon.swing_dir = from_command.weapon.swing_dir
	_step_blade(from_command, 0)
	_step_blade(from_plant, 0)
	assert_eq(from_plant.weapon.angle, from_command.weapon.angle, "the next return tick matches")
	assert_eq(from_plant.weapon.speed, from_command.weapon.speed, "and so does its speed")
	assert_eq(from_plant.weapon.stable_side, from_command.weapon.stable_side, "the side still agrees")


## RECOVERY-001 / GUARD-RETURN-001. Above control speed the brake arrests;
## once under it, the return carries the blade to the guard.
func test_recovery_returns_only_once_the_blade_is_under_control() -> void:
	var definition := _rules.combatant(0).weapon
	var fast := _idle_blade(0.0, definition.control_speed + 2.0, -1.0)
	fast.weapon.set_phase(CombatPhase.Id.RECOVERY)
	fast.weapon.recovery_left = definition.tap_threshold_ticks
	var speed_before := fast.weapon.speed
	_step_blade(fast, 0)
	assert_true(fast.weapon.speed < speed_before, "above control speed the brake slows it")
	assert_true(fast.weapon.angle >= -0.02, "and does not yet carry it off toward the guard")
	var slow := _idle_blade(0.0, definition.control_speed * 0.25, -1.0)
	slow.weapon.set_phase(CombatPhase.Id.RECOVERY)
	slow.weapon.recovery_left = definition.tap_threshold_ticks
	_step_blade(slow, 0)
	assert_true(slow.weapon.angle < -0.001, "under control speed the return carries it to the right guard")


## Persistent steel reduces the return; it does not stop it.
func test_a_bind_scales_the_return_down() -> void:
	var free := _idle_blade(0.0, 0.0, -1.0)
	var bound := _idle_blade(0.0, 0.0, -1.0)
	_step_blade(free, 0, 1.0)
	_step_blade(bound, 0, _rules.combat.guard_steel_return_scale)
	assert_true(free.weapon.angle < bound.weapon.angle, "the free return travels further in the same tick")
	assert_true(bound.weapon.angle < 0.0, "and the bound return still moves")


func test_a_mirror_returns_to_the_mirror_guard() -> void:
	var right := _idle_blade(-0.2, 0.4, -1.0)
	var left := _idle_blade(0.2, -0.4, 1.0)
	for tick in 30:
		_step_blade(right, tick)
		_step_blade(left, tick)
		assert_near(right.weapon.angle, -left.weapon.angle, 1e-9, "tick %d angle mirrors" % tick)
		assert_near(right.weapon.speed, -left.weapon.speed, 1e-9, "tick %d speed mirrors" % tick)


## STAMINA-004: fatigue does not scale the return. Same health, different stamina.
func test_fatigue_does_not_scale_the_guard_return() -> void:
	var body := _rules.combatant(0).fighter
	var fresh_state := ConditionModel.compute(body.max_health, body.max_health, 1.0, _rules.combat, ConditionState.new())
	var tired_state := ConditionModel.compute(body.max_health, body.max_health, 0.0, _rules.combat, ConditionState.new())
	assert_true(fresh_state.fatigue_scale > tired_state.fatigue_scale, "fixture: the tired fighter has less force")
	var fresh := _idle_blade(0.0, 0.0, -1.0)
	var tired := _idle_blade(0.0, 0.0, -1.0)
	_step_blade(fresh, 0, 1.0, null, fresh_state)
	_step_blade(tired, 0, 1.0, null, tired_state)
	assert_eq(fresh.weapon.angle, tired.weapon.angle, "the return does not depend on stamina")
	assert_eq(fresh.weapon.speed, tired.weapon.speed, "nor does its speed")


## STAMINA-004: fatigue scales swing and brake force. The speed ceiling does
## not move, and a blade already on that ceiling stays there at either stamina.
func test_fatigue_scales_weapon_force_and_not_its_speed_ceiling() -> void:
	var body := _rules.combatant(0).fighter
	var weapon := _rules.combatant(0).weapon
	var fresh_state := ConditionModel.compute(body.max_health, body.max_health, 1.0, _rules.combat, ConditionState.new())
	var tired_state := ConditionModel.compute(body.max_health, body.max_health, 0.0, _rules.combat, ConditionState.new())
	var fresh := _idle_blade(-weapon.guard_angle, 0.0, -1.0)
	var tired := _idle_blade(-weapon.guard_angle, 0.0, -1.0)
	for fighter: FighterState in [fresh, tired]:
		fighter.weapon.set_phase(CombatPhase.Id.ACTIVE_THREAT)
		fighter.weapon.swing_dir = 1.0
		fighter.weapon.swing_charge = 1.0
		fighter.weapon.launch_preparation = 1.0
	_step_blade(fresh, 0, 1.0, null, fresh_state)
	_step_blade(tired, 0, 1.0, null, tired_state)
	assert_true(fresh.weapon.speed > tired.weapon.speed, "the rested swing accelerates harder")
	assert_near(tired.weapon.speed / fresh.weapon.speed, tired_state.fatigue_scale / fresh_state.fatigue_scale, 1e-9, "by the fatigue term, and nothing else")
	var ceiling := weapon.achievable_swing_speed(1.0, 1.0)
	var rested_ceiling := _idle_blade(0.0, ceiling, -1.0)
	var tired_ceiling := _idle_blade(0.0, ceiling, -1.0)
	for fighter: FighterState in [rested_ceiling, tired_ceiling]:
		fighter.weapon.set_phase(CombatPhase.Id.ACTIVE_THREAT)
		fighter.weapon.swing_dir = 1.0
		fighter.weapon.swing_charge = 1.0
		fighter.weapon.launch_preparation = 1.0
	_step_blade(rested_ceiling, 0, 1.0, null, fresh_state)
	_step_blade(tired_ceiling, 0, 1.0, null, tired_state)
	assert_eq(rested_ceiling.weapon.speed, ceiling, "a rested blade already on the ceiling is not pushed past it")
	assert_eq(tired_ceiling.weapon.speed, ceiling, "and fatigue does not lower that ceiling")
	var rested_brake := _idle_blade(0.0, 8.0, -1.0)
	var tired_brake := _idle_blade(0.0, 8.0, -1.0)
	for fighter: FighterState in [rested_brake, tired_brake]:
		fighter.weapon.set_phase(CombatPhase.Id.OVERSWING)
		fighter.weapon.swing_charge = 0.0
	_step_blade(rested_brake, 0, 1.0, null, fresh_state)
	_step_blade(tired_brake, 0, 1.0, null, tired_state)
	var rested_drop := 8.0 - rested_brake.weapon.speed
	var tired_drop := 8.0 - tired_brake.weapon.speed
	assert_true(rested_drop > tired_drop, "the rested brake takes off more speed")
	assert_near(tired_drop / rested_drop, tired_state.fatigue_scale / fresh_state.fatigue_scale, 1e-9, "brake force carries fatigue; the brake law does not change")
	## v²/2a would be the stopping distance only if this deceleration held for
	## the whole coast. This tick does not show that: the soft zone, the guard
	## limit and a phase change can all end it first.
	var rested_wind := _idle_blade(-weapon.guard_angle, 0.0, -1.0)
	var tired_wind := _idle_blade(-weapon.guard_angle, 0.0, -1.0)
	for fighter: FighterState in [rested_wind, tired_wind]:
		fighter.weapon.set_phase(CombatPhase.Id.CHARGING)
		fighter.weapon.swing_dir = 1.0
	_step_blade(rested_wind, 0, 1.0, null, fresh_state)
	_step_blade(tired_wind, 0, 1.0, null, tired_state)
	assert_true(absf(rested_wind.weapon.speed) > absf(tired_wind.weapon.speed), "the rested wind-up accelerates harder")
	assert_near(tired_wind.weapon.speed / rested_wind.weapon.speed, tired_state.fatigue_scale / fresh_state.fatigue_scale, 1e-9, "by the same fatigue term")


## The step and the predictor share one coast.
func test_one_coast_tick_matches_the_weapon_step() -> void:
	var fighter := _idle_blade(0.2, 1.5, -1.0)
	var definition := _rules.combatant(0).weapon
	var spec := _rules.combatant(0)
	var inertia := WeaponKinematics.motor_inertia(spec, fighter.weapon.angle)
	var drive := spec.fighter.weapon_torque_scale
	var out := PackedFloat64Array([0.0, 0.0])
	var speed := WeaponSystem.coast_speed(fighter.weapon.speed, fighter.weapon.angle, fighter.weapon.phase, fighter.weapon.stable_side, fighter.weapon.swing_charge, definition, drive, drive, inertia, _rules.combat, 1.0, false)
	WeaponSystem.write_limited(out, fighter.weapon.angle, speed, definition.guard_limit, _rules.combat.guard_limit_zone, WeaponSystem.zone_spring(definition, drive, inertia, _rules.combat), _rules.combat.guard_limit_damping, WeaponSystem.limit_accel_cap(definition, drive, inertia))
	_step_blade(fighter, 0)
	assert_near(fighter.weapon.angle, out[0], 1e-12, "the step's angle is the shared coast")
	assert_near(fighter.weapon.speed, out[1], 1e-12, "and so is its speed")


## One clamp for the weapon step and the predictor's buffer.
func test_the_stop_rule_is_one_clamp() -> void:
	var limit := 1.0
	var cases: Array[Array] = [
		[0.2, 0.5, 0.2, 0.5, false],
		[1.0, 0.4, 1.0, 0.0, true],
		[1.0, -0.4, 1.0, -0.4, false],
		[1.0, 0.0, 1.0, 0.0, false],
		[-1.0, -0.4, -1.0, 0.0, true],
		[-1.0, 0.4, -1.0, 0.4, false],
		[1.2, 0.3, 1.0, 0.0, true],
		[-1.2, -0.3, -1.0, 0.0, true],
		[1.2, -0.3, 1.0, -0.3, true],
		[1.0 - 5.0e-10, 0.4, 1.0 - 5.0e-10, 0.0, true],
		[-(1.0 - 5.0e-10), -0.4, -(1.0 - 5.0e-10), 0.0, true],
		[1.0 - 2.0e-9, 0.4, 1.0 - 2.0e-9, 0.4, false],
		[-(1.0 - 2.0e-9), -0.4, -(1.0 - 2.0e-9), -0.4, false],
		[1.0 - 5.0e-10, -0.4, 1.0 - 5.0e-10, -0.4, false],
		[-(1.0 - 5.0e-10), 0.4, -(1.0 - 5.0e-10), 0.4, false],
	]
	for row: Array in cases:
		assert_eq(WeaponSystem.stopped_angle(float(row[0]), limit), float(row[2]), "angle at %s" % str(row))
		assert_eq(WeaponSystem.stopped_speed(float(row[0]), float(row[1]), limit), float(row[3]), "speed at %s" % str(row))
		assert_eq(WeaponSystem.stop_engaged(float(row[0]), float(row[1]), limit), bool(row[4]), "engaged at %s" % str(row))
		var weapon := WeaponState.new()
		var assigned := WeaponSystem.assign_stop(weapon, float(row[0]), float(row[1]), limit)
		var out := PackedFloat64Array([0.0, 0.0])
		var written := WeaponSystem._write_stop(out, float(row[0]), float(row[1]), limit)
		assert_eq(assigned, written, "both callers report the same stop")
		assert_eq(weapon.angle, out[0], "and the same angle")
		assert_eq(weapon.speed, out[1], "and the same speed")


## GUARD-LIMIT-SOFT-001. The ramp is zero and flat at the inner edge, inward
## speed adds nothing, outward speed adds resistance.
func test_the_soft_zone_is_continuous_and_outward_only() -> void:
	var limit := _rules.combatant(0).weapon.guard_limit
	var zone := _rules.combat.guard_limit_zone
	var edge := limit - zone
	var k := 40.0
	var c := 10.0
	assert_eq(WeaponSystem.limit_zone_accel(edge, 0.0, limit, zone, k, c), 0.0, "no force on the inner edge at rest")
	assert_eq(WeaponSystem.limit_zone_accel(edge, 4.0, limit, zone, k, c), 0.0, "nor with outward speed, so the ramp starts flat")
	var just_inside := edge + 1.0e-4
	var at_rest := WeaponSystem.limit_zone_accel(just_inside, 0.0, limit, zone, k, c)
	var midway := WeaponSystem.limit_zone_accel(edge + zone * 0.5, 0.0, limit, zone, k, c)
	assert_true(absf(at_rest) < absf(midway) * 1.0e-4, "a hair inside, the Hermite ramp is still negligible against mid-zone (%s vs %s)" % [str(at_rest), str(midway)])
	var planted := limit - zone * 0.5
	var still := WeaponSystem.limit_zone_accel(planted, 0.0, limit, zone, k, c)
	var inward := WeaponSystem.limit_zone_accel(planted, -5.0, limit, zone, k, c)
	var outward := WeaponSystem.limit_zone_accel(planted, 5.0, limit, zone, k, c)
	assert_eq(inward, still, "inward speed is not damped")
	assert_true(still < 0.0, "the spring on the positive side pushes inward")
	assert_true(outward < still, "outward speed adds to that push")


## A sustained wind-up rests on the stop without counting as the fallback.
## A blade thrown at the stop does count, and stays inside the limit.
func test_a_resting_windup_is_not_a_hard_stop_and_a_slam_is() -> void:
	var diagnostics := ContactDiagnostics.new()
	var fighter := _idle_blade(-_rules.combatant(0).weapon.guard_angle, 0.0, -1.0)
	var events: Array[DuelEvent] = []
	WeaponSystem.apply_input(fighter, PlayerCommand.create(0, 0.0, 0.0, true, false), _rules, 0, events)
	for tick in 600:
		WeaponSystem.step(fighter, _rules, tick, events, null, null, 1.0, diagnostics)
	assert_eq(fighter.weapon.charge, 1.0, "fixture: the hold reached full charge")
	assert_near(fighter.weapon.angle, -_rules.combatant(0).weapon.guard_limit, 1e-6, "and sits on the stop")
	var resting := diagnostics.guard_hard_stop_hits
	for tick in 120:
		WeaponSystem.step(fighter, _rules, 600 + tick, events, null, null, 1.0, diagnostics)
	assert_eq(diagnostics.guard_hard_stop_hits, resting, "ticks spent already on the stop add none (%d at arrival)" % resting)
	fighter.weapon.set_phase(CombatPhase.Id.NEUTRAL)
	fighter.attack_held = false
	fighter.press_tick = -1
	fighter.weapon.angle = -_rules.combatant(0).weapon.guard_limit + 0.02
	fighter.weapon.speed = -40.0
	var before := diagnostics.guard_hard_stop_hits
	WeaponSystem.step(fighter, _rules, 800, events, null, null, 1.0, diagnostics)
	assert_true(diagnostics.guard_hard_stop_hits > before, "a slam the zone cannot bleed is the fallback")
	assert_true(fighter.weapon.angle >= -_rules.combatant(0).weapon.guard_limit - 1e-9, "and the hard stop keeps it inside")


## A wind-up that has arrived keeps being pressed outward. Each tick the motor
## asks for more outward speed and the stop removes it. The blade stays on the
## stop with no speed left to oscillate, and the stop does not hand speed back.
func test_a_windup_held_on_the_stop_does_not_chatter() -> void:
	var limit := _rules.combatant(0).weapon.guard_limit
	var fighter := _idle_blade(-_rules.combatant(0).weapon.guard_angle, 0.0, -1.0)
	var events: Array[DuelEvent] = []
	WeaponSystem.apply_input(fighter, PlayerCommand.create(0, 0.0, 0.0, true, false), _rules, 0, events)
	var arrived := -1
	for tick in 240:
		_step_blade(fighter, tick)
		if absf(fighter.weapon.angle + limit) <= WeaponSystem.STOP_ARRIVAL_RAD and fighter.weapon.speed == 0.0:
			arrived = tick
			break
	assert_true(arrived >= 0, "fixture: the wind-up reached the stop")
	var furthest := fighter.weapon.angle
	for tick in 90:
		_step_blade(fighter, arrived + 1 + tick)
		assert_eq(fighter.weapon.speed, 0.0, "tick %d keeps no speed to re-engage with" % (arrived + 1 + tick))
		assert_true(absf(fighter.weapon.angle + limit) <= WeaponSystem.STOP_ARRIVAL_RAD, "and the blade stays on the stop")
		assert_true(fighter.weapon.angle <= furthest + 1.0e-12, "it does not bounce back off the stop")
		furthest = minf(furthest, fighter.weapon.angle)