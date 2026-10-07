extends TestCase

## RULES: standard content is valid and expresses the specified geometry.
##
## See also: /docs/concepts/combat.md


func _init() -> void:
	suite_name = "RULES"


func test_standard_rules_are_valid() -> void:
	var rules := StandardDuelRules.create()
	assert_true(rules.is_valid(), "standard duel rules validate")
	assert_eq(rules.id, ContentIds.RULES_STANDARD_DUEL, "rules id")
	assert_eq(rules.weapon.id, ContentIds.WEAPON_BASTARD_SWORD, "weapon id")
	assert_eq(rules.fighter.id, ContentIds.FIGHTER_DUELIST, "fighter id")
	assert_eq(rules.rounds_to_win, 3, "best of five is first to three")


func test_bastard_sword_geometry_matches_spec() -> void:
	var weapon := WeaponCatalog.bastard_sword()
	assert_near(weapon.length(), 1.22, 1e-12, "1.22 m overall")
	assert_near(weapon.blade_length(), 0.97, 1e-9, "~0.97 m effective blade")
	assert_near(rad_to_deg(weapon.guard_limit) * 2.0, 270.0, 1e-9, "270° coverage")


func test_arc_grows_ninety_degrees_with_charge() -> void:
	var weapon := WeaponCatalog.bastard_sword()
	assert_near(rad_to_deg(weapon.arc(0.0)), 90.0, 1e-9, "tap arc 90°")
	assert_near(rad_to_deg(weapon.arc(0.5)), 135.0, 1e-9, "half charge 135°")
	assert_near(rad_to_deg(weapon.arc(1.0)), 180.0, 1e-9, "full charge 180°")
	assert_near(rad_to_deg(weapon.windback_span()), 90.0, 1e-9, "full charge is bought with 90° of wind-back")
	assert_eq(weapon.earned_charge(weapon.windback_span()), 1.0, "the whole span is full charge")
	assert_eq(weapon.earned_charge(0.0), 0.0, "no travel, no charge")
	assert_near(weapon.windback_baseline(deg_to_rad(20.0)), weapon.guard_angle, 1e-12, "an under-prepared hold must still reach the canonical guard")
	assert_near(weapon.windback_baseline(deg_to_rad(-100.0)), deg_to_rad(100.0), 1e-12, "an over-displaced hold must beat where it started")


func test_inertia_is_mass_times_length_squared() -> void:
	var weapon := WeaponCatalog.bastard_sword()
	var expected := weapon.inertia_coefficient * weapon.mass * weapon.length() * weapon.length()
	assert_near(weapon.moment_of_inertia(), expected, 1e-12, "inertia is k·m·L² about the pivot")
	assert_true(weapon.moment_of_inertia() > 0.0, "precondition: a real weapon resists being turned")
	## Sanity against the hand calculation for a rod pivoting about its end:
	## ⅓ × 1.6 × 1.22² ≈ 0.794 kg·m². This blade's mass starts at the hilt
	## rather than the pivot, so it sits a little above that — but not
	## anywhere near a different order of magnitude.
	var rod_about_end := PhysicalBaseline.SWORD_MASS_KG * PhysicalBaseline.SWORD_LENGTH_M * PhysicalBaseline.SWORD_LENGTH_M / 3.0
	assert_near(rod_about_end, 0.794, 1e-3, "precondition: the baseline hand calculation is ~0.794 kg·m²")
	assert_between(weapon.moment_of_inertia(), rod_about_end, rod_about_end * 1.5, "the shipped blade is in that neighbourhood")


func test_mass_distribution_is_authored_not_assumed() -> void:
	## The uniform rod must be one authorable case, not a hard-wired law: a
	## tip-heavy weapon of identical length and mass is harder to turn.
	var rod := WeaponCatalog.bastard_sword()
	var tip_heavy := WeaponCatalog.bastard_sword()
	tip_heavy.inertia_coefficient = rod.inertia_coefficient * 1.5
	assert_true(tip_heavy.moment_of_inertia() > rod.moment_of_inertia(), "a tip-heavy blade has more inertia")
	assert_true(tip_heavy.swing_accel(1.0, 1.0) < rod.swing_accel(1.0, 1.0), "so the same torque accelerates it less")
	assert_true(tip_heavy.brake_accel(1.0, 1.0) < rod.brake_accel(1.0, 1.0), "and arrests it less")


