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
	return _rules.weapon.windup_speed * SimulationTimebase.TICK_SECONDS


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
	rig.hold(_rules.weapon.tap_threshold_ticks)
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
	rig.hold(_rules.weapon.tap_threshold_ticks + 20)
	var weapon := rig.fighter.weapon
	assert_true(weapon.earned_windback > 0.0, "precondition: the blade actually travelled")
	assert_near(weapon.charge, weapon.earned_windback / _rules.weapon.windback_span(), 1e-12, "charge is wind-back as a fraction of the span")
	var travelled := absf(weapon.angle) - _rules.weapon.guard_angle
	assert_near(weapon.earned_windback, travelled, 1e-9, "every degree past the guard was credited")
	rig.release()
	var arc := rig.events_of(DuelEventTypes.ATTACK_RELEASED)[0].number(DuelEventKeys.ARC)
	assert_near(arc, _rules.weapon.min_arc + weapon.swing_charge * _rules.weapon.windback_span(), 1e-9, "arc is 90° plus the earned wind-back")


func test_charge_caps_at_full_and_spans_half_a_turn() -> void:
	var rig := _rig()
	rig.press()
	rig.hold(600)
	assert_true(rig.fighter.weapon.charge == 1.0, "charge stops at 100% once the blade runs out of travel")
	assert_near(rig.fighter.weapon.earned_windback, _rules.weapon.windback_span(), 1e-9, "and wind-back saturates with it")
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
	WeaponSystem.update_stable_side(rig.fighter.weapon, _rules.weapon)
	rig.press()
	rig.hold(_rules.weapon.tap_threshold_ticks)
	var ticks := 0
	while rig.fighter.weapon.angle > -_rules.weapon.guard_angle:
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
	WeaponSystem.update_stable_side(rig.fighter.weapon, _rules.weapon)
	rig.step(true, true)
	assert_eq(rig.fighter.weapon.swing_charge, 0.0, "releasing from inherited displacement is a 0% tap")
	var far := _rig()
	far.fighter.weapon.angle = deg_to_rad(135.0)
	WeaponSystem.update_stable_side(far.fighter.weapon, _rules.weapon)
	far.press()
	far.hold(300)
	assert_eq(far.fighter.weapon.charge, 0.0, "a blade already at the limit can hold forever and earn nothing")


## Charge-while-pinned. A bind is the one place a fighter is holding the
## button with a blade that physically cannot travel, so it is where a
## duration-based charge would be most obviously wrong: the player would walk
## out of the bind with a free full swing they never earned.
func test_a_press_while_the_blades_are_bound_cannot_charge() -> void:
	var rig := _rig()
	rig.fighter.weapon.set_phase(CombatPhase.Id.BIND)
	rig.press()
	## The press is not swallowed: it waits, like any press made while the
	## weapon is busy. It just never becomes a charge while the blade is held.
	assert_true(rig.fighter.buffered_press_tick >= 0, "the press is buffered rather than discarded")
	rig.hold(_rules.weapon.tap_threshold_ticks * 4)
	assert_eq(rig.fighter.weapon.phase, CombatPhase.Id.BIND, "precondition: still pinned")
	assert_eq(rig.fighter.weapon.charge, 0.0, "a pinned blade earns nothing however long it is held")
	assert_eq(rig.fighter.weapon.earned_windback, 0.0, "because it has not travelled")
	assert_eq(rig.events_of(DuelEventTypes.CHARGE_STARTED).size(), 0, "and it never entered a charge at all")
	## A bind outlasting the input buffer expires the press, so walking out of
	## a long bind does not fire a swing the player has mentally moved on from.
	assert_eq(rig.fighter.buffered_press_tick, -1, "and a bind longer than the buffer expires it")


