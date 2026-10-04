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
	assert_true(rig.fighter.weapon.charge == 0.0, "charge starts at zero at the threshold")
	rig.hold(27)
	assert_near(rig.fighter.weapon.charge, 0.5, 1e-12, "27 of 54 charge ticks is half charge")
	rig.release()
	var released := rig.events_of(DuelEventTypes.ATTACK_RELEASED)
	assert_near(rad_to_deg(released[0].number(DuelEventKeys.ARC)), 135.0, 1e-9, "half charge arc 135°")


func test_charge_caps_at_full_and_spans_half_a_turn() -> void:
	var rig := _rig()
	rig.press()
	rig.hold(200)
	assert_true(rig.fighter.weapon.charge == 1.0, "charge stops at 100%")
	rig.release()
	assert_near(rad_to_deg(rig.events_of(DuelEventTypes.ATTACK_RELEASED)[0].number(DuelEventKeys.ARC)), 180.0, 1e-9, "full charge arc 180°")


func test_charging_retracts_the_blade_behind_the_guard() -> void:
	var rig := _rig()
	var guard := rig.fighter.weapon.angle
	assert_near(rad_to_deg(guard), -45.0, 1e-9, "precondition: right-side guard")
	rig.press()
	rig.hold(120)
	assert_near(rad_to_deg(rig.fighter.weapon.angle), -135.0, 0.5, "full charge winds back 90° to the guard limit")


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
	WeaponSystem.kill(rig.fighter)
	rig.step(true, true)
	assert_eq(rig.events.size(), 0, "no events from a dead fighter")
	assert_eq(rig.fighter.weapon.phase, CombatPhase.Id.DEAD, "stays dead")