func test_motor_accelerations_derive_from_torque_over_inertia() -> void:
	var weapon := WeaponCatalog.bastard_sword()
	var inertia := weapon.moment_of_inertia()
	assert_near(weapon.swing_accel(0.0, 1.0), weapon.swing_torque_tap / inertia, 1e-12, "tap swing is τ/I")
	assert_near(weapon.swing_accel(1.0, 1.0), weapon.swing_torque_full / inertia, 1e-12, "full swing is τ/I")
	assert_near(weapon.brake_accel(0.0, 1.0), weapon.brake_torque_tap / inertia, 1e-12, "tap brake is τ/I")
	assert_near(weapon.windup_accel(1.0), weapon.windup_torque / inertia, 1e-12, "wind-back is τ/I")
	assert_near(weapon.hold_accel(1.0), weapon.hold_torque / inertia, 1e-12, "settling is τ/I")
	assert_true(weapon.brake_accel(0.0, 1.0) > weapon.brake_accel(1.0, 1.0), "a full swing is far more reluctant to be arrested than a tap")


func test_tap_threshold_is_in_the_specified_window() -> void:
	var ms := float(WeaponCatalog.bastard_sword().tap_threshold_ticks) * 1000.0 / float(SimulationTimebase.TICK_RATE)
	assert_between(ms, 100.0, 130.0, "tap threshold 100–130 ms")


func test_sweet_spot_is_outer_middle() -> void:
	var weapon := WeaponCatalog.bastard_sword()
	assert_true(weapon.efficiency(0.7) > weapon.efficiency(1.0), "outer-middle beats the tip")
	assert_true(weapon.efficiency(0.7) > weapon.efficiency(0.2), "outer-middle beats near the hilt")


func test_broken_rules_fail_validation() -> void:
	var rules := StandardDuelRules.create()
	rules.weapon.tip_radius = rules.weapon.hilt_radius
	assert_false(rules.is_valid(), "zero-length blade is invalid")
	var empty := DuelRules.new()
	assert_false(empty.is_valid(), "neutral defaults are invalid until content fills them")


func test_damage_curve_is_monotonic_and_nonlinear() -> void:
	var combat := StandardDuelRules.combat_tuning()
	var previous := -1.0
	var first_drop := -1
	for i in range(0, 121):
		var damage := combat.damage_for(float(i) / 100.0)
		if damage < previous and first_drop < 0:
			first_drop = i
		previous = damage
	assert_eq(first_drop, -1, "damage never decreases as quality rises")
	assert_true(combat.damage_for(0.9) - combat.damage_for(0.7) > combat.damage_for(0.3) - combat.damage_for(0.1), "top of curve is steeper")


func test_fighter_has_base_stamina() -> void:
	var fighter := FighterCatalog.duelist()
	assert_true(fighter.base_stamina > 0.0, "the duelist has a positive stamina pool")
	assert_true(fighter.is_valid(), "the duelist with base_stamina passes validation")


func test_base_stamina_required_for_validation() -> void:
	var rules := StandardDuelRules.create()
	rules.fighter.base_stamina = 0.0
	assert_false(rules.is_valid(), "a fighter with zero base_stamina is invalid")
	rules.fighter.base_stamina = -10.0
	assert_false(rules.is_valid(), "a fighter with negative base_stamina is invalid")


func test_stamina_initialized_at_round_start() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	for slot in 2:
		assert_eq(state.fighter(slot).stamina, rules.fighter.base_stamina, "slot %d starts with full stamina" % slot)


func test_stamina_enters_the_state_hash() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var baseline := StateHasher.hash_state(state)
	state.fighter(0).stamina -= 1.0
	var changed := StateHasher.hash_state(state)
	assert_ne(baseline, changed, "a stamina change is reflected in the state hash")


func test_current_rules_version() -> void:
	var rules := StandardDuelRules.create()
	assert_eq(rules.version, 18, "rules version tracks gameplay-affecting changes")