func test_wind_back_is_credited_from_where_the_hold_began() -> void:
	## Beyond baseline the hold has to beat its own start, so the 100° blade
	## earns only what it adds — not the 55° it was handed.
	var rig := _rig()
	rig.fighter.weapon.angle = deg_to_rad(100.0)
	WeaponSystem.update_stable_side(rig.fighter.weapon, _rules.weapon)
	rig.press()
	rig.hold(_rules.weapon.tap_threshold_ticks + 400)
	var weapon := rig.fighter.weapon
	assert_near(rad_to_deg(weapon.angle), 135.0, 1e-9, "precondition: wound out to the limit")
	assert_near(rad_to_deg(weapon.earned_windback), 35.0, 1e-9, "only the 35° it travelled counts")
	assert_near(weapon.charge, 35.0 / 90.0, 1e-9, "so charge is 35 of the 90° span")


func test_earned_wind_back_is_not_refunded_by_drifting_back() -> void:
	var rig := _rig()
	rig.press()
	rig.hold(_rules.weapon.tap_threshold_ticks + 20)
	var earned := rig.fighter.weapon.earned_windback
	assert_true(earned > 0.0, "precondition: some wind-back earned")
	rig.fighter.weapon.angle = -_rules.weapon.guard_angle
	rig.hold(1)
	assert_eq(rig.fighter.weapon.earned_windback, earned, "being shoved back to baseline does not refund the hold")


func test_charge_cannot_outrun_the_motor() -> void:
	## One violent impulse must not convert itself into instant full charge.
	var rig := _rig()
	rig.press()
	rig.hold(_rules.weapon.tap_threshold_ticks + 4)
	var before := rig.fighter.weapon.earned_windback
	rig.fighter.weapon.angle = -_rules.weapon.guard_limit
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
	var one_tick := rad_to_deg(_rules.weapon.swing_speed_tap / float(SimulationTimebase.TICK_RATE))
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
		WeaponSystem.update_stable_side(rig.fighter.weapon, _rules.weapon)
		rig.step(true, true)
		assert_near(
			rad_to_deg(rig.fighter.weapon.swing_end),
			expected[i],
			1e-9,
			"a tap from %.0f° commands %.0f°" % [cases[i], expected[i]]
		)


func test_committed_side_ignores_the_centre_deadzone() -> void:
	var deadzone := _rules.weapon.side_deadzone
	var rig := _rig()
	assert_eq(rig.fighter.weapon.stable_side, -1.0, "precondition: blade committed to the right")
	rig.fighter.weapon.angle = deadzone * 0.5
	WeaponSystem.update_stable_side(rig.fighter.weapon, _rules.weapon)
	assert_eq(rig.fighter.weapon.stable_side, -1.0, "drifting a hair past centre does not re-commit the side")
	assert_eq(WeaponSystem.swing_direction(rig.fighter.weapon), 1.0, "so the valid attack direction is unchanged")
	rig.fighter.weapon.angle = deadzone * 2.0
	WeaponSystem.update_stable_side(rig.fighter.weapon, _rules.weapon)
	assert_eq(rig.fighter.weapon.stable_side, 1.0, "clearing the deadzone commits to the new side")
	assert_eq(WeaponSystem.swing_direction(rig.fighter.weapon), -1.0, "and reverses the valid attack direction")


func test_side_does_not_chatter_across_centre() -> void:
	var rig := _rig()
	var deadzone := _rules.weapon.side_deadzone
	var sides := PackedFloat64Array()
	for i in 12:
		## Noise straddling exact zero, the case the old `angle <= 0`
		## tie-break would have flipped on every sample.
		rig.fighter.weapon.angle = (deadzone * 0.4) * (1.0 if i % 2 == 0 else -1.0)
		WeaponSystem.update_stable_side(rig.fighter.weapon, _rules.weapon)
		sides.append(rig.fighter.weapon.stable_side)
	for side in sides:
		assert_eq(side, -1.0, "numerical noise at centre never re-commits the side")


func test_readiness_is_continuous_and_saturates_at_baseline() -> void:
	var weapon := _rules.weapon
	assert_eq(weapon.readiness(0.0), 0.0, "a blade at dead centre has no preparation")
	assert_near(weapon.readiness(deg_to_rad(22.5)), 0.5, 1e-12, "halfway to baseline is half readiness")
	assert_eq(weapon.readiness(weapon.guard_angle), 1.0, "the canonical guard is fully prepared")
	assert_eq(weapon.readiness(weapon.guard_limit), 1.0, "wound back past baseline stays fully prepared, not more")
	assert_eq(weapon.readiness(-weapon.guard_angle), 1.0, "readiness is side-agnostic")


func test_under_prepared_tap_reaches_a_lower_top_speed() -> void:
	var prepared := _rig()
	prepared.step(true, true)
	var under := _rig()
	under.fighter.weapon.angle = deg_to_rad(-10.0)
	WeaponSystem.update_stable_side(under.fighter.weapon, _rules.weapon)
	under.step(true, true)
	assert_near(prepared.fighter.weapon.launch_readiness, 1.0, 1e-12, "the canonical guard launches fully prepared")
	assert_near(under.fighter.weapon.launch_readiness, 10.0 / 45.0, 1e-12, "a 10° blade launches at 10/45 readiness")
	prepared.step_until_phase(CombatPhase.Id.OVERSWING)
	under.step_until_phase(CombatPhase.Id.OVERSWING)
	var prepared_peak := _peak_speed(prepared)
	var under_peak := _peak_speed(under)
	assert_true(under_peak < prepared_peak, "under-loaded cuts cannot reach the prepared top speed (%f vs %f)" % [under_peak, prepared_peak])
	assert_true(under_peak > 0.0, "but they still swing")


func test_launch_readiness_is_fixed_at_release() -> void:
	## Crossing centre mid-swing must not retroactively upgrade an
	## under-prepared cut into a prepared one.
	var rig := _rig()
	rig.fighter.weapon.angle = deg_to_rad(-10.0)
	WeaponSystem.update_stable_side(rig.fighter.weapon, _rules.weapon)
	rig.step(true, true)
	var at_launch := rig.fighter.weapon.launch_readiness
	rig.step_until_phase(CombatPhase.Id.OVERSWING)
	assert_true(absf(rig.fighter.weapon.angle) > _rules.weapon.guard_angle, "precondition: the blade swept well past baseline")
	assert_eq(rig.fighter.weapon.launch_readiness, at_launch, "readiness stays the value captured at release")


func test_guard_region_classifies_without_snapping() -> void:
	var guard := _rules.weapon.guard_angle
	assert_eq(GuardRegion.of(0.0, guard), GuardRegion.Id.UNDER_PREPARED, "centre is under-prepared")
	assert_eq(GuardRegion.of(guard, guard), GuardRegion.Id.BASELINE, "the canonical guard is baseline")
	assert_eq(GuardRegion.of(-guard, guard), GuardRegion.Id.BASELINE, "either canonical guard is baseline")
	assert_eq(GuardRegion.of(_rules.weapon.guard_limit, guard), GuardRegion.Id.OUTWARD, "the guard limit is outward")
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


func test_sword_persists_where_it_stopped() -> void:
	var rig := _rig()
	rig.attack(3)
	rig.settle()
	var rest := rig.fighter.weapon.angle
	assert_ne(rest, -_rules.weapon.guard_angle, "precondition: blade left the guard")
	rig.hold(120)
	assert_eq(rig.fighter.weapon.angle, rest, "no automatic return to an idle pose")


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
	assert_true(heavy.fighter.weapon.recovery_ticks > tap_recovery, "heavy recovery is longer")


func test_press_just_before_recovery_ends_is_buffered() -> void:
	var rig := _rig()
	rig.attack(3)
	assert_true(rig.step_until_phase(CombatPhase.Id.RECOVERY), "reached recovery")
	while rig.fighter.weapon.recovery_left > 2:
		rig.step()
	var pressed_at := rig.tick
	rig.press()
	assert_eq(rig.events_of(DuelEventTypes.ATTACK_STARTED).size(), 1, "press during recovery does not start yet")
	rig.hold(_rules.weapon.buffer_ticks)
	var starts := rig.events_of(DuelEventTypes.ATTACK_STARTED)
	assert_eq(starts.size(), 2, "buffered press started once control returned")
	assert_true(starts[1].tick - pressed_at <= _rules.weapon.buffer_ticks, "within the buffer window")


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
	assert_true(worst <= _rules.weapon.guard_limit + 1e-12, "blade stays inside the 270° coverage")
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
